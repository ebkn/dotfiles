# Observability

**Applies when:** always — every production app needs to be observable. Some items (uptime, alerting infra) are often Cannot-verify from the repo; surface them as questions rather than assuming pass/fail.

Ground every judgment in `path:line`.

## Checklist
- [ ] Structured logging with request/correlation IDs; **no secrets or PII in logs**; log persistence/retention (drains) for long-running debugging
- [ ] Error tracking (e.g. Sentry) wired on both frontend and backend, with source maps uploaded; server errors raise a notification/alert
- [ ] Analytics / product-metrics tool wired (page views, key events/conversions); consent-gated where required
- [ ] SPA analytics accuracy: page views fire on client-side soft navigations (route changes), not just the initial load, and events aren't double-fired (Strict Mode double-effect, remounts, duplicate script tags) — verify actual payloads, not just that the script loads
- [ ] Metrics/alerting and uptime monitoring (often cannot-verify — infra); distributed tracing for multi-service/serverless paths

## Best-practice sources (fetch the live page; it wins over this file)
- The error-tracker's own setup docs (e.g. Sentry) for the framework in use
- The analytics vendor's docs for SPA / soft-navigation page-view tracking
