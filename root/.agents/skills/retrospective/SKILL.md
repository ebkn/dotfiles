---
name: retrospective
description: Review recent AI coding sessions for inefficiency. Aggregates transcripts across sessions into distributions, names the outlying sessions, then reads those sessions to explain what actually happened in them. Use when asked to look back over recent sessions, find where time or tokens went, or check whether the way work is going has been getting worse — triggered by "最近のセッションを振り返りたい", "非効率なところを探して", "セッションの傾向を見たい", "開発の進め方が悪化していないか", "review my recent sessions", "where am I wasting tokens", or the /retrospective command. Not for reviewing a pull request, a diff, or test code, and not for reducing permission prompts.
effort: high
allowed-tools: Bash(session-review *), Bash(session-extract *), Read, Glob, Grep
---

Look across recent sessions, find the ones that stand out, and explain them.

Match the user's language in the report.

## Boundary of this skill: read and measure only

**Never write.** No file edits, no `git add` / `git commit` / `git push`, no `gh pr create` / `gh pr edit`, and no changes to `CLAUDE.md`, `AGENTS.md`, `settings.json`, or any skill. This holds even when asked directly: "also update CLAUDE.md while you're at it" is answered with the proposal, not the edit. A retrospective that edits config closes its own feedback loop — the next run then measures a setup this skill wrote.

**The boundary is this skill's own contract, not something the host enforces.** Some hosts ignore `allowed-tools` entirely (Codex reads only `name` and `description`), and on this machine `git add` / `commit -m` / `push` and `gh pr create` / `edit` are pre-approved, so they would run with no prompt at all. **The absence of a prompt is not permission.**

`Bash` is granted only for `session-review` and `session-extract`, which only read transcripts. Anything else prompts, **which is the correct outcome** — do not work around it.

## Procedure

### 1. Aggregate

```
session-review --days 90
```

`session-review` is on `PATH` via `~/.local/bin`. If it is not found, tell the user to run `relink` and stop; do not reach into the dotfiles checkout by path, since this skill runs from whatever project the session is in.

Flags: `--repo PATTERN` restricts to one project, `--json` gives the full structure, `--days N` changes the window. The window is on transcript **mtime**, so a session resumed yesterday is in range even if it began months ago.

Read the header before the numbers: session count, date range, how many subagent transcripts and scratch sessions were excluded, and which weeks have nothing in them. Scratch sessions are ones Claude ran from its own `/tmp/claude-<uid>` area — evals of this skill, typically — and are not the user's work; `--include-scratch` brings them back deliberately.

### 2. Decide whether the distribution can be read at all

Under roughly 20 sessions a p90 is three or four data points. Say so and hedge every comparison rather than reporting percentiles as if they were stable. If the weekly series has gaps, do not describe a trend across them.

### 3. Open the outliers

Take at most five, preferring sessions that are outliers on **more than one** metric — a single high number is usually a long task, while several together is usually a session that went badly.

Each outlier is printed with its `source_path` (in `--json` as a field). Use it rather than reconstructing a path from the session id: a subagent transcript carries its parent's session id, so the id does not identify a file.

Read the human turns only — a full transcript is megabytes and will not fit:

```
session-extract --human-turns <source_path>
```

What the human said is where friction shows: corrections, restatements of the same request, abandoned directions, visible irritation. Pull tool detail only for a specific question the human turns raise.

### 4. Permission and safety

Read the report's `permission & safety` block separately from the distributions. These events are rare — most sessions have zero — so a median says nothing and the totals carry the information.

- **Denials by kind** — `rule` (a `permissions.ask` entry), `classifier` (auto mode), `user` (declined at the prompt), `hook` (a guard script). A high `rule` count usually means the configuration is fighting itself: look at which commands were refused and whether the instructions asked for them.
- **Retries after a denial** — a denied Bash call followed within three calls by one of the same intent (`rm` → `git clean`, `reset --hard` → `reset`, `--command "UPDATE"` → `--file`). **Any non-zero value is a finding.** A denial is a decision; re-issuing it in another form is the behaviour this metric exists to catch. Open every session it names and quote the pair.
- **Risky commands by kind** — pattern matches: delete, discard, force_push, privilege, pipe_to_shell, remote_write, kill, hooks_bypass, credentials. Heuristic: a heredoc body containing `rm -rf` counts too. Treat the totals as "look here", not as a verdict. `credentials` deserves the command text quoted, since a token read that was *not* denied is the case that matters.
- **Corrections** — typed prompts matching a push-back word list (いらない, 不要, やめて, don't, wrong, …). It under-counts and has misfired before; its value is the sessions it points at. Read those turns and say what was pushed back on.
- **Convention breaches** (`interpreter_oneliners`, `compound_cd`, `absolute_bin`) — this repo's rules, counted so their trend is visible. An `absolute_bin` such as `/usr/bin/ssh` is also how a prefix rule gets sidestepped.

### 5. Report

Numbers first, then what they mean, then what to consider changing. Tie every claim to a transcript id so it can be checked. Mark which findings are limited by what the metrics can see, and give the permission & safety findings their own section — they are the ones a reader will act on.

## Reading the numbers

Each metric describes **how a session ran**, never how good its output was. Keep that distinction visible in the report.

Every metric carries a tier, and the report must say which: **1** is a count over records and cannot be wrong about what it counts; **2** is a pattern match on command text and can misfire either way; **3** is a convention of this repo or a word list, meaningful here and nowhere else.

- **`assistant_per_user`** — turns per human prompt. High means long autonomous stretches, which is often exactly what was wanted. It is worth attention only alongside something else: large `tool_result_bytes`, or human turns that keep restating the same request.
- **`bash_error_rate`** — a **weak** signal that under-counts. Bash results carry no exit code, so only commands that wrote to stderr are visible. Treat a high value as real and a low value as unproven.
- **`cache_read_tokens`** — dominates cost, typically by orders of magnitude over `input`. Large values with few human turns mean a long autonomous run, which may be entirely reasonable.
- **`wall_seconds`** — clock time from first to last record, spanning resumes. A session can span days while being worked on for an hour. Not time spent.
- **`tool_result_bytes`** — context spent on tool output. The clearest waste signal in the set: output that was paid for and mostly not used.
- **`compactions`** — how many times the context filled up and was summarised. Each one loses detail the model then re-derives; a high count says the work was shaped as one very long session when it wanted to be several.
- **`interrupts`** — the human hit escape mid-turn. Rare and unambiguous: the model was doing something the human did not want. Read the turns around it.
- **`user_turns`** — only what the human typed; the harness's own injections (skill bodies, compaction summaries, slash-command echo, task notifications) are excluded, and `--human-turns` uses the same definition.
- **Version column in the weekly series** — if medians move at a Claude Code version boundary, suspect configuration that no longer suits the harness before suspecting the work itself. Never conclude this from a single boundary; the versions move most weeks.

## What this cannot see

State these limits in the report when they bear on a finding.

- **Nothing about the quality of the code produced.** Every metric describes the session, not its output. A session that wrote bad code efficiently looks good here.
- **File-level rework** is not measured. Which files a session touched is only visible through `Edit`/`Write` results, and many sessions write through Bash instead.
- **Reading and writing are not measurable from tool names.** Sessions differ enormously in whether they read through `Read` or through `cat` and `grep`, so tool mix says little about how carefully the codebase was consulted.
- **Slow degradation that has not been noticed.** This skill runs when asked, and it is asked when something already feels wrong. Quiet erosion is exactly what it will miss.
- **Subagent runs** are excluded by default. They have one human turn by construction and would otherwise fill every outlier slot. Add `--include-subagents` to look at them deliberately.
