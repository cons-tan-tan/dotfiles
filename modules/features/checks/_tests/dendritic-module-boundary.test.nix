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
  supportFiles = builtins.filter isSupportPath allNixFiles;
  relativePath = path: lib.removePrefix "${toString repoRoot}/" (toString path);
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
  matchingFilesBy =
    files: predicate:
    builtins.concatMap (
      path:
      let
        contents = builtins.readFile path;
      in
      lib.optional (predicate contents) (relativePath path)
    ) files;
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
  windowsSubstrateDependencyViolations =
    matchingFilesBy
      (builtins.filter (
        path: !lib.hasInfix "/modules/features/windows/" (toString path)
      ) productionArchitectureSourceFiles)
      (contents: lib.hasInfix "features.windows-base" (sanitizeNixSource contents));
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

  testAutoImportedFilesHaveModuleValues = {
    expr = builtins.all isNonemptyModuleValue actualModuleFiles;
    expected = true;
  };

  testWindowsSubstrateIsOwnedByWindowsComposition = {
    expr = windowsSubstrateDependencyViolations;
    expected = [ ];
  };

  testPureTestsAreNotAutoImported = {
    expr = builtins.filter (
      path: lib.hasSuffix ".test.nix" (toString path) || lib.hasSuffix ".suite.nix" (toString path)
    ) actualModuleFiles;
    expected = [ ];
  };

  testBroadUnfreePolicyIsAbsent = {
    expr = broadUnfreePolicyFiles;
    expected = [ ];
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
