//! Cryptographic Operations Module
//! 
//! This module handles all cryptographic operations for the trusted verifier service,
//! including Ed25519 key generation, message signing, signature verification, and
//! secure random number generation. It provides the cryptographic foundation
//! for secure cross-chain validation and approval signatures.
//! 
//! ## Security Requirements
//! 
//! ⚠️ **CRITICAL**: All cryptographic operations must use secure random number generation
//! and proper key management practices. Private keys must never be exposed or logged.

use anyhow::Result;
use ed25519_dalek::{SigningKey, VerifyingKey, Signature, Signer};
use k256::{
    ecdsa::{SigningKey as EcdsaSigningKey, Signature as EcdsaSignature, VerifyingKey as EcdsaVerifyingKey},
};
use sha3::{Keccak256, Digest};
use serde::{Deserialize, Serialize};
use tracing::info;
use base64::{Engine as _, engine::general_purpose};
use hex;

use crate::config::Config;

// ============================================================================
// CRYPTOGRAPHIC DATA STRUCTURES
// ============================================================================

/// Cryptographic signature for approval/rejection decisions.
/// 
/// This structure contains a digital signature along with the approval decision
/// and timestamp. It's used to cryptographically authorize escrow releases
/// and other critical operations.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApprovalSignature {
    /// Approval value: 1 = approve, 0 = reject
    pub approval_value: u64,
    /// Base64-encoded Ed25519 signature
    pub signature: String,
    /// Timestamp when signature was created
    pub timestamp: u64,
}

// ============================================================================
// CRYPTOGRAPHIC SERVICE IMPLEMENTATION
// ============================================================================

/// Cryptographic service that handles all crypto operations for the verifier.
/// 
/// This service provides secure key generation, message signing, signature
/// verification, and other cryptographic operations required for secure
/// cross-chain validation and approval signatures.
pub struct CryptoService {
    /// Private key for signing operations (Ed25519 for Aptos)
    signing_key: SigningKey,
    /// Public key for signature verification (Ed25519 for Aptos)
    verifying_key: VerifyingKey,
    /// ECDSA signing key for EVM operations (secp256k1)
    /// Derived from Ed25519 private key by taking first 32 bytes
    ecdsa_signing_key: EcdsaSigningKey,
}

impl CryptoService {
    /// Creates a new cryptographic service with the given configuration.
    /// 
    /// This function initializes the cryptographic service with either
    /// a provided key pair from configuration or generates a new one
    /// if none is provided.
    /// 
    /// # Arguments
    /// 
    /// * `config` - Service configuration containing key information
    /// 
    /// # Returns
    /// 
    /// * `Ok(CryptoService)` - Successfully created crypto service
    /// * `Err(anyhow::Error)` - Failed to create crypto service
    pub fn new(config: &Config) -> Result<Self> {
        // Load private key from config
        let private_key_b64 = &config.verifier.private_key;
        let private_key_bytes = general_purpose::STANDARD.decode(private_key_b64)?;
        
        if private_key_bytes.len() != 32 {
            return Err(anyhow::anyhow!("Invalid private key length: expected 32 bytes, got {}", private_key_bytes.len()));
        }
        
        let secret_key_bytes: [u8; 32] = private_key_bytes.try_into()
            .map_err(|_| anyhow::anyhow!("Failed to convert private key to array"))?;
        
        let signing_key = SigningKey::from_bytes(&secret_key_bytes);
        let verifying_key = signing_key.verifying_key();
        
        // Verify public key matches config
        let expected_public_key_b64 = &config.verifier.public_key;
        let actual_public_key_b64 = general_purpose::STANDARD.encode(verifying_key.to_bytes());
        
        if actual_public_key_b64 != *expected_public_key_b64 {
            return Err(anyhow::anyhow!(
                "Public key mismatch: config has {}, but private key corresponds to {}",
                expected_public_key_b64,
                actual_public_key_b64
            ));
        }
        
        info!("Crypto service initialized with key pair from config");
        
        // Derive ECDSA key from Ed25519 private key for EVM compatibility
        // Use the Ed25519 private key bytes as seed for ECDSA (taking first 32 bytes)
        let ecdsa_secret_bytes: [u8; 32] = secret_key_bytes;
        let ecdsa_signing_key = EcdsaSigningKey::from_bytes(&ecdsa_secret_bytes.into())
            .map_err(|e| anyhow::anyhow!("Failed to create ECDSA signing key: {}", e))?;
        
        Ok(Self {
            signing_key,
            verifying_key,
            ecdsa_signing_key,
        })
    }
    
