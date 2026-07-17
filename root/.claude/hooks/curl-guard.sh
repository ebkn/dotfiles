#!/bin/bash
# Auto-approve curl invocations that provably target an allow-listed host with
# no dangerous flags, letting them skip the blanket `Bash(curl *)` ask rule.
#
# Why a hook instead of `Bash(curl *<domain>*)` allow rules: permission patterns
# match the raw command string and do no URL parsing, so `curl *github.com*`
# also matches `curl https://evil.com/?ref=github.com`. Anthropic documents this
# class of rule as fragile and recommends a PreToolUse hook instead.
# See: https://code.claude.com/docs/en/permissions.md (Bash / Wildcard patterns)
#
# Fail-closed by design: this hook only ever emits "allow". Anything it cannot
# fully verify -- unknown host, dangerous flag, shell expansion, a non-curl
# segment -- emits no decision, leaving `Bash(curl *)` to prompt as it does now.
# A bug here therefore degrades to "you get asked", never to "it runs".
#
# The host allow-list is derived from the WebFetch(domain:...) rules in
# settings.json so curl and WebFetch stay in sync from a single source.
# Matching is exact host, mirroring WebFetch: api.github.com does not inherit
# github.com.
#
# Docs: https://docs.claude.com/en/hooks

set -euo pipefail

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')

[[ -n "$COMMAND" ]] || exit 0

# Only engage when curl appears as a bare word; otherwise leave the call alone.
[[ "$COMMAND" =~ (^|[^[:alnum:]_./-])curl([^[:alnum:]_./-]|$) ]] || exit 0

# Any shell expansion makes the final argv unknowable at this point, so the
# host we would verify is not necessarily the host curl ends up contacting.
case "$COMMAND" in
  *'$'* | *'`'* | *$'\n'*) exit 0 ;;
esac

SETTINGS="${HOME}/.claude/settings.json"
[[ -f "$SETTINGS" ]] || exit 0

allowed_hosts=$(jq -r '
  .permissions.allow[]?
  | capture("^WebFetch\\(domain:(?<d>[^)]+)\\)$")
  | .d
' "$SETTINGS" 2>/dev/null) || exit 0
[[ -n "$allowed_hosts" ]] || exit 0

host_is_allowed() {
  local host=$1 allowed
  while IFS= read -r allowed; do
    [[ -n "$allowed" ]] || continue
    [[ "$host" == "$allowed" ]] && return 0
  done <<<"$allowed_hosts"
  return 1
}

# Extract the hostname from a URL the way curl resolves it: strip the scheme,
# drop any userinfo before '@', then cut at the first '/', '?' or '#', and drop
# a trailing :port. Rejects anything that is not a plain http(s) URL.
url_host() {
  local url=$1 rest host
  case "$url" in
    http://*) rest=${url#http://} ;;
    https://*) rest=${url#https://} ;;
    *) return 1 ;;
  esac
  rest=${rest%%[/?#]*}
  rest=${rest##*@}
  host=${rest%%:*}
  [[ -n "$host" ]] || return 1
  # A bare host only: no stray delimiters that would mean we mis-parsed.
  [[ "$host" =~ ^[A-Za-z0-9.-]+$ ]] || return 1
  printf '%s' "$host"
}

# Flags that are read-only and cannot redirect curl to another host, write a
# file, or attach credentials. Anything absent from these two lists defers.
is_safe_flag() {
  case "$1" in
    -s | --silent | -S | --show-error | -f | --fail | --fail-with-body | \
      -i | --include | -I | --head | -v | --verbose | --compressed | -G | --get)
      return 0
      ;;
  esac
  # Bundled short flags (-sS, -sSf): safe only if every letter is itself a safe
  # valueless flag. A value-taking letter (-m10) or an unsafe one (-sSL) defers.
  if [[ "$1" =~ ^-[A-Za-z]{2,}$ ]]; then
    local rest=${1#-}
    while [[ -n "$rest" ]]; do
      case "${rest:0:1}" in
        s | S | f | i | I | v | G) ;;
        *) return 1 ;;
      esac
      rest=${rest:1}
    done
    return 0
  fi
  return 1
}

# Safe flags that consume the following token as their value.
takes_value() {
  case "$1" in
    -m | --max-time | --connect-timeout | --retry | --retry-max-time | \
      -A | --user-agent | -H | --header | -X | --request)
      return 0
      ;;
  esac
  return 1
}

# Headers that would hand a secret to the remote host.
header_is_safe() {
  local lower
  lower=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    authorization:* | proxy-authorization:* | cookie:* | x-api-key:* | \
      x-auth-token:* | x-amz-security-token:*)
      return 1
      ;;
  esac
  return 0
}

segment_is_safe() {
  local seg=$1 tokens=() tok url="" saw_curl=0

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
      # Accept `curl` and absolute paths to it, nothing else.
      [[ "$tok" == "curl" || "$tok" == */curl ]] || return 1
      saw_curl=1
      ((i++))
      continue
    fi

    if [[ "$tok" == -* ]]; then
      # Reject --flag=value: the value is unvalidated and -X=POST style would
      # otherwise slip past the -X check below.
      [[ "$tok" == *=* ]] && return 1

      if takes_value "$tok"; then
        ((i + 1 < ${#tokens[@]})) || return 1
        local val=${tokens[i + 1]}
        case "$tok" in
          -H | --header)
            header_is_safe "$val" || return 1
            ;;
          -X | --request)
            # Only non-mutating methods.
            [[ "$val" == "GET" || "$val" == "HEAD" ]] || return 1
            ;;
        esac
        ((i += 2))
        continue
      fi

      is_safe_flag "$tok" || return 1
      ((i++))
      continue
    fi

    # A non-flag token is a URL. Exactly one is permitted, so a second URL
    # (which curl would also fetch) cannot ride along unchecked.
    [[ -z "$url" ]] || return 1
    url=$tok
    ((i++))
  done

  ((saw_curl)) || return 1
  [[ -n "$url" ]] || return 1

  local host
  host=$(url_host "$url") || return 1
  host_is_allowed "$host" || return 1
  return 0
}

# Split on every shell operator curl output could be piped or chained into.
# Splitting inside a quoted URL query (`?a=1&b=2`) yields a fragment that is not
# a curl call, which fails closed into a prompt -- acceptable, never unsafe.
segments=$(printf '%s' "$COMMAND" | sed -E 's/(\|\||&&|\|&|[;|&])/\n/g')

while IFS= read -r segment; do
  segment="${segment#"${segment%%[![:space:]]*}"}"
  segment="${segment%"${segment##*[![:space:]]}"}"
  [[ -n "$segment" ]] || continue
  # Every segment must independently be a safe curl. A single unverifiable
  # segment defers the whole command, because "allow" would approve all of it.
  segment_is_safe "$segment" || exit 0
done <<<"$segments"

jq -n '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "allow",
    permissionDecisionReason: "curl targets a WebFetch allow-listed host with no dangerous flags (curl-guard)"
  }
}'
