//! Signing Service
//!
//! Main service loop that polls the verifier for pending drafts,
//! evaluates acceptance, and signs/submits accepted drafts.

use crate::acceptance::{should_accept_draft, AcceptanceConfig, AcceptanceResult, DraftIntentData};
use crate::config::SolverConfig;
use crate::crypto::{get_intent_hash, get_private_key_from_profile, sign_intent_hash};
use crate::verifier_client::{PendingDraft, VerifierClient};
use anyhow::{Context, Result};
use serde_json::Value;
use std::time::Duration;
use tracing::{debug, error, info, warn};

/// Signing service that polls verifier and signs accepted drafts.
pub struct SigningService {
    /// Solver configuration
    config: SolverConfig,
    /// Acceptance configuration (token pairs and exchange rates)
    acceptance_config: AcceptanceConfig,
}

impl SigningService {
    /// Create a new signing service.
    ///
    /// # Arguments
    ///
    /// * `config` - Solver configuration loaded from TOML
    ///
    /// # Returns
    ///
    /// * `Result<SigningService>` - New service instance or error
    pub fn new(config: SolverConfig) -> Result<Self> {
        // Convert config token pairs to AcceptanceConfig
        let token_pairs = config.get_token_pairs()?;
        let acceptance_config = AcceptanceConfig {
            token_pairs,
        };

        Ok(Self {
            config,
            acceptance_config,
        })
    }

    /// Run the main signing service loop.
    ///
    /// This function polls the verifier for pending drafts at the configured interval,
    /// evaluates each draft for acceptance, and signs/submits accepted drafts.
    ///
    /// Runs indefinitely until the service is stopped.
    pub async fn run(&self) -> Result<()> {
        let polling_interval = Duration::from_millis(self.config.service.polling_interval_ms);

        info!("Starting signing service loop (polling interval: {:?})", polling_interval);

        loop {
            // Poll for pending drafts
            match self.poll_and_process_drafts().await {
                Ok(processed) => {
                    if processed > 0 {
                        info!("Processed {} draft(s)", processed);
                    }
                }
                Err(e) => {
                    error!("Error in signing loop: {}", e);
                }
            }

            // Sleep for polling interval
            tokio::time::sleep(polling_interval).await;
        }
    }

    /// Poll verifier for pending drafts and process them.
    ///
    /// # Returns
    ///
    /// * `Result<usize>` - Number of drafts processed
    async fn poll_and_process_drafts(&self) -> Result<usize> {
        // Clone base_url for spawn_blocking
        let base_url = self.config.service.verifier_url.clone();
        let drafts = tokio::task::spawn_blocking(move || {
            let client = VerifierClient::new(&base_url);
            client.poll_pending_drafts()
        })
        .await
        .context("Failed to spawn blocking task")?
        .context("Failed to poll pending drafts")?;

        if drafts.is_empty() {
            debug!("No pending drafts");
            return Ok(0);
        }

        info!("Found {} pending draft(s)", drafts.len());

        let mut processed = 0;
        for draft in drafts {
            match self.process_draft(&draft).await {
                Ok(true) => {
                    processed += 1;
                    info!("Successfully signed and submitted draft {}", draft.draft_id);
                }
                Ok(false) => {
                    debug!("Draft {} was not accepted or already signed", draft.draft_id);
                }
                Err(e) => {
                    error!("Error processing draft {}: {}", draft.draft_id, e);
                }
            }
        }

        Ok(processed)
    }

    /// Process a single draft intent.
    ///
    /// Evaluates acceptance and signs/submits if accepted.
    ///
    /// # Arguments
    ///
    /// * `draft` - Pending draft from verifier
    ///
    /// # Returns
    ///
    /// * `Result<bool>` - `true` if draft was signed and submitted, `false` otherwise
    pub async fn process_draft(&self, draft: &PendingDraft) -> Result<bool> {
        // Check if draft has expired
        let now = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs();

        if now >= draft.expiry_time {
            debug!("Draft {} has expired (expiry: {}, now: {})", draft.draft_id, draft.expiry_time, now);
            return Ok(false);
        }

        // Parse draft data
        let draft_data = self.parse_draft_data(&draft.draft_data)?;

        // Evaluate acceptance
        match should_accept_draft(&draft_data, &self.acceptance_config) {
            AcceptanceResult::Accept => {
                info!("Draft {} accepted, signing...", draft.draft_id);
                self.sign_and_submit(draft, &draft_data).await
            }
            AcceptanceResult::Reject(reason) => {
                debug!("Draft {} rejected: {}", draft.draft_id, reason);
                Ok(false)
            }
        }
    }

    /// Parse draft data from JSON value.
    ///
    /// # Arguments
    ///
    /// * `draft_data` - JSON value containing draft data
    ///
    /// # Returns
    ///
    /// * `Result<DraftIntentData>` - Parsed draft data
    fn parse_draft_data(&self, draft_data: &Value) -> Result<DraftIntentData> {
        parse_draft_data(draft_data)
    }

