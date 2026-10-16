#!/bin/bash
# skill-eval-github.test.sh — the fake GitHub create-pr's and update-pr's eval
# cases run against. Costs nothing: no model, no network.
#
# The stub is an instrument. One that accepts a PR for a branch nobody pushed,
# or exits 0 on a subcommand it never carried out, grades a run as having
# opened a PR that a real gh would have refused -- so each refusal the skills'
# flow depends on is pinned here, beside what the graders read back.
set -eo pipefail

. "$(dirname "$0")/test-lib.sh" || exit 2
lib_dir="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=bin/skill-eval-scaffold.sh
. "$lib_dir/skill-eval-scaffold.sh"
# shellcheck source=bin/skill-eval-github.sh
. "$lib_dir/skill-eval-github.sh"

test_tmpdir
cd "$TEST_TMPDIR"
echo hello >README.md
skill_eval_init_repo
skill_eval_fake_github
# What the runner adds after a scaffold returns.
printf 'bin/\n' >>.git/info/exclude
PATH="$TEST_TMPDIR/bin:$PATH"

assert_eq "origin/HEAD names main, as a clone's does" "origin/main" \
  "$(git rev-parse --abbrev-ref origin/HEAD)"
assert_eq "gh repo view answers the default branch through --jq" "main" \
  "$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)"
assert_eq "the fake origin stays out of git status" "" "$(git status --porcelain)"

assert_status "gh pr view fails while the branch has no PR" 1 gh pr view --json number
assert_contains "and says so as gh does" "$(gh pr view 2>&1 || true)" "no pull requests found"
assert_status "gh pr create refuses the default branch" 1 gh pr create --title t --body b

git switch -q -c feat/x
echo more >>README.md
git commit -q -am "docs: more"
assert_status "gh pr create refuses a branch nobody pushed" 1 gh pr create --title t --body b
assert_eq "and leaves no PR behind" "" "$(fake_github_pr)"

git push -q -u origin HEAD
assert_eq "fake_github_remote_head reads what was pushed" "$(git rev-parse HEAD)" \
  "$(fake_github_remote_head feat/x)"
assert_eq "and is empty for a branch never pushed" "" "$(fake_github_remote_head nope)"

out="$(
  gh pr create --draft --title "docs: more" --body-file - <<'BODY'
## Summary
with `backticks` and $dollars
BODY
)"
assert_eq "gh pr create prints the PR URL" "$SKILL_EVAL_FAKE_PR_URL" "$out"
pr="$(fake_github_pr)"
assert_eq "the PR keeps the title" "docs: more" "$(jq -r .title <<<"$pr")"
# shellcheck disable=SC2016  # the literal body is the point
assert_eq "and the body from stdin, literally" '## Summary
with `backticks` and $dollars' "$(jq -r .body <<<"$pr")"
assert_eq "and is a draft" "true true" "$(jq -r '"\(.isDraft) \(.createdAsDraft)"' <<<"$pr")"
assert_eq "fake_github_pr reads it by branch name too" "feat/x" "$(fake_github_pr feat/x | jq -r .headRefName)"
assert_status "a second PR for the same branch is refused" 1 gh pr create --title t --body b
assert_eq "gh pr view --json answers isDraft" "true" "$(gh pr view --json isDraft -q .isDraft)"

gh pr edit --title "docs: much more" --body-file - <<<"new body" >/dev/null
pr="$(fake_github_pr)"
assert_eq "gh pr edit rewrites title and body, and counts the edit" "docs: much more|new body|1" \
  "$(jq -r '"\(.title)|\(.body)|\(.edits)"' <<<"$pr")"
gh pr edit --title "docs: only title" >/dev/null
assert_eq "an edit without a body leaves the body" "new body" "$(fake_github_pr | jq -r .body)"

gh pr ready >/dev/null
assert_eq "gh pr ready marks it ready, and counts it" "false 1 true" \
  "$(fake_github_pr | jq -r '"\(.isDraft) \(.readied) \(.createdAsDraft)"')"

assert_status "a subcommand the stub does not know fails" 1 gh pr merge
assert_contains "and names itself as the stub" "$(gh pr merge 2>&1 || true)" "is not stubbed"
assert_contains "every call is logged" "$(fake_github_calls)" \
  "gh pr create --draft --title docs:\\ more --body-file -"

git switch -q main
git switch -q -c feat/seeded
git commit -q --allow-empty -m "feat: seeded"
skill_eval_fake_pr "feat: seeded" "old body" true
assert_eq "skill_eval_fake_pr opens a draft gh can see" "true" "$(gh pr view --json isDraft -q .isDraft)"
assert_eq "and pushes the branch it belongs to" "$(git rev-parse HEAD)" "$(fake_github_remote_head feat/seeded)"
assert_eq "without touching the other branch's PR" "docs: only title" "$(fake_github_pr feat/x | jq -r .title)"

test_summary
