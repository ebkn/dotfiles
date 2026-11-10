#!/bin/bash
#
# The no-fire-small-fix fixture with a second, independent non-interface bug
# grafted next to it: format_size's MB branch divides by 1000 where its
# comment says 1024 KB to the MB. The base tests cover neither bug, so both
# fixes leave the suite green; the prompt asks for the two fixes as two
# commits inside one request. Call order matters: bug 1 through the lib
# helper (the pair's fixture), bug 2 written fresh here.
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-scaffold.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-scaffold.sh"
# shellcheck source=../lib.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design/evals/lib.sh"

review_design_fixture_init
review_design_plant_upper_case_bug

# The second bug, written straight: comment promises 1024, code divides 1000.
cat >lib/size.sh <<'SIZE'
#!/bin/bash
# format_size <bytes> — human-readable size. 1 KB = 1024 B, 1 MB = 1024 KB.
format_size() {
  awk -v b="$1" 'BEGIN {
    if (b < 1024) { printf "%d B\n", b; exit }
    if (b < 1024 * 1024) { printf "%.1f KB\n", b / 1024; exit }
    printf "%.1f MB\n", b / 1000 / 1000
  }'
}
SIZE
cat >lib/size.test.sh <<'TEST'
#!/bin/bash
set -uo pipefail
. "$(dirname "$0")/size.sh"
t() {
  local expect=$1 input=$2 got
  got=$(format_size "$input")
  if [ "$got" = "$expect" ]; then
    echo "ok - $input -> $expect"
  else
    echo "FAIL - $input: $expect, $got"
    exit 1
  fi
}
t "9 B" "9" "9 B"
t "1.0 KB" "1024" "1.0 KB"
TEST
chmod +x lib/size.test.sh

skill_eval_init_repo
review_design_begin_unit fix/case-and-unit
