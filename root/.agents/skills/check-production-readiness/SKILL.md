---
name: check-production-readiness
description: Pre-launch readiness check for a web application before it goes public. Walk a concrete checklist across backend/API, forms, frontend (including a11y, SEO, and AIO/LLMO for AI-search discoverability), Next.js, legal/compliance, observability, ops, toolchain/CI gates, config/deploy, data, and manual launch setup (Search Console, Bing Webmaster, Rich Results Test, Sentry, analytics) — grounding every finding in actual code and config, and pulling the current official best-practice/production docs for the detected stack (Vercel, Next.js, React, web.dev, OWASP, Google Search) rather than relying on a static list. Report blockers and gaps with priorities (P1/P2/P3), and separate what cannot be verified from the repo and needs human confirmation. Security covers only common items here; deeper security auditing is delegated to the security-review skill. Read-and-report only: no code changes, no git operations. Triggered by requests like "production readiness check", "pre-launch checklist", "is this ready to ship", "check before going public", or the `/check-production-readiness` command.
effort: max
allowed-tools: Bash, Read, Glob, Grep, WebSearch, WebFetch
---

Check whether a web application is ready to go public, by walking a concrete checklist against the repo and reporting gaps with priorities (P1/P2/P3).

**Write the report in English.** Quote code, file paths, and command output verbatim. Use raw strings for URLs and paths (`app/page.tsx`, `https://...`), not `[text](url)` links — the terminal can't follow them.

**Scope: whole web application / repository** by default, unless the requester narrows it (one app in a monorepo, backend only, frontend only).

**Boundary of this skill: read and report only.** Make no file changes and no git operations (add / commit / push, etc.). Use `Bash` only to gather evidence — read config, inspect the dependency tree, run a dependency/vuln audit, `git log`/`git show` for history — never for writes or destructive actions. `WebSearch`/`WebFetch` are for verifying advisories (CVEs, EOL dates), framework-version-specific behavior, and — importantly — pulling the **current** official best-practice/production docs for the detected stack (see **Best-practice sources** in Phase 1). Applying any fix is a separate request.

**Security scope: common items only, then delegate.** This check covers the everyday security hygiene in the checklist below (hardcoded secrets, secret scanning, HTTPS/cookies, security headers/CSP, input validation, open redirect, `npm audit`, `NEXT_PUBLIC_` leakage). It does **not** attempt a full security audit. When findings suggest deeper exposure — injection surfaces, access-control logic, data handling — recommend running the `security-review` skill rather than going deep here.

## Core principle: evidence over checklist

A checklist is only useful if each item is judged against what this codebase actually does, cited by `path:line` — never a generic pass/fail from the item text alone. For each checklist item, land in one of four states and say which:

- **OK** — the safeguard exists and is wired correctly (cite it).
- **Gap** — the code shows the item missing or broken (cite it). This is where findings come from.
- **N/A** — this app doesn't need it (say why once, then drop it).
- **Cannot verify** — readiness depends on infra or process the repo can't prove (uptime monitoring wired, backups running, DNS/SSL, branch protection, cloud-account MFA, CDN/WAF config). Do **not** assume pass or fail — surface it as a question.

Distinguish fact from inference; when you can't tell, say so. Treat the final verdict as provisional and revisable.

## Procedure

### Phase 1: Detect stack and select applicable buckets

Readiness items depend on what the app is. Establish from the repo:

