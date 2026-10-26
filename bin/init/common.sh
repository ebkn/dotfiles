# Sourced by both zsh (macos.sh) and bash (ubuntu.sh/wsl.sh/relink), so it has
# no shebang. Declare the dialect explicitly or shellcheck refuses the file
# (SC2148) and CI silently checks nothing.
# shellcheck shell=bash

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
  local src dest suffix stem n
  src="$1"

  if [ ! -e "$src" ] && [ ! -L "$src" ]; then
    return 0
  fi

  : "${BACKUP_DIR:=${HOME}/backup}"
  mkdir -p "$BACKUP_DIR"

  dest="${BACKUP_DIR}/$(basename "$src")"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    suffix="$(date +%Y%m%d%H%M%S)"
    stem="${dest}.${suffix}"
    dest="$stem"
    # A second-resolution stamp is not unique: one link_dotfiles run backs up
    # several destinations sharing a basename (settings.json, AGENTS.md, each
    # skill three times) within the same second, and `mv` onto the taken name
    # would silently replace that earlier backup -- or, for a directory, move
    # into it. Count up until the name is free.
    n=1
    while [ -e "$dest" ] || [ -L "$dest" ]; do
      dest="${stem}.${n}"
      n=$((n + 1))
    done
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

  # Already correctly linked, or dest already resolves to src through a symlinked
  # parent dir — nothing to do in either apply or check mode. The `-ef` test alone
  # (dest and src are the same file) covers both cases: dropping the earlier
  # `[ -L "$dest" ]` requirement is deliberate. When a parent dir is itself
  # symlinked into the repo, dest is a *real* file (not a symlink) that already IS
  # src; without this guard, backup_path below would `mv` the real repo file out
  # to ~/backup and `ln -s` would leave a self-referential symlink in the repo — a
  # data-loss bug.
  if [ -e "$dest" ] && [ "$dest" -ef "$src" ]; then
    return 0
  fi

  # Check mode (LINK_CHECK=1): report drift and record it in LINK_DRIFT without
  # touching the filesystem. `relink` uses this to preview work before asking.
  if [ "${LINK_CHECK:-0}" = "1" ]; then
    # Consumed by bin/relink to decide whether to prompt.
    # shellcheck disable=SC2034
    LINK_DRIFT=1
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      printf "drift:   %s does not point to %s\n" "$dest" "$src"
    else
      printf "missing: %s -> %s\n" "$dest" "$src"
    fi
    return 0
  fi

  mkdir -p "$(dirname "$dest")"

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    backup_path "$dest"
  fi

  ln -s "$src" "$dest"
}

