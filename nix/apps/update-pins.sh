# nix/pins/*.json を upstream の最新状態に同期する。
# 実行: nix run .#update-pins
# 変更が出たら git diff を確認し、nix run .#build を通してからコミットする。

# 失敗時に一時ファイルを残さない。各ブロックは TMPFILES に追記してから使う。
TMPFILES=()
TMPDIRS=()
managed_files=()
managed_pathspecs=(':(glob)nix/pins/*.json' flake.nix flake.lock nix/packages/difit/package-lock.json)
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

# 内部 package のビルドだけを目的に root flake output を公開しない。
# UPDATE_PINS_PACKAGE は Nix の属性選択にだけ使い、shell 展開を式へ埋め込まない。
build_local_package() {
  local package=$1
  # `${...}` は Nix の動的属性選択であり、shell には展開させない。
  # shellcheck disable=SC2016
  UPDATE_PINS_PACKAGE="$package" nix build --impure --expr '
    let
      flake = builtins.getFlake (toString ./.);
      pkgs = import ./nix/lib/mk-pkgs.nix {
        inputs = flake.inputs;
      } builtins.currentSystem;
    in
    pkgs.${builtins.getEnv "UPDATE_PINS_PACKAGE"}
  ' --no-link
}

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

latest_codex_app_json() {
  local appcast=$1 xml
  xml=$(mktemp)
  TMPFILES+=("$xml")
  curl -fsSL "$appcast" >"$xml"
  python3 - "$xml" <<'PY'
import json
import sys
import xml.etree.ElementTree as ET

ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
root = ET.parse(sys.argv[1]).getroot()

for item in root.findall("./channel/item"):
    version = item.findtext("sparkle:shortVersionString", namespaces=ns) or item.findtext("title")
    hardware = item.findtext("sparkle:hardwareRequirements", namespaces=ns) or ""
    enclosure = item.find("enclosure")
    url = enclosure.get("url") if enclosure is not None else ""
    if version and url and "darwin-arm64" in url and (not hardware or "arm64" in hardware):
        print(json.dumps({"version": version, "url": url}))
        break
else:
    raise SystemExit("codex-app: appcast did not contain a darwin arm64 enclosure")
PY
}

