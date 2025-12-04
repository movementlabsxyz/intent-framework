//! Verifier API Client
//!
//! HTTP client for communicating with the Trusted Verifier service.
//! Provides methods for polling pending drafts, submitting signatures,
//! and validating fulfillments.

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::time::Duration;

// ============================================================================
// API RESPONSE WRAPPER
// ============================================================================

/// Standardized response structure from verifier API.
///
/// All verifier endpoints return this format:
/// ```json
/// {
///   "success": true|false,
///   "data": <payload>|null,
///   "error": <message>|null
/// }
/// ```
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ApiResponse<T> {
    /// Whether the request was successful
    pub success: bool,
    /// Response data (if successful)
    pub data: Option<T>,
    /// Error message (if failed)
    pub error: Option<String>,
}

// ============================================================================
// DRAFT-INTENT STRUCTURES
// ============================================================================

/// Pending draftintent from verifier API.
///
/// Matches the response format from GET /draftintents/pending.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PendingDraft {
    /// Unique identifier for the draft
    pub draft_id: String,
    /// Address of the requester who submitted the draft
    pub requester_address: String,
    /// Draft data (JSON object - matches Draftintent structure from Move)
    pub draft_data: serde_json::Value,
    /// Timestamp when draft was created (Unix timestamp)
    pub timestamp: u64,
    /// Expiry time (Unix timestamp)
    pub expiry_time: u64,
}

/// Request structure for submitting a signature for a draftintent.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignatureSubmission {
    /// Address of the solver submitting the signature
    pub solver_address: String,
    /// Signature in hex format (Ed25519, 64 bytes = 128 hex characters)
    pub signature: String,
    /// Public key of the solver (hex format)
    pub public_key: String,
}

/// Response structure for signature submission.
#[derive(Debug, Clone, Deserialize)]
pub struct SignatureSubmissionResponse {
    /// Unique identifier for the draft
    pub draft_id: String,
    /// Current status of the draft
    pub status: String,
}

/// Response structure for signature retrieval.
#[derive(Debug, Clone, Deserialize)]
pub struct SignatureResponse {
    /// Signature in hex format
    pub signature: String,
    /// Address of the solver who signed (first signer)
    pub solver_address: String,
    /// Timestamp when signature was received
    pub timestamp: u64,
}

// ============================================================================
// OUTFLOW FULFILLMENT STRUCTURES (Phase 2)
// ============================================================================

/// Request structure for validating outflow fulfillment transactions.
#[derive(Debug, Clone, Serialize)]
pub struct ValidateOutflowFulfillmentRequest {
    /// Transaction hash on the connected chain
    pub transaction_hash: String,
    /// Chain type: "mvm" or "evm"
    pub chain_type: String,
    /// Intent ID to validate against (optional)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub intent_id: Option<String>,
}

/// Validation result from verifier.
#[derive(Debug, Clone, Deserialize)]
pub struct ValidationResult {
    /// Whether validation passed
    pub valid: bool,
    /// Validation message
    pub message: String,
}

/// Approval signature from verifier.
#[derive(Debug, Clone, Deserialize)]
pub struct ApprovalSignature {
    /// Signature in base64 format
    pub signature: String,
}

/// Response structure for outflow fulfillment validation.
#[derive(Debug, Clone, Deserialize)]
pub struct OutflowFulfillmentValidationResponse {
    /// Validation result
    pub validation: ValidationResult,
    /// Approval signature for hub chain intent fulfillment (only present if validation passed)
    pub approval_signature: Option<ApprovalSignature>,
}

/// Approval entry from GET /approvals.
#[derive(Debug, Clone, Deserialize)]
pub struct Approval {
    /// Escrow ID
    pub escrow_id: String,
    /// Intent ID
    pub intent_id: String,
    /// Signature in base64 format
    pub signature: String,
    /// Timestamp when approval was generated
    pub timestamp: u64,
}

// ============================================================================
// VERIFIER CLIENT
// ============================================================================

/// HTTP client for communicating with the Trusted Verifier service.
///
/// Uses blocking HTTP requests (reqwest blocking client).
/// All methods return `Result` with appropriate error context.
pub struct VerifierClient {
    /// Base URL of the verifier service (e.g., "http://127.0.0.1:3333")
    base_url: String,
    /// HTTP client instance
    client: reqwest::blocking::Client,
}

impl VerifierClient {
    /// Create a new verifier client.
    ///
    /// # Arguments
    ///
    /// * `base_url` - Base URL of the verifier service (e.g., "http://127.0.0.1:3333")
    ///
    /// # Returns
    ///
    /// * `VerifierClient` - New client instance
    pub fn new(base_url: impl Into<String>) -> Self {
        let client = reqwest::blocking::Client::builder()
            .timeout(Duration::from_secs(30))
            .build()
            .expect("Failed to create HTTP client");

        Self {
            base_url: base_url.into(),
            client,
        }
    }

