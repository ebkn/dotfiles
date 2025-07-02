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
  dir=$(find ${1:-.} -type d 2> /dev/null | fzf --reverse +m) && cd "$dir"
  if [ "$dir" != "" ]; then
    cd $dir
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
alias gw='git worktree add -b'
alias gpull='git pull origin `git rev-parse --abbrev-ref HEAD` --recurse-submodules'
alias gpush='git push origin `git rev-parse --abbrev-ref HEAD`'
alias gpushf='git push origin `git rev-parse --abbrev-ref HEAD` --force-with-lease'
function gdmerged() {
  echo "Checking for merged branches..."
  local current_branch=$(git rev-parse --abbrev-ref HEAD)
  echo "Current branch: $current_branch"

  # Use main/master as the base for checking merged branches, not current branch
  local base_branch=""
  if git rev-parse --verify refs/heads/main >/dev/null 2>&1; then
    base_branch="main"
  elif git rev-parse --verify refs/heads/master >/dev/null 2>&1; then
    base_branch="master"
  else
    echo "Warning: Could not find main or master branch. Using current branch as base."
    base_branch="$current_branch"
  fi

  echo "Using base branch for merge check: $base_branch"

  local merged_branches=$(git branch --merged "$base_branch" | sed 's/^[*+ ]*//' | grep -v -E "^($current_branch|$base_branch|develop|staging)$")

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
      if git worktree remove "$worktree_path" 2>/dev/null; then
        echo "✓ Removed worktree: $worktree_path"
        # Now delete the branch after removing worktree
        if git branch -d "$branch" 2>/dev/null; then
          echo "✓ Deleted branch after worktree removal: $branch"
        elif git branch -D "$branch" 2>/dev/null; then
          echo "✓ Force-deleted branch after worktree removal: $branch"
        else
          echo "✗ Failed to delete branch after worktree removal: $branch"
        fi
      elif git worktree remove --force "$worktree_path" 2>/dev/null; then
        echo "✓ Force-removed worktree: $worktree_path"
        # Now delete the branch after removing worktree
        if git branch -d "$branch" 2>/dev/null; then
          echo "✓ Deleted branch after worktree removal: $branch"
        elif git branch -D "$branch" 2>/dev/null; then
          echo "✓ Force-deleted branch after worktree removal: $branch"
        else
          echo "✗ Failed to delete branch after worktree removal: $branch"
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
  git tag -s -am $tag $tag && git push origin $tag
}

# interactive cd to ghq repository
# requires ghq, fzf
function move_to_repository() {
  local dir
  dir=$(ghq list -p --vcs=git | fzf --reverse)
  if [ "$dir" != "" ]; then
    cd $dir
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

case `uname` in
  "Darwin" ) # requires gnu-sed
    his() {
      print -z $( ([ -n "$ZSH_NAME" ] && fc -l 1 || history) | fzf +s --tac --reverse | gsed -r 's/ *[0-9]*\*? *//' | gsed -r 's/\\/\\\\/g')
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

    # GitHub Copilot CLI
    eval "$(github-copilot-cli alias -- "$0")"

    update-all() {
      brew upgrade
      brew upgrade --cask
      zinit ice proto=ssh depth=1
      zinit update --all
      nvim +'CocUpdate'
      nvim +'TSUpdate'
      go install golang.org/x/tools/...@latest
      go install github.com/cweill/gotests/...@latest
      go install github.com/mattn/efm-langserver@latest
      go install github.com/hashicorp/terraform-ls@latest
      go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest
      go install github.com/nametake/golangci-lint-langserver@latest
      go install github.com/mikefarah/yq/v4@latest
      go install github.com/x-motemen/ghq@latest
      go install github.com/cloudspannerecosystem/spanner-cli@latest
      go install github.com/aquasecurity/tfsec/cmd/tfsec@latest
      go install github.com/bufbuild/buf-language-server/cmd/bufls@latest
      go install mvdan.cc/gofumpt@latest
      npm update --location=global
      npm i --location=global diagnostic-languageserver
      npm i --location=global markdownlint-cli
      npm i --location=global textlint
      npm i --location=global git-delete-squashed
      npm i --location=global @modelcontextprotocol/server-brave-search
      npm i --location=global yarn
      npm i --location=global corepack # for yarn
      gcloud components update --quiet
    }
  ;;

  "Linux" )
    his() {
      print -z $( ([ -n "$ZSH_NAME" ] && fc -l 1 || history) | fzf +s --tac | sed -r 's/ *[0-9]*\*? *//' | sed -r 's/\\/\\\\/g')
    }

    gs() {
      local branches branch
      branches=$(git branch --all | grep -v HEAD) &&
      branch=$(echo "$branches" | fzf) &&
      git switch $(echo "$branch" | sed "s/.* //" | sed "s#remotes/[^/]*/##")
    }
  ;;
esac