- **App shape** — backend/API only, frontend SPA, full-stack, or Next.js (App Router vs Pages Router)? And: **public-facing/indexable site vs. an internal tool / API**. Read `package.json`, framework config (`next.config.*`, etc.), `README`, `docs/**`, and deployment/CI config.
- **Topology** — datastores, object storage, queues, external services called, forms, and how it deploys (Vercel, container, serverless, CI/CD, IaC).
- **Critical paths** — the flows whose failure is user-visible or loses data (for a lead-gen site, the form submission *is* the conversion). These get the most scrutiny.
- **Existing signals** — CI checks enforced, prior incident notes, TODO/FIXME markers, existing runbook/readiness docs.
- **Current best practices (do not rely on this file alone)** — for each framework / platform / major library the app actually uses, `WebFetch` its official production/best-practice guide (see **Best-practice sources** below) and `WebSearch` for version-specific guidance or breaking changes for the versions pinned in `package.json`. **This file's checklist is a floor, not the source of truth** — it dates quickly. **Fast-moving areas especially — SEO / AIO / LLMO ranking and preview behavior, platform features, security advisories — change frequently; `WebSearch` the latest from authoritative sources** (official docs, Google Search Central, web.dev, OWASP, the vendor's own blog/changelog) and prefer that over this file when they differ. Cite the source URL in the finding, and fold any new or changed guidance into the review as extra checks.

Then apply only the relevant buckets in Phase 2. The **Frontend (SEO)** and **Frontend (AIO / LLMO)** buckets apply only to public, indexable content sites — skip them (say so once) for internal tools and pure APIs. Skip **Forms** if there are no user submissions. State the selected scope so the report is anchored to it.

**Best-practice sources** (fetch only the ones matching the detected stack; the live doc always wins over this file):

| Area | Source (fetch the live page) |
|---|---|
| Vercel | Production checklist — https://vercel.com/docs/production-checklist |
| Next.js | Production checklist + Optimizing (Images/Scripts/Fonts) + Caching — https://nextjs.org/docs (search "production checklist" if the path moved) |
| React | https://react.dev — rules of hooks, performance, `use client`/server boundaries |
| Core Web Vitals / perf | https://web.dev/explore/learn-core-web-vitals ; Lighthouse docs |
| Accessibility | WCAG 2.2 quick ref — https://www.w3.org/WAI/WCAG22/quickref/ ; MDN ARIA |
| Security headers / CSP | OWASP Secure Headers — https://owasp.org/www-project-secure-headers/ ; OWASP Cheat Sheets — https://cheatsheetseries.owasp.org/ ; MDN CSP |
| SEO / structured data | Google Search Essentials — https://developers.google.com/search/docs/essentials ; Structured data — https://developers.google.com/search/docs/appearance/structured-data ; robots meta / preview controls (`max-image-preview` etc.) — https://developers.google.com/search/docs/crawling-indexing/robots-meta-tag |
| AIO / LLMO (AI search) | llms.txt spec — https://llmstxt.org/ ; crawler docs: GPTBot — https://platform.openai.com/docs/gptbot ; Google-Extended — https://developers.google.com/search/docs/crawling-indexing/overview-google-crawlers ; ClaudeBot — https://support.anthropic.com/en/articles/8896518 |
| Datastore / ORM / other host | The official docs of whatever the app actually uses (DB, ORM, queue, CDN) — `WebSearch` "\<lib\>@\<version\> production best practices" |

### Phase 2: Walk the checklist

Treat each bucket as a **lens, not a rigid script** — skip N/A items (say so once), go deep where the app is exposed, and add anything stack-specific the buckets miss. Ground every judgment in code/config.

**Common / Backend & API**
- [ ] Error handling on every external/IO call; correct HTTP status codes; no swallowed errors
- [ ] No internal exception / stack trace / raw server error leaked to users (map to safe messages)
- [ ] Timeouts on all outbound calls (DB, HTTP, cache); bounded retries with backoff (never infinite)
- [ ] Input validation on every endpoint (schema/type validation at the boundary)
- [ ] (optional) Rate limiting / abuse protection on public endpoints
- [ ] Idempotency for retryable or redelivered mutations (webhooks, queue consumers, double-clicks)
- [ ] (optional) Pagination / result limits on list queries (no unbounded fetches)
- [ ] No N+1 queries; indexes present on hot query paths
- [ ] Connection pooling with a bounded pool size
- [ ] Transactions around multi-step writes
- [ ] (optional) Graceful shutdown: drain in-flight requests, close DB/connections
- [ ] Health/readiness endpoint matched to the deploy orchestrator
- [ ] CORS scoped correctly (no wildcard origin with credentials); request body size limits
- [ ] Open-redirect protection: user-supplied redirect targets validated against an allowlist
- [ ] No user input reflected unvalidated into response headers (header injection)
- [ ] Personalized/private responses are not cached by shared CDN/KV caches (`Cache-Control: private`/`no-store`); only truly public responses are cached
- [ ] Object storage: buckets/prefixes not publicly listable; only intended objects are public

