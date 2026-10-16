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
# A local path here read as "no GitHub origin", and a run rightly published
# nothing.
assert_eq "origin's URL is a GitHub one, as git remote shows it" \
  "origin	git@github.com:example/fixture.git (push)" "$(git remote -v | tail -n 1)"
assert_eq "and git reaches it through the ssh stub" "$(git rev-parse main)" \
  "$(git ls-remote origin refs/heads/main | cut -f 1)"
assert_status "the ssh stub runs nothing but git's own transfer commands" 1 bin/ssh git@github.com "rm -rf /"

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
assert_eq "gh pr list --head finds it, as a run checking for an open PR asks" "1" \
  "$(gh pr list --head feat/x --json number -q '.[].number')"
assert_eq "and lists nothing for another head" "[]" "$(gh pr list --head other --json number)"
assert_eq "or for closed PRs" "[]" "$(gh pr list --state closed --json number)"
assert_contains "without --json it prints a row" "$(gh pr list)" "feat/x	DRAFT"

gh pr edit --title "docs: much more" --body-file - <<<"new body" >/dev/null
pr="$(fake_github_pr)"
assert_eq "gh pr edit rewrites title and body, and counts the edit" "docs: much more|new body|1" \
  "$(jq -r '"\(.title)|\(.body)|\(.edits)"' <<<"$pr")"
gh pr edit --title "docs: only title" >/dev/null
assert_eq "an edit without a body leaves the body" "new body" "$(fake_github_pr | jq -r .body)"

printf 'from a file\n' >"$TEST_TMPDIR/body.md"
gh pr edit -t "docs: short flags" --body-file "$TEST_TMPDIR/body.md" >/dev/null
assert_eq "gh pr edit takes -t, and --body-file from a path" "docs: short flags|from a file" \
  "$(fake_github_pr | jq -r '"\(.title)|\(.body)"')"
gh pr edit -b "inline body" >/dev/null
assert_eq "and -b inline" "inline body" "$(fake_github_pr | jq -r .body)"
gh pr edit --title="docs: equals form" --body=x=y >/dev/null
assert_eq "and --flag=value, splitting at the first =" "docs: equals form|x=y" \
  "$(fake_github_pr | jq -r '"\(.title)|\(.body)"')"
assert_status "a flag the stub does not know fails" 1 gh pr edit --fill
assert_contains "and names itself as the stub" "$(gh pr edit --fill 2>&1 || true)" "flag --fill is not stubbed"
assert_eq "leaving the PR as it was" "docs: equals form" "$(fake_github_pr | jq -r .title)"
gh pr edit --title "docs: only title" >/dev/null
assert_contains "gh pr view without --json prints it for a reader" "$(gh pr view)" "draft:	true"

gh pr ready >/dev/null
assert_eq "gh pr ready marks it ready, and counts it" "false 1 true" \
  "$(fake_github_pr | jq -r '"\(.isDraft) \(.readied) \(.createdAsDraft)"')"
gh pr ready --undo >/dev/null
assert_eq "gh pr ready --undo makes it a draft again, without counting" "true 1" \
  "$(fake_github_pr | jq -r '"\(.isDraft) \(.readied)"')"
gh pr ready >/dev/null

assert_status "a subcommand the stub does not know fails" 1 gh pr merge
assert_contains "and names itself as the stub" "$(gh pr merge 2>&1 || true)" "is not stubbed"
assert_contains "every call is logged" "$(fake_github_calls)" \
  "gh pr create --draft --title docs:\\ more --body-file -"

git switch -q main
git switch -q -c feat/no-pr
assert_status "gh pr edit fails on a branch with no PR" 1 gh pr edit --title t
assert_status "and so does gh pr ready" 1 gh pr ready
assert_eq "and neither makes one" "" "$(fake_github_pr)"

git switch -q main
git switch -q -c feat/seeded
git commit -q --allow-empty -m "feat: seeded"
skill_eval_fake_pr "feat: seeded" "old body" true
assert_eq "the scaffold's own gh call is not left as the run's" "" "$(fake_github_calls)"
assert_eq "skill_eval_fake_pr opens a draft gh can see" "true" "$(gh pr view --json isDraft -q .isDraft)"
assert_eq "and pushes the branch it belongs to" "$(git rev-parse HEAD)" "$(fake_github_remote_head feat/seeded)"
# The graders read .edits and .readied off a seeded PR; a record of another
# shape would make them read null.
assert_eq "a seeded PR has the fields of one a run opens" \
  "$(fake_github_pr feat/x | jq -c 'keys')" "$(fake_github_pr | jq -c 'keys')"
assert_eq "without touching the other branch's PR" "docs: only title" "$(fake_github_pr feat/x | jq -r .title)"

test_summary
