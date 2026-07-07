# Delivery, infra & config (Ops + Toolchain/CI + Config/Deploy/Data)

**Applies when:** always — every app ships through some pipeline and runs on some infra. Many items here are **Cannot-verify** from the repo (branch protection, backups, uptime, budgets, DNS/SSL); surface those as explicit questions in Needs-confirmation rather than assuming pass/fail.

Ground code/config-visible items in `path:line`.

## Ops
- [ ] Rollback strategy and, for risky launches, feature flags
- [ ] Incident response plan: escalation paths, comms channel, and who-does-what documented
- [ ] (optional) Load/stress test the critical path against upstream services (DB, third-party APIs) before launch
- [ ] Spend/budget alerts and usage limits configured to catch runaway cost (cannot-verify — platform setting)

## Toolchain & CI gates
- [ ] Lint (with accessibility rules enabled as errors), typecheck (`tsc --noEmit`), unit/component tests, and production build all run and pass in CI
- [ ] Dead-code / unused-dependency detection wired (knip for JS/TS; golangci-lint `unused` / `deadcode` for Go; ruff `F401`/`F841` + optional vulture for Python) — no unused files, exports, or dependencies shipped. Unused runtime deps are both bundle bloat and extra supply-chain attack surface; if a detector exists, confirm it runs in CI and cite its config, and if none exists flag the gap. If the repo has installed deps, you may run the read-only detector (e.g. `npx knip`) to ground the finding in its actual output
- [ ] (optional) Lighthouse CI (or equivalent) gating accessibility / SEO / best-practices in CI, and performance measured against a real deployed URL — a manual Lighthouse run (Frontend bucket) stays required regardless
- [ ] Runtime version pinned and consistent (`engines` / `.nvmrc` / `.tool-versions`) between local, CI, and deploy
- [ ] Lockfile committed to pin dependencies and speed up cached builds
- [ ] Build caching configured (e.g. Turborepo/remote cache in a monorepo) so unrelated packages don't rebuild
- [ ] Branch protection: PR required, required status checks, review before merge (usually cannot-verify — repo settings)

## Supply-chain & build integrity

The attack surface is everything the build *pulls in* — packages, GitHub Actions, base images — plus how much a compromised one of those can do. Cite the config/line for each; where a control is missing, that absence is the finding.

- [ ] Dependencies pinned to exact versions (no floating `^`/`~`) with a committed lockfile, and pinning enforced by config (`.npmrc` `save-exact`, or equivalent) — a floating range lets an unreviewed transitive bump land on the next install
- [ ] Freshly-published versions held back before adoption — `.npmrc` `min-release-age` and/or Dependabot `cooldown` — so a just-hijacked release isn't auto-pulled during its most dangerous window; cite the config
- [ ] Install-time script execution accounted for: `postinstall`/`preinstall` scripts are the primary npm RCE vector. If `ignore-scripts` (or pnpm's built-dependency allowlist) is set, note it; if not, flag it as residual attack surface — do **not** hard-fail, since many native deps legitimately need scripts
- [ ] GitHub Actions pinned to a full 40-char commit SHA, not a mutable tag (`@v4`) — the tj-actions/changed-files compromise (2025) was a tag re-point that hit tens of thousands of repos; cite any unpinned `uses:`
- [ ] Workflow `GITHUB_TOKEN` scoped least-privilege (top-level `permissions: contents: read`, escalated per-job only where needed) — caps the blast radius of a compromised action; a workflow with no `permissions:` block inherits broad write defaults
- [ ] `actions/checkout` uses `persist-credentials: false` unless a later step needs the token — otherwise the token is written to `.git/config` and can leak via artifacts/images
- [ ] Dockerfile base image pinned by digest (`FROM …@sha256:`), not a floating tag; OS packages version-pinned; app deps installed from the lockfile (`npm ci`, not `npm install`); runs as non-root — cite the `FROM`/`RUN`/`USER` lines
- [ ] Dependabot (or equivalent) covers **every** ecosystem actually present — the language (`npm`/`pip`/`gomod`) **and** `github-actions` **and** `docker` if a Dockerfile ships — so pins are refreshed instead of rotting into known-CVE territory

## Config, Deploy & Data
- [ ] Env vars documented (`.env.example`) and set per environment; secrets not committed
- [ ] Reproducible build; CI green; zero-downtime / rolling deploy
- [ ] DB migrations backward-compatible and reversible (expand/contract for zero downtime)
- [ ] Backups enabled and restore-tested for the DB and object storage (usually cannot-verify); PII handling deliberate
- [ ] Serverless/compute region colocated with the primary DB/origin (avoid cross-region latency); function `maxDuration`/memory right-sized
- [ ] Custom domain DNS + SSL valid; a single canonical host (apex↔www redirect unified); cross-browser/device smoke check before launch

## Best-practice sources (fetch the live page; it wins over this file)
- The deploy platform's production checklist (e.g. Vercel — https://vercel.com/docs/production-checklist)
- The framework's own deployment/build docs for the version in use
- GitHub Actions secure-use reference (SHA pinning, `permissions`, `persist-credentials`) — https://docs.github.com/en/actions/reference/security/secure-use
- OpenSSF Scorecard checks (pinned dependencies, token permissions) — https://github.com/ossf/scorecard/blob/main/docs/checks.md
- SLSA supply-chain levels — https://slsa.dev/spec/
