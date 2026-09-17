#!/bin/bash
# Auto-approve `rm` invocations that provably stay inside a disposable scratch
# directory, letting them skip the blanket `Bash(rm *)` ask rule.
#
# Why the ask rule exists at all: an `ask` rule is evaluated before the auto-mode
# classifier and can never be auto-approved, and it is the only gate on `rm`
# under acceptEdits and bypassPermissions. `rm`'s false negative -- a deleted
# git-untracked file (.env, a local DB, working data) -- is unrecoverable, which
# is why it is worth disabling the classifier's better-informed judgement for.
# See root/README.md "Destructive filesystem permissions".
#
# Why a hook instead of an allow glob like `Bash(rm ./tmp/*)`: permission
# patterns match the raw command string and do no path resolution, so that
# pattern also matches `rm ./tmp/../../important`. Same fragility Anthropic
# documents for curl. This hook resolves each operand's parent directory
# physically (so a symlinked ancestor cannot smuggle the target elsewhere) and
# compares the result against the scratch roots.
#
# Fail-closed by design, exactly like curl-guard.sh: this hook only ever emits
# "allow". Anything it cannot fully verify -- a glob, a redirection, a shell
# expansion, an unknown flag, a path outside the roots, a non-rm segment --
# emits no decision and leaves `Bash(rm *)` to prompt as it does today. A bug
# here therefore degrades to "you get asked", never to "it runs".
#
# Measured scope (see root/README.md): roughly a quarter of `rm` calls are a
# lone scratch-dir cleanup and are covered here. The rest are compound commands
# (`rm -rf tmp; git status --short`), which defer because approving the call
# would approve every segment of it, not just the rm.
#
# Docs: https://docs.claude.com/en/hooks

set -euo pipefail

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')

[[ -n "$COMMAND" ]] || exit 0
[[ -n "$CWD" && -d "$CWD" ]] || exit 0

# Only engage when rm appears as a bare word; otherwise leave the call alone.
[[ "$COMMAND" =~ (^|[^[:alnum:]_./-])rm([^[:alnum:]_./-]|$) ]] || exit 0

# Any shell expansion makes the final argv unknowable at this point, so the path
# we would verify is not necessarily the path rm ends up unlinking.
case "$COMMAND" in
  *'$'* | *'`'* | *$'\n'*) exit 0 ;;
esac

CWD_P=$(cd -P "$CWD" 2>/dev/null && pwd -P) || exit 0

# Scratch roots, canonicalised the same way operands are so the macOS
# /tmp -> /private/tmp symlink cannot cause a spurious mismatch.
canon_dir() {
  (cd -P "$1" 2>/dev/null && pwd -P) || return 1
}

ROOTS=()
# The project-local scratch dir this repo's CLAUDE.md mandates for temp files.
PROJECT_TMP="${CWD_P}/tmp"
ROOTS+=("$PROJECT_TMP")

# Claude Code's own per-session scratchpad tree for this uid. Only paths *under*
# it qualify: the tree root itself holds every session's scratchpad.
uid=$(id -u)
for candidate in "/tmp/claude-${uid}" "/private/tmp/claude-${uid}"; do
  if resolved=$(canon_dir "$candidate"); then
    SCRATCH_ROOT="$resolved"
    break
  fi
done

# Resolve an operand to an absolute path, resolving its *parent* physically.
# rm unlinks the name, not the target, so the final component must stay
# unresolved -- but a symlinked ancestor really does redirect the whole path,
# so the parent must be resolved. A final component of . or .. is refused
# outright rather than reasoned about.
resolve_operand() {
  local p=$1 dir base rdir
  [[ "$p" == /* ]] || p="${CWD_P}/${p}"
  dir=$(dirname "$p")
  base=$(basename "$p")
  [[ "$base" == "." || "$base" == ".." || -z "$base" ]] && return 1
  rdir=$(canon_dir "$dir") || return 1
  printf '%s/%s' "${rdir%/}" "$base"
}

operand_is_safe() {
  local p=$1 resolved
  resolved=$(resolve_operand "$p") || return 1

  # The project scratch dir itself is disposable, so allow removing it whole.
  [[ "$resolved" == "$PROJECT_TMP" ]] && return 0

  local root
  for root in "${ROOTS[@]}"; do
    [[ "$resolved" == "$root"/* ]] && return 0
  done
  # Strictly under the session scratchpad tree, never the tree root.
  if [[ -n "${SCRATCH_ROOT:-}" ]]; then
    [[ "$resolved" == "$SCRATCH_ROOT"/*/* ]] && return 0
  fi
  return 1
}

# Valueless flags that cannot make rm reach outside the named operands.
is_safe_flag() {
  case "$1" in
    -r | -R | --recursive | -f | --force | -v | --verbose | -d | --dir)
      return 0
      ;;
  esac
  # Bundled short flags (-rf, -rfv): safe only if every letter is itself safe.
  if [[ "$1" =~ ^-[rRfvd]+$ ]]; then
    return 0
  fi
  return 1
}

segment_is_safe() {
  local seg=$1 tokens=() tok saw_rm=0 operands=0 end_of_flags=0

  local split
  split=$(printf '%s' "$seg" | xargs -n1 2>/dev/null) || return 1
  while IFS= read -r tok; do
    [[ -n "$tok" ]] && tokens+=("$tok")
  done <<<"$split"

  ((${#tokens[@]})) || return 1

  local i=0
  while ((i < ${#tokens[@]})); do
    tok=${tokens[i]}

    if ((i == 0)); then
      # The bare word only. A path-qualified `/bin/rm` never reaches here (the
      # engage regex above excludes a leading `/`), and it does not need to:
      # `Bash(rm *)` does not match it either, so it was never deferred to us.
      [[ "$tok" == "rm" ]] || return 1
      saw_rm=1
      ((i++))
      continue
    fi

    # A glob's expansion is decided by the shell after this hook runs, and a
    # redirection is not an operand at all. Neither is verifiable here.
    case "$tok" in
      *'*'* | *'?'* | *'['* | *'<'* | *'>'*) return 1 ;;
    esac

    if [[ "$tok" == "--" && $end_of_flags -eq 0 ]]; then
      end_of_flags=1
      ((i++))
      continue
    fi

    if [[ "$tok" == -* && $end_of_flags -eq 0 ]]; then
      is_safe_flag "$tok" || return 1
      ((i++))
      continue
    fi

    operand_is_safe "$tok" || return 1
    operands=$((operands + 1))
    ((i++))
  done

  ((saw_rm)) || return 1
  ((operands)) || return 1
  return 0
}

# Split on every shell operator an rm could be chained with.
segments=$(printf '%s' "$COMMAND" | sed -E 's/(\|\||&&|\|&|[;|&])/\n/g')

while IFS= read -r segment; do
  segment="${segment#"${segment%%[![:space:]]*}"}"
  segment="${segment%"${segment##*[![:space:]]}"}"
  [[ -n "$segment" ]] || continue
  # Every segment must independently be a safe rm. A single unverifiable segment
  # defers the whole command, because "allow" would approve all of it.
  segment_is_safe "$segment" || exit 0
done <<<"$segments"

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    permissionDecisionReason: "every rm operand resolves inside a disposable scratch dir (rm-guard)"
  }
}'
