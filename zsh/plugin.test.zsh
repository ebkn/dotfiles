#!/usr/bin/env zsh
# Unit tests for the supply-chain pins in zsh/plugin.zsh.
#
# Every plugin and zinit itself run inside every shell with the user's keys and
# tokens in reach, so each is pinned to a commit and moves only when a commit
# here moves it. Both ways the pin can be lost are silent:
#
# - A plugin whose ice has `depth` next to a commit `ver` is cloned shallow,
#   the checkout of an older commit fails, and the clone is left at the newest
#   one. zinit says so once, on the install; every later shell loads the
#   unpinned code without a word. So the static cases forbid `depth` outright.
# - zinit itself is not a plugin and has no `ver`. plugin.zsh holds it at its
#   pin, and a check that stopped doing so looks exactly like one that passed.
#
# The zinit cases run the real plugin.zsh against a local repository standing
# in for zinit, whose zinit.zsh defines a `zinit` that only logs. The copy of
# plugin.zsh has its pin rewritten to a commit of that repository and nothing
# else changed.
#
# Run: zsh zsh/plugin.test.zsh   (exit 0 = pass)

set -u
setopt extendedglob # (#c40) in the SHA patterns

HERE=${0:A:h}
PLUGIN=$HERE/plugin.zsh

typeset -i failures=0

# want is a pattern, so a case can name the parts that matter.
check() {
  local desc="$1" want="$2" got="$3"
  if [[ "$got" == $~want ]]; then
    printf 'ok   %s\n' "$desc"
  else
    printf 'FAIL %s\n  want: %s\n  got : %s\n' "$desc" "$want" "$got"
    (( failures++ ))
  fi
}

# --- Static: what plugin.zsh and update.zsh say -----------------------------

# Every `zinit light|load` must follow a `zinit ice` carrying a full commit
# `ver`. Comments and blank lines between them are skipped, as zinit does.
unpinned=()
ice=''
for line in "${(@f)$(<$PLUGIN)}"; do
  [[ $line == [[:space:]]#(\#*|) ]] && continue
  if [[ $line == zinit\ (light|load)\ * ]]; then
    [[ $ice == *ver[\"\'][[:xdigit:]](#c40)[\"\']* ]] || unpinned+=("${${line#zinit (light|load) }%% *}")
    ice=''
  elif [[ $line == zinit\ ice\ * ]]; then
    ice=$line
  else
    ice=''
  fi
done
check 'every plugin is pinned to a full commit SHA by its ver ice' \
  '' \
  "${unpinned[*]}"

check 'no zinit ice in plugin.zsh or update.zsh uses depth' \
  '' \
  "$(grep -n 'zinit ice.*depth' $PLUGIN $HERE/update.zsh)"

zinit_pin=$(sed -n 's/^_zinit_pin=\([[:xdigit:]]\{40\}\)$/\1/p' $PLUGIN)
check 'zinit itself is pinned to a full commit SHA' \
  '[[:xdigit:]](#c40)' \
  "$zinit_pin"

# --- zinit's own pin, run for real ------------------------------------------

TMP=$(mktemp -d "${TMPDIR:-/tmp}/plugin-test.XXXXXX")
trap 'rm -rf $TMP' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
git_c=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main)

# A stand-in for zinit with two commits: the pin, and a newer one on main that
# a shell must not end up running.
$git_c init -q $TMP/origin
print -r -- 'zinit() { print -r -- "$*" >> $HOME/zinit.log; }' > $TMP/origin/zinit.zsh
$git_c -C $TMP/origin add zinit.zsh
$git_c -C $TMP/origin commit -qm pinned
PINNED=$(git -C $TMP/origin rev-parse HEAD)
print -r -- '# newer' >> $TMP/origin/zinit.zsh
$git_c -C $TMP/origin commit -qam newer
NEWER=$(git -C $TMP/origin rev-parse HEAD)

# home_at <name> <commit> — a $HOME whose zinit is a clone of origin checked
# out at <commit>, on main when that is main's tip, as a fresh clone is.
home_at() {
  local home=$TMP/$1
  git clone -q $TMP/origin $home/.zinit/bin
  [[ $2 == $NEWER ]] || git -C $home/.zinit/bin checkout -q --detach $2
  print -r -- $home
}

# start_shell <home> <pin> — source plugin.zsh, its pin rewritten to <pin>, as
# a shell start would; prints stderr.
start_shell() {
  sed "s/^_zinit_pin=.*/_zinit_pin=$2/" $PLUGIN > $1/plugin.zsh
  HOME=$1 zsh -f -c "source $1/plugin.zsh" 2>&1 >/dev/null
}

head_of() { git -C $1/.zinit/bin rev-parse HEAD; }

# A fresh clone is on main's tip, ahead of the pin.
home=$(home_at drifted $NEWER)
check 'a zinit ahead of its pin is put back on it' \
  '' \
  "$(start_shell $home $PINNED)"
check '  ... and HEAD is the pin' "$PINNED" "$(head_of $home)"

# The common case, on every shell start: already pinned, so nothing may touch
# the network. The remote is made unreachable to prove it is not asked.
home=$(home_at pinned $PINNED)
git -C $home/.zinit/bin remote set-url origin $TMP/nowhere
check 'a zinit already at its pin is left alone, without fetching' \
  '' \
  "$(start_shell $home $PINNED)"
check '  ... and HEAD is still the pin' "$PINNED" "$(head_of $home)"

# A pin moved to a commit published after this machine last fetched: the
# commit is not in the clone, so it has to be fetched.
home_bumped=$(home_at bumped $PINNED)
home_offline=$(home_at offline $PINNED)
print -r -- '# later' >> $TMP/origin/zinit.zsh
$git_c -C $TMP/origin commit -qam later
LATER=$(git -C $TMP/origin rev-parse HEAD)

check 'a pin moved past what the clone has is fetched' \
  '' \
  "$(start_shell $home_bumped $LATER)"
check '  ... and HEAD is the new pin' "$LATER" "$(head_of $home_bumped)"

# Offline: the shell must still start, and must say that it is running
# unpinned code rather than pass for pinned.
git -C $home_offline/.zinit/bin remote set-url origin $TMP/nowhere
check 'a pin that cannot be reached is reported, naming it' \
  "*$LATER*" \
  "$(start_shell $home_offline $LATER)"
check '  ... and the plugins are still loaded' \
  '*light *' \
  "$(<$home_offline/zinit.log)"

if (( failures )); then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi
printf '\nall tests passed\n'
