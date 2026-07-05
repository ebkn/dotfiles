---
name: check-production-readiness
description: Pre-launch readiness check for a web application before it goes public. Acts as an orchestrator — detects the stack, selects the applicable checklist buckets (kept as separate files under checklists/), and fans out one read-only sub-agent per bucket in parallel (backend/API, forms, frontend + a11y/SEO/AIO-LLMO, Next.js, payments, security, legal, observability, delivery/infra, manual launch setup), each matched to a model suited to that bucket's reasoning demand (deep models for security/backend/payments/Next.js, faster ones for lighter buckets), so every bucket gets full, concurrent attention instead of skimming a 140-item wall. Every finding is grounded in actual code/config and checked against the current official best-practice docs for the detected stack (Vercel, Next.js, React, web.dev, OWASP, Google Search) rather than a static list. Reports blockers and gaps with priorities (P1/P2/P3) and separates what cannot be verified from the repo. Security covers only common items; deeper auditing is delegated to the security-review skill. Read-and-report only: no code changes, no git operations. Triggered by requests like "production readiness check", "pre-launch checklist", "is this ready to ship", "check before going public", or the `/check-production-readiness` command.
effort: max
allowed-tools: Read, Glob, Grep, Task, WebSearch, WebFetch, Bash(git log:*), Bash(git show:*), Bash(git diff:*), Bash(git status:*), Bash(git blame:*), Bash(git ls-files:*), Bash(npm audit:*), Bash(npm ls:*), Bash(npm outdated:*), Bash(pnpm audit:*), Bash(pnpm ls:*), Bash(pnpm outdated:*), Bash(yarn audit:*), Bash(yarn npm audit:*), Bash(bun audit:*), Bash(npx lighthouse:*), Bash(lighthouse:*), Bash(curl:*)
---

Check whether a web application is ready to go public. This skill is an **orchestrator**: it detects the stack, selects which checklist buckets apply, then **fans out one read-only sub-agent per bucket, in parallel** — each matched to a model suited to that bucket's reasoning demand — because a single 140-item sweep in one context gets skimmed, not honored. The detailed items live in `checklists/*.md`, one file per bucket; this file holds the orchestration, model routing, classification rules, and the report format.

**Write the report in English.** Quote code, file paths, and command output verbatim. Use raw strings for URLs and paths (`app/page.tsx`, `https://...`), not `[text](url)` links — the terminal can't follow them.

**Scope: whole web application / repository** by default, unless the requester narrows it (one app in a monorepo, backend only, frontend only).

**Boundary of this skill: read and report only.** Make no file changes and no git operations (add / commit / push, etc.). This is enforced by the grant, not just this prose: `allowed-tools` pre-authorizes only read-only `Bash` — read-only git (`git log`/`show`/`diff`/`status`/`blame`/`ls-files`), package audits/inventory (`npm/pnpm/yarn/bun audit`, `ls`, `outdated`), `lighthouse`, and `curl` (for response-header inspection). Read/search/list files through the `Read`/`Grep`/`Glob` tools, not shell. Any other command — including anything that writes or mutates git — is **not** pre-authorized and will prompt for approval; a read-only inspector for another ecosystem (`go list`, `cargo tree`, `pip-audit`, etc.) prompting is expected, but a write/commit/push prompt means something is wrong — do not approve it. `WebSearch`/`WebFetch` are for verifying advisories (CVEs, EOL dates), framework-version-specific behavior, and pulling the **current** official best-practice docs for the detected stack (each checklist file lists its own sources). `Task` is included so the orchestrator can fan out the per-bucket passes (Phase 2). **Note the read-only guarantee is weaker for those sub-agents than for this orchestrator:** the scoped `Bash` grant above constrains *this* agent, but a sub-agent's `Bash` is not scoped the same way. They are kept read-only by construction (the `Explore` agent type, which cannot `Edit`/`Write`) plus a verbatim read-only instruction in every prompt — enforcement at the prompt level, not the grant level. Applying any fix is a separate request.

**Security scope: common items only, then delegate.** This check covers the everyday security hygiene in `checklists/security.md` (hardcoded secrets, secret scanning, HTTPS/cookies, security headers/CSP, input validation, open redirect, SSRF, `npm audit`, `NEXT_PUBLIC_` leakage, and a first-pass server-side-authorization check). It does **not** attempt a full security audit. When findings suggest deeper exposure — injection surfaces, access-control logic, data handling — recommend running the `security-review` skill rather than going deep here.

