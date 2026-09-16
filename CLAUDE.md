# Project: dotfiles

Personal dotfiles repository managing shell, editor, terminal, and development tool configurations for macOS, Linux, and Windows.

## Structure

```
.
├── zsh/                # Zsh config modules sourced from .zshrc
│   ├── alias.zsh       #   Shell aliases + rm/fd/his wrappers, imgcat
│   ├── completion.zsh  #   Completion settings
│   ├── directory.zsh   #   Directory navigation options
│   ├── git.zsh         #   Git aliases, gs, gw/gdmerged worktree flow, ghq picker
│   ├── gpg.zsh         #   GPG_TTY export for commit signing
│   ├── history.zsh     #   History settings
│   ├── lang.zsh        #   Language manager lazy-loading
│   ├── path.zsh        #   PATH configuration
│   ├── plugin.zsh      #   Zinit plugin definitions
│   ├── ssh-agent.zsh   #   SSH agent selection (WSL only)
│   ├── ssh.zsh         #   ssh/myssh wrappers publishing @ssh_host to tmux
│   ├── update.zsh      #   update-all
│   ├── *.test.zsh      #   Unit tests for the modules above
│   └── .p10k.zsh       #   Powerlevel10k theme config
├── vim/                # Neovim/Vim configuration
│   ├── nvim/lua/plugins/
│   │   ├── instantly/  #   Plugins loaded at startup
│   │   └── lazy/       #   Plugins loaded on demand (filetype, etc.)
│   ├── coc/            #   CoC (Conquer of Completion) extensions config
│   ├── *.vim           #   Vim core config (base, color, keymap, view)
│   └── lazy.lua        #   lazy.nvim bootstrap
├── autohotkey/         # AutoHotkey v2 scripts for Windows
│   └── keyremap.ahk   #   Key remapping (CapsLock→Ctrl, Alt→IME switch)
├── bin/
│   ├── init/           #   Platform setup scripts (macos.sh, ubuntu.sh, wsl.sh, windows.ps1)
│   │   ├── common.sh   #     Shared setup helpers (link_with_backup, etc.)
│   │   └── links.sh    #     link_dotfiles(): re-syncable $HOME symlinks (shared by macos.sh + relink)
│   ├── wsl/               #   WSL-only helper scripts (e.g. notify-send OSC 9 shim)
│   ├── relink             #   Re-sync symlinks from link_dotfiles() (drift check + prompt; called by update-all)
│   ├── launchd-load       #   Load linked LaunchAgents that are not running (--status to look; NOT called by relink)
│   ├── tmux-agents        #   Pick a Claude Code agent by state (prefix + a) and jump to its WezTerm tab
│   ├── tmux-agent-view    #   Answer a blocked agent from the picker (ctrl-o): mirror its window in a popup
│   ├── tmux-cheatsheet    #   Annotated key bindings, grouped into columns (prefix + ?)
│   ├── tmux-tig           #   Run tig, holding the popup open on failure (prefix + t)
│   ├── tmux-popup         #   Open the per-tab popup session (prefix + p/t/o all go through it)
│   ├── fzf-nvim           #   Pick a file with fzf and open it in nvim (prefix + o)
│   ├── tmux-pane-titles   #   Name the window after its panes' dirs/branches (called from zsh hooks)
│   ├── tmux-restore-tabs  #   Re-open a WezTerm tab per orphaned tmux session
│   ├── tmux-track-session #   Remember the remote session an ssh pane was in, for autossh reconnect
│   ├── tmux-session-swap  #   Swap two clients on prefix + w, so one tab keeps meaning one session
│   ├── autossh-ssh        #   AUTOSSH_PATH shim: the reconnect notice myssh shows between attempts
│   ├── fzf-files          #   List git-changed files first for fzf (symlinked to ~/.local/bin)
│   ├── git-generated      #   Locally hide linguist-generated files from diffs via .git/info/attributes
│   ├── lint-shell         #   shellcheck + shfmt + zsh -n over every shell script (same command CI runs)
│   ├── lint-shell.test.sh #   Pins the target enumeration (a failed listing must not report ok)
│   ├── skill-eval         #   Run a skill's eval cases against a throwaway fixture (calls the API; costs money)
│   ├── skill-eval-*.sh    #   Assertions and fixture helpers the cases source
│   ├── textlint-docs      #   Run textlint/ rules on any repo (symlinked to ~/.local/bin; backs the lint-docs skill)
│   ├── read-doc           #   Typeset a document as HTML and open it in the browser (symlinked to ~/.local/bin)
│   │                      #   (session-extract / session-review, which back the retrospective skill, live beside its SKILL.md and are linked the same way)
│   ├── pr-review-common.sh  #   Pid-based lock + repo/worktree/session lookup shared by the three below
│   ├── pr-review-watch    #   Poll GitHub for new PR review feedback and queue it per PR
│   ├── pr-conflict-watch  #   Poll GitHub for PRs of yours that stopped merging, onto the same queue
│   ├── pr-review-dispatch #   Post a queued job to that branch's session inbox socket
│   └── install_minimum_vim.sh
├── brewfiles/          #   Homebrew dependency lists by category
│   ├── Brewfile-shell  #     Shell tools (tmux, fzf, ripgrep, etc.)
│   ├── Brewfile-lang   #     Language runtimes and managers
│   ├── Brewfile-xcode  #     Swift tools requiring Xcode.app
│   ├── Brewfile-cask   #     GUI applications
│   └── Brewfile-mas    #     Mac App Store apps
├── root/               #   Home directory configs (symlinked to ~/)
│   ├── CLAUDE.md       #     Global Claude Code instructions
│   ├── .agents/skills/ #     Cross-tool agent skills (single source of truth)
│   ├── .claude/        #     Claude Code settings and hooks
│   ├── .codex/         #     Codex prefix rules
│   └── opencode/       #     OpenCode config → ~/.config/opencode
├── read-doc/           #   Presentation assets for bin/read-doc
│   ├── style.css       #     Body face, measure, leading + Everforest syntax colours
│   └── after-body.html #     Inline script: code-block copy buttons, link targets
├── launchd/            #   macOS LaunchAgents (symlinked to ~/Library/LaunchAgents)
│   ├── com.ebkn.pr-review-watch.plist     # 60s poll driving bin/pr-review-watch
│   ├── com.ebkn.pr-conflict-watch.plist   # 300s poll driving bin/pr-conflict-watch
│   └── com.ebkn.pr-review-dispatch.plist  # 30s pass driving bin/pr-review-dispatch
├── textlint/           #   Japanese prose rules for bin/textlint-docs (not a project config)
│   ├── textlintrc.yml  #     Rule set, each relaxation justified inline
│   ├── prh.yml         #     Notation dictionary, split into universal / project-dependent
│   ├── textlintignore  #     Category-level exclusions
│   └── package.json    #     Pinned toolchain (+ package-lock.json)
├── .textlintignore     #   This repo's own exclusions, overriding textlint/textlintignore (not linked to ~/)
├── cursor/             #   Cursor editor settings and keybindings
├── .github/workflows/  #   CI for setup script validation
├── .shellcheckrc       #   external-sources/source-path, so an editor and bin/lint-shell agree
├── .zshrc              #   Zsh entrypoint (sources zsh/ modules)
├── .zshenv             #   Zsh early env (locale settings)
├── .tmux.conf          #   Tmux configuration
├── .gitconfig          #   Git configuration (includes .gitconfig-ebkn)
├── wezterm.lua         #   WezTerm terminal configuration
└── .*                  #   Other dotfiles (.tigrc, .ideavimrc, etc.)
```

