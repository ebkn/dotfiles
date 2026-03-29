alias c='clear'
alias l='ls -lahG'
alias mv='mv -i'
alias cp='cp -i -r'
alias mkdir='mkdir -p'

# vim
alias v='nvim'
alias vi='nvim'
alias vim='nvim'

# dotfiles
alias dot='cd ~/dotfiles'
alias zshrc='vim ~/.zshrc'

# requires procs
alias memory='procs --watch --sortd mem '
alias cpu='procs --watch --sortd cpu'

# interactive cd
# requires fzf
fd() {
  local dir
  dir=$(find "${1:-.}" -type d 2> /dev/null | fzf --reverse +m) && cd "$dir"
  if [ "$dir" != "" ]; then
    cd "$dir"
  fi
}

# create Scrapbox page from text
# requires nkf(brew install nkf), gsed (or linux sed)
# usage
# $ scrapbox foo.txt
function scrapbox() {
  title=$(cat $1 | head -n 1); \
  body=$(cat "$1" | tail -n +2 | gsed 's/  /\t/g' | gsed 's/&/%26/g'); \
  open https://scrapbox.io/ebiken/${title}?body=${body}
}

# requires tree
alias tree='tree -a -I "\.DS_Store|\.git|\.svn|node_modules|vendor|volumes" -N -A -C'

# requires trash
alias rm='trash'

# terminal image viewer (sixel via ImageMagick, works over SSH+tmux)
# Fits image within terminal bounds, preserving aspect ratio.
imgcat() {
  local pw=$(( $(tput cols) * 9 ))
  local ph=$(( $(tput lines) * 18 ))
  magick "$1" -resize "${pw}x${ph}" sixel:-
}

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

