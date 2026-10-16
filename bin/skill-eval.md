# skill-eval — measuring a skill's behaviour

`bin/skill-eval` runs the eval cases of a skill this repo owns: it builds a
throwaway fixture, runs `claude -p` against it under the skill's own
`allowed-tools`, and grades the result with the case's `assert.sh`.

It exists because **a skill's behaviour is invisible in its diff.** Editing
`SKILL.md` changes what a model does, not what a program does, so "did that
help" cannot be read off the change, and trying it once by hand proves nothing
about a non-deterministic system. The cases here are the only way to compare
before and after on something other than an impression.

Ported from `tetsunavi-monorepo`'s `scripts/skill_eval` (PR #7032 added the
proactive case there). The divergences are recorded below rather than papered
over.

## Running it

```sh
bin/skill-eval review-test                              # every case, once each
bin/skill-eval review-test proactive-after-writing-tests --runs 3
bin/skill-eval review-test gaps-in-error-contract --keep # keep the fixture to debug a FAIL
```

**Every run spends model usage on your Claude Code credentials** — the same
login your interactive sessions use; no separate key is issued for it. What
that costs depends on how Claude Code is authenticated. With an API key or a
Console login it is billed per token. On a Pro or Max subscription it draws on
the plan's usage limits instead, and the dollar figures the runner prints are
Claude Code's own estimate at list price, [not a
bill](https://code.claude.com/docs/en/costs). The `apiKeySource` field of a
transcript's `init` record says which credential a run used (`none` means the
subscription login). Either way `--max-budget-usd` (default 1 USD per run,
measured on that estimate) is the only cap. The default model is sonnet
(`--model`); the `check_llm` judge is haiku (`SKILL_EVAL_JUDGE_MODEL`).
Artifacts land in `tmp/skill-eval/<skill>/<case>/<timestamp>/run-N/`
(`transcript.jsonl`, `result.json`, `assert.log`, `git-log.txt`,
`git-status.txt`, `rounds.jsonl`), which is gitignored.

**How heavy each call of the skill was is recorded, not graded.** For every
run the runner writes `rounds.jsonl` — per call of the skill, the P1/P2 items
it left open, the tool calls made inside the fork, and the time and tokens
where the transcript carries them (`null` where it does not) — prints one
`round:` line each, and lists the rounds of every run in the summary's
`rounds` column (`2,2,5`, never a mean). There is no threshold on any of
it yet: a ceiling picked before a few runs show the spread would be either
flaky or meaningless. Whether a forked Skill's `tool_result` record carries
`totalDurationMs` / `totalTokens` at all is unverified; if every run prints
`ms=-`, the fork's tool calls are the only per-round measure there is, and the
run's own `duration_ms` the only time.

A single green run means little. The output wobbles, so raise `--runs` before
concluding that an edit helped.

## Writing a case

Three files in `root/.agents/skills/<skill>/evals/<case>/`:

| File | Role |
| --- | --- |
| `prompt.md` | the prompt for `claude -p`. Leading YAML frontmatter is stripped before it is passed, and carries the case's own `allowed_tools` / `max_turns` / `budget_usd` / `claude_md` / `skills` (see [What the eval can and cannot see](#what-the-eval-can-and-cannot-see)) |
| `scaffold.sh` | builds the fixture; cwd is an empty temp dir. Source `$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh` and call `skill_eval_init_repo`, which tags the starting state `eval-base`. A non-zero exit stops the whole run as `case <name>: scaffold.sh exited N` — a broken harness is not graded as a failing skill. With `--keep` the half-built working directory is kept and named |
| `assert.sh` | grades; cwd is the working directory after the run. Source `$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh`, emit one `check` per assertion, end with `skill_eval_finish`. Any `FAIL` line in its output fails the run even if the script exits 0, so a grader that forgets `skill_eval_finish` cannot report `[PASS]` |

`allowed-tools` is read from `SKILL.md`'s frontmatter only; a body line starting
with the key is documentation, not configuration.

Functions available to `assert.sh`: `check`, `check_eq`, `check_match`,
`check_not_match`, `transcript_denials`, `transcript_commands`,
`transcript_result_text`, `transcript_tool_uses <tool>`,
`transcript_skill_uses <skill>`, `transcript_first_tool_index <tool>`,
`transcript_first_command_index <regex>`, `transcript_command_indexes <regex>`,
`transcript_first_text_index <regex>`,
`transcript_tool_uses_precede <tool> <index>`,
`transcript_skill_rounds <skill>`, `transcript_caller_writes_between <from> <to>`,
`review_loop_reran_only_after_findings <skill>`,
`review_loop_fixed_before_each_rerun <skill>`, `review_loop_ended_clean <skill>`,
`review_loop_rerun_checks <skill>`, `review_loop_checks <skill>`,
`check_llm <label> <rubric> [<text>]`.

