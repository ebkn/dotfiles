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

_review_design_sum_doc_skipping() {
  cat <<'PART'
# sum_quantities [<input>...]
# Print the total of every argument, in tonnes. No arguments is 0.
# An argument parse_quantity refuses is skipped: it is named on stderr as
# "skipped: <input>" and left out of the total, and the status stays 0. So if
# none can be read, the total is 0.
PART
}

# The skipping code once more, this time saying why parse_quantity's own
# message is dropped -- the missing why a review of the bare version raises.
_review_design_sum_code_skipping_explained() {
  cat <<'PART'
sum_quantities() {
  local total=0 input value
  for input in "$@"; do
    # parse_quantity's own message is dropped so that each skipped weight is
    # reported once, in the one form a caller can look for.
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

_review_design_usage_skipping() {
  cat <<'PART'
A weight that cannot be read is skipped: it is named on stderr as
"skipped: <weight>", the rest are totalled, and the exit status is 0.
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

_review_design_readme_skipping() {
  cat <<'PART'
A weight that cannot be read -- empty, not a number, or negative -- is
skipped: `total.sh` names it on stderr as `skipped: <weight>` and totals the
rest, exiting 0. If none can be read the total is 0, so check stderr before a
total goes into the ledger.
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

# review_design_plant_upper_case_bug
# For no-fire-small-fix: parse_quantity drops only a lower-case `t`, though
# its comment promises either case -- a one-character bug that none of the
# base's tests reach. Call it before skill_eval_init_repo, so the bug is part
# of main. A literal replacement through awk's index(), since the pattern is
# itself a sed expression full of characters sed would read as syntax.
review_design_plant_upper_case_bug() {
  awk '{ i = index($0, "[tT]$"); if (i) $0 = substr($0, 1, i - 1) "t$" substr($0, i + 5) } 1' \
    lib/quantity.sh >lib/quantity.sh.new
  mv lib/quantity.sh.new lib/quantity.sh
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

# review_design_unit_incidental_forwarder
# The unit for pass-through-layer: a feature -- delivery.sh totals the weights
# listed in a file -- that picks up a forwarder on the way. delivery_sum only
# calls sum_quantities with the same arguments, and nothing about the feature
# asked for it. Its one caller is in the unit, so removing it reaches nothing
# outside and undoes nothing anyone decided.
review_design_unit_incidental_forwarder() {
  cat >lib/delivery.sh <<'PART'
# delivery.sh -- total the weighbridge tickets of one delivery.
#
# shellcheck shell=bash

# shellcheck source=quantity.sh
. "$(dirname "${BASH_SOURCE[0]}")/quantity.sh"

# delivery_total <file>
# Print the total of the weights listed in <file>, one per line, in tonnes.
# Blank lines are ignored. If any weight cannot be read, the total is refused
# the way sum_quantities refuses it.
delivery_total() {
  local line weights=()
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    weights+=("$line")
  done <"$1"
  delivery_sum "${weights[@]}"
}

# delivery_sum <input>...
# Total the weights of a delivery. See sum_quantities.
delivery_sum() {
  sum_quantities "$@"
}
PART

  cat >delivery.sh <<'PART'
#!/bin/bash
# delivery.sh -- print the total weight of one delivery's tickets, read from a
# file with one weight per line.
set -eo pipefail

# shellcheck source=lib/delivery.sh
. "$(dirname "$0")/lib/delivery.sh"

if [ $# -ne 1 ]; then
  printf 'usage: delivery.sh <file>\n' >&2
  exit 2
fi

delivery_total "$1"
PART
  chmod +x delivery.sh

  cat >delivery.test.sh <<'TEST'
#!/bin/bash
# Tests for delivery.sh
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

list="$(mktemp)"
trap 'rm -f "$list"' EXIT

printf '12.5t\n3t\n\n' >"$list"
t "totals the weights listed in the file" "15.5" "$(./delivery.sh "$list")"
printf '12.5t\ntwelve\n' >"$list"
t "an unreadable weight fails the total" "1" "$(./delivery.sh "$list" >/dev/null 2>&1; printf '%s' "$?")"
t "prints nothing when the total fails" "" "$(./delivery.sh "$list" 2>/dev/null)"
t "asks for exactly one file" "2" "$(./delivery.sh >/dev/null 2>&1; printf '%s' "$?")"

exit "$fails"
TEST

  cat >>README.md <<'PART'

## A whole delivery

    ./delivery.sh tickets.txt      # one weight per line

`delivery.sh` totals the weights listed in a file, one per line; blank lines
are ignored. An unreadable weight fails the total the same way it does for
`total.sh`.
PART
}

# review_design_unit_intended_layer
# The unit for intended-layer-asks: a "ticket API" in lib/ticket.sh, meant --
# says the commit -- to keep the scripts from depending on how quantity.sh
# reads a weight. Its two functions forward to quantity.sh under new names with
# the same arguments, the same output and the same refusals, so it hides
# nothing, and total.sh is switched over to it. The layer is shallow, but it is
# what the commit set out to build: removing it undoes a decision.
review_design_unit_intended_layer() {
  cat >lib/ticket.sh <<'PART'
# ticket.sh -- the weighbridge ticket API.
#
# shellcheck shell=bash

# shellcheck source=quantity.sh
. "$(dirname "${BASH_SOURCE[0]}")/quantity.sh"

# ticket_weight <input>
# Read one weight off a ticket. See parse_quantity.
ticket_weight() {
  parse_quantity "$@"
}

# ticket_total <input>...
# Total the weights on a stack of tickets. See sum_quantities.
ticket_total() {
  sum_quantities "$@"
}
PART

  # total.sh keeps its own text; only what it sources and calls moves to the
  # new layer. Through a temporary file rather than `sed -i`, which BSD and GNU
  # spell differently.
  # shellcheck disable=SC2016  # the $(...) is total.sh's own text, matched literally
  sed -e 's|^# shellcheck source=lib/quantity.sh$|# shellcheck source=lib/ticket.sh|' \
    -e 's|^\. "$(dirname "$0")/lib/quantity.sh"$|. "$(dirname "$0")/lib/ticket.sh"|' \
    -e 's|^sum_quantities "\$@"$|ticket_total "$@"|' \
    total.sh >total.sh.new
  mv total.sh.new total.sh
  chmod +x total.sh
}

# Line-level edits for units that change only a line or two of a file the base
# wrote. Exact-line matching through awk rather than sed, so nothing in the line
# is read as a pattern; -v expands "\n", which is how one line becomes two.
_review_design_replace_line() { # <file> <exact line> <replacement>
  awk -v at="$2" -v with="$3" '$0 == at { print with; next } { print }' "$1" >"$1.new"
  mv "$1.new" "$1"
}
_review_design_insert_after() { # <file> <exact line> <new line>
  awk -v at="$2" -v add="$3" '{ print } $0 == at { print add }' "$1" >"$1.new"
  mv "$1.new" "$1"
}
_review_design_insert_before() { # <file> <exact line> <new line>
  awk -v at="$2" -v add="$3" '$0 == at { print add } { print }' "$1" >"$1.new"
  mv "$1.new" "$1"
}

# _review_design_replace_line_raw <file> <exact line> <replacement>
# The same as _review_design_replace_line, with both strings taken verbatim
# through the environment: -v would turn a backslash the replacement means
# literally -- the \n inside a printf format -- into a real newline.
_review_design_replace_line_raw() {
  AT="$2" WITH="$3" awk '$0 == ENVIRON["AT"] { print ENVIRON["WITH"]; next } { print }' "$1" >"$1.new"
  mv "$1.new" "$1"
}

# review_design_unit_unit_suffix_twice
# The unit for next-change-scattered: every total is now printed with its unit,
# and a new delivery.sh totals a delivery from a file -- each script writing
# the "t" itself. Nothing wrong with that as it stands; but the next change,
# stated in the case's prompt rather than here, is a kg output, which would
# have to edit both. Both scripts are in the unit, so pulling the formatting
# into one place reaches nothing outside.
review_design_unit_unit_suffix_twice() {
  # shellcheck disable=SC2016  # these are total.sh's own lines, written literally
  _review_design_replace_line_raw total.sh 'sum_quantities "$@"' \
    "$(printf '%s\n%s' 'total="$(sum_quantities "$@")"' "printf '%st\\n' \"\$total\"")"
  _review_design_insert_after total.sh 'optional trailing "t", such as 12.5t.' \
    'The total is printed with its unit, as in "15.5t".'
  chmod +x total.sh

  cat >delivery.sh <<'PART'
#!/bin/bash
# delivery.sh -- print the total weight of one delivery's tickets, read from a
# file with one weight per line, with its unit.
set -eo pipefail

# shellcheck source=lib/quantity.sh
. "$(dirname "$0")/lib/quantity.sh"

if [ $# -ne 1 ]; then
  printf 'usage: delivery.sh <file>\n' >&2
  exit 2
fi

weights=()
while IFS= read -r line || [ -n "$line" ]; do
  [ -n "$line" ] || continue
  weights+=("$line")
done <"$1"

total="$(sum_quantities "${weights[@]}")"
printf '%st\n' "$total"
PART
  chmod +x delivery.sh

  cat >delivery.test.sh <<'TEST'
#!/bin/bash
# Tests for delivery.sh
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

list="$(mktemp)"
trap 'rm -f "$list"' EXIT

printf '12.5t\n3t\n\n' >"$list"
t "totals the weights listed in the file, with the unit" "15.5t" "$(./delivery.sh "$list")"
printf '12.5t\ntwelve\n' >"$list"
t "an unreadable weight fails the total" "1" "$(./delivery.sh "$list" >/dev/null 2>&1; printf '%s' "$?")"
t "asks for exactly one file" "2" "$(./delivery.sh >/dev/null 2>&1; printf '%s' "$?")"

exit "$fails"
TEST

  # shellcheck disable=SC2016  # test lines, expanded when the tests run
  _review_design_replace_line total.test.sh 't "prints the total" "15.5" "$(./total.sh 12.5t 3t)"' \
    't "prints the total with its unit" "15.5t" "$(./total.sh 12.5t 3t)"'
  _review_design_replace_line README.md '    ./total.sh 12.5t 3t      # prints 15.5' \
    '    ./total.sh 12.5t 3t      # prints 15.5t'
  cat >>README.md <<'PART'

## A whole delivery

    ./delivery.sh tickets.txt      # one weight per line; prints 15.5t

`delivery.sh` totals the weights listed in a file, one per line, and prints the
total with its unit, as `total.sh` does.
PART
}

# review_design_unit_clock_inside
# The unit for hidden-clock-no-seam: total.sh stamps each total with the day it
# was weighed, through a new stamp_total that reads the clock itself. Nothing
# can hand it a date, so the tests can only recompute today and compare -- and
# would fail across midnight. The docs and tests moved with the code: the one
# thing wrong is the missing seam. Its callers are all in the unit.
review_design_unit_clock_inside() {
  cat >>lib/quantity.sh <<'PART'

# stamp_total <total>
# Print <total> as a ticket line: the total in tonnes and the day it was
# weighed, as in "15.5t on 2026-10-02".
stamp_total() {
  printf '%st on %s\n' "$1" "$(date +%F)"
}
PART

  # shellcheck disable=SC2016  # these are total.sh's own lines, written literally
  _review_design_replace_line total.sh 'sum_quantities "$@"' \
    'total="$(sum_quantities "$@")"\nstamp_total "$total"'
  _review_design_insert_after total.sh 'optional trailing "t", such as 12.5t.' \
    'The total is stamped with the day it was weighed: "15.5t on 2026-10-02".'
  chmod +x total.sh
  _review_design_replace_line README.md '    ./total.sh 12.5t 3t      # prints 15.5' \
    '    ./total.sh 12.5t 3t      # prints 15.5t on the day it was weighed'

  # shellcheck disable=SC2016  # test lines, expanded when the tests run
  _review_design_replace_line total.test.sh 't "prints the total" "15.5" "$(./total.sh 12.5t 3t)"' \
    't "prints the total, stamped with today" "15.5t on $(date +%F)" "$(./total.sh 12.5t 3t)"'
  # shellcheck disable=SC2016  # test lines, expanded when the tests run
  _review_design_insert_before lib/quantity.test.sh 'exit "$fails"' \
    't "stamps a total with today" "15.5t on $(date +%F)" "$(stamp_total 15.5)"'
}

# review_design_unit_skip_with_docs
# The unit for clean-unit-no-false-p1: the same change, done properly. The
# comment, the usage text and the README all move with the code, the case of
# nothing readable is stated rather than left open, and the one non-obvious
# line says why. A review of this has nothing that meets P1.
review_design_unit_skip_with_docs() {
  {
    _review_design_module_head
    _review_design_sum_doc_skipping
    _review_design_sum_code_skipping_explained
  } >lib/quantity.sh
  _review_design_write_command _review_design_usage_skipping
  _review_design_write_readme _review_design_readme_skipping
  _review_design_write_tests_skipping
}
