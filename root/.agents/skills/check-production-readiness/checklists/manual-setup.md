# Manual setup & launch registration

**Applies when:** the app is launching to the public and depends on external consoles / one-time human actions. Most items are **Cannot-verify from the repo** — the repo can show the wiring (verification tokens, DSN in env) but not that the external step was completed. Report these as Needs-confirmation questions, and check the code side of each where it exists (cite `path:line`).

## Checklist
- [ ] Google Search Console: property registered and verified (verification token wired, e.g. `metadata.verification.google`); sitemap submitted; URL inspection / index request for key pages
- [ ] Microsoft (Bing) Webmaster Tools: property added (import from Search Console, or `msvalidate.01` verification); sitemap submitted — matters because some AI search backends use Bing
- [ ] Rich Results Test — validate the production URL's structured data (JSON-LD): https://search.google.com/test/rich-results (reference: https://developers.google.com/search/docs/appearance/structured-data)
- [ ] OGP/social preview validated on the major platforms; `curl -I` the prod URL to confirm HSTS / CSP / canonical / robots response headers
- [ ] Error tracking (Sentry) actually set up on the console side: project created, DSN in env, source-map upload token configured (CI/host), alert rules for server errors
- [ ] Analytics tool set up on the console side: account/project created, script wired and receiving events, key conversions/events configured, consent-gated where required

## Best-practice sources (fetch the live page; it wins over this file)
- Google Search Console / Rich Results Test docs — https://developers.google.com/search
- Bing Webmaster Tools — https://www.bing.com/webmasters/help
