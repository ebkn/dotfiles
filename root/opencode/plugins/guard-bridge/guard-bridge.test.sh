#!/bin/bash
# Guards the guard-bridge plugin (this directory) against silent breakage.
#
# Why this exists: bridge.mjs is the OpenCode translation of the six Claude
# PreToolUse hooks in root/.claude/hooks, driven through plugin hooks
# (shell.create.before for the one rewrite, permission.evaluate for the five
# judgments). OpenCode loads it only when a shell command next runs, so a
# broken descriptor, a pairing that no longer matches, or a misread spawn
# outcome would degrade silently -- mostly into prompts the user cannot see
# from a green CI. This suite fails closed instead, and it pins:
#
#   - the pure layer: descriptors mirror each script's own bail-out, the
#     parse of Claude's hookSpecificOutput (including `defer`, which strip
#     emits after rewriting -- read for updatedInput.command only), the
#     deny > ask > allow ranking, cwd resolution semantics, and
#     HOOK_TIMEOUT_MS = 5s mirroring settings.json's `timeout: 5`;
#   - runHook's plumbing: stdin delivered verbatim, cwd and
#     CLAUDE_PROJECT_DIR (layered over the host PATH/HOME) observed by the
#     child, nonzero exit with a stderr tail, the kill at the timeout, and
#     spawn failures (missing file, throwing spawn impl);
#   - the wiring: execute.before stashes the command, evaluate pairs with it
#     through `source` (never top-level ids -- the evaluate event does not
#     carry them), workdir and session-directory resolution, the resources
#     fallback for an unpaired event, the 128-entry cap, execute.after
#     cleanup, verdicts applied to effect/message, silent failure for the
#     five allow/rewrite scripts vs. fail-closed deny for git-guard (its
#     settings.json onFailure: "block"), quiet degradation when ~/.claude
#     /hooks does not exist (an OpenCode-only machine), and the create.before
#     rewrite staying off when the strip script does not rewrite;
#   - and ALL SIX REAL scripts, run from this repo's root/.claude/hooks:
#     strip rewrites `cd <cwd> && rest` and refuses an unrelated cd;
#     git-guard denies a `-c` before the subcommand through exit 0 + JSON,
#     not the crash path; rm-guard allows an operand inside the cwd's own
#     tmp/ and stays silent outside it; approve-multiline-commands allows a
#     newline held inside a commit message; git-dash-c-allow and curl-guard
#     act on the allow rules they read, under a STAGED HOME holding a
#     minimal settings.json, so the verdicts are properties of the fixtures
#     and not of the machine running the suite. The mocks exist for the
#     failure paths (crash, hang) a real script cannot be asked to take on
#     cue; the stdio shape they imitate is the same one checked here.
#
# The mock scripts share one directory: behavior comes from a
# `<script>.out` file the case writes (absent = silent, `sleep` hangs,
# `crash` exits 7 with stderr), so one copy serves every case (rule 3 of
# bin/testing.md). The node drivers under test/ record
# `ok|fail<TAB>name<TAB>detail` lines that the shell turns into test-lib
# checks, so node's findings count in the same tally (rule 6: no separate
# counter).
#
# Run by bin/test (discovery is `git ls-files`, tracked is enough for CI).
set -eo pipefail

# shellcheck source=bin/test-lib.sh
. "$(dirname "$0")/../../../../bin/test-lib.sh" || exit 2

suite_dir=$(cd "$(dirname "$0")" && pwd)
claude_hooks=$(cd "$suite_dir/../../.." && pwd)/.claude/hooks
node_dir="$suite_dir/test"

# One staging dir for the whole suite: the mock hook scripts and per-case
# logs (testing.md rule 3: fixture built once).
test_tmpdir
stage=$TEST_TMPDIR/stage
mkdir -p "$stage/session" "$stage/mock"
export MOCK_DIR="$stage/mock"

# ── the mock hook scripts ─────────────────────────────────────────────
# One body for all six names: the stdio contract of the real scripts, with
# behavior switched by the .out file beside the copy.
for name in approve-multiline-commands git-dash-c-allow curl-guard rm-guard git-guard strip-redundant-cd; do
  cat >"$MOCK_DIR/$name.sh" <<'MOCKERC'
#!/bin/sh
# Same stdio shape as the ~/.claude hook scripts: one JSON input line on
# stdin, an optional hookSpecificOutput on stdout, silent exit for no
# opinion. Behavior comes from the .out file beside this copy:
#   absent -> silent   | sleep -> hang (the runHook timeout case). The
#                          hang is a sh-builtin loop, deliberately not
#                          `sleep`: the bridge kills the direct child only,
#                          and a forked `sleep` surviving it would hold the
#                          pipe open until its own expiry -- a 60s stall
#                          here, a duration flake in unit-slow. The loop
#                          dies with the child, so the kill closes the pipe.
#   crash -> stderr + exit 7  | otherwise the file is catted verbatim
IFS=
line=$(cat)
if [ -n "${MOCK_LOG:-}" ]; then
  {
    printf '%s\n' "$line"
    printf 'cwd=%s\n' "$(pwd)"
    printf 'project=%s\n' "${CLAUDE_PROJECT_DIR-}"
    printf 'home=%s\n' "${HOME-}"
    printf 'path=%s\n' "${PATH+set}"
  } >>"$MOCK_LOG"
