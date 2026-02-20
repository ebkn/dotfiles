---
name: commit
description: Stage and commit git changes with Conventional Commits. Use when the user asks to commit current work, split changes into logical commits, or prepare clean commit history.
---

# Commit Workflow

Commit changes quickly and keep output minimal. Do not provide a long post-commit summary unless the user asks.

1. Run `git status --short` and `git diff --stat` to understand scope.
2. Run `git diff` and `git log --oneline -5` to review details and recent message style.
3. Group unrelated edits into separate commits when needed.
4. For each commit:
   - `git add <files>`
   - `git diff --cached --stat`
   - `git commit -m "<message>"`
5. Write commit messages in Conventional Commits format:
   - `type(scope): description`
   - English
   - Imperative mood
   - 72 chars or less on the subject line
   - Add a body that briefly explains **why** the change was made and any relevant background. Keep it concise — just enough for a future reader to understand the motivation without re-reading the diff.
   - Omit the body only when the subject line alone is self-explanatory (e.g., fixing a typo).
6. Ask the user before committing only if:
   - Changes span many unrelated concerns and grouping is unclear
   - Potential secrets are present
   - Generated files may be accidental
