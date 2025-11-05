#!/usr/bin/env python3
"""
Common utilities for testing infrastructure scripts.

This module provides Python equivalents of the bash functions in common.sh.
Import this module in other Python scripts with: from common import *
"""

import os
import sys
import json
import subprocess
import time
from datetime import datetime
from pathlib import Path
from typing import Optional, Tuple


# Global variables
PROJECT_ROOT: Optional[Path] = None
LOG_DIR: Optional[Path] = None
LOG_FILE: Optional[Path] = None
TIMESTAMP: Optional[str] = None


def setup_project_root(script_path: Optional[Path] = None) -> Path:
    """
    Get project root - can be called from any script location.

    Args:
        script_path: Path to the calling script. If None, uses current file location.

    Returns:
        Path to project root directory
    """
    global PROJECT_ROOT

    if script_path is None:
        # Use the path of the calling script
        import inspect
        frame = inspect.stack()[1]
        script_path = Path(frame.filename).resolve()
    else:
        script_path = Path(script_path).resolve()

    script_dir = script_path.parent

    # Determine how many levels up to go based on script location
    # Scripts in testing-infra/*/* need to go up 2 levels
    # Scripts in testing-infra/* need to go up 1 level
    script_str = str(script_dir)

    if "/testing-infra/" in script_str and script_str.count("/testing-infra/") > 0:
        # Count path components after testing-infra
        parts_after = script_str.split("/testing-infra/")[1]
        depth = parts_after.count("/") + 1  # +1 for the immediate subdirectory

        # Go up: script dir + testing-infra + depth levels
        PROJECT_ROOT = script_dir
        for _ in range(depth + 1):  # +1 to get out of testing-infra itself
            PROJECT_ROOT = PROJECT_ROOT.parent
    else:
        # Script is directly in testing-infra or elsewhere
        PROJECT_ROOT = script_dir.parent

    return PROJECT_ROOT


def setup_logging(script_name: str = "script") -> Tuple[Path, Path]:
    """
    Setup logging functions and directory.

    Creates log file: tmp/intent-framework-logs/script-name_TIMESTAMP.log

    Args:
        script_name: Name of the script for log file naming

    Returns:
        Tuple of (log_dir, log_file) paths
    """
    global LOG_DIR, LOG_FILE, TIMESTAMP, PROJECT_ROOT

    if PROJECT_ROOT is None:
        setup_project_root()

    LOG_DIR = PROJECT_ROOT / "tmp" / "intent-framework-logs"
    LOG_DIR.mkdir(parents=True, exist_ok=True)

    TIMESTAMP = datetime.now().strftime("%Y%m%d_%H%M%S")
    LOG_FILE = LOG_DIR / f"{script_name}_{TIMESTAMP}.log"

    return LOG_DIR, LOG_FILE


def log_and_echo(message: str = "") -> None:
    """
    Print message to terminal and also log it to file.

    Args:
        message: Message to print and log
    """
    print(message)
    if LOG_FILE is not None:
        with open(LOG_FILE, 'a') as f:
            f.write(message + "\n")


def log(message: str = "") -> None:
    """
    Write message only to log file (not terminal).

    Args:
        message: Message to log
    """
    print(message)  # Still print to stdout like the bash version. This is a temporary solution to aid in debugging.
    if LOG_FILE is not None:
        with open(LOG_FILE, 'a') as f:
            f.write(message + "\n")


def run_command(cmd: str, shell: bool = True, check: bool = False,
                capture_output: bool = True, text: bool = True, env: dict = None) -> subprocess.CompletedProcess:
    """
    Run a shell command and return the result.

    Args:
        cmd: Command to run
        shell: Run in shell mode
        check: Raise exception on non-zero exit
        capture_output: Capture stdout/stderr
        text: Return output as string
        env: Environment variables dict (if None, uses current environment)

    Returns:
        CompletedProcess object with returncode, stdout, stderr
    """
    if capture_output:
        return subprocess.run(cmd, shell=shell, check=check,
                              capture_output=capture_output, text=text, env=env)
    else:
        # When not capturing output, don't pass stdout/stderr parameters
        # This allows output to go directly to terminal in real-time
        # The process will return normally when it completes
        return subprocess.run(cmd, shell=shell, check=check, env=env)


def get_aptos_address(profile: str) -> Optional[str]:
    """
    Get address from Aptos profile.

    Args:
        profile: Aptos profile name to query

    Returns:
        Account address or None if not found
    """
    try:
        result = run_command("aptos config show-profiles")
        if result.returncode == 0:
            data = json.loads(result.stdout)
            return data.get("Result", {}).get(profile, {}).get("account")
    except (json.JSONDecodeError, subprocess.SubprocessError):
        return None
    return None


