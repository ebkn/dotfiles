export ZSH=/Users/kenichi/.oh-my-zsh

eval "$(rbenv init -)"
eval "$(hub alias -s)"
export PATH="/usr/local/sbin:$PATH"

# mysql
export PATH="/usr/local/opt/mysql@5.6/bin:$PATH"

# postgresql
export PGDATA=/usr/local/var/postgres

# nodebrew
export PATH=$PATH:/Users/kenichi/.nodebrew/current/bin

# vsc
export PATH="/usr/local/bin/code:$PATH"

# pyenv
export PYENV_ROOT="$HOME/.pyenv"
export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"

ZSH_THEME="robbyrussell"

plugins=(git ruby osx bundler brew rails emoji-clock zsh-syntax-highlighting zsh-256color zsh-autosuggestions)

source $ZSH/oh-my-zsh.sh

# display
setopt print_exit_value

# no peep
setopt no_beep
setopt no_hist_beep
setopt no_list_beep

# warning before delete
setopt rm_star_wait

###################################
## autocomplete ##

setopt auto_list
setopt auto_menu
###################################

####################################
## alias ##

# alias for shell settings
alias vi='vim'

# alias for rails projects
alias ch='cd ~/projects/rails/chat-space'
alias pr='cd ~/projects/rails/protospace'
alias pi='cd ~/projects/rails/pictweet_curriculum'
alias mo='cd ~/projects/rails/mooovi_curriculum'

# alias for command
alias ll='ls -la'
alias t='tree'

# alias for opening by application
alias c='code .'
alias f='open .'
alias xc='open -a xcode .'
alias v='vi .'
alias mine='mine .'

# alias for restarting mysql
alias myst='mysql.server start'

# alias for local server
alias deflocalserver='cd /Library/WebServer/Documents/'
alias localserver='cd ~/projects/local/'

# alias for ssh login
alias sshtakaisami='ssh ebinuma@takaisami.mind.meiji.ac.jp'

#####################################

#####################################
## history ##
alias his='cat ~/.zsh_history'

# settings of history
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
HISTTIMEFORMAT='%Y-%m-%dT%T%z '
setopt extended_history
setopt hist_no_store
setopt hist_expand
setopt inc_append_history
setopt hist_save_no_dups
setopt share_history
setopt hist_ignore_dups
setopt hist_ignore_all_dups

#####################################

# swiftenv
if which swiftenv > /dev/null; then eval "$(swiftenv init -)"; fi

# ctags
alias ctags=/usr/local/Cellar/ctags/5.8_1/bin/ctags

# disable no matches found error
setopt nonomatch

