# nix/pins/*.json を upstream の最新リリースに同期する。
# 実行: nix run .#update-pins
# 変更が出たら git diff を確認し、nix run .#build を通してからコミットする。

root=$(git rev-parse --show-toplevel)
cd "$root"

# GitHub API: gh があれば認証付きで叩く (rate limit 回避)。無ければ素の curl。
latest_tag() {
  local repo=$1
  if command -v gh >/dev/null 2>&1; then
    gh api "repos/$repo/releases/latest" --jq .tag_name
  else
    curl -fsSL "https://api.github.com/repos/$repo/releases/latest" | jq -r .tag_name
  fi
}

prefetch() {
  nix store prefetch-file --json "$1" | jq -r .hash
}

# fetchFromGitHub の hash は展開後ツリーの NAR hash なので --unpack で計算する
prefetch_unpack() {
  nix store prefetch-file --json --unpack "$1" | jq -r .hash
}

# release アセット型 pin (hcom / agent-slack) の共通更新処理。
# JSON の assets.<system>.name を読んで各アセットを prefetch し直す。
update_release_pin() {
  local label=$1 repo=$2 pin=$3
  local tag ver cur tmp
  tag=$(latest_tag "$repo")
  ver=${tag#v}
  cur=$(jq -r .version "$pin")
  if [ "$ver" = "$cur" ]; then
    echo "$label: $cur (up to date)"
    return 0
  fi
  echo "$label: $cur -> $ver (prefetching assets...)"
  tmp=$(mktemp)
  jq --arg version "$ver" '.version = $version' "$pin" >"$tmp"
  local system name hash
  while IFS= read -r system; do
    name=$(jq -r --arg s "$system" '.assets[$s].name' "$pin")
    hash=$(prefetch "https://github.com/$repo/releases/download/$tag/$name")
    jq --arg s "$system" --arg h "$hash" '.assets[$s].hash = $h' "$tmp" >"$tmp.next"
    mv "$tmp.next" "$tmp"
  done < <(jq -r '.assets | keys[]' "$pin")
  mv "$tmp" "$pin"
}

echo "== hcom"
hcom_before=$(jq -r .version nix/pins/hcom.json)
update_release_pin "hcom" "aannoo/hcom" "nix/pins/hcom.json"
if [ "$(jq -r .version nix/pins/hcom.json)" != "$hcom_before" ]; then
  # バイナリと skill ドキュメント (flake input hcom-src) の版ズレを防ぐ
  echo "hcom: updating flake input hcom-src to match"
  nix flake update hcom-src
fi

echo "== agent-slack"
update_release_pin "agent-slack" "stablyai/agent-slack" "nix/pins/agent-slack.json"

echo "== git-wt"
pin=nix/pins/git-wt.json
tag=$(latest_tag k1LoW/git-wt)
ver=${tag#v}
cur=$(jq -r .version "$pin")
if [ "$ver" = "$cur" ]; then
  echo "git-wt: $cur (up to date)"
else
  echo "git-wt: $cur -> $ver (prefetching source...)"
  src_hash=$(prefetch_unpack "https://github.com/k1LoW/git-wt/archive/refs/tags/$tag.tar.gz")
  tmp=$(mktemp)
  # vendorHash は go modules のダウンロード結果から決まるため事前計算できない。
  # 空にして lib.fakeHash でビルドし、hash mismatch エラーから実値を取り出す。
  jq --arg v "$ver" --arg s "$src_hash" \
    '.version = $v | .srcHash = $s | .vendorHash = ""' "$pin" >"$tmp"
  mv "$tmp" "$pin"
  echo "git-wt: computing vendorHash (expect one failing build)..."
  build_log=$(nix build .#git-wt --no-link 2>&1 || true)
  vendor_hash=$(echo "$build_log" | grep -Eo 'got: *sha256-[A-Za-z0-9+/=]+' | head -1 | grep -Eo 'sha256-[A-Za-z0-9+/=]+' || true)
  if [ -z "$vendor_hash" ]; then
    echo "git-wt: failed to extract vendorHash from build output:" >&2
    echo "$build_log" | tail -10 >&2
    exit 1
  fi
  tmp=$(mktemp)
  jq --arg h "$vendor_hash" '.vendorHash = $h' "$pin" >"$tmp"
  mv "$tmp" "$pin"
  echo "git-wt: verifying build..."
  nix build .#git-wt --no-link
fi

echo "== codex-schema"
pin=nix/pins/codex-schema.json
new_hash=$(prefetch "$(jq -r .url "$pin")")
if [ "$new_hash" = "$(jq -r .hash "$pin")" ]; then
  echo "codex-schema: up to date"
else
  echo "codex-schema: upstream schema changed; updating hash"
  tmp=$(mktemp)
  jq --arg h "$new_hash" '.hash = $h' "$pin" >"$tmp"
  mv "$tmp" "$pin"
fi

echo
if git diff --quiet -- nix/pins flake.lock; then
  echo "All pins up to date."
else
  echo "Pins updated. Review with 'git diff', verify with 'nix run .#build', then commit."
fi
