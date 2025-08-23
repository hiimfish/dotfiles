#!/usr/bin/env bash

set -e

GIT_NAME='hiimfish'
GIT_EMAIL='chao.yen.po@gmail.com'
GITHUB_USER='hiimfish'
DOTFILES=$HOME/.dotfiles
Q='-q'

# Symlink files.
symlink_header() { echo "Linking files into home directory"; }

# 智能 symlink 測試函數
symlink_test() {
  local source_file="$1"
  local dest_file="$2"

  # 如果目標文件不存在，直接返回（可以創建 symlink）
  if [[ ! -e "$dest_file" ]]; then
    return 0
  fi

  # 如果目標已經是正確的 symlink，跳過
  if [[ -L "$dest_file" ]] && [[ "$(readlink "$dest_file")" == "$source_file" ]]; then
    echo "already linked"
    return 0
  fi

  # 如果目標是錯誤的 symlink，需要處理
  if [[ -L "$dest_file" ]]; then
    if [[ "$(readlink "$dest_file")" != "$source_file" ]]; then
      echo "wrong symlink"
      return 0
    fi
  fi

  # 如果目標是普通文件或目錄，檢查內容差異
  if [[ -f "$dest_file" ]] || [[ -d "$dest_file" ]]; then
    if [[ -f "$source_file" ]] && [[ -f "$dest_file" ]]; then
      # 比較文件內容
      if ! cmp -s "$source_file" "$dest_file" 2>/dev/null; then
        echo "different content"
        return 0
      fi
    else
      # 類型不同，需要備份
      echo "different type"
      return 0
    fi
  fi

  # 如果完全相同，跳過
  if [[ "$source_file" -ef "$dest_file" ]]; then
    echo "same file"
    return 0
  fi

  # 默認情況，需要處理
  return 0
}

# 智能備份和 symlink 創建
symlink_do() {
  local base="$1"
  local source_file="$2"
  local dest_file="$HOME/$base"
  local backup_dir="$DOTFILES/backups"

  # 創建備份目錄
  [[ -e "$backup_dir" ]] || mkdir -p "$backup_dir"

  # 如果目標文件存在且需要備份
  if [[ -e "$dest_file" ]]; then
    local backup_path="$backup_dir/${base}.$(date +%Y%m%d_%H%M%S)"
    local timestamp=$(date +%Y%m%d_%H%M%S)

    # 智能備份：如果是 symlink，備份其目標內容；如果是普通文件，直接備份
    if [[ -L "$dest_file" ]]; then
      local link_target=$(readlink "$dest_file")
      echo "Backing up symlink ~/$base (target: $link_target) to $backup_path"

      # 創建備份目錄結構
      mkdir -p "$(dirname "$backup_path")"

      # 如果 symlink 目標存在，複製內容；否則只保存 symlink 信息
      if [[ -e "$link_target" ]]; then
        if [[ -d "$link_target" ]]; then
          cp -r "$link_target" "$backup_path"
        else
          cp "$link_target" "$backup_path"
        fi
      else
        # 如果目標不存在，創建一個記錄文件
        echo "Symlink target: $link_target" > "$backup_path.info"
        echo "Original symlink: $dest_file" >> "$backup_path.info"
        echo "Backup time: $(date)" >> "$backup_path.info"
      fi
    else
      echo "Backing up ~/$base to $backup_path"
      if [[ -d "$dest_file" ]]; then
        cp -r "$dest_file" "$backup_path"
      else
        cp "$dest_file" "$backup_path"
      fi
    fi

    # 設置備份標誌
    backup=1
  fi

  # 創建 symlink
  echo "Linking ~/$base -> $source_file"
  ln -sfn "$source_file" "$dest_file"
}

do_stuff() {
  local base dest skip
  local files=($DOTFILES/$1/*)
  local backup_dir="$DOTFILES/backups"
  local backup=0

  [[ $(declare -f "$1_files") ]] && files=($($1_files "${files[@]}"))
  # No files? abort.
  if (( ${#files[@]} == 0 )); then return; fi
  # Run _header function only if declared.
  [[ $(declare -f "$1_header") ]] && "$1_header"
  # Iterate over files.
  for file in "${files[@]}"; do
    base="$(basename $file)"
    # Get dest path.
    if [[ $(declare -f "$1_dest") ]]; then
      dest="$("$1_dest" "$base")"
    else
      dest="$HOME/$base"
    fi
    # Run _test function only if declared.
    if [[ $(declare -f "$1_test") ]]; then
      # If _test function returns a string, skip file and print that message.
      skip="$("$1_test" "$file" "$dest")"
      if [[ "$skip" == "already linked" ]]; then
        echo "Skipping ~/$base, already correctly linked."
        continue
      elif [[ "$skip" == "same file" ]]; then
        echo "Skipping ~/$base, same file."
        continue
      fi
    fi
    # Do stuff.
    "$1_do" "$base" "$file"
  done

  # 顯示備份信息
  if [[ $backup -eq 1 ]]; then
    echo ""
    echo "📁 備份文件已保存到: $backup_dir"
    echo "💡 如果需要恢復，可以從備份目錄手動恢復文件"
  fi
}

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

# # 檢查 macOS 更新
# echo "檢查 macOS 更新..."
# if softwareupdate -l 2>&1 | grep -q "No new software available."; then
#   echo "macOS 已是最新版本。"
# else
#   read -p "有可用的 macOS 更新，是否重新啟動以安裝？(Y/N): " answer
#   if [[ "$answer" =~ ^[Yy]$ ]]; then
#     sudo softwareupdate --install --all --restart
#   else
#     softwareupdate --download
#   fi
# fi

# Clone dotfiles
if git ls-remote "https://github.com/$GITHUB_USER/dotfiles" &>/dev/null; then
  echo "下載 dotfiles..."
  if [ ! -d "$DOTFILES" ]; then
    git clone "$Q" "https://github.com/$GITHUB_USER/dotfiles" "$DOTFILES"
  else
    git -C "$DOTFILES" pull "$Q" --rebase --autostash
  fi
fi

do_stuff symlink

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
mkdir -pv "$HOME/OSS" "$HOME/Forceit" "$HOME/YT" "$HOME/POYUN"
# ln -sf "$(pwd -P)" "$HOME/OSS/dotfiles"

# 安裝前端環境
volta install node
volta install yarn
volta install pnpm
# volta install bun
# volta install turbo
# volta install next

echo "✅ 設定完成！請重新啟動終端機以應用所有變更。"
