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
#
# The cd runs once. It used to run twice -- once in the && chain and again in an
# if -- which mostly went unnoticed because the pick is a path relative to the
# starting directory, so the second cd simply failed from the new one. It only
# does harm where that path resolves again from inside itself (a/a, src/src),
# and then it lands a level too deep with no error. Pinned by zsh/fd.test.zsh.
fd() {
  local dir
  dir=$(find "${1:-.}" -type d 2> /dev/null | fzf --reverse +m) || return
  [[ -n "$dir" ]] && cd "$dir"
}

# requires tree
alias tree='tree -a -I "\.DS_Store|\.git|\.svn|node_modules|vendor|volumes" -N -A -C'

# Route rm through `trash` so a mistake is recoverable from the Finder trash.
#
# Recent macOS ships its own /usr/bin/trash (confirmed on 26.1), so this
# normally needs nothing installed; Homebrew's trash formula is deliberately
# NOT a dependency, since it only shadows the system one with an unmaintained
# 0.9.2 and the wrapper passes nothing but paths, which both accept.
#
# There is no trash on Linux, though, and none on macOS old enough to predate
# the system binary. Without the guard the wrapper resolved to nothing and `rm`
# answered "command not found" on those hosts -- a shell where rm does not work
# at all is worse than one where it does not go to the trash.
#
# The fallback is deliberately silent (a warning on every rm would be noise),
# which does mean rm deletes for real there. That trade-off is the reason this
# comment exists.
rm() {
  (( $+commands[trash] )) || { command rm "$@"; return; }

  # Flags are dropped rather than forwarded, so that `rm -rf dir` still reaches
  # trash instead of being refused for an option trash does not have -- moving a
  # directory to the trash is already recursive, and there is nothing to force.
  # Two of them cannot simply be dropped, though, because they change which
  # operands there are:
  #
  #   --  ends the options. Everything after it is a filename even if it starts
  #       with a dash, which is the whole reason to type it.
  #   -f  means "ignore operands that do not exist, and never prompt". Handing a
  #       missing path to trash makes it fail instead, which breaks -f in
  #       exactly the case it exists for.
  local -a paths
  local arg force=0 opts_done=0
  for arg in "$@"; do
    if (( opts_done )); then
      paths+=("$arg")
      continue
    fi
    case "$arg" in
      --)          opts_done=1 ;;
      --force)     force=1 ;;
      # Long options are matched whole. A substring test would read the "f" in
      # GNU's --one-file-system as -f and silently start dropping operands.
      --*)         ;;
      -*f*)        force=1 ;;      # bundled short flags: -f, -rf, -fr
      -*)          ;;              # any other flag: drop
      *)           paths+=("$arg") ;;
    esac
  done

  if (( force )); then
    local -a existing
    # -e is false for a dangling symlink, which is still something rm removes.
    for arg in "${paths[@]}"; do
      [[ -e "$arg" || -L "$arg" ]] && existing+=("$arg")
    done
    paths=("${existing[@]}")
    # -f asks for silence when there is nothing left, and calling trash with no
    # operands would instead print its usage.
    (( ${#paths} )) || return 0
  fi

  # No operands and no -f: let the real rm produce the usage error rather than
  # inventing a second wording for it. Only flags are left in "$@" here, so it
  # cannot delete anything.
  (( ${#paths} )) || { command rm "$@"; return; }

  # An operand starting with a dash would be read back as an option by whatever
  # receives it. "./" is prepended instead of relying on the receiver
  # understanding "--", so this holds for trash and for the command rm fallback
  # alike. Absolute paths already begin with "/" and are left alone.
  local -a safe
  for arg in "${paths[@]}"; do
    case "$arg" in
      -*) safe+=("./$arg") ;;
      *)  safe+=("$arg") ;;
    esac
  done

  trash "${safe[@]}"
}

# terminal image viewer (sixel via ImageMagick, works over SSH+tmux)
# Fits image to 90% of available area, preserving aspect ratio.
# Uses CSI 16t to get cell pixel size (physical pixels, HiDPI-aware).
# In tmux: renders on the alternate screen (like vim/less) so sixel data
# never enters the main scrollback. Press any key to return.
imgcat() {
  if [ -z "$1" ] || [ ! -f "$1" ]; then
    echo "Usage: imgcat <image-file>" >&2
    return 1
  fi

  local cw=9 ch=18
  local old_settings=$(stty -g < /dev/tty)
  stty raw -echo min 0 time 1 < /dev/tty
  printf '\e[16t' > /dev/tty
  local resp=""
  while IFS= read -r -k1 -t 0.1 c < /dev/tty; do
    resp+="$c"
    [[ "$c" == "t" ]] && break
  done
  stty "$old_settings" < /dev/tty
  if [[ "$resp" =~ '\[6;([0-9]+);([0-9]+)t' ]]; then
    ch=${match[1]}
    cw=${match[2]}
  fi
  local pw=$(( $(tput cols) * cw * 9 / 10 ))
  local ph=$(( $(tput lines) * ch * 9 / 10 ))

  if [ -n "$TMUX" ]; then
    tput smcup
    clear
    magick "$1" -resize "${pw}x${ph}" sixel:-
    read -k1
    tput rmcup
    return
  fi

  magick "$1" -resize "${pw}x${ph}" sixel:-
}

alias dc='docker compose'
alias kc='kubectl'
alias tf='terraform'
export KUBE_EDITOR=nvim

alias python='python3'


# Pick a line out of shell history and put it on the command line to edit.
#
# There used to be one definition per platform, differing only in `gsed -r` vs
# `sed -r` -- and, by drift rather than intent, in whether the list was
# --reverse'd. Both are gone: -E is the ERE flag BSD sed and GNU sed agree on
# (GNU has accepted it since 4.2), so there is nothing left for gnu-sed to do
# here, and one definition cannot drift from itself.
#
# _his_clean is separate so the substitutions can be tested without an
# interactive `print -z`; zsh/his.test.zsh runs it on macOS and, through CI, on
# GNU sed, which is the differential that keeps -E honest.
_his_clean() {
  sed -E 's/ *[0-9]*\*? *//' | sed -E 's/\\/\\\\/g'
}

his() {
  print -z $( ([ -n "$ZSH_NAME" ] && fc -l 1 || history) \
    | fzf +s --tac --reverse --no-preview | _his_clean)
}

# $OSTYPE rather than `uname`: zsh sets it, so this costs no fork at startup.
if [[ "$OSTYPE" == darwin* ]]; then
  alias xcode='open -a xcode .'

  f() {
    if [ -z "$1" ]; then
      open .
    else
      open "$@"
    fi
  }
fi
