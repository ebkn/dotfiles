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
# which files lint-shell decides to hand them, with which shfmt mode, and
# whether a failure -- to list, or a checker's finding -- reaches the exit
# status. Every case asserting a pass has checkers that always pass, so the
# finding cases are the only ones that can see a swallowed verdict.
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

# Whole-argument matches against a stub's recorded argv, one argument per line.
# A substring match is not enough: `-d` occurs inside the path
# root/.agents/skills/review-design/..., which every run passes.
assert_arg() {
  local label=$1 file=$2 arg=$3
  if grep -qxF -- "$arg" "$file" 2>/dev/null; then
    ok "$label"
  else
    fail "$label" "no argument [$arg] in $(tr '\n' ' ' <"$file" 2>/dev/null)"
  fi
}

refute_arg() {
  local label=$1 file=$2 arg=$3
  if grep -qxF -- "$arg" "$file" 2>/dev/null; then
    fail "$label" "argument [$arg] was passed"
  else
    ok "$label"
  fi
}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Stub the three checkers. Each records the argv it was handed so a case can
# assert on the target list, and one line per invocation in <tool>.calls, and
# succeeds -- except the one named as failing, which exits 1 as a checker does
# on a finding, so a case can see whether a finding reaches the exit status.
make_stubs() { # make_stubs <dir> [failing-tool]
  local dir=$1 failing=${2:-} tool code
  mkdir -p "$dir"
  for tool in shellcheck shfmt zsh; do
    code=0
    [ "$tool" = "$failing" ] && code=1
    cat >"$dir/$tool" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" >>"$dir/$tool.argv"
echo call >>"$dir/$tool.calls"
exit $code
STUB
    chmod +x "$dir/$tool"
  done
  make_shellcheck_stub "$dir" "$([ "$failing" = shellcheck ] && echo 1 || echo 0)"
}

# The shellcheck stub is a separate one, because the parallel split is only
# observable through what each invocation was handed and what it printed:
# - one `checked: <file>` line per file on stdout, so a split run's output can
#   be compared line for line with a single job's;
# - like the real one (`No files specified.`, exit 3), it fails when handed no
#   files, so an empty job breaks a clean run instead of passing unseen;
# - FAIL_ON=<file> fails only the invocation handed that file, with a finding on
#   stdout and an error on stderr -- the real one reports an unreadable file on
#   stderr alone. Only this stub honours it: shfmt is handed the same file, and
#   its failure would mask a lost job;
# - SLOW_ON=<file> holds back the invocation handed that file, so a job that
#   finishes first is not also the one printed first by luck.
make_shellcheck_stub() { # make_shellcheck_stub <dir> <exit code>
  local dir=$1 code=$2
  cat >"$dir/shellcheck" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\$@" >>"$dir/shellcheck.argv"
echo call >>"$dir/shellcheck.calls"
files=0
for a in "\$@"; do
  case "\$a" in -x | -P | SCRIPTDIR) continue ;; esac
  files=\$((files + 1))
  [ "\$a" = "\${SLOW_ON:-}" ] && sleep 0.5
  echo "checked: \$a"
  if [ "\$a" = "\${FAIL_ON:-}" ]; then
    echo "finding: \$a"
    echo "error: \$a" >&2
    exit 1
  fi
done
if [ "\$files" -eq 0 ]; then
  echo "No files specified." >&2
  exit 3
