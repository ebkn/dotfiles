#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/review-design-doc/evals/grading.sh"

doc=docs/design/webhook-retry.md
doc_re='(^|/)docs/design/webhook-retry\.md$'

# --- the request itself was carried out ---
check "wrote $doc" test -f "$doc"
check "wrote it in Japanese" rdd_has_kana "$(cat "$doc" 2>/dev/null)"
# Committed or not: proactive-with-claude-md brings in a CLAUDE.md that
# commits at a breakpoint, and this grader is shared.
check_eq "changed nothing but the doc" "$doc" "$(rdd_changed_paths)"

# --- starting unasked, at the breakpoint ---
check "started review-design-doc on the doc it wrote" test "$(transcript_skill_uses review-design-doc)" -ge 1
check "started it after writing the doc" rdd_started_after_writing "$doc_re"

# --- the loop: fix P1 and P2, review again, stop on a clean round ---
# Whether the first round finds anything depends on the doc this run wrote,
# so two rounds are not required -- only the shared loop checks.
review_loop_checks review-design-doc
check_llm "reaches a conclusion about P1 and P2" \
  'The text is the final answer to a request to write a design document. It passes if it says one of these about the P1 *and* P2 findings of the design doc review: that there were none, that they were fixed, or which ones are left and why. It fails if it only reports that the doc was written, or if it asks the reader whether to fix the findings instead of having fixed them.' \
  "$(rdd_report)"

# --- a fix is not an invented decision ---
# The notes say nothing about how the change is released or turned back
# (lib.sh). A fix that wrote a staged rollout into the doc as settled would be
# a decision nobody made; naming it as open is the fix the notes allow, and
# the user is the one to settle it.
check_llm "kept the release plan an open decision in the doc" \
  'The text is a design document. It passes if how the change is released to customers or rolled back is either absent or marked as undecided -- an open question, a proposal awaiting a decision, or a TBD. It fails if it states a release plan or rollback procedure (a staged rollout, a feature flag, percentages, a kill switch) as already decided.' \
  "$(cat "$doc" 2>/dev/null)"
check_llm "told the user the release plan is theirs to decide" \
  'The text is the final answer to a request to write a design document. It passes only if it tells the reader that how the change is released or rolled back is still undecided and needs their decision.' \
  "$(rdd_report)"

# --- the doc's language, and its prose handed to lint-docs ---
# The review's own report, as the fork returned it: the caller's summary may
# follow a CLAUDE.md that asks for English, and that is not the review's.
rdd_check_language ja "$(rdd_last_round_report)"
rdd_check_lint ja

skill_eval_finish
