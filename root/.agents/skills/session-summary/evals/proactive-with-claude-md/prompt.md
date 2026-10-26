---
name: proactive-with-claude-md
allowed_tools: Skill, Write, Edit, Bash(git*), Bash(./install.sh*), Bash(ls*), Bash(cat*)
claude_md: root/CLAUDE.md
skills: commit
max_turns: 60
budget_usd: 2
# Nothing in the request mentions a summary. Whether the run ends with
# session-summary rests on root/CLAUDE.md's "Reporting Back" and the skill's
# description. The fixture has no origin, so CLAUDE.md opens no PR.
---
README.md の Install 節が古いままです。Makefile はもうなく、install.sh に置き換わっています。直してコミットしてください。
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
