//! Cross-Chain Validation Module
//! 
//! This module handles cross-chain validation logic, ensuring that escrow deposits
//! on the connected chain properly fulfill the conditions specified in intents
//! created on the hub chain. It provides cryptographic validation and approval
//! mechanisms for secure cross-chain operations.
//! 
//! ## Security Requirements
//! 
//! ⚠️ **CRITICAL**: All validations must verify that escrow intents are **non-revocable** 
//! (`revocable = false`) before issuing any approval signatures.

use anyhow::{Result, Context};
use serde::{Deserialize, Serialize};
use tracing::info;

use crate::config::Config;
use crate::monitor::{RequestIntentEvent, EscrowEvent, FulfillmentEvent, ChainType};

// ============================================================================
// VALIDATION DATA STRUCTURES
// ============================================================================

/// Result of cross-chain validation between an intent and escrow event.
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

/// Cross-chain validator that ensures escrow deposits fulfill intent conditions.
/// 
/// This validator performs comprehensive checks to ensure that deposits
/// made on the connected chain properly fulfill the requirements specified
/// in intents created on the hub chain. It provides cryptographic approval
/// signatures for valid fulfillments.
pub struct CrossChainValidator {
    /// Service configuration
    config: std::sync::Arc<Config>,
    /// HTTP client for blockchain communication
    #[allow(dead_code)]
    client: reqwest::Client,
}

impl CrossChainValidator {
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
    
