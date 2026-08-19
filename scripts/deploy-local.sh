#!/usr/bin/env bash
set -euo pipefail

# Deploy two local Avalanche L1s using Avalanche CLI, deploy ICM/Teleporter,
# start the ICM relayer, and deploy the project contracts.
#
# NOTE: On some platforms (e.g. Intel Macs) Avalanche CLI's local L1 deploy
# fails at the Proof-of-Authority Validator Manager initialization step due to
# a Signature Aggregator incompatibility. This script works around that by:
#   1. Creating the Subnet-EVM chains with the CLI.
#   2. Running `avalanche blockchain deploy --local` to boot the network and
#      create the chains. The command may exit non-zero at the PoA step, but
#      the chains are already running with RPC endpoints.
#   3. Deploying ICM/Teleporter separately with `avalanche icm deploy`.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

INITIATOR_NAME="${INITIATOR_NAME:-initiatorSubnet}"
SETTLEMENT_NAME="${SETTLEMENT_NAME:-settlementSubnet}"

INITIATOR_CHAIN_ID="${INITIATOR_CHAIN_ID:-12345}"
SETTLEMENT_CHAIN_ID="${SETTLEMENT_CHAIN_ID:-67890}"

P_CHAIN_URL="${P_CHAIN_URL:-http://127.0.0.1:9650}"

# Well-known ewoq key used by Avalanche CLI to fund local network operations.
# You can override via DEPLOYER_PRIVATE_KEY in .env if your local network uses a
# different genesis key.
EWOQ_PK="${DEPLOYER_PRIVATE_KEY:-0x56289e99c94b6912bfc12adc093c9b51124f0dc54ac7a766b2bc5ccf558d8027}"

cd "$ROOT_DIR"

for cmd in avalanche forge python3 tsx; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "Error: $cmd not found in PATH."
    exit 1
  fi
done

# Load .env so we can read RELAYER_PRIVATE_KEY and role keys.
if [[ -f .env ]]; then
  set -a
  # shellcheck source=/dev/null
  source .env
  set +a
fi

echo "Building contracts..."
forge build

echo ""
echo "Ensuring Avalanche L1 configurations exist..."

# NOTE: `avalanche blockchain describe` exits 0 even for non-existent blockchains,
# so we check for the CLI's config directory instead.
EWOQ_ADDR=$(cast wallet address "$EWOQ_PK")

# On Intel Macs, AvalancheGo v1.14.0+ has no prebuilt macOS amd64 binary.
# Pin Subnet-EVM v0.7.3 (RPC 39) which is compatible with AvalancheGo v1.13.0.
VM_VERSION_FLAG=""
AVALANCHEGO_VERSION_FLAG=""
if [[ "$(uname -s)" == "Darwin" && "$(uname -m)" == "x86_64" ]]; then
  echo "Intel Mac detected. Using Subnet-EVM v0.7.3 and AvalancheGo v1.13.0 for compatibility."
  VM_VERSION_FLAG="--vm-version v0.7.3"
  AVALANCHEGO_VERSION_FLAG="--avalanchego-version v1.13.0"
fi

create_blockchain_config() {
  local name="$1" chain_id="$2" token="$3"
  # shellcheck disable=SC2086
  avalanche blockchain create "$name" \
    --evm \
    --proof-of-authority \
    --validator-manager-owner "$EWOQ_ADDR" \
    --proxy-contract-owner "$EWOQ_ADDR" \
    --evm-chain-id "$chain_id" \
    --evm-token "$token" \
    --test-defaults \
    --icm \
    --sovereign \
    --force \
    --skip-update-check \
    $VM_VERSION_FLAG
}

if [[ ! -f "$HOME/.avalanche-cli/subnets/$INITIATOR_NAME/chain.json" ]]; then
  echo "Creating $INITIATOR_NAME..."
  create_blockchain_config "$INITIATOR_NAME" "$INITIATOR_CHAIN_ID" "INIT"
fi

