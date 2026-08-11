use crate::error::{AppError, Result};

pub const BEGIN_MARKER: &[u8] = b"# BEGIN cons-tan-tan/dotfiles apply-nix-settings";
pub const END_MARKER: &[u8] = b"# END cons-tan-tan/dotfiles apply-nix-settings";

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum MarkerState {
    Outside,
    Inside,
    Complete,
}

pub fn render_desired(current: &[u8], snippet: &[u8]) -> Result<Vec<u8>> {
    let current_lines = lines(current);
    let mut state = MarkerState::Outside;
    let mut begin_index = None;
    let mut end_index = None;

    for (index, line) in current_lines.iter().enumerate() {
        if *line == BEGIN_MARKER {
            if state != MarkerState::Outside {
                return malformed(
                    "expected exactly one matching BEGIN/END pair, or no managed block",
                );
            }
            state = MarkerState::Inside;
            begin_index = Some(index);
        } else if *line == END_MARKER {
            if state != MarkerState::Inside {
                return malformed("expected END only after BEGIN");
            }
            state = MarkerState::Complete;
            end_index = Some(index);
        }
    }

    if state == MarkerState::Inside {
        return malformed("expected matching BEGIN/END markers");
    }

    match (begin_index, end_index) {
        (None, None) => append_block(current, snippet),
        (Some(begin), Some(end)) => Ok(replace_block(&current_lines, snippet, begin, end)),
        _ => malformed("expected matching BEGIN/END markers"),
    }
}

fn append_block(current: &[u8], snippet: &[u8]) -> Result<Vec<u8>> {
    let mut desired = Vec::with_capacity(
        current.len() + snippet.len() + BEGIN_MARKER.len() + END_MARKER.len() + 3,
    );
    desired.extend_from_slice(current);
    if !current.is_empty() {
        desired.push(b'\n');
    }
    desired.extend_from_slice(BEGIN_MARKER);
    desired.push(b'\n');
    desired.extend_from_slice(snippet);
    desired.extend_from_slice(END_MARKER);
    desired.push(b'\n');
    Ok(desired)
}

fn replace_block(current_lines: &[&[u8]], snippet: &[u8], begin: usize, end: usize) -> Vec<u8> {
    let mut desired = Vec::new();
    for line in &current_lines[..begin] {
        push_line(&mut desired, line);
    }
    push_line(&mut desired, BEGIN_MARKER);
    for line in lines(snippet) {
        push_line(&mut desired, line);
    }
    push_line(&mut desired, END_MARKER);
    for line in &current_lines[end + 1..] {
        push_line(&mut desired, line);
    }
    desired
}

fn lines(content: &[u8]) -> Vec<&[u8]> {
    if content.is_empty() {
        return Vec::new();
    }
    let mut lines: Vec<&[u8]> = content.split(|byte| *byte == b'\n').collect();
    if content.ends_with(b"\n") {
        lines.pop();
    }
    lines
}

fn push_line(output: &mut Vec<u8>, line: &[u8]) {
    output.extend_from_slice(line);
    output.push(b'\n');
}

fn malformed<T>(reason: &str) -> Result<T> {
    Err(AppError::new(reason))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn block(snippet: &[u8]) -> Vec<u8> {
        let mut expected = Vec::new();
        push_line(&mut expected, BEGIN_MARKER);
        expected.extend_from_slice(snippet);
        push_line(&mut expected, END_MARKER);
        expected
    }

    #[test]
    fn appends_with_the_shell_newline_contract() {
        assert_eq!(render_desired(b"", b"x = 1\n").unwrap(), block(b"x = 1\n"));

        let desired = render_desired(b"before = keep\n", b"x = 1\n").unwrap();
        assert_eq!(
            desired,
            b"before = keep\n\n"
                .iter()
                .copied()
                .chain(block(b"x = 1\n"))
                .collect::<Vec<_>>()
        );

        let desired = render_desired(b"before = keep", b"x = 1\n").unwrap();
        assert_eq!(
            desired,
            b"before = keep\n"
                .iter()
                .copied()
                .chain(block(b"x = 1\n"))
                .collect::<Vec<_>>()
        );
    }

    #[test]
    fn preserves_append_behavior_for_snippet_without_newline() {
        let desired = render_desired(b"", b"x = 1").unwrap();
        assert!(
            desired
                .windows(b"x = 1# END".len())
                .any(|window| window == b"x = 1# END")
        );
    }

    #[test]
    fn replaces_only_the_exact_pair_and_normalizes_printed_lines() {
        let current = b"before\n# BEGIN cons-tan-tan/dotfiles apply-nix-settings\nold\n# END cons-tan-tan/dotfiles apply-nix-settings\nafter";
        let desired = render_desired(current, b"new").unwrap();
        assert_eq!(
            desired,
            b"before\n# BEGIN cons-tan-tan/dotfiles apply-nix-settings\nnew\n# END cons-tan-tan/dotfiles apply-nix-settings\nafter\n"
        );
    }

    #[test]
    fn rejects_missing_reversed_and_duplicate_markers() {
        for current in [
            b"# BEGIN cons-tan-tan/dotfiles apply-nix-settings\n".as_slice(),
            b"# END cons-tan-tan/dotfiles apply-nix-settings\n# BEGIN cons-tan-tan/dotfiles apply-nix-settings\n",
            b"# BEGIN cons-tan-tan/dotfiles apply-nix-settings\n# BEGIN cons-tan-tan/dotfiles apply-nix-settings\n# END cons-tan-tan/dotfiles apply-nix-settings\n",
            b"# BEGIN cons-tan-tan/dotfiles apply-nix-settings\n# END cons-tan-tan/dotfiles apply-nix-settings\n# END cons-tan-tan/dotfiles apply-nix-settings\n",
        ] {
            assert!(render_desired(current, b"x\n").is_err(), "{current:?}");
        }
    }

    #[test]
    fn partial_marker_text_is_unmanaged_content() {
        let current = b"prefix # BEGIN cons-tan-tan/dotfiles apply-nix-settings suffix\n";
        let desired = render_desired(current, b"x\n").unwrap();
        assert!(desired.starts_with(current));
    }
}
