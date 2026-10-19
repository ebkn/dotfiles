# lint-shell

`shellcheck` + `shfmt` + `zsh -n` over every shell script. The same command CI
runs (`.github/workflows/lint-and-test.yml`), so local and CI cannot disagree —
except in the `zsh -n` pass, whose zsh is not pinned. CI's apt zsh 5.9 (and
macOS `/bin/zsh`) evaluates a top-level `$(<file)` even under `-n` and fails
when the file is absent, while Homebrew's 5.9.2 does not: main was red on that
for a week with every local run green. Check zsh with `/bin/zsh -n` too, and
read files in zsh tests with `$(cat …)`.

- `shellcheck -x -P SCRIPTDIR` and `shfmt -d -i 2 -ci` over the sh/bash ones
- `zsh -n` over the zsh ones (shellcheck cannot parse zsh — SC1071 — and shfmt
  would silently reformat it as bash)
- `--write` applies the formatting instead of reporting it

Run it before pushing.

## shellcheck runs as parallel jobs

shellcheck was ~6.5s of an ~8s run on one core, and a gate this slow gets run
less. It checks each file independently (`-x` follows sources per file), so the
targets are split into contiguous chunks, one background job each — CPU count
by default, `LINT_SHELL_JOBS=<n>` to override (a positive integer; empty means
the default; anything else is rejected, each reason beside the check in the
script). Measured on an 18-core Mac:
8.2s → 3.3s; what remains is mostly the chunk holding `tmux-agents.test.sh`
and the shebang discovery loop. That loop ran `head -n 1 | grep` per tracked
file, three processes each, ~1.2 s for 327 files; reading the first line with
`read` and matching whole words with `case` took the run to ~1.8 s (2026-10),
and gave the same target lists on the repo and on an edge-case fixture
(`env -S bash`, `bashful`, `my-sh`, CRLF, no trailing newline).

Two things the split must not lose, both pinned by the suite and both confirmed
red by mutation:

- **Every job's status.** Each pid gets its own `wait`; a bare `wait` returns 0,
  and keeping only the last status drops a finding in an earlier chunk.
- **The report's shape.** Each job writes stdout and stderr to files of its
  own, replayed in chunk order, so the output reads as one run's rather than
  interleaving — and stderr matters, since the real shellcheck reports an
  unreadable file there alone. The suite holds the first chunk back so it
  finishes last; printing jobs as they finish then puts it last, and fails.

## The same command is not the same gate unless the tools are pinned

"Local and CI cannot disagree" is a claim about the *command*, and it is worth
exactly as much as the versions behind it. **Both `shellcheck` and `shfmt` are
therefore pinned in the workflow**, by version and SHA256, and both pins are
cross-referenced from `brewfiles/Brewfile-shell`: bump them together or the two
sides drift. zsh is the one gate tool that is **not** pinned, and the only one
that has actually disagreed (see the top of this file).

shellcheck was not pinned at first — it ships with the GitHub runner image, which
looked like a reason to use it. Then the image moved, that copy began reporting
`SC2317` on a `review-test` eval helper, and **main went red with nobody having
changed a shell script**. The local shellcheck said nothing about the same file,
so the failure was unreproducible by the one command that is supposed to
reproduce it. An unpinned linter in a gate does not fail loudly; it fails on
somebody else's commit.

## Targets are discovered, not listed

By shebang, so a new script is covered automatically. The exceptions are named
in the script: the zsh config (the `zsh/` modules, matched by path, and the
`.zshrc`/`.zshenv` entrypoints, listed by name — a new shebang-less entrypoint
such as `.zprofile` must be added there, and no test catches its absence), and
every sourced fragment (such as
`bin/init/common.sh` or an eval's `lib.sh`) — never executed directly, so no
shebang; each carries a `# shellcheck shell=bash` directive and **must be added
to the inline list**, or nothing checks it. `lint-shell.test.sh` fails on a
tracked fragment that is missing, which is how `review-test/evals/grading.sh`
was found unchecked. That test looks for the bash directive only, so a
**sourced zsh fragment** outside `zsh/` (`bin/cooldown.zsh`) is like
`.zprofile`: named in `zsh_targets`, and nothing catches one left out.

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
against the previous script. The split is pinned against a one-job baseline:
the same targets, each once, each job handed `-x -P SCRIPTDIR`, no empty job.

Traps the suite once fell into, each of which kept it green while proving
nothing:

- **Stubs that only ever pass cannot see a swallowed verdict.** One stub per
  checker now exits 1, and the run must too. Confirmed red by turning the
  `status=1` after shellcheck into a no-op.
- **argv is matched argument by argument, never as a substring.** `-d` occurs
  inside `root/.agents/skills/review-design/…`, which every run passes, so the
  "default run asks for a diff" check passed even with `-w`. The failed-listing
  stub likewise prints a usable listing, or a script ignoring the status would
  fall through to the empty-listing guard and fail for the wrong reason.
- **A second failing checker masks the one under test.** `FAIL_ON=<file>`, which
  fails the job handed that file, is honoured by the shellcheck stub only:
  shfmt is handed the same file, and when its stub honoured it too, the run
  failed through shfmt and a swallowed shellcheck job went unseen.
- **A crash passes for a rejection.** `LINT_SHELL_JOBS=0` and `=abc` also break
  the chunk arithmetic, so a script with no validation exits non-zero too. The
  cases assert the message and that no job started.
- **A stub that is more forgiving than the tool.** The real shellcheck fails
  when handed no files; a stub that did not would let an empty job pass.
