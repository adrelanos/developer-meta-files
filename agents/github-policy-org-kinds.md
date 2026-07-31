# Org kinds and the policy each gets (AI-Assisted)

The dm-github-* tool family applies one baseline policy, with a small
set of deliberate diffs driven by what the target actually holds.
Companion to [github-org-tools.md](github-org-tools.md). The kind
names here are the values `org_kind()` returns, so this document and
the code share one vocabulary.

The five roles are:

| Role | Where it lives | Tool that touches it |
| --- | --- | --- |
| SOURCE | Kicksecure, Whonix orgs | dm-github-org-policy, kind=source |
| MIRROR | org-ai-assisted org | dm-github-org-policy, kind=mirror |
| PROJECT | secure-terminal, output-lies orgs | dm-github-org-policy, kind=project |
| PERSON | PERSON_USERS array | dm-github-personal-policy, target_kind=person |
| BOT | BOT_USERS array | dm-github-personal-policy, target_kind=bot |

The distinction that drives every diff below is whether the code has
somewhere ELSE to be maintained:

- **MIRROR** holds forks of SOURCE. Issues, alerts and vulnerability
  reports belong upstream, so they are turned OFF here: raising them
  on a fork only duplicates what the canonical repo already reports.
- **SOURCE** and **PROJECT** both hold code that is maintained where
  it lives. A PROJECT org is not a copy of anything -- it holds one
  self-contained first-party project (the secure-terminal app, the
  output-lies site) with no upstream to file against. So both keep
  issues and Dependabot alerts ON. (Private vulnerability reporting
  is a narrower question and does NOT follow this split -- see the
  table below.)

MIRROR is therefore the only kind that switches alerts off, and
"mirror" means specifically "mirrors Kicksecure / Whonix" -- not
"any org that is not SOURCE".

A second axis cuts across the first: whether a setting opens PULL
REQUESTS. Actions is disabled org-wide on SOURCE by deliberate policy
(the canonical repos run their own CI), so any PR raised on SOURCE by
a bot can never carry a CI verdict. Every PR-producing Dependabot
switch is therefore OFF on SOURCE, while the notification-only ones
stay on. See "Dependabot on SOURCE" below.

## Free-plan code-security replacements

Applied per-repo on the org side after the org-level Code Security
Configurations API turned out to be PAID PLAN ONLY. Enabled wherever
the code is actually maintained (SOURCE, PROJECT) and disabled where
it is a copy (MIRROR): a mirror running these would duplicate every
alert the canonical SOURCE repo already raises. Empirically tested on
Free 2026-05.

| Feature | SOURCE | MIRROR | PROJECT | PERSON | BOT |
| --- | --- | --- | --- | --- | --- |
| Dependabot alerts (`PUT /vulnerability-alerts` enable, `DELETE` on MIRROR) | on | actively disabled | on | off | off |
| Dependabot security updates (`PUT /automated-security-fixes` on PROJECT, `DELETE` on SOURCE + MIRROR) | actively disabled | actively disabled | on | off | off |
| Dependabot version updates (no REST setter; `.github/dependabot.yml` presence IS the switch) | must be absent | not required, allowed | allowed | - | - |
| Private vulnerability reporting (PVR) | actively disabled | actively disabled | **on** | off | off |
| `secret_scanning` + push protection (in PATCH body) | on | on | on | on | on |
| Branch + tag rulesets (`POST /repos/{}/{}/rulesets`) | on | on | on | on | on |
| `has_issues` | on | off | on | - | - |
| `has_wiki` / `has_discussions` | off | off | off | - | - |

PROJECT is the only kind that ENABLES private vulnerability
reporting. SOURCE disables it because Kicksecure and Whonix take
security reports through their own documented channel, not GitHub;
a PROJECT org has no such channel, so GitHub's is the one a
researcher can find.

Notes:

