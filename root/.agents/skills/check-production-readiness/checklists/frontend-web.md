# Frontend (general web)

**Applies when:** the app renders a UI in the browser (any SPA, SSR, or static frontend). Skip for a pure API / backend service.

Ground every judgment in `path:line`. Each item names a `verify:` and a `pass:`. Run Lighthouse against the actual app where you can — most of this bucket is about what a user experiences, and that is measured, not read.

## Checklist
- [ ] Error states and error boundaries — no white screen / unhandled rejection on failure
      `verify:` make a data dependency fail against the running app (block the API host, or request a route whose upstream is down) and look at what renders · `pass:` a readable error state. A boundary component that exists in the tree but sits above/below the throwing component never catches it, and only the failed render shows that
- [ ] Loading and empty states for async data
      `verify:` throttle the network and load a data-backed view; separately, view it with zero results · `pass:` both states are designed, not a blank region
- [ ] Failed `fetch`/query has a retry affordance and a terminal error state — never an infinite spinner; guard against a hung request (timeout / `AbortController`) so a slow network resolves to an error, not a permanent load
      `verify:` block the API host entirely and wait · `pass:` it resolves to an error with a retry within a bounded time. A bare `fetch()` has no timeout, so the default outcome here is a spinner that never ends — assume that unless a timeout is cited
- [ ] Responsive / mobile+tablet layout; long text or URLs don't break layout (`overflow-wrap` / `word-break`); no horizontal shift from always-on scrollbars (`scrollbar-gutter: stable`)
      `verify:` view at 320px, 768px, and desktop widths; paste a long unbroken string into any user-content area · `pass:` no horizontal page scroll at any width
- [ ] `viewport` meta present (`width=device-width, initial-scale=1`); form inputs use ≥16px font so iOS Safari doesn't auto-zoom on focus; don't disable user zoom (`maximum-scale=1`/`user-scalable=no` — an a11y regression)
      `verify:` read the rendered HTML head from the served response; check the computed font-size on form inputs · `pass:` viewport present, zoom not disabled, inputs ≥16px
- [ ] `<html lang>` set correctly (e.g. `lang="ja"` for a Japanese site)
      `verify:` read it from the served HTML and compare against the actual content language · `pass:` they agree — a Japanese site shipping the framework default `lang="en"` is the common miss
- [ ] Font loading avoids FOIT/CLS (`next/font` or `font-display: swap`; subset large fonts)
      `verify:` check the Lighthouse CLS breakdown and the font requests in the network panel · `pass:` no layout shift attributable to font swap; fonts self-hosted or preconnected
- [ ] Image optimization: right formats/sizes (WebP/AVIF), explicit dimensions/`aspect-ratio` + `sizes`, lazy loading; no oversized originals
      `verify:` read Lighthouse's "properly size images" / "next-gen formats" audits and the transferred byte sizes · `pass:` no image transferred at many times its displayed size; dimensions declared so nothing shifts
- [ ] Third-party/analytics scripts loaded with `async`/`defer` or `next/script` strategy; not blocking render
      `verify:` check for render-blocking resources in the Lighthouse report · `pass:` no third-party script blocks first paint
- [ ] Ad-blocker resilience: core flows (navigation, form submit, conversion) don't depend on analytics/GTM/pixel scripts loading — 20–40% of users block them, so guard against the script being absent (no unhandled error, no blocked submit when `gtag`/`dataLayer` is undefined)
      `verify:` load the app with the analytics host blocked and complete a conversion flow end to end · `pass:` the flow completes with no console error. Reading for `typeof gtag !== 'undefined'` guards is a weaker substitute — the failure is usually in a path nobody guarded
- [ ] Deep-link / return-to restoration: an unauthenticated deep link that bounces through an authorization redirect returns the user to the originally requested URL afterward (validated `returnTo`, not an open redirect), not dumped on a generic home/dashboard
      `verify:` request a deep link while logged out, authenticate, and see where you land; then try an external `returnTo` value · `pass:` returned to the original path, and external targets refused — cross-check the second half against `backend-api.md`'s open-redirect item and merge
- [ ] Large media (video / large GIFs) served from blob/object storage or a CDN, not bundled or inline
      `verify:` check the origin of large media requests and the build output size · `pass:` large media served from storage/CDN
- [ ] Core Web Vitals sane (LCP < 2.5s, CLS ~0, INP < 200ms, TTFB low); hero/LCP element prioritized; consider real-user/field data (RUM) in addition to synthetic Lighthouse
      `verify:` run Lighthouse mobile **against a deployed URL** and read the metric values · `pass:` within the thresholds. A local-build measurement is not comparable — no network latency, no CDN, no real device throttling — so report a local run as indicative only, and ask for field/RUM data if any exists, since synthetic and real users routinely disagree on INP
- [ ] Custom 404 / error page, branded, returning the correct status code; favicon and apple-touch-icon present; no console errors in the prod build
      `verify:` `curl -sSI <url>/definitely-not-a-real-path` and read the **status line**, then load it in a browser and read the console · `pass:` a branded page served with 404, not 200. A soft-404 (branded page, 200 status) is a real finding and is invisible in the browser
- [ ] Bundle size controlled: code splitting, no oversized JS, no dev/unused modules shipped
      `verify:` read the build output's per-route JS sizes; check for a dev-only dependency in the client bundle · `pass:` no route shipping an outlier bundle, no dev tooling in production output
- [ ] Static assets served with CDN/long-cache headers (fingerprinted) where appropriate
      `verify:` `curl -sSI` a fingerprinted asset and read `Cache-Control` · `pass:` a long `max-age` with `immutable` on fingerprinted assets, and a short/revalidating policy on HTML
- [ ] API base URLs and config are env-driven, not hardcoded per environment
      `verify:` grep for literal environment hostnames in source · `pass:` all environment-varying values come from env
- [ ] Client-side storage resilient to Safari ITP (7-day eviction) — the app doesn't break when cookies/localStorage are cleared; no dependence on third-party cookies
      `verify:` clear site data and reload · `pass:` the app recovers to a sane signed-out state rather than erroring on missing storage
- [ ] Run Lighthouse against the app (mobile + desktop) and check the scores — performance / accessibility / best-practices / SEO; note regressions against the target thresholds
      `verify:` `lighthouse <url> --preset=desktop` and a mobile run; report the four category scores · `pass:` report the numbers and the URL they were measured against. State whether the target was a deployed origin or a local build — without that, the scores are uninterpretable

## Best-practice sources (fetch the live page; it wins over this file)
- Core Web Vitals / perf — https://web.dev/explore/learn-core-web-vitals ; Lighthouse docs
- Next.js Optimizing (Images / Scripts / Fonts) — https://nextjs.org/docs (if Next.js)
