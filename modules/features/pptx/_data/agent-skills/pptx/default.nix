{ original, ... }:
''

  > **Local override**: run shell commands in this skill through the
  > declarative PPTX tool environment:
  >
  > `nix run dotfiles#pptx -- <command>`
  >
  > Examples:
  >
  > `nix run dotfiles#pptx -- python -m markitdown input.pptx`
  > `nix run dotfiles#pptx -- pdftoppm -jpeg -r 150 output.pdf slide`
  >
  > Helper scripts such as `python scripts/thumbnail.py ...` are also
  > resolved from the installed `/pptx` skill when the current project
  > does not have its own `scripts/` directory.
''
+ original
