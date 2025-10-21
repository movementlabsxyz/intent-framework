#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)"
LOCK_FILE="$REPO_ROOT_DIR/infra/external/aptos-core.lock"
AP_DIR="$REPO_ROOT_DIR/infra/external/aptos-core"

if [ ! -f "$LOCK_FILE" ]; then
  echo "[verify] Lock file missing: $LOCK_FILE" >&2
  exit 1
fi

if [ ! -d "$AP_DIR/.git" ]; then
  echo "[verify] aptos-core repo missing at: $AP_DIR (run setup_aptos_core.sh)" >&2
  exit 1
fi

EXPECTED_SHA=$(tr -d ' \t\n' < "$LOCK_FILE")
ACTUAL_SHA=$(git -C "$AP_DIR" rev-parse HEAD || echo none)

if [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
  echo "[verify] aptos-core mismatch" >&2
  echo "         expected: $EXPECTED_SHA" >&2
  echo "         actual:   $ACTUAL_SHA" >&2
  exit 1
fi

echo "[verify] aptos-core pinned correctly: $ACTUAL_SHA"

