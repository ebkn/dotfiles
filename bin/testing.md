# Writing shell test suites

How a `*.test.sh` suite here should be shaped so that it stays fast, and why.
Each suite's own `.md` keeps *what* it pins; this file keeps the rules every
suite shares. The zsh suites follow the same output contract and the waiting
rules, but not the helper library, which is bash.

**Status: target, not yet the state of the repo.** The migration list at the
end says what still deviates. Until a rule's step there is done, "the suite
does X" below means "a new or touched suite should do X".

## What a test costs here

Measured on macOS (Apple silicon, 2026-10), 200 calls each:

| Operation | Cost |
| --- | --- |
| builtin (`:`, `case`, `[ ]`, `${var#…}`) | 0.03 ms |
| subshell `$(:)` | 0.6 ms |
| any external command (`/usr/bin/true`) | 1.4 ms |
| `bash -c :` | 1.8 ms |
| `jq -n 1` | 2.5 ms |
| `git --version` | 3.1 ms |
| `git init` + one commit | 25 ms |

So **the run time of a suite is roughly (processes spawned × 2 ms) + time spent
waiting.** The number of cases is not the variable: `pr-state-watch.test.sh`
checks 156 things in 7 s and spawns about 8 processes per check, while
`review-design/evals/assert.test.sh` checked 169 in 112 s before migration step
2 and spawns about 133 per check (22,563 `jq`/`git`/`grep`/`sed`/`awk`/`cat`
calls, counted with shims).
Linux forks are roughly twice as cheap, so CI hides what macOS shows.

The other cost is waiting, and the expensive waits were not in the tests: of
`pr-review-dispatch.test.sh`'s 111 s on CI, 105 s was 21 deliveries each idling
out `nc -w 5` (Linux netcat does not close on stdin EOF).

## Rules

### 1. Wait for an observable, never for a duration

A fixed `sleep` is either too short (flaky under load) or too long (paid on every
green run). Poll for the thing the assertion is about, with a deadline that is
only reached when the test is failing:

```bash
wait_until 5 test -s "$out" || fail "nothing was written"
```

A **negative** assertion ("nothing was sent", "the view did not open") is the
trap: polling for an absence always runs to the deadline. Wait instead for a
positive event that proves the branch has been decided — a log line, a state
file, the process exiting — and then check the absence once. **The event must
come after the last moment the unwanted effect could start**, or it decides
nothing: `tmux-agents` logs a refusal *before* the line where a missing
`exit 0` would fall through to opening a view in the background, so waiting
for the log line and then reading "no view" passed with that `exit 0` deleted.
Models:

- `tmux-agents.test.sh`'s `wait_said`: the refusal's line in tmux's message
  log, for the effects that would come before it.
- `ssh-keepalive.test.zsh`'s `settled_pings` waits for the supervisor that must
  lose the lock race to exit; its `wait_poll` plants an owner file for a pid
  that cannot exist and waits for a poll to prune it, twice.
- `tmux-track-session.test.sh` starts a job that fails on purpose after the
  monitor dies, waits for its report, and checks that nothing came before it.

When nothing observable decides it, a short fixed window is the honest
remainder, with a comment saying so: `tmux-agents`' `no_view_after` (1 s, the
case above), `settled_pings 0` (1 s, a ping that should never start), and the
0.5 s that `tmux-popup` and `tmux-cheatsheet` wait to show a pane does not
close on its own.

Two more ways to stop paying for a wait that is already over:

- `tmux run-shell` **without `-b`**, and `display-popup` run from the command
  line, **block** until their command exits (both measured on 3.7c), so what
  that command did to the server is done when they return; a poll after them
  only adds its first sleep. Not what the command *started*: a `run-shell -b`
  or `&` inside it can still be on its way.
- A wait for tmux's one-second `session_created` or an epoch-second stamp to
  differ waits for the clock to pass that second, not for `sleep 1`.

### 2. Every interval in a program under test can be shortened from outside

If the program sleeps or times out, the test pays it unless the program reads
the interval from the environment. Default unchanged; the test sets it small:

```bash
: "${TMUX_TRACK_SESSION_POLL:=2}"   # in the program
TMUX_TRACK_SESSION_POLL=0.05 tmux-track-session monitor …   # in the test
```

`zsh/ssh.zsh`'s `_SSH_KEEPALIVE_POLL` already does this. Name the variable after
the program, and list it in the program's `.md`. This is a seam for time only;
it does not license a test-only branch in the program.