**The review loop is graded per round, not by a count.** `review-test` and
`review-design` both fix their P1 and P2 findings and review again until a
round reports none. Two Skill calls are the same number whether the second
followed a fix or was the same review started twice, so
`transcript_skill_rounds` takes each call apart: its brief, the report it handed
back (the forked `tool_result`, which the caller may never have written out),
how many P1/P2 items that report lists, and how many tool calls the fork made.
The three `review_loop_*` predicates are built on it — no re-run after a clean
round, a caller write before every re-run, and a clean last round — and
`bin/skill-eval.test.sh` pins each against a two-round fixture transcript.
A case calls them bundled as `check` lines, not one by one:
`review_loop_rerun_checks` and `review_loop_checks`, whose comment says what
each asks and which case calls which. A check on the re-runs — a ceiling, say
— goes in `review_loop_rerun_checks`, so it reaches every case that calls
either bundle; that comment names the two that call neither.
A fix made through `Bash` instead of `Write`/`Edit` is invisible to them; the
review cases open no command that writes.

Where they apply: a case whose first round **must** find something
(`review-test`'s `gaps-in-error-contract`; `review-design`'s
`stale-doc-after-change`, `pass-through-layer`, `hidden-clock-no-seam`,
`next-change-scattered`) also requires two rounds and a brief fit for the
re-run — naming the fix for `review-test`, carrying the last `Reviewed:` line
for `review-design` (`*_check_loop` in each skill's `grading.sh`).
`intended-layer-asks` runs no loop checks at all: its finding crosses the
range, so in a run nobody can answer it stays open and no round can come back
clean — though the case can still re-run, and nothing grades whether it does.
The proactive cases, whose first round may or may not find something, run
`review_loop_checks`. `clean-unit-no-false-p1` runs `review_loop_rerun_checks`
only — a P2 may be raised and fixed there, but whether the loop ended clean is
not asked. `well-tested-no-false-p1`, with nothing to find, asks only that the
review was not started again, and runs neither. The loop needs a second forked review, so the cases that
require one raise `max_turns` / `budget_usd` in their frontmatter, each with a
comment saying why. **None of this has been measured on real runs yet.**

**Starting too often has cases of its own.** `review-test`'s
`no-fire-test-typo` (a committed change to a test file that changes nothing it
asserts) runs with `root/CLAUDE.md`, because that is where `review-test`'s
auto-start rests and without it the case would pass by never starting
anything. `review-design`'s `no-fire-small-fix` runs without it, which is
meaningful only because `review-design` starts on its description alone (9/9,
measured before `context: fork`, in its `evals/README.md`); it has no
CLAUDE.md variant yet. `proactive-at-breakpoint-with-claude-md` is
`review-design`'s counterpart of `proactive-with-claude-md`.

The four index functions exist for **ordering** assertions, which is what is
left once a skill's caller acts on its report in the same run: "never wrote" is
no longer true of the run, while "wrote nothing before the report" still
separates the skill from its caller. They return a 0-based record index, or
empty when there is no match.

**Assert on the observable contract, not on the exit status** — `claude -p`
exits 0 for a run that did nothing. What a case can actually see is what the
skill wrote, what it refused to write, which tools it reached for, and what the
report says.

`check_llm` asks a toolless `claude -p` whether the text satisfies a rubric. It
is for contracts no regex can state ("P1 names the untested error contract").
The verdict is itself non-deterministic, so keep everything expressible as a
deterministic check on one, and read an LLM-graded case across several runs.
A judge that cannot be reached counts as **FAIL**, deliberately: treating it as
a pass is how a case stays green while grading nothing.

### The two things a case must not do

- **Do not let the model read the grader.** The runner copies the skill into the
  fixture without its `evals/`, and `bin/skill-eval.test.sh` pins that.
- **Do not let the harness leak into the fixture.** The `.claude/` the runner
  brings in and the `bin/` a scaffold uses for stubs are added to
  `.git/info/exclude`, so a skill reading `git status` sees the fixture and
  nothing else. The runner writes that exclude only after the scaffold returns,
  while `.claude/` is already there when it starts, so `skill_eval_init_repo`
  excludes `.claude/` itself before its first commit — otherwise the skill
  under evaluation is committed into the fixture's history, where a clean
  `git status` cannot show it. `bin/` stays the scaffold's job: write stubs
  *after* `skill_eval_init_repo`.

### Adding tools a scenario needs

A case that measures whether a skill **starts by itself** has a problem: the
scenario has to be carried out before the skill can trigger, and that needs
tools the skill does not have (writing tests, for `review-test`). Put those in
`prompt.md`'s frontmatter:

```yaml
---
name: proactive-after-writing-tests
allowed_tools: Skill, Write, Edit, Bash(./run-tests.sh*)
---
```

They are added to the skill's `allowed-tools`, never substituted for them. **Do
not widen the skill's own frontmatter to make a case pass** — that changes the
thing being measured.

A scenario that needs **another skill** names it the same way, comma-separated
(`skills: update-pr, commit`). `create-pr`'s cases follow a unit from its first
commit to a finished PR, which is three skills' work. Each one is carried in
the way the skill under evaluation is — without its `evals/`, under its own
`allowed-tools` — and a name with no `SKILL.md` is refused before any case
runs, since a run without the skill would grade the model improvising it.

### A case that needs more room than the defaults

`max_turns` and `budget_usd` in the same frontmatter override the runner's
defaults (40 turns, 1 USD) for that case alone:

```yaml
---
name: swift-makefile-entry-point
max_turns: 220
budget_usd: 6
---
```

This is not tuning — it is what makes a long case runnable at all. `claude -p`
stops at `--max-turns` and exits non-zero, and the runner grades a non-zero
`claude -p` as FAIL by design, so a scenario that does not fit reports a broken
*skill* when what ran out was the harness. The failure is legible in
`claude.stderr`, but only if you go and look; the summary just says FAIL.

Raising `SKILL_EVAL_MAX_TURNS` instead would hand that ceiling to every case,
including the ones whose whole point is that the skill stops early. Declare it
where the scenario is, and set the value from what the skill actually has to do
— a full `init-project` scaffold is twelve steps with a verification block each,
which is an order of magnitude more than a `review-test` review.

## What the eval can and cannot see

The working directory is created **outside this repo**, under `$TMPDIR` (an
explicit `mktemp` template, since macOS's bare `mktemp` ignores `TMPDIR`). Inside
the repo, Claude Code would read this repo's `CLAUDE.md` and grade the fixture
against dotfiles' conventions rather than the skill's own contract. `--setting-sources
project` and `--strict-mcp-config` keep the caller's user settings and MCP
servers out for the same reason.

What the runner leaves in `$TMPDIR`: **nothing without `--keep`, however the
run ends** — finished, stopped by a failed scaffold, or cut short by any step
failing under `set -e` (the EXIT trap removes the summary, the case's cost file
and the run's working directory; the cost file once outlived a failed
scaffold). With `--keep` the working directory stays and is named, **a failed
scaffold's included**: a half-built fixture is what fixing the scaffold needs
to look at. Each of those is pinned.

The consequence is the limit worth knowing: **by default a case measures only
what `SKILL.md` achieves on its own.** Read that the other way round and it is
the point: a case that passes predicts the behaviour in a repository with no
`CLAUDE.md` of ours, and under an agent that reads only `.agents/skills/`.

A rule that lives in a `CLAUDE.md` needs the opposite, and a case opts in by
naming the file, as a path from the repo root:

```yaml
---
name: proactive-with-claude-md
claude_md: root/CLAUDE.md
---
```

The runner copies it in as the fixture's `CLAUDE.md` after the scaffold, and
excludes it from git only then, so a skill that writes a `CLAUDE.md` of its own
still sees that one. A path that does not exist is refused before any case
runs, since a typo would otherwise measure `SKILL.md` alone under the other
name. Every case's frontmatter is checked before the first one starts, so a bad
case further down is not reached only after the ones ahead of it were paid for.

**Pair such a case with one that leaves the file out** — same prompt, fixture
and grader — so the difference between them is the file's. `review-test`'s
pair also differs in `max_turns` / `budget_usd`, which matter only to a run that
starts the skill: the runs without the file ended in 6 or 7 turns at about
0.08 USD, so the ceilings did not decide the result. Raise them on both sides
before comparing runs that do start it. `review-test` has
the pair, and it is why the option exists. Measured 2026-10-10 with sonnet:

| Case | Started review-test on its own |
| --- | --- |
| `proactive-after-writing-tests` (no CLAUDE.md) | 0 of 7 (4 forked, 3 with the fork lines removed) |
| `proactive-with-claude-md` (`root/CLAUDE.md`) | 9 of 9 |

So the auto-start rests on `root/CLAUDE.md`, not on the description. Passing as
a whole took two more things, each found by these runs:

| Round | Passed | What failed |
| --- | --- | --- |
| first | 0 of 3 | the caller acted on the forked report without writing it out (3); the review found real defects in the fixture (`%g` printing `1e+06`, a multi-line input passing `grep`) and the caller stopped to ask (2) |
| after the `Caller:` line was made explicit and the fixture fixed | 1 of 3 | the fixture fix itself rounded after every addition (2) |
| after rounding once | 1 of 3 | no commit, since `root/CLAUDE.md` names a `commit` skill the fixture does not carry (1); P2 findings left as questions for the user (1) |

From the second round on, every run wrote the report out before acting on it.
**A fixture a good review can fault makes the case unsatisfiable**: the tests
that expose a defect fail, and fixing it fails "left the implementation
untouched". So the fixture's contract has to be one a careful reader finds
complete. **A `CLAUDE.md` brought in whole also brings its references**: the
`commit` skill it names is not in the fixture, which is a gap between the two,
not something the skill under evaluation did.

## Divergences from the monorepo harness

- **The fixture is shell, not TypeScript.** This repo is shell, and a shell
  fixture installs nothing: the tests really run, with nothing stubbed. The cost
  is that there is no coverage tool for shell, so **Phase 4 of `review-test` has
  nothing to collect in these cases** and no case asserts on coverage. A gap in
  the coverage, not a claim that Phase 4 is unnecessary.
- **Stubs live per skill, not in a shared `stubs.sh`.** The monorepo stubs `gh`
  and `yarn` centrally because its skills call the same two. Here the only case
  that needs stubs is `init-project`'s Swift path, and what it needs is an Xcode
  toolchain nothing else will ever ask for, so the stubs sit in that skill's own
  `evals/lib.sh` (see above). Move them up only when a second skill wants the
  same binary — which `gh` did: `create-pr` and `update-pr` both push and call
  `gh pr`, so `bin/skill-eval-github.sh` gives a fixture an `origin` (a bare
  repository inside its `.git/`) and a `gh` that keeps one PR per branch as
  JSON in `bin/gh-state/`. It refuses what the real `gh` refuses where the
  skills' flow depends on it — a PR for an unpushed branch, a second PR for a
  branch, one from the default branch — and fails on any subcommand it does
  not know, so a run cannot believe in a PR nothing opened.
  `bin/skill-eval-github.test.sh` pins each of those.
- **The cases do not assert `transcript_denials` is 0.** `review-test` here has
  no `Bash` in `allowed-tools` at all (see its SKILL.md for why), so a refused
  `Bash` call is the expected behaviour, not a violation.
- **The read-only boundary is asserted by order, not by absence.** The cases
  used to assert that the run wrote nothing at all — `Write` and `Edit` unused,
  working tree untouched, no commit. That stopped being the contract when the
  skill's caller began fixing P1 and P2 findings and committing them, because
  the caller is the same agent in a `claude -p` run, with no marker in the
  transcript for where the skill ends. What the cases assert instead is that
  nothing was written and no `git` ran **before the review was reported**, and
  then that the fix and the commit did happen. The weaker half is real: a skill
  that wrote a file and only afterwards produced its report would pass.
- **Skills live in `root/.agents/skills/`,** so `evals/` sits inside the
  directory that gets symlinked into `~/.claude/skills/<name>`. It is inert
  there (nothing reads it but this runner), but it does mean the cases ship to
  every machine that runs `relink`.

## Stubbing a toolchain the grading machine may not have

`init-project`'s Swift case drives Xcode. Running `xcodebuild` for real would
need a full Xcode wherever the case is graded, a genuine compile per run, and it
would answer differently on a machine with a different Xcode — so
`root/.agents/skills/init-project/evals/lib.sh` puts stubs for `xcodebuild`,
`xcodegen`, `swiftlint` and `swift` in the fixture's `bin/`, which the runner
prepends to `PATH` and keeps out of the fixture's git.

Two rules that keep a stub honest:

- **A stub decides nothing.** It records its argv to `bin/calls.log` and exits
  0. Grading then reads what the scaffold *really* passed — the flags are the
  contract, and a Makefile that passes the wrong ones still exits 0. The one
  exception is `xcodegen`, which fails when `project.yml` is missing or unnamed,
  because "generate succeeded against no spec" is a scaffold error worth seeing.
- **Stub the toolchain, never the thing under test.** `make`, the Makefile and
  the shell stay real, so a space-indented recipe or an empty variable fails the
  way it would on a developer's machine.

What that buys is stated in `lib.sh` rather than discovered from a green run:
the case cannot see whether the app compiles or whether any gate would reject
anything. It measures the scaffold, not the toolchain.

**`assert.sh` is graded by a test of its own.** The grader is an instrument, and
an inert one — a `check-ignore` that silently never matches, a regex that no
longer matches the real output — reports a paid, non-deterministic run that
measured nothing. `swift-makefile-entry-point/assert.test.sh` builds the
reference scaffold, asserts it passes, then provokes every assertion in turn and
asserts each FAIL appears. It costs nothing and CI runs it. It also takes the
Makefile out of the fenced `make` block in `references/swift.md` instead of copying
it, so the documented snippet is executed rather than trusted.

`review-test/evals/assert.test.sh` does the same for that skill's cases (`proactive-with-claude-md` runs
`proactive-after-writing-tests`'s scaffold and grader, so it is pinned through
that one), `review-design/evals/assert.test.sh` for all eight of its, and
`create-pr/evals/assert.test.sh` for `create-pr`'s and `update-pr`'s, which
share their graders. A case there is graded on the transcript as much as on the tree, so it
writes synthetic transcripts, and two things about them are worth copying:

- **A synthetic transcript carries the loaded SKILL.md.** The Skill tool puts
  the skill's body into the conversation, report template included, so a check
  that searched the whole transcript for the report heading would find it
  whether or not a report was written. "reports under a test-review heading"
  did exactly that, and also counted any mention of a test review, a preamble
  included. Headings are now looked for in the model's own text blocks only,
  and need the colon (`evals/grading.sh`). The shape is the one a real run of
  a forked skill emitted: the body is a user text record carrying the Skill
  call's id as `parent_tool_use_id`, the fork's own tool calls carry it too,
  and the report comes back as the Skill's `tool_result`. That result does not
  count as reported either — the caller has to write it out, and a real run of
  `review-design` that went straight to its fixes is what the control pins.
- **`check_llm` is pinned by its wiring, not its rubric.** A stub judge fails
  exactly when its input contains `JUDGE_FAIL`, so planting the marker in the
  text a judged check is meant to read shows that it reads that text. Whether
  the rubric is right is left to real runs.

**`review-design/evals/assert.test.sh` runs sharded** — `TEST_JOBS` shards:
one per CPU when run alone, and under `bin/test` (every CI run) the job count
`bin/test` chose and exports (see "The job count" in [test.md](test.md)); `1`
is a sequential run — because its ~165
scenarios each spend ~0.45 s in the real grader, and that is not the place to
save time. On macOS it took 112 s before; scaffolding each case once and
copying it per scenario brought a sequential run to ~95 s, and sharding to
~34 s. The output is merged back into source order, and the merge fails
closed: a shard that dies, a scenario that never ran or asserted nothing, or a
merge that itself breaks is a FAIL. See rule 7 in [testing.md](testing.md).

## The runner's own test

`bin/skill-eval.test.sh` replaces `claude` with a stub, so it needs no
credentials, makes no API call and costs nothing. CI runs it on every push.

It exists because **every way the runner breaks produces a green run that
measured nothing**: dropping `allowed-tools` on the way to `claude -p` lets the
skill run with the session's own permissions, so every "it did not write"
assertion passes for the wrong reason; carrying `evals/` in lets the model read
its own grader; leaving the harness visible to git makes the fixture's status
not the fixture's; swallowing an assertion FAIL or a non-zero `claude -p` paints
a broken case green. Each of those has a case in the test.

**The boundary flags are asserted by value, not by name.** `--permission-mode
bypassPermissions` carries the same flag as `acceptEdits`, and `--setting-sources
user,project` the same as `project`; the test once checked only that each flag
was present, so either change passed. The judge's `--tools ""` is checked the
same way, with an empty value kept distinct from an absent flag.

**The transcript readers are pinned against a fixture transcript**, not only
through the stub. The review skills' read-only boundary is graded by order —
nothing written before the report — so an off-by-one in a record index, a
heading quoted inside a tool's input counted as the report, or `last` where
`first` belongs moves that line and grades a write-before-report run as clean.
The fixture has a heading inside a `Write` input and a tool result, a call that
is not its record's first block, and a tool called twice; each reader was
mutated in those ways and went red.
