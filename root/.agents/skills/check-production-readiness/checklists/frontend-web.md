# Frontend (general web)

**Applies when:** the app renders a UI in the browser (any SPA, SSR, or static frontend). Skip for a pure API / backend service.

Ground every judgment in `path:line`. Run Lighthouse against the actual app where you can.

## Checklist
- [ ] Error states and error boundaries — no white screen / unhandled rejection on failure
- [ ] Loading and empty states for async data
- [ ] Failed `fetch`/query has a retry affordance and a terminal error state — never an infinite spinner; guard against a hung request (timeout / `AbortController`) so a slow network resolves to an error, not a permanent load
- [ ] Responsive / mobile+tablet layout; long text or URLs don't break layout (`overflow-wrap` / `word-break`); no horizontal shift from always-on scrollbars (`scrollbar-gutter: stable`)
- [ ] `viewport` meta present (`width=device-width, initial-scale=1`); form inputs use ≥16px font so iOS Safari doesn't auto-zoom on focus; don't disable user zoom (`maximum-scale=1`/`user-scalable=no` — an a11y regression)
- [ ] `<html lang>` set correctly (e.g. `lang="ja"` for a Japanese site)
- [ ] Font loading avoids FOIT/CLS (`next/font` or `font-display: swap`; subset large fonts); OS/browser font fallback checked
- [ ] Image optimization: right formats/sizes (WebP/AVIF), explicit dimensions/`aspect-ratio` + `sizes`, lazy loading; no oversized originals
- [ ] Third-party/analytics scripts loaded with `async`/`defer` or `next/script` strategy; not blocking render
- [ ] Ad-blocker resilience: core flows (navigation, form submit, conversion) don't depend on analytics/GTM/pixel scripts loading — 20–40% of users block them, so guard against the script being absent (no unhandled error, no blocked submit when `gtag`/`dataLayer` is undefined)
- [ ] Deep-link / return-to restoration: an unauthenticated deep link that bounces through an authorization redirect returns the user to the originally requested URL afterward (validated `returnTo`, not an open redirect), not dumped on a generic home/dashboard
- [ ] Large media (video / large GIFs) served from blob/object storage or a CDN, not bundled or inline
- [ ] Core Web Vitals sane (LCP < 2.5s, CLS ~0, INP < 200ms, TTFB low); hero/LCP element prioritized; consider real-user/field data (RUM) in addition to synthetic Lighthouse
- [ ] Custom 404 / error page, branded, returning the correct status code; favicon and apple-touch-icon present; no console errors in the prod build
- [ ] Bundle size controlled: code splitting, no oversized JS, no dev/unused modules shipped
- [ ] Static assets served with CDN/long-cache headers (fingerprinted) where appropriate
- [ ] API base URLs and config are env-driven, not hardcoded per environment
- [ ] Client-side storage resilient to Safari ITP (7-day eviction) — the app doesn't break when cookies/localStorage are cleared; no dependence on third-party cookies
- [ ] Run Lighthouse against the app (mobile + desktop) and check the scores — performance / accessibility / best-practices / SEO; note regressions against the target thresholds

## Best-practice sources (fetch the live page; it wins over this file)
- Core Web Vitals / perf — https://web.dev/explore/learn-core-web-vitals ; Lighthouse docs
- Next.js Optimizing (Images / Scripts / Fonts) — https://nextjs.org/docs (if Next.js)
