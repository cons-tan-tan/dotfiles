---
name: design-with-den
description: Guides architecture and review of Den configurations around ownership, scope, and data flow. Use when migrating to Den, restructuring aspects or classes, or choosing among module options, quirks, pipes, and policies.
---

# Design with Den

Treat the resolved configuration graph as the architecture. Treat files and directories as a human-facing projection of that graph.

## Workflow

1. Read the target repository instructions and identify its Den input and revision. Use `nix flake metadata --json . | jq -r '.locks.nodes.den.locked.rev'` by default; inspect `flake.lock` when the input node has another name.
2. Read the core principles and only the task-specific documentation listed below. Use current public docs for concepts; inspect the matching Den revision before relying on API names or behavior.
3. Inspect the existing configuration to reconstruct what it actually resolves. Do not infer intended ownership from directory names.
4. For each concern, record a temporary working model containing:
   - stable entity data;
   - owner aspect and composition aspects;
   - entity kinds and output classes;
   - required context and whether it is reachable;
   - producer and consumer scopes;
   - module option, quirk, pipe, or policy data path;
   - dependencies, policy activation site, and affected subtree.
5. Keep this model in the review response or working notes. Do not add a snapshot inventory of current wiring to the repository.
6. Assign logical ownership before considering physical placement. Co-locate code only when doing so makes ownership and dependencies clearer.
7. For a whole-project review, trace all entities, policies, quirks, custom classes, and public outputs. Sample repetitive direct-option aspects by ownership pattern and state what was sampled.
8. Gather evidence in order: statically trace declarations and activation, inspect existing evaluation or contract tests, then run a narrow non-mutating evaluation when authorized.
9. For a read-only review, stop after reporting evidence, sampling, risks, checks not run, and unverified assumptions. For an implementation, change one coherent vertical slice and run the target repository's prescribed check; use `nix flake check` when no verification guidance exists.

## Core boundaries

- Keep stable infrastructure facts in entities and reusable behavior in aspects.
- Distinguish entity kind, such as host or user, from Nix class, such as nixos or homeManager.
- Organize primarily by feature. Use host, user, environment, and role aspects mainly to compose features.
- Keep class-specific behavior for one concern logically owned by that concern's aspect, even when physical separation is justified.
- Use aspect `includes` for the composition DAG and `provides` for named sub-aspects. Check the pinned Den revision before using version-specific cross-entity provider APIs.
- Treat a custom namespace as an aspect library. Do not classify it as legacy merely because it is outside `den.aspects`.
- Treat batteries as Den-provided aspects or aspect providers that compose with project aspects.
- Distinguish Den context functions from Nix module arguments. Den resolves context before module evaluation.
- Verify that every parametric aspect's required context is reachable from its include scope. Unreachable context can leave behavior inert.
- Verify that each class module is delivered to the intended entity scope and output class.
- Treat a scope as a partition and delivery boundary for emissions, routing state, and quirks, not as a sealed container. Account for inherited context, cascading policies, and ancestor composition.
- Do not derive architecture from an upstream tutorial tree. File placement is secondary to the resolved configuration graph.
- Preserve public flake outputs and other project contracts unless the task explicitly changes them.

## Choose a data path

- Write a Nix module option directly when its ownership and merge semantics already express the desired behavior.
- Use a quirk when producers should emit structured contributions without knowing the consumer, or when data needs aggregation or reuse by multiple consumers.
- Use a pipe when quirk data needs processing, renaming, targeted delivery, or explicit cross-scope movement. Same-scope collection needs no pipe.
- Use a policy for entity relationships, context enrichment, routing, aspect injection, or another explicit resolution effect.
- Choose a policy activation site separately from its registry entry. Confirm the intended subtree, cascading behavior, and authoritative parent exclusions.
- When a policy injects an aspect, preserve aspect composition, parametric dispatch, and deduplication unless raw class-module delivery is intentionally required. Verify the available delivery effects in the pinned reference.

Do not treat quirks as mutable global stores: contributions are scope-local unless a pipe explicitly moves or collects them. Do not add a policy, quirk, or pipe merely to make conventional module configuration look more Den-specific.

For example, let services write a mergeable Nix option directly when that option is the intended shared contract. Use a firewall quirk when services should declare structured port requirements independently of the eventual firewall, documentation, or monitoring consumers.

## Check dependency direction

Allow relative imports for co-located implementation helpers and stable package sources. Question imports that expose another feature's internals, make a feature depend on entity implementation details, or break when unrelated directories move.

Move a helper toward the concern that owns it, inject a stable dependency, or introduce a Den data-flow mechanism only when that change clarifies ownership. Do not replace path coupling with ceremonial indirection.

## Documentation routing

Read only the sections relevant to the task.

- Architecture: <https://den.denful.dev/explanation/core-principles/>
- Entities and schema:
  - <https://den.denful.dev/explanation/entities/>
  - <https://den.denful.dev/reference/schema/>
- Aspects, context, scopes, and classes:
  - <https://den.denful.dev/explanation/aspects/>
  - <https://den.denful.dev/explanation/parametric/>
  - <https://den.denful.dev/explanation/class-modules/>
  - <https://den.denful.dev/explanation/context-pipeline/>
  - <https://den.denful.dev/reference/aspects/>
  - <https://den.denful.dev/guides/custom-classes/>
- Policies:
  - <https://den.denful.dev/explanation/policies/>
  - <https://den.denful.dev/explanation/policy-activation/>
  - <https://den.denful.dev/reference/policies/>
- Quirks, pipes, and cross-scope flow:
  - <https://den.denful.dev/explanation/quirks-and-pipes/>
  - <https://den.denful.dev/guides/quirks/>
  - <https://den.denful.dev/reference/quirks/>
  - <https://den.denful.dev/explanation/fleet/>
- Batteries, namespaces, and entity integration:
  - <https://den.denful.dev/guides/batteries/>
  - <https://den.denful.dev/reference/batteries/>
  - <https://den.denful.dev/guides/namespaces/>
  - <https://den.denful.dev/guides/mutual/>
  - <https://den.denful.dev/guides/home-manager/>
- Migration and versioning:
  - <https://den.denful.dev/explanation/coming-from/>
  - <https://den.denful.dev/guides/migrate/>
  - <https://den.denful.dev/guides/from-flake-to-den/>
  - <https://den.denful.dev/guides/migrate-ctx/>
  - <https://den.denful.dev/releases/>
- Advanced scope internals: <https://den.denful.dev/explanation/scope-partitioning/>

When API behavior may differ from current documentation, read the corresponding document or implementation in `denful/den` at the target revision. Prefer `gh repo read-file`; consult `gh repo read-file --help` for mechanics.

## Review completion

Confirm that every concern has an owner, every required context is reachable, every output class reaches the intended scope, and every policy is activated over the intended subtree. Record quirk and pipe scope flow, dependency-direction exceptions, validation performed, and anything left unverified.
