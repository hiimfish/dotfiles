#!/bin/bash

GITHUB_USER='hiimfish'
Q="-q"

# Prevent sleeping during script execution, as long as the machine is on AC power
caffeinate -s -w $$ &

echo "Setting up your Mac..."

# Check for Oh My Zsh and install if we don't have it
if [ ! -d "$ZSH" ]; then
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

# Setup dotfiles
if [ -n "$GITHUB_USER" ]; then
  DOTFILES_URL="https://github.com/$GITHUB_USER/dotfiles"

  if git ls-remote "$DOTFILES_URL" &>/dev/null; then
    echo  "Fetching $GITHUB_USER/dotfiles from GitHub:"
    if [ ! -d "$HOME/.dotfiles" ]; then
      echo "Cloning to ~/.dotfiles:"
      git clone $Q "$DOTFILES_URL" $HOME/.dotfiles
    else
      cd $HOME/.dotfiles
      git pull $Q --rebase --autostash
    fi    
  fi
fi