# lint-shell

`shellcheck` + `shfmt` + `zsh -n` over every shell script. The same command CI
runs (`.github/workflows/lint-and-test.yml`), so local and CI cannot disagree.

- `shellcheck -x -P SCRIPTDIR` and `shfmt -d -i 2 -ci` over the sh/bash ones
- `zsh -n` over the zsh ones (shellcheck cannot parse zsh — SC1071 — and shfmt
  would silently reformat it as bash)
- `--write` applies the formatting instead of reporting it

Run it before pushing.

## Targets are discovered, not listed

By shebang, so a new script is covered automatically. The two exceptions are
named in the script: sourced fragments (`bin/init/common.sh`, `links.sh`,
`bin/pr-review-common.sh` — no shebang, so they carry a
`# shellcheck shell=bash` directive) and the `zsh/` modules.

Discovery is `git ls-files`, so an **untracked** script is skipped silently — run
it after `git add`, or a brand-new file passes vacuously.

**zsh is formatted by nobody.** shfmt parses as bash, and `shfmt -f` claims
`*.zsh` by extension (21 files here), so a listing built with `shfmt -f` — the
form the upstream convention doc uses, where no zsh exists — would rewrite `zsh/`
modules through a parser that cannot represent them. This script therefore feeds
shfmt its own shebang-discovered list, and `lint-shell.test.sh` pins that no zsh
module reaches shfmt.

## A gate that discovers its own targets fails by checking nothing and reporting ok

Which is exactly what happened while the listing was read through a process
substitution: `git ls-files` failing left the fallback three files as the entire
target set, and the run printed `ok`. It checked 3 files instead of 52.

This is the single most expensive trap in this repo's history, and the reason the
convention exists: **a process substitution's exit status reaches neither
`set -e` nor `pipefail`.** Take the output with a command substitution
(`out=$(cmd)` with an explicit status check) and read it with `<<<`.

## Testing (`lint-shell.test.sh`)

Pins that a failed or empty `git ls-files` exits non-zero, and stubs
shellcheck/shfmt/zsh so it asserts on **which files the gate decided to hand
them** rather than on their verdicts. Both enumeration cases were confirmed red
against the previous script.
