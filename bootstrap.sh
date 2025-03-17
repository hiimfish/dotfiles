#!/usr/bin/env bash

set -e

GIT_NAME='hiimfish'
GIT_EMAIL='chao.yen.po@gmail.com'
GITHUB_USER='hiimfish'
DOTFILES=$HOME/.dotfiles
Q='-q'

# Tweak file globbing
shopt -s dotglob nullglob

# 確保使用者不是 root
[ "$USER" = "root" ] && { echo "請不要以 root 身份執行此腳本"; exit 1; }
groups | grep -qE "\b(admin)\b" || { echo "請將 $USER 加入 admin 群組"; exit 1; }

# 初始化 sudo（避免多次輸入密碼）
sudo -v

# 防止 Mac 進入睡眠模式（僅限 AC 電源）
caffeinate -s -w $$ &

# 裝 Xcode Command Line Tools
if ! [ -f "/Library/Developer/CommandLineTools/usr/bin/git" ]; then
  echo "安裝 Xcode Command Line Tools..."
  sudo touch "/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"
  CLT_PACKAGE=$(softwareupdate -l | grep -B 1 "Command Line Tools" | awk -F"*" '/^ *\*/ {print $2}' | sed -e 's/^ *Label: //' -e 's/^ *//' | sort -V | tail -n1)
  sudo softwareupdate -i "$CLT_PACKAGE" --agree-to-license
  sudo rm -f "/tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress"

  # 確保 Xcode CLI 工具安裝成功
  if ! [ -f "/Library/Developer/CommandLineTools/usr/bin/git" ]; then
    echo "手動安裝 Xcode Command Line Tools（會彈出 GUI）："
    sudo xcode-select --install
    read -p "安裝完成後請按 Enter 繼續..."
    sudo xcode-select -s "/Library/Developer/CommandLineTools"
  fi
fi

# 設定 Git
echo "設定 Git..."
git config --global user.name "$GIT_NAME"
git config --global user.email "$GIT_EMAIL"
git config --global github.user "$GITHUB_USER"

# 安裝 Homebrew
if ! command -v brew &>/dev/null; then
  echo "安裝 Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  [[ $(uname -m) == "arm64" ]] && echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> $HOME/.zprofile
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# 安裝 Oh My Zsh
if [ ! -d "$ZSH" ]; then
  echo "安裝 Oh My Zsh..."
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/HEAD/tools/install.sh)"
fi

# 檢查 macOS 更新
echo "檢查 macOS 更新..."
if softwareupdate -l 2>&1 | grep -q "No new software available."; then
  echo "macOS 已是最新版本。"
else
  read -p "有可用的 macOS 更新，是否重新啟動以安裝？(Y/N): " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    sudo softwareupdate --install --all --restart
  else
    softwareupdate --download
  fi
fi

# Clone dotfiles
if git ls-remote "https://github.com/$GITHUB_USER/dotfiles" &>/dev/null; then
  echo "下載 dotfiles..."
  if [ ! -d "$DOTFILES" ]; then
    git clone "$Q" "https://github.com/$GITHUB_USER/dotfiles" "$DOTFILES"
  else
    git -C "$DOTFILES" pull "$Q" --rebase --autostash
  fi
fi

# 安裝 Homebrew 軟體
if [ -f "$DOTFILES/install/Brewfile" ]; then
  echo "安裝 Brewfile 軟體..."
  ln -sf "$DOTFILES/install/Brewfile" ~/.Brewfile
  brew bundle --global --quiet
fi

# 執行 macOS 設定腳本
if [ -f "$DOTFILES/setup/macos.sh" ]; then
  echo "執行 macOS 設定腳本..."
  /bin/sh "$DOTFILES/setup/macos.sh"
fi

# 建立必要的目錄
mkdir -pv "$HOME/OSS" "$HOME/Forceit"
# ln -sf "$(pwd -P)" "$HOME/OSS/dotfiles"

echo "✅ 設定完成！請重新啟動終端機以應用所有變更。"
