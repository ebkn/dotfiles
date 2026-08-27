# Forms

**Applies when:** the app accepts user submissions (contact/lead form, signup, upload, multi-step wizard). Skip if there are no user submissions.

Ground every judgment in `path:line`. For a lead-gen site the form submission *is* the conversion — scrutinize it hardest.

Each item names a `verify:` and a `pass:`. This is the bucket where running beats reading by the widest margin: a form's real behavior is the product of client validation, server validation, the framework's action plumbing, and the browser, and no one of those files tells you what a user experiences.

**Submit to a test/staging target only.** A real submission fires whatever the form is wired to — an email, a CRM record, a charge. Confirm with the requester where the running instance points before sending anything, and if that cannot be established, mark the runtime items Cannot-verify rather than submitting blind.

## Checklist
- [ ] Validation on both client and server (schema-based); submit disabled while sending
      `verify:` submit an invalid payload **directly to the endpoint**, bypassing the client, and read the response · `pass:` rejected server-side with a 4xx. Client-only validation passes every in-browser test and stops nothing — bypassing the client is the only check that distinguishes the two
- [ ] Idempotency (idempotency key or server-side dedupe) so retries/double-clicks don't duplicate
      `verify:` submit the same payload twice and count the resulting records/emails · `pass:` one result. Check the disabled-while-sending state too, but treat it as UX: it reduces double-submits and cannot prevent them, since a retry or a second tab bypasses it entirely
- [ ] Bot / spam protection on public forms
      `verify:` cite the CAPTCHA/turnstile/honeypot wiring and confirm the **server** verifies the token — a widget rendered client-side whose token is never checked is decoration · `pass:` a server-side verification call whose failure rejects the submission
- [ ] URL/text inputs restrict dangerous protocols (`http(s):` only; block `javascript:`); user-supplied HTML escaped/sanitized
      `verify:` submit a `javascript:` URL and a value containing HTML tags, then look at where that value is rendered back · `pass:` the protocol is rejected and the markup renders as text
- [ ] File uploads validated (type, size, filename) and stored outside a publicly listable path
      `verify:` check that type is determined from content rather than the client-sent `Content-Type` or the extension; confirm a size limit exists; `curl` the storage prefix for listability · `pass:` content-based type check, an enforced size cap, a filename that cannot traverse (`../`), and a non-listable storage prefix
- [ ] Multi-step forms handle browser Back/Forward sanely: going back doesn't lose entered data or desync the step from the URL, and doesn't resubmit a completed step (post/redirect/get or state guard)
      `verify:` walk the flow in a browser and use the actual Back button — this one cannot be settled by reading, because it is browser history behavior, not application logic · `pass:` data preserved, URL and step agree, no resubmission prompt. Without a browser, mark it Cannot-verify and say so; do not infer it from the presence of a redirect

## Best-practice sources (fetch the live page; it wins over this file)
- OWASP Input Validation & File Upload Cheat Sheets — https://cheatsheetseries.owasp.org/
- The form/validation library's own docs for the versions pinned in `package.json`
