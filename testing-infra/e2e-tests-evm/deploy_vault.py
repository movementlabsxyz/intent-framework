#!/usr/bin/env python3
"""
Deploy IntentVault contract to EVM chain.

This script deploys the IntentVault smart contract to a running Hardhat node.
Python equivalent of deploy-vault.sh
"""

import sys
import re
import os
from pathlib import Path

# Add parent directory to path to import common
sys.path.insert(0, str(Path(__file__).parent.parent))
import common
from common import (
    setup_project_root, setup_logging, log, log_and_echo,
    run_command, LOG_FILE
)


def is_hardhat_running() -> bool:
    """
    Check if Hardhat node is running on port 8545.

    Returns:
        True if Hardhat is running, False otherwise
    """
    try:
        import requests
        response = requests.post(
            "http://127.0.0.1:8545",
            json={"jsonrpc": "2.0", "method": "eth_blockNumber", "params": [], "id": 1},
            timeout=2
        )
        return response.status_code == 200
    except:
        return False


def get_verifier_eth_address() -> str:
    """
    Get verifier Ethereum address from config.

    Returns:
        Ethereum address (0x...) or empty string if not found
    """
    log("   Computing verifier Ethereum address from config...")

    verifier_dir = common.PROJECT_ROOT / "trusted-verifier"
    config_path = common.PROJECT_ROOT / "trusted-verifier" / "config" / "verifier_testing.toml"

    # Check if config file exists
    if not config_path.exists():
        log_and_echo(f"❌ ERROR: verifier_testing.toml not found at {config_path}")
        log_and_echo("   The verifier config file is required for deployment")
        return ""

    env = os.environ.copy()
    env["VERIFIER_CONFIG_PATH"] = str(config_path)

    result = run_command(
        f"cd {verifier_dir} && cargo run --bin get_verifier_eth_address",
        check=False
    )

    if result.returncode != 0:
        log_and_echo("❌ ERROR: Failed to compute verifier Ethereum address from config")
        log_and_echo(f"   Command exit code: {result.returncode}")
        log_and_echo("   Command output:")
        output = result.stdout + result.stderr
        for line in output.strip().split('\n'):
            log_and_echo(f"      {line}")
        log_and_echo("   Check that trusted-verifier/config/verifier_testing.toml has valid keys")
        log_and_echo("   The [verifier] section must contain valid private_key and public_key (base64 encoded)")
        return ""

    # Extract Ethereum address (0x followed by 40 hex chars)
    output = result.stdout + result.stderr
    for line in output.strip().split('\n'):
        match = re.match(r'^(0x[a-fA-F0-9]{40})$', line.strip())
        if match:
            return match.group(1)
    
    # If we get here, no address was found in output
    log_and_echo("❌ ERROR: Could not extract verifier Ethereum address from output")
    log_and_echo("   Command output:")
    for line in output.strip().split('\n'):
        log_and_echo(f"      {line}")
    log_and_echo("   Expected format: 0x followed by 40 hex characters")
    return ""


def deploy_vault_contract(verifier_address: str = "") -> str:
    """
    Deploy IntentVault contract.

    Args:
        verifier_address: Optional verifier Ethereum address

    Returns:
        Deployed contract address

    Raises:
        SystemExit: If deployment fails
    """
    log("")
    log("📤 Deploying IntentVault...")

    evm_dir = common.PROJECT_ROOT / "evm-intent-framework"

    if verifier_address:
        # Use computed verifier address
        env_cmd = f"VERIFIER_ADDRESS='{verifier_address}' "
    else:
        # Use Hardhat account 1 (fallback)
        env_cmd = ""

    # Run deployment in nix develop
    cmd = (
        f"cd {evm_dir} && "
        f"nix develop {common.PROJECT_ROOT} -c bash -c \""
        f"{env_cmd}npx hardhat run scripts/deploy.js --network localhost"
        f"\""
    )

    result = run_command(cmd, check=False)
    deploy_output = result.stdout + result.stderr

    # Log deployment output
    log("")
    log("📋 Raw Hardhat deployment output:")
    log("=" * 50)
    if deploy_output:
        log(deploy_output)
    else:
        log("   (No output captured)")
    log("=" * 50)
    log("")
    
    if LOG_FILE:
        with open(LOG_FILE, 'a') as f:
            f.write("\n📋 Raw Hardhat deployment output:\n")
            f.write("=" * 50 + "\n")
            f.write(deploy_output + "\n")
            f.write("=" * 50 + "\n\n")

    # Extract contract address from output - must match exact pattern
    # Pattern: "IntentVault deployed to: 0x..." or "IntentVault deployed to 0x..."
    match = re.search(r"IntentVault deployed to:?\s+(0x[a-fA-F0-9]{40})", deploy_output, re.IGNORECASE)
    if not match:
        log_and_echo("❌ Failed to extract contract address from deployment")
        log_and_echo("   Expected pattern: 'IntentVault deployed to: 0x...' or 'IntentVault deployed to 0x...'")
        log_and_echo("   Deployment output:")
        print(deploy_output)
        os._exit(1)
    
    return match.group(1)


def main():
    """Deploy IntentVault contract."""
    # Setup project root and logging
    setup_project_root(Path(__file__))
    log_dir, log_file = setup_logging("deploy-vault")

    log("📦 Deploying IntentVault Contract")
    log("==================================")
    log_and_echo(f"📝 All output logged to: {log_file}")

    # Check if Hardhat node is running
    if not is_hardhat_running():
        log_and_echo("❌ Hardhat node is not running. Please run testing-infra/connected-chain-evm/setup-evm-chain.sh first")
        os._exit(1)

    log("")
    log("🔑 Configuration:")

    # Get verifier Ethereum address - REQUIRED, fail if not found
    verifier_eth_address = get_verifier_eth_address()

    if not verifier_eth_address:
        # get_verifier_eth_address() already printed detailed error messages
        log_and_echo("❌ ERROR: Could not compute verifier Ethereum address from config")
        log_and_echo("   Deployment cannot proceed without a valid verifier address")
        os._exit(1)

    log(f"   ✅ Verifier Ethereum address: {verifier_eth_address}")
    log("   RPC URL: http://127.0.0.1:8545")

    # Deploy contract
    vault_address = deploy_vault_contract(verifier_eth_address)

    log("")
    log("✅ IntentVault deployed successfully!")
    log(f"   Contract Address: {vault_address}")
    log("")
    log("📋 Contract Details:")
    log("   Network:      localhost")
    log("   RPC URL:      http://127.0.0.1:8545")
    log("   Chain ID:     31337 (Hardhat default)")
    log("")
    log("🔍 Verify deployment:")
    log(f"   npx hardhat verify --network localhost {vault_address} <verifier_address>")


if __name__ == "__main__":
    main()
