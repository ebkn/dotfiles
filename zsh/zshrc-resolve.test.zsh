#!/usr/bin/env zsh
# Unit test for how .zshrc finds its own zsh/ directory.
#
# The source lines used to spell out $HOME/dotfiles, which meant pointing
# ~/.zshrc at a git worktree still loaded the main checkout's modules -- the
# opposite of what testing a change in a worktree is for. They now resolve
# relative to .zshrc itself.
#
# What earns a test here is the expansion. ${(%):-%N} is the script's own name
# under every combination of functionargzero/posixargzero; $0 is not, and when
# it is not it expands to the *shell's* name, which ${0:A:h} then resolves
# against $PWD -- so every source line would quietly point into whatever
# directory the shell started in. Nothing about that failure is visible: the
# shell starts, sources nothing, and simply has no configuration.
#
# So the assertion is on which directory the source lines resolved to, using a
# throwaway checkout whose zsh/ modules are stubs that announce themselves. The
# .zshrc under test is a *copy*, because a symlink back into this repo is
# exactly what :A would follow to defeat the point.
#
# Run: zsh zsh/zshrc-resolve.test.zsh   (exit 0 = pass)

set -u

repo="${0:A:h:h}"
typeset -i failures=0
work=${$(mktemp -d):A}

check() {
  local desc="$1" want="$2" got="$3"
  if [[ "$got" == "$want" ]]; then
    printf 'ok   %s\n' "$desc"
  else
    printf 'FAIL %s\n  want: %s\n  got : %s\n' "$desc" "$want" "$got"
    (( failures++ ))
  fi
}

# The 13 modules .zshrc sources, as stubs that print where they were loaded
# from. Deriving the list from .zshrc rather than hard-coding it means adding a
# module cannot silently skip this test.
# Matched loosely on purpose: tying this to the "$DOTFILES" spelling would make
# a regression fail here, with "no source lines found", instead of failing the
# assertion that says which directory the modules came from.
zshrc_modules=(${(f)"$(sed -n 's|^source "[^"]*/zsh/\([^"/]*\)"$|\1|p' "$repo/.zshrc")"})
[[ ${#zshrc_modules} -gt 0 ]] || { print -u2 'no source lines found in .zshrc'; exit 1 }

# make_checkout <dir> -- a fake dotfiles checkout: a copy of the real .zshrc
# next to a zsh/ of stubs.
make_checkout() {
  local dir=$1 m
  mkdir -p "$dir/zsh"
  command cp "$repo/.zshrc" "$dir/.zshrc"
  for m in $zshrc_modules; do
    print -r -- 'print -r -- "LOADED ${${(%):-%N}:A:h}"' > "$dir/zsh/$m"
  done
}

# start <home> -- run an interactive shell that reads <home>/.zshrc.
# -d skips /etc/zsh*, TMUX is set because .zshrc otherwise starts tmux and
# exits the shell before reaching a single source line.
start() {
  local home=$1
  (
    export HOME="$home" ZDOTDIR="$home" TMUX="fake,0,0"
    zsh -d -i -c exit 2>&1
  )
}

# loaded_from <output> -- the unique directories the stubs reported.
loaded_from() {
  print -r -- "$1" | sed -n 's/^LOADED //p' | sort -u
}

# --- a checkout somewhere other than ~/dotfiles ----------------------------
elsewhere="$work/some/where/dotfiles"
make_checkout "$elsewhere"
home="$work/home"
mkdir -p "$home"
ln -s "$elsewhere/.zshrc" "$home/.zshrc"

out=$(start "$home")
check 'every module loads from the checkout the .zshrc lives in' \
  "$elsewhere/zsh" "$(loaded_from "$out")"
check 'and all of them load' "${#zshrc_modules}" \
  "$(print -r -- "$out" | grep -c '^LOADED ')"

# --- the guard: a .zshrc with no zsh/ beside it falls back to ~/dotfiles ---
# Losing this would mean a shell that resolves neither path starts with no
# configuration at all, which is a far worse failure than loading the wrong one.
loose="$work/loose"
mkdir -p "$loose"
command cp "$repo/.zshrc" "$loose/.zshrc"
home2="$work/home2"
mkdir -p "$home2"
make_checkout "$home2/dotfiles"
ln -s "$loose/.zshrc" "$home2/.zshrc"

out=$(start "$home2")
check 'a .zshrc with no zsh/ beside it falls back to $HOME/dotfiles' \
  "$home2/dotfiles/zsh" "$(loaded_from "$out")"

/bin/rm -rf "$work"

if (( failures )); then
  printf '\nFAIL=%d\n' "$failures"
  exit 1
fi
printf '\nall passed\n'
