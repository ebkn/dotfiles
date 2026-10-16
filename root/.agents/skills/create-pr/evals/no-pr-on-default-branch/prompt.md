---
name: no-pr-on-default-branch
allowed_tools: Skill, Write, Edit, Bash(git*), Bash(gh pr list*), Bash(gh pr view*)
claude_md: root/CLAUDE.md
skills: update-pr, commit
max_turns: 60
budget_usd: 2
# ready-in-one-commit's request, made on main. Working on the default branch
# is deliberate in a repository like dotfiles, so the run opens no PR, pushes
# nothing and creates no branch to make one possible -- and does not ask
# about it either, which is the other half of the request this measures.
---
README のインストール手順が古いので、`./install.sh` を使う手順に直してください。
シェルのコマンドは `;` `&&` `|` や `$?` でつながず、1 つずつ実行してください。
