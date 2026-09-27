#!/usr/bin/env zsh
# Measures every benchmarked vault on EraVM using real transaction
# receipts, because forge's gas report cannot attribute gas per call on zkSync.
#
# Requires foundry-zksync (forge, cast, anvil-zksync on PATH).
#
#   anvil-zksync --port 8011 &
#   script/bench-eravm.sh
#
# Optional: RPC and PK environment variables override the local node and the
# first anvil-zksync rich account; PK3 overrides the second.
#
# EraVM charges pubdata by how well each written value compresses, so a call's
# gas depends on the balances and nonces written before it. The first five
# vaults share one account in a fixed order. LeanVault3 was added later and runs
# every transaction, deploy included, from its own account, so adding it left
# the other five columns unchanged to the gas.
set -e
cd "$(dirname "$0")/.."
RPC=${RPC:-http://127.0.0.1:8011}
PK=${PK:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}
PK3=${PK3:-0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d}
export FOUNDRY_PROFILE=zksync
ME=$(cast wallet address --private-key $PK)
ME3=$(cast wallet address --private-key $PK3)

deploy() { forge create --zksync --rpc-url $RPC --private-key ${KEY:-$PK} --broadcast "$@" 2>&1 | grep "Deployed to" | awk '{print $NF}'; }
gas_used() { cast send --rpc-url $RPC --private-key ${KEY:-$PK} --json "$@" 2>/dev/null | python3 -c 'import sys,json; print(int(json.load(sys.stdin)["gasUsed"],16))'; }
estimate() { cast estimate --rpc-url $RPC --from ${FROM:-$ME} "$@" 2>/dev/null; }
# LeanVault3 counterparts: same calls, second account.
deploy3() { KEY=$PK3 deploy "$@"; }
gas_used3() { KEY=$PK3 gas_used "$@"; }
estimate3() { FROM=$ME3 estimate "$@"; }
row() { printf "%-20s %10s %10s %10s %10s %10s %10s\n" "$1" "$2" "$3" "$4" "$5" "$6" "$7"; }

ASSET=$(deploy src/mocks/MockERC20.sol:MockERC20 --constructor-args "Test Token" "TEST" 18)
YS=$(deploy src/vaults/YulSafeERC20.sol:YulSafeERC20 --constructor-args $ASSET "YulSafe Vault" "ysVAULT")
SO=$(deploy src/vaults/SoladyVault.sol:SoladyVault --constructor-args $ASSET "Solady Vault" "sVAULT")
PL=$(deploy src/vaults/PlainPackedVault.sol:PlainPackedVault --constructor-args $ASSET "Plain Vault" "pVAULT")
LN=$(deploy src/vaults/LeanVault.sol:LeanVault --constructor-args $ASSET "Lean Vault" "lVAULT")
L2=$(deploy src/vaults/LeanVault2.sol:LeanVault2 --constructor-args $ASSET "Lean Vault 2" "lVAULT2")
L3=$(deploy3 src/vaults/LeanVault3.sol:LeanVault3 --constructor-args $ASSET "Lean Vault 3" "lVAULT3")
MAX=0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff
gas_used $ASSET "mint(address,uint256)" $ME 1000000000000000000000000 >/dev/null
gas_used $ASSET "approve(address,uint256)" $YS $MAX >/dev/null
gas_used $ASSET "approve(address,uint256)" $SO $MAX >/dev/null
gas_used $ASSET "approve(address,uint256)" $PL $MAX >/dev/null
gas_used $ASSET "approve(address,uint256)" $LN $MAX >/dev/null
gas_used $ASSET "approve(address,uint256)" $L2 $MAX >/dev/null
gas_used3 $ASSET "mint(address,uint256)" $ME3 1000000000000000000000000 >/dev/null
gas_used3 $ASSET "approve(address,uint256)" $L3 $MAX >/dev/null

D1=10000000000000000000000   # 10,000 tokens
D2=1000000000000000000000    #  1,000 tokens
row "function" "YulSafe" "Solady" "Plain" "Lean" "Lean2" "Lean3"
row "first_deposit"      "$(gas_used $YS 'deposit(uint256,address)' $D1 $ME)" "$(gas_used $SO 'deposit(uint256,address)' $D1 $ME)" "$(gas_used $PL 'deposit(uint256,address)' $D1 $ME)" "$(gas_used $LN 'deposit(uint256,address)' $D1 $ME)" "$(gas_used $L2 'deposit(uint256,address)' $D1 $ME)" "$(gas_used3 $L3 'deposit(uint256,address)' $D1 $ME3)"
gas_used $YS 'deposit(uint256,address)' $D2 $ME >/dev/null; gas_used $SO 'deposit(uint256,address)' $D2 $ME >/dev/null; gas_used $PL 'deposit(uint256,address)' $D2 $ME >/dev/null; gas_used $LN 'deposit(uint256,address)' $D2 $ME >/dev/null; gas_used $L2 'deposit(uint256,address)' $D2 $ME >/dev/null; gas_used3 $L3 'deposit(uint256,address)' $D2 $ME3 >/dev/null
row "subsequent_deposit" "$(gas_used $YS 'deposit(uint256,address)' $D2 $ME)" "$(gas_used $SO 'deposit(uint256,address)' $D2 $ME)" "$(gas_used $PL 'deposit(uint256,address)' $D2 $ME)" "$(gas_used $LN 'deposit(uint256,address)' $D2 $ME)" "$(gas_used $L2 'deposit(uint256,address)' $D2 $ME)" "$(gas_used3 $L3 'deposit(uint256,address)' $D2 $ME3)"
row "mint"               "$(gas_used $YS 'mint(uint256,address)' $D2 $ME)" "$(gas_used $SO 'mint(uint256,address)' $D2 $ME)" "$(gas_used $PL 'mint(uint256,address)' $D2 $ME)" "$(gas_used $LN 'mint(uint256,address)' $D2 $ME)" "$(gas_used $L2 'mint(uint256,address)' $D2 $ME)" "$(gas_used3 $L3 'mint(uint256,address)' $D2 $ME3)"
row "withdraw"           "$(gas_used $YS 'withdraw(uint256,address,address)' $D2 $ME $ME)" "$(gas_used $SO 'withdraw(uint256,address,address)' $D2 $ME $ME)" "$(gas_used $PL 'withdraw(uint256,address,address)' $D2 $ME $ME)" "$(gas_used $LN 'withdraw(uint256,address,address)' $D2 $ME $ME)" "$(gas_used $L2 'withdraw(uint256,address,address)' $D2 $ME $ME)" "$(gas_used3 $L3 'withdraw(uint256,address,address)' $D2 $ME3 $ME3)"
row "redeem"             "$(gas_used $YS 'redeem(uint256,address,address)' $D2 $ME $ME)" "$(gas_used $SO 'redeem(uint256,address,address)' $D2 $ME $ME)" "$(gas_used $PL 'redeem(uint256,address,address)' $D2 $ME $ME)" "$(gas_used $LN 'redeem(uint256,address,address)' $D2 $ME $ME)" "$(gas_used $L2 'redeem(uint256,address,address)' $D2 $ME $ME)" "$(gas_used3 $L3 'redeem(uint256,address,address)' $D2 $ME3 $ME3)"
echo "eth_estimateGas for views (includes zkSync's fixed per-transaction overhead):"
row "totalAssets"        "$(estimate $YS 'totalAssets()')" "$(estimate $SO 'totalAssets()')" "$(estimate $PL 'totalAssets()')" "$(estimate $LN 'totalAssets()')" "$(estimate $L2 'totalAssets()')" "$(estimate3 $L3 'totalAssets()')"
row "convertToShares"    "$(estimate $YS 'convertToShares(uint256)' $D2)" "$(estimate $SO 'convertToShares(uint256)' $D2)" "$(estimate $PL 'convertToShares(uint256)' $D2)" "$(estimate $LN 'convertToShares(uint256)' $D2)" "$(estimate $L2 'convertToShares(uint256)' $D2)" "$(estimate3 $L3 'convertToShares(uint256)' $D2)"
row "convertToAssets"    "$(estimate $YS 'convertToAssets(uint256)' $D2)" "$(estimate $SO 'convertToAssets(uint256)' $D2)" "$(estimate $PL 'convertToAssets(uint256)' $D2)" "$(estimate $LN 'convertToAssets(uint256)' $D2)" "$(estimate $L2 'convertToAssets(uint256)' $D2)" "$(estimate3 $L3 'convertToAssets(uint256)' $D2)"
