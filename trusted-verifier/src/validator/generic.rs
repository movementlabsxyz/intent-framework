//! Generic validator structures and CrossChainValidator definition
//!
//! This module contains shared validation structures and the CrossChainValidator struct definition
//! that are used across all flow types (inflow/outflow) and chain types (Move VM/EVM).

use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::sync::Arc;

use crate::config::Config;
use crate::monitor::{ChainType, FulfillmentEvent, IntentEvent};

// ============================================================================
// CHAIN TYPE UTILITIES
// ============================================================================

/// Normalizes an address by padding it to the expected length for the given chain type.
///
/// Move VM addresses can be serialized without leading zeros (e.g., 63 hex chars instead of 64),
/// so this function pads them to the expected length before validation or comparison.
///
/// # Arguments
///
/// * `address` - The address to normalize (with or without 0x prefix)
/// * `chain_type` - The chain type (determines expected address length)
///
/// # Returns
///
/// * `String` - The normalized address with 0x prefix, padded to expected length
pub fn normalize_address(address: &str, chain_type: ChainType) -> String {
    let address_no_prefix = address.strip_prefix("0x").unwrap_or(address);
    let expected_len = match chain_type {
        ChainType::Evm => 40, // 20 bytes = 40 hex chars
        ChainType::Mvm => 64, // 32 bytes = 64 hex chars
        ChainType::Svm => 64, // 32 bytes = 64 hex chars
    };

    if address_no_prefix.len() < expected_len {
        // Pad with leading zeros to expected length
        format!("0x{:0>width$}", address_no_prefix, width = expected_len)
    } else {
        // Ensure 0x prefix is present
        if address.starts_with("0x") {
            address.to_string()
        } else {
            format!("0x{}", address)
        }
    }
}

/// Determines the chain type from a chain ID by comparing it to configured chain IDs.
///
/// This function compares the provided chain ID against the configured EVM and MVM
/// chain IDs to determine which type of chain it represents. This is more reliable
/// than checking which config section is present, as the chain ID comes directly
/// from the intent.
///
/// # Arguments
///
/// * `chain_id` - The chain ID to look up
/// * `config` - The validator configuration containing chain ID mappings
///
/// # Returns
///
/// * `Ok(ChainType)` - The chain type (Evm or Mvm)
/// * `Err(anyhow::Error)` - Chain ID does not match any configured connected chain, or duplicate chain IDs detected
pub fn get_chain_type_from_chain_id(chain_id: u64, config: &Config) -> Result<ChainType> {
    // Validate that EVM and MVM chains don't have the same chain ID
    if let (Some(evm_config), Some(mvm_config)) = (&config.connected_chain_evm, &config.connected_chain_mvm)
    {
        if evm_config.chain_id == mvm_config.chain_id {
            return Err(anyhow::anyhow!(
                "Configuration error: EVM and MVM chains have the same chain ID {}. Each chain must have a unique chain ID.",
                evm_config.chain_id
            ));
        }
    }

    // Check if chain_id matches configured EVM chain
    if let Some(evm_config) = &config.connected_chain_evm {
        if evm_config.chain_id == chain_id {
            return Ok(ChainType::Evm);
        }
    }

    // Check if chain_id matches configured MVM chain
    if let Some(mvm_config) = &config.connected_chain_mvm {
        if mvm_config.chain_id == chain_id {
            return Ok(ChainType::Mvm);
        }
    }

    Err(anyhow::anyhow!(
        "Chain ID {} does not match any configured connected chain (EVM: {:?}, MVM: {:?})",
        chain_id,
        config.connected_chain_evm.as_ref().map(|c| c.chain_id),
        config.connected_chain_mvm.as_ref().map(|c| c.chain_id)
    ))
}

// ============================================================================
// ADDRESS VALIDATION UTILITIES
// ============================================================================

