# launchd-load

Load linked LaunchAgents that are not running. `--status` looks without changing
anything.

## Linking is not loading, and the gap is invisible

launchd runs nothing, logs nothing, and the only symptom is a feature quietly not
happening. Both PR-review agents sat unloaded on this machine with their symlinks
perfectly in place.

This script closes that: it walks `launchd/*.plist`, loads each through its
**linked** path in `~/Library/LaunchAgents` (not the repo copy, so launchd holds
the path `relink` maintains), and skips any that
`launchctl print gui/<uid>/<label>` already shows — a `bootstrap` on a loaded
service errors, and bootout-then-bootstrap would restart one that was running
fine.

Targets are discovered from the directory rather than listed, so a new plist
needs no second place to remember.

## Why it is its own command

`bin/init/macos.sh` calls it after `link_dotfiles` (skipped on CI alongside mas
and Xcode), but it is **its own command rather than a step in there** because
provisioning runs once: an already-provisioned machine gaining a new agent would
otherwise have to re-run the whole init, brew bundles included.

It is equally deliberately **not** called by `link_dotfiles`, which `relink` runs
on every `update-all`: loading an agent is a decision about the machine, not a
fact about the file layout. `launchctl bootout gui/$UID/com.ebkn.pr-review-dispatch`
— the documented way to stop delivery while notifications keep arriving, which is
the entire reason the pipeline is two agents — would be silently undone on every
update, bringing the agent that posts into live sessions back from the dead.

So `link_dotfiles` links `launchd-load` but never calls it.

## No Aqua session

A machine with no Aqua session (ssh-only) has no `gui/<uid>` domain to load into.
That is reported per agent and sets a non-zero exit, without aborting the rest.