`AGENTS.md` is a symlink to this file for Codex compatibility.

**Detailed notes live next to the thing they describe**, not here. Every
non-trivial script has a sibling `.md` (`bin/tmux-agents.md`,
`bin/pr-conflict-watch.md`, …), and each area has one too (`zsh/README.md`,
`root/README.md`, `vim/coc-trust.md`). This file keeps the conventions and one
line per feature pointing at its doc. **Read the doc before editing the thing** —
most of these have failure modes that are completely silent, and the doc is where
the measurement and the reason live.

## Key Conventions

- **Symlink-based**: Setup scripts in `bin/init/` symlink files from this repo to `~/`. Existing files are backed up to `~/backup/`.
- **Modular zsh**: Shell config is split by concern in `zsh/` and sourced from `.zshrc`. **Module order is not fully free** and the constraint is invisible — `alias.zsh` must precede `git.zsh`. See [zsh/README.md](zsh/README.md).
- **`.zshrc` finds `zsh/` relative to itself** via `${(%):-%N}`, never `$0`, so a checkout anywhere loads its own modules. See [zsh/README.md](zsh/README.md); pinned by `zsh/zshrc-resolve.test.zsh`.
- **Never `stat` a path under `/home` on macOS** — autofs makes it ~16ms per stat, on every zsh start. Guard on `$OSTYPE`. See [zsh/README.md](zsh/README.md).
- **Tmux auto-start**: `.zshrc` starts tmux automatically and exits the shell when tmux closes.
- **Lazy loading**: Language managers and CLI tools are lazy-loaded in `zsh/lang.zsh` for fast startup. Consequence: see the AWS note in Environment Notes below.
- **Plugin managers**: Neovim uses lazy.nvim; Zsh uses Zinit.
- **Everything clones over SSH, deliberately.** `.gitconfig` rewrites every `https://github.com/…` URL to SSH before git dials out, including zinit's plugin clones. So a brand-new machine can fetch **nothing** from GitHub until an SSH key is in place (key first, then first login), and **changing a URL here to HTTPS accomplishes nothing** — the rewrite converts it straight back, silently. Verify which transport a command really uses with `GIT_SSH_COMMAND=false git ls-remote https://github.com/…`; `GIT_CONFIG_GLOBAL=/dev/null` is the only switch that neutralizes it, at the cost of the credential helper.

