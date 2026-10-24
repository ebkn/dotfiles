---
name: no-fire-code-design-request
allowed_tools: Skill
skills: review-design
max_turns: 60
budget_usd: 4
# "設計をレビューして" about a commit that adds code: review-design's request,
# worded the way its description quotes it, with a design doc lying in
# docs/design/ to pull the other way. review-design is carried so the run has
# the right skill to reach for; it runs forked on opus, hence the budget.
---
直前のコミットの設計をレビューしてください。
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
