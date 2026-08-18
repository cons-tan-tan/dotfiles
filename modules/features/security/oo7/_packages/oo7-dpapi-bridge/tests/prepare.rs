use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::{Command, Stdio};

use oo7::{Secret, file::UnlockedKeyring};
use oo7_dpapi_bridge::{MASTER_BYTES, PrepareConfig, PrepareError, prepare};

fn fixture() -> &'static Path {
    Path::new(env!("CARGO_BIN_EXE_wsl-dpapi-test-fixture"))
}

fn bridge() -> &'static Path {
    Path::new(env!("CARGO_BIN_EXE_oo7-dpapi-bridge"))
}

fn config(root: &Path) -> PrepareConfig {
    PrepareConfig {
        helper: fixture().to_path_buf(),
        blob: root.join("state/login-master.dpapi"),
        data_home: root.join("data"),
    }
}

fn unprotect(blob: &Path) -> Vec<u8> {
    let input = fs::File::open(blob).unwrap();
    let output = Command::new(fixture())
        .arg("unprotect")
        .stdin(Stdio::from(input))
        .output()
        .unwrap();
    assert!(output.status.success());
    output.stdout
}

fn protect_to_blob(blob: &Path, plaintext: &[u8]) {
    fs::create_dir_all(blob.parent().unwrap()).unwrap();
    let mut child = Command::new(fixture())
        .arg("protect")
        .stdin(Stdio::piped())
        .stdout(fs::File::create(blob).unwrap())
        .spawn()
        .unwrap();
    child.stdin.take().unwrap().write_all(plaintext).unwrap();
    assert!(child.wait().unwrap().success());
}

fn assert_mode(path: &Path, expected: u32) {
    assert_eq!(
        fs::metadata(path).unwrap().permissions().mode() & 0o777,
        expected
    );
}

#[test]
fn cli_initializes_from_xdg_data_home() {
    let root = tempfile::tempdir().unwrap();
    let blob = root.path().join("state/login-master.dpapi");
    let data_home = root.path().join("xdg-data");

    let status = Command::new(bridge())
        .arg(fixture())
        .arg(&blob)
        .env("XDG_DATA_HOME", &data_home)
        .env_remove("HOME")
        .status()
        .unwrap();

    assert!(status.success());
    assert_eq!(unprotect(&blob).len(), MASTER_BYTES);
    assert!(data_home.join("keyrings/v1/login.keyring").exists());
}

#[test]
fn cli_falls_back_to_home() {
    let root = tempfile::tempdir().unwrap();
    let blob = root.path().join("state/login-master.dpapi");
    let home = root.path().join("home");

    let status = Command::new(bridge())
        .arg(fixture())
        .arg(&blob)
        .env_remove("XDG_DATA_HOME")
        .env("HOME", &home)
        .status()
        .unwrap();

    assert!(status.success());
    assert_eq!(unprotect(&blob).len(), MASTER_BYTES);
    assert!(home.join(".local/share/keyrings/v1/login.keyring").exists());
}

#[tokio::test]
async fn initializes_and_then_verifies_without_rewriting_state() {
    let root = tempfile::tempdir().unwrap();
    let config = config(root.path());

    prepare(&config).await.unwrap();
    let first_blob = fs::read(&config.blob).unwrap();
    let first_keyring = fs::read(config.login_keyring()).unwrap();
    assert_eq!(unprotect(&config.blob).len(), MASTER_BYTES);
    assert_mode(&config.blob, 0o600);
    assert_mode(config.blob.parent().unwrap(), 0o700);
    assert_mode(config.login_keyring().parent().unwrap(), 0o700);
    assert_mode(&config.login_keyring(), 0o600);

    fs::set_permissions(&config.blob, fs::Permissions::from_mode(0o644)).unwrap();
    fs::set_permissions(config.login_keyring(), fs::Permissions::from_mode(0o644)).unwrap();
    prepare(&config).await.unwrap();
    assert_eq!(fs::read(&config.blob).unwrap(), first_blob);
    assert_eq!(fs::read(config.login_keyring()).unwrap(), first_keyring);
    assert_mode(&config.blob, 0o600);
    assert_mode(&config.login_keyring(), 0o600);
}

#[tokio::test]
async fn refuses_to_replace_a_missing_blob_for_an_existing_keyring() {
    let root = tempfile::tempdir().unwrap();
    let config = config(root.path());
    let keyring_path = config.login_keyring();
    fs::create_dir_all(keyring_path.parent().unwrap()).unwrap();
    fs::write(&keyring_path, b"existing-keyring").unwrap();

    let error = prepare(&config).await.unwrap_err();
    assert!(matches!(
        error,
        PrepareError::MissingBlobForExistingKeyring(path) if path == keyring_path
    ));
    assert!(!config.blob.exists());
    assert_eq!(fs::read(keyring_path).unwrap(), b"existing-keyring");
}

