---
name: retrospective
description: Review recent AI coding sessions for inefficiency. Aggregates transcripts across sessions into distributions, names the outlying sessions, then reads those sessions to explain what actually happened in them. Use when asked to look back over recent sessions, find where time or tokens went, or check whether the way work is going has been getting worse — triggered by "最近のセッションを振り返りたい", "非効率なところを探して", "セッションの傾向を見たい", "開発の進め方が悪化していないか", "review my recent sessions", "where am I wasting tokens", or the /retrospective command. Not for reviewing a pull request, a diff, or test code, and not for reducing permission prompts.
effort: high
allowed-tools: Bash(session-review *), Bash(session-extract *), Read, Glob, Grep
---

Look across recent sessions, find the ones that stand out, and explain them.

Match the user's language in the report.

## Boundary of this skill: read and measure only

**Never write.** No file edits, no `git add` / `git commit` / `git push`, no
`gh pr create` / `gh pr edit`, and no changes to `CLAUDE.md`, `AGENTS.md`,
`settings.json`, or any skill. `Bash` is for running `session-review`, reading
transcripts, and gathering context — never for writing or destructive work.

This holds even when asked directly: "also update CLAUDE.md while you're at it"
is answered with the proposal, not the edit. Applying a change is a separate
request the user makes with the finding in hand.

**The boundary is this skill's own contract, not something the host enforces.**
Some hosts ignore `allowed-tools` entirely (Codex reads only `name` and
`description`), and on this machine `git add` / `commit -m` / `push` and
`gh pr create` / `edit` are pre-approved, so they would run with no prompt at
all. **The absence of a prompt is not permission.** The question is not whether
a write would succeed but whether this skill performs one. It does not.

The reason is specific to this skill: a retrospective that edits config closes
its own feedback loop. The next run then measures a setup this skill wrote, and
there is no longer an outside view.

**`allowed-tools` grants `Bash` only for this skill's own two commands.**
`allowed-tools` is a grant rather than a restriction, so a bare `Bash` would
widen permissions past the session's own for as long as the skill runs. Granted
here are `session-review` and `session-extract`, both of which only read
transcripts. Notably `jq` is **not** granted: a Bash prefix grant covers
redirects, so `Bash(jq *)` would also permit `jq . x > ~/.zshrc`. That is why
`session-extract --human-turns` exists instead. Anything else this skill needs
will prompt, **which is the correct outcome** — do not work around it.

## Procedure

### 1. Aggregate

```
session-review --days 90
```

`session-review` is on `PATH` via `~/.local/bin`. If it is not found, the
symlink has not been made yet — tell the user to run `relink`, and stop. Do not
reach into the dotfiles checkout by path: this skill runs from whatever project
the session is in.

Useful flags: `--repo PATTERN` to restrict to one project, `--json` for the
full structure, `--days N` to change the window. The window is on transcript
**mtime**, so a session resumed yesterday is in range even if it began months
ago.

Read the header before the numbers: session count, date range, how many
subagent transcripts were excluded, and which weeks have nothing in them.

### 2. Decide whether the distribution can be read at all

Under roughly 20 sessions a p90 is three or four data points. Say so and hedge
every comparison rather than reporting percentiles as if they were stable. If
the weekly series has gaps, do not describe a trend across them.

### 3. Open the outliers

Take at most five, preferring sessions that are outliers on **more than one**
metric — a single high number is usually a long task, while several together
is usually a session that went badly.

Each outlier in `--json` carries a `source_path`. Use it. Do not reconstruct a
path from the session id: a subagent transcript carries its parent's session id,
so the id does not identify a file.

Read the human turns only — a full transcript is megabytes and will not fit:

```
session-extract --human-turns <source_path>
```

What the human said is where friction shows: corrections, restatements of the
same request, abandoned directions, visible irritation. Pull tool detail only
for a specific question the human turns raise, and expect a prompt when you do.

### 4. Report

Numbers first, then what they mean, then what to consider changing. Tie every
claim to a transcript id so it can be checked. Mark which findings are limited
by what the metrics can see.

## Reading the numbers

Each metric describes **how a session ran**, never how good its output was.
Keep that distinction visible in the report.

- **`assistant_per_user`** — turns per human prompt. High means long autonomous
  stretches, which is often exactly what was wanted. It is worth attention only
  alongside something else: large `tool_result_bytes`, or human turns that keep
  restating the same request.
- **`bash_error_rate`** — a **weak** signal that under-counts. Bash results
  carry no exit code, so only commands that wrote to stderr are visible; a
  command that fails quietly is invisible. Treat a high value as real and a low
  value as unproven.
- **`cache_read_tokens`** — dominates cost, typically by orders of magnitude
  over `input`. Large values with few human turns mean a long autonomous run,
  which may be entirely reasonable.
- **`wall_seconds`** — clock time from first to last record, spanning resumes.
  A session can span days while being worked on for an hour. Not time spent.
- **`tool_result_bytes`** — context spent on tool output. The clearest waste
  signal in the set: output that was paid for and mostly not used.
- **`compactions`** — how many times the context filled up and was summarised.
  Each one loses detail the model then re-derives. Nine in one session says
  the work was shaped as one very long session when it wanted to be several.
- **`interrupts`** — the human hit escape mid-turn. Rare and unambiguous: the
  model was doing something the human did not want. Read the turns around it.
- **`user_turns`** counts only what the human typed. A `user` record is also
  how the harness injects skill bodies, compaction summaries, slash-command
  echo and task notifications; those are excluded, and `--human-turns` uses
  the same definition, so the count and the text always agree.
- **Version column in the weekly series** — if medians move at a Claude Code
  version boundary, the cause may be configuration that no longer suits the
  harness rather than a change in how the work is being done. Never conclude
  this from a single boundary; the versions move most weeks.

## What this cannot see

State these limits in the report when they bear on a finding.

- **Nothing about the quality of the code produced.** Every metric currently
  implemented is Tier 1 — record counts and usage numbers. A session that
  wrote bad code efficiently looks good here.
- **File-level rework and convention compliance** are not implemented yet
  (Tier 2 and Tier 3 in the design). Do not infer them from Tier 1 numbers.
- **Reading and writing are not measurable from tool names.** Sessions differ
  enormously in whether they read through `Read` or through `cat` and `grep`,
  so tool mix says little about how carefully the codebase was consulted.
- **Slow degradation that has not been noticed.** This skill runs when asked,
  and it is asked when something already feels wrong. Quiet erosion is exactly
  what it will miss.
- **Subagent runs** are excluded by default. They have one human turn by
  construction and would otherwise fill every outlier slot. Add
  `--include-subagents` to look at them deliberately.