## Editing Guidelines

- **Zsh config**: Identify the correct module in `zsh/` rather than editing `.zshrc` directly. See [zsh/README.md](zsh/README.md), and [ssh.md](zsh/ssh.md) / [git.md](zsh/git.md) / [alias.md](zsh/alias.md).
- **Neovim plugins**: Config lives in `vim/nvim/lua/plugins/`, split into `instantly/` (always loaded) and `lazy/` (on-demand by filetype). Core Vim settings are in `vim/*.vim`.
- **coc.nvim workspace trust**: coc has no trust model at all, so a cloned repo's `.vim/coc-settings.json` can spawn an arbitrary executable just by opening a file in it. The only gate is not starting coc. Four things silently break it — read [vim/coc-trust.md](vim/coc-trust.md) before touching `vim/nvim/lua/coc_trust.lua`.
- **Brewfiles**: Changes go in the appropriate category file under `brewfiles/` (shell, lang, cask, mas).
- **New dotfiles**: For a plain, order-independent `$HOME` symlink, add a `link_with_backup` line to `link_dotfiles()` in `bin/init/links.sh` — the single source of truth shared by `bin/init/macos.sh` and `bin/relink`, so `update-all` picks it up with no init re-run. For `ubuntu.sh`/`wsl.sh` add the line inline (not yet migrated). Keep order-sensitive links (`.zshrc`/`.zshenv`, `.npmrc`) or links wrapped in special logic inline in the platform init script.
- **Re-syncing symlinks**: `update-all` runs `relink` at the end; it reports drift and asks before creating/fixing links. Run `relink` directly anytime.
- **Platform-specific binaries**: Helpers that only make sense on one OS go under `bin/<platform>/` (e.g. `bin/wsl/`). Cross-platform helpers stay at `bin/` root. Symlink them from the matching `bin/init/<platform>.{sh,ps1}`.
- **Executables live in `bin/`, never at the repo root.** The root is for files symlinked into `$HOME` as-is (`.zshrc`, `.tmux.conf`, `wezterm.lua`); anything that ends up on `$PATH` belongs in `bin/`. **Moving a `bin/` script breaks running machines until `relink` is run**: `~/.local/bin/<name>` becomes a dangling symlink, and every caller here redirects stderr to `/dev/null`, so the only symptom is a feature quietly not happening. `relink` does detect and re-point it, but it has to actually be run.
- **Home directory agent config**: Global Claude Code/Codex settings live in `root/` and are symlinked to `~/`. **This repository is public, and `root/.claude/settings.json` is the one file that keeps forgetting it** — `/config` writes machine-local state, and `autoMode.environment` is a profile of whatever private repo you were working in. That, the three `root/CLAUDE.md` destinations, the curl and `rm` permission rules, the Codex prefix rules and the skill-linking policy are all in [root/README.md](root/README.md). **Read it before editing anything under `root/`.**
- **Agent skills**: Skills this repo OWNS live once under `root/.agents/skills/<name>/SKILL.md` and are linked **individually** into each consumer dir. A new owned skill needs a `relink` to appear. Note that Codex ignores `allowed-tools`, so **a read-only skill must state that boundary in its body** — see [root/README.md](root/README.md).

