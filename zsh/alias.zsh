alias c='clear'
alias l='ls -lahG'
alias mv='mv -i'
alias cp='cp -i'

# vim
alias v='nvim'
alias vi='nvim'

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

# requires rmtrash
alias rm='rmtrash'

# git
alias ga='git add'
alias gap='git add -p'
alias gc='git commit -v -m'
alias gca='git commit --amend'
alias gst='git status'
alias gd='git diff'
alias gf='git fetch'
alias current_branch='git rev-parse --abbrev-ref HEAD'
alias gcob='git checkout -b'
alias gpull='git pull origin `git rev-parse --abbrev-ref HEAD` --recurse-submodules'
alias gpush='git push origin `git rev-parse --abbrev-ref HEAD`'
alias gdmerged='git branch --merged | grep -vE "^\*|master$|develop$|staging$" | xargs -I % git branch -d %'

# interactive cd to ghq repository
# requires ghq, fzf
function move_to_repository() {
  cd $(ghq list -p --vcs=git | fzf --reverse)
  zle reset-prompt
}
zle -N move_to_repository
bindkey '^g' move_to_repository

# requires github/gh/gh
alias github="gh repo view --web"
alias pr="gh pr create"

alias dc='docker-compose'
alias kc='kubectl'
export KUBE_EDITOR=vim


case `uname` in
  "Darwin" ) # requires gnu-sed
    his() {
      print -z $( ([ -n "$ZSH_NAME" ] && fc -l 1 || history) | fzf +s --tac --reverse | gsed -r 's/ *[0-9]*\*? *//' | gsed -r 's/\\/\\\\/g')
    }

    gco() {
      local branches branch
      branches=$(git branch --all | grep -v HEAD) &&
      branch=$(echo "$branches" |
               fzf-tmux -d $(( 2 + $(wc -l <<< "$branches") )) +m) &&
      git checkout $(echo "$branch" | gsed "s/.* //" | gsed "s#remotes/[^/]*/##")
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
      brew cask upgrade
      zinit update --all
      vim +CocUpdate +qall
    }
  ;;

  "Linux" )
    his() {
      print -z $( ([ -n "$ZSH_NAME" ] && fc -l 1 || history) | fzf +s --tac | sed -r 's/ *[0-9]*\*? *//' | sed -r 's/\\/\\\\/g')
    }

    gco() {
      local branches branch
      branches=$(git branch --all | grep -v HEAD) &&
      branch=$(echo "$branches" |
               fzf-tmux -d $(( 2 + $(wc -l <<< "$branches") )) +m) &&
      git checkout $(echo "$branch" | sed "s/.* //" | sed "s#remotes/[^/]*/##")
    }
  ;;
esac
