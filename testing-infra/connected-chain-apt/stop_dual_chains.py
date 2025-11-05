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

    # Check for running containers and list their IDs
    log("🔍 Checking for running containers...")
    result = run_command(
        'docker ps --filter "name=aptos-localnet-chain" --format "{{.ID}}|{{.Names}}|{{.Status}}"',
        check=False
    )
    
    if result.returncode == 0 and result.stdout.strip():
        log("📋 Found running containers:")
        for line in result.stdout.strip().split('\n'):
            if line.strip():
                parts = line.split('|')
                if len(parts) >= 2:
                    container_id = parts[0]
                    container_name = parts[1]
                    container_status = parts[2] if len(parts) > 2 else "unknown"
                    log(f"   - {container_name} (ID: {container_id[:12]}, Status: {container_status})")
    else:
        log("   No running containers found")

    log("")
    
    # Stop Chain 1
    log("🧹 Stopping Chain 1...")
    run_command(
        "docker-compose -f testing-infra/connected-chain-apt/docker-compose-chain1.yml "
        "-p aptos-chain1 down",
        check=False
    )

    # Stop Chain 2
    log("🧹 Stopping Chain 2...")
    run_command(
        "docker-compose -f testing-infra/connected-chain-apt/docker-compose-chain2.yml "
        "-p aptos-chain2 down",
        check=False
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