/// Validates that an address string matches the required format for the chain type.
///
/// EVM addresses must be exactly 20 bytes (40 hex chars after removing 0x prefix).
/// Move VM addresses must be exactly 32 bytes (64 hex chars after removing 0x prefix).
///
/// # Arguments
///
/// * `address` - Address string to validate (with or without 0x prefix)
/// * `chain_type` - The chain type (EVM or Move VM)
///
/// # Returns
///
/// * `Ok(())` - Address format is valid
/// * `Err(anyhow::Error)` - Address format is invalid
pub fn validate_address_format(address: &str, chain_type: ChainType) -> Result<()> {
    let address_no_prefix = address.strip_prefix("0x").unwrap_or(address);
    let address_len = address_no_prefix.len();

    match chain_type {
        ChainType::Evm => {
            // EVM addresses must be exactly 20 bytes (40 hex chars)
            if address_len != 40 {
                return Err(anyhow::anyhow!(
                    "Invalid EVM address format: expected 20 bytes (40 hex chars), got {} chars. Address: '{}'",
                    address_len, address
                ));
            }
        }
        ChainType::Mvm => {
            // Move VM addresses must be exactly 32 bytes (64 hex chars)
            if address_len != 64 {
                return Err(anyhow::anyhow!(
                    "Invalid Move VM address format: expected 32 bytes (64 hex chars), got {} chars. Address: '{}'",
                    address_len, address
                ));
            }
        }
        ChainType::Svm => {
            // Solana addresses are 32 bytes (64 hex chars), same as Move VM
            if address_len != 64 {
                return Err(anyhow::anyhow!(
                    "Invalid Solana address format: expected 32 bytes (64 hex chars), got {} chars. Address: '{}'",
                    address_len, address
                ));
            }
        }
    }

    // Validate that the address contains only valid hex characters
    if !address_no_prefix.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(anyhow::anyhow!(
            "Invalid address format: contains non-hexadecimal characters. Address: '{}'",
            address
        ));
    }

    Ok(())
}

// ============================================================================
// VALIDATION DATA STRUCTURES
// ============================================================================

/// Result of cross-chain validation between a intent and escrow event.
///
/// This structure contains the validation result and any relevant metadata
/// for approval or rejection decisions.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ValidationResult {
    /// Whether the validation passed
    pub valid: bool,
    /// Detailed reason for validation result
    pub message: String,
    /// Timestamp when validation was performed
    pub timestamp: u64,
}

/// Extracted parameters from a connected chain fulfillment transaction
#[derive(Debug, Clone)]
pub struct FulfillmentTransactionParams {
    /// Intent ID extracted from transaction
    pub intent_id: String,
    /// Recipient address (where tokens were sent)
    pub recipient: String,
    /// Amount transferred (u64, matching Move contract constraint)
    pub amount: u64,
    /// Solver address (transaction sender)
    pub solver: String,
    /// Token metadata/address
    ///
    /// Note: Currently extracted but not used in validation. Kept for completeness
    /// and potential future validation logic.
    #[allow(dead_code)]
    pub token_metadata: String,
}

// ============================================================================
// CROSS-CHAIN VALIDATOR STRUCTURE
// ============================================================================

/// Cross-chain validator that ensures escrow deposits fulfill intent conditions.
///
/// This validator performs comprehensive checks to ensure that deposits
/// made on the connected chain properly fulfill the requirements specified
/// in intents created on the hub chain. It provides cryptographic approval
/// signatures for valid fulfillments.
pub struct CrossChainValidator {
    /// Service configuration
    pub config: Arc<Config>,
    /// HTTP client for blockchain communication
    #[allow(dead_code)]
    pub client: reqwest::Client,
}

impl CrossChainValidator {
    /// Returns a reference to the validator's configuration
    pub fn config(&self) -> &Config {
        &self.config
    }

    /// Creates a new cross-chain validator with the given configuration.
    ///
    /// This function initializes HTTP clients for communication with both
    /// chains and prepares the validator for operation.
    ///
    /// # Arguments
    ///
    /// * `config` - Service configuration containing chain URLs and timeouts
    ///
    /// # Returns
    ///
    /// * `Ok(CrossChainValidator)` - Successfully created validator
    /// * `Err(anyhow::Error)` - Failed to create validator
    pub async fn new(config: &Config) -> anyhow::Result<Self> {
        // Create HTTP client with configured timeout
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_millis(
                config.verifier.validation_timeout_ms,
            ))
            .build()?;

