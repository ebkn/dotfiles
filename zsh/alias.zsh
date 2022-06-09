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
alias tmuxs='tmux source-file ~/.tmux.conf'
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
alias ga='git add'
alias gap='git add -p'
alias gc='git commit -v -m'
alias gca='git commit --amend'
alias gst='git status'
alias gd='git diff --word-diff-regex="\w+"'
alias gf='git fetch'
alias current_branch='git rev-parse --abbrev-ref HEAD'
alias gsc='git switch -c'
alias gpull='git pull origin `git rev-parse --abbrev-ref HEAD` --recurse-submodules'
alias gpush='git push origin `git rev-parse --abbrev-ref HEAD`'
alias gpushf='git push origin `git rev-parse --abbrev-ref HEAD` --force-with-lease'
alias gdmerged='git branch --merged | grep -vE "^\*|main$|master$|develop$|staging$" | xargs -I % git branch -d %'
alias gdsquashed='git-delete-squashed main' # requires npm i -g git-delete-squashed
alias gp='gpull && gf && gdmerged && gdsquashed'
alias gcp='git cherry-pick'
function gtag() {
  local tag
  tag="$1"
  git tag -am $tag $tag && git push origin $tag
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
    alias md='open -a Typora'

    function f() {
      if [ -z "$1" ]; then
        open .
      else
        open "$@"
      fi
    }

    update-all() {
      brew upgrade
      brew upgrade --cask
      zinit ice proto=ssh depth=1
      zinit update --all
      nvim +'call dein#update()' +qall
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
      go install github.com/cweill/gotests/...@latest
      go install github.com/cloudspannerecosystem/spanner-cli@latest
      npm update --location=global
      npm i --location=global diagnostic-languageserver
      npm i --location=global markdownlint-cli
      npm i --location=global textlint
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
