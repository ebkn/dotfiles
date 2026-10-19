# Sourced by bin/zinit-cooldown and bin/lazy-cooldown: the parts of the gate
# both apply, kept in one place because each is easy to get subtly wrong. The
# caller has run `emulate -L zsh`, `setopt extendedglob pipefail` and
# `zmodload zsh/datetime`. See bin/zinit-cooldown.md.

# cooldown_cutoff <days> — sets $cutoff, that many days before now. GitHub's
# timestamps are UTC ISO 8601, which order as strings.
cooldown_cutoff() {
  cutoff=$(TZ=UTC strftime '%Y-%m-%dT%H:%M:%SZ' $(( EPOCHSECONDS - $1 * 86400 )))
}

api() { command gh api "$@"; }

# status <repo> <base> <head> — GitHub's compare status of head against base:
# ahead, behind, identical or diverged.
status() { api "repos/$1/compare/$2...$3" | jq -er .status; }

# tip_at <repo> <branch> — the branch's tip at $cutoff: the newest push
# GitHub's activity log records at or before it. A push's time is GitHub's,
# which the pusher cannot set. Prints nothing when no push that old is on
# record. Status 1 when the log cannot be read or parsed; 2 when that push
# deleted the branch, so it did not exist at the cutoff -- a rename shows up
# as a deletion too, and its `after` is the zero SHA, not a commit.
# One call: asking again to tell "unreadable" from "empty" could get a
# different answer the second time.
tip_at() {
  local activity tip
  activity=$(api "repos/$1/activity?ref=refs/heads/$2&per_page=100") || return 1
  tip=$(jq -r --arg c "$cutoff" '[.[] | select(.timestamp <= $c)][0].after // empty' <<<$activity) || return 1
  [[ -n $tip && $tip == 0## ]] && return 2
  print -r -- $tip
}

# rewrite_once <file> <old> <new> — replace the one occurrence of <old> in
# <file>. Status 0 rewritten; 1 <old> does not appear exactly once, with the
# number found in $count; 2 the write failed, the file left as it was.
# The rewrite is a plain substitution, so the SHA must appear exactly once --
# counted by occurrence, not by line: a comment quoting the SHA on the pin's
# own line would leave the old one behind. `read -d ''` keeps the file byte
# for byte, trailing newlines included, which $(<file) would strip; the new
# file replaces the old with mv, so a failure part-way leaves the old one
# whole.
rewrite_once() {
  local content
  IFS= read -rd '' content < $1
  count=$(( ${#${(ps:$2:)${:-x${content}x}}} - 1 ))
  (( count == 1 )) || return 1
  if ! { print -rn -- "${content/$2/$3}" > $1.cooldown && command mv -f $1.cooldown $1; }; then
    command rm -f $1.cooldown
    return 2
  fi
}
