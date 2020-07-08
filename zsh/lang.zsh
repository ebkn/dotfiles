# lazyload
if [ `uname` = 'Darwin' ]; then
  function rbenv() {
    unset -f rbenv
    eval "$(rbenv init - --no-rehash)"
    rbenv "$@"
  }

  function pyenv() {
    unset -f pyenv
    eval "$(pyenv init - --no-rehash)"
    pyenv "$@"
  }

  function swiftenv() {
    unset -f swiftenv
    eval "$(swiftenv init - --no-rehash)"
    swiftenv "$@"
  }

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
fi


