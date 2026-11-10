# Review breakpoints: unit, trigger, round cap

Settles the trigger policy for `root/CLAUDE.md` and `root/.agents/skills/{review-test,review-design,review-design-doc,update-pr,create-pr}`. One commit sits behind it. Feedback wanted: anything that changes the decisions, the cap value, or the boundary carve-out.

## Problem (14 days of Claude Code transcripts, all assistant records incl. `subagents/`)

| | runs | output | cache read | cache new |
| --- | --- | --- | --- | --- |
| `review-design` forks | 103 | 3.6 M | 212 M | 39 M |
| `review-design-doc` forks | 55 | 3.0 M | 120 M | 31 M |
| `review-test` forks | 15 | 0.1 M | 15 M | ≈ 0 |
| main sessions | — | 23.3 M | 6 262 M | 205 M |

Forks = 29% of output, 34% of cache-new (the expensive parts); `session-review`'s default aggregates shows none of it. One session: **53 forks** — a one-sentence doc correction, a recolored button, each its own opus/high fork. Mean 8.8 forks/session over 18 sessions.

Mechanisms:

1. **No unit.** CLAUDE.md: "once a unit of work (a plan step, a task, a request)" — the model picks the smallest. `review-design-doc` has no granularity exclusion at all ("rewritten a section of one" = one sentence fires).
2. **No round cap.** "There is no round cap" in CLAUDE.md ×3 and each skill; `review-design` adds "no fix too small to skip it" (step 6) and "however small the fix" (template `Caller:` line).
3. **Full freight per round** — opus/high re-reads everything.

Firing evidence is measured: auto-start rests on `CLAUDE.md` (review-test 9/9 with, 0/7 without) but descriptions fire alone too (review-design 9/9) — **both layers must carry the rule**.

## Decision (user, 2026-11-10)

1. **Unit = the user's request.** Mid-request forks only when the range added/changed an **interface or contract**, or moved a design doc's **claim/structure/decision**. Wording, reordering, one-figure/token corrections, formatting: ride to the boundary.
2. **Round cap.** Two re-rounds after round 1. At the cap: an open P2 is fixed without a further round and disclosed (unless its reach crosses the range — then it waits, per the reach rule); an open **P1 is not auto-fixed** — it goes to the user and **blocks `gh pr ready`**.
3. **`review-design-doc` re-reviews changed claims only.**

Boundary rules, per skill scope ("fire when the thing it reviews changed", never per calendar):

- `review-test`: typo/format-only test edits don't fire (boundary included; "nothing the tests assert could have changed").
- `review-design`: fires at the boundary for any non-test code change, docs written with that code, or interfaces. Docs-token/rewording-only requests get **no fork** — explicit carve-out, deliberate (nothing in scope changed; doc claims are `review-design-doc`'s lens).
- `review-design-doc`: substantively changed doc.

The range still runs from the last review: a skipped breakpoint delays a review, never loses one.

## Rejected

- **Size thresholds** — neither skill reviews size (a 500-line rename needs none; a 15-line interface change does).
- **PreToolUse hook** — can't parse "an interface changed", re-asks requested reviews; the measured trigger layer is text. Kept in reserve (`review-design/NOTES.md`); returns if the day-7 measure relapses.
- **Fork reuse across re-rounds** — kills the fresh context, the load-bearing property.
- **CLAUDE.md-only or skills-only** — both layers fire measured; the weaker one keeps firing.

## Changes (1–6 in one commit; 7, 8 own commits)

1. **`root/CLAUDE.md`** (Test Review / Design Review / Design Doc Review): unit → request; mid-request rule; round cap + open-P1 blocks ready; doc-rewording carve-out; delete "the next breakpoint's range still covers it" (its premise dies with the per-commit unit).
2. **`review-design/SKILL.md`** — four places: description/"When to start" (mid-request only on the interface trigger; **delete** the 200-line criterion); two flow lines; "After the review" step 6 ("no round cap, no fix too small") → cap with the P1/P2 end-state; template `Caller:` line ("however small the fix").
3. **`review-design-doc/SKILL.md`** — description/"When to start" (claims/structure/decisions, not "rewritten a section"); loop step 3 → cap; template `Caller:` line → cap.
4. **`review-test/SKILL.md`** — description gets the request boundary; loop step → cap.
5. **`review-design/NOTES.md`** — "Breakpoints" note (why the unit moved; the evidence; hook unchanged in reserve).
6. **`update-pr/SKILL.md` + `create-pr/SKILL.md`** — one sentence each on the ready path: no `gh pr ready` / no ready-open when the caller's latest round named an open P1. `update-pr` alone is not enough: with `ready` and no PR, its step 2 hands over to `create-pr` (without draft) — the ungated second route to the same action.
7. **`bin/review-token-audit`** (**new**) — the aggregation behind this doc's tables: token sums over `subagents/agent-*.jsonl` by mtime, keyed by skill, plus **forks/session** (the relapse metric) and main-session totals. Committed first, so baseline and re-measure share an instrument.
8. **`bin/skill-eval.md`** — the new cases (below); the cap ceiling check at the already-named home, `review_loop_rerun_checks`.

## Verification

Eval cases before the policy commits (fixtures per `bin/skill-eval.md`; low `--runs` first — evals spend real usage):

- `review-design-doc` `no-fire-doc-rewording`: one-sentence fix after a clean final round → **no new fork**.
- `review-design` `no-fire-midrequest-non-interface` → no fork before the boundary; `no-fire-small-fix` CLAUDE.md variant (noted missing in the harness doc) → expected shape corrected: **one fork, at the boundary only** (the small non-interface code fix is the session's only request).
- `review-test` `boundary-only` (five small commits) → forks at the boundary only, within the cap.
- Cap check in `review_loop_rerun_checks`: three-round fixture, round 2 still reporting a finding → round 3 is the last, the leftover lands in the report, no round 4.

**Day-7 re-measure** with `bin/review-token-audit`; relapse (> ~3 forks/session, or one session > ~6) → the hook leaves its reserve. Rollback: `git revert` of the policy commit — the eval cases then fail toward today's behaviour.

## Open

- Cap value (two re-rounds): judgement, not measured; the eval case makes changing it a one-value edit.
- `review-design` `effort: high` → `medium`: not in the same commit — the frequency fix may be enough, and quality and cost should not shift together.
- One-sentence corrections of a *wrong statement*: currently a changed claim; may fold into the wording clause if day-to-day runs disagree.
