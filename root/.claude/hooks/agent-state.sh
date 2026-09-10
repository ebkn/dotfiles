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
# ONE PANE HOLDS SEVERAL ACTORS. Hooks fire inside subagents too, and the input
# then carries `agent_id` / `agent_type` identifying which one
# (https://code.claude.com/docs/en/hooks). A pane therefore has as many live
# states as it has actors: the main thread plus one per running subagent. The
# first version of this hook published a single last-write-wins value, which is
# structurally unable to represent that — with three subagents running, one of
# them hitting a permission prompt published `waiting`, and the very next
# PostToolBatch from either of the other two overwrote it with `busy`. The tab
# then claimed progress while a dialog sat unanswered, which is the opposite of
# what this indicator exists for.
#
# So state is kept per actor, one small file each, under
#   ${XDG_STATE_HOME:-~/.local/state}/claude-agent-state/<socket>-<pane>/
# and the pane options are a *derived* view: the highest-priority state wins,
#   asking > waiting > busy > stalled
# i.e. anything blocked on the human outranks anything still running. Ties go to
# the oldest, so the age in the picker is how long that state has actually held.
# asking outranks waiting because it is the only state carrying a note you
# cannot reconstruct from anywhere else (the question itself).
#
# Files rather than more pane options, for two reasons. Enumerating options by
# prefix is not something tmux formats can do, so a per-agent option could be
# written but never aggregated cheaply; and each hook writes only *its own*
# actor's file, so several subagents firing at once cannot lose each other's
# writes — a single shared file would need locking on the hottest path here.
#
# Usage: agent-state.sh <mode>
#   clear          — drop all state                (SessionStart, SessionEnd)
#   busy           — working                       (UserPromptSubmit, PostToolBatch)
#   ask            — read stdin, question          (PreToolUse, matcher AskUserQuestion)
#   notify         — read stdin, may set           (Notification)
#   done           — turn finished, unread         (Stop)
#   subagent-start — a subagent began              (SubagentStart)
#   subagent-stop  — a subagent finished           (SubagentStop)
#
# Modes name the *transition*, states name what is published, and the two need
# not match: `done` is the Stop transition, and the state it publishes is
# `stalled`, because a finished turn nobody has read yet is exactly that. Keeping
# the mode name also means settings.json does not have to change in lockstep,
# so sessions running an older hook snapshot keep working.
#
# The mode comes from argv, not from the stdin JSON's hook_event_name, so that
# the hot paths avoid spawning jq. `busy` in particular runs once per tool batch,
# and a jq fork there would tax the inner agent loop. It reads stdin only when
# the pane already has subagent entries — with no subagent registered there is
# exactly one actor and nothing to attribute, which is the common case.
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

