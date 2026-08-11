{ lib, ... }:
let
  identityAliases = values: builtins.listToAttrs (map (value: lib.nameValuePair value value) values);
  aliasesTo =
    canonical: values: builtins.listToAttrs (map (value: lib.nameValuePair value canonical) values);
  mkDenyOption = takesValue: option: reason: alternative: {
    decision = true;
    optionSyntax = {
      valueTaking = lib.optional takesValue option;
      optionalEquals = [ ];
    };
    deny = [
      {
        when.options.all = [ [ option ] ];
        inherit reason;
        alternatives = [ alternative ];
      }
    ];
  };
  denyFlag = mkDenyOption false;
  denyValueOption = mkDenyOption true;

  # Executable-wide option arities used for syntax-aware scanning. Some options
  # are only valid for selected subcommands; semantic policy owns that decision.
  nixKnownOptions = {
    "--accept-flake-config" = 0;
    "--arg" = 2;
    "--arg-from-file" = 2;
    "--arg-from-stdin" = 1;
    "--argstr" = 2;
    "--commit-lock-file" = 0;
    "--debug" = 0;
    "--debugger" = 0;
    "--eval-store" = 1;
    "--expr" = 1;
    "--experimental-features" = 1;
    "--extra-experimental-features" = 1;
    "--file" = 1;
    "--impure" = 0;
    "--include" = 1;
    "--inputs-from" = 1;
    "--log-format" = 1;
    "--no-registries" = 0;
    "--no-update-lock-file" = 0;
    "--no-write-lock-file" = 0;
    "--offline" = 0;
    "--option" = 2;
    "--override-flake" = 2;
    "--override-input" = 2;
    "--output-lock-file" = 1;
    "--print-build-logs" = 0;
    "--priority" = 1;
    "--profile" = 1;
    "--quiet" = 0;
    "--recreate-lock-file" = 0;
    "--reference-lock-file" = 1;
    "--refresh" = 0;
    "--repair" = 0;
    "--stdin" = 0;
    "--store" = 1;
    "--update-input" = 1;
    "--verbose" = 0;
    "-I" = 1;
    "-L" = 0;
    "-f" = 1;
    "-v" = 0;
  };

  nixEnvOptions = {
    "--always" = 0;
    "--arg" = 2;
    "--arg-from-file" = 2;
    "--arg-from-stdin" = 1;
    "--argstr" = 2;
    "--attr" = 1;
    "--attr-path" = 0;
    "--available" = 0;
    "--compare-versions" = 0;
    "--cores" = 1;
    "--description" = 0;
    "--drv-path" = 0;
    "--dry-run" = 0;
    "--eq" = 0;
    "--eval-store" = 1;
    "--fallback" = 0;
    "--file" = 1;
    "--from-expression" = 0;
    "--from-profile" = 1;
    "--impure" = 0;
    "--include" = 1;
    "--installed" = 0;
    "--json" = 0;
    "--keep-failed" = 0;
    "--keep-going" = 0;
    "--leq" = 0;
    "--log-format" = 1;
    "--lt" = 0;
    "--max-jobs" = 1;
    "--max-silent-time" = 1;
    "--meta" = 0;
    "--no-build-output" = 0;
    "--no-name" = 0;
    "--option" = 2;
    "--out-path" = 0;
    "--prebuilt-only" = 0;
    "--preserve-installed" = 0;
    "--profile" = 1;
    "--quiet" = 0;
    "--readonly-mode" = 0;
    "--remove-all" = 0;
    "--repair" = 0;
    "--status" = 0;
    "--system" = 0;
    "--system-filter" = 1;
    "--timeout" = 1;
    "--verbose" = 0;
    "--xml" = 0;
    "-A" = 1;
    "-I" = 1;
    "-K" = 0;
    "-P" = 0;
    "-Q" = 0;
    "-a" = 0;
    "-b" = 0;
    "-c" = 0;
    "-f" = 1;
    "-j" = 1;
    "-k" = 0;
    "-p" = 1;
    "-r" = 0;
    "-s" = 0;
    "-v" = 0;
  };

  commonLegacyOptions = {
    "--log-format" = 1;
    "--option" = 2;
    "--quiet" = 0;
    "--verbose" = 0;
    "-v" = 0;
  };

  legacyEvaluatorOptions = commonLegacyOptions // {
    "--arg" = 2;
    "--arg-from-file" = 2;
    "--arg-from-stdin" = 1;
    "--argstr" = 2;
    "--attr" = 1;
    "--cores" = 1;
    "--eval-store" = 1;
    "--expr" = 0;
    "--file" = 1;
    "--include" = 1;
    "--max-jobs" = 1;
    "--max-silent-time" = 1;
    "--override-flake" = 2;
    "--repair" = 0;
    "--store" = 1;
    "--timeout" = 1;
    "-A" = 1;
    "-E" = 0;
    "-I" = 1;
    "-f" = 1;
    "-j" = 1;
  };

  legacyBuildOptions = legacyEvaluatorOptions // {
    "--drv-link" = 1;
    "--exclude" = 1;
    "--keep" = 1;
    "--out-link" = 1;
    "-o" = 1;
  };

  nixStoreOptions = commonLegacyOptions // {
    "--arg" = 2;
    "--arg-from-file" = 2;
    "--arg-from-stdin" = 1;
    "--argstr" = 2;
    "--add-root" = 1;
    "--binding" = 1;
    "--cores" = 1;
    "--max-freed" = 1;
    "--max-jobs" = 1;
    "--max-silent-time" = 1;
    "--repair" = 0;
    "--store" = 1;
    "--timeout" = 1;
    "-I" = 1;
    "-b" = 1;
    "-j" = 1;
  };

  stage =
    {
      aliases,
      at ? [ ],
      selector,
      unknownOption ? "deny",
      unknownSelector ? "deny",
    }:
    {
      inherit
        aliases
        at
        selector
        unknownOption
        unknownSelector
        ;
    };
