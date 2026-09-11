# lib.sh — the fixture the review-test eval cases share.
#
# A small shell module that reads a weight written the way a weighbridge ticket
# writes it ("12.5t") and returns tonnes. The implementation is the same in
# every case; what changes per case is which test file ships with it, which is
# the thing under review.
#
# The fixture is shell rather than TypeScript because this repository is shell,
# and because a shell fixture needs no package install: the tests really run,
# with nothing stubbed. The cost is that there is no coverage tool, so Phase 4
# of the skill has nothing to collect here -- see bin/skill-eval.md.
#
# Sourced, so it declares no `set -e` / `set -o`.
#
# shellcheck shell=bash

# review_test_fixture_init
# Writes the module and the test runner. The case adds its own test file (or
# none at all) and then calls skill_eval_init_repo.
review_test_fixture_init() {
  mkdir -p lib

  cat >lib/quantity.sh <<'QUANTITY'
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
  if [ -z "$normalized" ]; then
    printf 'invalid quantity: %s\n' "$input" >&2
    return 1
  fi
  # Leading `-` is not matched, so a negative weight is refused here rather
  # than compared numerically afterwards.
  if ! printf '%s' "$normalized" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
    printf 'invalid quantity: %s\n' "$input" >&2
    return 1
  fi
  printf '%s\n' "$normalized"
}

# sum_quantities [<input>...]
# Print the total of every argument, in tonnes. No arguments is 0.
# If any one of them is refused by parse_quantity, the total is refused too:
# status 1, nothing on stdout. A partial sum is never printed.
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
QUANTITY

  cat >run-tests.sh <<'RUNNER'
#!/bin/bash
# Run every test file in lib/. Exits non-zero if any of them fails.
set -uo pipefail

cd "$(dirname "$0")" || exit 1

status=0
found=0
for t in lib/*.test.sh; do
  [ -f "$t" ] || continue
  found=1
  printf -- '--- %s\n' "$t"
  if ! bash "$t"; then
    status=1
  fi
done

if [ "$found" -eq 0 ]; then
  printf 'no test files under lib/\n' >&2
  exit 1
fi

exit "$status"
RUNNER
  chmod +x run-tests.sh
}

# review_test_write_happy_path_test
# Tests that exercise the success path only. Nothing here touches the error
# contract parse_quantity documents, the empty-list case, or the promise that a
# partial sum is never printed -- the gaps the review is expected to find.
review_test_write_happy_path_test() {
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
t "sums two weights" "3" "$(sum_quantities '1t' '2t')"

exit "$fails"
TEST
}

# review_test_write_thorough_test
# Tests that cover the whole documented contract: both success paths, the
# refusals with their status and stderr, the boundaries, and the promise that
# sum_quantities prints no partial total. A review of these should find no P1,
# and a run that reports one is the false positive this case exists to catch.
review_test_write_thorough_test() {
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

# --- parse_quantity: what it accepts ---
t "parses a plain number" "12.5" "$(parse_quantity '12.5')"
t "drops the trailing unit" "12.5" "$(parse_quantity '12.5t')"
t "drops an upper-case unit" "12.5" "$(parse_quantity '12.5T')"
t "ignores surrounding whitespace" "12.5" "$(parse_quantity '  12.5t  ')"
t "accepts zero" "0" "$(parse_quantity '0')"

# --- parse_quantity: what it refuses, and how ---
refusal_status() {
  parse_quantity "$1" >/dev/null 2>&1
  printf '%s' "$?"
}
refusal_stdout() {
  parse_quantity "$1" 2>/dev/null
}
t "refuses the empty string" "1" "$(refusal_status '')"
t "refuses whitespace alone" "1" "$(refusal_status '   ')"
t "refuses a non-number" "1" "$(refusal_status 'twelve')"
t "refuses a negative weight" "1" "$(refusal_status '-1t')"
t "prints nothing on stdout when it refuses" "" "$(refusal_stdout 'twelve')"
t "explains the refusal on stderr" "invalid quantity: twelve" "$(parse_quantity 'twelve' 2>&1 >/dev/null)"

# --- sum_quantities ---
t "sums two weights" "3" "$(sum_quantities '1t' '2t')"
t "sums a single weight" "1.5" "$(sum_quantities '1.5t')"
t "an empty list is zero" "0" "$(sum_quantities)"

sum_status() {
  sum_quantities "$@" >/dev/null 2>&1
  printf '%s' "$?"
}
t "refuses the whole sum when one element is invalid" "1" "$(sum_status '1t' 'twelve' '2t')"
t "prints no partial total when it refuses" "" "$(sum_quantities '1t' 'twelve' 2>/dev/null)"

exit "$fails"
TEST
}
