#!/bin/bash
#
# assert.test.sh — pins this case's grader, and the Makefile the Swift reference
# documents, without calling the API.
#
# Two things here, and the second is the reason the file exists:
#
# 1. The Makefile is not copied into this test. It is extracted from the ```make
#    block of references/swift.md and has {AppName} substituted, so what runs is
#    the snippet the skill actually tells the scaffold to write. A TAB that
#    became spaces in the documentation, a variable renamed in one place, a
#    `clean` that no longer removes what `build` creates — all of those fail
#    here, in a repository where nothing else can see them.
#
# 2. Every assertion in assert.sh is provoked. A grader is an instrument, and an
#    instrument that cannot fail reports a green eval run that measured nothing:
#    a check-ignore that silently never matches, a regex that stopped matching
#    the real output, a target that is read rather than run. The eval run itself
#    costs money and is non-deterministic, so it is the worst possible place to
#    discover that the grading was inert.
#
# No `claude`, no network, no Xcode: the toolchain is the stub set from
# evals/lib.sh. Written for bash 3.2 (macOS) and run on Linux in CI, so no
# `sed -i` (the BSD and GNU spellings differ) and no mapfile.
set -uo pipefail

cd "$(dirname "$(readlink -f "$0")")" || exit 1
case_dir="$PWD"
repo_root="$(cd "$case_dir/../../../../../.." && pwd)"

fails=0
app="Tonnage"

ok() { printf 'ok   %s\n' "$1"; }
bad() {
  printf 'FAIL %s\n' "$1"
  fails=$((fails + 1))
}

# sed without -i: the in-place flag is spelled differently on BSD and GNU, and
# this test runs on both.
# shellcheck disable=SC2329  # called from the mutation strings, through eval
edit_file() {
  local file="$1" script="$2" tmp
  tmp="$(mktemp)"
  sed "$script" "$file" >"$tmp" && mv "$tmp" "$file"
}

# The reference scaffold: what a correct run of the Swift path leaves behind.
# Everything except the Makefile is the minimum the grader reads; the Makefile
# comes out of the documentation.
build_fixture() {
  local work="$1"
  rm -rf "$work"
  mkdir -p "$work"
  (
    cd "$work" || exit 1
    SKILL_EVAL_LIB_DIR="$repo_root/bin" SKILL_EVAL_REPO_ROOT="$repo_root" \
      bash "$case_dir/scaffold.sh"
    # The runner does this after the scaffold; the fixture's git must not see
    # the harness.
    printf '.claude/\nbin/\n' >>.git/info/exclude

    mkdir -p "$app" "${app}Tests" .claude .github/workflows

    # The Makefile under test, taken from references/swift.md rather than
    # copied. awk over the fence, because the block is the contract.
    awk '/^```make$/ { inside = 1; next } inside && /^```$/ { exit } inside { print }' \
      "$repo_root/root/.agents/skills/init-project/references/swift.md" |
      sed "s/{AppName}/$app/g" >Makefile

    cat >project.yml <<YAML
name: $app
options:
  bundleIdPrefix: local.tonnage
targets:
  $app:
    type: application
    platform: macOS
    sources: [$app]
YAML

    cat >README.md <<'MD'
# tonnage

## Setup

```bash
make generate
```

## Development

```bash
make test
make lint
make format
make build
make clean
```
MD

    cat >CLAUDE.md <<'MD'
# Project: tonnage

## Development

### Setup

```bash
make generate
```

### Test

```bash
make test
make lint
make format
make build
make clean
```
MD

    cat >.gitignore <<MD
.DS_Store
.env*
!.env.example
$app.xcodeproj/
$app/Info.plist
DerivedData/
.build/
MD

    cat >.claude/settings.json <<'JSON'
{
  "permissions": {
    "deny": ["Read(.env)", "Edit(.env)"],
    "allow": [
      "Bash(make generate)",
      "Bash(make build)",
      "Bash(make test)",
      "Bash(make lint)",
      "Bash(make format)",
      "Bash(make clean)"
    ]
  }
}
JSON

    cat >.github/workflows/ci.yml <<'YAML'
jobs:
  ci:
    runs-on: macos-latest
    steps:
      - run: make lint
      - run: make test
YAML

    git add -A
    git commit -q -m "chore: scaffold"
  ) || return 1
}

# The two files the runner normally hands the grader. A clean run denies
# nothing, which is what the fixture stands for.
write_transcript() {
  local dir="$1"
  mkdir -p "$dir"
  printf '{"permission_denials":[]}\n' >"$dir/result.json"
  : >"$dir/transcript.jsonl"
}

run_grader() {
  local work="$1" art="$2"
  (
    cd "$work" || exit 1
    SKILL_EVAL_LIB_DIR="$repo_root/bin" \
      SKILL_EVAL_TRANSCRIPT="$art/transcript.jsonl" \
      SKILL_EVAL_RESULT_FILE="$art/result.json" \
      bash "$case_dir/assert.sh" 2>&1
  )
}

