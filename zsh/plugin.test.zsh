#!/usr/bin/env zsh
# Unit tests for the supply-chain pins in zsh/plugin.zsh.
#
# Every plugin and zinit itself run inside every shell with the user's keys and
# tokens in reach, so each is pinned to a commit and moves only when its SHA in
# plugin.zsh moves (see zsh/README.md). Both ways the pin can be lost are
# silent:
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

# How a pin is written is bin/zinit-pins' to know (see bin/zinit-pins.md); it
# fails on a plugin without a full SHA and on any zinit form it cannot read.
# Here it is held to the real file: every pin read, and one per plugin plus
# zinit's own, so none was skipped.
pins=$($HERE/../bin/zinit-pins $PLUGIN 2>&1)
check 'bin/zinit-pins reads plugin.zsh without refusing anything' \
  'exit=0 *' \
  "exit=$? $pins"

# How many plugins plugin.zsh loads, counted apart from the reader so that it
# can disagree with it. Also what the offline case expects zinit to be asked
# for, so one count serves both.
plugins=$(grep -c '^[[:space:]]*zinit \(light\|load\) ' $PLUGIN)
check 'every plugin is pinned, and zinit too' \
  "$(( plugins + 1 ))" \
  "${#${(f)pins}}"

# Anywhere but a comment: an ice can be inline or continued onto a next line.
# update.zsh is included so that an ice written before `zinit update` is caught.
check 'depth appears in neither plugin.zsh nor update.zsh' \
  '' \
  "$(grep -n 'depth' $PLUGIN $HERE/update.zsh | grep -v ':[[:space:]]*#')"

# --- zinit's own pin, run for real ------------------------------------------

TMP=$(mktemp -d "${TMPDIR:-/tmp}/plugin-test.XXXXXX")
trap 'rm -rf $TMP' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
git_c=(git -c user.name=t -c user.email=t@t -c init.defaultBranch=main)

# plugin.zsh runs `command git`, so a git first on PATH sees every call. It logs
# the subcommand and hands over to the real one: whether a start forked git at
# all, and whether it fetched, is otherwise invisible -- a fetch that fails is
# silenced, and a checkout of a commit already in the clone succeeds anyway.
mkdir -p $TMP/bin
print -r -- "#!/bin/sh
printf '%s\n' \"\$*\" >> \"\$GIT_LOG\"
exec ${commands[git]} \"\$@\"" > $TMP/bin/git
chmod +x $TMP/bin/git

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

# The zsh start_shell runs, for the completion dump below.
ZSH_UNDER_TEST=$(zsh -f -c 'print -r -- $ZSH_VERSION')

# home_at <name> <commit> — a $HOME whose zinit is a clone of origin checked
# out at <commit>, on main when that is main's tip, as a fresh clone is.
# It holds a .zcompdump for that zsh, as a home in use does, so plugin.zsh
# takes its `compinit -C` path: with none, plain compinit runs compaudit over
# the system $fpath, and on the CI runner one of those directories is
# insecure, so its y/n prompt ("not interactive and can't open terminal")
# lands in the stderr these cases require to be empty -- noise from the
# machine, not a warning from the pin.
home_at() {
  local home=$TMP/$1
  git clone -q $TMP/origin $home/.zinit/bin
  print -r -- "#files: 0	version: $ZSH_UNDER_TEST" > $home/.zcompdump
  [[ $2 == $NEWER ]] || git -C $home/.zinit/bin checkout -q --detach $2
  print -r -- $home
}

# start_shell <home> <pin> — source plugin.zsh, its pin rewritten to <pin>, as
# a shell start would; prints stderr. Every git call is logged to <home>/git.log.
start_shell() {
  sed "s/^_zinit_pin=.*/_zinit_pin=$2/" $PLUGIN > $1/plugin.zsh
  : > $1/git.log
  HOME=$1 GIT_LOG=$1/git.log PATH=$TMP/bin:$PATH zsh -f -c "source $1/plugin.zsh" 2>&1 >/dev/null
}

head_of() { git -C $1/.zinit/bin rev-parse HEAD; }

# The subcommands a start ran, one per line, without their options.
git_calls() { awk '{ for (i = 1; i <= NF; i++) if ($i !~ /^-/ && $(i-1) != "-C" && $(i-1) != "-c") { print $i; break } }' $1/git.log; }

# A fresh clone is on main's tip, ahead of the pin. The pin is in the clone,
# so it is checked out without asking the network.
home=$(home_at drifted $NEWER)
check 'drifted: a zinit ahead of its pin starts without a warning' \
  '' \
  "$(start_shell $home $PINNED)"
check 'drifted: HEAD is put back on the pin' "$PINNED" "$(head_of $home)"
check 'drifted: a pin already in the clone is not fetched' \
  '' \
  "$(git_calls $home | grep -x fetch)"

# The common case, on every shell start: already pinned, so git is not run at
# all -- not to fetch, and not to look.
home=$(home_at pinned $PINNED)
check 'pinned: a zinit already at its pin starts without a warning' \
  '' \
  "$(start_shell $home $PINNED)"
check 'pinned: HEAD is still the pin' "$PINNED" "$(head_of $home)"
check 'pinned: git is not run' '' "$(<$home/git.log)"

# A pin moved to a commit published after this machine last fetched: the
# commit is not in the clone, so it has to be fetched.
home_bumped=$(home_at bumped $PINNED)
home_offline=$(home_at offline $PINNED)
print -r -- '# later' >> $TMP/origin/zinit.zsh
$git_c -C $TMP/origin commit -qam later
LATER=$(git -C $TMP/origin rev-parse HEAD)

check 'bumped: a pin moved past the clone starts without a warning' \
  '' \
  "$(start_shell $home_bumped $LATER)"
check 'bumped: the new pin is fetched' 'fetch' "$(git_calls $home_bumped | grep -x fetch)"
check 'bumped: HEAD is the new pin' "$LATER" "$(head_of $home_bumped)"

# Offline: the shell must still start, and must say that it is running
# unpinned code -- and which -- rather than pass for pinned.
git -C $home_offline/.zinit/bin remote set-url origin $TMP/nowhere
check 'offline: the warning names the pin and the commit running instead' \
  "*$LATER*$PINNED*" \
  "$(start_shell $home_offline $LATER)"
check 'offline: every plugin is still loaded' \
  "$plugins" \
  "$(grep -c '^light ' $home_offline/zinit.log)"

if (( failures )); then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi
printf '\nall tests passed\n'
