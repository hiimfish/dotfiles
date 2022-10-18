#!/usr/bin/env bash

GIT_NAME='hiimfish'
GIT_EMAIL='chao.yen.po@gmail.com'
GITHUB_USER='hiimfish'
DOTFILES=$HOME/.dotfiles
BOOTSTRAP_INTERACTIVE=0
Q='-q'

# If backups are needed, this is where they'll go.
backup_dir="$DOTFILES/backups/$(date "+%Y_%m_%d-%H_%M_%S")/"
backup=0

# Initialise (or reinitialise) sudo to save unhelpful prompts later.
sudo_init() {
  if [ -z "$BOOTSTRAP_INTERACTIVE" ]; then
    return
  fi

  local SUDO_PASSWORD SUDO_PASSWORD_SCRIPT

  if ! sudo --validate --non-interactive &>/dev/null; then
    while true; do
      user ' - What is your sudo password?'
      read -rse SUDO_PASSWORD
      echo
      if sudo --validate --stdin 2>/dev/null <<<"$SUDO_PASSWORD"; then
        break
      fi

      unset SUDO_PASSWORD
      echo "!!! Wrong password!" >&2
    done
    
    SUDO_PASSWORD_SCRIPT="$(
      cat <<BASH
#!/bin/bash
echo "$SUDO_PASSWORD"
BASH
    )"
    unset SUDO_PASSWORD
    SUDO_ASKPASS_DIR="$(mktemp -d)"
    SUDO_ASKPASS="$(mktemp "$SUDO_ASKPASS_DIR"/strap-askpass-XXXXXXXX)"
    chmod 700 "$SUDO_ASKPASS_DIR" "$SUDO_ASKPASS"
    bash -c "cat > '$SUDO_ASKPASS'" <<<"$SUDO_PASSWORD_SCRIPT"
    unset SUDO_PASSWORD_SCRIPT

    export SUDO_ASKPASS
  fi
}

sudo_askpass() {
  if [ -n "$SUDO_ASKPASS" ]; then
    sudo --askpass "$@"
  else
    sudo "$@"
  fi
}

sudo_refresh() {
  if [ -n "$SUDO_ASKPASS" ]; then
    sudo --askpass --validate
  else
    sudo_init
  fi
}

info () {
  printf "\r  [ \033[00;34m..\033[0m ] $1\n"
}

success () {
  printf "\r\033[2K  [ \033[00;32mOK\033[0m ] $1\n"
}

fail () {
  printf "\r\033[2K  [\033[0;31mFAIL\033[0m] $1\n"
  echo ''
}

abort () {
  fail $1
  exit 1
}

user () {
  printf "\r  [ \033[0;33m??\033[0m ] $1\n"
}

# Link files.
link_header() { info "Linking files into home directory"; }
link_test() {
  [[ "$1" -ef "$2" ]] && echo "same file"
}
link_do() {
  success "Linking ~/$1."
  ln -sf ${2#$HOME/} ~/
}

do_stuff() {
  local base dest skip
  local files=($DOTFILES/$1/*)
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
      if [[ "$skip" ]]; then
        fail "Skipping ~/$base, $skip."
        continue
      fi
      # Destination file already exists in ~/. Back it up!
      if [[ -e "$dest" ]]; then
        info "Backing up ~/$base."
        # Set backup flag, so a nice message can be shown at the end.
        backup=1
        # Create backup dir if it doesn't already exist.
        [[ -e "$backup_dir" ]] || mkdir -p "$backup_dir"
        # Backup file / link / whatever.
        mv "$dest" "$backup_dir"
      fi
    fi
    # Do stuff.
    "$1_do" "$base" "$file"
  done
}

# We want to always prompt for sudo password
sudo --reset-timestamp
sudo -v
while true; do sudo -n true; sleep 10; kill -0 "$$" || exit; done 2>/dev/null &

[ "$USER" = "root" ] && abort "Run Strap as yourself, not root."
groups | grep $Q -E "\b(admin)\b" || abort "Add $USER to the admin group."

# Prevent sleeping during script execution, as long as the machine is on AC power
caffeinate -s -w $$ &

# Setup Git configuration.
info "Configuring Git"
if [ -n "$GIT_NAME" ] && ! git config user.name >/dev/null; then
  git config --global user.name "$GIT_NAME"
fi

if [ -n "$GIT_EMAIL" ] && ! git config user.email >/dev/null; then
  git config --global user.email "$GIT_EMAIL"
fi

if [ -n "$GITHUB_USER" ] && [ "$(git config github.user)" != "$GITHUB_USER" ]; then
  git config --global github.user "$GITHUB_USER"
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

# Check for Oh My Zsh and install if we don't have it
if test ! -d "$ZSH"; then
  /bin/sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/HEAD/tools/install.sh)"
fi

# Check and install any remaining software updates.
info "Checking for software updates"
if softwareupdate -l 2>&1 | grep $Q "No new software available."; then
  info "No new software available."
else
  softwareupdate --install --all
fi
success

# Setup dotfiles project
if [ -n "$GITHUB_USER" ]; then
  DOTFILES_URL="https://github.com/$GITHUB_USER/dotfiles"

  if git ls-remote "$DOTFILES_URL" &>/dev/null; then
    info  "Fetching $GITHUB_USER/dotfiles from GitHub:"
    if [ ! -d "$DOTFILES" ]; then
      info "Cloning to $DOTFILES."
      git clone $Q "$DOTFILES_URL" $DOTFILES
    else
      info "Pulling to $DOTFILES."
      cd $DOTFILES
      git pull $Q --rebase --autostash
    fi    
  fi
fi
success

# Dotfiles Install
if [ -f "$DOTFILES/install/Brewfile" ]; then
  info "Installing Brewfile:"
  brew bundle --quiet --file $DOTFILES/install/Brewfile
  success
fi

# Dotfiles Setup
if [ -f "$DOTFILES/setup/macos.sh" ]; then
  info "Setuping macOS:"
  /bin/sh $DOTFILES/setup/macos.sh
  success
fi

do_stuff link

# Alert if backups were made.
if [[ "$backup" ]]; then
  info "\nBackups were moved to ~/${backup_dir#$HOME/}"
fi