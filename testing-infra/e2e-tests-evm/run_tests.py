#!/usr/bin/env python3
"""
E2E Integration Test Runner (Mixed-Chain: Aptos Hub + EVM Escrow)

This script runs the mixed-chain E2E flow:
- Chain 1 (Aptos Hub): Intent creation and fulfillment
- Chain 3 (EVM): Escrow operations
- Verifier: Monitors Chain 1 and releases escrow on Chain 3

Python equivalent of run-tests.sh
"""

import sys
import json
import re
import os
import time
import signal
import subprocess
from pathlib import Path

# Add parent directory to path to import common
sys.path.insert(0, str(Path(__file__).parent.parent))
import common
from common import (
    setup_project_root, setup_logging, log, log_and_echo,
    run_command, get_aptos_address, display_balances,
    LOG_FILE, stop_evm_chain_if_running, stop_aptos_chains_if_running
)
from config import TestConfig, setup_config_file


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
    # Kill cargo processes running trusted-verifier
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


def get_evm_vault_address() -> str:
    """Extract EVM vault address from deployment logs."""
    log_dir = common.PROJECT_ROOT / "tmp" / "intent-framework-logs"

    if not log_dir.exists():
        return ""

    for log_file in sorted(log_dir.glob("deploy-vault*.log"), reverse=True):
        try:
            with open(log_file, 'r') as f:
                content = f.read()
                # Try multiple patterns to match both shell and Python script output
                patterns = [
                    r'IntentVault deployed to\s+(0x[a-fA-F0-9]{40})',
                    r'Contract Address:\s+(0x[a-fA-F0-9]{40})',
                    r'✅ IntentVault deployed successfully!.*?Contract Address:\s+(0x[a-fA-F0-9]{40})',
                ]
                for pattern in patterns:
                    match = re.search(pattern, content, re.IGNORECASE | re.DOTALL)
                    if match:
                        return match.group(1)
        except:
            pass

    return ""


def get_verifier_eth_address(config_path: Path) -> str:
    """Compute verifier Ethereum address from config."""
    verifier_dir = common.PROJECT_ROOT / "trusted-verifier"

    result = run_command(
        f"cd {verifier_dir} && VERIFIER_CONFIG_PATH='{config_path}' cargo run --bin get_verifier_eth_address 2>/dev/null",
        check=False
    )

    if result.returncode == 0:
        for line in result.stdout.strip().split('\n'):
            match = re.match(r'^(0x[a-fA-F0-9]{40})$', line.strip())
            if match:
                return match.group(1)

    return ""


def get_hardhat_account_address(account_index: int) -> str:
    """Get Hardhat account address."""
    evm_dir = common.PROJECT_ROOT / "evm-intent-framework"

    result = run_command(
        f"cd {evm_dir} && nix develop {common.PROJECT_ROOT} -c bash -c "
        f"\"cd '{evm_dir}' && ACCOUNT_INDEX={account_index} npx hardhat run scripts/get-account-address.js --network localhost\" 2>&1",
        check=False
    )

    if result.returncode == 0:
        for line in result.stdout.strip().split('\n'):
            match = re.match(r'^(0x[a-fA-F0-9]{40})$', line.strip())
            if match:
                return match.group(1)

    return ""


def update_evm_chain_section(config_content: str, vault_address: str, verifier_address: str) -> str:
    """Update or add [evm_chain] section in config."""
    evm_config = f"""[evm_chain]
rpc_url = "http://127.0.0.1:8545"
vault_address = "{vault_address}"
chain_id = 31337
verifier_address = "{verifier_address}"
"""

    if '[evm_chain]' in config_content:
        # Update existing section
        config_content = re.sub(
            r'\[evm_chain\].*?(?=\n\[|\Z)',
            evm_config.rstrip(),
            config_content,
            flags=re.DOTALL
        )
    else:
        # Add new section before [verifier] if it exists
        if '[verifier]' in config_content:
            config_content = re.sub(
                r'(\[verifier\])',
                f'{evm_config}\n\\1',
                config_content
            )
        else:
            # Append at end
            config_content = config_content.rstrip() + '\n\n' + evm_config

    return config_content


