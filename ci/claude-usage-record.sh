#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Distil a claude-code-action execution file into one compact usage
## record, and mirror it into ${GITHUB_STEP_SUMMARY}.
##
## Why this exists: an OAuth-token run spends Claude subscription
## quota, and the action reports no remaining quota and - with
## 'display_report' off, its default - no cost figure either. The
## execution file is the only per-run source of truth, it is written
## to ${RUNNER_TEMP} and never uploaded. Without this step a run
## leaves no evidence of what it cost.
##
## The record carries NUMBERS AND METADATA ONLY. Message bodies, the
## final result text and every other model-authored or
## repository-derived string are dropped on purpose, so the artifact
## can be collected centrally without carrying repository content or
## injected text off the runner.
##
## R-093: self-contained apart from the sibling step-summary-emit.sh
## (no helper-scripts source) so it runs from workflow steps that
## have not installed helper-scripts.
##
## Usage:
##   ci/claude-usage-record.sh \
##      --execution-file "${RUNNER_TEMP}/claude-execution-output.json" \
##      --output         "${RUNNER_TEMP}/claude-usage.json" \
##      [--job-status success]

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose

execution_file=''
output=''
job_status='unknown'

print_usage() {
   cat <<'EOF'
Distil a claude-code-action execution file into one compact usage
record, and mirror it into ${GITHUB_STEP_SUMMARY}.

Usage:
   ci/claude-usage-record.sh \
      --execution-file "${RUNNER_TEMP}/claude-execution-output.json" \
      --output         "${RUNNER_TEMP}/claude-usage.json" \
      [--job-status success]
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
      --execution-file)
         [ "$#" -ge 2 ] || die_with_usage 'missing value for --execution-file'
         execution_file="$2"
         shift 2
         ;;
      --output)
         [ "$#" -ge 2 ] || die_with_usage 'missing value for --output'
         output="$2"
         shift 2
         ;;
      --job-status)
         [ "$#" -ge 2 ] || die_with_usage 'missing value for --job-status'
         job_status="$2"
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

[ -n "${execution_file}" ] || die_with_usage 'missing --execution-file'
[ -n "${output}" ] || die_with_usage 'missing --output'

## Fail loud. This step only runs when the action reported an
## execution file, so a missing or unparsable one means the contract
## with the action changed - silently emitting an empty record would
## under-report spend, which is the exact failure this guards.
[ -f "${execution_file}" ] \
   || die "claude-usage-record: execution file not found: ${execution_file}"

my_dir="$(dirname -- "$(readlink --canonicalize -- "$0")")"

[ -v GITHUB_REPOSITORY ] || GITHUB_REPOSITORY=''
[ -v GITHUB_WORKFLOW ] || GITHUB_WORKFLOW=''
[ -v GITHUB_EVENT_NAME ] || GITHUB_EVENT_NAME=''
[ -v GITHUB_ACTOR ] || GITHUB_ACTOR=''
[ -v GITHUB_RUN_ID ] || GITHUB_RUN_ID=''
[ -v GITHUB_RUN_ATTEMPT ] || GITHUB_RUN_ATTEMPT=''
[ -v GITHUB_SERVER_URL ] || GITHUB_SERVER_URL='https://github.com'
[ -v GITHUB_EVENT_PATH ] || GITHUB_EVENT_PATH=''

run_url="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"

## The PR or issue the mention came from, so a central ledger can
## attribute spend to a thread without re-querying the API.
entity_number=''
if [ -n "${GITHUB_EVENT_PATH}" ] && [ -f "${GITHUB_EVENT_PATH}" ]; then
   entity_number="$(jq --raw-output \
      '(.issue.number // .pull_request.number // empty)' \
      -- "${GITHUB_EVENT_PATH}")"
fi

recorded_at="$(date --utc '+%Y-%m-%dT%H:%M:%SZ')"

## The result fields below carry no jq alternative operator on
## purpose: jq already yields null for a missing key, while the
## alternative operator would rewrite a legitimate false (is_error)
## or a legitimate 0 into null, erasing the difference between a
## clean run and a run whose outcome was never reported. The usage
## counters keep their 0 fallback because a missing usage block
## there means nothing was counted, not that counting failed.
jq \
   --arg schema 'claude-ci-usage/1' \
   --arg recorded_at "${recorded_at}" \
   --arg repository "${GITHUB_REPOSITORY}" \
   --arg workflow "${GITHUB_WORKFLOW}" \
   --arg event "${GITHUB_EVENT_NAME}" \
   --arg actor "${GITHUB_ACTOR}" \
   --arg run_id "${GITHUB_RUN_ID}" \
   --arg run_attempt "${GITHUB_RUN_ATTEMPT}" \
   --arg run_url "${run_url}" \
   --arg job_status "${job_status}" \
   --arg entity_number "${entity_number}" \
   '
   ([.[] | select(.type == "result")] | last // {}) as $result
   | {
      schema: $schema,
      recorded_at: $recorded_at,
      repository: $repository,
      workflow: $workflow,
      event: $event,
      actor: $actor,
      entity_number: (if $entity_number == "" then null else ($entity_number | tonumber) end),
      run_id: $run_id,
      run_attempt: $run_attempt,
      run_url: $run_url,
      job_status: $job_status,
      models: ([.[] | select(.type == "assistant") | .message.model?]
               | map(select(. != null)) | unique),
      subtype: $result.subtype,
      is_error: $result.is_error,
      num_turns: $result.num_turns,
      duration_ms: $result.duration_ms,
      total_cost_usd: $result.total_cost_usd,
      usage: {
         input_tokens: ($result.usage.input_tokens // 0),
         output_tokens: ($result.usage.output_tokens // 0),
         cache_creation_input_tokens: ($result.usage.cache_creation_input_tokens // 0),
         cache_read_input_tokens: ($result.usage.cache_read_input_tokens // 0)
      }
   }' \
   -- "${execution_file}" \
   > "${output}"

## Echoed to the job log as well as the summary: the log survives
## even when a later step fails before the artifact is uploaded.
printf '%s\n' 'claude-usage-record:'
cat -- "${output}"

models="$(jq --raw-output '.models | join(", ")' -- "${output}")"
[ -n "${models}" ] || models='unknown'

"${my_dir}/step-summary-emit.sh" \
   --tool 'Claude usage (subscription quota spent)' \
   --column-header metric \
   --row "models=${models}" \
   --row "turns=$(jq --raw-output '.num_turns // "?"' -- "${output}")" \
   --row "duration_ms=$(jq --raw-output '.duration_ms // "?"' -- "${output}")" \
   --row "input_tokens=$(jq --raw-output '.usage.input_tokens' -- "${output}")" \
   --row "output_tokens=$(jq --raw-output '.usage.output_tokens' -- "${output}")" \
   --row "cache_creation_input_tokens=$(jq --raw-output '.usage.cache_creation_input_tokens' -- "${output}")" \
   --row "cache_read_input_tokens=$(jq --raw-output '.usage.cache_read_input_tokens' -- "${output}")" \
   --row "api_equivalent_cost_usd=$(jq --raw-output '.total_cost_usd // "?"' -- "${output}")" \
   --row "outcome=${job_status}" \
   --details-url "${run_url}"
