use std::ops::Range;

use tree_sitter::{Node, Parser};

use crate::error::{GuardError, Result};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WordValue {
    Static(String),
    Dynamic,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Word {
    pub value: WordValue,
    pub source: Range<usize>,
}

impl Word {
    pub fn synthetic(value: impl Into<String>) -> Self {
        Self {
            value: WordValue::Static(value.into()),
            source: 0..0,
        }
    }

    pub fn static_value(&self) -> Option<&str> {
        match &self.value {
            WordValue::Static(value) => Some(value),
            WordValue::Dynamic => None,
        }
    }

    pub fn dynamic() -> Self {
        Self {
            value: WordValue::Dynamic,
            source: 0..0,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Redirect {
    operator: String,
    destination: Option<Word>,
}

impl Redirect {
    fn projection(&self) -> Projection {
        let mut projection = Projection::default();
        projection.push_piece(&self.operator, OriginRole::Operator, false);
        if let Some(destination) = &self.destination {
            projection.push_token(
                destination
                    .static_value()
                    .unwrap_or("__AGENT_DYNAMIC_WORD__"),
                OriginRole::Argument,
            );
        }
        projection
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SimpleCommand {
    pub words: Vec<Word>,
    pub(crate) redirects: Vec<Redirect>,
    pub source: Range<usize>,
}

impl SimpleCommand {
    pub fn synthetic(words: impl IntoIterator<Item = String>) -> Self {
        Self {
            words: words.into_iter().map(Word::synthetic).collect(),
            redirects: Vec::new(),
            source: 0..0,
        }
    }

    pub fn static_argv(&self) -> Vec<Option<&str>> {
        self.words.iter().map(Word::static_value).collect()
    }

    pub fn projection(&self) -> Projection {
        let mut projection = Projection::default();
        for (index, word) in self.words.iter().enumerate() {
            let value = word.static_value().unwrap_or("__AGENT_DYNAMIC_WORD__");
            projection.push_token(
                value,
                if index == 0 {
                    OriginRole::Executable
                } else {
                    OriginRole::Argument
                },
            );
        }
        for redirect in &self.redirects {
            projection.push_piece(&redirect.operator, OriginRole::Operator, true);
            if let Some(destination) = &redirect.destination {
                projection.push_token(
                    destination
                        .static_value()
                        .unwrap_or("__AGENT_DYNAMIC_WORD__"),
                    OriginRole::Argument,
                );
            }
        }
        projection
    }

    pub fn redirect_projections(&self) -> Vec<Projection> {
        self.redirects.iter().map(Redirect::projection).collect()
    }
}

#[derive(Debug, Clone)]
pub struct Pipeline {
    pub commands: Vec<SimpleCommand>,
    pub operators: Vec<String>,
}

impl Pipeline {
    pub fn projection(&self) -> Projection {
        let mut projection = Projection::default();
        for (index, command) in self.commands.iter().enumerate() {
            if index > 0 {
                projection.push_piece(&self.operators[index - 1], OriginRole::Operator, true);
            }
            projection.append(&command.projection());
        }
        projection
    }
}

#[derive(Debug)]
pub struct ParsedShell {
    pub assignment_names: Vec<String>,
    pub commands: Vec<SimpleCommand>,
    pub pipelines: Vec<Pipeline>,
    pub functions: Vec<FunctionDefinition>,
    pub standalone_redirects: Vec<Projection>,
}

#[derive(Default)]
struct CollectedShell {
    assignment_names: Vec<String>,
    commands: Vec<SimpleCommand>,
    functions: Vec<FunctionDefinition>,
    pipelines: Vec<Pipeline>,
    standalone_redirects: Vec<Projection>,
}

#[derive(Debug, Clone)]
pub struct FunctionDefinition {
    pub name: String,
    pub body: String,
    pub source_start: usize,
    pub inherited: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum OriginRole {
    Executable,
    Argument,
    Operator,
    Separator,
}

#[derive(Debug, Clone)]
struct OriginRange {
    range: Range<usize>,
    role: OriginRole,
}

#[derive(Debug, Clone, Default)]
pub struct Projection {
    text: String,
    origins: Vec<OriginRange>,
}

impl Projection {
    pub fn text(&self) -> &str {
        &self.text
    }

    pub fn is_executable_match(&self, candidate: Range<usize>) -> bool {
        if candidate.is_empty() {
            return false;
        }
        self.origins
            .iter()
            .filter(|origin| ranges_overlap(&origin.range, &candidate))
            .find(|origin| origin.role != OriginRole::Separator)
            .is_some_and(|origin| {
                matches!(origin.role, OriginRole::Executable | OriginRole::Operator)
            })
    }

    fn push_token(&mut self, value: &str, role: OriginRole) {
        self.push_piece(&quote_shell_word(value), role, true);
    }

    fn push_piece(&mut self, value: &str, role: OriginRole, separate: bool) {
        if separate && !self.text.is_empty() {
            let start = self.text.len();
            self.text.push(' ');
            self.origins.push(OriginRange {
                range: start..self.text.len(),
                role: OriginRole::Separator,
            });
        }
        let start = self.text.len();
        self.text.push_str(value);
        self.origins.push(OriginRange {
            range: start..self.text.len(),
            role,
        });
    }

    fn append(&mut self, other: &Self) {
        if other.text.is_empty() {
            return;
        }
        if !self.text.is_empty() {
            self.push_piece("", OriginRole::Separator, true);
        }
        let offset = self.text.len();
        self.text.push_str(&other.text);
        self.origins
            .extend(other.origins.iter().map(|origin| OriginRange {
                range: (origin.range.start + offset)..(origin.range.end + offset),
                role: origin.role,
            }));
    }
}

fn ranges_overlap(left: &Range<usize>, right: &Range<usize>) -> bool {
    left.start < right.end && right.start < left.end
}

pub fn parse(source: &str) -> Result<ParsedShell> {
    let mut parser = Parser::new();
    parser
        .set_language(&tree_sitter_bash::LANGUAGE.into())
        .map_err(|error| GuardError::Parser(error.to_string()))?;
    let tree = parser
        .parse(source, None)
        .ok_or_else(|| GuardError::Parser("tree-sitter returned no parse tree".to_owned()))?;
    let root = tree.root_node();
    if root.has_error() {
        return Err(GuardError::Parser(
            "shell command contains a parse error".to_owned(),
        ));
    }

    let mut collected = CollectedShell::default();
    walk(root, source.as_bytes(), false, &mut collected)?;
    collected
        .commands
        .sort_by_key(|command| (command.source.start, command.source.end));
    collected
        .commands
        .dedup_by_key(|command| (command.source.start, command.source.end));
    collected.assignment_names.sort();
    collected.assignment_names.dedup();
    Ok(ParsedShell {
        assignment_names: collected.assignment_names,
        commands: collected.commands,
        functions: collected.functions,
        pipelines: collected.pipelines,
        standalone_redirects: collected.standalone_redirects,
    })
}

fn walk(
    node: Node<'_>,
    source: &[u8],
    inside_function: bool,
    collected: &mut CollectedShell,
) -> Result<()> {
    if node.kind() == "function_definition" && !inside_function {
        collected.functions.push(extract_function(node, source)?);
    }
    if node.kind() == "redirected_statement" && !inside_function {
        let mut cursor = node.walk();
        for redirect in node.children_by_field_name("redirect", &mut cursor) {
            if redirect.kind() == "file_redirect" {
                collected
                    .standalone_redirects
                    .push(extract_redirect(redirect, source)?.projection());
            }
        }
    }
    let inside_function = inside_function || node.kind() == "function_definition";
    if node.kind() == "variable_assignment" && !inside_function {
        collected
            .assignment_names
            .push(extract_assignment_name(node, source)?);
    }
    if matches!(node.kind(), "command" | "declaration_command") && !inside_function {
        collected
            .commands
            .push(extract_simple_command(node, source)?);
    }
    if node.kind() == "pipeline"
        && !inside_function
        && let Some(pipeline) = extract_pipeline(node, source)?
    {
        collected.pipelines.push(pipeline);
    }
    let mut cursor = node.walk();
    for child in node.named_children(&mut cursor) {
        walk(child, source, inside_function, collected)?;
    }
    Ok(())
}

fn extract_assignment_name(node: Node<'_>, source: &[u8]) -> Result<String> {
    let raw = std::str::from_utf8(&source[node.byte_range()])
        .map_err(|_| GuardError::Parser("shell assignment is not valid UTF-8".to_owned()))?;
    let name = raw
        .split_once('=')
        .map(|(name, _)| name.trim_end_matches('+'))
        .filter(|name| !name.is_empty())
        .ok_or_else(|| GuardError::Parser("shell assignment has no variable name".to_owned()))?;
    Ok(name.to_owned())
}

fn extract_function(node: Node<'_>, source: &[u8]) -> Result<FunctionDefinition> {
    let name = node
        .child_by_field_name("name")
        .ok_or_else(|| GuardError::Parser("function definition has no name".to_owned()))?;
    let body = node
        .child_by_field_name("body")
        .ok_or_else(|| GuardError::Parser("function definition has no body".to_owned()))?;
    let name = extract_word(name, source)?
        .static_value()
        .ok_or_else(|| GuardError::Parser("function name is dynamic".to_owned()))?
        .to_owned();
    let body = std::str::from_utf8(&source[body.byte_range()])
        .map_err(|_| GuardError::Parser("function body is not valid UTF-8".to_owned()))?
        .to_owned();
    Ok(FunctionDefinition {
        name,
        body,
        source_start: node.start_byte(),
        inherited: false,
    })
}

fn extract_command(node: Node<'_>, source: &[u8]) -> Result<SimpleCommand> {
    let name = node
        .child_by_field_name("name")
        .ok_or_else(|| GuardError::Parser("command has no name".to_owned()))?;
    let mut words = vec![extract_word(name, source)?];
    let mut cursor = node.walk();
    for argument in node.children_by_field_name("argument", &mut cursor) {
        words.push(extract_word(argument, source)?);
    }
    let mut redirects = Vec::new();
    let mut cursor = node.walk();
    for redirect in node.children_by_field_name("redirect", &mut cursor) {
        redirects.push(extract_redirect(redirect, source)?);
    }
    Ok(SimpleCommand {
        words,
        redirects,
        source: node.byte_range(),
    })
}

fn extract_declaration_command(node: Node<'_>, source: &[u8]) -> Result<SimpleCommand> {
    let name = node
        .child(0)
        .ok_or_else(|| GuardError::Parser("declaration command has no name".to_owned()))?;
    let mut words = vec![extract_word(name, source)?];
    let mut cursor = node.walk();
    for argument in node.named_children(&mut cursor) {
        words.push(extract_word(argument, source)?);
    }
    Ok(SimpleCommand {
        words,
        redirects: Vec::new(),
        source: node.byte_range(),
    })
}

fn extract_simple_command(node: Node<'_>, source: &[u8]) -> Result<SimpleCommand> {
    match node.kind() {
        "command" => extract_command(node, source),
        "declaration_command" => extract_declaration_command(node, source),
        kind => Err(GuardError::Parser(format!(
            "unsupported simple command node {kind}"
        ))),
    }
}

fn extract_redirect(node: Node<'_>, source: &[u8]) -> Result<Redirect> {
    let destination = node.child_by_field_name("destination");
    let operator_end = destination.map_or(node.end_byte(), |value| value.start_byte());
    let operator = source[node.start_byte()..operator_end]
        .iter()
        .map(|byte| char::from(*byte))
        .collect::<String>()
        .trim()
        .to_owned();
    Ok(Redirect {
        operator,
        destination: destination
            .map(|value| extract_word(value, source))
            .transpose()?,
    })
}

fn extract_pipeline(node: Node<'_>, source: &[u8]) -> Result<Option<Pipeline>> {
    let mut commands = Vec::new();
    let mut command_nodes = Vec::new();
    let mut cursor = node.walk();
    for child in node.named_children(&mut cursor) {
        if let Some(command) = find_primary_command(child) {
            commands.push(extract_simple_command(command, source)?);
            command_nodes.push(command);
        }
    }
    if commands.len() < 2 {
        return Ok(None);
    }
    let operators = command_nodes
        .windows(2)
        .map(|pair| {
            let between = &source[pair[0].end_byte()..pair[1].start_byte()];
            let text = String::from_utf8_lossy(between);
            if text.contains("|&") {
                "|&".to_owned()
            } else {
                "|".to_owned()
            }
        })
        .collect();
    Ok(Some(Pipeline {
        commands,
        operators,
    }))
}

fn find_primary_command(node: Node<'_>) -> Option<Node<'_>> {
    if matches!(node.kind(), "command" | "declaration_command") {
        return Some(node);
    }
    if matches!(
        node.kind(),
        "command_substitution" | "process_substitution" | "function_definition"
    ) {
        return None;
    }
    let mut cursor = node.walk();
    node.named_children(&mut cursor)
        .find_map(find_primary_command)
}

fn extract_word(node: Node<'_>, source: &[u8]) -> Result<Word> {
    let bytes = &source[node.byte_range()];
    let raw = std::str::from_utf8(bytes)
        .map_err(|_| GuardError::Parser("shell command is not valid UTF-8".to_owned()))?;
    let value = if contains_dynamic(node) {
        WordValue::Dynamic
    } else {
        WordValue::Static(decode_shell_literal(raw)?)
    };
    Ok(Word {
        value,
        source: node.byte_range(),
    })
}

fn contains_dynamic(node: Node<'_>) -> bool {
    if matches!(
        node.kind(),
        "arithmetic_expansion"
            | "command_substitution"
            | "expansion"
            | "process_substitution"
            | "simple_expansion"
    ) {
        return true;
    }
    let mut cursor = node.walk();
    node.named_children(&mut cursor).any(contains_dynamic)
}

fn decode_shell_literal(raw: &str) -> Result<String> {
    #[derive(Clone, Copy, PartialEq, Eq)]
    enum State {
        Unquoted,
        Single,
        Double,
        Ansi,
    }

    let chars = raw.chars().collect::<Vec<_>>();
    let mut output = String::new();
    let mut state = State::Unquoted;
    let mut index = 0;
    while index < chars.len() {
        let current = chars[index];
        match state {
            State::Unquoted => match current {
                '\'' => state = State::Single,
                '"' => state = State::Double,
                '$' if chars.get(index + 1) == Some(&'\'') => {
                    state = State::Ansi;
                    index += 1;
                }
                '\\' => {
                    index += 1;
                    let escaped = chars.get(index).ok_or_else(|| {
                        GuardError::Parser("shell word ends with an escape".to_owned())
                    })?;
                    if *escaped != '\n' {
                        output.push(*escaped);
                    }
                }
                _ => output.push(current),
            },
            State::Single => {
                if current == '\'' {
                    state = State::Unquoted;
                } else {
                    output.push(current);
                }
            }
            State::Double => match current {
                '"' => state = State::Unquoted,
                '\\' => {
                    index += 1;
                    let escaped = chars.get(index).ok_or_else(|| {
                        GuardError::Parser("double-quoted word ends with an escape".to_owned())
                    })?;
                    if matches!(*escaped, '"' | '\\' | '$' | '`') {
                        output.push(*escaped);
                    } else if *escaped != '\n' {
                        output.push('\\');
                        output.push(*escaped);
                    }
                }
                _ => output.push(current),
            },
            State::Ansi => {
                if current == '\'' {
                    state = State::Unquoted;
                } else if current == '\\' {
                    index += 1;
                    let escaped = chars.get(index).ok_or_else(|| {
                        GuardError::Parser("ANSI-C word ends with an escape".to_owned())
                    })?;
                    match escaped {
                        'n' => output.push('\n'),
                        'r' => output.push('\r'),
                        't' => output.push('\t'),
                        'a' => output.push('\x07'),
                        'b' => output.push('\x08'),
                        'e' | 'E' => output.push('\x1b'),
                        'f' => output.push('\x0c'),
                        'v' => output.push('\x0b'),
                        '\\' => output.push('\\'),
                        '\'' => output.push('\''),
                        '"' => output.push('"'),
                        '?' => output.push('?'),
                        '\n' => {}
                        'x' => output.push(decode_ansi_digits(&chars, &mut index, 16, 2)?),
                        'u' => output.push(decode_ansi_digits(&chars, &mut index, 16, 4)?),
                        'U' => output.push(decode_ansi_digits(&chars, &mut index, 16, 8)?),
                        'c' => {
                            index += 1;
                            let control = chars.get(index).ok_or_else(|| {
                                GuardError::Parser("ANSI-C control escape has no value".to_owned())
                            })?;
                            if !control.is_ascii() {
                                return Err(GuardError::Parser(
                                    "ANSI-C control escape is not ASCII".to_owned(),
                                ));
                            }
                            output.push((control.to_ascii_uppercase() as u8 & 0x1f) as char);
                        }
                        octal @ '0'..='7' => {
                            output.push(decode_ansi_octal(&chars, &mut index, *octal)?);
                        }
                        other => output.push(*other),
                    }
                } else {
                    output.push(current);
                }
            }
        }
        index += 1;
    }
    if state != State::Unquoted {
        return Err(GuardError::Parser(
            "shell word has an unclosed quote".to_owned(),
        ));
    }
    Ok(output)
}

fn decode_ansi_digits(
    chars: &[char],
    index: &mut usize,
    radix: u32,
    maximum: usize,
) -> Result<char> {
    let start = *index + 1;
    let mut end = start;
    while end < chars.len() && end - start < maximum && chars[end].is_digit(radix) {
        end += 1;
    }
    if end == start {
        return Err(GuardError::Parser(
            "ANSI-C numeric escape has no digits".to_owned(),
        ));
    }
    let value = u32::from_str_radix(&chars[start..end].iter().collect::<String>(), radix)
        .map_err(|_| GuardError::Parser("ANSI-C numeric escape is invalid".to_owned()))?;
    *index = end - 1;
    char::from_u32(value)
        .ok_or_else(|| GuardError::Parser("ANSI-C escape is not a valid character".to_owned()))
}

fn decode_ansi_octal(chars: &[char], index: &mut usize, first: char) -> Result<char> {
    let mut digits = String::from(first);
    let mut end = *index + 1;
    while end < chars.len() && digits.len() < 3 && matches!(chars[end], '0'..='7') {
        digits.push(chars[end]);
        end += 1;
    }
    *index = end - 1;
    let value = u32::from_str_radix(&digits, 8)
        .map_err(|_| GuardError::Parser("ANSI-C octal escape is invalid".to_owned()))?;
    char::from_u32(value)
        .ok_or_else(|| GuardError::Parser("ANSI-C escape is not a valid character".to_owned()))
}

fn quote_shell_word(value: &str) -> String {
    if !value.is_empty()
        && value.chars().all(|character| {
            character.is_ascii_alphanumeric()
                || matches!(
                    character,
                    '_' | '-' | '.' | '/' | ':' | '@' | '%' | '+' | '=' | ','
                )
        })
    {
        value.to_owned()
    } else {
        format!("'{}'", value.replace('\'', "'\\''"))
    }
}

pub fn quote_word(value: &str) -> String {
    quote_shell_word(value)
}

#[cfg(test)]
mod tests {
    use std::collections::BTreeSet;

    use super::*;

    #[test]
    fn preserves_static_word_boundaries_in_projection() {
        let parsed = parse(r#"git "push --force""#).unwrap();
        assert_eq!(parsed.commands[0].projection().text(), "git 'push --force'");
    }

    #[test]
    fn finds_nested_command_substitution_as_a_command() {
        let parsed = parse(r#"gh pr create --body "$(rm -rf target)""#).unwrap();
        let executables = parsed
            .commands
            .iter()
            .filter_map(|command| command.words[0].static_value())
            .collect::<BTreeSet<_>>();
        assert_eq!(executables, BTreeSet::from(["gh", "rm"]));
    }

    #[test]
    fn does_not_treat_function_body_as_immediate_execution() {
        let parsed = parse("f() { rm -rf target; }").unwrap();
        assert!(parsed.commands.is_empty());
        assert_eq!(parsed.functions.len(), 1);
        assert_eq!(parsed.functions[0].name, "f");
    }

    #[test]
    fn pipeline_projection_marks_real_operator() {
        let parsed = parse("curl https://example.com/install | bash").unwrap();
        assert_eq!(parsed.pipelines.len(), 1);
        assert_eq!(
            parsed.pipelines[0].projection().text(),
            "curl https://example.com/install | bash"
        );
    }

    #[test]
    fn decodes_ansi_c_hex_in_executable_position() {
        let parsed = parse(r"$'\x72\x6d' -rf target").unwrap();
        assert_eq!(parsed.commands[0].words[0].static_value(), Some("rm"));
    }

    #[test]
    fn collects_standalone_redirects() {
        let parsed = parse("> /etc/hosts").unwrap();
        assert_eq!(parsed.standalone_redirects.len(), 1);
        assert_eq!(parsed.standalone_redirects[0].text(), "> /etc/hosts");
    }

    #[test]
    fn preserves_assignment_and_declaration_nodes() {
        let parsed = parse("BASH_ENV=/tmp/setup.sh bash -c true; export -f f").unwrap();
        assert_eq!(parsed.assignment_names, ["BASH_ENV"]);
        assert!(
            parsed
                .commands
                .iter()
                .any(|command| command.projection().text() == "export -f f")
        );
    }
}
