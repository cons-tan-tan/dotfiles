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
