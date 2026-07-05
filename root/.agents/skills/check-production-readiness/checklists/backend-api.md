# Backend & API

**Applies when:** the app has any server-side code — API routes, route handlers, server actions, background workers, or a datastore. Skip for a pure static site with no server logic.

Ground every judgment in `path:line`. Land each item in OK / Gap / N/A / Cannot-verify.

## Checklist
- [ ] Error handling on every external/IO call; correct HTTP status codes; no swallowed errors
- [ ] No internal exception / stack trace / raw server error leaked to users (map to safe messages)
- [ ] Timeouts on all outbound calls (DB, HTTP, cache); bounded retries with backoff (never infinite)
- [ ] Input validation on every endpoint (schema/type validation at the boundary)
- [ ] (optional) Rate limiting / abuse protection on public endpoints
- [ ] Idempotency for retryable or redelivered mutations (webhooks, queue consumers, double-clicks)
- [ ] (optional) Pagination / result limits on list queries (no unbounded fetches)
- [ ] No N+1 queries; indexes present on hot query paths
- [ ] Connection pooling with a bounded pool size
- [ ] Transactions around multi-step writes
- [ ] (optional) Graceful shutdown: drain in-flight requests, close DB/connections
- [ ] Health/readiness endpoint matched to the deploy orchestrator
- [ ] CORS scoped correctly (no wildcard origin with credentials); request body size limits
- [ ] Open-redirect protection: user-supplied redirect targets validated against an allowlist
- [ ] SSRF protection on server-side fetches of user-supplied URLs (link previews, import-by-URL, webhooks): validate against an allowlist, block private/link-local/loopback ranges and cloud metadata endpoints (`169.254.169.254`, `metadata.google.internal`), disable redirect-following to those ranges — otherwise an attacker exfiltrates instance credentials/IMDS tokens
- [ ] No user input reflected unvalidated into response headers (header injection)
- [ ] Personalized/private responses are not cached by shared CDN/KV caches (`Cache-Control: private`/`no-store`); only truly public responses are cached
- [ ] Object storage: buckets/prefixes not publicly listable; only intended objects are public

## Best-practice sources (fetch the live page; it wins over this file)
- OWASP Cheat Sheets (SSRF Prevention, Unvalidated Redirects, REST Security) — https://cheatsheetseries.owasp.org/
- OWASP Secure Headers — https://owasp.org/www-project-secure-headers/
- The official docs of the actual datastore / ORM / queue / cache in use — `WebSearch` "\<lib\>@\<version\> production best practices"
