---
name: proactive-at-breakpoint-with-claude-md
allowed_tools: Skill, Write, Edit, Bash(./run-tests.sh*), Bash(./total.sh*), Bash(git*), Bash(tail*), Bash(head*), Bash(echo*)
claude_md: root/CLAUDE.md
max_turns: 100
budget_usd: 5
# The pair of proactive-at-breakpoint: the same prompt, fixture and grader,
# plus the CLAUDE.md that states the auto-start rule a second time. The other
# case measures SKILL.md's description alone; this one the path a real session
# takes, where review-test may start first. The ceilings leave room for both
# reviews and their loops. evals/assert.test.sh pins the prompt as shared.
---
total.sh に `--kg` オプションを追加して、合計をキログラムで出力できるようにしてください。テストも書いて、終わったらコミットしてください。
テストは `./run-tests.sh` で実行し、シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
