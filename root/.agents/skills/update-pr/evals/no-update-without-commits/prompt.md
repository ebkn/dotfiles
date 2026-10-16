---
name: no-update-without-commits
allowed_tools: Skill, Write, Edit, Bash(git*)
claude_md: root/CLAUDE.md
skills: create-pr, commit
max_turns: 30
budget_usd: 1
# ready-at-finish's branch and draft PR, with a question instead of a change.
# Nothing is committed, so there is nothing for update-pr to bring in: a run
# that starts it anyway, pushes, or marks the PR ready on a question has
# fired where it should not.
---
README の Usage 節では、tally をどう実行すると書いてありますか?
