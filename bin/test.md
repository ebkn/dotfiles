# test

`bin/test` runs the repo's test suites in parallel, and is what CI runs: the
test job installs the tools the suites run against and then runs `bin/test`,
nothing else. How a suite should be shaped is in [testing.md](testing.md);
this file is about the runner.

```
bin/test                 every tracked *.test.sh / *.test.zsh, minus the skips below
bin/test <suite>...      just those, whatever the skips say
bin/test --list          what a bare run would run and skip, and why
TEST_JOBS=<n>            suites at once (default: CPU count, at most 4)
TEST_TIMEOUT=<s>         a suite running longer is killed and failed (default 600)
```

## What it runs

**Suites are discovered with `git ls-files`**, so an untracked suite is not run
(the rule `bin/lint-shell` follows; `git add` first). The workflow used to list
its ~45 suites one step each, and three were written, documented as gating CI
and run by nothing. Discovery has no list to be missing from.

A bare run skips two kinds of suite, and `--list` says which and why:

- **The exclusions in `bin/test.skip`**, `<path>|<reason>` per line; the
  file is the list, and `bin/test --list` prints it with the reasons. A
  suite that would exit 0 with "skipping" where its tool is missing belongs
  there, not in the run: run anywhere without the tool, it is a permanently
  green check that proves nothing. A file rather than a list inside the
  script, so `bin/test.test.sh` can give its fixture repository a list of its
  own. Entries match the whole path (a substring match
  would also skip a suite whose path is the tail of an excluded one), and an
  entry naming no tracked suite fails the run: only the runner can see one,
  since `--list` prints a skip only for a suite the listing found.
- **The tmux suites, outside a container or CI.** They refuse a developer
  machine (`bin/tmux-test-guard.sh`), so on a laptop they are reported as
  skipped and `bin/test-in-docker` runs them -- the list it takes from this
  `--list`, by reading its `skip <path>  (a tmux suite: …)` lines, so the two
  cannot disagree and that line's shape is an interface. They are found by
  the sourcing line `bin/tmux-test-guard.test.sh` checks for.

`bin/ci-enrollment.test.sh` holds the rest of the old guarantee: the workflow
runs `bin/test`, and in CI's environment `bin/test --list` succeeds and runs or
skips, with a reason, every tracked suite.

## How it fails

The runner can fail the way a lint gate does, by running less than it should
and reporting green, so the verdict is built to fail closed:

- **The listing is a command substitution with its status checked**, and an
  empty one is an error — never "ran nothing, all green" (see `bin/lint-shell`'s
  header for the time that happened there).
- **The verdict comes from GNU parallel's job log, checked against the list it
  was given.** parallel's own exit status counts failed jobs, but a job that
  never started is counted nowhere; a log with fewer rows than suites fails the
  run.
- **A suite past `TEST_TIMEOUT` is killed and reported, with what it printed
  before.** Each suite writes to a file first, so a killed one still leaves its
  output, and every block is printed whole rather than interleaved.
- **stdin is `/dev/null`**: a suite that reads it sees EOF instead of hanging.

Output: a passing suite is one `ok   <suite>` line locally; under GitHub
Actions its output is kept inside a folded `::group::`. A failing suite prints
`FAIL <suite> (exit N)` and its whole output. The end is a table of every suite
that took a second or more, slowest first — the budget in testing.md made
visible — then `N passed, M failed` and the failed suites by name.

`bin/test.test.sh` pins all of this against a throwaway repository of tiny
suites, with the real parallel. It overrides the two environment probes
(`GITHUB_ACTIONS`, and `TEST_CONTAINER_MARK` for `/.dockerenv`), since it runs
on a laptop, in the container and in CI and must see both answers in each.
`bin/test-in-docker` sets the same two to ask for the laptop's list of tmux
suites, so they are an interface, not a test hook.

## Open: which bash runs a suite

`bin/test` starts every `*.test.sh` with PATH's `bash` — Homebrew's 5.x on a
developed Mac — whatever its shebang says. CI is unaffected (the workflow ran
`bash <path>` before too), but the suites declaring `#!/bin/bash` — under
`bin/` and `root/`, the permission hooks' among them — were the only place
bash 3.2 was exercised, and only when run directly. Choosing the
interpreter from the shebang would restore that; it is a behaviour change and
may surface suites that pass only on bash 5, so it waits for its own change.

## GNU parallel

