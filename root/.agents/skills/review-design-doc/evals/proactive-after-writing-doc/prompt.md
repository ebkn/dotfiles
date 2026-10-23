---
name: proactive-after-writing-doc
allowed_tools: Skill, Write, Edit
budget_usd: 3
# Having written a design doc, the agent reviews it before reporting, without
# being asked. Write and Edit are the scenario's own tools. The budget is the
# writing plus a review. no-fire-readme-edit is the pair: a document written
# that is not a design doc, where it must not start.
---
docs/notes/webhook-retry.md の議論メモをもとに、docs/design/webhook-retry.md に設計ドキュメントを書いてください。書き終えたら報告してください。
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
