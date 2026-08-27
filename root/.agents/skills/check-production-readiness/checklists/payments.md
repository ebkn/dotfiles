# Payments & billing (deliberately thin — verify, don't skip)

**Applies when:** the app charges money, holds card data, or integrates a payment provider (Stripe, PayPal, in-app purchase, subscriptions). **N/A otherwise — skip and say so once.**

This bucket is intentionally not a fine-grained checklist because the correct behavior is provider-specific. Thin coverage is **not** permission to skim: if a money path exists and is load-bearing, treat its correctness as launch-critical, and `WebSearch` the payment provider's own current security/integration docs rather than relying on general knowledge. Ground every judgment in `path:line`.

**Verification here is by reading and by the provider's own test mode — never against live payments.** Every item below can be settled from the code plus the provider's test-mode tooling (test keys, CLI webhook replay, test card numbers). Do not initiate a real charge, refund, or subscription change, and do not touch a live-mode key. If only live credentials exist, read the code and report; an unexercised money path stated as a gap is a correct outcome, a stray live charge is not.

## Checklist
- [ ] Server-side amount/price verification — the charged amount is computed and confirmed on the server, never trusted from a client-sent value
      `verify:` trace the amount from the request body to the provider call; if a request field reaches it without being recomputed from server-held prices, that is the finding. Confirm in test mode by submitting a tampered amount · `pass:` the server's own price wins, and the tampered request is rejected or charged the correct amount
- [ ] Webhook signature verification (provider secret) and idempotency — a replayed or duplicated webhook doesn't double-fulfill / double-charge
      `verify:` two separate checks. Signature: post an unsigned/wrongly-signed body to the webhook endpoint — it must be rejected before any handler logic runs. Idempotency: replay the *same* valid test event twice (the provider CLI does this) and compare resulting state · `pass:` unsigned rejected with 4xx, and the replayed event fulfills exactly once. Reading the handler settles the first; only the replay settles the second
- [ ] No card data (PAN, CVV) touching your servers unless you are explicitly PCI-scoped — use the provider's hosted fields / tokenization
      `verify:` grep for card-shaped field names (`cardNumber`, `cvc`, `cvv`, `pan`) in request handlers, logs, and analytics payloads · `pass:` card data never reaches your origin — and equally never reaches a log line or an analytics event, which is the leak that survives an otherwise correct tokenized integration
- [ ] Failed / duplicate / refunded / disputed transactions handled correctly, with fulfillment tied to a confirmed payment state (not to the client returning to a success URL)
      `verify:` find where fulfillment is triggered. If it hangs off the browser landing on a success/return URL, it is forgeable — request that URL directly without paying · `pass:` fulfillment is driven by a verified webhook or a server-side status fetch, and hitting the success URL alone fulfills nothing
- [ ] Prices / currency / tax computed authoritatively server-side; no client-editable line items
      `verify:` check whether line items, quantities, currency, or discount codes are accepted from the request · `pass:` all derived server-side from an identifier; a client-supplied discount code is fine, a client-supplied discount *amount* is not
- [ ] Recommend a focused review of the money path before launch; if it's present but under-examined here, **say so in the report** as a stated gap — not a silent pass.
      `verify:` state plainly which of the items above were measured in test mode and which were only read · `pass:` the report distinguishes the two. An unexercised money path reported as "OK" is the single most expensive false pass this skill can produce

## Best-practice sources (fetch the live page; it wins over this file)
- The payment provider's own security & webhook docs (e.g. Stripe security / webhook signature verification) — `WebSearch` "\<provider\> webhook signature verification" and "\<provider\> integration security"
- PCI DSS overview (only if you handle card data directly) — https://www.pcisecuritystandards.org/
- OWASP Cheat Sheets — https://cheatsheetseries.owasp.org/
