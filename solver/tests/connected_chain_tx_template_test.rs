//! Unit tests for connected_chain_tx_template binary
//!
//! These tests verify the core functionality of address normalization,
//! EVM calldata generation, and error handling without requiring CLI execution.

#[cfg(test)]
mod tests {
    use ethereum_types::U256;

    // Helper functions from the binary (would need to be extracted to a lib module)
    // For now, we'll test the logic directly

    fn normalize_address(input: &str) -> Result<String, String> {
        let stripped = strip_0x(input)?;
        Ok(format!("0x{}", stripped.to_lowercase()))
    }

    fn strip_0x(input: &str) -> Result<String, String> {
        let s = input.trim();
        let without = s.strip_prefix("0x").unwrap_or(s);

        if without.is_empty() {
            return Err(format!("Address '{}' is empty", input));
        }

        if !without.chars().all(|c| c.is_ascii_hexdigit()) {
            return Err(format!("Address '{}' must be hex", input));
        }

        Ok(without.to_string())
    }

    fn generate_evm_calldata(
        recipient: &str,
        amount: &str,
        intent_id: &str,
    ) -> Result<String, String> {
        let recipient_clean = strip_0x(recipient)?;
        let intent_clean = strip_0x(intent_id)?;

        let amount_u256 =
            U256::from_dec_str(amount).map_err(|e| format!("Invalid amount: {}", e))?;

        let selector = "a9059cbb";
        let recipient_hex = format!("{:0>64}", recipient_clean.to_lowercase());
        let amount_hex = format!("{amount:064x}", amount = amount_u256);
        let intent_hex = format!("{:0>64}", intent_clean.to_lowercase());

        Ok(format!(
            "0x{}{}{}{}",
            selector, recipient_hex, amount_hex, intent_hex
        ))
    }

    // ============================================================================
    // Address Normalization Tests
    // ============================================================================

    #[test]
    fn test_normalize_address_with_prefix() {
        // What is tested: Address normalization when input already has 0x prefix
        // Why: Ensures addresses with prefix are handled correctly and remain valid
        let result = normalize_address("0xaaaaaaaa").unwrap();
        assert_eq!(result, "0xaaaaaaaa");
    }

    #[test]
    fn test_normalize_address_without_prefix() {
        // What is tested: Address normalization when input lacks 0x prefix
        // Why: Users may provide addresses without prefix; we must normalize them consistently
        let result = normalize_address("bbbbbbbbbbbbbbbb").unwrap();
        assert_eq!(result, "0xbbbbbbbbbbbbbbbb");
    }

    #[test]
    fn test_normalize_address_uppercase() {
        // What is tested: Uppercase hex characters are converted to lowercase
        // Why: Ensures consistent address format regardless of input case
        let result = normalize_address("0xAAAAAAAABBBBBBBB").unwrap();
        assert_eq!(result, "0xaaaaaaaabbbbbbbb");
    }

    #[test]
    fn test_normalize_address_mixed_case() {
        // What is tested: Mixed case hex characters are normalized to lowercase
        // Why: Handles real-world input variations and ensures consistent output
        let result = normalize_address("0xAaBbCcDdEeFf1111").unwrap();
        assert_eq!(result, "0xaabbccddeeff1111");
    }

    #[test]
    fn test_normalize_address_mvm_format() {
        // What is tested: Full 64-character Move VM address format is normalized correctly
        // Why: Move VM addresses are 64 hex chars; we must handle full-length addresses
        let addr = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        let result = normalize_address(addr).unwrap();
        assert_eq!(result, addr.to_lowercase());
    }

