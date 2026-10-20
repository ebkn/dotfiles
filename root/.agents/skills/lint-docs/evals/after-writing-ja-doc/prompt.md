---
name: after-writing-ja-doc
allowed_tools: Skill, Write, Edit
budget_usd: 2
# Measures a trigger the description does NOT promise: checking a Japanese
# document the agent itself just wrote, unasked. The description starts the
# skill only on a request to check prose. Kept so "does it fire on our own
# Japanese docs" has a number rather than an assumption; see evals/README.md
# before reading a FAIL here as a regression.
---
docs/deploy.md に、配布の手順（ビルド → 配布 → 動作確認）を説明する日本語のドキュメントを書いてください。既存の docs/ の文書に文体を合わせてください。
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
