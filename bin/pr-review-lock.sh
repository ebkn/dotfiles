# Sourced by bin/pr-review-watch and bin/pr-review-dispatch, not executed.
# The directive below is required for the linter to accept a file with no
# shebang at all -- see the note in bin/init/common.sh.
# shellcheck shell=bash
#
# A single-holder lock for the two review-pipeline programs. Both are driven by
# launchd, which fires on a fixed interval and does not care that the previous
# run is still going, so overlapping runs are the normal case rather than an
# edge one: two watchers would interleave writes to the same job file, and two
# dispatchers would deliver one job twice.
#
# mkdir is the test-and-set, because it is atomic on every filesystem that
# matters and macOS ships no flock(1).
#
# The interesting part is what happens to a lock whose holder died. An earlier
# version stole any lock older than ten minutes, which quietly assumed no run
# ever legitimately takes that long -- an assumption nothing enforced and
# nothing checked. It is replaced here by asking the only question that actually
# matters: is the process that took this lock still alive? The holder's pid is
# written into the directory, and a lock is stolen only when `kill -0` says that
# pid is gone. There is no timeout to tune and no slow-run hazard left.
#
# The age check survives only as the fallback for a lock with no readable pid,
# which is a real state: mkdir succeeds and the write of the pid file can still
# fail (a full or read-only volume), and a lock from an older version of this
# code has no pid file at all. An hour is deliberately far longer than the ten
# minutes it replaces, because this branch is now guesswork rather than the
# primary mechanism and should almost never be the thing that frees a lock.
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
