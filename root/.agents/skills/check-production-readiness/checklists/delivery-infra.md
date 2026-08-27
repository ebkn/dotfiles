# Delivery, infra & config (Ops + Toolchain/CI + Config/Deploy/Data)

**Applies when:** always — every app ships through some pipeline and runs on some infra. Many items here are **Cannot-verify** from the repo (branch protection, backups, uptime, budgets, DNS/SSL); surface those as explicit questions in Needs-confirmation rather than assuming pass/fail.

Ground code/config-visible items in `path:line`. Each item names a `verify:` and a `pass:`.

Two rules specific to this bucket. **A CI gate must be shown to run, not merely to be configured** — a lint script in `package.json` that no workflow invokes, or a step in a workflow that is not a required check, is a convention rather than a gate, and the two halves live in different files. And **the absence of a control is the finding**: a missing `permissions:` block is not a neutral silence, it inherits a broad default, so assert absence explicitly instead of skimming past it.

## Ops
- [ ] Rollback strategy and, for risky launches, feature flags
      `verify:` cite the documented rollback procedure and the platform's instant-rollback capability · `pass:` a named, tested path back — "redeploy the previous commit" only counts if migrations are reversible too, so read it together with the migration item below
- [ ] Incident response plan: escalation paths, comms channel, and who-does-what documented
      `verify:` cite the runbook; otherwise ask · `pass:` a named on-call owner and a channel. Cannot-verify is the honest answer for most repos
- [ ] (optional) Load/stress test the critical path against upstream services (DB, third-party APIs) before launch
      `verify:` ask whether one was run and against what · `pass:` stated. **Do not run a load test yourself** — it is an intrusive action against someone's infrastructure and their upstream providers' quotas
- [ ] Spend/budget alerts and usage limits configured to catch runaway cost (cannot-verify — platform setting)
      `verify:` ask · `pass:` an alert exists with a named recipient

## Toolchain & CI gates
- [ ] Lint (with accessibility rules enabled as errors), typecheck (`tsc --noEmit`), unit/component tests, and production build all run and pass in CI
      `verify:` list the gates defined in `package.json`, list those actually invoked by a workflow, and list those that are required status checks; the three lists must agree · `pass:` every gate runs on every PR and blocks merge. Report which of the three lists each gate is missing from — that names the fix
- [ ] Dead-code / unused-dependency detection wired (knip for JS/TS; golangci-lint `unused` / `deadcode` for Go; ruff `F401`/`F841` + optional vulture for Python) — no unused files, exports, or dependencies shipped. Unused runtime deps are both bundle bloat and extra supply-chain attack surface
      `verify:` if deps are installed, run the read-only detector (`npx knip`) and ground the finding in its output; cite its config and its CI step · `pass:` a detector runs in CI and its output is clean. If none exists, that absence is the finding
- [ ] (optional) Lighthouse CI (or equivalent) gating accessibility / SEO / best-practices in CI, and performance measured against a real deployed URL — a manual Lighthouse run (Frontend bucket) stays required regardless
      `verify:` cite the CI config and the URL it targets · `pass:` present, or explicitly out of scope
- [ ] Runtime version pinned and consistent (`engines` / `.nvmrc` / `.tool-versions`) between local, CI, and deploy
      `verify:` read the version from **each** of the three places — the pin file, the CI setup step, and the platform's runtime setting — and compare · `pass:` all three agree. Comparing only two is the usual mistake: CI reading `.nvmrc` proves nothing about what the deploy platform runs
- [ ] Lockfile committed to pin dependencies and speed up cached builds
      `verify:` confirm the lockfile is tracked, and that CI installs with the frozen-lockfile form (`npm ci`, `--frozen-lockfile`, `uv sync --locked`) · `pass:` both. A committed lockfile that CI ignores via a plain `install` is not a pin
- [ ] Build caching configured (e.g. Turborepo/remote cache in a monorepo) so unrelated packages don't rebuild
      `verify:` cite the cache config · `pass:` present where the repo shape warrants it; N/A for a single package
- [ ] Branch protection: PR required, required status checks, review before merge (usually cannot-verify — repo settings)
      `verify:` ask, or read it via the host's API if the requester has granted access · `pass:` PRs required with the CI gates listed as required checks — the second half is what ties this item to the CI gates above

## Supply-chain & build integrity

The attack surface is everything the build *pulls in* — packages, GitHub Actions, base images — plus how much a compromised one of those can do. Cite the config/line for each; where a control is missing, that absence is the finding.

- [ ] Dependencies pinned to exact versions (no floating `^`/`~`) with a committed lockfile, and pinning enforced by config (`.npmrc` `save-exact`, or equivalent)
      `verify:` grep the manifest for `^`/`~` ranges; cite the `save-exact` setting · `pass:` exact versions and enforcement — without the config, the next `npm install <pkg>` reintroduces a range and nothing notices
