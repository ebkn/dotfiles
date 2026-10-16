#!/bin/bash
# Exercises git-guard.sh. DENY = hook blocks the call. PASS = hook stays
# silent, leaving the existing permission rules to decide as they do today.
#
# The PASS half is the half that matters for day-to-day use: this repo's
# monorepo layout means the agent routinely runs `git -C <absolute path> add`,
# and a hook that got in the way of that would not survive contact.
set -uo pipefail

HOOK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/git-guard.sh"

pass=0
fail=0

# PASS means exactly "exit 0, nothing on stdout" -- the hook staying out of the
# way. Anything else that is not a deny is ERROR, so a hook that crashes on an
# input cannot be mistaken for one that let it through on purpose.
# The command goes to jq on stdin, not as --arg: Linux caps a single argument at
# 128KB, and the timing cases below are larger than that.
run_hook() {
  printf '%s' "$1" | jq -Rs '{tool_name:"Bash", tool_input:{command:.}}' | "$HOOK" 2>/dev/null
}
verdict() {
  local cmd=$1 out rc
  out=$(run_hook "$cmd") && rc=0 || rc=$?
  if [[ $rc -eq 0 ]] && printf '%s' "$out" | grep -q '"permissionDecision": *"deny"'; then
    echo DENY
  elif [[ $rc -eq 0 && -z "$out" ]]; then
    echo PASS
  else
    echo "ERROR(rc=$rc)"
  fi
}

# An optional third argument labels a command too long to print.
check() {
  local expect=$1 cmd=$2 label=${3:-$2} got
  got=$(verdict "$cmd")
  if [[ "$got" == "$expect" ]]; then
    pass=$((pass + 1))
    printf '  ok   %-4s %s\n' "$got" "$label"
  else
    fail=$((fail + 1))
    printf '  FAIL want=%s got=%s  %s\n' "$expect" "$got" "$label"
  fi
}

echo "-- must DENY: verified execution vectors --"
check DENY "git -c core.fsmonitor='echo pwned' status"
check DENY "git -C /tmp -c core.hooksPath=/tmp/e commit -m x"
check DENY "git -c diff.external='echo pwned' diff"
check DENY 'git --config-env=core.pager=EV status'

echo "-- must DENY: other options that reach a program --"
check DENY 'git --exec-path=/tmp/e add .'
check DENY 'git --git-dir=/tmp/e/.git commit -m x'
check DENY 'git --work-tree=/tmp/e add .'
check DENY 'git --namespace=x push'
check DENY 'git -C /tmp --bare status'
# Bare, it only prints a path, but the safelist matches whole tokens and the
# `--exec-path=<dir>` form is a vector; keeping both out keeps the list simple.
check DENY 'git --exec-path'

echo "-- must DENY: unknown option before the subcommand (safelist, not blocklist) --"
check DENY 'git --some-future-option add .'
check DENY 'git -Z add .'

echo "-- must DENY: reached through the wrappers Claude Code strips --"
check DENY 'timeout 5 git -c a=b status'
check DENY 'timeout --preserve-status 5 git -c a=b status'
check DENY 'nice -n 5 git -c a=b status'
check DENY 'stdbuf -o0 git -c a=b status'
check DENY 'nohup git -c a=b status'
check DENY 'xargs git -c a=b status'
check DENY 'FOO=bar git -c a=b status'
check DENY '/usr/bin/git -c a=b status'

echo "-- must DENY: hiding behind a separator or unparseable quoting --"
check DENY 'echo hi; git -c a=b status'
check DENY 'ls && git -c a=b status'
check DENY "git -C '/unterminated status"
check DENY 'git -C'
check DENY 'timeout 5 git -C'

