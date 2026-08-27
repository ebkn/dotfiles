# Frontend (AIO / LLMO — AI-search discoverability)

**Applies when:** the app is a public content site that wants to be discoverable/citable by AI search (ChatGPT search, Perplexity, Google AI Overviews, Gemini; a.k.a. GEO). **N/A for internal tools and pure APIs.**

Emerging, hard to measure, and **fast-changing** — weigh ROI, and confirm current crawler/preview behavior via `WebSearch` of authoritative sources before asserting anything. Ground every judgment in `path:line`.

Each item names a `verify:` and a `pass:`. Note the honest limit of this whole bucket: what you can verify is that the *signals are present and well-formed*. Whether they produce a citation is not observable from here, on any timescale this check operates on — so no item below should be reported as "working", only as present or absent. Saying that plainly is more useful than a confident-sounding pass.

## Checklist
- [ ] `llms.txt` at the site root: a plain-text, factual summary of the org/product — what it does, services, key facts, tech stack, contact
      `verify:` `curl <url>/llms.txt` · `pass:` 200 with plain text, and its claims match the site. A 404 here is a Gap only if the site opted into this strategy — say which
- [ ] AI-crawler policy explicit in `robots`: per-UA allow/disallow for GPTBot / OAI-SearchBot / ChatGPT-User / ClaudeBot / PerplexityBot / Google-Extended / Applebot-Extended (block only what you intend, e.g. scrapers); `/api` and monitoring/tunnel routes disallowed
      `verify:` `curl <url>/robots.txt` and read the per-UA blocks; confirm the UA strings against the live crawler docs, since this list changes · `pass:` the policy in the file matches what the owner intends. **Ask what they intend rather than assuming** — "blocks GPTBot" is correct for some sites and a self-inflicted invisibility for others, and this bucket exists because the second one is usually unintentional
- [ ] Entity-recognition structured data (JSON-LD): `Organization` / `Service` / `FAQPage` / `Person` (author/founder) with `sameAs` to authoritative profiles — factual only; pass the CSP nonce so it isn't blocked
      `verify:` extract and parse the JSON-LD from the served page; `curl -sSI` each `sameAs` URL · `pass:` parses, factual, and every `sameAs` resolves — a dead profile link is a negative authority signal, not a neutral one
- [ ] Representative image pinned for AI Overview / Search thumbnails: Google self-selects the preview image from page signals (often the first/most prominent image on the page), **not** from `og:image` — designate the intended one explicitly via JSON-LD (`WebPage.primaryImageOfPage` → `ImageObject`), or make that image the first prominent one, so an unintended image (e.g. a team-member photo) isn't chosen
      `verify:` check for `primaryImageOfPage` in the JSON-LD, and separately identify which image is actually first in the rendered DOM · `pass:` the designated image and the first prominent image are the one you want. Where they disagree with `og:image`, say so — that disagreement is the whole point of this item
- [ ] Value proposition and key facts are **real machine-readable text**, not locked inside images/canvas; semantic HTML so LLMs can extract them
      `verify:` fetch the page **without executing JavaScript** (plain `curl`) and read what text is present · `pass:` the core proposition is in the returned HTML. A client-rendered value proposition is absent for any crawler that does not execute JS, and this is the one check that distinguishes them
- [ ] Citable, concrete facts present: numbers, dates, tech-stack names, quantitative outcomes — LLMs extract and cite statistical claims; FAQ written as question → factual answer
      `verify:` read the rendered copy and count the concrete, checkable claims · `pass:` specifics rather than adjectives. Flag any claim you cannot corroborate from the repo or the site — an invented statistic is a legal and reputational problem long before it is an SEO one
- [ ] E-E-A-T / authority signals: author/team bios, credentials, experience marked up (`Person`/`author`)
      `verify:` check for `Person`/`author` markup and visible bios · `pass:` present and factual
- [ ] Sitemap submitted to Bing Webmaster Tools (ChatGPT search uses a Bing backend) — see `manual-setup.md`
      `verify:` console-side; not observable here · `pass:` report as Needs-confirmation, not as a pass — see `manual-setup.md` and merge
- [ ] No AI-specific anti-patterns: no hidden text / cloaking for crawlers, no keyword stuffing, no doorway pages; never add `unsafe-inline` to CSP just to ship JSON-LD (use the nonce)
      `verify:` compare the response served to a normal user agent against one served to a crawler UA; grep the CSP for `unsafe-inline` and check whether JSON-LD is the reason it is there · `pass:` identical content to both, and no `unsafe-inline` added for JSON-LD's sake
- [ ] (optional) Measure indirectly: watch referrers from `chat.openai.com` / `perplexity.ai` / `gemini.google.com`; periodically ask the AI engines for your brand + service and check whether you're cited
      `verify:` cite whether referrer segmentation exists in the analytics setup · `pass:` a way to observe this after launch exists. This is the only item here that becomes measurable later, which is precisely why it is worth wiring before launch rather than after

## Best-practice sources (fetch the live page; it wins over this file — this area changes monthly)
- llms.txt spec — https://llmstxt.org/
- GPTBot — https://platform.openai.com/docs/gptbot
- Google-Extended / crawler overview — https://developers.google.com/search/docs/crawling-indexing/overview-google-crawlers
- ClaudeBot — https://support.anthropic.com/en/articles/8896518
