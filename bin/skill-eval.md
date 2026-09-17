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

**This spends money.** Every run calls the API on your Claude Code credentials;
`--max-budget-usd` (default 1 USD per run) is the only cap. The default model is
sonnet (`--model`); the `check_llm` judge is haiku (`SKILL_EVAL_JUDGE_MODEL`).
Artifacts land in `tmp/skill-eval/<skill>/<case>/<timestamp>/run-N/`
(`transcript.jsonl`, `result.json`, `assert.log`, `git-log.txt`,
`git-status.txt`), which is gitignored.

A single green run means little. The output wobbles, so raise `--runs` before
concluding that an edit helped.

## Writing a case

Three files in `root/.agents/skills/<skill>/evals/<case>/`:

| File | Role |
| --- | --- |
| `prompt.md` | the prompt for `claude -p`. Leading YAML frontmatter is stripped before it is passed, and carries the case's own `allowed_tools` / `max_turns` / `budget_usd` |
| `scaffold.sh` | builds the fixture; cwd is an empty temp dir. Source `$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh` and call `skill_eval_init_repo`, which tags the starting state `eval-base` |
| `assert.sh` | grades; cwd is the working directory after the run. Source `$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh`, emit one `check` per assertion, end with `skill_eval_finish` |

Functions available to `assert.sh`: `check`, `check_eq`, `check_match`,
`check_not_match`, `transcript_denials`, `transcript_commands`,
`transcript_result_text`, `transcript_tool_uses <tool>`,
`transcript_skill_uses <skill>`, `transcript_first_tool_index <tool>`,
`transcript_first_command_index <regex>`, `transcript_first_text_index <regex>`,
`transcript_tool_uses_precede <tool> <index>`,
`check_llm <label> <rubric> [<text>]`.

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
  nothing else.

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

The working directory is created **outside this repo** (`mktemp`). Inside it,
Claude Code would read this repo's `CLAUDE.md` and grade the fixture against
dotfiles' conventions rather than the skill's own contract. `--setting-sources
project` and `--strict-mcp-config` keep the caller's user settings and MCP
servers out for the same reason.

The consequence is the limit worth knowing: **a case can only measure what
`SKILL.md` achieves on its own.** The auto-start rule in `root/CLAUDE.md` is not
loaded, so its effect is not measured here. Read that the other way round and it
is the point: a case that passes predicts the behaviour in a repository with no
`CLAUDE.md` of ours, and under an agent that reads only `.agents/skills/`.

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
  same binary.
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
