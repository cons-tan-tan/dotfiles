use crate::discovery::DocumentKind;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::sync::OnceLock;

pub const LANGUAGE_SERVER_BUNDLE: &[u8] = include_bytes!("../vendor/cli.bundle.cjs");
const LANGUAGE_SERVER_METADATA: &str = include_str!("../language-server.json");

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LanguageServerMetadata {
    pub package: String,
    pub version: String,
    pub integrity: String,
    pub git_head: String,
    pub published_at: String,
    pub attestation: String,
    pub provenance_predicate_type: String,
    pub registry_signature_key_id: String,
    pub upstream_package_lock_sha256: String,
    pub registry_verification: RegistryVerificationMetadata,
    pub bundle_reproduction: BundleReproductionMetadata,
    pub experimental_features: Vec<String>,
    pub bundle_sha256: String,
    pub node_licenses_sha256: String,
    pub node_licenses_inventory_sha256: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RegistryVerificationMetadata {
    pub source_dependencies: bool,
    pub reproduction_dependencies: bool,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BundleReproductionMetadata {
    pub byte_for_byte: bool,
    pub esbuild_version: String,
}

pub fn language_server_metadata() -> &'static LanguageServerMetadata {
    static METADATA: OnceLock<LanguageServerMetadata> = OnceLock::new();
    METADATA.get_or_init(|| {
        serde_json::from_str(LANGUAGE_SERVER_METADATA)
            .expect("embedded language-server.json must be valid")
    })
}

#[derive(Debug, Clone, Serialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct Diagnostic {
    pub file: String,
    pub severity: Severity,
    pub message: String,
    pub line: u64,
    pub column: u64,
    pub end_line: u64,
    pub end_column: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub code: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
}

#[derive(Debug, Clone, Copy, Serialize, PartialEq, Eq, PartialOrd, Ord)]
#[serde(rename_all = "lowercase")]
pub enum Severity {
    Error,
    Warning,
    Information,
    Hint,
}

impl Severity {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Error => "error",
            Self::Warning => "warning",
            Self::Information => "information",
            Self::Hint => "hint",
        }
    }
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Report {
    pub schema_version: &'static str,
    pub tool: Tool,
    pub language_server: LanguageServer,
    pub runtime: Runtime,
    pub hardening: Hardening,
    pub failure_threshold: Severity,
    pub empty_input_allowed: bool,
    pub conclusion: &'static str,
    pub exit_code: u8,
    pub blocking_diagnostics: usize,
    pub files: Vec<CheckedFileEvidence>,
    pub read_dependencies: Vec<FileEvidence>,
    pub diagnostics: Vec<Diagnostic>,
    pub limitations: Vec<&'static str>,
}

#[derive(Debug, Serialize)]
pub struct Tool {
    pub name: &'static str,
    pub version: &'static str,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LanguageServer {
    pub package: &'static str,
    pub version: &'static str,
    pub source: &'static str,
    pub integrity: &'static str,
    pub git_head: &'static str,
    pub published_at: &'static str,
    pub attestation: &'static str,
    pub provenance_predicate_type: &'static str,
    pub registry_signature_key_id: &'static str,
    pub upstream_package_lock_sha256: &'static str,
    pub registry_verification: RegistryVerification,
    pub bundle_reproduction: BundleReproduction,
    pub bundle_sha256: String,
    pub license_evidence: LicenseEvidence,
    pub position_encoding: &'static str,
    pub experimental_features: Vec<String>,
    pub experimental_feature_policy: ExperimentalFeaturePolicy,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ExperimentalFeaturePolicy {
    pub mode: &'static str,
    pub available: Vec<String>,
    pub disabled: Vec<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RegistryVerification {
    pub source_dependencies: bool,
    pub reproduction_dependencies: bool,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BundleReproduction {
    pub byte_for_byte: bool,
    pub esbuild_version: &'static str,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LicenseEvidence {
    pub node_notice_sha256: &'static str,
    pub node_inventory_sha256: &'static str,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Runtime {
    pub implementation: &'static str,
    pub version: String,
    pub executable: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Hardening {
    pub environment_allowlist: bool,
    pub synthetic_home: bool,
    pub node_permission_model: bool,
    pub node_permission_model_restricts_network: bool,
    pub lsp_operation_timeout_seconds: u64,
    pub max_old_space_size_mib: u64,
    pub max_lsp_message_bytes: usize,
}

#[derive(Debug, Serialize)]
pub struct FileEvidence {
    pub path: String,
    pub sha256: String,
}

#[derive(Debug, Serialize)]
pub struct CheckedFileEvidence {
    pub path: String,
    pub sha256: String,
    pub kind: DocumentKind,
}

pub fn sha256(bytes: &[u8]) -> String {
    let digest = Sha256::digest(bytes);
    digest.iter().map(|byte| format!("{byte:02x}")).collect()
}

pub fn format_text(diagnostic: &Diagnostic) -> String {
    let code = diagnostic
        .code
        .as_ref()
        .map(|code| format!(" [{}]", sanitize_log_text(code)))
        .unwrap_or_default();
    let source = sanitize_log_text(
        diagnostic
            .source
            .as_deref()
            .unwrap_or("actions-language-server"),
    );
    format!(
        "{}:{}:{}: {}: {} ({}){}",
        sanitize_log_text(&diagnostic.file),
        diagnostic.line,
        diagnostic.column,
        diagnostic.severity.as_str(),
        sanitize_log_text(&diagnostic.message),
        source,
        code
    )
}

pub fn sanitize_log_text(value: &str) -> String {
    let mut sanitized = String::with_capacity(value.len());
    for character in value.chars() {
        match character {
            '\n' => sanitized.push_str("\\n"),
            '\r' => sanitized.push_str("\\r"),
            '\t' => sanitized.push_str("\\t"),
            value if value.is_control() => {
                sanitized.push_str(&format!("\\u{{{:x}}}", value as u32));
            }
            value => sanitized.push(value),
        }
    }
    sanitized
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn text_diagnostics_cannot_inject_log_lines_or_terminal_controls() {
        let diagnostic = Diagnostic {
            file: "workflow\n::error::fake.yaml".to_owned(),
            severity: Severity::Error,
            message: "first\r\n\u{1b}[31msecond".to_owned(),
            line: 1,
            column: 2,
            end_line: 1,
            end_column: 3,
            code: Some("bad\tcode".to_owned()),
            source: Some("source\nname".to_owned()),
        };

        let output = format_text(&diagnostic);
        assert!(!output.contains('\n'));
        assert!(!output.contains('\r'));
        assert!(!output.contains('\u{1b}'));
        assert!(output.contains("\\n::error::"));
        assert!(output.contains("\\u{1b}[31m"));
    }
}