fi
exit $code
STUB
  chmod +x "$dir/shellcheck"
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
# The regression this file exists for. The stub still prints a usable listing,
# the way a git that dies part-way does: with empty output, a lint-shell that
# ignored the status would fall through to the empty-listing guard below and
# fail anyway, for the wrong reason.
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
# bin/init/macos.sh is a real `#!/bin/zsh` script outside zsh/, so only its
# shebang can route it -- the case a loosened pattern (`^#!.*sh`, or `\bsh\b`
# matching the `sh` inside `zsh`) would wrongly hand to shellcheck.
make_stubs "$work/normal"
make_git_stub "$work/normal" 0 "bin/lint-shell
bin/tmux-popup
bin/init/macos.sh
zsh/alias.zsh
README.md
"
assert_eq "a normal listing exits 0" "0" "$(run_lint "$work/normal")"
assert_arg "the bash script reaches shellcheck" "$work/normal/shellcheck.argv" "bin/lint-shell"
# bin/tmux-popup is `#!/bin/sh`, like seven other scripts in bin/. Without one in
# the listing, a pattern tightened to `\bbash\b` would drop all eight from both
# checkers and still pass.
assert_arg "a #!/bin/sh script reaches shellcheck" "$work/normal/shellcheck.argv" "bin/tmux-popup"
assert_arg "and shfmt" "$work/normal/shfmt.argv" "bin/tmux-popup"
assert_arg "the zsh module reaches zsh -n" "$work/normal/zsh.argv" "zsh/alias.zsh"
assert_arg "a zsh-shebang script outside zsh/ reaches zsh -n" "$work/normal/zsh.argv" "bin/init/macos.sh"
refute_arg "and not shellcheck" "$work/normal/shellcheck.argv" "bin/init/macos.sh"
# The entrypoints have no shebang and live outside zsh/, so only their inline
# names put them in front of zsh -n.
assert_arg "the zsh entrypoint .zshrc is always checked" "$work/normal/zsh.argv" ".zshrc"
assert_arg "the zsh entrypoint .zshenv is always checked" "$work/normal/zsh.argv" ".zshenv"
for tool in shellcheck shfmt zsh; do
  refute_arg "a file with no shell shebang reaches no checker ($tool)" "$work/normal/$tool.argv" "README.md"
done

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

# --- zsh never reaches shfmt -------------------------------------------------
# shfmt parses as bash. Handing it a zsh module would reformat constructs it
# cannot represent, so the formatter must be fed the shellcheck target list
# and not a listing of its own (`shfmt -f` does claim *.zsh).
assert_arg "the bash script reaches shfmt" "$work/normal/shfmt.argv" "bin/lint-shell"
refute_arg "no zsh module reaches shfmt" "$work/normal/shfmt.argv" "zsh/alias.zsh"
refute_arg "no zsh-shebang script reaches shfmt" "$work/normal/shfmt.argv" "bin/init/macos.sh"

# --- the formatter defaults to reporting, not rewriting ----------------------
# A lint command that edits the working tree as a side effect of being run is
# a surprise; --write is the opt-in.
assert_arg "the default run asks shfmt for a diff" "$work/normal/shfmt.argv" "-d"
refute_arg "the default run never asks shfmt to rewrite" "$work/normal/shfmt.argv" "-w"
make_stubs "$work/write"
make_git_stub "$work/write" 0 "bin/lint-shell
"
assert_eq "--write exits 0" "0" "$(run_lint "$work/write" --write)"
assert_arg "--write asks shfmt to rewrite" "$work/write/shfmt.argv" "-w"

# --- a finding from any checker fails the run --------------------------------
# The verdict itself: every case above has checkers that always pass, so they
# would stay green if a finding no longer reached the exit status. And the
# other checkers must still run: a failing first checker that skipped the
# formatter would hide a second class of problem until the first was fixed.
for tool in shellcheck shfmt zsh; do
  make_stubs "$work/finding-$tool" "$tool"
  make_git_stub "$work/finding-$tool" 0 "bin/lint-shell
zsh/alias.zsh
"
  assert_nonzero "a $tool finding exits non-zero" "$(run_lint "$work/finding-$tool")"
  for other in shellcheck shfmt zsh; do
    [ "$other" = "$tool" ] && continue
    if [ -s "$work/finding-$tool/$other.argv" ]; then
      ok "with $tool failing, $other still runs"
    else
      fail "with $tool failing, $other still runs" "$other was never called"
    fi
  done
done
assert_contains "a zsh -n failure names the file" "$(cat "$work/finding-zsh/out")" "FAIL zsh/alias.zsh"
assert_nonzero "a finding fails --write too" "$(run_lint "$work/finding-shellcheck" --write)"

# --- splitting shellcheck across jobs changes nothing about what it checks ---
# Most of the run's time is shellcheck, which checks each file on its own, so the
# targets are split across parallel jobs. The split must neither drop nor
# repeat a target, must hand every job the -x -P SCRIPTDIR that makes sourced
# paths resolve, and must not let one job's finding be lost behind another
# job's pass. One job is the baseline the split is compared against.
split_listing="bin/lint-shell
bin/relink
bin/launchd-load
bin/read-doc
bin/fzf-files
"
targets_of() { grep -vxE -- '-x|-P|SCRIPTDIR' "$1" | sort; }
calls_of() { wc -l <"$1" | tr -d ' '; }

