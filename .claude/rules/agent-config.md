---
paths:
  - "root/**"
---

# Agent config under root/

**Read [root/README.md](../../root/README.md) before editing anything here.** It covers `settings.json`, the three `root/CLAUDE.md` destinations, the curl, `rm` and git permission rules (no git allow rule may put a `*` before the subcommand), the Codex prefix rules and the skill-linking policy.

- Skills this repo owns live once under `root/.agents/skills/<name>/SKILL.md` and are linked **individually** into each consumer dir; a new one needs a `relink` to appear.
- Codex ignores `allowed-tools`, so **a read-only skill must state that boundary in its body**.
- Scripts that back one skill (e.g. retrospective's `session-extract`) live beside its `SKILL.md`, not in `bin/`, and are linked to `~/.local/bin`.
