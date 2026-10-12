# Lending protocol example

A small over-collateralized lending protocol in four contracts, used to exercise
the Aomi security agent on a bug that only shows up **across** contracts.

| Contract | Role |
|---|---|
| `LendingPool` | Lenders supply native USDC for shares. Borrowers post WGLD collateral and borrow native USDC up to the collateral factor of its oracle value. Unhealthy positions can be liquidated at a bonus. |
| `CollateralToken` | WGLD, a protocol-native ERC-20. The pool may pull it without an allowance. |
| `SimpleAMM` | A constant-product WGLD / native-USDC pool. |
| `PriceOracle` | Reports WGLD's price to the pool — by reading the AMM's **spot** price. |

## The planted vulnerability

`PriceOracle.price()` returns `SimpleAMM.spotPrice()` with no time-weighting. A
single large `buy` on the AMM pumps the spot price inside one transaction, so
collateral deposited right after is valued at the pumped price and the pool
lends against it:

1. `SimpleAMM.buy` with a large amount of native USDC — the spot price jumps.
2. `LendingPool.depositCollateral` with the WGLD just bought.
3. `LendingPool.borrow` near the inflated limit. The position reads as healthy.

The borrower walks away with more native USDC than the collateral is worth at
the real price. No single contract is wrong in isolation; the bug is the
composition.

## Deploy and seed

`script/Deploy.s.sol` deploys the four contracts, wires them, and seeds
liquidity in one broadcast, so the protocol is live as soon as it lands. It has
no library dependency. Amounts are read from the environment (wei, 18
decimals) with faucet-sized defaults; the deployer needs
`SEED_AMM_USDC + SEED_POOL_USDC` native USDC plus gas.

```bash
forge script script/Deploy.s.sol --rpc-url $ARC_TESTNET_RPC --private-key $DEPLOYER_KEY --broadcast
```

| Variable | Default | Meaning |
|---|---|---|
| `SEED_MINT_WGLD` | 10,000 | WGLD minted to the deployer |
| `SEED_AMM_WGLD` | 20 | WGLD side of the AMM pool |
| `SEED_AMM_USDC` | 20 | native USDC side of the AMM pool (sets the spot price) |
| `SEED_POOL_USDC` | 50 | native USDC supplied to the lending pool |

For a local run without a chain, `scripts/seed-protocol.mjs` at the repo root
deploys the same protocol on a throwaway anvil and dumps it as a seed for
Aomi's simulation world.
