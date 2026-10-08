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
# assert on the target list, and succeeds -- unless it is named as the one to
# fail, which is how the verdict itself is tested: a gate that swallowed every
# checker failure would pass every enumeration case below.
make_stubs() { # make_stubs <dir> [failing-tool]
  local dir=$1 failing=${2:-}
  mkdir -p "$dir"
  local tool code
  for tool in shellcheck shfmt zsh; do
    code=0
    [ "$tool" = "$failing" ] && code=1
    cat >"$dir/$tool" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" >>"$dir/$tool.argv"
exit $code
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
# The failing listing still prints a file, the way a git that dies part-way
# does: an empty one would be caught by the emptiness check below anyway, and
# leave the status check itself unpinned.
make_stubs "$work/failed"
make_git_stub "$work/failed" 1 "bin/lint-shell
"
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
# bin/init/macos.sh is a real `#!/bin/zsh` script, the case a loosened shebang
# pattern (`^#!.*sh`) would wrongly hand to shellcheck.
make_stubs "$work/normal"
make_git_stub "$work/normal" 0 "bin/lint-shell
bin/init/macos.sh
zsh/alias.zsh
README.md
"
assert_eq "a normal listing exits 0" "0" "$(run_lint "$work/normal")"
assert_contains "the bash script reaches shellcheck" \
  "$(cat "$work/normal/shellcheck.argv")" "bin/lint-shell"
assert_contains "the zsh module reaches zsh -n" \
  "$(cat "$work/normal/zsh.argv")" "zsh/alias.zsh"
assert_contains "a zsh-shebang script reaches zsh -n" \
  "$(cat "$work/normal/zsh.argv")" "bin/init/macos.sh"
case "$(cat "$work/normal/shellcheck.argv")" in
  *bin/init/macos.sh*) fail "a zsh-shebang script does not reach shellcheck" "it was passed" ;;
  *) ok "a zsh-shebang script does not reach shellcheck" ;;
esac
# The entrypoints have no shebang and live outside zsh/, so only their inline
# names put them in front of zsh -n.
for f in .zshrc .zshenv; do
  if grep -qxF "$f" "$work/normal/zsh.argv"; then
    ok "$f reaches zsh -n"
  else
    fail "$f reaches zsh -n" "zsh argv: $(tr '\n' ' ' <"$work/normal/zsh.argv")"
  fi
done
case "$(cat "$work/normal/shellcheck.argv" "$work/normal/shfmt.argv" "$work/normal/zsh.argv")" in
  *README.md*) fail "a non-script reaches no checker" "README.md was passed" ;;
  *) ok "a non-script reaches no checker" ;;
esac

# --- every sourced fragment is a target --------------------------------------
# Fragments carry no shebang, so discovery cannot find them and they are named
# inline. A new fragment that is not added to that list is checked by nobody,
# silently. The invariant is read from the real repository: every tracked file
# declaring `# shellcheck shell=` without a shebang must reach shellcheck.
if ! fragments=$(git grep -l -E '^# shellcheck shell=(bash|sh)' -- . ':!*.md'); then
  fail "the fragment listing worked" "git grep failed"
fi
nfrag=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  case "$(head -n 1 "$f")" in '#!'*) continue ;; esac
  nfrag=$((nfrag + 1))
  grep -qxF "$f" "$work/normal/shellcheck.argv" ||
    fail "sourced fragment $f reaches shellcheck" "it is not named in bin/lint-shell"
done <<<"$fragments"
# A listing that found nothing would make the loop vacuous.
if [ "$nfrag" -ge 5 ]; then
  ok "all $nfrag sourced fragments reach shellcheck"
else
  fail "the fragment listing found the fragments" "found only $nfrag"
fi

# --- a checker that fails fails the run --------------------------------------
# The verdict path. Each checker in turn, and the others must still run: a
# failing first checker that skipped the formatter would hide a second class of
# problem until the first was fixed.
for tool in shellcheck shfmt zsh; do
  make_stubs "$work/fail-$tool" "$tool"
  make_git_stub "$work/fail-$tool" 0 "bin/lint-shell
zsh/alias.zsh
"
  assert_nonzero "a failing $tool fails the run" "$(run_lint "$work/fail-$tool")"
  for other in shellcheck shfmt zsh; do
    [ "$other" = "$tool" ] && continue
    if [ -s "$work/fail-$tool/$other.argv" ]; then
      ok "with $tool failing, $other still runs"
    else
      fail "with $tool failing, $other still runs" "$other was never called"
    fi
  done
done

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
# The flag is the first argument, compared whole: `-d` as a substring also
# matches a target path such as review-design/evals/lib.sh, which is in every
# argv, so a run that defaulted to -w used to pass this.
assert_eq "the default run asks shfmt for a diff" \
  "-d" "$(head -n 1 "$work/normal/shfmt.argv")"
make_stubs "$work/write"
make_git_stub "$work/write" 0 "bin/lint-shell
"
assert_eq "--write exits 0" "0" "$(run_lint "$work/write" --write)"
assert_eq "--write asks shfmt to rewrite" \
  "-w" "$(head -n 1 "$work/write/shfmt.argv")"

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
