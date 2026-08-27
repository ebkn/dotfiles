# Manual setup & launch registration

**Applies when:** the app is launching to the public and depends on external consoles / one-time human actions. Most items are **Cannot-verify from the repo** — the repo can show the wiring (verification tokens, DSN in env) but not that the external step was completed. Report these as Needs-confirmation questions, and check the code side of each where it exists (cite `path:line`).

Each item names a `verify:` and a `pass:`. The pattern throughout is a **split verdict**: the wiring half is checkable here, the console half is not. Report both halves separately rather than collapsing them — "the token is in the code" and "the property is verified" are different facts, and a launch fails on the second while the first looks reassuring.

## Checklist
- [ ] Google Search Console: property registered and verified (verification token wired, e.g. `metadata.verification.google`); sitemap submitted; URL inspection / index request for key pages
      `verify:` wiring — `curl` the production page and confirm the verification meta tag is in the served HTML, not merely in the source. Console — ask · `pass:` tag present **and** the owner confirms the property is verified and the sitemap submitted
- [ ] Microsoft (Bing) Webmaster Tools: property added (import from Search Console, or `msvalidate.01` verification); sitemap submitted — matters because some AI search backends use Bing
      `verify:` wiring — check for `msvalidate.01` in the served HTML if that verification route was used. Console — ask · `pass:` owner confirms. Worth raising even when the team considers Bing irrelevant: the reason is ChatGPT search, not Bing's own traffic share
- [ ] Rich Results Test — validate the production URL's structured data (JSON-LD): https://search.google.com/test/rich-results (reference: https://developers.google.com/search/docs/appearance/structured-data)
      `verify:` extract and parse the JSON-LD from the production response yourself first — a parse error or a missing required property is findable here and does not need the console. Then ask for a Rich Results Test run · `pass:` valid JSON-LD locally **and** a clean console run. Report the local result as evidence; it is the half that turns "please go run this" into a specific fix
- [ ] OGP/social preview validated on the major platforms; `curl -I` the prod URL to confirm HSTS / CSP / canonical / robots response headers
      `verify:` `curl -sS -D - <prod url>/` for the headers and OG tags, and `curl -sSI` the `og:image` URL · `pass:` headers as expected and the image returns 200. Platform-side preview rendering (and cache busting on their debuggers) stays a console step — merge the header half with `security.md` rather than reporting it twice
- [ ] Error tracking (Sentry) actually set up on the console side: project created, DSN in env, source-map upload token configured (CI/host), alert rules for server errors
      `verify:` wiring — cite the SDK init and the CI source-map upload step; confirm the DSN comes from env and is set in the deploy environment. Console — ask whether a test event has ever arrived and whether an alert rule exists · `pass:` both. An SDK initialized with an unset DSN no-ops silently, so "the code calls init" is not evidence of anything — see `observability.md`, and merge
- [ ] Analytics tool set up on the console side: account/project created, script wired and receiving events, key conversions/events configured, consent-gated where required
      `verify:` wiring — confirm an actual analytics request leaves the running app (see `observability.md`). Console — ask whether events are visible in the dashboard and whether conversions are defined · `pass:` both. Events arriving is not the same as conversions being configured, and only the second one is what anyone will look at after launch

## Best-practice sources (fetch the live page; it wins over this file)
- Google Search Console / Rich Results Test docs — https://developers.google.com/search
- Bing Webmaster Tools — https://www.bing.com/webmasters/help
