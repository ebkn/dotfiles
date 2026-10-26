#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"
# shellcheck source=../grading.sh
source "$SKILL_EVAL_REPO_ROOT/root/.agents/skills/session-summary/evals/grading.sh"

summary="$(transcript_result_text)"
# haiku passed repetition it had itself called "borderline"; the message
# rubrics here need a stricter reader. An explicit setting still wins.
SKILL_EVAL_JUDGE_MODEL="${SKILL_EVAL_JUDGE_MODEL:-sonnet}"

check_eq "started session-summary once" "1" "$(transcript_skill_uses session-summary)"

summary_eval_check_read_only

# --- facts from the repository, not from main ---
# CHANGELOG.md landed on main after the branch split off. A two-dot diff
# lists it as removed by this branch; the merge-base diff does not.
check_not_match "reports nothing from main (CHANGELOG.md)" 'CHANGELOG' "$summary"
check_match "names the interface as written" '--json' "$summary"

# --- the sections ("## The message") ---
check_llm "opens with the request, its goal and the change of direction" \
  "The text is a closing report for finished work, possibly in Japanese. It passes only if, before describing what was done, it restates what the user asked: JSON output from tally.sh, the goal of passing the result to other tools, and the user's mid-way decision to use a --json flag instead of --format=json. Each may be given inside a quotation of the user's words -- a quoted request that says why counts as stating the goal. It fails if any of the three is missing or if the restatement comes after the description of the work." \
  "$summary"
check_llm "keeps the unrequested fix apart from the request" \
  "The text is a closing report for finished work, possibly in Japanese. The work included one change the user did not ask for: tally.sh now exits with a usage error when no file is given (it used to hang reading stdin). It passes only if the text presents that change as not requested -- in a section or line set apart from what was asked for, or explicitly labelled as beyond the request. It fails if the change is missing or listed as if it had been part of the request." \
  "$summary"
check_llm "shows the interface a reviewer needs" \
  "The text is a closing report for finished work, possibly in Japanese. It passes only if it shows how to call the new --json flag of tally.sh or what its output looks like (the JSON shape with files, path, lines and total), so that a reviewer can check the interface without opening the code. It fails if it only says that a --json flag was added." \
  "$summary"
check_llm "says what is left and that there is no PR" \
  "The text is a closing report for finished work, possibly in Japanese. It passes only if it ends with a section on what is left for the user that says at least that the commits are local or that there is no pull request. It fails if nothing tells the user what state the work was left in." \
  "$summary"
check_llm "keeps to what a reviewer needs" \
  "The text is a closing report for finished work, possibly in Japanese. Its format is fixed: it must first restate what the user asked (that section is required, not a recap to cut), then what was done, what went beyond the request, how it is built, and what is left. Judge only these: no preamble or closing pleasantries, no step-by-step narration of the commands that were run, no section that only says there is nothing to report, and roughly 40 lines or fewer, code blocks included. It fails on any of these." \
  "$summary"

# Concision, as the passing runs actually broke it -- each named, because a
# general "no repetition" rubric passed all of them. The flag decision, the
# limitations and the step-like lines are the ones this fixture provokes.
check_llm "states the flag decision once" \
  "The text is a closing report for finished work, possibly in Japanese, in sections: the request, what was done, beyond the request, how it is built, what is left. The user's decision to use --json rather than --format=json belongs to the request section. It fails if any later section states that decision again -- for example 'the flag is --json', 'I made it --json', '--format=json was not implemented', 'a single switch rather than a format option'. Showing --json in a usage line, a command or an output example is not stating the decision, and passes." \
  "$summary"
check_llm "puts every limitation under what is left, once" \
  "The text is a closing report for finished work, possibly in Japanese, in sections: the request, what was done, beyond the request, how it is built, what is left (the last section). A limitation is anything that does not work, is not handled, was not run or not verified -- for example characters a path may not contain, tests not run. How the interface is called -- which argument comes first, the usage line -- is the interface, not a limitation, and belongs to how it is built. It fails if a limitation is described in any section other than the last, including one the last section then refers back to. It also fails if one point -- a limitation or a rule of the interface -- appears both in how it is built and in the last section. A change listed as done or beyond the request, with what it stops from working stated in the last section, is two points, not one: that passes. Otherwise it passes." \
  "$summary"
check_llm "lists outcomes as what was done" \
  "The text is a closing report for finished work, possibly in Japanese. Look only at its section on what was done (the second section). It passes only if each item there states what now works or holds for the user -- a behaviour, a command, a test that now exists. It fails if any item there instead records a decision already given in the request section, a commit hash, a count of files, or the state of the working tree." \
  "$summary"
summary_eval_check_accurate

skill_eval_finish
