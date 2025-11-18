//! Generic validator structures and CrossChainValidator definition
//!
//! This module contains shared validation structures and the CrossChainValidator struct definition
//! that are used across all flow types (inflow/outflow) and chain types (Move VM/EVM).

use serde::{Deserialize, Serialize};
use std::sync::Arc;

use crate::config::Config;
use crate::monitor::{RequestIntentEvent, FulfillmentEvent};

// ============================================================================
// VALIDATION DATA STRUCTURES
// ============================================================================

/// Result of cross-chain validation between a request intent and escrow event.
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
    /// Amount transferred
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

/// Cross-chain validator that ensures escrow deposits fulfill request intent conditions.
/// 
/// This validator performs comprehensive checks to ensure that deposits
/// made on the connected chain properly fulfill the requirements specified
/// in request intents created on the hub chain. It provides cryptographic approval
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
            .timeout(std::time::Duration::from_millis(config.verifier.validation_timeout_ms))
            .build()?;
        
        Ok(Self {
            config: Arc::new(config.clone()),
            client,
        })
    }
    
    /// Validates that a request intent is safe for escrow operations.
    /// 
    /// This function performs critical security checks to ensure that a request intent
    /// can be safely used for escrow operations. The most important check
    /// is verifying that the request intent is non-revocable.
    /// 
    /// # Arguments
    /// 
    /// * `request_intent` - The request intent event to validate
    /// 
    /// # Returns
    /// 
    /// * `Ok(ValidationResult)` - Validation result with detailed information
    /// * `Err(anyhow::Error)` - Validation failed due to error
    #[allow(dead_code)]
    pub async fn validate_request_intent_safety(&self, request_intent: &RequestIntentEvent) -> anyhow::Result<ValidationResult> {
        use tracing::info;
        
        info!("Validating request intent safety: {}", request_intent.intent_id);
        
        // CRITICAL SECURITY CHECK: Verify request intent is non-revocable
        if request_intent.revocable {
            return Ok(ValidationResult {
                valid: false,
                message: "Request intent is revocable - NOT safe for escrow operations".to_string(),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
        
        // Additional safety checks: verify request intent has not expired
        if request_intent.expiry_time < chrono::Utc::now().timestamp() as u64 {
            return Ok(ValidationResult {
                valid: false,
                message: "Request intent has expired".to_string(),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
        
        // All safety checks passed
        Ok(ValidationResult {
            valid: true,
            message: "Request intent is safe for escrow operations".to_string(),
            timestamp: chrono::Utc::now().timestamp() as u64,
        })
    }
    
    /// Validates that a fulfillment event satisfies the request intent requirements.
    /// 
    /// This function checks that:
    /// 1. The fulfilled amount matches the request intent's desired amount
    /// 2. The fulfilled metadata matches the request intent's desired metadata
    /// 3. The fulfillment occurred before the request intent expired
    /// 
    /// # Arguments
    /// 
    /// * `request_intent` - The request intent event from the hub chain
    /// * `fulfillment` - The fulfillment event from the hub chain
    /// 
    /// # Returns
    /// 
    /// * `Ok(ValidationResult)` - Validation result with detailed information
    /// * `Err(anyhow::Error)` - Validation failed due to error
    #[allow(dead_code)]
    pub async fn validate_fulfillment(
        &self,
        request_intent: &RequestIntentEvent,
        fulfillment: &FulfillmentEvent,
    ) -> anyhow::Result<ValidationResult> {
        use tracing::info;
        
        info!("Validating fulfillment for request intent: {}", request_intent.intent_id);
        
        // Verify fulfillment is for the same request intent
        if fulfillment.intent_id != request_intent.intent_id {
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "Fulfillment intent_id {} does not match request intent intent_id {}",
                    fulfillment.intent_id, request_intent.intent_id
                ),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
        
        // Validate the fulfillment's provided_amount matches the request intent's desired_amount
        if fulfillment.provided_amount != request_intent.desired_amount {
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "Fulfillment provided amount {} does not match request intent desired amount {}",
                    fulfillment.provided_amount, request_intent.desired_amount
                ),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
        
        // Validate the fulfillment's provided_metadata matches the request intent's desired_metadata
        if fulfillment.provided_metadata != request_intent.desired_metadata {
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "Fulfillment provided metadata '{}' does not match request intent desired metadata '{}'",
                    fulfillment.provided_metadata, request_intent.desired_metadata
                ),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
        
        // Validate fulfillment occurred before request intent expired
        if fulfillment.timestamp > request_intent.expiry_time {
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "Fulfillment occurred after request intent expiry (fulfillment: {}, expiry: {})",
                    fulfillment.timestamp, request_intent.expiry_time
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

