---
name: review-test
description: Review test code. Start from the module's public contract (inputs and outputs, error conditions, guaranteed side effects) and judge whether the tests hold as a specification of behavior, then report what to improve, ranked P1/P2/P3. Use when asked to review the tests themselves — "テストをレビューして", "テストのレビューをお願い", "test review", "review the tests" — or via the /review-test command. Use it proactively as well — once test files (`*.test.*`, `*.spec.*`, `*_test.*`, `*_spec.*`) have been written or changed, start without being asked.
effort: max
allowed-tools: Read, Glob, Grep
---

Review test code and report what to improve, ranked P1/P2/P3.

**Match the user's language.** Answer a Japanese request in Japanese, an English one in English. Quote code, file paths, and command output verbatim.

**Boundary of this skill: reading, plus running tests.** Never edit a file, never run git (`git add` / `git commit` / `git push`) or `gh pr create` / `gh pr edit`. `Bash` is for the project's test and coverage commands and for the reading a review needs — checking a config file, say — never for writing or destructive operations. Acting on the findings happens outside the skill (see "After the review").

**`Bash` is deliberately absent from `allowed-tools`.** That field grants pre-approval; it does not impose a limit. A bare `Bash` entry would therefore widen the session's normal permissions for as long as this skill runs, and the operations this body forbids would go through in silence. A test command is arbitrary code execution, and nothing can enumerate in advance what a given project runs, so a prompt is the right outcome. **Expect to be asked before tests run**, and do not work around it.

**The boundary is this skill's own contract, not something the host enforces.** Some hosts ignore `allowed-tools` outright — Codex reads only `name` and `description` — and there the git and gh commands above are already pre-approved and execute without confirmation. **The absence of a prompt is not permission.** What matters is not what can run but what this skill promises not to do.

## When to start

Beyond an explicit request, **start once a batch of test-code changes is finished, even if no one asked**. Tests are the specification of behavior, and the moment right after writing them is when they are cheapest to fix.

- **Start** when additions or changes to test files reach a natural stopping point — `*.test.ts`, `*.spec.ts`, `*_test.go`, `*_spec.rb`, `*.test.sh`, `*.test.zsh`, whatever the language. Run before the `commit` skill commits them.
- **Don't start** when:
  - the user has said a review is unnecessary, or to commit as is
  - the change never reached test code (implementation only, configuration only)
  - nothing the tests assert could have changed — a typo, formatting, reordered imports

Do not leave this condition to the caller's configuration alone (a `CLAUDE.md` or equivalent). Hosts that read nothing but `name` and `description` still have to trigger, and so does any repository whose configuration this skill never sees. That is why the condition lives here.

## After the review

This skill changes no files while it runs, per the boundary above. Once it reports, the caller takes over.

1. **Fix the P1 and P2 findings, without asking first.** P1 means "deal with this before merging" and P2 decides how far the tests can be trusted; reporting and stopping discharges neither. Asking for permission to act on a review the caller already asked for is the failure mode this step exists to prevent.
2. **Review again** with this skill. A fix can break another part of the test or introduce a new P1, and this is where that surfaces.
3. **Repeat 1–2 until no P1 is left, for at most three rounds.** If P1 survives three rounds, report what remains and why, then let the user decide. Stop on the same terms when one finding survives two rounds — an LLM's findings wobble, and grinding on it mechanically is not convergence.
4. **The loop gate is P1 only.** Fix the P2 of the **first** report; P2 that a later round raises is reported, not chased. P2 is where the findings wobble most (a "missing boundary case" can always be claimed again), so gating the loop on it would never terminate.
5. **Never auto-fix P3.** Report it; acting on it is the user's call.
6. **Commit the fixes once the loop ends**, at the granularity the caller's commit workflow would use anyway — a fix that changes what a test asserts and one that only reorganizes it are separate commits. Not inside this skill: it runs no git at all, per the boundary above. This is the caller's step, and it is here because a review whose fixes sit uncommitted is indistinguishable from one that was never acted on.

## Procedure

Five phases, in this order.

### Phase 1: Read the public contract

Identify what the module under review **promises to its callers**. Tests are a specification of behavior, so the starting point is that promise, never the internal workings of the implementation.

1. **Public interface**: the exported functions, classes, resolvers, and endpoints, and their types — input, output, error
2. **Explicit contract**: what the types and doc comments state outright — the successful input-output pairs, the error conditions, the side effects
3. **Implicit contract**: guarantees the types cannot express (never returns null, preserves array order, is idempotent), inferred from the implementation. Keep to behavior a caller could rely on; do not enumerate internal branches.
4. **Boundaries**: the edges of the input domain — empty collections, null/undefined, upper and lower limits — derived from the types and the contract

Internal logic, such as a branch inside a private method, is not a starting point for test-case design.

### Phase 2: Design the tests that ought to exist

From the contract in Phase 1, design test cases around the behavior callers depend on.

**The design principle:** derive cases from what a caller expects, not from internal branching. A good test survives a refactor that leaves behavior intact.

