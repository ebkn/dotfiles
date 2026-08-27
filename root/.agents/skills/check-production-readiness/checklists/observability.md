# Observability

**Applies when:** always — every production app needs to be observable. Some items (uptime, alerting infra) are often Cannot-verify from the repo; surface them as questions rather than assuming pass/fail.

Ground every judgment in `path:line`. Each item names a `verify:` and a `pass:`.

The failure mode this whole bucket guards against is silence: an integration that is wired but never fires looks exactly like one that is working, from the repo and from the running app alike. So the verification here is consistently "make it emit, then confirm something received it" — presence of an SDK call is the weakest possible evidence and should never be reported as OK on its own.

## Checklist
- [ ] Structured logging with request/correlation IDs; **no secrets or PII in logs**; log persistence/retention (drains) for long-running debugging
      `verify:` make the running app emit a log on a request path and read the actual line — is it JSON, does it carry a request ID, and does the ID propagate to a downstream call? Separately, grep for logging of whole request/user objects · `pass:` structured output with a correlated ID, and no token, password, email, or full request body in any log line. `console.log(req.body)` on an auth route is the standard PII leak and reads as harmless at the call site
- [ ] Error tracking (e.g. Sentry) wired on both frontend and backend, with source maps uploaded; server errors raise a notification/alert
      `verify:` **both halves, separately.** Force a server error and a client error against the running instance, then confirm each arrives in the tracker (ask the requester to check the project — you will not have console access). Cite the CI source-map upload step · `pass:` both events land, the stack trace is symbolicated, and an alert rule exists. Frontend-only wiring is the common half-configuration, and it is invisible unless you test both sides
- [ ] Analytics / product-metrics tool wired (page views, key events/conversions); consent-gated where required
      `verify:` load the running app and inspect the outgoing network requests to the analytics endpoint — not the presence of the script tag · `pass:` a request with the expected payload actually leaves. Where consent is required, confirm nothing is sent *before* consent is granted, which is the half that fails compliance rather than measurement
- [ ] SPA analytics accuracy: page views fire on client-side soft navigations (route changes), not just the initial load, and events aren't double-fired (Strict Mode double-effect, remounts, duplicate script tags) — verify actual payloads, not just that the script loads
      `verify:` navigate between routes client-side and count the page-view requests; then trigger one key event and count its requests · `pass:` exactly one per navigation and one per event. Both failure directions are silent and they cancel out in aggregate dashboards — undercounting reads as low traffic, double-firing reads as growth
- [ ] Metrics/alerting and uptime monitoring (often cannot-verify — infra); distributed tracing for multi-service/serverless paths
      `verify:` cite the monitor/alert definitions if they live in the repo; otherwise ask who owns them and whether an alert has ever fired · `pass:` stated by the operator. "A monitoring tool is installed" is not the same as "an alert reaches a human at 3am", and only the second one matters — ask for the second

## Best-practice sources (fetch the live page; it wins over this file)
- The error-tracker's own setup docs (e.g. Sentry) for the framework in use
- The analytics vendor's docs for SPA / soft-navigation page-view tracking
