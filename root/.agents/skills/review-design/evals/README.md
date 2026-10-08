# review-design evals

Run with `bin/skill-eval review-design` ([bin/skill-eval.md](../../../../../bin/skill-eval.md)).
This file sits in `evals/` on purpose: the runner strips the directory from the
copy of the skill a run sees, so what is measured here stays out of the
model's reach, as the graders do.

## The cases come in pairs

Each pair differs in one thing, so a pass is not a fluke of the scenario:

| Pair | Differs in |
| --- | --- |
| `stale-doc-after-change` / `clean-unit-no-false-p1` | the docs moved with the code, or did not |
| `pass-through-layer` / `intended-layer-asks` | nobody asked for the shallow layer, or the commit did |
| `proactive-at-breakpoint` / `no-fire-small-fix` | the unit changed an interface, or did not |

Two stand alone for now, one per remaining lens: `hidden-clock-no-seam`
(testability — a new interface reads the clock with no seam) and
`next-change-scattered` (change cost — the prompt names the next change,
which would have to edit two places). Their pairs, a clock read once at the
edge and the same scattering with no next change named, are not written yet.

They share one fixture, `lib.sh` (a weighbridge module, the command that totals
its tickets, and the docs beside them), and one set of graders, `grading.sh`:
where the report starts, which range its `Reviewed:` line names, and that
nothing is written before it.

## What the evals taught about the harness

- **The prompt's conventions line stands in for CLAUDE.md**, which the runner
  leaves out. Without "one command at a time" and "tests via `./run-tests.sh`",
  runs chained `$?` or ran `bash run-tests.sh`; nobody can approve those in a
  run, the refusal says everything else needing approval is refused too, and
  the caller gave up on fixing or committing. That failed cases on the harness,
  not the skill.
- **Grade by order, at git that writes.** The skill runs git while it reviews,
  so `review-test`'s "no git before the report" cannot apply.
- **A report heading is found by its colon**, not by its markdown level: runs set
  it as `##` or as bold, and a preamble like "設計レビューを始めます" has no colon.
- **Graders are checked before they are paid for.** Each case's checks were run
  against synthetic transcripts with a stub judge — a good run passing all of
  them, each bad run failing only its own — before any real run.
- **`skill_eval_init_repo` used to commit the skill under test into the
  fixture**, where a doc-reviewing skill would read itself. Fixed in the harness.
- **Pin the behaviour the tests do not reach.** Every case that lets the caller
  fix something also pins an input no test covers — an all-unreadable total, a
  `--kg` that must stay refused — because a fix answering an open question in
  code passes every test.
- **"Tests untouched" was too strict.** A fix may add a test beside the kept
  ones; what it may not do is remove or change a line of them. One shared check
  counts deleted lines.

## Last measured

**Before `context: fork`.** Everything below was measured with the review
running inline in the caller's context; the forked version has not been run
yet. Expect the ordering graders to need a look: the report now reaches the
transcript as the forked skill's result and is then relayed by the caller.

On the final SKILL.md, every one of the eight cases has passed; the latest full
run was 7/8, the miss being `hidden-clock-no-seam` reporting after its fix,
which then went 3/3. The trigger pair over three runs each: starts at the
breakpoint 9/9, always after the unit's commit; stays out of a small fix 3/3;
opens its closing message with the report 3/3.

Requested reviews reporting first is the softest result: a small finding with
an obvious fix tempts a run to fix first and report in its closing summary.

Not measured yet: the 200-line trigger, the `create-pr` fallback, a unit that
spans several commits, and whether an interface or merely the size of a change
is what starts the skill.