def main():
    """Run mixed-chain E2E integration tests."""
    # Setup project root first (needed for cleanup)
    setup_project_root(Path(__file__))
    
    # Cleanup any existing chains and processes - before logging setup
    # The stop scripts will output their own messages
    stop_evm_chain_if_running()
    stop_aptos_chains_if_running()
    
    # Now setup logging
    log_dir, log_file = setup_logging("run-tests-evm")

    log_and_echo("🧪 MIXED-CHAIN E2E Integration Tests Runner")
    log_and_echo("==========================================")
    log_and_echo(f"📝 All output logged to: {log_file}")
    log_and_echo("")

    # Stop any existing verifier processes
    log("   - Stopping any existing verifier processes...")
    stop_verifier_processes()

    log_and_echo("✅ Cleanup complete")
    log_and_echo("")

    log_and_echo("🚀 Step 0: Setting up chains and deploying contracts...")
    log_and_echo("======================================================")

    # Set up config file (get path and clean up any old config)
    config_file = setup_config_file(None, log)

    # Setup EVM chain first
    log_and_echo("📦 Setting up EVM chain...")
    setup_evm_script = common.PROJECT_ROOT / "testing-infra" / "e2e-tests-evm" / "setup_and_deploy_evm.py"
    result = run_command(f"python3 -u {setup_evm_script}", check=False, capture_output=False)

    if result.returncode != 0:
        log_and_echo("❌ Failed to setup EVM chain")
        sys.exit(1)

    log_and_echo("")
    log_and_echo("📦 Setting up Aptos chains...")
    setup_apt_script = common.PROJECT_ROOT / "testing-infra" / "e2e-tests-apt" / "setup_and_deploy.py"
    result = run_command(f"python3 -u {setup_apt_script}", check=False, capture_output=False)

    if result.returncode != 0:
        log_and_echo("❌ Failed to setup Aptos chains")
        sys.exit(1)

    log_and_echo("")
    log_and_echo("✅ Setup complete! Extracting module addresses...")
    log_and_echo("")

    # Extract deployed addresses from aptos profiles
    result = run_command("aptos config show-profiles", check=False)
    if result.returncode != 0:
        log_and_echo("❌ ERROR: Could not read aptos config")
        sys.exit(1)

    try:
        data = json.loads(result.stdout)
        chain1_address = data.get("Result", {}).get("intent-account-chain1", {}).get("account", "")
    except json.JSONDecodeError:
        log_and_echo("❌ ERROR: Could not parse aptos config")
        sys.exit(1)

    if not chain1_address:
        log_and_echo("❌ ERROR: Could not extract Chain 1 deployed module address")
        sys.exit(1)

    log_and_echo(f"   Chain 1 deployer: {chain1_address}")

    # Get EVM vault address
    vault_address = get_evm_vault_address()

    if not vault_address:
        log_dir = common.PROJECT_ROOT / "tmp" / "intent-framework-logs"
        log_and_echo("❌ ERROR: Could not extract EVM vault address from deployment logs")
        log_and_echo(f"   Check deployment logs in: {log_dir}")
        if log_dir.exists():
            log_files = list(log_dir.glob("deploy-vault*.log"))
            if log_files:
                log_and_echo(f"   Found {len(log_files)} deploy-vault log file(s)")
                log_and_echo(f"   Most recent: {log_files[0]}")
            else:
                log_and_echo("   No deploy-vault log files found")
                log_and_echo("   EVM vault deployment may not have completed successfully")
        else:
            log_and_echo("   Log directory does not exist - EVM setup may have failed")
        sys.exit(1)

    log_and_echo(f"   EVM Vault: {vault_address}")

    # Use verifier_testing.toml for tests
    verifier_testing_config = common.PROJECT_ROOT / "trusted-verifier" / "config" / "verifier_testing.toml"

    if not verifier_testing_config.exists():
        log_and_echo(f"❌ ERROR: verifier_testing.toml not found at {verifier_testing_config}")
        log_and_echo("   Tests require trusted-verifier/config/verifier_testing.toml to exist")
        sys.exit(1)

    # Get verifier Ethereum address from config
    log("   - Computing verifier Ethereum address from config...")
    verifier_address = get_verifier_eth_address(verifier_testing_config)

    if not verifier_address:
        log_and_echo("   ⚠️  Warning: Could not compute verifier Ethereum address from config")
        log_and_echo("   Falling back to Hardhat account 1 (Bob)")
        verifier_address = get_hardhat_account_address(1)

        if not verifier_address:
            verifier_address = "0x70997970C51812dc3A010C7d01b50e0d17dc79C8"  # Hardhat default account 1

    log_and_echo(f"   EVM Verifier: {verifier_address}")

    # Create and populate test config
    config = TestConfig()
    config.chain1_address = chain1_address
    config.vault_address = vault_address
    config.verifier_address = verifier_address
    config.alice_chain1_address = get_aptos_address("alice-chain1")
    config.bob_chain1_address = get_aptos_address("bob-chain1")
    config.verifier_config_path = verifier_testing_config

    # Save config to temp file (config_file already defined above)
    config.save(config_file)
    log(f"   Saved test config to: {config_file}")

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

    # Update or add EVM chain section
    config_content = update_evm_chain_section(config_content, vault_address, verifier_address)

    # Get Alice and Bob addresses and update known_accounts
    alice_chain1 = get_aptos_address("alice-chain1") or ""
    bob_chain1 = get_aptos_address("bob-chain1") or ""

    if alice_chain1 and bob_chain1:
        config_content = update_toml_section(
            config_content,
            "[hub_chain]",
            "[connected_chain]",
            "known_accounts",
            f'["{alice_chain1}", "{bob_chain1}"]'
        )

    # Write updated config
    with open(verifier_testing_config, 'w') as f:
        f.write(config_content)

    log_and_echo("✅ Updated verifier_testing.toml with deployed addresses")
    log_and_echo("")

    log_and_echo("📝 Step 1: Submitting mixed-chain intents...")
    log_and_echo("===========================================")

    # Call submit-cross-chain-intent-evm.py (already converted)
    # Pass the config file
    submit_script = common.PROJECT_ROOT / "testing-infra" / "e2e-tests-evm" / "submit_cross_chain_intent_evm.py"
    log_and_echo(f"   Passing config file to submit script: {config_file}")
    result = run_command(f"python3 -u {submit_script} 0 --config-file {config_file}", check=False, capture_output=False)

    if result.returncode != 0:
        log_and_echo("❌ Failed to submit intents")
        sys.exit(1)

    log_and_echo("")
    log_and_echo("✅ Intents submitted successfully!")
    log_and_echo("")
    display_balances()
    log_and_echo("")

    log_and_echo("🚀 Step 2: Running verifier service to monitor and release escrow...")
    log_and_echo("================================================================")
    log_and_echo("   The verifier will:")
    log_and_echo("   1. Monitor Chain 1 (Aptos hub) for intents and fulfillments")
    log_and_echo("   2. When fulfillment detected, create ECDSA signature")
    log_and_echo("   3. Release escrow on Chain 3 (EVM)")
    log_and_echo("")

    # Check if verifier is already running and stop it
    log_and_echo("   Checking for existing verifiers...")
    result = run_command("pgrep -f 'cargo.*trusted-verifier' || pgrep -f 'target/debug/trusted-verifier'", check=False)

    if result.returncode == 0:
        log_and_echo("   ⚠️  Found existing verifier processes, stopping them...")
        stop_verifier_processes()
    else:
        log_and_echo("   ✅ No existing verifier processes")

    # Start verifier in background
    verifier_dir = common.PROJECT_ROOT / "trusted-verifier"
    verifier_log = common.PROJECT_ROOT / "tmp" / "intent-framework-logs" / "verifier-evm.log"
    verifier_log.parent.mkdir(parents=True, exist_ok=True)

    log_and_echo("   Starting verifier service...")

    # Set environment for verifier
    env = os.environ.copy()
    env["VERIFIER_CONFIG_PATH"] = str(verifier_testing_config.resolve())

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

    # Wait for verifier to start
    time.sleep(5)

    if not is_process_running(verifier_pid):
        log_and_echo("   ❌ Verifier failed to start")
        with open(verifier_log, 'r') as f:
            log_and_echo(f.read())
        sys.exit(1)

    log_and_echo(f"   ✅ Verifier started (PID: {verifier_pid})")
    log_and_echo("")

    # Give verifier some time to process events
    log_and_echo("   ⏳ Waiting for verifier to process events (30 seconds)...")
    time.sleep(30)

    # Check verifier health
    try:
        import requests
        response = requests.get("http://127.0.0.1:3333/health", timeout=5)
        if response.status_code == 200:
            log_and_echo("   ✅ Verifier is healthy")
        else:
            log_and_echo("   ⚠️  Verifier health check failed")
    except:
        log_and_echo("   ⚠️  Verifier health check failed")

    log_and_echo("")
    log_and_echo("🔓 Step 3: Releasing EVM escrow...")
    log_and_echo("==================================")

    # Call release-evm-escrow.py (already converted)
    # Pass the config file
    release_script = common.PROJECT_ROOT / "testing-infra" / "e2e-tests-evm" / "release_evm_escrow.py"
    log_and_echo(f"   Passing config file to release script: {config_file}")
    result = run_command(f"python3 -u {release_script} --config-file {config_file}", check=False, capture_output=False)

    if result.returncode != 0:
        log_and_echo("❌ Failed to release EVM escrow")
        log_and_echo("")
        # Try to read the log file to show the error
        log_dir = common.PROJECT_ROOT / "tmp" / "intent-framework-logs"
        if log_dir.exists():
            log_files = sorted(log_dir.glob("release-evm-escrow*.log"), reverse=True)
            if log_files:
                log_file = log_files[0]
                log_and_echo(f"   Reading error from log: {log_file}")
                try:
                    with open(log_file, 'r') as f:
                        lines = f.readlines()
                        # Show last 20 lines that contain errors
                        error_lines = []
                        for line in reversed(lines[-50:]):  # Check last 50 lines
                            if '❌' in line or 'ERROR' in line or 'error' in line.lower():
                                error_lines.insert(0, line.strip())
                                if len(error_lines) >= 10:
                                    break
                        if error_lines:
                            log_and_echo("   Recent errors from log:")
                            for line in error_lines:
                                log_and_echo(f"   {line}")
                except Exception as e:
                    log_and_echo(f"   Could not read log file: {e}")
        log_and_echo("")
        log_and_echo("   Check release-evm-escrow logs for full details")
        sys.exit(1)

    log_and_echo("")
    display_balances()
    log_and_echo("")
    log_and_echo("✅ E2E test flow completed!")
    log_and_echo("")

    # Stop verifier
    if is_process_running(verifier_pid):
        log_and_echo("   Stopping verifier...")
        try:
            verifier_process.terminate()
            verifier_process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            verifier_process.kill()
            verifier_process.wait()
        log_and_echo("   ✅ Verifier stopped")

    log_and_echo("")
    log_and_echo("🧹 Step 4: Cleaning up chains...")
    log_and_echo("================================")

    result = run_command(f"python3 -u {stop_evm_script}", check=False, capture_output=False)
    if result.returncode != 0:
        log_and_echo("❌ Failed to stop EVM chain")
        sys.exit(1)

    result = run_command(f"python3 -u {stop_apt_script}", check=False, capture_output=False)
    if result.returncode != 0:
        log_and_echo("❌ Failed to stop Aptos chains")
        sys.exit(1)

    log_and_echo("")
    log_and_echo("✅ All E2E tests completed!")


if __name__ == "__main__":
    main()
