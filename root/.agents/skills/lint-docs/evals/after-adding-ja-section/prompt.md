---
name: after-adding-ja-section
allowed_tools: Skill, Edit
budget_usd: 2
# The second half of "## いつ起動するか": a section added to an existing
# Japanese document, by Edit. With after-writing-ja-doc (a new document, by
# Write) and no-fire-small-ja-edit (a few characters, by Edit), the pairs
# differ in the size of the change, not in the tool that made it. Write is
# not allowed, so the section has to go in by Edit.
---
docs/ops.md に「障害時の切り替え」という節を足してください。片方のサーバーが落ちたときの切り替え手順と、切り替え後に確かめることを、既存の文体で数段落にまとめてください。
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