# --- where the per-actor state lives -----------------------------------------
#
# Keyed by socket *and* pane id, not by pane id alone: a tmux pane id is only
# unique within one server, so two servers would otherwise share a directory
# (the same trap bin/tmux-track-session documents for its records). $TMUX is
# "socket,pid,session-id", so the socket name costs no fork.
#
# State, not cache: it is the only representation of which subagents are live.
sock=${TMUX%%,*}
sock=${sock##*/}
state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/claude-agent-state/${sock//[^A-Za-z0-9_.-]/_}-${TMUX_PANE//[^A-Za-z0-9]/_}"

# -t "$TMUX_PANE" is explicit rather than relying on tmux resolving the current
# pane from the environment: hooks run without a controlling terminal, so there
# is no attached client for tmux to infer a target from.
set_opt() { tmux set-option -p -t "$TMUX_PANE" "$1" "$2" 2>/dev/null; }
unset_opt() { tmux set-option -p -u -t "$TMUX_PANE" "$1" 2>/dev/null; }

# --- reading the hook payload ------------------------------------------------
#
# `read -d ''` consumes the whole of stdin with no fork. The tty guard is for a
# human running this by hand: a hook always has stdin attached to a pipe, and
# without the guard an interactive invocation would just hang.
json=""
read_stdin() {
  [ -t 0 ] && return 0
  IFS= read -r -d '' json
  return 0
}

# Extracting agent_id with a shell regex is deliberately NOT done: PostToolBatch
# carries the *content* of every tool result in the batch, so a file this repo
# reads — this one, for instance — would match a "agent_id":"..." pattern in its
# own comments and misattribute the state to a subagent that does not exist. jq
# reads the top-level key and cannot be fooled that way, so the choice is jq or
# nothing, and `has_agents` below decides which.
agent_id=""
agent_type=""
parse_agent() {
  read_stdin
  [ -n "$json" ] || return 0
  {
    IFS= read -r agent_id
    IFS= read -r agent_type
  } < <(printf '%s' "$json" | jq -r '
    (.agent_id // ""),
    (.agent_type // "" | gsub("[^A-Za-z0-9 ._:-]"; ""))
  ' 2>/dev/null)
  return 0
}

# True while any subagent is registered on this pane. Used to keep the hot path
# fork-free in the ordinary single-actor case: with no subagent there is only
# one actor, so the payload cannot say anything the answer does not already
# contain.
has_agents() {
  local f
  for f in "$state_dir"/a_*; do
    [ -e "$f" ] && return 0
    break
  done
  return 1
}

# The actor's file name. `main` is the conversation you are looking at; every
# subagent gets its id, flattened to something safe to use as a file name.
actor_file() {
  if [ -n "$agent_id" ]; then
    printf '%s/a_%s' "$state_dir" "${agent_id//[^A-Za-z0-9_.-]/_}"
  else
    printf '%s/main' "$state_dir"
  fi
}

# Fields are separated by "|" and NOT by a tab, on purpose. Tab is an IFS
# *whitespace* character however narrow IFS is, so `IFS=$'\t' read` collapses
# runs of them and strips leading ones — and these records have optional middle
# fields, so an entry with no label would arrive shifted by one (the same trap
# bin/tmux-agents documents for its pane rows). With "|" every empty field is
# preserved, and the note, which is the last field, keeps any "|" of its own.
readonly SEP='|'

read_entry() { # $1 file → state/since/label/note
  e_state=""; e_since=""; e_label=""; e_note=""
  [ -f "$1" ] || return 1
  IFS="$SEP" read -r e_state e_since e_label e_note <"$1" || return 1
  [ -n "$e_state" ] || return 1
  return 0
}

# --- writing one actor's state ----------------------------------------------

record() { # $1 state, $2 note (the glyph is derived on read, not stored)
  local state=$1 note=${2:-} file
  file=$(actor_file)
  [ -d "$state_dir" ] || mkdir -p "$state_dir" 2>/dev/null || return 0
  # A state's timestamp is when the actor *entered* it, so re-publishing the
  # same state does not restamp it — the age column in bin/tmux-agents means
  # "how long has it been like this", which is the only reading that is useful
  # for a pane that has been blocked for an hour.
  local since=""
  if read_entry "$file" && [ "$e_state" = "$state" ]; then
    since=$e_since
  fi
  [ -n "$since" ] || since=$(date +%s)
  # The label is what bin/tmux-agents shows to tell one subagent from another;
  # jq has already stripped anything that could break the encoding out of it.
  printf '%s%s%s%s%s%s%s\n' \
    "$state" "$SEP" "$since" "$SEP" "$agent_type" "$SEP" "${note//$'\n'/ }" \
    >"$file" 2>/dev/null || true
}

current_state() { # of *this* actor, for the within-actor precedence rules
  read_entry "$(actor_file)" && printf '%s' "$e_state"
}

forget_actor() {
  rm -f "$(actor_file)" 2>/dev/null || true
}

# --- deriving the pane options ----------------------------------------------

rank_of() { # lower wins
  case "$1" in
    asking) printf 0 ;;
    waiting) printf 1 ;;
    busy) printf 2 ;;
    stalled) printf 3 ;;
    *) printf 9 ;;
  esac
}

