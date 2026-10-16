# shellcheck shell=bash
# The one answer to "may an allow hook approve git's -C here", so that hooks
# approving a git -C cannot disagree; git-dash-c-allow.sh sources it. Sourced:
# no shebang, no shell options. The caller must also refuse a -C value the shell
# expands (see SCAN_ARGV_EXPANDS): this resolves the text it is given.
#
#   git_workdir_in_project <cwd> <project> [<-C value>...]
#
# Resolves the directory git would work in after the given -C values, applied
# in order the way git applies them -- each relative to the last, an empty one
# meaning none -- and returns 0 only when it resolves, physically, inside
# <project> or to it. Physically, so a symlink inside the project that points
# out of it does not count as inside, and the textual `..` after a symlink is
# taken from the symlink's target, as chdir takes it. A directory that does not
# exist cannot be resolved, and returns 1.

git_workdir_in_project() {
  local cur=$1 project=$2 d resolved root
  shift 2
  [[ -n "$cur" && -n "$project" ]] || return 1
  for d in "$@"; do
    [[ -n "$d" ]] || continue
    if [[ "$d" == /* ]]; then cur=$d; else cur="$cur/$d"; fi
  done
  resolved=$(cd -P -- "$cur" 2>/dev/null && pwd -P) || return 1
  root=$(cd -P -- "$project" 2>/dev/null && pwd -P) || return 1
  [[ "$resolved" == "$root" || "$resolved" == "$root"/* ]]
}
