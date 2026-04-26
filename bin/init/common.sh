# ZERR (zsh) / ERR (bash) — report the failing line before set -e exits.
if [ -n "${ZSH_VERSION:-}" ]; then
  trap 'printf "error: %s failed at line %d (exit %d)\n" "${0}" ${LINENO} $? >&2' ZERR
else
  trap 'printf "error: %s failed at line %d (exit %d)\n" "${BASH_SOURCE[0]:-$0}" ${LINENO} $? >&2' ERR
fi

log_step() {
  printf "\n--- %s ---\n" "$1"
}

backup_path() {
  local src dest suffix
  src="$1"

  if [ ! -e "$src" ] && [ ! -L "$src" ]; then
    return 0
  fi

  : "${BACKUP_DIR:=${HOME}/backup}"
  mkdir -p "$BACKUP_DIR"

  dest="${BACKUP_DIR}/$(basename "$src")"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    suffix="$(date +%Y%m%d%H%M%S)"
    dest="${dest}.${suffix}"
  fi

  printf "backup: %s -> %s\n" "$src" "$dest"
  mv "$src" "$dest"
}

link_with_backup() {
  local src dest
  src="$1"
  dest="$2"

  if [ ! -e "$src" ] && [ ! -L "$src" ]; then
    printf "warning: missing source for link (skipping): %s -> %s\n" "$src" "$dest" >&2
    return 0
  fi

  mkdir -p "$(dirname "$dest")"

  if [ -L "$dest" ] && [ -e "$dest" ] && [ "$dest" -ef "$src" ]; then
    return 0
  fi

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    backup_path "$dest"
  fi

  ln -s "$src" "$dest"
}

detect_brew_bin() {
  local candidate

  if command -v brew >/dev/null 2>&1; then
    command -v brew
    return 0
  fi

  for candidate in \
    "/opt/homebrew/bin/brew" \
    "/usr/local/bin/brew" \
    "/home/linuxbrew/.linuxbrew/bin/brew" \
    "${HOME}/.linuxbrew/bin/brew"
  do
    if [ -x "$candidate" ]; then
      printf "%s\n" "$candidate"
      return 0
    fi
  done

  return 1
}

activate_brew_shellenv() {
  local brew_bin

  if ! brew_bin="$(detect_brew_bin)"; then
    printf "warning: brew is not installed yet (cannot initialize shellenv)\n" >&2
    return 1
  fi

  eval "$("$brew_bin" shellenv)"
}

install_or_upgrade_homebrew_linux() {
  if ! detect_brew_bin >/dev/null 2>&1; then
    if ! command -v curl >/dev/null 2>&1; then
      printf "warning: curl is not installed yet (cannot install homebrew)\n" >&2
      return 1
    fi

    # Ubuntu CI and fresh machines should install non-interactively.
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  activate_brew_shellenv
}

install_or_upgrade_brew_formula() {
  local formula
  formula="$1"

  if brew list --formula "$formula" >/dev/null 2>&1; then
    brew upgrade "$formula"
  else
    brew install "$formula"
  fi
}

install_or_upgrade_brew_bundle() {
  local brewfile
  brewfile="$1"
  # --verbose streams each formula's install output instead of buffering it
  # until the bundle completes, so long-running installs show progress/errors.
  brew bundle --verbose --file="$brewfile"
}

install_or_upgrade_git_repo() {
  local repo_url dest
  repo_url="$1"
  dest="$2"
  shift 2

  if [ -d "$dest/.git" ]; then
    if ! git -C "$dest" fetch --all --prune; then
      printf "warning: failed to fetch %s\n" "$dest" >&2
      return 1
    fi
    # Fast-forward the working directory so the init script uses the latest
    # files.  Non-fast-forward cases (local changes, diverged history) are
    # intentionally left alone with a warning.
    git -C "$dest" merge --ff-only 2>/dev/null ||
      printf "warning: could not fast-forward %s\n" "$dest" >&2
    return 0
  fi

  if [ -e "$dest" ]; then
    printf "warning: %s exists and is not a git repo (skipping clone)\n" "$dest" >&2
    return 1
  fi

  # Some callers use nested destinations (e.g. ~/.tmux/plugins/tpm).
  mkdir -p "$(dirname "$dest")"
  git clone "$@" "$repo_url" "$dest"
}

