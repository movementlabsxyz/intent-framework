#!/usr/bin/env python3
"""
Setup EVM chain and deploy IntentVault.

This script:
1. Sets up EVM Chain (Hardhat node)
2. Verifies EVM accounts are funded
3. Deploys IntentVault contract

Python equivalent of setup-and-deploy-evm.sh
"""

import sys
import os
import re
from pathlib import Path

# Add parent directory to path to import common
sys.path.insert(0, str(Path(__file__).parent.parent))
import common
from common import (
    setup_project_root, setup_logging, log, log_and_echo,
    run_command, display_balances, LOG_FILE
)


def get_evm_account_address(account_index: int) -> str:
    """Get EVM account address using Hardhat script."""
    evm_dir = common.PROJECT_ROOT / "evm-intent-framework"

    result = run_command(
        f"cd {evm_dir} && nix develop {common.PROJECT_ROOT} -c bash -c "
        f"'ACCOUNT_INDEX={account_index} npx hardhat run scripts/get-account-address.js --network localhost' 2>&1",
        check=False
    )

    # Extract Ethereum address
    for line in result.stdout.strip().split('\n'):
        match = re.match(r'^(0x[a-fA-F0-9]{40})$', line.strip())
        if match:
            return match.group(1)

    return ""


def get_evm_account_balance(account_index: int) -> tuple[str, str]:
    """
    Get EVM account balance.

    Returns:
        Tuple of (balance_in_wei, output_text)
    """
    evm_dir = common.PROJECT_ROOT / "evm-intent-framework"

    result = run_command(
        f"cd {evm_dir} && nix develop {common.PROJECT_ROOT} -c bash -c "
        f"'ACCOUNT_INDEX={account_index} npx hardhat run scripts/get-account-balance.js --network localhost' 2>&1",
        check=False
    )

    output = result.stdout + result.stderr

    # Check for errors
    if any(err in output.lower() for err in ["error", "cannot connect", "econnrefused"]):
        return "", output

    # Extract balance - look for a line that's purely numeric
    for line in output.strip().split('\n'):
        if line.strip().isdigit():
            return line.strip(), output

    return "", output