in
{
  features.nix-command-policy =
    { config, ... }:
    {
      name = "feature/nix/command-policy";
      agent-command-policy = [
        {
          owner = config.name;
          policy = {
            commandGrammars = {
              nix = {
                executableAliases = {
                  "nixpkgs#fd" = "fd";
                  "nixpkgs#nix" = "nix";
                  "nixpkgs#nixVersions.latest" = "nix";
                  "nixpkgs#nixVersions.stable" = "nix";
                  "nixpkgs#rm" = "rm";
                };
                options = nixKnownOptions;
                terminalOptions = [
                  "--help"
                  "--version"
                ];
                stages = [
                  (stage {
                    selector = "positional";
                    unknownSelector = "ignore";
                    aliases = identityAliases [
                      "profile"
                      "build"
                      "copy"
                      "develop"
                      "print-dev-env"
                      "registry"
                      "run"
                      "shell"
                      "store"
                      "upgrade-nix"
                    ];
                  })
                  (stage {
                    at = [ "profile" ];
                    selector = "positional";
                    aliases = identityAliases [
                      "add"
                      "diff-closures"
                      "history"
                      "install"
                      "list"
                      "remove"
                      "rollback"
                      "upgrade"
                      "wipe-history"
                    ];
                  })
                  (stage {
                    at = [ "registry" ];
                    selector = "positional";
                    aliases = identityAliases [
                      "add"
                      "list"
                      "pin"
                      "remove"
                      "resolve"
                    ];
                  })
                  (stage {
                    at = [ "store" ];
                    selector = "positional";
                    aliases = identityAliases [
                      "add"
                      "add-file"
                      "add-path"
                      "cat"
                      "copy-log"
                      "copy-sigs"
                      "delete"
                      "diff-closures"
                      "dump-path"
                      "gc"
                      "info"
                      "ls"
                      "make-content-addressed"
                      "optimise"
                      "path-from-hash-part"
                      "prefetch-file"
                      "repair"
                      "roots-daemon"
                      "sign"
                      "verify"
                    ];
                  })
                ];
              };

              "nix-env" = {
                options = nixEnvOptions;
                terminalOptions = [
                  "--help"
                  "--version"
                ];
                stages = [
                  (stage {
                    selector = "option";
                    unknownSelector = "ignore";
                    aliases =
                      aliasesTo "install" [
                        "--install"
                        "-i"
                      ]
                      // aliasesTo "upgrade" [
                        "--upgrade"
                        "-u"
                      ]
                      // aliasesTo "uninstall" [
                        "--uninstall"
                        "-e"
                      ]
                      // aliasesTo "switch-profile" [
                        "--switch-profile"
                        "-S"
                      ]
                      // aliasesTo "switch-generation" [
                        "--switch-generation"
                        "-G"
                      ]
                      // aliasesTo "delete-generations" [ "--delete-generations" ]
                      // aliasesTo "list-generations" [ "--list-generations" ]
                      // aliasesTo "query" [ "--query" ]
                      // aliasesTo "rollback" [ "--rollback" ]
                      // aliasesTo "set" [ "--set" ]
                      // aliasesTo "set-flag" [ "--set-flag" ]
                      // aliasesTo "query" [ "-q" ];
                  })
                ];
              };

              "nix-build" = {
                options = legacyBuildOptions // {
                  "--dry-run" = 0;
                  "--no-out-link" = 0;
                };
                terminalOptions = [
                  "--help"
                  "--version"
                ];
                stages = [ ];
              };

              "nix-instantiate" = {
                options = legacyEvaluatorOptions // {
                  "--add-root" = 1;
                  "--eval" = 0;
                  "--find-file" = 0;
                  "--json" = 0;
                  "--parse" = 0;
                  "--read-write-mode" = 0;
                  "--strict" = 0;
                  "--xml" = 0;
                };
                terminalOptions = [
                  "--help"
                  "--version"
                ];
                stages = [ ];
              };

              "nix-shell" = {
                options = legacyBuildOptions // {
                  "--command" = 1;
                  "--packages" = 0;
                  "--pure" = 0;
                  "--run" = 1;
                  "--shell-file" = 1;
                  "-i" = 1;
                  "-p" = 0;
                };
                terminalOptions = [
                  "--help"
                  "--version"
                ];
                stages = [ ];
              };

              "nix-channel" = {
                options = commonLegacyOptions;
                terminalOptions = [
                  "--help"
                  "--version"
                ];
                stages = [
                  (stage {
                    selector = "option";
                    unknownSelector = "ignore";
                    aliases =
                      aliasesTo "add" [ "--add" ]
                      // aliasesTo "list" [ "--list" ]
                      // aliasesTo "list-generations" [ "--list-generations" ]
                      // aliasesTo "remove" [ "--remove" ]
                      // aliasesTo "rollback" [ "--rollback" ]
                      // aliasesTo "update" [ "--update" ];
                  })
                ];
              };

              "nix-collect-garbage" = {
                options = commonLegacyOptions // {
                  "--dry-run" = 0;
                  "--max-freed" = 1;
                };
                terminalOptions = [
                  "--help"
                  "--version"
                ];
                stages = [
                  (stage {
                    selector = "option";
                    unknownOption = "ignore";
                    unknownSelector = "ignore";
                    aliases =
                      aliasesTo "delete-old" [
                        "--delete-old"
                        "-d"
                      ]
                      // aliasesTo "delete-older-than" [ "--delete-older-than" ];
                  })
                ];
              };

              "nix-store" = {
                options = nixStoreOptions;
                terminalOptions = [
                  "--help"
                  "--version"
                ];
                stages = [
                  (stage {
                    selector = "option";
                    unknownOption = "ignore";
                    aliases =
                      aliasesTo "realise" [
                        "--realise"
                        "-r"
                      ]
                      // aliasesTo "serve" [ "--serve" ]
                      // aliasesTo "gc" [ "--gc" ]
                      // aliasesTo "delete" [ "--delete" ]
                      // aliasesTo "query" [
                        "--query"
                        "-q"
                      ]
                      // aliasesTo "add" [ "--add" ]
                      // aliasesTo "add-fixed" [ "--add-fixed" ]
                      // aliasesTo "verify" [ "--verify" ]
                      // aliasesTo "verify-path" [ "--verify-path" ]
                      // aliasesTo "repair-path" [ "--repair-path" ]
                      // aliasesTo "dump" [ "--dump" ]
                      // aliasesTo "restore" [ "--restore" ]
                      // aliasesTo "export" [ "--export" ]
                      // aliasesTo "import" [ "--import" ]
                      // aliasesTo "optimise" [ "--optimise" ]
                      // aliasesTo "read-log" [ "--read-log" ]
                      // aliasesTo "dump-db" [ "--dump-db" ]
                      // aliasesTo "load-db" [ "--load-db" ]
                      // aliasesTo "print-env" [ "--print-env" ]
                      // aliasesTo "generate-binary-cache-key" [ "--generate-binary-cache-key" ];
                  })
                ];
              };

              nh = {
                options = {
                  "--elevation-strategy" = 1;
                  "--quiet" = 0;
                  "--verbose" = 0;
                  "-e" = 1;
                  "-q" = 0;
                  "-v" = 0;
                };
                terminalOptions = [
                  "--help"
                  "--version"
                  "-h"
                  "-V"
                ];
                stages = [
                  (stage {
                    selector = "positional";
                    unknownSelector = "ignore";
                    aliases = identityAliases [ "clean" ];
                  })
                  (stage {
                    at = [ "clean" ];
                    selector = "positional";
                    aliases = identityAliases [
                      "all"
                      "profile"
                      "user"
                    ];
                  })
                ];
              };
            };

            commands = {
              # These rules govern agent actions only. Recovery commands remain
              # available to the user, but an agent must not imperatively move
              # a profile away from the declarative Home/System configuration.
              nix = {
                _self =
                  denyFlag "--repair" "Agents must not rewrite missing or corrupted Nix store paths."
                    "Let the user perform store recovery manually.";
                build =
                  denyValueOption "--profile" "Agents must not create or update a profile from nix build."
                    "Build without --profile and switch through the declarative configuration.";
                copy =
                  denyValueOption "--profile" "Agents must not create or update a profile from nix copy."
                    "Copy store paths without --profile.";
                develop =
                  denyValueOption "--profile" "Agents must not create or update a profile from nix develop."
                    "Enter the development environment without --profile.";
                print-dev-env =
                  denyValueOption "--profile" "Agents must not create or update a profile from nix print-dev-env."
                    "Print the environment without --profile.";
                profile = {
                  add = false;
                  install = false;
                  remove = false;
                  rollback = false;
                  upgrade = false;
                  wipe-history = false;
                };
                registry = {
                  add = false;
                  pin = false;
                  remove = false;
                };
                store = {
                  delete = false;
                  gc = false;
                  repair = false;
                };
                upgrade-nix = false;
              };
              "nix-env" = {
                delete-generations = false;
                install = false;
                rollback = false;
                set = false;
                set-flag = false;
                switch-generation = false;
                switch-profile = false;
                uninstall = false;
                upgrade = false;
              };
              "nix-build"._self =
                denyFlag "--repair" "Agents must not repair store paths through nix-build."
                  "Build without --repair, or let the user perform recovery manually.";
              "nix-instantiate"._self =
                denyFlag "--repair" "Agents must not repair store paths through nix-instantiate."
                  "Evaluate without --repair, or let the user perform recovery manually.";
              "nix-shell"._self =
                denyFlag "--repair" "Agents must not repair store paths through nix-shell."
                  "Enter the shell without --repair, or let the user perform recovery manually.";
              "nix-channel" = {
                add = false;
                remove = false;
                rollback = false;
                update = false;
              };
              # Store reclamation and nh cleanup are intentionally all-or-
              # nothing: even their default forms delete unreachable paths.
              "nix-collect-garbage" = false;
              "nix-store" = {
                delete = false;
                gc = false;
                load-db = false;
                realise =
                  denyFlag "--repair" "Agents must not repair store paths while realising them."
                    "Realise without --repair, or let the user perform recovery manually.";
                repair-path = false;
                verify = false;
              };
              nh.clean = false;
            };
          };
        }
      ];
    };
}
