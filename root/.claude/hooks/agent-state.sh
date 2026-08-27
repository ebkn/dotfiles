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
#   ask     — read stdin, question    (PreToolUse, matcher AskUserQuestion)
#   notify  — read stdin, may set     (Notification)
#   done    — turn finished, unread   (Stop)
#
# The mode comes from argv, not from the stdin JSON's hook_event_name, so that
# every transition except `ask`/`notify` avoids spawning jq. `busy` in particular
# runs once per tool batch, and a jq fork there would tax the inner agent loop.
# `ask` only ever fires for one tool (the hook carries a matcher), and `notify`
# is rare, so a fork on those two costs nothing measurable.
#
# Why `ask` exists at all: a Notification cannot tell "Claude is asking you a
# question" apart from "Claude wants permission to run a tool". Verified against
# 2.1.247 by logging the raw hook stdin for both — AskUserQuestion and a Bash
# `rm` prompt send byte-identical payloads:
#
#   {"notification_type":"permission_prompt","message":"Claude needs your permission"}
#
# The message carries no tool name. (The binary does contain a
# "Claude needs your permission to use ${tool}" string, but that is the push
# notification path, not the hook path — do not be misled by grepping for it.)
# PreToolUse is the only surface where the two differ, because its matcher *is*
# the tool name. That makes `asking` arrive when the dialog opens rather than
# after the notification's delay, so it also lands sooner than `waiting` does.
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
get_opt() { tmux show-options -p -t "$TMUX_PANE" -qv "$1" 2>/dev/null; }

publish() {
  local state=$1 glyph=$2 note=${3:-}
  set_opt @claude_state "$state"
  # @claude_glyph is stored ready to concatenate — separator included —
  # so a format can prepend it unconditionally and an unset option then
  # contributes nothing at all. The separator is per-glyph rather than
  # appended here: 🔶 🛑 🔘 ⚪ carry emoji presentation and already occupy
  # two terminal cells, so a space after them reads as a gap, while the
  # narrow ▶ (U+25B6, East Asian Ambiguous, one cell) needs one.
  #
  # Every glyph here must have Emoji_Presentation=Yes on its own — never a
  # base character promoted with VS16 (U+FE0F). Terminals and tmux disagree on
  # whether such a sequence is one cell or two, and being wrong shifts the tab
  # title and knocks bin/tmux-agents' columns out of line with no error at all.
  # ⚠️ (U+26A0 U+FE0F) was tried here and did visibly misalign, which is why
  # asking is the orange diamond and not the warning sign it wants to be.
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
    publish 'done' '⚪'
    ;;
  ask)
    # The matcher already restricts this to AskUserQuestion, so the tool name is
    # not re-checked; what the jq pass is for is the first question's text, which
    # is the only useful thing to put in @claude_note (the Notification for the
    # same dialog carries a fixed, contentless message).
    question=$(jq -r '(.tool_input.questions[0].question // "")
                      | gsub("\\s+"; " ")' 2>/dev/null)
    publish asking '🔶' "${question:0:120}"
    ;;
  notify)
    # Only the notification types that mean "this session is blocked on the
    # human" publish anything. auth_success / agent_completed and the
    # elicitation_* result types are informational and must not stick.
    #
    # The split is by how loudly the pane should shout, which is what the two
    # groups below encode:
    #   waiting (🛑) — a modal is open; nothing moves until it is answered.
    #   stalled (🔘) — the turn is over and has been sitting unattended.
    # `stalled` deliberately overwrites `done`: idle_prompt fires 60s after the
    # turn ends, so ⚪ ("just finished") ageing into 🔘 ("finished, still
    # untouched") is the intended reading, not a lost signal.
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
      permission_prompt | elicitation_dialog | elicitation_url_dialog)
        # permission_prompt also fires for the AskUserQuestion dialog, with an
        # identical payload (see the header). `ask` has already published the
        # richer state by then, so this must not demote it to a bare 🛑.
        [ "$(get_opt @claude_state)" = "asking" ] && exit 0
        publish waiting '🛑' "${message:0:120}"
        ;;
      idle_prompt | agent_needs_input)
        # idle_prompt is "no input for 60s", which is also true of a dialog the
        # human has walked away from — so it can arrive while one is still open.
        # Letting it through would relabel a genuinely blocked pane as merely
        # unattended, which is the one direction that loses information.
        case "$(get_opt @claude_state)" in
          asking | waiting) exit 0 ;;
        esac
        publish stalled '🔘' "${message:0:120}"
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
