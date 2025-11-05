#!/usr/bin/env python3
"""
Release EVM escrow by monitoring verifier approvals.

This script:
1. Polls verifier for escrow approvals
2. Releases approved escrows by calling claim on IntentVault
3. Verifies funds were received

Python equivalent of release-evm-escrow.sh
"""

import sys
import os
import json
import time
import re
import base64
from pathlib import Path

# Add parent directory to path to import common
sys.path.insert(0, str(Path(__file__).parent.parent))
import common
from common import (
    setup_project_root, setup_logging, log, log_and_echo,
    run_command, LOG_FILE
)
from config import TestConfig, print_config_content


def is_verifier_running() -> bool:
    """Check if verifier is running."""
    try:
        import requests
        response = requests.get("http://127.0.0.1:3333/health", timeout=2)
        return response.status_code == 200
    except:
        return False


def get_bob_balance() -> tuple[str, str]:
    """Get Bob's EVM balance. Returns (balance_wei, output)."""
    evm_dir = common.PROJECT_ROOT / "evm-intent-framework"

    result = run_command(
        f"nix develop {common.PROJECT_ROOT} -c bash -c "
        f"\"cd '{evm_dir}' && ACCOUNT_INDEX=2 npx hardhat run scripts/get-account-balance.js --network localhost\" 2>&1",
        check=False
    )

    output = result.stdout + result.stderr

    # Extract balance
    for line in output.strip().split('\n'):
        if line.strip().isdigit():
            return line.strip(), output

    return "", output


def check_and_release_escrows(vault_address: str, released_escrows: set) -> set:
    """
    Check for new approvals and release escrows.

    Args:
        vault_address: IntentVault address
        released_escrows: Set of already released escrow IDs

    Returns:
        Updated set of released escrow IDs
    """
    try:
        import requests
        response = requests.get("http://127.0.0.1:3333/approvals", timeout=5)
        approvals_data = response.json()

        if not approvals_data.get("success"):
            return released_escrows

        approvals = approvals_data.get("data", [])

        for approval in approvals:
            escrow_id = approval.get("escrow_id")
            intent_id = approval.get("intent_id")
            approval_value = approval.get("approval_value")
            signature_base64 = approval.get("signature")

            # Skip if invalid or already released
            if not escrow_id or approval_value != 1 or escrow_id in released_escrows:
                continue

            log("")
            log(f"   📦 New approval found for escrow: {escrow_id}")
            log("   🔓 Releasing escrow on EVM chain...")

            # Convert intent_id to EVM format
            intent_id_hex = intent_id.replace("0x", "")
            intent_id_hex = intent_id_hex.zfill(64)
            intent_id_evm = f"0x{intent_id_hex}"

            # Convert signature from base64 to hex
            try:
                signature_bytes = base64.b64decode(signature_base64)
                signature_hex = signature_bytes.hex()
            except:
                log("   ❌ Failed to decode signature")
                continue

            if len(signature_hex) != 130:
                log(f"   ❌ Invalid signature length: expected 130 hex chars, got {len(signature_hex)}")
                continue

            # Get Bob's balance before claim
            log("   - Getting Bob's balance before claim...")
            bob_balance_before, bob_output_before = get_bob_balance()

            if not bob_balance_before:
                log_and_echo("   ❌ ERROR: Failed to get Bob's balance before claim")
                log_and_echo(f"   Balance output: {bob_output_before}")
                os._exit(1)

            log(f"   - Bob's balance before claim: {bob_balance_before} wei")

            # Submit escrow release transaction
            evm_dir = common.PROJECT_ROOT / "evm-intent-framework"

            log("   - Calling IntentVault.claim() on EVM...")
            result = run_command(
                f"nix develop {common.PROJECT_ROOT} -c bash -c "
                f"\"cd '{evm_dir}' && VAULT_ADDRESS='{vault_address}' INTENT_ID_EVM='{intent_id_evm}' "
                f"SIGNATURE_HEX='{signature_hex}' npx hardhat run scripts/claim-escrow.js --network localhost\" 2>&1",
                check=False
            )

            claim_output = result.stdout + result.stderr

            # Log claim output
            if LOG_FILE:
                with open(LOG_FILE, 'a') as f:
                    f.write(claim_output + "\n")

            if result.returncode != 0:
                log_and_echo("   ❌ ERROR: Failed to release escrow on EVM chain")
                log_and_echo(f"   Claim output: {claim_output}")
                log_and_echo(f"   See log file for details: {LOG_FILE}")
                os._exit(1)

            # Verify claim succeeded
            if "escrow released successfully" not in claim_output.lower():
                log_and_echo("   ❌ ERROR: Escrow claim did not complete successfully")
                log_and_echo(f"   Claim output: {claim_output}")
                log_and_echo("   Expected to see 'Escrow released successfully' in output")
                os._exit(1)

            # Wait for transaction to be processed
            time.sleep(2)

            # Get Bob's balance after claim
            log("   - Getting Bob's balance after claim...")
            bob_balance_after, bob_output_after = get_bob_balance()

            if not bob_balance_after:
                log_and_echo("   ❌ ERROR: Failed to get Bob's balance after claim")
                log_and_echo(f"   Balance output: {bob_output_after}")
                os._exit(1)

            log(f"   - Bob's balance after claim: {bob_balance_after} wei")

            # Calculate balance increase
            expected_amount_wei = 1000000000000000000000  # 1000 ETH
            balance_increase = int(bob_balance_after) - int(bob_balance_before)

            log(f"   - Balance increase: {balance_increase} wei")
            log(f"   - Expected: ~{expected_amount_wei} wei (1000 ETH minus gas)")

            # Check if balance increased by at least 99% of expected
            min_expected = int(expected_amount_wei * 0.99)

            if balance_increase < min_expected or balance_increase == 0:
                log_and_echo("   ❌ ERROR: Bob did not receive the escrow funds!")
                log_and_echo(f"   Bob's balance before: {bob_balance_before} wei")
                log_and_echo(f"   Bob's balance after:  {bob_balance_after} wei")
                log_and_echo(f"   Balance increase:    {balance_increase} wei")
                log_and_echo(f"   Expected increase:   ~{expected_amount_wei} wei (1000 ETH)")
                log_and_echo(f"   Minimum expected:     {min_expected} wei (99% of 1000 ETH)")
                log_and_echo("   Escrow release FAILED - Bob did not receive funds!")
                os._exit(1)

            log("   ✅ Escrow released successfully on EVM chain!")
            log(f"   ✅ Bob received {balance_increase} wei (expected ~{expected_amount_wei} wei)")
            released_escrows.add(escrow_id)

    except Exception as e:
        # Non-fatal error, continue polling
        # Note: os._exit(1) bypasses all exception handlers, so it won't be caught here
        log(f"   ⚠️  Error checking approvals: {e}")

    return released_escrows


