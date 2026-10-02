# lib.sh — the fixture the review-design eval cases share.
#
# A weighbridge module and the command that totals its tickets, each with the
# documentation a real repository keeps beside its code: a comment on every
# function, a usage text, a README. On `main` every one of them tells the
# truth. A case then makes one unit of work on a feature branch and commits it,
# tagged `unit-done`. That unit is what the review is asked about, and
# `unit-done..HEAD` is what the review's caller did afterwards.
#
# Kept out of bin/: the runner excludes bin/ from git for a scaffold's stubs,
# so fixture code there would be invisible to `git status`.
#
# Sourced, so it declares no `set -e` / `set -o`.
#
# shellcheck shell=bash

# The module is assembled from parts so that a case can change the code of
# sum_quantities while leaving its comment as it was -- the drift a review is
# expected to catch -- without restating the rest of the file.
_review_design_module_head() {
  cat <<'PART'
# quantity.sh -- read the weights on a weighbridge ticket.
#
# shellcheck shell=bash

# parse_quantity <input>
# Print <input> as a number of tonnes.
# Surrounding whitespace and one trailing unit `t` (either case) are ignored,
# so "12.5t", " 12.5 " and "12.5" all read as 12.5.
# Input that is empty, not a number, or negative is refused: the message goes
# to stderr and the status is 1, with nothing on stdout.
parse_quantity() {
  local input="$1"
  local normalized
  normalized="$(printf '%s' "$input" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[tT]$//')"
  if ! printf '%s' "$normalized" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
    printf 'invalid quantity: %s\n' "$input" >&2
    return 1
  fi
  printf '%s\n' "$normalized"
}

PART
}

_review_design_sum_doc_refusing() {
  cat <<'PART'
# sum_quantities [<input>...]
# Print the total of every argument, in tonnes. No arguments is 0.
# If any one of them is refused by parse_quantity, the total is refused too:
# status 1, nothing on stdout. A partial sum is never printed.
PART
}

_review_design_sum_code_refusing() {
  cat <<'PART'
sum_quantities() {
  local total=0 input value
  for input in "$@"; do
    if ! value="$(parse_quantity "$input")"; then
      return 1
    fi
    total="$(awk -v a="$total" -v b="$value" 'BEGIN { printf "%g", a + b }')"
  done
  printf '%s\n' "$total"
}
PART
}

_review_design_sum_code_skipping() {
  cat <<'PART'
sum_quantities() {
  local total=0 input value
  for input in "$@"; do
    if ! value="$(parse_quantity "$input" 2>/dev/null)"; then
      printf 'skipped: %s\n' "$input" >&2
      continue
    fi
    total="$(awk -v a="$total" -v b="$value" 'BEGIN { printf "%g", a + b }')"
  done
  printf '%s\n' "$total"
}
PART
}

_review_design_write_tests_refusing() {
  cat >lib/quantity.test.sh <<'TEST'
#!/bin/bash
# Tests for lib/quantity.sh
set -uo pipefail

# shellcheck source=./quantity.sh
. "$(dirname "$0")/quantity.sh"

fails=0
t() {
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}

t "parses a plain number" "12.5" "$(parse_quantity '12.5')"
t "drops the trailing unit" "12.5" "$(parse_quantity '12.5t')"
t "ignores surrounding whitespace" "12.5" "$(parse_quantity ' 12.5t ')"
t "refuses a non-number" "1" "$(parse_quantity 'twelve' >/dev/null 2>&1; printf '%s' "$?")"
t "sums the weights" "15.5" "$(sum_quantities '12.5t' '3t')"
t "an empty list is zero" "0" "$(sum_quantities)"
t "refuses the total when one weight is unreadable" "1" "$(sum_quantities '12.5t' 'twelve' >/dev/null 2>&1; printf '%s' "$?")"
t "prints no partial total when it refuses" "" "$(sum_quantities '12.5t' 'twelve' 2>/dev/null)"

exit "$fails"
TEST

  cat >total.test.sh <<'TEST'
#!/bin/bash
# Tests for total.sh
set -uo pipefail

cd "$(dirname "$0")" || exit 1

fails=0
t() {
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}

t "prints the total" "15.5" "$(./total.sh 12.5t 3t)"
t "--help exits 0" "0" "$(./total.sh --help >/dev/null 2>&1; printf '%s' "$?")"
t "an unreadable weight fails the total" "1" "$(./total.sh 12.5t twelve >/dev/null 2>&1; printf '%s' "$?")"
t "prints nothing when the total fails" "" "$(./total.sh 12.5t twelve 2>/dev/null)"

exit "$fails"
TEST
}

