#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Assert that every name in the Claude review roster actually holds
## write on every repository that runs the Claude review workflow.
##
## Why this exists: GitHub Actions exposes no expression for "does
## this actor have write on this repo", so the workflow's pre-runner
## gate has to name accounts, and that list is a duplicate of the
## repository permissions it stands in for. Duplication that nobody
## checks drifts: a roster member demoted to read still passes the
## gate, and claude-code-action then hard-fails at the OIDC app-token
## exchange with
##
##   App token exchange failed: 401 Unauthorized -
##     User does not have write access on this repository
##
## which surfaces as a red X on somebody's PR, weeks later, with no
## hint at the cause. This turns that silent drift into a loud audit
## failure. The roster stays the single place a name is written; this
## script only checks it against reality.
##
## Roster source of truth is the 'allowed-users' default in
## .github/workflows/reusable-claude-code-review.yml - not a copy
## here.
##
## R-093: self-contained (no helper-scripts source) so it runs from
## workflow steps that have not installed helper-scripts.
##
## Expected env:
##   GITHUB_TOKEN - needs, per endpoint used below:
##                    Organization: Members            read  (repo listing)
##                    Repository:   Metadata           read  (always implied)
##                    Repository:   Contents           read  (workflow probe)
##                    Repository:   Administration     read  (collaborator
##                                                            permission)
##                  Administration alone is NOT sufficient.
##
## Usage:
##   ci/claude-roster-verify.sh [--org org-ai-assisted] \
##      [--reusable .github/workflows/reusable-claude-code-review.yml]

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose

org='org-ai-assisted'
reusable='.github/workflows/reusable-claude-code-review.yml'
consumer_path='.github/workflows/consumer-claude-code.yml'

print_usage() {
   cat <<'EOF'
Assert that every name in the Claude review roster holds write on
every repository that runs the Claude review workflow.

Usage:
   ci/claude-roster-verify.sh [--org ORG] [--reusable PATH]

Requires GITHUB_TOKEN with permission to read collaborator
permissions.
EOF
}

die_with_usage() {
   printf '%s\n' "$1" >&2
   print_usage >&2
   exit 64
}

die() {
   printf '%s\n' "$1" >&2
   exit 1
}

while [ "$#" -gt 0 ]; do
   case "$1" in
      --org)
         [ "$#" -ge 2 ] || die_with_usage 'missing value for --org'
         org="$2"
         shift 2
         ;;
      --reusable)
         [ "$#" -ge 2 ] || die_with_usage 'missing value for --reusable'
         reusable="$2"
         shift 2
         ;;
      --)
         shift
         break
         ;;
      -h|--help)
         print_usage
         exit 0
         ;;
      *)
         die_with_usage "unknown flag: '$1'"
         ;;
   esac
done

[ -v GITHUB_TOKEN ] || die 'claude-roster-verify: GITHUB_TOKEN is not set'
[ -f "${reusable}" ] || die "claude-roster-verify: no such file: ${reusable}"

body_file="$(mktemp)"
cleanup() {
   safe-rm --force -- "${body_file}"
}
trap cleanup EXIT

## Prints the HTTP status and writes the body to ${body_file}. Deliberately
## NOT --fail-with-body: this audit exists to prove a negative, so it must be
## able to tell 404 ("this repo does not carry the workflow") apart from 403 /
## 429 / 5xx / a transport failure. Collapsing those into one non-zero exit is
## what turns a rate-limited scan into a false pass. A transport failure gets
## the synthetic status 000 so every caller's case statement sees it.
api_status() {
   local path="$1" code status
   status=0
   code="$(curl \
      --silent \
      --show-error \
      --max-time 30 \
      --output "${body_file}" \
      --write-out '%{http_code}' \
      --header "Authorization: Bearer ${GITHUB_TOKEN}" \
      --header 'Accept: application/vnd.github+json' \
      --header 'X-GitHub-Api-Version: 2022-11-28' \
      -- "https://api.github.com${path}")" || status="$?"
   if [ "${status}" -ne 0 ]; then
      printf '000\n'
      return 0
   fi
   printf '%s\n' "${code}"
}

