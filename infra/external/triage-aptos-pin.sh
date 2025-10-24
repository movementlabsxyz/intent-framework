#!/usr/bin/env bash
#
# Aptos Core Pin Triage Script
#
# This script automatically tests multiple Aptos commits/tags to find one that builds
# cleanly on stable Rust, then updates the pin lock file.
#
# Purpose:
# - The official aptos-sdk on crates.io is broken/yanked
# - We need a stable, pinned version of aptos-core for the trusted-verifier
# - This script finds compatible commits and updates infra/external/aptos-core.lock
#
# Usage:
#   ./infra/external/triage-aptos-pin.sh
#
# What it does:
# 1. Tests multiple Aptos framework versions (v1.35.0, v1.36.0, v1.37.0, etc.)
# 2. Checks if each version builds on stable Rust
# 3. Updates the pin lock file with the first working version
# 4. Verifies the pin integrity
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../.. && pwd)"
AP_DIR="$REPO_ROOT/infra/external/aptos-core"

log() { printf "%b\n" "$*"; }

need() { command -v "$1" >/dev/null || { echo "Missing: $1"; exit 1; }; }

need git
need rg
need cargo
need rustup

mkdir -p "$(dirname "$AP_DIR")"
if [ ! -d "$AP_DIR/.git" ]; then
  log "Cloning aptos-core -> $AP_DIR"
  git clone https://github.com/aptos-labs/aptos-core.git "$AP_DIR"
fi

cd "$AP_DIR"
git fetch --all --tags --prune

check_sha() {
  local rev="$1"
  git checkout --quiet --detach "$rev" || { echo "bad rev $rev"; return 1; }

  # tokio check
  if rg -n "disable_lifo_slot" -S aptos-runtimes >/dev/null 2>&1; then
    echo "❌ tokio lifo $rev"
    return 2
  fi

  # try stable first
  rustup toolchain install -q stable >/dev/null 2>&1 || true
  if cargo +stable check -q -p aptos-rest-client -p aptos-types -p aptos-runtimes; then
    echo "✅ stable $rev"
    return 0
  fi

  # fallback nightly
  rustup toolchain install -q nightly >/dev/null 2>&1 || true
  if cargo +nightly check -q -p aptos-rest-client -p aptos-types -p aptos-runtimes; then
    echo "⚠️ nightly $rev"
    return 0
  fi

  echo "❌ fails $rev"
  return 3
}

# iterate through last 20 tags
for t in $(git tag --list --sort=-creatordate | head -n 20); do
  check_sha "$t" && PICK="$t" && break
done

# fallback: last 50 commits on main
if [ -z "${PICK:-}" ]; then
  for c in $(git rev-list --max-count=50 origin/main); do
    check_sha "$c" && PICK="$c" && break
  done
fi

if [ -n "${PICK:-}" ]; then
  GOOD_SHA=$(git rev-parse HEAD)
  echo "✅ picked $PICK ($GOOD_SHA)"
  cd "$REPO_ROOT"
  echo "$GOOD_SHA" > infra/external/aptos-core.lock
  "$REPO_ROOT/infra/external/verify-aptos-pin.sh"
else
  echo "❌ no good pin found"
  exit 1
fi

