# Frontend (SEO)

**Applies when:** the app is a **public, indexable content site** (marketing site, docs, blog). **N/A for internal tools and pure APIs — skip and say so once.**

Ground every judgment in `path:line`. External-console registration (GSC / Bing / Rich Results / OGP validation) lives in `manual-setup.md`, not here.

## Checklist
- [ ] `metadataBase` set from the production URL (env-driven) — otherwise OG/canonical URLs resolve to the preview domain and break in prod
- [ ] Per-page `title`/template and meta description on key pages; `alternates.canonical` on important pages
- [ ] `allowIndexing` actually enabled in production (no stray site-wide `noindex`); no leftover example/sample routes indexed
- [ ] Error pages return the correct status code and `noindex`; thin/search/filter/duplicate pages set `noindex` or a canonical URL
- [ ] `openGraph` + `twitter` metadata (og:title/description/url/image, twitter:card); OG image (1200×630)
- [ ] `max-image-preview:large` in the `robots` directive (production only) so Google shows large image previews in Search / Discover / AI Overview — without it the preview is shrunk to a small thumbnail
- [ ] `robots.ts` (allow public, disallow `/api` and monitoring/tunnel routes, declare sitemap) and `sitemap.ts` (including dynamically generated pages)
- [ ] Structured data (JSON-LD): `Organization` / `WebSite` / `FAQPage` — factual only, no exaggeration; pass the CSP nonce if CSP is nonce-based, or it's blocked
- [ ] Single H1, semantic heading order, meaningful `alt` (decorative images `alt=""`)

## Best-practice sources (fetch the live page; it wins over this file — SEO behavior is fast-moving)
- Google Search Essentials — https://developers.google.com/search/docs/essentials
- Structured data — https://developers.google.com/search/docs/appearance/structured-data
- robots meta / preview controls (`max-image-preview` etc.) — https://developers.google.com/search/docs/crawling-indexing/robots-meta-tag