fi
behavior=$(cat "$(dirname "$0")/$(basename "$0" .sh).out" 2>/dev/null)
case "$behavior" in
  sleep) while :; do :; done ;;
  crash)
    printf 'mock crash from %s\n' "$(basename "$0")" >&2
    exit 7
    ;;
  '') ;;
  *) printf '%s\n' "$behavior" ;;
esac
MOCKERC
  chmod +x "$MOCK_DIR/$name.sh"
done

# runHook unit probes: echo recites what the child process saw (stdout stays
# a clean hook JSON; observations land in $PROBE_LOG), fail exits 7 with
# stderr bait, slow hangs.
cat >"$stage/unit-echo.sh" <<'UNIT'
#!/bin/sh
IFS=
line=$(cat)
{
  printf 'stdin=%s\n' "$line"
  printf 'cwd=%s\n' "$(pwd)"
  printf 'proj=%s\n' "${CLAUDE_PROJECT_DIR-}"
  printf 'home=%s\n' "${HOME-}"
  printf 'path=%s\n' "${PATH+set}"
} >>"${PROBE_LOG:?PROBE_LOG unset}"
printf '{"hookSpecificOutput":{"permissionDecision":"allow","permissionDecisionReason":"probe"}}\n'
UNIT
cat >"$stage/unit-fail.sh" <<'UNIT'
#!/bin/sh
printf 'unit-fail stderr line 1\nunit-fail stderr line 2\n' >&2
exit 7
UNIT
cat >"$stage/unit-slow.sh" <<'UNIT'
#!/bin/sh
# Hangs without forking a child: a `sleep` here would survive the runHook
# kill as an orphan holding the pipe open (the mock's comment explains why).
while :; do :; done
UNIT
chmod +x "$stage/unit-echo.sh" "$stage/unit-fail.sh" "$stage/unit-slow.sh"

# assert_recorded <tsv-file> -- turn the node pass's recorded
# `ok|fail<TAB>name<TAB>detail` lines into test-lib checks.
# shellcheck disable=SC2329  # called from the test functions below
assert_recorded() {
  local file=$1 st name detail
  [ -s "$file" ] || {
    assert_eq 'node pass recorded checks' ok "no results file $file"
    return
  }
  while IFS=$'\t' read -r st name detail || [ -n "$name" ]; do
    [ -n "$name" ] || continue
    if [ "$st" = "ok" ]; then
      assert_eq "$name" ok ok
    else
      assert_eq "$name" ok "fail: $detail"
    fi
  done <"$file"
}

# Each test runs one node driver pass; the driver exits nonzero when any
# recorded check failed, assert_recorded shows every finding, and the
# driver's own crash shows under the assert_status line. shellcheck sees
# none of the invocations (run_tests calls these by name), hence the
# disable above each.

# shellcheck disable=SC2329
test_pure_helpers() {
  test_tmpdir
  assert_status "pure helpers node pass" 0 node "$node_dir/pure.mjs" "$TEST_TMPDIR/pure.tsv" "$claude_hooks"
  assert_recorded "$TEST_TMPDIR/pure.tsv"
}

# shellcheck disable=SC2329
test_run_hook_plumbing() {
  test_tmpdir
  assert_status "runHook plumbing node pass" 0 node "$node_dir/runhook.mjs" "$TEST_TMPDIR/runhook.tsv" "$stage"
  assert_recorded "$TEST_TMPDIR/runhook.tsv"
}

# shellcheck disable=SC2329
test_wire_allow_and_pairing() {
  test_tmpdir
  assert_status "wire: verdicts and pairing node pass" 0 \
    node "$node_dir/wire.mjs" "$TEST_TMPDIR/wire-allow.tsv" "$stage" allow
  assert_recorded "$TEST_TMPDIR/wire-allow.tsv"
}

# shellcheck disable=SC2329
test_wire_rank_and_fallback() {
  test_tmpdir
  assert_status "wire: ranking, fallback and cap node pass" 0 \
    node "$node_dir/wire.mjs" "$TEST_TMPDIR/wire-rank.tsv" "$stage" rank
  assert_recorded "$TEST_TMPDIR/wire-rank.tsv"
}

# shellcheck disable=SC2329
test_wire_failures() {
  test_tmpdir
  assert_status "wire: failure postures node pass" 0 \
    node "$node_dir/wire.mjs" "$TEST_TMPDIR/wire-failures.tsv" "$stage" failures
  assert_recorded "$TEST_TMPDIR/wire-failures.tsv"
}

# shellcheck disable=SC2329
test_wire_rewrite() {
  test_tmpdir
  assert_status "wire: create.before rewrite node pass" 0 \
    node "$node_dir/wire.mjs" "$TEST_TMPDIR/wire-rewrite.tsv" "$stage" rewrite
  assert_recorded "$TEST_TMPDIR/wire-rewrite.tsv"
}

# shellcheck disable=SC2329
test_real_scripts() {
  test_tmpdir
  assert_status "real hooks scripts node pass" 0 \
    node "$node_dir/wire.mjs" "$TEST_TMPDIR/wire-real.tsv" "$stage" real "$claude_hooks"
  assert_recorded "$TEST_TMPDIR/wire-real.tsv"
}

run_tests
