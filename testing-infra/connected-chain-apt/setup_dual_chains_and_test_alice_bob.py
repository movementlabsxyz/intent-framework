#!/usr/bin/env python3
"""
Setup dual chains and test Alice/Bob accounts.

This script:
1. Sets up dual Docker Aptos localnets
2. Creates and funds Alice and Bob accounts on both chains
3. Tests transfers between Alice and Bob on both chains

Python equivalent of setup-dual-chains-and-test-alice-bob.sh
"""

import sys
import os
import time
import subprocess
from pathlib import Path

# Add parent directory to path to import common
sys.path.insert(0, str(Path(__file__).parent.parent))
import common
from common import (
    setup_project_root, setup_logging, log, log_and_echo,
    run_command, fund_and_verify_aptos_account, display_balances,
    get_aptos_address, LOG_FILE
)


def verify_chain_running(port: int, chain_name: str) -> bool:
    """Verify an Aptos chain is running."""
    try:
        import requests
        response = requests.get(f"http://127.0.0.1:{port}/v1", timeout=5)
        return response.status_code == 200
    except Exception as e:
        log(f"   verify_chain_running error: {e}")
        return False


def verify_faucet_running(port: int, chain_name: str) -> bool:
    """Verify a faucet is running."""
    try:
        import requests
        response = requests.get(f"http://127.0.0.1:{port}/", timeout=5)
        return response.text.strip() == "tap:ok"
    except:
        return False


