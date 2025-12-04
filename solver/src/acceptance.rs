//! Draft-intent acceptance logic
//!
//! Determines whether the solver should sign a draftintent based on:
//! - Token pair validation (must be in configured supported pairs)
//! - Exchange rate validation (offered amount must meet required rate for the pair)

use std::collections::HashMap;

/// Token pair identifier for exchange rate lookup
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct TokenPair {
    pub offered_chain_id: u64,
    pub offered_token: String,
    pub desired_chain_id: u64,
    pub desired_token: String,
}

/// Temporary acceptance config structure
/// TODO: Replace with SolverConfig from config module in Task 5
pub struct AcceptanceConfig {
    /// Supported token pairs with exchange rates
    /// Key: TokenPair (offered_chain_id, offered_token, desired_chain_id, desired_token)
    /// Value: Exchange rate (how many offered tokens per 1 desired token)
    pub token_pairs: HashMap<TokenPair, f64>,
}

/// Draft-intent data from verifier API
#[derive(Debug, Clone)]
pub struct DraftintentData {
    pub offered_token: String,      // Contract address
    pub offered_amount: u64,
    pub offered_chain_id: u64,
    pub desired_token: String,      // Contract address
    pub desired_amount: u64,
    pub desired_chain_id: u64,
}

/// Result of acceptance evaluation
#[derive(Debug)]
pub enum AcceptanceResult {
    Accept,
    Reject(String),  // Reason for rejection
}

/// Evaluate whether to accept a draftintent
pub fn should_accept_draft(draft: &DraftintentData, config: &AcceptanceConfig) -> AcceptanceResult {
    // Create token pair key for lookup
    let pair = TokenPair {
        offered_chain_id: draft.offered_chain_id,
        offered_token: draft.offered_token.clone(),
        desired_chain_id: draft.desired_chain_id,
        desired_token: draft.desired_token.clone(),
    };

    // Check if token pair is supported
    let exchange_rate = match config.token_pairs.get(&pair) {
        Some(rate) => *rate,
        None => {
            return AcceptanceResult::Reject(format!(
                "Token pair not supported: {}:{} -> {}:{}",
                draft.offered_chain_id, draft.offered_token,
                draft.desired_chain_id, draft.desired_token
            ));
        }
    };

    // Calculate required offered amount based on exchange rate
    // exchange_rate = offered_tokens_per_desired_token
    // required_offered = desired_amount * exchange_rate
    let required_offered = (draft.desired_amount as f64 * exchange_rate) as u64;

    if draft.offered_amount >= required_offered {
        AcceptanceResult::Accept
    } else {
        AcceptanceResult::Reject(format!(
            "Swap rejected: offered {} < required {} (rate: {} offered/desired)",
            draft.offered_amount, required_offered, exchange_rate
        ))
    }
}