root_dir="$(mktemp -d)"
trap 'rm -rf "$root_dir"' EXIT
art_dir="$root_dir/artifacts"
write_transcript "$art_dir"

# --- the positive control ---
# The documented Makefile runs, and a correct scaffold passes every check. This
# half is what makes the negative controls below mean anything: without it, a
# grader that fails on everything would look perfect.
work="$root_dir/ok"
if ! build_fixture "$work"; then
  printf 'FAIL could not build the reference fixture\n'
  exit 1
fi
out="$(run_grader "$work" "$art_dir")"
grader_status=$?
if [ "$grader_status" -eq 0 ]; then
  ok "the documented Makefile passes every assertion"
else
  bad "the reference scaffold does not pass its own grader"
  printf '%s\n' "$out" | grep '^FAIL' | sed 's/^/       /'
fi
if printf '%s' "$out" | grep -q '^FAIL'; then
  bad "the reference scaffold produced a FAIL line"
fi

# --- the negative controls ---
# expect_fail <label> <the FAIL line that must appear> <mutation>
expect_fail() {
  local label="$1" needle="$2" mutation="$3"
  local mut="$root_dir/mut"
  if ! build_fixture "$mut"; then
    bad "$label (fixture)"
    return
  fi
  (
    cd "$mut" || exit 1
    eval "$mutation"
    git add -A
    git commit -q -m "mutate" --allow-empty
  ) >/dev/null 2>&1
  local mout mstatus=0
  mout="$(run_grader "$mut" "$art_dir")" || mstatus=$?
  if printf '%s' "$mout" | grep -q "FAIL  $needle"; then
    ok "$label"
  else
    bad "$label (expected a FAIL matching: $needle)"
    printf '%s\n' "$mout" | grep '^FAIL' | sed 's/^/       got: /'
  fi
  # The FAIL line is for a human reading assert.log; the *status* is what the
  # runner grades on (`if ! bash assert.sh; then assert_exit=1`). Checking only
  # the text leaves a grader that prints FAIL and exits 0 looking correct here,
  # and every eval case would then report PASS while grading nothing.
  if [ "$mstatus" -ne 0 ]; then
    ok "$label — and the grader exits non-zero"
  else
    bad "$label — the grader printed FAIL but exited 0"
  fi
  rm -rf "$mut"
}

# The TAB. `make -n` is the only thing that sees it, and an editor that expands
# tabs reintroduces it silently.
expect_fail "a space-indented recipe is caught" \
  "make -n build parses the Makefile" \
  "edit_file Makefile 's/^	\$(XCODEBUILD) build/    \$(XCODEBUILD) build/'"

# The dependency that removes "I forgot to run xcodegen".
expect_fail "build that does not depend on generate is caught" \
  "build regenerates the project before compiling" \
  "edit_file Makefile 's/^build: generate/build:/'"

# Drop the flag and build output goes back to ~/Library, where this clean
# cannot reach it.
expect_fail "a shared derived data path is caught" \
  "build output is project-local" \
  "edit_file Makefile 's/ -derivedDataPath \$(DERIVED_DATA)//'"

# The one target that exits 0 while doing nothing.
expect_fail "a clean that deletes nothing is caught" \
  "clean removed the derived data" \
  "edit_file Makefile 's|^	rm -rf .*|	@true|'"

# ... and its opposite, which the ls checks alone cannot see.
expect_fail "a clean that takes out project.yml is caught" \
  "a cleaned tree still builds" \
  "edit_file Makefile 's|^	rm -rf \(.*\)|	rm -rf \1 project.yml|'"

expect_fail "a README still carrying xcodebuild is caught" \
  "no raw xcodebuild is left in the documented commands" \
  "edit_file README.md 's|^make build\$|xcodebuild build -project $app.xcodeproj|'; edit_file CLAUDE.md 's|^make build\$|xcodebuild build -project $app.xcodeproj|'"

expect_fail "README and CLAUDE.md drifting apart is caught" \
  "README.md and CLAUDE.md carry identical command blocks" \
  "edit_file README.md 's|^make clean\$|make cleanup|'"

expect_fail "a wholesale make allow-list is caught" \
  "does not allow make wholesale" \
  "edit_file .claude/settings.json 's|\"Bash(make build)\"|\"Bash(make *)\"|'"

expect_fail "CI spelling out xcodebuild instead is caught" \
  "CI runs make test" \
  "edit_file .github/workflows/ci.yml 's|- run: make test|- run: xcodebuild test|'"

expect_fail "an unignored DerivedData is caught" \
  "the derived data path is gitignored" \
  "edit_file .gitignore 's|^DerivedData/\$||'"