- Dependabot alerts off on MIRROR/PERSON/BOT for the split-inbox /
  duplicate-notifications reason; ON for SOURCE and PROJECT, which
  have no upstream inbox to split against. On MIRROR
  `apply_repo_policy` actively DELETEs the two Dependabot settings
  (every `--apply` reconciles), so leftovers from older un-gated runs
  or accidental UI flips are cleaned up. Order: DEPENDABOT_FIXES_OFF
  before DEPENDABOT_ALERTS_OFF - the security-fixes endpoint
  returns HTTP 422 once alerts are off, which is the idempotent
  steady state and is captured as ok via the
  `_EXTRA_OK_STATUS=422` knob (see G-035 in
  `github-org-tools.md`). On PERSON/BOT
  `dm-github-personal-policy` keeps step 8 commented out for the
  same reason (with the canonical-home-uncomment note); the
  personal mirror never had these on so an active-disable pass
  is unnecessary.

- SOURCE keeps alerts but not security updates. An alert is a
  notification; a security update is a pull request, and on SOURCE no
  pull request can be verified. `apply_repo_policy` therefore PUTs
  `REPO_DEPENDABOT_ALERTS` and DELETEs
  `REPO_DEPENDABOT_FIXES_SOURCE_OFF` on SOURCE (its own constant, not
  the MIRROR one: same endpoint and 422 tolerance, different reason and
  log line). Alerts first, then the DELETE - the reverse order hits the
  same 422 as on MIRROR.

- PVR (Private Vulnerability Reporting) is off on EVERY role,
  including SOURCE. The canonical disclosure channel for
  Kicksecure / Whonix is the wiki (linked from the SECURITY.md
  committed at `org-ai-assisted/.github/SECURITY.md`, pointing
  to
  https://www.kicksecure.com/wiki/Reporting_Bugs#Security_Vulnerabilities
  and the Vulnerability Disclosure Policy page). Enabling PVR on top
  of that would split the disclosure inbox between the wiki flow and a
  parallel GitHub-side flow. `apply_repo_policy` actively DELETEs PVR
  on every repo unconditionally; there is no PUT-style enable constant
  in `github-policy-data.bsh`.
- Secret scanning + push protection are about local git ops, not
  inbox routing, so they stay on everywhere.
- Rulesets stay on everywhere; the bypass-actor list and the
  required_signatures rule both pivot on role (see Summary table
  below).

## Summary of intentional per-kind splits

| Axis | Canonical (SOURCE) | Mirror (MIRROR / PERSON / BOT) |
| --- | --- | --- |
| Issue tracking | `has_issues=on` | `has_issues=off` (route upstream) |
| Project boards / discussions / wikis | (default on, unset) | off |
| Ruleset bypass | `[OrgAdmin]` (org owner can bypass; non-admins still blocked) | `[OrgAdmin]` on MIRROR; `[User: target_user_id]` on PERSON (computed at apply time from `GET /users/{login}` since user-owned repos have no org-admin actor); `[]` on BOT (no rule needs a bypass and the bot must not be able to force-push or delete its own branches) |
| Ruleset `required_signatures` ("allow only signed commits") | **on** (org owner bypasses via `[OrgAdmin]`) | **on PERSON** (owner bypasses via `[User]`); **off on MIRROR / BOT** (AI-assisted automation pushes commits without a verifiable GPG key for the bot identity) |
| CI / Actions | **disabled entirely, org-wide** (`enabled_repositories=none`); canonical CI runs on the org's own infra, not GitHub Actions | disabled entirely on PERSON/BOT (mirrors only); MIRROR keeps CI on, allow-list = github-owned + verified-creators (it is where AI-assisted dev + CI run) |
| Dependabot alerts | on | off (would duplicate upstream alerts) |
| Dependabot security updates | **off** (they open PRs; Actions is off on SOURCE, so nothing can verify them) | off |
| Dependabot version updates (`.github/dependabot.yml`) | **must be absent** (same no-CI reason) | allowed; MIRROR is where a bump gets a CI verdict |
| PVR (Private Vulnerability Reporting) | **off everywhere** (canonical disclosure is the wiki - see `.github/SECURITY.md`) | off |
| GitHub Pages site | not touched | `DELETE /pages` on PERSON/BOT (mirror should not host Pages) |

Net deliberate diffs after this split:

1. `has_issues=on` only on SOURCE. Everywhere else issues route
   upstream.
