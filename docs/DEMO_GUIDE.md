# Step-By-Step Demo Guide

This guide walks through every command required to run the cross-subnet demo from a fresh checkout. It assumes macOS or Linux with a terminal and an internet connection.

## Prerequisites

| Tool | Purpose | Check command |
|---|---|---|
| Node.js 20+ | TypeScript scripts | `node --version` |
| npm | Package manager | `npm --version` |
| Foundry | Solidity compiler & test runner | `forge --version` |
| `cast` (comes with Foundry) | CLI Ethereum wallet & RPC calls | `cast --version` |
| Avalanche CLI | Local network and L1 management | `avalanche --version` |
| Python 3 | JSON parsing helper in deploy script | `python3 --version` |
| `tsx` | TypeScript runner (installed by npm) | `npx tsx --version` |

If you are missing any of the above, install them first:

```bash
# Node.js: https://nodejs.org/ (use the LTS installer or your package manager)

# Foundry:
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Avalanche CLI:
curl -sSfL https://raw.githubusercontent.com/ava-labs/avalanche-cli/main/scripts/install.sh | sh -
# Then restart your terminal or run: export PATH="$HOME/.avalanche-cli/bin:$PATH"
```

## Step 1: Clone and install

```bash
git clone <repository-url>
cd cross-subnet-agent-coordinator
npm install
forge build
```

## Step 2: Create your environment file

```bash
cp .env.example .env
```

Edit `.env` and replace the agent/keeper keys with your own **different** funded keys. On a local network, you can generate four random keys with `cast`:

```bash
cast wallet new
cast wallet new
cast wallet new
cast wallet new
```

Fill them into `.env`:

```bash
# .env (example)
# The deploy script auto-funds from the Avalanche ewoq genesis key.
# You only need the deployer key if you override it.
DEPLOYER_PRIVATE_KEY=<local-genesis-key-or-ewoq>
INITIATOR_PRIVATE_KEY=<key-1>
EXECUTOR_PRIVATE_KEY=<key-2>
KEEPER_PRIVATE_KEY=<key-3>
RELAYER_PRIVATE_KEY=<key-4>
```

> **Important:** Using separate keys for each role makes the final balance report clean and readable. All four keys will be funded automatically by the deploy script on the local network.

## Step 3: Deploy the local Avalanche L1s, ICM, contracts, and relayer

This single command does everything:

```bash
npm run deploy:local
```

What it does internally:

1. Ensure Avalanche CLI configs exist for `initiatorSubnet` and `settlementSubnet` (creates them non-interactively with all validator and chain flags if missing).
2. `avalanche blockchain deploy initiatorSubnet --local --ewoq`
3. `avalanche blockchain deploy settlementSubnet --local --ewoq`
4. `avalanche icm deploy --local --blockchain initiatorSubnet --genesis-key`
5. `avalanche icm deploy --local --blockchain settlementSubnet --genesis-key`
6. Parse `~/.avalanche-cli/subnets/{initiator,settlement}Subnet/sidecar.json`
7. Convert cb58 blockchain IDs to hex and write `deployed.json`
8. Deploy mocks (`MockWAVAX`, `MockUSDC`, `MockDEX`)
9. Deploy `SettlementMessenger`, `TradeEscrow`, wire up escrow
10. Deploy `InitiatorMessenger`, wire up initiator messenger
11. Generate `icm-relayer-config.json`
12. Fund the Initiator, Executor, Keeper, Initiator Payout, and relayer accounts on their respective subnets
13. Start the ICM relayer

> **Note for Intel Mac users:** The script automatically pins `--vm-version v0.7.3` and `--avalanchego-version v1.13.0` on macOS x86_64 to avoid the missing prebuilt binary for AvalancheGo v1.14.0+.

If anything fails mid-way, you can resume from individual steps. See the script source in `scripts/deploy-local.sh` or the README for the individual commands.

## Step 4: Verify the deployment

```bash
npm run bootstrap
```

This checks that both L1s are reachable and all contracts exist at the addresses written to `deployed.json`. Expected output:

