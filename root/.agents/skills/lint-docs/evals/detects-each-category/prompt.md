---
name: detects-each-category
budget_usd: 2
# Started by name, so the case measures what the skill reports, not whether it
# starts (the fires-* cases measure that). The second line stands in for the
# caller's conventions, as in review-test's cases.
---
/lint-docs docs/guide.md
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
