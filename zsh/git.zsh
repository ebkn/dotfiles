# Git: aliases, the worktree workflow (gw / gdmerged / open-worktree-tabs) and
# the ghq repository picker bound to ^g.
#
# Anything that reads or writes a repository belongs here rather than in
# alias.zsh. gw and gdmerged between them are most of this file.
#

# git
alias gti='git' # typo
alias got='git' # typo
alias ga='git add'
alias gap='git add -p'
alias gbr='git branch --all --format="%(HEAD) %(color:yellow)%(refname:short)%(color:reset) - %(contents:subject) %(color:green)(%(committerdate:relative)) [%(authorname)]" --sort=-committerdate'
alias gc='git commit -v -m'
alias gca='git commit --amend'
alias gst='git status'
alias gd='git diff --word-diff-regex="\w+"'
alias gf='git fetch'
alias current_branch='git rev-parse --abbrev-ref HEAD'
alias gsc='git switch -c'

# Fuzzy-switch branches, local or remote.
#
# This lived in alias.zsh's `uname` case until the gsed/sed split that put it
# there was removed -- both substitutions are basic REs that every sed accepts,
# so there was never anything platform-specific about it.
gs() {
  local branches branch
  branches=$(git branch --all | grep -v HEAD) &&
  branch=$(echo "$branches" | fzf) &&
  git switch $(echo "$branch" | sed "s/.* //" | sed "s#remotes/[^/]*/##")
}
alias gpull='git pull origin `git rev-parse --abbrev-ref HEAD` --recurse-submodules'
alias gpush='git push origin `git rev-parse --abbrev-ref HEAD`'
gpushf() {
  local branch=$(git rev-parse --abbrev-ref HEAD)
  if [[ "$branch" =~ ^(main|master|develop|staging)$ ]]; then
    echo "Error: force-push to '$branch' is not allowed." >&2
    return 1
  fi
  git push origin "$branch" --force-with-lease
}

# --- worktree workflow -----------------------------------------------------
#
# gw() creates or picks a worktree; gdmerged() deletes the ones whose branches
# are merged. Both used to be one long function each, which hid how much they
# share -- notably the `git worktree list --porcelain` parse below, which
# gdmerged open-coded through a temp file.
#
# Everything named `_gw_*` / `_gdmerged_*` is an implementation detail of the
# function it is named after; nothing else calls them.

# Print the path of the worktree that has <branch> checked out, and return 1
# when no worktree does. `git worktree list --porcelain` emits one paragraph
# per worktree with the "worktree <path>" line first, so the branch line always
# refers to the path most recently seen.
_git_worktree_for_branch() {
  local branch=$1 line current=""
  while IFS= read -r line; do
    case "$line" in
      "worktree "*)                 current="${line#worktree }" ;;
      "branch refs/heads/$branch")  print -r -- "$current"; return 0 ;;
    esac
  done < <(git worktree list --porcelain 2>/dev/null)
  return 1
}

# The settings both `git worktree add` call sites need, kept in one place
# because the reasons are long enough that two copies would drift.
#
# LFS の smudge（巨大ファイルの物理コピー）が worktree 作成を数秒〜十数秒遅くするためスキップする。
# LFS ファイルはポインタのまま checkout されるので、必要になった worktree でだけ `git lfs pull` する。
# hooksPath も無効化する: リポジトリの post-checkout フック（git lfs post-checkout / dedup）が
# ポインタを実体に置き換えてしまい、index の stat が古いまま git status が dirty になるため。
_gw_worktree_add() {
  GIT_LFS_SKIP_SMUDGE=1 git -c core.hooksPath=/dev/null worktree add "$@"
}

