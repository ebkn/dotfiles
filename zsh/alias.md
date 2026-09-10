# zsh/alias.zsh — the wrapper functions

Shell aliases plus the `rm`, `fd` and `his` wrappers, and `imgcat`.

## rm.test.zsh and fd.test.zsh

These two cover the wrappers **whose failure modes are indistinguishable from
success**:

- `rm()` — losing the `trash` fallback leaves Linux with no working rm;
  mishandling `--`/`-f` sends the wrong argv to the deleting command.
- `fd()` — a stray second `cd` lands the shell a level too deep, but only when
  the picked path resolves from inside itself.

Both stub the external command (`trash`, `fzf`) so the assertions are on the real
contract without deleting anything outside a temp dir.

**Note the `rm` guard case builds a PATH holding a link to `rm` and nothing
else**: trimming to `/bin:/usr/bin` is a **false green** on macOS, which ships its
own `/usr/bin/trash`.

## his.test.zsh

Covers `his()` and `gs()`, which used to exist twice — once per platform,
differing only in `gsed` vs `sed`.

Collapsing them rests on a single claim: **`-E` is the ERE flag BSD sed and GNU
sed both accept** (GNU since 4.2), so `gsed -r` and `sed -E` do the same thing,
and nothing here needs `gnu-sed` any more.

That claim cannot be checked on one machine, so **this file *is* the
differential**: macOS runs it against BSD sed, CI's `ubuntu-latest` against GNU
sed, and disagreement between the two runs is the signal — neither run alone
proves much.

**Nothing in this repo calls `gsed` any more** — the last caller was
`scrapbox()`, since deleted. `gnu-sed` stays in `brewfiles/Brewfile-others` as a
tool to have around, not as a dependency of anything here, so **a `gsed`
reappearing in a script is worth a second look**: BSD sed differs in ways that
bite quietly (it does not expand `\t` in a replacement, the trap
[bin/tmux-agents.md](../bin/tmux-agents.md) also documents), and reaching for
`gsed` to dodge that makes the script macOS-only.

`his()` ends in `print -z`, which pushes onto the editor buffer stack and cannot
be read back from a non-interactive shell, so the substitutions live in
`_his_clean` and are tested there.

`gs()` is tested end to end with `git` and `fzf` stubbed, since what is worth
pinning is the branch name that reaches `git switch` — in particular that
`remotes/<remote>/` is stripped, and that `grep -v HEAD` keeps the symbolic ref
out of the picker.
