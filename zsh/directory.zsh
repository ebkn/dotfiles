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
  _tmux_set_git_pane_options() {
    local git_dir common_dir branch
    git_dir=$(git rev-parse --git-dir 2>/dev/null) || {
      tmux set-option -p @git_worktree '' 2>/dev/null
      tmux set-option -p @git_branch '' 2>/dev/null
      return
    }
    common_dir=$(git rev-parse --git-common-dir 2>/dev/null)
    branch=$(git branch --show-current 2>/dev/null)

    # Worktree: git-dir differs from common-dir
    if [[ "$git_dir" != "$common_dir" ]]; then
      tmux set-option -p @git_worktree "$branch" 2>/dev/null
    else
      tmux set-option -p @git_worktree '' 2>/dev/null
    fi

    # Branch: skip main/develop/empty
    if [[ -n "$branch" && "$branch" != "main" && "$branch" != "develop" ]]; then
      tmux set-option -p @git_branch "$branch" 2>/dev/null
    else
      tmux set-option -p @git_branch '' 2>/dev/null
    fi
  }
  _tmux_update_pane_titles() {
    _tmux_set_git_pane_options
    tmux-pane-titles 2>/dev/null
  }
  chpwd_functions+=(_tmux_update_pane_titles)
  # Initial title is set by tmux hooks (after-new-window, after-new-session)
  # in .tmux.conf, so no need to call here on shell startup (~20ms saving).
fi
