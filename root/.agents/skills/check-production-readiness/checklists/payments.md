# Payments & billing (deliberately thin — verify, don't skip)

**Applies when:** the app charges money, holds card data, or integrates a payment provider (Stripe, PayPal, in-app purchase, subscriptions). **N/A otherwise — skip and say so once.**

This bucket is intentionally not a fine-grained checklist because the correct behavior is provider-specific. Thin coverage is **not** permission to skim: if a money path exists and is load-bearing, treat its correctness as launch-critical, and `WebSearch` the payment provider's own current security/integration docs rather than relying on general knowledge. Ground every judgment in `path:line`.

## Checklist
- [ ] Server-side amount/price verification — the charged amount is computed and confirmed on the server, never trusted from a client-sent value
- [ ] Webhook signature verification (provider secret) and idempotency — a replayed or duplicated webhook doesn't double-fulfill / double-charge
- [ ] No card data (PAN, CVV) touching your servers unless you are explicitly PCI-scoped — use the provider's hosted fields / tokenization
- [ ] Failed / duplicate / refunded / disputed transactions handled correctly, with fulfillment tied to a confirmed payment state (not to the client returning to a success URL)
- [ ] Prices / currency / tax computed authoritatively server-side; no client-editable line items
- [ ] Recommend a focused review of the money path before launch; if it's present but under-examined here, **say so in the report** as a stated gap — not a silent pass.

## Best-practice sources (fetch the live page; it wins over this file)
- The payment provider's own security & webhook docs (e.g. Stripe security / webhook signature verification) — `WebSearch` "\<provider\> webhook signature verification" and "\<provider\> integration security"
- PCI DSS overview (only if you handle card data directly) — https://www.pcisecuritystandards.org/
- OWASP Cheat Sheets — https://cheatsheetseries.owasp.org/
