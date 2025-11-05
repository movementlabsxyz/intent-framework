#!/usr/bin/env python3
"""
Stop dual-chain setup for Aptos testing.

This script stops both Docker-based Aptos chains and cleans up all Aptos CLI profiles.
Python equivalent of stop-dual-chains.sh
"""

import sys
from pathlib import Path

# Add parent directory to path to import common
sys.path.insert(0, str(Path(__file__).parent.parent))
from common import setup_project_root, setup_logging, log, log_and_echo, run_command


def main():
    """Stop dual-chain setup and clean up profiles."""
    # Setup project root and logging
    setup_project_root(Path(__file__))
    setup_logging("stop-dual-chains")

    log("🛑 STOPPING DUAL-CHAIN SETUP")
    log("=============================")

    # Stop Chain 1
    log("🧹 Stopping Chain 1...")
    run_command(
        "docker-compose -f testing-infra/connected-chain-apt/docker-compose-chain1.yml "
        "-p aptos-chain1 down"
    )

    # Stop Chain 2
    log("🧹 Stopping Chain 2...")
    run_command(
        "docker-compose -f testing-infra/connected-chain-apt/docker-compose-chain2.yml "
        "-p aptos-chain2 down"
    )

    log("")
    log("🧹 Cleaning up Aptos CLI profiles...")

    # Delete all profiles (ignore errors if profiles don't exist)
    profiles = [
        "alice-chain1",
        "bob-chain1",
        "alice-chain2",
        "bob-chain2",
        "intent-account-chain1",
        "intent-account-chain2"
    ]

    for profile in profiles:
        run_command(f"aptos config delete-profile --profile {profile}", check=False)

    log("")
    log_and_echo("✅ Both chains stopped and all accounts cleaned up!")


if __name__ == "__main__":
    main()
