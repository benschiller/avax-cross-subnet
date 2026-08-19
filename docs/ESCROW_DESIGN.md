# Escrow Design

`TradeEscrow.sol` is the economic enforcement layer. It holds the commission until the Executor proves it has deposited enough output token, then releases the commission to a fixed initiator payout address.

## Commission math

Commission is calculated with floor integer division:

```solidity
commissionAmount = amountIn * commissionBps / 10_000;
tradeAmount      = amountIn - commissionAmount;
```

For the demo:

- `amountIn` = 500,000 mWAVAX = `500_000e18`
- `commissionBps` = 5
- `commissionAmount` = `500_000e18 * 5 / 10_000` = `250e18` mWAVAX
- `tradeAmount` = `499_750e18` mWAVAX

The commission value passed in the Teleporter message is informational only. The immutable `TradeEscrow.commissionBps` is the single source of truth.

## Token model

- **Input token:** `MockWAVAX`, 18 decimals.
- **Output token:** `MockUSDC`, 6 decimals.

The escrow works purely with ERC-20 transfers. There is no native AVAX branch inside the escrow.

## Trade lifecycle

### 1. Funding (`openLeg`)

Callable by the Executor or the trusted Settlement Messenger.

1. Require the order ID has not been used.
2. Pull `amountIn` of `tokenIn` from the Executor via `transferFrom`.
3. Calculate and lock `commissionAmount`.
4. Return `tradeAmount` to the Executor immediately.
5. Record `initiatorPayout`, `tokenIn`, `tokenOut`, `amountIn`, `minAmountOut`, and `commissionAmount`.
6. Emit `TradeFunded`.

### 2. Execution (`closeOpenLeg`)

Callable only by the Executor.

1. Require the trade is funded and not already executed.
2. Read the escrow's `tokenOut` balance.
3. Require `balance >= minAmountOut`.
4. Set `executed = true` before any external transfer.
5. Transfer the full `tokenOut` balance to the Executor.
6. Emit `TradeExecuted`.

### 3. Payout (`payOpenCommission`)

Permissionless caller, fixed destination.

1. Require `funded` and `executed`.
2. Require `commissionPaid == false`.
3. Set `commissionPaid = true` before the transfer.
4. Transfer `commissionAmount` of `tokenIn` to `trade.initiatorPayout`.
5. Emit `CommissionPaid`.

## Balance invariants

After a successful trade:

- Escrow holds `0` `tokenIn` (commission paid out).
- Escrow holds `0` `tokenOut` (output transferred out on close).
- Initiator payout received exactly `commissionAmount` of `tokenIn`.
- Executor received exactly `tradeAmount` of `tokenIn` after funding and `outputBalance` of `tokenOut` after close.

## Security properties

- **No double funding:** duplicate `orderId` reverts.
- **No early close:** close before funding reverts.
- **No double close:** second `closeOpenLeg` reverts.
- **Slippage enforcement:** insufficient output reverts.
- **No early payout:** payout before execution reverts.
- **No double payout:** second `payOpenCommission` reverts.
- **Caller cannot steal:** payout always goes to the stored `initiatorPayout`, never `msg.sender`.
- **Checks-effects-interactions:** state changes occur before external token transfers.

## Trust model

The current implementation relies on the escrow's on-chain `executed` flag to authorize commission payout. The Settlement Messenger validates the Teleporter message origin, but the escrow itself does not independently verify a Teleporter execution proof. This is an intentional simplification for the current demo; see `docs/EXTENDING.md` for a possible extension to integrate proof verification into the payout path.
