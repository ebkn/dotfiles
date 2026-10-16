# session-cwd.sh — where each session is now

Records each Claude Code session's **current** working directory, so the PR
review pipeline can route a PR to the session that is actually in its worktree.
The consumer is `with_current_cwd` in
[bin/pr-review-common.sh](../../../bin/pr-review-common.md#a-session-that-moved-after-it-started).

## Why the registry is not enough

Both sources the pipeline reads, the session registry
(`~/.claude/sessions/<pid>.json`) and `claude agents --json`, report the
directory a session was **launched** in. A `cd` through the Bash tool, which is
what `gw` is, moves the harness's working directory but not that field.
Measured on 2.1.301: after `cd` into a worktree, the harness reported the new
primary working directory and the transcript recorded the new `cwd`, while the
registry still named the main checkout.

So a session started at the project root that ran `gw` and opened a PR from the
worktree was never found for that PR: every job held as "no live session". It
also went on answering for the main checkout it had left, so a PR built from
the main checkout could be delivered to it.

## Why a hook, and not the transcript

The transcript's per-entry `cwd` does follow the move, and it would cover
sessions already running. But reading it means depending on a second
undocumented layout (`~/.claude/projects/<encoded launch dir>/<id>.jsonl` and its
record shape), and the pipeline's docs already spend a section on detecting a
silent rename of the one undocumented field it does read. `CwdChanged` is a
[documented hook event](https://code.claude.com/docs/en/hooks) ("when the working
directory changes, for example when Claude executes a `cd` command"), so the
moving part is the public interface.

The payload carries `old_cwd` and `new_cwd` (read out of the 2.1.301 binary;
the docs page lists the event but its input section was not checked). The hook
reads `new_cwd`, falling back to the common `cwd` field, which SessionStart has.

Verified on a live session: the record appeared just after the `cd`'s tool call
returned. It is not there in the same instant, which is fine for a pipeline
that polls every 30 seconds.

**Not verified: whether `EnterWorktree` fires `CwdChanged`.** The docs say only
that the hook `cwd` field is the worktree root after entering one. A session in
a worktree made that way that cannot be routed is the symptom to look for.

## The record

```
${CLAUDE_SESSION_CWD_DIR:-${XDG_STATE_HOME:-~/.local/state}/claude-session-cwd}/<session_id>.json
{"cwd": "...", "since": <epoch ms>}
```

- **`since` is arrival time, and it ranks.** With moving sessions found, one
  worktree can hold two: one launched there and one that moved in. The one that
  arrived last wins (falling back to `startedAt`, also in ms, for a session with
  no record). It is kept while the directory is unchanged, because SessionStart
  also fires on **compaction**, mid-session, and restamping there would let a
  session that has been in a worktree for an hour outrank one that just arrived.
- **The id is refused, not sanitised,** when it is anything but
  `[A-Za-z0-9_.-]`. It names a file, and stripping characters could turn one id
  into another session's: a record under the wrong id misroutes a review.
- Written to a temp file and renamed, and only when jq produced a record, so
  the reader never sees a half-written or empty one.
- **SessionEnd removes it; SessionStart sweeps records untouched for 30 days.** A
  crashed session fires no SessionEnd, but its leftover record is harmless: the
  reader looks records up by the ids of *live* sessions and never globs, so a
  dead id is never read. The sweep exists only so the directory does not grow.

## The tmux pane option `@claude_cwd`

The same cwd is set as the pane option `@claude_cwd` on `$TMUX_PANE`, which
hooks inherit from the shell that launched claude (as
[agent-state.sh](agent-state.md) relies on). `.tmux.conf`'s `@popup_dir` reads
it so that `prefix + p` / `t` open where the session is, not in
`#{pane_current_path}`, which a Bash-tool `cd` never moves — see
[bin/tmux-popup.md](../../../bin/tmux-popup.md#where-p-and-t-open-popup_dir).

A pane option rather than the file, because `display-popup -d` is a format and
a format can read an option but not a file. It is set only after a record was
written, so the two never disagree; SessionEnd unsets it so the popups fall back
to the pane path. A session that crashes leaves it set until the next session
in that pane starts. Outside tmux nothing is called. A trailing `;` is escaped as
`\;`, the same tmux argv trap `agent-state.sh` documents.

## The trade-off it brings

Any `cd` counts as moving, including one made only to look at another worktree.
That session then outranks the one working there until it moves back. The rules
this repository gives agents (`git -C`, no `cd` in compound commands, work in the
current directory) make such visits uncommon, and the alternative is the
original bug. If it bites, the fix is to rank by something closer to "is working
here" than "was last here", not to drop the record.

## Always exits 0

No `set -e`. It runs on every `cd`, and a hook that fails must never be what the
session notices. An unknown mode, a payload that is not JSON, a missing id or
cwd, and an unwritable directory all do nothing.

## Testing (`session-cwd.test.sh`)

Asserts the file, the one thing the reader sees, rather than the exit status,
which is 0 by design whatever happens. The routing that consumes the record is
pinned in `bin/pr-review-common.test.sh` (overlay and ranking) and in each of
the three pipeline suites (that the program actually applies it).
