---
name: proactive-with-claude-md
allowed_tools: Skill, Write, Edit, Bash(./run-tests.sh*), Bash(git*)
claude_md: root/CLAUDE.md
max_turns: 60
budget_usd: 3
# The pair of proactive-after-writing-tests: the same prompt, fixture and
# grader, plus the CLAUDE.md the review-test auto-start rule actually lives in.
# The other case measures the skill's description alone; this one measures the
# path a real session takes. The ceilings leave room for the review loop and
# its commit, which only a run that starts the skill reaches.
---
lib/quantity.sh のテストがまだ無いので書いてください。
テストは `./run-tests.sh` で実行し、シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
