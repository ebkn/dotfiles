#!/bin/bash
#
# What this case measures: whether the Swift path's Makefile really is the one
# entry point, or only says so. The three failure modes it separates are all
# silent -- a Makefile that exists but does not run, a README whose commands no
# longer match the Makefile, and an allow-list that opened `make` wholesale.
#
# The targets are *run*, against the stubs in bin/. A Makefile can be read and
# look right while `make build` dies on a space-indented recipe or a variable
# that expands to nothing, and `clean` is the one target that exits 0 when it
# does nothing at all.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"

# The runner prepends the fixture's bin/ for `claude -p`, not for the grader.
# Without this the stubs are invisible here and `make build` would reach for a
# real Xcode.
export PATH="$PWD/bin:$PATH"

app="Tonnage"
calls="bin/calls.log"

# --- the file exists and is part of the project ---
check "wrote a Makefile" test -f Makefile
check "committed the scaffold" test "$(git rev-list --count eval-base..HEAD)" -ge 1
check "the Makefile is tracked" git ls-files --error-unmatch Makefile

if [ ! -f Makefile ]; then
  # Everything below runs the Makefile; without one there is nothing to grade
  # and every remaining check would fail for the same single reason.
  printf 'FAIL  no Makefile: skipping the behavioural checks\n'
  exit 1
fi

# --- it parses, and build regenerates before it builds ---
# `make -n` is the parse: a space-indented recipe fails here, before anything
# runs. The ordering in its output is the dependency that removes the
# "forgot to run xcodegen" failure the Swift path warns about.
dry_run_status=0
dry_run="$(make -n build 2>&1)" || dry_run_status=$?
check_eq "make -n build parses the Makefile" 0 "$dry_run_status"
check_match "build regenerates the project before compiling" \
  'xcodegen generate.*xcodebuild' "$dry_run"

# --- the targets actually run ---
: >"$calls"
build_status=0
make build >bin/make-build.log 2>&1 || build_status=$?
check_eq "make build succeeds" 0 "$build_status"
check "make build generated the project" test -d "$app.xcodeproj"
check "build output is project-local" test -d DerivedData

build_line="$(grep '^xcodebuild .*[[:space:]]build\([[:space:]]\|$\)' "$calls" | tail -n 1 || true)"
check_match "build passes the project-local derived data path" \
  '\-derivedDataPath DerivedData' "$build_line"
# Signing stays on for `build`: this is the target that verifies the .app can
# actually launch locally, which is the half `test` deliberately does not cover.
check_not_match "build keeps signing on" 'CODE_SIGNING_ALLOWED=NO' "$build_line"

test_status=0
make test >bin/make-test.log 2>&1 || test_status=$?
check_eq "make test succeeds" 0 "$test_status"
test_line="$(grep '^xcodebuild .*[[:space:]]test\([[:space:]]\|$\)' "$calls" | tail -n 1 || true)"
check_match "test runs unsigned, the way CI does" \
  'CODE_SIGNING_ALLOWED=NO' "$test_line"

lint_status=0
make lint >bin/make-lint.log 2>&1 || lint_status=$?
check_eq "make lint succeeds" 0 "$lint_status"
check_match "lint runs swift format" 'swift format lint' "$(cat "$calls")"
check_match "lint runs swiftlint" 'swiftlint' "$(cat "$calls")"

# --- clean, which is the target that can do nothing and still exit 0 ---
clean_status=0
make clean >bin/make-clean.log 2>&1 || clean_status=$?
check_eq "make clean succeeds" 0 "$clean_status"
check "clean removed the derived data" test ! -d DerivedData
check "clean removed the generated project" test ! -d "$app.xcodeproj"
# The positive control. A `clean` that also took out project.yml or a source
# directory passes both checks above and fails here.
rebuild_status=0
make build >bin/make-rebuild.log 2>&1 || rebuild_status=$?
check_eq "a cleaned tree still builds" 0 "$rebuild_status"
make clean >/dev/null 2>&1 || true

# --- the documented commands are the Makefile's ---
# shellcheck disable=SC2016  # the fence is literal text, not a variable
readme_blocks="$(sed -n '/^```bash$/,/^```$/p' README.md 2>/dev/null || true)"
# shellcheck disable=SC2016  # as above
claude_blocks="$(sed -n '/^```bash$/,/^```$/p' CLAUDE.md 2>/dev/null || true)"
check_eq "README.md and CLAUDE.md carry identical command blocks" \
  "$readme_blocks" "$claude_blocks"
for target in build test lint clean; do
  check_match "the documented commands include make $target" \
    "make $target" "$readme_blocks"
done
# The whole point of the Makefile: the long invocation lives in one file. A
# README still carrying it is the drift this change exists to prevent.
check_not_match "no raw xcodebuild is left in the documented commands" \
  'xcodebuild' "$readme_blocks"

# --- the allow-list is enumerated, not wildcarded ---
# Conditional, and the condition is not laziness: `.claude/settings.json` is
# special-cased by Claude Code and cannot be written without an interactive
# approval, which a `claude -p` run does not have. So in an eval run the file is
# normally absent, and what is left to assert is the fallback contract -- that
# the run said so rather than reporting a finished scaffold. Where the file does
# exist (a host that allowed the write, or this case's own grader test), the
# real assertions run.
if [ -f .claude/settings.json ]; then
  allow="$(jq -r '.permissions.allow[]?' .claude/settings.json 2>/dev/null || true)"
  check_match "allow-lists make build" 'Bash\(make build\)' "$allow"
  check_match "allow-lists make test" 'Bash\(make test\)' "$allow"
  # `Bash(make *)` would pre-approve every target the Makefile ever grows,
  # including the signing and notarization ones this path keeps prompted.
  check_not_match "does not allow make wholesale" 'Bash\(make \*\)' "$allow"
else
  check_match "reports that .claude/settings.json could not be written" \
    'settings\.json' "$(transcript_result_text)"
fi

# --- CI calls the same targets ---
ci="$(cat .github/workflows/*.yml 2>/dev/null || true)"
check_match "CI runs make lint" 'make lint' "$ci"
check_match "CI runs make test" 'make test' "$ci"

# --- generated output stays out of the repo ---
check "the derived data path is gitignored" git check-ignore -q DerivedData/
check "the generated project is gitignored" git check-ignore -q "$app.xcodeproj/"

# --- nothing was left behind ---
# The skill's Verification provokes each gate with a throwaway violation file
# and deletes it again. One left in the tree ships in the initial commit.
check_eq "left a clean working tree" "" "$(git status --porcelain)"
check_eq "no violation file was committed" "" "$(git ls-files '*Gate.swift')"

# Narrowed to `make`, deliberately. A blanket "no denials" cannot hold and would
# make the case permanently red: Claude Code always prompts for a compound
# command or one containing `$(…)` / `<(…)`, whatever the allow-list says, and a
# model phrases commands however it likes. What *is* the skill's business is
# whether the targets it documents are the targets it allowed -- the failure
# this narrow check caught on the first run was `make -n test`, refused because
# only `make -n build` had been enumerated.
denied_make="$(jq '[.permission_denials[]? | .tool_input.command? // ""
                    | select(test("(^|[^[:alnum:]_-])make[[:space:]]"))]
                   | length' "$SKILL_EVAL_RESULT_FILE")"
check_eq "no make command was refused" 0 "$denied_make"

skill_eval_finish
