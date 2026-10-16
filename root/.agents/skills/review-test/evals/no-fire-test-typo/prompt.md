---
name: no-fire-test-typo
allowed_tools: Skill, Write, Edit, Bash(./run-tests.sh*), Bash(git*)
claude_md: root/CLAUDE.md
# With the CLAUDE.md, because that is where the auto-start rests (see
# bin/skill-eval.md): a case without it would pass by never starting anything.
# The second line stands in for the conventions, as in the other cases.
---
lib/quantity.test.sh のテスト名に typo があります（"pases a plain number" → "parses a plain number"）。直してコミットしてください。
テストは `./run-tests.sh` で実行し、シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
