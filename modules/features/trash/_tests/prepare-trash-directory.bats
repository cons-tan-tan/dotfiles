#!/usr/bin/env bats

DOTFILES_TEST_REPO_ROOT=${DOTFILES_TEST_REPO_ROOT:-$(git -C "$BATS_TEST_DIRNAME" rev-parse --show-toplevel)}
SCRIPT="$DOTFILES_TEST_REPO_ROOT/modules/features/trash/_scripts/prepare-trash-directory.sh"

setup() {
  TRASH_DIRECTORY="$BATS_TEST_TMPDIR/Trash"
}

@test "creates the Freedesktop trash directories with private permissions" {
  run env TRASH_DIRECTORY="$TRASH_DIRECTORY" bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [ -d "$TRASH_DIRECTORY/files" ]
  [ -d "$TRASH_DIRECTORY/info" ]
  [ "$(stat -c %a "$TRASH_DIRECTORY")" = 700 ]
  [ "$(stat -c %a "$TRASH_DIRECTORY/files")" = 700 ]
  [ "$(stat -c %a "$TRASH_DIRECTORY/info")" = 700 ]
}

@test "is idempotent and preserves existing trash entries" {
  mkdir -p "$TRASH_DIRECTORY/files" "$TRASH_DIRECTORY/info"
  printf 'payload\n' >"$TRASH_DIRECTORY/files/item"
  printf 'metadata\n' >"$TRASH_DIRECTORY/info/item.trashinfo"

  run env TRASH_DIRECTORY="$TRASH_DIRECTORY" bash "$SCRIPT"

  [ "$status" -eq 0 ]
  [ "$(cat "$TRASH_DIRECTORY/files/item")" = payload ]
  [ "$(cat "$TRASH_DIRECTORY/info/item.trashinfo")" = metadata ]
}

@test "fails closed when the trash directory is not provided" {
  run env -u TRASH_DIRECTORY bash "$SCRIPT"

  [ "$status" -ne 0 ]
}