_review_design_write_tests_skipping() {
  cat >lib/quantity.test.sh <<'TEST'
#!/bin/bash
# Tests for lib/quantity.sh
set -uo pipefail

# shellcheck source=./quantity.sh
. "$(dirname "$0")/quantity.sh"

fails=0
t() {
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}

t "parses a plain number" "12.5" "$(parse_quantity '12.5')"
t "drops the trailing unit" "12.5" "$(parse_quantity '12.5t')"
t "ignores surrounding whitespace" "12.5" "$(parse_quantity ' 12.5t ')"
t "refuses a non-number" "1" "$(parse_quantity 'twelve' >/dev/null 2>&1; printf '%s' "$?")"
t "sums the weights" "15.5" "$(sum_quantities '12.5t' '3t')"
t "an empty list is zero" "0" "$(sum_quantities)"
t "skips an unreadable weight and totals the rest" "12.5" "$(sum_quantities '12.5t' 'twelve' 2>/dev/null)"
t "names the skipped weight on stderr" "skipped: twelve" "$(sum_quantities '12.5t' 'twelve' 2>&1 >/dev/null)"
t "still succeeds when it skips" "0" "$(sum_quantities '12.5t' 'twelve' >/dev/null 2>&1; printf '%s' "$?")"

exit "$fails"
TEST

  cat >total.test.sh <<'TEST'
#!/bin/bash
# Tests for total.sh
set -uo pipefail

cd "$(dirname "$0")" || exit 1

fails=0
t() {
  if [ "$2" = "$3" ]; then
    printf 'ok   %s\n' "$1"
  else
    printf 'FAIL %s\n       expected: %s\n       actual:   %s\n' "$1" "$2" "$3"
    fails=$((fails + 1))
  fi
}

t "prints the total" "15.5" "$(./total.sh 12.5t 3t)"
t "--help exits 0" "0" "$(./total.sh --help >/dev/null 2>&1; printf '%s' "$?")"
t "skips an unreadable weight" "12.5" "$(./total.sh 12.5t twelve 2>/dev/null)"
t "names the skipped weight on stderr" "skipped: twelve" "$(./total.sh 12.5t twelve 2>&1 >/dev/null)"
t "still exits 0 when it skips" "0" "$(./total.sh 12.5t twelve >/dev/null 2>&1; printf '%s' "$?")"

exit "$fails"
TEST
}

# total.sh and the README are assembled the same way as the module: each takes
# the name of a function that prints its one paragraph on unreadable weights,
# so a case can swap that paragraph and keep the rest.

# _review_design_write_command <part>
_review_design_write_command() {
  {
    cat <<'PART'
#!/bin/bash
# total.sh -- print the total weight of the weighbridge tickets given as
# arguments.
set -eo pipefail

# shellcheck source=lib/quantity.sh
. "$(dirname "$0")/lib/quantity.sh"

usage() {
  cat <<'USAGE'
usage: total.sh <weight>...

Print the total of the weights, in tonnes. A weight is a number with an
optional trailing "t", such as 12.5t.

PART
    "$1"
    cat <<'PART'
USAGE
}

case "${1:-}" in
  -h | --help)
    usage
    exit 0
    ;;
esac

sum_quantities "$@"
PART
  } >total.sh
  chmod +x total.sh
}

_review_design_usage_refusing() {
  cat <<'PART'
If any weight cannot be read, nothing is printed and the exit status is 1.
PART
}

# _review_design_write_readme <part>
_review_design_write_readme() {
  {
    cat <<'PART'
# weighbridge

`total.sh` adds up the weights printed on a stack of weighbridge tickets.

    ./total.sh 12.5t 3t      # prints 15.5

A weight is a number of tonnes with an optional trailing `t`.

## Unreadable weights

PART
    "$1"
  } >README.md
}

_review_design_readme_refusing() {
  cat <<'PART'
A weight that cannot be read -- empty, not a number, or negative -- fails the
whole total: `total.sh` prints nothing and exits 1,
so a wrong total never reaches the ledger.
PART
}

# review_design_fixture_init
# Writes the base state -- the module, the command, their docs and tests, and
# the test runner -- with every doc true of the code. Call skill_eval_init_repo
# afterwards to commit it on main.
review_design_fixture_init() {
  mkdir -p lib
  {
    _review_design_module_head
    _review_design_sum_doc_refusing
    _review_design_sum_code_refusing
  } >lib/quantity.sh
  _review_design_write_command _review_design_usage_refusing
  _review_design_write_readme _review_design_readme_refusing
  _review_design_write_tests_refusing

  cat >run-tests.sh <<'RUNNER'
#!/bin/bash
# Run every test file. Exits non-zero if any of them fails.
set -uo pipefail

cd "$(dirname "$0")" || exit 1

status=0
for t in lib/*.test.sh ./*.test.sh; do
  [ -f "$t" ] || continue
  printf -- '--- %s\n' "$t"
  if ! bash "$t"; then
    status=1
  fi
done

exit "$status"
RUNNER
  chmod +x run-tests.sh
}

# review_design_begin_unit <branch>
# Starts the unit of work on its own branch, so the review finds its range the
# way it would in a real repository: from the merge-base with main.
review_design_begin_unit() {
  git checkout -q -b "$1"
}

# review_design_commit_unit <subject> <body>
# Commits the unit and tags it `unit-done`, so a case can ask for exactly what
# the review's caller did afterwards with `unit-done..HEAD`.
review_design_commit_unit() {
  git add -A
  git commit -q -m "$1" -m "$2"
  git tag unit-done
}

# review_design_unit_skip_without_docs
# The unit for stale-doc-after-change: sum_quantities now skips a weight it
# cannot read instead of refusing the whole total, and the tests say so -- but
# its comment, total.sh's usage text and the README still describe the
# refusal. Three docs, each now false, none of them touched by the commit.
review_design_unit_skip_without_docs() {
  {
    _review_design_module_head
    _review_design_sum_doc_refusing
    _review_design_sum_code_skipping
  } >lib/quantity.sh
  _review_design_write_tests_skipping
}
