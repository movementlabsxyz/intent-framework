const hre = require("hardhat");

async function main() {
  const vaultAddress = process.env.VAULT_ADDRESS;
  const intentIdHex = process.env.INTENT_ID_EVM;
  const signatureHex = process.env.SIGNATURE_HEX;

  if (!vaultAddress || !intentIdHex || !signatureHex) {
    throw new Error("Missing required environment variables: VAULT_ADDRESS, INTENT_ID_EVM, SIGNATURE_HEX");
  }

  const signers = await hre.ethers.getSigners();
  const bob = signers[2]; // Bob (Account 2)
  
  // Use contract factory to get ABI, then create contract instance directly
  // This avoids the name resolution issue with getContractAt on localhost network
  const IntentVaultFactory = await hre.ethers.getContractFactory("IntentVault", bob);
  const vault = IntentVaultFactory.attach(vaultAddress);
  
  // Debug: Log the intentId values
  console.log("Debug info:");
  console.log("  IntentIdHex (string):", intentIdHex);
  console.log("  VaultAddress:", vaultAddress);
  
  // Convert intentId - use BigInt directly like other scripts
  const intentId = BigInt(intentIdHex);
  console.log("  IntentId (BigInt):", intentId.toString());
  
  const approvalValue = 1;
  const signature = `0x${signatureHex}`;
  
  // Validate signature format
  if (signatureHex.length !== 130) {
    throw new Error(`Invalid signature hex length: expected 130 chars (65 bytes), got ${signatureHex.length}`);
  }
  
  // Verify signature is valid hex
  if (!/^[0-9a-fA-F]+$/.test(signatureHex)) {
    throw new Error(`Invalid signature hex format: contains non-hex characters`);
  }
  
  // Check signature byte length (should be 65 bytes = 130 hex chars)
  const signatureBytes = Buffer.from(signatureHex, 'hex');
  if (signatureBytes.length !== 65) {
    throw new Error(`Invalid signature byte length: expected 65 bytes, got ${signatureBytes.length}`);
  }
  
  // Extract r, s, v from signature
  const r = signatureBytes.slice(0, 32);
  const s = signatureBytes.slice(32, 64);
  const v = signatureBytes[64];
  console.log("  Signature validation:");
  console.log("    r (first 4 bytes):", r.slice(0, 4).toString('hex'));
  console.log("    s (first 4 bytes):", s.slice(0, 4).toString('hex'));
  console.log("    v:", v);
  
  // Validate v is 27 or 28
  if (v !== 27 && v !== 28) {
    throw new Error(`Invalid signature v value: expected 27 or 28, got ${v}`);
  }
  
  // Verify signature matches the expected message format
  // Message should be: keccak256(abi.encodePacked(intentId, approvalValue))
  const { ethers } = hre;
  
  // Create the message hash (same as contract does)
  const messageHash = ethers.keccak256(
    ethers.solidityPacked(["uint256", "uint8"], [intentId, approvalValue])
  );
  
  // Apply Ethereum signed message prefix (same as contract does)
  const ethMessagePrefix = "\x19Ethereum Signed Message:\n32";
  const prefixedMessage = ethers.concat([
    ethers.toUtf8Bytes(ethMessagePrefix),
    ethers.getBytes(messageHash)
  ]);
  const ethSignedMessageHash = ethers.keccak256(prefixedMessage);
  
  // Recover signer using ecrecover (same logic as contract)
  let recoveredSigner;
  try {
    // Use ethers' recoverAddress which does ecrecover internally
    recoveredSigner = ethers.recoverAddress(ethers.getBytes(ethSignedMessageHash), signature);
  } catch (recoverError) {
    console.error("Failed to recover signer from signature:", recoverError.message);
    throw new Error(`Invalid signature: could not recover signer. ${recoverError.message}`);
  }
  
  // Get verifier address from contract
  const verifierAddress = await vault.verifier();
  console.log("  Signature verification:");
  console.log("    Message hash:", messageHash);
  console.log("    ETH signed message hash:", ethSignedMessageHash);
  console.log("    Recovered signer:", recoveredSigner);
  console.log("    Contract verifier:", verifierAddress);
  console.log("    Signatures match:", recoveredSigner.toLowerCase() === verifierAddress.toLowerCase());
  
  if (recoveredSigner.toLowerCase() !== verifierAddress.toLowerCase()) {
    throw new Error(`Signature verification failed: recovered signer ${recoveredSigner} does not match verifier ${verifierAddress}`);
  }
  
  try {
    // Check vault state before claim
    let vaultBefore;
    try {
      vaultBefore = await vault.getVault(intentId);
      console.log("Vault state before claim:");
      console.log("  Maker:", vaultBefore.maker);
      console.log("  Amount:", vaultBefore.amount.toString());
      console.log("  IsClaimed:", vaultBefore.isClaimed);
      
      if (vaultBefore.maker === "0x0000000000000000000000000000000000000000") {
        throw new Error(`Vault does not exist for intentId: ${intentIdHex}`);
      }
      
      if (vaultBefore.amount === 0n) {
        throw new Error("Vault has no funds to claim");
      }
      
      if (vaultBefore.isClaimed) {
        throw new Error("Vault already claimed");
      }
    } catch (getVaultError) {
      if (getVaultError.message.includes("could not decode result data")) {
        throw new Error(`Vault does not exist for intentId: ${intentIdHex}. The vault may not have been initialized or the intentId format is incorrect.`);
      }
      throw getVaultError;
    }

    // Log claim parameters before attempting
    console.log("Attempting claim with:");
    console.log("  IntentId:", intentId.toString());
    console.log("  ApprovalValue:", approvalValue);
    console.log("  Signature length:", signature.length, "bytes");
    console.log("  Signature (first 20 chars):", signature.substring(0, 20) + "...");

    // Estimate gas first to catch errors early
    try {
      const gasEstimate = await vault.claim.estimateGas(intentId, approvalValue, signature);
      console.log("Gas estimate:", gasEstimate.toString());
    } catch (estimateError) {
      console.error("⚠️ Gas estimation failed - transaction will likely fail:");
      console.error("  Error message:", estimateError.message);
      if (estimateError.reason) {
        console.error("  Reason:", estimateError.reason);
      }
      if (estimateError.data) {
        console.error("  Error data:", estimateError.data);
        // Try to decode error selector
        if (estimateError.data.length >= 10) {
          const errorSelector = estimateError.data.slice(0, 10);
          console.error("  Error selector:", errorSelector);
        }
      }
      // Try to get more details from the error
      if (estimateError.error) {
        console.error("  Nested error:", estimateError.error);
      }
      // Re-throw to show it's a gas estimation failure
      throw new Error(`Gas estimation failed: ${estimateError.message}. ${estimateError.reason || ''}`);
    }

    const tx = await vault.claim(intentId, approvalValue, signature);
    const receipt = await tx.wait();
    
    if (!receipt.status) {
      throw new Error(`Transaction reverted: ${receipt.hash}`);
    }
    
    // Check vault state after claim
    const vaultAfter = await vault.getVault(intentId);
    console.log("Vault state after claim:");
    console.log("  Amount:", vaultAfter.amount.toString());
    console.log("  IsClaimed:", vaultAfter.isClaimed);
    
    if (!vaultAfter.isClaimed) {
      throw new Error("Vault was not marked as claimed after transaction");
    }
    
    console.log("Claim transaction hash:", receipt.hash);
    console.log("Escrow released successfully!");
  } catch (error) {
    console.error("Error claiming escrow:", error.message);
    if (error.reason) {
      console.error("Reason:", error.reason);
    }
    if (error.data) {
      console.error("Error data:", error.data);
      // Try to decode error selector if present
      if (error.data.length >= 10) {
        const errorSelector = error.data.slice(0, 10);
        console.error("Error selector:", errorSelector);
      }
    }
    // Log nested error if present
    if (error.error) {
      console.error("Nested error:", error.error);
    }
    // Log full error details for debugging
    console.error("Error details:", {
      message: error.message,
      reason: error.reason,
      data: error.data,
      code: error.code,
      action: error.action
    });
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

