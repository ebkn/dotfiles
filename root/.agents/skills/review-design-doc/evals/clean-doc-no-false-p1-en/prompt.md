---
name: clean-doc-no-false-p1-en
allowed_tools: Skill
skills: lint-docs
budget_usd: 2
# clean-doc-no-false-p1 in English, request and doc alike: the same grader
# with `en`, so the report must be English and lint-docs left out.
---
Review docs/design/webhook-retry.md with the review-design-doc skill.
Run shell commands one at a time; do not chain them with `;`, `&&`, `|` or `$?`.
