# erc4626-bench

**Per-transaction gas benchmarks for ERC4626 vaults, on the EVM and on EraVM, same calls, same script.**

The benchmark repos people cite compare three libraries and have not moved since 2024. This one measures every call the way a user pays for it, from an isolated transaction, and keeps the baselines in the tree so anyone can add a vault and get a row.

![License: MIT](https://img.shields.io/badge/license-MIT-blue)
![Status](https://img.shields.io/badge/status-alpha-orange)

---

## Why per transaction

`forge test --gas-report` aggregates calls from different tests into one row, so a cold first deposit and a warm tenth deposit end up as "min" and "max" of the same function, and the labels get swapped. `script/bench-evm.py` runs each benchmark on its own under `forge test --isolate`, so every call starts cold like a real transaction, and reads the gas of that one call from its trace. The number excludes the 21,000 intrinsic cost, which is the same for every vault.

On zkSync Era, forge's gas report is dominated by a fixed bootloader cost and `gasleft()` inside the emulator does not measure EraVM execution. `script/bench-eravm.sh` deploys every vault to a local `anvil-zksync` node, sends the same transaction sequence to each, and reads `gasUsed` from the receipts.

## Baselines

| Vault | What it is |
|---|---|
| `SoladyVault` | Solady's `ERC4626`, the accepted cheapest general-purpose implementation |
| `YulSafeERC20` | [YulSafe](https://github.com/yodablocks/yulsafe): packed totals, inline assembly on the hot path, first-deposit burn |
| `PlainPackedVault` | YulSafe rewritten in plain Solidity with the same layout and zero assembly |
| `LeanVault` | Packed totals and pause flag, transient reentrancy guard, single supply counter, first-deposit burn |
| `LeanVault2` | LeanVault with a virtual-share offset instead of the burn and a one-slot owner |

All five pass a16z's 26 ERC4626 properties in the YulSafe repo. Only the benchmark itself lives here.

## Results

Per transaction, solc 0.8.37, cancun, optimizer at 10,000,000 runs, 2026-09-26:

| Call | YulSafe | Plain | Lean | Lean2 | Solady |
|---|---|---|---|---|---|
| `deposit()` first, cold vault | 175,513 | 173,805 | 129,500 | 106,096 | 106,009 |
| `deposit()` subsequent | 63,028 | 61,551 | 54,469 | 54,796 | 54,709 |
| `mint()` | 63,078 | 61,740 | 54,636 | 54,843 | 54,735 |
| `withdraw()` | 61,279 | 59,938 | 52,986 | 53,264 | 54,576 |
| `redeem()` | 61,303 | 59,818 | 52,866 | 53,126 | 53,284 |
| `totalAssets()` | 2,321 | 2,321 | 2,321 | 2,321 | 5,621 |
| `convertToShares()` | 2,674 | 2,679 | 2,656 | 3,002 | 8,072 |
| `convertToAssets()` | 2,675 | 2,680 | 2,680 | 3,004 | 8,108 |
| Deployment gas | 1,712,163 | 2,154,694 | 1,983,630 | 1,764,437 | 1,185,598 |

EraVM, from receipts on `anvil-zksync` 0.6.11 with zksolc 1.5.15 and the patched solc 0.8.30:

| Call | YulSafe | Plain | Lean | Lean2 | Solady |
|---|---|---|---|---|---|
| `deposit()` first | 201,031 | 198,979 | 179,832 | 170,532 | 173,466 |
| `deposit()` subsequent | 178,774 | 176,740 | 163,369 | 163,172 | 166,106 |
| `mint()` | 178,768 | 176,734 | 163,236 | 162,932 | 166,148 |
| `withdraw()` | 176,294 | 174,272 | 160,806 | 160,502 | 167,356 |
| `redeem()` | 176,288 | 174,266 | 160,800 | 160,484 | 164,200 |

## Run it

```sh
git clone https://github.com/yodablocks/erc4626-bench && cd erc4626-bench
forge test                                 # the benchmark tests, all vaults
script/bench-evm.py                        # per-transaction table, default profile
FOUNDRY_PROFILE=viair script/bench-evm.py  # same, via-IR at 200 runs

anvil-zksync --port 8011 &                 # needs foundry-zksync
script/bench-eravm.sh
```

## Add a vault

1. Put the contract under `src/vaults/` with a constructor `(address asset, string name, string symbol)`.
2. Add it to `test/GasBenchmark.t.sol` by copying one vault's eight `test_gas_*` functions.
3. Add its name to `gas_reports` in `foundry.toml`, to the `vaults` list in `script/bench-evm.py`, and as a column in `script/bench-eravm.sh`.

## License

[MIT](LICENSE). Solady and forge-std are vendored under their own licenses in `lib/`.
