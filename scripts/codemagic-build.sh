#!/usr/bin/env bash
#
# Start a Codemagic build.
#
# This file exists so that "Claude may trigger a build" can be granted as a
# permission without also granting "Claude may POST anywhere with a token".
# Claude Code's auto mode blocks an authenticated POST to an external service,
# correctly -- it spends build minutes and this project's Android workflow
# publishes to a Play track. The allow rule in .claude/settings.local.json names
# this script and nothing else, so the grantable surface is the code below,
# which is in git and shows up in a diff when it changes.
#
#   scripts/codemagic-build.sh <workflow-id> [branch]
#
# Reads CODEMAGIC_API_TOKEN from the environment. Never echoes it.

set -euo pipefail

# The mgk-fitness app in Codemagic. Hardcoded rather than taken as an argument:
# the same token also reaches frunt-mobile, and nothing here should be able to
# start a build in another product.
readonly APP_ID="6a7a17bc06c948c981e49bd2"
readonly API="https://api.codemagic.io"

usage() {
  echo "usage: $0 <workflow-id> [branch]" >&2
  echo >&2
  echo "workflows declared in codemagic.yaml:" >&2
  printf '  %s\n' "${WORKFLOWS[@]}" >&2
}

# The allowlist is read from codemagic.yaml rather than written here, so a
# workflow renamed in one place cannot be silently missing from the other.
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mapfile -t WORKFLOWS < <(
  awk '/^workflows:/{f=1;next} f && /^  [a-z][a-z0-9-]*:/{gsub(/[ :]/,"");print}' \
    "$repo_root/codemagic.yaml"
)

if [[ $# -lt 1 || $# -gt 2 ]]; then usage; exit 2; fi

workflow="$1"
branch="${2:-main}"

if [[ ! " ${WORKFLOWS[*]} " == *" $workflow "* ]]; then
  echo "unknown workflow: $workflow" >&2
  usage
  exit 2
fi

if [[ -z "${CODEMAGIC_API_TOKEN:-}" ]]; then
  echo "CODEMAGIC_API_TOKEN is not set" >&2
  exit 1
fi

# Say what is about to happen before it happens. A release workflow's publishing
# block is the part worth reading twice -- run-android-release uploads an AAB to
# the Play internal track on success.
echo "starting $workflow on $branch"
if grep -q "^  $workflow:" "$repo_root/codemagic.yaml" \
   && awk -v w="  $workflow:" '$0==w{f=1;next} f&&/^  [a-z]/{exit} f' \
        "$repo_root/codemagic.yaml" | grep -qE '^\s{4}publishing:'; then
  echo "  NOTE: this workflow has a live publishing: block"
fi

response="$(
  curl -fsS -X POST "$API/builds" \
    -H "x-auth-token: $CODEMAGIC_API_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"appId\":\"$APP_ID\",\"workflowId\":\"$workflow\",\"branch\":\"$branch\"}"
)"

build_id="$(printf '%s' "$response" | python -c \
  'import sys,json; print(json.load(sys.stdin).get("buildId",""))' 2>/dev/null || true)"

if [[ -z "$build_id" ]]; then
  echo "no buildId in response: $response" >&2
  exit 1
fi

echo "build $build_id"
echo "https://codemagic.io/app/$APP_ID/build/$build_id"
