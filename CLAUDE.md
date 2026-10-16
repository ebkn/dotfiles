# Project: dotfiles

Personal dotfiles for macOS, Linux and Windows — shell, editor, terminal and
agent config, symlinked into `~/`. `AGENTS.md` is a symlink to this file, for Codex.

<!--
Maintainers: this file is loaded into every session, so keep a line only if
removing it would make the agent err. Anything that matters for one area goes
in a path-scoped rule under .claude/rules/ or in the doc beside the thing.
-->

## Layout

Only what `ls` cannot tell you.

- `zsh/` — modules sourced from `.zshrc`, one per concern; `*.test.zsh` beside them.
- `bin/` — everything that ends up on `$PATH`. `bin/init/` is platform setup;
  `bin/init/links.sh` holds `link_dotfiles()`, shared with `bin/relink`.
  One-OS helpers go in `bin/<platform>/`.
- `root/` — agent and tool config linked into `~/` (`CLAUDE.md`, `.claude/`,
  `.codex/`, `.agents/skills/`).
- `launchd/` — LaunchAgents. Linking is not loading: see `bin/launchd-load`.
- `textlint/` — rules `bin/textlint-docs` carries to *other* repos; this repo's
  own is `./.textlintignore`.
- Top-level dotfiles (`.zshrc`, `.tmux.conf`, `wezterm.lua`, …) are linked as-is.

**Every non-trivial script has a sibling `.md`, and each area has one
(`zsh/README.md`, `root/README.md`, `vim/coc-trust.md`). Read it before editing
the thing**: most failure modes here are silent, and the doc holds the reason.

## Path-scoped rules

Claude Code loads these from `.claude/rules/` when a matching file is touched.
Codex does not — read the matching one before editing.

| Rule               | Covers                                                  |
| ------------------ | ------------------------------------------------------- |
| `shell-scripts.md` | any shell script: shebang, `set` flags, format, shellcheck |
| `testing.md`       | suites, CI workflows, the test container, version pins  |
| `zsh.md`           | `zsh/`, `.zshrc`, `.zshenv`                             |
| `vim.md`           | `vim/`, including coc workspace trust                   |
| `agent-config.md`  | `root/`                                                 |

## Conventions

- **New `$HOME` link**: add a `link_with_backup` line to `link_dotfiles()` in
  `bin/init/links.sh`, so `bin/init/macos.sh` and `relink` both pick it up
  (`ubuntu.sh`/`wsl.sh`: inline, not yet migrated). Order-sensitive links
  (`.zshrc`/`.zshenv`, `.npmrc`) stay inline in the platform script. `relink`
  reports drift and asks before fixing; `update-all` runs it at the end.
- **Executables live in `bin/`, never at the repo root.** Moving a `bin/`
  script leaves `~/.local/bin/<name>` dangling until `relink` runs, and callers
  discard stderr, so the only symptom is a feature quietly not happening.
- **Everything clones over SSH.** `.gitconfig` rewrites every
  `https://github.com/…` URL to SSH, zinit's included, so a new machine fetches
  nothing from GitHub until it has an SSH key, and changing a URL here to HTTPS
  does nothing. Check with `GIT_SSH_COMMAND=false git ls-remote https://github.com/…`;
  only `GIT_CONFIG_GLOBAL=/dev/null` neutralises the rewrite.
- **This repository is public.** `root/.claude/settings.json` collects
  machine-local state from `/config` and private-repo profiles in
  `autoMode.environment`; read [root/README.md](root/README.md) before staging it.

## Testing

- `bin/test` runs every suite in parallel, and CI runs exactly that. Discovery
  is `git ls-files`, so `git add` a new suite first. See [bin/test.md](bin/test.md).
- `bin/lint-shell` is the static gate; run it before pushing, after `git add`.
- **IMPORTANT: never run tmux suites or tmux experiments on the host.** Use
  `bin/test-in-docker`. `TMUX_TMPDIR` does not isolate inside a pane because
  tmux prefers the socket in `$TMUX`; a probe that forgot `unset TMUX` killed
  every local session. Ad hoc: the container, or an explicit `-L`/`-S` socket
  with `TMUX` unset.
- Assert on the observable contract, not the exit status: nearly every failure
  mode here is silent.

## Feature docs

| Feature                                          | Doc |
| ------------------------------------------------ | --- |
| Agent state indicator (tmux pane options, sync)  | [root/.claude/hooks/agent-state.md](root/.claude/hooks/agent-state.md) |
| Agent picker (`prefix + a`), answering (`ctrl-o`, `prefix + A`) | [bin/tmux-agents.md](bin/tmux-agents.md), [bin/tmux-agent-view.md](bin/tmux-agent-view.md) |
| tmux popups (`prefix + p`/`t`/`o`)               | [bin/tmux-popup.md](bin/tmux-popup.md) |
| `.tmux.conf` and the `prefix + ?` cheatsheet     | [bin/tmux-conf.md](bin/tmux-conf.md), [bin/tmux-cheatsheet.md](bin/tmux-cheatsheet.md) |
| One WezTerm tab = one tmux session (`prefix + w`) | [bin/tmux-session-swap.md](bin/tmux-session-swap.md) |
| Remote sessions, autossh, tab restore            | [bin/tmux-track-session.md](bin/tmux-track-session.md), [bin/tmux-restore-ssh-tabs.md](bin/tmux-restore-ssh-tabs.md), [bin/autossh-ssh.md](bin/autossh-ssh.md) |
| Document reading (`read-doc`)                    | [bin/read-doc.md](bin/read-doc.md) |
| PR automation (detectors → queue → dispatch)     | [bin/pr-review-watch.md](bin/pr-review-watch.md), [bin/pr-state-watch.md](bin/pr-state-watch.md), [bin/pr-review-dispatch.md](bin/pr-review-dispatch.md) |
| Japanese prose linting (`textlint-docs`)         | [bin/textlint-docs.md](bin/textlint-docs.md) |
| Skill evals (`skill-eval`)                       | [bin/skill-eval.md](bin/skill-eval.md) |
| Session retrospective (`/retrospective`)         | [root/.agents/skills/retrospective/NOTES.md](root/.agents/skills/retrospective/NOTES.md) |