echo "-- must DENY: after a wrapper, the first git word is the command (each form here once bypassed a flag parser) --"
# Claude Code strips `timeout` before matching, so `Bash(git status*)` would
# approve these; reading `KILL` as the duration made `5` the command word.
check DENY 'timeout -s KILL 5 git -c a=b status'
check DENY 'timeout -k 1 5 git -c a=b status'
check DENY 'timeout --signal KILL 5 git -c a=b status'
check DENY 'timeout --kill-after=1 5 git -c a=b status'
check DENY 'stdbuf -o 0 git -c a=b status'
check DENY 'stdbuf -i 0 git -c a=b status'
check DENY 'stdbuf -e 0 git -c a=b status'
check DENY 'timeout --signal=KILL 5 git -c a=b status'
check DENY 'nice -n5 git -c a=b status'
check DENY 'nice --adjustment 5 git -c a=b status'
check DENY 'nice --adjustment=5 git -c a=b status'

echo "-- must DENY: every wrapper Claude Code strips is seen through --"
check DENY 'time git -c a=b status'
check DENY 'command git -c a=b status'
check DENY 'builtin git -c a=b status'
check DENY 'noglob git -c a=b status'
# Whether Claude Code strips these with flags is not documented (it strips
# xargs only without), but seeing through them costs nothing and errs to deny.
check DENY 'time -p git -c a=b status'
check DENY 'command -p git -c a=b status'
check DENY 'xargs -0 git -c a=b status'
check DENY 'xargs -n 1 git -c a=b status'
check DENY 'xargs -I {} git -c a=b status'
check DENY 'xargs -L 1 git -c a=b status'
check DENY 'xargs -P 2 git -c a=b status'
check DENY 'timeout --kill-after 1 5 git -c a=b status'
# Long forms and flags no list anticipated: after a wrapper, the first `git`
# word is the command, whatever flags come before it.
check DENY 'stdbuf --output 0 git -c a=b status'
check DENY 'stdbuf --input=0 git -c a=b status'
check DENY 'xargs --max-args 1 git -c a=b status'
check DENY 'time -f %e git -c a=b status'
check DENY 'nice --some-future-flag x 5 git -c a=b status'
check DENY 'timeout 5 nice -n 1 git -c a=b status'
# Over-refusal accepted in exchange: a wrapped non-git command with a git word
# among its arguments, bare or as a path ending in /git.
check DENY 'timeout 5 echo git -c a=b'
check DENY 'timeout 5 ls build/git -c a=b'
# A wrapper with no git word after it runs no git. The text must still contain
# "git" -- otherwise the substring bail-out ends the hook before this path.
check PASS 'timeout 5 echo "a git"'
check PASS 'timeout 5 git'
# The git word after a wrapper is recognised in every spelling the segment head
# is, and assignments and keywords around the wrapper change nothing.
check DENY 'timeout 5 /usr/bin/git -c a=b status'
check DENY 'timeout 5 "git" -c a=b status'
check DENY 'timeout 5 \git -c a=b status'
check DENY 'FOO=1 timeout 5 git -c a=b status'
check DENY 'timeout 5 FOO=1 git -c a=b status'
check DENY 'if timeout 5 git -c a=b status; then :; fi'
# Everyday wrapped forms stay out of the way.
check PASS 'command -v git'
check PASS 'xargs git status'
# Reading stops at the git word: what follows the subcommand is never parsed.
check PASS "timeout 5 git commit -m $(printf 'a"b"%.0s' $(seq 100))" "timeout 5 git commit -m <200-run word>"
check DENY "timeout 5 FOO=$(printf 'a"b"%.0s' $(seq 32))a git status" "65-run word before the git word: refused"

echo "-- must DENY: an assignment with a quoted value is one word --"
# Read as `FOO="a` and `b"`, the second half became the command word.
check DENY 'FOO="a b" git -c a=b status'
check DENY "FOO='a b' git -c a=b status"
check DENY 'FOO=a"b c"d git -c a=b status'
check PASS 'FOO="a b" git status'
# Too many quoted runs in one word to read within the timeout: refused unread.
check DENY "FOO=$(printf 'a"b"%.0s' $(seq 2000)) git status" "2000 quoted runs in one word"
# Each `a"b"` pair is two runs (`FOO=a` being the first), so 32 pairs are 64
# runs and a trailing `a` makes 65.
check PASS "FOO=$(printf 'a"b"%.0s' $(seq 32)) git status" "64 runs in one word: read"
check DENY "FOO=$(printf 'a"b"%.0s' $(seq 32))a git status" "65 runs in one word: refused"
# An unterminated quote before the command word: unreadable, so refused.
check DENY 'FOO="x git -c a=b status'

