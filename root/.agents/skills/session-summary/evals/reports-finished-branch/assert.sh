#!/bin/bash
set -eo pipefail

# shellcheck source=../../../../../../bin/skill-eval-assert.sh
source "$SKILL_EVAL_LIB_DIR/skill-eval-assert.sh"

summary="$(transcript_result_text)"

check_eq "started session-summary once" "1" "$(transcript_skill_uses session-summary)"

# --- reading only ("## Boundary") ---
check_eq "wrote no file" "0" "$(($(transcript_tool_uses Write) + $(transcript_tool_uses Edit)))"
check_eq "left the tree as it was" "" "$(git status --porcelain)"
check_eq "made no commit" "$(git rev-parse run-start)" "$(git rev-parse HEAD)"
# The command check names the usual spellings; the ref check below is the
# outcome, which no spelling (-c, env prefixes, a second line) gets past.
check_eq "ran no git that writes" "" \
  "$(transcript_first_command_index '^git +(-C +[^ ]+ +)?((add|commit|push|reset|switch|merge|rebase|restore)( |$)|checkout +(-b|-B|--orphan) )')"
check_eq "left branches and tags as they were" "$(cat .git/refs-at-start)" \
  "$(git for-each-ref --format='%(refname) %(objectname)' refs/heads refs/tags)"

# --- facts from the repository, not from main ---
# CHANGELOG.md landed on main after the branch split off. A two-dot diff
# lists it as removed by this branch; the merge-base diff does not.
check_not_match "reports nothing from main (CHANGELOG.md)" 'CHANGELOG' "$summary"
check_match "names the interface as written" '--json' "$summary"

# --- the sections ("## The message") ---
check_llm "opens with the request, its goal and the change of direction" \
  "The text is a closing report for finished work, possibly in Japanese. It passes only if, before describing what was done, it restates what the user asked: JSON output from tally.sh, the goal of passing the result to other tools, and the user's mid-way decision to use a --json flag instead of --format=json. It fails if any of the three is missing or if the restatement comes after the description of the work." \
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
  "The text is a closing report for finished work, possibly in Japanese. Its format is fixed: it must first restate what the user asked (that section is required, not a recap to cut), then what was done, what went beyond the request, how it is built (the interface, which may repeat a flag named earlier), and what is left. Judge only whether it is concise within that format: no preamble or closing pleasantries, no step-by-step narration of the commands that were run, no section that only says there is nothing to report, and no explanation written out twice in full (naming the same flag, file or usage line in several sections, or adding a detail in a later section, is not repetition). Roughly 40 lines or fewer, code blocks included. It fails on any of these." \
  "$summary"

skill_eval_finish
