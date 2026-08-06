#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
source "$DOTFILES_TEST_REPO_ROOT/modules/features/checks/_interface/bats/test-helper.bash"

setup() {
  require_nix_fixture CODEX_UPDATE_TEST_FIXTURE 'Codex app updater dependencies'
}

@test "Codex app updater validates the archive and accepts CFBundleName fallback" {
  local repo="$BATS_TEST_TMPDIR/repo"
  local stubs="$BATS_TEST_TMPDIR/stubs"
  local fixture="$BATS_TEST_TMPDIR/fixture"
  local appcast="$fixture/appcast.xml"
  local archive="$fixture/Codex.zip"
  local pin=modules/features/agents/codex/_packages/codex-app/pin.json
  local url=https://persistent.oaistatic.com/codex-app-prod/ChatGPT-darwin-arm64-2.0.0.zip
  mkdir -p "$repo/$(dirname "$pin")" "$stubs" "$fixture/ChatGPT.app/Contents"
  git -C "$repo" init --quiet
  jq -n '
    {
      version: "1.0.0",
      appcast: "https://example.invalid/appcast.xml",
      url: "https://example.invalid/old.zip",
      hash: "sha256-old",
      appName: "ChatGPT.app",
      bundleIdentifier: "com.openai.codex",
      displayName: "ChatGPT"
    }
  ' >"$repo/$pin"
  printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>' \
    '<sparkle:shortVersionString>2.0.0</sparkle:shortVersionString>' \
    "<enclosure url=\"${url}\"/>" \
    '</item></channel></rss>' >"$appcast"
  printf '%s\n' \
    '<?xml version="1.0" encoding="UTF-8"?>' \
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
    '<plist version="1.0"><dict>' \
    '<key>CFBundleIdentifier</key><string>com.openai.codex</string>' \
    '<key>CFBundleName</key><string>ChatGPT</string>' \
    '<key>CFBundleShortVersionString</key><string>2.0.0</string>' \
    '</dict></plist>' >"$fixture/ChatGPT.app/Contents/Info.plist"
  (cd "$fixture" && zip -qr "$archive" ChatGPT.app)

  write_bash_stub "$stubs/nix" <<'SH'
url=${!#}
if [[ $url == https://example.invalid/appcast.xml ]]; then
  jq -n --arg storePath "$UPDATE_APPCAST" '{storePath: $storePath}'
else
  jq -n --arg storePath "$UPDATE_ARCHIVE" \
    '{storePath: $storePath, hash: "sha256-new"}'
fi
SH

  run env \
    PATH="$stubs:$PATH" \
    UPDATE_APPCAST="$appcast" \
    UPDATE_ARCHIVE="$archive" \
    bash -c 'cd "$1" && exec bash "$2"' _ "$repo" \
    "$DOTFILES_TEST_REPO_ROOT/modules/features/agents/codex/_scripts/update-app.sh"
  [ "$status" -eq 0 ]
  [ "$(jq -r .version "$repo/$pin")" = 2.0.0 ]
  [ "$(jq -r .url "$repo/$pin")" = "$url" ]
  [ "$(jq -r .hash "$repo/$pin")" = sha256-new ]
}
