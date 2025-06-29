ENABLE_CORRECTION="true"

source "$HOME/dotfiles/zsh/path.zsh"
source "$HOME/dotfiles/zsh/.p10k.zsh"
source "$HOME/dotfiles/zsh/alias.zsh"
source "$HOME/dotfiles/zsh/completion.zsh"
source "$HOME/dotfiles/zsh/directory.zsh"
source "$HOME/dotfiles/zsh/history.zsh"
source "$HOME/dotfiles/zsh/lang.zsh"
source "$HOME/dotfiles/zsh/plugin.zsh"

# Settings for fzf
export FZF_DEFAULT_COMMAND="rg --files --hidden --smart-case --glob='!.git/*'"

# display
setopt print_exit_value

# no peep (except general beep for notifications)
unsetopt BEEP
setopt no_hist_beep
setopt no_list_beep

# warning before delete
setopt rm_star_wait

# ctags
# disable no matches found error
setopt nonomatch

#####################################
# to check starting time of zsh,
# uncomment following commands.
# (please check also .zshenv)
#####################################
# if (which zprof > /dev/null) ;then
#   zprof | less
# fi
####################################