if [[ ! -f "$HOME/.avalanche-cli/subnets/$SETTLEMENT_NAME/chain.json" ]]; then
  echo "Creating $SETTLEMENT_NAME..."
  create_blockchain_config "$SETTLEMENT_NAME" "$SETTLEMENT_CHAIN_ID" "SETL"
fi

echo ""
echo "Deploying $INITIATOR_NAME to local network (best-effort)..."
set +e
# shellcheck disable=SC2086
avalanche blockchain deploy "$INITIATOR_NAME" --local --ewoq --skip-update-check $AVALANCHEGO_VERSION_FLAG < /dev/null
INITIATOR_DEPLOY_STATUS=$?
set -e

echo ""
echo "Deploying $SETTLEMENT_NAME to local network (best-effort)..."
set +e
# shellcheck disable=SC2086
avalanche blockchain deploy "$SETTLEMENT_NAME" --local --ewoq --skip-update-check $AVALANCHEGO_VERSION_FLAG < /dev/null
SETTLEMENT_DEPLOY_STATUS=$?
set -e

if [[ $INITIATOR_DEPLOY_STATUS -ne 0 || $SETTLEMENT_DEPLOY_STATUS -ne 0 ]]; then
  echo ""
  echo "Warning: avalanche blockchain deploy exited with errors."
  echo "This is expected on some platforms. The chains should still be running."
fi

echo ""
echo "Deploying ICM/Teleporter to the L1s..."
avalanche icm deploy --local --blockchain "$INITIATOR_NAME" --genesis-key --skip-update-check
avalanche icm deploy --local --blockchain "$SETTLEMENT_NAME" --genesis-key --skip-update-check

echo ""
echo "Capturing deployment details from Avalanche CLI sidecars..."

SIDECAR_INITIATOR="$HOME/.avalanche-cli/subnets/$INITIATOR_NAME/sidecar.json"
SIDECAR_SETTLEMENT="$HOME/.avalanche-cli/subnets/$SETTLEMENT_NAME/sidecar.json"

if [[ ! -f "$SIDECAR_INITIATOR" || ! -f "$SIDECAR_SETTLEMENT" ]]; then
  echo "Error: Could not find Avalanche CLI sidecar files."
  echo "  $SIDECAR_INITIATOR"
  echo "  $SIDECAR_SETTLEMENT"
  exit 1
fi

python3 - "$SIDECAR_INITIATOR" "$SIDECAR_SETTLEMENT" "$P_CHAIN_URL" <<'PY'
import json, sys, urllib.request

ALPHABET = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

def b58decode(s):
    val = 0
    for c in s:
        val = val * 58 + ALPHABET.index(c)
    result = []
    while val > 0:
        val, mod = divmod(val, 256)
        result.append(mod)
    return bytes(reversed(result))

def cb58_to_hex(s):
    data = b58decode(s)
    payload = data[:-4]
    return "0x" + payload.hex()

def load_sidecar(path):
    with open(path) as f:
        return json.load(f)

def get_local_network(sidecar):
    return sidecar["Networks"]["Local Network"]

initiator_path, settlement_path, p_chain_url = sys.argv[1:4]

i_sidecar = load_sidecar(initiator_path)
settlementSidecar = load_sidecar(settlement_path)

initiatorNet = get_local_network(i_sidecar)
settlementNet = get_local_network(settlementSidecar)

initiator_blockchain_id_cb58 = initiatorNet["BlockchainID"]
settlement_blockchain_id_cb58 = settlementNet["BlockchainID"]