# Paths here are placeholders on purpose: this repository is public, so a real
# private-repo path in a test fixture would publish it.
echo "-- must PASS: a monorepo's everyday git -C usage --"
check PASS 'git -C /tmp add .'
check PASS 'git -C /Users/x/ghq/github.com/acme/example-monorepo/git-worktrees/some-branch add apps/frontend'
check PASS 'git -C "/path with space" add .'
check DENY 'git -C "/path with space" -c a=b status'
# A backslash-escaped space is part of the word, as the shell reads it. Read as
# a word break, `a\` became the -C path and `b` the subcommand, and the -c after
# it went uninspected.
check DENY 'git -C a\ b -c a=b status'
check DENY 'FOO=a\ b git -c a=b status'
check PASS 'git -C a\ b status'
check DENY '\git -c a=b status'
# Quoting the word reader does not model exactly is refused, not guessed at: a
# backslash inside double quotes, and ANSI-C $'...'. Guessed, `\"` closed the
# run early and a later `'` re-synchronised the quotes, so `-c` was read as
# part of a quoted subcommand while the shell ran it as an option.
check DENY "git -C \"x\\\" '\" -c a=b status \"' y\""
check DENY "git -C \$'x\\' \"' -c a=b status '\" y'"
check DENY 'git -C "a\"b" status'
check PASS 'git -C "a b" status'
check PASS "git -C 'a\\b' status"
# The same refusal before the command word, where skipping the unreadable word
# instead would leave the git after it unread.
check DENY 'FOO="a\"b" git status'
check DENY "FOO=\$'a' git status"

echo "-- a redirection is removed from argv, as the shell does --"
# Read as words, `2>/dev/null` took the subcommand's place and left `-c` unread,
# and a leading `>/dev/null` took the command word's.
check DENY 'git -C . 2>/dev/null -c a=b status'
check DENY 'git -C . > /dev/null -c a=b status'
check DENY '>/dev/null git -C . -c a=b status'
check DENY 'timeout 5 2>/dev/null git -c a=b status'
check PASS 'git -C . 2>/dev/null status'
check PASS 'git status>/dev/null'
check PASS 'git status >/dev/null 2>&1'
check PASS 'command -v git >/dev/null 2>&1'
# Only an unquoted digit run is a file descriptor: `"2">x` passes "2" to git, so
# here it is the -C path and `-c` is git's next option.
check DENY 'git -C "2">x -c a=b status'
# More than one redirection in a word, or more than a handful in a row, is
# beyond what this models: refused.
check DENY 'git -C . >a>b status'
check PASS "git -C . $(printf '>a %.0s' $(seq 15))status" "15 redirections before the subcommand: read"
check DENY "git -C . $(printf '>a %.0s' $(seq 16))status" "16 redirections before the subcommand: refused"
check DENY 'git <in -c a=b status'
check PASS 'git status <in'
# The `&` or `|` of a redirection operator is no separator. Split there, `git >`
# looked like a whole command and `2 -c a=b status` like another.
check DENY 'git >&2 -c a=b status'
check DENY 'git 2>&1 -c a=b status'
check DENY 'git &>/dev/null -c a=b status'
check DENY 'git &>>log -c a=b status'
check DENY 'git <&0 -c a=b status'
check DENY 'git >|x -c a=b status'
check PASS 'git status 2>&1'
check PASS 'git status &>/dev/null'
# Read, not refused: each operator before the subcommand is removed and the
# words around it still inspected.
check PASS 'git 2>&1 status'
check PASS 'git >&2 -C . status'
check PASS 'git &>/dev/null status'
check PASS 'git <&0 status'
check PASS 'git >|x status'
# A quoted operator character is no redirection, so the `&` after it still is.
check DENY 'echo ">"& git -c a=b status'
check DENY "echo '>'| git -c a=b status"
# A command the walk cannot split (unbalanced quoting) is refused whole if any
# word could be git; there is no second, cruder splitter to get wrong.
check DENY 'echo "x; git >&2 -c a=b status'
check DENY 'echo "x; git status'
# On the raw text of an unsplittable command a separator glued to the word
# still bounds it.
check DENY 'echo "x;git -c a=b status'
check DENY 'echo "x(git -c a=b status'
# A redirection glued to the git word still leaves it the git word.
check DENY 'git>/dev/null -C . -c a=b status'
check DENY 'git&>/dev/null -C . -c a=b status'
check PASS 'git>/dev/null status'
check PASS 'git&>/dev/null status'
# A redirection target is no argument of git's: its `$` marks nothing, attached
# to the operator or not.
# shellcheck disable=SC2016 # literal command text under test
check PASS 'git -C . >"$f" status'
# shellcheck disable=SC2016 # literal command text under test
check PASS 'git -C . > "$f" status'

