# Teleporter / ICM Guide

This project uses Avalanche Interchain Messaging (ICM), historically also called Teleporter, for cross-L1 messaging. The contracts implement the standard Teleporter receiver interface and run against the real `TeleporterMessenger` contracts deployed by Avalanche CLI on local L1s.

## Receiver interface

`SettlementMessenger.sol` implements:

```solidity
function receiveTeleporterMessage(
    bytes32 sourceBlockchainID,
    address originSenderAddress,
    bytes calldata message
) external;
```

This is the current Avalanche Teleporter/ICM receiver API. The older `onTeleporterMessage(...)` interface is not used.

## Authentication checks

`SettlementMessenger.receiveTeleporterMessage` enforces three checks:

1. `msg.sender == teleporterMessenger` — only the destination `TeleporterMessenger` contract can deliver.
2. `sourceBlockchainID == initiatorBlockchainID` — only the configured Initiator L1.
3. `originSenderAddress == initiatorMessenger` — only the configured Initiator Messenger contract.

If any check fails, the call reverts.

## Message format

The initiator messenger encodes a `CREATE_ORDER` message:

```solidity
abi.encode(
    MESSAGE_TYPE_CREATE_ORDER,
    orderId,
    tokenIn,
    tokenOut,
    amountIn,
    minAmountOut,
    commissionBps,
    initiatorPayout
)
```

The settlement messenger decodes this tuple and calls `TradeEscrow.openLeg(...)`.

## Local deployment and relayer

Avalanche CLI normally deploys `TeleporterMessenger` and a relayer automatically during `avalanche blockchain deploy --local`. This project splits the process to remain fully non-interactive and compatible with all platforms (including Intel Macs):

1. `avalanche blockchain create` runs non-interactively with all validator, chain, and ICM flags pre-populated (including `--validator-manager-owner`, `--proxy-contract-owner`, `--evm-chain-id`, `--icm`, `--sovereign`, and on Intel Macs `--vm-version v0.7.3`).
2. `avalanche blockchain deploy --local` boots the network and creates the L1 chains (on Intel Macs it pins `--avalanchego-version v1.13.0` for compatibility).
3. `avalanche icm deploy --local --blockchain <name> --genesis-key` deploys `TeleporterMessenger` and `TeleporterRegistry` to each L1.
4. `scripts/generate-relayer-config.ts` reads `deployed.json` and `.env` and writes `icm-relayer-config.json`.
5. `scripts/start-relayer.sh` runs a dedicated `icm-relayer` process.

The relayer listens for outgoing Teleporter messages on the Initiator L1, aggregates the Warp signature, and submits `receiveCrossChainMessage` on the Settlement L1's `TeleporterMessenger`. That contract then calls `SettlementMessenger.receiveTeleporterMessage(...)`.

For the demo to work end-to-end, the relayer must be configured for the `initiatorSubnet -> settlementSubnet` pair. If the auto-generated config does not work, run:

```bash
npm run relayer:config
npm run relayer:start
```

## Configuration values

After `npm run deploy:local`, `deployed.json` contains:

- `initiator.rpcUrl` / `settlement.rpcUrl`
- `initiator.chainId` / `settlement.chainId`
- `initiator.blockchainId` / `settlement.blockchainId` (hex)
- `initiator.blockchainIdCb58` / `settlement.blockchainIdCb58`
- `initiator.teleporterMessenger` / `settlement.teleporterMessenger`

See `.env.example` for the role key and demo parameter template.

## Unit-test mocks

Foundry tests use a minimal `MockTeleporterMessenger` so the Solidity logic can be exercised without a live Avalanche network. The mock is only for unit tests; the runnable demo always uses the real Avalanche Teleporter/ICM infrastructure.
