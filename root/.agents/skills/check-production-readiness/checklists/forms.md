# Forms

**Applies when:** the app accepts user submissions (contact/lead form, signup, upload, multi-step wizard). Skip if there are no user submissions.

Ground every judgment in `path:line`. For a lead-gen site the form submission *is* the conversion — scrutinize it hardest.

## Checklist
- [ ] Validation on both client and server (schema-based); submit disabled while sending
- [ ] Idempotency (idempotency key or server-side dedupe) so retries/double-clicks don't duplicate
- [ ] Bot / spam protection on public forms
- [ ] URL/text inputs restrict dangerous protocols (`http(s):` only; block `javascript:`); user-supplied HTML escaped/sanitized
- [ ] File uploads validated (type, size, filename) and stored outside a publicly listable path
- [ ] Multi-step forms handle browser Back/Forward sanely: going back doesn't lose entered data or desync the step from the URL, and doesn't resubmit a completed step (post/redirect/get or state guard)

## Best-practice sources (fetch the live page; it wins over this file)
- OWASP Input Validation & File Upload Cheat Sheets — https://cheatsheetseries.owasp.org/
- The form/validation library's own docs for the versions pinned in `package.json`