**Forms** (apps that accept user submissions)
- [ ] Validation on both client and server (schema-based); submit disabled while sending
- [ ] Idempotency (idempotency key or server-side dedupe) so retries/double-clicks don't duplicate
- [ ] Bot / spam protection on public forms
- [ ] URL/text inputs restrict dangerous protocols (`http(s):` only; block `javascript:`); user-supplied HTML escaped/sanitized
- [ ] File uploads validated (type, size, filename) and stored outside a publicly listable path

**Frontend (general web)**
- [ ] Error states and error boundaries — no white screen / unhandled rejection on failure
- [ ] Loading and empty states for async data
- [ ] Responsive / mobile+tablet layout; long text or URLs don't break layout (`overflow-wrap` / `word-break`); no horizontal shift from always-on scrollbars (`scrollbar-gutter: stable`)
- [ ] `<html lang>` set correctly (e.g. `lang="ja"` for a Japanese site)
- [ ] Font loading avoids FOIT/CLS (`next/font` or `font-display: swap`; subset large fonts); OS/browser font fallback checked
- [ ] Image optimization: right formats/sizes (WebP/AVIF), explicit dimensions/`aspect-ratio` + `sizes`, lazy loading; no oversized originals
- [ ] Third-party/analytics scripts loaded with `async`/`defer` or `next/script` strategy; not blocking render
- [ ] Large media (video / large GIFs) served from blob/object storage or a CDN, not bundled or inline
- [ ] Core Web Vitals sane (LCP < 2.5s, CLS ~0, INP < 200ms, TTFB low); hero/LCP element prioritized; consider real-user/field data (RUM) in addition to synthetic Lighthouse
- [ ] Custom 404 / error page, branded, returning the correct status code; favicon and apple-touch-icon present; no console errors in the prod build
- [ ] Bundle size controlled: code splitting, no oversized JS, no dev/unused modules shipped
- [ ] Static assets served with CDN/long-cache headers (fingerprinted) where appropriate
- [ ] API base URLs and config are env-driven, not hardcoded per environment
- [ ] Client-side storage resilient to Safari ITP (7-day eviction) — the app doesn't break when cookies/localStorage are cleared; no dependence on third-party cookies
- [ ] Run Lighthouse against the app (mobile + desktop) and check the scores — performance / accessibility / best-practices / SEO; note regressions against the target thresholds

