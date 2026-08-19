# Architecture

## Overview

The Cross-Subnet Order Coordinator demonstrates two sovereign Avalanche L1s coordinating a single-leg, deterministic trade. The economic relationship is enforced by `TradeEscrow` rather than by trust in the Executor.

## Components

### Initiator Subnet

- **Initiator:** Off-chain agent that creates orders and calls `InitiatorMessenger.sendOrder()`.
- **InitiatorMessenger:** Solidity contract that encodes the order and sends it via Avalanche Teleporter/ICM.

### Cross-subnet transport

- **Teleporter / ICM:** Avalanche's native cross-L1 messaging protocol.
- **Relayer:** A dedicated ICM relayer started by `npm run relayer:start`. It listens for outgoing messages on the Initiator L1 and delivers them to the Settlement L1 via the destination `TeleporterMessenger`.

### Settlement Subnet

- **SettlementMessenger:** Receives the Teleporter message, validates source blockchain and origin sender, and calls `TradeEscrow.openLeg()`.
- **TradeEscrow:** Locks commission, enforces slippage, and releases commission to a fixed initiator payout address.
- **Executor:** Receives the trade amount from escrow, executes the swap via `MockDEX`, deposits output back into escrow, and calls `closeOpenLeg()`.
- **Keeper:** Permissionless caller that triggers `payOpenCommission()` after the trade is executed.

## Data flow

```text
Initiator
    |
    | sendOrder()
    v
InitiatorMessenger
    |
    | Teleporter message
    v
Relayer
    |
    v
SettlementMessenger
    |
    | openLeg()
    v
TradeEscrow
    | locks commission
    | returns tradeAmount
    v
Executor
    |
    | MockDEX.swap()
    v
TradeEscrow.closeOpenLeg()
    | verifies output
    | executed = true
    v
Keeper.payOpenCommission()
    v
initiatorPayout receives commission
```

## Trust boundaries

- The Initiator trusts the InitiatorMessenger to send its order unchanged.
- The Settlement Messenger trusts Teleporter to authenticate the source.
- The Executor must execute the swap honestly enough to produce `amountOut >= minAmountOut`.
- The Keeper is untrusted with respect to payout destination; the escrow fixes the destination.
- The escrow is the root of trust for commission release.

## Deployment order

1. Deploy mocks (`MockWAVAX`, `MockUSDC`, `MockDEX`) on Settlement Subnet.
2. Deploy `SettlementMessenger` with placeholder initiator messenger and zero escrow.
3. Deploy `TradeEscrow` pointing to the Executor and `SettlementMessenger`.
4. Call `SettlementMessenger.setEscrow(tradeEscrow)`.
5. Deploy `InitiatorMessenger` on Initiator Subnet pointing to `SettlementMessenger`.
6. Call `SettlementMessenger.setInitiatorMessenger(initiatorMessenger)`.

This order resolves the circular dependency between `SettlementMessenger` and `InitiatorMessenger`.

## Current limitations

- `TradeEscrow` authorizes payout based on its own on-chain `executed` flag. It does not independently verify a Teleporter execution proof (this is a known design choice for the current implementation; see `docs/EXTENDING.md`).
- `MockDEX` is a deterministic swap mock, not a real DEX integration.
- No timeout, refund, or dispute handling for stuck trades.
- Only single-token-in, single-token-out swaps are supported.
