use clap::{Parser, ValueEnum};

#[derive(Debug, Parser)]
#[command(
    name = "update-pins",
    about = "Synchronize repository pins with their upstream releases"
)]
pub struct Cli {
    #[arg(default_value = "all", value_name = "target")]
    pub target: Target,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, ValueEnum)]
pub enum Target {
    All,
    Hcom,
    AgentSlack,
    AgentBrowser,
    Watchexec,
    Shellfirm,
    Herdr,
    Difit,
    ClaudeCodeSettingsSchema,
    CodexApp,
}

#[cfg(test)]
mod tests {
    use clap::{CommandFactory, Parser};

    use super::{Cli, Target};

    #[test]
    fn defaults_to_all_targets() {
        let cli = Cli::try_parse_from(["update-pins"]).expect("default CLI should parse");

        assert_eq!(cli.target, Target::All);
    }

    #[test]
    fn parses_every_supported_target() {
        let cases = [
            ("all", Target::All),
            ("hcom", Target::Hcom),
            ("agent-slack", Target::AgentSlack),
            ("agent-browser", Target::AgentBrowser),
            ("watchexec", Target::Watchexec),
            ("shellfirm", Target::Shellfirm),
            ("herdr", Target::Herdr),
            ("difit", Target::Difit),
            (
                "claude-code-settings-schema",
                Target::ClaudeCodeSettingsSchema,
            ),
            ("codex-app", Target::CodexApp),
        ];

        for (name, expected) in cases {
            let cli = Cli::try_parse_from(["update-pins", name])
                .unwrap_or_else(|error| panic!("{name} should parse: {error}"));
            assert_eq!(cli.target, expected);
        }
    }

    #[test]
    fn rejects_unknown_and_multiple_targets_with_usage_exit_code() {
        let unknown =
            Cli::try_parse_from(["update-pins", "unknown"]).expect_err("unknown target must fail");
        assert_eq!(unknown.exit_code(), 2);

        let multiple = Cli::try_parse_from(["update-pins", "herdr", "hcom"])
            .expect_err("multiple targets must fail");
        assert_eq!(multiple.exit_code(), 2);
    }

    #[test]
    fn help_lists_every_supported_target() {
        let help = Cli::command().render_help().to_string();

        assert!(help.contains("Usage: update-pins [target]"));
        for target in [
            "all",
            "hcom",
            "agent-slack",
            "agent-browser",
            "watchexec",
            "shellfirm",
            "herdr",
            "difit",
            "claude-code-settings-schema",
            "codex-app",
        ] {
            assert!(help.contains(target), "help omitted {target}");
        }
    }
}
