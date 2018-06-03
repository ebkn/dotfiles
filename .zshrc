export LANG=ja_JP.UTF-8

# tmux起動
[[ -z "$TMUX" && ! -z "$PS1" ]] && exec tmux -u

export ZSH=/Users/kenichi/.oh-my-zsh
export LANG=ja_JP.UTF-8
export LC_CTYPE=ja_JP.UTF-8
export TERM=xterm-256color

eval "$(rbenv init -)"
eval "$(hub alias -s)"
eval "$(nodenv init -)"
eval "$(goenv init -)"
eval "$(pyenv init -)"
if which swiftenv > /dev/null; then eval "$(swiftenv init -)"; fi

export PATH="/usr/local/sbin:$PATH"
export PATH="/usr/local/opt/mysql@5.6/bin:$PATH"
export PGDATA=/usr/local/var/postgres
export PATH=$PATH:/Users/kenichi/.nodebrew/current/bin
export PATH="/usr/local/bin/code:$PATH"
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
export GOPATH=$HOME/go
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/tools
export PATH=$PATH:$ANDROID_HOME/platform-tools
export PATH=/Applications/Postgres.app/Contents/Versions/latest/bin:$PATH

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

## autocomplete ##
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
alias f='open .'
alias xc='open -a xcode .'
alias mi='mine .'
alias vc='code .'
alias myst='sudo mysql.server start'
# alias pgst='pg_ctl start -D /usr/local/var/postgres'
alias defaultlocalserver='cd /Library/WebServer/Documents/'
alias localserver='cd ~/projects/local/'
alias apacheconfig='sudo vim /private/etc/apache2/httpd.conf'
alias apachelog='tail -n 100 /private/var/log/apache2/error_log'
alias st-list='speedtest-cli --list | grep Tokyo'
alias st-exec='(){ speedtest-cli --server $1 --simple }'
alias his='cat ~/.zsh_history'
alias ctags=/usr/local/Cellar/ctags/5.8_1/bin/ctags
# aliases for git
alias ga='git add'
alias gc='git commit'
alias gst='git status'
alias gb='git branch'
alias gc='git checkout'
alias gpull='git pull'
alias gpush='git push'
alias gcp='git cherry-pick'
# aliases for rails
alias rs='bundle exec rails s'
alias rc='bundle exec rails c'

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

# Settings for gcp
# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/kenichi/google-cloud-sdk/path.zsh.inc' ]; then source '/Users/kenichi/google-cloud-sdk/path.zsh.inc'; fi
# The next line enables shell command completion for gcloud.
if [ -f '/Users/kenichi/google-cloud-sdk/completion.zsh.inc' ]; then source '/Users/kenichi/google-cloud-sdk/completion.zsh.inc'; fi
