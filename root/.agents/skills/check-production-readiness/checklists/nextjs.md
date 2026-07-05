# Next.js specific

**Applies when:** the app is a Next.js project (`next` in `package.json`). Note App Router vs Pages Router and adjust items accordingly. Skip entirely for non-Next.js apps.

Ground every judgment in `path:line`.

## Checklist
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
- [ ] Post-deploy version skew handled: a client on the old bundle requesting a now-removed chunk shouldn't dead-end on `ChunkLoadError` — recover (error boundary that hard-reloads on chunk-load failure) and/or enable deployment skew protection where the platform offers it (e.g. Vercel Skew Protection)
- [ ] Source maps: uploaded to the error tracker so prod stack traces are readable, **but not served publicly** — leaving `productionBrowserSourceMaps: true` (or shipping `.map` files) exposes readable source to anyone; upload then withhold from the public bundle unless public exposure is intended; monitoring/tunnel routes (e.g. `/monitoring`) excluded from indexing

## Best-practice sources (fetch the live page; it wins over this file)
- Next.js production checklist + Optimizing + Caching — https://nextjs.org/docs (search "production checklist" if the path moved)
- Vercel production checklist — https://vercel.com/docs/production-checklist
- Vercel Skew Protection — https://vercel.com/docs/deployments/skew-protection
- React (rules of hooks, `use client`/server boundaries) — https://react.dev
