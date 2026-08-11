{
  ciCheck,
  currentTargets,
  flake,
  lib,
  pkgs,
  subjects,
  username,
}:
let
  commandPolicyInterface = import ../../agents/base/_interface/command-policy.nix;
  repositoryHome =
    if pkgs.stdenv.hostPlatform.isDarwin then
      flake.darwinConfigurations.${currentTargets.darwin}.config.home-manager.users.${username}
    else
      flake.homeConfigurations.${currentTargets.home.linux}.config;
  guardHook = commandPolicyInterface.mkGuard {
    inherit lib pkgs;
    policy = repositoryHome.dotfiles.agentCommandPolicyCompiled.guardPolicy;
  };

  exactDenyReason = "Forbidden by the shared agent command policy";
  semanticDenyReason = "Agents must not";
  rejectedReason = "could not safely analyze";

  exactDeniedCommands = [
    "nix profile add nixpkgs#hello"
    "/usr/bin/nix profile add nixpkgs#hello"
    "nix profile install nixpkgs#hello"
    "nix profile remove hello"
    "nix profile rollback"
    "nix profile upgrade hello"
    "nix profile wipe-history"
    "nix profile add --argstr marker --help nixpkgs#hello"
    "nix registry add dotfiles path:/tmp/dotfiles"
    "nix registry pin nixpkgs"
    "nix registry remove dotfiles"
    "nix store delete /nix/store/example"
    "nix store gc"
    "nix store repair /nix/store/example"
    "nix upgrade-nix"
    "nix-env --install hello"
    "nix-env --upgrade hello"
    "nix-env --uninstall hello"
    "nix-env --set hello"
    "nix-env --set-flag keep true hello"
    "nix-env --switch-profile /tmp/profile"
    "nix-env --switch-generation 1"
    "nix-env --rollback"
    "nix-env --delete-generations old"
    "nix-env -i hello"
    "nix-env -u hello"
    "nix-env -e hello"
    "nix-env -S /tmp/profile"
    "nix-env -G 1"
    "nix-channel --add https://example.invalid/channel test"
    "nix-channel --remove test"
    "nix-channel --rollback"
    "nix-channel --update"
    "nix-collect-garbage"
    "nix-store --delete /nix/store/example"
    "nix-store --gc"
    "nix-store --gc --argstr marker --help"
    "nix-store --repair-path /nix/store/example"
    "nix-store --load-db"
    "nix-store --verify"
    "nh clean all"
    "nix run nixpkgs#nix -- profile add nixpkgs#hello"
    "nix run nixpkgs#nixVersions.latest -- profile add nixpkgs#hello"
    "nix run nixpkgs#nixVersions.stable -- profile add nixpkgs#hello"
    "nix run --offline nixpkgs#nixVersions.latest -- profile add nixpkgs#hello"
    "nix develop -vv nixpkgs#nix --command nix profile add nixpkgs#hello"
    "nix-shell -p nix --run 'nix profile add nixpkgs#hello'"
  ];

  semanticDeniedCommands = [
    "nix build --profile /tmp/agent-guard-profile nixpkgs#hello"
    "nix --offline build --profile /tmp/agent-guard-profile nixpkgs#hello"
    "nix develop --profile /tmp/agent-guard-profile nixpkgs#hello"
    "nix print-dev-env --profile /tmp/agent-guard-profile nixpkgs#hello"
    "nix copy --from /tmp/nix --profile /tmp/agent-guard-profile /nix/store/example"
    "nix store verify --repair /nix/store/example"
    "nix-store --realise --repair /nix/store/example"
    "nix-store --repair --realise /nix/store/example"
    "nix-store --repair -r /nix/store/example"
    "nix build --repair nixpkgs#hello"
    "nix develop --repair nixpkgs#hello --command true"
    "nix eval --repair --expr '1'"
    "nix-build --repair nixpkgs#hello"
    "nix-build --expr --repair 'builtins.currentSystem'"
    "nix-build -E --repair 'builtins.currentSystem'"
    "nix-instantiate --repair '<nixpkgs>' -A hello"
    "nix-instantiate --expr --repair 'builtins.currentSystem'"
    "nix-shell --repair -p hello"
    "nix-shell --expr --repair 'import <nixpkgs> {}'"
  ];

  rejectedCommands = [
    "nix run nixpkgs#unknown -- profile add nixpkgs#hello"
    "nix profile future-mutate target"
    "nix-env --future-operation target"
    "nix-store --future-operation target"
    "nix \"$TOP_LEVEL\" add nixpkgs#hello"
    "nix profile \"$ACTION\" target"
    "nix-env \"$OPERATION\" target"
    "nix profile add nixpkgs#hello \"$OPTION\" --help"
    "nix --store $STORE profile list"
    "nix --store \"\${@:1}\" profile list"
    "zsh -c 'nix --store \"$=STORE\" profile list'"
    "nix build --argstr marker -- \"$OPTION\""
    "nix build --future-option value -- \"$OPTION\""
    "nix-shell --future-option value --run 'nix profile add nixpkgs#hello'"
    "nh --future-cache /tmp clean all"
  ];

  reasonedDeniedCommands = [
    {
      command = "nix run nixpkgs#rm -- -rf target";
      reason = "Recursive forced deletion";
    }
    {
      command = "nix run nixpkgs#fd -- --exec echo";
      reason = "fd command execution options";
    }
  ];

  safeCommands = [
    "nix profile list"
    "nix profile history"
    "nix profile diff-closures"
    "nix profile add --help"
    "nix --help profile add"
    "nix profile --help add"
    "nix profile list --profile \"$PROFILE\""
    "nix --store \"$STORE\" profile list"
    "zsh -c 'nix --store \"$STORE\" profile list'"
    "nix registry list"
    "nix registry resolve nixpkgs"
    "nix store diff-closures /nix/store/a /nix/store/b"
    "nix store info"
    "nix --store local profile list"
    "nix -vv profile list"
    "nix build nixpkgs#hello"
    "nix build --argstr marker --profile nixpkgs#hello"
    "nix build --output-lock-file --profile nixpkgs#hello"
    "nix build --option key --profile nixpkgs#hello"
    "nix eval --argstr marker --repair --expr 'marker: marker'"
    "nix-build --argstr marker --repair '<nixpkgs>' -A hello"
    "nix-build --override-flake nixpkgs --repair '<nixpkgs>' -A hello"
    "nix-build --cores --repair '<nixpkgs>' -A hello"
    "nix-build --cores \"$CORES\" '<nixpkgs>' -A hello"
    "nix-build --exclude --repair '<nixpkgs>' -A hello"
    "nix-build --drv-link --repair '<nixpkgs>' -A hello"
    "nix-build -o --repair '<nixpkgs>' -A hello"
    "nix-instantiate --argstr marker --repair --eval --expr 'marker: marker'"
    "nix-instantiate --add-root --repair --eval --expr '1'"
    "nix-instantiate --timeout --repair --eval --expr '1'"
    "nix-instantiate --store --repair --eval --expr '1'"
    "nix-shell --argstr marker --repair --run true"
    "nix-shell --exclude --repair --run true"
    "nix-shell --out-link --repair --run true"
    "nix-shell -i --repair --run true"
    "nix-shell --override-flake nixpkgs --run '<nixpkgs>' -A hello"
    "nix-shell --out-link --run '<nixpkgs>' -A hello"
    "nix-shell -i --run '<nixpkgs>' -A hello"
    "nix-shell --help --run 'nix profile add nixpkgs#hello'"
    "nix-shell() { printf safe; }; nix-shell --repair"
    "nix develop nixpkgs#hello --command true"
    "nix develop nixpkgs#hello --command printf --profile"
    "nix develop nixpkgs#hello --command printf --help"
    "nix shell nixpkgs#hello --command printf --repair"
    "nix shell nixpkgs#hello --command printf --version"
    "nix print-dev-env nixpkgs#hello"
    "nix store verify /nix/store/example"
    "nix-store --query --references /nix/store/example"
    "nix-store --query --repair --references /nix/store/example"
    "nix-store --store --repair --realise /nix/store/example"
    "nix-env -qc"
    "nix-env -q -c"
    "nix-env --query --repair"
    "nix-env --query \"$PACKAGE\""
    "nix-env --list-generations --repair"
    "nix-env --help --install"
    "nix-channel --list"
    "nix-channel --list-generations"
    "nix-collect-garbage --help"
  ];

  renderDenyChecks =
    reason: commands:
    lib.concatMapStringsSep "\n" (
      command:
      lib.escapeShellArgs [
        "check_deny"
        reason
        command
      ]
    ) commands;
  renderReasonedDenyChecks = lib.concatMapStringsSep "\n" (
    entry:
    lib.escapeShellArgs [
      "check_deny"
      entry.reason
      entry.command
    ]
  );
