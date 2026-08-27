# Security (common items only — delegate the rest to `security-review`)

**Applies when:** always. This bucket covers everyday security hygiene only. It is **not** a full security audit — when a finding suggests deeper exposure (injection surfaces, access-control logic, data-handling), recommend the `security-review` skill rather than going deep here.

Ground every judgment in `path:line`. Each item names a `verify:` and a `pass:`; where `verify:` is a command and a URL is reachable, **run it**. Security is the bucket where reading the config and reading the response diverge most often, because headers pass through middleware, the platform edge, and a CDN before a client sees them.

**Test the app, not the infrastructure around it.** Every command below is an ordinary request or a local inspection. Do not attempt exploitation, credential brute-forcing, or scanning of hosts beyond the app under review — this skill has no authorization for that, and a readiness check is not a penetration test.

## Checklist
- [ ] No hardcoded secrets / API keys / tokens; an automated secret-scan gate in CI and pre-commit; secrets sourced from env/vault
      `verify:` grep the tree for key-shaped literals (`sk-`, `AKIA`, `-----BEGIN`, long base64/hex assigned to a name containing key/token/secret) and **check git history too** — a rotated-out secret still in an old commit is still leaked; then cite the CI secret-scan step · `pass:` no live credential in the tree or history, and a scan gate that runs on every push
- [ ] Env vars validated at the boundary so misconfig fails fast, not at runtime
      `verify:` cite the schema that parses `process.env`/`os.environ` at startup · `pass:` a missing required var stops the process at boot with a named error, rather than surfacing as `undefined` in a request months later
- [ ] HTTPS/TLS enforced; HSTS (ideally with preload)
      `verify:` `curl -sSI http://<domain>` — read the redirect — then `curl -sSI https://<domain>` and read `Strict-Transport-Security` · `pass:` plain HTTP 301/308s to HTTPS, and HSTS is present with a non-trivial `max-age`. Only a real HTTPS origin settles this: HSTS delivered over `localhost` is ignored by every browser, so a local run leaves this Cannot-verify
- [ ] Cookies: `HttpOnly` + `Secure` + `SameSite` (Lax/Strict), `Domain` scoped correctly, `__Host-`/`__Secure-` prefix for session cookies
      `verify:` `curl -sSI` a route that sets a session cookie and read every `Set-Cookie` attribute verbatim · `pass:` session cookies carry all three flags. Read the response, not the code that builds it — a framework's session middleware, a proxy, and the code each get a say, and the wire is the only place their combined result is visible
- [ ] Security headers complete: CSP (prefer nonce + `strict-dynamic` over `unsafe-inline`), `X-Frame-Options` (DENY/SAMEORIGIN) or `frame-ancestors`, `X-Content-Type-Options: nosniff`, `object-src 'none'`, `base-uri 'self'`, `form-action 'self'`, `upgrade-insecure-requests`
      `verify:` `curl -sS -D - -o /dev/null <url>/` and check each header against the list; repeat on an API route and a dynamic route, not just the home page · `pass:` all present on every route type. A `headers()` matcher that covers `/` and misses `/api/*` is the standard failure and is invisible from a single request — and a CSP containing `unsafe-inline` is a Gap even though the header is present
- [ ] Injection surfaces handled: no `dangerouslySetInnerHTML` on untrusted input, parameterized queries (no string-built SQL), output escaped/sanitized
      `verify:` grep for `dangerouslySetInnerHTML`, `innerHTML`, and string-concatenated/interpolated SQL; for each hit, trace whether the value can originate from a request · `pass:` no user-controlled value reaches an HTML sink or a query string unparameterized. Reachability is the judgment — a constant passed to `dangerouslySetInnerHTML` is not a finding
- [ ] **Authorization enforced server-side on every protected route/action** — no missing object-level checks / IDOR, no client-only gating. This is the deep access-control concern: verify the basics here, then **explicitly hand deeper authz analysis to `security-review`** rather than green-lighting it from this skill.
      `verify:` list protected routes/actions, then list those whose handler performs an ownership or role check *before* acting; the difference is the finding. Where the app is running and the requester has supplied two test accounts, confirm by requesting one account's object as the other · `pass:` 403/404 for the wrong owner. **Only test with credentials the requester provided for this purpose** — never with a real user's account
- [ ] Dependency vulnerabilities checked (`npm audit` / `pnpm audit`) and automated dependency updates configured; no known-exploitable, reachable advisory
      `verify:` run the ecosystem's audit command and read the output; for each high/critical, determine whether the vulnerable code path is actually reached by this app · `pass:` no reachable known-exploitable advisory. Report the count *and* the reachability judgment — an unqualified "12 vulnerabilities" is noise that trains the reader to ignore this line
- [ ] Supply-chain surface minimized: dependencies, GitHub Actions, and container base images pinned (exact/SHA/digest); install-script execution considered; updates gated by a release-age cooldown — full checklist lives in `delivery-infra.md` (merge overlaps in Phase 3), and deeper provenance/build-integrity analysis goes to `security-review`
      `verify:` see `delivery-infra.md`, which carries the commands · `pass:` as stated there — report once, merged, not twice
- [ ] `NEXT_PUBLIC_`/client bundle carries no secret; cloud-provider accounts have MFA (cannot-verify — account setting)
      `verify:` grep the **built** client bundle for the values of server-side env vars, not just the source for `NEXT_PUBLIC_` prefixes — a secret can reach the browser through an import chain without ever being prefixed · `pass:` no server-side secret value appears in any client-served asset. MFA is Cannot-verify; ask
- [ ] Non-production deployments protected from public/crawler access (deployment protection / auth on preview envs), not just `noindex`
      `verify:` `curl -sSI <preview/staging URL>` from an unauthenticated context · `pass:` 401/403, not 200. `noindex` is not protection — it asks crawlers not to list the URL and does nothing about anyone who has it
- [ ] Platform WAF / managed rules and bad-bot blocking configured where available (cannot-verify — platform setting)
      `verify:` cite the IaC/platform config if it is in the repo; otherwise ask · `pass:` stated by the operator — do not infer this from the absence of evidence in either direction

→ For anything beyond these basics, recommend the `security-review` skill; don't attempt a full audit here.

## Best-practice sources (fetch the live page; it wins over this file — advisories change frequently)
- OWASP Secure Headers — https://owasp.org/www-project-secure-headers/
- OWASP Cheat Sheets — https://cheatsheetseries.owasp.org/
- OWASP ASVS / Authentication & Authorization Cheat Sheets — https://cheatsheetseries.owasp.org/
