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
use serde::{Deserialize, Serialize};
use tracing::info;
use base64::{Engine as _, engine::general_purpose};

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
    /// Private key for signing operations
    signing_key: SigningKey,
    /// Public key for signature verification
    verifying_key: VerifyingKey,
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
        
        Ok(Self {
            signing_key,
            verifying_key,
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
}