def display_balances() -> None:
    """
    Fetch and display balances for Aptos and EVM chains.

    Fetches balances from aptos CLI and displays them on both terminal and log file.
    Also shows EVM chain balances if EVM chain is running.
    """
    # Fetch Aptos balances
    def get_aptos_balance(profile: str) -> str:
        try:
            result = run_command(f"aptos account balance --profile {profile} 2>/dev/null")
            if result.returncode == 0:
                data = json.loads(result.stdout)
                return str(data.get("Result", [{}])[0].get("balance", 0))
        except:
            pass
        return "0"

    alice1 = get_aptos_balance("alice-chain1")
    alice2 = get_aptos_balance("alice-chain2")
    bob1 = get_aptos_balance("bob-chain1")
    bob2 = get_aptos_balance("bob-chain2")

    log_and_echo("")
    log_and_echo("   Chain 1 (Hub):")
    log_and_echo(f"      Alice: {alice1} Octas")
    log_and_echo(f"      Bob:   {bob1} Octas")
    log_and_echo("   Chain 2 (Connected):")
    log_and_echo(f"      Alice: {alice2} Octas")
    log_and_echo(f"      Bob:   {bob2} Octas")

    # Check if EVM chain is running
    try:
        import requests
        response = requests.post(
            "http://127.0.0.1:8545",
            json={"jsonrpc": "2.0", "method": "eth_blockNumber", "params": [], "id": 1},
            timeout=2
        )
        if response.status_code == 200:
            # EVM chain is running, fetch balances
            os.chdir(PROJECT_ROOT / "evm-intent-framework")

            # Get Alice's balance (account 0)
            alice_result = run_command(
                f'nix develop "{PROJECT_ROOT}" -c bash -c '
                f'"cd \'{PROJECT_ROOT}/evm-intent-framework\' && '
                f'ACCOUNT_INDEX=0 npx hardhat run scripts/get-account-balance.js --network localhost" 2>&1'
            )
            alice_evm = "0"
            if alice_result.returncode == 0:
                # Extract numeric balance from output
                for line in alice_result.stdout.strip().split('\n'):
                    if line.strip().isdigit():
                        alice_evm = line.strip()

            # Get Solver's balance (account 1)
            solver_result = run_command(
                f'nix develop "{PROJECT_ROOT}" -c bash -c '
                f'"cd \'{PROJECT_ROOT}/evm-intent-framework\' && '
                f'ACCOUNT_INDEX=1 npx hardhat run scripts/get-account-balance.js --network localhost" 2>&1'
            )
            solver_evm = "0"
            if solver_result.returncode == 0:
                for line in solver_result.stdout.strip().split('\n'):
                    if line.strip().isdigit():
                        solver_evm = line.strip()

            os.chdir(PROJECT_ROOT)

            log_and_echo("   Chain 3 (EVM):")

            # Format EVM balances (show in ETH)
            if alice_evm != "0" and alice_evm:
                try:
                    alice_eth = float(alice_evm) / 1e18
                    log_and_echo(f"      Alice (Acc 0): {alice_eth:.4f} ETH")
                except:
                    log_and_echo("      Alice (Acc 0): 0 ETH")
            else:
                log_and_echo("      Alice (Acc 0): 0 ETH")

            if solver_evm != "0" and solver_evm:
                try:
                    bob_eth = float(solver_evm) / 1e18
                    log_and_echo(f"      Bob (Acc 1): {bob_eth:.4f} ETH")
                except:
                    log_and_echo("      Bob (Acc 1): 0 ETH")
            else:
                log_and_echo("      Bob (Acc 1): 0 ETH")
    except:
        # EVM chain not running or error occurred
        pass

    log_and_echo("")