glyph_of() {
  # @claude_glyph is stored ready to concatenate — separator included — so a
  # format can prepend it unconditionally and an unset option then contributes
  # nothing at all. The separator is per-glyph rather than appended by the
  # caller: 🔶 🛑 🔘 carry emoji presentation and already occupy two terminal
  # cells, so a space after them reads as a gap, while the narrow ▶ (U+25B6,
  # East Asian Ambiguous, one cell) needs one.
  #
  # Every glyph here must have Emoji_Presentation=Yes on its own — never a base
  # character promoted with VS16 (U+FE0F). Terminals and tmux disagree on
  # whether such a sequence is one cell or two, and being wrong shifts the tab
  # title and knocks bin/tmux-agents' columns out of line with no error at all.
  # ⚠️ (U+26A0 U+FE0F) was tried here and did visibly misalign, which is why
  # asking is the orange diamond and not the warning sign it wants to be.
  case "$1" in
    asking) printf '🔶' ;;
    waiting) printf '🛑' ;;
    busy) printf '▶ ' ;;
    stalled) printf '🔘' ;;
  esac
}

# Record separators for @claude_agents, the per-actor listing bin/tmux-agents
# expands into one row each. ASCII RS/US rather than printable characters: a
# note is arbitrary text from a permission prompt or a question, and any
# printable delimiter would eventually appear inside one. They travel through
# `tmux set-option` and back out of a `list-panes -F` format unchanged, which
# agent-state.test.sh pins, because that round trip is the whole contract with
# the picker — including over ssh, where the remote tmux expands the format.
readonly RS=$'\036'
readonly US=$'\037'

publish() {
  local best_state="" best_since="" best_note="" best_rank=9 rank listing=""
  local f

  for f in "$state_dir"/main "$state_dir"/a_*; do
    read_entry "$f" || continue
    rank=$(rank_of "$e_state")
    [ "$rank" -eq 9 ] && continue
    listing="$listing$e_state$US$e_since$US$e_label$US$e_note$RS"
    # Rank first, then the oldest, then whichever entry actually says something.
    # The last clause is not cosmetic: several actors routinely enter a state
    # within the same second — Stop lands on the main thread while a worker is
    # already blocked — and with a pure `<` the main thread's noteless record
    # wins by being read first, hiding the one message that explains the glyph.
    if [ "$rank" -lt "$best_rank" ] ||
      { [ "$rank" -eq "$best_rank" ] && [ "${e_since:-0}" -lt "${best_since:-0}" ]; } ||
      { [ "$rank" -eq "$best_rank" ] && [ "${e_since:-0}" -eq "${best_since:-0}" ] &&
        [ -z "$best_note" ] && [ -n "$e_note" ]; }; then
      best_rank=$rank
      best_state=$e_state
      best_since=$e_since
      best_note=$e_note
      # Which actor is blocked matters more than the note when there are
      # several, so the label leads it. Truncation is applied after, on the
      # combined string, so the option can never exceed what a title can hold.
      [ -n "$e_label" ] && best_note="$e_label: $e_note"
      best_note=${best_note:0:120}
    fi
  done

  if [ -z "$best_state" ]; then
    clear_opts
    return 0
  fi

  # Skip the tmux round trips when nothing a consumer can see has changed. This
  # is what pays for the file work above: a subagent reporting busy while the
  # pane is already busy — the single most frequent event here — now costs no
  # fork at all, where the previous version spent four on every batch.
  local pub="$best_state$US$best_since$US$best_note$US$listing" prev=""
  # Read with the builtin, not $(cat ...): a fork here would spend exactly what
  # this check exists to save. The record carries no newline, so `read` reports
  # EOF while still having filled prev.
  [ -f "$state_dir/.published" ] && IFS= read -r prev <"$state_dir/.published"
  if [ "$prev" = "$pub" ]; then
    return 0
  fi
  printf '%s' "$pub" >"$state_dir/.published" 2>/dev/null || true

  set_opt @claude_state "$best_state"
  set_opt @claude_glyph "$(glyph_of "$best_state")"
  set_opt @claude_since "$best_since"
  if [ -n "$best_note" ]; then
    set_opt @claude_note "$best_note"
  else
    unset_opt @claude_note
  fi
  set_opt @claude_agents "$listing"

  # The status line and the client title are only recomputed on redraw, and
  # status-interval is 30s (.tmux.conf) to keep #() fork rates low. Force the
  # redraw here so the glyph appears the moment the state changes, instead of
  # lowering that interval for everyone.
  tmux refresh-client -S 2>/dev/null
  return 0
}

