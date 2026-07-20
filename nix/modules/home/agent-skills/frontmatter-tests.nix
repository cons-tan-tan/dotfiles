# frontmatter.nix の純関数テスト。lib.runTests は失敗ケースのリストを返す
# (空リスト = 全 pass)。flake.nix の checks が eval 時に空であることを
# assert するため、退行は nix flake check --no-build の段階で検知される。
{ lib }:
let
  fm = import ./frontmatter.nix { inherit lib; };

  withFm = "---\nname: demo\n---\nbody line\n";
  noFm = "body only\n---\nnot frontmatter\n";
in
lib.runTests {
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

  testReplaceFrontmatter = {
    expr = fm.replaceFrontmatter "---\nnew: true\n---\n" withFm;
    expected = "---\nnew: true\n---\nbody line\n";
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

  testCodexPolicyCreatedWhenMissingFile = {
    expr = fm.disableCodexImplicitInvocation "";
    expected = ''
      policy:
        allow_implicit_invocation: false
    '';
  };

  testCodexPolicyAppendedWithoutDroppingInterface = {
    expr = fm.disableCodexImplicitInvocation ''
      interface:
        display_name: 'Difit'
        default_prompt: 'Use $difit.'
    '';
    expected = ''
      interface:
        display_name: 'Difit'
        default_prompt: 'Use $difit.'

      policy:
        allow_implicit_invocation: false
    '';
  };

  testCodexPolicyInsertedIntoExistingPolicy = {
    expr = fm.disableCodexImplicitInvocation ''
      interface:
        display_name: 'Demo'
      policy:
        other: true
    '';
    expected = ''
      interface:
        display_name: 'Demo'
      policy:
        allow_implicit_invocation: false
        other: true
    '';
  };

  testCodexPolicyReplacesExistingValue = {
    expr = fm.disableCodexImplicitInvocation ''
      policy:
        allow_implicit_invocation: true
        other: true
    '';
    expected = ''
      policy:
        allow_implicit_invocation: false
        other: true
    '';
  };

  testInjectAfterFrontmatter = {
    expr = fm.injectAfterFrontmatter "NOTE\n" withFm;
    expected = "---\nname: demo\n---\nNOTE\nbody line\n";
  };

  # frontmatter が無い場合は先頭に挿入される
  testInjectWithoutFrontmatter = {
    expr = fm.injectAfterFrontmatter "NOTE\n" "plain body\n";
    expected = "NOTE\nplain body\n";
  };
}