**How to derive them:**
1. Design at least one case per contract from Phase 1 — successful input and output, error conditions, guaranteed side effects
2. Attach each boundary from Phase 1 to the contract it belongs to, as a variation of it
3. Design cases for the implicit contracts from Phase 1 that a caller could genuinely rely on

**Categories that must be covered:**
- **Success**: the main successful scenarios (input → expected output)
- **Failure**: the error conditions the contract defines (validation, permissions, a failing external dependency)
- **Boundaries**: the edges of the input domain (empty collections, null/undefined, upper and lower limits)
- **Side effects**: that the effects the contract promises — a database write, an external API call, an emitted event — actually happen

Follow the project's own testing guidelines, where they exist, for the choice of test scope and test size.

### Phase 3: Compare against the tests that exist

Put the cases from Phase 2 next to the real test code.

**Coverage of cases:** find which of the Phase 2 cases are missing. A missing main success path is P1 on its own.

**Quality:**
- **Names**: does each state the expected behavior plainly?
- **AAA**: Arrange → Act → Assert?
- **Independence**: is there any dependence on execution order between tests?
- **Granularity**: one assertion of one thing per test?
- **Scope against size**: is a unit test reaching a database? Does an integration test's mocking hollow out the integration it exists to check?
- **What the assertions mean**: do they check the behavior of the public contract? Is anything settled by a bare existence check (`toBeDefined()` in JS and the like)? Do any of them assert internal implementation detail?
- **Mocking**: is the mocking library used correctly? Has over-mocking drifted away from how the code actually behaves?
- **Coupling to implementation**: tests of private methods, assertions on the order of internal calls, structures a refactor would break, test splits that simply mirror the implementation's branches
- **Signs of flakiness**: dependence on the clock (`Date.now()` unmocked), random values, timing and race conditions, mutated shared state, unmocked network calls
- **Test data**: if the project has a way to build test data (factory, fixture, template), do the tests use it?
- **Cleanup**: in integration tests that touch a database, is the data cleaned up properly?
- **Environment and global state**: is anything mutated in place inside a test (`process.env` in JS and the like)?

**Problems in the implementation:**

The subject of the review is the test code. But reading the public contract in Phase 1 and judging coupling in Phase 3 turns up possible bugs and plainly wrong code, so write those down. Report them in a separate section rather than as P1/P2/P3.

### Phase 4: Collect coverage

Run the tests, collect coverage, and check it against the gaps from Phase 3.

Use the project's own command (`yarn test:coverage`, `npm run test:coverage`, `go test -cover`, and so on). Where it is unclear, find it in `package.json` or the project's configuration.

Coverage is a hint, not a target. 100% is not the goal; whether the paths that matter are exercised is.

### Phase 5: Report

Use this format. Translate the headings into the language of the report.

```
## Test review: [what was reviewed]

### Summary
- Target: [file path or module name]
- Test files: N
- Test cases: N
- Coverage: N% (lines)

### P1 (Critical)
- [the finding, and why it matters]
- [ ] ...

### P2 (Important)
- [the finding, and why it matters]
- [ ] ...

### P3 (Nice to have)
- [the finding, and why it matters]
- [ ] ...

### Findings in the implementation
- [bugs or problems in the implementation found during the review]
```

Drop any priority section with nothing in it, and the implementation section too.

## How to assign priority

P1/P2/P3 are **absolute criteria**, not a distribution. Classify by whether a finding meets the criterion; do not spread findings evenly across the three, and do not manufacture a P1 for tests that are already good.

**P1 (Critical)** — must be dealt with before merging. Left alone, it leads directly to a missed bug or a regression.

P1 only if **any one** of these holds.
- No test exists for a main behavior the public contract promises
- A test has no assertion, or checks nothing beyond existence (`toBeDefined()` in JS and the like), which manufactures false confidence
- A test asserts only internal detail — how often a private method was called, an intermediate internal value — and never the behavior of the public contract, which manufactures false coverage and obstructs refactoring
- The choice of test scope and size is wrong (a unit test depending on an external resource, and so on)
- Tests depend implicitly on execution order and break when run in parallel or in random order
- Global state or environment variables are mutated inside a test (`process.env` in JS and the like)
- A **main** error path — an error condition the public contract defines — is untested (a missing secondary error path is P2)

**P2 (Important)** — worth dealing with for quality. It affects how much the tests can be trusted and how well they can be maintained.

P2 if **any one** of these holds.
- Boundary cases are missing
- A test name does not describe the behavior it checks
- The test does not follow AAA
- Over-mocking has pulled the test away from real behavior
- The test is coupled tightly enough to implementation detail that a behavior-preserving refactor would break it
- There are signs of flakiness (clock, random values, timing, shared state, network)
- The coverage report shows changed lines left untested
- A secondary error path is untested

**P3 (Nice to have)** — an improvement, not an obligation.

- The structure and organization of the test files
- Redundant assertions
- Simpler test setup
- The grouping hierarchy (`describe` blocks in JS and the like)
- Test cases split along the implementation's branches rather than along contracts and behavior — it works, but it costs maintainability