#[tokio::test]
async fn resumes_from_a_blob_when_keyring_creation_was_interrupted() {
    let root = tempfile::tempdir().unwrap();
    let config = config(root.path());
    let master = vec![0x42; MASTER_BYTES];
    protect_to_blob(&config.blob, &master);

    prepare(&config).await.unwrap();
    assert!(config.login_keyring().exists());
    assert_eq!(unprotect(&config.blob), master);
}

#[tokio::test]
async fn rejects_a_corrupt_blob_without_touching_the_keyring() {
    let root = tempfile::tempdir().unwrap();
    let config = config(root.path());
    fs::create_dir_all(config.blob.parent().unwrap()).unwrap();
    fs::write(&config.blob, b"corrupt").unwrap();

    let error = prepare(&config).await.unwrap_err();
    assert!(matches!(
        error,
        PrepareError::HelperFailed {
            operation: "unprotect",
            ..
        }
    ));
    assert!(!config.login_keyring().exists());
}

#[tokio::test]
async fn rejects_a_blob_with_an_invalid_master_length() {
    let root = tempfile::tempdir().unwrap();
    let config = config(root.path());
    protect_to_blob(&config.blob, b"short");

    assert!(matches!(
        prepare(&config).await,
        Err(PrepareError::InvalidMasterLength { actual: 5 })
    ));
    assert!(!config.login_keyring().exists());
}

#[tokio::test]
async fn rejects_a_blob_that_does_not_unlock_the_existing_keyring() {
    let root = tempfile::tempdir().unwrap();
    let config = config(root.path());
    prepare(&config).await.unwrap();
    let keyring_before = fs::read(config.login_keyring()).unwrap();

    let replacement_master = vec![0x33; MASTER_BYTES];
    protect_to_blob(&config.blob, &replacement_master);

    assert!(matches!(
        prepare(&config).await,
        Err(PrepareError::Keyring(_))
    ));
    assert_eq!(fs::read(config.login_keyring()).unwrap(), keyring_before);
}

#[tokio::test]
async fn rejects_a_mismatched_verifier_without_rewriting_it() {
    let root = tempfile::tempdir().unwrap();
    let config = config(root.path());
    prepare(&config).await.unwrap();
    let master = unprotect(&config.blob);
    let keyring = UnlockedKeyring::load(config.login_keyring(), Secret::blob(&master))
        .await
        .unwrap();
    let attributes = [
        ("xdg:schema", "io.github.cons-tan-tan.oo7-dpapi"),
        ("purpose", "dpapi-master-verifier-v1"),
    ];
    keyring
        .create_item(
            "mismatched verifier",
            &attributes,
            Secret::blob(b"wrong"),
            true,
        )
        .await
        .unwrap();
    let mismatched = fs::read(config.login_keyring()).unwrap();

    assert!(matches!(
        prepare(&config).await,
        Err(PrepareError::SentinelMismatch)
    ));
    assert_eq!(fs::read(config.login_keyring()).unwrap(), mismatched);
}

#[tokio::test]
async fn refuses_a_legacy_keyring_instead_of_shadowing_it() {
    let root = tempfile::tempdir().unwrap();
    let config = config(root.path());
    let legacy = config.legacy_login_keyring();
    fs::create_dir_all(legacy.parent().unwrap()).unwrap();
    fs::write(&legacy, b"legacy").unwrap();

    assert!(matches!(
        prepare(&config).await,
        Err(PrepareError::LegacyKeyring(path)) if path == legacy
    ));
    assert!(!config.blob.exists());
    assert!(!config.login_keyring().exists());
}

#[tokio::test]
async fn refuses_non_regular_security_state() {
    let root = tempfile::tempdir().unwrap();
    let config = config(root.path());
    fs::create_dir_all(&config.blob).unwrap();

    assert!(matches!(
        prepare(&config).await,
        Err(PrepareError::NonRegularFile(path)) if path == config.blob
    ));
    assert!(!config.login_keyring().exists());
}

#[tokio::test]
async fn can_adopt_an_empty_v1_keyring_and_bind_it_to_the_dpapi_master() {
    let root = tempfile::tempdir().unwrap();
    let config = config(root.path());
    let master = vec![0x17; MASTER_BYTES];
    protect_to_blob(&config.blob, &master);

    let path = config.login_keyring();
    fs::create_dir_all(path.parent().unwrap()).unwrap();
    UnlockedKeyring::load(&path, Secret::blob(&master))
        .await
        .unwrap()
        .write()
        .await
        .unwrap();

    prepare(&config).await.unwrap();
    assert!(fs::metadata(path).unwrap().len() > 0);
}
