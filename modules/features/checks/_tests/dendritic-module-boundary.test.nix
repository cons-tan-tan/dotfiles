{
  inputs,
  lib,
  repoRoot,
}:
let
  modulesRoot = repoRoot + "/modules";
  allNixFiles = builtins.filter (path: lib.hasSuffix ".nix" (toString path)) (
    lib.filesystem.listFilesRecursive modulesRoot
  );
  allBatsFiles = builtins.filter (path: lib.hasSuffix ".bats" (toString path)) (
    lib.filesystem.listFilesRecursive repoRoot
  );
  expectedModuleFiles = builtins.filter (path: !lib.hasInfix "/_" (toString path)) allNixFiles;
  actualModuleFiles = (inputs.import-tree.withLib lib).leafs modulesRoot;
  isSupportPath =
    path: lib.hasInfix "/_tests/" (toString path) || lib.hasInfix "/_lib/" (toString path);
  isTestPath = path: lib.hasInfix "/_tests/" (toString path);
  supportFiles = builtins.filter isSupportPath allNixFiles;
  libNixFiles = builtins.filter (path: lib.hasInfix "/_lib/" (toString path)) allNixFiles;
  approvedLibRelativePaths = [
    "modules/features/agents/base/_lib/command-policy/aggregate.nix"
    "modules/features/agents/base/_lib/command-policy/compiler.nix"
    "modules/features/agents/base/_lib/command-policy/mk-guard.nix"
    "modules/features/agents/base/_lib/command-policy/profile.nix"
    "modules/features/agents/base/_lib/command-policy/rule-dsl.nix"
    "modules/features/agents/base/_lib/command-policy/shell-policy-schema.nix"
    "modules/features/agents/skills/_lib/aggregate.nix"
    "modules/features/agents/skills/_lib/codex-invocation-policy.nix"
    "modules/features/agents/skills/_lib/skill-policy.nix"
    "modules/features/agents/skills/_lib/yaml-frontmatter.nix"
    "modules/features/checks/_lib/bats/harness.nix"
    "modules/features/checks/_lib/bats/validate-catalog.nix"
    "modules/features/checks/_lib/compose.nix"
    "modules/features/checks/_lib/eval/den-suite-harness.nix"
    "modules/features/checks/_lib/eval/harness.nix"
    "modules/features/checks/_lib/home-contract-protocol.nix"
    "modules/features/checks/_lib/test-discovery.nix"
    "modules/features/cli-tools/_lib/aggregate.nix"
    "modules/features/lint/_lib/mk-node-lint-app.nix"
    "modules/features/nixpkgs/_lib/mk-pinned-asset.nix"
    "modules/features/nixpkgs/_lib/mk-pkgs.nix"
    "modules/features/update-pins/_lib/candidate-package.nix"
  ];
  relativePath = path: lib.removePrefix "${toString repoRoot}/" (toString path);
  unapprovedLibPaths = builtins.filter (
    path: !(builtins.elem (relativePath path) approvedLibRelativePaths)
  ) libNixFiles;
  libBoundaryViolations = builtins.filter (
    path:
    builtins.elem (baseNameOf path) [
      "catalog.nix"
      "class.nix"
      "default.nix"
      "home.nix"
      "module.nix"
      "options.nix"
      "pipe.nix"
      "policy.nix"
      "quirk.nix"
      "registry.nix"
      "settings.nix"
      "sources.nix"
    ]
    || lib.hasSuffix ".fixture.nix" (baseNameOf path)
  ) libNixFiles;
  isNonemptyModuleValue =
    path:
    let
      value = import path;
    in
    builtins.isFunction value || (builtins.isAttrs value && builtins.attrNames value != [ ]);
  architectureSourceFiles = [
    (repoRoot + "/flake.nix")
  ]
  ++ builtins.filter (path: lib.hasSuffix ".nix" (toString path)) (
    lib.filesystem.listFilesRecursive modulesRoot
  );
  architectureRelativePaths = map relativePath architectureSourceFiles;
  matchingFiles =
    needles:
    builtins.concatMap (
      path:
      let
        contents = builtins.readFile path;
      in
      lib.optional (builtins.any (needle: lib.hasInfix needle contents) needles) (relativePath path)
    ) architectureSourceFiles;
  matchingFilesBy =
    files: predicate:
    builtins.concatMap (
      path:
      let
        contents = builtins.readFile path;
      in
      lib.optional (predicate contents) (relativePath path)
    ) files;
  lineMatches = pattern: line: builtins.match pattern line != null;
  sanitizeNixSource =
    source:
    let
      length = builtins.stringLength source;
      characterAt = index: builtins.substring index 1 source;
      tokens = builtins.genList (index: {
        character = characterAt index;
        nextCharacter = if index + 1 < length then characterAt (index + 1) else "";
        nextNextCharacter = if index + 2 < length then characterAt (index + 2) else "";
      }) length;
      scanCharacter =
        accumulator: token:
        let
          blank = if token.character == "\n" then "\n" else " ";
          emit = value: updates: accumulator // updates // { output = [ value ] ++ accumulator.output; };
          escapedIndentedCharacter = builtins.elem token.nextNextCharacter [
            "$"
            "'"
            "\\"
          ];
        in
        if accumulator.skip > 0 then
          emit blank { skip = accumulator.skip - 1; }
        else if accumulator.state == "line-comment" then
          if token.character == "\n" then emit "\n" { state = "normal"; } else emit blank { }
        else if accumulator.state == "block-comment" then
          if token.character == "*" && token.nextCharacter == "/" then
            emit blank {
              state = "normal";
              skip = 1;
            }
          else
            emit blank { }
        else if accumulator.state == "double-string" then
          if accumulator.escaped then
            emit blank { escaped = false; }
          else if token.character == "\\" then
            emit blank { escaped = true; }
          else if token.character == "\"" then
            emit blank { state = "normal"; }
          else
            emit blank { }
        else if accumulator.state == "indented-string" then
          if token.character == "'" && token.nextCharacter == "'" && !escapedIndentedCharacter then
            emit blank {
              state = "normal";
              skip = 1;
            }
          else if token.character == "'" && token.nextCharacter == "'" && escapedIndentedCharacter then
            emit blank { skip = 2; }
          else
            emit blank { }
        else if token.character == "#" then
          emit blank { state = "line-comment"; }
        else if token.character == "/" && token.nextCharacter == "*" then
          emit blank {
            state = "block-comment";
            skip = 1;
          }
        else if token.character == "\"" then
          emit blank { state = "double-string"; }
        else if token.character == "'" && token.nextCharacter == "'" then
          emit blank {
            state = "indented-string";
            skip = 1;
          }
        else
          emit token.character { };
      scanned = builtins.foldl' scanCharacter {
        escaped = false;
        output = [ ];
        skip = 0;
        state = "normal";
      } tokens;
    in
    lib.concatStrings (lib.reverseList scanned.output);
  libGraphBoundaryNeedles = [
    "features."
    "den.aspects"
    "den.policies"
    "den.quirks"
    "den.schema"
    "policy.resolve"
    "pipe."
  ];
  libGraphBoundaryViolations = matchingFilesBy libNixFiles (
    contents:
    let
      sanitizedContents = sanitizeNixSource contents;
      lines = lib.splitString "\n" sanitizedContents;
    in
    builtins.any (needle: lib.hasInfix needle sanitizedContents) libGraphBoundaryNeedles
    || builtins.any (
      line: lineMatches "^[[:space:]]*(features|includes|provides)[[:space:]]*=.*$" line
    ) lines
  );
  libClassModuleViolations = matchingFilesBy libNixFiles (
    contents:
    builtins.any (
      line:
      lineMatches "^[[:space:]]*(nixos|darwin|homeManager|perSystem|generic|hjem|maid)[[:space:]]*=.*$" line
    ) (lib.splitString "\n" (sanitizeNixSource contents))
  );
  libModuleOptionViolations = matchingFilesBy libNixFiles (
    contents:
    builtins.any (
      line:
      lineMatches "^[[:space:]]*(assertions|environment|fonts|home|homebrew|launchd|networking|nix|nixpkgs|programs|security|services|system|systemd|users)[.][^=]*=.*$" line
    ) (lib.splitString "\n" (sanitizeNixSource contents))
  );
  legacyTopologyNeedles = [
    ("mk" + "Host")
    ("mk" + "Darwin")
    ("mk" + "NixosWsl")
    ("mk-home-" + "modules")
    ("linuxHost" + "Matrix")
    ("nixosWsl" + "Matrix")
    ("linux-config-" + "name")
    ("config" + ".my")
    ("options" + ".my")
    ("my." + "hostKind")
    ("my." + "dotfilesDir")
    ("my." + "windows")
    ("extraSpecialArgs" + ".inputs")
  ];
  legacyTopologyPathPrefixes = [
    ("modules/" + "_legacy/")
  ];
  legacyTopologyExactPaths = [
    ("modules/entities/_lib/configuration-" + "names.nix")
    ("modules/entities/_lib/configuration-" + "names.test.nix")
  ];
  legacyTopologyPaths = builtins.filter (
    path:
    builtins.elem path legacyTopologyExactPaths
    || builtins.any (prefix: lib.hasPrefix prefix path) legacyTopologyPathPrefixes
  ) architectureRelativePaths;
  hasLegacyExtraSpecialArgsInputs =
    contents:
    let
      sanitizedContents = sanitizeNixSource contents;
      chunks = lib.drop 1 (lib.splitString ("extraSpecial" + "Args") sanitizedContents);
      assignmentChunks = builtins.filter (
        chunk:
        lineMatches "^[[:space:]]*=.*$" (builtins.head (lib.splitString "\n" chunk))
        && lib.hasInfix "{" (builtins.head (lib.splitString ";" chunk))
      ) chunks;
      countCharacter = character: value: builtins.length (lib.splitString character value) - 1;
      takeAttributeSet =
        chunk:
        let
          takeLines =
            depth: started: lines:
            if lines == [ ] then
              [ ]
            else
              let
                line = builtins.head lines;
                nextStarted = started || lib.hasInfix "{" line;
                nextDepth = depth + countCharacter "{" line - countCharacter "}" line;
              in
              [ line ]
              ++ lib.optionals (!nextStarted || nextDepth > 0) (
                takeLines nextDepth nextStarted (builtins.tail lines)
              );
        in
        lib.concatStringsSep "\n" (takeLines 0 false (lib.splitString "\n" chunk));
      blocks = map takeAttributeSet assignmentChunks;
      hasInputsBinding =
        block:
        builtins.any (
          line:
          lineMatches "^([[:space:]]*|[^#]*[{][[:space:]]*)inherit[[:space:]]+inputs[[:space:]]*;.*$" line
          || lineMatches "^([[:space:]]*|[^#]*[{][[:space:]]*)inputs[[:space:]]*=[[:space:]]*inputs[[:space:]]*;.*$" line
        ) (lib.splitString "\n" block);
    in
    builtins.any hasInputsBinding blocks;
  extraSpecialArgsInputFiles = matchingFilesBy architectureSourceFiles hasLegacyExtraSpecialArgsInputs;
  productionArchitectureSourceFiles = builtins.filter (
    path:
    let
      pathString = toString path;
    in
    !lib.hasSuffix ".test.nix" pathString && !lib.hasInfix "/_tests/" pathString
  ) architectureSourceFiles;
  hasBroadUnfreePolicy =
    contents:
    let
      normalizedContents =
        builtins.replaceStrings
          [
            "\n"
            "\r"
            "\t"
          ]
          [
            " "
            " "
            " "
          ]
          (sanitizeNixSource contents);
    in
    builtins.match "^([^[:alnum:]_'-]*|.*[^[:alnum:]_'-])allowUnfree[[:space:]]*=[[:space:]]*(lib[.](mkForce|mkDefault)[[:space:]]+)?true[[:space:]]*;.*$" normalizedContents
    != null;
  broadUnfreePolicyFiles = matchingFilesBy productionArchitectureSourceFiles hasBroadUnfreePolicy;
  inputDeclarationsByOwner = {
    agents = (import ../../agents/default.nix { features = { }; }).flake-file.inputs;
    agentAx =
      (import ../../agents/ax/default.nix {
        features = { };
        inputs = { };
      }).flake-file.inputs;
    developmentMozuku = (import ../../development/mozuku/default.nix { }).flake-file.inputs;
    foundation = (import ../../../flake/inputs/core.nix).flake-file.inputs;
    ciTooling = (import ../../ci/inputs.nix).flake-file.inputs;
    platformConfigurations = (import ../../platform/inputs/configurations.nix).flake-file.inputs;
    repositoryChecks =
      (import ../repository.nix {
        config = { };
        den = { };
        inputs = { };
        inherit lib;
      }).flake-file.inputs;
    formatting =
      (import ../../formatting/default.nix {
        den = { };
        inputs = { };
        inherit lib;
      }).flake-file.inputs;
    pptxSkill =
      (import ../../pptx/default.nix {
        den = { };
        inputs = { };
      }).flake-file.inputs;
    darwinBrew = (import ../../platform/inputs/brew.nix { }).flake-file.inputs;
  };
  canonicalCrossClassFeatureFiles = [
    ../../agents/claude/default.nix
    ../../security/gpg/default.nix
    ../../source-control/git.nix
  ];
  retiredLocalityPaths = [
    "modules/features/platform/darwin.nix"
    "modules/features/platform/wsl.nix"
    "modules/features/windows/claude.nix"
    "modules/features/windows/git.nix"
    "modules/features/windows/gpg.nix"
    "modules/features/windows/static.nix"
    "modules/flake/inputs/mozuku.nix"
    "modules/flake/inputs/python.nix"
    "modules/features/apps/secrets.nix"
    "modules/features/apps/host.nix"
    "modules/features/apps/common.nix"
    "modules/features/apps/lint.nix"
    "modules/features/formatting.nix"
    "modules/_tests/den-entity-topology.fixture.nix"
    "modules/features/apps/update-pins.nix"
    "modules/features/platform/wsl/nix-settings.nix"
    "modules/features/packages"
    "modules/features/agents/guidance/_data/context"
    "modules/features/agents/skills/_data/local"
    "modules/features/agents/claude/_data/commands"
    "modules/features/agents/claude/_data/hooks"
    "modules/features/agents/claude/_data/output-styles"
    "modules/features/agents/pi/_data/extensions"
    "bats"
    "nix"
  ];
  nativePayloadRoots = [
    "agents/context"
    "agents/skills"
    "claude/commands"
    "claude/hooks"
    "claude/output-styles"
    "pi/extensions"
  ];