### Features

Each entry names the doc to read first.

- **Agent state indicator** — which Claude session is blocked, published as tmux pane user options (`@claude_state` and friends), kept per actor because hooks fire inside subagents too. Producer: `root/.claude/hooks/agent-state.sh`; consumers: `set-titles-string` in `.tmux.conf` and `bin/tmux-agents`. → [root/.claude/hooks/agent-state.md](root/.claude/hooks/agent-state.md)
- **Agent picker** (`prefix + a`) — list every session by state and jump to its WezTerm tab. **Latency-critical: the cost is process count, not work.** → [bin/tmux-agents.md](bin/tmux-agents.md)
- **Answering a blocked agent** (`ctrl-o` in the picker, `C-]` to leave) — mirrors the agent's window in a popup so a dialog can be answered in place. → [bin/tmux-agent-view.md](bin/tmux-agent-view.md)
- **tmux popups** (`prefix + p` shell, `t` tig, `o` fzf→nvim) — each opens a real session named `_<name>_<id>`; the leading `_` is the guard that stops a popup opening inside a popup. → [bin/tmux-popup.md](bin/tmux-popup.md)
- **Key-binding cheatsheet** (`prefix + ?`) — derived from `tmux list-keys -N`, so adding `-N "<category>: <description>"` to a `bind` line is what documents it. A binding without a note is invisible here, deliberately. → [bin/tmux-cheatsheet.md](bin/tmux-cheatsheet.md)
- **One WezTerm tab means one tmux session** (`prefix + w`) — nothing in tmux enforces it, so `w` swaps clients rather than switching. → [bin/tmux-session-swap.md](bin/tmux-session-swap.md)
- **Remote session tracking** — the autossh reconnect binding must stay single-valued in both directions. → [bin/tmux-track-session.md](bin/tmux-track-session.md)
- **`.tmux.conf` itself** — `prefix + d` asks before detaching; every non-`-n` binding must carry `-N`. → [bin/tmux-conf.md](bin/tmux-conf.md)
- **The reconnect screen** — `AUTOSSH_PATH` shim owning the screen between attempts; the mouse-report flood is the half that looks like a separate bug. → [bin/autossh-ssh.md](bin/autossh-ssh.md)
- **Document reading** (`bin/read-doc` + `read-doc/style.css`) — the point is the stylesheet, not the converter; **do not turn it into a terminal pager.** Untrusted input, so pandoc runs `--sandbox` behind a CSP. Includes the ssh forward mode. → [bin/read-doc.md](bin/read-doc.md)
- **PR automation** — two stages on purpose: the detectors queue, [dispatch](bin/pr-review-dispatch.md) delivers to a session's inbox socket. The queue is what makes interruption avoidable, so **it must never be bypassed.** Two detectors feed it: [pr-review-watch](bin/pr-review-watch.md) for review feedback, and [pr-conflict-watch](bin/pr-conflict-watch.md) for a PR that stopped merging — **separate because a conflict raises no notification**, so it cannot use the conditional request that makes the review poll free, and its `mergeable` has a third value (`UNKNOWN`) that is neither answer. **Neither detector nor dispatch ever writes to a worktree**; the session does the merge. Shared lock and worktree lookup: [pr-review-common.md](bin/pr-review-common.md). Loading the launchd agents is a separate decision: [launchd-load.md](bin/launchd-load.md).
- **Japanese prose linting** (`textlint/` + `bin/textlint-docs`, backing the `lint-docs` skill) — the rules are materialized into a cache dir, so the target project gets no config. Narrowing to Japanese files is the caller's job. → [bin/textlint-docs.md](bin/textlint-docs.md)
- **Skill evals** (`bin/skill-eval`) — a skill's behaviour is invisible in its diff, so editing a `SKILL.md` is otherwise unmeasurable. Cases live beside the skill in `evals/`; running them calls the API and costs money, so CI runs only the runner's own test. → [bin/skill-eval.md](bin/skill-eval.md)
- **Session retrospective** (`/retrospective`) — aggregates transcripts into distributions, never a mean. → [root/.agents/skills/retrospective/NOTES.md](root/.agents/skills/retrospective/NOTES.md)

