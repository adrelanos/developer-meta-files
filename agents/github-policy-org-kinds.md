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
  issues ON. (Private vulnerability reporting is a narrower question
  and does NOT follow this split -- see the table below.)

"Mirror" means specifically "mirrors Kicksecure / Whonix" -- not "any
org that is not SOURCE".

A second axis cuts across the first, and Dependabot follows the
SECOND one, not the first: **where does the CI that acts on the
report run?** SOURCE has Actions disabled org-wide
(`enabled_repositories=none`), and the PROJECT repos are mirrored
into `org-ai-assisted`, where the AI-assisted test and scanner
suites run. `org-ai-assisted` is therefore the one place a bump PR
can carry a verdict and a CVE alert has a build to fix it in, so
Dependabot is ON on MIRROR only and actively OFF on every other kind.
See "Dependabot lives on the mirror only" below.

## Free-plan code-security replacements

Applied per-repo on the org side after the org-level Code Security
Configurations API turned out to be PAID PLAN ONLY. Empirically
tested on Free 2026-05.

| Feature | SOURCE | MIRROR | PROJECT | PERSON | BOT |
| --- | --- | --- | --- | --- | --- |
| Dependabot alerts (`PUT /vulnerability-alerts` on MIRROR, `DELETE` elsewhere) | actively disabled | **on** | actively disabled | off | off |
| Dependabot security updates (`PUT /automated-security-fixes` on MIRROR, `DELETE` elsewhere) | actively disabled | **on** | actively disabled | off | off |
| Dependabot version updates (no REST setter; `.github/dependabot.yml` presence IS the switch) | must be absent | opt-in per repo | must be absent | - | - |
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

- Dependabot is ON on MIRROR and actively DELETEd on every other kind
  (every `--apply` reconciles), so leftovers from older un-gated runs
  or accidental UI flips are cleaned up. Order on the disable side:
  DEPENDABOT_FIXES_OFF before DEPENDABOT_ALERTS_OFF - the
  security-fixes endpoint returns HTTP 422 once alerts are off, which
  is the idempotent steady state and is captured as ok via the
  `_EXTRA_OK_STATUS=422` knob (see G-035 in `github-org-tools.md`).
  On the enable side the order is reversed: alerts first, because
  `PUT /automated-security-fixes` requires them. On PERSON/BOT
  `dm-github-personal-policy` keeps step 8 commented out; the
  personal mirror never had these on so an active-disable pass
  is unnecessary.

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
| Dependabot alerts | **off** (Actions is off on SOURCE; alerts belong where the fix gets built and tested) | **on MIRROR**; off on PERSON/BOT |
| Dependabot security updates | **off** (they open PRs; Actions is off on SOURCE, so nothing can verify them) | **on MIRROR**; off on PERSON/BOT |
| Dependabot version updates (`.github/dependabot.yml`) | **must be absent** (same no-CI reason) | opt-in per repo on MIRROR, which is where a bump gets a CI verdict; absent on PERSON/BOT |
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
5. Dependabot -- all three switches -- on MIRROR only, actively
   disabled on SOURCE and PROJECT. It follows GitHub Actions, and
   Actions runs on `org-ai-assisted` alone. PVR (Private
   Vulnerability Reporting) actively disabled everywhere except
   PROJECT, because the canonical disclosure channel is the wiki (per
   `.github/SECURITY.md`), not GitHub's PVR flow. The two do NOT
   share a pivot: Dependabot follows CI, PVR follows who receives a
   researcher's report.
6. GitHub Pages cleanup (DELETE) only on PERSON/BOT.

Everything else (fork-PR approval policy, workflow GITHUB_TOKEN
permissions, secret scanning, rulesets) is identical content with
only the API scope (org-level vs per-repo) differing.

## UI-only operator flips

Dependabot and Code-scanning settings whose desired state is known
to the policy but which have **no documented REST setter** as of
2026-05. `dm-github-org-policy --apply` (and `--dry-run`) emits a
`skip: ... see <URL>` log line on every org / repo the setting
applies to, so the operator can complete each flip via the UI.

The emitting kind is per row -- a flip is emitted where its subject
exists. The three Dependabot rows are MIRROR only, because MIRROR is
the only kind with Dependabot alerts or security-update PRs at all.

| Setting | Scope | Emitted on | Desired | Why moot elsewhere |
| --- | --- | --- | --- | --- |
| Dependabot grouped security updates | org | MIRROR | **on** | Every other kind has Dependabot off entirely; no security-update PRs to group |
| Code scanning: recommend security-extended query suite | org | SOURCE | **on** | MIRROR repos use the reusable `codeql.yml` workflow (advanced setup), which carries its own `queries:` value and ignores the default-setup recommendation |
| Auto-triage rule "Dismiss low-impact dev-scoped" preset | repo | MIRROR | **off** | Alerts off everywhere else; none to triage |
| Auto-triage rule "Dismiss package malware alerts" preset | repo | MIRROR | **off** | Alerts off; no malware alerts to (not-)dismiss |
| Delegated Dependabot alert dismissal ("Prevent direct alert dismissals") | repo | MIRROR | **on** | Alerts off; no dismissals to delegate |
| Dependabot version updates (delete `.github/dependabot.yml`) | repo | SOURCE, PROJECT | **off** | Not a UI flip at all -- the fix is a commit; listed here because it shares the "no REST setter" shape. See "Dependabot lives on the mirror only" below |

