---
paths:
  - "bin/**"
  - "**/*.sh"
  - "**/*.zsh"
  - "zsh/**"
  - ".zshrc"
  - ".zshenv"
  - "root/.agents/skills/retrospective/session-*"
---

# Shell script conventions

Adopted from `tetsunavi-monorepo`'s `015_shell_scripts.md`, divergences recorded below. Enforced by `bin/lint-shell` (`shellcheck` + `shfmt -i 2 -ci` + `zsh -n`), which CI runs on every push. See [bin/lint-shell.md](../../bin/lint-shell.md).

- **Formatting is `shfmt -i 2 -ci`** (`bin/lint-shell --write`). `-ci` keeps `case` branches indented, as the repo already did. **zsh is formatted by nobody**: shfmt parses as bash, and `shfmt -f` claims `*.zsh` by extension, so a list built with `shfmt -f` would rewrite `zsh/` modules through a parser that cannot represent them. `bin/lint-shell` feeds shfmt its own shebang-discovered list; `bin/lint-shell.test.sh` pins that no zsh module reaches shfmt.
- **The shebang is `#!/bin/bash`, deliberately — not `#!/usr/bin/env bash`.** `env bash` resolves Homebrew's 5.x on a developed Mac, so `mapfile` or `declare -A` pass locally and break on a stock machine. This repo provisions such machines: `bin/init/*` runs before Homebrew exists, and the hooks under `root/.claude/` run wherever Claude Code starts. `#!/bin/bash` pins **3.2** on macOS, so the constraint is enforced by running the script at all: no `mapfile`, no associative arrays, no `${var^^}`, no empty-array expansion under `set -u`. Portable scripts that never touch a bare machine keep `env bash`. **Never "modernise" a `#!/bin/bash` to `env bash`** — nothing fails until someone runs it on a fresh Mac.
- **A process substitution's exit status reaches neither `set -e` nor `pipefail`.** `while read …; done < <(cmd)` runs zero iterations when `cmd` fails and carries on — `bin/lint-shell` once checked 3 files instead of 52 that way and printed `ok`. Use `out=$(cmd)` with an explicit status check and read it with `<<<`; skip the empty line `<<<` yields on an empty string.
- **Don't test `$?` directly**: `if cmd; then … fi`, which also keeps `set -e` honest. `2>&1` goes last (`>/dev/null 2>&1`).
- **`curl` that saves a response takes `-f`** — without it a 4xx/5xx exits 0 and the error body is written as the payload. `-sf` silent, `-fsS` with messages.
- **shellcheck runs at default severity**, not the monorepo's `--severity=warning`. Suppress a false positive on the line above with a reason (`# shellcheck disable=SCxxxx`), never file-wide, and only after trying to satisfy it. `external-sources` / `source-path` live in `/.shellcheckrc`.
- **`set -eo pipefail` at the top of anything executed directly**; `-u` is optional. **Sourced fragments get none of it** (`bin/init/common.sh`, `links.sh`, `bin/pr-review-common.sh`) because `set` mutates the caller's shell. They have no shebang, carry `# shellcheck shell=bash`, and must be named inline in `bin/lint-shell` (`lint-shell.test.sh` fails otherwise).