install_or_upgrade_volta() {
  local volta_bin
  volta_bin="${VOLTA_HOME:-${HOME}/.volta}/bin/volta"

  if command -v volta >/dev/null 2>&1 || [ -x "$volta_bin" ]; then
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    printf "warning: curl is not installed yet (cannot install volta)\n" >&2
    return 1
  fi

  # Avoid modifying symlinked shell rc files; PATH is managed in dotfiles.
  curl -fsSL https://get.volta.sh | bash -s -- --skip-setup
}

install_or_upgrade_node_with_volta() {
  local volta_cmd
  volta_cmd="${VOLTA_HOME:-${HOME}/.volta}/bin/volta"

  if command -v volta >/dev/null 2>&1; then
    volta install node
    return $?
  fi

  # init runs before a new shell picks up PATH changes from dotfiles.
  if [ -x "$volta_cmd" ]; then
    "$volta_cmd" install node
    return $?
  fi

  printf "warning: volta is not installed yet (cannot install node)\n" >&2
  return 1
}

install_or_upgrade_npm_global() {
  local package npm_cmd volta_npm
  package="$1"
  volta_npm="${VOLTA_HOME:-${HOME}/.volta}/bin/npm"

  if command -v npm >/dev/null 2>&1; then
    npm_cmd="$(command -v npm)"
  # Use Volta-managed npm directly during bootstrap before PATH reload.
  elif [ -x "$volta_npm" ]; then
    npm_cmd="$volta_npm"
  else
    printf "warning: npm is not installed yet (cannot install %s)\n" "$package" >&2
    return 1
  fi

  if "$npm_cmd" list -g --depth=0 "$package" >/dev/null 2>&1; then
    "$npm_cmd" update --global "$package"
  else
    "$npm_cmd" install --global "$package"
  fi
}

install_or_upgrade_gcloud() {
  local gcloud_bin
  gcloud_bin="${HOME}/google-cloud-sdk/bin/gcloud"

  if [ -x "$gcloud_bin" ] || command -v gcloud >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    printf "warning: curl is not installed yet (cannot install gcloud)\n" >&2
    return 1
  fi

  # zsh/lang.zsh lazy-loads the SDK from ~/google-cloud-sdk.
  curl -fsSL https://sdk.cloud.google.com | bash -s -- --disable-prompts --install-dir="${HOME}"
}

is_wsl() {
  [ -n "${WSL_DISTRO_NAME:-}" ] || grep -qi microsoft /proc/version 2>/dev/null
}

# Generate a locale via locale-gen if it is missing. .zshenv/.bash_profile
# export LANG=en_US.UTF-8, but a fresh Ubuntu/WSL only ships C.UTF-8, so libc
# emits "cannot set LC_CTYPE to default locale" until the locale is generated.
ensure_locale() {
  local locale_name normalized
  locale_name="${1:-en_US.UTF-8}"
  # locale -a reports "en_US.utf8" (no dash, lowercase) — normalize both sides.
  normalized="$(printf '%s' "$locale_name" | tr '[:upper:]' '[:lower:]' | tr -d '-')"

  if locale -a 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr -d '-' | grep -qx "$normalized"; then
    return 0
  fi

  if ! command -v locale-gen >/dev/null 2>&1; then
    sudo apt-get install -y locales
  fi

  sudo locale-gen "$locale_name"
  sudo update-locale LANG="$locale_name"
}

wsl_windows_home() {
  local cmd_exe userprofile

  if command -v cmd.exe >/dev/null 2>&1; then
    cmd_exe="cmd.exe"
  elif [ -x "/mnt/c/Windows/System32/cmd.exe" ]; then
    cmd_exe="/mnt/c/Windows/System32/cmd.exe"
  else
    printf "warning: cmd.exe not found\n" >&2
    return 1
  fi

  userprofile="$("$cmd_exe" /C 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r')"
  if [ -z "$userprofile" ]; then
    printf "warning: could not determine Windows USERPROFILE\n" >&2
    return 1
  fi

  wslpath "$userprofile"
}

install_or_upgrade_claude() {
  if command -v claude >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    printf "warning: curl is not installed yet (cannot install claude)\n" >&2
    return 1
  fi

  # Use the official installer; ~/.claude config is linked separately by init.
  curl -fsSL https://claude.ai/install.sh | bash
}