def main():
    """Monitor and release EVM escrows."""
    import argparse
    
    parser = argparse.ArgumentParser(description="Release EVM escrows")
    parser.add_argument('--config-file', type=Path, required=True,
                       help='Path to test config file (pickle format)')
    args = parser.parse_args()

    # Setup project root and logging
    setup_project_root(Path(__file__))
    log_dir, log_file = setup_logging("release-evm-escrow")

    log("🔓 EVM ESCROW RELEASE")
    log("=====================")
    log_and_echo(f"📝 All output logged to: {log_file}")

    # Check if verifier is running
    if not is_verifier_running():
        log_and_echo("❌ Verifier is not running. Please start it first:")
        log_and_echo("   python3 testing-infra/e2e-tests-apt/run_cross_chain_verifier.py")
        os._exit(1)

    # Load config - required
    if not args.config_file.exists():
        log_and_echo(f"❌ Config file not found: {args.config_file}")
        log_and_echo("   The config file must be created by run_tests.py first")
        os._exit(1)
    
    config = TestConfig.load(args.config_file)
    log(f"   Loaded config from: {args.config_file}")
    
    # Print config content for debugging
    print_config_content(config, log_and_echo)
    
    vault_address = config.vault_address
    if not vault_address:
        log_and_echo("❌ Vault address not found in config")
        log_and_echo("   The config must be populated with vault_address")
        os._exit(1)

    log(f"   Vault address: {vault_address}")
    log_and_echo(f"   Vault address: {vault_address}")
    
    # Verify vault contract exists on chain using direct RPC call
    rpc_payload = {
        "jsonrpc": "2.0",
        "method": "eth_getCode",
        "params": [vault_address, "latest"],
        "id": 1
    }
    
    result = run_command(
        f"curl -s -X POST http://127.0.0.1:8545 "
        f"-H 'Content-Type: application/json' "
        f"--data '{json.dumps(rpc_payload)}'",
        check=False
    )
    
    if result.returncode == 0:
        try:
            rpc_response = json.loads(result.stdout)
            code = rpc_response.get("result", "")
            if code == "0x" or not code:
                log_and_echo("❌ ERROR: Vault contract does not exist at the specified address!")
                log_and_echo(f"   Address: {vault_address}")
                log_and_echo("   The Hardhat chain may have been reset. Please redeploy the vault.")
                log_and_echo("   Run: python3 testing-infra/e2e-tests-evm/deploy_vault.py")
                os._exit(1)
            log(f"   ✅ Vault contract verified (code length: {len(code) - 2} bytes)")
        except (json.JSONDecodeError, KeyError):
            log_and_echo("   ⚠️  Warning: Could not verify vault contract (RPC response invalid)")
    else:
        log_and_echo("   ⚠️  Warning: Could not verify vault contract (RPC call failed)")

    # Track released escrows
    released_escrows = set()

    log("")
    log("⏳ Polling verifier for approvals...")
    log("   Verifier API: http://127.0.0.1:3333/approvals")
    log("")

    # Poll for approvals
    log("   - Checking for approvals (will check 10 times with 3 second intervals)...")
    for i in range(1, 11):
        time.sleep(3)
        released_escrows = check_and_release_escrows(vault_address, released_escrows)

    log("")
    # Check if any escrows were released
    if not released_escrows:
        log_and_echo("❌ ERROR: No escrows were released!")
        log_and_echo("   The verifier may not have approved the escrow, or the claim failed")
        log_and_echo("   Check verifier logs and approvals API")
        os._exit(1)

    released_list = " ".join(released_escrows)
    log("✅ Escrow release monitoring complete!")
    log(f"   Released escrows: {released_list}")
    log("")
    log("📝 Useful commands:")
    log("   View approvals:  curl -s http://127.0.0.1:3333/approvals | jq")
    log("   View events:    curl -s http://127.0.0.1:3333/events | jq")
    log("   Health check:   curl -s http://127.0.0.1:3333/health")


if __name__ == "__main__":
    main()
