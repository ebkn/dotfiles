# Frontend (SEO)

**Applies when:** the app is a **public, indexable content site** (marketing site, docs, blog). **N/A for internal tools and pure APIs — skip and say so once.**

Ground every judgment in `path:line`. External-console registration (GSC / Bing / Rich Results / OGP validation) lives in `manual-setup.md`, not here.

Each item names a `verify:` and a `pass:`. Almost everything here is delivered as markup or a header, so the served response is the evidence — and for SEO specifically, the response that matters is the **production** one: `metadataBase`, canonical URLs, and the robots directive are exactly the values that differ between environments, which is why reading them off a local build is misleading rather than merely weaker.

## Checklist
- [ ] `metadataBase` set from the production URL (env-driven) — otherwise OG/canonical URLs resolve to the preview domain and break in prod
      `verify:` read the rendered `og:url` and `link rel=canonical` from the production response · `pass:` absolute URLs on the production origin. A preview-domain canonical served in production points search engines at the wrong host, and it is only visible in the rendered output
- [ ] Per-page `title`/template and meta description on key pages; `alternates.canonical` on important pages
      `verify:` fetch several key pages and compare their `<title>` and description · `pass:` each page distinct and descriptive — a template applied but never overridden yields the same title sitewide, which reads as configured
- [ ] `allowIndexing` actually enabled in production (no stray site-wide `noindex`); no leftover example/sample routes indexed
      `verify:` `curl -sS -D - <prod url>/` and check **both** the `X-Robots-Tag` response header and the `robots` meta tag · `pass:` neither says `noindex`. Check both: a header set at the platform layer overrides correct markup and is invisible in the HTML. This is the single highest-cost item in the bucket — a site launched with `noindex` is simply absent from search until someone notices
- [ ] Error pages return the correct status code and `noindex`; thin/search/filter/duplicate pages set `noindex` or a canonical URL
      `verify:` `curl -sSI` a non-existent path and read the status line · `pass:` 404 status, not a 200 soft-404 — cross-check with `frontend-web.md`'s 404 item and merge the finding
- [ ] `openGraph` + `twitter` metadata (og:title/description/url/image, twitter:card); OG image (1200×630)
      `verify:` read the tags from the response, then `curl -sSI` the `og:image` URL · `pass:` all tags present and the image URL returns 200 with the right dimensions. A relative or preview-domain `og:image` is the usual break, and every social platform silently drops it
- [ ] `max-image-preview:large` in the `robots` directive (production only) so Google shows large image previews in Search / Discover / AI Overview — without it the preview is shrunk to a small thumbnail
      `verify:` read the robots directive from the production response · `pass:` present in production
- [ ] `robots.ts` (allow public, disallow `/api` and monitoring/tunnel routes, declare sitemap) and `sitemap.ts` (including dynamically generated pages)
      `verify:` `curl <url>/robots.txt` and `curl <url>/sitemap.xml` · `pass:` both return content rather than 404, the sitemap is declared in robots.txt, and the sitemap's URL count matches the number of real pages. These are generated routes — a file existing in the tree is not evidence the route resolves, and a sitemap listing only static routes is the standard omission
- [ ] Structured data (JSON-LD): `Organization` / `WebSite` / `FAQPage` — factual only, no exaggeration; pass the CSP nonce if CSP is nonce-based, or it's blocked
      `verify:` extract the JSON-LD from the served HTML, confirm it parses, and check its claims against what the site actually offers; if CSP is nonce-based, confirm the script carries the nonce · `pass:` valid, factual, and not blocked. Console-side validation via the Rich Results Test belongs to `manual-setup.md`
- [ ] Single H1, semantic heading order, meaningful `alt` (decorative images `alt=""`)
      `verify:` extract the heading outline and image alt attributes from the rendered page · `pass:` one H1, no skipped level — same evidence as `frontend-a11y.md`'s heading item, so merge rather than reporting twice

## Best-practice sources (fetch the live page; it wins over this file — SEO behavior is fast-moving)
- Google Search Essentials — https://developers.google.com/search/docs/essentials
- Structured data — https://developers.google.com/search/docs/appearance/structured-data
- robots meta / preview controls (`max-image-preview` etc.) — https://developers.google.com/search/docs/crawling-indexing/robots-meta-tag
