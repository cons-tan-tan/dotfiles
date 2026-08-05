use std::fs;
use std::os::unix::ffi::OsStrExt;
use std::path::{Path, PathBuf};

use crate::error::{AppError, Result};
use crate::filesystem::parent_or_current;

pub fn validate(nix_conf: &Path, target: &Path) -> Result<()> {
    let metadata = fs::metadata(nix_conf).map_err(|error| {
        AppError::new(format!(
            "apply-nix-settings: nix.conf not found: {}: {error}",
            nix_conf.display()
        ))
    })?;
    if !metadata.is_file() {
        return Err(AppError::new(format!(
            "apply-nix-settings: nix.conf is not a regular file: {}",
            nix_conf.display()
        )));
    }
    let expected = normalize_parent(target).map_err(|error| {
        AppError::new(format!(
            "apply-nix-settings: cannot resolve target directory for {}: {error}",
            target.display()
        ))
    })?;
    let content = fs::read(nix_conf).map_err(|error| AppError::io("read", nix_conf, error))?;
    let base = parent_or_current(nix_conf);

    let found = content.split(|byte| *byte == b'\n').any(|line| {
        let mut fields = line.split(|byte| byte.is_ascii_whitespace());
        let directive = fields.find(|field| !field.is_empty());
        let include = fields.find(|field| !field.is_empty());
        if !matches!(directive, Some(b"include" | b"!include")) {
            return false;
        }
        let Some(include) = include else {
            return false;
        };
        let include = PathBuf::from(std::ffi::OsStr::from_bytes(include));
        let candidate = if include.is_absolute() {
            include
        } else {
            base.join(include)
        };
        normalize_parent(&candidate).is_ok_and(|path| path == expected)
    });

    if found {
        Ok(())
    } else {
        Err(AppError::new(format!(
            "apply-nix-settings: {} does not include {}",
            nix_conf.display(),
            target.display()
        )))
    }
}

fn normalize_parent(path: &Path) -> std::io::Result<PathBuf> {
    let parent = parent_or_current(path);
    let name = path
        .file_name()
        .ok_or_else(|| std::io::Error::other("path has no file name"))?;
    Ok(parent.canonicalize()?.join(name))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::symlink;
    use tempfile::tempdir;

    #[test]
    fn accepts_relative_absolute_and_bang_includes() {
        let work = tempdir().unwrap();
        let target = work.path().join("nix.custom.conf");
        for directive in [
            b"include nix.custom.conf\n".as_slice(),
            b"!include nix.custom.conf ignored\n",
            format!("include {}\n", target.display()).as_bytes(),
        ] {
            let nix_conf = work.path().join("nix.conf");
            fs::write(&nix_conf, directive).unwrap();
            validate(&nix_conf, &target).unwrap();
        }
    }

    #[test]
    fn compares_symlinked_ancestors_physically() {
        let work = tempdir().unwrap();
        let real = work.path().join("real");
        let link = work.path().join("link");
        fs::create_dir(&real).unwrap();
        symlink(&real, &link).unwrap();
        let target = link.join("nix.custom.conf");
        let nix_conf = work.path().join("nix.conf");
        fs::write(
            &nix_conf,
            format!("!include {}/nix.custom.conf\n", real.display()),
        )
        .unwrap();
        validate(&nix_conf, &target).unwrap();
    }

    #[test]
    fn rejects_another_file_and_does_not_parse_comments_or_quotes() {
        let work = tempdir().unwrap();
        let target = work.path().join("nix.custom.conf");
        let nix_conf = work.path().join("nix.conf");
        for line in [
            b"include other.conf\n".as_slice(),
            b"# include nix.custom.conf\n",
            b"include \"nix.custom.conf\"\n",
        ] {
            fs::write(&nix_conf, line).unwrap();
            assert!(validate(&nix_conf, &target).is_err());
        }
    }
}
