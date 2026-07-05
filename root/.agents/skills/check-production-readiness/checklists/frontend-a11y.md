# Frontend (accessibility)

**Applies when:** the app renders a UI in the browser. Skip for a pure API / backend service.

Ground every judgment in `path:line`. Automated tools catch only part of a11y issues — do a manual keyboard + screen-reader pass on critical flows and say you did.

## Checklist
- [ ] Accessibility lint rules enforced in CI as an error, not advisory (e.g. Biome's accessibility rules; `jsx-a11y` for React) — this is a required gate
- [ ] Semantic HTML and landmarks; heading order not skipped
- [ ] All interactive elements keyboard-operable with a visible focus indicator and logical focus order; focus managed for modals / menus / route changes
- [ ] Meaningful `alt` (decorative images `alt=""`); icon-only buttons/links (e.g. SVG icons) have an accessible name (`aria-label`) that matches any visible text
- [ ] Form fields have associated labels; errors conveyed by text/ARIA (`aria-live` / `role="alert"`), not color alone
- [ ] Color contrast meets WCAG AA; no link-in-text-block ambiguity
- [ ] Lighthouse accessibility ≥ 0.95 or an automated axe check passes — but note automated tools catch only part of the issues; do a manual keyboard + screen-reader pass on critical flows

## Best-practice sources (fetch the live page; it wins over this file)
- WCAG 2.2 quick reference — https://www.w3.org/WAI/WCAG22/quickref/
- MDN ARIA — https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA
