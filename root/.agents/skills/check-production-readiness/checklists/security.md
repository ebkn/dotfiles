# Security (common items only — delegate the rest to `security-review`)

**Applies when:** always. This bucket covers everyday security hygiene only. It is **not** a full security audit — when a finding suggests deeper exposure (injection surfaces, access-control logic, data-handling), recommend the `security-review` skill rather than going deep here.

Ground every judgment in `path:line`.

## Checklist
- [ ] No hardcoded secrets / API keys / tokens; an automated secret-scan gate in CI and pre-commit; secrets sourced from env/vault
- [ ] Env vars validated at the boundary so misconfig fails fast, not at runtime
- [ ] HTTPS/TLS enforced; HSTS (ideally with preload)
- [ ] Cookies: `HttpOnly` + `Secure` + `SameSite` (Lax/Strict), `Domain` scoped correctly, `__Host-`/`__Secure-` prefix for session cookies
- [ ] Security headers complete: CSP (prefer nonce + `strict-dynamic` over `unsafe-inline`), `X-Frame-Options` (DENY/SAMEORIGIN) or `frame-ancestors`, `X-Content-Type-Options: nosniff`, `object-src 'none'`, `base-uri 'self'`, `form-action 'self'`, `upgrade-insecure-requests`
- [ ] Injection surfaces handled: no `dangerouslySetInnerHTML` on untrusted input, parameterized queries (no string-built SQL), output escaped/sanitized
- [ ] **Authorization enforced server-side on every protected route/action** — no missing object-level checks / IDOR, no client-only gating. This is the deep access-control concern: verify the basics here, then **explicitly hand deeper authz analysis to `security-review`** rather than green-lighting it from this skill.
- [ ] Dependency vulnerabilities checked (`npm audit` / `pnpm audit`) and automated dependency updates configured; no known-exploitable, reachable advisory
- [ ] `NEXT_PUBLIC_`/client bundle carries no secret; cloud-provider accounts have MFA (cannot-verify — account setting)
- [ ] Non-production deployments protected from public/crawler access (deployment protection / auth on preview envs), not just `noindex`
- [ ] Platform WAF / managed rules and bad-bot blocking configured where available (cannot-verify — platform setting)

→ For anything beyond these basics, recommend the `security-review` skill; don't attempt a full audit here.

## Best-practice sources (fetch the live page; it wins over this file — advisories change frequently)
- OWASP Secure Headers — https://owasp.org/www-project-secure-headers/
- OWASP Cheat Sheets — https://cheatsheetseries.owasp.org/
- OWASP ASVS / Authentication & Authorization Cheat Sheets — https://cheatsheetseries.owasp.org/
