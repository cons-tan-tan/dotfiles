# nix/pins/*.json を upstream の最新状態に同期する。
# 実行: nix run .#update-pins
# 変更が出たら git diff を確認し、nix run .#build を通してからコミットする。

# 失敗時に一時ファイルを残さない。各ブロックは TMPFILES に追記してから使う。
TMPFILES=()
TMPDIRS=()
managed_files=()
managed_pathspecs=(':(glob)nix/pins/*.json' flake.lock nix/packages/difit/package-lock.json)
managed_backup_dir=""
restore_managed_files=false

restore_managed_files_now() {
  local file backup
  if ! $restore_managed_files || [ -z "$managed_backup_dir" ]; then
    return 0
  fi
  echo "update-pins: failed; restoring managed files from backup" >&2
  for file in "${managed_files[@]}"; do
    backup="$managed_backup_dir/$file"
    if [ -f "$backup" ]; then
      case $file in
      */*) mkdir -p "${file%/*}" ;;
      esac
      cp "$backup" "$file"
    else
      rm -f "$file"
    fi
  done
  restore_managed_files=false
}

cleanup() {
  local status=$?
  set +e
  if [ "$status" -ne 0 ]; then
    restore_managed_files_now
  fi
  rm -f "${TMPFILES[@]}"
  rm -rf "${TMPDIRS[@]}"
  exit "$status"
}
trap cleanup EXIT

root=$(git rev-parse --show-toplevel)
cd "$root"

check_managed_files_clean() {
  if ! git diff --quiet -- "${managed_pathspecs[@]}"; then
    echo "update-pins: managed files already have unstaged changes; refusing to overwrite them" >&2
    return 1
  fi
  if ! git diff --cached --quiet -- "${managed_pathspecs[@]}"; then
    echo "update-pins: managed files already have staged changes; refusing to overwrite them" >&2
    return 1
  fi
}

load_managed_files() {
  local file
  managed_files=()
  while IFS= read -r -d '' file; do
    managed_files+=("$file")
  done < <(git ls-files -z -- "${managed_pathspecs[@]}")
  # 新規追加でまだ git add されていない pin もトランザクションで守る
  while IFS= read -r -d '' file; do
    managed_files+=("$file")
  done < <(git ls-files -z --others --exclude-standard -- "${managed_pathspecs[@]}")
}

backup_managed_files() {
  local file backup
  load_managed_files
  managed_backup_dir=$(mktemp -d)
  TMPDIRS+=("$managed_backup_dir")
  for file in "${managed_files[@]}"; do
    backup="$managed_backup_dir/$file"
    mkdir -p "${backup%/*}"
    cp "$file" "$backup"
  done
  restore_managed_files=true
}

check_managed_files_clean
backup_managed_files

# GitHub API: gh があれば認証付きで叩く (rate limit 回避)。無ければ素の curl。
latest_tag() {
  local repo=$1 tag
  if command -v gh >/dev/null 2>&1; then
    tag=$(gh api "repos/$repo/releases/latest" --jq .tag_name)
  else
    tag=$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" | jq -r .tag_name)
  fi
  # API がリリースを返さない場合に "null" のまま download URL を組み立てて
  # 意味不明なエラーで落ちるのを防ぎ、根本原因をここで報告する
  if [[ -z $tag || $tag == "null" ]]; then
    echo "latest_tag: $repo の latest release tag を取得できなかった" >&2
    return 1
  fi
  printf '%s\n' "$tag"
}

latest_npm_version() {
  local package=$1 version
  version=$(curl -fsSL "https://registry.npmjs.org/$package/latest" | jq -r .version)
  if [[ -z $version || $version == "null" ]]; then
    echo "latest_npm_version: $package の latest version を取得できなかった" >&2
    return 1
  fi
  printf '%s\n' "$version"
}

prefetch() {
  nix store prefetch-file --json "$1" | jq -r .hash
}

# fetchFromGitHub の hash は展開後ツリーの NAR hash なので --unpack で計算する
prefetch_unpack() {
  nix store prefetch-file --json --unpack "$1" | jq -r .hash
}

update_url_pin() {
  local label=$1 pin=$2
  local url cur hash tmp
  url=$(jq -r .url "$pin")
  cur=$(jq -r .hash "$pin")
  echo "$label: checking schema hash..."
  hash=$(prefetch "$url")
  if [ "$hash" = "$cur" ]; then
    echo "$label: up to date"
    return 0
  fi
  tmp=$(mktemp)
  TMPFILES+=("$tmp")
  jq --arg h "$hash" '.hash = $h' "$pin" >"$tmp"
  mv "$tmp" "$pin"
  echo "$label: hash updated"
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
  TMPFILES+=("$tmp")
  jq --arg version "$ver" '.version = $version' "$pin" >"$tmp"
  local system name hash next
  while IFS= read -r system; do
    name=$(jq -r --arg s "$system" '.assets[$s].name' "$pin")
    hash=$(prefetch "https://github.com/$repo/releases/download/$tag/$name")
    next=$(mktemp)
    TMPFILES+=("$next")
    jq --arg s "$system" --arg h "$hash" '.assets[$s].hash = $h' "$tmp" >"$next"
    mv "$next" "$tmp"
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
agent_slack_before=$(jq -r .version nix/pins/agent-slack.json)
update_release_pin "agent-slack" "stablyai/agent-slack" "nix/pins/agent-slack.json"
if [ "$(jq -r .version nix/pins/agent-slack.json)" != "$agent_slack_before" ]; then
  # バイナリと skill ドキュメント (flake input agent-slack-skill) の版ズレを防ぐ
  echo "agent-slack: updating flake input agent-slack-skill to match"
  nix flake update agent-slack-skill
fi

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
  TMPFILES+=("$tmp")
  # vendorHash は go modules のダウンロード結果から決まるため事前計算できない。
  # 空にして lib.fakeHash でビルドし、hash mismatch エラーから実値を取り出す。
  jq --arg v "$ver" --arg s "$src_hash" \
    '.version = $v | .srcHash = $s | .vendorHash = ""' "$pin" >"$tmp"
  mv "$tmp" "$pin"
  echo "git-wt: computing vendorHash (expect one failing build)..."
  build_log=$(nix build .#git-wt --no-link 2>&1 || true)
  vendor_hash=$(echo "$build_log" | grep -Eo 'got: *sha256-[A-Za-z0-9+/=_-]+' | head -1 | grep -Eo 'sha256-[A-Za-z0-9+/=_-]+' || true)
  if [ -z "$vendor_hash" ]; then
    echo "git-wt: failed to extract vendorHash from build output:" >&2
    echo "$build_log" | tail -10 >&2
    exit 1
  fi
  tmp=$(mktemp)
  TMPFILES+=("$tmp")
  jq --arg h "$vendor_hash" '.vendorHash = $h' "$pin" >"$tmp"
  mv "$tmp" "$pin"
  echo "git-wt: verifying build..."
  if ! nix build .#git-wt --no-link; then
    echo "git-wt: verification build failed" >&2
    exit 1
  fi
fi

echo "== shellfirm"
pin=nix/pins/shellfirm.json
tag=$(latest_tag kaplanelad/shellfirm)
ver=${tag#v}
cur=$(jq -r .version "$pin")
if [ "$ver" = "$cur" ]; then
  echo "shellfirm: $cur (up to date)"
else
  echo "shellfirm: $cur -> $ver (prefetching source...)"
  src_hash=$(prefetch_unpack "https://github.com/kaplanelad/shellfirm/archive/refs/tags/$tag.tar.gz")
  tmp=$(mktemp)
  TMPFILES+=("$tmp")
  # cargoHash は Cargo.lock ベースの vendor tree から決まるため、fake hash
  # で一度ビルドして hash mismatch から実値を取り出す。
  jq --arg v "$ver" --arg s "$src_hash" \
    '.version = $v | .srcHash = $s | .cargoHash = ""' "$pin" >"$tmp"
  mv "$tmp" "$pin"
  echo "shellfirm: computing cargoHash (expect one failing build)..."
  build_log=$(nix build .#shellfirm --no-link 2>&1 || true)
  cargo_hash=$(echo "$build_log" | grep -Eo 'got: *sha256-[A-Za-z0-9+/=_-]+' | head -1 | grep -Eo 'sha256-[A-Za-z0-9+/=_-]+' || true)
  if [ -z "$cargo_hash" ]; then
    echo "shellfirm: failed to extract cargoHash from build output:" >&2
    echo "$build_log" | tail -10 >&2
    exit 1
  fi
  tmp=$(mktemp)
  TMPFILES+=("$tmp")
  jq --arg h "$cargo_hash" '.cargoHash = $h' "$pin" >"$tmp"
  mv "$tmp" "$pin"
  echo "shellfirm: verifying build..."
  if ! nix build .#shellfirm --no-link; then
    echo "shellfirm: verification build failed" >&2
    exit 1
  fi
fi

echo "== herdr"
herdr_pin=nix/pins/herdr.json
herdr_before=$(jq -r .version "$herdr_pin")
update_release_pin "herdr" "ogulcancelik/herdr" "$herdr_pin"
herdr_after=$(jq -r .version "$herdr_pin")
if [ "$herdr_after" != "$herdr_before" ]; then
  echo "herdr: updating srcHash"
  src_hash=$(prefetch_unpack "https://github.com/ogulcancelik/herdr/archive/refs/tags/v$herdr_after.tar.gz")
  tmp=$(mktemp)
  TMPFILES+=("$tmp")
  jq --arg h "$src_hash" '.srcHash = $h' "$herdr_pin" >"$tmp"
  mv "$tmp" "$herdr_pin"
fi

echo "== difit"
difit_pin=nix/pins/difit.json
difit_lock=nix/packages/difit/package-lock.json
difit_cur=$(jq -r .version "$difit_pin")
difit_ver=$(latest_npm_version difit)
if [ "$difit_ver" = "$difit_cur" ]; then
  echo "difit: $difit_cur (up to date)"
else
  echo "difit: $difit_cur -> $difit_ver (prefetching source...)"
  difit_url="https://registry.npmjs.org/difit/-/difit-$difit_ver.tgz"
  difit_src_hash=$(prefetch "$difit_url")

  difit_tmpdir=$(mktemp -d)
  TMPDIRS+=("$difit_tmpdir")
  curl -fsSL "$difit_url" | tar -xz -C "$difit_tmpdir"
  if [ ! -f "$difit_tmpdir/package/package.json" ]; then
    echo "difit: npm tarball did not contain package/package.json" >&2
    exit 1
  fi
  (
    cd "$difit_tmpdir/package"
    npm install --package-lock-only --ignore-scripts --no-audit --no-fund
  )
  cp "$difit_tmpdir/package/package-lock.json" "$difit_lock"

  tmp=$(mktemp)
  TMPFILES+=("$tmp")
  # npmDepsHash は npm 依存のダウンロード結果から決まるため事前計算できない。
  # 空にして lib.fakeHash でビルドし、hash mismatch エラーから実値を取り出す。
  jq --arg v "$difit_ver" --arg s "$difit_src_hash" \
    '.version = $v | .srcHash = $s | .npmDepsHash = ""' "$difit_pin" >"$tmp"
  mv "$tmp" "$difit_pin"
  echo "difit: computing npmDepsHash (expect one failing build)..."
  build_log=$(nix build .#difit --no-link 2>&1 || true)
  npm_deps_hash=$(echo "$build_log" | grep -Eo 'got: *sha256-[A-Za-z0-9+/=_-]+' | head -1 | grep -Eo 'sha256-[A-Za-z0-9+/=_-]+' || true)
  if [ -z "$npm_deps_hash" ]; then
    echo "difit: failed to extract npmDepsHash from build output:" >&2
    echo "$build_log" | tail -10 >&2
    exit 1
  fi
  tmp=$(mktemp)
  TMPFILES+=("$tmp")
  jq --arg h "$npm_deps_hash" '.npmDepsHash = $h' "$difit_pin" >"$tmp"
  mv "$tmp" "$difit_pin"
  echo "difit: verifying build..."
  if ! nix build .#difit --no-link; then
    echo "difit: verification build failed" >&2
    exit 1
  fi
  echo "difit: updating flake input difit-src to match"
  nix flake update difit-src
fi

echo "== claude-code-settings-schema"
update_url_pin "claude-code-settings-schema" "nix/pins/claude-code-settings-schema.json"

echo
if git diff --quiet -- "${managed_pathspecs[@]}"; then
  echo "All pins up to date."
else
  echo "Pins updated. Review with 'git diff', verify with 'nix run .#build', then commit."
fi
restore_managed_files=false
