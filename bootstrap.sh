#!/bin/bash

GITHUB_USER='hiimfish'
DOTFILES=$HOME/.dotfiles
Q="-q"

# Prevent sleeping during script execution, as long as the machine is on AC power
caffeinate -s -w $$ &

echo "Setting up your Mac..."

# Check for Oh My Zsh and install if we don't have it
if test ! -d "$ZSH"; then
  /bin/sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/HEAD/tools/install.sh)"
fi

# Check for Homebrew and install if we don't have it
if test ! -x "$(which brew)"; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  UNAME_MACHINE="$(/usr/bin/uname -m)"
  if [[ $UNAME_MACHINE == "arm64" ]]; then
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> $HOME/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
fi

# Check and install any remaining software updates.
echo "Checking for software updates:"
if softwareupdate -l 2>&1 | grep $Q "No new software available."; then
  echo 'OK'
else
  echo "Installing software updates:"
  softwareupdate --install --all
fi

# Setup dotfiles project
if [ -n "$GITHUB_USER" ]; then
  DOTFILES_URL="https://github.com/$GITHUB_USER/dotfiles"

  if git ls-remote "$DOTFILES_URL" &>/dev/null; then
    echo  "Fetching $GITHUB_USER/dotfiles from GitHub:"
    if [ ! -d "$DOTFILES" ]; then
      echo "Cloning to $DOTFILES."
      git clone $Q "$DOTFILES_URL" $DOTFILES
    else
      echo "Pulling to $DOTFILES."
      cd $DOTFILES
      git pull $Q --rebase --autostash
    fi    
  fi
fi

# Dotfiles Install
if [ -f "$DOTFILES/install/Brewfile" ]; then
  echo "Installing Brewfile:"
  brew bundle check --file $DOTFILES/install/Brewfile || brew bundle --file $DOTFILES/install/Brewfile
fi

# Dotfiles Setup
if [ -f "$DOTFILES/setup/macos.sh" ]; then
  echo "Setuping macOS:"
  DOTFILES/setup/macos.sh
fi
