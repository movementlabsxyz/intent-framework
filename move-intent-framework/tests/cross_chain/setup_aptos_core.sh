#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../../.. && pwd)"
AP_DIR="$REPO_ROOT_DIR/infra/external/aptos-core"

echo "[setup] Repo root: $REPO_ROOT_DIR"

if [ -d "$AP_DIR/.git" ]; then
  echo "[setup] Found external/aptos-core. Updating to main…"
  git -C "$AP_DIR" fetch origin
  git -C "$AP_DIR" checkout main
  git -C "$AP_DIR" pull --ff-only origin main
  git -C "$AP_DIR" submodule update --init --recursive
else
  echo "[setup] Cloning external/aptos-core (branch main)…"
  mkdir -p "$REPO_ROOT_DIR/infra/external"
  git clone --branch main https://github.com/aptos-labs/aptos-core.git "$AP_DIR"
  git -C "$AP_DIR" submodule update --init --recursive
fi

echo "[setup] aptos-core available at: $AP_DIR"

