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
# update-all reads the gcloud pin from bin/init/pins.sh under $DOTFILES.
DOTFILES=${0:A:h:h}
GCLOUD_PIN=$(source "$DOTFILES/bin/init/pins.sh"; print -r -- $GCLOUD_VERSION)

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

# ~/.npmrc's ignore-scripts=true keeps a dependency's install script -- the
# usual way a hijacked package runs -- from running. update-all once turned it
# off for every global and their whole trees; none of them needs a script
# (zsh/README.md). npm logs each argument, as nvim does above.
out=$(
  (
    OSTYPE=linux
    relink() { :; }
    nvim() { :; }
    npm() { print -r -- "npm ${(qq)@}"; }
    path=()
    update-all 2>/dev/null
  )
)
check 'update-all updates the npm globals' "*npm 'update' '--location=global'*" "$out"
check '  ... leaving install scripts to ~/.npmrc' '' "${(M)${(f)out}:#npm *ignore-scripts*}"

# A cooldown that fails has still decided the pins it could, and they are to
# be applied: the restore runs anyway, and the failure is named at the end,
# where the scroll of brew and go output does not bury it.
# update_with <zinit-cooldown> <lazy-cooldown> <restore> <go-cooldown>
# <go-tools-install> [<tmux-plugins-install>] [<gcloud>] — run update-all with those
# exiting with the given
# statuses and everything else succeeding; prints what it printed.
# OSTYPE=linux keeps the uptime warning silent, so the list, when there is
# one, is the last line.
update_with() {
  print -r -- $LOCKED > $LOCK
  (
    OSTYPE=linux
    typeset -g ZC=$1 LC=$2 RS=$3 GC=$4 GI=$5 TP=${6:-0} GU=${7:-0}
    relink() { :; }
    zinit-cooldown() { return $ZC; }
    zinit() { :; }
    lazy-cooldown() { return $LC; }
    go-cooldown() { print -r -- go-cooldown; return $GC; }
    go-tools-install() { print -r -- go-tools-install; return $GI; }
    tmux-plugins-install() { return $TP; }
    gcloud() { print -r -- "gcloud ${(qq)@}"; return $GU; }
    go() { print -r -- "go ${(qq)@}"; }
    nvim() {
      print -r -- "nvim ${(qq)@}"
      [[ $2 == '+Lazy! restore' ]] && return $RS
      return 0
    }
    path=()
    update-all 2>&1
  )
}
# lists — the update-all: lines in $out, one per line.
lists() { print -rl -- ${(M)${(f)out}:#update-all: *}; }

out=$(update_with 0 0 0 0 0)
check 'when every pin step succeeds, no failure is listed' '' "$(lists)"

out=$(update_with 0 1 0 0 0)
check 'a failed lazy-cooldown still lets the restore run' \
  "*nvim '--headless' '+Lazy! restore' '+qa'*" "$out"
check '  ... and is named, alone, on the last line' \
  'update-all: lazy-cooldown failed;*' "$(lists)"
check '  ... which is the last line' "${(b)$(lists)}" "${${(f)out}[-1]}"

out=$(update_with 1 0 0 0 0)
check 'a failed zinit-cooldown is named, alone' 'update-all: zinit-cooldown failed;*' "$(lists)"

out=$(update_with 0 0 1 0 0)
check 'a failed restore is named, alone' 'update-all: Lazy! restore failed;*' "$(lists)"

# The Go tools are installed only at the versions go-cooldown let through: no
# `go install …@latest` of update-all's own, and the install after the
# cooldown, whether or not the cooldown decided every module.
golines() { local -a l=(${(M)${(f)out}:#go*}); print -rl -- $l; }
check 'update-all cools the Go tools down, then installs them, and nothing else' \
  $'go-cooldown\ngo-tools-install' "$(golines)"

out=$(update_with 0 0 0 1 0)
check 'a failed go-cooldown still lets the install run' '*go-cooldown'$'\n''go-tools-install*' "$out"
check '  ... and is named, alone' 'update-all: go-cooldown failed;*' "$(lists)"

out=$(update_with 0 0 0 0 1)
check 'a failed go-tools-install is named, alone' 'update-all: go-tools-install failed;*' "$(lists)"

out=$(update_with 0 0 0 0 0 1)
check 'a failed tmux-plugins-install is named, alone' 'update-all: tmux-plugins-install failed;*' "$(lists)"

# gcloud components move to the release bin/init/pins.sh names, never to the
# newest; a bare `components update` would undo the pin setup installed.
out=$(update_with 0 0 0 0 0)
check 'update-all updates gcloud components to the pinned release' \
  "*gcloud 'components' 'update' '--quiet' '--version=$GCLOUD_PIN'*" "$out"
check '  ... and the pin is a version' '<->.<->.<->' "$GCLOUD_PIN"

out=$(update_with 0 0 0 0 0 0 1)
check 'a failed gcloud components update is named, alone' \
  'update-all: gcloud components update failed;*' "$(lists)"

out=$(update_with 1 1 1 1 1 1 1)
check 'all seven failing are named on one line, in order' \
  'update-all: zinit-cooldown, lazy-cooldown, Lazy! restore, go-cooldown, go-tools-install, tmux-plugins-install, gcloud components update failed;*' "$(lists)"

# --- The restore guard ------------------------------------------------------

# A restore can still undo the cooldown: an nvim whose startup installs a
# plugin missing from disk -- one that failed to clone in the clean before it
# -- rewrites the lockfile from what is installed before the restore reads it.
# _lazy_restore keeps the lockfile it was given and puts it back if the restore
# changed it, so the pins that passed the cooldown stay recorded.
# restore_with <nvim body> — run _lazy_restore against that nvim, starting
# from the fixture lockfile; prints what it printed, then its status.
restore_with() {
  print -r -- $LOCKED > $LOCK
  restore_as_is "$1"
}
# restore_as_is <nvim body> — the same, on the lockfile as it stands.
restore_as_is() {
  (
    eval "nvim() { $1; }"
    path=()
    _lazy_restore 2>&1
    print -r -- "status=$?"
  )
}
# lock_bytes — the lockfile exactly, trailing newlines included, which $(cat)
# would strip.
lock_bytes() { local b; IFS= read -rd '' b < $LOCK; print -rn -- "$b|"; }

check 'restore guard: silent when the restore follows the lockfile' \
  'status=0' "$(restore_with ':')"

out=$(restore_with "print -r -- '{ \"one.nvim\": { \"branch\": \"main\", \"commit\": \"2222222222222222222222222222222222222222\" } }' > \$LOCK")
check 'restore guard: a restore that rewrote the lockfile fails, saying it is put back' \
  '*did not follow*the lockfile is put back*status=1' "$out"
check '  ... and not that it cannot be' '' "${(M)${(f)out}:#*cannot*}"
check '  ... and the lockfile it was given is put back, byte for byte' \
  "${(b)LOCKED}"$'\n''\|' "$(lock_bytes)"

# zsh's own rm and mkdir: an empty path leaves no other.
out=$(restore_with 'zmodload -F zsh/files b:zf_rm; zf_rm $LOCK')
check 'restore guard: a restore that removed the lockfile fails, saying it is put back' \
  '*did not follow*the lockfile is put back*status=1' "$out"
check '  ... and the lockfile is back' "${(b)LOCKED}"$'\n''\|' "$(lock_bytes)"

# The put-back itself fails: a directory where the lockfile was, which no
# write can replace -- as root too, where a chmod would not stop it.
out=$(restore_with 'zmodload -F zsh/files b:zf_rm b:zf_mkdir; zf_rm $LOCK; zf_mkdir $LOCK')
check 'restore guard: a lockfile that cannot be put back fails, saying so' \
  '*did not follow*cannot be put back*status=1' "$out"
check '  ... and not that it is put back' '' "${(M)${(f)out}:#*is put back*}"
zmodload -F zsh/files b:zf_rm
zf_rm -r $LOCK

# Its own status, not just "1": the guard passes nvim's on.
check 'restore guard: a restore that fails fails the guard with its status' \
  'status=3' "$(restore_with 'return 3')"

rm $LOCK
out=$(restore_as_is "print -r -- 'nvim ran'")
check 'restore guard: without a lockfile, it fails, saying so' '*cannot read*status=1' "$out"
check '  ... and nvim is not run' '' "${(M)${(f)out}:#nvim ran}"

: > $LOCK
out=$(restore_as_is "print -r -- 'nvim ran'")
check 'restore guard: with an empty lockfile, it fails, saying so' '*cannot read*status=1' "$out"
check '  ... and nvim is not run' '' "${(M)${(f)out}:#nvim ran}"
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