### 3. Build a fixture once, copy it per case

A case needs its own directory, not its own build. Build the fixture (a git
repo, a fake `$HOME`, a scaffolded eval) once per file, then `cp -R` it into
each case's directory: 20 ms against 116 ms for one review-design scaffold.
Isolation is unchanged, because every case still mutates only its copy.

### 4. Spend processes in the loop on purpose

Inside a check that runs many times, prefer builtins to external commands:

- `case "$out" in *"$want"*)` rather than `grep -q` for "contains";
- `${var#prefix}` / `${var%suffix}` rather than `sed`/`cut`;
- one `jq` that emits every field you need (`@tsv`, `read`) rather than one
  `jq` per field;
- `<<<` rather than `printf … | cmd` (also avoids the SIGPIPE-under-pipefail
  failure that `ci-enrollment.test.sh` documents).

Do not contort a check to save a process outside a loop; 2 ms once is nothing.
When the slow part is the *program under test* (a grader that spawns 100
processes per run), do not optimise the program for its test: the lever is
how many times the test runs it, and running those runs at once (rule 7).

### 5. One output contract

Every suite prints one line per check and exits accordingly:

```
ok   <what was checked>
FAIL <what was checked>
     <want/got detail, indented>
```

and ends with a summary line; the exit status is 0 if and only if no `FAIL`
was printed. Fixed columns, no leading indent: a runner and a reader can then
count and filter results across suites. (Today about eight helper dialects
print `ok`, `  ok`, `PASS`; counting them took a regex per dialect.)

### 6. Shared helpers live in `bin/test-lib.sh`

One sourced fragment instead of a hand-rolled `t`/`check`/`ok`/`eq` per file:

- assertions: `assert_eq`, `assert_contains`, `assert_not_contains`,
  `assert_status` — each prints the rule-5 lines;
- `wait_until <seconds> <cmd…>` for rule 1;
- `test_tmpdir` with an EXIT trap that kills the pids registered through
  `track_pid` and removes the directory;
- `run_tests`: runs every `test_*` function, each in a subshell (0.6 ms; a
  case cannot leak `cd` or variables into the next), skipping those that do not
  match `$TEST_FILTER`, then prints the summary and sets the exit status.

It is a sourced fragment, so per the shell conventions: bash 3.2, no shebang,
no `set`, `# shellcheck shell=bash`, and named inline in `bin/lint-shell`.

**Why not bats-core.** It gives filtering, TAP output and parallel cases, and
supports bash 3.2. Against it: it is one more tool pinned in three places
(workflow, Dockerfile, Brewfile), and its benefits arrive only after a suite is
rewritten into `@test` blocks — 18,000 lines here. The fragment can be adopted
one suite at a time, and every suite already prints something close to rule 5.
Reconsider if the fragment grows a parallel runner of its own.

### 7. Run suites in parallel; cases within a suite in order, with one exception

Suites share nothing (each has its own temp dir and tmux socket), so `bin/test`
runs them concurrently and prints each one's wall time, slowest first
([test.md](test.md)). On a Mac that pays off up to about 4 jobs and then stops:
the suites are fork-heavy, so past that they queue on the kernel (~55 s for
the host suites at 4–12 jobs, from 142 s one at a time). Cases inside a suite
stay sequential: parallel cases interleave output and need every fixture to be
safe to share, which usually buys less than rule 3 does.

**The exception is a suite made of independent scenarios that each cost
hundreds of milliseconds in a program it cannot make cheaper** — the eval
graders, where ~70 % of every scenario is the grader under test. There rule 3
saved 16 % and sharding saved the rest:
`review-design/evals/assert.test.sh` runs itself as `TEST_JOBS` shards (one
per CPU alone, `bin/test`'s job count under `bin/test`), each
scenario's output tagged with its index and merged back into source order, so
the scenarios' output matches a sequential run line for line; the merge's
self-check lines come first and the summary adds the shard count. The merge
fails closed: green needs a token printed only once every scenario left a block
holding a check, so a shard that dies — or a merge that breaks — cannot become
a shorter green run. Because a real run only ever exercises the green verdict,
every run first checks the merge's failing verdicts against made-up shard
output. Shards run on `"$BASH"`, not on PATH's bash, or the bash 3.2 constraint
stops being exercised on a Mac — though under `bin/test`, which starts every
bash suite with PATH's bash, `"$BASH"` is that one too (an open item in
[test.md](test.md)). `TEST_JOBS` overrides the shard count;
`TEST_SHARD` is the driver's handshake with each shard and is never set by
hand — a shard run alone checks only its own subset.

