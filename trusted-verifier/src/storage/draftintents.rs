//! Draft Intent Storage Module
//!
//! This module provides in-memory storage for draft intents used in the
//! negotiation routing system. Drafts are stored with metadata and can be
//! queried by ID or retrieved as pending drafts for solvers to poll.

use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::RwLock;

// ============================================================================
// DATA STRUCTURES
// ============================================================================

/// Status of a draft intent.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DraftintentStatus {
    /// Draft is pending and waiting for solver signature
    Pending,
    /// Draft has been signed by a solver (first signature wins - FCFS)
    Signed,
    /// Draft has expired
    Expired,
}

/// First signature received for a draft intent (FCFS - First Come First Served).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DraftSignature {
    /// Address of the solver who signed (first signer wins)
    pub solver_address: String,
    /// Signature in hex format
    pub signature: String,
    /// Public key of the solver (hex format)
    pub public_key: String,
    /// Timestamp when signature was received (Unix timestamp)
    pub signature_timestamp: u64,
}

/// Draft intent data structure.
///
/// Represents a draft intent submitted by a requester, open to any solver.
/// The first solver to sign wins (FCFS).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Draftintent {
    /// Unique identifier for the draft (UUID or hash)
    pub draft_id: String,
    /// Address of the requester who submitted the draft
    pub requester_address: String,
    /// Draft data (JSON object - matches Draftintent structure from Move)
    pub draft_data: serde_json::Value,
    /// Current status of the draft
    pub status: DraftintentStatus,
    /// Timestamp when draft was created (Unix timestamp)
    pub timestamp: u64,
    /// Expiry time (Unix timestamp)
    pub expiry_time: u64,
    /// First signature received (None if not yet signed)
    pub signature: Option<DraftSignature>,
}

// ============================================================================
// STORAGE IMPLEMENTATION
// ============================================================================

/// In-memory storage for draft intents.
///
/// Uses HashMap for O(1) lookup by draft_id. Thread-safe via RwLock.
/// All solvers see all pending drafts (no filtering).
pub struct DraftintentStore {
    /// Map of draft_id -> Draftintent
    drafts: RwLock<HashMap<String, Draftintent>>,
}

impl DraftintentStore {
    /// Create a new draft intent store.
    pub fn new() -> Self {
        Self {
            drafts: RwLock::new(HashMap::new()),
        }
    }

    /// Add a new draft intent.
    ///
    /// # Arguments
    ///
    /// * `draft_id` - Unique identifier for the draft
    /// * `requester_address` - Address of the requester
    /// * `draft_data` - Draft data (JSON)
    /// * `expiry_time` - Expiry timestamp
    ///
    /// # Returns
    ///
    /// The created Draftintent
    pub async fn add_draft(
        &self,
        draft_id: String,
        requester_address: String,
        draft_data: serde_json::Value,
        expiry_time: u64,
    ) -> Draftintent {
        let timestamp = Self::current_timestamp();
        let draft = Draftintent {
            draft_id: draft_id.clone(),
            requester_address,
            draft_data,
            status: DraftintentStatus::Pending,
            timestamp,
            expiry_time,
            signature: None,
        };

        let mut drafts = self.drafts.write().await;
        drafts.insert(draft_id, draft.clone());
        draft
    }

    /// Get a draft intent by ID.
    ///
    /// # Arguments
    ///
    /// * `draft_id` - The draft ID to retrieve
    ///
    /// # Returns
    ///
    /// * `Some(Draftintent)` if found
    /// * `None` if not found
    pub async fn get_draft(&self, draft_id: &str) -> Option<Draftintent> {
        let drafts = self.drafts.read().await;
        drafts.get(draft_id).cloned()
    }

    /// Get all pending drafts.
    ///
    /// Returns all drafts with status=Pending that haven't expired.
    /// All solvers see all pending drafts (no filtering).
    ///
    /// # Returns
    ///
    /// Vector of pending draft intents
    pub async fn get_pending_drafts(&self) -> Vec<Draftintent> {
        let drafts = self.drafts.read().await;
        let current_time = Self::current_timestamp();

        drafts
            .values()
            .filter(|draft| {
                draft.status == DraftintentStatus::Pending && draft.expiry_time > current_time
            })
            .cloned()
            .collect()
    }

    /// Update draft status to signed and store signature (FCFS).
    ///
    /// Only succeeds if draft is currently pending (first signature wins).
    ///
    /// # Arguments
    ///
    /// * `draft_id` - The draft ID
    /// * `solver_address` - Address of the solver signing
    /// * `signature` - Signature in hex format
    /// * `public_key` - Public key in hex format
    ///
    /// # Returns
    ///
    /// * `Ok(())` if signature was accepted (first signature)
    /// * `Err(String)` if draft not found, already signed, or expired
    pub async fn add_signature(
        &self,
        draft_id: &str,
        solver_address: String,
        signature: String,
        public_key: String,
    ) -> Result<(), String> {
        let mut drafts = self.drafts.write().await;
        let draft = drafts.get_mut(draft_id).ok_or("Draft not found")?;

        // FCFS: Only accept if still pending
        if draft.status != DraftintentStatus::Pending {
            return Err("Draft already signed or expired".to_string());
        }

        // Check expiry
        let current_time = Self::current_timestamp();
        if draft.expiry_time <= current_time {
            draft.status = DraftintentStatus::Expired;
            return Err("Draft expired".to_string());
        }

        // Store first signature
        draft.signature = Some(DraftSignature {
            solver_address,
            signature,
            public_key,
            signature_timestamp: current_time,
        });
        draft.status = DraftintentStatus::Signed;

        Ok(())
    }

    /// Remove expired drafts (cleanup).
    ///
    /// Marks drafts as expired if their expiry_time has passed.
    #[allow(dead_code)] // Will be used in Task 2 (periodic cleanup task)
    pub async fn cleanup_expired(&self) {
        let mut drafts = self.drafts.write().await;
        let current_time = Self::current_timestamp();

        for draft in drafts.values_mut() {
            if draft.status == DraftintentStatus::Pending && draft.expiry_time <= current_time {
                draft.status = DraftintentStatus::Expired;
            }
        }
    }

    /// Get current Unix timestamp.
    fn current_timestamp() -> u64 {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs()
    }
}

impl Default for DraftintentStore {
    fn default() -> Self {
        Self::new()
    }
}


