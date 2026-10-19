#!/usr/bin/env zsh
# Unit tests for _uptime_reboot_warning and its place in update-all
# (zsh/update.zsh), and for the order of update-all's lazy.nvim steps: clean,
# then lazy-cooldown, then a restore in an nvim of its own (see the case).
#
# The warning predicts a failure that gives no notice of its own: on macOS
# 26.0-26.3 the kernel's TCP clock stops 49.7 days after boot, TIME_WAIT sockets
# are never reaped again, and days later every outbound connection fails at
# once. A warning that quietly stopped firing looks exactly like a healthy
# machine -- so the cases pin when it speaks, which releases it speaks on, and
# that update-all still ends with it.
#
# sysctl and date are replaced by functions, so the release and the uptime are
# whatever a case says. The sysctl stub answers per OID the way the real one
# does -- one value per line, in the order asked -- so no case depends on
# whether the function reads its two values in one call or in two.
#
# Run: zsh zsh/update.test.zsh   (exit 0 = pass)

set -u

source "${0:A:h}/update.zsh"

typeset -i failures=0

# want is a pattern, so a case can name the parts of the message that matter
# without freezing its wording. '' matches only silence.
check() {
  local desc="$1" want="$2" got="$3"
  if [[ "$got" == $~want ]]; then
    printf 'ok   %s\n' "$desc"
  else
    printf 'FAIL %s\n  want: %s\n  got : %s\n' "$desc" "$want" "$got"
    (( failures++ ))
  fi
}

TMP=$(mktemp -d "${TMPDIR:-/tmp}/update-test.XXXXXX")
trap 'rm -rf $TMP' EXIT
# update-all's restore guard reads lazy.nvim's lockfile under here, so no case
# reads or writes the real one.
export XDG_CONFIG_HOME=$TMP/config
mkdir -p $XDG_CONFIG_HOME/nvim
LOCK=$XDG_CONFIG_HOME/nvim/lazy-lock.json
LOCKED='{
  "one.nvim": { "branch": "main", "commit": "1111111111111111111111111111111111111111" }
}'
print -r -- $LOCKED > $LOCK

typeset -i NOW=1800000000 DAY=86400
# Well past both the day-30 threshold and the 49.7-day deadline.
typeset -i LONG=$(( 400 * DAY ))
# macOS 26.1, the release this was first measured on.
AFFECTED=25.1.0

# boottime_at <uptime-seconds> — kern.boottime as the kernel formats it.
boottime_at() {
  print -r -- "{ sec = $(( NOW - $1 )), usec = 482779 } Wed Aug  5 08:24:58 2026"
}

# stub_machine <kern.osrelease> <kern.boottime> [now] — make sysctl and date
# answer as that machine would. Call it inside a subshell.
stub_machine() {
  typeset -g STUB_RELEASE="$1" STUB_BOOTTIME="$2" STUB_NOW="${3:-$NOW}"
  sysctl() {
    [[ "$1" == -n ]] || return 1
    shift
    local oid
    for oid; do
      case "$oid" in
        kern.osrelease) print -r -- "$STUB_RELEASE" ;;
        kern.boottime) print -r -- "$STUB_BOOTTIME" ;;
        *) return 1 ;;
      esac
    done
  }
  date() {
    [[ "$1" == +%s ]] || return 1
    print -r -- "$STUB_NOW"
  }
}

# warning_on <kern.osrelease> <uptime-seconds> [ostype] — what the function
# prints on such a machine.
warning_on() {
  (
    OSTYPE="${3:-darwin25.0}"
    stub_machine "$1" "$(boottime_at "$2")"
    _uptime_reboot_warning 2>&1
  )
}

check 'silent one second before day 30' \
  '' \
  "$(warning_on $AFFECTED $(( 30 * DAY - 1 )))"

check 'speaks from day 30, naming the uptime, the deadline and the fix' \
  '*up 30 days*49.7 days*26.4*' \
  "$(warning_on $AFFECTED $(( 30 * DAY )))"

