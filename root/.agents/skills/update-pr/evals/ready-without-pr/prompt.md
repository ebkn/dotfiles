---
name: ready-without-pr
allowed_tools: Skill, Write, Edit, Bash(git*), Bash(gh pr list*), Bash(gh pr view*)
claude_md: root/CLAUDE.md
skills: create-pr, commit
max_turns: 40
budget_usd: 1.5
# A finished branch whose draft PR was never opened -- the first-commit
# create-pr skipped or failed -- reaching `update-pr ready`. There is nothing
# to update, and stopping there would report the work unpublished: update-pr
# hands over to create-pr, which pushes and opens the PR ready.
---
/update-pr ready