2. Ruleset bypass on SOURCE / MIRROR / PERSON only; BOT gets `[]`.
   Actor type pivots on whether the repo is org-owned or user-owned:
   - SOURCE / MIRROR use `[OrgAdmin]` (static; org_id=1 maps to
     "any org admin"). SOURCE picked it up together with the
     `required_signatures`-blocked-pushes fix; MIRROR has had it
     for hotfix re-fork without dropping the ruleset.
   - PERSON uses `[User: target_user_id]` (computed at apply
     time). User-owned repos have no `OrganizationAdmin`
     equivalent, but the `User` actor type IS supported on
     repo-level rulesets - the maintainer's own GitHub
     user_id, resolved via `GET /users/{login}` in
     `dm-github-personal-policy`, is the equivalent
     repo-owner-bypass for the `required_signatures` rule.
   - BOT gets `[]`. There is no `required_signatures` rule to
     bypass, and the remaining rules (`deletion`,
     `non_fast_forward`) do not block legitimate bot pushes -
     adding a `User` bypass would let the bot force-push and
     delete branches on its own repos, defeating the whole
     point of those rules. SOURCE / MIRROR / PERSON let the
     maintainer bypass; BOT does not.
3. `required_signatures` ruleset rule on SOURCE and PERSON.
   MIRROR (`org-ai-assisted`) and BOT (`assisted-by-ai` and
   peers) drop the rule because AI-assisted pushes carry no GPG
   key matching the bot's GitHub-verified identity, so leaving
   the rule on would block every legitimate bot push. SOURCE
   keeps the rule plus the `[OrgAdmin]` bypass; PERSON keeps it
   plus the `[User: target_user_id]` bypass - non-admin
   collaborators on either side still get the protection.
   Dispatched via `POLICY_RULESET_RULES_<ROLE>` in
   `github-policy-data.bsh` (same naming pattern as
   `POLICY_RULESET_BYPASS_<ROLE>`).
4. CI disabled entirely on SOURCE (Kicksecure / Whonix -
   `enabled_repositories=none`, org-wide) and on PERSON/BOT (no
   workflows run on the personal mirrors). Only MIRROR
   (org-ai-assisted / output-lies) runs GitHub Actions CI, under the
   selected-actions allow-list - it is where the AI-assisted test +
   scanner suites run. The canonical SOURCE repos run their own CI,
   not GitHub Actions.
5. Dependabot ALERTS on SOURCE and PROJECT, actively disabled on
   MIRROR. Dependabot's two PR-producing switches (security updates
   and version updates) run on PROJECT only: MIRROR gets bumps from
   the upstream config it forks, and SOURCE has Actions off, so a
   bump PR there could never be verified. PVR (Private Vulnerability
   Reporting) actively disabled everywhere except PROJECT, because
   the canonical disclosure channel is the wiki (per
   `.github/SECURITY.md`), not GitHub's PVR flow.
6. GitHub Pages cleanup (DELETE) only on PERSON/BOT.

Everything else (fork-PR approval policy, workflow GITHUB_TOKEN
permissions, secret scanning, rulesets) is identical content with
only the API scope (org-level vs per-repo) differing.

## SOURCE-side UI-only operator flips

Dependabot and Code-scanning settings whose desired state is known
to the policy but which have **no documented REST setter** as of
2026-05. `dm-github-org-policy --apply` (and `--dry-run`) emits a
`skip: ... see <URL>` log line on every org / repo the setting
applies to, so the operator can complete each flip via the UI.

The section keeps its name because most of these are SOURCE-side,
but the emitting kind is per row -- a flip is emitted where its
subject exists. The three alert-triage rows follow the ALERTS
split (SOURCE + PROJECT); grouped security updates follows the
security-PR split (PROJECT only, since 2026-07-31).