echo "-- must DENY: an expansion where git reads its options --"
# The shell expands braces, globs and unquoted parameters, so the word read here
# is not what git receives -- each of these left `-c` as git's next argument.
check DENY 'git -C {.,-c} a=b status'
check DENY 'git -C . {-c,a=b} status'
check DENY 'git -C . -* status'
check DENY 'git -C . ?c a=b status'
check DENY 'git -C . [-]c a=b status'
# shellcheck disable=SC2016 # literal command text under test
check DENY 'git -C $D status'
check PASS 'git -C "{dir}" status'
# shellcheck disable=SC2016 # literal command text under test
check PASS 'git -C "$D" status'
# Quoted, a parameter is one word but of unknown content: harmless as -C's path,
# an option of its choosing where git reads options (`X=--exec-path=...`).
# shellcheck disable=SC2016 # literal command text under test
check DENY 'git "$X" status'
# shellcheck disable=SC2016 # literal command text under test
check DENY 'git -C . "${X}" status'
# Past the subcommand nothing is read, so a parameter there is ordinary.
# shellcheck disable=SC2016 # literal command text under test
check PASS 'git log "$X"'
# shellcheck disable=SC2016 # literal command text under test
check PASS 'git commit -m "$MSG"'
check PASS "git log --format='%h {x}' -- '*.sh'"
# `{}` is not a brace expansion, so xargs' placeholder is read as written.
check PASS 'xargs -I{} git -C {} status'
# Before the git word an expansion is not refused, and a word is judged as
# written: an assignment is not expanded at all, a command word like `[` is not
# git, and one whose text ends in /git is, expansion or not.
check DENY 'FOO=* git -c a=b status'
check PASS 'FOO={a,b} git status'
check PASS '[ -x /usr/bin/git ]'
check PASS '{ git status; }'
# shellcheck disable=SC2016 # literal command text under test
check DENY '$D/git -c a=b status'
# Over-refusal accepted in exchange: after a wrapper, an argument named git
# followed by a glob (the same cost as `timeout 5 echo git -c x` above).
check DENY 'timeout 5 rg git *.md'
check PASS 'git -C /tmp commit -m "fix: something"'
check PASS 'git -C /tmp'
check PASS 'git -C /tmp status --short'

echo "-- must PASS: -c after the subcommand is a different option entirely --"
check PASS 'git switch -c feat/x'
check PASS 'git -C /tmp switch -c feat/x'
check PASS 'git commit -c HEAD --amend'
check PASS 'git branch -c old new'
check PASS 'git log -c'

echo "-- must PASS: safe globals and ordinary commands --"
check PASS 'git status'
check PASS 'git'
check PASS 'git --no-pager log --oneline'
check PASS 'git -P diff'
check PASS 'git --no-optional-locks status'
check PASS 'git --paginate log'
check PASS 'git --no-replace-objects log'
check PASS 'git --no-lazy-fetch log'
check PASS 'git --no-advice status'
check PASS 'git --literal-pathspecs add a'
check PASS 'git --glob-pathspecs add a'
check PASS 'git --noglob-pathspecs add a'
check PASS 'git --icase-pathspecs add a'
check PASS 'git -v'
check PASS 'git --version'
check PASS 'git -h'
check PASS 'git --man-path'
check PASS 'git --html-path'
check PASS 'git --info-path'
check PASS 'timeout 5 git status'
check PASS 'nice -n 5 git status'
check PASS 'git add -p'

