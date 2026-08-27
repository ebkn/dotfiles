# Legal & compliance (deliberately thin — verify, don't skip)

**Applies when:** the app collects personal data, sets non-essential cookies/trackers, or has jurisdiction-specific obligations. **N/A for a purely internal tool with no personal data.**

Kept deliberately high-level: the jurisdiction- and business-specific obligations turn on facts the repo can't settle. Do **not** assert compliance from this skill. Flag what applies, mark it **Needs-confirmation**, recommend qualified (legal) review, and `WebSearch` the applicable legal source rather than relying on general knowledge. Ground code-visible items in `path:line`.

Each item names a `verify:` and a `pass:`. Read the `pass:` conditions narrowly: they describe **observable behavior**, never compliance. "The consent gate works as built" and "this app complies with GDPR" are different claims, and only the first is in scope here — conflating them is the specific failure this bucket is written to prevent.

## Checklist
- [ ] Cookie/consent UI where non-essential cookies or trackers are used; analytics/tag scripts load **only after** consent (and CSP updated for any added domains)
      `verify:` load the running app in a fresh session, **decline or ignore consent**, and watch the network requests and `Set-Cookie` responses · `pass:` no analytics/tag request and no non-essential cookie before consent is granted; both appear after. This is the one item in the bucket that is fully measurable, and it is also the one most often wrong — a banner that renders while the tag already fired is a common pattern and looks correct on screen
- [ ] Privacy policy published and linked from forms and the footer; states what personal data is collected, why, and where it goes
      `verify:` `curl` the policy URL, and check the link is present on the footer and on each form; then compare the data categories it names against the fields the app actually collects and the third parties it actually calls · `pass:` reachable, linked, and consistent with the code. The mismatch — a policy that omits a processor the app demonstrably sends data to — is code-visible and worth reporting even though the policy's adequacy is not
- [ ] Data handling deliberate: retention period, deletion path, and third-party processors disclosed; retention/deletion implemented where claimed
      `verify:` list the third parties the code sends personal data to; check whether a deletion path exists in the code for data the policy promises to delete · `pass:` the processors match the disclosure and a promised deletion path exists. Where the policy claims something the code does not do, that is a finding this skill *can* make — it is a factual inconsistency, not a legal opinion
- [ ] Applicable regime considered (GDPR / local personal-data law) and reviewed by someone qualified
      `verify:` ask; `WebSearch` the regime's official source only to frame the question · `pass:` **Needs-confirmation, always.** Do not mark this OK under any circumstances — this skill has no basis for that judgment, and a readiness report that appears to bless it is worse than one that says nothing
- [ ] Legally required notices present where applicable to the jurisdiction/feature (e.g. JP telecommunications-business notification for private messaging features)
      `verify:` identify features that commonly trigger a notification requirement (private messaging, payments, marketplace, health/financial data) and name them as questions for the owner · `pass:` Needs-confirmation with the specific features named — naming the trigger is the useful output, not a verdict
- [ ] Product/service name checked for unintended meanings in target locales
      `verify:` `WebSearch` the name in each target locale · `pass:` nothing obviously problematic surfaced; flag anything ambiguous for a native speaker rather than adjudicating it

## Best-practice sources (fetch the live page; it wins over this file)
- The applicable legal regime's official source (e.g. GDPR text/guidance, the local personal-data-protection authority)
- Route anything past the basics to a qualified human (legal) — do not assert compliance from this skill.
