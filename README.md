# Cross-Subnet Order Coordinator

A minimal, reproducible demo of deterministic, non-custodial trade execution between two sovereign Avalanche L1s. No pooled deposits. No discretionary manager. Enforcement by escrow state, not trust — using native Avalanche Interchain Messaging (ICM / Teleporter).

> **Why this matters now:** On July 22, 2026, SEC Commissioner Hester Peirce warned that actively managed crypto vaults and lending pools may qualify as securities. ([Read the story](https://beincrypto.com/sec-crypto-vaults-securities-law/)) This demo shows a different architectural path: **bilateral, deterministic execution** that removes the actively-managed, pooled-deposit features regulators are targeting.

## What it demonstrates

- A **Initiator** on a private/permissioned L1 creates an order.
- The order crosses to a **Settlement L1** via Avalanche ICM / Teleporter.
- A **Settlement Messenger** authenticates the message and opens a leg in **TradeEscrow**.
- The escrow locks a 5 bps commission and returns the non-commission trade amount to the **Executor**.
- The Executor swaps tokens on a mock DEX and deposits the output back into escrow.
- The escrow verifies the output against the slippage threshold, marks the trade executed, and transfers the output to the Executor.
- A permissionless **Keeper** triggers commission payout, but the commission can only go to the recorded `initiatorPayout` address — the caller cannot redirect it.

The enforcement chain is escrow state, not trust in the Executor.

## Why this architecture matters

This demo is **not a vault, not a lending pool, and not a fund.** It is deterministic, bilateral execution infrastructure.

| What regulators are scrutinizing | What this demo does instead |
|---|---|
| Pooled deposits from multiple depositors | Two known counterparties; no pooling |
| Active manager selecting strategies for others | Initiator sends a single atomic order with immutable parameters |
| Curator earning profits for depositors | Fixed commission protocol fee, hard-coded at order open |
| Operator setting rates / LTV / liquidation terms | Slippage bound burned into the order; no post-hoc discretion |
| Note-style lending | No lending; escrow holds only until deterministic conditions are met |

Avalanche's subnet model adds a native compliance advantage: the **Initiator L1** and **Settlement L1** can be legally and operationally separated sovereign chains. The result is cross-subnet execution where enforcement is code, not trust.

## What this is not

This is a local-network demo with mock tokens and a mock DEX. It intentionally does not include:

- Independent Teleporter proof verification inside `TradeEscrow` (the escrow uses its own `executed` flag, authenticated by the Settlement Messenger).
- Real DEX integration, timeout handling, encrypted intents, or round-trip trading.
- Production access controls, upgradeability, or formal auditing.

These are documented in `docs/EXTENDING.md`.

## Quick start

### Prerequisites

| Tool | Version | Check |
|---|---|---|
| Node.js | 20+ | `node --version` |
| npm | 10+ | `npm --version` |
| Foundry | latest | `forge --version` |
| Avalanche CLI | latest | `avalanche --version` |
| Python 3 | 3.9+ | `python3 --version` |

Install missing tools:

```bash
# Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Avalanche CLI
curl -sSfL https://raw.githubusercontent.com/ava-labs/avalanche-cli/main/scripts/install.sh | sh -
# Restart your shell or: export PATH="$HOME/.avalanche-cli/bin:$PATH"
```

### Install dependencies

```bash
git clone <repository-url>
cd cross-subnet-agent-coordinator
npm install
forge build
```

### Configure keys

```bash
cp .env.example .env
```

Generate four separate keys (one for each role) and paste them into `.env`:

```bash
cast wallet new
cast wallet new
cast wallet new
cast wallet new
```

> Using separate keys is optional but recommended — it makes the demo's final balance report clean and readable. All role accounts (Initiator, Executor, Keeper, Initiator Payout, and relayer) are funded automatically by the deploy script on the local network.

### Deploy everything and run the demo

```bash
npm run deploy:local
npm run demo
```

`deploy:local` creates two Subnet-EVM L1s, deploys Teleporter/ICM, deploys the project contracts, generates the relayer config, funds the relayer, and starts the relayer.

> **Note for Intel Mac users:** `deploy:local` automatically pins `--vm-version v0.7.3` and `--avalanchego-version v1.13.0` on macOS x86_64 to avoid missing prebuilt binaries for newer AvalancheGo versions. The deploy is fully non-interactive and should complete without errors.

### Example demo output

```text
Initiator: 0xAd8bD56907Ca54D4562D043e9761B7681a952CE7
Executor: 0xb756d4fdc8d73ad433D664a955FDe4290a643F1E
Keeper: 0x21Cd01077F429DBD96247491395b98D399B362C4
Initiator Payout: 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65

Relayer already running.
--- Funding & approvals ---
Executor mWAVAX: 500000
MockDEX mUSDC: 4000

--- Initiator sends order ---
Order ID: 0x...
Order sent. Tx: 0x...

--- Waiting for ICM relayer to deliver message ---
Message delivered and escrow leg opened.

--- Executor executes trade ---
Commission: 250 mWAVAX
Trade amount: 499750 mWAVAX
Executor mUSDC after swap: 2000
Trade closed

--- Keeper triggers payout ---
Commission paid

--- Final balances ---
Escrow mWAVAX: 0
Escrow mUSDC: 0
Initiator Payout mWAVAX: 500
Keeper mWAVAX: 0
Executor mWAVAX: 0
Executor mUSDC: 2000

Demo completed successfully.
```

### Scripts

```bash
npm run test              # Foundry unit tests (21 tests)
npm run demo              # Full cross-L1 demo
npm run deploy:local      # One-shot deploy of L1s, ICM, contracts, relayer
npm run deploy:contracts  # Deploy only project contracts (requires deployed.json)
npm run relayer:config    # Regenerate icm-relayer-config.json
npm run relayer:start     # Start ICM relayer in the background
npm run relayer:stop      # Stop ICM relayer
npm run bootstrap         # Verify contracts exist at deployed.json addresses
```

## Architecture

```text
INITIATOR L1
  Initiator
       |
       | sendOrder()
       v
  InitiatorMessenger
       |
       | ICM / Teleporter message
       v
  ICM Relayer
       |
       v
SETTLEMENT L1
  SettlementMessenger
       |
       | openLeg()
       v
  TradeEscrow
       | locks 5 bps commission
       | returns tradeAmount to Executor
       v
  Executor
       |
       | MockDEX.swap()
       v
  TradeEscrow.closeOpenLeg()
       | verifies output, executed = true
       | transfers output to Executor
       v
  Keeper.payOpenCommission()
       v
  initiatorPayout receives commission
```

## Contracts

| Contract | Purpose |
|---|---|
| `TradeEscrow.sol` | Locks commission, enforces slippage, releases commission to fixed payout address |
| `InitiatorMessenger.sol` | Sends orders from Initiator L1 to Settlement L1 via Teleporter |
| `SettlementMessenger.sol` | Receives Teleporter messages and opens escrow legs |
| `MockWAVAX.sol` | 18-decimal input token |
| `MockUSDC.sol` | 6-decimal output token |
| `MockDEX.sol` | Deterministic swap mock |

## Project layout

```text
├── contracts/          # Solidity contracts
├── test/               # Foundry tests (uses mock Teleporter for unit testing)
├── scripts/
│   ├── deploy-local.sh         # One-shot deploy orchestration
│   ├── deploy-contracts.ts     # Contract deployment from deployed.json
│   ├── generate-relayer-config.ts
│   ├── start-relayer.sh
│   ├── stop-relayer.sh
│   ├── run-demo.ts
│   ├── verify-demo.ts          # Post-demo cryptographic transaction trail
│   └── bootstrap.ts            # Post-deploy verification
├── docs/
│   ├── ARCHITECTURE.md         # Components, data flow, deployment order
│   ├── TELEPORTER_GUIDE.md     # Receiver interface, message format, relayer
│   ├── ESCROW_DESIGN.md        # Commission math, lifecycle, invariants
│   ├── DEMO_GUIDE.md           # Every command to replicate the demo
│   └── EXTENDING.md            # Possible future upgrades
├── .env.example        # Configuration template
├── deployed.json.example
└── foundry.toml
```

## Security notes

1. **Teleporter proof not verified inside escrow.** `TradeEscrow` trusts the Settlement Messenger's authentication of the Teleporter message. The escrow's `executed` flag is set when `closeOpenLeg()` succeeds, not by an independent proof check.
2. **No access control on `receiveTeleporterMessage`.** The Settlement Messenger relies entirely on the `msg.sender == teleporterMessenger` check combined with source-blockchain and origin-sender validation.
3. **No timeout or refund.** If the Executor never calls `closeOpenLeg()`, funds remain locked in escrow indefinitely.
4. **Mock tokens and DEX.** The demo uses mintable ERC-20s and a deterministic swap mock. Do not deploy these mocks to a public network.
5. **Role keys in `.env`.** The `.env` file contains private keys. It is listed in `.gitignore` and must never be committed.

## Documentation

- [`docs/DEMO_GUIDE.md`](docs/DEMO_GUIDE.md) — full step-by-step replication guide.
- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — components, data flow, and deployment order.
- [`docs/ESCROW_DESIGN.md`](docs/ESCROW_DESIGN.md) — commission math, balance invariants, permissionless payout.
- [`docs/TELEPORTER_GUIDE.md`](docs/TELEPORTER_GUIDE.md) — receiver interface, source validation, relayer setup.
- [`docs/EXTENDING.md`](docs/EXTENDING.md) — possible upgrades: proof verification, real DEX, timeouts, privacy.

## License

MIT