echo "-- must PASS: quoting the subcommand region does not reach --"
check PASS "git commit -m \"it's broken\""
check PASS 'git commit -m "fix: a && b"'
check PASS 'git commit -m "wip; more"'
check PASS 'git log --grep="a|b"'
check PASS 'git commit -m "fix(scope): subject"'

echo "-- must PASS: heredoc bodies are data, not commands --"
# Regression: this hook's own commit message quoted `git -c ...` as an example,
# and an earlier version of the hook refused the commit.
check PASS $'git commit -F - <<\'EOF\'\nfix(claude): guard git global options\n\nVerified that `git -c core.fsmonitor=<cmd> status` executes.\nEOF'
check PASS $'git -C /tmp commit -F - <<\'MSG\'\nsubject\n\ngit --exec-path=/tmp/e add .\nMSG'
check PASS $'cat <<-EOF\n\tgit -c a=b status\n\tEOF'

echo "-- must DENY: a real invocation outside the heredoc still counts --"
check DENY $'git -c a=b commit -F - <<\'EOF\'\nsubject\nEOF'
check DENY $'cat <<\'EOF\'\ngit -c harmless=example status\nEOF\ngit -c a=b status'

echo "-- must DENY: what only looks like a heredoc opener hides nothing --"
check DENY $'cat <<<EOF\ngit -c a=b status'
check DENY $'echo "<<EOF"\ngit -c a=b status\nEOF'
check DENY $'echo \'<<EOF\'\ngit -c a=b status\nEOF'
check DENY $'echo \\<<EOF\ngit -c a=b status\nEOF'
# No terminator: stripping to the end would hide every later line, so the body
# is inspected rather than assumed to be data.
check DENY $'cat <<EOF\ngit -c a=b status'
check DENY $'cat <<A <<B\na\nA\nb\nB\ngit -c a=b status'
check PASS $'cat <<A <<B\ngit -c a=b status\nA\ngit -c a=b status\nB'
check PASS $'cat << "EOF"\ngit -c a=b status\nEOF'
check DENY $'cat << "EOF"\nbody\nEOF\ngit -c a=b status'
check PASS $'cat <<"EOF"\ngit -c a=b status\nEOF'

echo "-- must DENY: a backslash-newline continues the same command --"
check DENY $'git \\\n-c a=b status'
check PASS $'git status \\\n--short'

echo "-- must PASS: not a git command --"
check PASS 'npm test'
check PASS 'echo git -c a=b'
check PASS 'grep git -c file.txt'
check PASS 'rg "git -c" .'

echo "-- must PASS: a separator inside quotes (outside any substitution) does not start a command --"
# Regression: an rg alternation `"warn|git -C|hook"` was split at the quoted
# `|`, leaving a bare `git -C` fragment that was refused as "-C with no path".
check PASS 'rg -n "warn|git -C|hook" file.txt'
check PASS "rg -n 'allow|matcher|git -C|approve-multiline' root/README.md"
check PASS 'rg "x; git -c a=b status" .'
check PASS "echo 'a && git -c a=b status'"
check PASS 'echo "a \" ; git -c a=b status"'
check PASS 'echo a\; git -c a=b status'
check PASS $'git commit -m "subject\ngit -c a=b status"'

echo "-- must DENY: a separator outside quotes still does --"
check DENY 'echo "hi"; git -c a=b status'
check DENY "echo 'x' && git -c a=b status"
check DENY $'echo "multi\nline"\ngit -c a=b status'
# Unbalanced quoting cannot be segmented, so the command is refused whole.
check DENY 'echo "x; git -c a=b status'
# A backslash is literal inside single quotes, so `'a\'` is closed there; treating
# it as an escape would swallow the closing quote and hide the git that follows.
check DENY "echo 'a\\' ; git -c a=b status"
# An escaped quote outside quotes opens nothing.
check DENY 'echo \"; git -c a=b status'

