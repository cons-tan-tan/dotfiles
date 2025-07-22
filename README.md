# dotfiles

## セットアップ

### chezmoiインストール

```shell
# miseのインストール
# 1. Windowsの場合
# https://scoop.sh/ がインストールされている前提(PowerShellでのインストール)
$ scoop install mise

# 2. WSLの場合
# https://brew.sh/ja/ のインストールスニペット
# rootユーザーだと実行できないので注意
$ /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
# miseのインストール
$ brew install mise

# 正しくインストールできたか確認
$ mise doctor
# miseの有効化
$ echo 'eval "$(mise activate bash)"' >> ~/.bashrc
$ echo 'eval "$(mise activate zsh)"' >> ~/.zshrc
# chezmoiのインストール
$ mise use -g chezmoi
```

### 初回実行

```shell
# https接続
$ chezmoi init https://github.com/cons-tan-tan/dotfiles.git
# ssh接続
$ chezmoi init git@github.com:cons-tan-tan/dotfiles.git

# 差分の確認(上書き前提なら飛ばしてOK)
$ chezmoi diff

# 問題なければ適用
$ chezmoi apply
# 個別に適用する場合
$ chezmoi apply [FILE]
```

### パッケージマネージャーの対応
```shell
# brewの一括インストール
$ brew bundle

# miseの一括インストール
$ mise install
```

### 他ツールの対応
```shell
# https://github.com/nullpo-head/WSL-Hello-sudo のインストール
$ wget http://github.com/nullpo-head/WSL-Hello-sudo/releases/latest/download/release.tar.gz
$ tar xvf release.tar.gz
$ cd release
$ ./install.sh
```

## 運用

```shell
# リモートリポジトリの最新状態を反映
$ chezmoi update

# chezmoiリポジトリに移動
$ chezmoi cd
```