inspect_codex_app_zip_json() {
  local zip_path=$1
  python3 - "$zip_path" <<'PY'
import json
import plistlib
import sys
import zipfile

with zipfile.ZipFile(sys.argv[1]) as archive:
    plist_name = None
    for name in archive.namelist():
        parts = name.split("/")
        if len(parts) == 3 and parts[0].endswith(".app") and parts[1:] == ["Contents", "Info.plist"]:
            plist_name = name
            break
    if plist_name is None:
        raise SystemExit("codex-app: zip did not contain a top-level .app/Contents/Info.plist")
    with archive.open(plist_name) as plist_file:
        plist = plistlib.load(plist_file)

print(
    json.dumps(
        {
            "appName": plist_name.split("/", 1)[0],
            "bundleIdentifier": plist.get("CFBundleIdentifier", ""),
            "displayName": plist.get("CFBundleDisplayName") or plist.get("CFBundleName", ""),
            "version": plist.get("CFBundleShortVersionString", ""),
        }
    )
)
PY
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

validate_release_version() {
  local label=$1 version=$2
  if [[ ! $version =~ ^[0-9]+(\.[0-9]+)+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$ ]]; then
    echo "$label: unsupported release version '$version'" >&2
    return 1
  fi
}

current_paired_version() {
  local repo=$1
  python3 - flake.nix "$repo" <<'PY'
import re
import sys

path, repo = sys.argv[1:]
with open(path, encoding="utf-8") as source:
    text = source.read()
matches = re.findall(rf'url = "github:{re.escape(repo)}/v([^"]+)";', text)
if len(matches) != 1:
    raise SystemExit(
        f"update-pins: expected one tagged flake input URL for {repo}, found {len(matches)}"
    )
print(matches[0])
PY
}

update_paired_flake_input() {
  local input=$1 repo=$2 version=$3 tmp
  validate_release_version "$input" "$version"
  tmp=$(mktemp)
  TMPFILES+=("$tmp")
  python3 - flake.nix "$repo" "$version" >"$tmp" <<'PY'
import re
import sys

path, repo, version = sys.argv[1:]
with open(path, encoding="utf-8") as source:
    text = source.read()
pattern = rf'url = "github:{re.escape(repo)}/v[^"]+";'
replacement = f'url = "github:{repo}/v{version}";'
updated, count = re.subn(pattern, replacement, text)
if count != 1:
    raise SystemExit(
        f"update-pins: expected one tagged flake input URL for {repo}, found {count}"
    )
sys.stdout.write(updated)
PY
  mv "$tmp" flake.nix
  echo "$input: updating flake input to v$version"
  nix flake update "$input"
}

update_paired_release_pin() {
  local label=$1 repo=$2 pin=$3 input=$4
  local tag version current tmp system name hash next
  tag=$(latest_tag "$repo")
  if [[ $tag != v* ]]; then
    echo "$label: unsupported release tag '$tag'" >&2
    return 1
  fi
  version=${tag#v}
  validate_release_version "$label" "$version"
  current=$(current_paired_version "$repo")
  if [ "$version" = "$current" ]; then
    echo "$label: $current (up to date)"
    return 0
  fi

  echo "$label: $current -> $version (prefetching assets...)"
  tmp=$(mktemp)
  TMPFILES+=("$tmp")
  cp "$pin" "$tmp"
  while IFS= read -r system; do
    name=$(jq -r --arg system "$system" '.assets[$system].name' "$pin")
    hash=$(prefetch "https://github.com/$repo/releases/download/$tag/$name")
    next=$(mktemp)
    TMPFILES+=("$next")
    jq --arg system "$system" --arg hash "$hash" '.assets[$system].hash = $hash' "$tmp" >"$next"
    mv "$next" "$tmp"
  done < <(jq -r '.assets | keys[]' "$pin")
  mv "$tmp" "$pin"
  update_paired_flake_input "$input" "$repo" "$version"
}

update_watchexec_pin() {
  local pin=nix/pins/watchexec.json
  local tag version current tmp system target name hash next
  tag=$(latest_tag watchexec/watchexec)
  version=${tag#v}
  current=$(jq -r .version "$pin")
  if [ "$version" = "$current" ]; then
    echo "watchexec: $current (up to date)"
    return 0
  fi

  echo "watchexec: $current -> $version (prefetching assets...)"
  tmp=$(mktemp)
  TMPFILES+=("$tmp")
  jq --arg version "$version" '.version = $version' "$pin" >"$tmp"
  while IFS= read -r system; do
    target=$(jq -r --arg system "$system" '.assets[$system].target' "$pin")
    name="watchexec-$version-$target.tar.xz"
    hash=$(prefetch "https://github.com/watchexec/watchexec/releases/download/$tag/$name")
    next=$(mktemp)
    TMPFILES+=("$next")
    jq --arg system "$system" --arg hash "$hash" '.assets[$system].hash = $hash' "$tmp" >"$next"
    mv "$next" "$tmp"
  done < <(jq -r '.assets | keys[]' "$pin")
  mv "$tmp" "$pin"
}

update_codex_app_pin() {
  local pin=nix/pins/codex-app.json
  local appcast latest latest_version latest_url cur_version cur_url expected_app_name expected_bundle_identifier expected_display_name
  local prefetch_json hash store_path zip_info app_name bundle_identifier display_name bundle_version tmp

  appcast=$(jq -r .appcast "$pin")
  latest=$(latest_codex_app_json "$appcast")
  latest_version=$(jq -r .version <<<"$latest")
  latest_url=$(jq -r .url <<<"$latest")
  cur_version=$(jq -r .version "$pin")
  cur_url=$(jq -r .url "$pin")
  expected_app_name=$(jq -r .appName "$pin")
  expected_bundle_identifier=$(jq -r .bundleIdentifier "$pin")
  expected_display_name=$(jq -r .displayName "$pin")

  if [ "$latest_version" = "$cur_version" ] && [ "$latest_url" = "$cur_url" ]; then
    echo "codex-app: $cur_version (up to date)"
    return 0
  fi

  echo "codex-app: $cur_version -> $latest_version (prefetching app...)"
  prefetch_json=$(nix store prefetch-file --json "$latest_url")
  hash=$(jq -r .hash <<<"$prefetch_json")
  store_path=$(jq -r .storePath <<<"$prefetch_json")
  zip_info=$(inspect_codex_app_zip_json "$store_path")
  app_name=$(jq -r .appName <<<"$zip_info")
  bundle_identifier=$(jq -r .bundleIdentifier <<<"$zip_info")
  display_name=$(jq -r .displayName <<<"$zip_info")
  bundle_version=$(jq -r .version <<<"$zip_info")

  if [ "$bundle_version" != "$latest_version" ]; then
    echo "codex-app: appcast version $latest_version did not match bundle version $bundle_version" >&2
    exit 1
  fi
  if [ "$app_name" != "$expected_app_name" ]; then
    echo "codex-app: expected app name $expected_app_name but downloaded $app_name" >&2
    exit 1
  fi
  if [ "$bundle_identifier" != "$expected_bundle_identifier" ]; then
    echo "codex-app: expected bundle identifier $expected_bundle_identifier but downloaded $bundle_identifier" >&2
    exit 1
  fi
  if [ "$display_name" != "$expected_display_name" ]; then
    echo "codex-app: expected display name $expected_display_name but downloaded $display_name" >&2
    exit 1
  fi

  tmp=$(mktemp)
  TMPFILES+=("$tmp")
  jq \
    --arg version "$latest_version" \
    --arg url "$latest_url" \
    --arg hash "$hash" \
    '
      .version = $version
      | .url = $url
      | .hash = $hash
    ' "$pin" >"$tmp"
  mv "$tmp" "$pin"
}

if [ "${UPDATE_PINS_ONLY:-}" = "codex-app" ]; then
  echo "== codex-app"
  update_codex_app_pin
  echo
  if git diff --quiet -- "${managed_pathspecs[@]}"; then
    echo "All pins up to date."
  else
    echo "Pins updated. Review with 'git diff', verify with 'nix run .#build', then commit."
  fi
  restore_managed_files=false
  exit 0
fi

echo "== hcom"
update_paired_release_pin hcom aannoo/hcom nix/pins/hcom.json hcom-src

echo "== agent-slack"
update_paired_release_pin agent-slack stablyai/agent-slack nix/pins/agent-slack.json agent-slack-skill

echo "== agent-browser"
update_paired_release_pin agent-browser vercel-labs/agent-browser nix/pins/agent-browser.json agent-browser-skill

echo "== watchexec"
update_watchexec_pin

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
  build_log=$(build_local_package shellfirm 2>&1 || true)
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
  if ! build_local_package shellfirm; then
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
difit_cur=$(current_paired_version yoshiko-pg/difit)
difit_ver=$(latest_npm_version difit)
validate_release_version difit "$difit_ver"
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
  jq --arg s "$difit_src_hash" \
    '.srcHash = $s | .npmDepsHash = ""' "$difit_pin" >"$tmp"
  mv "$tmp" "$difit_pin"
  update_paired_flake_input difit-src yoshiko-pg/difit "$difit_ver"
  echo "difit: computing npmDepsHash (expect one failing build)..."
  build_log=$(build_local_package difit 2>&1 || true)
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
  if ! build_local_package difit; then
    echo "difit: verification build failed" >&2
    exit 1
  fi
fi

echo "== claude-code-settings-schema"
update_url_pin "claude-code-settings-schema" "nix/pins/claude-code-settings-schema.json"

echo "== codex-app"
update_codex_app_pin

echo
if git diff --quiet -- "${managed_pathspecs[@]}"; then
  echo "All pins up to date."
else
  echo "Pins updated. Review with 'git diff', verify with 'nix run .#build', then commit."
fi
restore_managed_files=false
