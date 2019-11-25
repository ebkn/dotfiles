################################
# check speed for starting zsh
# $ time ( zsh -i -c exit )
# zmodload zsh/zprof && zprof
###############################
# start tmux
[[ -z "$TMUX" ]] && tmux -u

export LANG=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export ZSH=~/.oh-my-zsh
export TERM=xterm-256color

ENABLE_CORRECTION="true"

export PATH="$PATH:/usr/local/sbin"

if [ `uname` = 'Darwin' ]; then
  # MySQL
  export PATH="$PATH:/usr/local/opt/mysql@5.6/bin"
  export PATH="$PATH:/usr/local/opt/mysql@5.7/bin"
  # PostgreSQL
  export PATH="$PATH:/Applications/Postgres.app/Contents/Versions/latest/bin"
  # Node.js
  export NVM_DIR="$HOME/.nvm"
  NODE_DEFAULT=versions/node/$(cat $NVM_DIR/alias/default)
  export PATH="$PATH:$NVM_DIR/$NODE_DEFAULT/bin" # this requires $ nvm alias default vX.Y.Z
  MANPATH="$PATH:$NVM_DIR/$NODE_DEFAULT/share/man"
  NODE_PATH=$NVM_DIR/$NODE_DEFAULT/lib/node_modules
  export NODE_PATH=${NODE_PATH:A}
  # VScode
  export PATH="$PATH:/usr/local/bin/code"
  # Python
  export PYENV_ROOT="$HOME/.pyenv"
  export PATH="$PATH:$PYENV_ROOT/bin"
  # Go
  export GOPATH=$HOME/go
  export GOENV_ROOT=$HOME/.goenv
  export PATH="$PATH:$GOPATH/bin"
  export PATH="$PATH:$GOENV_ROOT/shims"
  # Android
  export ANDROID_HOME=~/Library/Android/sdk
  export PATH="$PATH:$ANDROID_HOME/tools"
  export PATH="$PATH:$ANDROID_HOME/tools/bin"
  export PATH="$PATH:$ANDROID_HOME/platform-tools"
  export ANDROID_SDK=$ANDROID_HOME
  # Deno
  export PATH="$PATH:/Users/kenichi/.deno/bin"
  # Flutter
  export PATH="$PATH:/Users/kenichi/flutter/bin"
  # protobuf
  export PATH="$PATH:/Users/kenichi/protoc-3.7.1-osx-x86_64/bin"
  # Swift
  export SOURCEKIT_TOOLCHAIN_PATH=/Library/Developer/Toolchains/swift-latest.xctoolchain
  # Rust
  export PATH="$PATH:~/.cargo/env"
  # nsq
  export PATH="$PATH:/usr/local/bin/nsqlookupd"

  # lazyload
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
export PATH="$PATH:$HOME/.fzf/bin"
export FZF_DEFAULT_COMMAND='rg --files --hidden --smart-case'
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Settings for theme
ZSH_THEME="robbyrussell"

# oh-my-zsh plugins
plugins=(osx zsh-syntax-highlighting zsh-256color zsh-autosuggestions)
source $ZSH/oh-my-zsh.sh

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

