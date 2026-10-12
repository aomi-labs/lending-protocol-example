// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Wrapped Gold (WGLD), the lending market's collateral asset.
/// @notice A protocol-native ERC-20: the lending pool may pull tokens a
/// holder deposits without a separate approval.
contract CollateralToken {
    string public constant name = "Wrapped Gold";
    string public constant symbol = "WGLD";
    uint8 public constant decimals = 18;

    address public immutable minter;
    address public pool;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor() {
        minter = msg.sender;
    }

    /// @notice One-time wiring of the lending pool, done at deployment.
    function setPool(address lendingPool) external {
        require(msg.sender == minter && pool == address(0), "pool already set");
        pool = lendingPool;
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == minter, "only minter");
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _move(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        if (msg.sender != pool) {
            uint256 allowed = allowance[from][msg.sender];
            require(allowed >= amount, "allowance");
            if (allowed != type(uint256).max) allowance[from][msg.sender] = allowed - amount;
        }
        _move(from, to, amount);
        return true;
    }

    function _move(address from, address to, uint256 amount) private {
        require(balanceOf[from] >= amount, "balance");
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
    }
}
