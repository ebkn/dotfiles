#!/bin/bash
# session-cwd.sh — record where this Claude Code session is NOW.
#
# Claude Code's session registry (~/.claude/sessions/<pid>.json) and `claude
# agents --json` both report the directory a session was LAUNCHED in, and
# neither follows a `cd` made through the Bash tool (measured on 2.1.301: after
# a cd into a worktree the harness's own working directory moved, the registry
# did not). The PR review pipeline routes a PR to the session working in its
# worktree, so a session started at the project root that ran `gw` and opened a
# PR from the worktree was unreachable for it, and still answered for the main
# checkout instead. with_current_cwd in bin/pr-review-common.sh reads these
# records over the registry's cwd. See session-cwd.md.
#
# One JSON file per session id:
#   ${CLAUDE_SESSION_CWD_DIR:-${XDG_STATE_HOME:-~/.local/state}/claude-session-cwd}/<session_id>.json
#   {"cwd": "<where it is>", "since": <epoch ms it got there>}
# `since` is in milliseconds to compare with the registry's startedAt, which
# the reader falls back to for a session with no record. Under tmux the cwd is
# also set as the pane option @claude_cwd; .tmux.conf decides who reads it.
#
# Usage: session-cwd.sh <mode>, hook payload on stdin
#   start — SessionStart: sweep month-old records, then record
#   cd    — CwdChanged: record new_cwd
#   end   — SessionEnd: remove this session's record
#
# Always exits 0, with no `set -e`: it runs on every cd, and a hook that fails
# must never be what the session notices.

set -u

dir=${CLAUDE_SESSION_CWD_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/claude-session-cwd}
mode=${1:-}
case "$mode" in
  start | cd | end) ;;
  *) exit 0 ;;
esac

# A hook always has stdin on a pipe; the guard is for a human running this by
# hand, who would otherwise sit at a hung prompt.
[ -t 0 ] && exit 0
json=$(cat)

# The id names a file, so anything that could leave the directory is refused
# rather than sanitised: stripping characters could turn one id into another
# session's, and a record under the wrong id misroutes a review.
id=$(printf '%s' "$json" | jq -r '.session_id // empty | strings' 2>/dev/null)
case "$id" in
  '' | . | .. | *[!A-Za-z0-9_.-]*) exit 0 ;;
esac
file="$dir/$id.json"

# The same answer goes onto this session's tmux pane as @claude_cwd, because
# #{pane_current_path} is the claude process's own directory, which a Bash-tool
# cd never moves. Which bindings read it is .tmux.conf's business (@popup_dir,
# bin/tmux-popup.md). A pane option rather than the file because display-popup
# -d is a format, and a format can read an option but not a file -- the same
# reason agent-state.sh publishes its state there. $TMUX_PANE is inherited from
# the shell that launched claude.
pane_set() {
  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || return 0
  local v=$1
  # tmux reads an argument ending in ';' as a command separator even on argv;
  # a trailing `\;` is its escape for a literal one.
  case $v in *';') v="${v%;}\\;" ;; esac
  tmux set-option -p -t "$TMUX_PANE" @claude_cwd "$v" 2>/dev/null
}
pane_unset() {
  [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] || return 0
  tmux set-option -p -u -t "$TMUX_PANE" @claude_cwd 2>/dev/null
}

if [ "$mode" = end ]; then
  rm -f "$file" 2>/dev/null
  pane_unset
  exit 0
fi

mkdir -p "$dir" 2>/dev/null || exit 0

# A session that crashes fires no SessionEnd and leaves its record. The reader
# never sees it -- records are looked up by live session ids only -- so all it
# costs is a file; SessionStart is rare enough to pay for the sweep.
if [ "$mode" = start ]; then
  find "$dir" -name '*.json' -mtime +30 -delete 2>/dev/null
fi

# new_cwd is CwdChanged's destination; SessionStart has only the common cwd.
#
# `since` is ARRIVAL time, and it ranks two sessions in one worktree, so it is
# kept while the directory is unchanged: SessionStart also fires on compaction,
# mid-session, and restamping there would make a session that has been in a
# worktree for an hour outrank one that just arrived.
old=$(cat "$file" 2>/dev/null)
tmp="$file.tmp.$$"
printf '%s' "$json" | jq -c --arg old "$old" '
  (.new_cwd // .cwd) as $cwd
  | select($cwd | type == "string" and length > 0)
  | (try ($old | fromjson) catch null) as $o
  | {cwd: $cwd,
     since: (if ($o | type) == "object" and $o.cwd == $cwd and ($o.since | type) == "number"
             then $o.since else (now * 1000 | floor) end)}' >"$tmp" 2>/dev/null
# Renamed into place so the reader never sees a half-written record, and only
# when jq produced one: an empty file would read as a record that says nothing.
#
# The pane is told only once the rename has landed, and what it is told comes
# from the record just written: publishing after a failed rename would point
# the popups at a cwd the record does not hold. A directory in the record's
# place is refused outright, because `mv` does not fail there -- it moves the
# file INTO it and returns 0.
if [ -s "$tmp" ] && [ ! -d "$file" ]; then
  cwd=$(jq -r .cwd "$tmp" 2>/dev/null)
  if mv -f "$tmp" "$file" 2>/dev/null; then
    pane_set "$cwd"
  fi
fi
rm -f "$tmp" 2>/dev/null
exit 0