## alias ##
alias v='vim'
alias vi='vim'
alias tmuxs='tmux source-file ~/.tmux.conf'
alias l='ls -lah'
alias c='clear'
alias rm='rmtrash'
alias mv='mv -i'
alias cp='cp -i'
alias dot='cd ~/dotfiles'
alias zshrc='vim ~/.zshrc'
alias tree='tree -a -I "\.DS_Store|\.git|\.svn|node_modules|vendor|tmp|volumes" -N -A -C'
alias memory='top -o mem'
alias cpu='top -o cpu'
his() {
  print -z $( ([ -n "$ZSH_NAME" ] && fc -l 1 || history) | fzf +s --tac | gsed -r 's/ *[0-9]*\*? *//' | gsed -r 's/\\/\\\\/g')
}
alias myst='sudo mysql.server start'
# aliases for git, Github
alias ga='git add'
alias gap='git add -p'
alias gc='git commit -v -m'
alias gca='git commit --amend'
alias gst='git status'
alias gd='git diff'
alias current_branch='git rev-parse --abbrev-ref HEAD'
alias gco='git checkout `git branch -a | fzf --reverse | sed -e "s/\* //g" | awk "{print \$1}"`'
alias gcob='git checkout -b'
alias gpull='git pull origin `git rev-parse --abbrev-ref HEAD`'
alias gf='git fetch'
alias gpush='git push origin `git rev-parse --abbrev-ref HEAD`'
alias gdmerged='git branch --merged master | grep -vE "^\*|master|develop|staging$" | xargs -I % git branch -d %'
[ `uname` = "Linux" ] && export PATH="$PATH:$HOME/hub-linux-arm64-2.6.0/bin/hub"
alias github="hub browse"
function _move_to_repository() {
  cd $(ghq list -p | fzf --reverse)
  zle reset-prompt
}
zle -N move_to_repository _move_to_repository
bindkey '^g' move_to_repository
function pr() {
  branch_name=$1;\
  template_path=$(git rev-parse --show-toplevel)/.github/PULL_REQUEST_TEMPLATE.md;\ 
  if [ -z ${branch_name} ]; then\
      branch_name='master';\
  fi;\
  hub browse -- compare/${branch_name}'...'$(git symbolic-ref --short HEAD)'?'expand=1'&'body=$(cat ${template_path} | perl -pe 'encode_utf8' | perl -pe 's/([^ 0-9a-zA-Z])/\"%\".uc(unpack(\"H2\",$1))/eg' | perl -pe 's/ /+/g');\
}
# aliases for docker
alias dc='docker-compose'
alias kc='kubectl'
if [ `uname` = "Darwin" ]; then
  # alias sed='gsed' # This requires `brew install gnu-sed`
  alias ql='qlmanage -p "$@" >& /dev/null' # Quick Look
  alias xcode='open -a xcode .'
  # Apache server
  alias defaultapacheserver='cd /Library/WebServer/Documents/'
  alias apacheserver='cd ~/projects/local/'
  alias apacheconfig='sudo vim /private/etc/apache2/httpd.conf'
  alias apachelog='tail -n 100 /private/var/log/apache2/error_log'
  # aliases for rails
  alias rs='bundle exec rails s'
  alias rc='bundle exec rails c'
  alias rcs='bundle exec rails c -s'
  function f() { # open file
    if [ -z "$1" ]; then
      open .
    else
      open "$@"
    fi
  }
  # kubectl completion
  # source <(kubectl completion zsh)
  # source "/usr/local/opt/kube-ps1/share/kube-ps1.sh"
fi
# create Scrapbox page from text
# requires nkf(brew install nkf), gsed (or linux sed)
# usage
# $ scrapbox foo.txt
function scrapbox() {
  title=$(cat $1 | head -n 1); \
  body=$(cat "$1" | tail -n +2 | gsed 's/  /\t/g' | gsed 's/&/%26/g'); \
  open https://scrapbox.io/ebiken/${title}?body=${body}
}
# translatin
alias en='trans ja:en "$@"'
alias ja='trans en:ja "$@"'

# history
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000
export HISTTIMEFORMAT='%Y-%m-%d T%T%z '
setopt extended_history
setopt hist_no_store
setopt hist_expand
setopt inc_append_history
setopt hist_save_no_dups
setopt share_history
setopt hist_ignore_dups
setopt hist_ignore_all_dups


#####################################
# check speed for starting zsh
# if (which zprof > /dev/null) ;then
#   zprof | less
# fi
####################################
fpath+=${ZDOTDIR:-~}/.zsh_functions

# The next line updates PATH for the Google Cloud SDK.
source '/Users/kenichi/google-cloud-sdk/path.zsh.inc'
# The next line enables shell command completion for gcloud.
source '/Users/kenichi/google-cloud-sdk/completion.zsh.inc'
