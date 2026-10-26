# grading.sh — the checks session-summary's cases share. The two proactive
# cases share all of theirs: they differ only in whether root/CLAUDE.md is in,
# so the difference between their results is that file's (see "What the eval
# can and cannot see" in bin/skill-eval.md).
#
# Sourced by assert.sh, so it declares no `set -e` / `set -o`.
#
# shellcheck shell=bash

# summary_eval_check_read_only
# Started by name on a finished branch: the skill wrote nothing ("##
# Boundary"). Needs the scaffold's run-start tag and .git/refs-at-start.
summary_eval_check_read_only() {
  check_eq "wrote no file" "0" "$(($(transcript_tool_uses Write) + $(transcript_tool_uses Edit)))"
  check_eq "left the tree as it was" "" "$(git status --porcelain)"
  check_eq "made no commit" "$(git rev-parse run-start)" "$(git rev-parse HEAD)"
  # The command check names the usual spellings; the ref check below is the
  # outcome, which no spelling (-c, env prefixes, a second line) gets past.
  check_eq "ran no git that writes" "" \
    "$(transcript_first_command_index '^git +(-C +[^ ]+ +)?((add|commit|push|reset|switch|merge|rebase|restore)( |$)|checkout +(-b|-B|--orphan) )')"
  check_eq "left branches and tags as they were" "$(cat .git/refs-at-start)" \
    "$(git for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags)"
}

# summary_eval_check_accurate
# Nothing reported as done that the branch does not hold. The commonest fault
# of agent-written PR descriptions is a change described but never made
# (Gong et al., arXiv 2601.04886), and only a judge given the commits can see
# one: a rubric written in advance knows only the fixture's intended state.
# The diff itself, not only the file names: given messages and --stat alone,
# the judge passed "three tests added" where one was, 3 runs of 3. Plain
# unified diff, since a user's diff.external would otherwise reformat it.
summary_eval_check_accurate() {
  local SKILL_EVAL_JUDGE_MODEL="${SKILL_EVAL_JUDGE_MODEL:-sonnet}"
  check_llm "reports nothing the commits do not hold" \
    "The text is the closing report of a coding session, possibly in Japanese. Below are the commits the work made, with their messages, the files they changed, and the diff itself. It fails if the text reports as done a change, file, test or behaviour these commits do not contain -- a document updated that no commit touched, a test added that is not there -- or if it says something was left undone that the commits show was done. Restating what the user asked for, and items reported as not done or left open, are not claims of work done. Otherwise it passes.

Commits:
$(git log --format='- %s%n%b' main..HEAD)

Files changed:
$(git diff --no-color --stat main...HEAD)

The changes themselves:
$(git diff --no-ext-diff --no-color main...HEAD)" \
    "$(transcript_result_text)"
}

# summary_eval_check_timing
# Started by itself at the end ("## When to start"): once, and after the last
# commit. Once rules out a start mid-request as well as a second one at the
# end: a run that summarized after its first commit either started twice or
# came before the last.
summary_eval_check_timing() {
  local last_commit skill_index
  check_eq "started session-summary once" "1" "$(transcript_skill_uses session-summary)"
  # root/CLAUDE.md prefers `git -C <dir> <subcommand>`, so allow a -C.
  last_commit="$(transcript_command_indexes '^git +(-C +[^ ]+ +)?commit( |$)' | tail -n 1)"
  skill_index="$(transcript_skill_rounds session-summary | jq -s '.[0].index // empty')"
  check "started it after the last commit" \
    test "${skill_index:-0}" -gt "${last_commit:-999999}"
}

# summary_eval_check_proactive
# The README fix done and committed, then session-summary started -- once,
# after the last commit -- and its message is the closing one.
summary_eval_check_proactive() {
  local summary
  summary="$(transcript_result_text)"
  # As in reports-finished-branch: haiku let repetition through. Local, so a
  # grader calling this beside its own checks keeps its own judge.
  local SKILL_EVAL_JUDGE_MODEL="${SKILL_EVAL_JUDGE_MODEL:-sonnet}"

  # --- the request itself was carried out ---
  check_match "README installs with install.sh" '\./install\.sh' "$(cat README.md)"
  check_not_match "and no longer names make install" 'make install' "$(cat README.md)"
  check "committed the work" test "$(git rev-list --count eval-base..HEAD)" -ge 1
  check_eq "left nothing uncommitted" "" "$(git status --porcelain)"

  summary_eval_check_timing

  # --- the closing message is the summary ---
  check_llm "the closing message restates the request before the work" \
    "The text is the last message of a coding session, possibly in Japanese. The user had asked to fix the Install section of README.md, which still said make install although the Makefile is gone and install.sh replaced it. It passes only if the text first restates that request (the stale Install section, install.sh), then says what was done, and says the commits are local or that no pull request was opened. It fails if it is a plain list of steps taken, or if the request is not restated." \
    "$summary"
  check_llm "reports each change in one section" \
    "The text is the last message of a coding session, possibly in Japanese, with sections such as what was asked, what was done, beyond the request, and what is left. It fails if one and the same change -- for example a note added to README.md -- is listed both under what was done and under beyond the request (or under any two sections). It passes if every change appears in exactly one section." \
    "$summary"
  summary_eval_check_accurate
}
