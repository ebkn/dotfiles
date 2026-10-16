# approve-multiline-commands.sh

A hook that emits `allow`, so its bug *widens* a permission boundary — and does
so silently: the command simply runs. `bin/test.md` lists every hook that does.

## Why it exists

The allow-list wildcard `*` does not match newlines, so
`git commit -F - <<'EOF'` and `gh pr create --body-file - <<'EOF'` (the forms the
`commit` / `create-pr` / `update-pr` skills emit) match no rule.

## The bug its first version had

It tested the **whole command string** — "first line starts with `git` + space" plus
"`git commit -m` + space appears somewhere" — so

    git status⏎rm -rf ~/important # git commit -m x

was approved: the guard token sat in a shell comment.

## What it does now

- parses the command into segments and requires **every** segment to be an
  approved git/gh invocation;
- reads the command word positionally per segment;
- requires the newlines to be *data* (inside a quoted argument or a heredoc
  body) rather than a plain statement separator — several statements on several
  lines have no wildcard problem to solve and are left to the normal flow;
- accepts `git -C <dir>` only into the project, through `git_dash_c_in_project`
  in `git-workdir.lib.sh` — the check `git-dash-c-allow.sh` makes, so the two
  hooks cannot disagree. It reads `.cwd` and `CLAUDE_PROJECT_DIR` for that, and
  refuses every `-C` when either is missing.

Beyond newline handling it grants almost nothing new: `git add *`,
`git commit -m *`, the three allow-listed `git push` forms, `gh pr create *` and
`gh pr edit*` are all already in `permissions.allow`. **The single addition is
`git commit -F`.**

Anything it cannot fully parse — an expansion (`$(…)`, backticks, an **unquoted**
heredoc tag, whose body the shell would expand), a redirection, a subshell, an
unterminated quote or heredoc — emits no decision, so a bug degrades to "you get
asked".

## Testing (`approve-multiline-commands.test.sh`)

**The DEFER half of the suite is the half that matters**; the ALLOW half is only
there to stop "defer on everything" passing.

One case is a **performance** assertion, not a behaviour one: scanning quoted
text a character at a time is O(n²) and took **25s** on a 1500-line message, and
a hook that exceeds its 5s timeout is killed — which looks exactly like an
unexplained permission prompt, not like a failure. The scanner therefore consumes
runs of ordinary text with `${seg%%$SCAN_UNQ_SPECIAL*}` rather than `${line:i:1}`
in a loop.

The scanner lives in `segment-scan.lib.sh`, sourced, because
`git-dash-c-allow.sh` needs the same argv.
It is **not** git-guard's parser, and must not become it: git-guard resolves
every ambiguity toward "inspect / refuse", which is correct for a hook that
denies and exactly wrong for one that allows.

Written for **bash 3.2** (`/bin/bash` on macOS, which the shebang selects): no
`mapfile`, no empty-array expansion under `set -u`.