| Setting | Scope | Emitted on | Desired | Why moot elsewhere |
| --- | --- | --- | --- | --- |
| Dependabot grouped security updates | org | PROJECT | **on** | No security-update PRs to group: MIRROR/PERSON/BOT have Dependabot off entirely, SOURCE keeps alerts but opens no security PRs |
| Code scanning: recommend security-extended query suite | org | SOURCE | **on** | MIRROR repos use the reusable `codeql.yml` workflow (advanced setup), which carries its own `queries:` value and ignores the default-setup recommendation |
| Auto-triage rule "Dismiss low-impact dev-scoped" preset | repo | SOURCE, PROJECT | **off** | Alerts off on MIRROR/PERSON/BOT; none to triage |
| Auto-triage rule "Dismiss package malware alerts" preset | repo | SOURCE, PROJECT | **off** | Alerts off; no malware alerts to (not-)dismiss |
| Delegated Dependabot alert dismissal ("Prevent direct alert dismissals") | repo | SOURCE, PROJECT | **on** | Alerts off; no dismissals to delegate |
| Dependabot version updates (delete `.github/dependabot.yml`) | repo | SOURCE | **off** | Not a UI flip at all -- the fix is a commit; listed here because it shares the "no REST setter" shape. See "Dependabot on SOURCE" below |

Rationale per setting:

- **Grouped security updates**: one PR per ecosystem + directory
  bundling all available security fixes instead of one PR per
  vulnerable dep. Emitted on PROJECT, the only kind that still
  opens security-update PRs; per-repo `dependabot.yml` `groups:`
  blocks override the org default for finer control. One source of
  truth - prefer the org-level UI flip.

- **Code scanning extended query suite recommendation**: nudges
  new opt-ins toward broader coverage (default suite + lower
  precision/severity queries). Security-focused project family
  trades extra triage for visibility. No effect on repos using
  advanced setup with a `queries:` value in their workflow.

- **Auto-triage "Dismiss low-impact dev-scoped"**: npm-only
  preset that auto-dismisses low-impact alerts on dev
  dependencies. Our repo family is mostly Debian-shaped (not
  npm) so the practical effect is small, but on principle a
  security project sees every alert. Still meaningful on SOURCE
  after the 2026-07-31 decision: alerts stay on there, only the
  PR streams go away.

- **Auto-triage "Dismiss package malware alerts"**: hard rule.
  Malware alerts are the highest-signal class; never silently
  dismiss. Cheap insurance against an accidental UI flip or an
  inherited security configuration that turns this on.

- **Delegated alert dismissal**: contributors with write access
  must request dismissal; org owners and security managers
  approve. Institutional gate against a single maintainer
  silently dismissing alerts that should reach human review.

## Dependabot on SOURCE (decision 2026-07-31)

**Decision: Dependabot opens no pull requests on Kicksecure and
Whonix. Alerts stay on.**

Why: Actions is disabled org-wide on SOURCE by deliberate policy
(the canonical repos run their own CI - see the CI / Actions row
above). Dependabot does not need repo Actions to run, so it kept
opening bump PRs on SOURCE that no check could ever report on. An
unverifiable PR stream is worse than no PR stream: it costs review
attention and produces a green-looking merge button backed by
nothing. The MIRROR (`org-ai-assisted`) is where Actions runs, so
that is where a bump is verified and merged.

This REPLACES the earlier "opt in per-repo on the canonical SOURCE
repo" recommendation, and it is why the grouped-security-updates
row above moved from SOURCE to PROJECT.

### The two switches are separate

They are not one toggle, and only one of them has an API:

| | VERSION updates | SECURITY updates |
| --- | --- | --- |
| What turns it on | `.github/dependabot.yml` exists in the repo | `PUT /repos/{o}/{r}/automated-security-fixes` |
| What turns it off | deleting that file (a commit) | `DELETE` on the same endpoint |
| Scope | per repo, content-based | per repo, setting-based |
| Org-wide setter | **none exists** | none; per-repo only |
| Needs a config file | yes | no -- a repo with no `dependabot.yml` still emits security PRs |
| Policy constant | `POLICY_DEPENDABOT_VERSION_UPDATES_OFF_*` (a skip line, not an API call) | `POLICY_REPO_DEPENDABOT_FIXES_SOURCE_OFF` |

GitHub documents exactly one config path, `.github/dependabot.yml`;
that single path is what the tools probe.

### Measured SOURCE inventory (2026-07-31)

124 repos (Kicksecure 93, Whonix 31). Exactly 15 carry
`.github/dependabot.yml`, zero carry a `.yaml` variant:

- Kicksecure: developer-meta-files, msgcollector, helper-scripts,
  tb-updater, usability-misc, security-misc, genmkfile,
  derivative-maker, grml-debootstrap, hardened_malloc
  (ARCHIVED), mediawiki-extensions-Kicksecure (ARCHIVED)