in
{
  owner = "Nix command policy integration checks";
  artifacts = [ ];
  buildEntries.nix-command-policy-integration =
    ciCheck.buildEntry (ciCheck.targets.both "rust-and-bats")
      (
        pkgs.runCommand "nix-command-policy-integration"
          {
            nativeBuildInputs = [
              pkgs.jq
              subjects.agentCommandGuard
            ];
          }
          ''
            run_guard() {
              jq --null-input --compact-output \
                --arg cwd "$TMPDIR" \
                --arg command "$1" \
                '{
                  cwd: $cwd,
                  hook_event_name: "PreToolUse",
                  tool_name: "Bash",
                  tool_input: {command: $command}
                }' \
                | agent-command-guard --policy ${guardHook.policyFile}
            }

            check_deny() {
              expected_reason="$1"
              command="$2"
              output="$(run_guard "$command")"
              decision="$(printf '%s' "$output" \
                | jq -r '.hookSpecificOutput.permissionDecision')"
              reason="$(printf '%s' "$output" \
                | jq -r '.hookSpecificOutput.permissionDecisionReason')"
              test "$decision" = deny
              case "$reason" in
                *"$expected_reason"*) ;;
                *)
                  printf 'unexpected deny reason for %s: %s\n' "$command" "$reason" >&2
                  return 1
                  ;;
              esac
            }

            check_safe() {
              test "$(run_guard "$1")" = '{}'
            }

            ${renderDenyChecks exactDenyReason exactDeniedCommands}
            ${renderDenyChecks semanticDenyReason semanticDeniedCommands}
            ${renderDenyChecks rejectedReason rejectedCommands}
            ${renderReasonedDenyChecks reasonedDeniedCommands}
            ${lib.concatMapStringsSep "\n" (command: "check_safe ${lib.escapeShellArg command}") safeCommands}

            touch "$out"
          ''
      );
}