# No upper cut-off: on a machine already failing, this is the line that
# explains every "command failed" scrolled past above it.
check 'still speaks once the deadline has passed' \
  '*up 61 days*49.7 days*' \
  "$(warning_on $AFFECTED $(( 61 * DAY )))"

# The gate is exact on both sides. Before Darwin 25 tcp_now was incremented and
# wrapped harmlessly; from 25.4 the comparison that froze it is modular. A
# warning on a fixed release would be a false alarm repeated on every run.
check 'silent on macOS 15 (Darwin 24), which predates the bug' \
  '' \
  "$(warning_on 24.6.0 $LONG)"

check 'warns on the first affected release, 26.0 (Darwin 25.0)' \
  '*up 400 days*' \
  "$(warning_on 25.0.0 $LONG)"

check 'warns on the last affected release, 26.3 (Darwin 25.3)' \
  '*up 400 days*' \
  "$(warning_on 25.3.0 $LONG)"

check 'silent from 26.4 (Darwin 25.4), which fixed it' \
  '' \
  "$(warning_on 25.4.0 $LONG)"

check 'silent on the next major (Darwin 26)' \
  '' \
  "$(warning_on 26.0.0 $LONG)"

# The bug is XNU's; a long-lived Linux box has nothing to be warned about.
check 'silent on Linux, whatever sysctl would have said' \
  '' \
  "$(warning_on $AFFECTED $LONG linux-gnu)"

# A machine it cannot read must not come out as "up 20000 days".
check 'silent when sysctl fails' \
  '' \
  "$(
    (
      OSTYPE=darwin25.0
      sysctl() { return 1; }
      date() { print -r -- "$NOW"; }
      _uptime_reboot_warning 2>&1
    )
  )"

check 'silent when kern.boottime is not in the shape it reads' \
  '' \
  "$(
    (
      OSTYPE=darwin25.0
      stub_machine $AFFECTED 'Wed Aug  5 08:24:58 2026'
      _uptime_reboot_warning 2>&1
    )
  )"

# It is update-all's last statement, so its status is update-all's status.
check 'a warning is not a failure: the status stays 0' \
  '0' \
  "$(
    (
      OSTYPE=darwin25.0
      stub_machine $AFFECTED "$(boottime_at $LONG)"
      _uptime_reboot_warning 2>/dev/null
      print -r -- $?
    )
  )"

# update-all names every tool bare, so an empty path turns each of them into
# "command not found" and the function runs to its end without touching the
# machine. (A line that named a tool by absolute path would run for real here.)
# relink is a function so that there is something for the warning to follow.
# Between the two comes the list of what failed: here, everything.
check 'update-all ends with the warning, after relink' \
  "*relink ran"$'\n'"update-all: *"$'\n'"${(b)$(warning_on $AFFECTED $LONG)}" \
  "$(
    (
      OSTYPE=darwin25.0
      stub_machine $AFFECTED "$(boottime_at $LONG)"
      relink() { print -r -- 'relink ran'; }
      path=()
      update-all 2>&1
    )
  )"

# lazy.nvim rewrites lazy-lock.json from the installed commits whenever a clean
# or an install finishes, and keeps that in memory for the rest of the process.
# So lazy-cooldown's rewrite survives only if nothing but the restore runs in
# the nvim after it: a clean in the same process put every pin back where it
# was, and nothing failed (bin/lazy-cooldown.md). `sync` or `update` would
# skip the lockfile altogether. nvim and lazy-cooldown are functions that log,
# which an empty path leaves as the only ones found. nvim logs each argument
# quoted: `+Lazy! clean` unquoted is two arguments, the second a file to edit,
# and joined with spaces it would read the same.
check 'update-all cleans, then cools down, then restores in an nvim of its own' \
  "nvim '--headless' '+Lazy! clean' '+qa'
