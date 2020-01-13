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
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    nvm "$@"
  }
  NVMRC_PATH=".nvmrc"
  if [[ -a "$NVMRC_PATH" ]]; then
    nvm use
  fi
fi


