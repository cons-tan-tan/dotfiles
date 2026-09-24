---
name: dendritic-design
description: Design and review Dendritic Nix configurations when adding features, changing module boundaries, or restructuring composition and data flow.
---

# Dendritic Design

Make a feature's behavior, consumers, and data flow easy to follow. Adapt these principles to the module infrastructure chosen for the task.

## Model

Dendritic uses a common top-level module evaluation to declare and compose lower-level modules and configurations, such as NixOS, Home Manager, and nix-darwin. Lower-level modules are mergeable option values. flake-parts is one way to host this pattern; a particular directory tree, option namespace, or discovery library is not required.

## Feature boundaries

- Keep the parts of a concern logically together across configuration classes. Split files when that helps a reader follow the feature.
- Give a lower-level module its own name when consumers need to select, reuse, or replace it independently. Fragments that are always selected together can contribute to the same merged module; splitting a file need not create another selection boundary.
- Let machine, user, and environment compositions primarily select features and supply identity. Keep reusable behavior with its feature.
- Keep frequently edited settings visible with the feature they configure. Extract helpers when they clarify responsibility or enable reuse, and apply the repository's discovery exclusions to helpers, package expressions, and test fixtures that are not top-level modules.

## Composition and data flow

- Distinguish discovery of module definitions from their selection into a concrete configuration. Trace the affected imports or equivalent composition mechanism to establish where behavior takes effect.
- Identify which evaluation supplies a value: the top-level configuration, a per-system context, or a particular host or home. The name `config` refers to the current evaluation; it does not make values global or shared between those scopes.
- Use an existing option when its merge semantics express the intended contract. Introduce a typed option when contributors need a shared contract or consumers need derived output. Choose its scope so contributions reach their intended consumers without leaking into unrelated configurations.
- Share values through the appropriate options or lexical scope. Use explicit arguments when an integration requires them; avoid forwarding entire configuration contexts merely to connect feature files.
- For changes to shared imports or merged module fragments, check the selected library version's identity, deduplication, and ordering semantics. Preserve distinct contributions as well as protection against repeated effects.

Judge a composition change by its evaluated behavior: selected features take effect, unrelated configurations stay unaffected, and aggregation preserves the intended contributions. Use the affected configurations and the repository's verification conventions to choose evidence proportional to the change.

## References

Consult the relevant reference when a design choice or API behavior needs clarification:

- [Dendritic pattern](https://github.com/mightyiam/dendritic): the top-level model, module merging, and tradeoffs around module granularity.
- [flake-parts modules](https://flake.parts/options/flake-parts-modules): module registries and configuration classes when using flake-parts.
- [flake-parts module arguments](https://flake.parts/module-arguments): evaluation scopes and available arguments when using flake-parts.

For behavior that depends on a library revision, consult that revision's documentation or implementation. Apply the pattern where it improves the requested design; retain justified exceptions.
