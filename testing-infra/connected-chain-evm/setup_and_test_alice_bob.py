#!/usr/bin/env python3
"""
Setup EVM chain and test Alice/Bob accounts.

This script:
1. Sets up Hardhat local EVM node
2. Verifies Alice and Bob accounts (Hardhat default accounts 0 and 1)
3. Tests basic transfers between Alice and Bob

Python equivalent of setup-and-test-alice-bob.sh
"""

import sys
import os
import time
from pathlib import Path

# Add parent directory to path to import common
sys.path.insert(0, str(Path(__file__).parent.parent))
from common import (
    setup_project_root, setup_logging, log, log_and_echo,
    run_command, PROJECT_ROOT, LOG_FILE
)


def is_evm_running() -> bool:
    """Check if EVM chain is running."""
    try:
        import requests
        response = requests.post(
            "http://127.0.0.1:8545",
            json={"jsonrpc": "2.0", "method": "eth_blockNumber", "params": [], "id": 1},
            timeout=2
        )
        return response.status_code == 200
    except:
        return False


def get_hardhat_address(account_index: int) -> str:
    """
    Get Hardhat account address using inline JavaScript.

    Args:
        account_index: Account index (0 for Alice, 1 for Bob)

    Returns:
        Account address or empty string on error
    """
    evm_dir = PROJECT_ROOT / "evm-intent-framework"

    js_code = f"""
const hre = require('hardhat');
(async () => {{
  const signers = await hre.ethers.getSigners();
  console.log(signers[{account_index}].address);
}})();
"""

    result = run_command(
        f"cd {evm_dir} && nix develop {PROJECT_ROOT} -c bash -c \"npx hardhat run - <<'EOF'\n{js_code}\nEOF\" 2>/dev/null",
        check=False
    )

    if result.returncode == 0:
        # Get last non-empty line
        lines = [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
        if lines:
            return lines[-1]

    return ""


def get_hardhat_balance(account_index: int) -> str:
    """
    Get Hardhat account balance in wei.

    Args:
        account_index: Account index (0 for Alice, 1 for Bob)

    Returns:
        Balance in wei as string
    """
    evm_dir = PROJECT_ROOT / "evm-intent-framework"

    js_code = f"""
const hre = require('hardhat');
(async () => {{
  const signers = await hre.ethers.getSigners();
  const balance = await hre.ethers.provider.getBalance(signers[{account_index}].address);
  console.log(balance.toString());
}})();
"""

    result = run_command(
        f"cd {evm_dir} && nix develop {PROJECT_ROOT} -c bash -c \"npx hardhat run - <<'EOF'\n{js_code}\nEOF\" 2>/dev/null",
        check=False
    )

    if result.returncode == 0:
        lines = [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]
        if lines:
            return lines[-1]

    return "0"


def test_transfer() -> bool:
    """
    Test transfer from Alice to Bob.

    Returns:
        True if transfer successful, False otherwise
    """
    evm_dir = PROJECT_ROOT / "evm-intent-framework"

    js_code = """
const hre = require('hardhat');
(async () => {
  const signers = await hre.ethers.getSigners();
  const alice = signers[0];
  const bob = signers[1];

  const amount = hre.ethers.parseEther('1.0'); // 1 ETH

  const tx = await alice.sendTransaction({
    to: bob.address,
    value: amount
  });

  await tx.wait();

  const bobBalanceAfter = await hre.ethers.provider.getBalance(bob.address);
  console.log('SUCCESS: Bob balance after transfer:', bobBalanceAfter.toString());
})();
"""

    result = run_command(
        f"cd {evm_dir} && nix develop {PROJECT_ROOT} -c bash -c \"npx hardhat run - <<'EOF'\n{js_code}\nEOF\" 2>&1",
        check=False
    )

    return "SUCCESS" in result.stdout or "SUCCESS" in result.stderr


def main():
    """Setup EVM chain and test Alice/Bob accounts."""
    # Setup project root and logging
    setup_project_root(Path(__file__))
    log_dir, log_file = setup_logging("setup-evm-alice-bob")

    log("🧪 Alice and Bob Account Testing - EVM CHAIN")
    log("==============================================")
    log_and_echo(f"📝 All output logged to: {log_file}")

    log("")
    log("% - - - - - - - - - - - SETUP - - - - - - - - - - - -")
    log("% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -")

    # Stop any existing Hardhat node
    log("🧹 Stopping any existing Hardhat node...")
    stop_script = PROJECT_ROOT / "testing-infra" / "connected-chain-evm" / "stop_evm_chain.py"
    run_command(f"python3 {stop_script}", check=False)

    # Start fresh Hardhat node
    log("🚀 Starting fresh Hardhat EVM node...")
    setup_script = PROJECT_ROOT / "testing-infra" / "connected-chain-evm" / "setup_evm_chain.py"
    result = run_command(f"python3 {setup_script}", check=False)

    if result.returncode != 0:
        log_and_echo("❌ Error: Failed to start EVM chain")
        os._exit(1)

    # Wait for node to be fully ready
    log("⏳ Waiting for node to be fully ready...")
    time.sleep(5)

    # Verify EVM chain is running
    log("🔍 Verifying EVM chain is running...")
    if not is_evm_running():
        log_and_echo("❌ Error: EVM chain failed to start on port 8545")
        os._exit(1)

    log("")
    log("% - - - - - - - - - - - ACCOUNTS - - - - - - - - - - - -")
    log("% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -")

    log("")
    log("📋 Hardhat Default Accounts:")
    log("   Alice = Account 0 (signer index 0)")
    log("   Bob   = Account 1 (signer index 1)")
    log("   Verifier = Account 1 (signer index 1)")

    # Get account addresses
    log("")
    log("🔍 Getting Alice and Bob addresses...")

    alice_address = get_hardhat_address(0)
    bob_address = get_hardhat_address(1)

    if not alice_address or not bob_address:
        log_and_echo("❌ Error: Failed to get account addresses")
        os._exit(1)

    log(f"   ✅ Alice (Account 0): {alice_address}")
    log(f"   ✅ Bob (Account 1):   {bob_address}")

    log("")
    log("% - - - - - - - - - - - BALANCES - - - - - - - - - - - -")
    log("% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -")

    # Check initial balances
    log("")
    log("💰 Checking initial balances...")

    alice_balance = get_hardhat_balance(0)
    bob_balance = get_hardhat_balance(1)

    log(f"   Alice balance: {alice_balance} wei (should be 10000 ETH = 10000000000000000000000 wei)")
    log(f"   Bob balance:   {bob_balance} wei (should be 10000 ETH = 10000000000000000000000 wei)")

    log("")
    log("% - - - - - - - - - - - TEST TRANSFER - - - - - - - - - - - -")
    log("% - - - - - - - - - - - - - - - - - - - - - - - - - - - - -")

    # Test transfer from Alice to Bob
    log("")
    log("🧪 Testing transfer from Alice to Bob...")

    if test_transfer():
        log("   ✅ Transfer successful!")
    else:
        log_and_echo("   ❌ Transfer failed!")
        os._exit(1)

    log("")
    log("🎉 All EVM chain setup and testing complete!")
    log("")
    log("📋 Summary:")
    log("   EVM Chain:     http://127.0.0.1:8545")
    log("   Chain ID:      31337")
    log(f"   Alice (Acc 0): {alice_address}")
    log(f"   Bob (Acc 1):   {bob_address}")
    log("")
    log("📋 Useful commands:")
    log(f"   Stop chain:    python3 {PROJECT_ROOT}/testing-infra/connected-chain-evm/stop_evm_chain.py")
    log("")
    log("✨ Script completed!")


if __name__ == "__main__":
    main()
