export LANG=ja_JP.UTF-8
export LC_CTYPE=ja_JP.UTF-8
export ZSH=~/.oh-my-zsh
export TERM=xterm-256color

[[ -z "$TMUX" && ! -z "$PS1" ]] && exec tmux -u

eval "$(rbenv init -)"
eval "$(goenv init -)"
eval "$(pyenv init -)"
eval "$(swiftenv init -)"

export PATH="/usr/local/sbin:$PATH"
export PATH="/usr/local/opt/mysql@5.6/bin:$PATH"
export PATH=/usr/local/opt/mysql@5.7/bin:$PATH
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
export PGDATA=/usr/local/var/postgres
export PATH="/usr/local/bin/code:$PATH"
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
export GOPATH=$HOME/go
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/tools
export PATH=$PATH:$ANDROID_HOME/platform-tools
export PATH=/Applications/Postgres.app/Contents/Versions/latest/bin:$PATH
# export FZF_DEFAULT_COMMAND='ag --hidden -g ""'

# Settings for fzf
# [ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Settings for theme
ZSH_THEME="robbyrussell"
# ZSH_THEME="bullet-train"
# ZSH_THEME="spaceship" # too late
# ZSH_THEME="avit"

plugins=(osx zsh-syntax-highlighting zsh-256color zsh-autosuggestions)
source $ZSH/oh-my-zsh.sh

# Settings for pure theme # git branch is difficult to see
# ZSH_THEME=""
# autoload -U promptinit; promptinit
# prompt pure

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
alias ll='ls -la'
alias c='clear'
alias cat='ccat'
alias tree='tree -a -I "\.DS_Store|\.git|\.svn|node_modules|vendor" -N -A -C'
alias ql='qlmanage -p "$@" >& /dev/null'
alias xc='open -a xcode .'
alias mi='mine .'
alias vc='code .'
alias myst='sudo mysql.server start'
# alias pgst='pg_ctl start -D /usr/local/var/postgres'
alias defaultlocalserver='cd /Library/WebServer/Documents/'
alias localserver='cd ~/projects/local/'
alias apacheconfig='sudo vim /private/etc/apache2/httpd.conf'
alias apachelog='tail -n 100 /private/var/log/apache2/error_log'
alias his='cat ~/.zsh_history'
alias ctags=/usr/local/Cellar/ctags/5.8_1/bin/ctags
# aliases for git
alias ga='git add'
alias gc='git commit -v -m'
alias gca='git commit --amend'
alias gst='git status'
alias gd='git diff'
alias gb='git branch -a'
alias gco='git checkout'
alias gpull='git pull'
alias gf='git fetch'
alias gpush='git push'
alias gcp='git cherry-pick'
alias gcleanbranch="git branch --merged master | grep -vE '^\*|master$|develop$' | xargs -I % git branch -d %"
alias github="hub browse"
# aliases for rails
alias rs='bundle exec rails s'
alias rc='bundle exec rails c'
alias rcs='bundle exec rails c -s'
function f() {
  if [ -z "$1" ]; then
    open .
  else
    open "$@"
  fi
}

# history
HISTFILE=~/.zsh_history
HISTSIZE=1000
SAVEHIST=1000
HISTTIMEFORMAT='%Y-%m-%d T%T%z '
setopt extended_history
setopt hist_no_store
setopt hist_expand
setopt inc_append_history
setopt hist_save_no_dups
setopt share_history
setopt hist_ignore_dups
setopt hist_ignore_all_dups

# Settings for gcp
# The next line updates PATH for the Google Cloud SDK.
if [ -f '~/google-cloud-sdk/path.zsh.inc' ]; then source '~/google-cloud-sdk/path.zsh.inc'; fi
# The next line enables shell command completion for gcloud.
if [ -f '~/google-cloud-sdk/completion.zsh.inc' ]; then source '~/google-cloud-sdk/completion.zsh.inc'; fi
