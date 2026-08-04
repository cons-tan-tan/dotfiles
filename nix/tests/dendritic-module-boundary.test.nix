{
  inputs,
  lib,
}:
let
  repoRoot = ../..;
  modulesRoot = ../../modules;
  allNixFiles = builtins.filter (path: lib.hasSuffix ".nix" (toString path)) (
    lib.filesystem.listFilesRecursive modulesRoot
  );
  expectedModuleFiles = builtins.filter (path: !lib.hasInfix "/_" (toString path)) allNixFiles;
  actualModuleFiles = (inputs.import-tree.withLib lib).leafs modulesRoot;
  isSupportPath =
    path: lib.hasInfix "/_tests/" (toString path) || lib.hasInfix "/_lib/" (toString path);
  supportFiles = builtins.filter isSupportPath allNixFiles;
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
    lib.filesystem.listFilesRecursive (repoRoot + "/nix")
    ++ lib.filesystem.listFilesRecursive modulesRoot
  );
  relativePath = path: lib.removePrefix "${toString repoRoot}/" (toString path);
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
  stripNixComments =
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
            emit token.character { escaped = false; }
          else if token.character == "\\" then
            emit token.character { escaped = true; }
          else if token.character == "\"" then
            emit token.character { state = "normal"; }
          else
            emit token.character { }
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
          emit token.character { state = "double-string"; }
        else if token.character == "'" && token.nextCharacter == "'" then
          emit token.character {
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
    ("nix/" + "hosts/")
  ];
  legacyTopologyExactPaths = [
    ("modules/entities/_lib/configuration-" + "names.nix")
    ("modules/entities/_lib/configuration-" + "names.test.nix")
    ("nix/lib/linux-config-" + "name.nix")
    ("nix/lib/linux-config-" + "name.test.nix")
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
  isProductionNixPath =
    path:
    let
      pathString = toString path;
    in
    lib.hasSuffix ".nix" pathString
    && !lib.hasInfix "/nix/checks/" pathString
    && !lib.hasInfix "/nix/tests/" pathString
    && !lib.hasSuffix ".test.nix" pathString
    && !lib.hasSuffix ".failure.test.nix" pathString;
  productionNixSourceFiles = builtins.filter isProductionNixPath (
    lib.filesystem.listFilesRecursive (repoRoot + "/nix")
  );
  removeWhitespace =
    builtins.replaceStrings
      [
        " "
        "\n"
        "\r"
        "\t"
      ]
      [
        ""
        ""
        ""
        ""
      ];
  hasModulesPathDependency =
    contents:
    let
      pathsOnly = sanitizeNixSource contents;
      commentsRemoved = removeWhitespace (stripNixComments contents);
      rootConstruction =
        builtins.match ".*[^[:alnum:]_'-][[:alnum:]_'-]*[Rr]oot[+][(]*\"/modules.*" ";${commentsRemoved}"
        != null;
    in
    lib.hasInfix "/modules/" pathsOnly || rootConstruction;
  productionModuleDependencyFiles = matchingFilesBy productionNixSourceFiles hasModulesPathDependency;
  inputDeclarationsByOwner = {
    foundation = (import ../../modules/flake/inputs/core.nix).flake-file.inputs;
    tooling = (import ../../modules/flake/inputs/tooling.nix).flake-file.inputs;
    platformConfigurations =
      (import ../../modules/features/platform/inputs/configurations.nix).flake-file.inputs;
    repositoryChecks =
      (import ../../modules/features/checks/repository.nix {
        config = { };
        den = { };
        inputs = { };
        inherit lib;
      }).flake-file.inputs;
    formatting =
      (import ../../modules/features/formatting.nix {
        den = { };
        inputs = { };
        inherit lib;
      }).flake-file.inputs;
    lintApps =
      (import ../../modules/features/apps/lint.nix {
        den = { };
        inputs = { };
        inherit lib;
      }).flake-file.inputs;
    packages =
      (import ../../modules/features/packages/default.nix {
        den = { };
        inputs = { };
      }).flake-file.inputs;
    darwinPackages =
      (import ../../modules/features/platform/darwin/packages.nix {
        den = { };
      }).flake-file.inputs;
  };
  canonicalCrossClassFeatureFiles = [
    ../../modules/features/agents/claude.nix
    ../../modules/features/security/gpg.nix
    ../../modules/features/source-control/git.nix
  ];
  retiredLocalityPaths = [
    "modules/features/platform/darwin.nix"
    "modules/features/platform/wsl.nix"
    "modules/features/windows/claude.nix"
    "modules/features/windows/git.nix"
    "modules/features/windows/gpg.nix"
    "modules/flake/inputs/mozuku.nix"
    "modules/flake/inputs/python.nix"
  ];
in
{
  testImportTreeUsesOfficialUnderscoreBoundary = {
    expr = actualModuleFiles;
    expected = expectedModuleFiles;
  };

  testModuleAndSupportTreesDoNotIntersect = {
    expr = lib.intersectLists actualModuleFiles supportFiles;
    expected = [ ];
  };

  testPureTestsUseSupportDirectories = {
    expr = builtins.all isSupportPath (
      builtins.filter (path: lib.hasSuffix ".test.nix" (toString path)) allNixFiles
    );
    expected = true;
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

  testProductionNixDoesNotDependOnModules = {
    expr = productionModuleDependencyFiles;
    expected = [ ];
  };

  testInputDeclarationsPreserveOwnerAndIdentity = {
    expr = inputDeclarationsByOwner;
    expected = {
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
          url = "path:./nix/systems";
          flake = false;
        };
      };
      tooling = {
        bun2nix = {
          url = "github:nix-community/bun2nix";
          inputs.nixpkgs.follows = "nixpkgs";
          inputs.systems.follows = "supported-systems";
          inputs.treefmt-nix.follows = "treefmt-nix";
        };
        llm-agents.url = "github:numtide/llm-agents.nix";
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
      lintApps = {
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
      packages = {
        ax = {
          url = "github:yusukebe/ax/v0.1.23";
          inputs.bun2nix.follows = "bun2nix";
          inputs.nixpkgs.follows = "nixpkgs";
        };
        mozuku.url = "github:t3tra-dev/MoZuKu";
      };
      darwinPackages = {
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

  testModulesDependencyDetectionFindsPathExpressions = {
    expr = map hasModulesPathDependency [
      "import ../../modules/features/example.nix"
      ''repoRoot + "/modules/features/example.nix"''
      ''(repoRoot + "/modules/features/example.nix")''
      ''repoRoot + ("/modules/features/example.nix")''
      ''repoRoot + (("/modules/features/example.nix"))''
    ];
    expected = [
      true
      true
      true
      true
      true
    ];
  };

  testModulesDependencyDetectionIgnoresCommentsAndDescriptions = {
    expr = map hasModulesPathDependency [
      "# import ../../modules/features/example.nix"
      "/* repoRoot + \"/modules/features/example.nix\" */"
      ''description = "modules/features/example.nix is the owner";''
      ''description = "repoRoot + \"/modules/features/example.nix\"";''
      ''description = prefix + "/modules/features/example.nix";''
      "'' description: repoRoot + \"/modules/features/example.nix\" ''"
    ];
    expected = [
      false
      false
      false
      false
      false
      false
    ];
  };

  testVerificationPathsAreExcludedByRole = {
    expr = map isProductionNixPath [
      "/repo/nix/lib/example.nix"
      "/repo/nix/checks/example.nix"
      "/repo/nix/tests/example.nix"
      "/repo/nix/lib/example.test.nix"
      "/repo/nix/lib/example.failure.test.nix"
    ];
    expected = [
      true
      false
      false
      false
      false
    ];
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