deployed = {
    "initiator": {
        "name": i_sidecar["Name"],
        "rpcUrl": initiatorNet["RPCEndpoints"][0],
        "wsUrl": initiatorNet["WSEndpoints"][0],
        "chainId": int(i_sidecar["ChainID"]) if i_sidecar["ChainID"] else 12345,
        "blockchainId": cb58_to_hex(initiator_blockchain_id_cb58),
        "blockchainIdCb58": initiator_blockchain_id_cb58,
        "subnetId": initiatorNet["SubnetID"],
        "teleporterMessenger": "0x253b2784c75e510dD0fF1da844684a1aC0aa5fcf",
        "initiatorMessenger": "",
    },
    "settlement": {
        "name": settlementSidecar["Name"],
        "rpcUrl": settlementNet["RPCEndpoints"][0],
        "wsUrl": settlementNet["WSEndpoints"][0],
        "chainId": int(settlementSidecar["ChainID"]) if settlementSidecar["ChainID"] else 67890,
        "blockchainId": cb58_to_hex(settlement_blockchain_id_cb58),
        "blockchainIdCb58": settlement_blockchain_id_cb58,
        "subnetId": settlementNet["SubnetID"],
        "teleporterMessenger": "0x253b2784c75e510dD0fF1da844684a1aC0aa5fcf",
        "mockWAVAX": "",
        "mockUSDC": "",
        "mockDEX": "",
        "tradeEscrow": "",
        "settlementMessenger": "",
    },
}

with open("deployed.json", "w") as f:
    json.dump(deployed, f, indent=2)

print(json.dumps(deployed, indent=2))
PY

echo ""
echo "Deployment details written to deployed.json"

echo ""
echo "Deploying project contracts to the local L1s..."
npx tsx "$SCRIPT_DIR/deploy-contracts.ts"

echo ""
echo "Generating ICM relayer configuration..."
npx tsx "$SCRIPT_DIR/generate-relayer-config.ts"

# Fund role accounts so the demo can pay for gas.
INITIATOR_RPC=$(python3 -c "import json; print(json.load(open('deployed.json'))['initiator']['rpcUrl'])")
SETTLEMENT_RPC=$(python3 -c "import json; print(json.load(open('deployed.json'))['settlement']['rpcUrl'])")

fund_if_empty() {
  local rpc="$1" addr="$2" label="$3"
  local balance
  balance=$(cast balance --rpc-url "$rpc" "$addr")
  if [[ "$balance" == "0" ]]; then
    echo "Funding $label $addr..."
    cast send --rpc-url "$rpc" --private-key "$EWOQ_PK" --value 10ether "$addr" >/dev/null
  fi
}

INITIATOR_ADDR=$(cast wallet address "${INITIATOR_PRIVATE_KEY:-$EWOQ_PK}")
EXECUTOR_ADDR=$(cast wallet address "${EXECUTOR_PRIVATE_KEY:-$EWOQ_PK}")
KEEPER_ADDR=$(cast wallet address "${KEEPER_PRIVATE_KEY:-$EWOQ_PK}")
PAYOUT_ADDR="${INITIATOR_PAYOUT_ADDRESS:-$INITIATOR_ADDR}"

fund_if_empty "$INITIATOR_RPC" "$INITIATOR_ADDR" "Initiator"
fund_if_empty "$SETTLEMENT_RPC" "$EXECUTOR_ADDR" "Executor"
fund_if_empty "$SETTLEMENT_RPC" "$KEEPER_ADDR" "Keeper"
fund_if_empty "$SETTLEMENT_RPC" "$PAYOUT_ADDR" "Initiator Payout"

# Fund the dedicated relayer account on the Settlement chain if one is configured.
RELAYER_KEY="${RELAYER_PRIVATE_KEY:-}"
if [[ -n "$RELAYER_KEY" ]]; then
  RELAYER_ADDR=$(cast wallet address "$RELAYER_KEY")
  RELAYER_BALANCE=$(cast balance --rpc-url "$SETTLEMENT_RPC" "$RELAYER_ADDR")
  if [[ "$RELAYER_BALANCE" == "0" ]]; then
    echo "Funding relayer account $RELAYER_ADDR on Settlement chain..."
    cast send --rpc-url "$SETTLEMENT_RPC" --private-key "$EWOQ_PK" --value 10ether "$RELAYER_ADDR" >/dev/null
  else
    echo "Relayer account $RELAYER_ADDR already funded."
  fi
fi

echo ""
echo "Starting ICM relayer..."
bash "$SCRIPT_DIR/start-relayer.sh"

echo ""
echo "Local Avalanche deployment complete."
echo "Run the demo with: npm run demo"
