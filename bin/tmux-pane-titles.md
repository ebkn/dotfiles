# tmux-pane-titles

Name the window after its panes' directories and branches. Called from zsh
hooks.

**It targets `$TMUX_PANE` explicitly.** Left untargeted, tmux does not resolve
"the current window" to the window of the pane the command runs in: measured on
3.7c with a client attached, a command run inside a background window's pane
resolves the client's *active* window. So a hook firing in a background window —
a long command finishing there — renamed the window being looked at. The suite
pins this by running the script inside a background pane (`respawn-pane`), the
way the hooks run; setting `TMUX_PANE` from outside the pane is not equivalent.

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