# Fuzzy-pick an existing worktree (excluding main) and print its absolute path.
# Returns 1 when there is nothing to pick or the user cancelled.
_gw_pick_worktree() {
  # Resolve the main repo root so worktree paths can be rendered relative to it.
  local main_root
  main_root=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  main_root="${main_root%/.git}"

  # Build "<padded_branch>\t<rel_path>\t<abs_path>" lines from `git worktree
  # list`, skipping the main branch. The branch is the bracketed last token
  # ("[name]") when present; bare/detached worktrees have no brackets. The
  # branch column is padded to (max branch length + 4) so all relative paths
  # line up with at least a few spaces of breathing room.
  local entries
  entries=$(git worktree list | awk -v root="$main_root" '
    {
      abs_path = $1
      rel_path = abs_path
      if (root != "" && index(abs_path, root "/") == 1) {
        rel_path = substr(abs_path, length(root) + 2)
      }
      branch = ""
      for (i = 2; i <= NF; i++) {
        if ($i ~ /^\[.+\]$/) {
          branch = substr($i, 2, length($i) - 2)
          break
        }
      }
      if (branch == "") branch = "(detached)"
      if (branch == "main") next
      n++
      branches[n] = branch
      rels[n] = rel_path
      abss[n] = abs_path
      if (length(branch) > max_branch) max_branch = length(branch)
    }
    END {
      pad = max_branch + 4
      for (i = 1; i <= n; i++) {
        printf "%-*s\t%s\t%s\n", pad, branches[i], rels[i], abss[i]
      }
    }')
  if [[ -z "$entries" ]]; then
    echo "No worktrees to pick" >&2
    return 1
  fi

  # --no-preview overrides the global FZF_DEFAULT_OPTS file/dir preview.
  # --with-nth=1,2 hides the absolute path column; --nth=1,2 lets users
  # search by branch or relative path; --accept-nth=3 returns the absolute
  # path on selection so `cd` works regardless of $PWD.
  fzf --reverse --no-preview \
      --delimiter=$'\t' --with-nth=1,2 --nth=1,2 --accept-nth=3 \
      --prompt='worktree> ' <<< "$entries"
}

# Resolve a GitHub PR to a local branch: check it belongs to this repository,
# fetch its head, and print the branch name. The URL is only used for the gh
# query and the error messages -- gw has already parsed it, and re-parsing here
# would put the pattern in two places.
_gw_fetch_pr_branch() {
  local url=$1 pr_owner=$2 pr_repo=$3 pr_number=$4

  if ! (( $+commands[gh] )); then
    echo "Error: gh CLI is required to handle PR URLs" >&2
    return 1
  fi

  # Abort if the PR's repo does not match the current repo's origin. Otherwise
  # `git fetch origin pull/<num>/head` would reach into an unrelated remote.
  # GitHub treats owner/repo case-insensitively, so normalize before comparing.
  local current_repo
  if ! current_repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null); then
    echo "Error: failed to resolve current repository via gh" >&2
    return 1
  fi
  if [[ "${current_repo:l}" != "${pr_owner:l}/${pr_repo:l}" ]]; then
    echo "Error: PR belongs to '$pr_owner/$pr_repo' but current repo is '$current_repo'" >&2
    return 1
  fi

  local branch_name
  if ! branch_name=$(gh pr view "$url" --json headRefName --jq .headRefName); then
    echo "Error: failed to fetch PR info from $url" >&2
    return 1
  fi
  if [[ -z "$branch_name" ]]; then
    echo "Error: could not parse PR info from $url" >&2
    return 1
  fi

  # Hard error on name collision: silently reusing a stale local branch can
  # check out completely unrelated commits.
  if git show-ref --verify --quiet "refs/heads/$branch_name"; then
    echo "Error: local branch '$branch_name' already exists" >&2
    echo "Delete it first: git branch -D '$branch_name'" >&2
    return 1
  fi

  echo "Fetching PR #$pr_number ($branch_name)..." >&2
  git fetch origin "pull/$pr_number/head:$branch_name" >&2 || return 1

  print -r -- "$branch_name"
}

# Copy one entry listed in .worktree-copy into the new worktree, skipping
# anything Git LFS manages (the source holds a pointer, not the file).
_gw_copy_entry() {
  local root_dir=$1 src=$2 dst=$3 label=$4
  local attr_output=$(git -C "$root_dir" check-attr filter -- "$label" 2>/dev/null)
  if [[ "$attr_output" == *": filter: lfs" ]]; then
    echo "  Skipped (git-lfs): $label"
    return 1
  fi
  mkdir -p "$(dirname "$dst")"
  # `command cp` bypasses `alias cp='cp -i -r'`, which would prompt.
  command cp -R "$src" "$dst"
}

