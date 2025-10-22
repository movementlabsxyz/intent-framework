#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../../.. && pwd)"
AP_DIR="$REPO_ROOT_DIR/infra/external/aptos-core"
LOCK_FILE="$REPO_ROOT_DIR/infra/external/aptos-core.lock"

echo "[setup] Repo root: $REPO_ROOT_DIR"

if [ -d "$AP_DIR/.git" ]; then
  echo "[setup] Found external/aptos-core. Checking out pinned commit..."
  git -C "$AP_DIR" fetch origin
  
  # Check if lock file exists and has a valid commit
  if [ -f "$LOCK_FILE" ] && [ "$(tr -d ' \t\n' < "$LOCK_FILE")" != "0000000000000000000000000000000000000000" ]; then
    PINNED_COMMIT="$(tr -d ' \t\n' < "$LOCK_FILE")"
    echo "[setup] Checking out pinned commit: $PINNED_COMMIT"
    git -C "$AP_DIR" checkout "$PINNED_COMMIT"
  else
    echo "[setup] No valid lock file, updating to main..."
    git -C "$AP_DIR" checkout main
    git -C "$AP_DIR" pull --ff-only origin main
  fi
  
  git -C "$AP_DIR" submodule update --init --recursive
else
  echo "[setup] Cloning external/aptos-core..."
  mkdir -p "$REPO_ROOT_DIR/infra/external"
  git clone https://github.com/aptos-labs/aptos-core.git "$AP_DIR"
  
  # Check if lock file exists and has a valid commit
  if [ -f "$LOCK_FILE" ] && [ "$(tr -d ' \t\n' < "$LOCK_FILE")" != "0000000000000000000000000000000000000000" ]; then
    PINNED_COMMIT="$(tr -d ' \t\n' < "$LOCK_FILE")"
    echo "[setup] Checking out pinned commit: $PINNED_COMMIT"
    git -C "$AP_DIR" checkout "$PINNED_COMMIT"
  else
    echo "[setup] No valid lock file, using main branch..."
    git -C "$AP_DIR" checkout main
  fi
  
  git -C "$AP_DIR" submodule update --init --recursive
fi

echo "[setup] aptos-core available at: $AP_DIR"

