# tmux-pane-titles

Name the window after its panes' directories and branches. Called from zsh
hooks.

## Testing (`tmux-pane-titles.test.sh`)

Runs against a throwaway server carrying real pane options, since that is the
actual contract. Two traps found while writing it, both of which made the script
look broken when it was not:

1. **A pane running a real shell fights the test.** The shell sources
   `zsh/directory.zsh`, whose precmd hook clears `@git_branch` when the pane is
   not in a git repository — which a temp directory never is — so options set
   right after creating a window are wiped a few hundred milliseconds later.
   Every pane in these tests runs `sleep`, never a shell.
2. A window-name counter incremented inside `$( )` is lost to the subshell, so
   every window ends up with the same name and `-t <name>` silently resolves to
   the first. Window **ids** are used instead.
