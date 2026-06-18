# Repository Agent Guide

This repo is a Nix flake for declarative dotfiles across macOS, Linux, WSL, and WSL-managed Windows companion config.

## Verification

Run the narrowest relevant checks. Before committing Nix or module changes, run at least:

- `nix flake check --no-build --all-systems`
- `nix run .#fmt -- --ci`

Other gates:

- `nix run .#fmt` formats the tree.
- `nix run .#build` builds without switching the host.
- `reuse lint` checks licensing in the dev shell.
- `bats tests/` checks shell scripts and hooks in the dev shell.

## Rules

- Keep repository agent instructions in `AGENTS.md`; `CLAUDE.md` is only a compatibility symlink.
- Avoid IFD during eval. Do not read derivation outputs with `builtins.readFile`; eval-time reads must be repo paths or flake inputs.
- The clone path is intentional: `nix/lib/mk-home-modules.nix` and out-of-store links expect `~/ghq/github.com/cons-tan-tan/dotfiles`.
- Respect REUSE. The default license is CC0-1.0 from `REUSE.toml`; add a sidecar `.license` only for files with different provenance.
- New shell tools should use `writeShellApplication`. Put nontrivial logic in `.sh` files wrapped with `builtins.readFile`, and cover behavior with Bats.
- Avoid `home.file.*.force = true`; prefer visible collisions or the configured backup extension over silently replacing user files.
- Never commit plaintext secrets. `secrets/` is sops/GPG-managed; see `secrets/README.md`.

## Notes

- Use `README.md` for setup and top-level layout instead of duplicating it here.
- `nix/lib/settings/*` often feeds both the current host and Windows companion output; check both consumers before changing shared settings.
- Commit messages follow Conventional Commits. Comments should explain why, not restate what the code already says.
