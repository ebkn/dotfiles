#!/bin/bash
# agent-state.sh — publish this Claude session's state onto its tmux pane.
#
# Claude Code hooks inherit the launching shell's environment, so $TMUX_PANE
# identifies the pane this session runs in without any extra bookkeeping. The
# state is stored as tmux *pane user options* rather than files: formats can
# read them directly (see set-titles-string in .tmux.conf), which keeps the
# WezTerm tab glyph free of any #() subprocess. Same storage pattern as
# @ssh_host / @git_branch (zsh/alias.zsh, zsh/directory.zsh).
#
# Consumers:
#   .tmux.conf  set-titles-string  → glyph in the WezTerm tab title
#   bin/tmux-agents                → popup dashboard / jump
#
# Usage: agent-state.sh <mode>
#   clear   — drop all state          (SessionStart, SessionEnd)
#   busy    — working                 (UserPromptSubmit, PostToolBatch)
#   notify  — read stdin, may set     (Notification)
#   done    — turn finished, unread   (Stop)
#
# The mode comes from argv, not from the stdin JSON's hook_event_name, so that
# every transition except `notify` avoids spawning jq. `busy` in particular runs
# once per tool batch, and a jq fork there would tax the inner agent loop.
#
# Always exits 0: a status indicator must never block the session.

set -u

# Not under tmux (plain terminal, remote web, CI): nothing to publish.
[ -n "${TMUX:-}" ] || exit 0
[ -n "${TMUX_PANE:-}" ] || exit 0

mode="${1:-}"

# -t "$TMUX_PANE" is explicit rather than relying on tmux resolving the current
# pane from the environment: hooks run without a controlling terminal, so there
# is no attached client for tmux to infer a target from.
set_opt() { tmux set-option -p -t "$TMUX_PANE" "$1" "$2" 2>/dev/null; }
unset_opt() { tmux set-option -p -u -t "$TMUX_PANE" "$1" 2>/dev/null; }

publish() {
  local state=$1 glyph=$2 note=${3:-}
  set_opt @claude_state "$state"
  # @claude_glyph is stored ready to concatenate — separator included —
  # so a format can prepend it unconditionally and an unset option then
  # contributes nothing at all. The separator is per-glyph rather than
  # appended here: ❓ and ✅ carry emoji presentation and already occupy
  # two terminal cells, so a space after them reads as a gap, while the
  # narrow ▶ (U+25B6, East Asian Ambiguous, one cell) needs one.
  set_opt @claude_glyph "$glyph"
  set_opt @claude_since "$(date +%s)"
  if [ -n "$note" ]; then
    set_opt @claude_note "$note"
  else
    unset_opt @claude_note
  fi
}

case "$mode" in
  clear)
    unset_opt @claude_state
    unset_opt @claude_glyph
    unset_opt @claude_since
    unset_opt @claude_note
    ;;
  busy)
    publish busy '▶ '
    ;;
  done)
    # 'done' quoted: bare, it reads as the loop-closing shell keyword.
    publish 'done' '✅'
    ;;
  notify)
    # Only the notification types that mean "this session is blocked on the
    # human" become `waiting`. auth_success / agent_completed and the
    # elicitation_* result types are informational and must not stick.
    #
    # jq collapses whitespace runs so the message stays on one line (the reader
    # below is line-based), and one pass emits both fields in a fixed order.
    {
      IFS= read -r ntype
      IFS= read -r message
    } < <(jq -r '
      (.notification_type // ""),
      (.message // "" | gsub("\\s+"; " "))
    ' 2>/dev/null)

    case "$ntype" in
      permission_prompt | idle_prompt | agent_needs_input | elicitation_dialog | elicitation_url_dialog)
        publish waiting '❓' "${message:0:120}"
        ;;
      *)
        exit 0
        ;;
    esac
    ;;
  *)
    exit 0
    ;;
esac

# The status line and the client title are only recomputed on redraw, and
# status-interval is 30s (.tmux.conf) to keep #() fork rates low. Force the
# redraw here so the glyph appears the moment the state changes, instead of
# lowering that interval for everyone.
tmux refresh-client -S 2>/dev/null

exit 0