# ensure_ssh_base_include <config> [target=config_base]
#
# Make <config> (~/.ssh/config, machine-local) pull in the shared defaults as
# its last lines, inside `Host *`:
#
#   Host *
#   Include config_base
#
# Both halves matter, and each was missed once. Last: ssh keeps the first value
# it reads for an option, so defaults read last never override a host's own
# setting (an Include at the top, as wsl.sh wrote, let them win). `Host *`: an
# Include after a Host block is conditional on that block, so a bare Include
# appended after the last host (as macos.sh wrote) reached that one host only.
#
# Any existing Include of the target is removed first, so the broken forms are
# repaired and a rerun changes nothing. The target is matched as written,
# ignoring only case and whitespace -- plus, for a relative target, its
# `~/.ssh/` spelling: ssh reads a relative Include in a user config from ~/.ssh, so
# `Include ~/.ssh/config_base` is the same file, and the repo's old .sshconfig
# template put exactly that line at the top. Nothing else is taken for it.
#
# A `Host *` directly above a removed Include goes too, but only when nothing
# but blanks and comments follow the Include in that block: a user who put
# settings there meant them for every host, and dropping the header would fold
# them into the block before -- the same silent narrowing this function exists
# to undo.
#
# The file is rewritten only when its content changes, and never from a failed
# read: it is the user's own file and no backup is taken, so an unreadable one
# is left alone and the call returns 1 (callers run without errexit, or under
# `||`, as much as with it).
ensure_ssh_base_include() {
  local config target tmp alias tilde
  config="$1"
  target="${2:-config_base}"
  tmp="${config}.tmp"
  # The ~/.ssh/ spelling of a relative target, as text in the file -- the tilde
  # is matched, never expanded. ssh draws the line the same way: only an
  # absolute or ~ path names itself; any other, with a / or not, is read from
  # ~/.ssh.
  tilde='~'
  case "$target" in
    /* | "$tilde"*) alias="$target" ;;
    *) alias="$tilde/.ssh/$target" ;;
  esac

  mkdir -p "$(dirname "$config")"
  if [ -f "$config" ]; then
    if ! awk -v inc="include $target" -v alt="include $alias" '
        function norm(s) {
          sub(/^[ \t]+/, "", s)
          sub(/[ \t]+$/, "", s)
          gsub(/[ \t]+/, " ", s)
          return tolower(s)
        }
        { line[NR] = $0 }
        END {
          for (i = 1; i <= NR; i++) {
            if (norm(line[i]) != tolower(inc) && norm(line[i]) != tolower(alt)) continue
            drop[i] = 1
            if (i == 1 || norm(line[i - 1]) != "host *") continue
            rest_empty = 1
            for (j = i + 1; j <= NR; j++) {
              n = norm(line[j])
              if (n ~ /^(host|match)( |$)/) break
              if (n != "" && substr(n, 1, 1) != "#") {
                rest_empty = 0
                break
              }
            }
            if (rest_empty) drop[i - 1] = 1
          }
          # Blank lines left at either end by a removed Include are dropped.
          first = 0
          last = 0
          for (i = 1; i <= NR; i++) {
            if (drop[i] || norm(line[i]) == "") continue
            if (!first) first = i
            last = i
          }
          for (i = first; i <= last && first; i++)
            if (!drop[i]) print line[i]
          if (last > 0) print ""
        }
      ' "$config" >"$tmp"; then
      rm -f "$tmp"
      printf "warning: could not read %s (left as is)\n" "$config" >&2
      return 1
    fi
  else
    : >"$tmp"
  fi
  if ! printf 'Host *\nInclude %s\n' "$target" >>"$tmp"; then
    rm -f "$tmp"
    printf "warning: could not write %s (left as is)\n" "$tmp" >&2
    return 1
  fi

  if [ -f "$config" ] && cmp -s "$tmp" "$config"; then
    rm -f "$tmp"
  elif ! mv "$tmp" "$config"; then
    rm -f "$tmp"
    printf "warning: could not replace %s (left as is)\n" "$config" >&2
    return 1
  fi
  chmod 600 "$config"
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
    "${HOME}/.linuxbrew/bin/brew"; do
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

# pin_platform -- this machine as the suffix bin/init/pins.sh names its
# checksums with (DARWIN_ARM64, LINUX_X64, ...). Fails on anything else, so a
# platform nobody pinned is refused rather than given another's binary.
pin_platform() {
  local os arch
  case "$(uname -s)" in
    Darwin) os=DARWIN ;;
    Linux) os=LINUX ;;
    *) return 1 ;;
  esac
  case "$(uname -m)" in
    arm64 | aarch64) arch=ARM64 ;;
    x86_64 | amd64) arch=X64 ;;
    *) return 1 ;;
  esac
  printf '%s_%s\n' "$os" "$arch"
}

# pinned_sha256 <TOOL> -- the value of <TOOL>_SHA256_<platform> from pins.sh.
# Fails only on a platform pin_platform does not know; a known platform with
# no pin prints an empty line and succeeds, and fetch_verified refuses that.
# <TOOL> goes through eval, so callers pass a literal name, never input.
pinned_sha256() {
  local platform
  platform="$(pin_platform)" || {
    printf "error: no %s checksum is pinned for %s %s\n" "$1" "$(uname -s)" "$(uname -m)" >&2
    return 1
  }
  eval "printf '%s\n' \"\${${1}_SHA256_${platform}:-}\""
}

# fetch_verified <url> <sha256> <dest> -- download to <dest> only if the bytes
# hash to the pin. The download lands beside <dest> first, so a mismatch
# leaves nothing behind for a later step to run. An empty pin is an error,
# not a pass: a checksum missing from pins.sh must not mean "unchecked".
fetch_verified() {
  local url sha dest actual
  url="$1"
  sha="$2"
  dest="$3"

  if [ -z "$sha" ]; then
    printf "error: no checksum pinned for %s\n" "$url" >&2
    return 1
  fi
  if ! command -v curl >/dev/null 2>&1; then
    printf "warning: curl is not installed yet (cannot fetch %s)\n" "$url" >&2
    return 1
  fi

  curl -fsSL -o "${dest}.part" "$url" || {
    rm -f "${dest}.part"
    return 1
  }
  if command -v sha256sum >/dev/null 2>&1; then
    actual="$(sha256sum "${dest}.part" | cut -d' ' -f1)"
  else
    actual="$(shasum -a 256 "${dest}.part" | cut -d' ' -f1)"
  fi
  if [ "$actual" != "$sha" ]; then
    rm -f "${dest}.part"
    printf "error: checksum mismatch for %s\n  want %s\n  got  %s\n" "$url" "$sha" "$actual" >&2
    return 1
  fi
  mv "${dest}.part" "$dest"
}

# install_homebrew -- run Homebrew's installer at the commit pins.sh names.
# NONINTERACTIVE so CI and a fresh Linux box do not stop at its prompt; a Mac
# keeps the prompt, which is where it asks for the sudo password.
install_homebrew() {
  local tmp rc=0
  tmp="$(mktemp -d)"
  if fetch_verified \
    "https://raw.githubusercontent.com/Homebrew/install/${HOMEBREW_INSTALL_COMMIT}/install.sh" \
    "$HOMEBREW_INSTALL_SHA256" "${tmp}/install.sh"; then
    /bin/bash "${tmp}/install.sh" || rc=$?
  else
    rc=1
  fi
  rm -rf "$tmp"
  return "$rc"
}

install_or_upgrade_homebrew_linux() {
  if ! detect_brew_bin >/dev/null 2>&1; then
    NONINTERACTIVE=1 install_homebrew || return 1
  fi

  activate_brew_shellenv
}

# Refresh Homebrew itself before touching any formula. CI runners ship a
# preinstalled Homebrew with auto-update disabled, and a Homebrew older than the
# formula JSON API's schema aborts mid-pour with "unknown install step: run".
#
# Credentials are ensured between the two: after the update, so gh is poured by
# a current Homebrew, and before the upgrade, the first command that pours a
# verified bottle. Every init script comes through here before its first
# install, which is why the check lives here and not in each script.
update_homebrew() {
  brew update || return 1
  ensure_homebrew_github_auth || return 1
  brew upgrade
}

# ensure_homebrew_github_auth -- make sure Homebrew will find GitHub
# credentials. With HOMEBREW_VERIFY_ATTESTATIONS=1 (homebrew-env.sh) and none,
# every bottle but gh's fails to install ("could not be verified ... missing
# GitHub API token"); Homebrew does not fall back to installing unverified. gh
# itself is exempt from verification, so it can be installed to log in with.
# A login needs a terminal: without one -- CI, a piped run -- this fails and
# says how to pass a token instead. Homebrew also reads macOS Keychain
# credentials, which this does not look for; a machine relying on those alone
# is asked to log in anyway.
ensure_homebrew_github_auth() {
  if [ -n "${HOMEBREW_GITHUB_API_TOKEN:-}" ]; then
    return 0
  fi

  if ! command -v gh >/dev/null 2>&1; then
    brew install gh || return 1
  fi
  if gh auth token >/dev/null 2>&1; then
    return 0
  fi

  if [ -t 0 ]; then
    printf "Homebrew verifies bottle attestations, which needs a GitHub login.\n"
    if gh auth login --hostname github.com --git-protocol ssh &&
      gh auth token >/dev/null 2>&1; then
      return 0
    fi
  fi

  printf "error: Homebrew found no GitHub credentials, so no bottle can be verified.\n" >&2
  printf "  Run 'gh auth login', or set HOMEBREW_GITHUB_API_TOKEN, and re-run.\n" >&2
  return 1
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

  # The destination's parent may not exist yet.
  mkdir -p "$(dirname "$dest")"
  git clone "$@" "$repo_url" "$dest"
}

install_or_upgrade_volta() {
  local volta_bin
  volta_bin="${VOLTA_HOME:-${HOME}/.volta}/bin/volta"

  if command -v volta >/dev/null 2>&1 || [ -x "$volta_bin" ]; then
    return 0
  fi

  local asset sha tmp rc=0
  case "$(pin_platform)" in
    DARWIN_*) asset=macos ;; # one universal tarball
    LINUX_X64) asset=linux ;;
    LINUX_ARM64) asset=linux-arm ;;
  esac
  sha="$(pinned_sha256 VOLTA)" || return 1

  # The release tarball holds only the binaries, so unpacking it is all
  # get.volta.sh --skip-setup did; no rc file is touched, as PATH is managed
  # in dotfiles.
  tmp="$(mktemp -d)"
  if fetch_verified \
    "https://github.com/volta-cli/volta/releases/download/v${VOLTA_VERSION}/volta-${VOLTA_VERSION}-${asset}.tar.gz" \
    "$sha" "${tmp}/volta.tar.gz"; then
    mkdir -p "$(dirname "$volta_bin")"
    tar -xzf "${tmp}/volta.tar.gz" -C "$(dirname "$volta_bin")" || rc=$?
  else
    rc=1
  fi
  rm -rf "$tmp"
  return "$rc"
}

install_or_upgrade_node_with_volta() {
  local volta_cmd
  volta_cmd="${VOLTA_HOME:-${HOME}/.volta}/bin/volta"

  if command -v volta >/dev/null 2>&1; then
    volta install "node@${NODE_VERSION}"
    return $?
  fi

  # init runs before a new shell picks up PATH changes from dotfiles.
  if [ -x "$volta_cmd" ]; then
    "$volta_cmd" install "node@${NODE_VERSION}"
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

  # Install scripts stay off (~/.npmrc ignore-scripts=true, linked before this
  # runs): none of the globals installed here needs one (zsh/README.md).
  if "$npm_cmd" list -g --depth=0 "$package" >/dev/null 2>&1; then
    "$npm_cmd" update --global "$package"
  else
    "$npm_cmd" install --global "$package"
  fi
}

# install_go_tools [--except <module>]... -- the Go tools in bin/go-tools.txt,
# at the versions bin/go-cooldown let through, never @latest. See
# bin/go-cooldown.md.
install_go_tools() {
  if ! command -v go >/dev/null 2>&1; then
    printf "warning: go is not installed yet (cannot install the Go tools)\n" >&2
    return 1
  fi

  "${DOTFILES_DIR}/bin/go-tools-install" "$@"
}

install_or_upgrade_gcloud() {
  local gcloud_bin
  gcloud_bin="${HOME}/google-cloud-sdk/bin/gcloud"

  if [ -x "$gcloud_bin" ] || command -v gcloud >/dev/null 2>&1; then
    return 0
  fi

  local asset sha tmp rc=0
  case "$(pin_platform)" in
    DARWIN_ARM64) asset=darwin-arm ;;
    DARWIN_X64) asset=darwin-x86_64 ;;
    LINUX_X64) asset=linux-x86_64 ;;
    LINUX_ARM64) asset=linux-arm ;;
  esac
  sha="$(pinned_sha256 GCLOUD)" || return 1

  # zsh/lang.zsh lazy-loads the SDK from ~/google-cloud-sdk. The flags are
  # what sdk.cloud.google.com's --disable-prompts did: no rc edits, no prompts.
  tmp="$(mktemp -d)"
  if fetch_verified \
    "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${GCLOUD_VERSION}-${asset}.tar.gz" \
    "$sha" "${tmp}/gcloud.tar.gz" &&
    tar -xzf "${tmp}/gcloud.tar.gz" -C "$HOME"; then
    "${HOME}/google-cloud-sdk/install.sh" --quiet --usage-reporting=false \
      --path-update=false --command-completion=false || rc=$?
  else
    rc=1
  fi
  rm -rf "$tmp"
  return "$rc"
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

# Install git's contrib/diff-highlight to $HOME/.local/bin so tig can spawn it
# via `set diff-highlight = true`. Debian/Ubuntu's git package ships only the
# Perl source under /usr/share/doc/git/contrib/; the Makefile inlines
# DiffHighlight.pm into a standalone script. Linuxbrew git ships it prebuilt.
install_or_upgrade_diff_highlight() {
  local target src brew_git contrib_dir build_dir
  target="${HOME}/.local/bin/diff-highlight"

  if command -v brew >/dev/null 2>&1; then
    brew_git="$(brew --prefix git 2>/dev/null || true)"
    if [ -n "$brew_git" ] && [ -x "${brew_git}/share/git-core/contrib/diff-highlight/diff-highlight" ]; then
      src="${brew_git}/share/git-core/contrib/diff-highlight/diff-highlight"
      mkdir -p "$(dirname "$target")"
      ln -sfn "$src" "$target"
      return 0
    fi
  fi

  contrib_dir="/usr/share/doc/git/contrib/diff-highlight"
  if [ ! -f "${contrib_dir}/diff-highlight.perl" ] ||
    [ ! -f "${contrib_dir}/DiffHighlight.pm" ] ||
    [ ! -f "${contrib_dir}/Makefile" ]; then
    printf "warning: diff-highlight sources not found in %s\n" "$contrib_dir" >&2
    return 1
  fi

  build_dir="$(mktemp -d)"
  cp "${contrib_dir}/diff-highlight.perl" \
    "${contrib_dir}/DiffHighlight.pm" \
    "${contrib_dir}/Makefile" \
    "$build_dir/"
  if ! (cd "$build_dir" && make diff-highlight >/dev/null); then
    printf "warning: failed to build diff-highlight in %s\n" "$build_dir" >&2
    rm -rf "$build_dir"
    return 1
  fi

  mkdir -p "$(dirname "$target")"
  install -m 755 "${build_dir}/diff-highlight" "$target"
  rm -rf "$build_dir"
}

install_or_upgrade_claude() {
  if command -v claude >/dev/null 2>&1; then
    return 0
  fi

  local platform sha tmp rc=0
  # Anthropic's release directory names, mapped one by one like the other
  # installers' assets, so renaming a pin_platform suffix cannot change a URL.
  case "$(pin_platform)" in
    DARWIN_ARM64) platform=darwin-arm64 ;;
    DARWIN_X64) platform=darwin-x64 ;;
    LINUX_X64) platform=linux-x64 ;;
    LINUX_ARM64) platform=linux-arm64 ;;
  esac
  sha="$(pinned_sha256 CLAUDE)" || return 1

  # What claude.ai/install.sh does, minus its first step: it always fetches
  # the newest build and checks it only against a manifest from the same
  # server. Here the binary is the pinned one, checked against pins.sh, and
  # installs itself. ~/.claude config is linked separately by init.
  tmp="$(mktemp -d)"
  if fetch_verified \
    "https://downloads.claude.ai/claude-code-releases/${CLAUDE_VERSION}/${platform}/claude" \
    "$sha" "${tmp}/claude"; then
    chmod +x "${tmp}/claude"
    "${tmp}/claude" install "$CLAUDE_VERSION" || rc=$?
  else
    rc=1
  fi
  rm -rf "$tmp"
  return "$rc"
}
