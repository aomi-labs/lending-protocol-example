// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CollateralToken} from "./CollateralToken.sol";
import {PriceOracle} from "./PriceOracle.sol";

/// @title Over-collateralized native-USDC lending against WGLD.
/// @notice Lenders supply native USDC for shares. Borrowers post WGLD and
/// borrow native USDC up to the collateral factor of its oracle value.
/// Unhealthy positions can be liquidated at a bonus.
contract LendingPool {
    uint256 public constant BPS = 10_000;

    CollateralToken public immutable collateral;
    PriceOracle public oracle;
    address public owner;
    uint256 public collateralFactorBps = 5_000;
    uint256 public liquidationBonusBps = 1_000;

    uint256 public totalShares;
    uint256 public totalBorrows;
    mapping(address => uint256) public shares;
    mapping(address => uint256) public collateralOf;
    mapping(address => uint256) public debtOf;

    event Supplied(address indexed lender, uint256 amount, uint256 shares);
    event Withdrawn(address indexed lender, uint256 amount, uint256 shares);
    event Borrowed(address indexed borrower, uint256 amount);
    event Repaid(address indexed borrower, uint256 amount);
    event Liquidated(address indexed borrower, address indexed liquidator, uint256 repaid, uint256 seized);

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner");
        _;
    }

    constructor(CollateralToken token, PriceOracle feed) {
        collateral = token;
        oracle = feed;
        owner = msg.sender;
    }

    function setCollateralFactor(uint256 bps) external onlyOwner {
        require(bps <= 8_000, "factor too high");
        collateralFactorBps = bps;
    }

    function setOracle(PriceOracle feed) external onlyOwner {
        oracle = feed;
    }

    /// @notice Native USDC held plus outstanding borrows.
    function totalAssets() public view returns (uint256) {
        return address(this).balance + totalBorrows;
    }

    function supply() external payable {
        require(msg.value > 0, "zero");
        uint256 assetsBefore = totalAssets() - msg.value;
        uint256 minted = totalShares == 0 ? msg.value : (msg.value * totalShares) / assetsBefore;
        shares[msg.sender] += minted;
        totalShares += minted;
        emit Supplied(msg.sender, msg.value, minted);
    }

    function withdraw(uint256 shareAmount) external {
        require(shareAmount > 0 && shares[msg.sender] >= shareAmount, "shares");
        uint256 amount = (shareAmount * totalAssets()) / totalShares;
        require(amount <= address(this).balance, "liquidity");
        shares[msg.sender] -= shareAmount;
        totalShares -= shareAmount;
        _send(msg.sender, amount);
        emit Withdrawn(msg.sender, amount, shareAmount);
    }

    function depositCollateral(uint256 amount) external {
        require(collateral.transferFrom(msg.sender, address(this), amount), "transfer");
        collateralOf[msg.sender] += amount;
    }

    function withdrawCollateral(uint256 amount) external {
        require(collateralOf[msg.sender] >= amount, "collateral");
        collateralOf[msg.sender] -= amount;
        require(healthy(msg.sender), "unhealthy");
        require(collateral.transfer(msg.sender, amount), "transfer");
    }

    function borrow(uint256 amount) external {
        debtOf[msg.sender] += amount;
        totalBorrows += amount;
        require(healthy(msg.sender), "unhealthy");
        _send(msg.sender, amount);
        emit Borrowed(msg.sender, amount);
    }

    function repay() external payable {
        uint256 amount = msg.value < debtOf[msg.sender] ? msg.value : debtOf[msg.sender];
        debtOf[msg.sender] -= amount;
        totalBorrows -= amount;
        if (msg.value > amount) _send(msg.sender, msg.value - amount);
        emit Repaid(msg.sender, amount);
    }

    function liquidate(address borrower) external payable {
        require(!healthy(borrower), "healthy");
        uint256 repaid = msg.value < debtOf[borrower] ? msg.value : debtOf[borrower];
        uint256 seized = (repaid * (BPS + liquidationBonusBps) * 1e18) / (BPS * oracle.price());
        if (seized > collateralOf[borrower]) seized = collateralOf[borrower];
        debtOf[borrower] -= repaid;
        totalBorrows -= repaid;
        collateralOf[borrower] -= seized;
        require(collateral.transfer(msg.sender, seized), "transfer");
        if (msg.value > repaid) _send(msg.sender, msg.value - repaid);
        emit Liquidated(borrower, msg.sender, repaid, seized);
    }

    /// @notice Native USDC the borrower may owe at most.
    function borrowLimit(address borrower) public view returns (uint256) {
        return (collateralOf[borrower] * oracle.price() / 1e18) * collateralFactorBps / BPS;
    }

    function healthy(address borrower) public view returns (bool) {
        return debtOf[borrower] <= borrowLimit(borrower);
    }

    function _send(address to, uint256 amount) private {
        (bool ok,) = to.call{value: amount}("");
        require(ok, "native transfer");
    }
}
