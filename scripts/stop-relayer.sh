#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="$ROOT_DIR/.relayer.pid"

if [[ -f "$PID_FILE" ]]; then
  PID=$(cat "$PID_FILE")
  if kill "$PID" >/dev/null 2>&1; then
    echo "Stopped ICM relayer (PID $PID)."
  else
    echo "Relayer process $PID not running."
  fi
  rm -f "$PID_FILE"
else
  echo "No relayer PID file found; killing any matching process..."
  pkill -f "icm-relayer" || true
fi
