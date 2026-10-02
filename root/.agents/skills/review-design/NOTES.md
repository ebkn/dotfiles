# review-design — notes

`SKILL.md` is loaded on every invocation, so it says what to do and only as much
of why as the judgement needs. The reasoning behind it, the sources, the designs
that were tried and dropped, and what the evals measured live here.

## What it is for

Catching design drift while it is cheap, by reviewing at implementation
breakpoints instead of at the end: docs and comments that no longer match the
code, and interfaces that hide less than they ask their callers to know. It
started from a request for a refactoring skill in the mould of `review-test`:
mechanical, routine, and firing only at proper breakpoints so the work keeps
moving.

## Why at a breakpoint

- **An interface gets dearer with every caller.** At a breakpoint its only
  callers are the ones just written; afterwards every caller, doc and test
  raises the price, and once something outside depends on it a change needs
  someone's agreement. This is the whole basis of the reach rule.
- **Drift is cheapest while it is known which side is right.** Right after a
  deliberate change the code is the truth; later, deciding which of code and doc
  is wrong takes archaeology.
- Fowler, *Workflows of Refactoring* (2014): planned refactoring "is a sign that
  the team hasn't done enough refactoring using the other workflows" — the case
  for small and continuous. *Is High Quality Software Worth the Cost?*: poor
  internal quality slows developers down "within a few weeks".
- Ousterhout's *tactical tornado* — "a prolific programmer who pumps out code far
  faster than others but works in a totally tactical fashion" — describes an
  agent left to itself; he suggests "about 10–20% of your total development time
  on investments".

## Decisions, and why

- **Read-only, with the caller fixing**, the same split as `review-test`, so the
  boundary is stated in the body for hosts that ignore `allowed-tools`. Unlike
  `review-test` it pre-approves git's reading commands: the range is the input
  of every run. A prefix rule matches the raw string, so `--output` (which makes
  `git diff`/`git log` write) is forbidden by name.
- **Runs after the unit's commit.** Its fixes touch the hunks just written, and
  interactive staging is unavailable, so reviewing before the commit would mix
  structure and behaviour in one commit. Fixes are commits of their own — doc
  fixes included, against the letter of "update docs in the same commit" —
  because the review is what justifies them (the same reason `review-test`'s
  fixes stay separate).
- **The stated intent decides which side of a drift is right.** The first eval
  run read an old README's *reason* for the old behaviour as a requirement and
  stopped to ask; the commit message had said the behaviour changed on purpose.
- **A fix that would change behaviour is not a tidying**: it goes under "Outside
  this review" as a question, so "fix P1 and P2 without asking" never reaches
  behaviour.
- **Priority and reach are separate axes.** Priority is how much leaving it
  costs; reach is who a fix touches. Local fixes go ahead; crossing ones — an
  outside caller, a published contract, or a structure the commit set out to
  build — wait for an answer. The last kind came from a run that, told to delete
  a ticket-API layer the commit had asked for, kept it and copied the contract
  into its comments instead.
- **Stance where principles conflict**, so rounds do not undo each other: deep
  modules over small functions (the point of the Ousterhout–Martin dialogue,
  2024–25); DRY as knowledge — Dave Thomas: "Most people take DRY to mean you
  shouldn't duplicate code. That's not its intention." — with Metz's "duplication
  is far cheaper than the wrong abstraction" for code that merely looks alike;
  deletion over a better layer; a copied contract is never a fix.
- **Evidence or nothing.** Every finding names the change it makes harder; Beck
  defines coupling as relative to "a particular change", so a finding that names
  none is taste. Absolute criteria, not a quota per priority.
- **The report.** Hashes, never branch or tag names (a run used the `eval-base`
  tag). With no findings it lists what was checked — the user's call: "no
  findings" alone cannot tell a clean change from an unread one. A requested
  review reports before any change. A self-started review reports at the top of
  its closing message, after its fixes — also the user's call, see below.
- **The trigger** decides when, and the range decides what: the range runs from
  the last review, so a skipped breakpoint delays a review and never loses one.
- **`effort: high`**, one step below `review-test`'s `max`, because it runs at
  every qualifying breakpoint.

## Tried and dropped

- **Tidy First's first/after/later/never as the priorities.** It did not fit a
  P1-gated loop; what survives of it is "drop what names no change".
- **A separate drift skill.** Drift happens on small fixes too, but the
  cumulative range catches it at the next breakpoint; two skills meant two
  triggers to keep apart.
- **`context: fork`.** It would make report-before-fix structural, but runs
  against the rule not to hand verification of one's own work to a subagent,
  and loses the conversation — including the next planned change.
- **A self-started report before the first fix.** Measured in three-run
  batches: 0/3, then 1/3, 1/3 and 2/3 as the wording got sharper and a short
  form was allowed. Reviewing code it has just written, the model treats the
  review as part of the work. Most misses still mentioned the findings in the
  closing summary, which is where the user reads anyway, so the self-started
  report moved there: 3/3.
- **A PostToolUse hook reminding after `git commit`** — kept in reserve. Commits
  are fine-grained, so a reminder per commit would be noise; worth it only if
  the description stops triggering.

## Measuring it

The eval cases, what each pair isolates, what they taught about the harness,
and the last measurement are in `evals/README.md` — kept there because the
runner strips `evals/` from the copy of the skill a run sees, and this file is
not stripped.

## Open

- **Testability and change-cost lenses** are designed but not yet in Phase 4:
  hidden inputs read without a seam (Feathers: "a place where you can alter
  behavior in your program without editing in that place"), and preparatory
  refactoring against a known next change (Beck: tidy first when
  cost(tidying) + cost(change after tidying) < cost(change without tidying)).
- **Not yet measured**: see `evals/README.md`.
- **Language**: one run answered a Japanese request in English throughout. No
  case grades the language yet.

## Sources

- Ousterhout, *A Philosophy of Software Design*, 2nd ed. — red flags, the three
  symptoms of complexity, the tactical tornado, the 10–20% investment.
- [Ousterhout and Martin, aposd-vs-clean-code](https://github.com/johnousterhout/aposd-vs-clean-code)
- [Fowler, Workflows of Refactoring](https://martinfowler.com/articles/workflowsOfRefactoring/);
  [Is High Quality Software Worth the Cost?](https://martinfowler.com/articles/is-quality-worth-cost.html)
- Beck, *Tidy First?*; [coupling](https://newsletter.kentbeck.com/p/coupling);
  [first, after, later, never](https://newsletter.kentbeck.com/p/first-after-later-never)
- [Thomas, Orthogonality and the DRY Principle](https://www.artima.com/articles/orthogonality-and-the-dry-principle)
- [Metz, The Wrong Abstraction](https://sandimetz.com/blog/2016/1/20/the-wrong-abstraction)
- [Google Engineering Practices, The Standard of Code Review](https://google.github.io/eng-practices/review/reviewer/standard.html)
- Feathers, *Working Effectively with Legacy Code*, ch. 4 (seams)
