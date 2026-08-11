use std::path::Path;

use similar::TextDiff;

pub fn unified(current: &[u8], desired: &[u8], target: &Path) -> String {
    let current = String::from_utf8_lossy(current);
    let desired = String::from_utf8_lossy(desired);
    let before = format!("{} (current)", target.display());
    let after = format!("{} (desired)", target.display());
    TextDiff::from_lines(&current, &desired)
        .unified_diff()
        .header(&before, &after)
        .to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shows_added_settings() {
        let output = unified(
            b"before\n",
            b"before\nadded = true\n",
            Path::new("/tmp/test"),
        );
        assert!(output.contains("+added = true"));
    }
}
