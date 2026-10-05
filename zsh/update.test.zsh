#!/usr/bin/env zsh
# Unit tests for _uptime_reboot_warning (zsh/update.zsh).
#
# The warning predicts a failure that gives no notice of its own: on macOS
# 26.0-26.3 the kernel's TCP clock stops 49.7 days after boot, TIME_WAIT sockets
# are never reaped again, and days later every outbound connection fails at
# once. A warning that quietly stopped firing looks exactly like a healthy
# machine -- so the cases pin when it speaks and which releases it speaks on.
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
check 'silent when kern.boottime is not in the shape it reads' \
  '' \
  "$(
    (
      OSTYPE=darwin25.0
      stub_machine $AFFECTED 'Wed Aug  5 08:24:58 2026'
      _uptime_reboot_warning 2>&1
    )
  )"

if (( failures )); then
  printf '\n%d test(s) failed\n' "$failures"
  exit 1
fi
printf '\nall tests passed\n'