# create a new git worktree
function gw() {
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

  local branch_name="$1"
  if [[ -z "$branch_name" ]]; then
    echo "Error: branch name is required" >&2
    return 1
  fi
  local worktree_name="${branch_name//\//-}"
  local worktree_path="$worktree_dir/$worktree_name"

  # Avoid downloading Git LFS contents when creating the worktree.
  # Large files remain as LFS pointer files until `git lfs pull` / `checkout`.
  echo "Creating worktree for branch '$branch_name' at '$worktree_path' (skip git-lfs smudge)"
  GIT_LFS_SKIP_SMUDGE=1 git worktree add -b "$branch_name" "$worktree_path" || return 1

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

  # Process each merged branch
  echo "$merged_branches" | while read -r branch; do
    # Skip if empty or protected branch
    if [ -z "$branch" ] || [ "$branch" = "main" ] || [ "$branch" = "master" ] || [ "$branch" = "develop" ] || [ "$branch" = "staging" ]; then
      echo "Skipping protected/empty branch: '$branch'"
      continue
    fi

    echo "Processing branch: $branch"

    # Delete the branch
    if git branch -d "$branch" 2>/dev/null; then
      echo "✓ Deleted branch: $branch"
    else
      echo "✗ Failed to delete branch: $branch"
    fi

    # Check and remove associated worktree
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
  done
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

alias dc='docker compose'
alias kc='kubectl'
alias tf='terraform'
export KUBE_EDITOR=nvim

alias python='python3'

# GitHub Copilot CLI (lazy-loaded to avoid ~200ms Node.js fork on every shell startup)
if (( $+commands[github-copilot-cli] )); then
  _copilot_cli_init() {
    unfunction _copilot_cli_init copilot_what-the-shell copilot_git-assist copilot_gh-assist
    eval "$(github-copilot-cli alias -- zsh)"
  }
  copilot_what-the-shell() { _copilot_cli_init; copilot_what-the-shell "$@" }
  copilot_git-assist() { _copilot_cli_init; copilot_git-assist "$@" }
  copilot_gh-assist() { _copilot_cli_init; copilot_gh-assist "$@" }
  alias '??'='copilot_what-the-shell'
  alias 'git?'='copilot_git-assist'
  alias 'gh?'='copilot_gh-assist'
  alias 'wts'='copilot_what-the-shell'
fi

update-all() {
  brew upgrade
  brew upgrade --cask
  zinit ice proto=ssh depth=1
  zinit update --all
  nvim --headless +'CocUpdate' +qa
  nvim --headless +'TSUpdate' +qa
  nvim --headless '+Lazy! sync' +qa
  go install golang.org/x/tools/...@latest
  go install github.com/cweill/gotests/...@latest
  go install github.com/mattn/efm-langserver@latest
  go install github.com/hashicorp/terraform-ls@latest
  go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@latest
  go install github.com/nametake/golangci-lint-langserver@latest
  go install github.com/mikefarah/yq/v4@latest
  go install github.com/x-motemen/ghq@latest
  go install github.com/cloudspannerecosystem/spanner-cli@latest
  go install github.com/aquasecurity/tfsec/cmd/tfsec@latest
  go install github.com/bufbuild/buf-language-server/cmd/bufls@latest
  go install mvdan.cc/gofumpt@latest
  go install tailscale.com/cmd/tailscale{,d}@main
  npm update --location=global
  npm i -g diagnostic-languageserver
  npm i -g markdownlint-cli
  npm i -g textlint
  npm i -g git-delete-squashed
  npm i -g yarn
  npm i -g @openai/codex
  npm i -g @githubnext/github-copilot-cli
  gcloud components update --quiet
}

# SSH wrapper: tmux visual indicator + auto-reconnect with remote tmux reattach.
# Interactive sessions (no remote command) auto-reconnect on disconnect.
# Non-interactive sessions (ssh host 'cmd') fall back to regular ssh.
# Bypass: use `command ssh` to skip this wrapper entirely.
ssh() {
  local ssh_opts=()
  local host=""
  local has_remote_cmd=false
  local skip_next=false
  local found_host=false

  for arg in "$@"; do
    if $skip_next; then
      skip_next=false
      ssh_opts+=("$arg")
      continue
    fi
    case "$arg" in
      -[bcDEeFIiJLlmOopQRSWw])
        skip_next=true
        ssh_opts+=("$arg")
        ;;
      -*)
        ssh_opts+=("$arg")
        ;;
      *)
        if $found_host; then
          has_remote_cmd=true
          break
        fi
        host="$arg"
        found_host=true
        ;;
    esac
  done

  if [ -n "$TMUX" ]; then
    # Everforest dark hard: bg_dim (#1e2326) — slightly darker than bg0
    tmux select-pane -P 'bg=#1e2326'
    tmux set-option -p @ssh_host "${host:-unknown}"
    tmux-pane-titles 2>/dev/null
  fi

  if ! $has_remote_cmd && (( $+commands[autossh] )); then
    # Interactive: auto-reconnect with per-pane remote tmux session.
    # Each local tmux pane gets its own remote session so multiple panes
    # connecting to the same host stay independent. On reconnect, autossh
    # reattaches to the same session via -A (attach-or-create).
    # NOTE: `exit` on the remote destroys the session (last window gone).
    # Closing the local pane or losing the network leaves the remote
    # session detached (shell still running), which autossh reattaches
    # on reconnect. To auto-clean orphaned sessions, set
    # `set -g destroy-unattached on` in the remote tmux.conf.
    local remote_session="main"
    if [ -n "$TMUX_PANE" ]; then
      remote_session="local-${TMUX_PANE#%}"
    fi
    # ControlPath=none: bypass stale ControlMaster sockets that can block reconnection.
    # autossh manages its own reconnection; shared sockets from ControlPersist interfere.
    AUTOSSH_GATETIME=0 autossh -M 0 \
      -o ControlPath=none "${ssh_opts[@]}" -t "$host" \
      "tmux new-session -A -s ${remote_session} 2>/dev/null || exec \$SHELL -l"
  else
    command ssh "$@"
  fi
  local ret=$?
  # Reset terminal state that remote tmux may have left behind on abrupt disconnect
  # (SGR/X10/button-event/all-mouse tracking, bracketed paste, cursor visibility,
  # text attributes). Without this, mouse scroll produces raw escape sequences
  # like "65;61;46M" instead of actual scrolling.
  printf '\e[?9l\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?2004l\e[?25h\e[0m'

  if [ -n "$TMUX" ]; then
    tmux select-pane -P default
    tmux set-option -p -u @ssh_host
    tmux-pane-titles 2>/dev/null
  fi

  return $ret
}

case `uname` in
  "Darwin" ) # requires gnu-sed
    his() {
      print -z $( ([ -n "$ZSH_NAME" ] && fc -l 1 || history) | fzf +s --tac --reverse --no-preview | gsed -r 's/ *[0-9]*\*? *//' | gsed -r 's/\\/\\\\/g')
    }

    gs() {
      local branches branch
      branches=$(git branch --all | grep -v HEAD) &&
      branch=$(echo "$branches" | fzf) &&
      git switch $(echo "$branch" | gsed "s/.* //" | gsed "s#remotes/[^/]*/##")
    }

    alias xcode='open -a xcode .'

    function f() {
      if [ -z "$1" ]; then
        open .
      else
        open "$@"
      fi
    }
  ;;

  "Linux" )
    his() {
      print -z $( ([ -n "$ZSH_NAME" ] && fc -l 1 || history) | fzf +s --tac --no-preview | sed -r 's/ *[0-9]*\*? *//' | sed -r 's/\\/\\\\/g')
    }

    gs() {
      local branches branch
      branches=$(git branch --all | grep -v HEAD) &&
      branch=$(echo "$branches" | fzf) &&
      git switch $(echo "$branch" | sed "s/.* //" | sed "s#remotes/[^/]*/##")
    }
  ;;
esac
