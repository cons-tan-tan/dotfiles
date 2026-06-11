# gh のエイリアス定義。現ホスト用 (modules/home/programs/gh.nix) と
# Windows companion 用 (modules/wsl/windows/gh.nix) で共有する。
{
  aliases = {
    # gh api を GET 固定で実行する (意図しない書き込み操作の防止)
    api-get = ''!gh api "$@" --method GET'';
  };
}
