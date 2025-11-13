//! Unit tests for cross-chain matching logic
//!
//! These tests verify that escrow events can be matched to intent events
//! across different chains using intent_id.

use trusted_verifier::monitor::{RequestIntentEvent, EscrowEvent};
#[path = "mod.rs"]
mod test_helpers;

/// Test that escrow events can be matched to intent events by intent_id
/// Why: Verify cross-chain matching logic correctly links escrow to hub intent for validation
///
/// Cross-chain escrow flow:
/// 1. [HUB CHAIN] User creates intent on hub chain (requests tokens - solver will fulfill)
///    - Intent requests 1000 tokens to be provided by solver
///    - User creates intent with intent_id
///
/// 2. [CONNECTED CHAIN] User creates escrow on connected chain WITH tokens locked in it
///    - User locks 1000 tokens in escrow
///    - User provides hub chain intent_id when creating escrow
///    - Escrow event includes intent_id linking back to hub intent
///
/// 3. [HUB CHAIN] Solver monitors escrow event on connected chain and fulfills intent on hub chain
///    - Solver sees escrow event on connected chain
///    - Solver provides 1000 tokens on hub chain to fulfill the intent
///    - Solver fulfills hub intent (provides tokens on hub chain)
///
/// 4. [HUB CHAIN] Verifier validates cross-chain conditions are met
///    - Verifier matches escrow.intent_id to hub_intent.intent_id
///    - Verifier validates solver fulfilled the intent on hub chain
///      (validates deposit amounts, metadata, and expiry)
///
/// 5. [CONNECTED CHAIN] Verifier releases escrow to solver on connected chain
///    - Verifier generates approval signature
///    - Escrow is released to solver on connected chain
#[test]
fn test_cross_chain_intent_matching() {
    // Step 1: User creates intent on hub chain (requests 1000 tokens to be provided by solver)
    let hub_intent = RequestIntentEvent {
        chain: "hub".to_string(),
        intent_id: "0xhub_abc123".to_string(),
        issuer: "0xalice".to_string(),
        offered_metadata: "{\"inner\":\"0xsource_meta\"}".to_string(),
        offered_amount: 1000, // amount that will be locked in escrow on connected chain
        desired_metadata: "{\"inner\":\"0xdesired_meta\"}".to_string(),
        desired_amount: 0, // Escrow only holds offered funds // User wants solver to provide 1000 tokens on hub chain
        expiry_time: 1000000,
        revocable: false,
        solver: None,
        connected_chain_id: Some(2),
        timestamp: 0,
    };
    
    // Step 2: User creates escrow on connected chain WITH tokens locked in it
    // The user must manually provide the hub_intent_id when creating the escrow
    let escrow_creation = EscrowEvent {
        chain: "connected".to_string(),
        escrow_id: "0xescrow_xyz789".to_string(), // Escrow object address on connected chain
        intent_id: "0xhub_abc123".to_string(),    // Intent ID from hub chain (provided by user)
        issuer: "0xalice".to_string(),           // Alice created the escrow and locked tokens
        offered_metadata: "{\"inner\":\"0xsource_meta\"}".to_string(), // User's locked tokens
        offered_amount: 1000,                     // User's tokens locked in escrow
        desired_metadata: "{\"inner\":\"0xdesired_meta\"}".to_string(), // What solver needs to provide
        desired_amount: 0, // Escrow only holds offered funds, requirement is in hub request intent
        expiry_time: 1000000,
        revocable: false, // Escrows must be non-revocable for security
        reserved_solver: None,
        chain_id: 2,
        chain_type: trusted_verifier::ChainType::Move,
        timestamp: 0,
    };
    
    // Step 3: Solver fulfills hub intent (solver provides 1000 tokens on hub chain)
    // [Not yet tested. This will also be tested here, not just in integration tests.]
    
    // Step 4: Verifier validation 
    // [Not yet tested. This will also be tested here, not just in integration tests.]
    
    // Step 5: Verifier release
    // [Not yet tested. This will also be tested here, not just in integration tests.]
    
    // This unit test verifies that data structures support cross-chain matching
    // Verify matching: intent_id should match
    assert_eq!(escrow_creation.intent_id, hub_intent.intent_id, 
               "Escrow intent_id should match the hub intent_id");
    
    // Verify escrow has tokens locked (user creates escrow with tokens locked)
    assert_eq!(escrow_creation.offered_amount, 1000,
               "Escrow should have tokens locked (user created escrow with tokens)");
    
    // Verify the locked tokens in escrow match what the intent wants
    assert_eq!(escrow_creation.offered_amount, hub_intent.offered_amount,
               "Escrow locked tokens should match what intent wants");
}

