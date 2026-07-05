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
- [ ] (optional) Lighthouse CI (or equivalent) gating accessibility / SEO / best-practices in CI, and performance measured against a real deployed URL — a manual Lighthouse run (Frontend bucket) stays required regardless
- [ ] Runtime version pinned and consistent (`engines` / `.nvmrc` / `.tool-versions`) between local, CI, and deploy
- [ ] Lockfile committed to pin dependencies and speed up cached builds
- [ ] Build caching configured (e.g. Turborepo/remote cache in a monorepo) so unrelated packages don't rebuild
- [ ] Branch protection: PR required, required status checks, review before merge (usually cannot-verify — repo settings)

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