**Deliberately-thin, high-stakes areas — verify, don't skip.** Payments, authentication/authorization, and legal/compliance are intentionally **not** expanded into fine-grained items. Thin coverage is not permission to skim them. They now have (or share) their own focused passes — `checklists/payments.md`, the authorization item in `checklists/security.md`, and `checklists/legal.md` — each of which tells the pass to `WebSearch` the authoritative source and route depth to the specialist (`security-review`, or a human for legal). If one of these domains is present but under-examined because it's out of this skill's depth, **say so in the report** — an unexamined payment or authz path is a stated gap, not a silent pass.

## Core principle: evidence over checklist

A checklist is only useful if each item is judged against what this codebase actually does, cited by `path:line` — never a generic pass/fail from the item text alone. For each item, land in one of four states and say which:

- **OK** — the safeguard exists and is wired correctly (cite it).
- **Gap** — the code shows the item missing or broken (cite it). This is where findings come from.
- **N/A** — this app doesn't need it (say why once, then drop it).
- **Cannot verify** — readiness depends on infra or process the repo can't prove (uptime monitoring wired, backups running, DNS/SSL, branch protection, cloud-account MFA, CDN/WAF config). Do **not** assume pass or fail — surface it as a question.

Distinguish fact from inference; when you can't tell, say so. Treat the final verdict as provisional and revisable.

## Procedure

### Phase 1: Detect the stack and select applicable buckets

Do this **once**, in the orchestrator context, and produce a short **stack profile** you will hand to every bucket pass (so no pass re-detects the stack or diverges).

- **App shape** — backend/API only, frontend SPA, full-stack, or Next.js (App Router vs Pages Router)? And: **public-facing/indexable site vs. an internal tool / API**. Read `package.json`, framework config (`next.config.*`, etc.), `README`, `docs/**`, and deployment/CI config.
- **Topology** — datastores, object storage, queues, external services called, forms, payment providers, and how it deploys (Vercel, container, serverless, CI/CD, IaC).
- **Critical paths** — the flows whose failure is user-visible or loses data (for a lead-gen site, the form submission *is* the conversion). These get the most scrutiny.
- **Existing signals** — CI checks enforced, prior incident notes, TODO/FIXME markers, existing runbook/readiness docs.

Then select which checklist files apply. **The point of gating is to never load a bucket that doesn't apply** — an internal API skips every frontend/SEO/AIO/a11y/forms/legal file and says so once.

| Bucket file | Applies to |
|---|---|
| `backend-api.md` | any app with server-side code / a datastore |
| `forms.md` | apps that accept user submissions |
| `frontend-web.md` | any app that renders a browser UI |
| `frontend-a11y.md` | any app that renders a browser UI |
| `nextjs.md` | Next.js apps only |
| `seo.md` | public, indexable content sites only |
| `aio-llmo.md` | public content sites wanting AI-search discoverability |
| `payments.md` | apps that charge money / integrate a payment provider |
| `security.md` | always |
| `legal.md` | apps collecting personal data / setting non-essential cookies |
| `observability.md` | always |
| `delivery-infra.md` | always |
| `manual-setup.md` | apps launching to the public (external-console registration) |

**Degraded mode (network unavailable).** Each bucket pass fetches its own best-practice sources. If `WebFetch`/`WebSearch` fail or are blocked, do **not** silently fall back and keep claiming the review reflects current official docs. State it plainly in the report — which sources could not be reached — and mark every finding that depended on a live lookup (fast-moving SEO/AIO/LLMO, platform features, advisory/EOL status) as **based on this possibly-stale checklist, not verified against current docs**. A degraded run is valid but must be labeled as such in the Overview.

### Phase 2: Fan out one read-only agent per bucket — in parallel, model-matched

Run the applicable buckets as **concurrent sub-agents**, one per bucket, each model-matched to its reasoning demand. The buckets are independent (no shared state, no ordering), so dispatch them all at once and collect the results before Phase 3.