    /// Sign a draft intent and submit to verifier.
    ///
    /// # Arguments
    ///
    /// * `draft` - Pending draft from verifier
    /// * `draft_data` - Parsed draft data
    ///
    /// # Returns
    ///
    /// * `Result<bool>` - `true` if signature was successfully submitted, `false` if already signed (FCFS)
    async fn sign_and_submit(
        &self,
        draft: &PendingDraft,
        draft_data: &DraftIntentData,
    ) -> Result<bool> {
        // Get solver profile and address from config
        let profile = &self.config.solver.profile;
        let solver_address = &self.config.solver.address;

        // Get module address and chain number from hub chain config
        let module_address = self.config.hub_chain.module_address
            .strip_prefix("0x")
            .context("Module address must start with 0x")?;
        let chain_num = 1u8; // Hub chain is always chain 1

        // Get private key
        let private_key = get_private_key_from_profile(profile)
            .context("Failed to get private key from profile")?;

        // Get intent hash
        let hash = get_intent_hash(
            profile,
            module_address,
            &draft_data.offered_token,
            draft_data.offered_amount,
            draft_data.offered_chain_id,
            &draft_data.desired_token,
            draft_data.desired_amount,
            draft_data.desired_chain_id,
            draft.expiry_time,
            &draft.requester_address,
            solver_address,
            chain_num,
        )
        .context("Failed to get intent hash")?;

        // Sign the hash
        let (signature_bytes, public_key_bytes) = sign_intent_hash(&hash, &private_key)
            .context("Failed to sign intent hash")?;

        // Convert to hex strings
        let signature_hex = hex::encode(signature_bytes);
        let public_key_hex = hex::encode(public_key_bytes);

        // Submit signature to verifier
        // Use spawn_blocking since verifier_client uses blocking HTTP
        let base_url = self.config.service.verifier_url.clone();
        let draft_id_for_log = draft.draft_id.clone();
        let draft_id_for_submit = draft.draft_id.clone();
        let submission = crate::verifier_client::SignatureSubmission {
            solver_address: solver_address.clone(),
            signature: signature_hex,
            public_key: public_key_hex,
        };
        let result = tokio::task::spawn_blocking(move || {
            let client = VerifierClient::new(&base_url);
            client.submit_signature(&draft_id_for_submit, &submission)
        })
        .await
        .context("Failed to spawn blocking task")?;

        // Check result - if error contains "already signed" or "409", it's FCFS conflict
        match result {
            Ok(_) => {
                info!("Successfully submitted signature for draft {}", draft_id_for_log);
                Ok(true)
            }
            Err(e) => {
                let error_msg = e.to_string();
                if error_msg.contains("already signed") || error_msg.contains("409") || error_msg.contains("Conflict") {
                    warn!("Draft {} already signed by another solver (FCFS)", draft_id_for_log);
                    Ok(false)
                } else {
                    Err(e).context("Failed to submit signature")
                }
            }
        }
    }
}

/// Parse draft data from JSON value.
///
/// Extracts intent fields from the JSON structure returned by the verifier.
///
/// # Arguments
///
/// * `draft_data` - JSON value containing draft data
///
/// # Returns
///
/// * `Result<DraftIntentData>` - Parsed draft data
pub fn parse_draft_data(draft_data: &Value) -> Result<DraftIntentData> {
    // Extract fields from draft_data JSON
    // Expected structure matches Move IntentDraft:
    // {
    //   "offered_metadata": {"inner": "0x..."},
    //   "offered_amount": 1000,
    //   "offered_chain_id": 1,
    //   "desired_metadata": {"inner": "0x..."},
    //   "desired_amount": 2000,
    //   "desired_chain_id": 2,
    //   "expiry_time": 1234567890,
    //   ...
    // }

    let offered_metadata = draft_data["offered_metadata"]["inner"]
        .as_str()
        .context("Missing or invalid offered_metadata.inner")?;

    let offered_amount = draft_data["offered_amount"]
        .as_u64()
        .context("Missing or invalid offered_amount")?;

    let offered_chain_id = draft_data["offered_chain_id"]
        .as_u64()
        .context("Missing or invalid offered_chain_id")?;

    let desired_metadata = draft_data["desired_metadata"]["inner"]
        .as_str()
        .context("Missing or invalid desired_metadata.inner")?;

    let desired_amount = draft_data["desired_amount"]
        .as_u64()
        .context("Missing or invalid desired_amount")?;

    let desired_chain_id = draft_data["desired_chain_id"]
        .as_u64()
        .context("Missing or invalid desired_chain_id")?;

    Ok(DraftIntentData {
        offered_token: offered_metadata.to_string(),
        offered_amount,
        offered_chain_id,
        desired_token: desired_metadata.to_string(),
        desired_amount,
        desired_chain_id,
    })
}