- [ ] Freshly-published versions held back before adoption — `.npmrc` `min-release-age` and/or Dependabot `cooldown` — so a just-hijacked release isn't auto-pulled during its most dangerous window; cite the config
      `verify:` cite the setting and its value · `pass:` a non-zero hold on both the install path and the update-bot path; one without the other leaves the corresponding window open
- [ ] Install-time script execution accounted for: `postinstall`/`preinstall` scripts are the primary npm RCE vector
      `verify:` cite `ignore-scripts` or the pnpm allowlist; list dependencies declaring install scripts · `pass:` either scripts are disabled, or the set that runs them is known and small. Do **not** hard-fail this — many native deps legitimately need scripts; report it as residual surface
- [ ] GitHub Actions pinned to a full 40-char commit SHA, not a mutable tag (`@v4`) — the tj-actions/changed-files compromise (2025) was a tag re-point that hit tens of thousands of repos
      `verify:` `grep -nE 'uses:.*@' .github/workflows/*.yml | grep -vE '@[0-9a-f]{40}'` must print nothing; then spot-check that a pinned SHA is the tag's **peeled commit** (`git ls-remote <repo> '<tag>^{}'`), not a tag object · `pass:` every `uses:` is a 40-hex commit SHA that resolves to its stated tag. The peeled check matters because an annotated tag's bare ref is also 40 hex characters and passes every syntactic test while pointing at an object no checkout matches
- [ ] Workflow `GITHUB_TOKEN` scoped least-privilege (top-level `permissions: contents: read`, escalated per-job only where needed)
      `verify:` `yq '.permissions' .github/workflows/*.yml` · `pass:` an explicit read-only default. `null` is a Gap, not a neutral result — it inherits the repository default, which is frequently write
- [ ] `actions/checkout` uses `persist-credentials: false` unless a later step needs the token
      `verify:` grep each checkout step · `pass:` present, or a cited reason a later step needs the token
- [ ] Dockerfile base image pinned by digest (`FROM …@sha256:`), not a floating tag; OS packages version-pinned; app deps installed from the lockfile (`npm ci`, not `npm install`); runs as non-root
      `verify:` read the `FROM`/`RUN`/`USER` lines · `pass:` digest-pinned base, lockfile install, and an explicit non-root `USER` — absence of `USER` means root, which is the default and therefore easy to miss
- [ ] Dependabot (or equivalent) covers **every** ecosystem actually present — the language (`npm`/`pip`/`gomod`) **and** `github-actions` **and** `docker` if a Dockerfile ships
      `verify:` compare `yq '.updates[].package-ecosystem' .github/dependabot.yml` against the ecosystems the repo actually contains · `pass:` every present ecosystem covered. A config listing only the language ecosystem lets the SHA pins above rot into known-CVE territory while looking configured

## Config, Deploy & Data
- [ ] Env vars documented (`.env.example`) and set per environment; secrets not committed
      `verify:` diff the keys read by the code against the keys in `.env.example`; confirm the deploy environment has them set · `pass:` no undocumented required var — a var missing from the deploy environment surfaces as a runtime failure on a code path nobody exercised before launch
- [ ] Reproducible build; CI green; zero-downtime / rolling deploy
      `verify:` confirm CI is green on the current head, and cite the deploy strategy · `pass:` both
- [ ] DB migrations backward-compatible and reversible (expand/contract for zero downtime)
      `verify:` read the pending migrations for a destructive statement (drop/rename/narrowing type change) against a live table, and check each has a down path · `pass:` no destructive change deployed simultaneously with the code that depends on it. This is the item where a rollback plan silently stops working, so read it together with the rollback item above
- [ ] Backups enabled and restore-tested for the DB and object storage (usually cannot-verify); PII handling deliberate
      `verify:` ask — specifically whether a **restore** has ever been performed, not whether backups exist · `pass:` a restore has been tested. An untested backup is a hypothesis
- [ ] Serverless/compute region colocated with the primary DB/origin (avoid cross-region latency); function `maxDuration`/memory right-sized
      `verify:` compare the configured function region against the database region · `pass:` colocated, or the latency accepted deliberately
- [ ] Custom domain DNS + SSL valid; a single canonical host (apex↔www redirect unified); cross-browser/device smoke check before launch
      `verify:` `curl -sSI` the apex and the `www` host, and both over plain HTTP · `pass:` all variants converge on one canonical host over HTTPS with a permanent redirect. Two hosts both serving 200 splits SEO signal and breaks cookie scoping, and it is invisible unless each variant is requested separately

## Best-practice sources (fetch the live page; it wins over this file)
- The deploy platform's production checklist (e.g. Vercel — https://vercel.com/docs/production-checklist)
- The framework's own deployment/build docs for the version in use
- GitHub Actions secure-use reference (SHA pinning, `permissions`, `persist-credentials`) — https://docs.github.com/en/actions/reference/security/secure-use
- OpenSSF Scorecard checks (pinned dependencies, token permissions) — https://github.com/ossf/scorecard/blob/main/docs/checks.md
- SLSA supply-chain levels — https://slsa.dev/spec/
