#!/usr/bin/env python3
"""
Setup EVM chain (Hardhat node) for testing.

This script starts a Hardhat node in the background and waits for it to be ready.
Python equivalent of setup-evm-chain.sh
"""

import sys
import time
import subprocess
import os
import signal
from pathlib import Path

# Add parent directory to path to import common
sys.path.insert(0, str(Path(__file__).parent.parent))
import common
from common import (
    setup_project_root, setup_logging, log, log_and_echo,
    run_command, LOG_FILE
)


def is_hardhat_ready() -> tuple[bool, str]:
    """
    Check if Hardhat node is ready by querying eth_blockNumber.

    Returns:
        Tuple of (is_ready, response_text)
    """
    try:
        import requests
        response = requests.post(
            "http://127.0.0.1:8545",
            json={"jsonrpc": "2.0", "method": "eth_blockNumber", "params": [], "id": 1},
            timeout=2
        )
        response_text = response.text
        if response.status_code == 200 and '"result"' in response_text:
            return True, response_text
        return False, response_text
    except Exception as e:
        return False, str(e)


def check_port_usage(port: int) -> str:
    """
    Check what's using a specific port.

    Args:
        port: Port number to check

    Returns:
        String describing port usage or empty string
    """
    result = run_command(f"lsof -i :{port}", check=False)
    if result.returncode == 0:
        return f"Port {port} is in use by:\n{result.stdout}"

    result = run_command(f"ss -tuln | grep ':{port}'", check=False)
    if result.returncode == 0:
        return f"Port {port} appears to be in use:\n{result.stdout}"

    return f"Port {port} is not in use"


def main():
    """Setup EVM chain (Hardhat node)."""
    # Setup project root and logging
    setup_project_root(Path(__file__))
    log_dir, log_file = setup_logging("setup-evm-chain")

    log("🔗 EVM CHAIN SETUP")
    log("==================")
    log_and_echo(f"📝 All output logged to: {log_file}")

    # Stop any existing Hardhat node
    log("🧹 Stopping any existing Hardhat node...")
    run_command('pkill -f "hardhat node"', check=False)
    time.sleep(2)

    log("")
    log("📦 Installing npm dependencies...")

    evm_dir = common.PROJECT_ROOT / "evm-intent-framework"
    node_modules = evm_dir / "node_modules"

    # Install dependencies if needed
    if not node_modules.exists():
        log("   Running npm install...")
        result = run_command(
            f"cd {evm_dir} && nix develop {common.PROJECT_ROOT} -c bash -c 'npm install'",
            check=False
        )

        if result.returncode != 0:
            log_and_echo("   ❌ ERROR: npm install failed")
            log_and_echo(f"   Check log file for details: {log_file}")
            sys.exit(1)

        log("   ✅ Dependencies installed")
    else:
        log("   ✅ Dependencies already installed")

    log("")
    log("🚀 Starting Hardhat node on port 8545...")

    # Start Hardhat node in background
    hardhat_log = open(log_file, 'a')
    hardhat_process = subprocess.Popen(
        f"cd {evm_dir} && nix develop {common.PROJECT_ROOT} -c bash -c 'npx hardhat node --port 8545'",
        shell=True,
        stdout=hardhat_log,
        stderr=hardhat_log,
        preexec_fn=os.setsid  # Create new process group
    )

    hardhat_pid = hardhat_process.pid

    # Save PID for cleanup
    pid_file = Path("/tmp/hardhat-node.pid")
    with open(pid_file, 'w') as f:
        f.write(f"{hardhat_pid}\n")

    # Also track child hardhat process
    time.sleep(2)
    result = run_command(f"pgrep -P {hardhat_pid} -f 'hardhat node'", check=False)
    if result.returncode == 0 and result.stdout.strip():
        child_pid = result.stdout.strip().split('\n')[0]
        with open(pid_file, 'a') as f:
            f.write(f"{child_pid}\n")

    log(f"   Hardhat node started with PID: {hardhat_pid}")

    log("")
    log("⏳ Waiting for Hardhat node to be ready...")

    # Wait for node to be ready (timeout: 180 seconds)
    max_wait = 180
    for i in range(1, max_wait + 1):
        is_ready, response = is_hardhat_ready()

        if is_ready:
            log("   ✅ Hardhat node ready!")
            break

        # Log progress every 30 seconds
        if i % 30 == 0:
            log(f"   Still waiting... ({i}/{max_wait} seconds)")
            log(f"   Response: {response[:200]}")  # First 200 chars

        if i == max_wait:
            log_and_echo(f"   ❌ Timeout waiting for Hardhat node ({max_wait} seconds)")
            log_and_echo("   Checking process status...")

            # Check if process is still running
            if hardhat_process.poll() is None:
                log_and_echo(f"   Process {hardhat_pid} is still running")
            else:
                log_and_echo(f"   Process {hardhat_pid} is not running (may have crashed)")

            # Show last 50 lines of log
            log_and_echo("   Last 50 lines of Hardhat log:")
            if log_file.exists():
                with open(log_file, 'r') as f:
                    lines = f.readlines()
                    for line in lines[-50:]:
                        log_and_echo(f"   {line.rstrip()}")
            else:
                log_and_echo(f"   Log file not found: {log_file}")

            # Check port usage
            log_and_echo("   Checking if port 8545 is in use:")
            port_info = check_port_usage(8545)
            for line in port_info.split('\n'):
                log_and_echo(f"   {line}")

            log_and_echo("   Final curl test response:")
            log_and_echo(f"   {response}")

            # Kill the process
            try:
                os.killpg(os.getpgid(hardhat_pid), signal.SIGTERM)
            except:
                pass

            sys.exit(1)

        time.sleep(1)

    hardhat_log.close()

    log("")
    log("✅ EVM chain (Hardhat) is running!")
    log("")
    log("📋 Hardhat Node Details:")
    log("   RPC URL:    http://127.0.0.1:8545")
    log("   Chain ID:   31337")
    log(f"   PID:        {hardhat_pid}")
    log("")
    log("   ... (20 accounts total)")
    log("")
    log("   Private keys available via: npx hardhat node")
    log("")
    log("📋 Management Commands:")
    log(f"   Stop node:      python3 {common.PROJECT_ROOT}/testing-infra/connected-chain-evm/stop_evm_chain.py")
    log(f"   View logs:      tail -f {log_file}")
    log("   Check status:   curl -X POST http://127.0.0.1:8545 -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'")
    log("")
    log("🎉 EVM chain setup complete!")


if __name__ == "__main__":
    main()
