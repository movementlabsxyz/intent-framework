#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../../.. && pwd)"
AP_DIR="$REPO_ROOT_DIR/infra/external/movement-aptos-core"

echo "[setup] Repo root: $REPO_ROOT_DIR"

if [ -d "$AP_DIR/.git" ]; then
  echo "[setup] Found external/movement-aptos-core. Updating to l1-migration…"
  git -C "$AP_DIR" fetch origin
  git -C "$AP_DIR" checkout l1-migration
  git -C "$AP_DIR" pull --ff-only origin l1-migration
  git -C "$AP_DIR" submodule update --init --recursive
else
  echo "[setup] Cloning external/movement-aptos-core (branch l1-migration)…"
  mkdir -p "$REPO_ROOT_DIR/infra/external"
  git clone --branch l1-migration https://github.com/movementlabsxyz/aptos-core.git "$AP_DIR"
  git -C "$AP_DIR" submodule update --init --recursive
fi

echo "[setup] aptos-core available at: $AP_DIR"

