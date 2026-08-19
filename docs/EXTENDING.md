# Extending the Project

This document lists the most natural upgrades from the escrow-enforced commission implementation to a production-ready cross-subnet agent coordination protocol.

## 1. Teleporter proof verification

Currently `TradeEscrow` authorizes payout based on its own on-chain `executed` flag. A possible extension is to integrate `TeleporterMessenger.verifyMessageProof()` so the escrow can independently verify a cross-subnet execution completion proof before releasing commission.

## 2. Real DEX integration

Replace `MockDEX` with a real Avalanche DEX such as Trader Joe or a GMX-style spot/perp pool. This requires:

- Accurate price/impact estimation off-chain.
- Proper slippage thresholds.
- Deadline and path parameters in the order payload.
- Handling of native AVAX wrapping where needed.

## 3. Timeout, refund, and dispute

The current implementation has no recovery path if the Executor fails to close the leg. Possible additions:

- An execution deadline after which the initiator can request a refund.
- A dispute window with an arbiter or optimistic resolution.
- Partial refund logic if output was partially deposited.

## 4. Close-leg / round-trip trading

Extend the trade struct to support both open and close legs:

- Commission on entry and exit.
- Payout conditions tied to net PnL.
- Separate `minAmountOut` for each leg.

## 5. Encrypted intents and commitment hashes

For production privacy:

- Commit to order parameters with a hash instead of sending plaintext.
- Reveal the preimage only after execution.
- Use encrypted payloads so only the executor can read details.

## 6. EIP-712 order signing

Allow an off-chain initiator to sign orders with EIP-712. The initiator messenger can verify the signature before sending the cross-chain message.

## 7. Automated keeper network

Replace the manual keeper with:

- A keeper network that watches `TradeExecuted` events.
- Incentive payments for keepers (without redirecting commission).
- MEV-resistant payout ordering.

## 8. Multi-token support

Generalize the escrow to handle arbitrary ERC-20s with different decimals:

- Normalize amounts off-chain or with a price oracle.
- Store token decimals per trade.
- Support multi-hop swaps.

## 9. Production controls

- Pausable contracts with role-based access.
- Upgradeable proxies for the messenger layer.
- Emergency fund recovery for stuck trades.
- Formal audit and fuzz testing.

## 10. Fuji and mainnet deployment

After the local path is stable:

- Deploy to Fuji with real Teleporter addresses.
- Run end-to-end tests on Fuji.
- Document mainnet deployment risks and mitigations.
