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
    printf "skip linking (missing source): %s -> %s\n" "$src" "$dest"
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
      printf "warning: failed to update %s (continuing)\n" "$dest" >&2
    fi
    return 0
  fi

  if [ -e "$dest" ]; then
    printf "warning: %s exists and is not a git repo (skipping clone)\n" "$dest" >&2
    return 0
  fi

  git clone "$@" "$repo_url" "$dest"
}
