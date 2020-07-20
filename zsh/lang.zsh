# lazyload
if [ `uname` = 'Darwin' ]; then
  eval "$(direnv hook zsh)"

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
    if [ -f '~/google-cloud-sdk/path.zsh.inc' ]; then . '~/google-cloud-sdk/path.zsh.inc'; fi
    if [ -f '~/google-cloud-sdk/completion.zsh.inc' ]; then . '~/google-cloud-sdk/completion.zsh.inc'; fi
    gcloud "$@"
  }

  function kubectl() {
    unset -f kubectl
    source <(kubectl completion zsh)
    kubectl "$@"
  }
fi