## Every caller funnels its unexpected statuses here, so no endpoint can
## quietly decide that an error means "absent".
die_on_status() {
   die "claude-roster-verify: GET ${1} returned HTTP ${2}; refusing to report a verdict from an incomplete scan"
}

## The roster is the only quoted 'default:' in the reusable
## (timeout-minutes carries a bare number). Requiring exactly one
## match makes a change to the file's shape a loud failure here
## rather than a silently empty roster that verifies nothing.
declare -a roster_lines=()
mapfile -t roster_lines < <(grep --extended-regexp \
   '^ +default: "[A-Za-z0-9,_-]+"$' -- "${reusable}")

if [ "${#roster_lines[@]}" -ne 1 ]; then
   die "claude-roster-verify: expected exactly 1 quoted default in ${reusable}, found ${#roster_lines[@]}"
fi

roster="${roster_lines[0]#*\"}"
roster="${roster%\"}"
[ -n "${roster}" ] || die 'claude-roster-verify: roster is empty'

## Default line delimiter, not -d '': a herestring appends a newline,
## and -d '' would fold it into the last field, yielding a member
## name with a trailing newline.
declare -a members=()
IFS=',' read -r -a members <<< "${roster}"

printf '%s\n' "roster: ${roster}"

declare -a repos=()
page=1
while true; do
   repos_path="/orgs/${org}/repos?per_page=100&type=all&page=${page}"
   code="$(api_status "${repos_path}")"
   if [ "${code}" != '200' ]; then
      die_on_status "${repos_path}" "${code}"
   fi
   ## Parse in its own step, not inside the mapfile process substitution:
   ## there, a jq failure cannot reach errexit, so a malformed page would
   ## yield an empty batch, break the loop, and pass the audit having
   ## scanned only part of the org.
   names="$(jq --raw-output '.[].name' -- "${body_file}")"
   if [ -z "${names}" ]; then
      break
   fi
   declare -a batch=()
   mapfile -t batch <<< "${names}"
   repos+=( "${batch[@]}" )
   page=$(( page + 1 ))
done

printf '%s\n' "scanning ${#repos[@]} repo(s) in ${org} for ${consumer_path} ..."

declare -a drift=()
claude_repos=0

for repo in "${repos[@]}"; do
   contents_path="/repos/${org}/${repo}/contents/${consumer_path}"
   code="$(api_status "${contents_path}")"
   case "${code}" in
      200)
         ;;
      404)
         ## The only status that legitimately means "this repo does not
         ## run the Claude workflow".
         continue
         ;;
      *)
         die_on_status "${contents_path}" "${code}"
         ;;
   esac
   claude_repos=$(( claude_repos + 1 ))
   for member in "${members[@]}"; do
      permission_path="/repos/${org}/${repo}/collaborators/${member}/permission"
      code="$(api_status "${permission_path}")"
      case "${code}" in
         200)
            ;;
         404)
            ## Not a collaborator at all: real drift, not an error.
            drift+=( "${org}/${repo}: ${member} is not a collaborator, needs write" )
            continue
            ;;
         *)
            die_on_status "${permission_path}" "${code}"
            ;;
      esac
      permission="$(jq --raw-output '.permission // "none"' -- "${body_file}")"
      case "${permission}" in
         admin|write)
            ;;
         *)
            drift+=( "${org}/${repo}: ${member} has '${permission}', needs write" )
            ;;
      esac
   done
done

printf '%s\n' "repos running the Claude review workflow: ${claude_repos}"

if [ "${claude_repos}" -eq 0 ]; then
   die 'claude-roster-verify: no repo carries the Claude workflow - the scan proved nothing'
fi

if [ "${#drift[@]}" -gt 0 ]; then
   printf '%s\n' 'claude-roster-verify: roster drift detected:' >&2
   printf '  %s\n' "${drift[@]}" >&2
   printf '%s\n' \
      'Fix by granting write, or by removing the name from the allowed-users default.' >&2
   exit 1
fi

printf '%s\n' 'claude-roster-verify: every roster member holds write everywhere'
