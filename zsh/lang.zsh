# lazyload
if [ `uname` = 'Darwin' ]; then
  # direnv
  ENVRC_PATH=".envrc"
  if [[ -a "$ENVRC_PATH" ]]; then
    eval "$(direnv hook zsh)"
  fi

  # ruby
  function rbenv() {
    unset -f rbenv
    eval "$(rbenv init - --no-rehash)"
    rbenv "$@"
  }

  # python
  function pyenv() {
    unset -f pyenv
    eval "$(pyenv init - --no-rehash)"
    pyenv "$@"
  }

  # swift
  function swiftenv() {
    unset -f swiftenv
    eval "$(swiftenv init - --no-rehash)"
    swiftenv "$@"
  }

  # Node.js
  function nvm() {
    unset -f nvm
    source $(brew --prefix nvm)/nvm.sh
    nvm "$@"
  }
  NVMRC_PATH=".nvmrc"
  if [[ -a "$NVMRC_PATH" ]]; then
    nvm use
  fi

  function gcloud() {
    unset -f gcloud
    SDK_DIR=$HOME/google-cloud-sdk
    if [ -f $SDK_DIR/path.zsh.inc ]; then . $SDK_DIR/path.zsh.inc; fi
    if [ -f $SDK_DIR/completion.zsh.inc ]; then . $SDK_DIR/completion.zsh.inc; fi
    gcloud "$@"
  }

  function kubectl() {
    unset -f kubectl
    source <(kubectl completion zsh)
    kubectl "$@"
  }
fi
