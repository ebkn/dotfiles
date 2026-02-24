log_step() {
  printf "\n--- %s ---\n" "$1"
}

backup_path() {
  local path backup_path suffix
  path="$1"

  if [ ! -e "$path" ] && [ ! -L "$path" ]; then
    return 0
  fi

  : "${BACKUP_DIR:=${HOME}/backup}"
  mkdir -p "$BACKUP_DIR"

  backup_path="${BACKUP_DIR}/$(basename "$path")"
  if [ -e "$backup_path" ] || [ -L "$backup_path" ]; then
    suffix="$(date +%Y%m%d%H%M%S)"
    backup_path="${backup_path}.${suffix}"
  fi

  mv "$path" "$backup_path"
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

install_or_upgrade_git_repo() {
  local repo_url dest
  repo_url="$1"
  dest="$2"
  shift 2

  if [ -d "$dest/.git" ]; then
    if ! git -C "$dest" pull --ff-only; then
      printf "warning: failed to update %s\n" "$dest" >&2
      return 1
    fi
    return 0
  fi

  if [ -e "$dest" ]; then
    printf "warning: %s exists and is not a git repo (skipping clone)\n" "$dest" >&2
    return 1
  fi

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

  curl -fsSL https://sdk.cloud.google.com | bash -s -- --disable-prompts --install-dir="${HOME}"
}

install_or_upgrade_claude() {
  if command -v claude >/dev/null 2>&1; then
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    printf "warning: curl is not installed yet (cannot install claude)\n" >&2
    return 1
  fi

  curl -fsSL https://claude.ai/install.sh | bash
}
