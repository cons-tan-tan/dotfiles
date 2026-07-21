# yaml-frontmatter.nix の純関数テスト。nix/tests/default.nix が
# *.test.nix を収集して lib.runTests を適用する。
{ lib }:
let
  fm = import ./yaml-frontmatter.nix { inherit lib; };

  withFm = "---\nname: demo\n---\nbody line\n";
  noFm = "body only\n---\nnot frontmatter\n";
  failsToEvaluate = value: !(builtins.tryEval (builtins.deepSeq value true)).success;
in
{
  testSplitWithFrontmatter = {
    expr = fm.splitFrontmatter withFm;
    expected = {
      frontmatter = "---\nname: demo\n---\n";
      body = "body line\n";
    };
  };

  # 先頭が "---\n" でなければ全体を本文として扱う
  testSplitWithoutFrontmatter = {
    expr = fm.splitFrontmatter noFm;
    expected = {
      frontmatter = "";
      body = noFm;
    };
  };

  # 本文中の "\n---\n" (Markdown の水平線) が分割で失われないこと
  testSplitBodyKeepsHr = {
    expr = (fm.splitFrontmatter "---\na: 1\n---\npart1\n---\npart2\n").body;
    expected = "part1\n---\npart2\n";
  };

  testSplitNormalizesBomAndCrLf = {
    expr = fm.splitFrontmatter "${fm.utf8Bom}---\r\nname: demo\r\n---\r\nbody\r\n";
    expected = {
      frontmatter = "---\nname: demo\n---\n";
      body = "body\n";
    };
  };

  testSplitClosingDelimiterAtEof = {
    expr = fm.splitFrontmatter "---\nname: demo\n---";
    expected = {
      frontmatter = "---\nname: demo\n---\n";
      body = "";
    };
  };

  testSplitRejectsUnterminatedFrontmatter = {
    expr = failsToEvaluate (fm.splitFrontmatter "---\nname: demo\nbody\n");
    expected = true;
  };

  testFoldYamlBlockLines = {
    expr = fm.foldYamlBlockLines [
      "first"
      "second"
      ""
      "third"
    ];
    expected = "first second\nthird";
  };

  testFoldYamlBlockLinesPreservesMoreIndentedBreaks = {
    expr = fm.foldYamlBlockLines [
      "first"
      "  indented"
      ""
      "last"
    ];
    expected = "first\n  indented\n\nlast";
  };

  testFoldYamlBlockLinesPreservesBreakBeforeMoreIndentedLine = {
    expr = fm.foldYamlBlockLines [
      "first"
      ""
      "  indented"
    ];
    expected = "first\n\n  indented";
  };

  testFoldYamlBlockLinesTreatsTabAsContent = {
    expr = fm.foldYamlBlockLines [
      "first"
      "\t"
      "last"
    ];
    expected = "first\n\t\nlast";
  };

  testNormalizeDescriptionFoldsMultilineText = {
    expr = fm.normalizeDescription ''
      Slack automation CLI for AI agents.

        Use when Slack interaction is required.
    '';
    expected = "Slack automation CLI for AI agents. Use when Slack interaction is required.";
  };

  testSetFrontmatterFieldWithFrontmatter = {
    expr = fm.setFrontmatterField "disable-model-invocation" "true" withFm;
    expected = "---\ndisable-model-invocation: true\nname: demo\n---\nbody line\n";
  };

  testSetFrontmatterFieldWithoutFrontmatter = {
    expr = fm.setFrontmatterField "disable-model-invocation" "true" noFm;
    expected = "---\ndisable-model-invocation: true\n---\n${noFm}";
  };

  testSetFrontmatterFieldReplacesExisting = {
    expr = fm.setFrontmatterField "disable-model-invocation" "true" ''
      ---
      name: demo
      disable-model-invocation: false
      ---
      body
    '';
    expected = ''
      ---
      name: demo
      disable-model-invocation: true
      ---
      body
    '';
  };

  testSetFrontmatterFieldReplacesBlockValue = {
    expr = fm.setFrontmatterField "description" "New description." ''
      ---
      name: demo
      description: |
        Old description.
        More old text.
      license: MIT
      ---
      body
    '';
    expected = ''
      ---
      name: demo
      description: New description.
      license: MIT
      ---
      body
    '';
  };

  testFilterFrontmatterFields = {
    expr =
      fm.filterFrontmatterFields
        [
          "name"
          "description"
          "license"
          "compatibility"
          "metadata"
          "hidden"
        ]
        ''
          ---
          name: demo
          description: |
            Multi-line description.
          license: MIT
          compatibility: Requires git and network access
          metadata:
            author: Example
          allowed-tools: Bash(example:*)
          hooks:
            PreToolUse: echo unsafe
          hidden: true
          ---
          body
        '';
    expected = ''
      ---
      name: demo
      description: |
        Multi-line description.
      license: MIT
      compatibility: Requires git and network access
      metadata:
        author: Example
      hidden: true
      ---
      body
    '';
  };

  testFilterFrontmatterFieldsAllowsExplicitField = {
    expr =
      fm.filterFrontmatterFields
        [
          "name"
          "description"
          "allowed-tools"
        ]
        ''
          ---
          name: demo
          description: Demo.
          allowed-tools: Bash(example:*)
          hidden: true
          ---
          body
        '';
    expected = ''
      ---
      name: demo
      description: Demo.
      allowed-tools: Bash(example:*)
      ---
      body
    '';
  };

  testFrontmatterFieldNamesListsTopLevelFields = {
    expr = fm.frontmatterFieldNames ''
      ---
      name: demo
      description: |
        Demo skill.
      metadata:
        author: Example
      allowed-tools: Bash(example:*)
      # comment
      hidden: true
      ---
      body
    '';
    expected = [
      "name"
      "description"
      "metadata"
      "allowed-tools"
      "hidden"
    ];
  };

  testFrontmatterFieldNamesAllowsLeadingWhitespaceAndComments = {
    expr = fm.frontmatterFieldNames "---\n  \n  # comment\nname: demo\ndescription: Demo.\n---\nbody\n";
    expected = [
      "name"
      "description"
    ];
  };

  testFrontmatterFieldNamesRejectsUnsupportedTopLevelSyntax = {
    expr = failsToEvaluate (
      fm.frontmatterFieldNames ''
        ---
        name: demo
        description: Demo.
        <<: *defaults
        ---
        body
      ''
    );
    expected = true;
  };

  # YAML merge key など、許可fieldの継続行ではない構文は保持しない。
  testFilterFrontmatterFieldsDropsUnknownTopLevelSyntax = {
    expr = fm.filterFrontmatterFields [ "name" "description" ] ''
      ---
      name: demo
      description: Demo.
      <<: *defaults
        allowed-tools: Bash(example:*)
      ---
      body
    '';
    expected = ''
      ---
      name: demo
      description: Demo.
      ---
      body
    '';
  };

  testFilterFrontmatterFieldsWithoutFrontmatter = {
    expr = fm.filterFrontmatterFields [ "name" "description" ] noFm;
    expected = noFm;
  };

  testFilterFrontmatterFieldsBlocksAllowedToolsWithCrLf = {
    expr = fm.filterFrontmatterFields [ "name" "description" ] (
      "---\r\nname: demo\r\ndescription: Demo.\r\nallowed-tools: Bash(example:*)\r\n---\r\nbody\r\n"
    );
    expected = "---\nname: demo\ndescription: Demo.\n---\nbody\n";
  };

  testFilterFrontmatterFieldsBlocksAllowedToolsWithBom = {
    expr = fm.filterFrontmatterFields [ "name" "description" ] (
      "${fm.utf8Bom}---\nname: demo\ndescription: Demo.\nallowed-tools: Bash(example:*)\n---\nbody\n"
    );
    expected = "---\nname: demo\ndescription: Demo.\n---\nbody\n";
  };

  testUtf8CodePointLength = {
    expr = fm.utf8CodePointLength "aあ🙂";
    expected = 3;
  };

}
