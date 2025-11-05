#!/usr/bin/env python3
"""
Setup dual-chain Aptos environment for testing.

This script starts two Docker-based Aptos chains with different ports
for cross-chain testing.
Python equivalent of setup-dual-chains.sh
"""

import sys
import time
from pathlib import Path

# Add parent directory to path to import common
sys.path.insert(0, str(Path(__file__).parent.parent))
import common
from common import (
    setup_project_root, setup_logging, log, log_and_echo,
    run_command, LOG_FILE
)


def wait_for_chain(chain_num: int, rest_port: int, faucet_port: int, max_attempts: int = 30) -> bool:
    """
    Wait for an Aptos chain to be ready.

    Args:
        chain_num: Chain number (1 or 2)
        rest_port: REST API port
        faucet_port: Faucet port
        max_attempts: Maximum number of attempts (default: 30)

    Returns:
        True if chain is ready, False otherwise
    """
    log(f"   - Waiting for Chain {chain_num} services...")

    import requests

    for attempt in range(1, max_attempts + 1):
        try:
            # Check REST API (using /v1 endpoint like the shell script)
            rest_response = requests.get(f"http://127.0.0.1:{rest_port}/v1", timeout=2)
            # Check Faucet
            faucet_response = requests.get(f"http://127.0.0.1:{faucet_port}/", timeout=2)

            if rest_response.status_code == 200 and faucet_response.status_code == 200:
                log(f"   ✅ Chain {chain_num} ready!")
                return True
        except:
            pass

        log(f"   Waiting... (attempt {attempt}/{max_attempts})")
        time.sleep(5)

    return False


def verify_chain(chain_num: int, rest_port: int) -> dict:
    """
    Verify chain is running and get its info.

    Args:
        chain_num: Chain number (1 or 2)
        rest_port: REST API port

    Returns:
        Dict with chain_id and block_height

    Raises:
        SystemExit: If chain verification fails
    """
    import requests
    import json

    try:
        response = requests.get(f"http://127.0.0.1:{rest_port}/v1", timeout=5)
        response.raise_for_status()
        info = response.json()

        chain_id = info.get("chain_id", "unknown")
        block_height = info.get("block_height", "unknown")

        log(f"✅ Chain {chain_num}: ID={chain_id}, Height={block_height}")
        return {"chain_id": chain_id, "block_height": block_height}
    except Exception as e:
        log_and_echo(f"❌ Chain {chain_num} failed to start")
        sys.exit(1)


def main():
    """Setup dual-chain Aptos environment."""
    # Setup project root and logging
    setup_project_root(Path(__file__))
    log_dir, log_file = setup_logging("setup-dual-chains")

    log("🔗 DUAL-CHAIN APTOS SETUP")
    log("==========================")
    log_and_echo(f"📝 All output logged to: {log_file}")

    # Stop any existing containers
    log("🧹 Stopping existing containers...")
    
    # Check for running containers and list their IDs
    result = run_command(
        'docker ps --filter "name=aptos-localnet-chain" --format "{{.ID}}|{{.Names}}|{{.Status}}"',
        check=False
    )
    
    found_containers = []
    if result.returncode == 0 and result.stdout.strip():
        log("📋 Found running containers:")
        for line in result.stdout.strip().split('\n'):
            if line.strip():
                parts = line.split('|')
                if len(parts) >= 2:
                    container_id = parts[0]
                    container_name = parts[1]
                    container_status = parts[2] if len(parts) > 2 else "unknown"
                    log(f"   - {container_name} (ID: {container_id[:12]}, Status: {container_status})")
                    found_containers.append((container_id[:12], container_name))
    else:
        log("   No running containers found")
    
    log("")
    
    # Stop the containers
    if found_containers:
        run_command(
            f"docker-compose -f {common.PROJECT_ROOT}/testing-infra/connected-chain-apt/docker-compose-chain1.yml "
            f"-p aptos-chain1 down 2>/dev/null",
            check=False
        )
        run_command(
            f"docker-compose -f {common.PROJECT_ROOT}/testing-infra/connected-chain-apt/docker-compose-chain2.yml "
            f"-p aptos-chain2 down 2>/dev/null",
            check=False
        )
        
        # Verify containers are stopped
        log("✅ Stopped containers:")
        for container_id, container_name in found_containers:
            log(f"   - {container_name} (ID: {container_id})")
    else:
        log("   No containers to stop")

    log("")
    log("🚀 Starting Chain 1 (ports 8080/8081)...")
    run_command(
        f"docker-compose -f {common.PROJECT_ROOT}/testing-infra/connected-chain-apt/docker-compose-chain1.yml "
        f"-p aptos-chain1 up -d"
    )

    log("")
    log("🚀 Starting Chain 2 (ports 8082/8083)...")
    run_command(
        f"docker-compose -f {common.PROJECT_ROOT}/testing-infra/connected-chain-apt/docker-compose-chain2.yml "
        f"-p aptos-chain2 up -d"
    )

    log("")
    log("⏳ Waiting for both chains to start (this may take 2-3 minutes)...")

    # Wait for Chain 1
    if not wait_for_chain(1, 8080, 8081):
        log_and_echo("❌ Chain 1 failed to start within timeout")
        sys.exit(1)

    # Wait for Chain 2
    if not wait_for_chain(2, 8082, 8083):
        log_and_echo("❌ Chain 2 failed to start within timeout")
        sys.exit(1)

    log("")
    log("🔍 Verifying both chains...")

    # Verify both chains
    chain1_info = verify_chain(1, 8080)
    chain2_info = verify_chain(2, 8082)

    log("")
    log("🔗 Dual-Chain Endpoints:")
    log("   Chain 1:")
    log("     REST API:        http://127.0.0.1:8080")
    log("     Faucet:          http://127.0.0.1:8081")
    log("   Chain 2:")
    log("     REST API:        http://127.0.0.1:8082")
    log("     Faucet:          http://127.0.0.1:8083")

    log("")
    log("📋 Management Commands:")
    log(f"   Stop Chain 1:    docker-compose -f {common.PROJECT_ROOT}/testing-infra/connected-chain-apt/docker-compose-chain1.yml -p aptos-chain1 down")
    log(f"   Stop Chain 2:    docker-compose -f {common.PROJECT_ROOT}/testing-infra/connected-chain-apt/docker-compose-chain2.yml -p aptos-chain2 down")
    log(f"   Stop Both:       python3 {common.PROJECT_ROOT}/testing-infra/connected-chain-apt/stop_dual_chains.py")
    log(f"   Logs Chain 1:    docker-compose -f {common.PROJECT_ROOT}/testing-infra/connected-chain-apt/docker-compose-chain1.yml -p aptos-chain1 logs -f")
    log(f"   Logs Chain 2:    docker-compose -f {common.PROJECT_ROOT}/testing-infra/connected-chain-apt/docker-compose-chain2.yml -p aptos-chain2 logs -f")

    log("")
    log("🎉 Dual-chain setup complete!")
    log("   Both chains are running independently with different chain IDs")
    log("   Ready for cross-chain testing!")


if __name__ == "__main__":
    main()