- Whonix: whonix-firewall, kloak, derivative-maker,
  Whonix-Installer

Most are the github-actions (+docker) weekly template. Two
outliers: `hardened_malloc` sets `target-branch: main` on a repo
with no `main` branch, so its config is inert;
`mediawiki-extensions-Kicksecure` is the only one configuring
composer/npm, daily. The two ARCHIVED repos must be un-archived
before their config can be deleted -- Dependabot does not run on an
archived repo, so those two configs are inert until that happens,
and `--audit` does not enumerate archived repos at all.

`security_and_analysis` was NOT READABLE with the bot token on any
of the 124 repos (403/404 permissions wall), so the per-repo
security-update state on SOURCE is currently UNKNOWN. The audit
reports it as unverified rather than assuming it is off.

### Sequencing (do not disable first)

Disabling Dependabot on SOURCE also stops the mechanism that
retires the currently-open SOURCE bump PRs: Dependabot closes its
own PR as superseded once the dependency is already at the new
version upstream. Turn it off first and that batch has to be
closed by hand. Cheaper order: let the mirror-side bumps land
upstream, let the SOURCE copies retire themselves, then disable.

### Consequence for the mirror, unresolved

MIRROR repos are forks that ff-sync from SOURCE, so
`.github/dependabot.yml` on the mirror IS the SOURCE file. Deleting
it upstream removes it from the mirror on the next sync, which ends
the mirror-side verified-bump stream too. Keeping verified bumps
would need the config to live somewhere that is not ff-synced from
SOURCE, or a deliberate mirror-only divergence. Recorded here
rather than decided: it is a maintenance-model question, not a
policy-encoding one.

### DECLARATIVE, not enforced

The bot is `role=member` on both SOURCE orgs, and `SOURCE_ORGS` is
commented out of the `ORGS` array in `dm-github-org-policy` pending
an admin token. Nothing here can be applied by the tool today:

- `--apply` never reaches Kicksecure / Whonix.
- `--dry-run` / `--audit` reach them only via
  `ORGS_OVERRIDE='Kicksecure,Whonix'`.
- The version-update half would not be an API call even with an
  admin token: it is a commit deleting a file in 13 non-archived
  repos, i.e. 13 pull requests an owner has to merge.

So this section is the desired state an owner can act on, plus the
measurement that says how far the live state is from it. It is not
a claim that the live state matches.

### What `--audit` compares

Compared (a finding on drift, and a finding on any endpoint that
could not be read - an unread endpoint is never a pass):

- SOURCE: `.github/dependabot.yml` must be ABSENT. Present is
  reported as drift. A probe answering neither 200 nor 404 is
  reported as NOT VERIFIED, because reading "could not tell" as
  "absent" is the exact false green this audit exists to prevent.
- SOURCE: security updates must read `enabled: false` from
  `GET /automated-security-fixes`. With the current member token
  that endpoint answers 404, so this reports NOT VERIFIED --
  honestly, since the state genuinely is unknown.
- SOURCE + PROJECT: alerts must read enabled
  (`GET /vulnerability-alerts` -> HTTP 204).
- PROJECT: security updates must read `enabled: true`.

Not compared yet, deliberately stated rather than implied:

- MIRROR's own "security updates off" claim. The endpoint returns
  a readable 200 body there, so the comparison is possible; it is
  not wired up because the mock suites that cover this tool live in
  a different package (`dist-ai`) and carry no fixture for the
  endpoint, and a missing fixture fails as a mock error rather than
  as real drift. Follow-up: add the fixtures, then drop the
  kind guard.
- MIRROR's "alerts off" claim cannot be verified through this
  endpoint at all: `GET /vulnerability-alerts` answers 404 both
  when alerts are off and when the token cannot see the repo, so a
  must-be-OFF assertion would be indistinguishable from a
  permissions wall. Only the must-be-ON direction is asserted.
- Per-repo settings other than Dependabot (the repo PATCH body,
  PVR, rulesets) are applied but not compared. Pre-existing gap,
  same shape, same fixture cost.

