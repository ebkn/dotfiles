################################
# check speed for starting zsh
# $ time ( zsh -i -c exit )
# zmodload zsh/zprof && zprof
###############################
# start tmux
[[ -z "$TMUX" ]] && tmux -u

export LANG=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export TERM=xterm-256color

ENABLE_CORRECTION="true"

source "$HOME/dotfiles/zsh/path.zsh"
source "$HOME/dotfiles/zsh/alias.zsh"
source "$HOME/dotfiles/zsh/directory.zsh"
source "$HOME/dotfiles/zsh/history.zsh"
source "$HOME/dotfiles/zsh/plugin.zsh"

# lazyload
if [ `uname` = 'Darwin' ]; then
  function rbenv() {
    unset -f rbenv
    eval "$(rbenv init - --no-rehash)"
    rbenv "$@"
  }

  function goenv() {
    unset -f goenv
    eval "$(goenv init - --no-rehash)"
    goenv "$@"
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
fi

# Settings for fzf
export FZF_DEFAULT_COMMAND='rg --files --hidden --smart-case'
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# display
setopt print_exit_value

# no peep
setopt no_beep
setopt no_hist_beep
setopt no_list_beep

# warning before delete
setopt rm_star_wait

# autocomplete
setopt auto_list
setopt auto_menu

# ctags
# disable no matches found error
setopt nonomatch


# create Scrapbox page from text
# requires nkf(brew install nkf), gsed (or linux sed)
# usage
# $ scrapbox foo.txt
function scrapbox() {
  title=$(cat $1 | head -n 1); \
  body=$(cat "$1" | tail -n +2 | gsed 's/  /\t/g' | gsed 's/&/%26/g'); \
  open https://scrapbox.io/ebiken/${title}?body=${body}
}

#####################################
# check speed for starting zsh
# if (which zprof > /dev/null) ;then
#   zprof | less
# fi
####################################
# fpath+=${ZDOTDIR:-~}/.zsh_functions

# The next line updates PATH for the Google Cloud SDK.
# source '/Users/kenichi/google-cloud-sdk/path.zsh.inc'
# The next line enables shell command completion for gcloud.
# source '/Users/kenichi/google-cloud-sdk/completion.zsh.inc'
