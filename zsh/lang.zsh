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

  GCLOUD_SDK_DIR=$HOME/google-cloud-sdk
  if [ -f $GCLOUD_SDK_DIR/path.zsh.inc ]; then . $GCLOUD_SDK_DIR/path.zsh.inc; fi
  function gcloud() {
    unset -f gcloud
    if [ -f $GCLOUD_SDK_DIR/completion.zsh.inc ]; then . $GCLOUD_SDK_DIR/completion.zsh.inc; fi
    gcloud "$@"
  }

  function kubectl() {
    unset -f kubectl
    source <(kubectl completion zsh)
    kubectl "$@"
  }

  function npm() {
    unset -f npm
    source <(eval `npm completion`)
    npm "$@"
  }
fi