## Shell Script Conventions

Adopted from `tetsunavi-monorepo`'s `015_shell_scripts.md`, with the divergences below recorded rather than papered over. Enforced by `bin/lint-shell` (`shellcheck` + `shfmt -i 2 -ci` + `zsh -n`), which CI runs on every push.

- **Formatting is `shfmt -i 2 -ci`, and is not a matter of taste.** `bin/lint-shell --write` applies it. `-ci` keeps `case` branches indented, which is what the repo already did; dropping it de-indents every branch in the repo for no reading benefit. **zsh is formatted by nobody.** shfmt parses as bash, and `shfmt -f` claims `*.zsh` by extension (21 files here), so a listing built with `shfmt -f` — the form the monorepo uses, where no zsh exists — would rewrite `zsh/` modules through a parser that cannot represent them. `bin/lint-shell` therefore feeds shfmt its own shebang-discovered list, and `bin/lint-shell.test.sh` pins that no zsh module reaches shfmt.
- **The shebang here is `#!/bin/bash`, not the monorepo's `#!/usr/bin/env bash`, and the difference is deliberate.** `env bash` resolves the *newest* bash on `PATH`, which on a developed macOS is Homebrew's 5.x — so a script using `mapfile` or `declare -A` passes locally and breaks on a machine that has only the stock shell. This repo's whole job is to provision such a machine: `bin/init/*` runs **before** Homebrew exists, and the hooks under `root/.claude/` run wherever Claude Code is started. `#!/bin/bash` pins **3.2** on macOS, so writing to the oldest bash is enforced by running the script at all rather than by remembering to. That is why `approve-multiline-commands.sh` and `pr-review-*.test.sh` say "written for bash 3.2": no `mapfile`, no associative arrays, no `${var^^}`, and no empty-array expansion under `set -u`. Portable scripts that never touch a bare machine keep `#!/usr/bin/env bash`. **The rule does not invert:** do not "modernise" a `#!/bin/bash` to `env bash` — it removes the only thing checking the 3.2 constraint, and nothing fails until someone runs the script on a fresh Mac.
- **A process substitution's exit status reaches neither `set -e` nor `pipefail`.** `while read …; do …; done < <(cmd)` runs zero iterations when `cmd` fails and carries on. This is the single most expensive trap in this file's history: `bin/lint-shell` itself read `git ls-files` that way and, with the listing failing, checked 3 files instead of 52 and printed `ok`. Take the output with a command substitution (`out=$(cmd)` with an explicit status check) and read it with `<<<`. Note `<<<` on an empty string still yields one empty line, so skip empties — `[ -f "$f" ] || continue` already does.
- **`$?` is not tested directly.** Use `if cmd; then … else … fi`, which is also what keeps `set -e` honest. `2>&1` goes last in a redirection (`>/dev/null 2>&1`).
- **`curl` that saves a response takes `-f`.** Without it a 4xx/5xx exits 0 and the error body is written as though it were the payload. `-sf` when silent, `-fsS` when the message is wanted.
- **shellcheck runs at its default severity here, not the monorepo's `--severity=warning`.** The repo is small and already clean at style level, so there is nothing to gain by lowering the bar. Suppress a false positive on the **line above** it with a reason (`# shellcheck disable=SCxxxx`), never file-wide, and only after trying to satisfy the check instead. `external-sources` / `source-path` are set once in `/.shellcheckrc` so an editor and the gate agree.
- **`set -eo pipefail` at the top of anything executed directly**; `-u` is optional and genuinely awkward around optional arguments and empty-array expansion on bash 3.2. **Sourced fragments get none of it** — `bin/init/common.sh`, `links.sh`, `bin/pr-review-common.sh` — because `set` mutates the caller's shell. Those three have no shebang either, so they are named inline in `bin/lint-shell` and carry `# shellcheck shell=bash`.