**Dispatch (Claude Code).** Launch the agents in a **single message with multiple `Task` calls** so they run concurrently — not one at a time. Use the read-only **`Explore`** agent type (it cannot `Edit`/`Write`/`NotebookEdit`), and set each call's `model` per the routing table below. Give every agent:

- the Phase-1 **stack profile** (so it does not re-detect the stack or diverge),
- the path to its checklist file (`checklists/<name>.md`) — or its contents, if your tool doesn't expose this skill's directory to sub-agents,
- the read-only contract, verbatim: **gather evidence with read-only commands only; never `Edit`/`Write` a file and never run a mutating or git-writing command**,
- the return contract: report each item as OK / Gap / N/A / Cannot-verify with `path:line` evidence and any `ref:` source URL, and **do not assign final P1/P2/P3** — the orchestrator classifies centrally in Phase 3 so priorities stay consistent across buckets.

Each agent, within its bucket: reads only its checklist file (so ~15 items are in focus, not 140), fetches that file's best-practice sources (the live doc wins over the file; fold any new/changed guidance in as extra checks — fast-moving SEO/AIO/LLMO, platform features, and advisories especially), audits the repo against every item grounded in `path:line`, and records any outright bug it spots (not just a readiness gap) as a concrete finding with evidence.

**Model routing — match the model to the bucket's reasoning demand.** Assign per this table; **upgrade** a bucket when the app makes it unusually subtle (a hand-rolled auth or payment layer, a bespoke caching scheme), **downgrade** when it's trivially thin.

| Model | Buckets | Why |
|---|---|---|
| **opus** (deep reasoning) | `backend-api`, `security`, `payments`, `nextjs` | Subtle, high-stakes correctness — SSRF / cache-leak / transaction / idempotency, authz / IDOR / injection / CSP, money-path integrity, RSC-boundary / caching / rendering. A miss here is a P1. |
| **sonnet** (balanced) | `frontend-web`, `frontend-a11y`, `seo`, `aio-llmo`, `legal`, `observability`, `delivery-infra`, `forms` | Real judgment but more pattern-based; several are WebSearch-driven (fast-moving SEO/AIO) or config-presence checks with moderate nuance. |
| **haiku** (fast) | `manual-setup` | Mostly presence-of-wiring and cannot-verify questions (verification tokens, DSN, external console steps) — little code reasoning. |

**Synthesis stays on the orchestrator** — this agent, at its own model and `effort: max`. Dedup and P1/P2/P3 classification (Phase 3) need the strongest reasoning and the full cross-bucket view; do **not** offload or downgrade them.

**Honest trade-off (accepted for parallelism).** Fan-out means the sub-agents' `Bash` is not grant-scoped the way this orchestrator's is — read-only is enforced at the prompt level, with `Explore` structurally blocking `Edit`/`Write` as a backstop. Keep the read-only instruction explicit in every sub-agent prompt.

**Fallback (no sub-agents / no per-agent model control).** If the tool can't spawn agents or can't set per-agent models, run the buckets **sequentially in this agent** instead: complete and record one checklist file before loading the next — never hold all buckets in focus at once — using the best available model throughout. This preserves the per-bucket focus (the point of the split) and keeps the grant-backed read-only enforcement fully in force, at the cost of wall-clock.

### Phase 3: Merge, dedup, and classify

Collect the findings from all passes into one set. Then:

- **Dedup cross-bucket overlap.** Some concerns legitimately appear in more than one bucket (a missing CSP nonce surfaces in SEO, AIO, and Security; `noindex` on monitoring routes in Next.js and SEO). Merge these into a single finding with all relevant evidence — don't report the same defect three times, and don't drop the cross-cutting interaction.
- **Classify** each finding by the **absolute criteria** in *Priority criteria* below — don't distribute evenly, and don't manufacture a P1 for a healthy app.
- Move everything the repo cannot settle into **Needs-confirmation** as an explicit question, not a pass or fail.

### Phase 4: Output the report

Use this format. Omit any priority section with no findings.