echo "-- must DENY: a command substitution runs, even inside double quotes --"
# The substitutions are the command text under test, so they must stay unexpanded.
# shellcheck disable=SC2016
{
  check DENY 'echo "$(true; git -c a=b status)"'
  check DENY 'echo "`true; git -c a=b status`"'
  check DENY 'echo "$(git -c a=b status)"'
  check DENY 'echo $(git -c a=b status)'
  check DENY 'echo `git -c a=b status`'
  check DENY 'x=$(git -c a=b status)'
}
check PASS "echo '\$(git -c a=b status)'"
# A substitution inside double quotes is walked as commands, and the double
# quotes resume after it. Before, such a command was unsplittable and went to a
# split-everywhere fallback, where `&>` and `a\;b` each hid a git.
# shellcheck disable=SC2016 # literal command text under test
{
  check DENY 'echo "$(date)"; git -C . &>/dev/null -c a=b status'
  check DENY 'echo "$(date)"; git -C a\;b -c a=b status'
  check DENY 'echo "$(echo "a;b")"; git -c a=b status'
  check PASS 'echo "$(echo "a;b") git -c a=b"'
  check DENY 'echo "$(echo "$(git -c a=b status)")"'
  check DENY 'echo "`echo a; git -c a=b status`"; true'
  check PASS $'git commit -m "$(cat <<\'EOF\'\nsubject\n\ngit -c a=b status\nEOF\n)"'
  check DENY 'echo "$(true; git status"'
  # The outer word keeps a placeholder where the substitution was, so what
  # follows it is still read as git's options.
  check PASS 'git -C "$(pwd)" status'
  check DENY 'git -C "$(pwd)" -c a=b status'
  check DENY 'git -C "`pwd`" -c a=b status'
  # The placeholder still varies, like the substitution it stands for: where
  # git reads an option it is refused, since the shell passes whatever the
  # substitution printed -- `--config-env=...` as one word.
  check DENY 'git -C . "$(echo --config-env=core.fsmonitor=X)" status'
  check DENY 'git "`echo --git-dir=/x`" status'
  check PASS 'git commit -m "$(echo subject)"'
  # In the subcommand position too: the word git reads first after its options
  # is a substitution of unknown output, which may well be an option. As -C's
  # path it is only a path, whatever it prints.
  check DENY 'git "$(echo status)"'
  check PASS 'git -C "$(echo -c)" status'
  # A case pattern's `)` would close the substitution early, leaving the git
  # after it as data, so a `case` inside a quoted substitution cannot be split.
  # Rather than refuse it -- it is an ordinary word, `git commit -m "$(echo
  # case 1)"` -- the hook stays silent and the normal flow decides: no allow
  # rule left can approve a git with an option before its subcommand, so it
  # prompts or goes to the auto mode classifier.
  check PASS 'echo "$(case x in x) git -c a=b status;; esac)"'
  check PASS 'git commit -m "$(echo case 1)"'
  check PASS 'echo "$(true;case x in x) y;; esac)"; git -c a=b status'
  # `case` is recognised after a separator too, not only first in the
  # substitution, and is silent there as well.
  check PASS 'echo "$(true;case x in x) git -c a=b status;; esac)"'
  check PASS 'echo "$(true&&case x in x) git -c a=b status;; esac)"'
  # Unquoted, the `)` only splits, so the git after it is inspected as usual.
  check DENY 'echo $(case x in x) git -c a=b status;; esac)'
}
# Unsplittable with no word that could be git: nothing to inspect, so it passes.
check PASS "echo \"it's"

echo "-- must DENY: grouping and compound-command keywords are not the command --"
check DENY '(git -c a=b status)'
check DENY '( git -c a=b status )'
check DENY '{ git -c a=b status; }'
check DENY 'if git -c a=b status; then echo y; fi'
check DENY 'while git -c a=b status; do break; done'
check DENY 'true && ! git -c a=b status'
check DENY 'until git -c a=b status; do break; done'
check DENY 'if false; then :; elif git -c a=b status; then :; fi'
check DENY 'if false; then git -c a=b status; fi'
check DENY 'if false; then :; else git -c a=b status; fi'

