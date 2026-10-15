# test-in-docker

`bin/test-in-docker [suite...]` runs test suites in a container built to match
the CI runner, through `bin/test` -- in parallel, with its timeout, time table
and verdict; `TEST_JOBS` and `TEST_TIMEOUT` are passed in. With no arguments it
runs the suites `bin/test --list` skips on a laptop as tmux suites: every suite
that sources `bin/tmux-test-guard.sh`, which never runs on the host.

Two consequences of taking the list from `bin/test --list`, asked as a laptop
wherever this runs:

- **A tmux suite does not go in `bin/test.skip`.** The listing would then print
  it with that entry's reason instead of as a tmux suite, and the no-argument
  run here would drop it too; `bin/tmux-test-guard.test.sh` fails on the
  difference. Run a broken tmux suite by name instead of skipping it.
- A `bin/test.skip` entry that `bin/test` refuses (stale, or without a reason)
  stops this script as well, before anything runs.

## Why the tmux suites never run on the host

They isolate themselves with `TMUX_TMPDIR`, and **that is not isolation on a
developer machine**: tmux prefers the socket named in `$TMUX` over
`TMUX_TMPDIR`, so inside a tmux pane one missed `unset TMUX` sends `new-session`,
`send-keys` and `kill-server` to the developer's own server.

That happened. A one-off probe set `TMUX_TMPDIR`, kept `$TMUX`, and its closing
`kill-server` killed every local session: every running Claude session, every
`myssh` connection. The suites themselves all `unset TMUX`, correctly. The
failure was the one command that forgot, and "remember to unset" is exactly the
rule that had already failed. So the host is taken out of reach instead.

`bin/tmux-test-guard.sh` exits 2 unless `/.dockerenv` exists (a Docker
container) or `GITHUB_ACTIONS=true` (the runner, disposable in the same way).
Each guarded suite sources it with `|| exit 2`. These suites do not `set -e`, so
a guard file that failed to load would otherwise be skipped silently.

**Every tmux suite sources the guard**: each `bin/tmux-*.test.sh`, and any
suite that invokes `tmux … new-session|kill-server` outside a comment.
Sourcing it is also what enrolls a suite in the no-argument run, since the list
is the files holding that sourcing line. Two of the `tmux-*` suites stub tmux and
could run on the host safely; they are guarded anyway, so the rule is one a
reader can check by file name.

`bin/tmux-test-guard.test.sh` enforces the enrollment in CI, so the rule does
not depend on anyone remembering it. It also requires the guard to come before
the suite's first `trap` or `tmux` line — a cleanup trap registered above it
would run `tmux kill-server` on the host on the very exit the guard causes — and
it runs this script with `docker` stubbed, asserting that the suites it would
run are exactly the guarded ones, mounted `:ro` and without `-t`, with
`TEST_JOBS`/`TEST_TIMEOUT` passed in. That run fakes the runner
(`GITHUB_ACTIONS=true`, an existing container mark), so the list is shown to be
asked as a laptop wherever this runs; because faking the runner is what lets
the guard through, the stub directory also puts a `tmux` that refuses first on
`PATH`, so nothing started from there can reach a real server. A failed
listing must run nothing and exit non-zero. The same stub can also run the
container's command on the host against fixture suites, which pins the
verdict: a failing suite makes this script exit non-zero, named by `bin/test`,
and a passing one exits 0. The guard test and `bin/test` find the tmux suites by
copies of one regex, and a drift would shrink the local run while it still
reported every suite passed; the test checks that `bin/test`'s host-mode
`--list` skips exactly the guarded suites as tmux suites. Matching the bare
words `new-session` or
`kill-server` would be wrong both ways: the stub suites only see them as text in
a call log, and `zsh/ssh-session.test.zsh` quotes them without running tmux. It
also checks that the guard really refuses outside a container. That half can
only run on the host or the runner, since `/.dockerenv` lets it through inside
Docker. It was confirmed red by removing one suite's guard line.

## Why the image looks the way it does

Every difference from the runner is a failure the container invents
(CLAUDE.md, Testing), so each line reproduces one runner property:

- **tmux 3.7c and fzf 0.74.3, the same pins and checksums as the workflow.** The
  suites read rendered output, which moves between versions. Bump the
  Dockerfile, the workflow and `brewfiles/Brewfile-shell` together.
- **`linux/amd64`**, even on Apple Silicon: the runner is amd64, and the fzf
  checksum is for the amd64 tarball. The first build compiles tmux under
  emulation and takes a while; later runs use the cache.
- **A non-root user.** As root the kernel ignores a `chmod 500`, and a permission
  case reports a bug that does not exist.
- **`LANG=C.UTF-8`**, or tmux renders every wide glyph as `_`.
- **`nc`, `procps`, `script(1)`, `ssh`**: present on the runner, absent from a
  bare `ubuntu:24.04`. `ssh` is for `relink.test.sh`, which checks the ssh
  config it writes by what `ssh -G` resolves; it fails rather than skips
  without it.
- **No `TERM`.** `docker run` without `-t` leaves it unset, as the runner does.
  That is the one environment difference worth keeping, because the suites have
  to survive it.

The checkout is mounted **read-only**: a suite writes to its own `mktemp` dir,
and one that tries to write to the checkout should fail loudly here.
`safe.directory` is set because the mount's owner differs from the container
user.
