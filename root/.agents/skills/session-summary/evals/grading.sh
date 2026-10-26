# grading.sh — the grader the two proactive cases share. They differ only in
# whether root/CLAUDE.md is in, so the difference between their results is
# that file's (see "What the eval can and cannot see" in bin/skill-eval.md).
#
# Sourced by assert.sh, so it declares no `set -e` / `set -o`.
#
# shellcheck shell=bash

# summary_eval_check_proactive
# The README fix done and committed, then session-summary started -- once,
# after the last commit -- and its message is the closing one.
summary_eval_check_proactive() {
  local summary last_commit skill_index
  summary="$(transcript_result_text)"

  # --- the request itself was carried out ---
  check_match "README installs with install.sh" '\./install\.sh' "$(cat README.md)"
  check_not_match "and no longer names make install" 'make install' "$(cat README.md)"
  check "committed the work" test "$(git rev-list --count eval-base..HEAD)" -ge 1
  check_eq "left nothing uncommitted" "" "$(git status --porcelain)"

  # --- starting by itself ("## When to start") ---
  check_eq "started session-summary once" "1" "$(transcript_skill_uses session-summary)"
  # root/CLAUDE.md prefers `git -C <dir> <subcommand>`, so allow a -C.
  last_commit="$(transcript_command_indexes '^git +(-C +[^ ]+ +)?commit( |$)' | tail -n 1)"
  skill_index="$(transcript_skill_rounds session-summary | jq -s '.[0].index // empty')"
  check "started it after the last commit" \
    test "${skill_index:-0}" -gt "${last_commit:-999999}"

  # --- the closing message is the summary ---
  check_llm "the closing message restates the request before the work" \
    "The text is the last message of a coding session, possibly in Japanese. The user had asked to fix the Install section of README.md, which still said make install although the Makefile is gone and install.sh replaced it. It passes only if the text first restates that request (the stale Install section, install.sh), then says what was done, and says the commits are local or that no pull request was opened. It fails if it is a plain list of steps taken, or if the request is not restated." \
    "$summary"
}