Chosen over `xargs -P` and a hand-written scheduler for its job log, grouped
output and per-job timeout, and over bats-core because bats would only have
wrapped each suite as one test: its assertions and per-test parallelism need
the suites rewritten (testing.md, rules 6 and 7).

**Pinned like the linters**, because it decides which suites ran and whether
they passed: version 20260922 in the workflow, `bin/test-in-docker.Dockerfile`
and `brewfiles/Brewfile-shell` — bump all three together. The runner image
carries apt's 20231122; the workflow's copy lands in `/usr/local/bin` ahead of
it.

**The citation notice.** In a terminal, parallel prints a request to cite it
until `parallel --citation` has been run once. `bin/test` does not pass
`--will-cite`: the author asks scripts run by others not to, since the notice
is how the project is funded. In CI stderr is not a terminal, so nothing is
printed there.

## The job count

Measured on an 18-core Mac, a full host run (35 suites) took ~55 s at 4, 6, 8
and 12 jobs alike, against 142 s one at a time — and 67 s at 18, with
`zsh/ssh-keepalive.test.zsh` failing. The suites are fork-heavy, so past a
handful of jobs they queue on the kernel instead of running: init-project's
grader test went from 11 s alone to 66 s at 18 jobs. Later runs of the same
set took 55–75 s, the four heaviest suites (lint-shell's, and the three eval
grader tests) each stretching from ~12 s to ~50 s side by side. Hence the
default cap of 4 — as fast as any higher figure, and the lightest load for a
suite that waits on a real clock; CI's runner has 4 CPUs anyway. The lever
beyond it is the process count of the suites themselves (testing.md, rule 4),
not more jobs.

`TEST_JOBS` is exported to the suites — the figure `bin/test` chose, not only
one the caller set — so review-design's sharded grader test splits itself the
same number of ways instead of across every CPU on top of these jobs. `zsh/ssh-keepalive.test.zsh` is the suite that shows
overload first: it waits on a real supervisor's poll.

## What each suite gates

Why each suite is worth running on every push — moved here from the per-suite
steps the workflow used to carry. The suite's own doc (CLAUDE.md, Testing)
has the detail. **This list is kept by hand and nothing checks that it is
complete**: a suite missing from it still runs, since `bin/test` finds suites
by itself. Add a line when you add a suite.

- **`ci-enrollment.test.sh`** — CI no longer lists its suites, but it must
  still run `bin/test`, and every suite must be run or skipped with a reason;
  under the old hand-written list, three suites were documented as gating CI
  and run by nothing.
- **`test.test.sh`** — the runner fails the way a lint gate does, by running
  less than it should and reporting green; this pins every way it could.
- **`test-lib.test.sh`** — the helpers suites source decide their verdict, so
  a helper that loses a FAIL makes every suite using it green; this pins the
  output contract and the verdict under `set -u` and `set -e`, on bash 3.2.

- **Permission hooks** — `curl-guard`, `rm-guard`, `approve-multiline-commands`.
  These are the hooks that emit "allow", so a regression widens a permission
  boundary silently rather than breaking a feature: the command just runs.
- **retrospective** `session-extract`, `session-review` — run against synthetic
  transcripts, needing only jq. The reporter test also runs `bash -n` on the
  script: it is one long single-quoted jq program, and an apostrophe in a jq
  comment has twice ended the string and failed every case at once.
- **`skill-eval.test.sh`** — bin/skill-eval is the only instrument for "did
  that SKILL.md edit help", and every way it breaks leaves a green run that
  measured nothing: a dropped allowed-tools, a fixture that can read its own
  grader, a swallowed FAIL. claude is stubbed, so no API call; the eval cases
  themselves never run in CI, since they would spend.
- **Eval graders** — init-project's swift case (which also extracts and runs
  the Makefile from `references/swift.md`, so a TAB lost in the documentation
  fails here), review-test's and review-design's cases. An inert grader reports
  a green, paid, non-deterministic eval run that measured nothing.
- **`relink.test.sh`** — link_with_backup moves real files out of `$HOME` on
  every update-all: a backup that replaces an earlier one, or a "backup" of a
  file that is the repo's own, loses data with no error. The setup workflows
  only show a bootstrap exited 0.
- **`git-generated.test.sh`** — asserts on what `git diff` prints after it
  writes `$GIT_DIR/info/attributes`.
- **`fzf-files.test.sh`** — the list behind prefix + o and nvim's `:Files`; its
  regressions fill the picker in the wrong order, or not at all, without error.
