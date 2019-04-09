################################
# check speed for starting zsh
# $ time ( zsh -i -c exit )
# zmodload zsh/zprof && zprof
###############################

# start tmux
[[ -z "$TMUX" ]] && tmux

export LANG=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export ZSH=~/.oh-my-zsh
export TERM=xterm-256color

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
  # The next line updates PATH for the Google Cloud SDK.
  if [ -f '~/google-cloud-sdk/path.zsh.inc' ]; then source '~/google-cloud-sdk/path.zsh.inc'; fi
  # The next line enables shell command completion for gcloud.
  if [ -f '~/google-cloud-sdk/completion.zsh.inc' ]; then source '~/google-cloud-sdk/completion.zsh.inc'; fi
else
fi

# Settings for fzf
export PATH="$PATH:$HOME/.fzf/bin"
export FZF_DEFAULT_COMMAND='ag --hidden -g ""'
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
alias l='ls -la'
alias c='clear'
alias rm='rmtrash'
alias mv='mv -i'
alias cp='cp -i'
alias dotfiles='cd ~/dotfiles'
alias zshrc='vim ~/.zshrc'
alias tree='tree -a -I "\.DS_Store|\.git|\.svn|node_modules|vendor|tmp|volumes" -N -A -C'
alias memory='top -o rsize'
alias cpu='top -o cpu'
# history of zsh
alias his='cat ~/.zsh_history'
alias myst='sudo mysql.server start'
# aliases for git, Github
alias ga='git add'
alias gap='git add -p'
alias gc='git commit -v -m'
alias gca='git commit --amend'
alias gst='git status'
alias gd='git diff'
alias current_branch='git rev-parse --abbrev-ref HEAD'
alias gco='git checkout `git branch -a | peco | sed -e "s/\* //g" | awk "{print \$1}"`'
alias gpull='git pull origin `git rev-parse --abbrev-ref HEAD`'
alias gf='git fetch'
alias gpush='git push origin `git rev-parse --abbrev-ref HEAD`'
alias gdmerged='git branch --merged master | grep -vE "^\*|master|develop|staging$" | xargs -I % git branch -d %'
[ `uname` = "Linux" ] && export PATH="$PATH:$HOME/hub-linux-arm64-2.6.0/bin/hub"
alias github="hub browse"
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
if [ `uname` = "Darwin" ]; then
  alias cat='bat --theme=TwoDark' # This requires `brew install bat`
  alias sed='gsed' # This requires `brew install gnu-sed`
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
fi
# translatin
alias en='trans ja:en "$@"'
alias ja='trans en:ja "$@"'

# history
HISTFILE=~/.zsh_history
HISTSIZE=100000
SAVEHIST=100000
HISTTIMEFORMAT='%Y-%m-%d T%T%z '
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