echo "-- must DENY: every separator Claude Code recognises --"
check DENY 'false || git -c a=b status'
check DENY 'echo | git -c a=b status'
check DENY 'echo |& git -c a=b status'
check DENY 'sleep 1 & git -c a=b status'
check DENY 'cat <(git -c a=b status)'
# shellcheck disable=SC2016 # literal command text under test
check DENY 'echo "$x" "$(git -c a=b status)"'

echo "-- must DENY: the option itself quoted or glued --"
check DENY 'git "-c" a=b status'
check DENY 'git -c"a=b" status'

echo "-- must PASS: input with nothing to inspect --"
check_input() {
  local label=$1 json=$2 out rc
  out=$(printf '%s' "$json" | "$HOOK" 2>/dev/null) && rc=0 || rc=$?
  if [[ $rc -eq 0 && -z "$out" ]]; then
    pass=$((pass + 1))
    printf '  ok   PASS %s\n' "$label"
  else
    fail=$((fail + 1))
    printf '  FAIL want=PASS got=rc=%s out=%s  %s\n' "$rc" "$out" "$label"
  fi
}
check_input "no tool_input" '{}'
check_input "no command" '{"tool_name":"Bash","tool_input":{}}'
check_input "empty command" '{"tool_name":"Bash","tool_input":{"command":""}}'

echo "-- the reason names what went wrong --"
# check_reason <cmd> <must contain> [<must not contain>]: the second pins which
# branch produced the reason, so swapping two branches cannot pass.
check_reason() {
  local cmd=$1 want=$2 not=${3:-} reason
  reason=$(run_hook "$cmd" | jq -r '.hookSpecificOutput.permissionDecisionReason')
  if [[ "$reason" == *"$want"* && (-z "$not" || "$reason" != *"$not"*) ]]; then
    pass=$((pass + 1))
    printf '  ok   %s -> %s\n' "$cmd" "$want"
  else
    fail=$((fail + 1))
    printf '  FAIL %s: want "%s"%s, got: %s\n' "$cmd" "$want" "${not:+ and not \"$not\"}" "$reason"
  fi
}
check_reason 'git -c a=b status' "refused '-c'"
check_reason 'git -C' "-C with no path" "unreadable"
check_reason 'git -C "a\"b" status' "an unreadable word after -C" "no path"
# An expansion is not unreadable but decided when the shell runs it, and the
# usual advice -- move the option after the subcommand -- does not apply to it.
check_reason 'git -C {.,-c} a=b status' "decided only when the shell runs it" "unreadable"
check_reason 'git -C . {-c,a=b} status' "decided only when the shell runs it" "Put the option after"
# shellcheck disable=SC2016 # literal command text under test
check_reason 'git "$(echo status)"' "decided only when the shell runs it" "unreadable"
# shellcheck disable=SC2016 # literal command text under test
check_reason 'git -C . "$X" status' "Write that word out literally" "Put the option after"
check_reason 'FOO="a\"b" git -c a=b status' "could not read the words before the command" "refused '"
# Read past the redirection, and refused whole when the command cannot be split.
check_reason 'git >&2 -c a=b status' "refused '-c'" "unreadable"
check_reason 'echo "x; git >&2 -c a=b status' "could not split" "refused '-c'"
check_reason 'echo "x; git status' "could not split" "refused '"
# Nesting too deep reaches the same refusal, not a later branch's. (A `case` in
# a quoted substitution is the one unsplittable cause left to the normal flow.)
# shellcheck disable=SC2016 # the openers are command text under test
check_reason "$(printf 'echo "$(%.0s' $(seq 17))true$(printf ')"%.0s' $(seq 17)); git status" "could not split" "refused '"