## Environment Notes

- **AWS CLI**: Use `/opt/homebrew/bin/aws` to invoke the AWS CLI. The `aws` command is lazy-loaded in zsh, so the bare `aws` may not resolve in non-interactive shells.

## Testing

`bin/lint-shell` is the static gate for every shell script and CI runs the same
command, so local and CI cannot disagree — see [bin/lint-shell.md](bin/lint-shell.md).
Run it before pushing, and **after `git add`**: discovery is `git ls-files`, so an
untracked script passes vacuously.

Each suite's rationale — what it pins, which cases earn their keep, and the
harness traps that made earlier versions green while proving nothing — is in the
doc beside it. The recurring lesson across all of them: **assert on the observable
contract, not on the exit status**, because nearly every failure mode here is
silent.

| Suite | Doc |
| --- | --- |
| `bin/lint-shell.test.sh` | [lint-shell.md](bin/lint-shell.md) |
| `bin/skill-eval.test.sh` | [skill-eval.md](bin/skill-eval.md) |
| `bin/tmux-agents.test.sh` | [tmux-agents.md](bin/tmux-agents.md) |
| `bin/tmux-agent-view.test.sh` | [tmux-agent-view.md](bin/tmux-agent-view.md) |
| `bin/tmux-popup.test.sh`, `bin/tmux-tig` | [tmux-popup.md](bin/tmux-popup.md) |
| `bin/tmux-cheatsheet` | [tmux-cheatsheet.md](bin/tmux-cheatsheet.md) |
| `bin/tmux-conf.test.sh` | [tmux-conf.md](bin/tmux-conf.md) |
| `bin/tmux-pane-titles.test.sh` | [tmux-pane-titles.md](bin/tmux-pane-titles.md) |
| `bin/tmux-session-swap.test.sh` | [tmux-session-swap.md](bin/tmux-session-swap.md) |
| `bin/tmux-track-session.test.sh` | [tmux-track-session.md](bin/tmux-track-session.md) |
| `bin/autossh-ssh.test.sh` | [autossh-ssh.md](bin/autossh-ssh.md) |
| `bin/pr-review-common.test.sh` | [pr-review-common.md](bin/pr-review-common.md) |
| `bin/pr-review-watch.test.sh` | [pr-review-watch.md](bin/pr-review-watch.md) |
| `bin/pr-conflict-watch.test.sh` | [pr-conflict-watch.md](bin/pr-conflict-watch.md) |
| `bin/pr-review-dispatch.test.sh` | [pr-review-dispatch.md](bin/pr-review-dispatch.md) |
| `root/.claude/hooks/agent-state.test.sh` | [agent-state.md](root/.claude/hooks/agent-state.md) |
| `root/.claude/hooks/approve-multiline-commands.test.sh` | [approve-multiline-commands.md](root/.claude/hooks/approve-multiline-commands.md) |
| `root/.claude/hooks/curl-guard.test.sh` | [root/README.md](root/README.md) |
| `root/.codex/rules/default.rules.test.sh` | [root/README.md](root/README.md) — local only, not in CI |
| `root/.agents/skills/retrospective/*.test.sh` | [NOTES.md](root/.agents/skills/retrospective/NOTES.md) |
| `zsh/*.test.zsh` | [zsh/README.md](zsh/README.md) |
| `bin/read-doc`, `bin/textlint-docs` | verified by running them: [read-doc.md](bin/read-doc.md), [textlint-docs.md](bin/textlint-docs.md) |

- **GitHub Actions CI** (`.github/workflows/`) runs the platform setup scripts plus lint, the hook tests, the tmux script tests, the retrospective tests and the `zsh/` unit tests. `git-guard.test.sh` is **not** wired in yet.
- **Setup workflows must test the pushed branch.** They `actions/checkout`, symlink the checkout to `~/dotfiles`, and run the bootstrap with `DOTFILES_SKIP_UPDATE=1` so it does not self-update over the branch under test. The earlier form — `curl .../main/bin/init/bootstrap-*.sh | sh`, letting the bootstrap `git clone` the default branch — meant every job validated `main` regardless of the pushed ref, so the checks could not fail on unmerged code. **Do not reintroduce a hardcoded `/main/` raw URL or drop the skip flag.**
