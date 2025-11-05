#!/usr/bin/env python3
"""
Cross-chain verifier runner.

This script:
  1. Starts the trusted verifier service
  2. Monitors events on Chain 1 (hub) and Chain 2 (connected)
  3. Validates cross-chain conditions match
  4. Waits for hub intent to be fulfilled by solver
  5. Provides approval signatures for escrow release after hub fulfillment

Python equivalent of run-cross-chain-verifier.sh
"""

import sys
import json
import re
import os
import time
import base64
import subprocess
from pathlib import Path

# Add parent directory to path to import common
sys.path.insert(0, str(Path(__file__).parent.parent))
import common
from common import (
    setup_project_root, setup_logging, log, log_and_echo,
    run_command, get_aptos_address, display_balances,
    LOG_FILE
)


def update_toml_section(config_content: str, start_section: str, end_section: str, key: str, value: str) -> str:
    """
    Update a TOML file section, matching sed's behavior with range patterns.
    
    sed pattern: /\[hub_chain\]/,/\[connected_chain\]/ s|intent_module_address = .*|intent_module_address = "0xADDRESS"|
    This means: from [hub_chain] to [connected_chain] (inclusive), update the key.
    
    Args:
        config_content: The TOML file content
        start_section: Section header to start from (e.g., "[hub_chain]")
        end_section: Section header to end at (e.g., "[connected_chain]")
        key: Key to update (e.g., "intent_module_address")
        value: New value
    
    Returns:
        Updated config content
    """
    lines = config_content.split('\n')
    result = []
    in_section = False
    
    for line in lines:
        # Check if we're entering the start section
        if line.strip() == start_section:
            in_section = True
            result.append(line)
            continue
        
        # Check if we've reached the end section (or any other section)
        if in_section and line.strip().startswith('['):
            # If this is the end section, we're done matching after this line
            if end_section and line.strip() == end_section:
                # Still process this line, but stop matching after
                result.append(line)
                in_section = False
                continue
            elif line.strip() != start_section:
                # We've moved to a different section (not the end section), stop matching
                in_section = False
        
        # If we're in the section and this line matches the key, replace it
        if in_section and line.strip().startswith(key + ' ='):
            result.append(f'{key} = {value}')
        else:
            result.append(line)
    
    return '\n'.join(result)


def stop_verifier_processes():
    """Stop any running verifier processes."""
    run_command("pkill -f 'cargo.*trusted-verifier' || true", check=False)
    run_command("pkill -f 'target/debug/trusted-verifier' || true", check=False)
    time.sleep(2)


def is_process_running(pid: int) -> bool:
    """Check if a process is running."""
    try:
        os.kill(pid, 0)
        return True
    except (ProcessLookupError, PermissionError):
        return False