in
{
  testBatsSourcesStayWithFeatureOwner = {
    expr = map relativePath (
      builtins.filter (
        path:
        !(lib.hasPrefix "${toString modulesRoot}/features/" (toString path))
        || !(lib.hasInfix "/_tests/" (toString path))
      ) allBatsFiles
    );
    expected = [ ];
  };

  testImportTreeUsesOfficialUnderscoreBoundary = {
    expr = actualModuleFiles;
    expected = expectedModuleFiles;
  };

  testModuleAndSupportTreesDoNotIntersect = {
    expr = lib.intersectLists actualModuleFiles supportFiles;
    expected = [ ];
  };

  testPureTestsUseSupportDirectories = {
    expr = builtins.all isTestPath (
      builtins.filter (path: lib.hasSuffix ".test.nix" (toString path)) allNixFiles
    );
    expected = true;
  };

  testLibContainsOnlyReusableImplementationHelpers = {
    expr = {
      forbiddenBasenames = map relativePath libBoundaryViolations;
      unapprovedPaths = map relativePath unapprovedLibPaths;
    };
    expected = {
      forbiddenBasenames = [ ];
      unapprovedPaths = [ ];
    };
  };

  testLibDoesNotDeclareOrChangeDenGraphs = {
    expr = libGraphBoundaryViolations;
    expected = [ ];
  };

  testLibDoesNotContainClassModules = {
    expr = {
      classKeys = libClassModuleViolations;
      moduleOptions = libModuleOptionViolations;
    };
    expected = {
      classKeys = [ ];
      moduleOptions = [ ];
    };
  };

  testAutoImportedFilesHaveModuleValues = {
    expr = builtins.all isNonemptyModuleValue actualModuleFiles;
    expected = true;
  };

  testPureTestsAreNotAutoImported = {
    expr = builtins.filter (path: lib.hasSuffix ".test.nix" (toString path)) actualModuleFiles;
    expected = [ ];
  };

  testLegacyTopologyPatternsAreAbsent = {
    expr = lib.unique (
      matchingFiles legacyTopologyNeedles ++ legacyTopologyPaths ++ extraSpecialArgsInputFiles
    );
    expected = [ ];
  };

  testBroadUnfreePolicyIsAbsent = {
    expr = broadUnfreePolicyFiles;
    expected = [ ];
  };

  testInputDeclarationsPreserveOwnerAndIdentity = {
    expr = inputDeclarationsByOwner;
    expected = {
      agents.llm-agents.url = "github:numtide/llm-agents.nix";
      agentAx.ax = {
        url = "github:yusukebe/ax/v0.1.23";
        inputs.bun2nix.follows = "bun2nix";
        inputs.nixpkgs.follows = "nixpkgs";
      };
      developmentMozuku.mozuku.url = "github:t3tra-dev/MoZuKu";
      foundation = {
        den.url = "github:denful/den/2040b61346a7215fd7b7f51d4a457544b6e597d0";
        den-gen-algebra = {
          url = "github:sini/gen-algebra/dd682674edad388c439c6f2b08f84c31feec1b68";
          flake = false;
        };
        den-gen-schema = {
          url = "github:sini/gen-schema/4bd0f6eb1799bf3c38eb3707419157b1f70eb1f5";
          flake = false;
        };
        den-nix-effects = {
          url = "github:denful/nix-effects/c3c68a45deb892d028711eeff8b80937e30a90dd";
          flake = false;
        };
        flake-file.url = "github:denful/flake-file/v0.6.0";
        flake-parts = {
          url = "github:hercules-ci/flake-parts";
          inputs.nixpkgs-lib.follows = "nixpkgs-lib";
        };
        import-tree.url = "github:vic/import-tree/v0.2.0";
        nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
        nixpkgs-lib.follows = "nixpkgs";
        supported-systems = {
          url = "path:./modules/flake/_data/systems";
          flake = false;
        };
      };
      ciTooling = {
        bun2nix = {
          url = "github:nix-community/bun2nix";
          inputs.nixpkgs.follows = "nixpkgs";
          inputs.systems.follows = "supported-systems";
          inputs.treefmt-nix.follows = "treefmt-nix";
        };
      };
      platformConfigurations = {
        darwin = {
          url = "github:LnL7/nix-darwin";
          inputs.nixpkgs.follows = "nixpkgs";
        };
        home-manager = {
          url = "github:nix-community/home-manager";
          inputs.nixpkgs.follows = "nixpkgs";
        };
        nixos-wsl = {
          url = "github:nix-community/NixOS-WSL/main";
          inputs.nixpkgs.follows = "nixpkgs";
        };
      };
      repositoryChecks.rustsec-advisory-db = {
        url = "github:RustSec/advisory-db";
        flake = false;
      };
      formatting.treefmt-nix = {
        url = "github:numtide/treefmt-nix";
        inputs.nixpkgs.follows = "nixpkgs";
      };
      pptxSkill = {
        pyproject-build-systems = {
          url = "github:pyproject-nix/build-system-pkgs";
          inputs.nixpkgs.follows = "nixpkgs";
          inputs.pyproject-nix.follows = "pyproject-nix";
          inputs.uv2nix.follows = "uv2nix";
        };
        pyproject-nix = {
          url = "github:pyproject-nix/pyproject.nix";
          inputs.nixpkgs.follows = "nixpkgs";
        };
        uv2nix = {
          url = "github:pyproject-nix/uv2nix";
          inputs.nixpkgs.follows = "nixpkgs";
          inputs.pyproject-nix.follows = "pyproject-nix";
        };
      };
      darwinBrew = {
        brew-api = {
          url = "github:BatteredBunny/brew-api";
          flake = false;
        };
        brew-nix = {
          url = "github:BatteredBunny/brew-nix";
          inputs.brew-api.follows = "brew-api";
          inputs.nix-darwin.follows = "darwin";
          inputs.nixpkgs.follows = "nixpkgs";
        };
      };
    };
  };

  testCanonicalCrossClassFeaturesDoNotIncludeWindowsSubstrate = {
    expr = map relativePath (
      builtins.filter (
        path: lib.hasInfix "features.windows-base" (builtins.readFile path)
      ) canonicalCrossClassFeatureFiles
    );
    expected = [ ];
  };

  testRetiredLocalityModulesAreAbsent = {
    expr = builtins.filter (path: builtins.pathExists (repoRoot + "/${path}")) retiredLocalityPaths;
    expected = [ ];
  };

  testNativePayloadTreesRemainAtCanonicalRoots = {
    expr = builtins.all (path: builtins.pathExists (repoRoot + "/${path}")) nativePayloadRoots;
    expected = true;
  };

  testLegacyExtraSpecialArgsDetectionIsScopedToItsAttributeSet = {
    expr = [
      (hasLegacyExtraSpecialArgsInputs ''
        ${"extraSpecial" + "Args"} = {
          inherit inputs;
        };
      '')
      (hasLegacyExtraSpecialArgsInputs ''
        ${"extraSpecial" + "Args"} = {
          inputs = inputs;
        };
      '')
      (hasLegacyExtraSpecialArgsInputs ("extraSpecial" + "Args = { inherit inputs; };"))
      (hasLegacyExtraSpecialArgsInputs ''
        ${"extraSpecial" + "Args"} = {
          nested = {
            enabled = true;
          };
          inherit inputs;
        };
      '')
      (hasLegacyExtraSpecialArgsInputs ''
        ${"extraSpecial" + "Args"} = {
          note = "}";
          inherit inputs;
        };
      '')
      (hasLegacyExtraSpecialArgsInputs ''
        ${"extraSpecial" + "Args"} = {
          inherit osConfig;
        };
        inherit inputs;
      '')
      (hasLegacyExtraSpecialArgsInputs ''
        ${"extraSpecial" + "Args"} = {
          note = "{";
        };
        inherit inputs;
      '')
    ];
    expected = [
      true
      true
      true
      true
      true
      false
      false
    ];
  };

  testBroadUnfreeDetectionAllowsNarrowOrDisabledPolicies = {
    expr = map hasBroadUnfreePolicy [
      ("allow" + "Unfree = true;")
      ("nixpkgs.config.allow" + "Unfree = lib.mkForce true;")
      ("config = { allow" + "Unfree = true; };")
      ("allow" + "Unfree =\n  lib.mkDefault true;")
      ("allow" + "Unfree = false;")
      ("# allow" + "Unfree = true;")
      ("option = \"allow" + "Unfree = true;\";")
      ("/* allow" + "Unfree = true; */")
      ("allow" + "UnfreePredicate = package: package.pname == \"example\";")
    ];
    expected = [
      true
      true
      true
      true
      false
      false
      false
      false
      false
    ];
  };
}