Rationale per setting:

- **Grouped security updates**: one PR per ecosystem + directory
  bundling all available security fixes instead of one PR per
  vulnerable dep. Emitted on MIRROR, the only kind that opens
  security-update PRs; per-repo `dependabot.yml` `groups:`
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
  security project sees every alert.

- **Auto-triage "Dismiss package malware alerts"**: hard rule.
  Malware alerts are the highest-signal class; never silently
  dismiss. Cheap insurance against an accidental UI flip or an
  inherited security configuration that turns this on.

- **Delegated alert dismissal**: contributors with write access
  must request dismissal; org owners and security managers
  approve. Institutional gate against a single maintainer
  silently dismissing alerts that should reach human review.

## Dependabot lives on the mirror only (decision 2026-07-31)

**Decision: Dependabot runs on `org-ai-assisted` and nowhere else.
Alerts, security updates and version updates are all OFF on
Kicksecure, Whonix and the PROJECT orgs.**

Why: every Dependabot output -- an alert, a security-update PR, a
version-bump PR -- only becomes work somebody can finish where CI can
build and test the result, and where merging it is the normal
workflow. SOURCE has GitHub Actions disabled org-wide by deliberate
policy (the canonical repos run their own CI - see the CI / Actions
row above), so a bump PR raised there can never carry a verdict. The
PROJECT repos are mirrored into `org-ai-assisted`, which is where the
AI-assisted test and scanner suites run, so Dependabot output on the
PROJECT side only splits one alert inbox and one bump stream in two.
An unverifiable PR stream is worse than no PR stream: it costs review
attention and produces a green-looking merge button backed by
nothing.

This REPLACES the earlier "Dependabot alerts belong on the canonical
repo, which is where a CVE must be visible" reasoning and the "opt in
per-repo on the canonical SOURCE repo" recommendation. Both are
overruled. The mirror is the single place.

### The three switches, and how each is flipped

| | ALERTS | SECURITY updates | VERSION updates |
| --- | --- | --- | --- |
| What turns it on | `PUT /repos/{o}/{r}/vulnerability-alerts` | `PUT /repos/{o}/{r}/automated-security-fixes` | `.github/dependabot.yml` exists in the repo |
| What turns it off | `DELETE` on the same endpoint | `DELETE` on the same endpoint | deleting that file (a commit) |
| Scope | per repo, setting-based | per repo, setting-based | per repo, content-based |
| Org-wide setter | none; per-repo only | none; per-repo only | **none exists at any scope** |
| Needs a config file | no | no -- a repo with no `dependabot.yml` still emits security PRs | yes |
| Policy constant | `POLICY_REPO_DEPENDABOT_ALERTS` / `_ALERTS_OFF` | `POLICY_REPO_DEPENDABOT_FIXES` / `_FIXES_OFF` | `POLICY_DEPENDABOT_VERSION_UPDATES_OFF_*` (a skip line, not an API call) |

Measured 2026-07-31 against `GET
/orgs/{org}/code-security/configurations`: the configuration object
carries `dependabot_alerts` and `dependabot_security_updates` but no
version-updates field at all, so the file really is the only switch
for the third column, at any scope. GitHub documents exactly one
config path, `.github/dependabot.yml`; that single path is what the
tools probe.

### How `dependabot.yml` reaches a repo: opt-in, not blanket

`usr/bin/dm-packaging-helper-script` is the deployment mechanism, and
it is deliberately NOT "put the file on every repo":

- The canonical copy is
  `developer-meta-files/consumer-templates/.github/dependabot.yml`
  (`canonical_dependabot_yml`).
- `pkg_update_consumer_workflows` refreshes a package's copy from the
  canonical one, and `dependabot_yml_is_manual` skips that refresh for
  any file carrying a `## propagation: manual` marker -- the opt-out
  for a hand-tuned config that must not be overwritten.
- A repo with nothing worth tracking carries no file, and nothing in
  the toolchain adds one on its behalf. The repos that need it are
  the ones pinning third-party Action SHAs, which is what the W-007
  `DEPENDABOT-MISSING` check in `test_workflow_yaml.py` flags.

So "Dependabot on the mirror" means "on the mirror repos that opted
in", never "on all of them".

### Consequence for the shared tree, unresolved

