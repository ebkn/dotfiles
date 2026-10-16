# grading.sh — what create-pr's and update-pr's eval cases read off a run the
# same way: where the commits fall, when each PR skill started, what the fake
# GitHub holds, and whether the user was asked anything about pushing or PRs.
#
# Sourced by a case's assert.sh after bin/skill-eval-assert.sh and
# bin/skill-eval-github.sh. update-pr's cases source it from here. Sourced, so
# it declares no `set -e` / `set -o`.
#
# shellcheck shell=bash

# A git commit, wherever it sits in a command line (as review-design's
# graders spell it). `commit-tree` and a path containing "commit" do not match.
PR_EVAL_GIT_COMMIT='(^|[;&|(]|[[:space:]])git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+)*[[:space:]]+commit([[:space:]]|$)'
PR_EVAL_GH_CREATE='(^|[;&|(]|[[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'

# The questions this work set out to remove, in the forms runs used. A judge
# reads the closing message as well (pr_eval_check_no_question): a regex
# cannot catch every phrasing, and a judge alone is not deterministic.
# Matched with bash's =~, whose `.` also crosses lines: the gap is kept short
# instead, so a report of a push and an unrelated question further on do not
# join up.
PR_EVAL_ASKS='((PR|プルリク|プッシュ|push|ドラフト|draft|ready).{0,40}(しますか|しましょうか|ましょうか|いたしますか|よろしいですか))|((Shall|Should) I|Would you like( me)? to|Do you want( me)? to|Want me to).{0,60}(push|PR|pull request|draft|ready)'

# pr_eval_skill_index <skill>
# Record index of the skill's first call; empty when it never started.
pr_eval_skill_index() {
  transcript_skill_rounds "$1" | jq -s '.[0].index // empty'
}

# pr_eval_skill_last_index <skill>
pr_eval_skill_last_index() {
  transcript_skill_rounds "$1" | jq -s '.[-1].index // empty'
}

# pr_eval_commit_indexes
# Record index of every git commit the run made, one per line.
pr_eval_commit_indexes() {
  transcript_command_indexes "$PR_EVAL_GIT_COMMIT"
}

# pr_eval_between <index> <after> <before>
# True when <after> < <index> < <before>, all non-empty.
pr_eval_between() {
  [ -n "$1" ] && [ -n "$2" ] && [ -n "$3" ] && [ "$1" -gt "$2" ] && [ "$1" -lt "$3" ]
}

# pr_eval_after <index> <after>
pr_eval_after() {
  [ -n "$1" ] && [ -n "$2" ] && [ "$1" -gt "$2" ]
}

# pr_eval_field <jq path>
# A field of the current branch's PR, or "none" when there is no PR.
pr_eval_field() {
  local pr
  pr="$(fake_github_pr)"
  if [ -z "$pr" ]; then
    echo none
    return 0
  fi
  jq -r "$1" <<<"$pr"
}

# pr_eval_pushed_head
# True when origin holds the branch at HEAD: nothing committed was left behind.
pr_eval_pushed_head() {
  [ "$(fake_github_remote_head "$(git rev-parse --abbrev-ref HEAD)")" = "$(git rev-parse HEAD)" ]
}

# shellcheck disable=SC2034  # read by the cases that source this file
PR_EVAL_NO_QUESTION_RUBRIC='The text is the closing message an agent wrote to its user after doing a task in a git repository. It passes if it asks the user nothing about publishing the work: not whether to push, not whether to open or create a pull request, not whether to update one, not whether to mark one ready for review -- and makes no offer to do any of these later ("let me know if you want me to push", "PR を作成しますか"). Reporting that a push happened, that a pull request was opened, updated or marked ready, or that none was opened and why, is fine. It fails if any such question or offer appears.'

# pr_eval_check_no_question
# The three ways a run asks: the AskUserQuestion tool, a question in the
# closing message a regex knows, and one only a reader would see.
pr_eval_check_no_question() {
  check_eq "asked nothing through AskUserQuestion" 0 "$(transcript_tool_uses AskUserQuestion)"
  check_not_match "the closing message asks nothing about pushing or a PR (known phrasings)" \
    "$PR_EVAL_ASKS" "$(transcript_result_text)"
  check_llm "the closing message asks nothing about pushing or a PR (judged)" "$PR_EVAL_NO_QUESTION_RUBRIC"
}
