#!/usr/bin/env python3
"""
Setup dual Aptos chains and deploy intent contracts.

This script:
1. Sets up dual Docker chains with Alice and Bob accounts
2. Configures Aptos CLI for both chains
3. Deploys contracts to both chains

Python equivalent of setup-and-deploy.sh
"""

import sys
import json
from pathlib import Path

# Add parent directory to path to import common
sys.path.insert(0, str(Path(__file__).parent.parent))
from common import (
    setup_project_root, setup_logging, log, log_and_echo,
    run_command, get_aptos_address, PROJECT_ROOT, LOG_FILE
)


def deploy_contract(profile: str, chain_address: str, chain_name: str) -> bool:
    """
    Deploy Move contract to an Aptos chain.

    Args:
        profile: Aptos CLI profile name
        chain_address: Deployer address
        chain_name: Chain name for logging

    Returns:
        True if successful, False otherwise
    """
    log(f"📦 Deploying contracts to {chain_name}...")
    log(f"   - Getting account address for {chain_name}...")
    log(f"   - Deploying to {chain_name} with address: {chain_address}")

    move_dir = PROJECT_ROOT / "move-intent-framework"

    result = run_command(
        f"cd {move_dir} && "
        f"aptos move publish --dev --profile {profile} "
        f"--named-addresses aptos_intent={chain_address} --assume-yes",
        check=False
    )

    # Append output to log
    if LOG_FILE:
        with open(LOG_FILE, 'a') as f:
            f.write(result.stdout + "\n")
            f.write(result.stderr + "\n")

    if result.returncode == 0:
        log(f"   ✅ {chain_name} deployment successful!")
        return True
    else:
        log_and_echo(f"   ❌ {chain_name} deployment failed!")
        log_and_echo(f"   See log file for details: {LOG_FILE}")
        return False


def main():
    """Setup and deploy Aptos intent framework."""
    # Setup project root and logging
    setup_project_root(Path(__file__))
    log_dir, log_file = setup_logging("setup-and-deploy")

    log("🚀 APTOS INTENT FRAMEWORK - SETUP AND DEPLOY")
    log("=============================================")
    log_and_echo(f"📝 All output logged to: {log_file}")

    log("")
    log("🔗 Step 1: Setting up dual Docker chains with Alice and Bob accounts...")
    log(" =============================================")

    # TODO: Replace with Python version when task 4.4 is complete
    # For now, call the shell script
    setup_script = PROJECT_ROOT / "testing-infra" / "connected-chain-apt" / "setup-dual-chains-and-test-alice-bob.sh"
    result = run_command(f"{setup_script}", check=False)

    if result.returncode != 0:
        log_and_echo("❌ Failed to setup dual chains with Alice and Bob accounts")
        sys.exit(1)

    log("")
    log("⚙️  Step 2: Configuring Aptos CLI for both chains...")
    log(" =============================================")

    # Clean up any existing profiles
    log("🧹 Cleaning up existing CLI profiles...")
    run_command("aptos config delete-profile --profile intent-account-chain1", check=False)
    run_command("aptos config delete-profile --profile intent-account-chain2", check=False)

    # Configure Chain 1 (port 8080)
    log("   - Configuring Chain 1 (port 8080)...")
    result = run_command(
        "printf '\\n' | aptos init --profile intent-account-chain1 --network local --assume-yes",
        check=False
    )
    if LOG_FILE:
        with open(LOG_FILE, 'a') as f:
            f.write(result.stdout + "\n")

    # Configure Chain 2 (port 8082)
    log("   - Configuring Chain 2 (port 8082)...")
    result = run_command(
        "printf '\\n' | aptos init --profile intent-account-chain2 --network custom "
        "--rest-url http://127.0.0.1:8082 --faucet-url http://127.0.0.1:8083 --assume-yes",
        check=False
    )
    if LOG_FILE:
        with open(LOG_FILE, 'a') as f:
            f.write(result.stdout + "\n")

    # Get Chain 1 address
    log("")
    log("📦 Step 3: Deploying contracts to Chain 1...")
    chain1_address = get_aptos_address("intent-account-chain1")
    if not chain1_address:
        log_and_echo("❌ Failed to get Chain 1 address")
        sys.exit(1)

    if not deploy_contract("intent-account-chain1", chain1_address, "Chain 1"):
        sys.exit(1)

    # Get Chain 2 address
    log("")
    log("📦 Step 4: Deploying contracts to Chain 2...")
    chain2_address = get_aptos_address("intent-account-chain2")
    if not chain2_address:
        log_and_echo("❌ Failed to get Chain 2 address")
        sys.exit(1)

    if not deploy_contract("intent-account-chain2", chain2_address, "Chain 2"):
        sys.exit(1)

    log_and_echo("✅ Contracts deployed")

    log("")
    log("🎉 DEPLOYMENT COMPLETE!")
    log("=======================")
    log("Chain 1 (intent-account-chain1):")
    log("   REST API: http://127.0.0.1:8080/v1")
    log("   Faucet:   http://127.0.0.1:8081")
    log(f"   Account:  {chain1_address}")
    log(f"   Contract: 0x{chain1_address}::aptos_intent")
    log("")
    log("Chain 2 (intent-account-chain2):")
    log("   REST API: http://127.0.0.1:8082/v1")
    log("   Faucet:   http://127.0.0.1:8083")
    log(f"   Account:  {chain2_address}")
    log(f"   Contract: 0x{chain2_address}::aptos_intent")
    log("")
    log("📝 NOTE: The 'Account' is the deployer address, 'Contract' is the actual contract address")
    log("   Use the Contract address to call contract functions!")
    log("")
    log("📡 API Examples:")
    log("   Check Chain 1 status:    curl -s http://127.0.0.1:8080/v1 | jq '.chain_id, .block_height'")
    log("   Check Chain 2 status:    curl -s http://127.0.0.1:8082/v1 | jq '.chain_id, .block_height'")
    log(f"   Get Chain 1 account:     curl -s http://127.0.0.1:8080/v1/accounts/{chain1_address}")
    log(f"   Get Chain 2 account:     curl -s http://127.0.0.1:8082/v1/accounts/{chain2_address}")
    log('   Fund Chain 1 account:   curl -X POST "http://127.0.0.1:8081/mint?address=<ADDRESS>&amount=100000000"')
    log('   Fund Chain 2 account:   curl -X POST "http://127.0.0.1:8083/mint?address=<ADDRESS>&amount=100000000"')
    log("")
    log("📋 Useful commands:")
    log(f"   Stop chains:     python3 {PROJECT_ROOT}/testing-infra/connected-chain-apt/stop_dual_chains.py")
    log("   View Chain 1:    aptos config show-profiles --profile intent-account-chain1")
    log("   View Chain 2:    aptos config show-profiles --profile intent-account-chain2")

    log("")
    log("✨ Setup and deployment script completed!")


if __name__ == "__main__":
    main()
