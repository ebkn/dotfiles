---
name: proactive-multi-step
allowed_tools: Skill, Write, Edit, Bash(git*), Bash(./install.sh*), Bash(./tally.sh*), Bash(ls*), Bash(cat*)
claude_md: root/CLAUDE.md
skills: commit
max_turns: 80
budget_usd: 3
# One request in two commits, asked for as such. The first commit is a
# natural point to report and is not the end: root/CLAUDE.md says to skip
# session-summary mid-request, so it starts once, after the second commit.
# No origin, as in proactive-with-claude-md, so no PR is opened.
---
README.md を 2 か所直してください。
1. Install 節が古いままです。Makefile はもうなく、install.sh に置き換わっています。直したら、ここで一度コミットしてください。
2. 次に Usage 節に、`./tally.sh README.md` を実行した例とその出力を足して、別のコミットにしてください。
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
