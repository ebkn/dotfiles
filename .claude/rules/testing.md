---
paths:
  - "**/*.test.*"
  - "bin/test*"
  - "bin/lint-shell*"
  - "bin/ci-enrollment*"
  - "bin/tmux-test-guard*"
  - "bin/init/bootstrap-*"
  - ".github/workflows/**"
  - "brewfiles/Brewfile-shell"
---

# Testing and CI

**How a suite should be shaped — waiting, fixtures, process count, output
format — is in [bin/testing.md](../../bin/testing.md).** Read it before writing
or speeding up a suite: a suite's time is processes spawned × ~2 ms plus
waiting, not its number of cases. A new or touched bash suite takes its
assertions and waits from `bin/test-lib.sh` (rule 6).

Each suite's rationale is in the doc beside it (`<script>.md`, or the suite's
header). Exceptions: zsh suites → [zsh/README.md](../../zsh/README.md), skill
eval graders → [bin/skill-eval.md](../../bin/skill-eval.md), curl/rm guard and
Codex rules suites → [root/README.md](../../root/README.md).

## Pinning: local and CI must not disagree

- `bin/lint-shell`'s shellcheck and shfmt agree with CI **only because both are
  version-pinned in the workflow**; an unpinned linter once turned main red on a
  runner-image bump. Its `zsh -n` pass is **not** pinned: Homebrew's zsh 5.9.2
  accepted what CI's 5.9 rejected, and main was red for a week. See
  [bin/lint-shell.md](../../bin/lint-shell.md).
- Tools a suite runs *against* are pinned too: `tmux` (built from a release;
  `agent-state.test.sh` depends on how it renders non-printable bytes), `fzf`
  (`tmux-agents.test.sh` reads the rendered screen; the runner lacks it), and
  `pandoc` (`read-doc.test.sh` asserts on its HTML). **Each pin lives in three
  places** — the workflow, `bin/test-in-docker.Dockerfile`,
  `brewfiles/Brewfile-shell` — each naming the other two. Bump all three.

## The test container

- **A test asserting a permission failure needs a non-root runner**: as root the
  kernel ignores `chmod 500`, and the case reports a bug that does not exist.
- That, a missing UTF-8 locale (tmux renders wide glyphs as `_`), a missing `nc`
  and a missing `fzf` are four failures a careless container invented, so **a
  difference only the container finds is a hypothesis until the container is
  shown to match the runner**. The one difference kept on purpose: it runs on
  the host's architecture, so re-run a container-only failure with
  `TEST_DOCKER_PLATFORM=linux/amd64` before believing it. See
  [bin/test-in-docker.md](../../bin/test-in-docker.md).
- Every tmux suite sources `bin/tmux-test-guard.sh`, which exits 2 outside a
  container or CI; `bin/tmux-test-guard.test.sh` fails CI when one is missing.

## Fixtures

**A test that needs something installed must supply it, not require it.** CI has
no tmux plugin manager, so `tmux-conf.test.sh` builds a fixture `$HOME` with a
no-op `tpm` — which also stops it rewriting a real plugin file with `sed -i`.

## CI workflows

- A new suite needs no workflow step; tracked is enough. To leave one out, add it
  to `bin/test.skip` with the reason. `bin/ci-enrollment.test.sh` checks the
  workflow runs `bin/test` and every suite is run or skipped with a reason.
  A `*.test.ps1` goes in `windows-setup.yml` by hand, and nothing checks it.
- **Setup workflows must test the pushed branch.** They `actions/checkout`,
  symlink the checkout to `~/dotfiles`, and run the bootstrap with
  `DOTFILES_SKIP_UPDATE=1`. The earlier `curl .../main/bin/init/bootstrap-*.sh | sh`
  validated `main` regardless of the pushed ref. **Do not reintroduce a
  hardcoded `/main/` raw URL or drop the skip flag.**