- **`launchd-load.test.sh`** — which launchctl calls it makes, launchctl
  stubbed: load through the linked path, never restart a running agent, change
  nothing under `--status`; and every plist's Label matching its file name.
- **`textlint-docs.test.sh`** — npm stubbed: when to install, that a failed
  install is not mistaken for a finished one, and which ignore list textlint
  gets — a wrong one skips files without a word.
- **`read-doc.test.sh`** — read-doc renders untrusted documents: the page must
  load nothing, and an image may only come from the document's own tree.
- **`tmux-test-guard.test.sh`** — every tmux suite must refuse a developer
  machine, where one missed `unset TMUX` killed the real server.
- **`agent-state.test.sh`** — the tab glyph and the prefix + a picker run off
  tmux pane options, against a real throwaway server: tmux is the subject under
  test, and the suite fails rather than skips without it.
- **`tmux-popup.test.sh`** — the prefix + p/t/o guards match popup sessions by
  `_*`; breaking the naming makes the chord stack popups with no error. Also
  tmux-tig, whose failed tig must leave its message on screen, and fzf-nvim.
- **`tmux-conf.test.sh`, `tmux-cheatsheet.test.sh`** — `.tmux.conf` is never
  re-read on a working machine, so a bad line sits there unnoticed; a bind that
  lost its `-N` keeps working while vanishing from the cheatsheet; a key column
  one token off still prints a plausible page.
- **`tmux-session-swap`, `tmux-track-session`** — one WezTerm tab means one
  tmux session, which tmux does not enforce; both fail silently, the old tab
  mirroring another minutes later, after an autossh reconnect.
- **`tmux-restore-tabs`, `tmux-restore-ssh-tabs`** — restored tabs must land in
  the window they were asked from, on the exact session, one per remote
  session. Both broke silently once; a failed `adopt` read as an empty list
  would restore nothing and say so politely.
- **`tmux-pane-titles`, `tmux-agents`** — both turn pane options into something
  a person reads, so every mistake renders a plausible wrong answer.
- **`tmux-agent-view.test.sh`** — the answer view's name must match the `_*`
  guard and `C-]` must stay bound, or the leave key types into the agent's own
  pane.
- **`autossh-ssh.test.sh`** — the reconnect shim owns the screen between
  attempts: a wrong passthrough breaks every first connection, a wrong notice
  leaves a dead frame and a flood of mouse reports.
- **`wsl/notify-send.test.sh`** — every write ends in `|| true`, so a misparsed
  flag is simply no notification. On the runner its `#!/bin/sh` is dash, as on
  WSL.
- **PR pipeline** — `pr-review-common` (the lock: refusing a dead holder's lock
  stops the pipeline silently, stealing a live one interleaves writes),
  `pr-review-watch` (a filter matching nothing looks like "no reviews"; one
  that keeps the token's own comments builds a reply loop),
  `pr-review-dispatch` (the socket schema is undocumented and a rejected line
  is dropped silently, so the exact bytes are asserted on a real socket),
  `pr-state-watch` (reading GitHub's lazy UNKNOWN as mergeable goes quiet;
  re-announcing an unchanged conflict trains its reader to ignore it).
- **zsh** — `ssh-parse-argv` (a hand-copied option list rots when openssh adds
  one, and myssh reconnects elsewhere), `ssh-decorate` (a pane left decorated
  swallows prefix + p forever), `ssh-session` (`MYSSH_SESSION` must reach the
  remote as one argument), `rm` (both failures look like a successful delete),
  `fd` (a misplaced cd is invisible), `git-worktree` (gdmerged deletes, gw
  checks out others' PRs: run against real repositories), `ssh-keepalive` (the
  supervisor is the only bound on a disowned ping), `zshrc-resolve` (a wrong
  expansion starts a shell with no configuration), `zshenv-autofs` (the Linux
  runner checks the macOS guard as well as the Linux side), `his` (run on the
  runner against GNU sed, on a Mac against BSD sed — the pair is the only check
  that they agree), `update` (a warning that stopped firing looks like a
  healthy machine; on the runner the kernel release and uptime are stubbed and
  the two Mac-only cases are skipped).
- **`lint-shell.test.sh`** — lint-shell discovers its own targets, and that
  discovery fails by checking almost nothing and reporting ok; this is the only
  check that the gate is looking at the repo. Its checkers are stubbed, so it
  runs here rather than in the lint job.
