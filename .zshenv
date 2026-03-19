#####################################
# to check starting time of zsh,
# uncomment following commands.
# (please check also .zshrc)
#####################################
# zmodload zsh/zprof && zprof
#####################################

# locale
export LANG="en_US.UTF-8"
export LC_COLLATE="en_US.UTF-8"
export LC_CTYPE="en_US.UTF-8"
export LC_MESSAGES="en_US.UTF-8"
export LC_MONETARY="en_US.UTF-8"
export LC_NUMERIC="en_US.UTF-8"
export LC_TIME="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

# Paths and env vars needed by non-interactive shells (e.g. tmux display-popup)
# Use terminal ANSI colors so bat inherits WezTerm's Everforest palette
export BAT_THEME="ansi"

export PATH="$HOME/.local/bin:$PATH"
export FZF_DEFAULT_COMMAND="fzf-files --label"
export FZF_DEFAULT_OPTS="--style=minimal --ansi --tabstop=1 --delimiter=\\t --nth=-1 --accept-nth=-1 --preview='if [ -d {-1} ]; then ls -1 --color=always {-1}; else bat --color=always --style=numbers --line-range=:500 {-1}; fi' --bind=ctrl-d:preview-half-page-down,ctrl-u:preview-half-page-up"

export VOLTA_HOME="$HOME/.volta"
export PATH="$VOLTA_HOME/bin:$PATH"
