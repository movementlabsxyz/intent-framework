#!/usr/bin/env python3
"""
Mixed-chain intent submission script.

This script submits mixed-chain intents (Steps 1-3):
  1. [HUB CHAIN] User creates intent requesting tokens
  2. [EVM CHAIN] User creates escrow with locked tokens
  3. [HUB CHAIN] Solver fulfills intent on hub chain

For verifier monitoring and approval (Steps 4-6), run:
  ./testing-infra/e2e-tests-evm/release-evm-escrow.sh

Python equivalent of submit-cross-chain-intent-evm.sh
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
    PROJECT_ROOT, LOG_FILE
)


def get_evm_vault_address() -> str:
    """Get EVM vault address from deployment logs."""
    log_dir = PROJECT_ROOT / "tmp" / "intent-framework-logs"

    if not log_dir.exists():
        return ""

    for log_file in sorted(log_dir.glob("deploy-vault*.log"), reverse=True):
        try:
            with open(log_file, 'r') as f:
                content = f.read()
                match = re.search(r'IntentVault deployed to\s+(0x[a-fA-F0-9]{40})', content, re.IGNORECASE)
                if match:
                    return match.group(1)
        except:
            pass

    return ""


def get_apt_metadata_address(chain_address: str, alice_address: str, chain_port: int) -> str:
    """Get APT metadata address by calling helper function and querying transaction events."""
    # Call helper function to emit event with APT metadata address
    result = run_command(
        f"aptos move run --profile alice-chain1 --assume-yes "
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
    """Submit mixed-chain intents."""
    # Validate parameter
    if len(sys.argv) < 2 or sys.argv[1] not in ["0", "1"]:
        print("❌ Error: Invalid parameter!")
        print("")
        print(f"Usage: {sys.argv[0]} <parameter>")
        print("  Parameter 0: Use existing running networks (skip setup)")
        print("  Parameter 1: Run full setup and deploy contracts")
        print("")
        print("Examples:")
        print(f"  {sys.argv[0]} 0    # Use existing networks")
        print(f"  {sys.argv[0]} 1    # Run full setup")
        sys.exit(1)

    setup_chains = sys.argv[1] == "1"

    # Setup project root and logging
    setup_project_root(Path(__file__))
    log_dir, log_file = setup_logging("submit-intent-evm")

    log("======================================")
    log("🎯 MIXED-CHAIN INTENT - SUBMISSION")
    log("======================================")
    log_and_echo(f"📝 All output logged to: {log_file}")
    log("")
    log("This script submits mixed-chain intents (Steps 1-3):")
    log("  1. [HUB CHAIN] User creates intent requesting tokens")
    log("  2. [EVM CHAIN] User creates escrow with locked tokens")
    log("  3. [HUB CHAIN] Solver fulfills intent on hub chain")
    log("")
    log("For verifier monitoring and approval (Steps 4-6), run:")
    log("  ./testing-infra/e2e-tests-evm/release-evm-escrow.sh")
    log("")
    log("The verifier will:")
    log("  4. Monitor Chain 1 (Aptos hub) for intents and fulfillments")
    log("  5. Wait for hub intent to be fulfilled")
    log("  6. Sign approval for escrow release on EVM chain")

    # Check if we should run setup or use existing networks
    if setup_chains:
        log("")
        log("🚀 Step 0.1: Setting up chains and deploying contracts...")
        log("========================================================")

        # Setup EVM chain first
        log("📦 Setting up EVM chain (Chain 3)...")
        setup_evm_script = PROJECT_ROOT / "testing-infra" / "e2e-tests-evm" / "setup_and_deploy_evm.py"
        result = run_command(f"python3 -u {setup_evm_script}", check=False, capture_output=False)

        if result.returncode != 0:
            log_and_echo("❌ Failed to setup EVM chain")
            sys.exit(1)

        log("")
        log("📦 Setting up Aptos chains (Chain 1)...")
        setup_apt_script = PROJECT_ROOT / "testing-infra" / "e2e-tests-apt" / "setup_and_deploy.py"
        result = run_command(f"python3 -u {setup_apt_script}", check=False, capture_output=False)

        if result.returncode != 0:
            log_and_echo("❌ Failed to setup Aptos chains")
            sys.exit(1)

        log("")
        log("✅ Chains setup and contracts deployed successfully!")
        log("")
    else:
        log("")
        log("⚡ Using existing running networks (skipping setup)")
        log("   Ensure both Aptos chains and EVM chain are running")
        log("   Use parameter '1' to run full setup: ./submit-cross-chain-intent-evm.py 1")
        log("")

    # Get addresses
    result = run_command("aptos config show-profiles", check=False)
    if result.returncode != 0:
        log_and_echo("❌ ERROR: Could not read aptos config")
        sys.exit(1)

    try:
        data = json.loads(result.stdout)
        chain1_address = data.get("Result", {}).get("intent-account-chain1", {}).get("account", "")
        alice_chain1_address = data.get("Result", {}).get("alice-chain1", {}).get("account", "")
        bob_chain1_address = data.get("Result", {}).get("bob-chain1", {}).get("account", "")
    except json.JSONDecodeError:
        log_and_echo("❌ ERROR: Could not parse aptos config")
        sys.exit(1)

    # Get EVM vault address
    vault_address = get_evm_vault_address()

    if not vault_address:
        log_and_echo("⚠️  Warning: Could not find vault address. Please ensure IntentVault is deployed.")
        log_and_echo("   Run: ./testing-infra/e2e-tests-evm/deploy-vault.sh")
        vault_address = "0x0000000000000000000000000000000000000000"  # Placeholder

    log("")
    log("📋 Chain Information:")
    log(f"   Hub Chain (Chain 1):     {chain1_address}")
    log(f"   EVM Chain (Chain 3):    {vault_address}")
    log(f"   Alice Chain 1 (hub):     {alice_chain1_address}")
    log(f"   Bob Chain 1 (hub):       {bob_chain1_address}")

    # Load oracle public key from verifier config
    verifier_testing_config = PROJECT_ROOT / "trusted-verifier" / "config" / "verifier_testing.toml"

    if not verifier_testing_config.exists():
        log_and_echo(f"❌ ERROR: verifier_testing.toml not found at {verifier_testing_config}")
        log_and_echo("   Tests require trusted-verifier/config/verifier_testing.toml to exist")
        sys.exit(1)

    # Read verifier public key from config
    with open(verifier_testing_config, 'r') as f:
        config_content = f.read()

    match = re.search(r'^public_key\s*=\s*"([^"]+)"', config_content, re.MULTILINE)
    if not match:
        log_and_echo("❌ ERROR: Could not find public_key in verifier_testing.toml")
        log_and_echo("   The verifier public key is required for escrow creation.")
        log_and_echo("   Please ensure verifier_testing.toml has a valid public_key field.")
        sys.exit(1)

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
        sys.exit(1)

    oracle_public_key = f"0x{oracle_public_key_hex}"
    log("   ✅ Loaded verifier public key from config (32 bytes)")

    # Generate expiry time and intent ID
    import datetime
    expiry_time = int((datetime.datetime.now() + datetime.timedelta(hours=1)).timestamp())

    # Generate a random intent_id (32 bytes)
    intent_id = f"0x{secrets.token_hex(32)}"

    log("")
    log("🔑 Configuration:")
    log(f"   Oracle public key: {oracle_public_key}")
    log(f"   Expiry time: {expiry_time}")
    log(f"   Intent ID (for hub & escrow): {intent_id}")

    # Check and display initial balances
    log("")
    display_balances()

    log("")
    log("📝 STEP 1: [HUB CHAIN] Alice creates intent requesting APT")
    log("=================================================")
    log("   User creates intent on hub chain requesting APT from solver")
    log("   - Alice creates intent on Chain 1 (hub chain)")
    log("   - Intent requests 1 APT to be provided by solver (1000 ETH for 1 APT)")
    log(f"   - Using intent_id: {intent_id}")

    # Get APT metadata addresses for Chain 1
    log("   - Getting APT metadata addresses...")
    log("     Getting APT metadata on Chain 1...")

    apt_metadata_chain1 = get_apt_metadata_address(chain1_address, alice_chain1_address, 8080)

    if not apt_metadata_chain1:
        log_and_echo("     ❌ Failed to extract APT metadata from Chain 1 transaction")
        sys.exit(1)

    log(f"     ✅ Got APT metadata on Chain 1: {apt_metadata_chain1}")
    source_fa_metadata_chain1 = apt_metadata_chain1
    desired_fa_metadata_chain1 = apt_metadata_chain1

    # Create cross-chain request intent on Chain 1
    apt_amount_octas = "100000000"  # 1 APT = 100000000 Octas
    log("   - Creating cross-chain request intent on Chain 1...")
    log(f"     Source FA metadata: {source_fa_metadata_chain1}")
    log(f"     Desired FA metadata: {desired_fa_metadata_chain1}")
    log(f"     Amount: 1 APT ({apt_amount_octas} Octas)")

    result = run_command(
        f"aptos move run --profile alice-chain1 --assume-yes "
        f"--function-id '0x{chain1_address}::fa_intent_cross_chain::create_cross_chain_request_intent_entry' "
        f"--args 'address:{source_fa_metadata_chain1}' 'address:{desired_fa_metadata_chain1}' "
        f"'u64:{apt_amount_octas}' 'u64:{expiry_time}' 'address:{intent_id}'",
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
        sys.exit(1)

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
                sys.exit(1)
        else:
            log_and_echo("     ❌ ERROR: Could not query transactions")
            sys.exit(1)
    except Exception as e:
        log_and_echo(f"     ❌ ERROR: Failed to verify intent: {e}")
        sys.exit(1)

    log("")
    log("📝 STEP 2: [EVM CHAIN] Alice creates escrow with locked ETH")
    log("=================================================")
    log("   User creates escrow on EVM chain WITH ETH locked in it")
    log("   - Alice locks 1000 ETH in escrow on Chain 3 (EVM)")
    log("   - User provides hub chain intent_id when creating escrow")
    log(f"   - Using intent_id from hub chain: {intent_id}")
    log("   - Exchange rate: 1000 ETH = 1 APT")

    # Convert intent_id to EVM format
    intent_id_hex = intent_id.replace("0x", "")
    intent_id_hex = intent_id_hex.zfill(64)
    intent_id_evm = f"0x{intent_id_hex}"

    log(f"     Intent ID (EVM): {intent_id_evm}")

    # Initialize vault for this intent with ETH
    log("   - Initializing vault for intent (ETH vault)...")
    expiry_time_evm = int((datetime.datetime.now() + datetime.timedelta(hours=1)).timestamp())

    evm_dir = PROJECT_ROOT / "evm-intent-framework"
    result = run_command(
        f"cd {evm_dir} && nix develop {PROJECT_ROOT} -c bash -c "
        f"\"cd '{evm_dir}' && VAULT_ADDRESS='{vault_address}' INTENT_ID_EVM='{intent_id_evm}' "
        f"EXPIRY_TIME_EVM='{expiry_time_evm}' npx hardhat run scripts/initialize-vault-eth.js --network localhost\" 2>&1",
        check=False
    )

    # Append to log file
    if LOG_FILE:
        with open(LOG_FILE, 'a') as f:
            f.write(result.stdout + "\n")

    if result.returncode != 0:
        log_and_echo("     ❌ ERROR: Vault initialization failed!")
        log_and_echo(f"   Initialization output: {result.stdout}")
        log_and_echo(f"   See log file for details: {LOG_FILE}")
        sys.exit(1)

    # Verify initialization succeeded
    if "Vault initialized for intent" not in result.stdout.lower():
        log_and_echo("     ❌ ERROR: Vault initialization did not complete successfully")
        log_and_echo(f"   Initialization output: {result.stdout}")
        log_and_echo("   Expected to see 'Vault initialized for intent (ETH)' in output")
        sys.exit(1)

    # Deposit 1000 ETH into vault
    log("   - Depositing 1000 ETH into vault...")
    eth_amount_wei = "1000000000000000000000"  # 1000 ETH = 1000 * 10^18 wei

    result = run_command(
        f"cd {evm_dir} && nix develop {PROJECT_ROOT} -c bash -c "
        f"\"cd '{evm_dir}' && VAULT_ADDRESS='{vault_address}' INTENT_ID_EVM='{intent_id_evm}' "
        f"ETH_AMOUNT_WEI='{eth_amount_wei}' npx hardhat run scripts/deposit-eth.js --network localhost\" 2>&1",
        check=False
    )

    # Append to log file
    if LOG_FILE:
        with open(LOG_FILE, 'a') as f:
            f.write(result.stdout + "\n")

    if result.returncode != 0:
        log_and_echo("     ❌ ERROR: ETH deposit failed!")
        log_and_echo(f"   Deposit output: {result.stdout}")
        log_and_echo(f"   See log file for details: {LOG_FILE}")
        sys.exit(1)

    # Verify deposit succeeded
    if not re.search(r"Deposited.*wei.*ETH.*vault", result.stdout, re.IGNORECASE):
        log_and_echo("     ❌ ERROR: ETH deposit did not complete successfully")
        log_and_echo(f"   Deposit output: {result.stdout}")
        log_and_echo("   Expected to see 'Deposited ... wei (ETH) into vault' in output")
        sys.exit(1)

    log("     ✅ Escrow created on Chain 3 (EVM)!")
    log_and_echo("✅ Escrow created")

    log("")
    log("📝 STEP 3: [HUB CHAIN] Bob fulfills intent on hub chain")
    log("=================================================")
    log("   Solver monitors escrow event on EVM chain and fulfills intent on hub chain")
    log(f"   - Bob sees intent with ID: {intent_id}")
    log(f"   - Bob provides 1 APT ({apt_amount_octas} Octas) on hub chain to fulfill the intent")

    # Get the intent object address from Step 1
    if not hub_intent_address or hub_intent_address == "null":
        log_and_echo("     ❌ ERROR: Could not find hub intent address")
        sys.exit(1)

    log(f"   - Intent object address: {hub_intent_address}")
    log("   - Fulfilling intent...")

    # Bob fulfills the intent
    result = run_command(
        f"aptos move run --profile bob-chain1 --assume-yes "
        f"--function-id '0x{chain1_address}::fa_intent_cross_chain::fulfill_cross_chain_request_intent' "
        f"--args 'address:{hub_intent_address}' 'u64:{apt_amount_octas}'",
        check=False
    )

    # Append to log file
    if LOG_FILE:
        with open(LOG_FILE, 'a') as f:
            f.write(result.stdout + "\n")
            f.write(result.stderr + "\n")

    if result.returncode != 0:
        log_and_echo("     ❌ Intent fulfillment failed!")
        log_and_echo(f"   See log file for details: {LOG_FILE}")
        sys.exit(1)

    log("     ✅ Bob successfully fulfilled the intent!")
    log_and_echo("✅ Intent fulfilled")

    log("")
    log("======================================")
    log("✅ CROSS-CHAIN INTENT SUBMISSION COMPLETE!")
    log("======================================")
    log("")
    log("Next steps:")
    log("  1. Run verifier to monitor and approve: ./testing-infra/e2e-tests-evm/release-evm-escrow.sh")
    log("")
    log("Summary:")
    log("   ✅ Intent created on Chain 1 (Aptos hub): Requesting 1 APT")
    log("   ✅ Escrow created on Chain 3 (EVM): 1000 ETH locked")
    log("   ✅ Intent fulfilled on Chain 1 (Aptos hub): Bob provided 1 APT")
    log("   ⏳ Waiting for verifier approval to release 1000 ETH escrow on Chain 3")


if __name__ == "__main__":
    main()
