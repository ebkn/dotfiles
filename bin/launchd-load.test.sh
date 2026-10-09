#!/bin/bash
#
# launchd-load.test.sh
#
# The contract (bin/launchd-load.md): every plist under launchd/ that is linked
# into ~/Library/LaunchAgents and not already running is bootstrapped, through
# the LINKED path; one already loaded is left alone (restarting a running agent
# is worse than doing nothing); one not linked is reported and skipped;
# --status changes nothing; a load that fails exits non-zero; off macOS it does
# nothing at all. And finding no plists at all is an error, not a quiet
# success: a wrong DOTFILES_DIR would otherwise report a fully loaded machine.
#
# launchctl and uname are stubs: the real launchctl acts on the developer's own
# GUI session, and CI is Linux. The stub records every call, so "left alone"
# is asserted as "no bootstrap was issued", not inferred from the output.

set -u

DIR=$(mktemp -d)
SCRIPT="$(cd "$(dirname "$0")" && pwd)/launchd-load"
fails=0
trap 'rm -rf "$DIR"' EXIT

t() { # t <name> <expected> <actual>
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}
has() { # has <name> <haystack> <needle>
  case "$2" in
    *"$3"*) printf 'ok   %s\n' "$1" ;;
    *)
      printf 'FAIL %s\n       missing: %s\n       in:      %s\n' "$1" "$3" "$2"
      fails=$((fails + 1))
      ;;
  esac
}

# launchctl: `print gui/<uid>/<label>` succeeds for the labels in $LOADED;
# `bootstrap` fails for the labels in $BOOTSTRAP_FAILS. Every call is recorded.
mkdir -p "$DIR/stub"
cat >"$DIR/stub/launchctl" <<'STUB'
#!/bin/sh
printf '%s\n' "$*" >>"$CALLS"
case "$1" in
  print)
    label=${2##*/}
    case " $LOADED " in *" $label "*) exit 0 ;; esac
    exit 113
    ;;
  bootstrap)
    label=$(basename "$3" .plist)
    case " ${BOOTSTRAP_FAILS:-} " in *" $label "*) exit 5 ;; esac
    ;;
esac
STUB
cat >"$DIR/stub/uname" <<'STUB'
#!/bin/sh
echo "${UNAME_S:-Darwin}"
STUB
chmod +x "$DIR/stub/launchctl" "$DIR/stub/uname"
export CALLS="$DIR/calls"
uid=$(id -u)

# A repo with four agents, and a $HOME linking three: one running, two stopped.
REPO="$DIR/repo"
H="$DIR/home"
mkdir -p "$REPO/launchd" "$H/Library/LaunchAgents"
for label in com.test.running com.test.stopped com.test.unlinked com.test.zulu; do
  printf '<plist/>\n' >"$REPO/launchd/$label.plist"
done
ln -s "$REPO/launchd/com.test.running.plist" "$H/Library/LaunchAgents/"
ln -s "$REPO/launchd/com.test.stopped.plist" "$H/Library/LaunchAgents/"
ln -s "$REPO/launchd/com.test.zulu.plist" "$H/Library/LaunchAgents/"

# run [args] -- sets OUT, ERR, RC; CALLS holds the launchctl calls.
run() {
  : >"$CALLS"
  HOME="$H" DOTFILES_DIR="${DOTFILES:-$REPO}" LOADED="com.test.running" PATH="$DIR/stub:$PATH" \
    "$SCRIPT" "$@" >"$DIR/out" 2>"$DIR/err"
  RC=$?
  OUT=$(cat "$DIR/out")
  ERR=$(cat "$DIR/err")
}
bootstraps() { grep '^bootstrap' "$CALLS"; }
# status <label> [text] -- what the report says about one agent: its line, with
# the label and the padding taken off.
status() { printf '%s\n' "${2-$OUT}" | sed -nE "s/^ *$1 +//p"; }

run
t "loads: exits 0" "0" "$RC"
t "loads: only the stopped agents, each through its linked path" \
  "bootstrap gui/$uid $H/Library/LaunchAgents/com.test.stopped.plist
bootstrap gui/$uid $H/Library/LaunchAgents/com.test.zulu.plist" "$(bootstraps)"
t "loads: reports a stopped agent loaded" "loaded" "$(status com.test.stopped)"
t "loads: reports the running agent left alone" "already loaded" "$(status com.test.running)"
t "loads: reports the unlinked agent, and the fix" "not linked (run relink)" "$(status com.test.unlinked)"
has "loads: counts what it loaded" "$OUT" "loaded 2 agent(s)"

run --status
t "--status: exits 0" "0" "$RC"
t "--status: loads nothing" "" "$(bootstraps)"
t "--status: reports a stopped agent not loaded" "NOT loaded" "$(status com.test.stopped)"
t "--status: reports the running agent loaded" "already loaded" "$(status com.test.running)"

# One agent that cannot be loaded (no Aqua session, say) must not stop the
# rest: zulu sorts after it and still gets loaded.
BOOTSTRAP_FAILS=com.test.stopped run
t "a failed load: exits non-zero" "1" "$RC"
t "a failed load: names the agent and the domain" "could not load into gui/$uid" \
  "$(status com.test.stopped "$ERR")"
t "a failed load: carries on and loads the agents after it" "loaded" "$(status com.test.zulu)"
t "a failed load: counts only what did load" "loaded 1 agent(s)" "$(printf '%s\n' "$OUT" | grep 'agent(s)')"

UNAME_S=Linux run
t "off macOS: exits 0" "0" "$RC"
t "off macOS: never calls launchctl" "" "$(cat "$CALLS")"
has "off macOS: says there is nothing to do" "$OUT" "macOS-only"

run --bogus
t "an unknown argument: exits 1" "1" "$RC"
has "an unknown argument: names it" "$ERR" "--bogus"

# A DOTFILES_DIR with no launchd/ plists -- a typo, or a checkout elsewhere.
# The loop would run zero times and the script would exit 0 having looked at
# nothing, which on a machine with every agent stopped reads as all is well.
mkdir -p "$DIR/empty-repo"
DOTFILES="$DIR/empty-repo" run
t "no plists found: exits non-zero" "1" "$RC"
has "no plists found: names where it looked" "$ERR" "$DIR/empty-repo/launchd"
t "no plists found: never calls launchctl" "" "$(cat "$CALLS")"

if [ "$fails" -eq 0 ]; then
  echo "PASS"
else
  echo "$fails failure(s)"
  exit 1
fi
