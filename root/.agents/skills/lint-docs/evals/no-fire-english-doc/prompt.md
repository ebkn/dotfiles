---
name: no-fire-english-doc
allowed_tools: Skill
# The counterpart of the fires-* cases: a request to proofread a document,
# in Japanese, about an English one. The skill's rules do not detect language
# (bin/textlint-docs.md), so starting here produces only noise.
---
README.md の英文に文法の誤りや読みにくい箇所が無いか見てください。
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
