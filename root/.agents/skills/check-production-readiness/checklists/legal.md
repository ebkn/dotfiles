# Legal & compliance (deliberately thin — verify, don't skip)

**Applies when:** the app collects personal data, sets non-essential cookies/trackers, or has jurisdiction-specific obligations. **N/A for a purely internal tool with no personal data.**

Kept deliberately high-level: the jurisdiction- and business-specific obligations turn on facts the repo can't settle. Do **not** assert compliance from this skill. Flag what applies, mark it **Needs-confirmation**, recommend qualified (legal) review, and `WebSearch` the applicable legal source rather than relying on general knowledge. Ground code-visible items in `path:line`.

## Checklist
- [ ] Cookie/consent UI where non-essential cookies or trackers are used; analytics/tag scripts load **only after** consent (and CSP updated for any added domains)
- [ ] Privacy policy published and linked from forms and the footer; states what personal data is collected, why, and where it goes
- [ ] Data handling deliberate: retention period, deletion path, and third-party processors disclosed; applicable regime considered (GDPR / local personal-data law)
- [ ] Legally required notices present where applicable to the jurisdiction/feature (e.g. JP telecommunications-business notification for private messaging features)
- [ ] Product/service name checked for unintended meanings in target locales

## Best-practice sources (fetch the live page; it wins over this file)
- The applicable legal regime's official source (e.g. GDPR text/guidance, the local personal-data-protection authority)
- Route anything past the basics to a qualified human (legal) — do not assert compliance from this skill.
