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

failed=0
while IFS= read -r entry; do
  rel_src=$(jq -r .src <<<"$entry")
  rel_dst=$(jq -r .dst <<<"$entry")
  mode=$(jq -r .mode <<<"$entry")
  dir_mode=$(jq -r .dirMode <<<"$entry")
  src="$APPLY_SECRETS_ROOT/$rel_src"
  dst="$HOME/$rel_dst"

  # マニフェストの誤記・混入で復号済み secret を $HOME 外へ書くのを防ぐ。
  # realpath による正規化はせず、絶対パスと .. 成分を字面で拒否する
  # (dst の親はまだ存在しないことがあり、正規化は逆に複雑になる)。
  case "$rel_dst" in
  /* | .. | ../* | */.. | */../*)
    echo "apply-secrets: dst '$rel_dst' escapes HOME; skipping" >&2
    failed=$((failed + 1))
    continue
    ;;
  esac

  if [ ! -f "$src" ]; then
    echo "apply-secrets: $rel_src is not in the repo; skipping" >&2
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
    failed=$((failed + 1))
    continue
  fi
  chmod "$mode" "$tmp"
  mv "$tmp" "$dst"
  trap - EXIT
  echo "apply-secrets: wrote $dst"
done < <(jq -c '.[]' "$APPLY_SECRETS_MANIFEST")

if [ "$failed" -gt 0 ]; then
  echo "apply-secrets: $failed file(s) skipped (decryption failed)" >&2
fi
