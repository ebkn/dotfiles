ENABLE_CORRECTION="true"

# Start Tmux
# /opt/homebrew/bin is added in .zshenv (needed by non-interactive shells too)
# tmuxを自動起動し、tmux終了時にシェルも終了する
[[ -z "$TMUX" ]] && tmux -u && exit

# Resolve this file's own directory rather than assuming ~/dotfiles, so a
# checkout anywhere -- a git worktree in particular -- loads *its own* modules.
# Before this, pointing ~/.zshrc at a worktree still loaded the main checkout's
# zsh/, which is the opposite of what testing a change there is for.
#
# ${(%):-%N} rather than $0: $0 is this file only while functionargzero is on
# and posixargzero is off. When it is not, $0 is the shell's own name, and
# ${0:A:h} then resolves it against $PWD -- so every source line below would
# point into whatever directory the shell started in, with no error. %N is the
# script name under all three settings (verified). The guard is there so a
# shell that somehow resolves neither does not start with no configuration at
# all.
DOTFILES="${${(%):-%N}:A:h}"
[[ -d "$DOTFILES/zsh" ]] || DOTFILES="$HOME/dotfiles"

# Module order is mostly alphabetical, but three lines below are not free to
# move. ssh-agent/gpg/path come first because later modules and the prompt need
# what they export. And alias.zsh must precede git.zsh: zsh expands aliases when
# it *parses* a function body, so `alias mkdir='mkdir -p'` is what turns the
# `mkdir -p` calls inside gw() into `mkdir -p -p`. Load git.zsh first and those
# functions are defined differently -- silently, and only visible in
# `print -r -- $functions[gw]`.
source "$DOTFILES/zsh/ssh-agent.zsh"
source "$DOTFILES/zsh/gpg.zsh"
source "$DOTFILES/zsh/path.zsh"
source "$DOTFILES/zsh/.p10k.zsh"
source "$DOTFILES/zsh/alias.zsh"
source "$DOTFILES/zsh/completion.zsh"
source "$DOTFILES/zsh/directory.zsh"
source "$DOTFILES/zsh/git.zsh"
source "$DOTFILES/zsh/history.zsh"
source "$DOTFILES/zsh/lang.zsh"
source "$DOTFILES/zsh/plugin.zsh"
source "$DOTFILES/zsh/ssh.zsh"
source "$DOTFILES/zsh/update.zsh"

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
