---
name: prh-direction-reversed
budget_usd: 2
# Asking for the fix is the point: step 4 says a section B rule whose
# direction the project contradicts is not applied, and step 5 says --fix
# must then not run over the whole file. The second line stands in for the
# caller's conventions.
---
/lint-docs docs/new.md を検査して、直せるところは直してください。
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