# Copy the untracked local files a fresh worktree needs to be usable (.env and
# friends), as listed in .worktree-copy at the main repo root.
_gw_copy_files() {
  local root_dir=$1 worktree_path=$2
  local list="$root_dir/.worktree-copy"
  [ -f "$list" ] || return 0

  echo "Copying files..."
  local file
  while IFS= read -r file || [ -n "$file" ]; do
    # Skip empty lines and comments
    [[ -z "$file" || "$file" =~ ^[[:space:]]*# ]] && continue
    file=$(echo "$file" | xargs)   # trim whitespace

    local src_path="$root_dir/$file"
    local dst_path="$worktree_path/$file"

    if [ ! -e "$src_path" ]; then
      echo "  Warning: $file not found in root directory"
      continue
    fi

    # A real directory is walked entry by entry, so the LFS check applies per
    # file rather than to the directory as a whole. A symlink to one is copied
    # as the link it is.
    if [ -d "$src_path" ] && [ ! -L "$src_path" ]; then
      mkdir -p "$dst_path"
      local entry rel_path
      while IFS= read -r entry; do
        rel_path="${entry#$root_dir/}"
        if [ -d "$entry" ] && [ ! -L "$entry" ]; then
          mkdir -p "$worktree_path/$rel_path"
          continue
        fi
        _gw_copy_entry "$root_dir" "$entry" "$worktree_path/$rel_path" "$rel_path"
      done < <(find "$src_path" -mindepth 1)
      echo "  Copied: $file"
    else
      _gw_copy_entry "$root_dir" "$src_path" "$dst_path" "$file" && echo "  Copied: $file"
    fi
  done < "$list"
}

# create a new git worktree, fuzzy-pick an existing one when called without args,
# or check out a GitHub PR into a new worktree when given a PR URL.
function gw() {
  # ${1:-} rather than $1: gw with no argument is the documented picker path,
  # and a bare $1 makes it an error under `set -u`.
  local input="${1:-}"

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Error: not inside a git repository" >&2
    return 1
  fi

  if [[ -z "$input" ]]; then
    local selected
    selected=$(_gw_pick_worktree) || return 0
    [[ -n "$selected" ]] && cd "$selected"
    return
  fi

  # Resolve the main repository root (not a worktree root).
  # --git-common-dir returns the shared .git directory; its parent is the main repo root.
  local root_dir=$(git rev-parse --path-format=absolute --git-common-dir)
  root_dir="${root_dir%/.git}"

  # Run from the repository root so that worktree paths resolve correctly.
  if [[ "$PWD" != "$root_dir" ]]; then
    echo "Changing directory to repository root: $root_dir"
    cd "$root_dir" || return 1
  fi

  local branch_name banner
  local pr_url_pattern='^https?://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)'
  local -i is_pr=0

  if [[ "$input" =~ $pr_url_pattern ]]; then
    # PR URL: check out the PR's existing head branch rather than creating one.
    is_pr=1
    branch_name=$(_gw_fetch_pr_branch "$input" "${match[1]}" "${match[2]}" "${match[3]}") || return 1
    banner="PR #${match[3]} ($branch_name)"
  else
    branch_name="$input"
    banner="branch '$branch_name'"
  fi

  local worktree_path="$root_dir/git-worktrees/${branch_name//\//-}"
  echo "Creating worktree for $banner at '$worktree_path'"
  if (( is_pr )); then
    _gw_worktree_add "$worktree_path" "$branch_name" || return 1
  else
    _gw_worktree_add -b "$branch_name" "$worktree_path" || return 1
  fi

  _gw_copy_files "$root_dir" "$worktree_path"

  cd "$worktree_path"
}

# Open a wezterm tab for each git worktree (skip the current one)
function open-worktree-tabs() {
  # Use the symlink that always points to the current socket (same as tmux-restore-tabs).
  export WEZTERM_UNIX_SOCKET=~/.local/share/wezterm/default-org.wezfurlong.wezterm

  local worktrees
  worktrees=$(git worktree list --porcelain 2>/dev/null)

  if [[ -z "$worktrees" ]]; then
    echo "Not in a git repository or no worktrees found" >&2
    return 1
  fi

  local current_worktree
  current_worktree=$(git rev-parse --show-toplevel 2>/dev/null)

  # Remember the current pane so we can return focus after spawning tabs.
  local current_pane=$WEZTERM_PANE

  local count=0
  local dir
  while IFS= read -r line; do
    case "$line" in
      "worktree "*)
        dir="${line#worktree }"
        if [[ "$dir" != "$current_worktree" ]]; then
          if [[ ! -d "$dir" ]]; then
            echo "Skipped (not found): $dir" >&2
            continue
          fi
          wezterm cli spawn --pane-id "$current_pane" --cwd "$dir" >/dev/null
          echo "Opened tab: $dir"
          (( count++ ))
        fi
        ;;
    esac
  done <<< "$worktrees"

  if (( count == 0 )); then
    echo "No other worktrees found"
  else
    echo "Opened $count worktree tab(s)"
    wezterm cli activate-pane --pane-id "$current_pane"
  fi
}

# Ask before destroying something. A separate function because the prompt reads
# /dev/tty directly -- the branch list is already on stdin -- so this is the
# only seam a test can answer through. Pinned by zsh/git-worktree.test.zsh.
_gdmerged_confirm() {
  local prompt=$1
  read -q "?$prompt" </dev/tty
}

# Delete <branch>, and the worktree it is checked out in when it has one.
# The worktree has to go first: git refuses `branch -d` while the branch is
# checked out somewhere.
_gdmerged_delete() {
  local branch=$1 worktree_path=$2

  if [ -n "$worktree_path" ]; then
    echo "✓ Found worktree for $branch: $worktree_path"
    # Untracked files in a worktree are, by definition, not recoverable from
    # git. Keep the whole worktree rather than lose them.
    local untracked=$(git -C "$worktree_path" ls-files --others --exclude-standard 2>/dev/null)
    if [ -n "$untracked" ]; then
      echo "⚠ Skipping worktree removal (has untracked files): $worktree_path"
      return 0
    fi
    if git worktree remove "$worktree_path" 2>/dev/null; then
      echo "✓ Removed worktree: $worktree_path"
    elif git worktree remove --force "$worktree_path" 2>/dev/null; then
      echo "✓ Force-removed worktree: $worktree_path"
    else
      echo "✗ Failed to remove worktree: $worktree_path"
      return 1
    fi
  else
    echo "No worktree found for branch: $branch"
  fi

  # -D after -d: the branch is already known to be merged into the current one,
  # so a -d refusal here means git is looking at a different base, not that
  # there is unmerged work.
  if git branch -d "$branch" 2>/dev/null; then
    echo "✓ Deleted branch: $branch"
  elif git branch -D "$branch" 2>/dev/null; then
    echo "✓ Force-deleted branch: $branch"
  else
    echo "✗ Failed to delete branch: $branch"
  fi
}

# delete merged branches (including squashed branches), worktrees
function gdmerged() {
  # Prune admin records for worktrees whose directories were deleted manually
  # (e.g. via `rm`/`trash`). Without this, `git branch -d` refuses to delete
  # the associated branch because git still believes it is checked out at the
  # now-missing path, and `git worktree remove` below errors on the same path.
  echo "Pruning stale worktrees..."
  git worktree prune -v

  echo "Checking for merged branches..."
  local current_branch=$(git rev-parse --abbrev-ref HEAD)
  echo "Current branch: $current_branch"
  echo "Using base branch for merge check: $current_branch"

  local protected='main|master|develop|staging'
  local merged_branches=$(git branch --merged "$current_branch" \
    | sed 's/^[*+ ]*//' | grep -v -E "^($current_branch|$protected)$")

  if [ -z "$merged_branches" ]; then
    echo "No merged branches found."
    return
  fi

  echo "Found merged branches:"
  echo "$merged_branches"
  echo

  # Use here-string (not pipe) so the loop runs in the current shell and
  # stdin stays free for the interactive prompt below.
  local branch worktree_path upstream_track hint
  while IFS= read -r branch; do
    [ -n "$branch" ] || continue

    echo "Processing branch: $branch"

    # Resolve the worktree before the prompt so its path can be shown in the
    # confirmation message.
    worktree_path=$(_git_worktree_for_branch "$branch")

    # Auto-delete only when the upstream is gone (PR merged and remote
    # branch already pruned). Anything else — including research worktrees
    # with no commits — gets a y/n prompt so it isn't lost by accident.
    upstream_track=$(git for-each-ref --format='%(upstream:track)' "refs/heads/$branch")
    if [[ "$upstream_track" != *"[gone]"* ]]; then
      hint=""
      [ -n "$worktree_path" ] && hint=" [worktree: $worktree_path]"
      if ! _gdmerged_confirm "  delete '$branch'$hint? [y/N] "; then
        echo
        echo "  skipped: $branch"
        echo
        continue
      fi
      echo
    fi

    _gdmerged_delete "$branch" "$worktree_path"
    echo
  done <<< "$merged_branches"
}
alias gdsquashed='git-delete-squashed main' # requires npm i -g git-delete-squashed
alias gp='gpull && gf && gdmerged && gdsquashed'
alias gcp='git cherry-pick'
function gtag() {
  local tag
  tag="$1"
  git tag -s -am "$tag" "$tag" && git push origin "$tag"
}

# interactive cd to ghq repository
# requires ghq, fzf
function move_to_repository() {
  local dir
  dir=$(ghq list -p --vcs=git | fzf --reverse --preview='')
  if [ "$dir" != "" ]; then
    cd "$dir"
  fi
  zle accept-line
}
zle -N move_to_repository
bindkey '^g' move_to_repository

# requires github/gh/gh
alias github="gh repo view --web"
alias pr="gh pr create"
