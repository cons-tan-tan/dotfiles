---
name: missing-tools
description: Resolves missing CLI tools. Use when a command is unavailable, a shell reports command not found, or a tool must be run without installing it globally.
---

# Missing Tools

Use this workflow when a command is unavailable in the current shell.

## Priority Order

1. Try the current project's direnv environment:

   ```sh
   direnv exec . <command>
   ```

2. Use [comma](https://github.com/nix-community/comma) for tools from nixpkgs:

   ```sh
   , <command>
   ```

   When more than one package provides the command and no package choice is cached, comma opens an interactive picker. The picker cannot open a TTY in a non-interactive agent shell. If this happens, inspect the candidates:

   ```sh
   , --print-packages <command>
   ```

   Select the appropriate package attribute, then continue with `nix run` or `nix shell`.

3. Use `nix run` when a specific nixpkgs package is needed:

   ```sh
   nix run nixpkgs#<package> -- <args>
   ```

4. Use `nix shell` as the last resort:

   ```sh
   nix shell nixpkgs#<package> --command <command>
   ```

## Notes

- Never use imperative global installers merely to resolve a missing command. Do not use `npm install -g`, `pnpm add -g`, `uv tool install`, `brew install`, `nix-env -i`, `nix profile add`, `comma --install`, or similar commands.
- If a tool appears appropriate for persistent global use, suggest adding it to the user's declarative Nix configuration. Do not modify that configuration as part of this fallback workflow.
- Do not add a project-local dependency solely to make a missing command available. Add it only when the task itself requires changing the project's declared dependencies or development environment.
- Prefer `direnv exec .` first because project-local dev shells often already provide the right tool version and environment variables.