**Frontend (a11y)**
- [ ] Accessibility lint rules enforced in CI as an error, not advisory (e.g. Biome's accessibility rules; `jsx-a11y` for React) — this is a required gate
- [ ] Semantic HTML and landmarks; heading order not skipped
- [ ] All interactive elements keyboard-operable with a visible focus indicator and logical focus order; focus managed for modals / menus / route changes
- [ ] Meaningful `alt` (decorative images `alt=""`); icon-only buttons/links (e.g. SVG icons) have an accessible name (`aria-label`) that matches any visible text
- [ ] Form fields have associated labels; errors conveyed by text/ARIA (`aria-live` / `role="alert"`), not color alone
- [ ] Color contrast meets WCAG AA; no link-in-text-block ambiguity
- [ ] Lighthouse accessibility ≥ 0.95 or an automated axe check passes — but note automated tools catch only part of the issues; do a manual keyboard + screen-reader pass on critical flows

**Next.js specific**
- [ ] Rendering strategy deliberate per route (Static / Dynamic / ISR / PPR); nothing forced dynamic by accident (stray `cookies()`/`headers()`/`no-store`)
- [ ] `next/image` for images and `next/font` for fonts (avoid CLS)
- [ ] Server vs Client Component boundary correct; `"use client"` kept minimal; no server-only secrets imported into client
- [ ] Server Actions validate their input; not exposing privileged operations
- [ ] Env vars: `NEXT_PUBLIC_` only for genuinely public values — **secrets must not be prefixed** (they ship to the browser)
- [ ] `next.config` production-safe: no `typescript.ignoreBuildErrors`, no `eslint.ignoreDuringBuilds`; security headers configured
- [ ] Caching intentional: `fetch` cache / `revalidate` / `cacheTag` / `cacheLife` set deliberately; no accidental stale or uncached hot paths
- [ ] `loading.tsx`, `error.tsx`, `not-found.tsx`, `global-error.tsx` present where they matter
- [ ] Route Handlers / Middleware: correct runtime (node/edge) and matcher; error handling
- [ ] Production build succeeds cleanly; Draft/Preview mode not reachable in prod
- [ ] Source maps uploaded to the error tracker so prod stack traces are readable; monitoring/tunnel routes (e.g. `/monitoring`) excluded from indexing

**Frontend (SEO)** (public, indexable sites only — N/A for internal tools / APIs)
- [ ] `metadataBase` set from the production URL (env-driven) — otherwise OG/canonical URLs resolve to the preview domain and break in prod
- [ ] Per-page `title`/template and meta description on key pages; `alternates.canonical` on important pages
- [ ] `allowIndexing` actually enabled in production (no stray site-wide `noindex`); no leftover example/sample routes indexed
- [ ] Error pages return the correct status code and `noindex`; thin/search/filter/duplicate pages set `noindex` or a canonical URL
- [ ] `openGraph` + `twitter` metadata (og:title/description/url/image, twitter:card); OG image (1200×630)
- [ ] `max-image-preview:large` in the `robots` directive (production only) so Google shows large image previews in Search / Discover / AI Overview — without it the preview is shrunk to a small thumbnail
- [ ] `robots.ts` (allow public, disallow `/api` and monitoring/tunnel routes, declare sitemap) and `sitemap.ts` (including dynamically generated pages)
- [ ] Structured data (JSON-LD): `Organization` / `WebSite` / `FAQPage` — factual only, no exaggeration; pass the CSP nonce if CSP is nonce-based, or it's blocked
- [ ] Single H1, semantic heading order, meaningful `alt` (decorative images `alt=""`)
- [ ] (External-console registration and launch validation for the above — GSC/Bing/Rich Results/OGP — live in the **Manual setup** bucket)

**Frontend (AIO / LLMO)** (public content sites that want to be discoverable/citable by AI search — ChatGPT search, Perplexity, Google AI Overviews, Gemini; a.k.a. GEO. Emerging, hard to measure, and **fast-changing** — weigh ROI, confirm current behavior via `WebSearch` of authoritative sources, and skip for internal tools / APIs)
- [ ] `llms.txt` at the site root: a plain-text, factual summary of the org/product — what it does, services, key facts, tech stack, contact
- [ ] AI-crawler policy explicit in `robots`: per-UA allow/disallow for GPTBot / OAI-SearchBot / ChatGPT-User / ClaudeBot / PerplexityBot / Google-Extended / Applebot-Extended (block only what you intend, e.g. scrapers); `/api` and monitoring/tunnel routes disallowed
- [ ] Entity-recognition structured data (JSON-LD): `Organization` / `Service` / `FAQPage` / `Person` (author/founder) with `sameAs` to authoritative profiles — factual only; pass the CSP nonce so it isn't blocked
- [ ] Representative image pinned for AI Overview / Search thumbnails: Google self-selects the preview image from page signals (often the first/most prominent image on the page), **not** from `og:image` — designate the intended one explicitly via JSON-LD (`WebPage.primaryImageOfPage` → `ImageObject`), or make that image the first prominent one, so an unintended image (e.g. a team-member photo) isn't chosen
- [ ] Value proposition and key facts are **real machine-readable text**, not locked inside images/canvas; semantic HTML so LLMs can extract them
- [ ] Citable, concrete facts present: numbers, dates, tech-stack names, quantitative outcomes — LLMs extract and cite statistical claims; FAQ written as question → factual answer
- [ ] E-E-A-T / authority signals: author/team bios, credentials, experience marked up (`Person`/`author`)
- [ ] Sitemap submitted to Bing Webmaster Tools (ChatGPT search uses a Bing backend) — see the **Manual setup** bucket
- [ ] No AI-specific anti-patterns: no hidden text / cloaking for crawlers, no keyword stuffing, no doorway pages; never add `unsafe-inline` to CSP just to ship JSON-LD (use the nonce)
- [ ] (optional) Measure indirectly: watch referrers from `chat.openai.com` / `perplexity.ai` / `gemini.google.com`; periodically ask the AI engines for your brand + service and check whether you're cited

**Legal & compliance** (any app that collects personal data or sets non-essential cookies)
- [ ] Cookie/consent UI where non-essential cookies or trackers are used; analytics/tag scripts load **only after** consent (and CSP updated for any added domains)
- [ ] Privacy policy published and linked from forms and the footer; states what personal data is collected, why, and where it goes
- [ ] Data handling deliberate: retention period, deletion path, and third-party processors disclosed; applicable regime considered (GDPR / local personal-data law)
- [ ] Legally required notices present where applicable to the jurisdiction/feature (e.g. JP telecommunications-business notification for private messaging features)
- [ ] Product/service name checked for unintended meanings in target locales

**Security (common only — delegate the rest to `security-review`)**
- [ ] No hardcoded secrets / API keys / tokens; an automated secret-scan gate in CI and pre-commit; secrets sourced from env/vault
- [ ] Env vars validated at the boundary so misconfig fails fast, not at runtime
- [ ] HTTPS/TLS enforced; HSTS (ideally with preload)
- [ ] Cookies: `HttpOnly` + `Secure` + `SameSite` (Lax/Strict), `Domain` scoped correctly, `__Host-`/`__Secure-` prefix for session cookies
- [ ] Security headers complete: CSP (prefer nonce + `strict-dynamic` over `unsafe-inline`), `X-Frame-Options` (DENY/SAMEORIGIN) or `frame-ancestors`, `X-Content-Type-Options: nosniff`, `object-src 'none'`, `base-uri 'self'`, `form-action 'self'`, `upgrade-insecure-requests`
- [ ] Injection surfaces handled: no `dangerouslySetInnerHTML` on untrusted input, parameterized queries (no string-built SQL), output escaped/sanitized
- [ ] Dependency vulnerabilities checked (`npm audit` / `pnpm audit`) and automated dependency updates configured; no known-exploitable, reachable advisory
- [ ] `NEXT_PUBLIC_`/client bundle carries no secret; cloud-provider accounts have MFA (cannot-verify — account setting)
- [ ] Non-production deployments protected from public/crawler access (deployment protection / auth on preview envs), not just `noindex`
- [ ] Platform WAF / managed rules and bad-bot blocking configured where available (cannot-verify — platform setting)
- → For anything beyond these basics, recommend the `security-review` skill; don't attempt a full audit here.

**Observability**
- [ ] Structured logging with request/correlation IDs; **no secrets or PII in logs**; log persistence/retention (drains) for long-running debugging
- [ ] Error tracking (e.g. Sentry) wired on both frontend and backend, with source maps uploaded; server errors raise a notification/alert
- [ ] Analytics / product-metrics tool wired (page views, key events/conversions); consent-gated where required
- [ ] Metrics/alerting and uptime monitoring (often cannot-verify — infra); distributed tracing for multi-service/serverless paths

**Ops**
- [ ] Rollback strategy and, for risky launches, feature flags
- [ ] Incident response plan: escalation paths, comms channel, and who-does-what documented
- [ ] (optional) Load/stress test the critical path against upstream services (DB, third-party APIs) before launch
- [ ] Spend/budget alerts and usage limits configured to catch runaway cost (cannot-verify — platform setting)

**Toolchain & CI gates**
- [ ] Lint (with accessibility rules enabled as errors), typecheck (`tsc --noEmit`), unit/component tests, and production build all run and pass in CI
- [ ] (optional) Lighthouse CI (or equivalent) gating accessibility / SEO / best-practices in CI, and performance measured against a real deployed URL — a manual Lighthouse run (Frontend bucket) stays required regardless
- [ ] Runtime version pinned and consistent (`engines` / `.nvmrc` / `.tool-versions`) between local, CI, and deploy
- [ ] Lockfile committed to pin dependencies and speed up cached builds
- [ ] Build caching configured (e.g. Turborepo/remote cache in a monorepo) so unrelated packages don't rebuild
- [ ] Branch protection: PR required, required status checks, review before merge (usually cannot-verify — repo settings)

**Config, Deploy & Data**
- [ ] Env vars documented (`.env.example`) and set per environment; secrets not committed
- [ ] Reproducible build; CI green; zero-downtime / rolling deploy
- [ ] DB migrations backward-compatible and reversible (expand/contract for zero downtime)
- [ ] Backups enabled and restore-tested for the DB and object storage (usually cannot-verify); PII handling deliberate
- [ ] Serverless/compute region colocated with the primary DB/origin (avoid cross-region latency); function `maxDuration`/memory right-sized
- [ ] Custom domain DNS + SSL valid; a single canonical host (apex↔www redirect unified); cross-browser/device smoke check before launch

**Manual setup & launch registration** (external consoles / one-time human actions — mostly cannot-verify from the repo; confirm they were done)
- [ ] Google Search Console: property registered and verified (verification token wired, e.g. `metadata.verification.google`); sitemap submitted; URL inspection / index request for key pages
- [ ] Microsoft (Bing) Webmaster Tools: property added (import from Search Console, or `msvalidate.01` verification); sitemap submitted — matters because some AI search backends use Bing
- [ ] Rich Results Test — validate the production URL's structured data (JSON-LD): https://search.google.com/test/rich-results (reference: https://developers.google.com/search/docs/appearance/structured-data)
- [ ] OGP/social preview validated on the major platforms; `curl -I` the prod URL to confirm HSTS / CSP / canonical / robots response headers
- [ ] Error tracking (Sentry) actually set up on the console side: project created, DSN in env, source-map upload token configured (CI/host), alert rules for server errors
- [ ] Analytics tool set up on the console side: account/project created, script wired and receiving events, key conversions/events configured, consent-gated where required

If you spot an outright bug while reading (not just a readiness gap), record it as a concrete finding with its evidence.

### Phase 3: Classify findings and separate the unverifiable

Assign each finding a priority by the **absolute criteria** below — don't distribute evenly, and don't manufacture a P1 for a healthy app. Move everything the repo cannot settle into the Needs-confirmation section as an explicit question, not a pass or fail.

### Phase 4: Output the report

Use this format. Omit any priority section with no findings.

```
## Production Readiness Check: <app / scope>

### Overview
- Scope: <what was evaluated — which buckets applied, which skipped and why>
- Stack: <framework, datastores, deploy target, public-facing vs internal>
- Verdict: <Ready / Conditional (after P1s) / Not ready> — provisional, evidence-based

### P1 (Blocker) — must fix before going public
- <finding> — evidence: `path:line`. Why it is catastrophic on launch (outage / data loss / breach / silent failure).

### P2 (Should-fix)
- <finding> — evidence: `path:line`. Impact on reliability / operability / UX / discoverability.

### P3 (Nice-to-have)
- <finding> — evidence: `path:line`.

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
