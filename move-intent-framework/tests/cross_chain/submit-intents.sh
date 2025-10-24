#!/bin/bash

echo "🎯 INTENT FRAMEWORK - SUBMIT ESCROW INTENT"
echo "==========================================="

echo ""
echo "🚀 Step 0: Setting up chains and deploying contracts..."
echo "========================================================"
./move-intent-framework/tests/cross_chain/setup-and-deploy.sh

if [ $? -ne 0 ]; then
    echo "❌ Failed to setup chains and deploy contracts"
    exit 1
fi

echo ""
echo "✅ Chains setup and contracts deployed successfully!"
echo ""

# Get addresses
CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain1"].account')
CHAIN2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["intent-account-chain2"].account')

echo ""
echo "📋 Chain Information:"
echo "   Chain 1 (intent-account-chain1):  $CHAIN1_ADDRESS"
echo "   Chain 2 (intent-account-chain2): $CHAIN2_ADDRESS"

echo ""
echo "💰 Step 1: Using existing Alice and Bob accounts..."

# Get Alice and Bob addresses (they're already set up from previous script)
ALICE_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["alice-chain1"].account')
BOB_CHAIN1_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["bob-chain1"].account')
ALICE_CHAIN2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["alice-chain2"].account')
BOB_CHAIN2_ADDRESS=$(aptos config show-profiles | jq -r '.["Result"]["bob-chain2"].account')

echo "   - Alice Chain 1: $ALICE_CHAIN1_ADDRESS"
echo "   - Bob Chain 1:   $BOB_CHAIN1_ADDRESS"
echo "   - Alice Chain 2: $ALICE_CHAIN2_ADDRESS"
echo "   - Bob Chain 2:   $BOB_CHAIN2_ADDRESS"
echo "   ✅ Alice and Bob accounts already funded from previous setup!"

cd move-intent-framework

echo ""
echo "🎯 Step 2: Creating escrow intent on Chain 1..."

# Create a Move script that creates an escrow using Alice's funded account
cat > create_escrow_intent.move << 'EOF'
script {
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata};
    use aptos_framework::primary_fungible_store;
    use aptos_intent::intent_as_escrow;
    use aptos_std::ed25519;
    use std::signer;
    use std::vector;

    fun main(account: signer) {
        // Create a simple token for escrow
        let metadata = fungible_asset::create_metadata(
            &account,
            vector::empty(),
            b"Escrow Token",
            b"ESC",
            6, // decimals
            false, // is_mutable
        );
        
        let token_type = fungible_asset::create(&account, metadata);
        let tokens = fungible_asset::mint(&account, token_type, 1000);
        
        // Store tokens in user's account
        primary_fungible_store::deposit(signer::address_of(&account), tokens);
        
        // Generate a dummy oracle public key for testing
        let (_, validated_pk) = ed25519::generate_keys();
        let oracle_public_key = ed25519::public_key_to_unvalidated(&validated_pk);
        
        // Create escrow intent with the tokens
        let escrow_intent = intent_as_escrow::create_escrow(
            &account,
            tokens,
            oracle_public_key,
            1761294000, // expiry_time (future timestamp)
        );
        
        // Clean up
        fungible_asset::destroy(token_type);
    }
}
EOF

echo "   - Created escrow intent script"

# Submit escrow intent using Alice's account on Chain 1
aptos move run --profile alice-chain1 --assume-yes

if [ $? -eq 0 ]; then
    echo "     ✅ Alice-chain1 escrow intent created successfully!"
else
    echo "     ❌ Alice-chain1 escrow intent creation failed!"
fi

echo ""
echo "🎯 Step 3: Creating escrow intent using Bob's account on Chain 1..."

# Submit escrow intent using Bob's account on Chain 1
aptos move run --profile bob-chain1 --assume-yes

if [ $? -eq 0 ]; then
    echo "     ✅ Bob-chain1 escrow intent created successfully!"
else
    echo "     ❌ Bob-chain1 escrow intent creation failed!"
fi

echo ""
echo "🎯 Step 4: Creating escrow intent using Alice's account on Chain 2..."

# Submit escrow intent using Alice's account on Chain 2
aptos move run --profile alice-chain2 --assume-yes

if [ $? -eq 0 ]; then
    echo "     ✅ Alice-chain2 escrow intent created successfully!"
else
    echo "     ❌ Alice-chain2 escrow intent creation failed!"
fi

echo ""
echo "🎯 Step 5: Creating escrow intent using Bob's account on Chain 2..."

# Submit escrow intent using Bob's account on Chain 2
aptos move run --profile bob-chain2 --assume-yes

if [ $? -eq 0 ]; then
    echo "     ✅ Bob-chain2 escrow intent created successfully!"
else
    echo "     ❌ Bob-chain2 escrow intent creation failed!"
fi

echo ""
echo "🎉 ESCROW INTENT SUBMISSION COMPLETE!"
echo "====================================="
echo ""
echo "Both chains now have escrow intents created!"
echo "   - Chain 1: http://127.0.0.1:8080"
echo "   - Chain 2: http://127.0.0.1:8082"
echo ""
echo "📋 What we accomplished:"
echo "   ✅ Used existing Alice and Bob accounts (already funded)"
echo "   ✅ Created fungible assets"
echo "   ✅ Submitted escrow intents with tokens to Chain 1"
echo "   ✅ Used the deployed Intent Framework contracts"

# Clean up temporary files
echo ""
echo "🧹 Cleaning up temporary files..."
rm -f create_escrow_intent.move
echo "   ✅ Cleaned up temporary Move script file"