    /// Creates an approval signature for intent fulfillment validation.
    /// 
    /// This function creates a cryptographic signature that approves or rejects
    /// the fulfillment of an intent. The signature can be verified by external
    /// systems to authorize escrow releases.
    /// 
    /// # Arguments
    /// 
    /// * `approve` - Whether to approve (true) or reject (false) the fulfillment
    /// 
    /// # Returns
    /// 
    /// * `Ok(ApprovalSignature)` - Cryptographic approval signature
    /// * `Err(anyhow::Error)` - Failed to create signature
    pub fn create_approval_signature(&self, approve: bool) -> Result<ApprovalSignature> {
        let approval_value: u64 = if approve { 1 } else { 0 };
        
        // Create signature over the approval value using BCS encoding (to match Move contract)
        let message = bcs::to_bytes(&approval_value)?;
        let signature = self.signing_key.sign(&message);
        
        info!("Created {} signature for approval value: {}", 
              if approve { "approval" } else { "rejection" }, approval_value);
        
        Ok(ApprovalSignature {
            approval_value,
            signature: general_purpose::STANDARD.encode(signature.to_bytes()),
            timestamp: chrono::Utc::now().timestamp() as u64,
        })
    }
    
    /// Creates an approval signature for escrow completion.
    /// 
    /// This function creates a cryptographic signature that approves or rejects
    /// the completion of an escrow operation. This signature is used to
    /// authorize the release of escrow funds.
    /// 
    /// # Arguments
    /// 
    /// * `approve` - Whether to approve (true) or reject (false) the escrow completion
    /// 
    /// # Returns
    /// 
    /// * `Ok(ApprovalSignature)` - Cryptographic approval signature
    /// * `Err(anyhow::Error)` - Failed to create signature
    #[allow(dead_code)]
    pub fn create_escrow_approval_signature(&self, approve: bool) -> Result<ApprovalSignature> {
        let approval_value: u64 = if approve { 1 } else { 0 };
        
        // Create signature over the approval value using BCS encoding (to match Move contract)
        let message = bcs::to_bytes(&approval_value)?;
        let signature = self.signing_key.sign(&message);
        
        info!("Created {} signature for escrow completion", 
              if approve { "approval" } else { "rejection" });
        
        Ok(ApprovalSignature {
            approval_value,
            signature: general_purpose::STANDARD.encode(signature.to_bytes()),
            timestamp: chrono::Utc::now().timestamp() as u64,
        })
    }
    
    /// Verifies a cryptographic signature against a message.
    /// 
    /// This function validates that a signature was created by the holder
    /// of the private key corresponding to the verifier's public key.
    /// 
    /// # Arguments
    /// 
    /// * `message` - The message that was signed
    /// * `signature` - The base64-encoded signature to verify
    /// 
    /// # Returns
    /// 
    /// * `Ok(bool)` - True if signature is valid, false otherwise
    /// * `Err(anyhow::Error)` - Failed to verify signature
    #[allow(dead_code)]
    pub fn verify_signature(&self, message: &[u8], signature: &str) -> Result<bool> {
        // Decode the base64 signature
        let signature_bytes = general_purpose::STANDARD.decode(signature)?;
        let signature_bytes: [u8; 64] = signature_bytes.try_into().map_err(|_| anyhow::anyhow!("Invalid signature length"))?;
        let signature = Signature::from_bytes(&signature_bytes);
        
        // Verify the signature using Ed25519
        match self.verifying_key.verify_strict(message, &signature) {
            Ok(_) => Ok(true),
            Err(_) => Ok(false),
        }
    }
    
    /// Returns the public key for external signature verification.
    /// 
    /// This function provides access to the verifier's public key,
    /// which can be used by external systems to verify signatures
    /// created by this verifier.
    /// 
    /// # Returns
    /// 
    /// The public key encoded as a base64 string
    pub fn get_public_key(&self) -> String {
        general_purpose::STANDARD.encode(self.verifying_key.to_bytes())
    }
    