```
## Production Readiness Check: <app / scope>

### Overview
- Scope: <what was evaluated — which buckets applied, which skipped and why>
- Stack: <framework, datastores, deploy target, public-facing vs internal>
- Best-practice sources consulted: <live docs actually fetched, as raw URLs — or "network unavailable: checklist-only run, live docs NOT verified" if in degraded mode (see below)>
- Verdict: <Ready / Conditional (after P1s) / Not ready> — provisional, evidence-based

Findings carry two references where they apply: `evidence:` the `path:line` in this repo that shows the gap, and `ref:` the external best-practice source URL the judgment rests on (include `ref:` whenever the finding leans on a live doc or a fast-moving-area lookup; omit it for a plain in-repo defect). If the run was degraded, mark any finding whose `ref:` could not be fetched as **unverified against current docs**.

### P1 (Blocker) — must fix before going public
- <finding> — evidence: `path:line`[; ref: <source URL>]. Why it is catastrophic on launch (outage / data loss / breach / silent failure).

### P2 (Should-fix)
- <finding> — evidence: `path:line`[; ref: <source URL>]. Impact on reliability / operability / UX / discoverability.

### P3 (Nice-to-have)
- <finding> — evidence: `path:line`[; ref: <source URL>].

### Needs confirmation (cannot verify from the repo)
- <item> — why the repo can't settle it / who to ask (e.g. DNS/SSL, branch protection, backups, uptime monitoring, cloud-account MFA, CDN cache config, and Manual setup items: Search Console / Bing Webmaster / Rich Results Test / Sentry project / analytics account).

### Deeper security recommended (if applicable)
- <concern surfaced by the common checks> — recommend scrutiny via the `security-review` skill.
```

## Priority criteria

Judge against these absolutes. A finding is P1 only if it clears the P1 bar.

**P1 (Blocker)** — would, on launch, cause an outage, data loss, a security breach, or a *silent* failure. Any one of:
- Hardcoded secret / credential / token committed to the repo, or a secret exposed to the browser (e.g. `NEXT_PUBLIC_`-prefixed secret, secret imported into a Client Component).
- A critical external/IO call with no timeout (thread/connection exhaustion) or unbounded/infinite retry.
- A personalized/private response cached by a shared CDN, or an object-storage bucket/prefix publicly listable — leaking one user's data to others.
- An open redirect or reflected-injection sink reachable from user input on a critical page.
- An SSRF sink: a server-side fetch of a user-supplied URL that can reach internal services or the cloud metadata endpoint (`169.254.169.254`), enabling instance-credential/IMDS exfiltration.
- A payment path that trusts a client-sent amount, or a webhook without signature verification / idempotency — enabling under-charging or double-fulfillment.
- A protected route/action with no server-side authorization (IDOR / client-only gating) exposing another user's data or a privileged operation.
- Unbounded query/resource growth on a hot path that will exhaust the instance (no pagination/limits).
- An irreversible or backward-incompatible migration against a live schema.
- A critical-path failure that emits no log/metric/error-tracking signal — invisible to operators.
- Missing health/readiness check where the deploy orchestrator needs one (bad deploys serve errors).
- A known-exploitable dependency vulnerability (confirmed advisory) on a reachable path.
- `next.config` shipping with `ignoreBuildErrors` / `ignoreDuringBuilds` masking real failures on a critical path.
- A public, indexable site shipping with indexing disabled or `metadataBase` unset so canonical/OG break — or the reverse, a pre-launch/staging site left publicly indexable.

**P2 (Should-fix)** — degrades reliability, operability, UX, security, or discoverability but not immediately catastrophic. E.g.: missing retries/backoff on a recoverable dependency; weak/unstructured observability; source maps not uploaded; no documented rollback; missing bot protection on a public form; incomplete cookie attributes or security headers; N+1 or missing index on a hot path; missing error/loading states; accessibility gaps or a11y lint rules not enforced as errors; missing SEO essentials (canonical, OG image, structured data) on a marketing site; unintended dynamic rendering / uncached-vs-overcached hot path; no secret-scan or dependency-update automation; secondary error paths untested; a vulnerable dependency on a low-severity or non-reachable path.

**P3 (Nice-to-have)** — hardening and polish: defense-in-depth extras, richer dashboards, docs, image/bundle optimization headroom, minor CWV improvements, GEO/`llms.txt`, scrollbar-gutter and long-text polish, apple-touch-icon and locale name checks.

Keep the verdict honest: if P1s exist, it is not ready to go public; if only cannot-verify items remain, say the code looks ready but named infra/process facts must be confirmed by a human before launch.
