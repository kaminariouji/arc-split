# ArcSplit

USDC revenue splits on Arc mainnet. One deposit, many payees, each payee withdraws on their own.

The contract never loops over transfers. `claim` moves funds to the caller only, so a payee that reverts cannot block the others and the creator's deposit is never stuck behind one bad address. Rounding dust is returned to the creator instead of being stranded in the contract.

## Live on Arc mainnet (chain id 5042)

| | |
|---|---|
| Contract | `0x4743aC7b133F98eD6fdfC897eb456bD12D8dB6b3` |
| Deploy tx | `0x87d149925b6b0c886cde8cb12b3e2cfd7584b3c5e3fddf8abc8cf3f64e00b1c7` |
| App | https://arc-split-eue.pages.dev |
| Arc Studio project | https://studio.arc.io/app/4a4be369-2b4a-43f1-804f-c43c670dccb1 |

One real split executed end to end, 0.10 USDC:

| Step | Transaction |
|---|---|
| approve | `0x36801fe12a6da2805b1c44140b4d417c0db44ad6fdd65e8cada9c8f99e6bb9b3` |
| createSplit (0.10 USDC, 60/40) | `0x903d3e2900e61f9c37a61c6e6f9273447582d2b10f309eae01b5f1d641c647c7` |
| claim (0.06 USDC out) | `0xdd7517a4f5c68e447bf9120ba9b7b150aa7dfdcbf78280e56cd72ffe6c157b83` |

Split id: `0x39c0e2b4b146fd26d39e6f57782860e61787f738d42cb71c958b5a19f86fa857` (keccak256 of `arc-split-demo-2026-10-28`).

## Verify without a block explorer

Arc's explorer requires a login, so the receipts are stored here as well. `media/receipts.json` was read from the public RPC, and the same check is one command:

```bash
curl -s https://rpc.mainnet.arc.io \
  -H 'content-type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"eth_getTransactionReceipt","params":["0xdd7517a4f5c68e447bf9120ba9b7b150aa7dfdcbf78280e56cd72ffe6c157b83"]}'
```

Look for `"status":"0x1"` and `"to":"0x4743ac7b133f98ed6fdfc897eb456bd12d8db6b3"`.

## What the contract does

1. `createSplit(id, payees[], sharesBps[], amount)` pulls USDC from the creator, checks that the shares sum to exactly 10000 bps, and stores one slice per payee.
2. `claim(id)` pays the caller their slice and zeroes it. A second claim reverts with `NothingToClaim`.
3. `sweepDust(id)` returns the rounding remainder to the creator. Unclaimed payee balances stay claimable.
4. `splitOf(id)` and `claimable(id, payee)` are the read side the app uses.

Splits are keyed by a caller-chosen `bytes32`, so an invoice id or a payroll run id can be the key, and an id can never be reused.

## Tests

```bash
forge test
```

10 tests, 10 passing: share math, claim, double claim, non-payee claim, bad share sum, duplicate payee, rounding dust, creator-only sweep, id reuse, and unclaimed balances surviving a sweep.

The same files were sent into the Arc Studio workspace for this project (the project URL above) and the suite was run there as well.

## Run the app

```bash
npx serve .
```

Then open the printed URL. The page reads straight from `https://rpc.mainnet.arc.io` and writes through your injected wallet, switching it to chain 5042.

## Layout

```
src/ArcSplit.sol          the contract
test/ArcSplit.t.sol       10 Foundry tests
test/mocks/MockUSDC.sol   6-decimal token for the tests
index.html                the app (viem, no build step)
media/receipts.json       raw RPC receipts for the three mainnet transactions
```
