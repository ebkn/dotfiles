# Backend & API

**Applies when:** the app has any server-side code — API routes, route handlers, server actions, background workers, or a datastore. Skip for a pure static site with no server logic.

Ground every judgment in `path:line`. Land each item in OK / Gap / N/A / Cannot-verify.

Each item names a `verify:` (how to establish its state) and a `pass:` (what counts as OK). Where `verify:` is a command and a URL is reachable, **run it** — a config that should produce a behavior and a response that does are different claims, and the report must say which one you have.

## Checklist
- [ ] Error handling on every external/IO call; correct HTTP status codes; no swallowed errors
      `verify:` grep each `await`/`fetch`/driver call for an enclosing try/catch or error branch; list the calls that have none · `pass:` every IO call either handles its failure or propagates to a handler that maps it to a status — an empty `catch {}` is a Gap, not a pass
- [ ] No internal exception / stack trace / raw server error leaked to users (map to safe messages)
      `verify:` request a route with input that forces a failure (malformed body, missing required field) against the running instance and read the response body · `pass:` no stack frame, file path, SQL text, or driver error string in the body — a generic message plus a correlation ID
- [ ] Timeouts on all outbound calls (DB, HTTP, cache); bounded retries with backoff (never infinite)
      `verify:` for each outbound client, cite the line setting its timeout; a bare `fetch()` has **none** by default, so absence of a `signal`/`AbortSignal.timeout` is itself the finding · `pass:` every outbound call has an explicit timeout and a retry count that terminates
- [ ] Input validation on every endpoint (schema/type validation at the boundary)
      `verify:` list endpoints, then list those whose handler parses the body through a schema; the difference is the finding. Confirm by POSTing a wrong-typed field to the running instance · `pass:` a 4xx with a validation error — not a 500, and not a 200
- [ ] (optional) Rate limiting / abuse protection on public endpoints
      `verify:` cite the limiter middleware/config, or the platform-level rule; if neither is visible this is Cannot-verify at the platform layer, not an automatic Gap · `pass:` a stated limit on public write endpoints
- [ ] Idempotency for retryable or redelivered mutations (webhooks, queue consumers, double-clicks)
      `verify:` send the same request twice against the running instance and compare the resulting state · `pass:` the second call is a no-op or returns the first result — not a second row, charge, or email
- [ ] (optional) Pagination / result limits on list queries (no unbounded fetches)
      `verify:` grep list queries for `limit`/`take`/`LIMIT`; call a list endpoint with no parameters and count what comes back · `pass:` a bounded default even when the caller asks for nothing
- [ ] No N+1 queries; indexes present on hot query paths
      `verify:` read the hot-path handlers for a query inside a loop or a per-item lazy relation; check schema/migrations for an index on every column filtered or joined on · `pass:` one query per request shape, and every hot filter column indexed
- [ ] Connection pooling with a bounded pool size
      `verify:` cite the pool configuration line; on serverless, check that a client is not constructed per invocation · `pass:` an explicit maximum — an unbounded pool on a scaling runtime exhausts the database, not the app
- [ ] Transactions around multi-step writes
      `verify:` for each handler writing more than one row or table, cite the transaction boundary · `pass:` all-or-nothing; a partial write reachable by an error between two statements is a Gap
- [ ] (optional) Graceful shutdown: drain in-flight requests, close DB/connections
      `verify:` cite the `SIGTERM`/`beforeExit` handler; N/A on platforms that do not deliver one · `pass:` in-flight requests complete before exit
- [ ] Health/readiness endpoint matched to the deploy orchestrator
      `verify:` `curl -i <url>/health` (or the configured path), then compare it against the path the orchestrator config actually probes · `pass:` 200 at the path the orchestrator polls — a health endpoint nothing checks is not a health check, and the mismatch is invisible in either file alone
- [ ] CORS scoped correctly (no wildcard origin with credentials); request body size limits
      `verify:` `curl -H 'Origin: https://evil.example' -i <url>/<api route>` and read `Access-Control-Allow-Origin` / `-Credentials` · `pass:` the hostile origin is not reflected, and `*` never appears alongside `Allow-Credentials: true`
- [ ] Open-redirect protection: user-supplied redirect targets validated against an allowlist
      `verify:` find handlers reading a `next`/`returnTo`/`redirect` parameter, then request one with an external target and read the `Location` response header · `pass:` external targets rejected or rewritten to a relative path. Test `//evil.example` and a backslash variant as well — both bypass the naive "starts with /" check that most hand-rolled guards use
- [ ] SSRF protection on server-side fetches of user-supplied URLs (link previews, import-by-URL, webhooks): validate against an allowlist, block private/link-local/loopback ranges and cloud metadata endpoints (`169.254.169.254`, `metadata.google.internal`), disable redirect-following to those ranges — otherwise an attacker exfiltrates instance credentials/IMDS tokens
      `verify:` locate every server-side fetch whose URL comes from a request; read the validation applied before it, and whether redirects are followed *after* that validation (the common bypass) · `pass:` an allowlist enforced against the resolved address, with redirects disabled or re-validated. **Read the code; do not fire a live SSRF probe** — sending a request at a metadata endpoint on someone's infrastructure is an intrusive test, and it needs the owner's explicit consent, which this skill does not have
- [ ] No user input reflected unvalidated into response headers (header injection)
      `verify:` grep for header values built from request data; check for CR/LF stripping · `pass:` no request-derived value reaches a header unescaped
- [ ] Personalized/private responses are not cached by shared CDN/KV caches (`Cache-Control: private`/`no-store`); only truly public responses are cached
      `verify:` `curl -i` an authenticated route both with and without credentials; read `Cache-Control`, `Vary`, and any CDN cache-status header · `pass:` personalized responses carry `private` or `no-store`. A shared-cacheable authenticated response is a P1 regardless of what the config says it should be — this is the item where reading the config is most likely to disagree with the wire
- [ ] Object storage: buckets/prefixes not publicly listable; only intended objects are public
      `verify:` `curl` the bucket's base URL and a known object path; cite the bucket policy or IaC if present · `pass:` listing denied, and only objects intended to be public are readable

## Best-practice sources (fetch the live page; it wins over this file)
- OWASP Cheat Sheets (SSRF Prevention, Unvalidated Redirects, REST Security) — https://cheatsheetseries.owasp.org/
- OWASP Secure Headers — https://owasp.org/www-project-secure-headers/
- The official docs of the actual datastore / ORM / queue / cache in use — `WebSearch` "\<lib\>@\<version\> production best practices"
