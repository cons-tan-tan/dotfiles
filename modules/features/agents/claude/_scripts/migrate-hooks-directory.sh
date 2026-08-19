set -euo pipefail

: "${CLAUDE_HOME:?}"
: "${DOTFILES_DIR:?}"

legacy_hooks="$CLAUDE_HOME/hooks"
legacy_target="$DOTFILES_DIR/claude/hooks"

if [[ ! -L $legacy_hooks ]]; then
  exit 0
fi

link_target="$(readlink "$legacy_hooks")"
case "$link_target" in
/*) ;;
*) link_target="$(dirname "$legacy_hooks")/$link_target" ;;
esac

normalized_target="$(realpath -m "$link_target")"
normalized_legacy_target="$(realpath -m "$legacy_target")"
old_generation_hooks=
if [[ -n ${OLD_GEN_PATH:-} ]] &&
  [[ -e "$OLD_GEN_PATH/home-files/.claude/hooks" || -L "$OLD_GEN_PATH/home-files/.claude/hooks" ]]; then
  old_generation_hooks="$(realpath -m "$OLD_GEN_PATH/home-files/.claude/hooks")"
fi

if [[ $normalized_target == "$normalized_legacy_target" ]] ||
  [[ -n $old_generation_hooks && $normalized_target == "$old_generation_hooks" ]]; then
  rm -- "$legacy_hooks"
fi