def check_and_release_escrows(released_escrows: set, chain2_deploy_address: str) -> set:
    """
    Check for new approvals and release escrows.

    Args:
        released_escrows: Set of already released escrow IDs
        chain2_deploy_address: Chain 2 deployer address

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

            # Check if escrow_id looks incorrect (not a proper object address)
            # Object addresses are 66 chars (0x + 64 hex)
            if len(escrow_id) < 64 or not re.match(r'^0x[0-9a-fA-F]{64}$', escrow_id):
                log(f"   ⚠️  escrow_id from approval looks incorrect ({escrow_id}), looking up from escrow events...")

                # Get escrow events and find matching escrow by intent_id
                events_response = requests.get("http://127.0.0.1:3333/events", timeout=5)
                events_data = events_response.json()

                actual_escrow_id = None
                for escrow_event in events_data.get("data", {}).get("escrow_events", []):
                    if escrow_event.get("intent_id") == intent_id:
                        actual_escrow_id = escrow_event.get("escrow_id")
                        break

                if actual_escrow_id and actual_escrow_id != "null" and actual_escrow_id != escrow_id:
                    log(f"   ✅ Found correct escrow object address: {actual_escrow_id} (was: {escrow_id})")
                    escrow_id = actual_escrow_id
                else:
                    log(f"   ❌ ERROR: Could not find escrow object address for intent_id: {intent_id}")
                    log("   ❌ This indicates no escrow event was found on the connected chain (Chain 2)")
                    log(f"   ❌ Expected escrow event with intent_id: {intent_id}")
                    log("   ❌ Cannot continue without valid escrow object address")
                    sys.exit(1)

            # Skip if already released
            if escrow_id in released_escrows:
                continue

            log("")
            log(f"   📦 New approval found for escrow: {escrow_id}")
            log("   🔓 Releasing escrow...")

            # Get Bob's balance before release
            log("   - Getting Bob's balance before release...")
            result = run_command("aptos account balance --profile bob-chain2 2>/dev/null", check=False)

            bob_balance_before = 0
            if result.returncode == 0:
                try:
                    data = json.loads(result.stdout)
                    bob_balance_before = int(data.get("Result", [{}])[0].get("balance", 0))
                except:
                    bob_balance_before = 0

            log(f"   - Bob's balance before release: {bob_balance_before} Octas")

            # Decode base64 signature to hex
            try:
                signature_bytes = base64.b64decode(signature_base64)
                signature_hex = signature_bytes.hex()
            except:
                log("   ❌ Failed to decode signature")
                continue

            # Submit escrow release transaction
            payment_amount = 1  # Placeholder amount

            result = run_command(
                f"aptos move run --profile bob-chain2 --assume-yes "
                f"--function-id '0x{chain2_deploy_address}::intent_as_escrow_entry::complete_escrow_from_fa' "
                f"--args 'address:{escrow_id}' 'u64:{payment_amount}' 'u64:{approval_value}' 'hex:{signature_hex}'",
                check=False
            )

            # Append to log file
            if LOG_FILE:
                with open(LOG_FILE, 'a') as f:
                    f.write(result.stdout + "\n")
                    f.write(result.stderr + "\n")

            # Wait for transaction to be processed
            time.sleep(2)

            # Get Bob's balance after release
            log("   - Getting Bob's balance after release...")
            result = run_command("aptos account balance --profile bob-chain2 2>/dev/null", check=False)

            bob_balance_after = 0
            if result.returncode == 0:
                try:
                    data = json.loads(result.stdout)
                    bob_balance_after = int(data.get("Result", [{}])[0].get("balance", 0))
                except:
                    bob_balance_after = 0

            log(f"   - Bob's balance after release: {bob_balance_after} Octas")

            # Calculate balance increase
            balance_increase = bob_balance_after - bob_balance_before

            # Expected amount: 100000000 tokens (locked in escrow) minus gas fees
            # We expect at least 99% of the locked amount to be received
            expected_min_amount = 99000000

            if result.returncode == 0:
                log("   ✅ Escrow release transaction succeeded!")

                # Verify Bob received the funds
                if balance_increase < expected_min_amount:
                    log_and_echo("   ❌ ERROR: Bob did not receive escrow funds!")
                    log_and_echo(f"      Balance increase: {balance_increase} Octas")
                    log_and_echo(f"      Expected minimum: {expected_min_amount} Octas (100000000 minus gas)")
                    log_and_echo(f"      Bob balance before: {bob_balance_before} Octas")
                    log_and_echo(f"      Bob balance after: {bob_balance_after} Octas")
                    log_and_echo(f"      Escrow ID: {escrow_id}")
                    sys.exit(1)

                log(f"   ✅ Bob received {balance_increase} Octas (expected ~100000000 minus gas)")
                released_escrows.add(escrow_id)
            else:
                # Check for object doesn't exist error
                error_output = result.stdout + result.stderr
                if "EOBJECT_DOES_NOT_EXIST" in error_output or "OBJECT_DOES_NOT_EXIST" in error_output:
                    log("   ℹ️  Escrow object no longer exists (may already be released)")

                    # Verify Bob received the funds
                    if balance_increase < expected_min_amount:
                        log_and_echo("   ❌ ERROR: Escrow object doesn't exist but Bob did NOT receive funds!")
                        log_and_echo(f"      Balance increase: {balance_increase} Octas")
                        log_and_echo(f"      Expected minimum: {expected_min_amount} Octas (100000000 minus gas)")
                        log_and_echo(f"      Bob balance before: {bob_balance_before} Octas")
                        log_and_echo(f"      Bob balance after: {bob_balance_after} Octas")
                        log_and_echo(f"      Escrow ID: {escrow_id}")
                        log_and_echo("      This indicates the escrow was released but funds went to wrong address or were lost")
                        sys.exit(1)

                    log(f"   ✅ Verified: Bob received {balance_increase} Octas (escrow was already released)")
                    released_escrows.add(escrow_id)
                else:
                    log("   ❌ Failed to release escrow")
                    log(f"      See log file for details: {LOG_FILE}")
                    log_and_echo("   ❌ ERROR: Escrow release failed and Bob did not receive funds")
                    log_and_echo(f"      Balance increase: {balance_increase} Octas")
                    log_and_echo(f"      Expected minimum: {expected_min_amount} Octas")
                    sys.exit(1)

    except Exception as e:
        # Non-fatal error, continue polling
        log(f"   ⚠️  Error checking approvals: {e}")

    return released_escrows


def main():
    """Run cross-chain verifier."""
    # Validate parameter
    if len(sys.argv) < 2 or sys.argv[1] not in ["0", "1"]:
        log_and_echo("🔍 CROSS-CHAIN VERIFIER - USAGE")
        log_and_echo("==============================================")
        log_and_echo("")
        log_and_echo(f"Usage: {sys.argv[0]} <parameter>")
        log_and_echo("")
        log_and_echo("Options:")
        log_and_echo("  0: Run verifier only (use existing running networks)")
        log_and_echo("  1: Run full setup + submit intents + verifier")
        log_and_echo("")
        log_and_echo("Examples:")
        log_and_echo(f"  {sys.argv[0]} 0    # Run verifier on existing networks")
        log_and_echo(f"  {sys.argv[0]} 1    # Setup, deploy, submit intents, then run verifier")
        log_and_echo("")
        sys.exit(1)

    run_setup = sys.argv[1] == "1"

    # Setup project root and logging
    setup_project_root(Path(__file__))
    log_dir, log_file = setup_logging("verifier_and_escrow_release")
    # Store log_dir for later use

    print("🔍 CROSS-CHAIN VERIFIER - STARTING MONITORING")
    log("==============================================")
    log_and_echo(f"📝 All output logged to: {log_file}")
    log("")

    # If option 1, run submit script first
    if run_setup:
        log("🚀 Step 0: Running setup and submitting intents...")
        log("=================================================")

        submit_script = common.PROJECT_ROOT / "testing-infra" / "e2e-tests-apt" / "submit_cross_chain_intent.py"
        result = run_command(f"python3 -u {submit_script} 1", check=False, capture_output=False)

        if result.returncode != 0:
            log_and_echo("❌ Failed to setup and submit intents")
            sys.exit(1)

        log("")
        log("✅ Setup and intent submission complete!")
        log("")

    log("This script will:")
    log("  1. Start the trusted verifier service")
    log("  2. Monitor events on Chain 1 (hub) and Chain 2 (connected)")
    log("  3. Validate cross-chain conditions match")
    log("  4. Wait for hub intent to be fulfilled by solver")
    log("  5. Provide approval signatures for escrow release after hub fulfillment")
    log("")

    # Check if verifier is already running and stop it
    log("   Checking for existing verifiers...")
    result = run_command("pgrep -f 'cargo.*trusted-verifier' || pgrep -f 'target/debug/trusted-verifier'", check=False)

    if result.returncode == 0:
        log("   ⚠️  Found existing verifier processes, stopping them...")
        stop_verifier_processes()
    else:
        log("   ✅ No existing verifier processes")

    # Get Alice and Bob addresses
    log("   - Getting Alice and Bob account addresses...")
    result = run_command("aptos config show-profiles", check=False)

    if result.returncode != 0:
        log_and_echo("❌ ERROR: Could not read aptos config")
        sys.exit(1)

    try:
        data = json.loads(result.stdout)
        alice_chain1_address = data.get("Result", {}).get("alice-chain1", {}).get("account", "")
        alice_chain2_address = data.get("Result", {}).get("alice-chain2", {}).get("account", "")
        bob_chain1_address = data.get("Result", {}).get("bob-chain1", {}).get("account", "")
        bob_chain2_address = data.get("Result", {}).get("bob-chain2", {}).get("account", "")
        chain1_deploy_address = data.get("Result", {}).get("intent-account-chain1", {}).get("account", "")
        chain2_deploy_address = data.get("Result", {}).get("intent-account-chain2", {}).get("account", "")
    except json.JSONDecodeError:
        log_and_echo("❌ ERROR: Could not parse aptos config")
        sys.exit(1)

    log(f"   ✅ Alice Chain 1: {alice_chain1_address}")
    log(f"   ✅ Alice Chain 2: {alice_chain2_address}")
    log(f"   ✅ Bob Chain 1: {bob_chain1_address}")
    log(f"   ✅ Bob Chain 2: {bob_chain2_address}")
    log(f"   ✅ Chain 1 Deployer: {chain1_deploy_address}")
    log(f"   ✅ Chain 2 Deployer: {chain2_deploy_address}")
    log("")

    # Check and display initial balances
    log("   - Checking initial balances...")
    display_balances()

    # Update verifier config
    log("   - Updating verifier configuration...")
    verifier_testing_config = common.PROJECT_ROOT / "trusted-verifier" / "config" / "verifier_testing.toml"

    if not verifier_testing_config.exists():
        log_and_echo(f"❌ ERROR: verifier_testing.toml not found at {verifier_testing_config}")
        log_and_echo("   Tests require trusted-verifier/config/verifier_testing.toml to exist")
        sys.exit(1)

    # Read config
    with open(verifier_testing_config, 'r') as f:
        config_content = f.read()

    # Update addresses using section-aware replacement (matches sed's behavior)
    # Update hub_chain intent_module_address: /\[hub_chain\]/,/\[connected_chain\]/
    config_content = update_toml_section(
        config_content,
        "[hub_chain]",
        "[connected_chain]",
        "intent_module_address",
        f'"0x{chain1_deploy_address}"'
    )

    # Update connected_chain intent_module_address: /\[connected_chain\]/,/\[verifier\]/
    config_content = update_toml_section(
        config_content,
        "[connected_chain]",
        "[verifier]",
        "intent_module_address",
        f'"0x{chain2_deploy_address}"'
    )

    # Update connected_chain escrow_module_address: /\[connected_chain\]/,/\[verifier\]/
    config_content = update_toml_section(
        config_content,
        "[connected_chain]",
        "[verifier]",
        "escrow_module_address",
        f'"0x{chain2_deploy_address}"'
    )

    # Update hub_chain known_accounts: /\[hub_chain\]/,/\[connected_chain\]/
    config_content = update_toml_section(
        config_content,
        "[hub_chain]",
        "[connected_chain]",
        "known_accounts",
        f'["{alice_chain1_address}", "{bob_chain1_address}"]'
    )

    # Update connected_chain known_accounts: /\[connected_chain\]/,/\[verifier\]/
    config_content = update_toml_section(
        config_content,
        "[connected_chain]",
        "[verifier]",
        "known_accounts",
        f'["{alice_chain2_address}"]'
    )

    # Write updated config
    with open(verifier_testing_config, 'w') as f:
        f.write(config_content)

    log("   ✅ Updated verifier_testing.toml with:")
    log(f"      Chain 1 intent_module_address: 0x{chain1_deploy_address}")
    log(f"      Chain 2 intent_module_address: 0x{chain2_deploy_address}")
    log(f"      Chain 2 escrow_module_address: 0x{chain2_deploy_address}")
    log(f"      Chain 1 known_accounts: [{alice_chain1_address}, {bob_chain1_address}]")
    log(f"      Chain 2 known_accounts: {alice_chain2_address}")
    log("")

    log("")
    log("🚀 Starting Trusted Verifier Service...")
    log("========================================")

    # Start verifier in background
    verifier_dir = common.PROJECT_ROOT / "trusted-verifier"
    verifier_log = log_dir / "verifier.log"

    env = os.environ.copy()
    env["VERIFIER_CONFIG_PATH"] = str(verifier_testing_config.resolve())
    env["RUST_LOG"] = "info"

    with open(verifier_log, 'w') as log_file_handle:
        verifier_process = subprocess.Popen(
            "cargo run --bin trusted-verifier",
            shell=True,
            cwd=verifier_dir,
            stdout=log_file_handle,
            stderr=subprocess.STDOUT,
            env=env
        )

    verifier_pid = verifier_process.pid
    log(f"   ✅ Verifier started with PID: {verifier_pid}")

    # Wait for verifier to be ready
    log("   - Waiting for verifier to initialize...")
    max_retries = 90

    for retry_count in range(max_retries):
        try:
            import requests
            response = requests.get("http://127.0.0.1:3333/health", timeout=1)
            if response.status_code == 200:
                log("   ✅ Verifier is ready!")
                break
        except:
            pass

        time.sleep(1)

        if retry_count == max_retries - 1:
            log_and_echo(f"   ❌ Verifier failed to start after {max_retries} seconds")
            log_and_echo("   Verifier log:")
            if verifier_log.exists():
                with open(verifier_log, 'r') as f:
                    log_and_echo(f"   {f.read()}")
            else:
                log_and_echo(f"   Log file not found at: {verifier_log}")
            sys.exit(1)

    log("")
    log("📊 Monitoring verifier events...")
    log("   Waiting 5 seconds for verifier to poll and collect events...")
    time.sleep(5)

    # Query verifier events
    log("")
    log("📋 Verifier Status:")
    log("========================================")

    try:
        import requests
        response = requests.get("http://127.0.0.1:3333/events", timeout=5)
        verifier_events = response.json()

        intent_count = len(verifier_events.get("data", {}).get("intent_events", []))
        escrow_count = len(verifier_events.get("data", {}).get("escrow_events", []))
        fulfillment_count = len(verifier_events.get("data", {}).get("fulfillment_events", []))

        if intent_count == 0 and escrow_count == 0 and fulfillment_count == 0:
            log("   ⚠️  No events monitored yet")
            log("   Verifier is running and waiting for events")
        else:
            if intent_count > 0:
                log(f"   ✅ Verifier has monitored {intent_count} intent events")
            if escrow_count > 0:
                log(f"   ✅ Verifier has monitored {escrow_count} escrow events")
            if fulfillment_count > 0:
                log(f"   ✅ Verifier has monitored {fulfillment_count} fulfillment events")
    except Exception as e:
        log(f"   ⚠️  Could not query verifier events: {e}")

    # Check for rejected intents in the logs
    log("")
    log("📋 Rejected Intents:")
    log("========================================")

    rejected_count = 0
    if verifier_log.exists():
        with open(verifier_log, 'r') as f:
            log_content = f.read()
            rejected_count = log_content.count("SECURITY: Rejecting")

    if rejected_count == 0:
        log_and_echo("✅ No intents rejected")
    else:
        log_and_echo(f"   ❌ ERROR: Found {rejected_count} rejected intents")
        log("")
        log_and_echo("   ❌ FATAL: Rejected intents detected. Exiting...")
        sys.exit(1)

    log("")
    log("🔍 Verifier is now monitoring:")
    log("   - Chain 1 (hub) at http://127.0.0.1:8080")
    log("   - Chain 2 (connected) at http://127.0.0.1:8082")
    log("   - API available at http://127.0.0.1:3333")
    log("")

    # Start automatic escrow release monitoring
    log("🔓 Starting automatic escrow release monitoring...")
    log("==================================================")

    if not chain2_deploy_address or chain2_deploy_address == "null":
        log_and_echo("   ❌ ERROR: Could not find Chain 2 deployer address")
        log_and_echo("      Automatic escrow release requires a valid deployer address")
        sys.exit(1)

    log("   ✅ Automatic escrow release enabled")
    log(f"      Chain 2 deployer: 0x{chain2_deploy_address}")

    # Track released escrows
    released_escrows = set()

    # Poll for approvals
    log("   - Checking for approvals (will check 5 times with 3 second intervals)...")
    for i in range(5):
        time.sleep(3)
        released_escrows = check_and_release_escrows(released_escrows, chain2_deploy_address)

    log("   ✅ Initial approval check complete")
    log("")
    log("   ℹ️  The verifier will continue monitoring in the background")
    log("      To manually check and release escrows, use:")
    log("      curl -s http://127.0.0.1:3333/approvals | jq")

    # Check final balances
    display_balances()

    log_and_echo("")
    log_and_echo("📝 Useful commands:")
    log_and_echo("   View events:      curl -s http://127.0.0.1:3333/events | jq")
    log_and_echo("   View approvals:  curl -s http://127.0.0.1:3333/approvals | jq")
    log_and_echo("   Health check:     curl -s http://127.0.0.1:3333/health")
    log_and_echo(f"   View logs:        tail -f {verifier_log}")
    log_and_echo(f"   Stop verifier:    kill {verifier_pid}")
    log_and_echo("")
    log_and_echo("ℹ️  Verifier is running in the background")
    log_and_echo(f"   Verifier PID: {verifier_pid}")
    log_and_echo("")
    log_and_echo("✨ Script complete! Verifier is monitoring events in the background.")

    # Store PID for cleanup
    pid_file = log_dir / "verifier.pid"
    with open(pid_file, 'w') as f:
        f.write(str(verifier_pid))


if __name__ == "__main__":
    main()