lazy-cooldown
nvim '--headless' '+Lazy! restore' '+qa'" \
  "$(
    (
      OSTYPE=linux
      relink() { :; }
      nvim() { print -r -- "nvim ${(qq)@}"; }
      lazy-cooldown() { print -r -- lazy-cooldown; }
      path=()
      update-all 2>/dev/null
    ) | grep -i 'lazy'
  )"

# A cooldown that fails has still decided the pins it could, and they are to
# be applied: the restore runs anyway, and the failure is named at the end,
# where the scroll of brew and go output does not bury it.
out=$(
  (
    OSTYPE=linux
    relink() { :; }
    nvim() { print -r -- "nvim ${(qq)@}"; }
    zinit-cooldown() { :; }
    zinit() { :; }
    lazy-cooldown() { return 1; }
    path=()
    update-all 2>&1
  )
)
check 'a failed lazy-cooldown still lets the restore run' \
  "*nvim '--headless' '+Lazy! restore' '+qa'*" "$out"
# OSTYPE=linux keeps the uptime warning silent, so the list is the last line.
check '  ... and is named at the end' \
  'update-all: lazy-cooldown failed;*' "${${(f)out}[-1]}"
said=(${(M)${(f)out}:#update-all: *})
check '  ... in one line, naming nothing else' '1' "${#said}"

# --- The restore guard ------------------------------------------------------

# A restore can still undo the cooldown: an nvim whose startup installs a
# plugin missing from disk -- one that failed to clone in the clean before it
# -- rewrites the lockfile from what is installed before the restore reads it.
# _lazy_restore keeps the lockfile it was given and puts it back if the restore
# changed it, so the pins that passed the cooldown stay recorded.
# restore_with <nvim body> — run _lazy_restore against that nvim; prints the
# status, then what it printed.
restore_with() {
  print -r -- $LOCKED > $LOCK
  (
    eval "nvim() { $1; }"
    path=()
    _lazy_restore 2>&1
    print -r -- "status=$?"
  )
}

check 'restore guard: silent when the restore follows the lockfile' \
  'status=0' "$(restore_with ':')"

out=$(restore_with "print -r -- '{ \"one.nvim\": { \"branch\": \"main\", \"commit\": \"2222222222222222222222222222222222222222\" } }' > \$LOCK")
check 'restore guard: a restore that rewrote the lockfile fails, saying so' \
  '*did not follow*status=1' "$out"
check '  ... and the lockfile it was given is put back' "${(b)LOCKED}" "$(cat $LOCK)"

check 'restore guard: a restore that fails fails the guard' \
  'status=1' "$(restore_with 'return 1')"

rm $LOCK
check 'restore guard: without a lockfile, nvim is not run' \
  '*cannot read*status=1' \
  "$(
    (
      nvim() { print -r -- 'nvim ran'; }
      path=()
      _lazy_restore 2>&1
      print -r -- "status=$?"
    )
  )"
print -r -- $LOCKED > $LOCK

# The stub is a hand copy of what one Mac printed. On a Mac, hold it against the
# real thing: the release must have the shape the gate reads, and the real boot
# time must parse. The clock is set to the year 2286 so that any real uptime is
# past day 30, and the release is pinned because this Mac is probably fixed.
if [[ "$OSTYPE" == darwin* ]]; then
  real=("${(@f)$(command sysctl -n kern.osrelease kern.boottime)}")
  check 'the real kern.osrelease is major.minor.patch' \
    '<->.<->.<->' \
    "$real[1]"
  check 'the real kern.boottime parses' \
    '*up <-> days*' \
    "$(
      (
        stub_machine $AFFECTED "$real[2]" 9999999999
        _uptime_reboot_warning 2>&1
      )
    )"
else
  printf 'skip the two cases that read the real sysctl (not macOS)\n'
fi

if (( failures )); then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi
printf '\nall tests passed\n'
