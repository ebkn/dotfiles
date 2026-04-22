setopt auto_cd
setopt auto_pushd
setopt pushd_ignore_dups
setopt pushdminus

# Emit OSC 7 so WezTerm can track the current working directory.
# Inside tmux, wrap in DCS passthrough so the sequence reaches WezTerm.
_wezterm_osc7() {
  if [[ -n "$TMUX" ]]; then
    printf '\ePtmux;\e\e]7;file://%s%s\a\e\\' "${HOST}" "${PWD}"
  else
    printf '\e]7;file://%s%s\e\\' "${HOST}" "${PWD}"
  fi
}
chpwd_functions+=(_wezterm_osc7)
_wezterm_osc7  # emit for the initial directory

# When over SSH without tmux, emit OSC 2 (terminal title) so the local
# tmux captures it as pane_title. The local set-titles-string displays
# this alongside the host name in the WezTerm tab.
# (Inside remote tmux, set-titles + tmux-pane-titles handle this instead.)
if [[ -n "$SSH_CONNECTION" && -z "$TMUX" ]]; then
  _ssh_set_pane_title() {
    local title="${PWD##*/}"
    local branch
    branch=$(git branch --show-current 2>/dev/null)
    if [[ -n "$branch" ]]; then
      case "$branch" in
        main|develop|staging) ;;
        *) title="b:$branch" ;;
      esac
    fi
    printf '\e]2;%s\a' "$title"
  }
  chpwd_functions+=(_ssh_set_pane_title)
  _ssh_set_pane_title  # emit for the initial directory
fi

alias -g ...='../..'
alias -g ....='../../..'
alias -g .....='../../../..'
alias -g ......='../../../../..'

# Update tmux window title with unique pane directories
if [[ -n "$TMUX" ]]; then
  _tmux_set_git_pane_options() {
    local git_dir common_dir branch
    # --path-format=absolute is required: --git-common-dir normally
    # returns a path relative to --git-dir (e.g. "../.git"), which breaks
    # string comparison against --git-dir's absolute path when cwd is a
    # subdirectory of the repo, misdetecting a normal checkout as a
    # linked worktree. Requires git >= 2.31.
    git_dir=$(git rev-parse --path-format=absolute --git-dir 2>/dev/null) || {
      tmux set-option -p @git_worktree '' 2>/dev/null
      tmux set-option -p @git_branch '' 2>/dev/null
      return
    }
    common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
    branch=$(git branch --show-current 2>/dev/null)

    # Worktree: git-dir differs from common-dir
    if [[ "$git_dir" != "$common_dir" ]]; then
      tmux set-option -p @git_worktree "$branch" 2>/dev/null
    else
      tmux set-option -p @git_worktree '' 2>/dev/null
    fi

    # Branch: skip default-ish branches where the name carries no
    # meaningful signal. tmux-pane-titles falls back to the directory
    # basename when @git_branch is empty.
    case "$branch" in
      ''|main|develop|staging)
        tmux set-option -p @git_branch '' 2>/dev/null
        ;;
      *)
        tmux set-option -p @git_branch "$branch" 2>/dev/null
        ;;
    esac
  }
  _tmux_update_pane_titles() {
    _tmux_set_git_pane_options
    tmux-pane-titles 2>/dev/null
  }
  chpwd_functions+=(_tmux_update_pane_titles)

  # Detect pane structure changes (open/close/split) and update title.
  # Replaces tmux server-side hooks (after-new-window, after-split-window,
  # window-layout-changed) which used run-shell -b and caused SIGSEGV in
  # tty_keys_next due to fork racing with tty input processing.
  # Calling from zsh forks the shell process, not the tmux server — safe.
  _TMUX_PANE_COUNT=""
  _tmux_check_pane_structure() {
    local count
    count=$(tmux display-message -p '#{window_panes}' 2>/dev/null) || return
    [[ "$count" != "$_TMUX_PANE_COUNT" ]] || return
    _TMUX_PANE_COUNT=$count
    _tmux_set_git_pane_options
    tmux-pane-titles 2>/dev/null
  }
  precmd_functions+=(_tmux_check_pane_structure)
fi