clear_opts() {
  unset_opt @claude_state
  unset_opt @claude_glyph
  unset_opt @claude_since
  unset_opt @claude_note
  unset_opt @claude_agents
  rm -f "$state_dir/.published" 2>/dev/null || true
  tmux refresh-client -S 2>/dev/null
}

case "$mode" in
  clear)
    rm -rf "$state_dir" 2>/dev/null || true
    clear_opts
    ;;
  busy)
    # Attribution costs a jq fork, so it is paid only when there is something to
    # attribute *to*. With no subagent registered the only actor is the main
    # thread, and this is the path that runs once per tool batch.
    has_agents && parse_agent
    record busy
    publish
    ;;
  done)
    # Stop is the main thread's turn ending. It deliberately does NOT clear the
    # subagent entries: a backgrounded agent outlives the turn that launched it,
    # and dropping it here would hide exactly the agent most likely to need you.
    # SubagentStop is what removes an entry; a subagent that dies without firing
    # it leaves a stale `busy` until SessionStart/SessionEnd clears the pane.
    record stalled
    publish
    ;;
  subagent-start)
    parse_agent
    [ -n "$agent_id" ] || exit 0
    record busy
    publish
    ;;
  subagent-stop)
    parse_agent
    [ -n "$agent_id" ] || exit 0
    forget_actor
    publish
    ;;
  ask)
    # The matcher already restricts this to AskUserQuestion, so the tool name is
    # not re-checked; what the jq pass is for is the first question's text, which
    # is the only useful thing to put in the note (the Notification for the same
    # dialog carries a fixed, contentless message).
    read_stdin
    {
      IFS= read -r question
      IFS= read -r agent_id
      IFS= read -r agent_type
    } < <(printf '%s' "$json" | jq -r '
      (.tool_input.questions[0].question // "" | gsub("\\s+"; " ")),
      (.agent_id // ""),
      (.agent_type // "" | gsub("[^A-Za-z0-9 ._:-]"; ""))
    ' 2>/dev/null)
    record asking "${question:0:120}"
    publish
    ;;
  notify)
    # Only the notification types that mean "this session is blocked on the
    # human" publish anything. auth_success / agent_completed and the
    # elicitation_* result types are informational and must not stick.
    #
    # The split is by how loudly the pane should shout:
    #   waiting (🛑) — a modal is open; nothing moves until it is answered.
    #   stalled (🔘) — nothing is happening and the next move is the human's.
    #
    # `idle_prompt` is deliberately absent from both lists. It fires 60s after a
    # turn ends, which is a state the Stop hook has already published — so all
    # it could do is republish the same thing. It earned its keep only while
    # `done` and `stalled` were separate glyphs; once they merged it became a
    # no-op with a side effect.
    #
    # jq collapses whitespace runs so the message stays on one line (the reader
    # below is line-based), and one pass emits every field in a fixed order.
    read_stdin
    {
      IFS= read -r ntype
      IFS= read -r message
      IFS= read -r agent_id
      IFS= read -r agent_type
    } < <(printf '%s' "$json" | jq -r '
      (.notification_type // ""),
      (.message // "" | gsub("\\s+"; " ")),
      (.agent_id // ""),
      (.agent_type // "" | gsub("[^A-Za-z0-9 ._:-]"; ""))
    ' 2>/dev/null)

    case "$ntype" in
      permission_prompt | elicitation_dialog | elicitation_url_dialog)
        # permission_prompt also fires for the AskUserQuestion dialog, with an
        # identical payload (see the header). `ask` has already published the
        # richer state by then, so this must not demote it to a bare 🛑. The
        # check is per actor: another actor being blocked says nothing about
        # this one, and the aggregate above already decides between them.
        [ "$(current_state)" = "asking" ] && exit 0
        record waiting "${message:0:120}"
        publish
        ;;
      agent_needs_input)
        # A background/worker agent is blocked. Unlike the Stop transition this
        # carries a useful message ("<agent> needs your input"), so it publishes
        # rather than being folded into the Stop path. It must still not relabel
        # an actor whose own dialog is open as merely idle — that is the one
        # direction that loses information.
        case "$(current_state)" in
          asking | waiting) exit 0 ;;
        esac
        record stalled "${message:0:120}"
        publish
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

exit 0
