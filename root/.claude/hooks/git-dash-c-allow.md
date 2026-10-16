# git-dash-c-allow.sh

Approves `git -C <dir> <rest>` when `<dir>` resolves inside the project and
`git <rest>` is something the user's own allow rules already approve. It emits
`allow` only, so — like `approve-multiline-commands.sh` — a bug in it *widens* a
permission boundary, silently.

## Why it exists

`Bash(git -C * status*)` and its siblings had two problems, and Claude Code warns
about the first ("has a wildcard before the rest of the command"):

- the `*` matches any text, so `git -C . -c core.fsmonitor=<cmd> status` matched,
  and `-c` makes git run a program of the caller's choosing;
- the path was anything, so a `git -C ~/some-cloned-repo status` ran that
  repository's own `.git/config` — where `core.fsmonitor` is just as executable.

`git-guard.sh` patched the first, but a hook that only denies fails open: when it
times out or errors, the call continues and the allow rule approves it. Moving
the approval into a hook turns that around — this hook failing means a prompt.

## What it checks

- every segment of the command, as read by `segment-scan.lib.sh`, is bare `git`
  (not `/usr/bin/git`, not under a wrapper);
- its `-C` values, applied in order as git applies them, resolve **physically**
  inside `$CLAUDE_PROJECT_DIR` (`git-workdir.lib.sh`, shared with
  `approve-multiline-commands.sh`), so a symlink pointing out of the project does
  not count;
- `git <rest>` matches a rule from **`~/.claude/settings.json` only**. Project
  settings are not used by Claude Code until its trust dialog is accepted; read
  here, a cloned repository could approve its own commands;
- only rules whose single `*` is trailing are used: `git log *` / `git log:*`
  (word prefix, also matching bare `git log`), `git status*` (string prefix of the
  last word), and exact rules. Matching is per argv word, so the words git
  receives are those of a command the rule approves;
- `git <rest>` matches no deny or ask rule, from any settings layer
  (`git-rules.lib.sh`). Claude Code evaluates those rules after an `allow`, but
  against the command as written, so `Bash(git branch -D *)` never sees
  `git -C x branch -D y`. `git-guard.sh` applies them to the `-C` form too;
  staying silent here keeps the outcome from depending on how the two hooks'
  decisions combine.

Anything else — no `-C`, an expansion, a redirection, a non-git segment — emits
nothing.

## What it costs

A compound command with a non-git segment (`git -C sub status && npm test`) is
no longer approved without a prompt, even when each half has a rule: this hook
cannot vouch for the other half, and Claude Code's own matcher no longer has a
`git -C *` rule to approve the first.

## This is the matcher root/README.md said not to rebuild

The README's rm-guard section judged re-implementing the allow-list matcher "not
worth it", because a matcher looser than Claude Code's over-approves. This one is
narrower by construction — only literal-prefix rules, compared word by word — so
it can under-approve (a prompt) but not approve a command its rule would not.

## Testing (`git-dash-c-allow.test.sh`)

The DEFER half is the half that matters. The suite builds a throwaway project
with a symlink pointing out of it, a user settings file, and a project settings
file whose rule must be ignored.

One trap, found by that suite: the scanner calls the predicate from inside its
own functions, and bash scope is dynamic, so a predicate variable not declared
`local` overwrites the scanner's. An undeclared `line` in the rule matcher
replaced the line being scanned and dropped `; rm -rf x` unread — the command
was approved.
