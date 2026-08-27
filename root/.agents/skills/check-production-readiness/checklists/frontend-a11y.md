# Frontend (accessibility)

**Applies when:** the app renders a UI in the browser. Skip for a pure API / backend service.

Ground every judgment in `path:line`. Each item names a `verify:` and a `pass:`.

Automated tools catch only part of a11y issues — roughly the part that is structural. Everything about *order*, *focus*, and *whether the announced text makes sense* needs a person driving the keyboard. Do that pass on the critical flows and say you did; if you could not, say that instead of reporting the automated score as the answer.

## Checklist
- [ ] Accessibility lint rules enforced in CI as an error, not advisory (e.g. Biome's accessibility rules; `jsx-a11y` for React) — this is a required gate
      `verify:` cite the rule severity in the linter config **and** confirm the lint step actually runs in CI and fails the job · `pass:` severity is error and the step is a required check. `warn` in a job that reports success is not a gate, and the two halves live in different files
- [ ] Semantic HTML and landmarks; heading order not skipped
      `verify:` extract the heading outline from the rendered page and read it as a list · `pass:` one `h1`, no skipped level, and content sits inside `main`/`nav`/`header`/`footer` landmarks
- [ ] All interactive elements keyboard-operable with a visible focus indicator and logical focus order; focus managed for modals / menus / route changes
      `verify:` Tab through each critical flow with the mouse untouched: open a modal, close it, change route · `pass:` everything reachable, focus always visible, focus moves into a modal on open and returns to the trigger on close, and Tab never escapes an open modal. A `div` with an `onClick` and no `tabindex`/role is the standard finding and is invisible to a mouse user
- [ ] Meaningful `alt` (decorative images `alt=""`); icon-only buttons/links (e.g. SVG icons) have an accessible name (`aria-label`) that matches any visible text
      `verify:` list images and icon-only controls, and read the computed accessible name of each · `pass:` informative images described, decorative ones `alt=""`, every control named. An `aria-label` that contradicts the visible text is a failure of its own — voice-control users say what they see
- [ ] Form fields have associated labels; errors conveyed by text/ARIA (`aria-live` / `role="alert"`), not color alone
      `verify:` submit a form with invalid input and confirm the error is both text and announced; check each field's label association · `pass:` every field labelled, errors announced and readable without color
- [ ] Color contrast meets WCAG AA; no link-in-text-block ambiguity
      `verify:` read Lighthouse/axe contrast findings, and check the states automation misses — placeholder, disabled, hover, focus ring against its background · `pass:` AA met in every state, and in-text links distinguishable by more than color alone
- [ ] Lighthouse accessibility ≥ 0.95 or an automated axe check passes — but note automated tools catch only part of the issues; do a manual keyboard + screen-reader pass on critical flows
      `verify:` run it, report the score, and report the manual pass separately · `pass:` the score meets the bar **and** the manual pass is stated as done or explicitly stated as not done. A perfect automated score is compatible with a page no keyboard user can operate — never let it stand in for the manual result

## Best-practice sources (fetch the live page; it wins over this file)
- WCAG 2.2 quick reference — https://www.w3.org/WAI/WCAG22/quickref/
- MDN ARIA — https://developer.mozilla.org/en-US/docs/Web/Accessibility/ARIA
