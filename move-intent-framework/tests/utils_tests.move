#[test_only]
module mvmt_intent::utils_tests {
    use std::signer;
    use aptos_framework::primary_fungible_store;
    use mvmt_intent::utils;
    use mvmt_intent::test_utils;

    // ============================================================================
    // TESTS
    // ============================================================================

    #[test(
        aptos_framework = @0x1,
        sender = @0xcafe,
        recipient = @0xdead
    )]
    /// Test: Successful transfer with intent_id
    /// Verifies that transfer_with_intent_id correctly transfers tokens from sender to recipient
    fun test_transfer_with_intent_id_success(
        aptos_framework: &signer,
        sender: &signer,
        recipient: &signer,
    ) {
        // Register and mint tokens for sender
        let (metadata, _) = test_utils::register_and_mint_tokens(aptos_framework, sender, 100);
        
        // Initial balances
        assert!(primary_fungible_store::balance(signer::address_of(sender), metadata) == 100, 1);
        assert!(primary_fungible_store::balance(signer::address_of(recipient), metadata) == 0, 2);
        
        // Transfer 50 tokens with intent_id
        let intent_id = @0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        utils::transfer_with_intent_id(
            sender,
            signer::address_of(recipient),
            metadata,
            50,
            intent_id,
        );
        
        // Verify balances after transfer
        assert!(primary_fungible_store::balance(signer::address_of(sender), metadata) == 50, 3);
        assert!(primary_fungible_store::balance(signer::address_of(recipient), metadata) == 50, 4);
    }

    #[test(
        aptos_framework = @0x1,
        sender = @0xcafe,
        recipient = @0xdead
    )]
    /// Test: Transfer zero amount
    /// Verifies that transfer_with_intent_id handles zero amount transfers
    fun test_transfer_with_intent_id_zero_amount(
        aptos_framework: &signer,
        sender: &signer,
        recipient: &signer,
    ) {
        // Register and mint tokens for sender
        let (metadata, _) = test_utils::register_and_mint_tokens(aptos_framework, sender, 100);
        
        // Transfer 0 tokens
        let intent_id = @0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        utils::transfer_with_intent_id(
            sender,
            signer::address_of(recipient),
            metadata,
            0,
            intent_id,
        );
        
        // Verify balances unchanged
        assert!(primary_fungible_store::balance(signer::address_of(sender), metadata) == 100, 1);
        assert!(primary_fungible_store::balance(signer::address_of(recipient), metadata) == 0, 2);
    }

    #[test(
        aptos_framework = @0x1,
        sender = @0xcafe,
        recipient = @0xdead
    )]
    #[expected_failure(abort_code = 65540, location = aptos_framework::fungible_asset)] // error::invalid_argument(EINSUFFICIENT_BALANCE)
    /// Test: Insufficient balance error
    /// Verifies that transfer_with_intent_id aborts when sender has insufficient balance
    fun test_transfer_with_intent_id_insufficient_balance(
        aptos_framework: &signer,
        sender: &signer,
        recipient: &signer,
    ) {
        // Register and mint only 50 tokens for sender
        let (metadata, _) = test_utils::register_and_mint_tokens(aptos_framework, sender, 50);
        
        // Try to transfer 100 tokens (more than available)
        let intent_id = @0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef;
        utils::transfer_with_intent_id(
            sender,
            signer::address_of(recipient),
            metadata,
            100,
            intent_id,
        );
    }

    #[test(
        aptos_framework = @0x1,
        sender = @0xcafe,
        recipient = @0xdead
    )]
    /// Test: Multiple transfers with different intent_ids
    /// Verifies that transfer_with_intent_id works correctly with different intent_ids
    fun test_transfer_with_intent_id_multiple_transfers(
        aptos_framework: &signer,
        sender: &signer,
        recipient: &signer,
    ) {
        // Register and mint tokens for sender
        let (metadata, _) = test_utils::register_and_mint_tokens(aptos_framework, sender, 100);
        
        // First transfer with intent_id_1
        let intent_id_1 = @0x1111111111111111111111111111111111111111111111111111111111111111;
        utils::transfer_with_intent_id(
            sender,
            signer::address_of(recipient),
            metadata,
            30,
            intent_id_1,
        );
        
        // Second transfer with intent_id_2
        let intent_id_2 = @0x2222222222222222222222222222222222222222222222222222222222222222;
        utils::transfer_with_intent_id(
            sender,
            signer::address_of(recipient),
            metadata,
            40,
            intent_id_2,
        );
        
        // Verify final balances
        assert!(primary_fungible_store::balance(signer::address_of(sender), metadata) == 30, 1);
        assert!(primary_fungible_store::balance(signer::address_of(recipient), metadata) == 70, 2);
    }
}

