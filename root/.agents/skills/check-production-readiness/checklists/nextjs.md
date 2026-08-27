# Next.js specific

**Applies when:** the app is a Next.js project (`next` in `package.json`). Note App Router vs Pages Router and adjust items accordingly. Skip entirely for non-Next.js apps.

Ground every judgment in `path:line`. Each item names a `verify:` and a `pass:`; where `verify:` names a command and a URL is reachable, run it.

Next.js is the bucket where source-reading is least reliable, because rendering mode, caching, and header delivery are all decided by a build-time and request-time interaction that no single file states. Prefer the build output and the response.

## Checklist
- [ ] Rendering strategy deliberate per route (Static / Dynamic / ISR / PPR); nothing forced dynamic by accident (stray `cookies()`/`headers()`/`no-store`)
      `verify:` read the **build output table** (`npm run build` prints a per-route ○/ƒ/● legend) and compare it against what each route ought to be; then trace any unexpected `ƒ` to the `cookies()`/`headers()`/`no-store` call that forced it · `pass:` every route's actual mode matches intent. Ask the requester for the build log if you cannot build; this table is the authoritative answer and nothing in the source is
- [ ] `next/image` for images and `next/font` for fonts (avoid CLS)
      `verify:` grep for raw `<img`/`<link rel="stylesheet" href="fonts.googleapis` · `pass:` framework primitives used, or a stated reason not to
- [ ] Server vs Client Component boundary correct; `"use client"` kept minimal; no server-only secrets imported into client
      `verify:` for each `"use client"` file, follow its import graph for modules that read server env or a database client; confirm against the built client bundle · `pass:` no server-only module reachable from a client entry
- [ ] Server Actions validate their input; not exposing privileged operations
      `verify:` every `"use server"` function is a public HTTP endpoint — treat it as one: check for schema validation and an authorization check at its top · `pass:` both present. This is the item most often missed, because an action *looks* like a local function call at every call site
- [ ] Env vars: `NEXT_PUBLIC_` only for genuinely public values — **secrets must not be prefixed** (they ship to the browser)
      `verify:` list every `NEXT_PUBLIC_` var and judge each one's sensitivity; then grep the built client assets for the *values* of the non-public ones · `pass:` no secret prefixed, and no secret value present in a client asset by any route
- [ ] `next.config` production-safe: no `typescript.ignoreBuildErrors`, no `eslint.ignoreDuringBuilds`; security headers configured
      `verify:` `grep -nE 'ignoreBuildErrors|ignoreDuringBuilds' next.config.*` — must print nothing; then confirm the headers on the wire, not in the config · `pass:` neither switch present, and the configured headers actually arrive
- [ ] Caching intentional: `fetch` cache / `revalidate` / `cacheTag` / `cacheLife` set deliberately; no accidental stale or uncached hot paths
      `verify:` for each hot route, request it twice and compare the platform cache-status header and any timestamp in the body · `pass:` cached routes hit, dynamic routes do not, and no personalized route is shared-cached — cross-check that last one with `backend-api.md`'s cache item and merge the finding
- [ ] `loading.tsx`, `error.tsx`, `not-found.tsx`, `global-error.tsx` present where they matter
      `verify:` list them, then request a non-existent route and a route forced to throw, and look at what actually renders · `pass:` a branded page with the right status — a file that exists but sits at the wrong segment level never renders, and only the request shows that
- [ ] Route Handlers / Middleware: correct runtime (node/edge) and matcher; error handling
      `verify:` read the `matcher` and test a path just inside and just outside it · `pass:` middleware runs where intended and nowhere else; an over-broad matcher that also catches static assets is a performance and correctness finding
- [ ] Production build succeeds cleanly; Draft/Preview mode not reachable in prod
      `verify:` read the build log for warnings, not just its exit status; `curl` the draft-mode enable route in production · `pass:` a clean build, and draft mode unreachable without the secret
- [ ] Post-deploy version skew handled: a client on the old bundle requesting a now-removed chunk shouldn't dead-end on `ChunkLoadError` — recover (error boundary that hard-reloads on chunk-load failure) and/or enable deployment skew protection where the platform offers it (e.g. Vercel Skew Protection)
      `verify:` grep the error boundary for a chunk-load-failure branch; cite the platform's skew-protection setting if enabled · `pass:` one of the two exists. Cannot-verify without platform access is a legitimate answer here — say which half you could see
- [ ] Source maps: uploaded to the error tracker so prod stack traces are readable, **but not served publicly** — leaving `productionBrowserSourceMaps: true` (or shipping `.map` files) exposes readable source to anyone; upload then withhold from the public bundle unless public exposure is intended; monitoring/tunnel routes (e.g. `/monitoring`) excluded from indexing
      `verify:` `curl -sSI` a `.map` URL derived from a `sourceMappingURL` comment in a served JS asset · `pass:` 404 on the public `.map`, **and** a CI step that uploads maps to the tracker. Both halves: maps that are neither uploaded nor served leave production stack traces unreadable, which is the opposite failure and just as real

## Best-practice sources (fetch the live page; it wins over this file)
- Next.js production checklist + Optimizing + Caching — https://nextjs.org/docs (search "production checklist" if the path moved)
- Vercel production checklist — https://vercel.com/docs/production-checklist
- Vercel Skew Protection — https://vercel.com/docs/deployments/skew-protection
- React (rules of hooks, `use client`/server boundaries) — https://react.dev