def fund_and_verify_aptos_account(
    profile: str,
    chain_num: int,
    account_label: str,
    expected_amount: int = 100000000
) -> Optional[int]:
    """
    Fund Aptos account and verify balance.

    Args:
        profile: Aptos profile name
        chain_num: Aptos chain number (1 or 2)
        account_label: Label for logging (e.g., "Alice Chain 1")
        expected_amount: Expected balance after funding in Octas (default: 100000000)

    Returns:
        Verified balance in Octas or None on error
    """
    # Determine ports based on chain number
    if chain_num == 1:
        rest_port = "8080"
        faucet_port = "8081"
    elif chain_num == 2:
        rest_port = "8082"
        faucet_port = "8083"
    else:
        log_and_echo(f"❌ ERROR: Invalid chain number: {chain_num} (must be 1 or 2)")
        sys.exit(1)

    log(f"Funding {account_label}...")
    address = get_aptos_address(profile)

    if not address:
        log_and_echo(f"❌ ERROR: Could not get address for profile {profile}")
        sys.exit(1)

    try:
        import requests
        response = requests.post(
            f"http://127.0.0.1:{faucet_port}/mint?address={address}&amount=100000000"
        )
        response.raise_for_status()
        tx_data = response.json()
        tx_hash = tx_data[0] if tx_data else None

        if tx_hash and tx_hash != "null":
            log(f"✅ {account_label} funded successfully (tx: {tx_hash})")

            # Wait for funding to be processed
            log("⏳ Waiting for funding to be processed...")
            time.sleep(10)

            # Get FA store address from transaction events
            tx_response = requests.get(f"http://127.0.0.1:{rest_port}/v1/transactions/by_hash/{tx_hash}")
            tx_response.raise_for_status()
            tx_info = tx_response.json()

            # Find all Deposit events and get the last one (like shell script uses tail -1)
            # Shell script uses: select(.type=="0x1::fungible_asset::Deposit").data.store | tail -1
            fa_store = None
            deposit_stores = []
            for event in tx_info.get("events", []):
                event_type = event.get("type", "")
                # Match exactly like shell script: .type=="0x1::fungible_asset::Deposit"
                if event_type == "0x1::fungible_asset::Deposit":
                    store = event.get("data", {}).get("store")
                    if store and store != "null":
                        deposit_stores.append(store)
            
            # Use the last matching store (like shell script's tail -1)
            if deposit_stores:
                fa_store = deposit_stores[-1]

            if fa_store and fa_store != "null":
                # Get balance from FA store
                resource_response = requests.get(
                    f"http://127.0.0.1:{rest_port}/v1/accounts/{fa_store}/resources"
                )
                resource_response.raise_for_status()
                resources = resource_response.json()

                balance = None
                for resource in resources:
                    if resource.get("type") == "0x1::fungible_asset::FungibleStore":
                        balance = int(resource.get("data", {}).get("balance", 0))
                        break

                if balance is None:
                    log_and_echo(f"❌ ERROR: Failed to get {account_label} balance")
                    sys.exit(1)

                if balance != expected_amount:
                    log_and_echo(f"❌ ERROR: {account_label} balance mismatch")
                    log_and_echo(f"   Expected: {expected_amount} Octas")
                    log_and_echo(f"   Got: {balance} Octas")
                    sys.exit(1)

                log(f"✅ {account_label} balance verified: {balance} Octas")
                return balance
            else:
                log_and_echo(f"❌ ERROR: Could not verify {account_label} balance via FA store")
                sys.exit(1)
        else:
            log_and_echo(f"❌ Failed to fund {account_label}")
            sys.exit(1)
    except Exception as e:
        log_and_echo(f"❌ ERROR funding {account_label}: {e}")
        sys.exit(1)

    return None


def stop_evm_chain_if_running() -> bool:
    """
    Stop EVM chain if running (non-fatal if not running).
    
    Returns:
        True if EVM chain was stopped (or wasn't running), False on error
    """
    if PROJECT_ROOT is None:
        setup_project_root()
    
    log("🧹 Stopping EVM chain if running (to avoid conflicts)...")
    
    stop_evm_script = PROJECT_ROOT / "testing-infra" / "connected-chain-evm" / "stop_evm_chain.py"
    result = run_command(f"python3 -u {stop_evm_script}", check=False, capture_output=False)
    
    if result.returncode != 0:
        log("   ℹ️  No EVM chain running")
        return True  # Not running is not an error
    
    return True


def stop_aptos_chains_if_running() -> bool:
    """
    Stop Aptos chains if running (non-fatal if not running).
    
    Returns:
        True if Aptos chains were stopped (or weren't running), False on error
    """
    if PROJECT_ROOT is None:
        setup_project_root()
    
    log("🧹 Stopping Aptos chains if running...")
    
    stop_apt_script = PROJECT_ROOT / "testing-infra" / "connected-chain-apt" / "stop_dual_chains.py"
    result = run_command(f"python3 -u {stop_apt_script}", check=False, capture_output=False)
    
    if result.returncode != 0:
        log("   ℹ️  No Aptos chains running")
        return True  # Not running is not an error
    
    return True


if __name__ == "__main__":
    # Example usage / testing
    print("Testing common.py utilities...")

    # Test setup_project_root
    root = setup_project_root()
    print(f"✅ Project root: {root}")

    # Test setup_logging
    log_dir, log_file = setup_logging("test")
    print(f"✅ Log directory: {log_dir}")
    print(f"✅ Log file: {log_file}")

    # Test logging functions
    log_and_echo("✅ Testing log_and_echo")
    log("✅ Testing log (file only)")

    print("\n✅ All basic tests passed!")
