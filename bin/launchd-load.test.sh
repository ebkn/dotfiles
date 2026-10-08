#!/bin/bash
#
# launchd-load.test.sh
#
# Pins bin/launchd-load: it loads the repo's agents that are linked and not
# running -- through the LINKED path -- and nothing else. Linking a plist is not
# loading it and the gap leaves no trace, so this is the step that matters; and
# it must never restart one that is running, or load one under --status.
#
# launchctl and uname are stubs: the subject is which launchctl calls the script
# decides to make, and a test has no business loading real agents. The plists
# are fixtures, except in the last case, which reads the repo's own.
#
# Written for bash 3.2 (/bin/bash on macOS).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
LL="$ROOT/bin/launchd-load"
TMP=$(mktemp -d)
TMP=$(cd "$TMP" && pwd -P)
trap '/bin/rm -rf "$TMP"' EXIT

fails=0
t() { # t <name> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}

mkdir -p "$TMP/stub" "$TMP/repo/launchd" "$TMP/home/Library/LaunchAgents"
# launchctl: `print gui/<uid>/<label>` succeeds for the labels in $LOADED;
# `bootstrap` fails for the plists named in $FAIL. Every call is logged.
cat >"$TMP/stub/launchctl" <<'STUB'
#!/bin/sh
echo "$*" >>"$CALLS"
case "$1" in
  print)
    label=${2##*/}
    case " $LOADED " in *" $label "*) exit 0 ;; esac
    exit 113
    ;;
  bootstrap)
    case " $FAIL " in *" ${3##*/} "*) exit 5 ;; esac
    exit 0
    ;;
esac
exit 64
STUB
cat >"$TMP/stub/uname" <<'STUB'
#!/bin/sh
echo "${UNAME:-Darwin}"
STUB
chmod +x "$TMP/stub"/*
for l in com.x.running com.x.stopped com.x.broken com.x.unlinked; do
  printf '<plist/>\n' >"$TMP/repo/launchd/$l.plist"
done
for l in com.x.running com.x.stopped com.x.broken; do
  ln -s "$TMP/repo/launchd/$l.plist" "$TMP/home/Library/LaunchAgents/$l.plist"
done
uid=$(id -u)

run() { # run [args] -- sets $out, $rc and leaves the calls in $TMP/calls
  : >"$TMP/calls"
  out=$(HOME="$TMP/home" DOTFILES_DIR="$TMP/repo" PATH="$TMP/stub:$PATH" CALLS="$TMP/calls" \
    LOADED="${LOADED:-}" FAIL="${FAIL:-}" UNAME="${UNAME:-}" "$LL" "$@" 2>&1)
  rc=$?
}
bootstraps() { grep '^bootstrap' "$TMP/calls"; }

LOADED="com.x.running" run
t "a linked agent that is not running is loaded, through the LINKED path" \
  "$(printf 'bootstrap gui/%s %s\nbootstrap gui/%s %s' \
    "$uid" "$TMP/home/Library/LaunchAgents/com.x.broken.plist" \
    "$uid" "$TMP/home/Library/LaunchAgents/com.x.stopped.plist")" \
  "$(bootstraps | sort)"
t "a running one is not restarted" "0" "$(bootstraps | grep -c running)"
t "an unlinked one is not loaded" "0" "$(bootstraps | grep -c unlinked)"
t "and is reported as not linked" "1" "$(printf '%s\n' "$out" | grep -c 'com.x.unlinked .*not linked (run relink)')"
t "the run says how many it loaded" "1" "$(printf '%s\n' "$out" | grep -cx 'loaded 2 agent(s)')"
t "and exits 0" "0" "$rc"

# One that cannot be loaded fails the run -- without stopping the others.
LOADED="com.x.running" FAIL="com.x.broken.plist" run
t "a failed load exits 1" "1" "$rc"
t "and says which, and where" "1" "$(printf '%s\n' "$out" | grep -c "com.x.broken .*could not load into gui/$uid")"
t "while the others are still loaded" "1" "$(bootstraps | grep -c stopped)"

# --status looks and changes nothing.
LOADED="com.x.running" run --status
t "--status loads nothing" "" "$(bootstraps)"
t "and reports what is not running" "1" "$(printf '%s\n' "$out" | grep -c 'com.x.stopped .*NOT loaded')"
t "and what is" "1" "$(printf '%s\n' "$out" | grep -c 'com.x.running .*already loaded')"

UNAME=Linux run
t "off macOS it says so and exits 0" "0:1" \
  "$rc:$(printf '%s\n' "$out" | grep -c 'macOS-only')"
t "without calling launchctl" "" "$(cat "$TMP/calls")"

run --bogus
t "an unknown argument exits 1" "1" "$rc"

# The label is taken from the FILE NAME, and launchctl knows the agent by the
# Label inside it. The two disagreeing makes `print` always miss -- so every
# run would bootstrap again, and fail, on an agent already running.
mismatch=""
for plist in "$ROOT"/launchd/*.plist; do
  label=$(awk '/<key>Label<\/key>/ { getline; gsub(/.*<string>|<\/string>.*/, ""); print; exit }' "$plist")
  [ "$label" = "$(basename "$plist" .plist)" ] || mismatch="$mismatch $(basename "$plist")"
done
t "every plist in launchd/ is named after its Label" "" "$mismatch"

if [ "$fails" -eq 0 ]; then
  echo "PASS"
else
  echo "$fails failure(s)"
  exit 1
fi
