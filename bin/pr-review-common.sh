# Sourced by bin/pr-review-watch and bin/pr-review-dispatch, not executed.
# The directive below is required for the linter to accept a file with no
# shebang at all -- see the note in bin/init/common.sh.
# shellcheck shell=bash
#
# A single-holder lock for the two review-pipeline programs. Both are driven by
# launchd, which fires on a fixed interval and does not care that the previous
# run is still going, so overlapping runs are the normal case: two watchers
# would interleave writes to the same job file, and two dispatchers would
# deliver one job twice.
#
# mkdir is the test-and-set, because it is atomic on every filesystem that
# matters and macOS ships no flock(1).
#
# THE LOCK IS PID-BASED, NOT TIME-BASED: the holder's pid goes in the directory
# and a lock is stolen only when `kill -0` says that pid is gone, so there is no
# timeout to tune. The age check below survives only as the fallback for a lock
# with no readable pid. Both failure directions are silent and unrecoverable --
# see bin/pr-review-common.md.
_PR_REVIEW_LOCK_STALE_MIN=${_PR_REVIEW_LOCK_STALE_MIN:-60}

# take_lock <dir> -- 0 if this process now holds it, 1 if somebody else does.
take_lock() {
  local lock=$1 holder

  if mkdir "$lock" 2>/dev/null; then
    printf '%s' "$$" >"$lock/pid" 2>/dev/null
    return 0
  fi

  holder=$(cat "$lock/pid" 2>/dev/null)
  case "$holder" in
    '' | *[!0-9]*)
      # No pid to ask about: fall back to age, and only for a lock old enough
      # that no plausible run is still inside it.
      [ -n "$(find "$lock" -maxdepth 0 -mmin +"$_PR_REVIEW_LOCK_STALE_MIN" 2>/dev/null)" ] || return 1
      ;;
    *)
      # kill -0 tests for existence without signalling. A live holder means
      # this run simply skips: the next interval is seconds away.
      kill -0 "$holder" 2>/dev/null && return 1
      ;;
  esac

  # The holder is gone. Clear the directory and re-take it through the same
  # atomic mkdir, so two processes arriving at this conclusion together still
  # produce exactly one winner.
  /bin/rm -f "$lock/pid" 2>/dev/null
  rmdir "$lock" 2>/dev/null
  if mkdir "$lock" 2>/dev/null; then
    printf '%s' "$$" >"$lock/pid" 2>/dev/null
    return 0
  fi
  return 1
}

# --- session lookup ---------------------------------------------------------
#
# Which live Claude Code session is working in a given worktree.
#
# Ownership is by LONGEST PREFIX, never by containment. Containment is WRONG the
# moment worktrees nest, and `gw` nests them by convention under
# `<checkout>/git-worktrees/`, making the main checkout a prefix of all of them:
# a PR on the main checkout matched every sibling session and delivered a review
# to an unrelated branch. So a cwd belongs to the deepest worktree containing
# it, and only that one. See bin/pr-review-common.md.
#
# The paths are compared as plain strings, so they must arrive already resolved
# the way git reports them -- on macOS git says /private/var where the shell says
# /var, and mixing the two silently matches nothing.

# worktree_paths_json <dir> -- every worktree of <dir>'s repo, as a JSON array.
worktree_paths_json() {
  git -C "$1" worktree list --porcelain 2>/dev/null |
    sed -n 's/^worktree //p' |
    jq -R -s 'split("\n") | map(select(length > 0))'
}

# session_in_worktree <agents-json> <worktree> <worktrees-json>
# Prints the newest matching interactive session as a JSON object, or nothing.
#
# Newest wins when a single worktree holds several sessions. That is arbitrary
# but bounded: two sessions in one worktree already break the one-writer rule
# the pipeline is built on, so there is no better answer to pick -- only a
# documented one.
session_in_worktree() {
  printf '%s' "$1" | jq -c --arg wt "$2" --argjson all "$3" '
    # $w is bound explicitly rather than left as `.`, because `$cwd |
    # startswith(. + "/")` rebinds `.` to $cwd inside the argument -- the
    # element is no longer reachable there, the comparison silently becomes
    # $cwd against itself, and owner() returns null for every nested cwd. The
    # same rebinding rule cost a poll that queued nothing in pr-review-watch.
    def owner($cwd):
      [ $all[] as $w | select($cwd == $w or ($cwd | startswith($w + "/"))) | $w ]
      | sort_by(length) | last;
    [ .[]
      | select(.kind == "interactive")
      | select(owner(.cwd) == $wt) ]
    | sort_by(.startedAt) | last // empty' 2>/dev/null
}

# release_lock <dir> -- safe to call from an EXIT trap that never ran take_lock.
release_lock() {
  local lock=$1
  [ -d "$lock" ] || return 0
  # Only the holder may release: a run that skipped because somebody else held
  # the lock must not free it on its way out.
  [ "$(cat "$lock/pid" 2>/dev/null)" = "$$" ] || return 0
  /bin/rm -f "$lock/pid" 2>/dev/null
  rmdir "$lock" 2>/dev/null
  return 0
}

# --- repository and branch lookup -------------------------------------------
#
# Shared by the two detectors (pr-review-watch, pr-state-watch), which both
# have to answer "is this PR something I can act on locally at all" before
# spending anything on it.

# repo_path <owner/name> <extra-repos> -- the local checkout, or non-zero.
#
# ghq owns almost everything; <extra-repos> is a colon-separated list covering
# the checkouts that predate it (dotfiles itself, notably) and is matched on the
# remote URL rather than on the directory name, since the two need not agree.
repo_path() {
  local full=$1 extra=${2:-} p
  p=$(ghq list --full-path --exact "github.com/$full" 2>/dev/null | head -1)
  if [ -n "$p" ] && [ -d "$p" ]; then
    printf '%s' "$p"
    return 0
  fi
  local IFS=:
  for p in $extra; do
    [ -d "$p" ] || continue
    # The insteadOf rewrite in .gitconfig means the stored URL may be either
    # transport, so match on the owner/name tail rather than the whole URL.
    case "$(git -C "$p" remote get-url origin 2>/dev/null)" in
      *"$full" | *"$full.git")
        printf '%s' "$p"
        return 0
        ;;
    esac
  done
  return 1
}

# worktree_for_branch <repo> <branch> -- the worktree holding it, or non-zero.
#
# A branch is checked out in at most one worktree, so this is unambiguous. The
# main checkout is a worktree too, which is why no special case is needed for a
# PR built without `gw`.
worktree_for_branch() {
  local repo=$1 branch=$2 path="" list line
  # Taken with a command substitution rather than read from a process
  # substitution: a `while read ... < <(cmd)` runs zero iterations when cmd
  # fails and carries on, and neither `set -e` nor pipefail sees it -- the trap
  # that had bin/lint-shell checking 3 files instead of 52 and printing ok.
  list=$(git -C "$repo" worktree list --porcelain 2>/dev/null) || return 1
  [ -n "$list" ] || return 1
  while IFS= read -r line; do
    case "$line" in
      "worktree "*) path=${line#worktree } ;;
      "branch refs/heads/$branch")
        printf '%s' "$path"
        return 0
        ;;
    esac
  done <<<"$list"
  return 1
}
