use std::path::Path;
use std::process::Command;

use crate::manifest::{Entry, Format};
use crate::renderer;

pub fn decrypt_and_render(sops_bin: &Path, entry: &Entry) -> Result<Vec<u8>, String> {
    let mut command = Command::new(sops_bin);
    command.arg("--decrypt");
    if entry.format == Format::SshConfigYaml {
        command.args(["--output-type", "json"]);
    }
    command.arg(&entry.source);

    let output = command
        .output()
        .map_err(|error| format!("could not start sops: {error}"))?;
    if !output.status.success() {
        return Err(format!("sops exited with {}", output.status));
    }

    match entry.format {
        Format::Raw => Ok(output.stdout),
        Format::SshConfigYaml => renderer::render_ssh_config(&output.stdout),
    }
}
