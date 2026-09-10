# approve-multiline-commands.sh

The one hook here that emits `allow`. The rest only ever `deny` or stay silent,
so this is the only one whose bug *widens* a permission boundary — and it does so
silently: the command simply runs.

## Why it exists

The allow-list wildcard `*` does not match newlines, so
`git commit -F - <<'EOF'` and `gh pr create --body-file - <<'EOF'` (the forms the
`commit` / `create-pr` / `update-pr` skills emit) match no rule.

## The bug its first version had

It tested the **whole command string** — "first line starts with `git `" plus
"`git commit -m ` appears somewhere" — so

    git status⏎rm -rf ~/important # git commit -m x

was approved: the guard token sat in a shell comment.

## What it does now

- parses the command into segments and requires **every** segment to be an
  approved git/gh invocation;
- reads the command word positionally per segment;
- requires the newlines to be *data* (inside a quoted argument or a heredoc
  body) rather than a plain statement separator — several statements on several
  lines have no wildcard problem to solve and are left to the normal flow.

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
runs of ordinary text with `${seg%%$UNQ_SPECIAL*}` rather than `${line:i:1}` in a
loop.

Written for **bash 3.2** (`/bin/bash` on macOS, which the shebang selects): no
`mapfile`, no empty-array expansion under `set -u`.