/// Test that escrow chain_id validation works correctly
/// Why: Verify that escrow chain_id matches the intent's offered_chain_id when provided
#[tokio::test]
async fn test_escrow_chain_id_validation() {
    use trusted_verifier::validator::CrossChainValidator;
    use test_helpers::build_test_config;
    
    let config = build_test_config();
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    // Test that escrow chain_id must match intent's offered_chain_id when provided
    let valid_intent = RequestIntentEvent {
        chain: "hub".to_string(),
        intent_id: "0xvalid_intent".to_string(),
        issuer: "0xalice".to_string(),
        offered_metadata: "{}".to_string(),
        offered_amount: 1000, // Must match escrow offered_amount
        desired_metadata: "{}".to_string(),
        desired_amount: 0, // Escrow only holds offered funds
        expiry_time: 1000000,
        revocable: false,
        solver: Some("0xsolver".to_string()),
        connected_chain_id: Some(2), // Has chain ID - should pass this check
        timestamp: 0,
    };
    
    let valid_escrow = EscrowEvent {
        chain: "connected".to_string(),
        escrow_id: "0xescrow_valid".to_string(),
        intent_id: "0xvalid_intent".to_string(),
        issuer: "0xalice".to_string(),
        offered_metadata: "{}".to_string(),
        offered_amount: 1000, // Matches intent source_amount
        desired_metadata: "{}".to_string(),
        desired_amount: 0, // Escrow only holds offered funds
        expiry_time: 1000000,
        revocable: false,
        reserved_solver: Some("0xsolver".to_string()),
        chain_id: 2,
        chain_type: trusted_verifier::ChainType::Move,
        timestamp: 0,
    };
    
    // This should pass the connected_chain_id check (may fail other validations, but not this one)
    let result = validator.validate_intent_fulfillment(&valid_intent, &valid_escrow).await;
    assert!(result.is_ok(), "Validation should complete");
    
    let validation_result = result.unwrap();
    // Assert 1: If validation fails, it should NOT be because of missing connected_chain_id
    if !validation_result.valid {
        assert!(!validation_result.message.contains("connected_chain_id"), 
                "Should not fail due to missing connected_chain_id when chain_id is provided");
    }
    // Assert 2: Validation may fail on other checks (like solver registry query), but should not fail on connected_chain_id
    // Note: This might fail other validations (like solver address mismatch if not properly mocked),
    // but for a complete test, we'd need to ensure all conditions are met
    // We just verify it doesn't fail on connected_chain_id check
}

/// Test that verifier rejects escrows where offered_amount doesn't match hub request intent's offered amount
/// Why: Verify that escrow amount validation works correctly
#[tokio::test]
async fn test_escrow_amount_must_match_hub_intent_offered_amount() {
    use trusted_verifier::validator::CrossChainValidator;
    use test_helpers::build_test_config;
    
    let config = build_test_config();
    let validator = CrossChainValidator::new(&config).await.expect("Failed to create validator");
    
    // Create a hub intent with offered_amount = 1000
    let hub_intent = RequestIntentEvent {
        chain: "hub".to_string(),
        intent_id: "0xintent_123".to_string(),
        issuer: "0xalice".to_string(),
        offered_metadata: "{\"inner\":\"0xsource_meta\"}".to_string(),
        offered_amount: 1000, // amount that will be locked in escrow
        desired_metadata: "{\"inner\":\"0xdesired_meta\"}".to_string(),
        desired_amount: 0, // Escrow only holds offered funds
        expiry_time: 1000000,
        revocable: false,
        solver: Some("0xsolver".to_string()),
        connected_chain_id: Some(2),
        timestamp: 0,
    };
    
    // Create an escrow with mismatched offered_amount (500 != 1000)
    let escrow_mismatch = EscrowEvent {
        chain: "connected".to_string(),
        escrow_id: "0xescrow_123".to_string(),
        intent_id: "0xintent_123".to_string(),
        issuer: "0xalice".to_string(),
        offered_metadata: "{\"inner\":\"0xsource_meta\"}".to_string(),
        offered_amount: 500, // Mismatch: should be 1000 to match hub intent
        desired_metadata: "{\"inner\":\"0xdesired_meta\"}".to_string(),
        desired_amount: 0, // Escrow only holds offered funds
        expiry_time: 1000000,
        revocable: false,
        reserved_solver: Some("0xsolver".to_string()),
        chain_id: 2,
        chain_type: trusted_verifier::ChainType::Move,
        timestamp: 0,
    };
    
    let validation_result = validator.validate_intent_fulfillment(&hub_intent, &escrow_mismatch).await
        .expect("Validation should complete without error");
    
    assert!(!validation_result.valid, "Validation should fail when escrow offered_amount doesn't match hub intent offered amount");
    assert!(validation_result.message.contains("offered amount"),
            "Error message should mention offered amount mismatch");
    
    // Now test with matching amounts
    let escrow_match = EscrowEvent {
        chain: "connected".to_string(),
        escrow_id: "0xescrow_456".to_string(),
        intent_id: "0xintent_123".to_string(),
        issuer: "0xalice".to_string(),
        offered_metadata: "{\"inner\":\"0xsource_meta\"}".to_string(),
        offered_amount: 1000, // Matches hub intent offered amount
        desired_metadata: "{\"inner\":\"0xdesired_meta\"}".to_string(),
        desired_amount: 0, // Escrow only holds offered funds
        expiry_time: 1000000,
        revocable: false,
        reserved_solver: Some("0xsolver".to_string()),
        chain_id: 2,
        chain_type: trusted_verifier::ChainType::Move,
        timestamp: 0,
    };
    
    let validation_result = validator.validate_intent_fulfillment(&hub_intent, &escrow_match).await
        .expect("Validation should complete without error");
    
    // Verify that validation doesn't fail due to amount mismatch (amount check passes)
    assert!(!validation_result.message.contains("offered amount"), 
            "Validation should not fail due to offered_amount mismatch when amounts match");
    
    // Verify that validation doesn't fail at all (all checks pass)
    assert!(validation_result.valid, "Validation should pass when all checks pass");
}

