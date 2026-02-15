# lazyload
if [ `uname` = 'Darwin' ]; then
  # direnv
  ENVRC_PATH=".envrc"
  if [[ -a "$ENVRC_PATH" ]]; then
    eval "$(direnv hook zsh)"
  fi

  # ruby
  function rbenv() {
    unfunction "$0"
    eval "$(rbenv init - --no-rehash)"
    $0 "$@"
  }

  # python
  function pyenv() {
    unfunction "$0"
    eval "$(pyenv init - --no-rehash)"
    $0 "$@"
  }

  # swift
  function swiftenv() {
    unfunction "$0"
    eval "$(swiftenv init - --no-rehash)"
    $0 "$@"
  }

  # Node.js
  function nvm() {
    unfunction "$0"
    source $(brew --prefix nvm)/nvm.sh
    $0 "$@"
  }
  NVMRC_PATH=".nvmrc"
  if [[ -a "$NVMRC_PATH" ]]; then
    nvm use
  fi

  GCLOUD_SDK_DIR=$HOME/google-cloud-sdk
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
    unfunction "$0"
    complete -C '/usr/local/bin/aws_completer' aws
    aws "$@"
  }
fi
