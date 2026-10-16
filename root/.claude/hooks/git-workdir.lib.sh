# shellcheck shell=bash
# The one answer to "may an allow hook approve git's -C here", so that hooks
# approving a git -C cannot disagree; git-dash-c-allow.sh sources it. Sourced:
# no shebang, no shell options.
#
#   git_dash_c_in_project <cwd> <project> <git argv...>
#
# Reads the leading `-C <dir>` pairs of a git argv ($3 is `git`), as read by
# segment-scan.lib.sh, and returns 0 when there are none or they land inside
# <project>. A -C with no value is refused, and so is one the shell would
# expand (SCAN_ARGV_EXPANDS, set by the scanner while its predicate runs):
# resolved as read, a project directory named `~` passes while the shell runs
# git in $HOME. Afterwards GIT_DASH_C_NEXT is the argv index of the first word
# after the pairs and GIT_DASH_C_SEEN whether there were any.
GIT_DASH_C_NEXT=1
GIT_DASH_C_SEEN=0
git_dash_c_in_project() {
  local cwd=$1 project=$2
  shift 2
  local argv=("$@") n=$# i=1 dirs=()
  GIT_DASH_C_NEXT=1 GIT_DASH_C_SEEN=0
  while ((i < n)) && [[ "${argv[i]}" == "-C" ]]; do
    ((i + 1 < n)) || return 1
    [[ "${SCAN_ARGV_EXPANDS[i + 1]:-0}" == 0 ]] || return 1
    dirs[${#dirs[@]}]=${argv[i + 1]}
    i=$((i + 2))
  done
  # shellcheck disable=SC2034 # an output, read by the sourcing hook
  GIT_DASH_C_NEXT=$i
  ((${#dirs[@]})) || return 0
  # shellcheck disable=SC2034 # an output, read by the sourcing hook
  GIT_DASH_C_SEEN=1
  _git_workdir_in_project "$cwd" "$project" "${dirs[@]}"
}

# Internal: hooks call git_dash_c_in_project, which refuses what this cannot
# see -- a missing value, or one the shell would expand. Given only text, this
# resolves the directory git would work in after the given -C values, applied in
# order the way git applies them -- each relative to the last, an empty one
# meaning none -- and returns 0 only when it resolves, physically, inside
# <project> or to it. Physically, so a symlink inside the project that points
# out of it does not count as inside, and the textual `..` after a symlink is
# taken from the symlink's target, as chdir takes it. A directory that does not
# exist cannot be resolved, and returns 1.

_git_workdir_in_project() {
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
