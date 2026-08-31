# Git: aliases, the worktree workflow (gw / gdmerged / open-worktree-tabs) and
# the ghq repository picker bound to ^g.
#
# Anything that reads or writes a repository belongs here rather than in
# alias.zsh. gw and gdmerged between them are most of this file.
#
# `gs` (fzf branch switch) is deliberately NOT here: it sits in the `uname` case
# at the end of alias.zsh because it needs gsed on macOS and sed on Linux, and
# moving it would add a third `uname` fork to shell startup. It stays there
# until that duplication is dealt with on its own.

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

  # No argument: fuzzy-pick an existing worktree (excluding main) and cd into it.
  if [[ -z "$input" ]]; then
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
      return 0
    fi
    # --no-preview overrides the global FZF_DEFAULT_OPTS file/dir preview.
    # --with-nth=1,2 hides the absolute path column; --nth=1,2 lets users
    # search by branch or relative path; --accept-nth=3 returns the absolute
    # path on selection so `cd` works regardless of $PWD.
    local selected
    selected=$(fzf --reverse --no-preview \
                   --delimiter=$'\t' --with-nth=1,2 --nth=1,2 --accept-nth=3 \
                   --prompt='worktree> ' <<< "$entries") || return 0
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
  local worktree_dir="$root_dir/git-worktrees"

  local branch_name worktree_name worktree_path
  local pr_url_pattern='^https?://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)'

  if [[ "$input" =~ $pr_url_pattern ]]; then
    # PR URL: resolve the head branch via gh, fetch it, and create a worktree
    # checked out on that existing branch (rather than creating a new one).
    if ! (( $+commands[gh] )); then
      echo "Error: gh CLI is required to handle PR URLs" >&2
      return 1
    fi

    local pr_owner="${match[1]}"
    local pr_repo="${match[2]}"
    local pr_number="${match[3]}"

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

    if ! branch_name=$(gh pr view "$input" --json headRefName --jq .headRefName); then
      echo "Error: failed to fetch PR info from $input" >&2
      return 1
    fi
    if [[ -z "$branch_name" ]]; then
      echo "Error: could not parse PR info from $input" >&2
      return 1
    fi

    worktree_name="${branch_name//\//-}"
    worktree_path="$worktree_dir/$worktree_name"

    # Hard error on name collision: silently reusing a stale local branch can
    # check out completely unrelated commits.
    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
      echo "Error: local branch '$branch_name' already exists" >&2
      echo "Delete it first: git branch -D '$branch_name'" >&2
      return 1
    fi

    echo "Fetching PR #$pr_number ($branch_name)..."
    git fetch origin "pull/$pr_number/head:$branch_name" || return 1

    echo "Creating worktree for PR #$pr_number ($branch_name) at '$worktree_path'"
    # LFS の smudge（巨大ファイルの物理コピー）が worktree 作成を数秒〜十数秒遅くするためスキップする。
    # LFS ファイルはポインタのまま checkout されるので、必要になった worktree でだけ `git lfs pull` する。
    # hooksPath も無効化する: リポジトリの post-checkout フック（git lfs post-checkout / dedup）が
    # ポインタを実体に置き換えてしまい、index の stat が古いまま git status が dirty になるため。
    GIT_LFS_SKIP_SMUDGE=1 git -c core.hooksPath=/dev/null worktree add "$worktree_path" "$branch_name" || return 1
  else
    # Branch name: create a brand-new branch alongside the worktree.
    branch_name="$input"
    worktree_name="${branch_name//\//-}"
    worktree_path="$worktree_dir/$worktree_name"

    echo "Creating worktree for branch '$branch_name' at '$worktree_path'"
    # LFS smudge / hooksPath をスキップする理由は PR URL 側の分岐のコメントを参照
    GIT_LFS_SKIP_SMUDGE=1 git -c core.hooksPath=/dev/null worktree add -b "$branch_name" "$worktree_path" || return 1
  fi

  local worktree_copy_file=".worktree-copy"

  # Copy files specified in .worktree-copy
  if [ -f "$root_dir/$worktree_copy_file" ]; then
    echo "Copying files..."
    while IFS= read -r file || [ -n "$file" ]; do
      # Skip empty lines and comments
      [[ -z "$file" || "$file" =~ ^[[:space:]]*# ]] && continue

      # Trim whitespace
      file=$(echo "$file" | xargs)

      if [ -e "$root_dir/$file" ]; then
        local src_path="$root_dir/$file"
        local dst_path="$worktree_path/$file"

        # Skip files tracked by Git LFS (filter=lfs in .gitattributes)
        if [ -d "$src_path" ] && [ ! -L "$src_path" ]; then
          mkdir -p "$dst_path"

          while IFS= read -r entry; do
            local rel_path="${entry#$root_dir/}"
            local rel_dst_path="$worktree_path/$rel_path"

            if [ -d "$entry" ] && [ ! -L "$entry" ]; then
              mkdir -p "$rel_dst_path"
              continue
            fi

            local attr_output=$(git -C "$root_dir" check-attr filter -- "$rel_path" 2>/dev/null)
            if [[ "$attr_output" == *": filter: lfs" ]]; then
              echo "  Skipped (git-lfs): $rel_path"
              continue
            fi

            mkdir -p "$(dirname "$rel_dst_path")"
            # Use `command cp` to bypass `alias cp='cp -i -r'` in this repo.
            command cp -R "$entry" "$rel_dst_path"
          done < <(find "$src_path" -mindepth 1)

          echo "  Copied: $file"
        else
          local attr_output=$(git -C "$root_dir" check-attr filter -- "$file" 2>/dev/null)
          if [[ "$attr_output" == *": filter: lfs" ]]; then
            echo "  Skipped (git-lfs): $file"
            continue
          fi

          # Create directory structure if needed
          local target_dir=$(dirname "$dst_path")
          mkdir -p "$target_dir"

          # Copy file or symlink. Use `command cp` to bypass the `cp` alias.
          command cp -R "$src_path" "$dst_path"
          echo "  Copied: $file"
        fi
      else
        echo "  Warning: $file not found in root directory"
      fi
    done < "$root_dir/.worktree-copy"
  fi

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

  local merged_branches=$(git branch --merged "$current_branch" | sed 's/^[*+ ]*//' | grep -v -E "^($current_branch|develop|staging)$")

  if [ -z "$merged_branches" ]; then
    echo "No merged branches found."
    return
  fi

  echo "Found merged branches:"
  echo "$merged_branches"
  echo

  # Use here-string (not pipe) so the loop runs in the current shell and
  # stdin stays free for the interactive prompt below.
  while IFS= read -r branch; do
    # Skip if empty or protected branch
    if [ -z "$branch" ] || [ "$branch" = "main" ] || [ "$branch" = "master" ] || [ "$branch" = "develop" ] || [ "$branch" = "staging" ]; then
      echo "Skipping protected/empty branch: '$branch'"
      continue
    fi

    echo "Processing branch: $branch"

    # Resolve associated worktree (if any) before the prompt so the path can
    # be shown in the confirmation message.
    local worktree_path=""
    local temp_file=$(mktemp)
    git worktree list --porcelain > "$temp_file" 2>/dev/null

    local current_path=""
    while IFS= read -r line; do
      case "$line" in
        "worktree "*)
          current_path="${line:9}"
          ;;
        "branch refs/heads/$branch")
          worktree_path="$current_path"
          break
          ;;
      esac
    done < "$temp_file"
    /bin/rm -f "$temp_file"

    # Auto-delete only when the upstream is gone (PR merged and remote
    # branch already pruned). Anything else — including research worktrees
    # with no commits — gets a y/n prompt so it isn't lost by accident.
    local upstream_track
    upstream_track=$(git for-each-ref --format='%(upstream:track)' "refs/heads/$branch")

    if [[ "$upstream_track" != *"[gone]"* ]]; then
      local hint=""
      [ -n "$worktree_path" ] && hint=" [worktree: $worktree_path]"
      if ! read -q "?  delete '$branch'$hint? [y/N] " </dev/tty; then
        echo
        echo "  skipped: $branch"
        echo
        continue
      fi
      echo
    fi

    # Delete the branch
    if git branch -d "$branch" 2>/dev/null; then
      echo "✓ Deleted branch: $branch"
    else
      echo "✗ Failed to delete branch: $branch"
    fi

    if [ -n "$worktree_path" ]; then
      echo "✓ Found worktree for $branch: $worktree_path"
      # Skip removal if worktree has untracked files
      local untracked=$(git -C "$worktree_path" ls-files --others --exclude-standard 2>/dev/null)
      if [ -n "$untracked" ]; then
        echo "⚠ Skipping worktree removal (has untracked files): $worktree_path"
      elif git worktree remove "$worktree_path" 2>/dev/null; then
        echo "✓ Removed worktree: $worktree_path"
        if git branch -d "$branch" 2>/dev/null; then
          echo "✓ Deleted branch after worktree removal: $branch"
        elif git branch -D "$branch" 2>/dev/null; then
          echo "✓ Force-deleted branch after worktree removal: $branch"
        fi
      elif git worktree remove --force "$worktree_path" 2>/dev/null; then
        echo "✓ Force-removed worktree: $worktree_path"
        if git branch -d "$branch" 2>/dev/null; then
          echo "✓ Deleted branch after worktree removal: $branch"
        elif git branch -D "$branch" 2>/dev/null; then
          echo "✓ Force-deleted branch after worktree removal: $branch"
        fi
      else
        echo "✗ Failed to remove worktree: $worktree_path"
      fi
    else
      echo "No worktree found for branch: $branch"
    fi
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
