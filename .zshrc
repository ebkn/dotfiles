export ZSH=/Users/kenichi/.oh-my-zsh

eval "$(rbenv init -)"
eval "$(hub alias -s)"
export PATH="/usr/local/sbin:$PATH"
export PATH="/usr/local/opt/mysql@5.6/bin:$PATH"

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
alias z='vi ~/.zshrc'
alias b='vi ~/.bash_profile'
alias v='vi ~/.vimrc'
alias sz='source ~/.zshrc'
alias sb='source ~/.bash_profile'
alias sv='source ~/.vimrc'

# alias for rails projects
alias ch='cd ~/projects/rails/chat-space'
alias pi='cd ~/projects/rails/pictweet_sample'

# alias for command
alias ll='ls -la'
alias his='cat ~/.zsh_history'

# alias for opening by application
alias at='atom .'
alias f='open .'

# alias for restarting mysql
alias myst='mysql.server start'

#####################################

#####################################
## history ##

# settings of history
HISTFILE=~/.zsh_history
HISTSIZE=1000
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

