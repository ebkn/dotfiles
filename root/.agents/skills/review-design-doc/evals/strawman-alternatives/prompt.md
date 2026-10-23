---
name: strawman-alternatives
allowed_tools: Skill
skills: lint-docs
budget_usd: 3
# Started by name, so the case measures what the review finds, not whether it
# starts (fires-on-phrase measures that). The second line stands in for the
# caller's conventions, as in the other skills' cases.
---
/review-design-doc docs/design/webhook-retry.md
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
