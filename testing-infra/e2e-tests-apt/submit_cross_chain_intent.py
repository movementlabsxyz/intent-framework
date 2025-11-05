#!/usr/bin/env python3
"""
Cross-chain intent submission script (Aptos chains only).

This script submits cross-chain intents (Steps 1-3):
  1. [HUB CHAIN] User creates intent requesting tokens
  2. [CONNECTED CHAIN] User creates escrow with locked tokens
  3. [HUB CHAIN] Solver fulfills intent on hub chain

For verifier monitoring and approval (Steps 4-6), run:
  ./testing-infra/e2e-tests-apt/run-cross-chain-verifier.sh

Python equivalent of submit-cross-chain-intent.sh
"""

import sys
import json
import re
import os
import time
import base64
import secrets
from pathlib import Path

# Add parent directory to path to import common
sys.path.insert(0, str(Path(__file__).parent.parent))
import common
from common import (
    setup_project_root, setup_logging, log, log_and_echo,
    run_command, get_aptos_address, display_balances,
    LOG_FILE
)
from config import TestConfig


def get_apt_metadata_address(chain_address: str, alice_address: str, chain_port: int, profile: str) -> str:
    """Get APT metadata address by calling helper function and querying transaction events."""
    # Call helper function to emit event with APT metadata address
    result = run_command(
        f"aptos move run --profile {profile} --assume-yes "
        f"--function-id '0x{chain_address}::test_fa_helper::get_apt_metadata_address'",
        check=False
    )

    # Append to log file
    if LOG_FILE:
        with open(LOG_FILE, 'a') as f:
            f.write(result.stdout + "\n")
            f.write(result.stderr + "\n")

    if result.returncode != 0:
        return ""

    # Wait for transaction to be processed
    time.sleep(2)

    # Query transaction events to get APT metadata
    try:
        import requests
        response = requests.get(
            f"http://127.0.0.1:{chain_port}/v1/accounts/{alice_address}/transactions?limit=1",
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            if len(data) > 0:
                for event in data[0].get("events", []):
                    if "APTMetadataAddressEvent" in event.get("type", ""):
                        metadata = event.get("data", {}).get("metadata")
                        if metadata and metadata != "null":
                            return metadata
    except:
        pass

    return ""


def main():
    """Submit cross-chain intents (Aptos chains)."""
    import argparse
    
    parser = argparse.ArgumentParser(description="Submit cross-chain intents (Aptos)")
    parser.add_argument('setup_flag', choices=['0', '1'],
                       help='0=skip setup (use existing), 1=run full setup')
    parser.add_argument('--config-file', type=Path,
                       help='Path to test config file (pickle format)')
    args = parser.parse_args()

    setup_chains = args.setup_flag == "1"
    
    # Load config if provided, otherwise create new one
    if args.config_file and args.config_file.exists():
        config = TestConfig.load(args.config_file)
        log(f"   Loaded config from: {args.config_file}")
    else:
        config = TestConfig()
        config.setup_chains = setup_chains

    # Setup project root and logging
    setup_project_root(Path(__file__))
    log_dir, log_file = setup_logging("submit-intent")

    log("======================================")
    log("🎯 CROSS-CHAIN INTENT - SUBMISSION")
    log("======================================")
    log_and_echo(f"📝 All output logged to: {log_file}")
    log("")
    log("This script submits cross-chain intents (Steps 1-3):")
    log("  1. [HUB CHAIN] User creates intent requesting tokens")
    log("  2. [CONNECTED CHAIN] User creates escrow with locked tokens")
    log("  3. [HUB CHAIN] Solver fulfills intent on hub chain")
    log("")
    log("For verifier monitoring and approval (Steps 4-6), run:")
    log("  ./testing-infra/e2e-tests-apt/run-cross-chain-verifier.sh")
    log("")
    log("The verifier will:")
    log("  4. Monitor both chains for intents and escrows")
    log("  5. Wait for hub intent to be fulfilled")
    log("  6. Sign approval for escrow release on connected chain")
    log("")

    # Check if we should run setup or use existing networks
    if setup_chains:
        log("")
        log("🚀 Setting up chains and deploying contracts...")
        log("========================================================")

        setup_script = common.PROJECT_ROOT / "testing-infra" / "e2e-tests-apt" / "setup_and_deploy.py"
        result = run_command(f"python3 -u {setup_script}", check=False, capture_output=False)

        if result.returncode != 0:
            log_and_echo("❌ Failed to setup chains and deploy contracts")
            os._exit(1)

        log("")
        log("✅ Chains setup and contracts deployed successfully!")
        log("")
    else:
        log("")
        log("⚡ Using existing running networks (skipping setup)")
        log("   Use parameter '1' to run full setup: ./submit-cross-chain-intent.py 1")
        log("")

    # Get addresses from config or extract from aptos
    result = run_command("aptos config show-profiles", check=False)
    if result.returncode != 0:
        log_and_echo("❌ ERROR: Could not read aptos config")
        os._exit(1)

    try:
        data = json.loads(result.stdout)
        
        # Use config values if available, otherwise extract and update config
        # If we just ran setup, config file was deleted, so we'll always extract fresh addresses
        if config.chain1_address and not setup_chains:
            chain1_address = config.chain1_address
        else:
            chain1_address = data.get("Result", {}).get("intent-account-chain1", {}).get("account", "")
            if chain1_address:
                config.chain1_address = chain1_address
        
        if config.chain2_address and not setup_chains:
            chain2_address = config.chain2_address
        else:
            chain2_address = data.get("Result", {}).get("intent-account-chain2", {}).get("account", "")
            if chain2_address:
                config.chain2_address = chain2_address
        
        if config.alice_chain1_address and not setup_chains:
            alice_chain1_address = config.alice_chain1_address
        else:
            alice_chain1_address = data.get("Result", {}).get("alice-chain1", {}).get("account", "")
            if alice_chain1_address:
                config.alice_chain1_address = alice_chain1_address
        
        if config.bob_chain1_address and not setup_chains:
            bob_chain1_address = config.bob_chain1_address
        else:
            bob_chain1_address = data.get("Result", {}).get("bob-chain1", {}).get("account", "")
            if bob_chain1_address:
                config.bob_chain1_address = bob_chain1_address
        
        alice_chain2_address = data.get("Result", {}).get("alice-chain2", {}).get("account", "")
    except json.JSONDecodeError:
        log_and_echo("❌ ERROR: Could not parse aptos config")
        os._exit(1)

    log("")
    log("📋 Chain Information:")
    log(f"   Hub Chain (Chain 1):     {chain1_address}")
    log(f"   Connected Chain (Chain 2): {chain2_address}")
    log(f"   Alice Chain 1 (hub):     {alice_chain1_address}")
    log(f"   Bob Chain 1 (hub):       {bob_chain1_address}")
    log(f"   Alice Chain 2 (connected): {alice_chain2_address}")

    # Load oracle public key from verifier config
    verifier_testing_config = common.PROJECT_ROOT / "trusted-verifier" / "config" / "verifier_testing.toml"

    if not verifier_testing_config.exists():
        log_and_echo(f"❌ ERROR: verifier_testing.toml not found at {verifier_testing_config}")
        log_and_echo("   Tests require trusted-verifier/config/verifier_testing.toml to exist")
        os._exit(1)

    # Read verifier public key from config
    with open(verifier_testing_config, 'r') as f:
        config_content = f.read()

    match = re.search(r'^public_key\s*=\s*"([^"]+)"', config_content, re.MULTILINE)
    if not match:
        log_and_echo("❌ ERROR: Could not find public_key in verifier_testing.toml")
        log_and_echo("   The verifier public key is required for escrow creation.")
        log_and_echo("   Please ensure verifier_testing.toml has a valid public_key field.")
        os._exit(1)

    verifier_public_key_b64 = match.group(1)

    # Convert base64 public key to hex (32 bytes)
    try:
        oracle_public_key_bytes = base64.b64decode(verifier_public_key_b64)
        if len(oracle_public_key_bytes) != 32:
            raise ValueError(f"Expected 32 bytes, got {len(oracle_public_key_bytes)}")
        oracle_public_key_hex = oracle_public_key_bytes.hex()
    except Exception as e:
        log_and_echo("❌ ERROR: Invalid public key format in verifier_testing.toml")
        log_and_echo("   Expected: base64-encoded 32-byte Ed25519 public key")
        log_and_echo(f"   Got: {verifier_public_key_b64}")
        log_and_echo("   Please ensure the public_key in verifier_testing.toml is valid base64 and decodes to 32 bytes (64 hex chars).")
        os._exit(1)

    oracle_public_key = f"0x{oracle_public_key_hex}"
    log("   ✅ Loaded verifier public key from config (32 bytes)")

    # Generate expiry time and intent ID
    import datetime
    expiry_time = int((datetime.datetime.now() + datetime.timedelta(hours=1)).timestamp())

    # Generate a random intent_id (32 bytes)
    intent_id = f"0x{secrets.token_hex(32)}"
    config.intent_id = intent_id

    log("")
    log("🔑 Configuration:")
    log(f"   Oracle public key: {oracle_public_key}")
    log(f"   Expiry time: {expiry_time}")
    log(f"   Intent ID (for hub & escrow): {intent_id}")

    # Check and display initial balances
    log("")
    display_balances()

    log("")
    log("📝 STEP 1: [HUB CHAIN] Alice creates intent requesting tokens")
    log("=================================================")
    log("   User creates intent on hub chain requesting tokens from solver")
    log("   - Alice creates intent on Chain 1 (hub chain)")
    log("   - Intent requests 100000000 tokens to be provided by solver")
    log(f"   - Using intent_id: {intent_id}")

    # Get APT metadata addresses for both chains
    log("   - Getting APT metadata addresses...")

    # Get APT metadata on Chain 1
    log("     Getting APT metadata on Chain 1...")
    apt_metadata_chain1 = get_apt_metadata_address(chain1_address, alice_chain1_address, 8080, "alice-chain1")

    if not apt_metadata_chain1:
        log_and_echo("     ❌ Failed to extract APT metadata from Chain 1 transaction")
        os._exit(1)

    log(f"     ✅ Got APT metadata on Chain 1: {apt_metadata_chain1}")
    source_fa_metadata_chain1 = apt_metadata_chain1
    desired_fa_metadata_chain1 = apt_metadata_chain1

    # Get APT metadata on Chain 2
    log("     Getting APT metadata on Chain 2...")
    apt_metadata_chain2 = get_apt_metadata_address(chain2_address, alice_chain2_address, 8082, "alice-chain2")

    if not apt_metadata_chain2:
        log_and_echo("     ❌ Failed to extract APT metadata from Chain 2 transaction")
        os._exit(1)

    log(f"     ✅ Got APT metadata on Chain 2: {apt_metadata_chain2}")
    source_fa_metadata_chain2 = apt_metadata_chain2

    # Create cross-chain request intent on Chain 1
    log("   - Creating cross-chain request intent on Chain 1...")
    log(f"     Source FA metadata: {source_fa_metadata_chain1}")
    log(f"     Desired FA metadata: {desired_fa_metadata_chain1}")

    result = run_command(
        f"aptos move run --profile alice-chain1 --assume-yes "
        f"--function-id '0x{chain1_address}::fa_intent_cross_chain::create_cross_chain_request_intent_entry' "
        f"--args 'address:{source_fa_metadata_chain1}' 'address:{desired_fa_metadata_chain1}' "
        f"'u64:100000000' 'u64:{expiry_time}' 'address:{intent_id}'",
        check=False
    )

    # Append to log file
    if LOG_FILE:
        with open(LOG_FILE, 'a') as f:
            f.write(result.stdout + "\n")
            f.write(result.stderr + "\n")

    if result.returncode != 0:
        log_and_echo("     ❌ Intent creation failed on Chain 1!")
        log_and_echo(f"   See log file for details: {LOG_FILE}")
        os._exit(1)

    log("     ✅ Intent created on Chain 1!")

    # Verify intent was stored on-chain
    time.sleep(2)
    log("     - Verifying intent stored on-chain...")

    try:
        import requests
        response = requests.get(
            f"http://127.0.0.1:8080/v1/accounts/{alice_chain1_address}/transactions?limit=1",
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            hub_intent_address = None
            if len(data) > 0:
                for event in data[0].get("events", []):
                    if "LimitOrderEvent" in event.get("type", ""):
                        hub_intent_address = event.get("data", {}).get("intent_address")
                        if hub_intent_address and hub_intent_address != "null":
                            break

            if hub_intent_address and hub_intent_address != "null":
                log(f"     ✅ Hub intent stored at: {hub_intent_address}")
                log_and_echo("✅ Intent created")
            else:
                log_and_echo("     ❌ ERROR: Could not verify hub intent address")
                os._exit(1)
        else:
            log_and_echo("     ❌ ERROR: Could not query transactions")
            os._exit(1)
    except Exception as e:
        log_and_echo(f"     ❌ ERROR: Failed to verify intent: {e}")
        os._exit(1)

    log("")
    log("📝 STEP 2: [CONNECTED CHAIN] Alice creates escrow intent with locked tokens")
    log("=================================================")
    log("   User creates escrow on connected chain WITH tokens locked in it")
    log("   - Alice locks 100000000 tokens in escrow on Chain 2 (connected chain)")
    log("   - User provides hub chain intent_id when creating escrow")
    log(f"   - Using intent_id from hub chain: {intent_id}")

    # Submit escrow intent using Alice's account on Chain 2
    log("   - Creating escrow intent on Chain 2...")
    log(f"     Source FA metadata: {source_fa_metadata_chain2}")

    result = run_command(
        f"aptos move run --profile alice-chain2 --assume-yes "
        f"--function-id '0x{chain2_address}::intent_as_escrow_entry::create_escrow_from_fa' "
        f"--args 'address:{source_fa_metadata_chain2}' 'u64:100000000' "
        f"'hex:{oracle_public_key}' 'u64:{expiry_time}' 'address:{intent_id}'",
        check=False
    )

    # Append to log file
    if LOG_FILE:
        with open(LOG_FILE, 'a') as f:
            f.write(result.stdout + "\n")
            f.write(result.stderr + "\n")

    if result.returncode != 0:
        log_and_echo("     ❌ Escrow intent creation failed!")
        os._exit(1)

    log("     ✅ Escrow intent created on Chain 2!")

    # Verify escrow was stored on-chain
    time.sleep(2)
    log("     - Verifying escrow stored on-chain with locked tokens...")

    try:
        import requests
        response = requests.get(
            f"http://127.0.0.1:8082/v1/accounts/{alice_chain2_address}/transactions?limit=1",
            timeout=5
        )
        if response.status_code == 200:
            data = response.json()
            escrow_address = None
            escrow_intent_id = None
            locked_amount = None
            desired_amount = None

            if len(data) > 0:
                for event in data[0].get("events", []):
                    if "OracleLimitOrderEvent" in event.get("type", ""):
                        event_data = event.get("data", {})
                        escrow_address = event_data.get("intent_address")
                        escrow_intent_id = event_data.get("intent_id")
                        locked_amount = event_data.get("source_amount")
                        desired_amount = event_data.get("desired_amount")
                        break

            if escrow_address and escrow_address != "null":
                log(f"     ✅ Escrow stored at: {escrow_address}")
                log(f"     ✅ Intent ID link: {escrow_intent_id} (should match: {intent_id})")
                log(f"     ✅ Locked amount: {locked_amount} tokens")
                log(f"     ✅ Desired amount: {desired_amount} tokens")

                # Verify intent_id matches (normalize hex strings)
                normalized_intent_id = intent_id.lower().replace("0x", "").lstrip("0") or "0"
                normalized_escrow_intent_id = escrow_intent_id.lower().replace("0x", "").lstrip("0") or "0"

                if normalized_intent_id == normalized_escrow_intent_id:
                    log("     ✅ Intent IDs match - correct cross-chain link!")
                else:
                    log_and_echo("     ❌ ERROR: Intent IDs don't match!")
                    log_and_echo(f"        Expected: {intent_id}")
                    log_and_echo(f"        Got: {escrow_intent_id}")
                    os._exit(1)

                # Verify locked amount
                if locked_amount == "100000000":
                    log("     ✅ Escrow has correct locked amount (100000000 tokens)")
                else:
                    log(f"     ⚠️  Escrow has unexpected locked amount: {locked_amount}")

                log_and_echo("✅ Escrow created")
            else:
                log_and_echo("     ❌ ERROR: Could not verify escrow from events")
                os._exit(1)
        else:
            log_and_echo("     ❌ ERROR: Could not query transactions")
            os._exit(1)
    except Exception as e:
        log_and_echo(f"     ❌ ERROR: Failed to verify escrow: {e}")
        os._exit(1)

    log("")
    log("📝 STEP 3: [HUB CHAIN] Bob fulfills intent on hub chain")
    log("=================================================")
    log("   Solver monitors escrow event on connected chain and fulfills intent on hub chain")
    log("   - Solver sees escrow event on connected chain")
    log(f"   - Bob sees intent with ID: {intent_id}")
    log("   - Bob provides 100000000 tokens on hub chain to fulfill the intent")

    # Use the intent object address from the intent creation transaction
    if not hub_intent_address or hub_intent_address == "null":
        log_and_echo("     ⚠️  Could not get intent object address, skipping fulfillment")
        os._exit(1)

    log(f"   - Fulfilling intent at: {hub_intent_address}")

    # Bob fulfills the intent
    result = run_command(
        f"aptos move run --profile bob-chain1 --assume-yes "
        f"--function-id '0x{chain1_address}::fa_intent_cross_chain::fulfill_cross_chain_request_intent' "
        f"--args 'address:{hub_intent_address}' 'u64:100000000'",
        check=False
    )

    # Append to log file
    if LOG_FILE:
        with open(LOG_FILE, 'a') as f:
            f.write(result.stdout + "\n")
            f.write(result.stderr + "\n")

    if result.returncode != 0:
        log_and_echo("     ❌ Intent fulfillment failed!")
        os._exit(1)

    log("     ✅ Bob successfully fulfilled the intent!")
    log_and_echo("✅ Intent fulfilled")

    log("")
    log("🎉 INTENT SUBMISSION COMPLETE!")
    log("==============================")
    log("")
    log("✅ Steps 1-3 completed successfully:")
    log("   1. Intent created on Chain 1 (hub chain)")
    log("   2. Escrow created on Chain 2 (connected chain) with locked tokens")
    log("   3. Intent fulfilled on Chain 1 by Bob")
    log("")
    log("📋 Intent Details:")
    log(f"   Intent ID: {intent_id}")
    if hub_intent_address and hub_intent_address != "null":
        log(f"   Chain 1 Hub Intent: {hub_intent_address}")
    if escrow_address and escrow_address != "null":
        log(f"   Chain 2 Escrow: {escrow_address}")

    # Display final balances
    display_balances()

    log("")
    log("🔍 Next Steps:")
    log("   To monitor and verify these events with the trusted verifier, run:")
    log("   ./testing-infra/e2e-tests-apt/run-cross-chain-verifier.sh")
    log("")
    log("✨ Script completed - intents are submitted and waiting for verification!")
    
    # Save config if provided
    if args.config_file:
        config.save(args.config_file)
        log(f"   Updated config saved to: {args.config_file}")


if __name__ == "__main__":
    main()