    /// Creates an ECDSA signature for EVM escrow release.
    /// 
    /// This function creates an ECDSA signature compatible with Ethereum/EVM
    /// for releasing escrow funds. The message format is:
    /// keccak256(abi.encodePacked(intentId, approvalValue))
    /// 
    /// Then applies Ethereum signed message format:
    /// keccak256("\x19Ethereum Signed Message:\n32" || messageHash)
    /// 
    /// # Arguments
    /// 
    /// * `intent_id` - The intent ID as a hex string (without 0x prefix)
    /// * `approval_value` - Approval value: 1 = approve, 0 = reject
    /// 
    /// # Returns
    /// 
    /// * `Ok(Vec<u8>)` - ECDSA signature bytes (65 bytes: r || s || v)
    /// * `Err(anyhow::Error)` - Failed to create signature
    pub fn create_evm_approval_signature(&self, intent_id: &str, approval_value: u8) -> Result<Vec<u8>> {
        // Remove 0x prefix if present
        let intent_id_hex = intent_id.strip_prefix("0x").unwrap_or(intent_id);
        
        // Convert hex string to bytes (intent_id should be 32 bytes)
        let intent_id_bytes = hex::decode(intent_id_hex)
            .map_err(|e| anyhow::anyhow!("Invalid intent_id hex: {}", e))?;
        
        // Pad intent_id to 32 bytes if needed (left-pad with zeros)
        let mut intent_id_padded = [0u8; 32];
        if intent_id_bytes.len() <= 32 {
            intent_id_padded[32 - intent_id_bytes.len()..].copy_from_slice(&intent_id_bytes);
        } else {
            return Err(anyhow::anyhow!("Intent ID too long: {} bytes", intent_id_bytes.len()));
        }
        
        // Create message: abi.encodePacked(intentId, approvalValue)
        let mut message = Vec::with_capacity(33);
        message.extend_from_slice(&intent_id_padded);
        message.push(approval_value);
        
        // Hash with keccak256
        let mut hasher = Keccak256::new();
        hasher.update(&message);
        let message_hash = hasher.finalize();
        
        // Apply Ethereum signed message prefix
        // keccak256("\x19Ethereum Signed Message:\n32" || messageHash)
        let prefix = b"\x19Ethereum Signed Message:\n32";
        let mut prefixed_message = Vec::with_capacity(prefix.len() + 32);
        prefixed_message.extend_from_slice(prefix);
        prefixed_message.extend_from_slice(&message_hash);
        
        let mut prefixed_hasher = Keccak256::new();
        prefixed_hasher.update(&prefixed_message);
        let final_hash = prefixed_hasher.finalize();
        
        // Convert GenericArray to [u8; 32] for signing
        let hash_array: [u8; 32] = final_hash.into();
        
        // Sign with ECDSA using precomputed hash (creates compact signature: r || s, 64 bytes)
        use k256::ecdsa::signature::hazmat::PrehashSigner;
        let signature: EcdsaSignature = self.ecdsa_signing_key.sign_prehash(&hash_array)
            .map_err(|e| anyhow::anyhow!("Failed to sign precomputed hash: {}", e))?;
        
        // Extract r and s from signature (each 32 bytes, total 64 bytes)
        let sig_bytes = signature.to_bytes();
        if sig_bytes.len() != 64 {
            return Err(anyhow::anyhow!("Invalid signature length: expected 64 bytes, got {}", sig_bytes.len()));
        }
        let r = &sig_bytes[..32];
        let s = &sig_bytes[32..64];
        
        // Calculate recovery ID by trying both 0 and 1
        // The recovery ID determines which public key can recover from the signature
        let verifying_key = self.ecdsa_signing_key.verifying_key();
        let public_key_point = verifying_key.to_encoded_point(false);
        let public_key_bytes = public_key_point.as_bytes();
        
        // Try recovery ID 0
        let recovery_id_0 = k256::ecdsa::RecoveryId::try_from(0u8).unwrap();
        let recovery_id = if let Ok(recovered) = EcdsaVerifyingKey::recover_from_prehash(&hash_array, &signature, recovery_id_0) {
            let recovered_point = recovered.to_encoded_point(false);
            if recovered_point.as_bytes() == public_key_bytes {
                0u8
            } else {
                1u8
            }
        } else {
            // If recovery with ID 0 fails, try ID 1
            1u8
        };
        
        // Convert recovery ID to Ethereum format (27 or 28)
        let v = recovery_id + 27;
        
        // Construct final signature: r || s || v (65 bytes total)
        let mut final_sig = Vec::with_capacity(65);
        final_sig.extend_from_slice(r);
        final_sig.extend_from_slice(s);
        final_sig.push(v);
        
        info!("Created ECDSA signature for EVM escrow release (intent_id: {}, approval_value: {})", 
              intent_id, approval_value);
        
        Ok(final_sig)
    }
    
    /// Derives the Ethereum address from the ECDSA public key.
    /// 
    /// The Ethereum address is computed as:
    /// keccak256(uncompressed_public_key)[12:32] (last 20 bytes)
    /// 
    /// # Returns
    /// 
    /// * `Ok(String)` - Ethereum address as hex string (with 0x prefix)
    /// * `Err(anyhow::Error)` - Failed to derive address
    #[allow(dead_code)]
    pub fn get_ethereum_address(&self) -> Result<String> {
        let verifying_key = self.ecdsa_signing_key.verifying_key();
        let public_key_point = verifying_key.to_encoded_point(false); // Uncompressed format
        let public_key_bytes = public_key_point.as_bytes();
        
        // Remove the 0x04 prefix (uncompressed point indicator) - we want just the coordinates
        // Uncompressed format: 0x04 || x (32 bytes) || y (32 bytes) = 65 bytes total
        if public_key_bytes.len() != 65 || public_key_bytes[0] != 0x04 {
            return Err(anyhow::anyhow!("Invalid public key format: expected 65 bytes with 0x04 prefix"));
        }
        
        // Hash the public key (without the 0x04 prefix)
        let mut hasher = Keccak256::new();
        hasher.update(&public_key_bytes[1..]); // Skip the 0x04 prefix
        let hash = hasher.finalize();
        
        // Ethereum address is the last 20 bytes of the hash
        let address_bytes = &hash[12..32];
        let address_hex = format!("0x{}", hex::encode(address_bytes));
        
        Ok(address_hex)
    }
}
