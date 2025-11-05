#!/usr/bin/env python3
"""
E2E Integration Test Runner

This script runs the Rust integration tests that require Docker chains.
It sets up chains, deploys contracts, submits intents, then runs the tests.

Python equivalent of run-tests.sh
"""

import sys
import json
import re
import os
from pathlib import Path

# Add parent directory to path to import common
sys.path.insert(0, str(Path(__file__).parent.parent))
import common
from common import (
    setup_project_root, setup_logging, log, log_and_echo,
    run_command, get_aptos_address, LOG_FILE
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


def main():
    """Run E2E integration tests."""
    # Setup project root and logging
    setup_project_root(Path(__file__))
    log_dir, log_file = setup_logging("run-tests")

    log("🧪 E2E Integration Tests Runner")
    log("================================")
    log_and_echo(f"📝 All output logged to: {log_file}")

    # Stop EVM chain if running (to avoid conflicts)
    log("")
    log("🧹 Stopping EVM chain if running...")
    stop_evm_script = common.PROJECT_ROOT / "testing-infra" / "connected-chain-evm" / "stop_evm_chain.py"
    result = run_command(f"python3 -u {stop_evm_script}", check=False, capture_output=False)
    if result.returncode != 0:
        log("   ℹ️  No EVM chain running")

    log("")
    log("🚀 Step 0: Setting up chains, deploying contracts, and submitting intents...")
    log("========================================================================")

    # Call submit-cross-chain-intent Python script
    submit_script = common.PROJECT_ROOT / "testing-infra" / "e2e-tests-apt" / "submit_cross_chain_intent.py"
    result = run_command(f"python3 -u {submit_script} 1", check=False, capture_output=False)

    if result.returncode != 0:
        log_and_echo("❌ Failed to setup and deploy contracts")
        sys.exit(1)

    log("")
    log("✅ Setup complete! Extracting module addresses...")

    # Extract deployed addresses from aptos profiles
    result = run_command("aptos config show-profiles", check=False)
    if result.returncode != 0:
        log_and_echo("❌ ERROR: Could not read aptos config")
        sys.exit(1)

    try:
        data = json.loads(result.stdout)
        chain1_address = data.get("Result", {}).get("intent-account-chain1", {}).get("account", "")
        chain2_address = data.get("Result", {}).get("intent-account-chain2", {}).get("account", "")
    except json.JSONDecodeError:
        log_and_echo("❌ ERROR: Could not parse aptos config")
        sys.exit(1)

    if not chain1_address or not chain2_address:
        log_and_echo("❌ ERROR: Could not extract deployed module addresses")
        sys.exit(1)

    log(f"   Chain 1 deployer: {chain1_address}")
    log(f"   Chain 2 deployer: {chain2_address}")

    # Use verifier_testing.toml for tests - required, panic if not found
    verifier_testing_config = common.PROJECT_ROOT / "trusted-verifier" / "config" / "verifier_testing.toml"

    if not verifier_testing_config.exists():
        log_and_echo(f"❌ ERROR: verifier_testing.toml not found at {verifier_testing_config}")
        log_and_echo("   Tests require trusted-verifier/config/verifier_testing.toml to exist")
        sys.exit(1)

    # Read current config
    with open(verifier_testing_config, 'r') as f:
        config_content = f.read()

    # Update module addresses in verifier_testing.toml using section-aware replacement
    # This matches sed's behavior: /\[hub_chain\]/,/\[connected_chain\]/
    config_content = update_toml_section(
        config_content,
        "[hub_chain]",
        "[connected_chain]",
        "intent_module_address",
        f'"0x{chain1_address}"'
    )

    # Update connected_chain intent_module_address: /\[connected_chain\]/,/\[verifier\]/
    config_content = update_toml_section(
        config_content,
        "[connected_chain]",
        "[verifier]",
        "intent_module_address",
        f'"0x{chain2_address}"'
    )

    # Update connected_chain escrow_module_address: /\[connected_chain\]/,/\[verifier\]/
    config_content = update_toml_section(
        config_content,
        "[connected_chain]",
        "[verifier]",
        "escrow_module_address",
        f'"0x{chain2_address}"'
    )

    # Get Alice and Bob addresses and update known_accounts
    alice_chain1 = get_aptos_address("alice-chain1") or ""
    bob_chain1 = get_aptos_address("bob-chain1") or ""
    alice_chain2 = get_aptos_address("alice-chain2") or ""

    if alice_chain1 and bob_chain1:
        config_content = update_toml_section(
            config_content,
            "[hub_chain]",
            "[connected_chain]",
            "known_accounts",
            f'["{alice_chain1}", "{bob_chain1}"]'
        )

    if alice_chain2:
        config_content = update_toml_section(
            config_content,
            "[connected_chain]",
            "[verifier]",
            "known_accounts",
            f'["{alice_chain2}"]'
        )

    # Write updated config
    with open(verifier_testing_config, 'w') as f:
        f.write(config_content)

    log("✅ Updated verifier_testing.toml with deployed addresses")
    log("")

    log("📋 Running E2E integration tests...")
    log("")

    # Create a temporary integration test entry point
    integration_test_file = common.PROJECT_ROOT / "trusted-verifier" / "tests" / "integration_test_e2e.rs"

    integration_test_content = """//! E2E Integration tests entry point
//!
//! This file is temporarily generated by run_tests.py to load e2e tests.

#[path = "../../testing-infra/e2e-tests-apt/integration-tests/mod.rs"]
mod integration;
"""

    with open(integration_test_file, 'w') as f:
        f.write(integration_test_content)

    # Run the tests from trusted-verifier directory
    verifier_dir = common.PROJECT_ROOT / "trusted-verifier"

    # Export config path for Rust code to use (absolute path so tests can find it)
    env = os.environ.copy()
    env["VERIFIER_CONFIG_PATH"] = str(verifier_testing_config.resolve())

    result = run_command(
        f"cd {verifier_dir} && cargo test --test integration_test_e2e",
        check=False,
        capture_output=False,
        env=env
    )

    # Clean up temporary test file
    if integration_test_file.exists():
        integration_test_file.unlink()

    if result.returncode != 0:
        log_and_echo("❌ E2E integration tests failed!")
        log_and_echo("   Check cargo test output for details")
        sys.exit(1)

    log("")
    log("✅ E2E integration tests completed!")
    log("")
    log("🚀 Step 2: Running verifier service to test end-to-end flow...")
    log("============================================================")

    # Call run-cross-chain-verifier Python script
    verifier_script = common.PROJECT_ROOT / "testing-infra" / "e2e-tests-apt" / "run_cross_chain_verifier.py"
    result = run_command(f"python3 -u {verifier_script} 0", check=False, capture_output=False)

    if result.returncode != 0:
        log_and_echo("❌ Verifier service test failed!")
        sys.exit(1)

    log("")
    log("✅ All E2E tests completed!")
    log("")
    log("🧹 Cleaning up Docker chains...")

    # Call stop-dual-chains.py (already converted)
    stop_script = common.PROJECT_ROOT / "testing-infra" / "connected-chain-apt" / "stop_dual_chains.py"
    result = run_command(f"python3 -u {stop_script}", check=False, capture_output=False)

    if result.returncode != 0:
        log_and_echo("❌ Failed to stop Docker chains")
        sys.exit(1)

    log("")
    log("✨ E2E test runner completed!")


if __name__ == "__main__":
    main()
