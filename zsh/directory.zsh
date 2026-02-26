setopt auto_cd
setopt auto_pushd
setopt pushd_ignore_dups
setopt pushdminus

alias -g ...='../..'
alias -g ....='../../..'
alias -g .....='../../../..'
alias -g ......='../../../../..'

# Update tmux window title with unique pane directories
if [[ -n "$TMUX" ]]; then
  _tmux_update_pane_titles() {
    tmux-pane-titles 2>/dev/null
  }
  chpwd_functions+=(_tmux_update_pane_titles)
  _tmux_update_pane_titles  # set title on shell startup
fi
