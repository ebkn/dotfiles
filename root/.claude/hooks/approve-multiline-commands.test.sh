#!/bin/bash
# Exercises approve-multiline-commands.sh, the one hook here that emits "allow".
# ALLOW = hook approves the command outright. DEFER = hook stays silent, so the
# normal permission flow (allow/ask/deny rules, then the auto-mode classifier)
# decides it.
#
# The DEFER half is what actually matters. An over-approval here is silent by
# construction -- the command simply runs -- so every case below that ends in a
# non-git segment exists to prove the parser cannot be talked past. The ALLOW
# half is the counterweight: without it, "defer on everything" would pass.
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/approve-multiline-commands.sh"

pass=0
fail=0

check() {
  local expect=$1 label=$2 cmd=$3 out got
  out=$(printf '%s' "$cmd" | jq -Rs '{tool_name:"Bash", tool_input:{command:.}}' |
    "$HOOK" 2>/dev/null)
  if printf '%s' "$out" | grep -q '"permissionDecision": *"allow"'; then
    got=ALLOW
  else
    got=DEFER
  fi
  if [[ "$got" == "$expect" ]]; then
    pass=$((pass + 1))
    printf '  ok   %-5s %s\n' "$got" "$label"
  else
    fail=$((fail + 1))
    printf '  FAIL want=%s got=%s  %s\n' "$expect" "$got" "$label"
  fi
}

# The forms the commit / create-pr / update-pr skills actually emit.
COMMIT_HEREDOC="git commit -F - <<'COMMIT_MSG_EOF'
feat(scope): subject

Body explaining why.
COMMIT_MSG_EOF"

PR_HEREDOC="gh pr create --title \"a title\" --body-file - <<'PR_BODY_EOF'
## Summary

- a point
PR_BODY_EOF"

echo "-- must ALLOW (the workflows this hook exists for) --"
check ALLOW 'commit skill heredoc' "$COMMIT_HEREDOC"
check ALLOW 'create-pr skill heredoc' "$PR_HEREDOC"
check ALLOW 'gh pr edit heredoc' "gh pr edit --title \"t\" --body-file - <<'PR_BODY_EOF'
body
PR_BODY_EOF"
check ALLOW 'add chained with &&' "git add zsh/git.zsh && $COMMIT_HEREDOC"
check ALLOW 'add on its own line' "git add zsh/git.zsh
$COMMIT_HEREDOC"
check ALLOW 'push then create pr' "git push -u origin HEAD && $PR_HEREDOC"
check ALLOW 'quoted multiline -m' 'git commit -m "feat: subject

Body explaining why."'
check ALLOW 'quoted multiline -m, single quotes' "git commit -m 'feat: subject

Body.'"
check ALLOW 'git -C worktree' "git -C /tmp/wt commit -F - <<'EOF'
msg

more
EOF"
check ALLOW 'bare git push after commit' "$COMMIT_HEREDOC
git push"
check ALLOW 'option fused to its value' 'git commit -m"feat: subject

Body."'
check ALLOW 'multiple heredocs are data' "gh pr create --title \"t\" --body-file - <<'B'
line one
line two
B"

