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
| `LeanVault3` | [leanvault](https://github.com/yodablocks/leanvault)'s idle vault as shipped, copied from its source: LeanVault2's accounting behind three virtual hooks, plus EIP-2612 `permit` |

The first five pass a16z's 26 ERC4626 properties in the YulSafe repo, `LeanVault3` passes them and its permit tests in leanvault. Only the benchmark itself lives here. Solady and `LeanVault3` are the two with `permit`.

## Results

Per transaction, solc 0.8.37, cancun, optimizer at 10,000,000 runs, 2026-09-26; Lean3 added 2026-09-27 on the same toolchain, with the other columns reproduced unchanged:

| Call | YulSafe | Plain | Lean | Lean2 | Lean3 | Solady |
|---|---|---|---|---|---|---|
| `deposit()` first, cold vault | 175,513 | 173,805 | 129,500 | 106,096 | 106,096 | 106,009 |
| `deposit()` subsequent | 63,028 | 61,551 | 54,469 | 54,796 | 54,796 | 54,709 |
| `mint()` | 63,078 | 61,740 | 54,636 | 54,843 | 54,877 | 54,735 |
| `withdraw()` | 61,279 | 59,938 | 52,986 | 53,264 | 53,303 | 54,576 |
| `redeem()` | 61,303 | 59,818 | 52,866 | 53,126 | 53,160 | 53,284 |
| `totalAssets()` | 2,321 | 2,321 | 2,321 | 2,321 | 2,321 | 5,621 |
| `convertToShares()` | 2,674 | 2,679 | 2,656 | 3,002 | 3,002 | 8,072 |
| `convertToAssets()` | 2,675 | 2,680 | 2,680 | 3,004 | 3,104 | 8,108 |
| `permit()` | | | | | 73,903 | 76,296 |
| Deployment gas | 1,712,163 | 2,154,694 | 1,983,630 | 1,764,437 | 2,028,691 | 1,185,598 |

Lean3 is Lean2 with hooks and `permit`. Together they add 34 to 100 gas on four calls and 264,266 to deployment; a signed `permit` runs 2,393 cheaper than Solady's. Deployment gas depends on the source path through the metadata hash: Lean and Lean2 were measured from YulSafe's copies under `test/mocks/` and deploy 12 gas cheaper from this repo, Lean3 is measured here.

EraVM, from receipts on `anvil-zksync` 0.6.11 with zksolc 1.5.15 and the patched solc 0.8.30:

| Call | YulSafe | Plain | Lean | Lean2 | Lean3 | Solady |
|---|---|---|---|---|---|---|
| `deposit()` first | 201,031 | 198,979 | 179,832 | 170,532 | 171,152 | 173,466 |
| `deposit()` subsequent | 178,774 | 176,740 | 163,369 | 163,172 | 163,792 | 166,106 |
| `mint()` | 178,768 | 176,734 | 163,236 | 162,932 | 163,552 | 166,148 |
| `withdraw()` | 176,294 | 174,272 | 160,806 | 160,502 | 161,122 | 167,356 |
| `redeem()` | 176,288 | 174,266 | 160,800 | 160,484 | 161,104 | 164,200 |

On EraVM, Lean3 pays a flat 620 gas per call over Lean2 and still beats Solady on every row; Lean beats it on everything but the first deposit. EraVM charges pubdata by how well each written value compresses, so a call's gas depends on the balances and nonces written before it. Lean3 runs from its own account for that reason: sharing the first account moved Lean's subsequent deposit by 119 gas. `permit` is not measured on EraVM.

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
3. Add its name to `gas_reports` in `foundry.toml`, to the `vaults` list in `script/bench-evm.py`, and as a column in `script/bench-eravm.sh`, sending its transactions from an account of its own the way `LeanVault3` does, so the existing columns do not move.

## License

[MIT](LICENSE). Solady and forge-std are vendored under their own licenses in `lib/`.
