#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

RELAYER_BIN="${RELAYER_BIN:-$HOME/.avalanche-cli/bin/icm-relayer/icm-relayer}"
CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/icm-relayer-config.json}"

if pgrep -f "icm-relayer.*$CONFIG_FILE" >/dev/null 2>&1; then
  echo "ICM relayer is already running."
  exit 0
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Relayer config not found at $CONFIG_FILE"
  echo "Generate it with: npx tsx scripts/generate-relayer-config.ts"
  exit 1
fi

if [[ ! -x "$RELAYER_BIN" ]]; then
  echo "Relayer binary not found at $RELAYER_BIN"
  echo "Install it with Avalanche CLI or download the icm-relayer release."
  exit 1
fi

echo "Starting ICM relayer..."
nohup "$RELAYER_BIN" --config-file "$CONFIG_FILE" > /tmp/icm-relayer.log 2>&1 &
echo $! > "$ROOT_DIR/.relayer.pid"
sleep 3

if pgrep -f "icm-relayer.*$CONFIG_FILE" >/dev/null 2>&1; then
  echo "ICM relayer started (PID $(cat "$ROOT_DIR/.relayer.pid"))."
  echo "Logs: tail -f /tmp/icm-relayer.log"
else
  echo "Relayer failed to start. See /tmp/icm-relayer.log"
  exit 1
fi
