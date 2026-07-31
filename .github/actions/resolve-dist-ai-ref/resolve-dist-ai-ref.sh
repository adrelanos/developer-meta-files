#!/bin/bash

## Copyright (C) 2026 - 2026 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
## See the file COPYING for copying conditions.

## AI-Assisted

## Decide which org-ai-assisted/dist-ai ref a CI job should check out, and
## emit it as `ref=` on $GITHUB_OUTPUT.
##
## WHY THIS EXISTS: dist-ai was pinned to 'master' for every consumer.
## dist-ai holds the tests; the consumers hold the behaviour those tests
## assert. So a change that alters behaviour AND its expectations could
## not be tested atomically:
##
##   * the consumer PR runs against dist-ai@master, which still has the
##     OLD expectations -> red;
##   * pushing the new expectations to dist-ai master first breaks
##     dist-ai's own CI against the consumer's unchanged master -> red.
##
## Chicken-and-egg, with no green path between the two states. Observed
## on a coordinated developer-meta-files + dist-ai change where the
## policy side landed on a branch and the test side had nowhere to go.
##
## THE RULE: a COMPANION BRANCH wins. If dist-ai has a branch with the
## same name as the branch under test, use it; otherwise master. So the
## two halves of a cross-repo change travel under one branch name and are
## tested together, and a lone consumer branch is unaffected because no
## companion exists.
##
## dist-ai itself always tests its own commit -- it is the repo under
## test there, not a dependency.
##
## Read-only: a single `git ls-remote` against a public repo, no token,
## no checkout. Unresolvable for ANY reason -> 'master', because the
## fallback must be the state of the world, never a hard failure of an
## unrelated job.

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace
shopt -s inherit_errexit
shopt -s shift_verbose

me="${0##*/}"

## Expected env (all set by the calling action):
##   THIS_REPO      github.repository
##   THIS_SHA       github.sha
##   BRANCH_NAME    github.head_ref (PR) or github.ref_name (push)
##   DIST_AI_REPO   owner/repo of dist-ai
[ -v THIS_REPO ] || THIS_REPO=''
[ -v THIS_SHA ] || THIS_SHA=''
[ -v BRANCH_NAME ] || BRANCH_NAME=''
[ -v DIST_AI_REPO ] || DIST_AI_REPO='org-ai-assisted/dist-ai'

emit() {
   printf '%s: dist-ai ref -> %s (%s)\n' "${me}" "$1" "$2" >&2
   printf 'ref=%s\n' "$1" >> "${GITHUB_OUTPUT}"
   exit 0
}

## dist-ai testing itself: its own commit is the subject.
if [ "${THIS_REPO}" = "${DIST_AI_REPO}" ]; then
   emit "${THIS_SHA}" 'this IS dist-ai; testing its own commit'
fi

## A branch name we cannot use is not an error, just no companion.
case "${BRANCH_NAME}" in
   ''|'master'|*' '*|-*)
      emit 'master' "no usable branch name ('${BRANCH_NAME}')"
      ;;
   *)
      true
      ;;
esac

## ls-remote rather than the REST API: no token, no rate limit, and it
## answers the exact question (does this ref exist) without a checkout.
if git ls-remote --exit-code --heads -- \
      "https://github.com/${DIST_AI_REPO}.git" "refs/heads/${BRANCH_NAME}" \
      > /dev/null 2>&1
then
   emit "${BRANCH_NAME}" "companion branch exists in ${DIST_AI_REPO}"
fi

emit 'master' "no companion branch '${BRANCH_NAME}' in ${DIST_AI_REPO}"