        Ok(Self {
            config: Arc::new(config.clone()),
            client,
        })
    }

    /// Validates that a intent is safe for escrow operations.
    ///
    /// This function performs critical security checks to ensure that a intent
    /// can be safely used for escrow operations. The most important check
    /// is verifying that the intent is non-revocable.
    ///
    /// # Arguments
    ///
    /// * `intent` - The intent event to validate
    ///
    /// # Returns
    ///
    /// * `Ok(ValidationResult)` - Validation result with detailed information
    /// * `Err(anyhow::Error)` - Validation failed due to error
    #[allow(dead_code)]
    pub async fn validate_intent_safety(
        &self,
        intent: &IntentEvent,
    ) -> anyhow::Result<ValidationResult> {
        use tracing::info;

        info!(
            "Validating intent safety: {}",
            intent.intent_id
        );

        // CRITICAL SECURITY CHECK: Verify intent is non-revocable
        if intent.revocable {
            return Ok(ValidationResult {
                valid: false,
                message: "Request-intent is revocable - NOT safe for escrow operations".to_string(),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }

        // Additional safety checks: verify intent has not expired
        if intent.expiry_time < chrono::Utc::now().timestamp() as u64 {
            return Ok(ValidationResult {
                valid: false,
                message: "Request-intent has expired".to_string(),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }

        // All safety checks passed
        Ok(ValidationResult {
            valid: true,
            message: "Request-intent is safe for escrow operations".to_string(),
            timestamp: chrono::Utc::now().timestamp() as u64,
        })
    }

    /// Validates that a fulfillment event satisfies the intent requirements.
    ///
    /// This function checks that:
    /// 1. The fulfilled amount matches the intent's desired amount
    /// 2. The fulfilled metadata matches the intent's desired metadata
    /// 3. The fulfillment occurred before the intent expired
    ///
    /// # Arguments
    ///
    /// * `intent` - The intent event from the hub chain
    /// * `fulfillment` - The fulfillment event from the hub chain
    ///
    /// # Returns
    ///
    /// * `Ok(ValidationResult)` - Validation result with detailed information
    /// * `Err(anyhow::Error)` - Validation failed due to error
    #[allow(dead_code)]
    pub async fn validate_fulfillment(
        &self,
        intent: &IntentEvent,
        fulfillment: &FulfillmentEvent,
    ) -> anyhow::Result<ValidationResult> {
        use tracing::info;

        info!(
            "Validating fulfillment for intent: {}",
            intent.intent_id
        );

        // Verify fulfillment is for the same intent
        if fulfillment.intent_id != intent.intent_id {
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "Fulfillment intent_id {} does not match intent intent_id {}",
                    fulfillment.intent_id, intent.intent_id
                ),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }

        // Validate the fulfillment's provided_amount matches the intent's desired_amount
        // Both are u64 (matching Move contract constraint)
        if fulfillment.provided_amount != intent.desired_amount {
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "Fulfillment provided amount {} does not match intent desired amount {}",
                    fulfillment.provided_amount, intent.desired_amount
                ),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }

        // Validate the fulfillment's provided_metadata matches the intent's desired_metadata
        if fulfillment.provided_metadata != intent.desired_metadata {
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "Fulfillment provided metadata '{}' does not match intent desired metadata '{}'",
                    fulfillment.provided_metadata, intent.desired_metadata
                ),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }

        // Validate fulfillment occurred before intent expired
        if fulfillment.timestamp > intent.expiry_time {
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "Fulfillment occurred after intent expiry (fulfillment: {}, expiry: {})",
                    fulfillment.timestamp, intent.expiry_time
                ),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }

        // All validations passed
        Ok(ValidationResult {
            valid: true,
            message: "Fulfillment validation successful".to_string(),
            timestamp: chrono::Utc::now().timestamp() as u64,
        })
    }

    /// Validates cross-chain conditions between hub and connected chains.
    ///
    /// This function performs validation of conditions that span both chains,
    /// ensuring consistency and proper state management across the cross-chain
    /// operation.
    ///
    /// # Arguments
    ///
    /// * `hub_condition` - Condition data from the hub chain
    /// * `connected_condition` - Condition data from the connected chain
    ///
    /// # Returns
    ///
    /// * `Ok(ValidationResult)` - Validation result with detailed information
    /// * `Err(anyhow::Error)` - Validation failed due to error
    #[allow(dead_code)]
    pub async fn validate_cross_chain_conditions(
        &self,
        _hub_condition: &str,
        _connected_condition: &str,
    ) -> anyhow::Result<ValidationResult> {
        use tracing::info;

        info!("Validating cross-chain conditions");

        // TODO: Implement actual cross-chain validation logic
        // This could involve:
        // - Checking balances and states across both chains
        // - Verifying transaction consistency
        // - Validating cryptographic proofs
        // - Ensuring atomicity of cross-chain operations

        Ok(ValidationResult {
            valid: true,
            message: "Cross-chain conditions validated successfully".to_string(),
            timestamp: chrono::Utc::now().timestamp() as u64,
        })
    }
}
