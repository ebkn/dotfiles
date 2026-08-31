ENABLE_CORRECTION="true"

# Start Tmux
# /opt/homebrew/bin is added in .zshenv (needed by non-interactive shells too)
# tmuxを自動起動し、tmux終了時にシェルも終了する
[[ -z "$TMUX" ]] && tmux -u && exit

# Module order is mostly alphabetical, but three lines below are not free to
# move. ssh-agent/gpg/path come first because later modules and the prompt need
# what they export. And alias.zsh must precede git.zsh: zsh expands aliases when
# it *parses* a function body, so `alias mkdir='mkdir -p'` is what turns the
# `mkdir -p` calls inside gw() into `mkdir -p -p`. Load git.zsh first and those
# functions are defined differently -- silently, and only visible in
# `print -r -- $functions[gw]`.
source "$HOME/dotfiles/zsh/ssh-agent.zsh"
source "$HOME/dotfiles/zsh/gpg.zsh"
source "$HOME/dotfiles/zsh/path.zsh"
source "$HOME/dotfiles/zsh/.p10k.zsh"
source "$HOME/dotfiles/zsh/alias.zsh"
source "$HOME/dotfiles/zsh/completion.zsh"
source "$HOME/dotfiles/zsh/directory.zsh"
source "$HOME/dotfiles/zsh/git.zsh"
source "$HOME/dotfiles/zsh/history.zsh"
source "$HOME/dotfiles/zsh/lang.zsh"
source "$HOME/dotfiles/zsh/plugin.zsh"
source "$HOME/dotfiles/zsh/ssh.zsh"
source "$HOME/dotfiles/zsh/update.zsh"

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