    /// Validates that an intent is safe for escrow operations.
    /// 
    /// This function performs critical security checks to ensure that an intent
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
    pub async fn validate_intent_safety(&self, intent: &RequestIntentEvent) -> Result<ValidationResult> {
        info!("Validating intent safety: {}", intent.intent_id);
        
        // 🔒 CRITICAL SECURITY CHECK: Verify intent is non-revocable
        if intent.revocable {
            return Ok(ValidationResult {
                valid: false,
                message: "Intent is revocable - NOT safe for escrow operations".to_string(),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
        
        // Additional safety checks: verify intent has not expired
        if intent.expiry_time < chrono::Utc::now().timestamp() as u64 {
            return Ok(ValidationResult {
                valid: false,
                message: "Intent has expired".to_string(),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
        
        // All safety checks passed
        Ok(ValidationResult {
            valid: true,
            message: "Intent is safe for escrow operations".to_string(),
            timestamp: chrono::Utc::now().timestamp() as u64,
        })
    }
    
    /// Validates fulfillment of intent conditions on the connected chain.
    /// 
    /// This function performs comprehensive validation to ensure that:
    /// 1. The escrow's offered_amount matches the hub request intent's offered_amount
    /// 2. The escrow's offered_metadata matches the hub request intent's offered_metadata
    /// 3. The escrow's chain_id matches the hub request intent's offered_chain_id (when provided)
    /// 4. The escrow's desired_amount is 0 (escrow only holds offered funds, requirement is in hub request intent)
    /// 5. The escrow's reserved_solver matches the hub request intent's solver (with chain-specific validation)
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
    pub async fn validate_intent_fulfillment(
        &self,
        request_intent_event: &RequestIntentEvent,
        escrow_event: &EscrowEvent,
    ) -> Result<ValidationResult> {
        info!("Validating intent fulfillment for intent: {}, escrow: {}", 
              request_intent_event.intent_id, escrow_event.escrow_id);
        
        // Validate the escrow's offered_amount matches the specified offered_amount in the hub request intent
        if escrow_event.offered_amount != request_intent_event.offered_amount {
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "Escrow offered amount {} does not match hub intent offered amount {}",
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
                    "Escrow offered metadata '{}' does not match hub intent offered metadata '{}'",
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
        
        // Validate solver addresses match between escrow and intent
        // For Move/Aptos escrows: Check if escrow's reserved_solver (Aptos address) matches hub intent's solver (Aptos address)
        // For EVM escrows: Check if escrow's reserved_solver (EVM address) matches registered solver's EVM address
        if let (Some(escrow_solver), Some(intent_solver)) = (&escrow_event.reserved_solver, &request_intent_event.solver) {
            // Determine chain type from the chain_type field set by the monitor
            let is_evm_escrow = escrow_event.chain_type == ChainType::Evm;
            
            if is_evm_escrow {
                // EVM escrow: Compare EVM addresses
                // The escrow_solver is an EVM address, intent_solver is an Aptos address
                // We need to query the solver registry to get the EVM address for intent_solver
                let hub_rpc_url = &self.config.hub_chain.rpc_url;
                let registry_address = &self.config.hub_chain.intent_module_address; // Registry is at module address
                
                let validation_result = self.validate_evm_escrow_solver(
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
                if escrow_solver != intent_solver {
                    return Ok(ValidationResult {
                        valid: false,
                        message: format!(
                            "Escrow reserved solver '{}' does not match hub intent solver '{}'",
                            escrow_solver, intent_solver
                        ),
                        timestamp: chrono::Utc::now().timestamp() as u64,
                    });
                }
            }
        } else if escrow_event.reserved_solver.is_some() || request_intent_event.solver.is_some() {
            // One is reserved but the other is not - mismatch
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "Escrow and intent reservation mismatch: escrow reserved_solver={:?}, intent solver={:?}",
                    escrow_event.reserved_solver, request_intent_event.solver
                ),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
        // Note: EVM escrow validation is handled separately in validate_evm_escrow_solver
        
        // Additional validation logic can be added here:
        // - Check solver reputation and authorization
        // - Verify additional conditions specified in the intent
        // - Validate cross-chain state consistency
        // - Check for duplicate or conflicting transactions
        
        // All validations passed
        Ok(ValidationResult {
            valid: true,
            message: "Intent fulfillment validation successful".to_string(),
            timestamp: chrono::Utc::now().timestamp() as u64,
        })
    }
    
    /// Validates that an EVM escrow's reserved solver matches the registered solver's EVM address.
    /// 
    /// This function checks that the EVM escrow's reservedSolver address matches
    /// the EVM address registered in the solver registry for the hub intent's solver.
    /// 
    /// # Arguments
    /// 
    /// * `intent` - The intent event from the hub chain (must have a solver)
    /// * `escrow_reserved_solver` - The reserved solver EVM address from the escrow
    /// * `hub_chain_rpc_url` - RPC URL of the hub chain (to query solver registry)
    /// * `registry_address` - Address where the solver registry is deployed
    /// 
    /// # Returns
    /// 
    /// * `Ok(ValidationResult)` - Validation result with detailed information
    /// * `Err(anyhow::Error)` - Validation failed due to error
    pub async fn validate_evm_escrow_solver(
        &self,
        intent: &RequestIntentEvent,
        escrow_reserved_solver: &str,
        hub_chain_rpc_url: &str,
        registry_address: &str,
    ) -> Result<ValidationResult> {
        // Check if intent has a solver
        let intent_solver = match &intent.solver {
            Some(solver) => solver,
            None => {
                return Ok(ValidationResult {
                    valid: false,
                    message: "Hub intent does not have a reserved solver".to_string(),
                    timestamp: chrono::Utc::now().timestamp() as u64,
                });
            }
        };
        
        // Query solver registry for EVM address
        let aptos_client = crate::aptos_client::AptosClient::new(hub_chain_rpc_url)?;
        let registered_evm_address = aptos_client.get_solver_evm_address(intent_solver, registry_address)
            .await
            .context("Failed to query solver EVM address from registry")?;
        
        let registered_evm_address = match registered_evm_address {
            Some(addr) => addr,
            None => {
                return Ok(ValidationResult {
                    valid: false,
                    message: format!("Solver '{}' is not registered in the solver registry", intent_solver),
                    timestamp: chrono::Utc::now().timestamp() as u64,
                });
            }
        };
        
        // Normalize addresses for comparison (lowercase, ensure 0x prefix)
        let escrow_solver_normalized = escrow_reserved_solver.strip_prefix("0x")
            .unwrap_or(escrow_reserved_solver)
            .to_lowercase();
        let registered_solver_normalized = registered_evm_address.strip_prefix("0x")
            .unwrap_or(&registered_evm_address)
            .to_lowercase();
        
        if escrow_solver_normalized != registered_solver_normalized {
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "EVM escrow reserved solver '{}' does not match registered solver EVM address '{}'",
                    escrow_reserved_solver, registered_evm_address
                ),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }
        
        Ok(ValidationResult {
            valid: true,
            message: "EVM escrow solver validation successful".to_string(),
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
        intent: &RequestIntentEvent,
        fulfillment: &FulfillmentEvent,
    ) -> Result<ValidationResult> {
        info!("Validating fulfillment for intent: {}", intent.intent_id);
        
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