// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CollateralToken} from "../src/CollateralToken.sol";
import {LendingPool} from "../src/LendingPool.sol";
import {PriceOracle} from "../src/PriceOracle.sol";
import {SimpleAMM} from "../src/SimpleAMM.sol";

/// @dev The Foundry cheatcode surface this script needs, so the example has no
/// library dependency (no forge-std checkout required to deploy it).
interface Vm {
    function startBroadcast() external;
    function stopBroadcast() external;
    function envOr(string calldata name, uint256 defaultValue) external view returns (uint256);
}

/// @title Deploy and seed the lending protocol in one broadcast.
/// @notice Deploys the four contracts, wires them, and seeds liquidity so the
/// protocol is usable as soon as the broadcast lands: the AMM holds a WGLD /
/// native-USDC pool (which the oracle reads), and the lending pool holds
/// native USDC for borrowers. The deployer is the collateral token's minter
/// and the pool's owner.
///
/// Amounts come from the environment so a testnet faucet balance is enough.
/// All are in wei of native USDC / WGLD (18 decimals):
///   SEED_MINT_WGLD  WGLD minted to the deployer            (default 10,000)
///   SEED_AMM_WGLD   WGLD side of the AMM pool              (default 20)
///   SEED_AMM_USDC   native USDC side of the AMM pool       (default 20)
///   SEED_POOL_USDC  native USDC supplied to the lending pool (default 50)
/// The deployer must hold SEED_AMM_USDC + SEED_POOL_USDC native USDC plus gas.
///
///   forge script script/Deploy.s.sol --rpc-url $ARC_TESTNET_RPC \
///     --private-key $DEPLOYER_KEY --broadcast
contract Deploy {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function run() external returns (CollateralToken token, SimpleAMM amm, PriceOracle oracle, LendingPool pool) {
        uint256 mintWgld = vm.envOr("SEED_MINT_WGLD", 10_000 ether);
        uint256 ammWgld = vm.envOr("SEED_AMM_WGLD", 20 ether);
        uint256 ammUsdc = vm.envOr("SEED_AMM_USDC", 20 ether);
        uint256 poolUsdc = vm.envOr("SEED_POOL_USDC", 50 ether);

        vm.startBroadcast();
        token = new CollateralToken(msg.sender);
        amm = new SimpleAMM(token);
        oracle = new PriceOracle(amm);
        pool = new LendingPool(token, oracle);

        // One-time wiring: the pool may pull collateral without an allowance.
        token.setPool(address(pool));
        token.mint(msg.sender, mintWgld);

        // AMM liquidity sets the spot price the oracle reports: ammUsdc / ammWgld.
        token.approve(address(amm), ammWgld);
        amm.seed{value: ammUsdc}(ammWgld);

        // Lenders' liquidity that borrowers draw on.
        pool.supply{value: poolUsdc}();
        vm.stopBroadcast();
    }
}