def main():
    """Setup dual chains and test Alice/Bob accounts."""
    # Setup project root and logging
    setup_project_root(Path(__file__))
    log_dir, log_file = setup_logging("setup-dual-chains")

    # Expected funding amount in octas
    EXPECTED_FUNDING_AMOUNT = 200000000

    log("🧪 Alice and Bob Account Testing - DUAL CHAINS")
    log("==============================================")
    log_and_echo(f"📝 All output logged to: {log_file}")

    log("")
    log("% - - - - - - - - - - - SETUP - - - - - - - - - - - -")
    log("% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -")

    # Stop any existing Docker containers
    log("🧹 Stopping any existing Docker containers...")
    run_command(
        f"docker-compose -f {common.PROJECT_ROOT}/testing-infra/connected-chain-apt/docker-compose-chain1.yml down",
        check=False
    )
    run_command(
        f"docker-compose -f {common.PROJECT_ROOT}/testing-infra/connected-chain-apt/docker-compose-chain2.yml down",
        check=False
    )

    # Start fresh Docker localnets
    log("🚀 Starting fresh Docker Aptos localnets (dual chains)...")
    setup_script = common.PROJECT_ROOT / "testing-infra" / "connected-chain-apt" / "setup_dual_chains.py"
    # Use unbuffered Python to ensure output is visible
    result = run_command(f"python3 -u {setup_script}", check=False, capture_output=False)

    if result.returncode != 0:
        log_and_echo("❌ Failed to setup dual chains")
        os._exit(1)

    # Wait for services to be fully ready
    log("⏳ Waiting for services to be fully ready...")
    time.sleep(15)

    # Verify Chain 1 is running
    log("🔍 Verifying Chain 1 is running...")
    if not verify_chain_running(8080, "Chain 1"):
        log_and_echo("❌ Error: Chain 1 failed to start on port 8080")
        os._exit(1)
    log("✅ Chain 1 is running")

    # Verify Chain 2 is running
    log("🔍 Verifying Chain 2 is running...")
    if not verify_chain_running(8082, "Chain 2"):
        log_and_echo("❌ Error: Chain 2 failed to start on port 8082")
        os._exit(1)
    log("✅ Chain 2 is running")

    # Verify faucets are running
    log("🔍 Verifying faucets are running...")
    if verify_faucet_running(8081, "Chain 1"):
        log("✅ Chain 1 faucet is running")
    else:
        log_and_echo("❌ Error: Chain 1 faucet failed to start on port 8081")
        os._exit(1)

    if verify_faucet_running(8083, "Chain 2"):
        log("✅ Chain 2 faucet is running")
    else:
        log_and_echo("❌ Error: Chain 2 faucet failed to start on port 8083")
        os._exit(1)

    log_and_echo("✅ Docker chains setup")

    # Show chain status
    log("")
    log("📊 Chain Status:")
    try:
        import requests
        chain1_info = requests.get("http://127.0.0.1:8080/v1", timeout=5)
        if chain1_info.status_code == 200:
            chain1_data = chain1_info.json()
            chain1_id = chain1_data.get("chain_id", "unknown")
            chain1_height = chain1_data.get("block_height", "unknown")
            chain1_role = chain1_data.get("node_role", "unknown")
            log(f"   Chain 1: ID={chain1_id}, Height={chain1_height}, Role={chain1_role}")

        chain2_info = requests.get("http://127.0.0.1:8082/v1", timeout=5)
        if chain2_info.status_code == 200:
            chain2_data = chain2_info.json()
            chain2_id = chain2_data.get("chain_id", "unknown")
            chain2_height = chain2_data.get("block_height", "unknown")
            chain2_role = chain2_data.get("node_role", "unknown")
            log(f"   Chain 2: ID={chain2_id}, Height={chain2_height}, Role={chain2_role}")
    except Exception as e:
        log(f"   Could not get chain status: {e}")

    # Clean up any existing profiles
    log("")
    log("🧹 Cleaning up existing CLI profiles...")
    run_command("aptos config delete-profile --profile alice-chain1", check=False)
    run_command("aptos config delete-profile --profile bob-chain1", check=False)
    run_command("aptos config delete-profile --profile alice-chain2", check=False)
    run_command("aptos config delete-profile --profile bob-chain2", check=False)

    # Create test accounts for Chain 1
    log("")
    log("👥 Creating test accounts for Chain 1...")

    log("Creating alice-chain1 account for Chain 1...")
    result = subprocess.run(
        "aptos init --profile alice-chain1 --network local --assume-yes",
        shell=True,
        input="\n",
        capture_output=True,
        text=True
    )
    if LOG_FILE:
        with open(LOG_FILE, 'a') as f:
            f.write("=== Alice-chain1 init output ===\n")
            if result.stdout:
                f.write(result.stdout + "\n")
            if result.stderr:
                f.write("STDERR:\n" + result.stderr + "\n")

    if result.returncode == 0:
        log("✅ Alice-chain1 account created successfully on Chain 1")
    else:
        log_and_echo("❌ Failed to create Alice-chain1 account on Chain 1")
        if result.stderr:
            log_and_echo(f"Error: {result.stderr}")
        os._exit(1)

    log("Creating bob-chain1 account for Chain 1...")
    result = subprocess.run(
        "aptos init --profile bob-chain1 --network local --assume-yes",
        shell=True,
        input="\n",
        capture_output=True,
        text=True
    )
    if LOG_FILE:
        with open(LOG_FILE, 'a') as f:
            f.write("=== Bob-chain1 init output ===\n")
            if result.stdout:
                f.write(result.stdout + "\n")
            if result.stderr:
                f.write("STDERR:\n" + result.stderr + "\n")

    if result.returncode == 0:
        log("✅ Bob-chain1 account created successfully on Chain 1")
    else:
        log_and_echo("❌ Failed to create Bob-chain1 account on Chain 1")
        if result.stderr:
            log_and_echo(f"Error: {result.stderr}")
        os._exit(1)

    # Create test accounts for Chain 2
    log("")
    log("👥 Creating test accounts for Chain 2...")

    log("Creating alice-chain2 account for Chain 2...")
    result = subprocess.run(
        "aptos init --profile alice-chain2 --network custom "
        "--rest-url http://127.0.0.1:8082 --faucet-url http://127.0.0.1:8083 --assume-yes",
        shell=True,
        input="\n",
        capture_output=True,
        text=True
    )
    if LOG_FILE:
        with open(LOG_FILE, 'a') as f:
            f.write("=== Alice-chain2 init output ===\n")
            if result.stdout:
                f.write(result.stdout + "\n")
            if result.stderr:
                f.write("STDERR:\n" + result.stderr + "\n")

    if result.returncode == 0:
        log("✅ Alice-chain2 account created successfully on Chain 2")
    else:
        log_and_echo("❌ Failed to create Alice-chain2 account on Chain 2")
        if result.stderr:
            log_and_echo(f"Error: {result.stderr}")
        os._exit(1)

    log("Creating bob-chain2 account for Chain 2...")
    result = subprocess.run(
        "aptos init --profile bob-chain2 --network custom "
        "--rest-url http://127.0.0.1:8082 --faucet-url http://127.0.0.1:8083 --assume-yes",
        shell=True,
        input="\n",
        capture_output=True,
        text=True
    )
    if LOG_FILE:
        with open(LOG_FILE, 'a') as f:
            f.write("=== Bob-chain2 init output ===\n")
            if result.stdout:
                f.write(result.stdout + "\n")
            if result.stderr:
                f.write("STDERR:\n" + result.stderr + "\n")

    if result.returncode == 0:
        log("✅ Bob-chain2 account created successfully on Chain 2")
    else:
        log_and_echo("❌ Failed to create Bob-chain2 account on Chain 2")
        if result.stderr:
            log_and_echo(f"Error: {result.stderr}")
        os._exit(1)

    log("")
    log("% - - - - - - - - - - - FUNDING - - - - - - - - - - - -")
    log("% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -")

    # Fund all accounts
    fund_and_verify_aptos_account("alice-chain1", 1, "Alice Chain 1", EXPECTED_FUNDING_AMOUNT)
    fund_and_verify_aptos_account("bob-chain1", 1, "Bob Chain 1", EXPECTED_FUNDING_AMOUNT)
    fund_and_verify_aptos_account("alice-chain2", 2, "Alice Chain 2", EXPECTED_FUNDING_AMOUNT)
    fund_and_verify_aptos_account("bob-chain2", 2, "Bob Chain 2", EXPECTED_FUNDING_AMOUNT)

    log_and_echo("✅ Accounts funded")

    # Display initial balances
    display_balances()

    # Get addresses for summary
    alice_address = get_aptos_address("alice-chain1") or "unknown"
    bob_address = get_aptos_address("bob-chain1") or "unknown"
    alice2_address = get_aptos_address("alice-chain2") or "unknown"
    bob2_address = get_aptos_address("bob-chain2") or "unknown"

    log("")
    log("% - - - - - - - - - - - SUMMARY - - - - - - - - - - - -")
    log("% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -")

    log("")
    log("🎉 DUAL-CHAIN ALICE AND BOB SETUP COMPLETE!")
    log("============================================")
    log("")
    log("📋 Account Information:")
    log("Chain 1 (port 8080):")
    log(f"   Alice: {alice_address}")
    log(f"   Bob:   {bob_address}")
    log("")
    log("Chain 2 (port 8082):")
    log(f"   Alice: {alice2_address}")
    log(f"   Bob:   {bob2_address}")
    log("")
    log("🔗 Chain Endpoints:")
    log("   Chain 1 REST API: http://127.0.0.1:8080/v1")
    log("   Chain 1 Faucet:   http://127.0.0.1:8081")
    log("   Chain 2 REST API: http://127.0.0.1:8082/v1")
    log("   Chain 2 Faucet:   http://127.0.0.1:8083")
    log("")
    log("📡 API Examples:")
    log("   Check Chain 1 status:    curl -s http://127.0.0.1:8080/v1 | jq '.chain_id, .block_height'")
    log("   Check Chain 2 status:    curl -s http://127.0.0.1:8082/v1 | jq '.chain_id, .block_height'")
    log(f"   Get Alice Chain 1:       curl -s http://127.0.0.1:8080/v1/accounts/{alice_address}")
    log(f"   Get Alice Chain 2:       curl -s http://127.0.0.1:8082/v1/accounts/{alice2_address}")
    log('   Fund Chain 1 account:    curl -X POST "http://127.0.0.1:8081/mint?address=<ADDRESS>&amount=100000000"')
    log('   Fund Chain 2 account:    curl -X POST "http://127.0.0.1:8083/mint?address=<ADDRESS>&amount=100000000"')
    log("")
    log("📋 Useful Commands:")
    log(f"   Stop chains:     python3 {common.PROJECT_ROOT}/testing-infra/connected-chain-apt/stop_dual_chains.py")
    log("   View profiles:   aptos config show-profiles")
    log("   Test Chain 1:    aptos account balance --profile alice-chain1")
    log("   Test Chain 2:    aptos account balance --profile alice-chain2")
    log("")
    log("✨ Ready for cross-chain testing!")


if __name__ == "__main__":
    main()
