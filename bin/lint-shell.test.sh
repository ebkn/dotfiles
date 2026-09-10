#!/usr/bin/env bash
# lint-shell.test.sh — pin bin/lint-shell's target enumeration.
#
# The only failure a lint gate must not have is a vacuous green: a run that
# checks nothing and reports ok. bin/lint-shell discovers its targets from
# `git ls-files`, and the original form read that through a process
# substitution (`done < <(git ls-files)`), whose exit status propagates to
# neither `set -e` nor `pipefail`. A failed listing therefore left the loop
# with zero iterations, the target list fell back to the three sourced
# fragments named inline, and the script printed `ok` and exited 0 having
# skipped every discovered script in the repo. Nothing reports that.
#
# The checkers themselves are stubbed onto PATH, so shellcheck / shfmt / zsh
# need not be installed and no real file is inspected — what is pinned here is
# which files lint-shell decides to hand them, and whether a failure to decide
# reaches the exit status.
#
# Written for bash 3.2 (/bin/bash on macOS): no mapfile, no associative arrays.
set -uo pipefail

cd "$(dirname "$(readlink -f "$0")")/.." || exit 1

LINT="$PWD/bin/lint-shell"

failures=0

ok() { printf 'ok: %s\n' "$1"; }

fail() {
  printf 'NG: %s\n' "$1" >&2
  shift
  for line in "$@"; do printf '  %s\n' "$line" >&2; done
  failures=$((failures + 1))
}

assert_eq() {
  local label=$1 expected=$2 actual=$3
  if [ "$expected" = "$actual" ]; then
    ok "$label"
  else
    fail "$label" "expected: $expected" "actual:   $actual"
  fi
}

assert_nonzero() {
  local label=$1 code=$2
  if [ "$code" != "0" ]; then
    ok "$label"
  else
    fail "$label" "exited 0, so the failure was swallowed"
  fi
}

assert_contains() {
  local label=$1 haystack=$2 needle=$3
  case "$haystack" in
    *"$needle"*) ok "$label" ;;
    *) fail "$label" "expected to contain: $needle" "actual: $haystack" ;;
  esac
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Stub the three checkers. Each records the argv it was handed so a case can
# assert on the target list, and succeeds, so only enumeration decides the
# outcome.
make_stubs() {
  local dir=$1
  mkdir -p "$dir"
  local tool
  for tool in shellcheck shfmt zsh; do
    cat >"$dir/$tool" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" >>"$dir/$tool.argv"
exit 0
STUB
    chmod +x "$dir/$tool"
  done
}

# A stub git standing in for the listing. Every other subcommand is refused
# loudly rather than passed through, so a case cannot pass by reaching the
# real repository behind the stub's back.
make_git_stub() {
  local dir=$1 status=$2 output=$3
  cat >"$dir/git" <<STUB
#!/usr/bin/env bash
if [ "\${1:-}" = "ls-files" ]; then
  printf '%s' "$output"
  exit $status
fi
echo "unexpected git subcommand: \$*" >&2
exit 127
STUB
  chmod +x "$dir/git"
}

run_lint() {
  local dir=$1
  shift
  local code=0
  PATH="$dir:$PATH" "$LINT" "$@" >"$dir/out" 2>&1 || code=$?
  printf '%s' "$code"
}

# --- a failed listing must reach the exit status -----------------------------
# The regression this file exists for.
make_stubs "$work/failed"
make_git_stub "$work/failed" 1 ""
assert_nonzero "a failed git ls-files exits non-zero" "$(run_lint "$work/failed")"
assert_contains "a failed git ls-files says so" "$(cat "$work/failed/out")" "git ls-files"

# --- an empty listing is a broken checkout, not a clean one ------------------
# Distinct from the case above: git can succeed and still return nothing (a
# stale index, the wrong directory). The inline fallback targets would
# otherwise make that look like a passing run.
make_stubs "$work/empty"
make_git_stub "$work/empty" 0 ""
assert_nonzero "an empty git ls-files exits non-zero" "$(run_lint "$work/empty")"

# --- a normal listing checks the files it was given --------------------------
make_stubs "$work/normal"
make_git_stub "$work/normal" 0 "bin/lint-shell
zsh/alias.zsh
README.md
"
assert_eq "a normal listing exits 0" "0" "$(run_lint "$work/normal")"
assert_contains "the bash script reaches shellcheck" \
  "$(cat "$work/normal/shellcheck.argv")" "bin/lint-shell"
assert_contains "the zsh module reaches zsh -n" \
  "$(cat "$work/normal/zsh.argv")" "zsh/alias.zsh"

# --- zsh never reaches shfmt -------------------------------------------------
# shfmt parses as bash. Handing it a zsh module would reformat constructs it
# cannot represent, so the formatter must be fed the shellcheck target list
# and not a listing of its own (`shfmt -f` does claim *.zsh).
assert_contains "the bash script reaches shfmt" \
  "$(cat "$work/normal/shfmt.argv")" "bin/lint-shell"
case "$(cat "$work/normal/shfmt.argv")" in
  *zsh/alias.zsh*) fail "no zsh module reaches shfmt" "zsh/alias.zsh was passed to shfmt" ;;
  *) ok "no zsh module reaches shfmt" ;;
esac

# --- the formatter defaults to reporting, not rewriting ----------------------
# A lint command that edits the working tree as a side effect of being run is
# a surprise; --write is the opt-in.
assert_contains "the default run asks shfmt for a diff" \
  "$(cat "$work/normal/shfmt.argv")" "-d"
make_stubs "$work/write"
make_git_stub "$work/write" 0 "bin/lint-shell
"
assert_eq "--write exits 0" "0" "$(run_lint "$work/write" --write)"
assert_contains "--write asks shfmt to rewrite" \
  "$(cat "$work/write/shfmt.argv")" "-w"

# --- an unknown argument is rejected -----------------------------------------
make_stubs "$work/badarg"
make_git_stub "$work/badarg" 0 "bin/lint-shell
"
assert_nonzero "an unknown argument exits non-zero" "$(run_lint "$work/badarg" --nope)"

if [ "$failures" -ne 0 ]; then
  printf '\nlint-shell: %d test(s) failed\n' "$failures" >&2
  exit 1
fi

printf '\nlint-shell: all tests passed\n'
