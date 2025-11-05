const hre = require("hardhat");

async function main() {
  const vaultAddress = process.env.VAULT_ADDRESS;
  const intentIdHex = process.env.INTENT_ID_EVM;
  const signatureHex = process.env.SIGNATURE_HEX;

  if (!vaultAddress || !intentIdHex || !signatureHex) {
    throw new Error("Missing required environment variables: VAULT_ADDRESS, INTENT_ID_EVM, SIGNATURE_HEX");
  }

  const signers = await hre.ethers.getSigners();
  const bob = signers[1];
  
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
    }
    process.exit(1);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

