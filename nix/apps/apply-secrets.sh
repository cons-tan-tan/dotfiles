# sops secrets をマニフェストに従って $HOME へ復号配置する本体。
# nix/lib/mk-apps.nix の applySecretsScript が以下を export して埋め込む:
#   APPLY_SECRETS_ROOT     — secrets/ を含むソースルート (flake の self)
#   APPLY_SECRETS_MANIFEST — 適用エントリの JSON 配列ファイル
# テスト (tests/apply-secrets.bats) はこの 2 変数を fixture に差し替えて
# 本体を直接実行する。
: "${APPLY_SECRETS_ROOT:?APPLY_SECRETS_ROOT must be set}"
: "${APPLY_SECRETS_MANIFEST:?APPLY_SECRETS_MANIFEST must be set}"

# --dry-run: 書き込み先の一覧だけ出して終了する (実環境を触らない検証用)
dry_run=false
if [ "${1:-}" = "--dry-run" ]; then
  dry_run=true
fi

decrypt_failures=0
manifest_errors=0

manifest_string_field() {
  local field=$1
  jq -er --arg field "$field" '.[$field] | select(type == "string" and length > 0)' <<<"$entry"
}

while IFS= read -r entry; do
  if ! rel_src=$(manifest_string_field src); then
    echo "apply-secrets: manifest error: src must be a non-empty string; skipping" >&2
    manifest_errors=$((manifest_errors + 1))
    continue
  fi
  if ! rel_dst=$(manifest_string_field dst); then
    echo "apply-secrets: manifest error: dst must be a non-empty string; skipping" >&2
    manifest_errors=$((manifest_errors + 1))
    continue
  fi
  if ! mode=$(manifest_string_field mode); then
    echo "apply-secrets: manifest error: mode must be a non-empty string; skipping" >&2
    manifest_errors=$((manifest_errors + 1))
    continue
  fi
  if ! dir_mode=$(manifest_string_field dirMode); then
    echo "apply-secrets: manifest error: dirMode must be a non-empty string; skipping" >&2
    manifest_errors=$((manifest_errors + 1))
    continue
  fi
  src="$APPLY_SECRETS_ROOT/$rel_src"
  dst="$HOME/$rel_dst"

  # マニフェストの誤記・混入で復号済み secret を $HOME 外へ書くのを防ぐ。
  # realpath による正規化はせず、絶対パスと .. 成分を字面で拒否する
  # (dst の親はまだ存在しないことがあり、正規化は逆に複雑になる)。
  case "$rel_dst" in
  /* | .. | ../* | */.. | */../*)
    echo "apply-secrets: manifest error: dst '$rel_dst' escapes HOME; skipping" >&2
    manifest_errors=$((manifest_errors + 1))
    continue
    ;;
  esac

  if [ ! -f "$src" ]; then
    echo "apply-secrets: manifest error: $rel_src is not in the repo; skipping" >&2
    manifest_errors=$((manifest_errors + 1))
    continue
  fi

  if $dry_run; then
    echo "apply-secrets: would write $dst (mode $mode)"
    continue
  fi

  mkdir -p "$(dirname "$dst")"
  chmod "$dir_mode" "$(dirname "$dst")"

  tmp=$(mktemp "$dst.XXXXXX")
  trap 'rm -f "$tmp"' EXIT
  if ! sops --decrypt "$src" >"$tmp"; then
    # GPG 鍵未導入でも switch を阻害しない方針 (案 B) はファイル単位で維持
    echo "apply-secrets: decryption of $rel_src failed (GPG key not imported?); skipping" >&2
    rm -f "$tmp"
    trap - EXIT
    decrypt_failures=$((decrypt_failures + 1))
    continue
  fi
  chmod "$mode" "$tmp"
  mv "$tmp" "$dst"
  trap - EXIT
  echo "apply-secrets: wrote $dst"
done < <(jq -c '.[]' "$APPLY_SECRETS_MANIFEST")

if [ "$decrypt_failures" -gt 0 ]; then
  echo "apply-secrets: $decrypt_failures file(s) skipped because decryption failed" >&2
fi

if [ "$manifest_errors" -gt 0 ]; then
  echo "apply-secrets: $manifest_errors manifest error(s); fix the manifest" >&2
  exit 1
fi