make_stubs "$work/one-job"
make_git_stub "$work/one-job" 0 "$split_listing"
assert_eq "one job exits 0" "0" "$(LINT_SHELL_JOBS=1 run_lint "$work/one-job")"
assert_eq "one job runs shellcheck once" "1" "$(calls_of "$work/one-job/shellcheck.calls")"
baseline=$(targets_of "$work/one-job/shellcheck.argv")
first=$(grep -vxE -- '-x|-P|SCRIPTDIR' "$work/one-job/shellcheck.argv" | head -n 1)
last=$(grep -vxE -- '-x|-P|SCRIPTDIR' "$work/one-job/shellcheck.argv" | tail -n 1)

make_stubs "$work/split"
make_git_stub "$work/split" 0 "$split_listing"
assert_eq "a split run exits 0" "0" "$(LINT_SHELL_JOBS=4 run_lint "$work/split")"
ncalls=$(calls_of "$work/split/shellcheck.calls")
# Without this the cases below would compare one invocation against itself.
if [ "$ncalls" -gt 1 ] && [ "$ncalls" -le 4 ]; then
  ok "four jobs split shellcheck into 2..4 invocations ($ncalls)"
else
  fail "four jobs split shellcheck into 2..4 invocations" "got $ncalls"
fi
assert_eq "a split run checks exactly the targets one job does, each once" \
  "$baseline" "$(targets_of "$work/split/shellcheck.argv")"
assert_eq "every job is handed -x" "$ncalls" "$(grep -cxF -- -x "$work/split/shellcheck.argv")"
assert_eq "every job is handed -P SCRIPTDIR" "$ncalls" "$(grep -cxF SCRIPTDIR "$work/split/shellcheck.argv")"

# The report reads as one job's would: the first chunk is held back so it
# finishes last, and must still be printed first. A run printing jobs as they
# finish, or letting them write straight to the terminal, puts it last.
make_stubs "$work/order"
make_git_stub "$work/order" 0 "$split_listing"
assert_eq "a split run with a slow first job exits 0" "0" \
  "$(SLOW_ON=$first LINT_SHELL_JOBS=4 run_lint "$work/order")"
assert_eq "a split run prints exactly what one job does, in the same order" \
  "$(cat "$work/one-job/out")" "$(cat "$work/order/out")"

# The edge where every chunk holds one file. The stub fails when handed no
# files, as the real one does, so an empty job fails this run outright.
make_stubs "$work/many-jobs"
make_git_stub "$work/many-jobs" 0 "$split_listing"
assert_eq "more jobs than targets exits 0, so no job is empty" "0" \
  "$(LINT_SHELL_JOBS=64 run_lint "$work/many-jobs")"
assert_eq "more jobs than targets checks exactly the targets one job does, each once" \
  "$baseline" "$(targets_of "$work/many-jobs/shellcheck.argv")"

# The first and the last target land in different jobs, so between them they
# catch a run that only looks at one job's status. Both of the failing job's
# streams must reach the output: each is held back and replayed.
for target in "$first" "$last"; do
  make_stubs "$work/finding-in-job"
  make_git_stub "$work/finding-in-job" 0 "$split_listing"
  assert_nonzero "a finding in the job checking $target exits non-zero" \
    "$(FAIL_ON=$target LINT_SHELL_JOBS=4 run_lint "$work/finding-in-job")"
  assert_contains "the job checking $target has its stdout shown" \
    "$(cat "$work/finding-in-job/out")" "finding: $target"
  assert_contains "the job checking $target has its stderr shown" \
    "$(cat "$work/finding-in-job/out")" "error: $target"
  rm -rf "$work/finding-in-job"
done

# Rejected by name, before any job starts. An exit status alone would not do:
# both values also crash the chunk arithmetic (division by zero, an unset
# variable under -u), so a run with no validation fails too, for that reason.
for jobs in 0 abc; do
  make_stubs "$work/bad-jobs"
  make_git_stub "$work/bad-jobs" 0 "$split_listing"
  assert_nonzero "LINT_SHELL_JOBS=$jobs is rejected" "$(LINT_SHELL_JOBS=$jobs run_lint "$work/bad-jobs")"
  assert_contains "LINT_SHELL_JOBS=$jobs is named as the reason" \
    "$(cat "$work/bad-jobs/out")" "LINT_SHELL_JOBS must be a positive integer"
  if [ -e "$work/bad-jobs/shellcheck.calls" ]; then
    fail "LINT_SHELL_JOBS=$jobs starts no job" "shellcheck was called"
  else
    ok "LINT_SHELL_JOBS=$jobs starts no job"
  fi
  rm -rf "$work/bad-jobs"
done

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
