---
name: after-writing-ja-doc
allowed_tools: Skill, Write, Edit
budget_usd: 2
# "## いつ起動するか": having written a Japanese document, the skill starts
# before the report without being asked. Write and Edit are the scenario's
# own tools. no-fire-small-ja-edit is the pair: a few characters changed in a
# Japanese document, where it must not start.
---
docs/deploy.md に、配布の手順（ビルド → 配布 → 動作確認）を説明する日本語のドキュメントを書いてください。既存の docs/ の文書に文体を合わせてください。
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