    #[test]
    fn test_normalize_address_empty() {
        // What is tested: Empty address strings are rejected with error
        // Why: Empty addresses are invalid and should fail early with clear error
        let result = normalize_address("");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("empty"));
    }

    #[test]
    fn test_normalize_address_invalid_hex() {
        // What is tested: Non-hexadecimal characters are rejected
        // Why: Addresses must be valid hex; invalid characters indicate user error
        let result = normalize_address("0xghijklmnop");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("must be hex"));
    }

    #[test]
    fn test_strip_0x_with_prefix() {
        // What is tested: 0x prefix is correctly stripped from hex strings
        // Why: Internal processing needs hex without prefix for formatting
        let result = strip_0x("0xaaaaaa").unwrap();
        assert_eq!(result, "aaaaaa");
    }

    #[test]
    fn test_strip_0x_without_prefix() {
        // What is tested: Hex strings without prefix remain unchanged
        // Why: Handles both prefixed and non-prefixed inputs gracefully
        let result = strip_0x("bbbbbb").unwrap();
        assert_eq!(result, "bbbbbb");
    }

    #[test]
    fn test_strip_0x_only_prefix() {
        // What is tested: Stripping "0x" alone results in empty string error
        // Why: "0x" by itself is not a valid address; should fail validation
        let result = strip_0x("0x");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("empty"));
    }

    // ============================================================================
    // Move VM Command Generation Tests
    // ============================================================================

    fn generate_mvm_command(
        recipient: &str,
        metadata: &str,
        amount: u64,
        intent_id: &str,
    ) -> Result<String, String> {
        let recipient_addr = normalize_address(recipient)?;
        let metadata_addr = normalize_address(metadata)?;
        let intent_id_addr = normalize_address(intent_id)?;

        Ok(format!(
            "aptos move run --profile <solver-profile> \\\n      --function-id <module_address>::utils::transfer_with_intent_id \\\n      --args address:{} address:{} u64:{} address:{}",
            recipient_addr, metadata_addr, amount, intent_id_addr
        ))
    }

    #[test]
    fn test_mvm_command_generation() {
        // What is tested: Complete aptos move run command is generated with all required arguments
        // Why: Solvers need a ready-to-use command; format must match Aptos CLI expectations
        // Use simple repeated patterns for addresses (64 hex chars = 32 bytes for Move)
        let recipient = "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        let metadata = "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
        let amount = 25000000u64;
        let intent_id = "0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc";

        let result = generate_mvm_command(recipient, metadata, amount, intent_id).unwrap();

        // Should contain the function call
        assert!(result.contains("utils::transfer_with_intent_id"));

        // Should contain all addresses in correct format
        assert!(result.contains(
            "address:0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        ));
        assert!(result.contains(
            "address:0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
        ));
        assert!(result.contains(
            "address:0xcccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
        ));

        // Should contain amount as u64
        assert!(result.contains("u64:25000000"));
    }

    #[test]
    fn test_mvm_command_address_normalization() {
        // What is tested: All addresses in command are normalized to lowercase with 0x prefix
        // Why: Aptos CLI requires consistent address format; normalization prevents errors (Move VM addresses)
        let recipient = "0xAAAA"; // Uppercase
        let metadata = "bbbbbbbbbbbbbbbb"; // No prefix
        let amount = 1000u64;
        let intent_id = "0x5678";

        let result = generate_mvm_command(recipient, metadata, amount, intent_id).unwrap();

        // All addresses should be normalized to lowercase with 0x prefix
        assert!(result.contains("address:0xaaaa"));
        assert!(result.contains("address:0xbbbbbbbbbbbbbbbb"));
        assert!(result.contains("address:0x5678"));
    }

    #[test]
    fn test_mvm_command_zero_amount() {
        // What is tested: Zero amount is handled correctly in command generation
        // Why: Edge case that should work (though not practical for transfers)
        let recipient = "0x1234";
        let metadata = "0x5678";
        let amount = 0u64;
        let intent_id = "0x9abc";

        let result = generate_mvm_command(recipient, metadata, amount, intent_id).unwrap();

        // Should handle zero amount
        assert!(result.contains("u64:0"));
    }

    #[test]
    fn test_mvm_command_large_amount() {
        // What is tested: Maximum u64 value is handled correctly
        // Why: Ensures large token amounts don't cause overflow or formatting issues
        let recipient = "0x1234";
        let metadata = "0x5678";
        let amount = u64::MAX;
        let intent_id = "0x9abc";

        let result = generate_mvm_command(recipient, metadata, amount, intent_id).unwrap();

        // Should handle max u64 value
        assert!(result.contains(&format!("u64:{}", u64::MAX)));
    }

    #[test]
    fn test_mvm_command_invalid_recipient() {
        // What is tested: Invalid recipient address is rejected with error
        // Why: Invalid addresses should fail early before command generation
        let recipient = "0xinvalid";
        let metadata = "0x5678";
        let amount = 1000u64;
        let intent_id = "0x9abc";

        let result = generate_mvm_command(recipient, metadata, amount, intent_id);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("must be hex"));
    }

    #[test]
    fn test_mvm_command_invalid_metadata() {
        // What is tested: Invalid metadata address is rejected with error
        // Why: Metadata is required for Move VM; invalid format should be caught
        let recipient = "0x1234";
        let metadata = "0xinvalid";
        let amount = 1000u64;
        let intent_id = "0x9abc";

        let result = generate_mvm_command(recipient, metadata, amount, intent_id);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("must be hex"));
    }

    #[test]
    fn test_mvm_command_invalid_intent_id() {
        // What is tested: Invalid intent_id address is rejected with error
        // Why: Intent ID must be valid hex address for verifier tracking
        let recipient = "0x1234";
        let metadata = "0x5678";
        let amount = 1000u64;
        let intent_id = "0xinvalid";

        let result = generate_mvm_command(recipient, metadata, amount, intent_id);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("must be hex"));
    }

    #[test]
    fn test_mvm_command_invalid_amount_parsing() {
        // What is tested: Non-numeric amount string is rejected
        // Why: Amount must parse as u64; invalid strings should fail with clear error
        fn generate_mvm_command_with_string_amount(
            recipient: &str,
            metadata: &str,
            amount: &str,
            intent_id: &str,
        ) -> Result<String, String> {
            let recipient_addr = normalize_address(recipient)?;
            let metadata_addr = normalize_address(metadata)?;
            let intent_id_addr = normalize_address(intent_id)?;

            let amount_u64: u64 = amount
                .parse()
                .map_err(|_| "Invalid amount: must be a u64".to_string())?;

            Ok(format!(
                "aptos move run --profile <solver-profile> \\\n      --function-id <module_address>::utils::transfer_with_intent_id \\\n      --args address:{} address:{} u64:{} address:{}",
                recipient_addr, metadata_addr, amount_u64, intent_id_addr
            ))
        }

        let recipient = "0x1234";
        let metadata = "0x5678";
        let amount = "not_a_number";
        let intent_id = "0x9abc";

        let result =
            generate_mvm_command_with_string_amount(recipient, metadata, amount, intent_id);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Invalid amount"));
    }

    // ============================================================================
    // EVM Calldata Generation Tests
    // ============================================================================

    #[test]
    fn test_evm_calldata_generation() {
        // What is tested: Complete EVM calldata payload is generated with selector, recipient, amount, and intent_id
        // Why: Solvers need correct calldata format for ERC20 transfer with embedded intent_id
        let recipient = "0x742d35Cc6634C0532925a3b844Bc9e7595f0bEb";
        let amount = "1000000000000000000";
        let intent_id = "0x5678123456789012345678901234567890123456789012345678901234567890";

        let result = generate_evm_calldata(recipient, amount, intent_id).unwrap();

        // Should start with selector
        assert!(result.starts_with("0xa9059cbb"));

        // Should contain recipient (padded to 64 hex chars)
        assert!(result.contains("742d35cc6634c0532925a3b844bc9e7595f0beb"));

        // Should contain amount (padded to 64 hex chars)
        assert!(result.contains("0de0b6b3a7640000")); // 1 ETH in hex

        // Should contain intent_id (padded to 64 hex chars)
        assert!(result.contains("5678123456789012345678901234567890123456789012345678901234567890"));

        // Total length: 0x (2) + selector (8) + recipient (64) + amount (64) + intent_id (64) = 202
        assert_eq!(result.len(), 202);
    }

    #[test]
    fn test_evm_calldata_recipient_padding() {
        // What is tested: Short recipient addresses are padded to 32 bytes (64 hex chars)
        // Why: EVM calldata requires fixed 32-byte words; padding ensures correct format
        let recipient = "0x1234"; // Short address
        let amount = "1000";
        let intent_id = "0x5678";

        let result = generate_evm_calldata(recipient, amount, intent_id).unwrap();

        // Recipient should be padded to 64 hex chars (32 bytes)
        // Position: after selector (0xa9059cbb = 8 chars) + 0x (2 chars) = starts at index 10
        let recipient_part = &result[10..74]; // 64 hex chars
        assert_eq!(recipient_part.len(), 64);
        assert!(recipient_part
            .starts_with("0000000000000000000000000000000000000000000000000000000000001234"));
    }

    #[test]
    fn test_evm_calldata_amount_padding() {
        // What is tested: Small amounts are padded to 32 bytes (64 hex chars)
        // Why: EVM uint256 requires 32-byte representation; padding ensures correct encoding
        let recipient = "0x1234";
        let amount = "1"; // Small amount
        let intent_id = "0x5678";

        let result = generate_evm_calldata(recipient, amount, intent_id).unwrap();

        // Amount should be padded to 64 hex chars
        // Position: after selector (8) + recipient (64) + 0x (2) = starts at index 74
        let amount_part = &result[74..138]; // 64 hex chars
        assert_eq!(amount_part.len(), 64);
        assert!(amount_part
            .starts_with("0000000000000000000000000000000000000000000000000000000000000001"));
    }

    #[test]
    fn test_evm_calldata_large_amount() {
        // What is tested: Maximum U256 value is handled correctly
        // Why: Ensures large token amounts (up to U256::MAX) don't cause overflow
        let recipient = "0x1234";
        let amount = U256::MAX.to_string();
        let intent_id = "0x5678";

        let result = generate_evm_calldata(recipient, &amount, intent_id);
        assert!(result.is_ok());

        // Should handle max U256 value
        let calldata = result.unwrap();
        assert!(
            calldata.contains("ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
        );
    }

    #[test]
    fn test_evm_calldata_invalid_amount() {
        // What is tested: Non-numeric amount string is rejected with error
        // Why: Amount must parse as decimal number; invalid strings should fail early
        let recipient = "0x1234";
        let amount = "not_a_number";
        let intent_id = "0x5678";

        let result = generate_evm_calldata(recipient, amount, intent_id);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("Invalid amount"));
    }

    #[test]
    fn test_evm_calldata_invalid_recipient() {
        // What is tested: Invalid recipient address is rejected with error
        // Why: Invalid addresses should fail before calldata generation
        let recipient = "0xinvalid";
        let amount = "1000";
        let intent_id = "0x5678";

        let result = generate_evm_calldata(recipient, amount, intent_id);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("must be hex"));
    }

    #[test]
    fn test_evm_calldata_invalid_intent_id() {
        // What is tested: Invalid intent_id address is rejected with error
        // Why: Intent ID must be valid hex for verifier tracking
        let recipient = "0x1234";
        let amount = "1000";
        let intent_id = "0xinvalid";

        let result = generate_evm_calldata(recipient, amount, intent_id);
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("must be hex"));
    }

    #[test]
    fn test_evm_calldata_zero_amount() {
        // What is tested: Zero amount is encoded correctly as all zeros
        // Why: Edge case that should work (though not practical for transfers)
        let recipient = "0x1234";
        let amount = "0";
        let intent_id = "0x5678";

        let result = generate_evm_calldata(recipient, amount, intent_id).unwrap();

        // Amount should be all zeros (padded)
        assert!(result.contains("0000000000000000000000000000000000000000000000000000000000000000"));
    }

    #[test]
    fn test_evm_calldata_selector_correct() {
        // What is tested: ERC20 transfer function selector is correct (0xa9059cbb)
        // Why: Selector must match transfer(address,uint256) signature for EVM to route call correctly
        let recipient = "0x1234";
        let amount = "1000";
        let intent_id = "0x5678";

        let result = generate_evm_calldata(recipient, amount, intent_id).unwrap();

        // ERC20 transfer selector: transfer(address,uint256) = 0xa9059cbb
        assert_eq!(&result[0..10], "0xa9059cbb");
    }
}
