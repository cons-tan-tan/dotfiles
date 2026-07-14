# Repository Agent Guide

This repo is a Nix flake for declarative dotfiles across macOS, Linux, WSL, and WSL-managed Windows companion config.

## Verification

Run the narrowest relevant checks. Before committing Nix or module changes, run at least:

- `nix flake check --no-build --all-systems`
- `nix run .#fmt -- --ci`

Other relevant gates:

- `nix run .#build` when evaluation is not enough and the changed output should build.
- `reuse lint` for licensing or provenance changes.
- `bats tests/` for shell scripts and wrappers.
- `nix run .#markdownlint` / `nix run .#textlint` for Markdown or prose changes.

## Rules

- Keep repository agent instructions in `AGENTS.md`; `CLAUDE.md` is only a compatibility symlink.
- Avoid IFD during eval. Do not read derivation outputs with `builtins.readFile`; eval-time reads must be repo paths or flake inputs.
- Respect REUSE. The default license is CC0-1.0 from `REUSE.toml`; add a sidecar `.license` only for files with different provenance.
- New shell tools should use `writeShellApplication`. Put nontrivial logic in `.sh` files wrapped with `builtins.readFile`, and cover behavior with Bats.
- Treat root flake `apps` and `packages` as permanent public CLI interfaces. Never add an entry solely to build, run, debug, or calculate hashes; build an overlaid package through an existing configuration's `pkgs`, or use `nix build --impure --expr` with `mk-pkgs.nix` and `callPackage` before adding the overlay.
- Avoid `home.file.*.force = true`; prefer visible collisions or the configured backup extension over silently replacing user files.
- Never commit plaintext secrets. `secrets/` is sops/GPG-managed; see `secrets/README.md`.

## Notes

- Use `README.md` for setup, top-level layout, and the canonical clone path instead of duplicating it here.
- When editing shared settings, search import/call sites instead of assuming a single consumer.
- Keep implementation-specific caveats next to the relevant code.
- Keep `AGENTS.md` as a stable index of repository-wide rules and entry points.
- Commit messages follow Conventional Commits. Comments should explain why, not restate what the code already says.
