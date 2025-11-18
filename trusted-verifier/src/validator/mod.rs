//! Cross-Chain Validation Module
//! 
//! This module handles cross-chain validation logic, ensuring that escrow deposits
//! on the connected chain properly fulfill the conditions specified in intents
//! created on the hub chain. It provides cryptographic validation and approval
//! mechanisms for secure cross-chain operations.
//! 
//! ## Security Requirements
//! 
//! **CRITICAL**: All validations must verify that escrow intents are **non-revocable** 
//! (`revocable = false`) before issuing any approval signatures.

use anyhow::Result;
use serde::{Deserialize, Serialize};
use tracing::info;

use crate::config::Config;
use crate::monitor::{RequestIntentEvent, EscrowEvent, FulfillmentEvent, ChainType};

// Chain-specific modules
pub mod aptos;
pub mod evm;

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

// ============================================================================
// CROSS-CHAIN VALIDATOR IMPLEMENTATION
// ============================================================================

/// Cross-chain validator that ensures escrow deposits fulfill request intent conditions.
/// 
/// This validator performs comprehensive checks to ensure that deposits
/// made on the connected chain properly fulfill the requirements specified
/// in request intents created on the hub chain. It provides cryptographic approval
/// signatures for valid fulfillments.
pub struct CrossChainValidator {
    /// Service configuration
    config: std::sync::Arc<Config>,
    /// HTTP client for blockchain communication
    #[allow(dead_code)]
    client: reqwest::Client,
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
    pub async fn new(config: &Config) -> Result<Self> {
        // Create HTTP client with configured timeout
        let client = reqwest::Client::builder()
            .timeout(std::time::Duration::from_millis(config.verifier.validation_timeout_ms))
            .build()?;
        
        Ok(Self {
            config: std::sync::Arc::new(config.clone()),
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
    pub async fn validate_request_intent_safety(&self, request_intent: &RequestIntentEvent) -> Result<ValidationResult> {
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
    
    /// Validates fulfillment of request intent conditions on the connected chain.
    /// 
    /// This function performs comprehensive validation to ensure that:
    /// 1. The request intent has a connected_chain_id (required for escrow validation)
    /// 2. The escrow's offered_amount matches the hub request intent's offered_amount
    /// 3. The escrow's offered_metadata matches the hub request intent's offered_metadata
    /// 4. The escrow's chain_id matches the hub request intent's connected_chain_id
    /// 5. The escrow's desired_amount is 0 (escrow only holds offered funds, requirement is in hub request intent)
    /// 6. The escrow's reserved_solver matches the hub request intent's solver (with chain-specific validation)
    /// 
    /// # Arguments
    /// 
    /// * `request_intent_event` - The request intent event from the hub chain
    /// * `escrow_event` - The escrow event from the connected chain
    /// 
    /// # Returns
    /// 
    /// * `Ok(ValidationResult)` - Validation result with detailed information
    /// * `Err(anyhow::Error)` - Validation failed due to error
    pub async fn validate_request_intent_fulfillment(
        &self,
        request_intent_event: &RequestIntentEvent,
        escrow_event: &EscrowEvent,
    ) -> Result<ValidationResult> {
        info!("Validating request intent fulfillment for request intent: {}, escrow: {}", 
              request_intent_event.intent_id, escrow_event.escrow_id);
        
        // Validate that request intent has connected_chain_id (required for escrow validation)
        if request_intent_event.connected_chain_id.is_none() {
            return Ok(ValidationResult {
                valid: false,
                message: "Request intent must specify connected_chain_id for escrow validation".to_string(),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
        
        // Validate the escrow's offered_amount matches the specified offered_amount in the hub request intent
        if escrow_event.offered_amount != request_intent_event.offered_amount {
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "Escrow offered amount {} does not match hub request intent offered amount {}",
                    escrow_event.offered_amount, request_intent_event.offered_amount
                ),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
        
        // Validate the escrow's offered_metadata matches the specified offered_metadata in the hub request intent
        if escrow_event.offered_metadata != request_intent_event.offered_metadata {
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "Escrow offered metadata '{}' does not match hub request intent offered metadata '{}'",
                    escrow_event.offered_metadata, request_intent_event.offered_metadata
                ),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
        
        // Validate the escrow's chain_id matches the specified offered_chain_id in the hub request intent
        // Note: offered_chain_id from Move event is stored as connected_chain_id in RequestIntentEvent.
        // The escrow_event.chain_id is set by the verifier based on which monitor discovered it (from config),
        // so we can trust it for validation.
        if let Some(intent_offered_chain_id) = request_intent_event.connected_chain_id {
            if escrow_event.chain_id != intent_offered_chain_id {
                return Ok(ValidationResult {
                    valid: false,
                    message: format!(
                        "Escrow chain_id {} does not match hub request intent offered_chain_id {}. Escrow was discovered on chain {} but intent specifies chain {}",
                        escrow_event.chain_id, intent_offered_chain_id, escrow_event.chain_id, intent_offered_chain_id
                    ),
                    timestamp: chrono::Utc::now().timestamp() as u64,
                });
            }
        }
        
        // Validate that escrow's desired_amount is 0 (escrow only holds offered funds, requirement is in hub request intent)
        if escrow_event.desired_amount != 0 {
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "Escrow desired amount must be 0, but got {}. Escrow only holds offered funds; the actual requirement is specified in the hub request intent",
                    escrow_event.desired_amount
                ),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
        
        // Note: We don't validate escrow's desired_metadata because it's a placeholder.
        // The actual requirement is the hub request intent's desired_metadata, which the solver
        // must fulfill on the hub chain before the verifier approves escrow release
        
        // Validate solver addresses match between escrow and request intent
        // For Move/Aptos escrows: Check if escrow's reserved_solver (Aptos address) matches hub request intent's solver (Aptos address)
        // For EVM escrows: Check if escrow's reserved_solver (EVM address) matches registered solver's EVM address
        if let (Some(escrow_solver), Some(request_intent_solver)) = (&escrow_event.reserved_solver, &request_intent_event.reserved_solver) {
            // Determine chain type from the chain_type field set by the monitor
            let is_evm_escrow = escrow_event.chain_type == ChainType::Evm;
            
            if is_evm_escrow {
                // EVM escrow: Compare EVM addresses
                // The escrow_solver is an EVM address, request_intent_solver is an Aptos address
                // We need to query the solver registry to get the EVM address for request_intent_solver
                let hub_rpc_url = &self.config.hub_chain.rpc_url;
                let registry_address = &self.config.hub_chain.intent_module_address; // Registry is at module address
                
                let validation_result = evm::validate_evm_escrow_solver(
                    request_intent_event,
                    escrow_solver,
                    hub_rpc_url,
                    registry_address,
                ).await?;
                
                if !validation_result.valid {
                    return Ok(validation_result);
                }
            } else {
                // Aptos escrow: Compare Aptos addresses directly
                if escrow_solver != request_intent_solver {
                    return Ok(ValidationResult {
                        valid: false,
                        message: format!(
                            "Escrow reserved solver '{}' does not match hub request intent solver '{}'",
                            escrow_solver, request_intent_solver
                        ),
                        timestamp: chrono::Utc::now().timestamp() as u64,
                    });
                }
            }
        } else if escrow_event.reserved_solver.is_some() || request_intent_event.reserved_solver.is_some() {
            // One is reserved but the other is not - mismatch
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "Escrow and request intent reservation mismatch: escrow reserved_solver={:?}, request intent solver={:?}",
                    escrow_event.reserved_solver, request_intent_event.reserved_solver
                ),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
        // Note: EVM escrow validation is handled separately in evm::validate_evm_escrow_solver
        
        // Additional validation logic can be added here:
        // - Check solver reputation and authorization
        // - Verify additional conditions specified in the request intent
        // - Validate cross-chain state consistency
        // - Check for duplicate or conflicting transactions
        
        // All validations passed
        Ok(ValidationResult {
            valid: true,
            message: "Request intent fulfillment validation successful".to_string(),
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
    ) -> Result<ValidationResult> {
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
    ) -> Result<ValidationResult> {
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

// ============================================================================
// FULFILLMENT TRANSACTION EXTRACTION
// ============================================================================

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

// Re-export chain-specific functions for convenience
pub use aptos::extract_aptos_fulfillment_params;
pub use evm::extract_evm_fulfillment_params;

/// Validates an outflow fulfillment transaction against a request intent
/// 
/// This function validates that a connected chain transaction properly fulfills
/// an outflow request intent by checking:
/// - Transaction was confirmed and successful
/// - intent_id matches the request intent
/// - Recipient address matches requester_address_connected_chain
/// - Amount matches desired_amount
/// - Solver address matches reserved solver
/// 
/// ## Solver Registration Requirements
/// 
/// **IMPORTANT**: The solver must be registered in the solver registry with the correct
/// address for the connected chain. All addresses (Aptos address for Aptos chains,
/// EVM address for EVM chains) must be provided during registration. If the solver
/// address for the connected chain is not found in the registry, this indicates an
/// error on the solver's side - they must register correctly before attempting to
/// fulfill intents. The verifier will reject transactions from unregistered or
/// incorrectly registered solvers.
/// 
/// # Arguments
/// 
/// * `validator` - The cross-chain validator instance
/// * `request_intent` - The outflow request intent from the hub chain
/// * `tx_params` - Extracted parameters from the connected chain transaction
/// * `tx_success` - Whether the transaction was successful
/// 
/// # Returns
/// 
/// * `Ok(ValidationResult)` - Validation result
/// * `Err(anyhow::Error)` - Validation failed due to error
pub fn validate_outflow_fulfillment(
    _validator: &CrossChainValidator,
    request_intent: &RequestIntentEvent,
    tx_params: &FulfillmentTransactionParams,
    tx_success: bool,
) -> Result<ValidationResult> {
    info!("Validating outflow fulfillment for intent: {}", request_intent.intent_id);

    // Validate transaction was successful
    if !tx_success {
        return Ok(ValidationResult {
            valid: false,
            message: "Transaction was not successful".to_string(),
            timestamp: chrono::Utc::now().timestamp() as u64,
        });
    }

    // Validate intent_id matches
    if tx_params.intent_id != request_intent.intent_id {
        return Ok(ValidationResult {
            valid: false,
            message: format!(
                "Transaction intent_id '{}' does not match request intent '{}'",
                tx_params.intent_id, request_intent.intent_id
            ),
            timestamp: chrono::Utc::now().timestamp() as u64,
        });
    }

    // Validate recipient matches requester_address_connected_chain (for outflow intents)
    if let Some(ref requester_address) = request_intent.requester_address_connected_chain {
        // Normalize addresses for comparison (remove 0x prefix, lowercase)
        let tx_recipient = tx_params.recipient.strip_prefix("0x").unwrap_or(&tx_params.recipient).to_lowercase();
        let requester = requester_address.strip_prefix("0x").unwrap_or(requester_address).to_lowercase();
        
        if tx_recipient != requester {
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "Transaction recipient '{}' does not match request intent requester_address_connected_chain '{}'",
                    tx_params.recipient, requester_address
                ),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
    } else {
        // For outflow intents, requester_address_connected_chain should be present
        // An outflow request intent without a requester address on the connected chain is rejected
        // by the Move contract itself (see create_outflow_request_intent which aborts with
        // EINVALID_REQUESTER_ADDRESS if requester_address_connected_chain is zero address).
        // If we receive such an intent with missing requester_address_connected_chain, it indicates
        // the field wasn't populated when the event was processed (should query intent object to get it).
        // For outflow intents (connected_chain_id is Some), this is required for validation
        if request_intent.connected_chain_id.is_some() {
            return Ok(ValidationResult {
                valid: false,
                message: "Request intent has connected_chain_id but missing requester_address_connected_chain (required for outflow validation)".to_string(),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
    }

    // Validate amount matches desired_amount
    if tx_params.amount != request_intent.desired_amount {
        return Ok(ValidationResult {
            valid: false,
            message: format!(
                "Transaction amount {} does not match request intent desired amount {}",
                tx_params.amount, request_intent.desired_amount
            ),
            timestamp: chrono::Utc::now().timestamp() as u64,
        });
    }

    // Validate solver matches reserved solver
    if let Some(ref reserved_solver) = request_intent.reserved_solver {
        // Normalize addresses for comparison (remove 0x prefix, lowercase)
        let tx_solver = tx_params.solver.strip_prefix("0x").unwrap_or(&tx_params.solver).to_lowercase();
        let reserved = reserved_solver.strip_prefix("0x").unwrap_or(reserved_solver).to_lowercase();
        
        if tx_solver != reserved {
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "Transaction solver '{}' does not match reserved solver '{}'",
                    tx_params.solver, reserved_solver
                ),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
    } else {
        return Ok(ValidationResult {
            valid: false,
            message: "Request intent has no reserved solver".to_string(),
            timestamp: chrono::Utc::now().timestamp() as u64,
        });
    }

    // All validations passed
    Ok(ValidationResult {
        valid: true,
        message: "Outflow fulfillment validation successful".to_string(),
        timestamp: chrono::Utc::now().timestamp() as u64,
    })
}