echo "-- heredoc bodies are data, not commands --"
check ALLOW 'body containing a shell command' "$(printf "git commit -F - <<'EOF'\nfix: x\n\nRan \`rm -rf /tmp/x\` locally.\nEOF")"
check ALLOW 'body containing a quoted-tag substitution' "$(printf "git commit -F - <<'EOF'\nfix: x\n\nUse \$(date) here.\nEOF")"
check ALLOW 'body containing a near-miss terminator' "$(printf "git commit -F - <<'EOF'\nfix: x\n\nEOFISH is not the tag\nEOF")"
check ALLOW 'message quoting a heredoc opener' "$(printf "git commit -m \"fix: x\n\nUse <<'EOF' in the skill.\"")"
check ALLOW 'message containing a hash' "$(printf "git commit -m \"fix: x\n\nCloses #123 # still data\"")"

echo "-- a large body stays well inside the 5s hook timeout --"
# Scanning quoted text one character at a time is O(n^2): a 1500-line message
# took 25s before the run-based scanner, and a hook that times out is killed,
# so the only symptom is an unexplained permission prompt on long messages.
# The bound is deliberately loose (this takes ~0.1s here) so a slow CI runner
# cannot make it flake -- it exists to catch a return to quadratic, not to
# measure anything.
BIG_BODY=$(
  i=1
  while ((i <= 300)); do
    echo "line $i of the body, with prose"
    i=$((i + 1))
  done
)
start=$SECONDS
check ALLOW '300-line heredoc body' "git commit -F - <<'EOF'
fix: x

$BIG_BODY
EOF"
check ALLOW '300-line quoted message' "git commit -m \"fix: x

$BIG_BODY\""
elapsed=$((SECONDS - start))
if ((elapsed < 5)); then
  pass=$((pass + 1))
  printf '  ok   %-5s large bodies scanned in %ds\n' 'PERF' "$elapsed"
else
  fail=$((fail + 1))
  printf '  FAIL large bodies took %ds; the scanner has gone quadratic again\n' "$elapsed"
fi

echo "-- must DEFER: the reported bypass and its family --"
check DEFER 'reported bypass (comment carries the token)' "git status
rm -rf ~/important # git commit -m x"
check DEFER 'trailing statement after the heredoc' "$COMMIT_HEREDOC
rm -rf /tmp/x"
check DEFER 'statement between add and commit' "git add .
rm -rf /tmp/x
git commit -m \"a

b\""
check DEFER 'unapproved segment after ;' "git commit -m \"a

b\"; bash /tmp/x.sh"
check DEFER 'unapproved segment via pipe' 'git commit -m "a

b" | tee /tmp/x'
check DEFER 'leading unapproved segment' 'echo hi
git commit -m "a

b"'
check DEFER 'commit token only inside a message' 'echo "git commit -m x

y" && bash /tmp/x.sh'
check DEFER 'trailing comment' 'git commit -m "a

b" # rm -rf /tmp/x'

echo "-- must DEFER: newlines that are not data (rule 3) --"
check DEFER 'several read-only statements' 'git status
git log --oneline -5'
check DEFER 'add then single-line commit' 'git add .
git commit -m "fix: x"'

echo "-- must DEFER: expansion makes the real argv unknowable --"
# The single quotes are the point: these cases must reach the hook with the
# expansion intact, exactly as Claude Code would send it.
# shellcheck disable=SC2016
check DEFER 'command substitution in -m' 'git commit -m "$(cat msg)

x"'
# shellcheck disable=SC2016
check DEFER 'backtick in -m' 'git commit -m "a

`whoami`"'
check DEFER 'unquoted heredoc tag' "git commit -F - <<EOF
fix: x

\$(rm -rf /tmp/x)
EOF"
check DEFER 'here-string' 'git commit -F - <<<"a

b"'
check DEFER 'unterminated heredoc' "git commit -F - <<'EOF'
fix: x

no terminator"
check DEFER 'unterminated quote' 'git commit -m "fix: x

'
check DEFER 'output redirection' 'git commit -m "a

b" > /tmp/out'
check DEFER 'subshell' 'git commit -m "a

b" && (rm -rf /tmp/x)'

echo "-- must DEFER: git invocations outside the safelist --"
check DEFER 'dangerous global option' "git -c core.fsmonitor=/tmp/x.sh commit -F - <<'EOF'
msg

x
EOF"
check DEFER 'exec-path global option' "git --exec-path=/tmp commit -F - <<'EOF'
msg

x
EOF"
check DEFER 'git commit --amend' "git commit --amend -F - <<'EOF'
msg

x
EOF"
check DEFER 'git commit with no message flag' "git commit -a
git commit -m \"a

b\""
check DEFER 'git push --force' 'git push --force
git commit -m "a

b"'
check DEFER 'git push origin main' 'git push origin main && git commit -m "a

b"'
check DEFER 'git checkout (an ask rule)' 'git checkout main && git commit -m "a

b"'
check DEFER 'non-git non-gh command word' 'gitfoo commit -m "a

b"'

# A `*/git` glob was here to tolerate /usr/bin/git and matched any path ending
# in /git, so a repo shipping `scripts/git` was approved outright. The command
# word must be the bare name and nothing else; $PATH does the resolving.
check DEFER 'relative path ending in /git' './evil/git add "line1

line2"'
check DEFER 'subdirectory path ending in /git' 'scripts/git commit -m "a

b"'
check DEFER 'absolute path to git' '/usr/bin/git commit -m "a

b"'
check DEFER 'relative path ending in /gh' './evil/gh pr create --body "a

b"'
# The unexpanded tilde is the point: the hook sees the raw string Claude Code
# sends, and the shell would only expand it at exec time.
# shellcheck disable=SC2088
check DEFER 'home-relative path ending in /gh' '~/x/gh pr edit --body "a

b"'
check DEFER 'gh subcommand outside the safelist' 'gh pr merge --body "a

b"'
check DEFER 'gh repo command' 'gh repo delete --yes x
gh pr create --title t --body "a

b"'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
