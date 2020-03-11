# start tmux
[[ -z "$TMUX" ]] && tmux -u

export LANG=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export TERM=xterm-256color

ENABLE_CORRECTION="true"

source "$HOME/dotfiles/zsh/.p10k.zsh"
source "$HOME/dotfiles/zsh/path.zsh"
source "$HOME/dotfiles/zsh/alias.zsh"
source "$HOME/dotfiles/zsh/completion.zsh"
source "$HOME/dotfiles/zsh/directory.zsh"
source "$HOME/dotfiles/zsh/history.zsh"
source "$HOME/dotfiles/zsh/lang.zsh"
source "$HOME/dotfiles/zsh/plugin.zsh"

# Settings for fzf
export FZF_DEFAULT_COMMAND='rg --files --hidden --smart-case'

# display
setopt print_exit_value

# no peep
setopt no_beep
setopt no_hist_beep
setopt no_list_beep

# warning before delete
setopt rm_star_wait

# ctags
# disable no matches found error
setopt nonomatch

# create Scrapbox page from text
# requires nkf(brew install nkf), gsed (or linux sed)
# usage
# $ scrapbox foo.txt
function scrapbox() {
  title=$(cat $1 | head -n 1); \
  body=$(cat "$1" | tail -n +2 | gsed 's/  /\t/g' | gsed 's/&/%26/g'); \
  open https://scrapbox.io/ebiken/${title}?body=${body}
}

# fpath+=${ZDOTDIR:-~}/.zsh_functions

# The next line updates PATH for the Google Cloud SDK.
# source '/Users/kenichi/google-cloud-sdk/path.zsh.inc'
# The next line enables shell command completion for gcloud.
# source '/Users/kenichi/google-cloud-sdk/completion.zsh.inc'

#####################################
# to check starting time of zsh,
# uncomment following commands.
# (please check also .zshenv)
#####################################
# if (which zprof > /dev/null) ;then
#   zprof | less
# fi
####################################