# The throwaway violation file the skill's own Verification creates.
expect_fail "a leftover violation file is caught" \
  "no violation file was committed" \
  "printf 'struct Gate {}\n' > $app/Gate.swift"

expect_fail "a missing Makefile is caught" \
  "wrote a Makefile" \
  "rm -f Makefile"

# --- the two checks that read the result record rather than the tree ---
# expect_fail_with_result <label> <FAIL substring> <result.json> [mutation]
expect_fail_with_result() {
  local label="$1" needle="$2" result="$3" mutation="${4:-}"
  local w="$root_dir/res" art="$root_dir/res-artifacts"
  if ! build_fixture "$w"; then
    bad "$label (fixture)"
    return
  fi
  if [ -n "$mutation" ]; then
    (cd "$w" && eval "$mutation" && git add -A && git commit -q -m "mutate" --allow-empty) >/dev/null 2>&1
  fi
  rm -rf "$art"
  mkdir -p "$art"
  printf '%s\n' "$result" >"$art/result.json"
  : >"$art/transcript.jsonl"
  local rout rstatus=0
  rout="$(run_grader "$w" "$art")" || rstatus=$?
  if printf '%s' "$rout" | grep -q "FAIL  $needle"; then
    ok "$label"
  else
    bad "$label (expected a FAIL matching: $needle)"
    printf '%s\n' "$rout" | grep '^FAIL' | sed 's/^/       got: /'
  fi
  if [ "$rstatus" -ne 0 ]; then
    ok "$label — and the grader exits non-zero"
  else
    bad "$label — the grader printed FAIL but exited 0"
  fi
  rm -rf "$w" "$art"
}

# A refused `make` means the documented targets and the enumerated ones have
# come apart — the failure the first real eval run hit, with `make -n test`.
expect_fail_with_result "a refused make command is caught" \
  "no make command was refused" \
  '{"permission_denials":[{"tool_name":"Bash","tool_input":{"command":"make -n test"}}]}'

# The narrowing has to be real, or this is the blanket denial check under a
# better name — and that one can never pass, since a compound command or a
# `<(…)` is always prompted however the allow-list reads.
work="$root_dir/other-denial"
other_art="$root_dir/other-artifacts"
if build_fixture "$work"; then
  rm -rf "$other_art"
  mkdir -p "$other_art"
  printf '{"permission_denials":[{"tool_name":"Bash","tool_input":{"command":"diff <(sed -n p a) <(sed -n p b)"}}]}\n' \
    >"$other_art/result.json"
  : >"$other_art/transcript.jsonl"
  oout="$(run_grader "$work" "$other_art")"
  if printf '%s' "$oout" | grep -q "PASS  no make command was refused"; then
    ok "a denial that is not a make command is ignored"
  else
    bad "a non-make denial was counted as a make denial"
  fi
fi

# With settings.json absent — the normal state of an eval run, since Claude Code
# will not write that file without an interactive approval — what is left to
# assert is that the run said so. Silence has to fail, or a missing step is
# indistinguishable from a finished one.
expect_fail_with_result "silence about an unwritten settings.json is caught" \
  "reports that .claude/settings.json could not be written" \
  '{"permission_denials":[],"result":"Scaffolded the project."}' \
  "rm -f .claude/settings.json"

# The positive half of that same branch. Without it, a regex that can never
# match would leave the control above passing for the wrong reason — it expects
# a FAIL, and an always-false check produces one.
work="$root_dir/reported"
reported_art="$root_dir/reported-artifacts"
if build_fixture "$work"; then
  (cd "$work" && rm -f .claude/settings.json && git add -A && git commit -q -m "mutate") >/dev/null 2>&1
  rm -rf "$reported_art"
  mkdir -p "$reported_art"
  printf '%s\n' '{"permission_denials":[],"result":"Step 5 could not write .claude/settings.json: it needs an interactive approval. Create it yourself with the allow list below."}' \
    >"$reported_art/result.json"
  : >"$reported_art/transcript.jsonl"
  rout2="$(run_grader "$work" "$reported_art")"
  rstatus2=$?
  if printf '%s' "$rout2" | grep -q "PASS  reports that .claude/settings.json could not be written"; then
    ok "a run that does report the unwritten settings.json passes"
  else
    bad "a run that reports the unwritten settings.json was still failed"
  fi
  if [ "$rstatus2" -eq 0 ]; then
    ok "and the grader exits 0 for it"
  else
    bad "the grader failed a run that met the fallback contract"
    printf '%s\n' "$rout2" | grep '^FAIL' | sed 's/^/       /'
  fi
fi

if [ "$fails" -eq 0 ]; then
  printf '\nall swift-makefile-entry-point grader tests passed\n'
  exit 0
fi
printf '\n%d swift-makefile-entry-point grader test(s) failed\n' "$fails"
exit 1