The `dependabot.yml` `groups:` block (with
`applies-to: security-updates`) remains the durable,
source-controlled form for per-repo custom grouping on the kinds
that still open security PRs.

## Potential future tightenings (not in policy yet)

Surfaced during the 2026-05 GitHub web-settings sweep. Each is a
low-risk addition; landing them is gated only on operator
appetite for the friction trade-off.

- **`web_commit_signoff_required: true`** at the org level (or
  per-repo via `POLICY_REPO_*`). NOT a security setting and NOT
  related to GPG. Forces commits made through the GitHub web UI
  ("edit this file" / suggestion-accept / web upload) to carry a
  `Signed-off-by: Name <email>` trailer - the textual DCO
  attestation (https://developercertificate.org/) that the
  contributor has the right to submit the code under the
  project's license. Same thing the Linux kernel and many other
  projects require on every patch. Worth enabling only if
  Kicksecure / Whonix wants to formally adopt the DCO sign-off
  contribution model; otherwise it just adds a UI checkbox click
  with no benefit. The cryptographic-signature requirement is a
  separate concern handled by the existing `required_signatures`
  ruleset rule, which web-UI commits already satisfy via
  GitHub's web-flow GPG key.

- **Tag-name pattern ruleset rule** like
  `^v[0-9]+\.[0-9]+(\.[0-9]+)?$` on the tag ruleset. Catches
  the rare class of "tag with wrong format" pushes that the
  current rules let through. May need a bypass exemption if
  hotfix tags ever use a different shape.

- **`interaction_limit: collaborators_only`** permanently on
  MIRROR repos via `PUT /repos/{}/{}/interaction-limits`.
  Issues / discussions are off everywhere on MIRROR so there is
  not much to interact with, but a hostile drive-by PR would be
  silently rejected by the API instead of opening a noisy issue
  in the maintainer's queue.

- **Audit flag for private repos** in `audit_org_state`. None
  exist today, but a regression (someone flipping a public repo
  to private via the UI) would silently break secret scanning +
  push protection on the affected repo since GHAS is required
  for those features on private Free-org repos. Read-only check;
  no apply mutation.

- **Org Copilot `public_code_suggestions: block`** (currently
  `allow`). Moot today - 0 seats assigned - but the moment a
  seat lands, blocking verbatim public-code suggestions reduces
  the risk of GPL / BSD-licensed snippets being accepted into
  Kicksecure / Whonix without their attribution. Org-level UI
  toggle, not in any of our policy scripts.

- **GitHub Code Quality** (CodeQL with the quality query suite,
  public preview since 2025-10-28). Differs from the Dependabot
  pattern because Code Quality fires on PR diffs and on the
  default branch; PRs only exist on whichever side carries them.

  | Role | Code Quality | Why |
  | --- | --- | --- |
  | SOURCE | (blocked) | Would need Actions; SOURCE has Actions disabled org-wide (see the CI / Actions row above), so GitHub-Actions-based Code Quality cannot run here until Actions are re-enabled or a non-Actions mechanism exists |
  | MIRROR | on | PR-time feedback where AI-assisted PRs land; `dm-github-org-security-report`'s MIRROR-default already routes the alerts here |
  | PERSON | off | No PRs land here |
  | BOT | off | No PRs land here; Actions disabled entirely |

  NOT the Dependabot SOURCE-only shape: Code Quality on MIRROR
  is the point where AI-authored diffs first get a quality
  signal. Engine is CodeQL with an extra query suite, so the
  Actions-minute cost is incremental on top of the existing
  Code Security scan. `require_code_quality_results` ruleset
  rule (with a `Severity` threshold) belongs on SOURCE only;
  enforcing it on MIRROR would block the AI's own iteration
  loop, defeating the PR-time-feedback purpose. Per-repo enable
  is UI-only today
  (`https://github.com/<owner>/<repo>/settings/code-quality`);
  the obvious REST setter slot is a new field on `PATCH
  /repos/{owner}/{repo}/code-scanning/default-setup`, but the
  public docs do not document one as of 2026-05.

`sha_pinning_required: true` is intentionally NOT in this list -
see `agents/github-actions.md` "Org-level `sha_pinning_required`
is intentionally OFF" for the rationale.
