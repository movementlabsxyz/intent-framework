//! Outflow-specific validation logic (chain-agnostic)
//!
//! This module handles validation logic for outflow intents.
//! Outflow intents have tokens locked on the hub chain and request tokens on the connected chain.

use anyhow::Result;
use tracing::info;

use super::generic::{
    validate_address_format, CrossChainValidator, FulfillmentTransactionParams, ValidationResult,
};
use crate::monitor::RequestIntentEvent;

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
/// address for the connected chain. All addresses (Move VM address for Move VM chains,
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
pub async fn validate_outflow_fulfillment(
    validator: &CrossChainValidator,
    request_intent: &RequestIntentEvent,
    tx_params: &FulfillmentTransactionParams,
    tx_success: bool,
) -> Result<ValidationResult> {
    info!(
        "Validating outflow fulfillment for intent: {}",
        request_intent.intent_id
    );

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
        // Determine chain type for address validation based on configured connected chain
        let chain_type = if validator.config().connected_chain_evm.is_some() {
            crate::monitor::ChainType::Evm
        } else if validator.config().connected_chain_mvm.is_some() {
            crate::monitor::ChainType::Mvm
        } else {
            return Ok(ValidationResult {
                valid: false,
                message: "No connected chain configured (neither EVM nor Move VM)".to_string(),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        };

        // Validate address formats match chain type
        if let Err(e) = validate_address_format(&tx_params.recipient, chain_type) {
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "Transaction recipient address format validation failed: {}",
                    e
                ),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }

        if let Err(e) = validate_address_format(requester_address, chain_type) {
            return Ok(ValidationResult {
                valid: false,
                message: format!(
                    "Request intent requester_address_connected_chain format validation failed: {}",
                    e
                ),
                timestamp: chrono::Utc::now().timestamp() as u64,
            });
        }

        // Normalize addresses for comparison (remove 0x prefix, lowercase)
        let tx_recipient = tx_params
            .recipient
            .strip_prefix("0x")
            .unwrap_or(&tx_params.recipient)
            .to_lowercase();
        let requester = requester_address
            .strip_prefix("0x")
            .unwrap_or(requester_address)
            .to_lowercase();

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

    // Validate amount matches expected amount
    // For outflow request intents: desired_amount specifies the amount desired on the connected chain
    // The event contains the original desired_amount for the connected chain
    // If desired_amount is 0, this indicates a bug in the Move code
    let expected_amount = request_intent.desired_amount;

    if expected_amount == 0 {
        return Ok(ValidationResult {
            valid: false,
            message: format!(
                "Request intent desired_amount is 0 - this indicates a bug in the Move code. The event should contain the original desired_amount for the connected chain"
            ),
            timestamp: chrono::Utc::now().timestamp() as u64,
        });
    }

    if tx_params.amount != expected_amount {
        return Ok(ValidationResult {
            valid: false,
            message: format!(
                "Transaction amount {} does not match request intent desired amount {} (amount desired on connected chain)",
                tx_params.amount, expected_amount
            ),
            timestamp: chrono::Utc::now().timestamp() as u64,
        });
    }

    // Validate solver matches reserved solver
    // reserved_solver in the event is always a Move VM address (from hub chain)
    // Always look up the solver in the hub registry to get their connected chain address
    if let Some(ref reserved_solver) = request_intent.reserved_solver {
        use crate::mvm_client::MvmClient;
        use anyhow::Context;

        let hub_rpc_url = &validator.config().hub_chain.rpc_url;
        let hub_registry_address = &validator.config().hub_chain.intent_module_address;
        let hub_client = MvmClient::new(hub_rpc_url)?;

        // Determine if this is a Move VM connected chain
        let is_mvm_chain = validator.config().connected_chain_mvm.is_some();

        if is_mvm_chain {
            // For Move VM chains: Look up connected chain Move VM address from hub registry and compare to transaction solver
            let registered_mvm_address = hub_client.get_solver_connected_chain_mvm_address(reserved_solver, hub_registry_address)
                .await
                .context("Failed to query reserved solver connected chain Move VM address from hub chain registry")?;

            let registered_mvm_address = match registered_mvm_address {
                Some(addr) => addr,
                None => {
                    return Ok(ValidationResult {
                        valid: false,
                        message: format!("Reserved solver '{}' is not registered in hub chain solver registry or has no connected chain Move VM address", reserved_solver),
                        timestamp: chrono::Utc::now().timestamp() as u64,
                    });
                }
            };

            // Compare transaction solver (Move VM address on connected chain) to registered connected chain address
            let tx_solver = tx_params
                .solver
                .strip_prefix("0x")
                .unwrap_or(&tx_params.solver)
                .to_lowercase();
            let registered_mvm = registered_mvm_address
                .strip_prefix("0x")
                .unwrap_or(&registered_mvm_address)
                .to_lowercase();

            if tx_solver != registered_mvm {
                return Ok(ValidationResult {
                    valid: false,
                    message: format!(
                        "Transaction solver '{}' does not match reserved solver's connected chain Move VM address '{}' (reserved solver hub chain address: '{}')",
                        tx_params.solver, registered_mvm_address, reserved_solver
                    ),
                    timestamp: chrono::Utc::now().timestamp() as u64,
                });
            }
        } else {
            // For EVM chains: Look up EVM address from hub registry and compare to transaction solver
            let registered_evm_address = hub_client
                .get_solver_evm_address(reserved_solver, hub_registry_address)
                .await
                .context("Failed to query reserved solver EVM address from hub chain registry")?;

            let registered_evm_address = match registered_evm_address {
                Some(addr) => addr,
                None => {
                    return Ok(ValidationResult {
                        valid: false,
                        message: format!(
                            "Reserved solver '{}' is not registered in hub chain solver registry",
                            reserved_solver
                        ),
                        timestamp: chrono::Utc::now().timestamp() as u64,
                    });
                }
            };

            // Compare transaction solver (EVM address) to registered EVM address
            let tx_solver = tx_params
                .solver
                .strip_prefix("0x")
                .unwrap_or(&tx_params.solver)
                .to_lowercase();
            let registered_evm = registered_evm_address
                .strip_prefix("0x")
                .unwrap_or(&registered_evm_address)
                .to_lowercase();

            if tx_solver != registered_evm {
                return Ok(ValidationResult {
                    valid: false,
                    message: format!(
                        "Transaction solver '{}' does not match reserved solver's EVM address '{}' (reserved solver Move VM address: '{}')",
                        tx_params.solver, registered_evm_address, reserved_solver
                    ),
                    timestamp: chrono::Utc::now().timestamp() as u64,
                });
            }
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