    /// Poll for pending draftintents.
    ///
    /// Returns all pending drafts (all solvers see all drafts).
    /// This is a polling endpoint - solvers call this regularly to discover new drafts.
    ///
    /// # Returns
    ///
    /// * `Ok(Vec<PendingDraft>)` - List of pending drafts
    /// * `Err(anyhow::Error)` - Failed to fetch drafts
    pub fn poll_pending_drafts(&self) -> Result<Vec<PendingDraft>> {
        let url = format!("{}/draftintents/pending", self.base_url);

        let response: ApiResponse<Vec<PendingDraft>> = self
            .client
            .get(&url)
            .send()
            .context("Failed to send GET /draftintents/pending request")?
            .json()
            .context("Failed to parse GET /draftintents/pending response")?;

        if !response.success {
            return Err(anyhow::anyhow!(
                "Verifier API error: {}",
                response.error.unwrap_or_else(|| "Unknown error".to_string())
            ));
        }

        Ok(response.data.unwrap_or_default())
    }

    /// Submit a signature for a draftintent.
    ///
    /// The solver submits its signature to the verifier. The verifier implements FCFS logic:
    /// the first signature wins, and later signatures are rejected with 409 Conflict.
    /// This method handles the 409 Conflict response and converts it to an appropriate error.
    ///
    /// # Arguments
    ///
    /// * `draft_id` - The draft ID to sign
    /// * `submission` - The signature submission data
    ///
    /// # Returns
    ///
    /// * `Ok(SignatureSubmissionResponse)` - Signature accepted (200 OK - solver was first)
    /// * `Err(anyhow::Error)` - Failed to submit signature (may be 409 Conflict if draft already signed by another solver)
    pub fn submit_signature(
        &self,
        draft_id: &str,
        submission: &SignatureSubmission,
    ) -> Result<SignatureSubmissionResponse> {
        let url = format!("{}/draftintent/{}/signature", self.base_url, draft_id);

        let http_response = self
            .client
            .post(&url)
            .json(submission)
            .send()
            .context("Failed to send POST /draftintent/:id/signature request")?;

        let status = http_response.status();
        let response: ApiResponse<SignatureSubmissionResponse> = http_response
            .json()
            .context("Failed to parse POST /draftintent/:id/signature response")?;

        if !response.success {
            if status == reqwest::StatusCode::CONFLICT {
                return Err(anyhow::anyhow!(
                    "Draft already signed by another solver (FCFS): {}",
                    response.error.unwrap_or_else(|| "Unknown error".to_string())
                ));
            }

            return Err(anyhow::anyhow!(
                "Verifier API error: {}",
                response.error.unwrap_or_else(|| "Unknown error".to_string())
            ));
        }

        Ok(response.data.context("Missing data in successful response")?)
    }

    /// Validate an outflow fulfillment transaction.
    ///
    /// This endpoint validates a connected chain transaction for an outflow intent
    /// and returns an approval signature for hub chain fulfillment if validation passes.
    ///
    /// # Arguments
    ///
    /// * `request` - The validation request
    ///
    /// # Returns
    ///
    /// * `Ok(OutflowFulfillmentValidationResponse)` - Validation result and approval signature
    /// * `Err(anyhow::Error)` - Failed to validate
    pub fn validate_outflow_fulfillment(
        &self,
        request: &ValidateOutflowFulfillmentRequest,
    ) -> Result<OutflowFulfillmentValidationResponse> {
        let url = format!("{}/validate-outflow-fulfillment", self.base_url);

        let response: ApiResponse<OutflowFulfillmentValidationResponse> = self
            .client
            .post(&url)
            .json(request)
            .send()
            .context("Failed to send POST /validate-outflow-fulfillment request")?
            .json()
            .context("Failed to parse POST /validate-outflow-fulfillment response")?;

        if !response.success {
            return Err(anyhow::anyhow!(
                "Verifier API error: {}",
                response.error.unwrap_or_else(|| "Unknown error".to_string())
            ));
        }

        Ok(response.data.context("Missing data in successful response")?)
    }

    /// Get approvals generated by the verifier.
    ///
    /// Returns approvals generated after observing fulfillment + matching escrow.
    /// Used for inflow intents where solver needs to wait for verifier approval.
    ///
    /// # Returns
    ///
    /// * `Ok(Vec<Approval>)` - List of approvals
    /// * `Err(anyhow::Error)` - Failed to fetch approvals
    pub fn get_approvals(&self) -> Result<Vec<Approval>> {
        let url = format!("{}/approvals", self.base_url);

        let response: ApiResponse<Vec<Approval>> = self
            .client
            .get(&url)
            .send()
            .context("Failed to send GET /approvals request")?
            .json()
            .context("Failed to parse GET /approvals response")?;

        if !response.success {
            return Err(anyhow::anyhow!(
                "Verifier API error: {}",
                response.error.unwrap_or_else(|| "Unknown error".to_string())
            ));
        }

        Ok(response.data.unwrap_or_default())
    }
}

