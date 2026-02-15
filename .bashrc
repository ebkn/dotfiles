# options
shopt -s autocd  # auto prepend cd before dir name
shopt -s cdspell # autocorrect path
shopt -s cmdhist # save multiple-line commands
shopt -s dotglob # search files with dot
shopt -s extglob # search files with extended pattern

# alias
alias ..="cd .."
alias ...="cd ../.."
alias cp='cp -i'
alias mv='mv -i'
alias v='nvim'
alias vi='nvim'
alias vim='nvim'
alias c='clear'
alias l='ls -lahG'
alias python='python3'

[ -f "$HOME/.docker/init-bash.sh" ] && source "$HOME/.docker/init-bash.sh" # Added by Docker Desktop
