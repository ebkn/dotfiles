---
name: proactive-after-pr
allowed_tools: Skill, Write, Edit, Bash(git*), Bash(gh pr list*), Bash(gh pr view*), Bash(./install.sh*), Bash(ls*), Bash(cat*)
claude_md: root/CLAUDE.md
skills: commit, create-pr, update-pr
max_turns: 80
budget_usd: 3
# proactive-with-claude-md's request, on a branch with a GitHub origin (the
# fake one in bin/skill-eval-github.sh). root/CLAUDE.md then opens a PR and
# marks it ready before reporting back, and the summary has to come after
# that: written before, it describes a PR in a state it no longer has.
---
README.md の Install 節が古いままです。Makefile はもうなく、install.sh に置き換わっています。直してコミットしてください。
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