def main():
    """Setup EVM chain and deploy IntentVault."""
    # Setup project root and logging
    setup_project_root(Path(__file__))
    log_dir, log_file = setup_logging("setup-and-deploy-evm")

    log("🚀 EVM CHAIN - SETUP AND DEPLOY")
    log("===============================")
    log_and_echo(f"📝 All output logged to: {log_file}")

    log("")
    log("🔗 Setting up EVM Chain (Hardhat node)...")
    log(" =============================================")

    setup_script = common.PROJECT_ROOT / "testing-infra" / "connected-chain-evm" / "setup_evm_chain.py"
    # Use unbuffered Python to ensure output is visible
    result = run_command(f"python3 -u {setup_script}", check=False, capture_output=False)

    if result.returncode != 0:
        log_and_echo("❌ Failed to setup EVM chain")
        os._exit(1)

    log("")
    log("🔍 Verifying EVM accounts are funded...")
    log(" =============================================")

    # Wait for Hardhat node to be fully ready
    import time
    time.sleep(2)

    # Get Alice address (Account 1)
    log("   - Getting Alice address (Account 1)...")
    alice_address = get_evm_account_address(1)

    # Get Bob address (Account 2)
    log("   - Getting Bob address (Account 2)...")
    bob_address = get_evm_account_address(2)

    if not alice_address or not bob_address:
        log_and_echo("❌ ERROR: Failed to get EVM account addresses")
        log_and_echo(f"   Alice address: {alice_address or 'empty'}")
        log_and_echo(f"   Bob address: {bob_address or 'empty'}")
        log_and_echo("   EVM chain may not be properly initialized")
        os._exit(1)

    log(f"   ✅ Alice address: {alice_address}")
    log(f"   ✅ Bob address: {bob_address}")

    # Verify balances
    log("   - Getting Alice balance...")
    alice_balance, alice_output = get_evm_account_balance(1)

    if not alice_balance:
        log_and_echo("❌ ERROR: Failed to get Alice balance - Hardhat node may not be ready")
        log_and_echo(f"   Error output: {alice_output}")
        os._exit(1)

    log(f"   DEBUG: Alice balance extracted: '{alice_balance}'")

    log("   - Getting Bob balance...")
    bob_balance, bob_output = get_evm_account_balance(2)

    if not bob_balance:
        log_and_echo("❌ ERROR: Failed to get Bob balance - Hardhat node may not be ready")
        log_and_echo(f"   Error output: {bob_output}")
        os._exit(1)

    log(f"   DEBUG: Bob balance extracted: '{bob_balance}'")

    # Check if balances are zero
    if not alice_balance or alice_balance == "0":
        log_and_echo("❌ ERROR: Alice (Account 1) has ZERO or empty balance on EVM chain")
        log_and_echo(f"   Balance extracted: '{alice_balance}'")
        log_and_echo(f"   Balance output: {alice_output}")
        log_and_echo(f"   Address: {alice_address}")
        log_and_echo("   Hardhat default accounts should have 10000 ETH each")
        log_and_echo("   EVM chain may not be properly initialized")
        os._exit(1)

    if not bob_balance or bob_balance == "0":
        log_and_echo("❌ ERROR: Bob (Account 2) has ZERO or empty balance on EVM chain")
        log_and_echo(f"   Balance extracted: '{bob_balance}'")
        log_and_echo(f"   Balance output: {bob_output}")
        log_and_echo(f"   Address: {bob_address}")
        log_and_echo("   Hardhat default accounts should have 10000 ETH each")
        log_and_echo("   EVM chain may not be properly initialized")
        os._exit(1)

    # Check if balances are sufficient (at least 1 ETH)
    MIN_BALANCE = 1000000000000000000  # 1 ETH in wei

    alice_balance_int = int(alice_balance)
    bob_balance_int = int(bob_balance)

    if alice_balance_int < MIN_BALANCE:
        log_and_echo("❌ ERROR: Alice (Account 1) balance insufficient")
        log_and_echo(f"   Balance: {alice_balance} wei")
        log_and_echo(f"   Required: At least 1 ETH ({MIN_BALANCE} wei)")
        log_and_echo(f"   Address: {alice_address}")
        os._exit(1)

    if bob_balance_int < MIN_BALANCE:
        log_and_echo("❌ ERROR: Bob (Account 2) balance insufficient")
        log_and_echo(f"   Balance: {bob_balance} wei")
        log_and_echo(f"   Required: At least 1 ETH ({MIN_BALANCE} wei)")
        log_and_echo(f"   Address: {bob_address}")
        os._exit(1)

    log(f"   ✅ Alice (Account 1): {alice_address} - Balance verified")
    log(f"   ✅ Bob (Account 2):   {bob_address} - Balance verified")

    # Display EVM chain balances
    display_balances()

    log("")
    log("📦 Deploying IntentVault to EVM chain...")
    log(" =============================================")

    deploy_script = common.PROJECT_ROOT / "testing-infra" / "e2e-tests-evm" / "deploy_vault.py"
    # Use unbuffered Python to ensure output is visible
    result = run_command(f"python3 -u {deploy_script}", check=False, capture_output=False)

    if result.returncode != 0:
        log_and_echo("❌ Failed to deploy IntentVault")
        os._exit(1)

    # Extract vault address from deployment logs
    log_dir = common.PROJECT_ROOT / "tmp" / "intent-framework-logs"
    vault_address = ""

    if log_dir.exists():
        for log_file_path in sorted(log_dir.glob("deploy-vault*.log"), reverse=True):
            try:
                with open(log_file_path, 'r') as f:
                    content = f.read()
                    # Try multiple patterns to find the vault address
                    patterns = [
                        r"IntentVault deployed to\s+(0x[a-fA-F0-9]{40})",
                        r"Contract Address:\s+(0x[a-fA-F0-9]{40})",
                        r"✅ IntentVault deployed successfully!.*?Contract Address:\s+(0x[a-fA-F0-9]{40})",
                    ]
                    for pattern in patterns:
                        match = re.search(pattern, content, re.IGNORECASE | re.DOTALL)
                        if match:
                            vault_address = match.group(1)
                            break
                    if vault_address:
                        break
            except:
                pass

    if not vault_address:
        log_and_echo("❌ ERROR: Could not extract vault address from deployment logs")
        log_and_echo("   This is required for verifier configuration")
        log_and_echo(f"   Check deployment logs in: {log_dir}")
        log_and_echo("   Deployment may have failed - check deploy-vault logs for errors")
        os._exit(1)
    else:
        log(f"   ✅ IntentVault deployed at: {vault_address}")

    # Get verifier address (computed from verifier's ECDSA public key)
    # Match deploy-vault.sh logic exactly
    log("   - Computing verifier Ethereum address from config...")
    verifier_dir = common.PROJECT_ROOT / "trusted-verifier"
    config_path = common.PROJECT_ROOT / "trusted-verifier" / "config" / "verifier_testing.toml"
    
    env = os.environ.copy()
    env["VERIFIER_CONFIG_PATH"] = str(config_path)
    
    # Run command and capture both stdout and stderr (like shell script does with 2>&1)
    # Shell script doesn't check return code, just greps the output
    verifier_result = run_command(
        f"cd {verifier_dir} && cargo run --bin get_verifier_eth_address",
        check=False,
        env=env
    )
    
    # Extract Ethereum address from both stdout and stderr (shell script uses 2>&1 then greps)
    # Pattern matches: grep -E '^0x[a-fA-F0-9]{40}$' | head -1 | tr -d '\n'
    # Shell script doesn't check return code, just extracts from output
    verifier_address = ""
    output = verifier_result.stdout + verifier_result.stderr
    for line in output.strip().split('\n'):
        match = re.match(r'^(0x[a-fA-F0-9]{40})$', line.strip())
        if match:
            verifier_address = match.group(1)
            break  # head -1 equivalent: take first match
    
    if not verifier_address:
        log_and_echo("❌ ERROR: Could not compute verifier Ethereum address from config")
        log_and_echo("   The verifier address is required for proper logging")
        log_and_echo("   Check that trusted-verifier/config/verifier_testing.toml exists and has valid keys")
        log_and_echo("   Run: cargo run --bin get_verifier_eth_address in trusted-verifier directory")
        os._exit(1)
    else:
        log(f"   ✅ Verifier address: {verifier_address}")

    log_and_echo("✅ EVM contracts deployed")

    log("")
    log("🎉 EVM DEPLOYMENT COMPLETE!")
    log("===========================")
    log("EVM Chain:")
    log("   RPC URL:  http://127.0.0.1:8545")
    log("   Chain ID: 31337")
    log(f"   Vault:    {vault_address}")
    log(f"   Verifier: {verifier_address}")
    log("")
    log("📡 API Examples:")
    log("   Check EVM Chain:    curl -X POST http://127.0.0.1:8545 -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'")
    log("")
    log("📋 Useful commands:")
    log(f"   Stop EVM chain:  python3 {common.PROJECT_ROOT}/testing-infra/connected-chain-evm/stop_evm_chain.py")

    log("")
    log("✨ EVM setup and deployment script completed!")


if __name__ == "__main__":
    main()