That is ~175 lines of harness, a third of it the merge's self-check (the
`shard_*` functions). A suite calls it in three places: `shard_drive <script>
<suite name>` once, before it creates anything needing cleanup (the driver sets
its own EXIT trap and exits); `shard_begin` where each scenario starts; and
`shard_end` as its last line. So it stays in that suite until a second one
needs it, then moves to `bin/test-lib.sh`. **That move is the trigger rule 6 names for
reconsidering bats-core** — decide it then and record the answer in rule 6.
Weigh too what adoption costs a suite whatever the harness looks like: every
helper that runs between scenarios needs the `skipping` guard, and any variable
top-level code reads after a scenario must be initialised, because a shard walks
the scenarios it skips.

The tmux suites run the same way inside the `bin/test-in-docker` container.
Their sockets look isolated (`$$`-suffixed or a private `TMUX_TMPDIR`), but that
is unverified until they have been run concurrently a few times.

### 8. CI runs `bin/test`: no suite hides another

The `test` job used to run ~45 suites as one step each, and the first red step
skipped every later one: from 2026-10-09 a broken pipe in
`tmux-test-guard.test.sh` kept 28 suites from running at all until it was fixed
on 10-14. Splitting the job by toolchain was the first plan; the runner made it
unnecessary. The job now installs the pinned tools and runs `bin/test`, which
runs every suite to the end and reports every failure — and CI and a laptop run
the same command, as they already did for `bin/lint-shell`. What is lost is
GitHub's per-step folding and timing; `bin/test` prints a `::group::` per suite
and its own time table instead.

### Budget

A suite that takes more than **5 s on macOS** has a cause worth finding; one over
10 s is a bug. `bin/test` printing per-suite time is what keeps this visible.

## Migration, in order of time saved

Estimates are from the measurements above, not yet confirmed by doing the work.

| # | Change | Expected effect |
| --- | --- | --- |
| 1 | **Done.** `pr-review-dispatch`: close the socket on EOF. **macOS `nc -N` is not Linux's `-N`** (it sets write-timeout probes), so the fix cannot be one flag. Behaviour change: regression test first | CI −105 s |
| 2 | **Done for review-design.** Rule 3 (112 → 94 s), then sharding per rule 7's exception (→ 34 s on 18 cores). The estimate assumed fixtures dominated; a profile showed the grader is ~70 % of a scenario. review-test (12 s) and init-project (11 s) are left: under the 10 s line by little, and not yet worth the harness | macOS 112 s → 34 s |
| 3 | **Done.** `bin/test` (rule 7) and CI running it (rule 8). Not the slowest suite, as estimated: the Mac stops scaling at ~4 jobs | host suites: macOS 142 s → ~55 s |
| 4 | `bin/test-in-docker` through `bin/test`, so the tmux suites run in parallel too; then `bin/test-lib.sh` (rules 5, 6) | — |
| 5 | **Done.** Rule 2 for `tmux-track-session` (`TMUX_TRACK_SESSION_POLL`); rule 1 for the fixed sleeps in `tmux-track-session`, `tmux-agents`, `ssh-keepalive`, `tmux-restore-tabs`, `tmux-pane-titles`, `agent-state`, and the 0.25/0.2 s steps of polls that run to a real wait cut to 0.05 s (those right after a blocking `run-shell`, which never sleep on a green run, left as they were). Left on purpose: `tmux-agents`' 2 s list refresh (`REFRESH`, readonly; a shorter one would reload under the cursor cases), the fixed windows rule 1 lists | in the container: track-session 23 → 11 s, tmux-agents 43 → 33 s, ssh-keepalive 12 → 4.5 s (host 11.4 → 4.3 s), pane-titles 5.3 → 2.7 s, agent-state 47 → 42 s, restore-tabs 3.1 → 2.6 s |

Existing suites move to the helper fragment when they are next touched, not in
one sweep: the rewrite would be large and the gain is consistency, not speed.

Open: `zsh/ssh-keepalive.test.zsh` fails under load — once alone ("the last
session ending stops it"), once in an 18-job `bin/test` run ("a session starts
a ping"). The suite already polls at 0.2 s, so the suspect is its 4 s
deadlines (`first_ping`, `wait_gone`) on a loaded machine. Unconfirmed.