```text
Verifying L1 connectivity and contract deployments...

✓ Initiator L1 (http://127.0.0.1:9654/ext/bc/.../rpc) - Block: 17
✓ Settlement L1 (http://127.0.0.1:9656/ext/bc/.../rpc) - Block: 96
✓ InitiatorMessenger deployed at 0x789a5FDac2b37FCD290fb2924382297A6AE65860
✓ SettlementMessenger deployed at 0x4a433BFD4D53A0657B15529D4880Dd0165a0CA2B
✓ TradeEscrow deployed at 0xd17C755b49A831CDF32Fb5C797cFdf3aD5Bbae24
✓ MockWAVAX deployed at 0x764a0e52e145BF7c970A0677856f2242fD06DB81
✓ MockUSDC deployed at 0xEC1bf080BDFBbBa102603Cc1C55aFd215C694a2b
✓ MockDEX deployed at 0x473dc5ba848779e00ec2615FF15EDeA1A21fAa62

✓ All L1s reachable and contracts verified at deployed addresses.
```

## Step 5: Run the cross-subnet demo

```bash
npm run demo
```

Expected output (addresses will differ because the relayer generates a new order ID each run):

```text
Initiator: 0xAd8bD56907Ca54D4562D043e9761B7681a952CE7
Executor: 0xb756d4fdc8d73ad433D664a955FDe4290a643F1E
Keeper: 0x21Cd01077F429DBD96247491395b98D399B362C4
Initiator Payout: 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65

Relayer already running.
--- Funding & approvals ---
Executor mWAVAX: 500000
MockDEX mUSDC: 2000

--- Initiator sends order ---
Order ID: 0x...
Order sent. Tx: 0x...

--- Waiting for ICM relayer to deliver message ---
Message delivered and escrow leg opened.

--- Executor executes trade ---
Commission: 250 mWAVAX
Trade amount: 499750 mWAVAX
Executor mUSDC after swap: 1000
Trade closed

--- Keeper triggers payout ---
Commission paid

--- Final balances ---
Escrow mWAVAX: 0
Escrow mUSDC: 0
Initiator Payout mWAVAX: 250
Keeper mWAVAX: 0
Executor mWAVAX: 0
Executor mUSDC: 1000

Demo completed successfully.
```

## Step 5.5: Verify the cross-subnet transaction trail

```bash
npx tsx scripts/verify-demo.ts
```

This script prints a complete cryptographic transaction trail: the `OrderSent` event on the Initiator L1, the cross-chain message delivery via Teleporter/ICM, and the `OrderReceived`, `TradeFunded`, `TradeExecuted`, and `CommissionPaid` events on the Settlement L1. It also verifies the final escrow balances and the invariant that the commission could only go to the fixed initiator payout address.

## Step 6: (Optional) Start and stop the relayer manually

```bash
# Generate or regenerate config after a fresh deploy
npm run relayer:config

# Start the relayer in the background
npm run relayer:start

# Stop it
npm run relayer:stop
```

Logs are written to `/tmp/icm-relayer.log`.

## Step 7: (Optional) Run tests

```bash
npm test
```

Expected output:

```text
Ran 2 test suites in 12ms: 21 tests passed, 0 failed, 0 skipped
```

## Troubleshooting

### "deployed.json not found"

You forgot `npm run deploy:local`. Run it first.

### "Timed out waiting for cross-chain message delivery. Is the relayer running?"

```bash
npm run relayer:start
```

Then run `npm run demo` again.

### "Error: avalanche not found in PATH"

Avalanche CLI was not installed or is not in your `$PATH`:

```bash
export PATH="$HOME/.avalanche-cli/bin:$PATH"
```

### Relayer fails with "insufficient funds"

The relayer address printed during `npm run deploy:local` must have native AVAX on the Settlement Subnet. The deploy script funds it automatically from the network genesis account, but if you change `.env` after deployment, you may need to fund it manually:

```bash
cast send --rpc-url <settlement-rpc> --private-key <genesis-key> --value 10ether <relayer-address>
```

### "Error: forge not found"

Install Foundry:

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

### Deploy script exited non-zero during `avalanche blockchain deploy`

On Intel Macs the script automatically pins a compatible AvalancheGo version. If you still see errors, stop any running network with `avalanche network stop` and run `npm run deploy:local` again. You can also remove stale subnet configs with `rm -rf ~/.avalanche-cli/subnets/initiatorSubnet ~/.avalanche-cli/subnets/settlementSubnet` before retrying.
