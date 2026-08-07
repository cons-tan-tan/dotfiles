use serde::Serialize;

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum OperatorGroup {
    Boolean,
    Logical,
    Equality,
}

impl OperatorGroup {
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "boolean" => Some(Self::Boolean),
            "logical" => Some(Self::Logical),
            "equality" => Some(Self::Equality),
            _ => None,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub enum MutationKind {
    BooleanFalse,
    BooleanTrue,
    EqualityEqual,
    EqualityNotEqual,
    LogicalAnd,
    LogicalOr,
}

impl MutationKind {
    pub fn name(self) -> &'static str {
        match self {
            Self::BooleanFalse => "boolean-false",
            Self::BooleanTrue => "boolean-true",
            Self::EqualityEqual => "equality-equal",
            Self::EqualityNotEqual => "equality-not-equal",
            Self::LogicalAnd => "logical-and",
            Self::LogicalOr => "logical-or",
        }
    }

    pub fn group(self) -> OperatorGroup {
        match self {
            Self::BooleanFalse | Self::BooleanTrue => OperatorGroup::Boolean,
            Self::LogicalAnd | Self::LogicalOr => OperatorGroup::Logical,
            Self::EqualityEqual | Self::EqualityNotEqual => OperatorGroup::Equality,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct Position {
    pub line: usize,
    pub column: usize,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct Range {
    pub start: Position,
    pub end: Position,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct Offsets {
    pub start: usize,
    pub end: usize,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
pub struct Candidate {
    pub id: String,
    pub file: String,
    pub mutation: String,
    pub operator: OperatorGroup,
    pub text: String,
    pub replacement: String,
    pub range: Range,
    #[serde(rename = "replacementOffsets")]
    pub replacement_offsets: Offsets,
    #[serde(rename = "sourceHash")]
    pub source_hash: String,
}

impl Candidate {
    pub fn location(&self) -> String {
        format!(
            "{}:{}:{}",
            self.file,
            self.range.start.line + 1,
            self.range.start.column + 1
        )
    }
}

#[derive(Default)]
pub struct Summary {
    pub killed: usize,
    pub survived: usize,
    pub invalid: usize,
    pub timed_out: usize,
}
