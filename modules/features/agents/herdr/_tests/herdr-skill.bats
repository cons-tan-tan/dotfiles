#!/usr/bin/env bats

@test "Nix skill preserves upstream instructions and requires explicit Codex invocation" {
  if [[ -z ${HERDR_SKILL_TEST_PACKAGE:-} ]]; then
    skip "HERDR_SKILL_TEST_PACKAGE is only available in the Nix check"
  fi

  cmp "$HERDR_SKILL_TEST_SOURCE/SKILL.md" "$HERDR_SKILL_TEST_PACKAGE/SKILL.md"
  run yq -e '.policy.allow_implicit_invocation == false' \
    "$HERDR_SKILL_TEST_PACKAGE/agents/openai.yaml"

  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
