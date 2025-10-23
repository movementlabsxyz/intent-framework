module aptos_intent::intent {
    use std::error;
    use std::signer;
    use std::option::Option;
    use aptos_framework::object::{Self, DeleteRef, Object};
    use aptos_framework::timestamp;
    use aptos_framework::type_info::{Self, TypeInfo};
    use aptos_intent::intent_reservation::IntentReserved;

    /// The offered intent has expired
    const EINTENT_EXPIRED: u64 = 0;

    /// The registered hook function for consuming resource doesn't match the type requirement.
    const ECONSUMPTION_FUNCTION_TYPE_MISMATCH: u64 = 1;

    /// Only owner can revoke an intent.
    const ENOT_OWNER: u64 = 2;

    /// Provided wrong witness to complete intent.
    const EINVALID_WITNESS: u64 = 3;

    /// Intent is not revocable by the owner.
    const ENOT_REVOCABLE: u64 = 4;

    /// Core intent structure that locks a resource until specific conditions are met.
    /// 
    /// - `offered_resource`: The resource being offered for trade
    /// - `argument`: Trading conditions and parameters
    /// - `self_delete_ref`: Reference to delete the intent object
    /// - `expiry_time`: Unix timestamp when the intent expires
    /// - `witness_type`: Type information for the required witness
    /// - `revocable`: Whether the intent can be revoked by the owner
    struct TradeIntent<Source, Args> has key {
        offered_resource: Source,
        argument: Args,
        self_delete_ref: DeleteRef,
        expiry_time: u64,
        witness_type: TypeInfo,
        reservation: Option<IntentReserved>,
        revocable: bool,
    }

    /// Active trading session containing the conditions and witness requirements.
    /// This is a "hot potato" type that must be consumed by calling finish_intent_session.
    struct TradeSession<Args> {
        argument: Args,
        witness_type: TypeInfo,
        reservation: Option<IntentReserved>,
    }

    // Core offering logic

    /// Creates a new trade intent that locks a resource until specific conditions are met.
    /// 
    /// The intent can only be completed by providing a witness of the specified type,
    /// or revoked by the owner if revocable is true.
    /// 
    /// # Arguments
    /// - `offered_resource`: The resource to be locked in the intent
    /// - `argument`: Trading conditions and parameters
    /// - `expiry_time`: Unix timestamp when the intent expires
    /// - `issuer`: Address of the intent creator
    /// - `_witness`: Witness type that must be provided to complete the intent
    /// - `revocable`: Whether the intent can be revoked by the owner
    /// 
    /// # Returns
    /// - `Object<TradeIntent<Source, Args>>`: Object reference to the created intent
    public fun create_intent<Source: store, Args: store + drop, Witness: drop>(
        offered_resource: Source,
        argument: Args,
        expiry_time: u64,
        issuer: address,
        _witness: Witness,
        reservation: Option<IntentReserved>,
        revocable: bool,
    ): Object<TradeIntent<Source, Args>> {
        let constructor_ref = object::create_object(issuer);
        let object_signer = object::generate_signer(&constructor_ref);
        let self_delete_ref = object::generate_delete_ref(&constructor_ref);

        move_to<TradeIntent<Source, Args>>(
            &object_signer,
            TradeIntent {
                offered_resource,
                argument,
                expiry_time,
                self_delete_ref,
                witness_type: type_info::type_of<Witness>(),
                reservation,
                revocable,
            }
        );
        object::object_from_constructor_ref(&constructor_ref)
    }

    /// Starts an intent session by unlocking the offered resource and creating a trading session.
    /// 
    /// This function checks that the intent hasn't expired and then destroys the intent object,
    /// returning the locked resource and a session that must be completed with finish_intent_session.
    /// 
    /// # Arguments
    /// - `intent`: Object reference to the intent to start
    /// 
    /// # Returns
    /// - `Source`: The unlocked resource that was offered
    /// - `TradeSession<Args>`: Session containing trading conditions (hot potato type)
    /// 
    /// # Aborts
    /// - `EINTENT_EXPIRED`: If the current time exceeds the intent's expiry time
    public fun start_intent_session<Source: store, Args: store + drop>(
        intent: Object<TradeIntent<Source, Args>>,
    ): (Source, TradeSession<Args>) acquires TradeIntent {
        let intent_ref = borrow_global<TradeIntent<Source, Args>>(object::object_address(&intent));
        assert!(timestamp::now_seconds() <= intent_ref.expiry_time, error::permission_denied(EINTENT_EXPIRED));

        let TradeIntent {
            offered_resource,
            argument,
            expiry_time: _,
            self_delete_ref,
            witness_type,
            reservation,
            revocable: _,
        } = move_from<TradeIntent<Source, Args>>(object::object_address(&intent));

        object::delete(self_delete_ref);

        return (offered_resource, TradeSession {
            argument,
            witness_type,
            reservation,
        })
    }

    /// Retrieves the trading conditions from a trading session.
    /// 
    /// # Arguments
    /// - `session`: Reference to the trading session
    /// 
    /// # Returns
    /// - `&Args`: Reference to the trading conditions
    public fun get_argument<Args>(session: &TradeSession<Args>): &Args {
        &session.argument
    }

    /// Retrieves the reservation from a trading session.
    ///
    /// # Arguments
    /// - `session`: Reference to the trading session
    ///
    /// # Returns
    /// - `&Option<IntentReserved>`: Reference to the reservation
    public fun get_reservation<Args>(session: &TradeSession<Args>): &Option<IntentReserved> {
        &session.reservation
    }

    /// Completes an intent session by providing the required witness.
    /// 
    /// This function verifies that the provided witness type matches the one
    /// required by the original intent. The witness serves as proof that the
    /// trading conditions have been satisfied.
    /// 
    /// # Arguments
    /// - `session`: The trading session to complete (consumed)
    /// - `_witness`: The witness proving conditions were met
    /// 
    /// # Aborts
    /// - `EINVALID_WITNESS`: If the witness type doesn't match the required type
    public fun finish_intent_session<Witness: drop, Args: store + drop>(
        session: TradeSession<Args>,
        _witness: Witness,
    ) {
        let TradeSession {
            argument:_ ,
            witness_type,
            reservation: _,
        } = session;

        assert!(type_info::type_of<Witness>() == witness_type, error::permission_denied(EINVALID_WITNESS));
    }

    /// Revokes an intent and returns the locked resource to the original owner.
    /// 
    /// Only the owner of the intent can revoke it. This function destroys the intent
    /// object and returns the offered resource to the issuer.
    /// 
    /// # Arguments
    /// - `issuer`: Signer of the intent owner
    /// - `intent`: Object reference to the intent to revoke
    /// 
    /// # Returns
    /// - `Source`: The locked resource that was offered
    /// 
    /// # Aborts
    /// - `ENOT_OWNER`: If the signer is not the owner of the intent
    /// - `ENOT_REVOCABLE`: If the intent is not revocable
    public fun revoke_intent<Source: store, Args: store + drop>(
        issuer: &signer,
        intent: Object<TradeIntent<Source, Args>>,
    ): Source acquires TradeIntent {
        assert!(object::owner(intent) == signer::address_of(issuer), error::permission_denied(ENOT_OWNER));
        let TradeIntent {
            offered_resource,
            argument: _,
            expiry_time: _,
            self_delete_ref,
            witness_type: _,
            reservation: _,
            revocable,
        } = move_from<TradeIntent<Source, Args>>(object::object_address(&intent));

        assert!(revocable, error::permission_denied(ENOT_REVOCABLE));
        object::delete(self_delete_ref);
        offered_resource
    }
}
