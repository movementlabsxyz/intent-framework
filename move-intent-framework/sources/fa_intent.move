module mvmt_intent::fa_intent {
    use std::error;
    use std::signer;
    use std::option::{Self, Option};
    use std::vector;
    use aptos_framework::event;
    use aptos_framework::fungible_asset::{Self, FungibleAsset, Metadata, FungibleStore};
    use mvmt_intent::intent::{Self, Session, Intent};
    use mvmt_intent::intent_reservation::{Self, IntentReserved};
    use aptos_framework::object::{Self, DeleteRef, ExtendRef, Object};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;

    /// The token offered is not the desired fungible asset.
    const ENOT_DESIRED_TOKEN: u64 = 0;

    /// The token offered does not meet amount requirement.
    const EAMOUNT_NOT_MEET: u64 = 1;
    /// The solver signature is invalid and cannot be verified.
    const EINVALID_SIGNATURE: u64 = 2;
    /// The offered metadata address is invalid or missing for cross-chain intents.
    const EINVALID_METADATA_ADDRESS: u64 = 5;
    /// Chain info has not been initialized.
    const ECHAIN_INFO_NOT_INITIALIZED: u64 = 3;
    /// Chain info has already been initialized.
    const ECHAIN_INFO_ALREADY_INITIALIZED: u64 = 4;

    /// Stores the chain ID where this module is deployed.
    struct ChainInfo has key {
        chain_id: u64,
    }

    /// Manages a fungible asset store for intent execution.
    /// Contains references needed to withdraw assets from the store.
    struct FungibleStoreManager has store {
        extend_ref: ExtendRef,
        delete_ref: DeleteRef
    }

    /// Trading conditions for a fungible asset limit order.
    /// Specifies what token type and amount the intent creator wants to receive.
    struct FungibleAssetLimitOrder has store, drop {
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        requester_addr: address,
        intent_id: Option<address>, // Optional cross-chain intent_id for linking (None for regular intents)
        offered_chain_id: u64,
        desired_chain_id: u64
    }

    /// Getter for desired_metadata to allow access from other modules
    public fun get_desired_metadata(order: &FungibleAssetLimitOrder): Object<Metadata> {
        order.desired_metadata
    }

    /// Initialize chain info with the chain ID where this module is deployed.
    /// Must be called once during module deployment.
    ///
    /// # Arguments
    /// - `account`: Signer of the account deploying the module (typically the module owner)
    /// - `chain_id`: The chain ID where this module is deployed
    public entry fun initialize(account: &signer, chain_id: u64) {
        let module_addr = signer::address_of(account);
        // Ensure account is the module deployer (address should match @mvmt_intent)
        assert!(
            module_addr == @mvmt_intent,
            error::invalid_argument(ECHAIN_INFO_NOT_INITIALIZED)
        );
        // Only allow initialization if ChainInfo doesn't exist yet
        assert!(
            !exists<ChainInfo>(module_addr),
            error::invalid_state(ECHAIN_INFO_ALREADY_INITIALIZED)
        );
        move_to(account, ChainInfo { chain_id });
    }

    /// Get the chain ID where this module is deployed.
    ///
    /// # Aborts
    /// - `ECHAIN_INFO_NOT_INITIALIZED`: If chain info has not been initialized
    fun get_chain_id(): u64 acquires ChainInfo {
        // ChainInfo is stored at the module deployer's address (same as @mvmt_intent)
        let module_addr = @mvmt_intent;
        assert!(
            exists<ChainInfo>(module_addr),
            error::invalid_state(ECHAIN_INFO_NOT_INITIALIZED)
        );
        borrow_global<ChainInfo>(module_addr).chain_id
    }

    /// Witness type for fungible asset intent completion.
    /// Empty struct that can only be created after verifying trading conditions.
    struct FungibleAssetRecipientWitness has drop {}

    #[event]
    /// Event emitted when a fungible asset limit order intent is created.
    /// Contains all the trading details that solvers need to evaluate the opportunity.
    struct LimitOrderEvent has store, drop {
        intent_addr: address,
        intent_id: address, // For cross-chain linking: same as intent_addr for regular intents, or shared ID for linked cross-chain intents
        offered_metadata: Object<Metadata>, // Required for type compatibility, but may be placeholder for cross-chain
        offered_metadata_addr: Option<address>, // Raw address for cross-chain tokens, None for same-chain
        offered_amount: u64,
        offered_chain_id: u64,
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        desired_chain_id: u64,
        requester_addr: address,
        expiry_time: u64,
        revocable: bool,
        reserved_solver: Option<address>, // Solver address if the intent is reserved (None for unreserved intents)
        requester_addr_connected_chain: Option<address> // Requester address on connected chain (for inflow intents)
    }

    #[event]
    /// Event emitted when a fungible asset limit order intent is fulfilled.
    /// Contains details about who fulfilled the intent and what they provided.
    struct LimitOrderFulfillmentEvent has store, drop {
        intent_addr: address,
        intent_id: address, // For cross-chain linking
        solver: address, // Who fulfilled the intent
        provided_metadata: Object<Metadata>,
        provided_amount: u64,
        timestamp: u64
    }

    /// Creates a fungible asset to fungible asset trading intent.
    ///
    /// This function locks the source fungible asset in a store and creates an intent
    /// that can only be completed by providing the desired fungible asset.
    ///
    /// # Arguments
    /// - `offered_fungible_asset`: The fungible asset being offered.
    ///   NOTE: This cannot be `Option<FungibleAsset>` because `FungibleAsset` doesn't have `drop`
    ///   and must be consumed. For cross-chain inflow intents (offered_chain_id != this_chain_id),
    ///   a placeholder FA must be provided (amount 0, using desired_metadata). The actual offered
    ///   amount and metadata address are provided via `offered_amount_override` and `offered_metadata_addr_override`.
    /// - `offered_chain_id`: Chain ID where offered tokens are located
    /// - `offered_amount_override`: Optional explicit offered amount (required when offered_chain_id != this_chain_id)
    /// - `offered_metadata_addr_override`: Optional explicit offered metadata address (required when offered_chain_id != this_chain_id)
    /// - `desired_metadata`: Metadata of the desired token type
    /// - `desired_amount`: Minimum amount of the desired token required
    /// - `desired_chain_id`: Chain ID where desired tokens are located
    /// - `expiry_time`: Unix timestamp when the intent expires
    /// - `requester`: Address of the intent creator
    /// - `reservation`: Optional solver reservation
    /// - `revocable`: Whether the intent can be revoked
    /// - `intent_id`: Optional cross-chain intent_id (None for regular intents)
    ///
    /// # Returns
    /// - `Object<Intent<FungibleStoreManager, FungibleAssetLimitOrder>>`: Intent object
    public fun create_fa_to_fa_intent(
        offered_fungible_asset: FungibleAsset,
        offered_chain_id: u64,
        offered_amount_override: Option<u64>, // Optional explicit offered amount for cross-chain intents
        offered_metadata_addr_override: Option<address>, // Optional explicit offered metadata address for cross-chain intents
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        desired_chain_id: u64,
        expiry_time: u64,
        requester_addr: address,
        reservation: Option<IntentReserved>,
        revocable: bool,
        intent_id: Option<address>, // Optional cross-chain intent_id (None for regular intents)
        requester_addr_connected_chain: Option<address> // Optional requester address on connected chain (for inflow intents)
    ): Object<Intent<FungibleStoreManager, FungibleAssetLimitOrder>> acquires ChainInfo {
        // Capture metadata before depositing
        let offered_metadata = fungible_asset::asset_metadata(&offered_fungible_asset);
        
        // Determine offered_amount and offered_metadata_addr:
        // - If offered_chain_id == this_chain_id: tokens are locked on this chain, use FA amount and metadata
        // - If offered_chain_id != this_chain_id: tokens are locked elsewhere, use explicit parameters
        let this_chain_id = get_chain_id();
        let (offered_amount, event_offered_metadata_addr) = if (offered_chain_id == this_chain_id) {
            // Same-chain: use FA amount, no metadata address override needed
            (fungible_asset::amount(&offered_fungible_asset), option::none<address>())
        } else {
            // Cross-chain: must provide explicit amount and metadata address
            assert!(
                option::is_some(&offered_amount_override),
                error::invalid_argument(EAMOUNT_NOT_MEET)
            );
            assert!(
                option::is_some(&offered_metadata_addr_override),
                error::invalid_argument(EINVALID_METADATA_ADDRESS)
            );
            (*option::borrow(&offered_amount_override), offered_metadata_addr_override)
        };

        let coin_store_ref = object::create_object(requester_addr);
        let extend_ref = object::generate_extend_ref(&coin_store_ref);
        let delete_ref = object::generate_delete_ref(&coin_store_ref);
        let transfer_ref = object::generate_transfer_ref(&coin_store_ref);
        let linear_ref = object::generate_linear_transfer_ref(&transfer_ref);
        object::transfer_with_ref(
            linear_ref, object::address_from_constructor_ref(&coin_store_ref)
        );

        fungible_asset::create_store(
            &coin_store_ref,
            fungible_asset::metadata_from_asset(&offered_fungible_asset)
        );
        fungible_asset::deposit(
            object::object_from_constructor_ref<FungibleStore>(&coin_store_ref),
            offered_fungible_asset
        );
        
        // Extract solver from reservation if present (before reservation is moved into create_intent)
        let reserved_solver = if (option::is_some(&reservation)) {
            let reservation_ref = option::borrow(&reservation);
            option::some(intent_reservation::solver(reservation_ref))
        } else {
            option::none<address>()
        };
        
        let intent_obj =
            intent::create_intent<FungibleStoreManager, FungibleAssetLimitOrder, FungibleAssetRecipientWitness>(
                FungibleStoreManager { extend_ref, delete_ref },
                FungibleAssetLimitOrder {
                    desired_metadata,
                    desired_amount,
                    requester_addr,
                    intent_id,
                    offered_chain_id,
                    desired_chain_id
                },
                expiry_time,
                requester_addr,
                FungibleAssetRecipientWitness {},
                reservation,
                revocable
            );

        // Emit event after creating intent so we have the intent address
        let intent_addr = object::object_address(&intent_obj);
        // Use intent_id from argument if present (cross-chain), otherwise use intent_addr (regular)
        let event_intent_id =
            if (option::is_some(&intent_id)) {
                *option::borrow(&intent_id)
            } else {
                intent_addr
            };
        event::emit(
            LimitOrderEvent {
                intent_addr,
                intent_id: event_intent_id,
                offered_metadata,
                offered_metadata_addr: event_offered_metadata_addr,
                offered_amount,
                offered_chain_id,
                desired_metadata,
                desired_amount,
                desired_chain_id,
                expiry_time,
                requester_addr,
                revocable,
                reserved_solver,
                requester_addr_connected_chain
            }
        );

        intent_obj
    }

    /// Entry function to create a fungible asset limit order intent.
    ///
    /// This function withdraws the specified amount of source tokens from the caller's
    /// primary fungible store and creates a limit order intent.
    ///
    /// # Arguments
    /// - `account`: Signer of the account creating the intent
    /// - `offered_metadata`: Metadata of the token being offered
    /// - `offered_amount`: Amount of tokens being offered
    /// - `desired_metadata`: Metadata of the desired token type
    /// - `desired_amount`: Minimum amount of desired tokens required
    /// - `expiry_time`: Unix timestamp when the intent expires
    /// - `chain_id`: Chain ID where this intent is created (same for both offered and desired)
    /// - `_issuer`: Address of the intent creator (must match signer)
    public entry fun create_fa_to_fa_intent_entry(
        account: &signer,
        offered_metadata: Object<Metadata>,
        offered_amount: u64,
        desired_metadata: Object<Metadata>,
        desired_amount: u64,
        expiry_time: u64,
        chain_id: u64,
        solver: address,
        solver_signature: vector<u8>
    ) acquires ChainInfo {
        let requester_addr = signer::address_of(account);
        let reservation =
            if (vector::is_empty(&solver_signature)) {
                option::none() // Explicitly unreserved intent
            } else {
                let intent_to_sign =
                    intent_reservation::new_intent_to_sign(
                        offered_metadata,
                        offered_amount,
                        chain_id,
                        desired_metadata,
                        desired_amount,
                        chain_id,
                        expiry_time,
                        requester_addr,
                        solver
                    );
                let result =
                    intent_reservation::verify_and_create_reservation(
                        intent_to_sign, solver_signature
                    );
                // Fail if signature verification failed instead of silently falling back
                assert!(
                    option::is_some(&result),
                    error::invalid_argument(EINVALID_SIGNATURE)
                );
                result
            };

        let fa =
            primary_fungible_store::withdraw(account, offered_metadata, offered_amount);
        create_fa_to_fa_intent(
            fa,
            chain_id, // offered_chain_id (same chain for regular intents)
            option::none(), // No offered_amount_override needed - tokens are locked on this chain
            option::none(), // No offered_metadata_addr_override needed - tokens are locked on this chain
            desired_metadata,
            desired_amount,
            chain_id, // desired_chain_id (same chain for regular intents)
            expiry_time,
            requester_addr,
            reservation,
            true, // revocable by default for regular intents
            option::none(), // No cross-chain intent_id for regular intents
            option::none() // No requester_addr_connected_chain for same-chain intents
        );
    }

    /// Starts a fungible asset offering session by unlocking the stored assets.
    ///
    /// This function extracts the fungible assets from the store manager and
    /// returns them along with the trading session.
    ///
    /// # Arguments
    /// - `intent`: Object reference to the fungible asset intent
    ///
    /// # Returns
    /// - `FungibleAsset`: The unlocked fungible asset
    /// - `Session<Args>`: Trading session containing the conditions
    public fun start_fa_offering_session<Args: store + drop>(
        solver: &signer, intent: Object<Intent<FungibleStoreManager, Args>>
    ): (FungibleAsset, Session<Args>) {
        let (store_manager, session) = intent::start_intent_session(intent);
        let reservation = intent::get_reservation(&session);
        intent_reservation::ensure_solver_authorized(solver, reservation);
        (destroy_store_manager(store_manager), session)
    }

    /// Destroys a fungible store manager and extracts all assets from the store.
    ///
    /// This helper function withdraws all fungible assets from the store and
    /// cleans up the store references.
    ///
    /// # Arguments
    /// - `store_manager`: The store manager to destroy
    ///
    /// # Returns
    /// - `FungibleAsset`: All assets that were in the store
    fun destroy_store_manager(store_manager: FungibleStoreManager): FungibleAsset {
        let FungibleStoreManager { extend_ref, delete_ref } = store_manager;
        let store_signer = object::generate_signer_for_extending(&extend_ref);
        let fa_store = object::object_from_delete_ref<FungibleStore>(&delete_ref);
        let fa =
            fungible_asset::withdraw(
                &store_signer, fa_store, fungible_asset::balance(fa_store)
            );
        fungible_asset::remove_store(&delete_ref);
        object::delete(delete_ref);
        fa
    }

    /// Completes a fungible asset intent session by verifying and depositing the received assets.
    ///
    /// This function verifies that the received fungible asset matches the trading
    /// conditions (correct token type and sufficient amount) and deposits it to
    /// the intent creator's primary fungible store.
    ///
    /// # Arguments
    /// - `session`: The trading session to complete (consumed)
    /// - `received_fa`: The fungible asset received from the trade
    ///
    /// # Aborts
    /// - `ENOT_DESIRED_TOKEN`: If the received asset is not the desired token type
    /// - `EAMOUNT_NOT_MEET`: If the received amount is less than the required amount
    /// Completes a receiving session with the provided fungible asset and emits fulfillment event.
    ///
    /// # Arguments
    /// - `session`: The trade session to complete
    /// - `received_fa`: The fungible asset received
    /// - `intent_addr`: The address of the intent being fulfilled
    /// - `solver`: The address of the solver who fulfilled the intent
    public fun finish_fa_receiving_session_with_event(
        session: Session<FungibleAssetLimitOrder>,
        received_fa: FungibleAsset,
        intent_addr: address,
        solver: address
    ) {
        let argument = intent::get_argument(&session);

        // Capture metadata and amount before depositing (received_fa doesn't have copy ability)
        let provided_metadata = fungible_asset::metadata_from_asset(&received_fa);
        let provided_amount = fungible_asset::amount(&received_fa);

        assert!(
            provided_metadata == argument.desired_metadata,
            error::invalid_argument(ENOT_DESIRED_TOKEN)
        );
        assert!(
            provided_amount >= argument.desired_amount,
            error::invalid_argument(EAMOUNT_NOT_MEET)
        );

        primary_fungible_store::deposit(argument.requester_addr, received_fa);

        // Emit fulfillment event
        let timestamp = timestamp::now_seconds();

        // Use intent_id from argument if present (cross-chain), otherwise use intent_addr (regular)
        let fulfillment_intent_id =
            if (option::is_some(&argument.intent_id)) {
                *option::borrow(&argument.intent_id)
            } else {
                intent_addr
            };

        event::emit(
            LimitOrderFulfillmentEvent {
                intent_addr: intent_addr,
                intent_id: fulfillment_intent_id,
                solver,
                provided_metadata,
                provided_amount,
                timestamp
            }
        );

        intent::finish_intent_session(session, FungibleAssetRecipientWitness {})
    }

    /// Legacy version without event - kept for compatibility
    public fun finish_fa_receiving_session(
        session: Session<FungibleAssetLimitOrder>, received_fa: FungibleAsset
    ) {
        let argument = intent::get_argument(&session);
        assert!(
            fungible_asset::metadata_from_asset(&received_fa)
                == argument.desired_metadata,
            error::invalid_argument(ENOT_DESIRED_TOKEN)
        );
        assert!(
            fungible_asset::amount(&received_fa) >= argument.desired_amount,
            error::invalid_argument(EAMOUNT_NOT_MEET)
        );

        primary_fungible_store::deposit(argument.requester_addr, received_fa);
        intent::finish_intent_session(session, FungibleAssetRecipientWitness {})
    }

    /// Entry function to revoke a fungible asset intent and return the locked assets.
    ///
    /// This function allows the intent owner to cancel their intent and get back
    /// their locked fungible assets before the intent expires or is completed.
    ///
    /// # Arguments
    /// - `account`: Signer of the intent owner
    /// - `intent`: Object reference to the intent to revoke
    public entry fun revoke_fa_intent<Args: store + drop>(
        account: &signer, intent: Object<Intent<FungibleStoreManager, Args>>
    ) {
        let store_manager = intent::revoke_intent(account, intent);
        let fa = destroy_store_manager(store_manager);
        primary_fungible_store::deposit(signer::address_of(account), fa);
    }
}
