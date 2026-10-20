---
name: excludes-english-docs
budget_usd: 2
# No path: step 1 picks the candidates from git status and must narrow them
# to Japanese by 。 density. The second line stands in for the caller's
# conventions.
---
/lint-docs
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