echo "-- must finish well inside the 5s hook timeout --"
# A timed-out hook does not block the call, so slowness is a bypass, not a
# nuisance. Measured on 100k bytes: the linear awk walk takes ~0.35s, a bash
# loop over `${s:i:1}` ~9s even under LC_ALL=C (it is quadratic), so a 3s bound
# tells them apart with room for a slow CI runner. Both outcomes of the walk are
# timed: a split, and the refusal of a command it cannot split.
# Each case ends in a git that must be refused, so a hook that bails out early
# on a huge input fails here rather than looking fast.
check_fast() {
  local label=$1 cmd=$2 got
  SECONDS=0
  got=$(verdict "$cmd")
  if ((SECONDS < 3)) && [[ "$got" == DENY ]]; then
    pass=$((pass + 1))
    printf '  ok   %s: DENY in %ds\n' "$label" "$SECONDS"
  else
    fail=$((fail + 1))
    printf '  FAIL %s: %s in %ds\n' "$label" "$got" "$SECONDS"
  fi
}
filler=$(printf 'é%.0s' $(seq 50000))
check_fast "100k-byte quoted message" "git commit -m \"$filler\"; git -c a=b status"
check_fast "100k-byte unbalanced quote (unsplittable)" "git commit -m \"$filler; git -c a=b status"
# Each unterminated opener searches the lines after it for its terminator; done
# per opener that is quadratic, and 20000 of them took 58s.
# ($(...) drops the final newline, so it is put back before the git line.)
openers=$(printf 'cat <<EOF%.0s\n' $(seq 20000))
check_fast "20000 unterminated heredoc openers" "${openers}"$'\n'"git -c a=b status"
openers=$(for i in $(seq 20000); do printf 'cat <<T%d\n' "$i"; done)
check_fast "20000 distinct unterminated openers" "${openers}"$'\n'"git -c a=b status"
# Each segment costs the bash loop ~0.2ms and more as they grow (100000 took
# 56s), so non-git segments must never reach it, and too many git-looking ones
# are refused rather than inspected one by one.
check_fast "100000 non-git segments" "$(printf 'echo x;%.0s' $(seq 100000)) git -c a=b status"
check_fast "100000 openers on one line" "cat $(printf '<<a %.0s' $(seq 100000))"$'\n'"git -c a=b status"
check_fast "a 500k-byte heredoc tag" "cat <<$(printf 'a%.0s' $(seq 500000))"$'\n'"git -c a=b status"
# shellcheck disable=SC2016 # literal command text under test
check_fast "100k-byte substitution inside double quotes" "echo \"\$(echo $filler)\"; git -c a=b status"
# Substitutions nest 16 deep inside double quotes; deeper is unsplittable.
# shellcheck disable=SC2016 # the openers are command text under test
{
  nest16="$(printf 'echo "$(%.0s' $(seq 16))true$(printf ')"%.0s' $(seq 16))"
  nest17="$(printf 'echo "$(%.0s' $(seq 17))true$(printf ')"%.0s' $(seq 17))"
}
check DENY "${nest16}; git -c a=b status" "16 nested substitutions, then a git: read"
check PASS "${nest16}; git status" "16 nested substitutions, then a safe git: read"
check DENY "${nest17}; git status" "17 nested substitutions: unsplittable, refused"
many_git=$(printf 'echo git;%.0s' $(seq 5000))
check_fast "5000 git-looking segments, refused unread" "$many_git"
check PASS "$(printf 'git status;%.0s' $(seq 1000))" "1000 git segments: at the cap, inspected"
check DENY "$(printf 'git status;%.0s' $(seq 1001))" "1001 git segments: past the cap, refused"
check DENY "git status; git -c a=b status" "a safe git first does not end the inspection"
tag64=$(printf 'a%.0s' $(seq 64))
check PASS "cat <<${tag64}"$'\n'"git -c a=b status"$'\n'"${tag64}" "64-byte heredoc tag: a heredoc"
check DENY "cat <<${tag64}a"$'\n'"git -c a=b status"$'\n'"${tag64}a" "65-byte heredoc tag: body inspected"
# Any spelling of the command word strip_wrappers would read as git survives
# the prefilter, or the inspection never sees it.
check DENY 'echo x; "git" -c a=b status'
check DENY "echo x; 'git' -c a=b status"
check DENY 'echo x; "/usr/bin/git" -c a=b status'
check DENY $'echo x;\tgit\t-c a=b status'
check DENY 'echo x; \git -c a=b status'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
