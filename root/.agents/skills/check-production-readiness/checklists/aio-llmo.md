# Frontend (AIO / LLMO — AI-search discoverability)

**Applies when:** the app is a public content site that wants to be discoverable/citable by AI search (ChatGPT search, Perplexity, Google AI Overviews, Gemini; a.k.a. GEO). **N/A for internal tools and pure APIs.**

Emerging, hard to measure, and **fast-changing** — weigh ROI, and confirm current crawler/preview behavior via `WebSearch` of authoritative sources before asserting anything. Ground every judgment in `path:line`.

## Checklist
- [ ] `llms.txt` at the site root: a plain-text, factual summary of the org/product — what it does, services, key facts, tech stack, contact
- [ ] AI-crawler policy explicit in `robots`: per-UA allow/disallow for GPTBot / OAI-SearchBot / ChatGPT-User / ClaudeBot / PerplexityBot / Google-Extended / Applebot-Extended (block only what you intend, e.g. scrapers); `/api` and monitoring/tunnel routes disallowed
- [ ] Entity-recognition structured data (JSON-LD): `Organization` / `Service` / `FAQPage` / `Person` (author/founder) with `sameAs` to authoritative profiles — factual only; pass the CSP nonce so it isn't blocked
- [ ] Representative image pinned for AI Overview / Search thumbnails: Google self-selects the preview image from page signals (often the first/most prominent image on the page), **not** from `og:image` — designate the intended one explicitly via JSON-LD (`WebPage.primaryImageOfPage` → `ImageObject`), or make that image the first prominent one, so an unintended image (e.g. a team-member photo) isn't chosen
- [ ] Value proposition and key facts are **real machine-readable text**, not locked inside images/canvas; semantic HTML so LLMs can extract them
- [ ] Citable, concrete facts present: numbers, dates, tech-stack names, quantitative outcomes — LLMs extract and cite statistical claims; FAQ written as question → factual answer
- [ ] E-E-A-T / authority signals: author/team bios, credentials, experience marked up (`Person`/`author`)
- [ ] Sitemap submitted to Bing Webmaster Tools (ChatGPT search uses a Bing backend) — see `manual-setup.md`
- [ ] No AI-specific anti-patterns: no hidden text / cloaking for crawlers, no keyword stuffing, no doorway pages; never add `unsafe-inline` to CSP just to ship JSON-LD (use the nonce)
- [ ] (optional) Measure indirectly: watch referrers from `chat.openai.com` / `perplexity.ai` / `gemini.google.com`; periodically ask the AI engines for your brand + service and check whether you're cited

## Best-practice sources (fetch the live page; it wins over this file — this area changes monthly)
- llms.txt spec — https://llmstxt.org/
- GPTBot — https://platform.openai.com/docs/gptbot
- Google-Extended / crawler overview — https://developers.google.com/search/docs/crawling-indexing/overview-google-crawlers
- ClaudeBot — https://support.anthropic.com/en/articles/8896518
