# Repository Agent Guide

## Entry points

- [`README.md`](README.md): setup, supported hosts, and the canonical clone path.
- [`docs/testing.md`](docs/testing.md): choosing a test layer and assertion style.
- [`secrets/README.md`](secrets/README.md): encrypted secret operations.
- `AGENTS.md` is the source of repository agent instructions; `CLAUDE.md` is a compatibility symlink.

## Verification

Run the narrowest relevant checks while iterating.

- `nix flake check` is the complete reproducible current-system gate and includes the treefmt check.
- `nix flake check --no-build --all-systems` evaluates every system but does not execute checks.
- Build an individual gate with `nix build --no-link .#checks.<system>.<name>` when the full gate is unnecessary.
- The Git flake ignores untracked files. Stage new files before the standard check, or use `nix flake check path:.` while iterating.

Checks and development aids outside the flake gate:

- `bats --print-output-on-failure bats/` is a source-only development aid; Nix package cases skip without their fixtures.
- `nix run .#markdownlint -- <files...>` checks Markdown structure.
- `nix run .#textlint -- tech-jp <files...>` checks Japanese technical prose.

## Repository constraints

- Do not mirror implementation inventories or current wiring in prose.
- Keep non-obvious why/why-not beside the relevant code. Reserve documentation for user operations or cross-cutting decisions that cannot be localized.
- Avoid IFD during eval. Do not read derivation outputs with `builtins.readFile`; eval-time reads must be repo paths or flake inputs.
- Respect REUSE. The default license is CC0-1.0 from `REUSE.toml`; add a sidecar `.license` only for files with different provenance.
- New shell tools should use `writeShellApplication`. Put nontrivial logic in `.sh` files wrapped with `builtins.readFile`, and cover behavior with Bats.
- Treat root flake `apps` and `packages` as permanent public interfaces; do not add one for a one-off build, debug session, or hash calculation.
- Build an overlaid package through an existing configuration's `pkgs`. For one-off evaluation, use `nix build --impure --expr` with `mk-pkgs.nix` and `callPackage` instead of widening the public flake interface.
- Avoid `home.file.*.force = true`; prefer visible collisions or the configured backup extension over silently replacing user files.