MIRROR repos are forks that ff-sync from SOURCE, so
`.github/dependabot.yml` on the mirror IS the SOURCE file: one object
in one history, not two independent settings. Deleting it on SOURCE
removes it from the mirror at the next sync; keeping it for the
mirror keeps it on SOURCE. The version-updates column therefore
cannot be split along the org-kind axis by file presence alone --
mirror-side version bumps would need the config to live somewhere
that is not ff-synced from SOURCE, or a deliberate mirror-only
divergence.

Recorded, not decided: it is a maintenance-model question, not a
policy-encoding one. What the policy DOES encode without ambiguity is
the pair with real per-repo API setters -- alerts and security
updates -- which are ON on the mirror and actively DELETEd everywhere
else, and which need no config file to work.

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
of the 124 repos (403/404 permissions wall), so the per-repo alert
and security-update state on SOURCE is currently UNKNOWN. The audit
reports it as NOT VERIFIED rather than assuming it is off.

### Sequencing (do not disable first)

Disabling Dependabot on SOURCE also stops the mechanism that
retires the currently-open SOURCE bump PRs: Dependabot closes its
own PR as superseded once the dependency is already at the new
version upstream. Turn it off first and that batch has to be
closed by hand. Cheaper order: let the mirror-side bumps land
upstream, let the SOURCE copies retire themselves, then disable.

### DECLARATIVE, not enforced -- the SOURCE half

The bot is `role=member` on both SOURCE orgs, and `SOURCE_ORGS` is
commented out of the `ORGS` array in `dm-github-org-policy` pending
an admin token. The SOURCE half of this section cannot be applied by
the tool today:

- `--apply` never reaches Kicksecure / Whonix.
- `--dry-run` / `--audit` reach them only via
  `ORGS_OVERRIDE='Kicksecure,Whonix'`.
- The version-update half would not be an API call even with an
  admin token: it is a commit deleting a file in 13 non-archived
  repos, i.e. 13 pull requests an owner has to merge.

So the SOURCE half is the desired state an owner can act on, plus the
measurement that says how far the live state is from it. It is not a
claim that the live state matches. The MIRROR and PROJECT halves are
reachable by `--apply` and are enforced on every run.

### What `--audit` compares

Compared (a finding on drift, and a finding on any endpoint that
could not be read - an unread endpoint is never a pass):

- MIRROR: security updates must read `enabled: true` from
  `GET /automated-security-fixes`, against
  `POLICY_REPO_DEPENDABOT_FIXES_EXPECT_ON` -- the read-side
  counterpart of the literal `--apply` PUTs.
- MIRROR: alerts must read enabled
  (`GET /vulnerability-alerts` -> HTTP 204).
- SOURCE + PROJECT: security updates must read `enabled: false`,
  against `POLICY_REPO_DEPENDABOT_FIXES_EXPECT_OFF`. With the current
  member token that endpoint answers 404 on SOURCE, so this reports
  NOT VERIFIED -- honestly, since the state genuinely is unknown.
- SOURCE + PROJECT: `.github/dependabot.yml` must be ABSENT. Present
  is reported as drift.
- EVERY kind: a `dependabot.yml` probe answering neither 200 nor 404
  is reported as NOT VERIFIED, MIRROR included, where either answer
  would otherwise be in policy. Reading "could not tell" as "absent"
  is the exact false green this audit exists to prevent, and the
  `no:` inventory line it would print is just as wrong on the mirror.

Not compared, deliberately stated rather than implied:

- The "alerts off" claim on SOURCE / PROJECT cannot be verified
  through this endpoint at all: `GET /vulnerability-alerts` answers
  404 both when alerts are off and when the token cannot see the
  repo, so a must-be-OFF assertion would be indistinguishable from a
  permissions wall. Only the must-be-ON direction is asserted, on
  MIRROR.
- Per-repo settings other than Dependabot (the repo PATCH body,
  PVR, rulesets) are applied but not compared. Pre-existing gap,
  same shape, same fixture cost.

The `dependabot.yml` `groups:` block (with
`applies-to: security-updates`) remains the durable,
source-controlled form for per-repo custom grouping on the mirror.

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
  public preview since 2025-10-28). Fires on PR diffs and on the
  default branch, so it lands on whichever side carries the PRs --
  the same MIRROR-only conclusion Dependabot reaches, for the same
  reason.

  | Role | Code Quality | Why |
  | --- | --- | --- |
  | SOURCE | (blocked) | Would need Actions; SOURCE has Actions disabled org-wide (see the CI / Actions row above), so GitHub-Actions-based Code Quality cannot run here until Actions are re-enabled or a non-Actions mechanism exists |
  | MIRROR | on | PR-time feedback where AI-assisted PRs land; `dm-github-org-security-report`'s MIRROR-default already routes the alerts here |
  | PERSON | off | No PRs land here |
  | BOT | off | No PRs land here; Actions disabled entirely |

  Code Quality on MIRROR is the point where AI-authored diffs
  first get a quality signal. Engine is CodeQL with an extra
  query suite, so the
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
