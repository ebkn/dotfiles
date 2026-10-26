---
name: proactive-at-finish
allowed_tools: Skill, Write, Edit, Bash(git*), Bash(./install.sh*), Bash(ls*), Bash(cat*)
max_turns: 60
budget_usd: 2
# proactive-with-claude-md without the CLAUDE.md: same prompt, fixture and
# grader, so this measures what the description alone achieves.
---
README.md の Install 節が古いままです。Makefile はもうなく、install.sh に置き換わっています。直してコミットしてください。
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
