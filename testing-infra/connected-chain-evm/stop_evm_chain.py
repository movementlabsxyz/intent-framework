#!/usr/bin/env python3
"""
Stop EVM chain (Hardhat node) and clean up processes.

This script stops the Hardhat node by killing processes via PID file,
process name, and port 8545.
Python equivalent of stop-evm-chain.sh
"""

import sys
import os
import signal
import time
from pathlib import Path

# Add parent directory to path to import common
sys.path.insert(0, str(Path(__file__).parent.parent))
from common import setup_project_root, setup_logging, log, log_and_echo, run_command


def kill_process_by_pid(pid: int, force: bool = False) -> bool:
    """
    Kill a process by PID.

    Args:
        pid: Process ID to kill
        force: If True, use SIGKILL; otherwise use SIGTERM

    Returns:
        True if process was killed, False otherwise
    """
    try:
        # Check if process exists
        os.kill(pid, 0)

        # Kill the process
        sig = signal.SIGKILL if force else signal.SIGTERM
        os.kill(pid, sig)
        return True
    except (OSError, ProcessLookupError):
        return False


def is_port_in_use(port: int) -> bool:
    """
    Check if a port is in use.

    Args:
        port: Port number to check

    Returns:
        True if port is in use, False otherwise
    """
    result = run_command(f"lsof -i :{port}", check=False)
    return result.returncode == 0


def kill_process_on_port(port: int) -> None:
    """
    Kill any process using the specified port.

    Args:
        port: Port number
    """
    result = run_command(f"lsof -ti :{port}", check=False)
    if result.returncode == 0 and result.stdout.strip():
        pids = result.stdout.strip().split('\n')
        for pid_str in pids:
            try:
                pid = int(pid_str.strip())
                kill_process_by_pid(pid, force=True)
            except ValueError:
                pass


def main():
    """Stop EVM chain and clean up processes."""
    # Setup project root and logging
    setup_project_root(Path(__file__))
    log_dir, log_file = setup_logging("stop-evm-chain")

    log("🛑 EVM CHAIN CLEANUP")
    log("====================")
    log_and_echo(f"📝 All output logged to: {log_file}")

    log("")
    log("🧹 Stopping Hardhat node...")

    # Kill by PID file if exists
    pid_file = Path("/tmp/hardhat-node.pid")
    if pid_file.exists():
        log("   - Found PID file, stopping processes...")
        try:
            with open(pid_file, 'r') as f:
                pids = [line.strip() for line in f if line.strip()]

            # First try graceful kill
            for pid_str in pids:
                try:
                    pid = int(pid_str)
                    if kill_process_by_pid(pid):
                        log(f"     Killing process (PID: {pid})...")
                except ValueError:
                    pass

            time.sleep(1)

            # Force kill any remaining
            for pid_str in pids:
                try:
                    pid = int(pid_str)
                    kill_process_by_pid(pid, force=True)
                except ValueError:
                    pass

            # Remove PID file
            pid_file.unlink()
            log("   ✅ Stopped processes from PID file")
        except Exception as e:
            log(f"   ⚠️  Error processing PID file: {e}")
    else:
        log("   - No PID file found")

    # Also try to kill by process name (covers nix develop processes too)
    log("   - Killing any remaining Hardhat node processes...")
    result = run_command('pkill -f "hardhat node"', check=False)
    if result.returncode == 0:
        log("   ✅ Killed Hardhat node processes")
    else:
        log("   - No Hardhat node processes found")

    # Wait a moment for processes to fully terminate
    time.sleep(1)

    # Verify port 8545 is free
    if is_port_in_use(8545):
        log("   ⚠️  Warning: Port 8545 is still in use")
        log("   - Attempting to kill process on port 8545...")
        kill_process_on_port(8545)
        time.sleep(1)

    # Note: Hardhat node is stateless - no accounts or state to clean up
    # Default accounts are generated fresh on each node start

    log("")
    log_and_echo("✅ EVM chain cleanup complete")
    log("")


if __name__ == "__main__":
    main()
