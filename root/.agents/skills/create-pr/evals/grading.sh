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
# Moved unchanged from ready-without-pr's grader. Narrower than
# PR_EVAL_GH_CREATE on purpose until decided: widening it to `[;&|(]` would
# change what that grader accepts (`;gh pr view`), so do not align the two in
# passing.
# shellcheck disable=SC2034  # read by the cases that source this file
PR_EVAL_GH_VIEW='(^|[[:space:]])gh[[:space:]]+pr[[:space:]]+view([[:space:]]|$)'
# shellcheck disable=SC2034  # read by the cases that source this file
PR_EVAL_GH_CREATE='(^|[;&|(]|[[:space:]])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'

# The questions this work set out to remove, in the forms runs used. A judge
# reads the closing message as well (pr_eval_check_no_question): a regex
# cannot catch every phrasing, and a judge alone is not deterministic.
# Matched one sentence at a time (pr_eval_asks_nothing), so a report of the
# PR and an unrelated question in the next sentence do not join up: "PR を
# ready にしました。ほかに何か直しますか？" once matched as a whole. Within a
# sentence the gap is still bounded, and `.` counts characters or bytes as the
# locale says. Under LC_ALL=C a Japanese character is three bytes, so the 40
# leaves about 13 characters, and an ordinary question such as "PR
# の説明文とタイトルを書き直して更新しますか？" slips past this regex. That is
# left to the judge on purpose: the runs execute on a developer's UTF-8
# machine, and pinning a UTF-8 locale here would need a name that differs
# between macOS and Linux.
# The ASCII keywords stand as words ([^A-Za-z] on both sides), or "ready" in
# "already" would turn any question into one about the PR. Not [:alpha:]: in
# some locales a Japanese character is a letter, and "PRを" must still count.
# Their plurals count too ("open PRs", "pull requests"), which the boundary
# alone would cut off. しましょうか and いたしますか are covered by ましょうか
# and しますか.
PR_EVAL_ASKS='(((^|[^A-Za-z])(PRs?|push(es)?|drafts?|ready)([^A-Za-z]|$)|プルリク|プッシュ|ドラフト).{0,40}(しますか|ましょうか|よろしいですか))|((Shall|Should) I|Would you like( me)? to|Do you want( me)? to|Want me to).{0,60}[^A-Za-z](push(es)?|PRs?|pull requests?|drafts?|ready)([^A-Za-z]|$)'

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

# pr_eval_opened_through_create_pr
# True when the first `gh pr create` came after create-pr started: the skill
# opened the PR. That create-pr started at all is not enough -- a run can open
# the PR by hand and start the skill afterwards.
pr_eval_opened_through_create_pr() {
  pr_eval_after "$(transcript_first_command_index "$PR_EVAL_GH_CREATE")" "$(pr_eval_skill_index create-pr)"
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

# Stated as one question with pass as its plain answer. Phrased as "passes if
# it asks nothing ... fails if any appears", the judge (haiku) twice returned
# a fail whose own reason concluded the text passed -- once with the verdict
# before the reason, once after. The question and the criterion cover the
# same ground: a step left to the user ("必要なら ready にしてください", a
# `! git push` handed over) is no question, but it is what the user wanted
# gone, and a criterion narrower than the question let the two disagree.
# This sits against root/CLAUDE.md's Permission Denials rule, which asks a
# run whose push was refused to hand it over as `! <command>`. No case here
# refuses a push, and one that did would fail "pushed every commit" anyway;
# a case built on a refused push needs this check left out, not this rubric
# loosened.
# shellcheck disable=SC2034  # read by the cases that source this file
PR_EVAL_NO_QUESTION_RUBRIC='The text is the closing message an agent wrote to its user after a task in a git repository. Question: does the text leave the user free of any step or decision about publishing the work? Publishing means pushing, opening or creating a pull request, updating one, or marking one ready for review. Set pass to false when the text asks the user about any of these ("PR を作成しますか"), offers to do one ("let me know if you want me to push"), or leaves one for the user to do or decide ("必要なら ready にしてください", a command for the user to run). Otherwise set pass to true. Stating that a push, a pull request, an update or a ready happened, or that none was opened and why, leaves nothing to the user.'

# pr_eval_asks_nothing <text>
# True when no sentence of the text matches PR_EVAL_ASKS. A sentence ends at
# 。！？!? or a line break; "." is left alone, since paths and URLs carry it.
pr_eval_asks_nothing() {
  local sentences sentence
  sentences="$(printf '%s\n' "$1" | awk '{ gsub(/。|！|？|!|\?/, "&\n"); print }')"
  while IFS= read -r sentence; do
    if [[ "$sentence" =~ $PR_EVAL_ASKS ]]; then
      printf 'asks: %s\n' "$sentence" >&2
      return 1
    fi
  done <<<"$sentences"
  return 0
}

# pr_eval_check_no_question
# The three ways a run asks: the AskUserQuestion tool, a question in the
# closing message a regex knows, and one only a reader would see.
pr_eval_check_no_question() {
  check_eq "asked nothing through AskUserQuestion" 0 "$(transcript_tool_uses AskUserQuestion)"
  check "the closing message asks nothing about pushing or a PR (known phrasings)" \
    pr_eval_asks_nothing "$(transcript_result_text)"
  check_llm "the closing message leaves no publishing step to the user (judged)" "$PR_EVAL_NO_QUESTION_RUBRIC"
}
