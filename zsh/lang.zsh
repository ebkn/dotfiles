# lazyload
# direnv: inline the hook to avoid forking `direnv hook zsh` on every shell startup.
# This registers a chpwd/precmd hook that runs `direnv export zsh` on directory change.
if (( $+commands[direnv] )); then
  _direnv_hook() {
    trap -- '' SIGINT
    eval "$("${commands[direnv]}" export zsh)"
    trap - SIGINT
  }
  typeset -ag precmd_functions
  if (( ! ${precmd_functions[(I)_direnv_hook]} )); then
    precmd_functions=(_direnv_hook $precmd_functions)
  fi
  typeset -ag chpwd_functions
  if (( ! ${chpwd_functions[(I)_direnv_hook]} )); then
    chpwd_functions=(_direnv_hook $chpwd_functions)
  fi
fi

# Node.js (nvm is installed via Homebrew on both macOS and Linux).
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
if command -v brew >/dev/null 2>&1; then
  NVM_BREW_PREFIX="$(brew --prefix nvm 2>/dev/null)"
  if [[ -n "$NVM_BREW_PREFIX" ]] && [[ -f "$NVM_BREW_PREFIX/nvm.sh" ]]; then
    function nvm() {
      unfunction "$0"
      source "$NVM_BREW_PREFIX/nvm.sh"
      $0 "$@"
    }
    NVMRC_PATH=".nvmrc"
    if [[ -a "$NVMRC_PATH" ]]; then
      nvm use
    fi
  fi
fi

# gcloud installer places the SDK under ~/google-cloud-sdk on both OSes.
GCLOUD_SDK_DIR="$HOME/google-cloud-sdk"
if [ -f "$GCLOUD_SDK_DIR/path.zsh.inc" ]; then . "$GCLOUD_SDK_DIR/path.zsh.inc"; fi
function gcloud() {
  unfunction "$0"
  if [ -f "$GCLOUD_SDK_DIR/completion.zsh.inc" ]; then . "$GCLOUD_SDK_DIR/completion.zsh.inc"; fi
  $0 "$@"
}

function kubectl() {
  unfunction "$0"
  source <(kubectl completion zsh)
  $0 "$@"
}

function npm() {
  unfunction "$0"
  source <(eval `npm completion`)
  $0 "$@"
}

function aws() {
  local aws_completer_path
  unfunction "$0"
  aws_completer_path="$(command -v aws_completer 2>/dev/null)"
  if [[ -n "$aws_completer_path" ]]; then
    complete -C "$aws_completer_path" aws
  fi
  aws "$@"
}
