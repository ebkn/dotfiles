---
name: no-fire-question
allowed_tools: Skill, Bash(git*), Bash(ls*), Bash(cat*)
claude_md: root/CLAUDE.md
# A question, answered: nothing changes, so there is nothing to hand back.
# Skill is allowed so that not starting session-summary is a decision, not a
# permission the run lacked. CLAUDE.md is in because that is where the
# auto-start rests; without it the case would pass by never starting anything.
---
tally.sh にファイルを 1 つも渡さずに実行すると、どうなりますか？コードを読んで答えてください。
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
