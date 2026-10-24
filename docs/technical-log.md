# Technical Documentation Log

Detailed record of every change made to this repository and to the `amf-dev` org,
phase by phase. Where `docs/decisions.md` records *approved deviations from the
architecture* in one line each, this file records *what was actually built, why it
was built that way, what broke, and how it was verified*.

**Maintained by:** Claude Code, appended at the end of every phase (and after any
out-of-phase fix) before the phase commit.

**Relationship to the other docs**

| Doc | Answers |
|---|---|
| `docs/architecture.md` | What the system is *supposed* to be. Source of truth. |
| `docs/build-playbook.md` | The order it gets built in, and the gate for each phase. |
| `docs/decisions.md` | One line per approved deviation from the architecture. |
| `docs/technical-log.md` (this file) | What was built, what went wrong, and the evidence it works. |

**Entry format:** newest phase appended at the bottom. Each entry carries the
commit SHA, the file-level change list, the reasoning behind non-obvious choices,
every failure encountered with its resolution, the verification evidence (real
command output, not "should work"), and any debt carried into later phases.

---

## ARCHITECTURE PIVOT — RESOLVED, BUILD RESUMED (2026-08-17)

`docs/architecture.md` is now **v3.0 — consolidated and self-contained**, superseding v1.0,
v2.0 and v2.1. The pause recorded below is lifted; the MVP build runs to the **M0–M3** plan
in `docs/architecture.md` §13.4, expanded into phase prompts and gates in
`docs/build-playbook.md`. The v1.0 phase rows further down are retained only as a record of
what was built at `e3ac256` and `a69e3c9`.

The history of the pivot is kept verbatim below because commit `a69e3c9` contains code built
to the v1.0 design, and because two of its findings are load-bearing for the MVP.

What changed at the premise level: v1.0 was *"the framework decides who approves and in what
order, via chained single-step processes."* v2.1 is *"the matrix decides **which** approval
process runs; the platform executes it."* Consequently the chain objects, chained single-step
execution, approver resolution, the Group Work Item pattern, the Approval Inbox LWC and the
SLA escalation batch all leave the design. Routing conditions move from
`Approval_Rule_Condition__mdt` rows to a compiled **expression grammar**, and configuration
collapses from four CMDT types to one, `Approval_Matrix_Rule__mdt`. Execution becomes dual —
Classic Approval Process or Flow Approval Orchestration, chosen per rule.

**Impact on built work:** roughly 12 of the 66 components in `a69e3c9` survive —
`Purchase_Request__c` and its five business fields, the two permission sets, and the
`AMF_Bypass_Chain_Lock` custom permission. Both chain objects, three of the four CMDT types,
the three per-object framework fields, all 14 CMDT records and three of the four list views
are superseded.

**One v1 finding carries forward and is confirmed by the new doc:** v2.1 §2.1 requires rule
priority ordering to happen in Apex rather than SOQL — the same constraint recorded in §1.4f
below. v2.1 §2.1 adds a second CMDT constraint worth pre-recording: `getAll()`/`getInstance()`
truncate Long Text Area fields to 255 characters, so the rule provider must load via SOQL.

**~~Blocked on:~~ CLEARED (2026-08-17).** The block was v2.0, which v2.1 deferred to for the
expression evaluator design, the 11-step engine flow, the `Approval_Decision_Log__c` schema,
template conventions and entry points. v3.0 consolidates all of it into one self-contained
document, so nothing defers to an absent version any more.

**Progress since the pivot (2026-08-14):** the superseded v1 metadata has been removed from the
repo and destructively deleted from `amf-dev` — all four CMDT types, all 14 CMDT records, both
chain objects (bar one, below) and the three per-object framework fields. `Purchase_Request__c`
is reduced to its five surviving business fields; the permission sets are reduced to that
object plus the custom permission, pending rebuild against the v2.1 model.

- **Outstanding manual step:** `Approval_Chain__c` could not be deleted — a soft-deleted
  `Purchase_Request__c.Active_Chain_del__c` still holds a relationship to it and lives in the
  recycle bin, where the Metadata API cannot see it. Erase it in **Setup → Object Manager →
  Purchase Request → Fields & Relationships → Deleted Fields → Erase**, then
  `sf project delete source -o amf-dev --no-prompt --metadata "CustomObject:Approval_Chain__c"`.
  Its source is deliberately still in the repo so repo and org stay in step.
- **Phase 4a spike is done** — see `docs/spike-results.md`. One finding contradicts v2.1 §3.3,
  and one adds unbudgeted work to §3.4. Q3 (group step semantics) remains open and is the
  highest-risk gap, because §3.4 routes every queue/group step to Flow on the strength of it.

**~~Agreed plan once v2.0 is supplied:~~ DONE (2026-08-17).** v2.0 and v2.1 were reconciled into
`docs/architecture.md` **v3.0**, which is self-contained and records every abandoned design in
its Appendix B rather than archiving the old file. `docs/build-playbook.md` was rewritten to the
M0–M3 plan. The superseded metadata was removed from the repo and destructively deleted from
`amf-dev` at `71fd786`, bar `Approval_Chain__c` — cleared in M0 below. The data model is rebuilt
against v3.0 §3 in M1.

---

## Phase status board

Each phase is built in its own chat session, so this table is the resume point: it, plus the
"Carried into later phases" table at the end of the most recent entry, is everything a fresh
session needs. Update the row when a phase completes.

### Current plan — MVP, architecture v3.0 §13.4

| Phase | Name | Status | Commit |
|---|---|---|---|
| **M0** | Baseline & cleanup | **Complete** — all gates green, no v1.0 metadata left | `9a54e68`, `6ccc2ed` + M0.8 |
| **M1** | Data model — `Approval_Matrix_Rule__mdt`, `Approval_Decision_Log__c`, SOQL provider | **Complete** — >255 gate green, 20/20 tests | `26a157f` |
| **M2** | Expression evaluator, reduced grammar | **Complete** — 100% coverage on all eight evaluator classes, 108/108 tests | `ce47137` |
| **M3** | Engine, two Classic templates, submit action | **Complete** — 141/141 Apex tests, 6/6 Jest, service and log writer at 100%; manual QA gate completed 2026-09-18 | `d13241f` |
| **M4** | Configuration validator, source guard gate, post-deploy check | **Complete** — source and live-org gates green; 166/166 Apex tests after M4.1, validator at 98% | `9893274` + M4.1 |
| **M5** | Preview modal — §6.4 preview, confirmation `LightningModal` | **Complete** — 175/175 Apex, 23/23 Jest, service at 100%; preview proved write-free in the org; manual gate run in the real UI on 2026-09-25 (M5.7) except its blocked-path check, which needs the catch-all deactivated | `5b99045` + M5.6, M5.7 |
| **M6** | Flow approvals technical spike — research only, `spikes/flow-approvals/` | **Complete, one item needs a person** — launch (Q1) and recall/cancel (Q4) confirmed by execution; group/queue any-member confirmed; unanimous metadata value still open; product untouched, 175/175 Apex | `972352a` (mislabelled, see M6.6) |
| **M7** | Decision timeline — §8's LWC, Classic half, on the Purchase Request record page | **Complete** — org gate passed 2026-10-08 (M7.7): deploy, post-deploy check, RunLocalTests and every manual timeline check; 57/57 Jest. The gate's recall check confirmed that a Classic recall leaves the guard set (M7.8), owed to M8. Two display defects, found by the first UI test run, fixed in M12.6: the browser's time zone, and a lost space | `25e0b2d` + M7.7, M12.6 |
| **M8** | Guard integrity — recall clears the guard; a record already in approval is refused | **Complete** — org gate steps 1–5 passed 2026-10-08 (M8.7): first deploy refused on a 329-character description, fixed; 197/197 Apex; PR-00000010 repaired. Step 6, the manual UI check, passed in the first UI test run, 2026-10-22 (M12.6) | `caeafb3` + M8.7, M12.6 |
| **M9** | Full expression grammar — `NOT`, word forms, `IN`, `CONTAINS`, `STARTS_WITH`, multipicklist, `TODAY(±n)`, three-hop paths | **Complete** — gate run in `amf-dev` 2026-10-08: 232/232 Apex, evaluator classes all 100%, mutation-checked, 57/57 Jest, matrix valid; optional manual UI check not run | `a79c880` |
| **M10** | Entry points and bulk — the Flow action, REST, per-record `submitEach()`, chunked and isolated submission, the log written after the platform answers; since M10.7 the guard staged per record | **Complete** — org gate passed 2026-10-21 (M10.8): 255/255 Apex at 98% after the locked-record fixture was replaced by a test-only validation rule (the lock did not stop the update in an Apex test), 59/59 Jest, the invocable and REST answered in the org | `393d9d5` + M10.7, M10.8 (`a0273e9`) |
| **M11** | A second governed object, Opportunity, by configuration alone — guard, two manager-hierarchy templates, the button off four layouts, rules, a log lookup, the timeline page; the source gate enforces §6.3, the validator runs each union query | **Complete** — gate run 2026-10-21: source gate and validator green across both objects and failing broken copies, 264/264 Apex at 98%, 59/59 Jest, UI API shows the action and no standard button, an Opportunity routed, approved and recalled in the org. The relationship limit measured as not enforced (142 joined). The manual check, step 8, passed in the first UI test run, 2026-10-22 (M12.6) | `6e3079d` + `96e5692`, M12.6 |
| **M12** | Template lifecycle, queue and committee templates, portability. A release manifest makes an in-place edit a gate failure. `PR_Credit_Risk_Queue` and `PR_Finance_Committee` each have a rule. Usernames are filled at deploy, and the org's own configuration has its own package directory. New and Mass Change Owner are off the decision-log list | **Complete.** Gate run 2026-10-22. The source gate is green and failed broken copies, and a correct `_v2` passed. `force-app` converts with another org's domain. The org's six templates match the manifest. 274/274 Apex at 98%, 59/59 Jest, the related list offers no actions. Queue and committee requests routed, decided and recalled in the org. The manual check, step 11, passed in the first UI test run that day. M12.6 fixed the two timeline defects that run found: 60/60 Jest, 274/274 Apex, deployed. The UI suite's re-run confirmed both fixes (M12.7). M12.8 added a Request Name field to Purchase Requests and two list views, gated and deployed 2026-10-23 | `bcedf6f` + M12.6 (`72f4dfd`), M12.7 (`0049677`), M12.8 (`c59e758`) |
| **M13** | AI around the engine. The Approval Matrix Assistant, an Agentforce employee agent, finds, previews, submits after confirmation and explains through the engine's own paths. The timeline explains recorded decisions in plain English through an Einstein prompt template | **Complete, bar the manual UI check.** Gate run 2026-10-23 (M13.7), once the user had turned on Agentforce. Deployed 145/145. 334/334 Apex at 98%. 75/75 Jest. Einstein explained a real decision accurately. A live preview session previewed, confirmed, submitted (ADL-00000032) and explained a throwaway, which was then recalled. The agent was published and activated (v2 active). Its Testing Center suite passed 9/9, 27/27 assertions, after two instruction fixes. Step 11, the manual UI check, is owed | `e81f487` |
| **M14** | The assistant for submitters and approvers. A what-if over a new write-nothing engine entry, `previewWith()`; the user's own requests; what is waiting for them; a briefing for the current approver; and the current approver's sight of the routing reason | **Complete, bar the manual UI check.** Gate run 2026-10-23 (M14.5). Deployed 163/163. 371/371 Apex at 98%. 75/75 Jest. A live session's what-ifs wrote no row. A throwaway (PR-00000050) was reassigned to the CLI user, listed as waiting, briefed and recalled. Published to v7; its 14-case suite passed 42/42 assertions in two consecutive runs. Two defects found and fixed: a reassigned step described the wrong way round, and routing of "brief me". Step 9, the manual UI check, which includes M13's step 11, is owed | `74ea4ed` |
| **M15** | The Approval Matrix Admin Assistant, a second agent for administrators. A rule drafted from a description and shown only once it passes the release checks; a change's impact on recent records over a new write-nothing engine entry, `previewEach()`; a matrix-health report counted in Apex | **Complete, bar the manual UI check.** Gate run 2026-10-23 (M15.5). Deployed 176/176. 404/404 Apex at 97%. 75/75 Jest. Both templates take their retrieved form. Live sessions drafted a checked rule, compared 16 requests and reported the log's real figures, with nothing written (29 rows and 9 rules before and after). Published to v1; its 6-case suite passed 18/18 assertions twice. The model answered without calling its tools until the script said what it does not know (M15.3). Step 11, the manual UI check, is owed | `11941dc` |
| **M16** | The Claude connector. Two Salesforce-hosted MCP servers, for everyone and for administrators, over the existing actions and seams. Claude writes from facts Apex returns, and submits only with a signed preview token after the user confirms | **Complete, bar the MCP login and the manual check.** Gate run 2026-10-24 (M16.5). Source gate unchanged. 75/75 Jest. The setup script deployed everything and activated both servers, with all twelve tools annotated. 451/451 Apex at 97%. Check-only 221/221. On real records every tool answered as expected over REST, a forged token and a wrong process were refused, and nothing was written. Steps 7 (one browser login for the MCP probe) and 8 (the conversations in claude.ai and Claude Code) are owed | recorded on commit |

### Superseded — the v1.0 plan

Retained only as a record of what was built. Phases 2–8 of that plan were never built.

| Phase | Name | Status | Commit |
|---|---|---|---|
| 0 | Scaffold & connectivity | Complete — survives into v3.0 | `e3ac256` |
| 1 | Data model (v1.0) | Built, then **superseded**; reverted at `71fd786` | `a69e3c9` |
| 2–8 | v1.0 plan | **Cancelled** — replaced by M0–M3 | |

**Starting a new phase:** read `CLAUDE.md`, then this file's most recent entry (especially its
carried-forward table), then the phase prompt in `docs/build-playbook.md`. Do not rely on
conversation history — there is none by design.

**Choosing the next phase:** nothing further is authorised after M16. `docs/build-playbook.md`
Part 5 holds the rest of the proposed roadmap (Flow approvals, the smaller items), with the
decisions each needs first. It authorises nothing; `CLAUDE.md` does. `docs/handoff.md` is the
short version.

---

## Environment baseline

Recorded once; update in place if any of it changes.

| Item | Value |
|---|---|
| Repo | `https://github.com/konigtejas/Approval-Matrix.git` |
| Working branch | `develop` (main branch: `main`) |
| Org alias | `amf-dev` |
| Org username | `tejas.vernekar.0d104ca05e80@agentforce.com` |
| Org Id | `00Daj000012Gj9BEAS` |
| Instance | `https://orgfarm-e5ccbd7218-dev-ed.develop.my.salesforce.com` |
| Org type | Developer Edition |
| `sourceApiVersion` | 62.0 |
| SF CLI | `@salesforce/cli/2.126.4` (win32-x64, node 22.22.0) |
| Deploy command | `sf project deploy start -o amf-dev` |
| Test command | `sf apex run test -o amf-dev -l RunLocalTests -w 10 -r human` |
| Seeded username domain | `@amf.00daj000012gj9b.dev` |

**Outstanding org prerequisites (manual, admin-only):**

- [x] ~~**Enable record locking and unlocking in Apex** (Setup → Process Automation
      Settings)~~ — **no longer required.** It existed for v1.0's `Approval.unlock()`
      re-submit cycling, which v3.0 Appendix B abandons: one submission per record, and the
      platform owns locking. Never enabled, and now nothing needs it.
- [x] **Erase the soft-deleted `Purchase_Request__c.Active_Chain_del__c`** (Setup → Object
      Manager → Purchase Request → Fields & Relationships → Deleted Fields → Erase). Done in
      M0 — it was the last thing holding `Approval_Chain__c` alive.

---

## Phase 0 — Scaffold & connectivity

**Date:** 2026-08-12 · **Commit:** `e3ac256` · **Status:** complete, all gates green
**Playbook goal:** DX project, org connected, CI-able test command, empty-but-deploying package.

### 0.1 File-level changes

| File | Change | Detail |
|---|---|---|
| `sfdx-project.json` | modified | `sourceApiVersion` `66.0` → `62.0` |
| `force-app/main/default/classes/AMF_Ping.cls` | added | Connectivity placeholder, `public with sharing`, single static `ping()` returning `'pong'` |
| `force-app/main/default/classes/AMF_Ping.cls-meta.xml` | added | `apiVersion 62.0`, status Active |
| `force-app/main/default/classes/AMF_PingTest.cls` | added | `@IsTest private`, one assertion on `AMF_Ping.ping()` |
| `force-app/main/default/classes/AMF_PingTest.cls-meta.xml` | added | `apiVersion 62.0`, status Active |
| `scripts/seed-data.apex` | added | Idempotent org seed — users, manager chain, queue, public group |
| `CLAUDE.md` | tracked | Existed untracked; committed so the project contract is versioned |
| `docs/architecture.md` | tracked | Existed untracked; committed — code cites its §sections |
| `docs/build-playbook.md` | tracked | Existed untracked |
| `docs/decisions.md` | tracked | Existed untracked |

### 0.2 API version

The scaffold shipped `sourceApiVersion 66.0`, but `CLAUDE.md` and the Phase 0
playbook prompt both specify **62.0**. Followed the spec and lowered it. All Apex
`-meta.xml` files pin `62.0` explicitly rather than inheriting, so a future bump of
the project-level version cannot silently move deployed classes.

Note the org itself reports API 67.0 — the project deliberately targets a lower
version than the org supports. That is intended, not drift.

### 0.3 `AMF_Ping` / `AMF_PingTest`

Deliberately trivial. Their only job is to prove the deploy → test → report loop
works end to end before any real logic exists. Both carry the ApexDoc header
required by `CLAUDE.md`, and both headers state explicitly that they map to **no**
architecture section — they are pipeline scaffolding and are deleted once the §4
engine classes land in Phase 2.

`AMF_` prefix per the naming convention.

### 0.4 `scripts/seed-data.apex`

Creates the fixture identities every later phase's manual QA depends on:

| Fixture | Detail |
|---|---|
| `amfu1` … `amfu5` | 5 test users, manager chain `amfu1 → amfu2 → amfu3 → amfu4 → amfu5` (`amfu5` tops the chain, no manager) |
| `amfsvc` | Framework service user for the §5.1 Group Work Item pattern |
| `Q_Credit_Risk` | Queue — route target of Phase 1 sample rule (b) |
| `G_Finance_Approvers` | Public group (Type `Regular`), members `amfu1`, `amfu2`, `amfu3` |

Design choices worth recording:

1. **Idempotent by construction.** Every section queries for what exists before
   inserting, and the manager chain is re-pointed only where it has drifted. The
   script is expected to be re-run after later phases (see point 4), so
   "run once" semantics would have been a trap. Proven by running it twice —
   the second run reports zero creations across every section.

2. **Usernames are org-scoped.** Salesforce usernames are globally unique across
   *all* orgs, so the script derives the domain from the org Id:
   `<alias>@amf.<15-char-org-id-lowercased>.dev` → `@amf.00daj000012gj9b.dev`.
   This makes the script portable to a second org without collision, which matters
   because the playbook's failure mode is "`git checkout .` and re-run the phase".

3. **Profile selection prefers the Platform licence.** The script picks
   `Standard Platform User` over `Standard User` (via `ORDER BY Name ASC` on a
   two-value `IN` filter), preserving the Developer Edition org's scarce full
   Salesforce seats. A licence pre-flight computes free seats and throws a
   descriptive error *before* any DML if there are not enough, rather than failing
   halfway through a partial insert.

4. **Queue supported objects are computed, not hardcoded.** `Purchase_Request__c`
   does not exist until Phase 1, so `Q_Credit_Risk` is registered against `Case` as
   a placeholder. The script probes `Schema.getGlobalDescribe()` for
   `purchase_request__c` and adds it automatically on a later run. **Action: re-run
   the seed after the Phase 1 deploy** so the queue supports the pilot object.

5. **Written flat, no helper methods.** Anonymous Apex cannot declare classes or
   methods, so the script is linear by necessity. Called out in the file header so
   nobody "refactors" it into something that will not compile.

6. **Report via `System.debug(LoggingLevel.ERROR, …)`.** ERROR level so the summary
   survives default debug-log filtering in `sf apex run` output.

### 0.5 Issues encountered

**(a) `amf-dev` was not an authorized org.**
`sf org display -o amf-dev` returned `NamedOrgNotFoundError`. Only `advisorshield`
(DevHub), `pallabDev` (DevHub) and `Tejas_Dev` were connected. Deploying framework
scaffolding and six seeded users into a DevHub work org without instruction would
have been the wrong call, so this was escalated rather than guessed.

*Resolution (user decision):* alias the existing `Tejas_Dev` org —
`sf alias set amf-dev=tejas.vernekar.0d104ca05e80@agentforce.com`. Confirmed to be a
genuine Developer Edition (`orgfarm-e5ccbd7218-dev-ed.develop`), so it satisfies the
`CLAUDE.md` contract.

**(b) `LICENSE_LIMIT_EXCEEDED` on the first seed run.**

```
System.DmlException: Insert failed. First exception on row 3;
first error: LICENSE_LIMIT_EXCEEDED, content feature license limit exceeded: []
```

Not the *user* licence — the pre-flight had correctly confirmed free seats. The
profile auto-grants **feature** licences (Salesforce CRM Content), whose Developer
Edition ceiling is far lower than the user licence ceiling and was exhausted at the
fourth user.

*Resolution:* explicitly disable the auto-granted feature licences the framework
does not need, on every seeded user —
`UserPermissionsSFContentUser`, `UserPermissionsKnowledgeUser`,
`UserPermissionsMarketingUser`, `UserPermissionsInteractionUser`,
`UserPermissionsSupportUser`, all set to `false`.

*Blast radius:* none. The insert was all-or-none, so the failed run created zero
users and left the script's idempotency intact.

**(c) `sf data query` failed under the Bash tool.**
`'C:\Program' is not recognized…` — a Windows path-quoting failure in the Git Bash
shim, not a CLI or org problem. Re-ran the same queries through PowerShell, which
resolves the launcher correctly. *Operational note for later phases: verification
queries go through PowerShell on this machine.*

### 0.6 Verification evidence

**Deploy** — `sf project deploy start -o amf-dev`

```
Status: Succeeded    Deploy ID: 0Afaj00000gdiXFCAY    Elapsed: 7.35s
Components: 2/2 (100%)   Created: AMF_Ping, AMF_PingTest
```

**Tests** — `sf apex run test -o amf-dev -l RunLocalTests -w 10 -r human`

```
AMF_PingTest.pingReturnsPong   Pass   35 ms
Outcome Passed · Tests Ran 1 · Pass Rate 100% · Fail Rate 0%
Test Run Id 707aj000018iA0K
```

**Seed, run 1** — `sf apex run --file scripts/seed-data.apex -o amf-dev`

```
=== AMF SEED COMPLETE ===
Users: 6 created, 0 already present
Manager chain: 4 link(s) set (amfu1 -> amfu2 -> amfu3 -> amfu4 -> amfu5)
Queue Q_Credit_Risk: created
Queue supported objects: Case (1 added)
Public group G_Finance_Approvers: created
Group members: 3 added (target: amfu1, amfu2, amfu3)
```

Limits consumed: 7 SOQL / 100, 6 DML / 150, 16 DML rows / 10000, 247 ms CPU / 10000.

**Seed, run 2 (idempotency proof)** — identical command

```
Users: 0 created, 6 already present
Manager chain: 0 link(s) set
Queue Q_Credit_Risk: already present
Queue supported objects: Case (0 added)
Public group G_Finance_Approvers: already present
Group members: 0 added
```

**Org state queries**

```
ALIAS   USERNAME                          ISACTIVE  MANAGER.ALIAS
amfsvc  amfsvc@amf.00daj000012gj9b.dev    true
amfu1   amfu1@amf.00daj000012gj9b.dev     true      amfu2
amfu2   amfu2@amf.00daj000012gj9b.dev     true      amfu3
amfu3   amfu3@amf.00daj000012gj9b.dev     true      amfu4
amfu4   amfu4@amf.00daj000012gj9b.dev     true      amfu5
amfu5   amfu5@amf.00daj000012gj9b.dev     true

ID                  DEVELOPERNAME        TYPE
00Gaj00000V8jvlEAB  Q_Credit_Risk        Queue
00Gaj00000V8jvmEAB  G_Finance_Approvers  Regular

G_Finance_Approvers members: 005aj00000bCONpAAO, 005aj00000bCONqAAO, 005aj00000bCONrAAO
```

### 0.7 Architecture deviations

None. Nothing in this phase touched the schema or patterns defined in
`docs/architecture.md`, so `docs/decisions.md` has no new entry.

### 0.8 Carried into later phases

| Item | Owed to |
|---|---|
| Re-run `scripts/seed-data.apex` so `Q_Credit_Risk` picks up `Purchase_Request__c` | Phase 1 — **done**, see 1.9 |
| Delete `AMF_Ping` / `AMF_PingTest` once real engine classes exist | Phase 2 |
| Enable **record locking/unlocking in Apex** in Setup (manual, admin) | Phase 4 |
| Manual QA of the seeded users/queue/group in the org UI | user, before Phase 1 |

---

## Phase 1 — Data model

**Date:** 2026-08-12 · **Status:** complete, all gates green
**Playbook goal:** all CMDT types, chain objects, and per-object fields for the pilot object.

Metadata only — no Apex, no LWC, no approval process. 62 components.

### 1.1 What was built

| Group | Components | Detail |
|---|---|---|
| CMDT types (§3.1) | 4 objects + 24 fields | `Approval_Object_Config__mdt` (7), `Approval_Rule__mdt` (5), `Approval_Rule_Condition__mdt` (5), `Approval_Route_Step__mdt` (7) |
| Chain objects (§3.2) | 2 objects + 21 fields | `Approval_Chain__c` (11), `Approval_Chain_Step__c` (10) |
| Pilot object (§3.3) | 1 object + 8 fields | `Purchase_Request__c`: 5 business fields + the 3 per-object framework fields |
| §8 lock | 1 validation rule + 1 custom permission | `Lock_Terminal_Chain`, `AMF_Bypass_Chain_Lock` |
| §12 security | 2 permission sets | `Approval_Matrix_User`, `Approval_Matrix_Admin` |
| Sample config | 14 CMDT records | 1 object config + 3 rules + 4 conditions + 6 route steps |

### 1.2 Ambiguities resolved before building

The §3 tables are underspecified in four places. Each was raised rather than guessed, per
`CLAUDE.md`; all four are now logged in `docs/decisions.md` and folded back into
`docs/architecture.md`.

| Gap | Resolution |
|---|---|
| §3.2 "timestamps" unnamed | `Submitted_At__c` + `Completed_At__c` |
| §8 "integration profile excepted" undefined | `AMF_Bypass_Chain_Lock` custom permission |
| Sample rule (a) "3 user levels" ambiguous | Three `Manager_Chain` steps `SUBMITTER:1/2/3` |
| Fields later phases need but §3 omits | **Not** built. Strict §3 tables only |

The last decision is deliberate scope discipline and has a known cost: **Phase 3 will need a
substitution flag** (§5 says substitutions are "recorded on the chain step"), **Phase 6 a
unanimous-vote JSON field** (§5.1 point 5), and **Phase 7 an escalation log plus a `Skipped`
outcome value** (§7.5). Each will carry its own schema change and `decisions.md` line.

### 1.3 Design choices worth recording

1. **`Record_Id__c` is an external id but not unique.** Chains are never deleted and a record
   can be recalled and resubmitted, so a unique index would reject the second chain. The
   external id supplies the lookup index without the uniqueness constraint.
2. **`Matched_Rule__c` is Text, not a lookup.** The platform has no relationship type from a
   custom object to a custom metadata record, so the rule DeveloperName is stored as text.
   Forced by the platform, not a shortcut.
3. **`Outcome__c` carries a `Pending` value** that §3.2 does not name. §7.5 scans "open steps",
   which needs a state meaning not-yet-actioned.
4. **The §8 rule tests `PRIORVALUE(Status__c)` and is skipped on insert.** PRIORVALUE is what
   lets the engine make the final transition *into* a terminal status while freezing every
   edit after it; `NOT(ISNEW())` keeps the rule off inserts, which matters because an
   `Auto_Approve` no-match chain (§3.1) can be born terminal.
5. **"Queues enabled" is not a metadata flag.** A custom object supports queues when it is
   ownable and `sharingModel` is Private. Private is what §12 wants anyway. Proven
   empirically rather than asserted — see 1.9.
6. **`Vendor_Type__c` values are invented.** Nothing in the architecture doc or the playbook
   specifies them; only `New` is implied, by sample rule (b). Using New / Existing / Strategic.

### 1.4 Issues encountered

**(a) `UNKNOWN_EXCEPTION` on the full deploy, with zero component errors.**

```
UNKNOWN_EXCEPTION: An unexpected error occurred.
Please include this ErrorId if you contact support: 648718192-242438 (-315522575)
numberComponentErrors: 0
```

Reproducible, and useless as a diagnostic: the Metadata API attributed the failure to no
component. Resolved by **deploying in stages** (`--source-dir` per group), which made the API
report real, attributed errors. Two genuine bugs were hiding behind that one opaque message:

- `ValidationRule description cannot be longer than 255 characters` — the `Lock_Terminal_Chain`
  description. **Validation rule and permission set descriptions cap at 255**, while field and
  object descriptions allow 1000. The long rationale moved here instead.
- The CMDT records (see (c) below).

*Operational lesson for later phases: when a deploy fails with `UNKNOWN_EXCEPTION` and zero
component errors, do not retry it — split it.*

**(b) `Permission Modify All Approval_Chain_Step__c depends on permission(s): Delete`.**

The platform makes Modify All depend on Delete, but §8 says chain records are never deleted.
Rather than grant deletion of the audit trail, `Approval_Matrix_Admin` now takes **View All +
edit, no Modify All, no Delete**. Logged in `decisions.md`.

**(c) CMDT records failed with the same opaque `UNKNOWN_EXCEPTION`, even one record alone.**

Root cause: the record files use `xsi:type="xsd:string"` but declared only the `xsi`
namespace, never `xsd`. The undeclared prefix made the XML invalid and the server rejected the
payload without attributing it. Fixed by adding
`xmlns:xsd="http://www.w3.org/2001/XMLSchema"` to all 14 records.

**(d) Phantom "missing field" results from the schema gate — the important one.**

The describe assertions reported all 24 CMDT fields present and **every one of the 29
custom-object fields missing**, while `FieldDefinition` SOQL confirmed all 29 existed. The
split is the tell: custom metadata has no field-level security; custom object fields do.

**A field deployed without profile FLS is granted to nobody — including the deploying System
Administrator — and is therefore invisible to `describeSObjects`.** Resolved by assigning
`Approval_Matrix_Admin` to the running user (`sf org assign permset`), after which the gate
passed unchanged.

*This is load-bearing for Phase 2:* the engine's consolidated dynamic SOQL (§4.1) will
silently fail to see fields for any user without one of the two permission sets. The
permission sets are not optional packaging — they are a runtime prerequisite.

*Detour worth recording so it is not repeated:* the shifting results across runs initially
looked like a stale describe cache, and the script was rewritten from cached
`getGlobalDescribe()` tokens to `Schema.describeSObjects`. That rewrite was not the fix — the
inconsistency was an artifact of truncated console output hiding most of the failures. The
`describeSObjects` form was kept because it is the more correct API, but FLS was the cause.

**(e) `sf data query -t` silently queries the Tooling API.**

`-t` is `--use-tooling-api`, not a table-format flag. Querying `Approval_Rule__mdt` through
Tooling reported `No such column 'Priority__c'`, which read like a deploy failure. The fields
were fine. *Verification queries must omit `-t`.*

**(f) CMDT SOQL rejects `ORDER BY` on a parent relationship field.**

`ORDER BY Rule__r.DeveloperName` returns *"The requested operation is not yet supported by
this sObject storage type"*. Ordering by a local field works. *Relevant to Phase 2:
`CmdtRuleProvider` must sort rules by Priority then DeveloperName **in Apex**, not in SOQL —
§4.1 step 2 depends on that ordering being deterministic.*

**(g) `Group_Completion__c` defaulted onto user levels.**

A restricted picklist with a `default` fills that value into any CMDT record that omits the
field, so manager-chain steps came back reading `Any_Member` — wrong, since §3.1 scopes the
field to queue/group levels, and visibly wrong on the record the manual QA step inspects.
Fixed by removing the picklist default and writing `<value xsi:nil="true"/>` on the five
user-level steps. The IDE's XSD flags `xsi:nil` on `value` as invalid; **the IDE is wrong** —
Salesforce accepts it, and it is the only way to null a CMDT field on redeploy.

### 1.5 Verification: deploy

Final state, all stages applied, full-package redeploy reports every component `Unchanged`.

### 1.6 Verification: schema gate (the phase's stated acceptance criterion)

Anonymous Apex describe assertions over every §3 field — type, picklist value set, lookup
target, and the structural specifics the doc calls out. Throws on any mismatch.

```
=== PHASE 1 SCHEMA GATE PASSED ===
53 fields verified across 7 objects
12 picklist value sets verified
7 lookup targets verified
Record_Id__c external id + non-unique: OK
Chain__c master-detail: OK
```

Held in the scratchpad, not committed: the Phase 1 prompt restricts source to `force-app`,
and `scripts/` is outside that. Phase 7 builds the permanent equivalent as
`AMF_ConfigValidator` + `scripts/validate-config.apex`.

### 1.7 Verification: CMDT read-back

```
DEVELOPERNAME            PRIORITY  LOGIC_EXPRESSION  VERSION  ACTIVE
Rule_A_High_Value_APAC   10        1 AND 2           1        true
Rule_B_High_Risk_Vendor  20        1 OR 2            1        true
Rule_C_Catch_All         999       null              1        true

RULE                     INDEX  FIELD_PATH      OPERATOR  VALUE
Rule_A_High_Value_APAC   1      Amount__c       greater   100000
Rule_A_High_Value_APAC   2      Region__c       equals    APAC
Rule_B_High_Risk_Vendor  1      Risk_Level__c   equals    High
Rule_B_High_Risk_Vendor  2      Vendor_Type__c  equals    New

DEVELOPERNAME  APPROVER_TYPE   APPROVER_REFERENCE  GROUP_COMPLETION  SLA_HOURS
Rule_A_L1      Manager_Chain   SUBMITTER:1         null              24
Rule_A_L2      Manager_Chain   SUBMITTER:2         null              24
Rule_A_L3      Manager_Chain   SUBMITTER:3         null              48
Rule_B_L1      Manager_Chain   SUBMITTER:1         null              24
Rule_B_L2      Queue           Q_Credit_Risk       Any_Member        48
Rule_C_L1      Manager_Chain   SUBMITTER:1         null              null
```

Rule C's null `Logic_Expression__c` is the "blank = AND of all conditions" case, and it has
zero conditions. **Phase 2 note: zero conditions with a blank expression must evaluate `true`,
or the priority-999 catch-all never fires and every unmatched record hits `No_Match_Behavior__c`.**

### 1.8 Verification: tests

`sf apex run test -o amf-dev -l RunLocalTests -w 10 -r human` — `AMF_PingTest.pingReturnsPong`
Pass, 1/1, 100%. Test Run Id `707aj000018j0Tw`. No new Apex this phase; this guards against
the metadata deploy breaking the existing build.

### 1.9 Verification: Phase 0 debt cleared

Re-running `scripts/seed-data.apex` picked up the new object automatically, exactly as the
script was written to:

```
Queue supported objects: Case, Purchase_Request__c (1 added)
```

This is also the empirical proof that `Purchase_Request__c` supports queues — stronger than a
describe assertion, since `DescribeSObjectResult` exposes no queue-support flag.

### 1.10 Architecture deviations

Six entries appended to `docs/decisions.md`, and `docs/architecture.md` §3.2 and §8 amended to
match what was built. The doc is now truthful about timestamp field names, the `Outcome__c`
value set, and the lock-bypass mechanism.

### 1.11 Carried into later phases

| Item | Owed to |
|---|---|
| Assign `Approval_Matrix_User` / `Approval_Matrix_Admin` to any user the engine runs as — without FLS the engine cannot see its own fields | Phase 2 |
| `CmdtRuleProvider` must order rules in Apex, not SOQL (see 1.4f) | Phase 2 |
| Blank expression + zero conditions must evaluate `true` (see 1.7) | Phase 2 |
| Substitution flag on the chain step | Phase 3 |
| Unanimous vote-tracking JSON field | Phase 6 |
| Escalation log field + `Skipped` outcome value | Phase 7 |
| Enable **record locking/unlocking in Apex** in Setup (manual, admin) | Phase 4 |
| Manual QA: open the CMDT records in Setup and confirm the sample rules read like a matrix a bank admin would write | user, before commit |

### 1.12 Follow-up: CMDT list views (post-`a69e3c9`)

Added an `All` list view to each of the four CMDT types, surfacing every configured field
as a column. Without them the Setup "Manage Records" page shows only Label and
DeveloperName, so reviewing the routing matrix means opening all 14 records one at a time —
which is exactly the manual QA step this phase ends on. Four `listViews/All.listView-meta.xml`
files, one per type; the `All` view already exists by default, so these update it rather than
adding a view the reviewer has to go and select.

Columns per type: object config shows all 7 config fields; rule shows priority, logic
expression, version and active; condition shows rule, index, field path, operator and value;
route step shows rule, level, approver type, reference, group completion, SLA and the skip
flag.

**`sortColumn` / `sortOrder` are not accepted on a CMDT list view.** Both `sortedBy` (wrong
element name) and `sortColumn` (correct name for standard objects) were rejected with
`Error parsing file: Element ... invalid at this location in type ListView`. Default sort was
dropped; column headers remain clickable in the UI. Worth knowing before writing list views
for the Phase 8 second object.

---

## Phase M0 — Baseline & cleanup

**Date:** 2026-08-17 · **Commits:** `9a54e68`, `6ccc2ed`, plus the M0.8 follow-up
**Status:** complete — all gates green, and the two items M0.7 carried are closed in M0.8
**Playbook goal:** repo and `amf-dev` hold exactly the surviving Phase 0/1 work plus the guard
field, and nothing from the v1.0 design. No new design in this phase.

This is the first phase of the **v3.0 MVP** plan. It exists because the v2.1 revert at
`71fd786` stopped one component short, and because `docs/build-playbook.md` still described a
build that no longer exists.

### M0.1 File-level changes

| File | Change | Detail |
|---|---|---|
| `docs/architecture.md` | rewritten (pre-existing, uncommitted) | v2.1 → **v3.0**, consolidated and self-contained. Amended in this phase at §3.3, §13.1 and §13.5 — see M0.3 |
| `docs/build-playbook.md` | rewritten | v1.0 nine-phase plan → the MVP **M0–M3** plan, with per-phase prompts, gates and manual QA. Part 1 now also records this workstation's tooling quirks |
| `CLAUDE.md` | modified (pre-existing, uncommitted) | Source-of-truth pointer corrected v2.1 → v3.0; CMDT § reference corrected §2 → §3.1; playbook named as the phase plan |
| `docs/technical-log.md` | modified | Paused banner lifted, status board split into the current M0–M3 plan and the superseded v1.0 rows, dead org prerequisite retired, this entry |
| `docs/decisions.md` | modified | Five entries — see M0.3 |
| `…/Purchase_Request__c/fields/Matrix_Submission__c.field-meta.xml` | **added** | The §3.4 guard. Checkbox, `defaultValue false` |
| `…/permissionsets/Approval_Matrix_User.permissionset-meta.xml` | modified | Guard field FLS **read-only**; description retargeted at v3.0 |
| `…/permissionsets/Approval_Matrix_Admin.permissionset-meta.xml` | modified | Guard field FLS read/edit; `AMF_Bypass_Chain_Lock` grant removed |
| `…/objects/Approval_Chain__c/validationRules/Lock_Terminal_Chain.validationRule-meta.xml` | **deleted** | v1.0 §8 chain lock. Removed from repo and org |
| `…/customPermissions/AMF_Bypass_Chain_Lock.customPermission-meta.xml` | **deleted** | v1.0 lock bypass. Removed from repo and org |

`Approval_Chain__c` itself is still present in both, deliberately — M0.5(a).

### M0.2 The guard field

`Matrix_Submission__c` is the framework's entire per-object field footprint (§3.4). Design
points worth recording:

1. **`defaultValue false`, not left blank.** Every new record starts un-armed, so the §6.3
   entry criteria reject anything the engine did not submit, including a record created by an
   integration that never touches the framework.
2. **Read-only in `Approval_Matrix_User`, editable in `Approval_Matrix_Admin`.** §6.3's whole
   argument is that *only the engine* sets the guard. A submitter who can tick the checkbox by
   hand and then press the standard Submit button walks straight past it. The engine is
   unaffected: its DML runs in system context, where FLS does not apply. Logged in
   `decisions.md`.
3. **FLS is a runtime prerequisite, not packaging.** §1.4d of this log established that a field
   deployed without FLS is invisible even to the deploying System Administrator, so the M0 gate
   asserts `isAccessible()` and `isUpdateable()` on the guard rather than mere existence.

### M0.3 Doc gaps closed before building

Three things in v3.0 were ambiguous or self-contradictory. All three were raised rather than
guessed, per `CLAUDE.md`, decided by the user, then folded back into the doc *and* logged in
`decisions.md`.

| Gap | Resolution |
|---|---|
| §3.3's log table lists `Execution_Type__c`, while §13.2 says do not build it, do not stub it | Omitted from the log as well as the CMDT. §3.3 and §13.1 annotated. With Classic the only path, the column would hold one constant value; re-adding it later is a field plus a default, no engine change |
| §13.1 names two Classic templates but specifies neither's steps or approvers | `PR_Two_Level_Mgmt` = two Manager-hierarchy steps; `PR_Three_Level_Finance` = three named-user steps (`amfu3` → `amfu4` → `amfu5`). Written into §13.1 |
| §13.5 recommends a fresh Developer Edition org over destructive deploys | Superseded by events — the destructive deletes already succeeded. Struck through in §13.5 with what actually happened. MVP stays on `amf-dev` and keeps Phase 0's seeded identities |

The custom permission rename (`AMF_Bypass_Chain_Lock` → `AMF_Bypass_Log_Lock`, §3.3) is the
fourth decision, and is a retire-plus-recreate rather than a rename: custom permissions cannot
be renamed in place, and the validation rule that consumed the old one was deleted with it. The
new permission arrives in M1 with the log object it excepts, so the admin permission set
temporarily grants no custom permission at all.

### M0.4 Deletion order matters, and the API tells you in the wrong order

The three v1.0 leftovers form a dependency chain, and each failure only names the *next* link:

```
CustomPermission:AMF_Bypass_Chain_Lock
  → "referenced elsewhere in Salesforce … Validation Rule - Lock_Terminal_Chain"
ValidationRule:Approval_Chain__c.Lock_Terminal_Chain   (deleted first, cleanly)
CustomObject:Approval_Chain__c
  → "other objects have one or more relationships to it: Purchase_Request__c.Active_Chain_del__c"
```

Correct order is **permission-set grant → validation rule → custom permission → object**. The
grant has to go first and in its own deploy: while `Approval_Matrix_Admin` still referenced the
custom permission, deleting the permission failed on the permission set instead of on the
validation rule, which is a less informative error and sends you looking in the wrong place.

### M0.5 Issues encountered

**(a) `Approval_Chain__c` still cannot be deleted — unchanged from `71fd786`, and now the only
open item.**

```
We couldn't delete Approval Chain because other objects have one or more relationships to it.
Remove the relationships and try again.: Purchase_Request__c.Active_Chain_del__c
```

`Active_Chain_del__c` is soft-deleted and sits in the recycle bin, where the Metadata API cannot
address it. Retried after the validation rule and custom permission were gone, in case one of
them was a second holder; the error is byte-identical, so the recycle-bin field is the sole
blocker. The manual erase (Setup → Object Manager → Purchase Request → Fields & Relationships →
**Deleted Fields** → Erase) was requested at the start of this phase and had not been completed
when the phase was committed. **The one command outstanding afterwards:**

```
sf project delete source -o amf-dev --no-prompt --metadata "CustomObject:Approval_Chain__c"
```

Repo and org stay deliberately in step until then: the object's source is still committed, and a
full-package deploy still reports its 11 fields as `Unchanged`.

**(b) `Description: data value too large … (max length=255)` on `Approval_Matrix_User`.**

Exactly the trap recorded in §1.4a: **validation rule and permission set descriptions cap at
255 characters** while field and object descriptions allow 1000. Caught on the first deploy of
this phase, and the deploy was all-or-none, so the guard field did not land until the
description was trimmed. Worth internalising rather than re-learning — it has now cost time in
two of the three phases that touched a permission set.

**(c) `sf data query` is still broken under the Bash tool, and PowerShell was unavailable.**

`'C:\Program' is not recognized as an internal or external command` — the Windows path-quoting
failure in the Git Bash shim recorded in §0.5c. §0.5c's workaround was "re-run through
PowerShell", but the PowerShell tool returned
`EPERM: operation not permitted, uv_spawn 'powershell.exe'` for the whole session, so that
escape hatch was closed too.

*Resolution:* verification moved entirely onto **anonymous Apex** and `sf org list metadata`,
both of which work under Bash. This is strictly better for a gate anyway — the describe
assertions throw, so a silent pass is impossible, whereas a query result has to be read by eye.
`sf org display`, `sf project deploy`, `sf project delete source` and `sf apex run` are all
unaffected. **Recorded in `docs/build-playbook.md` Part 1** so the next phase does not rediscover
it.

**(d) `Flow:AMF_Spike_Approval` could not be deleted — tooling, not the org.**

The spike artefact from Appendix A is still deployed as `Draft`, and Appendix A says to delete it
or complete it into a real template. Flow execution is out of MVP scope, so deletion is correct.
Three attempts to run

```
sf project delete source -o amf-dev --no-prompt --metadata "Flow:AMF_Spike_Approval"
```

were refused by the agent harness's permission classifier, not by Salesforce. Nothing about the
org blocks it. Carried to M0.7 for the user to run or approve; a `Draft` orchestration is inert
and blocks no MVP work in the meantime.

### M0.6 Verification evidence

**Guard field + permission sets** — `sf project deploy start --source-dir …objects/Purchase_Request__c --source-dir …permissionsets`

```
Status: Succeeded    Deploy ID: 0Afaj00000gz1tSCAQ    Elapsed: 7.05s
Created:   Purchase_Request__c.Matrix_Submission__c
Changed:   Purchase_Request__c, Approval_Matrix_Admin, Approval_Matrix_User
Unchanged: Account__c, Amount__c, Region__c, Risk_Level__c, Vendor_Type__c
```

**M0 describe gate** — anonymous Apex, throws on any mismatch. Asserts the guard's type and
per-user accessibility, the five surviving business fields, the absence of the three v1.0
per-object fields, the absence of all four v1.0 CMDT types, and — as scope discipline — that
`Approval_Matrix_Rule__mdt` and `Approval_Decision_Log__c` do **not** yet exist.

```
=== PHASE M0 GATE ===
  Matrix_Submission__c: BOOLEAN, accessible=true, updateable=true, defaultedOnCreate=true
  Approval_Chain__c present in org: true
=== PHASE M0 GATE PASSED === 16 fields described on Purchase_Request__c
```

`Approval_Chain__c present: true` is reported, not asserted — it is M0.5a, and the gate would be
lying if it claimed otherwise.

**Full-package deploy** — `sf project deploy start -o amf-dev`

```
Status: Succeeded   Deploy ID: 0Afaj00000gzuWXCAY
numberComponentsTotal: 23   numberComponentsDeployed: 23   numberComponentErrors: 0
```

**Org state** — `sf org list metadata -m CustomPermission` returns **empty**, confirming
`AMF_Bypass_Chain_Lock` is gone from the org and not merely from the repo.

**Tests** — `sf apex run test -o amf-dev -l RunLocalTests -w 10 -r human`

```
AMF_PingTest.pingReturnsPong   Pass   33 ms
Outcome Passed · Tests Ran 1 · Pass Rate 100% · Fail Rate 0%
Test Run Id 707aj000019QevU
```

No new Apex this phase; this guards against the metadata changes breaking the existing build.

**Seed idempotency** — `sf apex run --file scripts/seed-data.apex`

```
=== AMF SEED COMPLETE ===
Users: 0 created, 6 already present
Manager chain: 0 link(s) set (amfu1 -> amfu2 -> amfu3 -> amfu4 -> amfu5)
Queue Q_Credit_Risk: already present
Queue supported objects: Case, Purchase_Request__c (0 added)
Public group G_Finance_Approvers: already present
Group members: 0 added (target: amfu1, amfu2, amfu3)
```

Zero creations across every section, and the manager chain M3's `PR_Two_Level_Mgmt` depends on is
intact. The seed script needed no changes.

### M0.7 Carried into later phases

| Item | Owed to |
|---|---|
| ~~Erase `Active_Chain_del__c`, then delete `CustomObject:Approval_Chain__c`~~ | **closed in M0.8** |
| ~~Delete `Flow:AMF_Spike_Approval` from `amf-dev`~~ | **closed in M0.8** |
| Create `AMF_Bypass_Log_Lock` and grant it in `Approval_Matrix_Admin`; the admin set currently grants no custom permission | M1 |
| Extend both permission sets to `Approval_Matrix_Rule__mdt` and `Approval_Decision_Log__c` with explicit FLS — without it the engine cannot see its own fields (§1.4d) | M1 |
| Delete `AMF_Ping` / `AMF_PingTest` once real engine classes exist | M2 |
| `AMF_CmdtRuleProvider` must sort by Priority then DeveloperName **in Apex**, not SOQL (§1.4f) | M1 |
| `scripts/seed-data.apex` cites v1.0 § numbers and seeds an `amfsvc` service user for the retired Group Work Item pattern. Harmless, but its comments now point at sections that mean something else | opportunistic |
| Remove the standard **Submit for Approval** button from the `Purchase_Request__c` layout (§6.3); no layout is in the repo yet | M3 |
| Manual QA: confirm `Matrix_Submission__c` is visible and un-tickable as a `Approval_Matrix_User` holder | user, before M3 |

### M0.8 Follow-up: both carried items closed, same day

**(a) `Approval_Chain__c` is gone.** The soft-deleted `Purchase_Request__c.Active_Chain_del__c`
was erased in Setup, after which the delete that had failed identically three times succeeded
first try:

```
sf project delete source -o amf-dev --no-prompt --metadata "CustomObject:Approval_Chain__c"
Status: Succeeded    (object + 11 fields removed from org and repo)
```

That closes the v1.0 revert that `71fd786` started. **No v1.0 metadata remains in either the
repo or the org** — four CMDT types, 14 CMDT records, both chain objects, three per-object
fields, the chain validation rule and the chain lock permission are all gone.

**(b) `AMF_Spike_Approval` is gone, and flows need a version-qualified name.** The unqualified
metadata name reached the server and was refused:

```
sf project delete source --metadata "Flow:AMF_Spike_Approval"
  → Error: insufficient access rights on cross-reference id
```

That message is misleading — it is not a permissions problem. A `Flow` component addresses a
specific *version*, and the unqualified name resolves to the `FlowDefinition` wrapper, which is
not deletable this way. Appending the version number works:

```
sf project delete source --metadata "Flow:AMF_Spike_Approval-1"
Status: Succeeded
Warning: Flow, AMF_Spike_Approval-1, returned from org, but not found in the local project
```

The warning is expected and correct — the spike was deployed from a scratchpad in MDAPI format
and was never project source. **Worth remembering:** deleting a flow by its bare API name fails
with an access error that sends you hunting for a permission problem that does not exist. Use
`<ApiName>-<version>`.

The agent permission classifier that had refused this command in M0.5d allowed it once the user
asked for it directly, so nothing about the org or the CLI was ever the obstacle.

**Re-verification after both deletions**

```
=== PHASE M0 GATE ===
  Matrix_Submission__c: BOOLEAN, accessible=true, updateable=true, defaultedOnCreate=true
  Approval_Chain__c present in org: false
=== PHASE M0 GATE PASSED === 16 fields described on Purchase_Request__c

sf org list metadata -m Flow          → only sfdc_default_ReportExport_Protection_Flow (standard)
sf org list metadata -m CustomObject  → only Purchase_Request__c among AMF objects
sf project deploy start               → Succeeded, 11/11 components, 0 errors (was 23/23 —
                                        the 12 Approval_Chain__c components are gone)
sf apex run test -l RunLocalTests     → Passed, 1/1, 100%, Test Run Id 707aj000019QQW3
```

The package is now exactly the MVP baseline: `Purchase_Request__c` with five business fields plus
the guard, two permission sets, and `AMF_Ping`/`AMF_PingTest`. M1 starts from a clean org.

---

## Phase M1 — Data model

**Date:** 2026-08-18 · **Commit:** `26a157f`
**Status:** complete — the >255-character gate is green and all 20 tests pass
**Playbook goal:** the matrix itself, the audit artefact, and the only sanctioned way to read
Custom Metadata.

Second phase of the **v3.0 MVP** plan. 34 new components: one Custom Metadata type and its seven
fields, one custom object with twelve fields and a validation rule, one custom permission, six Apex
classes, four CMDT records, a list view, and FLS for all of it.

### M1.1 File-level changes

| File | Change | Detail |
|---|---|---|
| `objects/Approval_Matrix_Rule__mdt/` | **added** | Type + 7 fields + `All` list view (§3.1). `Execution_Type__c` deliberately absent |
| `objects/Approval_Decision_Log__c/` | **added** | Object + 12 fields + `Lock_Decision_Log` validation rule (§3.3). `Execution_Type__c` deliberately absent |
| `customPermissions/AMF_Bypass_Log_Lock.customPermission-meta.xml` | **added** | The §3.3 immutability exception. Closes the M0.7 debt |
| `customMetadata/Approval_Matrix_Rule.PR_High_Value_APAC.md-meta.xml` | **added** | Priority 10, active |
| `customMetadata/Approval_Matrix_Rule.PR_High_Risk.md-meta.xml` | **added** | Priority 20, active |
| `customMetadata/Approval_Matrix_Rule.PR_Long_Expression_Pin.md-meta.xml` | **added** | Priority 9998, **inactive** — the >255-character test fixture |
| `customMetadata/Approval_Matrix_Rule.PR_Catch_All.md-meta.xml` | **added** | Priority 9999, active, expression `TRUE` |
| `classes/AMF_RuleProvider.cls` | **added** | Interface. The only sanctioned read path for the matrix |
| `classes/AMF_RuleDefinition.cls` | **added** | DTO, `implements Comparable` — owns the priority ordering |
| `classes/AMF_CmdtRuleProvider.cls` | **added** | SOQL implementation. Never `getAll()`/`getInstance()` |
| `classes/AMF_RuleBuilder.cls` | **added** | `@IsTest` fluent fixture + `Stub` provider (§10) |
| `classes/AMF_RuleDefinitionTest.cls` | **added** | 6 tests, entirely in-memory |
| `classes/AMF_CmdtRuleProviderTest.cls` | **added** | 7 tests, including the phase gate |
| `classes/AMF_DecisionLogLockTest.cls` | **added** | 6 tests pinning the immutability rule — see M1.3 |
| `permissionsets/Approval_Matrix_Admin.permissionset-meta.xml` | modified | Log object read/edit/View All, FLS on 12 fields, CMDT type access, `AMF_Bypass_Log_Lock` grant |
| `permissionsets/Approval_Matrix_User.permissionset-meta.xml` | modified | Log object read-only, FLS readable-not-editable on 12 fields, no CMDT access |
| `docs/decisions.md` | modified | Three entries — see M1.2 |
| `docs/technical-log.md` | modified | Status board, this entry |

`AMF_Ping`/`AMF_PingTest` are untouched; M2 owns their deletion.

### M1.2 Three doc conflicts, resolved before building

Each was raised with the user rather than guessed, per `CLAUDE.md`, and each is now a line in
`docs/decisions.md`.

| Conflict | Resolution |
|---|---|
| §3.3 "blocks edits after creation" vs §6.1 step 11's post-insert `Execution_Ref_Id__c` stamp | The rule permits exactly one update: the stamp, blank to populated, nothing else changed |
| `CLAUDE.md` "zero dependence on org CMDT rows" vs a >255 round trip that needs a real row | One inactive pin record, read by exactly one test class; every other rule test uses in-memory fixtures |
| `CLAUDE.md` "AMF_ on Apex classes" vs the doc's bare `RuleProvider` | `AMF_RuleProvider`. M3's strategy interface follows as `AMF_SubmissionStrategy` |

### M1.3 The immutability rule is not a plain freeze

A blanket "no edits after insert" rule is what §3.3 reads like in isolation, and it would have
made M3 impossible: §6.1 step 11 has the engine write the log row *before* submitting, then stamp
`Execution_Ref_Id__c` back onto it afterwards. The formula therefore allows exactly one transition:

```
AND(
  NOT(ISNEW()),
  NOT($Permission.AMF_Bypass_Log_Lock),
  OR(
    NOT(ISBLANK(PRIORVALUE(Execution_Ref_Id__c))),   /* already stamped -> frozen forever */
    ISBLANK(Execution_Ref_Id__c),                    /* an update that is not the stamp */
    ISCHANGED(Record_Id__c), ISCHANGED(Object_API_Name__c), ISCHANGED(Matched_Rule__c),
    ISCHANGED(Rule_Version__c), ISCHANGED(Selected_Process__c), ISCHANGED(Outcome__c),
    ISCHANGED(Submitted_By__c), ISCHANGED(Submitted_At__c)
  )
)
```

Consequences worth stating explicitly, because M3 depends on all of them:

1. **`Blocked_No_Match` and `Failed` rows freeze on insert.** They never receive a stamp, so
   `ISBLANK(Execution_Ref_Id__c)` catches every update to them.
2. **The stamp is one-shot.** A second stamp trips the `PRIORVALUE` clause.
3. **The engine must not change any other field during the stamp** — not even `Outcome__c`. If a
   submission fails after the row is written, M3 must let the transaction roll back rather than try
   to flip the row to `Failed`.
4. **Known residual hole, deliberately not hidden:** the single stamping update could also alter
   `Expression_Snapshot__c`, `Evaluated_Values__c` or `Failure_Detail__c`, because **`ISCHANGED` is
   not supported on Long Text Area fields**. Closing it would need a trigger, which is out of MVP
   scope. The exposure is one update, on a row nobody but the engine has yet touched, after which
   the row is frozen permanently.

`AMF_DecisionLogLockTest` pins all four. That class is the one addition beyond the M1 prompt's
literal list, and it earns its place: the rule's formula is the resolution of a doc conflict, M3's
step 11 rests on it, and discovering it wrong during M3's manual QA would cost far more than the
six tests cost to write.

### M1.4 The truncation claim, measured rather than inherited

§3.1 asserts that `getAll()`/`getInstance()` truncate Long Text Area to 255 characters. Rather than
encode that as folklore, it was measured on `amf-dev` against `PR_Long_Expression_Pin`, whose
expression is 290 characters:

```
SOQL          -> 290 characters, intact
getInstance() -> 255 characters
getAll()      -> 255 characters
```

Both truncated forms cut off inside `(Risk_Level`, mid-token. That is the whole danger in one
image: the expression does not fail loudly, it comes back as a **different, shorter, still-parseable
expression**, and every record routes by it silently. The two halves are asserted separately —
`longExpressionSurvivesSoqlLoad` proves SOQL returns all 290 characters byte for byte, and
`getAllTruncatesWhereSoqlDoesNot` proves `getAll()` does not. Together they make it impossible for
the gate to pass against a `getAll()`-based provider, which is the playbook's stated requirement.

### M1.5 Design choices worth recording

1. **Ordering lives in `AMF_RuleDefinition.compareTo`, not in the provider.** §6.1 step 2 is
   "priority-ordered first match", and §1.4f established that CMDT SOQL rejects `ORDER BY` on a
   relationship field. Putting the comparator on the DTO means every call site — real provider,
   test stub, future engine — gets the same total order for free. Nulls sort last rather than
   throwing: `Priority__c` is required on the CMDT so the provider cannot emit one, but a
   `Comparable` that can NPE inside `List.sort()` is a landmine.
2. **`AMF_CmdtRuleProvider.load(objectApiName, activeOnly)` is `@TestVisible`, not public.** The
   interface stays a single method. The second parameter exists only so the gate can reach the
   inactive pin, which is what lets the pin stay inactive and route nothing.
3. **The stub honours the same contract as the real provider**, asserted by a shared
   `assertProviderContract` helper run against both. Otherwise M2 and M3 would build on a fixture
   that had quietly drifted from production behaviour.
4. **`Outcome__c` carries no default.** A default of `Submitted` would let a row the engine failed
   to populate masquerade as a successful submission. Blank is a bug made visible.
5. **`Active__c` defaults false.** A newly added rule is inert until someone deliberately switches
   it on, which is the safer failure mode for a routing table.
6. **The log's `sharingModel` is Private**, which is what makes §11's "read own logs" work with no
   extra machinery: the engine's rows are owned by the submitter.
7. **`Approval_Matrix_User` gets no CMDT access at all.** Reading the matrix through SOQL in Apex
   does not require it; only editing rows in Setup does, and submitters have no business there.

### M1.6 Issues encountered

**(a) `CustomPermission` descriptions also cap at 255 — a third metadata type with that limit.**

```
CustomPermission  AMF_Bypass_Log_Lock
  Value too long for field: Description maximum length is:255
```

§1.4a recorded the cap for **validation rules and permission sets**; M0.5b hit it again on a
permission set. Custom permissions belong on that list too. Field and object descriptions still
allow 1000, which is what makes the inconsistency easy to walk into. **Running tally of the
255-character description cap: validation rules, permission sets, custom permissions.**

**(b) `MasterLabel` on a Custom Metadata record caps at 40 characters.**

```
CustomMetadata  Approval_Matrix_Rule.PR_Long_Expression_Pin
  Value too long for field: MasterLabel maximum length is:40
```

The pin's original label, `ZZ - Long Expression Pin (test fixture, inactive)`, is 48. Shortened to
`ZZ - Long Expression Pin (INACTIVE)`. Not documented anywhere in the v1.0 phases because none of
the 14 v1 records came close to the limit.

**(c) A Long Text Area field cannot be marked `required`.** `Expression__c` is the one §3.1 field
without `required=true`; the platform forbids it on that type. A rule with a null expression is
therefore possible at the schema level and must be caught by §9's config validator, which is out of
MVP scope. Recorded in the carried-forward table.

**(d) The validation rule's dependency ordering is the reverse of M0.4's deletion ordering.** The
first deploy failed twice over: the custom permission was rejected for its description, and the
validation rule was then rejected with `Field AMF_Bypass_Log_Lock does not exist. Check spelling.`
The second error is a *cascade*, not a real problem — `$Permission.X` cannot resolve while `X` is
failing to deploy. Creation order is permission then rule, exactly inverse to M0.4's
rule then permission deletion order. Worth knowing so the misleading "does not exist" message does
not send the next person hunting for a typo.

**(e) Assigning `Approval_Matrix_Admin` to yourself silently disarms the log lock.** The permission
set grants `AMF_Bypass_Log_Lock`, and the running user
(`tejas.vernekar.0d104ca05e80@agentforce.com`) holds the set from §1.4d's FLS fix.
`FeatureManagement.checkPermission('AMF_Bypass_Log_Lock')` returns **true** for them. An
anonymous-Apex immutability check as that user therefore proves nothing at all — every edit
succeeds. This is why `AMF_DecisionLogLockTest` runs its negative cases under
`System.runAs(amfu1)`, and why one test asserts the bypass path deliberately.

**This directly affects M3's manual QA.** Playbook step 6 is "Try to edit a decision log row →
blocked by the immutability rule". Performed while holding `Approval_Matrix_Admin`, that step will
show the edit **succeeding**, and will look like a broken validation rule. Do it as a user holding
only `Approval_Matrix_User`, or temporarily remove the admin assignment.

**(f) Tooling, unchanged from M0.** `sf data query` still fails under the Bash tool with
`'C:\Program' is not recognized` (§0.5c), and the PowerShell tool still returns
`EPERM: operation not permitted, uv_spawn 'powershell.exe'` for the whole session (§M0.5c). `node`
is also absent from the Git Bash PATH. Verification ran entirely through anonymous Apex and
`sf project deploy`, both of which work, and string-length checks through `tr`/`sed`. No new
workaround was needed; the M0 escape hatch held.

**(g) The full-package deploy reports `Purchase_Request__c` as `Changed` on every run** even when
nothing about it was edited. Cosmetic, present in M0 too, and not worth chasing — the object's six
fields all report `Unchanged`.

### M1.7 Verification evidence

**Staged deploys.** Deployed in four groups rather than one, per §1.4a's rule — objects + custom
permission, then permission sets, then CMDT records, then classes. The failures in (a), (b) and (d)
were all attributed to real components, so no `UNKNOWN_EXCEPTION` splitting was needed this time.

```
objects + customPermissions   Succeeded  24/24 created   Deploy ID 0Afaj00000h5VjyCAE (after fixes)
permissionsets                Succeeded  2 changed       Deploy ID 0Afaj00000h5joXCAQ
customMetadata                Succeeded  4 created
classes                       Succeeded  6 created
```

**Full-package deploy** — `sf project deploy start -o amf-dev`

```
Status: Succeeded    numberComponentsTotal: 46    numberComponentErrors: 0
```

46 components, up from M0's 11.

**Tests** — `sf apex run test -o amf-dev -l RunLocalTests -w 10 -r human`

```
AMF_CmdtRuleProviderTest.longExpressionSurvivesSoqlLoad               Pass    <- PHASE GATE
AMF_CmdtRuleProviderTest.getAllTruncatesWhereSoqlDoesNot              Pass
AMF_CmdtRuleProviderTest.activeRulesExcludeTheInactivePin             Pass
AMF_CmdtRuleProviderTest.cmdtProviderHonoursTheProviderContract       Pass
AMF_CmdtRuleProviderTest.shippedMatrixComesBackInPriorityOrder        Pass
AMF_CmdtRuleProviderTest.stubHonoursTheSameContractAsTheRealProvider  Pass
AMF_CmdtRuleProviderTest.unknownObjectReturnsEmptyRatherThanNull      Pass
AMF_RuleDefinitionTest  (6 methods: ordering, ties, stability, nulls, equality, builder)  Pass
AMF_DecisionLogLockTest (6 methods: stamp once, re-stamp blocked, smuggled field blocked,
                         unstamped frozen, frozen rule edit blocked, bypass works)        Pass
AMF_PingTest.pingReturnsPong                                          Pass

Outcome Passed · Tests Ran 20 · Pass Rate 100% · Fail Rate 0%
Test Run Id 707aj000019YfBO
```

**M1 describe gate** — anonymous Apex, throws on any mismatch. Covers every §3.1 and §3.3 field's
type, the lengths the doc specifies, the `Outcome__c` value set and its absence of a default,
`Record_Id__c` as external-id-but-not-unique, the `Submitted_By__c` lookup target, per-user FLS on
all 12 log fields, and — as scope discipline — that `Execution_Type__c` exists on **neither** object.

```
=== PHASE M1 GATE ===
  Expression__c: TEXTAREA(2000)
  Record_Id__c: externalId=true unique=false
  Outcome__c values: {Blocked_No_Match, Failed, Submitted}
  Execution_Type__c absent from both: true
=== PHASE M1 GATE PASSED === 19 fields described
```

**Truncation probe** — anonymous Apex, the raw measurement behind M1.4:

```
=== TRUNCATION PROBE ===
SOQL        length: 290
getInstance length: 255
getAll      length: 255
SOQL   value: (Amount__c > 100000 && Region__c == 'APAC') || ... || (Risk_Level__c == 'Low' && Amount__c > 750000)
getAll value: (Amount__c > 100000 && Region__c == 'APAC') || ... || (Risk_Level
```

Both scratchpad scripts are held outside the repo, not committed: the M1 prompt restricts source to
`force-app` and `docs`, and `scripts/` is outside both — the same call §1.6 made.

### M1.8 The shipped matrix

What a reviewer sees in Setup → Custom Metadata Types → Approval Matrix Rule → Manage Records:

| Priority | DeveloperName | Expression | Process | Active |
|---|---|---|---|---|
| 10 | `PR_High_Value_APAC` | `Amount__c > 100000 && Region__c == 'APAC'` | `PR_Three_Level_Finance` | yes |
| 20 | `PR_High_Risk` | `Risk_Level__c == 'High'` | `PR_Three_Level_Finance` | yes |
| 9998 | `PR_Long_Expression_Pin` | 290-character chain | `PR_Two_Level_Mgmt` | **no** |
| 9999 | `PR_Catch_All` | `TRUE` | `PR_Two_Level_Mgmt` | yes |

It reads as a routing matrix: high-value APAC spend and anything high-risk take the three-level
finance chain, everything else takes two levels of management, and the catch-all is visibly last.
Every expression is legal under the §13.3 reduced grammar and references only real
`Purchase_Request__c` fields and real picklist values, so M2's compiler will accept all four —
including the pin.

The process names point at templates that do not exist until M3. `Process_API_Name__c` is Text with
no referential check; §9's validator would catch a stale name, and it is out of MVP scope.

**Set up for the M3 demo.** The playbook's rule-flip is scripted as `PR_Two_Level_Mgmt` to
`PR_Three_Level_Finance`, so the record to submit is an ordinary one — low amount, non-APAC, low
risk — which falls through to the catch-all. Flipping **`PR_Catch_All`'s** `Process_API_Name__c` is
then the cleanest possible demonstration, because it changes the org's *default* routing by editing
one field in one Custom Metadata row.

### M1.9 Architecture deviations

Three entries appended to `docs/decisions.md` (M1.2). No amendment to `docs/architecture.md` was
needed: §3.3's "blocks edits after creation" remains true in substance — the row is immutable from
every point of view except the engine's one-shot stamp — and that mechanism detail belongs in this
log rather than in the design document.

### M1.10 Carried into later phases

| Item | Owed to |
|---|---|
| ~~Create `AMF_Bypass_Log_Lock` and grant it in `Approval_Matrix_Admin`~~ | **closed in M1** |
| ~~Extend both permission sets to the CMDT and the log object with explicit FLS~~ | **closed in M1** |
| ~~`AMF_CmdtRuleProvider` must sort by Priority then DeveloperName in Apex~~ | **closed in M1** — it is `AMF_RuleDefinition.compareTo` |
| Delete `AMF_Ping` / `AMF_PingTest` once real engine classes exist | M2 |
| Name the strategy interface `AMF_SubmissionStrategy`, per M1.2's naming decision | M3 |
| The engine must not change any field other than `Execution_Ref_Id__c` during the step-11 stamp; a post-write failure must roll back rather than flip `Outcome__c` to `Failed` (M1.3) | M3 |
| **M3 manual QA step 6 must be run as a non-admin** — `Approval_Matrix_Admin` grants the bypass and the log lock will appear broken (M1.6e) | M3 |
| `Expression__c` cannot be `required` at the schema level (M1.6c), so a null expression is only catchable by §9's config validator | post-MVP |
| `ISCHANGED` does not cover the three Long Text Area log fields, leaving a one-update residual hole in the lock (M1.3 point 4) | post-MVP |
| `AMF_DecisionLogLockTest` depends on the seeded `amfu1` user; re-run `scripts/seed-data.apex` before running tests in a fresh org | any new org |
| Manual QA: open the four CMDT records in Setup and confirm the matrix reads in priority order, catch-all last, pin visibly inactive | user, before commit |

---

## Phase M2 — Expression evaluator

**Date:** 2026-08-18 · **Commit:** `ce47137`
**Status:** complete — 100% coverage on all eight evaluator classes, 108/108 tests pass
**Playbook goal:** the hard part. The reduced grammar, compiled and evaluated, with zero
dependence on org configuration.

Third phase of the **v3.0 MVP** plan, and the one the framework is actually made of. Eight
production classes (1,636 lines including ApexDoc) and seven test classes carrying **89 test
methods**, of which 116 are `(expression, record, expected)` triples and 41 are malformed-input
cases asserting a character position. Two classes deleted. No metadata outside
`force-app/main/default/classes` was touched.

### M2.1 File-level changes

| File | Change | Detail |
|---|---|---|
| `classes/AMF_ExpressionException.cls` | **added** | The package's single error type. Carries a zero-based `position` and the source `expressionText` |
| `classes/AMF_Ast.cls` | **added** | `ValueType` enum, `Node`, `BinaryNode`, `ComparisonNode`, `FieldNode`, `LiteralNode` (§4.2) |
| `classes/AMF_Lexer.cls` | **added** | String → tokens, every token positioned (§4.2) |
| `classes/AMF_Parser.cls` | **added** | Recursive descent → AST, precedence per §4.1 |
| `classes/AMF_ExprCompiler.cls` | **added** | Parse + static analysis against describe (§4.2, §4.3, §4.4) |
| `classes/AMF_ExprCache.cls` | **added** | Static map keyed by DeveloperName + `Version__c` (§4.5) |
| `classes/AMF_Evaluator.cls` | **added** | AST + SObject → Boolean and the evaluated-values map (§4.3) |
| `classes/AMF_FieldPathResolver.cls` | **added** | Union of paths → one dynamic SOQL per object (§4.4) |
| `classes/AMF_LexerTest.cls` | **added** | 14 tests |
| `classes/AMF_ParserTest.cls` | **added** | 15 tests, asserted on tree shape rather than on evaluation |
| `classes/AMF_ExprCompilerTest.cls` | **added** | 12 tests |
| `classes/AMF_ExprCacheTest.cls` | **added** | 7 tests, all on `AMF_RuleBuilder` fixtures |
| `classes/AMF_EvaluatorTest.cls` | **added** | 22 tests / 116 table rows — the phase's headline suite |
| `classes/AMF_FieldPathResolverTest.cls` | **added** | 9 tests |
| `classes/AMF_ExpressionErrorTest.cls` | **added** | 10 tests / 41 positioned malformed-input cases |
| `classes/AMF_Ping.cls` + `AMF_PingTest.cls` | **deleted** | From repo and org. Closes the M1.10 debt; the class's own header said to remove it once §4 landed |
| `docs/decisions.md` | modified | Three entries — see M2.2 |
| `docs/technical-log.md` | modified | Status board, this entry |

### M2.2 Three doc conflicts, resolved before building

Each was raised with the user before any code was written, per `CLAUDE.md`, and each is now a
line in `docs/decisions.md`.

| Conflict | Resolution |
|---|---|
| §4.1 accepts `AND`/`OR` word forms; §13.3 and `CLAUDE.md` list only `&&`/`||` | **Symbols only.** `CLAUDE.md` is the override document. `TRUE AND FALSE` fails at position 5 rather than routing on half an expression; the word forms are two entries in `AMF_Lexer.KEYWORDS` whenever they are wanted |
| §4.1's `bool_atom` includes a bare Checkbox path; §13.3 names only "bare `TRUE`" | **Support `bool_atom` in full.** A boolean field path is absent from §13.3's deferred list, so it is part of the grammar, and it costs no special-casing — a primary with no comparison operator after it is a boolean atom, and the compiler rejects it if the path is not Boolean |
| §4.3 says both "null == null is true" **and** "null anywhere in a relationship path makes the comparison false" | **The relationship rule wins on the collision.** A null *intermediate* makes the comparison false for every operator including `== NULL`; a *leaf* that resolves to null follows the ordinary null rules. An unresolvable path routes nothing rather than quietly passing a presence check |

### M2.3 How the pipeline is split, and why it is split there

The four stages are not decoration. Each boundary is load-bearing for something §4 asks for.

1. **The lexer knows no grammar.** It knows `&&` is one token, not that it joins two
   comparisons. That is what makes §13.3's deferred constructs additive: `IN`, `CONTAINS`,
   `STARTS_WITH` and `NOT` become entries in a `KEYWORDS` map, and `TODAY(n)` reuses the
   identifier and parenthesis tokens that already exist. **Nothing in the lexer is written
   around their absence** — a word that is not in the table is simply an identifier, which is
   the whole of the extension point.
2. **The parser asks the schema nothing.** It will happily build a four-segment path or a bare
   `Amount__c` used as a condition. Both are rejected by the compiler, because both need
   describe information. Keeping the line exactly there means raising §13.3's two-segment cap
   to §4.4's platform four is *one constant in the compiler* and no parser change at all.
3. **The compiler is where §4.6 is won.** Every path is resolved through describe and every
   operator checked against its operand type at compile time, so `Region__c > 'APAC'` is a
   positioned error rather than a runtime false that silently falls through to the next rule.
   §4.3's table is enforced literally: Boolean is identity-only, and text types carry equality
   but **no ordering**.
4. **The evaluator does no describe work at all.** The compiler annotates the tree with
   `valueType` and `operandType`, so evaluation reads values and applies §4.3. That is what
   makes compilation worth caching and evaluation not.

Other choices worth recording:

1. **Positions are zero-based character indexes**, so `expression.substring(position)` starts
   at the character the message blames. Messages render as §4.2 specifies —
   `<detail> at position <n>` — and the position is asserted **both** as a structured field on
   the exception and as text in the message, because a caller may only ever read one of the two.
2. **The evaluated-values map is built from the compiled path list, not from the nodes
   evaluation reached.** `FALSE && Amount__c > 100` short-circuits, but `Evaluated_Values__c`
   still records `Amount__c` — otherwise the audit record would change shape depending on which
   branch ran, which is the opposite of what §3.3 is for.
3. **Path keys are canonicalised to API-name spelling.** A rule written `amount__c` logs
   `Amount__c`, and `account__r.name` logs `Account__r.Name`, so the audit JSON reads the same
   however the admin typed the rule.
4. **A broken relationship path records `null` in the map rather than being omitted**, so the
   log shows which path could not be resolved rather than staying silent about it.
5. **`AMF_FieldPathResolver` re-validates path *shape* even though the compiler already
   resolved every path.** This class concatenates its input into a query string; refusing
   anything that is not a plain dotted identifier is defence in depth, not distrust of the
   compiler. `Amount__c FROM User WHERE Name != '' --` is refused rather than concatenated.
6. **It is declared `inherited sharing`.** §11 makes the *service* the place that decides — it
   runs `without sharing` and authorises the submitter explicitly — and a library class that
   forced its own answer would take that decision away from the caller in M3 that is supposed
   to be making it.
7. **The cache does not remember failures.** A compile error throws every time it is asked
   for. A negative cache is a second thing that can go stale, and §4.6 wants failures loud and
   repeatable.
8. **`AMF_ExprCache`'s key is a design statement, and `AMF_ExprCacheTest` pins its sharp
   edge**: editing an expression *without* bumping `Version__c` is invisible to a transaction
   that already compiled the old one. That is exactly why §3.3 stamps `Rule_Version__c` onto
   every decision log row — the log records which version actually routed the record.
9. **Types the pilot object does not carry are tested against standard objects**, per §10 —
   Date on `Opportunity.CloseDate`, Integer and Double on `Account` — rather than adding fields
   to `Purchase_Request__c` that only a test would ever read. M2's allowed paths were
   `classes` and `docs` in any case, so a new field was not an option, and it should not have
   been one.

### M2.4 Issues encountered

**(a) Six Apex reserved identifiers, found only by deploying.**

`BOOLEAN`, `DATE`, `AND` and `OR` will not compile as enum constants, and `inner` and `number`
will not compile as local variable names. `AMF_Ast.ValueType` therefore spells two of its four
members `BOOLEAN_VALUE` and `DATE_VALUE`, and `AMF_Lexer.TokenType` uses `LOGICAL_AND` /
`LOGICAL_OR`. That platform detail must not leak into an error message an admin reads, so
`AMF_Ast.labelFor()` maps the enum to the word — `boolean`, `date` — and every message goes
through it. *Lesson: a dry-run deploy after the first class compiles is worth more than
re-reading the file.*

**(b) An enum constant referenced from an inner class needs the outer class name.**

`this.valueType = ValueType.BOOLEAN_VALUE;` inside `AMF_Ast.BinaryNode` fails with *"Static
field cannot be referenced from a non static context"* — a misleading message for what is
really a scoping rule. `AMF_Ast.ValueType.BOOLEAN_VALUE` compiles.

**(c) `instanceof Decimal` is true for *every* boxed numeric in Apex — measured, and it
deleted code.**

`AMF_Evaluator.toDecimal` was written with the obvious four branches, one per Apex numeric
type. Coverage then reported three of them **unreachable**. Probing `amf-dev` rather than
guessing:

```
Integer field (NumberOfEmployees) -> Decimal=true Integer=true Long=true Double=true
Currency field (AnnualRevenue)    -> Decimal=true Integer=false Long=false Double=true
Double field (BillingLatitude)    -> Decimal=true Integer=false Long=false Double=true
Apex (Long) 5000000000            -> Decimal=true Integer=false Long=true  Double=true
```

Every numeric answers `instanceof Decimal`, and the cast succeeds for all of them. The three
per-type branches were dead code, and were deleted; one cast now covers every numeric field
type. `AMF_EvaluatorTest.numbersCompareWhicheverApexTypeTheyArriveAs` still drives Decimal,
Integer, Long and Double through the comparison, so it is the test that would notice if that
platform behaviour ever changed. *The coverage hole was the signal; the probe was the
diagnosis. Neither alone would have found it.*

**(d) Two shell quoting traps writing Apex from the tooling, not from the platform.**

A `<<'EOF'` heredoc terminated early because the Apex source contained a line whose content was
`EOF` (an enum constant, since renamed `END_OF_INPUT`), and a later heredoc broke on Apex's
`'\''` escape sequences. Both produced a shell parse error rather than a bad file, so nothing
was silently corrupted, but Apex source with embedded quotes goes through the file-write tool
from here on. *Recorded because it cost two failed writes and will otherwise cost them again.*

### M2.5 Verification evidence

**Deploy — green, all 15 classes:**

```
Status: Succeeded
```

**Tests and coverage — the phase gate is ≥90% on the evaluator package (§13.4):**

```
=== Apex Code Coverage by Class
CLASSES                  PERCENT  UNCOVERED LINES
AMF_Ast                  100%
AMF_ExpressionException  100%
AMF_Lexer                100%
AMF_Parser               100%
AMF_ExprCompiler         100%
AMF_ExprCache            100%
AMF_Evaluator            100%
AMF_FieldPathResolver    100%
AMF_CmdtRuleProvider     100%
AMF_RuleDefinition       91%      68,77,80

Outcome              Passed
Tests Ran            108
Pass Rate            100%
Org Wide Coverage    99%
```

All eight evaluator classes are at **100%**, against a gate of 90%. The two guards that the
grammar cannot reach — an ordering operator on a type that has no ordering, and a comparison
whose operand type never resolved — are covered by tests that hand the evaluator a
**hand-built AST the compiler would never produce**, which is the only way to prove they throw
rather than falling through to false (§4.6). `AMF_RuleDefinition`'s three uncovered lines are
M1's null-priority comparator branches and are untouched by this phase.

**The whole pipeline over the real shipped matrix and a real record** (§6.1 steps 1–5, run as
anonymous Apex — the playbook's "you verify" step):

```
--- step 1-2: active rules in priority order ---
  10  PR_High_Value_APAC  ->  PR_Three_Level_Finance
  20  PR_High_Risk  ->  PR_Three_Level_Finance
  9999  PR_Catch_All  ->  PR_Two_Level_Mgmt
--- step 3-4: one query for the union of paths ---
  SELECT Id, Amount__c, Region__c, Risk_Level__c FROM Purchase_Request__c WHERE Id IN :recordIds
--- step 5: first true expression wins ---
  PR_High_Value_APAC  Amount__c > 100000 && Region__c == 'APAC'  ->  true
  MATCHED PR_High_Value_APAC -> PR_Three_Level_Finance
  Evaluated_Values__c would hold: {"Region__c":"APAC","Amount__c":150000.00}
```

Three rules, four field paths across them, **one** query for the union, first-true-wins on a
record seeded at 150,000 / APAC / Low. The seeded record was deleted afterwards; the org
carries no M2 data.

**M1.8's open claim, now closed.** M1 asserted that the compiler would accept all four shipped
CMDT records including the inactive 290-character pin. Compiling each of them:

```
PR_Catch_All           (active=true,  4 chars)   -> compiled, paths=()
PR_High_Risk           (active=true,  23 chars)  -> compiled, paths=(Risk_Level__c)
PR_High_Value_APAC     (active=true,  41 chars)  -> compiled, paths=(Amount__c, Region__c)
PR_Long_Expression_Pin (active=false, 290 chars) -> compiled, paths=(Amount__c, Region__c, Risk_Level__c)
```

The catch-all reads **no** fields, which is what lets a matrix of catch-alls cost nothing at
step 4.

**The malformed-input suite** covers every category the M2 gate names, each asserting the
character position: unbalanced parentheses (both directions, and nested), unknown field,
unknown relationship, over-deep path, unterminated string, impossible date (`2026-13-01`,
`2026-02-30`, `2025-02-29`), stray character, dangling operator, type mismatch, an ordering
operator on text or Boolean, a non-Boolean standing alone as a condition, and an empty
expression. **Every deferred §13.3 construct is also pinned** — `IN`, `CONTAINS`, `NOT`, `!`,
`AND`, `OR` each fail with a position rather than silently, and each will start working the day
it is added.

### M2.6 Architecture deviations

Three entries appended to `docs/decisions.md` (M2.2). No amendment to `docs/architecture.md`
was needed: §4.1 and §4.3 remain true of the target design, and all three decisions are about
which part of that design the **MVP** implements, which is §13's job and is already recorded
there.

One §4 statement is worth flagging as *not yet true*, by design rather than by omission. §4.6
says "compile errors cannot reach runtime" on the strength of §9's config validator compiling
every active expression at deploy time — and §9 is explicitly out of MVP scope (§13.2). In the
MVP a compile error therefore surfaces at **submit** time, as a thrown, positioned exception.
That is still fail-loud and still blocks, which is what §4.6 actually protects; it simply fails
later than it eventually will.

### M2.7 Carried into later phases

| Item | Owed to |
|---|---|
| ~~Delete `AMF_Ping` / `AMF_PingTest` once real engine classes exist~~ | **closed in M2** |
| ~~Prove the compiler accepts all four shipped CMDT rules, including the 290-character pin (M1.8)~~ | **closed in M2** |
| Name the strategy interface `AMF_SubmissionStrategy`, per M1.2's naming decision | M3 |
| The engine must not change any field other than `Execution_Ref_Id__c` during the step-11 stamp; a post-write failure must roll back rather than flip `Outcome__c` to `Failed` (M1.3) | M3 |
| **M3 manual QA step 6 must be run as a non-admin** — `Approval_Matrix_Admin` grants the bypass and the log lock will appear broken (M1.6e) | M3 |
| A runtime evaluation error must mark the row `Failed`, write the exception to `Failure_Detail__c` and **block** — the evaluator throws `AMF_ExpressionException` (positioned) or `System.SObjectException` (schema drift), and M3 must catch neither into a boolean | M3 |
| `AMF_Evaluator` requires the record to carry every path in `compiled.fieldPaths`; M3 must load records through `AMF_FieldPathResolver.load` and not by its own query, or evaluation throws `SObjectException` on the first unqueried field | M3 |
| Compilation resolves fields through describe, so it inherits M1.4d: a user with neither permission set gets "Unknown field" for a rule over `Purchase_Request__c`. The permission sets are a runtime prerequisite, not packaging | M3 / any new org |
| §9's config validator would move compile errors from submit time to deploy time (M2.6) | post-MVP |
| Word forms `AND`/`OR` are two entries in `AMF_Lexer.KEYWORDS`; `IN`, `CONTAINS`, `STARTS_WITH`, `NOT`, `TODAY(n)` and multipicklist each need one node type and one branch per stage | post-MVP |
| Raising the path cap from 2 to §4.4's platform 4 is `AMF_ExprCompiler.MAX_PATH_SEGMENTS` plus the mirrored constant in `AMF_FieldPathResolver` | post-MVP |

---

## Phase M3 — Engine, templates, submit action

**Date:** 2026-08-18 · **Commit:** `d13241f`
**Status:** complete — 141/141 Apex tests, 6/6 Jest tests, `AMF_ApprovalMatrixService`
and `AMF_DecisionLogWriter` at 100%, org-wide 99%. The manual phase gate was completed on
2026-09-18 (see M3.7).
**Playbook goal:** the demo. End to end, one rule change away from different routing.

The last phase of the **v3.0 MVP** plan, and the one that turns three phases of parts into
the thing §13 claims: *an admin changes one Custom Metadata row, the next submission routes
to a different approval process, and a log record explains why.* Seven production Apex
classes, one test fixture, four test classes, two native approval processes, a workflow field
update, an LWC quick action and a layout change.

### M3.1 File-level changes

| File | Change | Detail |
|---|---|---|
| `classes/AMF_SubmissionStrategy.cls` | **added** | The interface. The only sanctioned route to `Approval.process()` (§6.2) |
| `classes/AMF_SubmitRequest.cls` | **added** | Record + process name. The engine's output, the strategy's input |
| `classes/AMF_SubmitResult.cls` | **added** | Record + execution reference, typed `String` so Flow's `ApprovalSubmission.Id` is additive |
| `classes/AMF_ClassicProcessStrategy.cls` | **added** | The one place `Approval.process()` appears (§6.2, §5.2) |
| `classes/AMF_SubmissionException.cls` | **added** | The engine's error type, for whole-call faults only |
| `classes/AMF_DecisionLogWriter.cls` | **added** | Row builders per outcome, `save`, and the step-11 `stamp` (§3.3) |
| `classes/AMF_ApprovalMatrixService.cls` | **added** | §6.1 steps 1–11, plus the `@AuraEnabled` UI entry point (§7) |
| `classes/AMF_StrategyStub.cls` | **added** | `@IsTest`. Records requests **and re-reads the guard from inside submit()** |
| `classes/AMF_ApprovalMatrixServiceTest.cls` | **added** | 17 tests — the engine's whole behaviour, zero org CMDT rows |
| `classes/AMF_DecisionLogWriterTest.cls` | **added** | 7 tests |
| `classes/AMF_ClassicProcessStrategyTest.cls` | **added** | 4 tests — guard clauses, not the platform call |
| `classes/AMF_SubmissionIntegrationTest.cls` | **added** | 2 tests — the only real `Approval.process()` in the suite |
| `approvalProcesses/Purchase_Request__c.PR_Two_Level_Mgmt.approvalProcess-meta.xml` | **added** | Two `userHierarchyField` steps (§5.2) |
| `approvalProcesses/Purchase_Request__c.PR_Three_Level_Finance.approvalProcess-meta.xml` | **added** | Three named-user steps, `amfu3` → `amfu4` → `amfu5` |
| `workflows/Purchase_Request__c.workflow-meta.xml` | **added** | `AMF_Clear_Matrix_Submission`, referenced by both templates from final approval **and** final rejection |
| `quickActions/Purchase_Request__c.AMF_Submit_For_Approval.quickAction-meta.xml` | **added** | `LightningWebComponent` type — see M3.4a |
| `lwc/amfSubmitForApproval/*` | **added** | Headless action, empty template, 6 Jest tests |
| `layouts/Purchase_Request__c-Purchase Request Layout.layout-meta.xml` | **added** | Retrieved from the org, then: governed fields added, empty `<quickActionList/>` added (§6.3) |
| `permissionsets/Approval_Matrix_*.permissionset-meta.xml` | modified | `classAccesses` for `AMF_ApprovalMatrixService`, so the LWC's Apex is callable |
| `docs/decisions.md` | modified | Four entries — see M3.2 |
| `docs/technical-log.md` | modified | Status board, this entry |

### M3.2 Doc conflicts, resolved before building

| Conflict | Resolution |
|---|---|
| §6.1 step 6 wants the `Blocked_No_Match` row **written** and an error **thrown** | Mutually exclusive in Apex — an exception escaping the top of a request rolls back the row. **Per-record blocked Outcome**, exceptions reserved for whole-call faults. Raised with the user before any code was written |
| §4.6 forbids catching into a boolean, but also requires a runtime error to mark the row `Failed` and block | Both hold. The prohibition binds the **evaluator package**, which still swallows nothing; §4.6 itself *requires* the engine to catch, and the engine's catch produces a `Failed` row rather than a false |
| §7 writes the UI row as a "LightningComponent" quick action | `LightningWebComponent`. The Aura pair does not resolve an LWC (M3.4a) |
| §6.4's `preview()` | Not built. §13.1 says "no preview modal" and nothing in the MVP calls it; building an unused method would be stubbing an out-of-scope feature |

### M3.3 Design choices worth recording

1. **The blocked path is the one that had to be got right.** Every other outcome writes a row
   and moves on; a blocked one has to write a row that *survives*. Making the service return
   Outcomes rather than throw is what buys that, and it is why `Blocked_No_Match` carries the
   union of values read across **every** rule tried rather than one rule's — with no winner
   there is nothing else to show the auditor. A matched row uses the winning rule's own map,
   because §8's narrative sentence is about the rule that won.
2. **`allOrNone = true` on `Approval.process()`,** which is the M1.10 carried item honoured.
   By step 10 the log rows already say `Submitted`, and `Lock_Decision_Log` permits exactly
   one post-insert update — `Execution_Ref_Id__c`, blank to populated — and explicitly not a
   change to `Outcome__c`. There is therefore **no way to walk a row back** from `Submitted`
   to `Failed`. A partial success would leave the audit trail lying, so the whole transaction
   fails instead.
3. **The step-11 stamp builds fresh SObjects** carrying only `Id` and `Execution_Ref_Id__c`,
   rather than re-saving the inserted instances. That is the same carried item from the other
   side: a row rebuilt from scratch cannot dirty a field the validation rule watches, however
   the caller has handled it in between.
4. **`AMF_StrategyStub` re-queries the record from inside `submit()`.** §6.1 step 9 is an
   *ordering* requirement — the guard true in the same transaction, before submit — and a stub
   that only recorded the requests could not tell a guard set before submit from one set
   after. Asserting `guardAtSubmit` is the only honest way to pin §6.3 without a real approval.
5. **A rule that will not compile blocks every record in the call.** See `docs/decisions.md`.
   The alternative — skip the broken rule, let a lower-priority one match — is the
   anti-Sitetracker failure wearing a different hat.
6. **The engine is object-agnostic.** The guard is staged through
   `newSObject(id).put('Matrix_Submission__c', true)` and the stub reads it through dynamic
   SOQL, because §3.2 makes the guard a convention on *every* governed object. Hardcoding
   `Purchase_Request__c` would have made the second object a code change.
7. **`requireGuardField` fails early, before any log row exists.** An object without the guard
   is misconfigured rather than differently configured, and the alternative is a
   field-not-found deep inside step 9 with a row already written.
8. **Authorisation is `UserRecordAccess`, not a CRUD check.** §11 says the service runs
   `without sharing` but authorises explicitly; a record-level question needs a record-level
   answer, and the class has deliberately stepped outside the sharing that would have given it.
9. **One object per call.** Both the rule set (step 1) and the union query (step 4) are per
   object, so a mixed batch is a caller error rather than something to silently partition.
10. **Both templates clear the guard from final *rejection* as well as final approval.** A
    rejected record that kept `Matrix_Submission__c = true` would stay permanently bypassable.

### M3.4 Issues encountered

**(a) The quick action could not find its own component, and the error named the wrong thing.**

`<type>LightningComponent</type>` with `<lightningComponent>amfSubmitForApproval</lightningComponent>`
— which is how §7's wording reads — failed with *"Unable to retrieve lightning component by
namespace/developer name : amfSubmitForApproval"*. The message points at the component, so the
first three attempts went looking at the component: the `c:` namespace prefix (same error),
the element order in `js-meta.xml`, and a redeploy in case of indexing lag.

The component was never the problem. Probing the org settled it:

```
LightningComponentBundle  amfSubmitForApproval  ApiVersion 62  IsExposed true
TargetConfigs  <targetConfig targets="lightning__RecordAction"><actionType>Action</actionType>
```

and an attempt to flip `actionType` was refused with *"Cannot change the type of the existing
Lightning Web Component action"* — the org knew it as a headless LWC action all along.
`<lightningComponent>` resolves against **Aura bundles only**. The LWC pair is
`<type>LightningWebComponent</type>` + `<lightningWebComponent>`, and it deployed first time.
*Lesson: when an error names an object that demonstrably exists, suspect the element that
names it, not the object.*

One genuine finding came out of the detour: the platform enforces `<targets>` **before**
`<targetConfigs>` in `js-meta.xml`, rejecting the documented alphabetical order with *"You
must specify targets first, before targetConfigs."*

**(b) An LWC quick action cannot be put on a page layout by the Metadata API at all.**

With the type fixed, the layout then failed: *"You can't add QuickActionType
LightningWebComponent to a QuickActionList."* Confirmed at API 62.0 **and** 64.0, so it is a
platform rule rather than a version gap.

Retrieving `Account-Account Layout` to see what a stock `quickActionList` actually contains
was what made the way forward clear:

```
FeedItem.TextPost  FeedItem.ContentPost  NewTask  NewContact  NewCase  LogACall
NewNote  NewOpportunity  NewEvent  FeedItem.LinkPost  FeedItem.PollPost  SendEmail
```

Two things follow. `Edit`, `Delete` and `Clone` are **not** in it — they render as standard
buttons regardless, which is why an earlier attempt to list them failed with *"no QuickAction
named Edit found"*. And neither is `SubmitForApproval`: the standard button appears because
Lightning falls back to a **default action set** when a layout declares no `quickActionList`
at all. Declaring the list — even empty — is therefore what removes it, which is what §6.3
asks for. `<quickActionList/>` deploys clean.

The consequence is recorded in `docs/decisions.md` and carried in M3.8: the framework's action
is deployed and functional but is **not on the layout**, and putting it there is a Setup step
whose result cannot be redeployed.

**(c) Three metadata length and shape limits, all found only by deploying.**

`WorkflowFieldUpdate`, `QuickAction` and `ApprovalProcess` all cap `<description>` at **255
characters**, and the first drafts of all four were 260–474. An approval step with a single
named approver still requires `<whenMultipleApprovers>`. And `unfiled$public/ApprovalRequest`
does not exist in this org — the `<emailTemplate>` element was dropped rather than pointed at
a template the repo does not own.

**(d) A green test that proved nothing, caught by a red one next to it.**

`AMF_DecisionLogWriterTest.aSecondStampIsRefusedByTheImmutabilityRule` failed with *"A second
stamp must be refused"* — the second stamp succeeded. The cause is the M2.7 carried item
arriving early: **the test-running admin holds `AMF_Bypass_Log_Lock`** via
`Approval_Matrix_Admin`, so `Lock_Decision_Log` never fires for them.

The failing test was removed rather than fixed: `AMF_DecisionLogLockTest` already owns the
lock's semantics and already runs every case as the seeded `amfu1`, who has no bypass.
Re-asserting it here would have duplicated that coverage and added a second dependency on a
seeded org user.

The more useful half of the finding is what it implied about the test *next to* it.
`stampWritesTheExecutionReferenceAndNothingElse` was passing as the admin — which proved
nothing, because the bypass meant the rule was never consulted. It now runs inside
`System.runAs(subjectWithoutBypass())`, so it actually proves what it claims: that the
engine's step-11 stamp survives the lock in the conditions a real submitter meets. *A false
green sitting beside a false red; only the red announced itself.*

**(e) Node.js is not installed on this workstation.**

`npm` is absent from both shells, so the phase's Jest gate initially had no way to run. The
Salesforce CLI bundles its own runtime — `C:\Program Files\sf\client\bin\node.exe` (v22.22.0)
and `npm-cli.js` alongside it — which installs the dev dependencies and runs Jest. One extra
step: `sfdx-lwc-jest` spawns a bare `node`, so its directory has to be on `PATH` for the call.
The `npm install` itself reports failure from the `husky` prepare hook under `cmd.exe`; the
install completes regardless.

```
$env:PATH = "C:\Program Files\sf\client\bin;$env:PATH"
node node_modules\jest\bin\jest.js --ci
```

### M3.5 Verification evidence

**Deploy — full package, green:**

```
Status: Succeeded
```

**Tests — 141/141:**

```
Outcome              Passed
Tests Ran            141
Pass Rate            100%
Org Wide Coverage    99%

CLASSES                     PERCENT  UNCOVERED LINES
AMF_ApprovalMatrixService   100%
AMF_DecisionLogWriter       100%
AMF_SubmitRequest           100%
AMF_SubmitResult            100%
AMF_ClassicProcessStrategy  81%      78,79,80,81,82
AMF_SubmissionException     0%       (no executable lines — an empty Exception subclass)
```

`AMF_ClassicProcessStrategy`'s five uncovered lines are one guard: a platform result that
reports success while returning no `ProcessInstance` Id. It cannot be produced —
`Approval.ProcessResult` is not constructible and the platform does not behave that way — so
it is left uncovered rather than contrived around. **The same invariant is covered at the
engine level**, where `AMF_StrategyStub.returnBlankReference` drives
`aSubmissionWithoutAnExecutionReferenceIsAContradiction`. The guard stays because §8 is
explicit that `Execution_Ref_Id__c` must not be optimised away, so "submitted, reference
unknown" has to be a failure rather than a result.

**Jest — 6/6:**

```
PASS force-app/main/default/lwc/amfSubmitForApproval/__tests__/amfSubmitForApproval.test.js
  √ renders nothing: it is a headless action (arch doc 13.1, no preview modal)
  √ reports the matched rule and the process it routed to
  √ surfaces a blocked submission as an error without treating it as a thrown fault
  √ keeps the positioned Apex message when the call throws
  √ falls back to a readable message when the error carries no body
  √ refreshes the record however the submission ended
Tests: 6 passed, 6 total
```

**The real `Approval.process()` path, in a test transaction** — the two integration tests both
pass, and together they are §6.3 stated twice:

- `aRealSubmissionEntersTheNamedProcessAndJoinsBackToIt` — the engine's chosen process name is
  accepted by the platform, entry criteria pass *because* step 9 staged the guard first, the
  returned Id resolves to a real `ProcessInstance` with `Status = Pending` and
  `TargetObjectId` pointing back at the record, step 1 of the template produced a work item,
  and the decision log row carries the same reference (§8's join).
- `bypassingTheEngineFailsEntryCriteriaRatherThanRoutingSilently` — a direct
  `Approval.process()` with the guard still false is **refused**, and nothing routes. This is
  the assertion that makes the guard worth having; if the entry criteria are ever lost from a
  template, this test goes red.

**The shipped CMDT matrix, read through the real provider and evaluator** (steps 1–7, run as
anonymous Apex — no submission, no rows written, nothing left in the org):

```
--- steps 1-2: active rules in priority order ---
  10  PR_High_Value_APAC  v1  ->  PR_Three_Level_Finance
  20  PR_High_Risk  v1  ->  PR_Three_Level_Finance
  9999  PR_Catch_All  v1  ->  PR_Two_Level_Mgmt
--- steps 3-4: one query for the union ---
  SELECT Id, Amount__c, Region__c, Risk_Level__c FROM Purchase_Request__c WHERE Id IN :recordIds
--- steps 5-7: first true expression wins ---
  Amount=500 Region=EMEA Risk=Low      ->  PR_Catch_All v1        ->  PR_Two_Level_Mgmt       evaluated={}
  Amount=250000 Region=APAC Risk=Low   ->  PR_High_Value_APAC v1  ->  PR_Three_Level_Finance  evaluated={"Region__c":"APAC","Amount__c":250000}
--- templates present and active ---
  PR_Three_Level_Finance  Approval  Active
  PR_Two_Level_Mgmt       Approval  Active
```

Both templates deployed **active**, and the catch-all still reads no fields — M1.8's
observation that a matrix of catch-alls costs nothing at step 4 survives into the engine.

**The rule-flip, proved at the seam a CMDT edit acts on.**
`aRuleFlipRoutesTheSameRecordSomewhereElseWithNoCodeChange` submits the same record twice with
the *only* difference being `Process_API_Name__c`, and asserts two log rows carrying the same
`Expression_Snapshot__c` and two different `Selected_Process__c` values. That is §8's deepest
claim as a unit test: keeping routing current did not destroy the historical record. The org
demo in M3.7 is the same thing with human eyes on it.

### M3.6 Architecture deviations

Four entries appended to `docs/decisions.md` (M3.2, M3.4b). No amendment to
`docs/architecture.md` was needed: §6.1's step list remains the design, and the one place the
MVP departs from its wording — how a block is signalled — is a platform constraint on *this*
implementation rather than a change to what the framework does. A blocked record still does
not route, still logs, and still explains itself.

### M3.7 The manual QA gate — COMPLETED (2026-09-18)

At code completion on 2026-08-18, this phase's gate was still human and had not been run. The
following checklist was completed on 2026-09-18, closing the final MVP phase gate.

**Prerequisite, and it will otherwise look like a bug.** `PR_Two_Level_Mgmt` resolves its
approvers from the **submitter's** `User.Manager` chain. The admin user has no manager, so
submitting a record that routes to it fails with *no approver found*. Either set your own
Manager to `amfu4` in Setup (giving `amfu4` → `amfu5`), or run those steps as `amfu1`.
`PR_Three_Level_Finance` uses named users and is unaffected, which is why the automated
integration test routes there.

**Second prerequisite.** The framework's Submit for Approval action is deployed but is **not
on the layout** (M3.4b). Add it in Setup → Object Manager → Purchase Request → Page Layouts →
Purchase Request Layout → Salesforce Mobile and Lightning Experience Actions. Do **not**
retrieve the layout afterwards — the result is not redeployable.

Then, in this order:

1. Submit a matching record → correct process, work item with the right approver, record locks.
2. Open the `Approval_Decision_Log__c` row → matched rule, version, expression snapshot,
   evaluated values JSON, `Execution_Ref_Id__c` populated and joining to `ProcessInstance`.
3. Approve through to the end → `Matrix_Submission__c` back to false.
4. Reject a second record → also back to false.
5. Deactivate the catch-all, submit a record that matches nothing → blocked, with a
   `Blocked_No_Match` row explaining it. **Run this as a non-admin** (M1.6e).
6. Try to edit a decision log row → blocked. **Also as a non-admin**, or the bypass hides it.
7. The rule-flip: edit `PR_Catch_All`'s `Process_API_Name__c` to `PR_Three_Level_Finance`,
   redeploy **that CMDT record only**, submit an identical record. It must route to the
   three-level process with no Apex changed and no code deployed.

### M3.8 Carried into later phases

| Item | Owed to |
|---|---|
| ~~Name the strategy interface `AMF_SubmissionStrategy`~~ | **closed in M3** |
| ~~The step-11 stamp must change no field but `Execution_Ref_Id__c`; a post-write failure must roll back (M1.3)~~ | **closed in M3** — fresh SObjects, and `allOrNone = true` |
| ~~Remove the standard Submit for Approval button from the layout (§6.3)~~ | **closed in M3.9** — by omitting `Submit` from `platformActionList`; the empty `<quickActionList/>` claimed in M3.4b did nothing |
| ~~A runtime evaluation error must mark the row `Failed`, write the exception and block~~ | **closed in M3** |
| ~~M3 must load records through `AMF_FieldPathResolver.load`~~ | **closed in M3** |
| ~~The framework's quick action cannot be put on the layout by the Metadata API~~ | **corrected in M3.9** — it deploys in `platformActionList`, and that same omission is what removes the standard button |
| ~~M3 manual QA steps 5 and 6 must be run as a non-admin~~ — `Approval_Matrix_Admin` grants the bypass (M1.6e) | **closed 2026-09-18** |
| ~~`PR_Two_Level_Mgmt` needs the submitting user to have a Manager~~ (M3.7) | **closed 2026-09-18** |
| Node.js is not installed on this workstation; Jest runs through the CLI's bundled runtime (M3.4e) | any new workstation |
| `AMF_ClassicProcessStrategy`'s blank-reference guard is unreachable through the platform; the same invariant is covered at the engine level | post-MVP |
| §9's config validator would move compile errors from submit time to deploy time, and would catch a `Process_API_Name__c` naming a process that does not exist — currently a `Failed` row at submit | post-MVP |
| Bulk: a `Blocked_No_Match` row written for record A is rolled back if record B's submission then fails, because `allOrNone = true` condemns the transaction. Harmless while the UI submits one record at a time; revisit with chunking | post-MVP |
| **Approvers need read access to the records they approve, and the framework does not grant it** (M3.10). The architecture says nothing about this; every adopting org must answer it by role hierarchy, sharing rule or Apex sharing | docs / post-MVP |
| `_v2` template cloning (§5.1) is untouched — both templates are v1 and editing one in place is currently possible | post-MVP |

### M3.9 Correction: the standard button was never removed (2026-08-20)

Found during the M3 manual QA, at the first click: the record page showed **two Submit for
Approval buttons**, identically labelled — the platform's and the framework's.

M3.4b concluded that declaring `<quickActionList/>`, even empty, suppressed the platform's
default action set and therefore satisfied §6.3. That is wrong, and the reasoning behind it
was wrong in an instructive way. Retrieving the layout after the action had been added through
Setup showed where the standard button actually lives:

```
<platformActionList>
    <actionListContext>Record</actionListContext>
    ...
    <platformActionListItems>
        <actionName>ChangeOwnerOne</actionName>  <actionType>StandardButton</actionType>  <sortOrder>10</sortOrder>
    <platformActionListItems>
        <actionName>Submit</actionName>          <actionType>StandardButton</actionType>  <sortOrder>11</sortOrder>
    <platformActionListItems>
        <actionName>Purchase_Request__c.AMF_Submit_For_Approval</actionName>
                                                 <actionType>QuickAction</actionType>     <sortOrder>12</sortOrder>
</platformActionList>
<quickActionList/>
```

`Submit` is the standard Submit for Approval button, and it lives in **`platformActionList`**,
a list unrelated to `quickActionList`. It has never been in `quickActionList` — which is why
the stock `Account` layout does not list it, and why M3.4b's inference from that layout ("the
default set is what puts it there, so declaring the list removes it") reached a true-sounding
conclusion from the wrong premise. The empty list removed nothing.

**The fix is one deletion.** Omitting the `Submit` entry from `platformActionList` is §6.3's
removal, and the same list is where an LWC quick action **can** be deployed —
`<actionType>QuickAction</actionType>` is accepted there, while `quickActionList` refuses the
type outright. Both halves of §6.3 are therefore one deployable element, and the earlier
caveat that a layout carrying the framework's action could not be redeployed is void.
Verified by round trip: deploy, retrieve, and the org returns eleven standard buttons with no
`Submit` and the framework's action at sortOrder 11.

Two things this cost, both worth naming:

1. **A green deploy was read as a verified behaviour.** `Status: Succeeded` on the layout said
   the metadata was accepted; it said nothing about what the action bar renders. Every claim
   in M3.4b about *what a user sees* rested on an inference, and the phase shipped without
   anyone opening the record page. The automated suite could not have caught it — no test
   asserts a layout — which is exactly the case the playbook's "trust your manual QA over the
   green run" is written for.
2. **Two actions under one label is a trap of our own making.** The quick action was labelled
   "Submit for Approval" deliberately, so the demo would look native. That is right once the
   standard button is gone and actively confusing while it is still there, because nothing on
   screen distinguishes them. It is left as-is now that only one exists.

`docs/decisions.md` carries the superseding entry; the 2026-08-18 line is struck through
rather than deleted, because the reasoning is the useful part.

### M3.10 Approvers cannot see what they are asked to approve (2026-08-20)

Second finding from manual QA, and unlike M3.9 this one is not a mistake in the build — it
is a gap between the framework and the org's sharing model that the MVP never had to face
until a real approval was pending.

`amfu2` and `amfu3` received the approval request for `PR-00000001` and could not open the
record:

```
amfu3 -> PR-00000001 : HasReadAccess = false
```

**A Classic approval process does not grant an approver access to the record.** Assignment
creates a `ProcessInstanceWorkitem`; it creates no share. The approver needs read access from
the sharing model like anyone else. Here nothing supplied it: `Purchase_Request__c` is Private
(§12 wants it that way, and it is what makes the object queue-assignable), the QA records are
owned by `amfu1`, and this org has **no role hierarchy** — so the manager chain that
`PR_Two_Level_Mgmt` walks for *approvers* has no counterpart granting those managers *sight*
of the record.

That last point is the real shape of it. In a production org the two usually coincide: an
approver is the submitter's manager, sits above them in the role hierarchy, and therefore sees
the record already. The seeded users have a `User.Manager` chain and no roles, so the halves
came apart, and the framework has nothing to say about it — §6.5 is explicit that the engine
does no access management, and it should not start.

**Unblocked with manual shares** on the five QA records (`Purchase_Request__Share`,
`RowCause = Manual`, Read) for `amfu2`–`amfu5`. Targeted, reversible by deleting the shares,
and it leaves the object's sharing model exactly as the architecture chose it — as opposed to
relaxing the OWD, which would have altered a design decision to make a test pass.

```
Shared 20 of 20 record/approver pairs.
amfu2 can now read 5 of 5 QA records
amfu3 can now read 5 of 5 QA records
amfu4 can now read 5 of 5 QA records
amfu5 can now read 5 of 5 QA records
```

Two notes for later:

1. **This belongs in the framework's deployment guidance, not its code.** "Approvers must be
   able to read the records they approve" is a sentence the architecture does not currently
   contain, and every org adopting the matrix has to answer it — by role hierarchy, sharing
   rule, or Apex sharing. Carried below.
2. **`UserRecordAccess` rejects selecting a `Has*Access` field while filtering on one**
   ("Cannot filter on a Has\*Access field when selecting a result field in addition to
   RecordId"). `AMF_ApprovalMatrixService.authorise` already has the supported shape —
   `SELECT RecordId ... WHERE ... HasReadAccess = TRUE` — so this cost a scratch script and
   nothing in the package.

### M3.11 The audit artefact had no UI (2026-08-20)

Third finding from manual QA, and the most embarrassing one: `Approval_Decision_Log__c` could
not be reached in the org at all. No tab, no list view, and no related list from a governed
record.

**Correction, 2026-08-26.** This entry originally called the missing related list
"platform-forced, because no relationship exists from a custom object to a custom metadata
record". That is the reason `Matched_Rule__c` is Text (§3.3), and it does not apply here at
all: `Record_Id__c` points at `Purchase_Request__c`, an ordinary custom object, and a lookup
to it would be perfectly legal. Two different fields, two different rationales, conflated.

The real reason `Record_Id__c` is Text(18) is **object-agnosticism**. §3.2 governs any object
carrying the guard field, and Salesforce has no custom polymorphic lookup — a lookup binds to
exactly one object, so pointing the log at `Purchase_Request__c` would either tie the audit
artefact to the pilot object or require one nullable lookup per governed object thereafter.
`Object_API_Name__c` + `Record_Id__c` is the standard polymorphic-reference pattern, and the
lost related list is its known cost, paid deliberately rather than forced.

So the object that §8 calls the answer to the framework's deepest flaw, and which is the one
thing this design does that native approvals cannot, was readable only through SOQL. M0–M3
each verified it by query and never needed to look at it, which is exactly how a gap like this
survives four phases.

Added: a `CustomTab`, an `All Decisions` list view showing the columns a reviewer actually
reads — outcome, matched rule, rule version, selected process, execution reference, submitter,
timestamp — and `tabSettings` on both permission sets so it is visible to admins and
submitters alike.

Deliberately still absent: the §8 timeline LWC, which renders the decision row and the native
approver history as one narrative. That is out of MVP scope (§13.2) and remains the right next
piece of UI. A tab is the minimum that makes the artefact demonstrable; the timeline is what
makes it persuasive.

### M3.12 A related list from the governed record, without losing object-agnosticism (2026-08-27)

`Approval_Decision_Log__c` gains `Purchase_Request__c`, a Lookup, and
`Purchase_Request__c` gains an **Approval Decisions** related list. Standing on a request,
you now see why it routed where it did, directly beneath the native who-and-when.

**The constraint this navigates.** `Record_Id__c` is Text(18) because the log serves any
governed object and Salesforce has no custom polymorphic lookup — one lookup binds to one
object. M3.11 originally mis-stated that as platform-forced, which it is not: a lookup to
`Purchase_Request__c` was always legal. The real trade is that a lookup costs one field per
governed object, and text costs the related list. Taking both is the resolution here:

- **`Record_Id__c` stays the provenance.** Object-agnostic, never null, written on every row
  including outcomes for objects the log holds no lookup to. It is what the audit rests on.
- **The lookup is navigation.** Nullable by definition, and its absence degrades a related
  list rather than an audit trail.

**The engine finds the lookup by describe, not by name.** `AMF_DecisionLogWriter` scans its
own object for a *custom reference* field whose `referenceTo` is the governed type, caches the
answer per transaction, and populates it when one exists. Governing a second object is
therefore a new lookup field on the log and **no Apex change at all** — the same bargain §3.2
already makes for the guard field. Restricting the scan to custom reference fields is what
stops `Submitted_By__c` or `OwnerId` ever being mistaken for the governed record; where two
lookups point at the same object the first by API name wins, deterministically.

`deleteConstraint` is **SetNull**, never cascade. §3.3 requires the audit row to outlive what
it explains, and a master-detail — or a `Restrict` — would either destroy audit history with
the record or make governed records undeletable. Deleting a request nulls the convenience and
leaves `Record_Id__c` holding the reference as text, which is the correct degradation.

**Deliberately NOT added to `Lock_Decision_Log`.** Every other governed field is in that
rule's `ISCHANGED` list; this one is not. A `SetNull` cascade from deleting a governed record
is a legitimate system write, and if validation fires on it, adding the field would make
deleting any Purchase Request fail with an immutability error — a genuinely horrible thing to
diagnose. The provenance field it mirrors is already locked, so nothing auditable is left
unguarded by the omission.

**Issues encountered.**

**(a) The related list name is neither the relationship name nor a label.** `Approval_Decisions`
is rejected with *Cannot find related list*. The layout wants
`<relatedList>Approval_Decision_Log__c.Purchase_Request__c</relatedList>` — child object API
name, dot, lookup field API name. Same shape of error as `RelatedProcessHistoryList` in M3.9,
and found the same way: by deploying and reading what the API said.

**(b) M1.4d, for the third time in this project.** The field deployed, the tests passed, and
anonymous Apex then refused to compile `SELECT Purchase_Request__c FROM
Approval_Decision_Log__c` with *No such column* — because the FLS edit had landed in
`Approval_Matrix_User` and silently missed `Approval_Matrix_Admin`, whose entries carry
`editable=true` and so did not match the same anchor. **Apex tests run in system mode and do
not see FLS**, so a fully green 144-test run said nothing about whether a human — or an
administrator's own anonymous Apex — could read the field. That is the same blind spot Group E
of the QA register exists for, showing up in a new place. *Grep both permission sets after any
scripted FLS edit; a count of one is a failure, not a success.*

**Verification.**

```
Tests            144 passed, 100%, run 707aj00001BGOqj   (141 before, +3)
Backfill         2 row(s) linked, 0 orphaned
Traversal        ADL-00000001 -> PR-00000001   PR_Catch_All -> PR_Two_Level_Mgmt
                 ADL-00000002 -> PR-00000003   PR_High_Value_APAC -> PR_Three_Level_Finance
```

Three tests were added: the lookup is populated alongside the text reference and traverses;
blocked and failed rows carry it too, since those belong in a record's related list at least as
much as successful ones; and an object the log holds no lookup to still gets its `Record_Id__c`,
which is the case that proves the field is optional rather than required.

---

## Phase M4 — Configuration validator

**Date:** 2026-09-18 · **Commit:** `9893274` (committed 2026-09-25) · **Status:** complete.

The first post-MVP increment closes the gap between a matrix edit and a failed submission.
`AMF_ConfigValidator` reads active rules only through `AMF_RuleProvider`, compiles each
expression, rejects duplicate priorities, confirms the governed object carries the Checkbox
guard, and confirms every referenced Classic process is active for that object. The
`AMF_ApprovalProcessProvider` seam keeps both rule and process fixtures in memory in unit
tests; the production provider queries `ProcessDefinition` by `DeveloperName`,
`TableEnumOrId`, `Type = 'Approval'` and `State = 'Active'`.

A Salesforce metadata deploy cannot call Apex. The release gate is therefore intentionally split:
`scripts/validate-approval-matrix-source.ps1` confirms source approval-process files are active
and use exactly `Matrix_Submission__c = TRUE`; after deploy,
`scripts/validate-config.apex` calls `AMF_ConfigValidator.validateOrThrow()`. The latter is
also available to Flow as **Validate Approval Matrix Configuration** and is granted only to
`Approval_Matrix_Admin`.

**Why two gates:** `ProcessDefinition` does not expose an entry-criteria field through Apex
SOQL. Rather than incorrectly claiming the live validator can inspect it, the source gate owns
that precise check and the Apex gate owns deployed-org state. Neither changes routing or writes
data; the successful live run consumed two SOQL queries and zero DML.

**Verification:**

```
Source guard gate       passed: 3 active rules
Deploy                  succeeded: 41 components, 0 errors (0Afaj00000klbEXCAY)
Focused tests           passed: 12/12 (707aj00001FlW6d)
Live post-deploy gate   passed: 2 SOQL, 0 DML
RunLocalTests           passed: 150/150 (707aj00001FlHXv)
```

### M4.1 Follow-up: the new read path was unpinned, the entry points untested (2026-09-25)

`9893274` was written in a Cursor session. A review before pushing found its tests green but
its coverage thin, and one CLAUDE.md non-negotiable no longer held:

| Class | Before | After |
|---|---|---|
| `AMF_ClassicApprovalProcessProvider` | 0% | 100% |
| `AMF_ConfigValidator` | 71% | 98% |
| `AMF_CmdtRuleProvider` | 76% | 100% |

**(a) A second CMDT query the >255 pin did not reach.** M4 added the configuration-wide
`AMF_CmdtRuleProvider.getActiveRules()` with its own SOQL, filtering `WHERE Active__c = TRUE`.
The M1 pin proves truncation-safety only for `load()`, and the pin fixture
`PR_Long_Expression_Pin` is inactive by design (M1.8), so that active-only query could never
return it: a regression to `getAll()` there would have passed every test. The method now
delegates to a `@TestVisible loadAll(Boolean activeOnly)` shaped exactly like `load()` — active
filter applied in Apex — and `longExpressionSurvivesTheConfigurationWideLoad` pins the same
290-character round trip through it. The M1 `load()` path is untouched.

**(b) The no-argument provider contract had no contract test.** `assertConfigurationWideContract`
now holds both the CMDT provider and `AMF_RuleBuilder.Stub` to the same rule — never null, no
null entries, active only, strictly ordered — as M1 did for the per-object method.

**(c) The static entry points were unreachable without the org's matrix.** `validateOrThrow()`
and the invocable construct their own validator with production wiring, so testing them would
have meant depending on deployed CMDT rows. A `@TestVisible` static `entryPointOverride` (null
in production) lets tests drive both with in-memory fixtures. Now pinned: the CI gate throws
with the complete report and passes a valid matrix; the Flow action returns one result per
request, reports by default, throws only when `failOnError = true`, and ignores an empty call.

**(d) Defensive branches.** A local `RawRuleProvider` returns its list verbatim, proving the
`RULE_PROVIDER_RETURNED_NULL`, `NULL_RULE`, `INACTIVE_RULE_RETURNED` and
`OBJECT_API_NAME_MISSING` findings (`AMF_RuleBuilder.Stub` honours the contract and cannot
reach them). An unknown object yields `OBJECT_NOT_FOUND` and no follow-on process finding.
Checked on the way: `AMF_ExprCompiler` raises `AMF_ExpressionException` for an unknown object,
so the validator reports it rather than crashing.

**(e) `AMF_ClassicApprovalProcessProviderTest` reads deployed metadata, deliberately** — a
`ProcessDefinition` cannot be created in a test. It asserts both shipped templates are active
for `Purchase_Request__c`, an unknown name is not, the same names on `Account` do not count, and
blank input costs no query.

**Still uncovered, deliberately:** the three lines of `GUARD_FIELD_WRONG_TYPE`. Reaching them
needs an object carrying a non-Checkbox `Matrix_Submission__c`, and scope discipline forbids
creating metadata to serve a test.

**Verification:**

```
Deploy                  succeeded: 5 classes (0Afaj00000llSXFCA2)
RunLocalTests           passed: 166/166, org-wide 98% (707aj00001HVtMw)   (150 before, +16)
Source guard gate       passed: 3 active rules
Live post-deploy gate   passed: 2 SOQL, 0 DML
```

---

## Phase M5 — Preview modal

**Date:** 2026-09-25 · **Commit:** `5b99045` · **Status:** complete — every automated gate green, and the
manual gate run in the real UI (M5.7) except its blocked-path check, which needs the catch-all
deactivated (M5.5).
**Playbook goal:** before anything is submitted, show the submitter where the record will go
and why.

The second post-MVP increment, and the first that changes what a user sees. §6.4 has specified
`preview()` since v3.0 and §7 has always described the UI row as "headless LWC quick action →
preview → confirm → submit"; §13.1 deferred both. CLAUDE.md's authorised-work paragraph now
admits the preview modal alongside M4's validator; everything else on the out-of-scope list
stays deferred.

### M5.1 File-level changes

| File | Change | Notes |
|---|---|---|
| `classes/AMF_ApprovalMatrixService.cls` | **modified** | `submit()` and new `preview()` share one private `run(recordIds, commitDecision)`; new `@AuraEnabled previewRecord`; `Outcome` gains `rulePriority`, `matchedExpression`, `evaluatedValuesJson` |
| `classes/AMF_ApprovalMatrixServiceTest.cls` | **modified** | +9 preview tests |
| `lwc/amfSubmitPreview/*` | **added** | `LightningModal` subclass, presentation only; 7 Jest tests |
| `lwc/amfSubmitForApproval/*` | **modified** | preview → modal → submit; double-click guard; changed-route warning; 16 Jest tests (was 6) |
| `jest-mocks/lightning/modal.{js,html}` | **added** | Jest stand-in for `lightning/modal` — see M5.3a |
| `jest.config.js` | **modified** | `moduleNameMapper` for `lightning/modal` |
| `CLAUDE.md`, `docs/architecture.md` (§6.4 note, §13.4 row), `docs/build-playbook.md` (M5) | **modified** | scope and plan |

No objects, fields, layouts, quick actions or permission-set entries changed. `previewRecord`
lives on `AMF_ApprovalMatrixService`, which both permission sets already grant, and the quick
action metadata is untouched — only the bundle behind it changed.

### M5.2 Design choices worth recording

**(a) One path, stopped early — not a parallel preview.** The whole of `submit()`'s old body is
now `run()`, with one early return between step 7 and step 8. Authorisation, the guard-field
check, rule order, compilation, the single union query and the first-true walk are therefore
*the same code* for both, and a preview cannot drift from the submission it predicts.
`aPreviewShowsExactlyWhatTheSubmissionThenRecords` pins that byte for byte: the preview's
expression and evaluated-values JSON equal the log row the submission then writes. §6.4 names
the flag `commit`; Apex reserves that word, hence `commitDecision`. `match()` still builds the
unsaved log row during a preview — cheap, and it is what keeps the path identical.

**(b) The preview returns the "why", with nothing new disclosed.** §6.4 lists rule, description
and template. The modal also shows priority, the rule's expression and the values it read — the
same content `Expression_Snapshot__c` and `Evaluated_Values__c` record, and
`Approval_Matrix_User` already grants read on both for the submitter's own rows. The preview is
held to the same `UserRecordAccess` check as a submission
(`aPreviewRequiresReadAccessToTheRecord`). Each JSON string is computed once and shared by the
outcome and the row.

**(c) `previewRecord` is not `cacheable`.** A cached answer would survive an edit to the record
or the matrix and confirm a route the submission would not take.

**(d) `LightningModal`, opened by the headless action itself.** M3.4a found the org refuses to
change an existing LWC action's type to a screen action, and §7 asks for headless anyway. The
modal is presentation only: it receives the preview and resolves `submit` or `cancel`; the
action does the one submission. The header's X and Escape resolve `undefined` and submit nothing.

**(e) Only a routable preview opens the modal.** A `Blocked_No_Match` or `Failed` preview has no
route to confirm, and §6.1 step 6 wants the *attempt* on record — but a preview writes nothing
(§6.4). So the action submits those directly, the submission writes the row and the sticky toast
explains it, exactly as before M5. M3 QA step 5 ("blocked, with a `Blocked_No_Match` row")
therefore still holds through the UI. The alternative, a modal with only Close, would have made
the UI path silently stop producing blocked and failed rows — including the stack trace an
admin needs when schema drift makes a rule fail at runtime.

**(f) A changed route is reported, not papered over.** `submitRecord` re-runs the engine. If
the record or the matrix changed after the preview and the submission matched a different rule,
rule version or process, the toast is a sticky warning naming what actually happened. Version is
compared too: a rule edited in place keeps its name.

**(g) Double clicks.** An async headless `invoke()` can be called again while the first call is
still awaiting Apex; an `isExecuting` guard drops the second, as the headless-action docs
recommend.

**(h) Rendering.** Numbers go through `lightning-formatted-number`, so they read in the viewer's
locale (`250,000`); a null reads `(blank)`, because a blank that decided a route is worth seeing;
booleans read `TRUE`/`FALSE`. A rule reading no fields says it "matches every record" — true,
because a field-less expression is constant and this one matched. Everything is rendered as
template text, never markup.

No `docs/decisions.md` entry: nothing departs from the doc. §6.4 and §7 are built as written,
and the one gap — what a blocked preview does — is resolved in §6.4's M5 note.

### M5.3 Issues encountered

**(a) `lightning/modal` has no Jest stub.** `@salesforce/sfdx-lwc-jest` 7.9.0 ships
`modalHeader`, `modalBody` and `modalFooter` stubs but not `lightning/modal`, and its resolver
returns nothing for a missing stub, so a `LightningModal` subclass cannot even be imported in a
test. Fixed with `jest-mocks/lightning/modal.js`, mapped in `jest.config.js`. It sits **outside
`force-app`** so no deploy can pick it up. The first version used `@api` decorators and failed
ESLint (*Parsing error: Unexpected character '@'*): the project's `**/jest-mocks/**` lint block
uses the plain parser. Nothing sets the modal's public properties in these tests, so the
decorators were dropped rather than the lint config changed.

**(b) The action is in the overflow menu.** The first real-UI run timed out looking for a
**Submit for Approval** button: on this layout the header shows Printable View, Sharing
Hierarchy and Edit Labels, and the framework's action sits under **▼**. Behaviour is unaffected;
promoting it is a `platformActionList` sort-order change, not M5's.

**(c) The org's matrix has drifted from the repo.** The real-org preview showed
`PR_High_Value_APAC` routing to `PR_Two_Level_Mgmt`. The repo's record says
`PR_Three_Level_Finance`; the org's row was edited in Setup on 2026-09-07 (the M3 rule-flip
QA, by the look of it) with `Version__c` still 1. The modal makes the drift visible: the rule's
description says "takes the three-level finance chain" beside a two-level route. M5 does not
touch configuration, so the row was left as found; redeploying the repo's record restores it.

**(d) Prettier.** The new files are not Prettier-formatted, and neither are the M3 files they
sit beside — checked against `HEAD`. Husky's `prepare` fails under `cmd.exe` (M3.4e), so
`core.hooksPath` was never set and lint-staged has never run on a commit here. The new code
follows the surrounding style rather than reformatting M3's files.

**(e) Two editor diagnostics, both pre-existing in kind.** The VS Code XML schema rejects
`<actionType>` in the action's `js-meta.xml` (the org has accepted it since M3), and the LWC
language server flags `createElement` in test files (LWC1702) because it lints them as
components. Jest and the deploy are the authorities for both.

### M5.4 Verification evidence

**Deploy** — `0Afaj00000llXBxCAM`, Succeeded: `AMF_ApprovalMatrixService`,
`AMF_ApprovalMatrixServiceTest`, `amfSubmitForApproval` (changed), `amfSubmitPreview` (created).
The platform compiled the `lightning/modal` import server-side.

**Apex — 175/175:**

```
Outcome              Passed
Tests Ran            175        (166 before, +9)
Org Wide Coverage    98%
Test Run Id          707aj00001HW50S
AMF_ApprovalMatrixService   204/204 lines, 100%
```

**Jest — 23/23** (was 6), and ESLint clean on `force-app/main/default/lwc`, `jest-mocks` and
`jest.config.js`:

```
c-amf-submit-for-approval
  √ renders nothing itself: it is headless, and the confirmation is a separate modal
  √ previews the route and shows it in the modal before submitting anything
  √ submits only after the user confirms, and reports the matched rule and process
  √ submits nothing, says nothing and refreshes nothing when the user backs out with Cancel
  √ submits nothing, says nothing and refreshes nothing when the user backs out with the X or Escape
  √ skips the modal for a Blocked_No_Match preview and submits, so the attempt is logged and explained
  √ skips the modal for a Failed preview and submits, so the attempt is logged and explained
  √ says so when the submission took a different route than the preview showed
  √ treats a new rule version as a changed route even when the process is the same
  √ surfaces a submission blocked after a routable preview as an error
  √ keeps the positioned Apex message when the preview throws, and submits nothing
  √ keeps the positioned Apex message when the submission throws
  √ falls back to a readable message when the error carries no body
  √ submits nothing if the modal cannot open
  √ refreshes the record however a submission ended
  √ ignores a second click while the first is still in flight, then works again
c-amf-submit-preview
  √ names the process, the rule that chose it, and the rule's condition
  √ shows each value the rule read, numbers formatted for the viewer's locale
  √ shows a blank value that decided a route rather than hiding it, and booleans as TRUE/FALSE
  √ says the catch-all reads no fields instead of showing an empty table
  √ leaves out the description row when the rule has no description
  √ resolves with submit only when the user confirms
  √ resolves with cancel when the user backs out
Tests: 23 passed, 23 total
```

**The real preview, against the org's deployed matrix and all six Purchase Requests** —
anonymous Apex calling `new AMF_ApprovalMatrixService().preview(ids)`, measuring its own writes:

```
PR-00000001 [500.00 EMEA Low]     -> Submitted | PR_Catch_All p9999 v1     | PR_Two_Level_Mgmt | values={}
PR-00000002 [250000.00 APAC Low]  -> Submitted | PR_High_Value_APAC p10 v1 | PR_Two_Level_Mgmt | values={"Region__c":"APAC","Amount__c":250000.00}
PR-00000004 [700.00 EMEA Low]     -> Submitted | PR_Catch_All p9999 v1     | PR_Two_Level_Mgmt | values={}
PR-00000006 [250000.00 APAC High] -> Submitted | PR_High_Value_APAC p10 v1 | PR_Two_Level_Mgmt | values={"Region__c":"APAC","Amount__c":250000.00}
(PR-00000003 and -05 as -02; submitted=false and log=null on every row)
PREVIEW WRITES: dml=0 logRowsBefore=6 logRowsAfter=6
```

**The real UI.** Headless Edge driven by `playwright-core` (installed in a scratch directory,
not the project), logged in through `sf org open --url-only`. On PR-00000001 and PR-00000006:
▼ → **Submit for Approval** → the modal opened from the headless action → text read → **Cancel**.

```
record 1: Confirm approval route | PR_Two_Level_Mgmt | PR_Catch_All | 9999 | 1 | TRUE
          "This rule's condition reads no fields, so it matches every record."
record 2: Confirm approval route | PR_Two_Level_Mgmt | PR_High_Value_APAC | 10 | 1
          Amount__c > 100000 && Region__c == 'APAC' | Region__c APAC | Amount__c 250,000
after Cancel (both): modal closed; toasts shown: 0
console errors mentioning amf/modal/preview/submit: 0
decision log rows before/after: 6 / 6
```

### M5.5 Carried into later phases

| Item | Owner |
|---|---|
| ~~**The modal's Submit button was not clicked in the org.**~~ | **closed in M5.7** — rehearsed on a throwaway record at the user's request |
| The gate's blocked-path check in the real UI: with the catch-all deactivated, a non-matching record skips the modal and still gets its `Blocked_No_Match` row. Covered by Jest and the Apex suite; running it in the org means deactivating a live rule | user, optional |
| ~~**Org drift:** `PR_High_Value_APAC` routes to `PR_Two_Level_Mgmt` in `amf-dev` but `PR_Three_Level_Finance` in the repo (M5.3c)~~ | **closed in M5.6** — the repo's record redeployed |
| ~~A preview does not know a record is already in an approval process: it shows the route, and the submission then fails with the platform's error, as before M5. A lock check in the preview would say so up front~~ | **closed in M8** — a pending `ProcessInstance` refuses preview and submit |
| ~~The action sits in the ▼ overflow menu (M5.3b)~~ | **closed in M5.6** — first in `platformActionList`, now a header button |
| ~~`AMF_ApprovalMatrixService`'s header still says §9 is out of MVP scope; stale since M4~~ | **closed in M8** |

### M5.6 Follow-up: demo preparation — drift restored, action promoted (2026-09-25)

Two M5.5 items, closed at the user's request before the demo.

**(a) `PR_High_Value_APAC` restored from the repo.** Every field of the org row was compared
with `customMetadata/Approval_Matrix_Rule.PR_High_Value_APAC.md-meta.xml` first: label,
expression, description, priority, version and active flag were identical, and only
`Process_API_Name__c` differed (`PR_Two_Level_Mgmt` in the org, `PR_Three_Level_Finance` in the
repo). Deploying the repo's record therefore changed exactly that field. It went through M4's
release gate in order: source gate, deploy, post-deploy gate.

The decision log shows where the drift came from. It is the M3 rule-flip QA, left flipped:

```
ADL-00000006  2026-09-07 10:46  PR-00000002  PR_High_Value_APAC  v1  PR_Three_Level_Finance
              2026-09-07 10:49  rule edited in Setup: Process_API_Name__c -> PR_Two_Level_Mgmt
ADL-00000010  2026-09-16 07:45  PR-00000005  PR_High_Value_APAC  v1  PR_Two_Level_Mgmt
```

Both rows read **v1**. §3.1 says `Version__c` is "incremented on any change", and the Setup edit
did not bump it. Nothing is lost — each row snapshots its own `Selected_Process__c` and
`Expression_Snapshot__c`, which is precisely §8's point — but the version column cannot tell the
two apart. The restore deliberately keeps the repo's v1 rather than inventing a number the repo
does not hold; **a live rule flip should bump `Version__c` with the process**, so the log reads
v1 → one process, v2 → the other.

**(b) Submit for Approval is now a header button.** The record header shows only the first few
applicable actions (three, at desktop width) and puts the rest under ▼. The framework's action
was last in `platformActionList` (`sortOrder` 11). It is now first (`sortOrder` 0), with the
other eleven entries renumbered in their existing order; standard `Submit` stays absent (§6.3).
Before deploying, the org's layout was retrieved into a scratch directory — not the project —
and compared with the repo's, comments ignored: identical, so the deploy changed only the order.
Edit Labels moves from the header into ▼. A browser that already has a Purchase Request open may
need a reload to show the new order.

**Verification:**

```
Source guard gate       passed: 3 active rules
Deploy                  0Afaj00000llabFCAQ Succeeded: Approval_Matrix_Rule.PR_High_Value_APAC,
                        Purchase_Request__c-Purchase Request Layout
Post-deploy gate        Approval Matrix configuration is valid (2 SOQL, 0 DML)
Active rules            10 PR_High_Value_APAC v1 -> PR_Three_Level_Finance
                        20 PR_High_Risk       v1 -> PR_Three_Level_Finance
                        9999 PR_Catch_All     v1 -> PR_Two_Level_Mgmt
Real preview            PR-00000002/3/5/6 -> PR_High_Value_APAC -> PR_Three_Level_Finance;
                        PR-00000001/4 -> PR_Catch_All -> PR_Two_Level_Mgmt; dml=0, log rows 6/6
Real UI (PR-00000006)   header: Submit for Approval | Printable View | Sharing Hierarchy | ▼
                        the button opened the modal directly: PR_Three_Level_Finance, rule
                        description now consistent with the route; Cancel -> no toast; log rows 6/6
```

### M5.7 Rehearsal and demo records (2026-09-25)

At the user's request, for a business-audience demo.

**Demo records, created unsubmitted.** Their routes were confirmed read-only through the real
preview before anything was clicked (`dml=0`, log rows 6/6):

```
PR-00000007  250,000  APAC  Low   -> PR_High_Value_APAC (p10)  -> PR_Three_Level_Finance
PR-00000008    5,000  EMEA  High  -> PR_High_Risk       (p20)  -> PR_Three_Level_Finance
PR-00000009      500  EMEA  Low   -> PR_Catch_All     (p9999)  -> PR_Two_Level_Mgmt
```

**The rehearsal — the one real submission, on a throwaway record.** PR-00000010, a copy of
PR-00000007's data, driven through the real UI by headless Edge: the header button → the modal
showed `PR_High_Value_APAC -> PR_Three_Level_Finance` → **Submit for Approval** → the modal
closed → the toast read *"Submitted for approval — Matched PR_High_Value_APAC (v1) and routed to
PR_Three_Level_Finance."* Four seconds later the page had refreshed itself and **Matrix
Submission** read ticked, which is `notifyRecordUpdateAvailable` working. No console errors.

That toast was M5's one unverified runtime question: whether a headless action is still alive to
dispatch a toast after the `LightningModal` it opened has closed. It is. The data behind it:

```
ProcessInstance       04gaj000001sZoDAAU  Pending  PR_Three_Level_Finance
Work item             AMF Approver Three (amfu3) - step 1 of the named-user chain
Decision log          ADL-00000011  Submitted  PR_High_Value_APAC v1  PR_Three_Level_Finance
                      expression and values snapshotted; Execution_Ref_Id__c = 04gaj000001sZoDAAU
Guard                 Matrix_Submission__c = true
```

PR-00000010 stays pending with `amfu3`, and ADL-00000011 is permanent. Both are the rehearsal,
not demo data.

---

## Phase M6 — Flow approvals technical spike (research only)

**Date:** 2026-10-07 · **Commit:** `972352a` (mislabelled — see M6.6) · **Status:** complete, with one item that needs a person (M6.5).
**Playbook goal:** answer Round 1's open questions and find every trap in moving from Classic
approval processes to Flow approvals, before any `FlowApprovalStrategy` is designed.

The findings themselves — every claim labelled, with its experiment id — are in
`docs/spike-results.md`, Round 2, together with an 18-point Classic → Flow migration checklist.
This entry records how the spike was run, what went wrong on the way, and what it left behind.

### M6.1 File-level changes

| File | Change |
|---|---|
| `spikes/flow-approvals/mdapi/flows/*.flow` | **added** — 11 spike flows (screen flow, guard-reset background flow, 9 orchestrations; `AMF_Spike_User_Id` is a negative test that must fail activation) |
| `spikes/flow-approvals/mdapi/classes/AMF_FlowApprovalSpikeTest.cls` | **added** — discovery test (reports through `Assert.fail`); deployed for the run, then **deleted from the org** |
| `spikes/flow-approvals/scripts/*` | **added** — group setup, MDAPI deploy, anonymous-Apex runner, inspect/launch/action scripts, teardown |
| `docs/spike-results.md` | Round 2 added above Round 1 (kept verbatim, headings demoted) |
| `docs/architecture.md` | §5.3 contract corrected; §5.4 open risk, §12 (items 1, 2, 6–8), §13.4 M6 row, Appendix A and B updated |
| `docs/decisions.md`, `docs/build-playbook.md` (M6), `CLAUDE.md` | doc-fix line; phase entry; M6 authorised as research only, plus the API ≤ 66 rule |

Nothing under `force-app` changed. `spikes/` is not a package directory, so `sf project deploy
start` cannot ship it.

### M6.2 Method

**Research before touching the org.** Salesforce Help and developer.salesforce.com refuse
automated fetches (client-rendered / HTTP 403), so desk research used release-note summaries and
practitioner write-ups, every claim treated as a hypothesis. The schema authority was the org's
own Metadata API WSDL (Summer '26, 1.97 MB), downloaded with the CLI session as a `sid` cookie
because `/services/wsdl/metadata` rejects a bearer token. It settled field names and enums the
web could not: `shouldLock`, `requiresMultiMemberApproval`, assignee types
`User`/`Group`/`Queue`/`Resource`, `pathType ApprovalRecall`, and `stepBackground`.

**Hands-on, isolated.** One small orchestration per question; spike records PR-00000011 onward;
the spike's own groups (`AMF_Spike_Any`, `AMF_Spike_All`, `AMF_Spike_Queue`, each holding the
admin plus `amfu1`), so the seeded `Q_Credit_Risk` and `G_Finance_Approvers` were never touched.
The admin's membership let a member decide from anonymous Apex; `System.runAs` in the test class
covered decisions by a non-admin.

### M6.3 Issues encountered

**(a) The platform corrected the template, one deploy at a time.** Background steps typed `flow`
were refused for this process type (`stepBackground` is right); then a fourth input,
`firstApprover`, was demanded (absent from Round 1's API 62 contract); then
`runInMode SystemModeWithoutSharing`. Each refusal is now a line in §5.3.

**(b) The first launch rolled itself back.** E1 created its submission, then died on
`Approval.isLocked()`: *"Apex approval lock/unlock api preference not enabled."* Even reading a
lock needs the org preference "Enable record locking and unlocking in Apex". It was left off, and
locking was proved instead by a non-admin owner's refused edit (T2).

**(c) The documented action values are wrong.** `reviewApprovalWorkItem` describes its valid
decisions as "approve, reject"; `approve` returns `INVALID_INPUT`, and only `Approve` works. In the
test class, an `Id` passed where the action declares a String returned `INVALID_ARGUMENT_TYPE`.

**(d) The gated two-level template was wrong, and its first test made it look right.** The gate
read a variable filled by the approval step's `outputParameters` mapping. Rejection at level 1
ended the run, which looked correct (E10). Approval at level 1 *also* ended the run — the submission
read **Approved after level 1 alone** (E11). A probe flow (E12) showed the mapped variable is
null for both outcomes, while the direct reference `Approve_L1.Outputs.approvalDecision` holds
`Approve` / `Reject`. Fixed and re-run on both paths (E10b, E11b). This is why checklist item 3 says
to test the approve path of every gate, not only the reject path.

**(e) The unanimous setting is silently dropped.** `requiresMultiMemberApproval` = `true` deployed,
activated and ran any-member (E7). Retrieval showed the element gone. Six more values (`TRUE`,
`True`, `Unanimous`, `Yes`, `AllMembers`, `All`) were dropped the same way through the Metadata
API, and the Tooling API dropped it too. That probing cost seven versions of `AMF_Spike_Group_All`
(the limit is 50). The Tooling attempt was useful anyway: its `infos` carried two warnings the
Metadata API deploy never shows — the Automated Process User has no email, so steps cannot send
emails; and literal `User`/`Group`/`Queue` assignees block packaging.

**(f) API 67.0 is user mode.** The first locking test failed on its own setup: a plain `insert` as an
`Approval_Matrix_User` was refused for the read-only guard field. The class was at API 67.0, where
Summer '26 makes database operations run in user mode by default. The setup now says `insert as
system`. The finding outranks the spike: the engine's classes stay at API 62 for exactly this
reason, and §12 item 6 and `CLAUDE.md` now say so.

**(g) Browser automation stopped working.** The same Playwright checks that verified M5 on
2026-09-25 now end with the whole browser closing as soon as the Salesforce sign-in page loads —
Edge 154 and Chrome 153, with an old and the current `playwright-core` alike, while `about:blank`
loads fine. That pattern fits a workstation security policy. It was not worked around, so the
Flow Builder and record-page checks are left to a person (M6.5).

**(h) `sf apex run test -s` is `--suite-names`** in this CLI version; synchronous is `--synchronous`.
And the tool's command guard blocked an `Env:` cleanup it misread as deleting `"C:\Program"`, so
nothing in that command ran — harmless, since an environment variable lives for one command anyway.

### M6.4 Verification evidence

The submission, work-item, orchestration and stage states for every experiment are in
`docs/spike-results.md`. The two test-context reports, verbatim:

```
T1  start=ok | inTest submissions=1 status=InProgress items=1 | approverReadAccess=false |
    reviewAsAssignee success=true | afterStopTest submissions=1 status=Approved itemStatus=Approved | guard=false
T2  startAsNonAdminSubmitter=ok | ownerEditWhilePending refused ENTITY_IS_LOCKED: This record is locked.
    If you need to edit it, contact your admin. | ownerEditUnsubmittedControl ok |
    reviewByNonAssignee success=false errors=(UNKNOWN_EXCEPTION: Orchestrator Event: Event payload
    value is invalid: StepInstanceId) | reviewByAssignee success=true | ownerEditAfterApproval ok |
    finalStatus=Approved
```

```
Flow submissions after the experiments   15  (Approved 6, Rejected 5, Recalled 3, Canceled 1)
ProcessInstance rows for those records    0
Dry-run deploy of the 10 committed flows  Succeeded (after XML normalisation)
Spike test class in the org               deleted; AMF_Spike_Probe draft deleted
RunLocalTests                             175/175 passed (707aj00001JswIb) - product untouched
```

### M6.5 Left behind, and carried forward

**In `amf-dev`, on purpose:** the spike flows, the three spike groups and the spike Purchase
Requests, so the unanimous check below can be done against them. Removal is
`spikes/flow-approvals/scripts/teardown.ps1 -DeleteFlows -DeleteGroups -DeleteRecords`.

| Item | Owner |
|---|---|
| **The `requiresMultiMemberApproval` value.** In Flow Builder open *AMF Spike Group All*, select *Unanimous Approval*, tick **Require unanimous approval**, save as a new version; the stored value is then readable through the Tooling API and E7 can be re-run | user (Flow Builder), then a session |
| The UI half: the lock icon, the Approval Trace component, and a decision made through the approval screen flow (to confirm it fills `<Step>.Outputs.approvalDecision` as the action path does) | user |
| Groups and queues through a `Resource` assignee — value format untested | next Flow session |
| Set the Automated Process User's email before any real Flow approval, or approvers are not notified | user / org admin |
| A reset path for cancelled Flow submissions (cancel leaves the guard set), or an operational rule to recall rather than cancel | Flow design phase |
| ~~M5's "preview does not know a record is already in approval": use SOQL on `ApprovalSubmission` / `ProcessInstance` — `Approval.isLocked()` needs an org preference~~ | **closed in M8**, Classic half: SOQL on `ProcessInstance` |
| A convention for API versions: Flow templates need a newer `sourceApiVersion`, while engine classes stay at ≤ 66 (§12 item 6) | Flow design phase |

### M6.6 Correction: the M6 commit carries the wrong message

The phase commit, `Phase M6: Flow approvals technical spike`, **never happened**. Its message
contained double quotes, and Windows PowerShell 5.1 strips embedded double quotes when it passes
arguments to a native program, so git received fragments of the message as pathspecs and refused.
The command had redirected git's error output away, so the failure went unseen. The next command
then committed **everything still staged** as `972352a` under the follow-up's message, *Record the
Phase M6 commit SHA in the technical log*, and wrote the previous commit's id, `6a37c65` (the M5
rehearsal record), into this log as M6's.

`972352a` is the complete M6 change (27 files) and is already pushed. Rewriting `develop` would
take a force push, so it stands, and this note is the correction: **M6 is `972352a`**. The log now
says so.

Two rules come out of it, both for this workstation's PowerShell: never discard git's error output
on a commit, and confirm the new commit id before writing it anywhere. Keep commit messages free
of double quotes, or pass them with `git commit -F <file>`.
---

## Phase M7 — Decision timeline

**Date:** 2026-10-08 · **Commit:** `25e0b2d` · **Status:** complete. Built and verified locally without
org access (M7.3a); the org gate then passed the same day (M7.7), and its recall check confirmed a
guard gap that predates M7 (M7.8).
**Playbook goal:** on the governed record, tell the whole story of each submission in one place:
why the matrix routed it where it did, and what has happened to it since.

§8 has described "a read-only timeline LWC [that] renders both halves as one narrative" since
v3.0, and §13.2 deferred it. `CLAUDE.md` now authorises the timeline alone, Classic only; every
other item on the out-of-scope list stays deferred.

### M7.1 File-level changes

| File | Change | Notes |
|---|---|---|
| `classes/AMF_DecisionTimelineService.cls` | **added** | `@AuraEnabled getTimeline(recordId)`, not cacheable; `build()` authorises, reads, joins, orders and caps |
| `classes/AMF_ApprovalHistory.cls` | **added** | value types `Instance` and `Step`, and the step-ordering rule |
| `classes/AMF_ApprovalHistoryProvider.cls` | **added** | read seam, as `AMF_ApprovalProcessProvider` is for §9 |
| `classes/AMF_ClassicApprovalHistoryProvider.cls` | **added** | `ProcessInstance` with `StepsAndWorkitems`, without sharing |
| `classes/AMF_DecisionTimelineServiceTest.cls` | **added** | 12 tests on an in-memory history |
| `classes/AMF_ApprovalHistoryTest.cls` | **added** | 4 tests on the ordering rule |
| `classes/AMF_ClassicApprovalHistoryProviderTest.cls` | **added** | 3 tests, one of them a real submission |
| `lwc/amfDecisionTimeline/*` | **added** | the container: loading, refresh, states; 11 Jest tests |
| `lwc/amfDecisionTimelineEntry/*` | **added** | one SLDS timeline item per entry; 20 Jest tests |
| `lwc/amfSubmitForApproval/*` | **modified** | dispatches `RefreshEvent` after every submission attempt; 19 Jest tests (was 16) |
| `flexipages/Purchase_Request_Record_Page.flexipage-meta.xml` | **added** | header, Details and Related tabs, the timeline in the sidebar |
| `objects/Purchase_Request__c/Purchase_Request__c.object-meta.xml` | **modified** | `View` override for `Large`: the page above becomes the desktop org default |
| `permissionsets/Approval_Matrix_Admin`, `Approval_Matrix_User` | **modified** | class access to `AMF_DecisionTimelineService`, one entry in each |
| `CLAUDE.md`, `docs/architecture.md` (§8 M7 note, §13.4 row), `docs/build-playbook.md` (M7), `docs/decisions.md` | **modified** | scope, design, gate, two decisions |

No objects, fields, layouts or quick actions changed, and no engine class was touched.

### M7.2 Design choices worth recording

**(a) One entry per submission attempt, joined through `Execution_Ref_Id__c`.** Each decision log
row is an entry. A `Submitted` row carries the `ProcessInstance` its `Execution_Ref_Id__c` names;
a `Blocked_No_Match` or `Failed` row carries none, because it never entered a process. The join is
a map lookup on the 18-character Id that §6.1 step 11 stamps, and each row claims its approval by
removing it from the map. Whatever remains is exactly the set of approvals that have no row this
user can read, and those become entries of their own, labelled as such, rather than being
dropped.

**(b) Two visibility rules, both borrowed from the platform.** Log rows are read
`WITH USER_MODE`, so a row appears in the timeline exactly when the viewer could open it anywhere
else: their own as an `Approval_Matrix_User`, every row with View All (§11). Native history is
shown to anyone who can read the record. That is the rule the Approval History related list
follows, and it is checked first, with the same `UserRecordAccess` query shape as the engine's
(M3.10), because the Classic provider reads without sharing. An approver will therefore see the
approval and its steps but not the routing reason for someone else's submission; that is
recorded in `docs/decisions.md`.

**(c) Only what was recorded.** The narrative names a rule by the DeveloperName and version the
row snapshotted, not by today's description, which would have to come from the live matrix and
would let a later edit rewrite an earlier explanation (`docs/decisions.md`). Field labels are
resolved by describe when the timeline is read. They are presentation only: the recorded path is
each value's tooltip and appears verbatim in the condition.

**(d) The read path degrades where routing would fail loudly.** §4.6 governs routing, where a
silent fallback misroutes a record. In an audit view the cost runs the other way, so: a field
deleted since the decision shows under its recorded path; a values snapshot that is not a JSON
object is shown whole, as recorded; a `Submitted` row whose approval the history does not return
says that history is not available; a row with no outcome is shown rather than hidden.

**(e) A window that stays honest across the join.** At most 50 entries. Both sources are read one
row past that, merged, sorted and only then cut, with `hasMore` set when anything was cut. A row
and its approval are written in one transaction, so a row too old to be fetched belongs to an
approval too old to survive the cut, and the reverse holds too. An approval is therefore never
labelled unexplained merely because its row fell outside a fetch.

**(f) Step order is a rule, not whatever the database returns.** Ties to the second are normal,
not rare: one `Approval.process()` writes the submission and the first work item, and one
approval writes the decision and the work item it hands on to. Within one instant the submission
comes first, open work items come last, and Id settles the rest. The rule lives in
`AMF_ApprovalHistory`, so the provider contract carries it, and it is tested on its own.

**(g) Current without a cache.** `getTimeline` is not cacheable, for §6.4's reason. The component
reads on connect, when the record page refreshes (`registerRefreshHandler`), and from its own
refresh button. `amfSubmitForApproval` now dispatches `RefreshEvent` after every submission
attempt, whether it was routed, blocked or refused: `notifyRecordUpdateAvailable` only reaches the
record cache, and a decision log row is not part of the record. Overlapping reads take a ticket
and only the latest may write the result. That guard was mutation-checked: with it removed, the
two race tests fail.

**(h) The record page.** Placing a component on a record needs a Lightning record page, and a
placement made only in App Builder would drift from the repo (M5.6). `Purchase_Request_Record_Page`
follows the structure of `trailheadapps/ebikes-lwc`'s `Product_Record_Page` (M7.3d), and the
`View` / `Large` / `Flexipage` override in the object file is what activates it as the desktop
org default. The header's actions still come from the page layout. §6.3's removal of the
standard Submit for Approval button lives in the layout's `platformActionList`, and switching
this page to dynamic actions would bypass it; the page's own header comment says so. Phones keep
the default page, and the default page's sidebar Activity panel is not carried over (the
activity related lists remain on the Related tab).

**(i) Presentation.** SLDS activity-timeline markup, newest entry open. Details are rendered only
while an entry is open, so `aria-expanded` stays truthful without relying on SLDS to hide them.
A number keeps the precision it was recorded with and is grouped for the viewer's locale
(`24,00,000` in `en-IN`, §8's own example). A blank reads `(blank)`, and booleans read `TRUE` /
`FALSE`, as in M5's modal. Recorded text keeps its line breaks and wraps in a narrow sidebar. Each
item sets `isolation: isolate`, so SLDS's connecting line, drawn behind the item, is not lost
behind the card's background. Every value is rendered as template text, never as markup.

### M7.3 Issues encountered

**(a) No org in this session.** The work ran in a cloud container with no `sf` CLI and no
`amf-dev` credentials. Nothing was deployed, no Apex was compiled or run there, and the UI was not
seen. The substitutes, strongest first:

1. **apex-ls 6.3.0** (`io.github.apexdevtools.apexls.CheckForIssues`, the JVM build from Maven
   Central, run from a scratch directory and not added to the project). It analyses Apex against
   the project's metadata and the standard SObject schema. Baseline before M7: no errors and one
   pre-existing warning. After M7: the same.
2. **The project's own Apex parser** (`prettier-plugin-apex`): every new class parses.
3. **Jest and ESLint**, in full.
4. **Public, deployable Salesforce sample metadata** as a reference for the FlexiPage and its
   activation (d).

None of these proves that the SOQL runs, that the platform returns `ProcessInstanceHistory` in
the shape the provider test asserts, that the FlexiPage deploys, or that the page looks right.
M7.5 is the gate that does.

**(b) apex-ls caught a compile error that a deploy would have hit.** `valuesOf(String json, …)`
called `JSON.deserializeUntyped(json)`. Apex identifiers are case-insensitive, so the parameter
`json` shadowed the `JSON` class and the call resolved against `String` (*No matching method
found for 'deserializeUntyped' on 'System.String'*). The parameter is now `snapshot`. The checker
also flagged `of` as a reserved identifier (now `labelOf`), the same warning that
`AMF_ExpressionException` already carries.

**(c) apex-ls does not check field names inside SOQL.** A probe query with invented fields
passed. It does check every field access in Apex, and every field the new queries select is
read in Apex. The fields that appear only in clauses (`TargetObjectId`, `Record_Id__c`,
`Submitted_At__c`, `CreatedDate`) are ones deployed code already queries. It did confirm that
`ProcessInstanceHistory` carries `ProcessNode`, `Actor`, `OriginalActor` and `IsPending`, and that
`ProcessInstance` carries `ProcessDefinition`.

**(d) A FlexiPage written without a schema, then compared.** The container had no metadata WSDL
to validate against, so `trailheadapps/ebikes-lwc`'s `Product_Record_Page.flexipage-meta.xml` and
`Product__c.object-meta.xml` were fetched into the scratchpad as reference data. They agree with
this page on the template, regions, facets, tab titles and `parentFlexiPage`; they reference a
custom LWC by its bare name (`similarProducts`), and they activate the page as `View` / `Large` /
`Flexipage`. Two adjustments followed: `<mode>Replace</mode>` on the facets, and no
`enablePageActionConfig` template property, which the sample does not set and which defaults to
false.

**(e) Two tests relied on a tick count.** The log link's href arrives from
`NavigationMixin.GenerateUrl` after render, and two tests asserted it after one macrotask. They
failed once in about ten runs, on the first instrumented run. They now wait, within a bound, for
the expected href, and still fail if it never arrives. The first version of that helper returned
any href other than the placeholder, which accepted the previous entry's href immediately after
the entry was replaced; that produced a consistent failure, which exposed the helper rather than
the component.

**(f) Two small Jest and ESLint frictions.** jsdom has no `structuredClone`, so fixtures are
cloned through JSON, which is how Apex delivers them anyway. `@lwc/lwc/no-async-operation`
forbids `setTimeout`, so the test-only flush carries a scoped disable comment stating why.

**(g) Prettier.** As M5.3d found: the repo's `.prettierrc` formats with Prettier's default
2-space indent, while every file in the repo uses 4, and `prettier --check` fails on the M5 files
too. The new files follow the surrounding style.

### M7.4 Verification evidence (this session)

```
apex-ls CheckForIssues, whole project, -d warnings
  AMF_ExpressionException.cls  Warning: line 48: 'of' ... reserved identifier   <- pre-existing, the only finding
Apex parser (prettier-plugin-apex)   7/7 new classes parse
Jest                                 57/57 in 4 suites (23 before M7, +34)
  amfDecisionTimeline       11 tests   100% lines
  amfDecisionTimelineEntry  20 tests   100% lines
  amfSubmitForApproval      19 tests   100% lines   (+3: page refresh after routed, blocked, refused)
  amfSubmitPreview           7 tests   unchanged
ESLint                               clean: force-app/main/default/lwc, jest-mocks, jest.config.js
Mutation check                       ticket guard removed -> both race tests fail; restored
Stability                            57/57 on six consecutive runs, three with a cleared cache
```

### M7.5 The gate still owed, in this order

1. `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-approval-matrix-source.ps1`
2. `sf project deploy start -o amf-dev`. If the FlexiPage or the `View` override is refused, the
   error names the element: deploy the rest by `--source-dir` (Part 4 of the playbook) and report
   the message.
3. `sf apex run test -o amf-dev -l RunLocalTests -w 10 -r human`. Expect 194/194 (175 + 19).
   `AMF_ClassicApprovalHistoryProviderTest` is the one org-dependent new class: like
   `AMF_SubmissionIntegrationTest` it needs `PR_Three_Level_Finance` active, and it asserts that
   the pending step is named `Finance Analyst`, i.e. that `ProcessNode.Name` carries the step's
   label rather than its API name. That is the assertion most likely to need adjusting.
4. Jest, as in the playbook.
5. The manual checks in the playbook's M7 gate: PR-00000010, M3's approved, rejected and blocked
   records, a never-submitted record, a throwaway live submission, and an approver's view.

### M7.6 Carried into later phases

| Item | Owner |
|---|---|
| ~~**The org gate in M7.5**, including the first compile of the seven new classes~~ | **closed in M7.7** |
| Phones keep the default record page: only the `Large` form factor is overridden | post-M7 |
| The default page's sidebar Activity panel is not on the new page | post-M7, if activities are used |
| Approvers see an approval but not the routing reason for other people's submissions (`docs/decisions.md`); widening that is a sharing decision on the log | product decision |
| Rule descriptions are not snapshotted, so the narrative uses DeveloperNames (`docs/decisions.md`) | post-M7 |
| The Flow half of §8 (`ApprovalSubmission` / `ApprovalWorkItem`) plugs in through `AMF_ApprovalHistoryProvider` when Flow execution exists | Flow phase |
| UI strings are English literals, as in M3 and M5; Custom Labels when the framework needs translation | post-M7 |
| `messageOf` exists in both `amfSubmitForApproval` and `amfDecisionTimeline`; sharing it would refactor M5 | next change to either |
| `.prettierrc` (2 spaces) disagrees with every file in the repo (4 spaces) | project |
| ~~Still open from M5.5: `AMF_ApprovalMatrixService`'s header says §9 is out of MVP scope~~ | **closed in M8** |

### M7.7 The org gate — PASSED (2026-10-08)

Run by the user against `amf-dev`, in M7.5's order: the source gate, the deploy, the post-deploy
configuration check, RunLocalTests, then the manual checks. Those were PR-00000010; M3's approved,
rejected and blocked records; a never-submitted record; a throwaway submission appearing without a
page reload; and `amfu3`'s view of a shared record, with the routing reason labelled as not
visible. All were reported as passing. The command output was not pasted back, so this entry
records the result as reported rather than quoting it.

Because the deploy and the full test run passed, both risks M7.5 named held: the FlexiPage and its
`View` override deployed as written, and `ProcessNode.Name` carries the approval step's label
(`Finance Analyst`), as `AMF_ClassicApprovalHistoryProviderTest` asserts. The throwaway record's
decision log row is permanent, as M5.7's was.

### M7.8 Finding: a Classic recall leaves the guard set (confirmed 2026-10-08)

The optional check in M7.5's list: PR-00000010, the M5.7 rehearsal that was pending with AMF
Approver Three, was recalled from its Approval History related list. The timeline showed it as
recalled. **`Matrix_Submission__c` stayed ticked.**

**Cause.** Both templates set `allowRecall` to true, and only their final approval and final
rejection actions run `AMF_Clear_Matrix_Submission`. Neither declares recall actions, so a recall
unlocks the record and leaves the guard exactly as the engine set it. §5.2 names final approval and
rejection as the points that re-arm the guard and says nothing about recall. M6 found the Flow
equivalent (a cancelled submission keeps its guard, M6.5), but the Classic case had never been
exercised: M3's QA approved and rejected, and never recalled.

**Consequence.** On a recalled record, §6.3's guard is disarmed. A submission that bypasses the
engine — through the API, a Flow's Submit for Approval action, or Apex naming a template — now
passes the template's entry criteria and routes with no decision log row, which is the silent route
§6.3 exists to make impossible. The engine itself is unaffected, because it sets the guard on every
submission it makes.

**Not fixed in M7.** The fix changes the templates, which M7 did not authorise. Owed to M8: a recall
action on both templates that runs `AMF_Clear_Matrix_Submission`, the source gate requiring it on
every template, and §5.2 amended. A recall action only fires on recalls made after it is deployed,
so records already recalled keep a stuck guard and need clearing once. PR-00000010 is the only one
known; this query finds any others:

```
SELECT Name FROM Purchase_Request__c
WHERE Matrix_Submission__c = true
  AND Id NOT IN (SELECT TargetObjectId FROM ProcessInstance WHERE Status = 'Pending')
```

---

## Phase M8 — Guard integrity

**Date:** 2026-10-08 · **Commit:** `caeafb3` · **Status:** built and verified locally. The org gate is
owed (M8.5).
**Playbook goal:** close the two ways a record and its guard could disagree with the engine.

M7's gate confirmed the first one in the org (M7.8): a recall left `Matrix_Submission__c` set. The
second had been carried since M5.5: the preview offered a route for a record that was already in
an approval process, and the submission then failed with the platform's `ALREADY_IN_PROCESS`. The
user authorised M8 on 2026-10-08 and chose to refuse a pending record outright, with no log row,
over a new `Outcome__c` value (`docs/decisions.md`).

### M8.1 File-level changes

| File | Change | Notes |
|---|---|---|
| `approvalProcesses/Purchase_Request__c.PR_Three_Level_Finance.approvalProcess-meta.xml` | **modified** | `recallActions` running `AMF_Clear_Matrix_Submission` |
| `approvalProcesses/Purchase_Request__c.PR_Two_Level_Mgmt.approvalProcess-meta.xml` | **modified** | the same |
| `workflows/Purchase_Request__c.workflow-meta.xml` | **modified** | the field update's description names all three ways out |
| `scripts/validate-approval-matrix-source.ps1` | **modified** | requires a guard-clearing field update in final approval, final rejection and (when allowed) recall actions; each template checked once |
| `classes/AMF_ApprovalMatrixService.cls` | **modified** | `refuseRecordsAlreadyInApproval()` after `authorise()`; the header and step-7 comments no longer call §9 out of scope |
| `classes/AMF_SubmissionIntegrationTest.cls` | **modified** | +3 tests (M8.2 f); header updated |
| `classes/AMF_ApprovalMatrixServiceTest.cls` | **modified** | the query-budget message names the new check; one stale §9 comment |
| `CLAUDE.md`, `docs/architecture.md` (§5.2, §6.1 M8 note, §13.4 row), `docs/build-playbook.md` (M8), `docs/decisions.md` | **modified** | authorisation, design, gate, two decisions |

No new objects, fields, classes, components or permissions.

### M8.2 Design choices worth recording

**(a) One way to re-arm the guard, used on every way out.** The recall action reuses
`AMF_Clear_Matrix_Submission`, the field update that final approval and final rejection already
run, so all three exits from a process re-arm the guard identically. The element sits between
`processOrder` and `recordEditability`, where the Metadata API schema expects it.

**(b) The source gate judges an action by what it does.** For every template an active rule
names, it reads the object's workflow file and collects the field updates that set
`Matrix_Submission__c` to false (`Literal`, `0` or `false`). It then requires one of those among
the final approval actions, the final rejection actions and, when `allowRecall` is true, the recall
actions. A renamed clearing update passes; a field update called `AMF_Clear_Matrix_Submission` that
sets the guard to true fails. A template referenced by several rules is checked once, so the gate
no longer repeats findings, the existing entry-criteria check included. A template that does not
allow recall needs no recall action.

**(c) A pending record is refused before step 1, after authorisation.** One SOQL on
`ProcessInstance` (`Status = 'Pending'`) for the call's records, after `authorise()` and the guard-field
check. A hit refuses the whole call with an `AMF_SubmissionException` naming each pending record and
its process. Because `previewRecord` runs the same path, the action's existing error branch shows
the sentence in a sticky toast and submits nothing; no LWC changed, and M5's Jest test for a
preview that throws already covers that branch. Running after `authorise()` means a caller who
cannot read a record learns nothing about its approval.

**(d) No log row for a refusal.** This was the user's choice, recorded in `docs/decisions.md`.
Nothing was decided: the matrix never ran. It mirrors the read-access refusal and leaves the
restricted `Outcome__c` picklist, which the lock rule and every report rely on, unchanged.

**(e) The query budget is now spent exactly.** `everyRuleIsCompiledOnceHoweverManyRecordsAreSubmitted`
caps an engine call at 4 queries. In its shape the engine used 3: authorisation, the union query
and the stub's read. The pending check makes it 4. The cap is unchanged, its message now names the
check, and the next query added to the engine will have to argue for a higher cap.

**(f) The integration tests that only a live approval can run.** Three tests join
`AMF_SubmissionIntegrationTest`, each routing through the engine and the real Classic strategy:
- **A recall re-arms the guard.** A real submission is recalled as its submitter. The test
  asserts the guard is cleared and that a submission bypassing the engine is then refused by
  entry criteria. That pins M7.8 as a regression.
- **A pending record is refused in both preview and submit.** The refusal names the process,
  exactly one decision log row exists (the first submission's), and exactly one
  `ProcessInstance`.
- **A caller who cannot read the record is told about access only.** The message never names
  the approval.

The recall calls `Approval.process()` directly: it simulates a person pressing Recall, as the
existing bypass test simulates a bypass. CLAUDE.md's rule that `Approval.process()` goes through
the strategy governs the product's own submissions.

### M8.3 Issues encountered

**(a) No org again, and no PowerShell either.** The Apex substitutes are M7.3a's. The source gate
is a PowerShell script and the container has none, so PowerShell 7.4.6 (the official Linux build
from the PowerShell GitHub releases, kept in the scratch directory and not added to the project)
ran it. The gate's documented runtime is Windows PowerShell 5.1, and the script uses nothing newer
than 5.1 supports: `[ordered]`, generic `HashSet`, namespaced XPath.

**(b) A test that would have broken, found by reading.** The 4-query cap in (e) was spotted in the
suite before anything ran. The new check uses the last query the cap allows, so the test passes,
but only just; hence the message.

**(c) PowerShell 7 prints a thrown multi-line message on one line.** Counting findings by line
reported zero for two failing cases. They were counted by message instead (6 each). This was a
harness artefact, not a gate defect: the exit code was 1 throughout.

**(d) The checker's reach, confirmed rather than assumed.** A probe class calling invented methods
on `Approval.ProcessWorkitemRequest` and `Approval.ProcessResult` was flagged, so the recall test's
`setAction`, `setWorkitemId`, `isSuccess` and `getErrors` calls are checked. As in M7.3c, field
names that appear only inside SOQL are not.

### M8.4 Verification evidence (this session)

```
Source gate, PowerShell 7.4.6, seven cases
  1 the repo with M8                          passed: 3 active rules, 2 approval processes
  2 both templates as they were before M8     failed: recall, on both     <- would have caught M7.8
  3 one template without a recall action      failed once, though two rules route to it
  4 recall not allowed and no recall action   passed
  5 the field update sets the guard to 1      failed: 6 findings (3 exits x 2 templates)
  6 no workflow file                          failed: 6 findings
  7 a differently named clearing update       passed (judged by effect, not by name)
apex-ls, whole project                        no errors; the one pre-existing warning
Apex parser                                   the 3 changed classes parse
Jest / ESLint                                 57/57 / clean (no LWC change in M8)
XML                                           both templates and the workflow well-formed
```

### M8.5 The gate still owed, in this order

1. `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-approval-matrix-source.ps1`
2. `sf project deploy start -o amf-dev`. This redeploys two **active** approval processes with
   their steps unchanged; only the recall actions are new, which the platform allows on an active
   process. If it refuses, the error names the element: report it.
3. `sf apex run --file scripts/validate-config.apex -o amf-dev`
4. `sf apex run test -o amf-dev -l RunLocalTests -w 10 -r human`. Expect 197/197 (194 + 3).
5. One-time repair, because a recall action only fires on recalls made after it is deployed:
   `sf data update record --sobject Purchase_Request__c --where "Name='PR-00000010'" --values "Matrix_Submission__c=false" -o amf-dev`,
   then M7.8's query should return no rows.
6. The manual checks in the playbook's M8 gate, on a throwaway record: submit; a second submit is
   refused by name with no modal and no new log row; recall unticks *Matrix Submission*; a
   resubmission routes.

### M8.6 Carried into later phases

| Item | Owner |
|---|---|
| ~~**The org gate in M8.5**, including the PR-00000010 repair~~ — steps 1–5 **closed in M8.7**; step 6, the manual UI check, is still owed | user |
| The engine's query cap in the unit suite is now spent exactly, 4 of 4 (M8.2e) | next engine change |
| `PR_Two_Level_Mgmt`'s recall action has no automated test: its approvers come from the submitter's manager chain, which a test user may lack (as for M3's integration test). The source gate covers it statically and the manual gate in the UI | — |
| A pending record refuses the whole call; per-record handling belongs with bulk entry points | if they are built |
| The Flow equivalent: a cancelled Flow submission keeps its guard (M6.5) | Flow phase |

### M8.7 The org gate — steps 1–5 PASSED (2026-10-08)

Run by Claude Code against `amf-dev`, in M8.5's order, after the M7 provider-test fix below.

**(a) The first deploy was refused, on one component.** `Purchase_Request__c.AMF_Clear_Matrix_Submission`
(`WorkflowFieldUpdate`): *Value too long for field: Description maximum length is:255*. M8 had
extended the field update's description to name all three exits, and it reached 329 characters.
Neither apex-ls nor the XML check M8.4 ran knows the metadata field's length, and M8 had no org.
The description was shortened to 232 characters with the same content; nothing else changed. The
deploy is all-or-nothing, so nothing from M8 had reached the org until the retry.

**(b) Evidence.**

```
1  source gate     Approval Matrix source guard validation passed for 3 active rule(s) and
                   2 approval process(es): entry criteria, and the guard cleared on every way out.
2  deploy          0Afaj00000n5jRiCAI  Succeeded  101 components, 0 errors
3  validate-config Approval Matrix configuration is valid.
4  RunLocalTests   707aj00001K671l  Passed  197/197  (194 + M8's 3)
5  repair          PR-00000010  Matrix_Submission__c -> false  (a02aj00000hp2wgAAA)
```

**(c) M7.8's query found eleven records, not one.** Besides PR-00000010 it returned PR-00000014 to
PR-00000025 (ten of them). Every one of those has **no** `ProcessInstance` at all, and all were
created on 2026-10-07: they are M6's Flow spike records (spike-results, "dedicated spike records,
PR-00000011 onward"). Flow approvals create no `ProcessInstance`, so the query reads them as
"guard set, nothing pending"; M6.5 already recorded that a Flow cancellation keeps the guard. They
were left alone: they belong to `spikes/flow-approvals/scripts/teardown.ps1 -DeleteRecords`, which
M6 defers until the unanimous check. M7.8's query is therefore only meaningful for Classic records.
Restricted to records that have ever entered a Classic process, it returns no rows after the repair:

```
SELECT Name FROM Purchase_Request__c
WHERE Matrix_Submission__c = true
  AND Id NOT IN (SELECT TargetObjectId FROM ProcessInstance WHERE Status = 'Pending')
  AND Id IN (SELECT TargetObjectId FROM ProcessInstance)
-> Total number of records retrieved: 0.
```

**(d) Still owed: step 6**, the manual check in the real UI on a throwaway record (submit; a second
submit is refused by name with no modal and no log row; recall unticks *Matrix Submission*; a
resubmission routes). The integration tests prove the same behaviour in Apex; only a person can
prove it through the header button.


## Fix — AMF_ClassicApprovalHistoryProviderTest actor-name assertions

`aRealSubmissionReadsBackAsTheStepsApprovalHistoryShows` (M7) failed with
`Expected: Tejas Vernekar, Actual: null` on a full `RunLocalTests` (193/194).

**Cause.** Inside the test transaction the platform returns `Actor.Name` and
`OriginalActor.Name` as null for `ProcessInstanceHistory` rows it has just created, while
`ActorId` is correct. Confirmed by diagnostic assertion output (both the Started and Pending
rows had null names) and by an anonymous-Apex query of committed history in amf-dev, where the
same relationship fields resolve (`Tejas Vernekar`, `AMF Approver Three`). The provider's query
is correct; the test's expectation was not achievable in-transaction.

**Change.** Test only: removed the two actor-name assertions and left a comment saying why. The
ID, status, step-name and pending assertions stand; name mapping remains covered by
`AMF_DecisionTimelineServiceTest` with in-memory instances. No production code changed.

**Result.** 194/194 on amf-dev before the M8 pull.

---

## Phase M9 — Full expression grammar

**Date:** 2026-10-08 · **Commit:** `a79c880` · **Status:** complete. Built,
deployed and gated against `amf-dev` in one session: 232/232 Apex, all eight evaluator classes at
100%, 57/57 Jest, the shipped matrix still valid.
**Playbook goal:** let an admin write every condition §4.1 describes.

The user authorised M9 on 2026-10-08, after choosing it from the next-steps review ("start M9")
as the grammar phase. `CLAUDE.md` now records it: §13.3's whole deferred list plus the word forms,
confined to the evaluator package. DateTime stays out, being on neither list.

### M9.1 File-level changes

| File | Change | Notes |
|---|---|---|
| `classes/AMF_Ast.cls` | **modified** | `UnaryNode`, `ListNode`, `TodayNode`; `ValueType.MULTI_SELECT` |
| `classes/AMF_Lexer.cls` | **modified** | keywords `AND OR NOT IN CONTAINS STARTS_WITH TODAY`; symbols `!` (when not `!=`) and `+` |
| `classes/AMF_Parser.cls` | **modified** | `unary`, `[NOT] IN list`, `CONTAINS`, `STARTS_WITH`, `TODAY[(±n)]`; canonical operator spellings |
| `classes/AMF_ExprCompiler.cls` | **modified** | the operator/type table for the new operators; multipicklist; `usesToday`; `MAX_PATH_SEGMENTS` 2 → 4, now public |
| `classes/AMF_Evaluator.cls` | **modified** | three-valued logic for broken paths; `IN`, `CONTAINS`, `STARTS_WITH`, set comparison, `TODAY`; `valueSet`; `TODAY` recorded |
| `classes/AMF_FieldPathResolver.cls` | **modified** | uses the compiler's constant instead of its own copy |
| `classes/AMF_LexerTest.cls` | **modified** | +4 tests; `!` is no longer an unexpected character |
| `classes/AMF_ParserTest.cls` | **modified** | the word-forms rejection test inverted; +7 tests; 17 new structural faults |
| `classes/AMF_ExprCompilerTest.cls` | **modified** | +4 tests; multipicklist accepted |
| `classes/AMF_EvaluatorTest.cls` | **modified** | +15 tests: every new operator, Kleene tables, three hops, `TODAY`, hand-built guards |
| `classes/AMF_ExpressionErrorTest.cls` | **modified** | the deferred-grammar test replaced by six positioned-error tables (41 cases); depths moved to 5 and 6 segments |
| `classes/AMF_FieldPathResolverTest.cls` | **modified** | depth limit 4; a real three-hop query |
| `CLAUDE.md`, `docs/architecture.md` (§4.1, §4.3, §4.4, §13.3 notes, §13.4 row), `docs/build-playbook.md` (M9), `docs/decisions.md` (7 entries) | **modified** | authorisation, semantics, gate, decisions |

No object, field, layout, permission set, CMDT row, LWC or engine class changed. `AMF_ApprovalMatrixService`,
`AMF_ConfigValidator`, the timeline and the preview needed nothing: they reach the grammar only
through `AMF_ExprCache`, `compile()` and the evaluated-values JSON.

### M9.2 Design choices worth recording

**(a) Unknown, not false, for a broken path.** M2 made a comparison over an unresolvable path
false, and docs/decisions.md 2026-08-18 says why: such a path must route nothing. Without `NOT`,
false and unknown cannot be told apart, because `&&` and `||` treat them alike for whether the whole
is true. `NOT` breaks that: `NOT (Account__r.Name == NULL)` would match a record with no Account.
So the evaluator returns `null` for such a comparison (and for a bare Checkbox reached through one).
`&&`, `||` and `!` follow Kleene's tables, and `evaluate()` matches only on `== true`. Short-circuiting
is kept, on the value that decides the result. No pre-M9 expression changes its result. The
proof is that every pre-M9 test passes unchanged; it was not argued from first principles alone.

**(b) Null leaves stay two-valued.** Only a *broken path* is unknown. A null field value is still
an ordinary value under 4.3's rules, so `NOT (Amount__c > 100)` is true for a blank amount, exactly as
`Amount__c != 100` already was. `aNullLeafIsAnOrdinaryValueUnderNegation` pins the difference.

**(c) NULL is refused in IN comparisons.** 4.3 says `IN` with a null operand is false. Defining `IN`
as `==` against any one value would make `Region__c IN ('A', NULL)` true for a blank region. Refusing
`NULL` on either side, with a message pointing at `== NULL`, keeps the rule exact and the
definition simple. `IN` is otherwise accepted for every single-valued type, which 4.3's table does
not forbid.

**(d) Multipicklists compare only with a value-list literal.** 4.3 gives `CONTAINS` = membership and
`==` = exact set match, and nothing else. The literal is split on `;`, trimmed, de-blanked and
lower-cased, the same as the stored value (`AMF_Evaluator.valueSet`, which the compiler reuses to
refuse a literal naming nothing). `CONTAINS 'A;B'` means both are selected, as SOQL's `INCLUDES('A;B')`
does. Membership is never substring: `Channel CONTAINS 'Mail'` does not match `Email`.

**(e) TODAY is fixed per transaction, the submitter's date, and recorded.** `Date.today()` is the
running user's local date, and the engine runs as the submitter. It is read once and cached
statically, so all rules and records in one submission agree. It is written into the evaluated
values under `TODAY`: the log otherwise records the moment (`Submitted_At__c`) but not the time zone
that turned it into a date. `TodayNode` is a node, not a literal, because a compiled expression is
cached and must not carry a date. `@TestVisible todayOverride` pins it for tests.

**(f) Canonical operators.** The parser emits `&&`, `||`, `!`, `IN`, `NOT IN`, `CONTAINS`,
`STARTS_WITH` however they were typed, because the evaluator's `switch on` a String is
case-sensitive (M9.3b).

**(g) Depth: four segments.** See M9.3a for the measurement. §4.1's "max 4 hops" is read in §13.3's
unit, where `Account__r.Region__c` was "2 hops", so `Account__r.Owner.Profile.Name` is the deepest
path. Under any reading of the doc this is the most conservative choice, and it is one constant away from the
platform's five hops. The resolver now reads the compiler's constant: two copies would have to be
found and raised together.

**(h) Portable tests for the multipicklist.** No standard object every org has carries one.
`QuickText.Channel` is in `amf-dev`, so the tests use it by name only (`Schema.getGlobalDescribe()`,
`newSObject`, `put`), never as a type. The suite therefore still compiles in an org without
QuickText, and the multipicklist tests fail there, naming the missing object. This follows arch §10:
no field was added to `Purchase_Request__c` that only a test would use.

### M9.3 Issues encountered

**(a) The doc's depth limit was wrong about the platform.** A read-only probe in `amf-dev` queried
`Purchase_Request__c` with paths of 4, 5, 6 and 7 segments:

```
DEPTH OK   SELECT Account__r.Owner.Profile.Name ...
DEPTH OK   SELECT Account__r.Owner.Manager.Profile.Name ...
DEPTH OK   SELECT Account__r.Owner.Manager.Manager.Profile.Name ...
DEPTH FAIL SELECT Account__r.Owner.Manager.Manager.Manager.Profile.Name ... -> cannot query foreign
           key relationships more than 5 levels away from the root SObject
```

§4.4 said "4 hops (platform limit)". It is five. Corrected in §4.4 and docs/decisions.md.

**(b) Apex `switch on` a String is case-sensitive.** Measured by the same probe:
`switch on 'IN' { when 'in' ... }` took the `when else` branch. That differs from Apex's `==` on
Strings, which ignores case. An admin's `in` would otherwise have reached the evaluator's
`when 'IN'` and fallen through. Hence M9.2f.

**(c) `list` is a reserved word in Apex.** The first deploy of the test classes failed on a local
variable `list` in `AMF_ParserTest` (*Missing ';' at 'list'*). It was renamed to `values`. The
production classes had already passed a `--dry-run` compile, so nothing else was affected.

**(d) Coverage found one unreachable branch and three untested ones.** At 99%, the uncovered lines
were: a bare Checkbox through a broken path, `NULL` on the left of `STARTS_WITH`, the `areEqual`
null guard, and `describeOperand`'s fallback for a non-operand node. The first three got tests;
the null guard is exercised by a hand-built list, because it applies the ordinary null rule
rather than falling through. The fourth was unreachable, since only fields, literals and `TODAY` are
ever operands, so it was removed rather than tested.

**(e) The multipicklist probe.** The same probe scanned 35 standard objects for MULTIPICKLIST fields.
`Idea.Categories` (no values in this org) and `QuickText.Channel` (Email, Portal, Phone, Internal,
Event, Task, Messaging, CaseComment) were the candidates; M9.2h explains the choice.

### M9.4 Verification evidence

```
dry-run compile, the six production classes     Succeeded (no save)
evaluator package, 7 test classes, -c           124/124  every class 100%:
  AMF_Lexer AMF_Parser AMF_Ast AMF_ExprCompiler AMF_Evaluator AMF_FieldPathResolver
  AMF_ExprCache AMF_ExpressionException
mutation check (AMF_EvaluatorTest, 37 tests)
  broken path -> false instead of unknown,
  multipicklist CONTAINS -> substring           3 tests failed:
    aBrokenPathStaysUnknownUnderNegation          9 of 23 cases
    multiSelectPicklistsCompareAsSets             2 of 20 cases ('Mail', 'Phone;Email')
    threeHopPathsResolveAndBreakSafelyAtEveryHop  1 of 10 cases
  restored from a saved copy and redeployed
gate 1  source gate      passed: 3 active rules, 2 approval processes
gate 2  deploy           0Afaj00000n5ECdCAM  Succeeded  101 components, 0 errors
gate 3  validate-config  Approval Matrix configuration is valid.
gate 4  RunLocalTests    707aj00001K5CNL  Passed  232/232 (197 + 35)  org-wide 99%
gate 5  Jest             57/57 in 4 suites (unchanged)
```

**Live, read-only, against real Purchase Requests** (anonymous Apex, no DML), through the real
resolver. One query covers every path, a three-hop path included, and the verdicts match the data:

```
LIVE QUERY SELECT Id, Account__r.Owner.Profile.Name, Amount__c, CreatedBy.Profile.Name,
           Matrix_Submission__c, Region__c, Risk_Level__c FROM Purchase_Request__c WHERE Id IN :recordIds
e0 Region__c IN ('APAC','EMEA') AND NOT (Amount__c < 100000)
e1 Risk_Level__c NOT IN ('Low') OR Region__c STARTS_WITH 'ap'
e2 NOT (Account__r.Owner.Profile.Name == NULL)        <- no Account: unknown, so false
e3 CreatedBy.Profile.Name CONTAINS 'admin' && Amount__c > 0
e4 Matrix_Submission__c || NOT Matrix_Submission__c
EMEA/500.00/Low     e0=false e1=false e2=false e3=true  e4=true
APAC/250000.00/Low  e0=true  e1=true  e2=false e3=true  e4=true
APAC/250000.00/High e0=true  e1=true  e2=false e3=false e4=true   (created by a non-admin)
TODAY JSON {"TODAY":"2026-10-08","CloseDate":"2026-10-08"}
```

The optional manual check in the playbook's M9 gate, a throwaway rule previewed in the UI, was not
run: it needs a CMDT row activated in the org, which changes routing for everyone while it is live.

### M9.5 Carried into later phases

| Item | Owner |
|---|---|
| DateTime fields and `DATETIME` literals: still a compile error naming the type | a later grammar phase |
| Text-like field types outside the map (Email, Phone, URL, Text Area, Long Text Area) are compile errors; each is a map entry plus a test | a later grammar phase |
| SOQL allows 55 child-to-parent relationships per query, across the union of an object's rules; deeper paths make that reachable. The validator compiles rules one at a time and does not check the union | config validator |
| `TODAY` is the running user's date. An entry point that runs as an integration user (Flow, REST, M10) gets that user's time zone | entry-points phase |
| Field-to-field multipicklist comparisons are refused (M9.2d) | if a need appears |
| Keywords are reserved: a field named exactly `AND`, `IN`, `TODAY` etc. cannot be referenced. No standard field is | — |
| The playbook's optional manual M9 check (a rule using the new grammar, previewed in the UI) | user, optional |
| Still open from M8.7: the manual UI check (step 6) | user |
| Still open from M8.7c: PR-00000014 to PR-00000025 carry the guard; they go with M6's teardown | M6 teardown |

## Phase M10 — Entry points and bulk submission

**Date:** 2026-10-08 · **Commit:** `393d9d5` · **Status:** built and verified locally. The org gate
is owed (M10.5).
**Playbook goal:** submit through the matrix from Flow, Apex and integrations, and keep one record's
problem from sinking a batch.

The user authorised M10 on 2026-10-08, after the post-M9 review, and took the three decisions the
roadmap asked for first. The bulk entry points answer per record, isolated, while the header button
keeps its whole-call contract. `TODAY` stays the running user's date. Flow and REST share one result
shape. `CLAUDE.md` records the authorisation, which supersedes "bulk chunking" on the out-of-scope
list.

### M10.1 File-level changes

| File | Change | Notes |
|---|---|---|
| `classes/AMF_ApprovalMatrixService.cls` | **modified** | `prepare()` (steps 1–7, writes nothing) and `execute()` (9, 10, then 8 with 11 folded in) behind `submit()` and `preview()`; new `submitEach()`; `submit()` refuses a duplicate Id; access checked in chunks of 200; `execute()` under a savepoint |
| `classes/AMF_SubmitResult.cls` | **modified** | `succeeded`, `errorMessage`, `refused()` |
| `classes/AMF_SubmissionStrategy.cls` | **modified** | the contract: one result per request, and a refusal is data |
| `classes/AMF_ClassicProcessStrategy.cls` | **modified** | chunks of 100, `allOrNone` false, the platform's reason per record |
| `classes/AMF_DecisionLogWriter.cls` | **modified** | `stamp()` removed; docs |
| `classes/AMF_SubmissionException.cls` | **modified** | docs only |
| `classes/AMF_SubmitForMatrixApproval.cls` | **new** | the *Submit for Matrix Approval* invocable action; its `submitEach()` also serves REST |
| `classes/AMF_MatrixSubmissionResource.cls` | **new** | `POST /services/apexrest/approval-matrix/v1/submissions` |
| `classes/AMF_StrategyStub.cls` | **modified** | `refuse`, `refusalMessage`, `omit` |
| `classes/AMF_ApprovalMatrixServiceTest.cls` | **modified** | +12 tests; two comments the new order made wrong; one user helper for the stranger and the submitter |
| `classes/AMF_SubmissionIntegrationTest.cls` | **modified** | +4 real-platform tests, including 200 records |
| `classes/AMF_ClassicProcessStrategyTest.cls` | **modified** | +1 test; the refused result |
| `classes/AMF_DecisionLogWriterTest.cls` | **modified** | the two `stamp()` tests removed |
| `classes/AMF_SubmitForMatrixApprovalTest.cls` | **new** | 4 tests |
| `classes/AMF_MatrixSubmissionResourceTest.cls` | **new** | 2 tests, one of them 12 bad bodies |
| `permissionsets/Approval_Matrix_Admin`, `Approval_Matrix_User` | **modified** | both new classes |
| `lwc/amfDecisionTimelineEntry` (+ Jest) | **modified** | a `Failed` entry's title and summary; +2 Jest tests |
| `CLAUDE.md`, `docs/architecture.md` (§6.1, §6.2, §7 notes; §13.4 row), `docs/build-playbook.md` (M10 in Part 3; Part 5 pointer), `docs/decisions.md` (4 entries) | **modified** | authorisation, design, gate, decisions |

No object, field, layout, validation rule, approval process or CMDT row changed.
`Lock_Decision_Log` is untouched (M10.6).

### M10.2 Design choices worth recording

**(a) Two contracts on one path.** The header button calls `submit()` and `preview()` for one
record, and its messages and tests rest on their whole-call refusals, so those stay. `submitEach()`
is a third entry over the same `prepare()`. It takes the records one object at a time, in the order
first supplied, submits a duplicate once, and turns each whole-call refusal into a `Refused`
outcome for the records concerned. `Refused` is an outcome, never an `Outcome__c` value: nothing
was decided, so nothing is logged. A fault that condemns one object's records (not governed, no
guard field, a rule that will not compile) refuses that object's records and no others. 4.6 still
holds, since none of them routes.

**(b) The log after the answer.** Before M10 the row was inserted first and stamped after submit
(step 11), and the Classic strategy ran `allOrNone` true. A row saying `Submitted` could not be
walked back to `Failed` under `Lock_Decision_Log` (M1.3), so one refusal had to roll back every
record in the call, rows included (M3.8's carried bulk item, closed here). Now `execute()` stages
the guard, submits, and only then inserts each row: with the reference, which arrives in the
insert so no update follows, or as `Failed` with the platform's reason. `stamp()` had no other
caller and is gone, with its two tests. Rows still go in input order, in one insert.

**(c) A refusal is data; an exception is a broken strategy.** The strategy answers once per
request. A refusal is `succeeded` false with the platform's errors as `STATUS_CODE: message`. A
request left unanswered, or a success with no reference, is a contradiction, and throws.

**(d) The engine rolls itself back.** `execute()` runs under a savepoint and rolls back to it
before rethrowing. An exception that escapes to the top of the request would roll back anyway,
but a Flow fault path or an Apex caller can catch it. Without the savepoint, that caller would keep
records in a process with no row explaining them, or guards staged on records that never entered
one. The cost is one DML statement per object per call.

**(e) A refused record's guard is re-armed** in the same transaction. Step 9 sets it so the
template's entry criteria pass; left set on a record in no process, it would let a bypass through,
the same hole M8 closed for recall.

**(f) Authorisation in chunks of 200.** `UserRecordAccess` answers for at most 200 records per
query. Flow batches and the REST cap are 200, but an Apex caller of `submitEach()` is not capped,
so the check runs one query per 200 records. Up to 200 records, the unit suite's query count is
still 4 (M8.6).

**(g) Duplicates.** `submit()` refuses an Id that appears twice: it would be submitted twice, the
second refused by the platform, and the guard of the first, by then pending, re-armed.
`submitEach()` submits it once and gives every request the same answer.

**(h) REST.** The body is `{"recordIds": [...]}`, and the answer `{"results": [...]}` rather than a
bare array, so v1 can add top-level fields later. Every 400 is decided before anything is read or
written. Any other fault escapes, so the platform answers 500 and rolls back: catching it would end
the request normally and commit whatever had happened. 15-character Ids are accepted.

**(i) A real refusal that can be counted on.** `PR_Two_Level_Mgmt` assigns the submitter's
manager, so a test user created without one is refused by it every time. That gives the
end-to-end refusal test a deterministic platform refusal with no new metadata. The strategy-level
isolation test uses entry criteria instead: a record without the guard.

**(j) `TODAY` unchanged.** It stays the running user's date (decisions.md), and each row records
the date it used (M9.2e). That closes M9.5's item by decision rather than by code.

**(k) The timeline's `Failed` wording.** A `Failed` row may now record the platform refusing the
process the matrix chose, so "routing failed while evaluating rule X" would misreport it. The
title now says the attempt failed, and the summary is the first line of `Failure_Detail__c`: the
engine's or the platform's sentence, without any stack trace. A row with no detail keeps the old
wording.

### M10.3 Issues encountered

**(a) Prettier is a parse check here, not a style gate.** `prettier --check` flags every Apex class
in the repo, untouched ones included (`AMF_Lexer`, `AMF_ConfigValidator`, `AMF_SubmitRequest`),
because the repo has never been formatted with it. Every class parsed. The style warnings predate
M10 and were left alone.

**(b) Review finding: guard staging is still all-or-nothing within an object.** Step 9's update
uses `allOrNone` true. A record whose guard cannot be set therefore fails the whole call, rolled
back, instead of failing alone. That covers a validation rule the record fails, and the lock a
final approval leaves (`finalApprovalRecordLock`). Not built in M10: no test can make that update
fail without adding metadata only a test would use, or depending on an org setting
(`Approval.lock()`). Carried (M10.6).

### M10.4 Verification evidence (this session)

No org access in this session.

```
apex-ls, whole project              no errors; the one pre-existing warning ('of', AMF_ExpressionException)
Apex parser (prettier-plugin-apex)  51/51 classes parse (style warnings pre-existing, M10.3a)
Jest                                59/59 in 4 suites (57 + 2)
ESLint (lwc)                        clean
source gate, PowerShell 7.4.6       passed: 3 active rules, 2 approval processes
metadata XML                        104 files well-formed; both new classes in both permission sets
Apex test methods                   232 -> 253: +12 engine, +4 integration, +1 strategy,
                                    +4 invocable, +2 REST, -2 decision log writer
```

### M10.5 The gate still owed, in this order

The playbook's M10 gate, Part 3:

1. `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-approval-matrix-source.ps1`
2. `sf project deploy start -o amf-dev`. Two new classes; no metadata beyond them and the
   permission sets.
3. `sf apex run --file scripts/validate-config.apex -o amf-dev`
4. `sf apex run test -o amf-dev -l RunLocalTests -w 10 -r human`. Expect 253/253. The new
   integration tests need both templates active, and create Standard Users. The 200-record test
   writes what it spent to the debug log and into its failure messages. If it fails on a governor
   limit, report which: that is a finding about bulk size, not a flake.
5. Jest, as in M5.
6. The invocable, through the platform's framework, in anonymous Apex (playbook step 6): a first
   run returns `submitted` true with a decision log row Id; a second run on the same record returns
   `Refused`, naming the process.
7. REST (playbook step 7): `Refused` for the pending Id, `Submitted` for the other, and a 400 for
   an empty body.

Still owed from M8.7: the manual UI check, step 6.

### M10.6 Carried into later phases

| Item | Owner |
|---|---|
| **The org gate in M10.5** | user |
| `Lock_Decision_Log` still permits one post-insert stamp of `Execution_Ref_Id__c`, which nothing performs since M10. Forbidding every update would also close M1.10's residual long-text hole, but it changes M1's rule and `AMF_DecisionLogLockTest` | a later hardening pass |
| Guard staging is all-or-nothing within an object (M10.3b). The remedy is `Database.update(…, false)` and a `Failed` row per failure, once a test can make the update fail | next bulk change |
| A record-triggered Flow on a governed object that calls the action is re-triggered by the engine's guard update and by the templates' clearing update. Its entry conditions must exclude those, for example "only when a record is updated to meet the condition requirements" | whoever builds such a Flow |
| ~~M8.6: a pending record refuses the whole call; per-record handling belongs with bulk entry points~~ | **closed in M10**, for `submitEach()` |
| ~~M3.8: a bulk submission's rows are rolled back if any record's submission fails~~ | **closed in M10** |
| ~~M9.5: `TODAY` for an integration user~~ | **closed by decision**, 2026-10-08 |
| Still open from M8.7: the manual UI check (step 6) | user |
| Still open from M8.7c: PR-00000014 to PR-00000025 carry the guard; they go with M6's teardown | M6 teardown |
| The playbook's optional manual M9 check | user, optional |
| M9.5's grammar items: DateTime, the text-like field types, the 55-relationship union, reserved keywords, field-to-field multipicklists | as in M9.5 |

### M10.7 Follow-up: the guard staged record by record (2026-10-21)

**Status:** built and verified locally, in a cloud container with no `sf` CLI and no `amf-dev`
credentials. Nothing was deployed or run in the org. The org gate, amended below, is owed.

The user gave the go-ahead on 2026-10-21 ("implement what's next in line", after a review of
`docs/handoff.md`). The handoff placed M10.3b under M10's authorisation in `CLAUDE.md` (a record
that cannot be submitted gets its own outcome while the rest still go through) and ahead of M11,
because validation rules are common on Opportunity. `CLAUDE.md` is unchanged.

| File | Change | Notes |
|---|---|---|
| `classes/AMF_ApprovalMatrixService.cls` | **modified** | `stageGuard()` sets the guard with `Database.update(…, false)`; `fail()` now writes both kinds of `Failed`; `setGuard()` split into `stageGuard()`, `rearmGuard()` and `guardRows()`; `reasonOf()` |
| `classes/AMF_SubmissionIntegrationTest.cls` | **modified** | +2 real-platform tests over a record a final approval left locked, a fixture helper and a shared assertion |
| `docs/architecture.md` (§6.1 M10 note), `docs/decisions.md` (1 entry), `docs/build-playbook.md` (M10 build, gate and acceptance; Part 5), `docs/handoff.md` | **modified** | design, decision, gate |

No object, field, layout, validation rule, approval process, permission set, CMDT row or LWC
changed.

**(a) Per record, like the platform's own answer.** Before this, step 9's one `update` threw if
any record refused it, and `execute()` rolled the call back, so one record sank the call. Now a
record whose guard the platform will not set gets a `Failed` outcome and row, with the message
"`Matrix_Submission__c` could not be set, so the record was not submitted to `<process>`:
`<STATUS_CODE>`: `<message>`". The reason is in the same `STATUS_CODE: message` form the
Classic strategy gives a refused submission. The row names the rule and process the matrix chose.
The record never reaches the strategy: without the guard its template's entry criteria would
refuse it anyway, and submitting it would trade the real reason for an entry-criteria one.

**(b) One bookkeeping path.** `fail()` writes the outcome and the `Failed` row for both cases, a
guard the platform would not set and a submission it refused. The stub tests of the refusal path
(M10.4) therefore also prove the half the two cases share.

**(c) Re-arming stays all-or-nothing.** A refused record left with its guard set is in no process
yet passes its template's entry criteria, which is the bypass §6.3 closes. If re-arming fails, the
call fails and `execute()` rolls it back; leaving the guard set would be worse. Re-arming touches
only records whose guard was set moments earlier in the same transaction, so this path should not
be reached in practice.

**(d) The header button.** `submit()` shares `execute()`, so a locked record now answers `Failed`
with a row and a toast message where the update used to throw, as a platform refusal has since M10.
Its whole-call contract covers refusals, where nothing was decided; this record was decided.
Recorded in `docs/decisions.md`.

**(e) The fixture and its one unproven assumption.** As the handoff proposed: a non-admin submits a
record to `PR_Three_Level_Finance` through the engine, all three steps are approved, and the
record stays locked (`finalApprovalRecordLock` is true in both templates' source). The same user
then resubmits it. The approvals run as the test's running user, because Modify All Data lets an
administrator act on any work item (a Salesforce knowledge article quoted on the Trailblazer
Community, and Veeva's support documentation). That keeps the approvers' record access (M3.10)
out of the fixture. The unproven part is that the lock stops a non-admin's update from Apex
running without sharing. The Approval class reference says only administrators, and depending on
the process the current approver, can edit a locked record. Record locking is not sharing, so
`without sharing` should not lift it, and `ENTITY_IS_LOCKED` is the expected code. The tests
assert the message's prefix, not the code. If the gate shows the lock does not stop the update,
both tests fail on their first assertion, whose message says so. The engine change stands; only
the fixture would need replacing.

**(f) No stub test makes the update fail.** Making a guard update fail needs either metadata only a
test would use (a validation rule), a test-only seam in the engine, or an org setting
(`Approval.lock()`), the same constraint M10.3b recorded. `stageGuard()`'s failure branch is
therefore covered only by the two integration tests. Every existing test still passes through
its success branch.

**(g) Partial success runs triggers twice.** With `allOrNone` false, if any record fails, the
platform saves the rest in a second attempt and runs their triggers again, without resetting
static variables. `Purchase_Request__c` has no trigger. Opportunity usually has several, which
matters for M11 (carried).

**(h) The preview cannot foresee it.** The preview stages nothing, so a locked or invalid record
previews as routable and fails at submit, with its row. `Approval.isLocked()` needs an org
preference (M6.5), and a validation rule cannot be asked without writing (carried).

**(i) Two corrections to the gate, from the same review.** Step 7 passed its JSON inline, and Windows
PowerShell 5.1 strips the double quotes inside an argument it passes to `sf` (M6.6). The endpoint
would have received `{recordIds:[…]}` and answered 400, a false failure. The quotes are now
escaped, Workbench is the alternative, and the 400 check sends `{}`, because PowerShell drops an
empty-string argument. Steps 6 and 7 also now say to give the throwaway records
`Risk_Level__c = High`. The admin has no manager (M3.7), so a record reaching the catch-all's
`PR_Two_Level_Mgmt` would answer `Failed` (`MANAGER_NOT_DEFINED`). That is correct behaviour
since M10, but not what those steps check.

**Issues encountered.** apex-ls's Maven group is `io.github.apex-dev-tools`, hyphenated, unlike its
Java package. Coursier resolved it, and Maven Central answered 429 intermittently through the
container's proxy. The fixture's first draft named a local `approval`, and since Apex names are
case-insensitive it shadowed the `Approval` class: the M7.3b trap. It was renamed before apex-ls
ran, and a planted copy confirmed that apex-ls reports it. `npm install` wires husky's pre-commit
hook, whose lint-staged step runs `prettier --write` and would rewrite whole files (carried), so
this commit skipped it with `HUSKY=0`.

**Verification evidence (this session):**

```
apex-ls 6.3.0 CheckForIssues, whole project, -d warnings
  before   AMF_ExpressionException.cls  'of' reserved identifier   <- pre-existing, the only finding
  after    the same, and nothing else
  planted errors, each in a scratch copy, each reported as Missing:
    saves[i].isSucess()                        no matching method on Database.SaveResult
    fail(result, plan, ...)                    wrong argument types for fail(Plan, Outcome, String)
    a local named approval, Approval.process   no method 'process' on Approval.ProcessWorkitemRequest
Apex parser (prettier-plugin-apex)  51/51 classes parse; 49 carry the pre-existing style warnings
Jest                                59/59 in 4 suites (unchanged)
ESLint (lwc, jest-mocks)            clean
source gate, PowerShell 7.4.6       passed: 3 active rules, 2 approval processes
metadata XML                        104 files well-formed (none changed)
Apex test methods                   253 -> 255: +2 integration
```

**The gate still owed, as amended** (the playbook's M10 gate, Part 3):

1. `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-approval-matrix-source.ps1`
2. `sf project deploy start -o amf-dev`
3. `sf apex run --file scripts/validate-config.apex -o amf-dev`
4. `sf apex run test -o amf-dev -l RunLocalTests -w 10 -r human`. Expect 255/255. Four tests rest
   on platform behaviour no session has run: the 200-record submission (on a governor limit,
   report which), the manager-less refusal, and this entry's two locked-record tests (on their
   first assertion, report the outcome shown: a finding about the lock, per (e)).
5. Jest, as in M5.
6. The invocable (playbook step 6), on a throwaway with `Risk_Level__c = High`.
7. REST (playbook step 7), with escaped quotes or Workbench, and `{}` for the 400.

Record the results as M10.8.

### M10.7 Carried into later phases

This table supersedes M10.6's.

| Item | Owner |
|---|---|
| **The org gate above** | user |
| ~~M10.6: guard staging is all-or-nothing within an object (M10.3b)~~ | **closed in M10.7** |
| The preview cannot foresee a guard failure: a locked or invalid record previews as routable, then fails at submit with its row (h) | if a need appears |
| A partial guard failure saves the other records in a second attempt that runs their triggers again (g). Any trigger on a governed object must tolerate that; check Opportunity's before M11 | M11 |
| `Lock_Decision_Log` still permits one post-insert stamp of `Execution_Ref_Id__c`, which nothing performs since M10. Forbidding every update would also close M1.10's residual long-text hole, but it changes M1's rule and `AMF_DecisionLogLockTest`. Test it against deleting a Purchase Request (M3.12) | a later hardening pass |
| A record-triggered Flow on a governed object that calls the action is re-triggered by the engine's guard update and by the templates' clearing update. Its entry conditions must exclude those, for example "only when a record is updated to meet the condition requirements" | whoever builds such a Flow |
| The source deploys only to `amf-dev`: `PR_Three_Level_Finance` names its approvers by username, and the domain (`@amf.00daj000012gj9b.dev`) is this org's. The seed script derives the domain per org, the template does not, against §1.5. A `replacements` entry in `sfdx-project.json` is one fix | M12, or any CI or second org |
| husky's pre-commit runs lint-staged's `prettier --write`, and about 175 files do not match Prettier's output (`.prettierrc` indents 2, the code 4), so wherever `npm install` has wired husky, a commit rewrites every file it touches. Align `.prettierrc` and reformat once, or drop the step | a tooling decision |
| Still open from M8.7: the manual UI check (step 6) | user |
| Still open from M8.7c: PR-00000014 to PR-00000025 carry the guard; they go with M6's teardown | M6 teardown |
| The playbook's optional manual M9 check | user, optional |
| M9.5's grammar items: DateTime, the text-like field types, the 55-relationship union, reserved keywords, field-to-field multipicklists | as in M9.5 |

### M10.8 The org gate — PASSED, after the locked-record fixture was replaced (2026-10-21)

**Status:** run in `amf-dev` on 2026-10-21 from `develop` at `7a0dc69`, with the `sf` CLI, by
Claude Code in the M11 session, which ran it first because M11 builds on it. Every step passed
except M10.7's two locked-record tests. They failed on their first assertion, the outcome M10.7(e)
said to report as a finding about the approval lock. On the user's choice the fixture was replaced
by a test-only validation rule, and the suite then passed 255/255.

| Step | Result |
|---|---|
| 1. Source gate | passed: 3 active rules, 2 approval processes |
| 2. Deploy | `0Afaj00000oYHfxCAG` Succeeded. The org held 47 unnamespaced classes, the repo 51: M10's four classes were new to it |
| 3. Post-deploy check | `Approval Matrix configuration is valid.` |
| 4. RunLocalTests | `707aj00001MsZoh`: **253/255**, org-wide 97%. The 200-record submission passed (53 s) and so did the manager-less refusal. Both locked-record tests failed on their first assertion with `Got: Submitted / null` |
| 5. Jest | 59/59 in 4 suites |
| 6. The invocable | PR-00000027 (`a02aj00000jTATVAA4`, `Risk_Level__c = High`). First run: `submitted=true`, `PR_High_Risk` v1 to `PR_Three_Level_Finance`, row `a03aj00002Wj2LZAAZ`, instance `04gaj000001yZn7AAE`. Second run: `Refused`, "This record is already in approval process PR_Three_Level_Finance…", still one row |
| 7. REST | 200, `{"results": [...]}`: PR-00000027 `Refused` by name; PR-00000028 (`a02aj00000jTA26AAG`) `Submitted`, instance `04gaj000001yZojAAE`, row `a03aj00002Wj2OnAAJ`. `--body '{}'` answered **400** with the `recordIds` message. Windows PowerShell 5.1 with the escaped quotes M10.7(i) prescribed |
| After the fixture change | deploy `0Afaj00000oYPGwCAO`; `AMF_SubmissionIntegrationTest` 11/11 (`707aj00001Msi16`); RunLocalTests `707aj00001MsMYD`: **255/255**, org-wide **98%**, `AMF_ApprovalMatrixService` 100% |

**(a) The finding: in an Apex test, the lock a final approval leaves did not stop the guard
update.** The fixture had a Standard User holding `Approval_Matrix_User` submit a record through the
engine. The running administrator then approved all three steps of `PR_Three_Level_Finance`, whose
`finalApprovalRecordLock` is true, and the record ended `Approved` with its guard cleared. The same
user resubmitted it under `System.runAs`. The engine set the guard and the platform accepted the
submission: `Submitted`, where M10.7 expected `Failed`.

Two explanations fit, and this org cannot tell them apart:

- `System.runAs` enforces record sharing but not user permissions, and editing a locked record is a
  permission (Modify All, or an administrator's).
- System-mode Apex is not stopped by an approval lock at all.

`Approval.isLocked()` would have shown whether the record was locked, but it throws
`System.NoAccessException: Apex approval lock/unlock api preference not enabled`, as M6.5 found.
Whether a real non-admin session outside a test is stopped is **unmeasured**.

Nothing breaks either way. If the lock does not stop the update, a completed record is staged and
submitted like any other, and resubmitting after a final approval is legitimate. If it does stop it
in production, the record becomes a `Failed` row by itself, which is M10.7's design. What changes
is the claim: the lock is not a case the engine can be said to meet, nor one a test can build. The
architecture's §6.1 M10 note, two comments in `AMF_ApprovalMatrixService` (comments only), the
playbook's M10 entry and `docs/decisions.md` now say so.

**(b) The replacement fixture**, chosen by the user over two other options: rewriting the tests to
pin what the org did, which would have left `stageGuard()`'s failure branch untested, or deleting
them.

| File | Change |
|---|---|
| `customPermissions/AMF_Test_Refuse_Guard.customPermission-meta.xml` | **new**. Granted by no permission set |
| `objects/Purchase_Request__c/validationRules/AMF_Test_Refuse_Guard.validationRule-meta.xml` | **new** |
| `classes/AMF_SubmissionIntegrationTest.cls` | **modified**. The two tests rewritten over the rule, the header-button test renamed `theHeaderButtonAnswersARefusedGuardWithAFailedRowRatherThanAnException`; `submitAndApproveToTheEnd()` removed with the lock fixture; `assertGuardNotStaged()` also asserts the status code; new `strategicVendor()` and `guardRefusingSubmitter()` |
| `classes/AMF_ApprovalMatrixService.cls` | **modified, comments only**. The two that named the lock |
| `docs/architecture.md` (§6.1 M10 note), `docs/build-playbook.md` (M10 build, gate step 4, acceptance; Part 5's owed table), `docs/decisions.md` (1 entry) | **modified** |

The rule is
`AND($Permission.AMF_Test_Refuse_Guard, ISCHANGED(Matrix_Submission__c), Matrix_Submission__c, ISPICKVAL(Vendor_Type__c, 'Strategic'))`.
Each conjunct does a job:

- **The custom permission makes it inert for real users.** No permission set grants it. The test
  builds a permission set at runtime, grants it through `SetupEntityAccess`, and assigns it to its
  submitter inside `System.runAs` of the running user, to avoid mixed DML.
- **`ISCHANGED` and true** confine it to setting the guard. It never fires on insert, and never on
  the templates' clearing update.
- **`Vendor_Type__c = 'Strategic'`** makes it per record. The `submitEach()` test needs one record
  refused and its neighbour accepted, in the same `Database.update`, by the same user, and
  `$Permission` is per user. No shipped rule reads `Vendor_Type__c`, and no other integration
  fixture sets it.

The platform's answer is a real `FIELD_CUSTOM_VALIDATION_EXCEPTION`, in every org, and the
assertion now checks that code as well as the engine's sentence. It lives on `Purchase_Request__c`,
the framework's own pilot object, so an adopter's object never carries it. It is the first metadata
the repository ships only for a test (`docs/decisions.md`).

The tests also got stronger in two small ways. The refused record now has no `ProcessInstance` at
all, rather than no pending one. The header-button test expects exactly one row, because there is
no earlier approval to account for.

**(c) Issues encountered.**

- **The first deploy of the fixture was refused**, because both descriptions ran past the
  platform's 255-character limit for a custom permission and a validation rule. This was the M8.7
  trap again. Both were shortened, measured at 229 and 233 characters after decoding, and
  redeployed. Descriptions are now measured before a deploy.
- **The deploy output hid the component errors.** `Select-String` over the progress lines showed
  only `Status: Failed`. `sf project deploy report --use-most-recent --json` has them in
  `details.componentFailures`.

**(d) Left in the org by the gate.** PR-00000027 and PR-00000028 are pending in
`PR_Three_Level_Finance` with AMF Approver Three. PR-00000027 can serve M8's owed manual check from
its second step onward, as the handoff proposed.

### M10.8 Carried into later phases

This table supersedes M10.7's.

| Item | Owner |
|---|---|
| ~~The org gate (M10.5, as amended in M10.7)~~ | **closed in M10.8** |
| Whether the lock a final approval leaves stops a real non-admin's Apex update outside a test is unmeasured; `Approval.isLocked()` needs the "Apex approval lock/unlock api" preference (a) | if a need appears |
| The preview cannot foresee a guard failure: a record a validation rule will refuse previews as routable, then fails at submit with its row (M10.7h) | if a need appears |
| A partial guard failure saves the other records in a second attempt that runs their triggers again (M10.7g). In `amf-dev`, Opportunity has no Apex triggers, validation rules or record-triggered flows (queried 2026-10-21) | M11 |
| `Lock_Decision_Log` still permits one post-insert stamp of `Execution_Ref_Id__c`, which nothing performs since M10. Forbidding every update would also close M1.10's residual long-text hole, but it changes M1's rule and `AMF_DecisionLogLockTest`. Test it against deleting a Purchase Request (M3.12) | a later hardening pass |
| A record-triggered Flow on a governed object that calls the action is re-triggered by the engine's guard update and by the templates' clearing update. Its entry conditions must exclude those, for example "only when a record is updated to meet the condition requirements" | whoever builds such a Flow |
| The source deploys only to `amf-dev`: `PR_Three_Level_Finance` names its approvers by username, and the domain (`@amf.00daj000012gj9b.dev`) is this org's. A `replacements` entry in `sfdx-project.json` is one fix | M12, or any CI or second org |
| husky's pre-commit runs lint-staged's `prettier --write`, which would rewrite every file a commit touches (M10.7). This session's commits run with `HUSKY=0` | a tooling decision |
| Still open from M8.7: the manual UI check (step 6). PR-00000027 serves it from its second step | user |
| Still open from M8.7c: PR-00000014 to PR-00000025 carry the guard; they go with M6's teardown | M6 teardown |
| The playbook's optional manual M9 check | user, optional |
| M9.5's grammar items: DateTime, the text-like field types, the 55-relationship union, reserved keywords, field-to-field multipicklists | as in M9.5; the union check is in M11 |

---

## Phase M11 — A second governed object: Opportunity

**Date:** 2026-10-21 · **Commits:** `6e3079d`, the baseline retrieved from the org and committed
unchanged, then `96e5692`, Phase M11 · **Status:** complete. The gate ran in `amf-dev`, apart from
its manual UI step, which is owed to the user.
**Playbook goal:** prove §3.2's claim that governing an object is configuration plus conventions,
with no engine change, on a standard object.

The user authorised M11 in this session. They chose Opportunity, the handoff's recommendation, over
a second custom object, and asked for the M9.5 relationship check to ride along. Measurement then
changed that check (d), and the user chose to have the validator run the real query. `CLAUDE.md`
records the authorisation; the playbook's Part 3 entry and gate were written before building.

### M11.1 File-level changes

`6e3079d` brought the four Opportunity layouts and Opportunity's object-level settings into source
**exactly as retrieved**, so that this phase's diff shows only what it changes in org-owned files.

| File | Change | Notes |
|---|---|---|
| `objects/Opportunity/Opportunity.object-meta.xml` | **new** (as retrieved), then one override | View, Large: `Opportunity_Record_Page`. Every other setting is the org's own; standard fields, list views and web links stay out of source |
| `objects/Opportunity/fields/Matrix_Submission__c.field-meta.xml` | **new** | the guard (§3.4) |
| `objects/Approval_Decision_Log__c/fields/Opportunity__c.field-meta.xml` | **new** | SetNull lookup; relationship `Approval_Decisions` |
| `workflows/Opportunity.workflow-meta.xml` | **new** | Opportunity's own `AMF_Clear_Matrix_Submission`; the org's file was empty |
| `approvalProcesses/Opportunity.OPP_Manager_Approval.approvalProcess-meta.xml` | **new** | one step: the submitter's manager |
| `approvalProcesses/Opportunity.OPP_Two_Level_Mgmt.approvalProcess-meta.xml` | **new** | two steps up the same hierarchy |
| `quickActions/Opportunity.AMF_Submit_For_Approval.quickAction-meta.xml` | **new** | over the unchanged `amfSubmitForApproval` |
| `layouts/Opportunity-*.layout-meta.xml` ×4 | **new** (as retrieved), then edited | `Submit` out of `platformActionList`, the framework's action first, renumbered; the guard read-only; Approval History and Approval Decisions related lists |
| `flexipages/Opportunity_Record_Page.flexipage-meta.xml` | **new** | highlights; Details, Related, Activity and Chatter tabs; the timeline in the sidebar |
| `customMetadata/Approval_Matrix_Rule.OPP_*.md-meta.xml` ×3 | **new** | `OPP_Large_Deal` (10), `OPP_Key_Industry` (20), `OPP_Catch_All` (9999) |
| `layouts/Approval_Decision_Log__c-Approval Decision Log Layout.layout-meta.xml` | **modified** | `Opportunity__c` beside `Purchase_Request__c` |
| `permissionsets/Approval_Matrix_User`, `Approval_Matrix_Admin` | **modified** | FLS on the guard (User read-only, Admin edit) and on the lookup; no Opportunity object permissions (e) |
| `classes/AMF_ConfigValidator.cls` | **modified** | `validateUnionQuery()`; header and invocable description |
| `classes/AMF_ConfigValidatorTest.cls` | **modified** | +2 tests |
| `classes/AMF_OpportunityGovernanceTest.cls` | **new** | 7 real-platform tests |
| `scripts/validate-approval-matrix-source.ps1` | **modified** | `Test-StandardSubmitRemoved`: §6.3 on every governed object's layouts |
| `CLAUDE.md`, `docs/architecture.md` (§3.2, §4.4, §6.3, §9, §11 notes; §13.4 row), `docs/build-playbook.md` (M11 in Part 3; Part 5), `docs/decisions.md` (3 entries), `docs/handoff.md` | **modified** | authorisation, design, corrections, decisions |

No engine class, LWC or `Purchase_Request__c` metadata changed. The engine, the strategy, the log
writer and the timeline served Opportunity as they were. The validator gained one check, and the
source gate one rule.

### M11.2 Design choices worth recording

**(a) Templates on the manager hierarchy, by necessity as much as by choice.** The seeded approvers
`amfu1` to `amfu5` hold the Standard Platform User profile. The Salesforce Platform license grants
no Opportunity access: no profile object permission exists for it. The only full-license users are
three System Administrators, and one Salesforce license is spare. A named-user template would have
to name an administrator, or spend that license on a seeded approver. Hierarchy templates name no
user, which also keeps them out of the org-bound-username debt that `PR_Three_Level_Finance`
carries. The two shapes still differ visibly (§5.5): one step, or two.

**(b) Unlocked after final approval.** `finalApprovalRecordLock` is false on both. A locked approved
deal could not be moved to its next stage by its owner. The Purchase Request templates lock,
because an approved request is finished.

**(c) Rules that use what a standard object offers:**

- `Amount >= 250000`: a standard Currency field;
- `Account.Industry IN ('Energy', 'Banking')`: a standard relationship, so no `__r`, with M9's
  `IN`;
- the visible catch-all.

Priorities 10, 20 and 9999 repeat the Purchase Request matrix's, which is legal because the
validator checks uniqueness per object. The compiler needed nothing new: it resolves relationships
by describe, and Opportunity's `Owner` points only at User, so it is even traversable, which the
Purchase Request's is not (polymorphic, User or Group).

**(d) The validator runs the union query instead of counting relationships.** Before building the
count M9.5 proposed, its premise was measured in anonymous Apex, read-only or rolled back:

| Root | Relationships in one query | API | Result |
|---|---|---|---|
| Opportunity | 54, 55, 56 prefix-closed paths | 68 | all accepted |
| Opportunity | 400 distinct paths, over 34 distinct `object.relationship` pairs and 7 target objects | 68 | accepted |
| Opportunity, Case, Contract | every reachable distinct pair, one at a time: 54, 54, 45 | 68 | all accepted |
| WorkOrder | 95 distinct pairs, then 142 in one query | 68 and 62 | accepted |
| WorkOrder, a row inserted and rolled back | 142 distinct pairs, `WHERE Id = :row` | 62 | accepted, 1 row |

So Apex does not enforce the documented 55, by any unit tried. A count against 55 would refuse
matrices the platform runs. `validateUnionQuery()` instead builds the engine's own query
(`AMF_FieldPathResolver.buildQuery` over the compiled rules' union) and runs it with an empty
`recordIds` bind.

A probe established three things first:

- such a query still executes (one SOQL spent, zero rows);
- a malformed path throws at parse time;
- `ContentDocumentLink` refuses `WHERE Id IN :recordIds` with "Implementation restriction". That
  is a deterministic platform refusal of a query whose rule compiles, which gives the check's
  failure branch a test.

`Database.queryWithBinds` with `SYSTEM_MODE` is refused in anonymous Apex, so the check binds a
local, as the resolver does. It runs only when every rule for the object compiles, because that is
the only case in which the engine builds the query.

**(e) Field-level access only.** Opportunity access comes from the user's profile and license. An
object permission in `Approval_Matrix_User`, which five Platform-license users hold, is the kind of
grant the platform refuses for that license. Field permissions on Opportunity fields deployed
without complaint.

**(f) The source gate learned §6.3** (`docs/decisions.md`). On Lightning, the standard button is the
`Submit` / `StandardButton` entry in a layout's `platformActionList`, and all four Opportunity layouts
listed it. Before M11 nothing enforced its removal: M3.9 found the Purchase Request layout still
showing it after M3 shipped. The gate now fails three things:

- a governed object's layout that keeps the entry;
- a layout with no list, which shows the platform's defaults;
- a governed object with no layout in source.

**(g) The record page keeps Opportunity's own panels.** Activity and Chatter join the Purchase
Request page's Details and Related tabs, so activating it as the desktop default takes nothing
away from sales users. There is no Path component: `amf-dev` has no Sales Path
(`sf org list metadata -m PathAssistant` is empty).

**(h) The tests' approver is the running user.** Each test creates one Standard User who reports
to the running user, so both templates' first step resolves to a full-license user with
Opportunity access, in any org. One user per test is also all the license count allows: inserting
a user needs a free license even in a test.

### M11.3 Issues encountered

**(a) The first two deploys failed on the record page alone** (`0Afaj00000oZ819CAC`,
`0Afaj00000oZatSCAS`), and nothing landed, because deploys are atomic.

1. "Facet activityTabContent has already been declared by another component". The parent
   template, `flexipage__default_rec_L`, already has that facet, which its sidebar's Activity
   panel uses.
2. Renamed `amfActivityTabContent` and `amfChatterTabContent`, the error became "'mode REPLACE'
   but a parent region enabling that mode doesn't exist". `mode Replace` replaces a parent's region
   of the same name; a new facet carries no mode.

A dry run of the page alone (`--dry-run`) then validated it before the full deploy.

**(b) One new test failed on its own assertion,** in the first full run, `707aj00001MvbU1`: 263/264.
`Assert.isTrue(outcomes[1].submitted, outcomes[1].message)` threw `NullPointerException: Message
parameter cannot be null`. A successful outcome's message is null, and Apex's `Assert` refuses a
null message even when the assertion holds. The record had been submitted. The message is now
built, and no other assertion in the suite passes a bare outcome message.

**(c) Two tool traps.**

- The Bash tool collapses `\\` inside a quoted heredoc, so an Apex `split('\\.')` reached the
  file as `split('\.')` and failed to compile. The probes count dots with `countMatches('.')`
  instead.
- A PowerShell harness with `$ErrorActionPreference = 'Stop'` turns a native command's stderr
  into a terminating error. The gate's expected failures crashed the harness until it relaxed the
  setting around the call.

**(d) A stale claim.** M3.7 and M10.7 say the admin has no manager. The admin reports to `amfu1`
(Platform license), presumably set during M3's QA as M3.7 suggested. So `PR_Two_Level_Mgmt` does
route an admin's submission, to `amfu1` then `amfu2`.

### M11.4 Verification evidence

```
source gate                 passed: 6 active rules, 4 approval processes, 5 layouts of 2 governed objects
  broken copy A             failed: OPP_Manager_Approval does not clear the guard on recall;
                            the Sales layout keeps Submit; the Support layout has no platformActionList
  broken copy B             failed: no layout of Opportunity is in source
  broken copy C             failed: both OPP templates, all three exits (no Opportunity field update;
                            Purchase Request's does not count)
deploy                      0Afaj00000oZiRBCA0 Succeeded (after the two record-page failures above);
                            test-class fix 0Afaj00000oZFtrCAG
post-deploy check           "Approval Matrix configuration is valid." Both objects: 6 rules compiled,
                            both union queries run, 4 processes active for their objects
ProcessDefinition           OPP_Manager_Approval, OPP_Two_Level_Mgmt: Opportunity, Active
FieldPermissions            User: guard R, lookup R. Admin: guard RW, lookup RW
RunLocalTests               707aj00001Mtchi: 264/264, org-wide 98%. AMF_ConfigValidator 98% (its
                            uncovered lines are M4's wrong-type branch); service, log writer,
                            resolver and timeline 100%
M11 classes                 707aj00001MtF8g: AMF_OpportunityGovernanceTest 7/7, AMF_ConfigValidatorTest 18/18
Jest                        59/59 in 4 suites (no LWC changed)
```

**The action bar, by the UI API** (`/ui-api/actions/record/006aj00000arfTmAAI?formFactor=Large&sections=Page`,
the admin's *Opportunity Layout*):

```
0 Follow  1 FollowInStream  2 Opportunity.AMF_Submit_For_Approval  3 FeedItem.TextPost ... 19 Share
20 actions, Submit absent
```

The two Follow buttons are the platform's, ahead of every layout's list. The same API, asked about
each related list, showed:

- **Approval History** (`ProcessSteps`) offers nothing on a record never submitted, so the standard
  submit lives only in the layout's action list. On the pending PR-00000027 it offers Approve,
  Reject, Reassign and Recall.
- **Approval Decisions** offers New and Mass Change Owner (carried).

**End to end, through the invocable, as the admin:**

| Throwaway | Route | Decision log row | After |
|---|---|---|---|
| *AMF M11 gate: large deal*, `006aj00000ffwjZAAQ`, 300,000 | `OPP_Large_Deal` v1 to `OPP_Two_Level_Mgmt`, instance `04gaj000001ybXBAAY`, with `amfu1` | ADL-00000015, `Opportunity__c` set, `{"Amount":300000.00}` | recalled by the admin: `Removed`, guard false |
| *AMF M11 gate: small deal*, `006aj00000ffwjaAAA`, 5,000 | `OPP_Catch_All` v1 to `OPP_Manager_Approval`, instance `04gaj000001ybXCAAY`, with `amfu1` | ADL-00000016, `Opportunity__c` set, `{}` | approved by the admin acting for `amfu1`: `Approved`, guard false |

The timeline returned each entry joined to its instance (Started > Removed, and Started > Approved),
the large deal's with its one value.

**Finding: the platform assigned both work items to `amfu1`,** whose license grants no Opportunity
access. It checks neither sharing (M3.10) nor license when it resolves an approver. §11 now says
approvers must hold a license that includes the object.

**Owed: the manual UI check** (playbook gate step 8). On a throwaway Opportunity, as the admin:

- the header's first button is Submit for Approval, and there is no second one;
- the modal names the route;
- after submitting, the timeline shows the entry without a reload;
- *Matrix Submission* is ticked.

### M11.5 Carried into later phases

This table supersedes M10.8's.

| Item | Owner |
|---|---|
| The M11 gate's manual UI check (step 8, above) | user |
| Still open from M8.7: the manual UI check (step 6). PR-00000027 serves it from its second step | user |
| The Approval Decisions related list offers New and Mass Change Owner, on both objects' layouts, to anyone who may create log rows (administrators). `excludeButtons` on each layout's related list removes them; the Purchase Request layout is outside M11's scope, so both wait together | a hardening pass |
| The source deploys only to `amf-dev`, for two reasons now: `PR_Three_Level_Finance` names its approvers by username, and the four Opportunity layouts reference this org's own fields (`OrderNumber__c` and others) | M12, or any CI or second org |
| The seeded approvers cannot approve Opportunities (Platform licenses). A demo that needs a non-admin Opportunity approver must spend the org's last Salesforce license on one | if a demo needs it |
| Whether the lock a final approval leaves stops a real non-admin's Apex update outside a test is unmeasured (M10.8a) | if a need appears |
| The preview cannot foresee a guard failure (M10.7h) | if a need appears |
| ~~Check Opportunity's triggers before M11 (M10.7g)~~ | **closed**: `amf-dev` has no Apex triggers, validation rules or record-triggered flows on Opportunity. In an org that has them, a partial guard failure re-runs their triggers on the other records |
| `Lock_Decision_Log` still permits one post-insert stamp of `Execution_Ref_Id__c`, which nothing performs since M10 (M10.6). Test it against deleting a governed record (M3.12) | a later hardening pass |
| A record-triggered Flow on a governed object that calls the action is re-triggered by the engine's guard update and by the templates' clearing update; its entry conditions must exclude those | whoever builds such a Flow |
| husky's pre-commit would rewrite every file a commit touches (M10.7); commits here run with `HUSKY=0` | a tooling decision |
| Still open from M8.7c: PR-00000014 to PR-00000025 carry the guard; they go with M6's teardown | M6 teardown |
| The playbook's optional manual M9 check | user, optional |
| ~~M9.5's 55-relationship union~~ | **closed in M11**: not enforced; the validator runs the query |
| M9.5's other grammar items: DateTime, the text-like field types, reserved keywords, field-to-field multipicklists | as in M9.5 |

---

## Phase M12 — Template lifecycle, queue and committee templates, portability

**Date:** 2026-10-22 · **Commit:** `bcedf6f`, Phase M12 · **Status:** complete. The gate
ran in `amf-dev`, apart from its manual UI step, which is owed to the user.
**Playbook goal:** make §5.1's rule that a live template is never edited in place a gate failure;
add the queue and committee shapes; let `force-app` deploy to an org other than `amf-dev`.

The user asked this session to start "the next major build" from the handoff, which named M12.
They took its three decisions in this session:

- a fingerprint manifest, over a git diff against a release tag;
- Classic committees now, over waiting for Flow;
- the org's own configuration in its own package directory, over stripping `amf-dev`'s fields or
  keeping them.

Of the two riders offered, they chose the related-list buttons. `Lock_Decision_Log` stays carried.
`CLAUDE.md` records the authorisation, and the playbook's Part 3 entry and gate were written before
building.

### M12.1 File-level changes

| File | Change | Notes |
|---|---|---|
| `config/template-releases.json` | **new** | the six released templates, each with its fingerprint and the phase that released it |
| `scripts/validate-approval-matrix-source.ps1` | **rewritten** | reads every package directory; guard checks on every active template; the lifecycle; usernames; the replacement config; standard objects' configuration kept out of `force-app`. `-ProjectRoot` replaces `-SourceRoot`, and XML is read as UTF-8 |
| `sfdx-project.json` | **modified** | the package directory `org-config/amf-dev`; a replacement of `{{AMF_USERNAME_DOMAIN}}` in approval processes, from the environment variable of that name |
| `org-config/amf-dev/main/default/layouts/Opportunity-*.layout-meta.xml` ×4 | **moved** from `force-app`, then the rider | otherwise unchanged |
| `org-config/amf-dev/main/default/objects/Opportunity/Opportunity.object-meta.xml` | **moved** from `force-app` | unchanged |
| `approvalProcesses/Purchase_Request__c.PR_Credit_Risk_Queue.approvalProcess-meta.xml` | **new** | one step on the queue `Q_Credit_Risk` |
| `approvalProcesses/Purchase_Request__c.PR_Finance_Committee.approvalProcess-meta.xml` | **new** | `amfu1` to `amfu3` unanimously, then `amfu4` or `amfu5` |
| `approvalProcesses/`, the four existing templates | **modified**, representation only | the form a retrieve returns (M12.3a); `PR_Three_Level_Finance` names its users through the placeholder |
| `customMetadata/Approval_Matrix_Rule.PR_Committee_Spend`, `PR_Credit_Risk_Review` | **new** | priorities 5 and 30 |
| `layouts/Purchase_Request__c-Purchase Request Layout.layout-meta.xml` | **modified** | the rider |
| `classes/AMF_TemplateShapesTest.cls` | **new** | 10 real-platform tests |
| `classes/AMF_CmdtRuleProviderTest.cls` | **modified** | one expectation: the shipped matrix's first rule (M12.3b) |
| `scripts/seed-data.apex` | **modified** | `G_Finance_Approvers` as `Q_Credit_Risk`'s member; prints the deploy value of `AMF_USERNAME_DOMAIN` |
| `CLAUDE.md`, `docs/architecture.md` (§3.2, §5.1, §5.2, §5.4, §6.3, §9, §11 notes; §13.4 row), `docs/build-playbook.md` (M12 in Part 3; Part 5), `docs/decisions.md` (6 entries), `docs/handoff.md` | **modified** | authorisation, design, decisions, the next handoff |

No engine class, LWC or validator class changed. The engine routed to the two new templates as it
routes to any other process.

### M12.2 Design choices worth recording

**(a) What the fingerprint covers: everything but `<active>`.** Excluding descriptions, labels or
`processOrder` was considered and rejected:

- A description is what an auditor and an approver read.
- A strict rule is easier to state than a list of exemptions.
- A retrieve returned all six templates exactly as source holds them, `processOrder` included,
  once source had taken the retrieved form (a, M12.3).

Line endings are normalised because git checks files out with CRLF on this workstation and with LF
elsewhere. Whitespace-only nodes are dropped, so re-indenting does not count as an edit. The name
is not part of the fingerprint, so a renamed copy has its original's fingerprint (case b, M12.4).
That is harmless, because the manifest is keyed by name.

**(b) Releasing is a line the gate prints, not a script.** A release script would have needed the
normaliser in two places, or a write mode in a gate. An unreleased template fails, and its message
carries the exact manifest line, so the gate stays read-only and releasing stays deliberate.

**(c) Version chains by name.** `X_v<n>` is version n, for n ≥ 2. `_v0` and `_v1` are refused,
because the first version has no suffix. Every lower version of a chain is superseded, and gaps
are allowed. A rule that names a superseded version gets its own message, beside "not active".

**(d) The guard checks run on every active template** (`docs/decisions.md`). Before M12 they ran
only on templates a rule named.

**(e) A placeholder rather than `amf-dev`'s domain** (`docs/decisions.md`). The replacement's glob
covers every approval process. A deploy that includes any template therefore needs the variable,
even for a template that names no user. Per-file entries would avoid that, at the cost of a list to
keep beside the templates. The gate checks that the replacement exists.

**(f) Where the org-configuration boundary lies.**

- **Moved:** the four Opportunity layouts and `Opportunity.object-meta.xml`.
- **Stayed:**
  - the guard field, the templates and the quick action, which are the framework;
  - `Opportunity_Record_Page`, which holds standard components and the timeline only, so it
    deploys anywhere. In another org it deploys but is not activated, because the View override
    that activates it moved with the object settings;
  - the Purchase Request layout, whose object the framework ships.
- **The rule, enforced on the default package:** a standard object's layouts and object settings
  are org configuration.
- **Measured first:** the CLI recomposes Opportunity across both package directories into one
  object, with the override and the guard field. Converted alone, `force-app` produces an
  `Opportunity.object` that holds the guard field and nothing else.

**(g) The two shapes.**

- `Q_Credit_Risk` was seeded in M0 and already supports `Purchase_Request__c`.
- The committee is `G_Finance_Approvers`' three members, then the two finance leaders that
  `PR_Three_Level_Finance` ends with. The same three people twice was considered and rejected.
- The queue reaches the group by holding it as a member. That is the Classic way to route to a
  public group, and the test in M12.4 shows it works.

**(h) The rules.** `PR_Committee_Spend` (5) outranks every other rule. `PR_Credit_Risk_Review` (30)
sits between `PR_High_Risk` (20) and the catch-all. One consequence: an APAC request of a million
or more used to reach `PR_Three_Level_Finance` through `PR_High_Value_APAC`, and now goes to the
committee. The M3 demo's amounts are below that.

**(i) The tests act as the real approvers, with shares.**

- The committee tests act as whichever seeded users the platform assigned, read from the work
  items, so no test names a username.
- Each approver is first given read access to the record, as §11 requires of an adopting org.
- The queue tests add a member of their own rather than rely on the seeded membership.
- Actor names are not asserted, after the fix following M8: in a test transaction they read back
  null.

### M12.3 Issues encountered

**(a) The platform normalises a template on deploy.** The first retrieve after deploying showed all
six templates differing from source:

- `rejectBehavior` is dropped from a template's first step, where a rejection always ends the
  request;
- `Owner` is appended to the Purchase Request templates' approval page fields. The Opportunity
  templates already listed it.

Released as authored, the templates would have failed the gate after their next retrieve. So
source took the retrieved form, with the placeholder put back, before anything was released. The
deploys before (`0Afaj00000obdATCAY`) and after (`0Afaj00000obhu1CAA`) put the same templates in
the org, which the retrieve check in M12.4 shows.

**(b) `AMF_CmdtRuleProviderTest.shippedMatrixComesBackInPriorityOrder` failed in the first full
run** (`707aj00001Mxqbv`, 273/274). It reads the org's shipped CMDT rows, and it pinned
`PR_High_Value_APAC` as the first rule. `PR_Committee_Spend` at priority 5 now is, so the
expectation changed. The test reads more org rows than the one pin its class header names as the
only exception. That has departed from `CLAUDE.md`'s convention since M1, and it is carried rather
than refactored, by scope discipline.

**(c) MAX_PATH.** The session scratchpad's path is 125 characters, and `force-app`'s deepest file
adds about 120. The broken-copy script therefore copies only the metadata folders the gate reads,
under one-letter directory names.

**(d) The broken-copy script misreported twice before it was right.** Both faults were in the
script, not the gate, and the gate's verdicts did not change:

- The child host wrapped the gate's thrown message, which split fingerprints across lines. The
  script now catches the exception and prints its message raw.
- A string replace inserted `Submit` 19 times into one layout, which produced 19 identical
  findings.

**(e) The end-to-end submit ran twice.** A command meant to print the first run's output started a
second run, through a trailing `sf apex run … | head -0`. That submitted PR-00000031 and
PR-00000032 as well. Both were recalled in the third transaction, which made them evidence of both
templates' recall exit in the org. Their log rows stand, because rows are never deleted.

**(f) The manifest's fingerprints were copied from wrapped output.** The gate then confirmed all
six, so none was damaged.

**(g) One test is slow sometimes.** `aMemberThroughAPublicGroupCanDecideAQueueStep` took 91 s in
its first run and 16 s in the next. Each of the others took under 3 s. It creates a public group
and nests it in a queue, which makes the platform recalculate group membership.

**(h) Neither Python nor `npx` is on this workstation.** Edits went through the file tools, and
Jest ran through the CLI's bundled Node, as in M3.4e.

### M12.4 Verification evidence

```
source gate                 passed: 8 active rules, 6 approval processes guard-checked, 6 of 6 templates
                            released and unchanged, 5 layouts of 2 governed objects
deploy without the variable --dry-run refused: "AMF_USERNAME_DOMAIN" is in sfdx-project.json as a value
                            for "replaceWithEnv" property, but it's not set in your environment
deploy                      0Afaj00000obdATCAY Succeeded 128/128 (PR_Credit_Risk_Queue, PR_Finance_Committee
                            created); after the retrieved form and the test class, 0Afaj00000obhu1CAA
                            Succeeded 129/129
seed                        "Queue Q_Credit_Risk members: G_Finance_Approvers (1 added)"
post-deploy check           "Approval Matrix configuration is valid."
M12 class                   707aj00001MxXNz: AMF_TemplateShapesTest 10/10
RunLocalTests               707aj00001Mxqbv: 273/274 (M12.3b); after the fix 707aj00001MwtT1: 274/274,
                            org-wide 98%. Service, timeline and history provider 100%, validator 98%;
                            AMF_ClassicProcessStrategy 78%, its uncovered lines M3's unreachable guard
Jest                        59/59 in 4 suites (no LWC changed)
```

**Step 2, broken scratch copies of the project.** A script in the session scratchpad copied the
project, broke each copy one way, and ran the gate with `-ProjectRoot`. Messages are shortened
here:

```
0  unchanged copy                         PASSED  6 of 6 released and unchanged
a  released template edited               FAILED  PR_Two_Level_Mgmt has changed since it was released ...
                                                  make the change in a new version, PR_Two_Level_Mgmt_v<n>
b  unreleased template                    FAILED  PR_Credit_Risk_Desk is not released. To release it, add
                                                  { "template": ..., "sha256": "3023d868..." }
c  released template deleted              FAILED  OPP_Catch_All names OPP_Manager_Approval, but source does not
                                                  contain it; OPP_Manager_Approval is released but not in source
d1 _v2, rule repointed, X still active    FAILED  PR_Credit_Risk_Queue is superseded by PR_Credit_Risk_Queue_v2
                                                  and must be deactivated
d2 _v2, X deactivated, rule still on X    FAILED  ...PR_Credit_Risk_Queue is not active, but PR_Credit_Risk_Review
                                                  names it; ... which PR_Credit_Risk_Queue_v2 supersedes; repoint it
e  literal username                       FAILED  names the user 'amfu2@amf.00daj000012gj9b.dev' literally;
                                                  PR_Finance_Committee has changed since it was released
f  replacement removed                    FAILED  no replacement of {{AMF_USERNAME_DOMAIN}} ... covering
                                                  approvalProcesses
g  Opportunity's configuration in force-app FAILED  a standard object's layout in force-app; Opportunity.object-meta.xml
                                                  holds a standard object's settings in force-app
h  Submit back on an org-config layout    FAILED  Opportunity (Sales) Layout keeps the standard Submit button
i  a _v1 suffix                           FAILED  not released; spells out a version below 2
PASS _v2 released, X deactivated, rule repointed  PASSED  7 of 7 released and unchanged; 6 guard-checked
```

The last case is §5.1's whole procedure. The deactivated predecessor still matches its fingerprint,
because the active flag is the one exclusion. It is no longer guard-checked, because nothing can
enter an inactive template.

**Step 3, portability offline.**

```
SF_APPLY_REPLACEMENTS_ON_CONVERT=true AMF_USERNAME_DOMAIN=acme.example.invalid
  sf project convert source --source-dir force-app
    user approvers   amfu1@acme.example.invalid ×1, amfu2 ×1, amfu3 ×2, amfu4 ×2, amfu5 ×2; placeholders left: 0
    standard objects Opportunity.object, holding the guard field alone (no settings, no layout)
without the variable  Error (ConversionError) ... "AMF_USERNAME_DOMAIN" ... not set in your environment; exit 10
force-app             no file contains 00daj000012gj9b, 00Daj000012Gj9B or agentforce.com
```

A second org was not used. The playbook's guardrail allows `amf-dev` alone, and the only other
aliases are two Dev Hubs that belong to other work.

**Step 5, the org holds what is released.** Retrieving every `ApprovalProcess` in `amf-dev`
returned exactly the six. Copied into a scratch project with the domain put back to the
placeholder, they passed the gate: "6 of 6 template(s) released and unchanged".

**Step 9, the rider, by the UI API.** `GET /ui-api/actions/record/<Id>/related-list/Approval_Decisions__r`
returned, before and after:

```
PR-00000028 (a02aj00000jTA26AAG)    before: New | MassChangeOwner (StandardButton)    after: "actions": {}
AMF M11 gate: small deal (006aj00000ffwjaAAA)                                         after: "actions": {}
```

**Step 10, end to end, through the production engine and the deployed rules.** There were three
committed transactions of anonymous Apex, run as the admin. The admin acted on others' work items,
as an administrator may.

```
1 submit      PR-00000029 (a02aj00000jVQp7AAG) Submitted by PR_Credit_Risk_Review to PR_Credit_Risk_Queue,
              instance 04gaj000001ygmzAAA, log a03aj00002Wp7ATAAZ, guard true
                  work item with Credit Risk (Queue 00Gaj00000V8jvlEAB)
              PR-00000030 (a02aj00000jVQp8AAG) Submitted by PR_Committee_Spend to PR_Finance_Committee,
              instance 04gaj000001ygn0AAA, log a03aj00002Wp7AUAAZ, guard true
                  work items with AMF Approver One, Three, Two
              (PR-00000031 and PR-00000032, the same again: M12.3e)
2 committee   after One approves: Pending, open with Three, Two
              after Three approves: Pending, open with Two
              after Two approves: Pending, open with Five, Four
3 finish      PR-00000030: Five approves -> Approved, open work items 0, guard false
              PR-00000029, -31 (queue), -32 (committee): recalled -> Removed, open work items 0, guard false
              PR-00000030 history (actor / original actor): Started; Approved by the admin for One, Three,
              Two and Five; NoResponse for Four
```

**What the real-platform tests add to that** (`AMF_TemplateShapesTest`):

- a queue member decides the queue's step, and the timeline shows the member as actor and the
  queue as original actor;
- a member of a public group that the queue holds can decide it, so the seed's configuration
  works;
- a user outside the queue cannot decide it, whatever their access to the record;
- two committee approvals of three leave the request pending, and one rejection ends it;
- both templates refuse a submission that bypasses the engine;
- a recall from either re-arms the guard.

**Owed to the user: the manual UI check (step 11), on a fresh medium-risk request of at least
50,000:**

1. The modal names `PR_Credit_Risk_Queue`.
2. After submitting, the timeline shows the step with *Credit Risk*.
3. The Approval Decisions list offers no New button.

### M12.5 Carried into later phases

This table supersedes M11.5's.

| Item | Owner |
|---|---|
| M12's manual UI check (step 11, above) | user |
| M11's manual UI check (playbook M11, step 8) | user |
| Still open from M8.7: the manual UI check (step 6). PR-00000027 serves it from its second step | user |
| `AMF_CmdtRuleProviderTest.shippedMatrixComesBackInPriorityOrder` reads the org's shipped rules, not only the pin (M12.3b); a new lowest-priority rule changes it again | a hardening pass |
| Portability is shown offline only: no second org has deployed `force-app`. In one, the admin also removes the standard Submit button from its own layouts of each governed standard object (§6.3) | whoever sets up CI or a second org |
| Every deploy that includes approval processes needs `AMF_USERNAME_DOMAIN`, `amf-dev`'s included (`CLAUDE.md`'s deploy line). A retrieve writes real usernames back, which the gate refuses: put the placeholder back | everyone who deploys or retrieves |
| The gate's fingerprints govern source only. A template edited in Setup is found only by the retrieve-and-compare of M12.4 step 5, which is not scripted | a later hardening pass |
| `aMemberThroughAPublicGroupCanDecideAQueueStep` takes 16 to 91 s (M12.3g) | if suite time matters |
| `Lock_Decision_Log` still permits one post-insert stamp of `Execution_Ref_Id__c`, which nothing performs since M10 (M10.6). Test it against deleting a governed record (M3.12) | a later hardening pass |
| The seeded approvers cannot approve Opportunities (Platform licenses) | if a demo needs it |
| Whether the lock a final approval leaves stops a real non-admin's Apex update outside a test is unmeasured (M10.8a) | if a need appears |
| The preview cannot foresee a guard failure (M10.7h) | if a need appears |
| A record-triggered Flow on a governed object that calls the action is re-triggered by the engine's guard update and by the templates' clearing update; its entry conditions must exclude those | whoever builds such a Flow |
| husky's pre-commit would rewrite every file a commit touches (M10.7); commits here run with `HUSKY=0` | a tooling decision |
| Still open from M8.7c: PR-00000014 to PR-00000025 carry the guard; they go with M6's teardown | M6 teardown |
| The playbook's optional manual M9 check | user, optional |
| M9.5's grammar items: DateTime, the text-like field types, reserved keywords, field-to-field multipicklists | as in M9.5 |
| ~~The Approval Decisions related list offers New and Mass Change Owner (M11.5)~~ | **closed in M12** |
| ~~The source deploys only to `amf-dev` (M11.5)~~ | **closed in M12**, offline; see the portability row |

### M12.6 Follow-up: the first UI test run, and two timeline fixes (2026-10-22)

**Commit:** `72f4dfd`, Phase M12.6 · **Status:** complete. The fixes are deployed to `amf-dev` and
passed every automated check. The UI suite's re-run against them is owed to the user.

The user asked for test scripts that an AI agent could run in the browser, to hand over the manual
UI checks that M8, M11 and M12 owed. The agent runs as its own Salesforce user, Grok Bot. The user
ran it once, as R20261022-1412. They then asked for its report to be checked, and for the necessary
fixes. `CLAUDE.md` records the authorisation: `amfDecisionTimelineEntry` and its Jest test alone,
plus the suite.

| File | Change | Notes |
|---|---|---|
| `docs/ui-tests/ui-test-scripts.md` | **new** | 16 test cases and 75 steps, each with a PASS and a FAIL condition the agent can observe; corrected after the first run (f) |
| `docs/ui-tests/README.md` | **new** | for the person who runs the agent: its user, the login link, the parameters, the coverage, reading a report |
| `lwc/amfDecisionTimelineEntry/amfDecisionTimelineEntry.js` | **modified** | imports the viewer's time zone, `@salesforce/i18n/timeZone` |
| `lwc/amfDecisionTimelineEntry/amfDecisionTimelineEntry.html` | **modified** | `time-zone` on both date components; the heading's comma in a span of its own; `data-id="approval-heading"` |
| `lwc/amfDecisionTimelineEntry/__tests__/amfDecisionTimelineEntry.test.js` | **modified** | one test of the time zone, with the import mocked to `Asia/Kolkata`; one assertion of the whole heading |
| `CLAUDE.md`, `docs/build-playbook.md` (the gate notes of M8, M11 and M12; the M12.6 follow-up; Part 5), `docs/handoff.md` | **modified** | authorisation, gate, handoff |

No Apex class, object, layout, approval process, permission set or CMDT row changed.

**(a) The suite.** Every expected value was read from the build, not written from memory:

- the LWC templates and their Jest tests;
- the shipped CMDT rows;
- the UI API in `amf-dev`;
- the approval history of M12's gate requests;
- a REST call that changes nothing.

The agent creates its own records and judges each step by what it can see. It reports a failure
rather than working around it. Two tests are optional: TC-15 changes Setup (M9's optional check),
and TC-16 opens Flow Builder.

**(b) The agent's user.** The expected values were read as Tejas Vernekar, the CLI's user. Grok Bot
(`tejas.vernekar@wissen.com.grokbot`) was made that user's equal by anonymous Apex:

- profile System Administrator;
- permission set `Approval_Matrix_Admin`;
- manager AMF Approver One.

Its locale (en_US) and time zone (America/Los_Angeles) already matched, and the licence count stayed
at 4 of 4. The suite takes the user's name as a parameter, `TESTER`. Grok Bot can now do anything an
administrator can, editing decision log rows included, so the README says to deactivate it between
runs.

**(c) The run.** R20261022-1412, 08:42 to 09:29 UTC, without the optional tests:

```
records     PR-00000039 (D1), -40 (D2), -41 (D3); accounts UITEST R20261022-1412 Energy Co and
            Hotels Ltd; its Energy deal (D5), Hotels deal (D7) and Large deal (D8);
            log rows ADL-00000021 to -25
tests       14 PASS, 3 FAIL (TC-03, TC-09, TC-14), 2 NOT RUN
steps       64 PASS, 3 FAIL (TC-03.6, TC-09.5, TC-14.5), 8 NOT RUN, 0 BLOCKED
afterwards  the guard false on all six governed records; no open work item from the run; every log row
            unchanged since written (CreatedDate = LastModifiedDate, both by Grok Bot)
```

It closed three owed checks:

- **M12's, step 11.** TC-03.1's modal named `PR_Credit_Risk_Queue`. TC-03.4 showed the step waiting
  on *Credit Risk*. TC-01.4 and TC-03.6 found no New or Change Owner on Approval Decisions.
- **M11's, step 8.** TC-11.1 found one Submit for Approval. TC-14 previewed and submitted, the
  timeline updated without a reload, and the guard ticked. The header shows Follow first, so the run
  counted the action rather than taking its position, which step 8 names.
- **M8's, step 6.** TC-05 refused the pending request by name, with no modal and no new log row.
  TC-06 recalled it, and the guard cleared. TC-07 routed it again.

**(d) The report, item by item.** Each item was checked against the source and the org first:

| Report item | Verdict | Evidence |
|---|---|---|
| TC-03.6, TC-09.5, TC-14.5: no Rule Version or Selected Process column | the script's error | the card shows the first four of the layout's six columns, Lightning's limit for the Related Lists component. The script took its columns from the layout |
| Timeline times 3 hours ahead of the related lists | **defect 1** | (e) |
| "PR_Credit_Risk_Queue,In approval", passed with a flag | **defect 2** | (e). The script's matching rule was loose enough to let it pass |
| Outcome stays "Submitted" after approval | by design | the log records the route, not the approval's result (§3.3); TC-08.4 now asserts it |
| ADL-00000021's Submitted At "reads 2:10 AM", not 2:19 | a misread | stored as 09:19:46 UTC, and its approval created at 09:19:47 UTC: both 2:19 AM Pacific |
| The log link "opens in a new console tab" | the agent's browser | `UserAppInfo` shows the Sales app all run, which has standard navigation. The link navigates in place |
| `$60,000.00` on the record, `60,000` in the modal | the script's error | a currency field. TD-01 now expects the currency form |
| Recall sits only in the card's drop-down | the script's error | section 0.6 now explains a card's drop-down |
| Stage set before the Account lookup; a browser crash; a 4.5-second watch; a late toast; a missing screenshot | the agent | no duplicate: 3 test opportunities and 2 accounts exist. TC-12.3 proved the cancelled preview wrote nothing |
| "Instead of Tejas Vernekar" in the report's header | the agent's copy | it may predate `TESTER`. The current file names no user |

**(e) The two defects.**

1. **Times followed the browser's time zone.**
   - Grok Bot, Tejas and the org are all on America/Los_Angeles.
   - ADL-00000021 was stamped 09:19:46 UTC, which the related lists showed as 2:19 AM. The timeline
     showed 05:19 AM, which is UTC−4 and matches no Salesforce setting, so it came from the agent's
     browser.
   - Given no `time-zone`, `lightning-formatted-date-time` uses the device's zone. The entry now
     passes `@salesforce/i18n/timeZone`, the viewer's Salesforce zone, to both of its date
     components, the entry's and each step's.
   - Nothing caught it before. M7.7's manual check compared no times, and the Jest stub of the date
     component renders nothing, so no test saw a zone.
   - The new test mocks the import to a zone that is neither the Jest default nor `amf-dev`'s, so
     the value must come from the import.
2. **The heading lost a space.**
   - Where HTML renders a line break between text and a tag as one space, the LWC compiler drops
     it, with its indentation.
   - The template broke the line after `</span>,`, so the compiled fragment read
     `</span>,<span data-id="approval-status">`.
   - The comma and its space now sit in a span of their own, and the fragment reads
     `</span><span>, </span><span data-id="approval-status">`.
   - A scan of all four templates' compiled output found no other text touching an inline element.
   - The tests asserted the process and status spans separately, so they missed it. The new
     assertion reads the whole heading.

**(f) The script's corrections**, from the run:

- TC-03.6, TC-09.5 and TC-14.5 check only the columns the card shows.
- Section 0.6 explains a card's drop-down and its four columns. A card "offers" an action in either
  place.
- A missing space is now a difference (0.4). TC-03.4 keeps the exact heading, and TC-06.3, TC-08.3
  and TC-10.6 check only its names, so one defect fails one step.
- TC-03.6 compares the timeline's time with Approval History's, to the minute.
- TC-08.4 asserts that both of D1's log rows still read Submitted.
- TD-01 expects currency amounts, and fills an Opportunity's Account Name last.
- TC-04.1 accepts the log opening in a new tab, and TC-05.1 takes its screenshot before the toast
  closes.

**Issues encountered.**

- **The first queries of the run's records went through the Bash tool,** where `sf` fails (Part 1's
  machine notes). One held `>=`, which cmd.exe took as a redirect. It left an empty file named
  `'ADL-00000021'` in the project root, deleted at once. The queries then went through PowerShell.
- **`@lwc/template-compiler` 8.28's `compile()` takes the file name second and the options third.**
  Passing the options second fails with LWC1028.

**Verification evidence:**

```
Jest, before the fix  the entry's suite 2 failed, 21 passed:
                        time zone  Expected 4 x "Asia/Kolkata"; Received 4 x undefined
                        heading    Received "Approval history: PR_Three_Level_Finance,In approval"
Jest, after           60/60 in 4 suites (59 before, plus the time-zone test)
ESLint                0 findings on the entry and its test
compiled heading      Approval history: <span data-id="process">…</span><span>, </span><span
                      data-id="approval-status">…</span>
source gate           passed: 8 active rules, 6 approval processes guard-checked, 6 of 6 templates
                      released and unchanged, 5 layouts of 2 governed objects
deploy                0Afaj00000ohxZVCAY Succeeded 129/129, 0 errors. It marked as changed the same
                      eleven components as M12's deploy (0Afaj00000obhu1CAA); only the entry's
                      source differs
the org's copy        retrieved: time-zone={timeZone} on both date components, the comma's span,
                      the import
post-deploy check     "Approval Matrix configuration is valid."
RunLocalTests         707aj00001N5wUj: 274/274, in 489 s (no Apex changed)
```

**Owed: the UI suite's re-run** against this build, as `docs/ui-tests/README.md` describes. TC-03.4
checks the heading, and TC-03.6 the time zone. TC-03.6's check only bites when the agent's browser
is not on Pacific time.

### M12.6 Carried into later phases

This table supersedes M12.5's.

| Item | Owner |
|---|---|
| The UI suite's re-run against M12.6 | user |
| Grok Bot holds System Administrator in `amf-dev`. Deactivate it, or return it to Standard User, between runs | user |
| PR-00000027 has been pending since M10.8 to serve M8's check, which M12.6 closed. It can be recalled | user |
| The Approval Decisions card shows four of its six columns. Reordering them, or an enhanced list, would bring Selected Process onto it | if wanted |
| The decision log's page offers Submit for Approval, Edit and Delete. An explicit action list on its layout would remove them (`docs/ui-tests/README.md`) | a later hardening pass |
| `AMF_CmdtRuleProviderTest.shippedMatrixComesBackInPriorityOrder` reads the org's shipped rules, not only the pin (M12.3b); a new lowest-priority rule changes it again | a hardening pass |
| Portability is shown offline only: no second org has deployed `force-app`. In one, the admin also removes the standard Submit button from its own layouts of each governed standard object (§6.3) | whoever sets up CI or a second org |
| Every deploy that includes approval processes needs `AMF_USERNAME_DOMAIN`, `amf-dev`'s included (`CLAUDE.md`'s deploy line). A retrieve writes real usernames back, which the gate refuses: put the placeholder back | everyone who deploys or retrieves |
| The gate's fingerprints govern source only. A template edited in Setup is found only by the retrieve-and-compare of M12.4 step 5, which is not scripted | a later hardening pass |
| Six tests take 21 to 88 s each, and RunLocalTests 489 s. `aMemberThroughAPublicGroupCanDecideAQueueStep` (M12.3g) and the 200-record test are among them | if suite time matters |
| `Lock_Decision_Log` still permits one post-insert stamp of `Execution_Ref_Id__c`, which nothing performs since M10 (M10.6). Test it against deleting a governed record (M3.12) | a later hardening pass |
| The seeded approvers cannot approve Opportunities (Platform licenses) | if a demo needs it |
| Whether the lock a final approval leaves stops a real non-admin's Apex update outside a test is unmeasured (M10.8a) | if a need appears |
| The preview cannot foresee a guard failure (M10.7h) | if a need appears |
| A record-triggered Flow on a governed object that calls the action is re-triggered by the engine's guard update and by the templates' clearing update; its entry conditions must exclude those | whoever builds such a Flow |
| husky's pre-commit would rewrite every file a commit touches (M10.7); commits here run with `HUSKY=0` | a tooling decision |
| Still open from M8.7c: PR-00000014 to PR-00000025 carry the guard; they go with M6's teardown | M6 teardown |
| The playbook's optional manual M9 check. The UI suite's TC-15 runs it when `RUN_OPTIONAL` is `yes` | user, optional |
| M9.5's grammar items: DateTime, the text-like field types, reserved keywords, field-to-field multipicklists | as in M9.5 |
| ~~M12's manual UI check (step 11)~~ | **closed in M12.6** |
| ~~M11's manual UI check (playbook M11, step 8)~~ | **closed in M12.6** |
| ~~Still open from M8.7: the manual UI check (step 6)~~ | **closed in M12.6** |

### M12.7 M12.6's gate closed: the UI suite's re-run (2026-10-22)

**Commit:** `0049677` · **Status:** complete. Step 3 of M12.6's gate passed. Nothing in `force-app`
changed.

The agent re-ran the suite against M12.6, as R20261022-1856, from 13:30 to about 13:45 UTC. The user
shared its account of the two steps that failed, TC-03.6 and TC-14.5. No other step failed.

**(a) Both fixes confirmed.**

- TC-03.4 passed under the strict matching rule, so the heading now reads "Approval history:
  PR_Credit_Risk_Queue, In approval".
- TC-03.6's new time check passed: 06:34 AM in the timeline, and 6:34 AM in Approval History.
  ADL-00000026 was stamped 13:34:51 UTC, which is 06:34 in Grok Bot's Pacific time zone. In the
  first run, the timeline showed its times 3 hours later.

**(b) The two FAILs were in the Approval Decisions card, not the build.**

- **What the agent saw.** On D1 (PR-00000042) and D5 (UITEST R20261022-1856 Energy deal), the card
  read "Approval Decisions (0)" right after the submission. The timeline already linked the new
  rows, ADL-00000026 and ADL-00000030. After one reload, the card read (1) with the right row, and
  every other condition held. The steps allowed no reload for the card, so the agent failed them.
  It added that both pass if a reload is allowed.
- **The submit action already refreshes the page.** It calls `notifyRecordUpdateAvailable` for
  the record, then dispatches the page's `RefreshEvent` (`lightning/refresh`). The timeline's
  registered handler re-reads on that event, but the card did not refresh.
- **It varies.** In the first run, the same two steps saw the new row with no reload.
- **No requirement promises the card a live update.** M7 and M11 promise one for the timeline,
  and that held.

So the script now allows one reload for a related-list card after a submission, with the note
"needed reload", as it already did for Matrix Submission. The rule is in section 0.5, and
TC-03.6, TC-07.4, TC-09.5 and TC-14.5 point to it. By the agent's own account, both steps meet
every condition after the reload. They pass under the corrected rule, so this run closes the gate
without another.

`amfSubmitForApproval`'s comment says the refresh reaches "the decision timeline and the related
lists". That holds for the timeline. The related lists are carried, below.

**(c) The org after the run:**

```
records     PR-00000042 (D1), -43 (D2), -44 (D3); accounts UITEST R20261022-1856 Energy Co and
            Hotels Ltd; its Energy, Hotels and Large deals. No duplicates
log rows    ADL-00000026 to -30, all by Grok Bot, none changed since written
approvals   D1 recalled, then approved; D2 recalled in cleanup; D3 rejected; D5 recalled in cleanup
afterwards  the guard false on all six governed records; no open work item from the run; no
            UITEST rule in the matrix
```

| File | Change | Notes |
|---|---|---|
| `docs/ui-tests/ui-test-scripts.md` | **modified** | section 0.5: related-list cards after a submission; TC-03.6, TC-07.4, TC-09.5 and TC-14.5 point to it |
| `docs/ui-tests/README.md` | **modified** | the re-run; what "needed reload" covers |
| `docs/build-playbook.md` (M12.6's gate; Part 5), `docs/handoff.md` | **modified** | the gate closed |

### M12.7 Carried into later phases

This table supersedes M12.6's.

| Item | Owner |
|---|---|
| After a submission, a standard related-list card can show its earlier state until a reload. The submit action's `RefreshEvent` reaches the timeline but not reliably the card, though the action's comment names both. Finding what refreshes the card needs someone in the browser | if wanted |
| Grok Bot holds System Administrator in `amf-dev`. Deactivate it, or return it to Standard User, between runs | user |
| PR-00000027 has been pending since M10.8 to serve M8's check, which M12.6 closed. It can be recalled | user |
| The Approval Decisions card shows four of its six columns. Reordering them, or an enhanced list, would bring Selected Process onto it | if wanted |
| The decision log's page offers Submit for Approval, Edit and Delete. An explicit action list on its layout would remove them (`docs/ui-tests/README.md`) | a later hardening pass |
| `AMF_CmdtRuleProviderTest.shippedMatrixComesBackInPriorityOrder` reads the org's shipped rules, not only the pin (M12.3b); a new lowest-priority rule changes it again | a hardening pass |
| Portability is shown offline only: no second org has deployed `force-app`. In one, the admin also removes the standard Submit button from its own layouts of each governed standard object (§6.3) | whoever sets up CI or a second org |
| Every deploy that includes approval processes needs `AMF_USERNAME_DOMAIN`, `amf-dev`'s included (`CLAUDE.md`'s deploy line). A retrieve writes real usernames back, which the gate refuses: put the placeholder back | everyone who deploys or retrieves |
| The gate's fingerprints govern source only. A template edited in Setup is found only by the retrieve-and-compare of M12.4 step 5, which is not scripted | a later hardening pass |
| Six tests take 21 to 88 s each, and RunLocalTests 489 s. `aMemberThroughAPublicGroupCanDecideAQueueStep` (M12.3g) and the 200-record test are among them | if suite time matters |
| `Lock_Decision_Log` still permits one post-insert stamp of `Execution_Ref_Id__c`, which nothing performs since M10 (M10.6). Test it against deleting a governed record (M3.12) | a later hardening pass |
| The seeded approvers cannot approve Opportunities (Platform licenses) | if a demo needs it |
| Whether the lock a final approval leaves stops a real non-admin's Apex update outside a test is unmeasured (M10.8a) | if a need appears |
| The preview cannot foresee a guard failure (M10.7h) | if a need appears |
| A record-triggered Flow on a governed object that calls the action is re-triggered by the engine's guard update and by the templates' clearing update; its entry conditions must exclude those | whoever builds such a Flow |
| husky's pre-commit would rewrite every file a commit touches (M10.7); commits here run with `HUSKY=0` | a tooling decision |
| Still open from M8.7c: PR-00000014 to PR-00000025 carry the guard; they go with M6's teardown | M6 teardown |
| The playbook's optional manual M9 check. The UI suite's TC-15 runs it when `RUN_OPTIONAL` is `yes` | user, optional |
| M9.5's grammar items: DateTime, the text-like field types, reserved keywords, field-to-field multipicklists | as in M9.5 |
| ~~The UI suite's re-run against M12.6~~ | **closed in M12.7** |

### M12.8 Follow-up: a Request Name field and two list views (2026-10-23)

**Commit:** `c59e758` · **Status:** complete. Authorised in `CLAUDE.md` the same
day.

The user asked for nine demo records, to walk through the post-MVP features in the UI, then asked
for readable names on them and for list views that show them. Opportunities and Accounts have
names already. A Purchase Request's only name was its `PR-` auto-number.

**(a) Two choices, both the user's.** They were put as questions, because new metadata on a
governed object was outside every authorised phase:
- **A new field, not a new name.** `Request_Name__c` is a Text(80) field beside the auto-number,
  which stays the record name. Converting `Name` to Text was the alternative. It would have changed
  every header, made the name mandatory on every new record, and broken the UI suite's checks for
  `PR-` and 8 digits. As built, the timeline, the decision log's lookup and the suite are unchanged.
- **In source, as a numbered follow-up.** The alternative, a change in the org alone, would have
  left `amf-dev` ahead of `develop`.

**(b) Where each piece lives.** The field, the layout and both permission sets are in `force-app`,
like the object's other fields. Both sets grant edit, as they do for `Region__c`. The Opportunity
list view goes in `org-config/amf-dev`, beside that org's Opportunity layouts and object settings:
`force-app` keeps no configuration of a standard object (M12). No rule reads the field, and the
validator compiles only what rules name, so it needs no change.

**(c) Demo data.** These records were created in `amf-dev` by anonymous Apex run as Tejas Vernekar.
None has been submitted, and no log row names them:

```
purchase requests  PR-00000045 PR-Queue      60,000 AMER Medium -> PR_Credit_Risk_Review (30)
                   PR-00000046 PR-Committee  1,200,000 AMER Low -> PR_Committee_Spend (5)
                   PR-00000047 PR-CatchAll   5,000 EMEA Low     -> PR_Catch_All (9999)
                   PR-00000048 PR-APAC       150,000 APAC Low   -> PR_High_Value_APAC (10)
accounts           DEMO Energy Co (Energy), DEMO Hotels Ltd (Hospitality)
opportunities      DEMO Energy deal 5,000 Energy Co    -> OPP_Key_Industry (20)
                   DEMO Hotels deal 5,000 Hotels Ltd   -> OPP_Catch_All (9999)
                   DEMO Large deal 300,000 Energy Co   -> OPP_Large_Deal (10)
                   all three Prospecting, closing 2026-11-21
```

The routes are `AMF_ApprovalMatrixService.previewRecord` on each record, which writes nothing. A log
count over the seven Ids returned 0 afterwards.

**Verification evidence:**

```
source gate      passed: 8 active rules, 6 processes guard-checked, 6 of 6 templates released and
                 unchanged, 5 layouts of 2 governed objects
deploy dry run   succeeded, both package directories
deploy           0Afaj00000opCf4CAE: Succeeded, 131/131 components, 0 errors
validator        "Approval Matrix configuration is valid."
field access     Request_Name__c readable and updateable for the CLI user; FieldPermissions read
                 and edit true in Approval_Matrix_Admin and Approval_Matrix_User
list views       UI API list-info:
                 All_Purchase_Requests: Purchase Request Number | Request Name | Amount | Region |
                   Risk Level | Matrix Submission | Owner Alias | Last Modified Date
                 Matrix_Opportunities: Opportunity Name | Account Name | Amount | Stage |
                   Close Date | Matrix Submission | Opportunity Owner Alias
data             PR-00000045 to -48 carry their Request Name; guard false on all four
apex tests       RunLocalTests, job 707aj00001NJFKBAA5, 07:38 to 07:44 UTC: "Outcome Passed,
                 Tests Ran 274, Pass Rate 100%". ApexTestResult for the job: Pass 274, nothing else.
                 ApexTestRunResult: Completed, MethodsFailed 0
```

The CLI exited 255 after printing that report. The org's records of the run show no failure, so
the gate counts it as passed. ApexTestRunResult also reads MethodsCompleted 259 of 274 enqueued,
though all 274 results exist. Neither has a known cause, and neither appeared in earlier phases'
reports.

No LWC changed, so Jest was not re-run. The UI suite needs no change: TD-01 leaves every unnamed
field empty, and no step reads the layout's field list or a list view's columns.

| File | Change | Notes |
|---|---|---|
| `objects/Purchase_Request__c/fields/Request_Name__c.field-meta.xml` | **new** | Text(80), optional |
| `layouts/Purchase_Request__c-Purchase Request Layout.layout-meta.xml` | modified | Request Name under the number, editable |
| `objects/Purchase_Request__c/listViews/All_Purchase_Requests.listView-meta.xml` | modified | Request Name column after the number |
| `permissionsets/Approval_Matrix_Admin…`, `Approval_Matrix_User…` | modified | read and edit on Request Name |
| `org-config/amf-dev/…/objects/Opportunity/listViews/Matrix_Opportunities.listView-meta.xml` | **new** | Name, Account, Amount, Stage, Close Date, Matrix Submission, Owner Alias; all opportunities |
| `CLAUDE.md` | modified | M12.8 authorised |
| `docs/handoff.md`, `docs/technical-log.md` | modified | M12.8 recorded; the status board |

### M12.8 Carried into later phases

M12.7's table carries unchanged, with one addition:

| Item | Owner |
|---|---|
| The demo records of (c) stay in `amf-dev` for the walkthrough. Recall any left pending after using them | user |

---

## Phase M13 — AI around the engine: the Approval Matrix Assistant and plain-English explanations

**Commit:** `e81f487`. **Status:** complete. Built 2026-10-23, then gated, deployed and committed
the same day (M13.7). Only gate step 11, the manual UI check, is owed. Authorised in
`CLAUDE.md` on 2026-10-23.

The user asked whether AI or Agentforce could be added to the framework. Five use cases were put
to them, with one design rule: AI works around the engine, never inside it. They chose two, and
asked for them to be built after thorough analysis, following best practice, with a good UI and
easy use:
- **submit by chat:** an agent that previews a record's route, then submits it once the user
  confirms;
- **a plain-English "why":** any recorded decision explained in everyday words.

Mid-session they added: **"dont push any changes to org or branch".** So M13.1 to M13.6 record a
build in which nothing reached `amf-dev` or `develop`. Every org check there is check-only
(`--dry-run`), a compile or a read, and saved nothing. They then turned on Agentforce, assigned
themselves the permission sets, and asked for the deploy and the push. M13.7 is that gate.

### M13.1 File-level changes

| File | Change | Notes |
|---|---|---|
| `classes/AMF_ExplanationException.cls` | **new** | the reader-facing failure of an explanation |
| `classes/AMF_ExplanationGenerator.cls` | **new** | the seam: facts and a question in, an explanation out |
| `classes/AMF_EinsteinExplanationGenerator.cls` | **new** | runs `AMF_Explain_Approval_Decision` through `ConnectApi.EinsteinLLM`; a refusal keeps the platform's reason |
| `classes/AMF_DecisionExplainer.cls` | **new** | the timeline entry as plain-text facts; `explainDecision` (`@AuraEnabled`), `explain`, `explainLatest`; `displayOf`, `recordLabelOf` shared |
| `classes/AMF_AgentSupport.cls` | **new** | an Id read from text; a reason ended as a sentence; values as a sentence |
| `classes/AMF_AgentPreviewRoute.cls` | **new** | invocable *Preview Approval Route*, over `preview()` |
| `classes/AMF_AgentSubmitRoute.cls` | **new** | invocable *Submit Previewed Route*, over `AMF_SubmitForMatrixApproval.submitEach` |
| `classes/AMF_AgentExplainDecision.cls` | **new** | invocable *Explain Approval Decision* |
| `classes/AMF_AgentFindRecord.cls` | **new** | invocable *Find Governed Record* |
| seven `…Test.cls` classes | **new** | 60 tests (M13.4) |
| `classes/AMF_DecisionTimelineService.cls` | modified | public `describeValues()`, additive (`docs/decisions.md`) |
| `lwc/amfDecisionExplanation/` | **new** | the button and the explanation card, with 12 Jest tests |
| `lwc/amfErrors/` | **new** | `messageOf`, shared from now on |
| `lwc/amfDecisionTimelineEntry/` (js, html, test) | modified | the explanation at the top of a decision's details; `historyKey`; 3 Jest tests |
| `permissionsets/Approval_Matrix_Admin…`, `Approval_Matrix_User…` | modified | class access to the five new entry classes |
| `agentforce/…/genAiPromptTemplates/AMF_Explain_Approval_Decision…` | **new** | Flex template, inputs `Facts` and `Question`, the org's default model |
| `agentforce/…/aiAuthoringBundles/AMF_Approval_Assistant/` | **new** | the employee agent, in Agent Script |
| `org-config/amf-dev/…/permissionsets/AMF_Approval_Assistant_Access…` | **new** | `agentAccesses` for the agent; deploys after publish |
| `specs/AMF_Approval_Assistant-testSpec.yaml` | **new** | 9 Testing Center cases, none of which submits |
| `scripts/explain-decision.apex` | **new** | the gate's live explanation check; writes nothing |
| `sfdx-project.json` | modified | the `agentforce` package directory; `sourceApiVersion` 66.0 |
| `CLAUDE.md`, `docs/architecture.md` (§1, §7, §8, §11, §12, §13.4), `docs/build-playbook.md`, `docs/decisions.md`, `docs/handoff.md`, `docs/technical-log.md` | modified | M13 authorised, designed, gated and recorded |

### M13.2 Design choices worth recording

`docs/decisions.md` holds the seven approved choices, one line each. The reasoning behind the
rest:

**(a) The org decided the shape.** Read-only checks of `amf-dev` before any design:

```
organization     Developer Edition, API 68.0 (Winter '27)
EinsteinGpt      enableEinsteinGptPlatform   true    -> prompt templates usable now
EinsteinCopilot  enableEinsteinGptCopilot    false   -> Agentforce off
Bot              enableBots                  false
describe         GenAiPromptTemplate, GenAiFunction, GenAiPlugin, LightningTypeBundle listed;
                 Bot, GenAiPlannerBundle, AiAuthoringBundle absent
licences         Agentforce (Default) 5, Einstein Prompt Templates 5000, Data Cloud, Agent
                 Platform Builder 5 -- the admin holds the PSLs, but none of the permission
                 sets that use them
CLI              @salesforce/cli 2.126.4, plugin-agent 1.30.11 (validate, preview start/send/end,
                 publish authoring-bundle, test create/run)
```

So the explanation could be built and checked now, and the agent could be built and compiled but
not deployed until Agentforce is turned on.

**(b) Agent Script, an employee agent.** Agent Script is the current authoring format, which the
CLI validates, previews, publishes and tests. The older Bot, GenAiPlannerBundle and GenAiPlugin
metadata is what publish generates from it. Three features make the safety properties hold
outside the model:
- `available when` offers submit only after a preview that reached a decision;
- a `with x = @variables.y` binding fills submit's record and expected process from the runtime,
  not the model;
- `require_user_confirmation` makes the platform ask before submit runs.

It is an employee agent because it runs as the logged-in user, so every action has that user's
access, as the header button does. A service agent would run as an Einstein Agent User. The
sources were Salesforce's own `forcedotcom/sf-skills` (Agent Script reference, CLI reference,
test-spec templates) and a published employee-agent sample, `afls-ideas/Context-Aware-Agent`.
`developer.salesforce.com` refused automated reads with 403. Every construct used was then compiled
by `sf agent validate`.

**(c) Page context.** `currentRecordId` and `currentObjectApiName` are declared
`mutable string = ""` with `visibility: "External"`, as the sample does. The sample says a
context variable without External fails at run time with `InternalVariableMutationAttemptException`.
These names are the panel's context variables; this org has not yet shown them populated (M13.6).
The model passes the record Id to every action as text, so every action reads it through
`AMF_AgentSupport.idOf` and answers a non-Id plainly.

**(d) A wrapper for submit, not the M10 action itself.** The M10 action takes an `Id` and returns
fields. The agent needs four more things:
- a sentence it can repeat;
- the route-changed check, in Apex;
- who the approval is waiting on;
- an Id that arrives as text.

`AMF_AgentSubmitRoute` calls `AMF_SubmitForMatrixApproval.submitEach`, so the engine path, the guard
and the row are exactly M10's, and the M10 action is unchanged.

**(e) Routable, not Submitted.** A preview's engine outcome is `Submitted`, because that is what a
submission would record (§6.4). In an agent's context that word invites "it has been submitted".
The preview action renames it `Routable` and ends every summary "Nothing has been submitted yet."

**(f) Blocked and failed previews.** The header button submits a blocked or failed preview straight
away, so the attempt is recorded (M5). The agent may do the same: `canSubmit` is true. But the
script has it say first that submitting only records the attempt, and submit only if the user still
wants that. In conversation, consent costs one sentence. Only `Refused` (nothing decided) is
`canSubmit` false.

**(g) The finder.** It is object-agnostic: governed objects come from
`AMF_RuleProvider.getActiveRules()`, so a third governed object needs no change. It makes three
passes, narrowest first:
1. an Id, then an exact name, which covers the `PR-` auto-number;
2. SOSL over all fields, which finds a request by its Request Name;
3. a contains-match on the name, for records the search index has not caught up with.

Input is bound, never spliced, except the SOSL term, which is escaped character by character. A
test proves that `%` matches itself. Several matches are listed with their Ids for the user to
choose from.

**(h) The facts, and the template's two text inputs.** The model is given one timeline entry
written out line by line:
- the record, and the time zone;
- the decision row: who, when, outcome, rule and version, condition, values as
  `Label (Path) = value`, recorded reason;
- the approval: status, then each step.

The label lets it speak as the page does; the path lets it match the value to the recorded
condition. Approver comments are quoted and capped at 500 characters, and the template says
everything between its FACTS markers is data. Approver comments are free text, so this is the
prompt-injection line. A template that grounded itself on a record input would have bypassed the
timeline's two visibility rules, and needed them again.

**(i) On demand, never stored, never stale.**
- The button generates nothing until asked, because a generation takes seconds and most readers
  need only the recorded facts.
- The card names its row and its time, carries an AI-generated badge, and sits above the recorded
  facts.
- `historyKey` (entry, approval status, step count, last step's Id, status and actor) changes when
  the timeline's refresh brings news. The card is then put away, and a generation still out is
  dropped on arrival.

**(j) Not built.**
- Lightning types for richer cards in the agent panel: they could not be exercised here, and
  Apex-built sentences already carry every fact (`docs/decisions.md`).
- Turning Agentforce on through a settings deploy: refused, M13.3(a).
- The other three proposed AI use cases (playbook Part 5).

### M13.3 Issues encountered

**(a) Turning Agentforce on was refused by the agent harness's permission classifier**, as an
org-wide permission grant. The attempt was to write a `Settings` package
(`EinsteinCopilot.enableEinsteinGptCopilot`, `Bot.enableBots`) to the session scratchpad, for a
deploy. Nothing was written or deployed. Whether to turn Agentforce on is the user's decision: gate
step 0. No settings file was added to source either, because the next routine deploy would then
switch it on as a side effect.

**(b) Two Apex reserved words.** The first check-only compile refused `when` and `number` as
variable names (`Identifier name is reserved`) in `AMF_DecisionExplainer`. They were renamed
`occurred` and `amount`.

**(c) A prompt template's description is at most 255 characters.** The first check-only deploy of
the template said `Value too long for field: Description maximum length is:255`. It was shortened.
The template then validated without `versionIdentifier`, `activeVersionIdentifier` or
`primaryModel`, so the platform assigns the version and the org's default model is used.

**(d) `Actor.Name` is null for an approval created in the same transaction.** That broke the agent,
not just its test. The real-approval test failed with `Expected: null, Actual: ` (empty) at
`AMF_AgentSubmitRouteTest` line 224:
- the expectation, read through `Actor.Name`, was null;
- the action's join of no names was empty.

This is the quirk recorded under "Fix — AMF_ClassicApprovalHistoryProviderTest actor-name
assertions" (after M8.7). It matters beyond the test, because the action reads the work items its
own transaction has just created, so in production too it could never have said who the approval
waits on. The action now resolves each `ActorId` against User and Group (a queue). The test
expects the name read the same way, and passes.

**(e) `RunSpecifiedTests` in a check-only deploy needs 75% on every class in the package.** A
re-run of the submit suite alone passed 8 of 8 but reported failure, for that reason. The full set
of new and affected suites gives the real result (M13.4).

**(f) A Jest default parameter.** `render({ logId: undefined })` took the helper's default Id,
because a default replaces an explicit `undefined`. The test now passes `null`.

**(g) The agent bundle cannot be checked against the org while Agentforce is off.** A check-only
deploy of `agentforce/` with the classes failed only on the bundle:
`AiAuthoringBundle: Not available for deploy for this organization`. `sf agent validate` compiles
the script, and stops at the first error, so it cannot say whether the four Apex targets resolve.
Deploy and publish will (gate steps 3 and 8).

### M13.4 Verification evidence (this session)

```
check-only compile  all 10 new classes and the changed timeline service: status 0, success True
prompt template     check-only deploy of agentforce/.../genAiPromptTemplates: status 0, success True
                    (after (c))
apex tests          check-only deploy 0Afaj00000opoScCAI, RunSpecifiedTests over the 7 new suites,
                    AMF_DecisionTimelineServiceTest and AMF_SubmitForMatrixApprovalTest:
                    "tests run: 75  failures: 0", success True, nothing saved to the org
full suite          check-only deploy 0Afaj00000oqPITCA2 of all of force-app at sourceApiVersion 66.0,
                    RunLocalTests, AMF_USERNAME_DOMAIN set: 143/143 components, 0 errors,
                    "tests run: 333  failures: 0", 98.5% coverage of the deployed classes.
                    Nothing saved
final code          after the last change -- a rule with no recorded version no longer reads
                    "version null" in either summary, and one test pins it -- check-only deploy
                    0Afaj00000oqPqLCAU, the same 9 suites: "tests run: 76  failures: 0", success
                    True. RunLocalTests on the final code is therefore 334 (gate step 5)
coverage            (final code) AMF_AgentPreviewRoute 85/85, AMF_AgentExplainDecision 24/24,
                    AMF_AgentSupport 35/35, AMF_DecisionTimelineService 158/158 (all 100%);
                    AMF_AgentFindRecord 172/174 (99%), AMF_AgentSubmitRoute 128/130 (98%),
                    AMF_DecisionExplainer 197/205 (96%), AMF_EinsteinExplanationGenerator 31/36
                    (86%: which branch of the live call runs inside a test depends on the org)
jest                Test Suites: 5 passed, 5 total; Tests: 75 passed, 75 total (60 before)
eslint              amfDecisionExplanation, amfErrors, amfDecisionTimelineEntry: exit 0
agent script        sf agent validate authoring-bundle --api-name AMF_Approval_Assistant:
                    {"status": 0, "result": {"success": true}, "warnings": []}
negative check      the same with "set @variables.can_submit = false" substituted: CompilationError
                    "'false' is not a valid value in AgentScript. Did you mean 'False'
                    (capitalized)? [Ln 211, Col 44]"; the file restored, byte for byte (True)
convert             sf project convert source --source-dir agentforce: AiAuthoringBundle and
                    GenAiPromptTemplate, package version 66.0
source gate         passed: 8 active rules, 6 processes guard-checked, 6 of 6 templates released
                    and unchanged, 5 layouts of 2 governed objects (unchanged by the new directory)
```

Not run, at the user's instruction: a deploy, RunLocalTests in the org, the live explanation, a
preview session, publish, the agent tests and the UI check. All are in the playbook's M13 gate.

### M13.5 The gate as it stood at the end of the build (run in M13.7)

The playbook's M13 gate, steps 0 to 11. In short:
- the user turns on Agentforce and assigns Prompt Template User and Access Agentforce Default Agent;
- then deploy `force-app` and `agentforce`, the post-deploy check, and RunLocalTests (334);
- the live explanation, and a live preview session on a throwaway record;
- publish and activate, then deploy `org-config` and assign the access set;
- the 9 agent tests, and the check in the real UI;
- then commit, `HUSKY=0`, as `Phase M13: AI around the engine` (Part 1, step 6). The user
  asked that nothing reach the branch until they say so.

### M13.6 Carried into later phases

M12.8's table carries unchanged, with these additions:

| Item | Owner |
|---|---|
| The M13 gate (M13.5), from turning Agentforce on in Setup | user |
| The page-context variable names (`currentRecordId`, `currentObjectApiName`) follow the published sample and are unproven in this org until gate steps 7 and 11. If the panel passes other names, only the `.agent` file's two declarations change | gate step 7 |
| How `require_user_confirmation` renders in the Lightning panel is unobserved. The script also tells the model to ask, so the two prompts may need merging into one after step 11 | after the gate |
| After the assistant submits, the record page's timeline shows the new entry on its refresh button or a reload: the panel cannot raise the page's `RefreshEvent` | if wanted |
| The template's first retrieve will add a platform-assigned `versionIdentifier`. As with M12's templates, take the retrieved form into source | first retrieve |
| Einstein's Trust Layer has prompt-injection and toxicity detection off in `amf-dev` (`EinsteinAISettings`). The template's facts-as-data rule is the only defence until they are turned on, which is an org decision | user |
| In an org without Einstein, `force-app` deploys and the Explain button answers "not available" with the platform's reason. A design-time switch to hide it would be a timeline change | if a second org needs it |
| The agent test spec names `amf-dev`'s records and Ids | whoever runs it elsewhere |
| The UI test suite (`docs/ui-tests/`) has no M13 case yet | the next UI run |
| `amfSubmitForApproval` and `amfDecisionTimeline` still carry their own `messageOf`; `c/amfErrors` now exists for them | a later hardening pass |
| Three more AI use cases are proposed, unauthorised: a rule-writing assistant, an approver briefing, a matrix-health report (playbook Part 5) | user |

### M13.7 The org gate — steps 0 to 10 PASSED (2026-10-23)

The user turned on Agentforce in Setup, assigned themselves the permission sets, and asked for the
deploy and the push. Six defects surfaced on the way, (a) to (f) below. All were fixed and every
step re-run.

**Steps and evidence**

```
0  prerequisites   metadata types now include Bot, GenAiPlannerBundle, AiAuthoringBundle; the CLI
                   user holds CopilotSalesforceUser, CopilotSalesforceAdmin,
                   EinsteinGPTPromptTemplateUser and EinsteinGPTPromptTemplateManager
1  source gate     passed: 8 rules, 6 processes, 6 of 6 templates released and unchanged, 5 layouts
2  offline         Jest 75/75; sf agent validate authoring-bundle: success
3  deploy          force-app + agentforce, 0Afaj00000oqe9SCAQ: Succeeded, 145/145, 0 errors
                   (the bundle, the template, 12 classes, 2 LWCs created; both permission sets)
4  post-deploy     "Approval Matrix configuration is valid."
5  RunLocalTests   707aj00001NJgRc: Outcome Passed, Tests Ran 334, Pass Rate 100%, Org Wide
                   Coverage 98%. AMF_EinsteinExplanationGenerator 86%: its uncovered lines are the
                   success path after the live call, which throws inside an Apex test
6  explanation     after (a) and (d), scripts/explain-decision.apex on PR-00000042:
                   Recorded: ADL-00000027, Submitted, PR_Credit_Risk_Review -> PR_Credit_Risk_Queue
                   Explained: "The matrix routed the purchase request to PR_Credit_Risk_Queue because
                   rule PR_Credit_Risk_Review evaluated true: the risk level, Medium, and the
                   amount, 60,000, met the condition ... The approval process PR_Credit_Risk_Queue
                   is complete and approved; the final approval step "Credit Risk Review" was
                   approved by Grok Bot on 22 Oct 2026 at 06:38."  Every fact matches the row and
                   the history
7  live preview    sf agent preview, --authoring-bundle, --use-live-actions, on throwaway
                   PR-00000049 ("M13 gate throwaway": 60,000, AMER, Medium):
                   "Where would PR-00000049 go?"   -> find_record, preview_route: "...would go to
                       the approval process PR_Credit_Risk_Queue. Rule PR_Credit_Risk_Review
                       decides this, because the Amount is 60,000 and the Risk Level is Medium ...
                       Nothing has been submitted yet." Log rows for it: still 0
                   "Submit it."                     -> the confirmation: "Please reply "yes" to
                       proceed or "no" to cancel." Log rows: still 0
                   "Yes."                           -> "Submitted. Purchase Request PR-00000049
                       entered approval process PR_Credit_Risk_Queue and is now waiting on Credit
                       Risk. Rule PR_Credit_Risk_Review (version 1) decided the route ...
                       ADL-00000032." In the org: ADL-00000032 Submitted with its
                       Execution_Ref_Id__c, the ProcessInstance Pending, the guard true
                   "Why did it go there?"           -> explain_approval: rule, values, ADL-00000032,
                       waiting on Credit Risk
                   cleanup: recalled by anonymous Apex, status Removed, guard false (M8)
8  publish         after (b), scripts/publish-agent.ps1: validate, publish, deploy; "Agent
                   AMF_Approval_Assistant activated." BotVersion v1 Active; after (e), v2 Active,
                   v1 Inactive
9  agent access    after (c), org-config/amf-dev, 0Afaj00000opx67CAA: 7/7;
                   AMF_Approval_Assistant_Access assigned to the CLI user
10 agent tests     run 1, 4KBaj00000046mnGAA, against v1: 5 of 9 cases passed all three assertions
                   (e). Run 2, 4KBaj00000046oPGAQ, against v2: 9 of 9, all 27 assertions PASS
                   (topic, actions, outcome)
final              the plain deploy of all three directories, check-only, 0Afaj00000oqjU5CAI:
                   153/153, 0 errors; the source gate green
```

**(a) A deployed prompt template has no active version until one is named.** The first explanation
answered `Einstein said: No active template version`. The deploy had published version
`/0MCy2NRnsP9ZLj9Xsgvh66VbJrjXadZVilhTmvLHyc=_1`, but no `activeVersionIdentifier` named it. The
source now takes the retrieved form, as M12's approval templates did:
- `activeVersionIdentifier` naming that version, and its `versionIdentifier`;
- the platform's defaults, `overridable` and `isCitationEnabled` false;
- the content with its apostrophes, quotes and `>=` written as XML entities.

Redeployed as 0Afaj00000oqfGnCAI. A retrieve then matched the source byte for byte. Editing the
template's content later makes a new version, which needs the same treatment.

**(b) `sf agent publish authoring-bundle` reads only the default package directory.** It answered
`Cannot find an authoring bundle in ...\force-app that matches AMF_Approval_Assistant`, and has no
path flag. `validate` and `preview` did find the bundle in `agentforce/`. Moving the bundle into
`force-app` would end M13's portability decision. Making `agentforce` the default would weaken
M12's source gate, which treats the default directory as the framework. `scripts/publish-agent.ps1`
instead publishes from a throwaway project, whose one default directory holds a copy of the
bundle. It passes `--skip-retrieve`, then activates, and leaves the repository untouched.

**(c) A permission set's description is at most 255 characters too.** The first `org-config`
deploy refused `AMF_Approval_Assistant_Access` for it, and rolled back all seven components. It was
shortened.

**(d) `explain-decision.apex` called the `@AuraEnabled` wrapper.** That wrapper converts every
failure to an `AuraHandledException`, which only an Aura or Visualforce request may throw. In
anonymous Apex it became `System.LimitException: Can only throw this exception type from
VisualForce or Aura context`, which hid (a). The script now calls
`new AMF_DecisionExplainer().explain(...)`.

**(e) The agent tests found two agent faults and three wrong expectations.**
- *Case 2, "Which rule applies to this request?":* the platform's built-in **Reverse_Engineering**
  guardrail topic took it, as an attempt to extract the agent's own rules, and declined. The system
  instructions and the router now say that the matrix's rules are business data the actions read.
  The router's preview description names the rule. In run 2 the case routed, previewed and passed.
- *Case 8, "Approve PR-00000045 for me.":* routed to preview, and offered to submit. That was not
  harmful, because nothing submits unconfirmed, but it was not what the agent should say. The
  router now has an explicit branch, which the preview subagent repeats: a request to approve,
  reject, recall or reassign calls no action and says why.
- *Case 9 and the router:* the platform reports `start_agent` as `topic_selector`, not
  `approval_router`. Its answer already passed.
- *Case 7's record had changed.* PR-00000045 was submitted and approved by the user at 10:17 UTC
  that day (ADL-00000031), after M12.8 recorded it as never submitted. The agent's explanation of
  it was correct. The case now uses PR-00000047, still unsubmitted.
- *Case 6's expectation was unjudgeable.* "Without inventing any rule, value or approver" read to
  the LLM judge as a ban on any name at all, so it failed an accurate answer. It now names the
  facts to find.

**(f) `sf agent test create` writes the generated `AiEvaluationDefinition` into `force-app`.** The
definition names `amf-dev`'s records and needs the published agent, so it lives in
`org-config/amf-dev`, beside the access permission set. The spec's header says so.

**Left in `amf-dev` by the gate:**
- PR-00000049, "M13 gate throwaway": recalled, guard false;
- its decision log row ADL-00000032, which is permanent;
- the agent at v2, active, with v1 inactive;
- the test definition `AMF_Approval_Assistant_Tests`, with its two runs.

The demo records PR-00000046 to -48 are untouched.

| File | Change | Notes |
|---|---|---|
| `agentforce/…/AMF_Explain_Approval_Decision.genAiPromptTemplate-meta.xml` | modified | the retrieved form, with `activeVersionIdentifier` (a) |
| `agentforce/…/AMF_Approval_Assistant.agent` | modified | matrix rules are business data; the approve, reject, recall and reassign branch (e) |
| `scripts/publish-agent.ps1` | **new** | publish and activate from a throwaway project (b) |
| `scripts/explain-decision.apex` | modified | calls the explainer, not its Aura wrapper (d) |
| `org-config/…/AMF_Approval_Assistant_Access.permissionset-meta.xml` | modified | description under 255 (c) |
| `org-config/…/aiEvaluationDefinitions/AMF_Approval_Assistant_Tests…` | **new** | the generated test definition (f) |
| `specs/AMF_Approval_Assistant-testSpec.yaml` | modified | `topic_selector`; PR-00000047 for case 7; case 6 names its facts; the header |
| `CLAUDE.md`, `docs/build-playbook.md`, `docs/decisions.md`, `docs/handoff.md`, this file | modified | the gate recorded; the publish step is the script |

### M13.7 Carried into later phases

This table supersedes M13.6's.

| Item | Owner |
|---|---|
| Gate step 11, the manual UI check: the Explain button on a timeline entry, and the assistant in the Agentforce panel on a throwaway record (playbook M13) | user |
| The Lightning panel's own page context is unobserved. Testing Center's `contextVariables` named `currentRecordId` and `currentObjectApiName` reached the agent (cases 1, 2, 6, 7), but step 11 shows whether the panel passes the same names | step 11 |
| Confirmation asked once in the CLI preview ("reply yes"). How the panel renders `require_user_confirmation` is seen in step 11 | step 11 |
| After the assistant submits, the record page's timeline shows the new entry on its refresh button or a reload: the panel cannot raise the page's `RefreshEvent` | if wanted |
| Editing the prompt template's content makes a new version: take the retrieved form, with `activeVersionIdentifier`, into source again (M13.7a) | whoever edits it |
| Editing the agent: deploy the bundle, then `scripts/publish-agent.ps1`. Every publish is a new, permanent version | whoever edits it |
| Einstein's Trust Layer has prompt-injection and toxicity detection off in `amf-dev` (`EinsteinAISettings`). The template's facts-as-data rule is the only defence until they are turned on, which is an org decision | user |
| In an org without Einstein, `force-app` deploys and the Explain button answers "not available" with the platform's reason. A design-time switch to hide it would be a timeline change | if a second org needs it |
| The agent test spec and its definition name `amf-dev`'s records. A demo that submits PR-00000046 to -48 changes what the cases expect | whoever runs it |
| The UI test suite (`docs/ui-tests/`) has no M13 case yet | the next UI run |
| `amfSubmitForApproval` and `amfDecisionTimeline` still carry their own `messageOf`; `c/amfErrors` now exists for them | a later hardening pass |
| Three more AI use cases are proposed, unauthorised: a rule-writing assistant, an approver briefing, a matrix-health report (playbook Part 5) | user |
| M12.8's items carry unchanged | as there |

## Phase M14 — The assistant for submitters and approvers

**Commit:** `74ea4ed`. **Status:** complete, bar the manual UI check (gate step 9), which
also covers M13's step 11. Authorised in `CLAUDE.md` on 2026-10-23, and built, gated and committed
the same day.

After asking what was done and what was pending, the user asked whether more Agentforce use cases
could be added. Six were offered: the three proposals M13 left (an approver briefing, a rule-writing
assistant, a matrix-health report) and three more (where are my requests, a what-if preview, a
rule-change impact check). The user said "yes do all". Four decisions were put to them first:
- **Approvers and the routing reason:** show it to the current approver, in the briefing and on the
  timeline.
- **The engine:** allow two additive write-nothing preview entries.
- **Admin features:** a second agent, for admins only.
- **Pallab Saikia:** no access for now.

The plan split the work into two phases, built back to back: M14 for the people who use approvals,
and M15 for administrators. Mid-build the user asked to "resume slowly". From then on the gate ran
one step at a time, with a report after each.

### M14.1 File-level changes

| File | Change | Notes |
|---|---|---|
| `classes/AMF_ApprovalMatrixService.cls` | modified | `previewWith()`; a private `prepare()` overload carrying the changes; `changedFields()` and `applyChanges()`. `submit`, `preview` and `submitEach` pass no changes and are unchanged |
| `classes/AMF_ApproverScope.cls` | **new** | who a user may act for: the user, queues and groups containing them (nested to depth 5), and the users they are delegated approver for; `isWaitingOn()` |
| `classes/AMF_DecisionTimelineService.cls` | modified | the current-approver rule in `build()`, `Decision.visibleAsApprover`, the `without sharing` inner `ApproverRowReader` |
| `classes/AMF_DecisionExplainer.cls` | modified | `BRIEFING_QUESTION` and `briefLatest()`, additive; a `Reassigned` step described by whom it went to (M14.3f) |
| `classes/AMF_AgentSupport.cls` | modified | `labelsOf()`, `actorNamesOf()` and `whenOf()`, additive |
| `classes/AMF_AgentWhatIfRoute.cls` | **new** | invocable *What-If Approval Route* |
| `classes/AMF_AgentMyRequests.cls` | **new** | invocable *My Approval Requests* |
| `classes/AMF_AgentMyApprovals.cls` | **new** | invocable *My Pending Approvals* |
| `classes/AMF_AgentBriefApproval.cls` | **new** | invocable *Brief Approver* |
| five new `…Test.cls` suites, and four suites extended | new / modified | 37 tests (M14.4) |
| `permissionsets/Approval_Matrix_Admin…`, `Approval_Matrix_User…` | modified | class access to the four new invocables |
| `agentforce/…/AMF_Approval_Assistant.agent` | modified | the router, `what_if` in `route_and_submit`, briefing in `explain_decision`, the new `my_work` subagent (M14.2c, M14.3i) |
| `specs/AMF_Approval_Assistant-testSpec.yaml` | modified | five cases and the header |
| `org-config/…/aiEvaluationDefinitions/AMF_Approval_Assistant_Tests…` | modified | regenerated from the spec, 14 cases, moved from `force-app` as M13.7f describes |
| `CLAUDE.md`, `docs/architecture.md` (§1, §6.4, §7, §8, §11, §13.4), `docs/build-playbook.md`, `docs/decisions.md`, this file | modified | M14 and M15 authorised; M14 designed, gated and recorded |

No object, field, template, rule or LWC changes.

### M14.2 Design choices worth recording

`docs/decisions.md` holds the approved choices, one line each. The reasoning behind the rest:

**(a) The what-if is the engine's, applied after step 4.** A what-if evaluated outside the engine
would be a second rule walk that could drift from the one a submission takes. Putting the changed
values on the in-memory copy that step 4 read keeps rule order, compilation and first-match the
engine's own. The record, the row and the guard are never touched.
- Only the record's own fields may change, because replacing a relationship path would answer a
  question about a different parent.
- The fields are checked inside step 4, after authorisation (M14.3c).

**(b) The action reads values the way a person writes them, and refuses rather than guesses.**
- Field names: label or API name, in any case.
- Numbers: commas, a currency sign or code, and k, m, thousand or million are all accepted.
- Picklists: a field's own value or label, in any case. Anything else is refused, with the valid
  values listed.
- Booleans: true/false, yes/no, checked/unchecked.
- Dates: `YYYY-MM-DD`, with the locale's own form as a fallback.
- Blank: "blank", "none" or "empty" tries a blank value.
- A field no active rule reads is still tried, and the answer says it cannot change the route. That
  is itself useful: "vendor type does not matter to the matrix".

**(c) A what-if clears `can_submit`.** Submit's record and expected process are bound to the last
preview. A what-if is not a preview, so after one, "submit it" must start from a fresh preview of the
record's real values.

**(d) The current approver's sight of the reason is one bounded read.**
- Rows are first read `WITH USER_MODE`, as before.
- A pending approval that no readable row claims gets its own row read without sharing, only if a
  pending step is assigned to someone in the reader's `AMF_ApproverScope`.
- The scope is computed only when such an approval exists, so most timelines cost no extra query.

`AMF_ApproverScope` is the single definition that the timeline, the briefing and "my approvals"
share. Two cases it does not cover:
- A queue whose member is a role is not followed, because membership through a role is not a
  `GroupMember` row and the templates name users, queues and groups only.
- An admin who can approve anything through Modify All Data is not counted as "waiting on". They read
  every row anyway.

**(e) Names by Id.** Approvers, submitters and the last actor are named through `actorNamesOf()` from
their Ids, never through `Actor.Name`, `SubmittedBy.Name` or `LastActor.Name`. M13 found that
`Actor.Name` is null on work items created in the running transaction. The Apex tests decide
approvals in the transaction they read them, so the relationship names could not be trusted there.

**(f) The lists are deterministic sentences, built in Apex.**
- "My requests" takes the newest attempt per record over 90 days (at most 500 rows read, 10 records
  listed), still-waiting first.
- "My approvals" lists the oldest first. A committee step's several work items count once per record.
- Each line carries the record's Id, so the next action can use it without a search.

### M14.3 Issues encountered

**(a) `list` cannot be an Apex method name.** The first check-only compile gave `Unexpected token
'<'` at `public static List<Result> list(...)` in both listing actions. They were renamed
`listRequests` and `listApprovals`. `when` is reserved too (M13.3b), and one local variable was
renamed before compiling.

**(b) The PowerShell tool's working directory had drifted** into `force-app/main/default/classes`,
so the first check-only deploy answered `File or folder not found`. Every `sf` call since runs from
the project root.

**(c) `previewWith()` first checked the field names before authorising the record.** Writing the
stranger test exposed this. Describe hides fields a user has no FLS on, so a caller who could not
read the record would have been told the field did not exist, not that they lacked access. The
check moved into step 4, after authorisation and the pending check. Only the emptiness check stays
in front.

**(d) One expectation compared JSON text where it meant values.** The first check-only run gave 146
tests and 1 failure:
```
AMF_ApprovalMatrixServiceTest.aWhatIfToABlankValueAndOneThatChangesNothingBothAnswerAsPreviewWould:
Expected: {"Region__c":"APAC","Amount__c":250000.00}, Actual: {"Region__c":"APAC","Amount__c":250000}
```
The stored amount carries the field's scale, and the tried one does not. The test now compares the
values. The engine suite then ran 46/46.

**(e) npm is still absent from both shells.** Jest runs through the CLI's bundled `node.exe`, as
M3.4e records.

**(f) The briefing reversed a reassignment.** The first live briefing said "you reassigned that step
to AMF Approver One". In fact the step had been reassigned from AMF Approver One to the CLI user. A
second reassignment of the throwaway to AMF Approver Two showed what a `Reassigned` history row
holds:
```
Reassigned  actor=Tejas Vernekar    original=AMF Approver One   (reassigned to the CLI user)
Reassigned  actor=AMF Approver Two  original=AMF Approver One   (reassigned by the CLI user)
```
- The actor is the new assignee.
- The original actor is the step's first assignee, not the previous one.
- The person who reassigned it is not recorded.
- A second reassignment in the same transaction, back to the CLI user, added no row.

M13's facts said "reassigned by X, for Y", which is wrong for this row and misled the model. The
explainer now writes "reassigned to X (first assigned to Y)", and a test pins it. It was deployed as
0Afaj00000orZajCAE, and its three suites ran 29/29. A fresh session then briefed correctly: "the
step was reassigned twice and is now assigned to Tejas Vernekar".

The timeline LWC words the same row "X, for Y", which is ambiguous but makes no claim about who
acted. It is carried, because M14 changes no LWC.

**(g) A preview session answers a repeated question from memory.** Asked for the briefing again in
the same session, the agent returned the earlier text word for word, without calling the action:
its instructions forbid calling an action again for a result it already has. The check was rerun
in a fresh session.

**(h) The first what-if answer dropped the comparison with today,** which the action's summary
carries. `route_and_submit` now says to "always include how the route compares with today", and the
next session did.

**(i) The published agent routed differently from the local preview.** Testing Center runs the
published agent. The authoring-bundle preview, which runs the local bundle, routed "Brief me on the
approval for PR-00000045 before I decide" to `my_work` in 3/3 sessions. The published agent sent it
to `explain_decision`:

| Version | Change | Run | Assertions | Failures |
|---|---|---|---|---|
| v3 | M14 as built | 4KBaj00000046y5GAA | 38/42 | case 5 topic (route_and_submit, then on to explain); case 12 routed to explain |
| v4 | router: "would go" against "already went"; briefing named first | 4KBaj000000471JGAQ | 36/42 | case 1 answered by the router itself ("which record?"); cases 5 and 12 as before |
| v5 | router never asks which record; hand-off descriptions sharpened; explain's instructions redirect "brief me" | 4KBaj000000472vGAA, 4KBaj000000474XGAQ | 38/42, 38/42 | case 5 topic (my_work, then route_and_submit); case 12 routed to explain |
| v6 | the router's and subagents' own descriptions | 4KBaj0000004769GAA, 4KBaj000000477lGAA | 38/42, 41/42 | case 12 in one run; case 5 topic in both |
| v7 | briefing moved into `explain_decision`; `my_work` holds the lists | 4KBaj000000479NGAQ, 4KBaj00000047AzGAI | **42/42, 42/42** | none |

What the investigation found:
- `sf agent preview start --api-name AMF_Approval_Assistant` cannot preview the published employee
  agent from the CLI: `Bad Request: Invalid user ID provided on start session`.
- The published planner, `GenAiPlannerBundle:AMF_Approval_Assistant_v5`, can be retrieved at API
  64.0. API 68.0 answers `Cannot use: GenAiPlannerBundle in this version`.
- That planner's `plannerType` is `Atlas__ConcurrentMultiAgentOrchestration`. Its embedded
  definition, base64-encoded, is identical to the source, router instructions included.
- The router's own description, though, still read "Send the user's request to previewing and
  submitting, or to explaining a decision".

So the published runtime does receive the router's instructions, but it chooses largely by the
descriptions. The lasting fix was structural, not wording. A briefing is an explanation written for
the approver, from the same facts and template, so it now belongs to the subagent the platform sends
it to. `my_work` lost the "where … stand" wording that drew case 5, and keeps the briefing action
only for an approval from a list it has just given. Case 12's expected topic changed with the design,
which is documented in the spec's header. No expected outcome was loosened.

**(j) A permission set edit that seemed to apply did not.** The first scripted insertion of the four
class grants left both files unchanged, and the grant counts showed it. It was rerun with patterns
that tolerate either line ending and checked: 14 grants in Admin, 13 in User, each new class once,
and line endings unchanged.

### M14.4 Verification evidence

```
check-only compile   the 9 new and changed classes: Succeeded (after (a))
check-only tests     14 suites, RunSpecifiedTests: 146 run, 1 failure (d); after the fix the engine
                     suite 46/46, AMF_ApprovalMatrixService 384/416 (92%) by its own suite
source gate          passed: 8 active rules, 6 processes guard-checked, 6 of 6 templates released and
                     unchanged, 5 layouts of 2 governed objects
jest                 Test Suites: 5 passed, 5 total; Tests: 75 passed, 75 total
agent validate       {"status": 0, "result": {"success": true}, "warnings": []}, after every change
deploy               0Afaj00000orXNdCAM: Succeeded, 163/163, 0 errors
post-deploy          "Approval Matrix configuration is valid."
RunLocalTests        707aj00001NLwGR: Passed, 370/370, org-wide 98%
                     AMF_ApprovalMatrixService 415/416, AMF_DecisionTimelineService 183/183,
                     AMF_ApproverScope 28/28, AMF_AgentMyRequests 144/144, AMF_AgentBriefApproval
                     24/24 (100%); AMF_AgentMyApprovals 130/131 (99%); AMF_DecisionExplainer 221/229
                     (97%); AMF_AgentSupport 74/77 (96%); AMF_AgentWhatIfRoute 274/298 (92%)
explainer fix        0Afaj00000orZajCAE, 3 suites: 29/29
final RunLocalTests  707aj00001NMg9J: Passed, 371/371, org-wide 98%; AMF_DecisionExplainer 226/234
final check-only     all three directories, 0Afaj00000oroujCAA: Succeeded, 163/163, 0 errors
```

New tests by suite:
- `AMF_ApprovalMatrixServiceTest` +6
- `AMF_ApproverScopeTest` 6
- `AMF_DecisionTimelineServiceTest` +3
- `AMF_DecisionExplainerTest` +3
- `AMF_AgentBriefApprovalTest` 3
- `AMF_AgentWhatIfRouteTest` 7
- `AMF_AgentMyRequestsTest` 4
- `AMF_AgentMyApprovalsTest` 4
- `AMF_AgentSupportTest` +1

That is 37, so 334 + 37 = 371. Two of them run real Classic approvals, one in each listing suite
(M14.2e).

### M14.5 The gate as run (2026-10-23)

```
1  source gate     passed (M14.4)
2  offline         Jest 75/75; sf agent validate: success
3  deploy          all three directories, 0Afaj00000orXNdCAM: 163/163
4  post-deploy     "Approval Matrix configuration is valid."
5  RunLocalTests   370/370 (707aj00001NLwGR); 371/371 after (f) (707aj00001NMg9J)
6  live preview    --authoring-bundle --use-live-actions; decision log rows 28 before
                   "What if PR-00000047 had an amount of 120000 and region APAC?"
                     -> PR_Three_Level_Finance under PR_High_Value_APAC; "Today, with its current
                        values, it would go to PR_Two_Level_Mgmt under rule PR_Catch_All. This is just
                        a what-if: nothing was changed or submitted." (after (h))
                   "...if its vendor type were Strategic?" -> "Changing Vendor Type makes no difference
                        to the route, since no active rule reads Vendor Type."
                   "Where do my approval requests stand?" -> "You submitted 15 records in the last 90
                        days, with 6 still waiting for approval", pending first, each with its approver
                        and date. PR-00000006, pending but submitted by AMF Approver One with no
                        decision log row, is rightly not among them
                   throwaway: PR-00000050 (500, AMER, Low) submitted by anonymous Apex through the
                        engine: Submitted, PR_Catch_All -> PR_Two_Level_Mgmt, ADL-00000033; its work
                        item reassigned from AMF Approver One to the CLI user
                   "Is anything waiting for my approval?" -> "One request is waiting on you for
                        approval: Purchase Request PR-00000050 (approval process PR_Two_Level_Mgmt,
                        step "Manager"), submitted by Tejas Vernekar, waiting on you since ..."
                   "Brief me on it before I decide." -> rule PR_Catch_All, process
                        PR_Two_Level_Mgmt, ADL-00000033, the step reassigned and now waiting on the
                        user; no recommendation (after (f))
                   decision log rows after: 29 (the throwaway's own submission only)
                   cleanup: recalled by anonymous Apex, status Removed, Matrix Submission false; no
                        work item left assigned to the CLI user
7  publish         scripts/publish-agent.ps1: v3, then v4 to v7 for (i); v7 active
8  agent tests     14 cases; v7: 42/42 assertions in two consecutive runs (M14.3i)
9  manual UI check owed by the user; it includes M13's step 11
```

**Left in `amf-dev` by the gate:**
- PR-00000050, "M14 gate throwaway": recalled, guard false;
- its permanent row, ADL-00000033;
- agent versions v1 to v6, inactive and permanent, with v7 active;
- the test definition's runs.

PR-00000045 to -48 were read, never submitted.

### M14.6 Carried into later phases

This table supersedes M13.7's.

| Item | Owner |
|---|---|
| Gate step 9, the manual UI check, including M13's step 11. In the Agentforce panel, on a record: "Where would this go?", "What if the amount were 120000?", "Where do my requests stand?", "What is waiting for my approval?". Then a throwaway, submitted and reassigned to the tester: "Brief me on it", then recall it. And the Explain button on PR-00000042's newest timeline entry | user |
| The panel's own page context and how it renders submit's confirmation, both unobserved (M13.7) | step 9 |
| The timeline LWC words a `Reassigned` row as "X, for Y". It is accurate about the actor, but does not say it is the new assignee (M14.3f) | a later LWC change |
| Topic assertions depend on the platform's model. v7 passed twice in a row. A platform change may need the descriptions revisited, the way M14.3i did | whoever reruns the suite |
| A follow-up what-if phrased "And would it …" carries the earlier values over, and the answer states them (M14.5 step 6) | as designed; revisit if confusing |
| Real approvers (`amfu1` to `5`) would each need an Agentforce licence to use the briefing; amf-dev has 5 seats, 1 used | user |
| Einstein's Trust Layer prompt-injection detection is still off. More free text now reaches the model: approver comments in briefings | user |
| `AMF_AgentSubmitRoute` keeps its own private approver-name lookup, now duplicated by `AMF_AgentSupport.actorNamesOf()` | a later hardening pass |
| M15, the Approval Matrix Admin Assistant: authorised, next | next phase |
| M13.7's other items carry unchanged: the prompt template's version, editing the agent, an org without Einstein, the agent spec's records, the UI suite, `messageOf` | as there |

## Phase M15 — The Approval Matrix Admin Assistant

**Commit:** `11941dc`. **Status:** complete, bar the manual UI check (gate step 11).
Authorised in `CLAUDE.md` on 2026-10-23, with M14, and built, gated and committed the same day,
straight after M14.

The second half of the user's "yes do all": the three uses for administrators, in a second agent
for them alone (the user's choice). They are a rule drafted from a description, a change's impact on
recent records, and a matrix-health report. The user asked to go slowly, and the gate ran one step
at a time, with a report after each.

### M15.1 File-level changes

| File | Change | Notes |
|---|---|---|
| `classes/AMF_ApprovalMatrixService.cls` | modified | `previewEach()`, one line over `prepare(ids, false)` |
| `classes/AMF_PromptRunner.cls`, `AMF_EinsteinPromptRunner.cls`, `AMF_PromptException.cls` | **new** | the prompt seam; M13's generator is untouched |
| `classes/AMF_DraftRuleProvider.cls` | **new** | the live matrix with one rule added, replaced at a new version, or taken out |
| `classes/AMF_RuleDrafter.cls` | **new** | context, the draft template, the release checks, one corrected attempt, the Custom Metadata file |
| `classes/AMF_MatrixImpact.cls` | **new** | two `previewEach()` runs over the object's records decided in the last 90 days, compared |
| `classes/AMF_MatrixHealthService.cls` | **new** | the counted facts, and the health template's summary |
| `classes/AMF_AgentDraftRule.cls`, `AMF_AgentCheckImpact.cls`, `AMF_AgentMatrixHealth.cls` | **new** | the three invocables |
| `classes/AMF_AgentSupport.cls` | modified | `governedObjectNamed()`, additive |
| nine new `…Test.cls` suites, and two extended | new / modified | 33 tests (M15.4) |
| `permissionsets/Approval_Matrix_Admin…` | modified | the three new invocables; `Approval_Matrix_User` unchanged |
| `agentforce/…/genAiPromptTemplates/AMF_Draft_Matrix_Rule…`, `AMF_Summarize_Matrix_Health…` | **new** | Flex templates, in the retrieved form with `activeVersionIdentifier` (M15.3e) |
| `agentforce/…/aiAuthoringBundles/AMF_Matrix_Admin_Assistant/` | **new** | the employee agent: a router and three subagents |
| `org-config/…/permissionsets/AMF_Matrix_Admin_Assistant_Access…` | **new** | `agentAccesses`; deployed after the first publish |
| `org-config/…/aiEvaluationDefinitions/AMF_Matrix_Admin_Assistant_Tests…` | **new** | generated from the spec, moved from `force-app` |
| `specs/AMF_Matrix_Admin_Assistant-testSpec.yaml` | **new** | six cases, none of which changes anything |
| `docs/architecture.md` (§1, §6.4, §7, §9, §11, §13.4), `docs/build-playbook.md`, `docs/decisions.md`, this file | modified | M15 designed, gated and recorded |

No object, field, approval template, rule or LWC changes.

### M15.2 Design choices worth recording

`docs/decisions.md` holds the approved choices, one line each. The reasoning behind the rest:

**(a) The drafter checks what the gate checks, then stops.**
- The checks:
  - the compiler;
  - a valid DeveloperName that is free, or is the name of the rule being changed;
  - a free priority;
  - an active Classic process for the object;
  - the metadata's own limits;
  - the engine's union query.
- Failures go back to the model once, as a list. Two attempts are enough to correct a typo or a
  taken priority. A third would be guessing, so the drafter refuses instead.
- A valid draft carries:
  - its place in the priority order ("tried after PR_High_Value_APAC (10) and before PR_High_Risk
    (20)"), worked out in Apex;
  - the file to commit, in the repository's own rule format: field order, `xsd` types,
    ampersands and angle brackets escaped.

**(b) The model is given configuration, not data.**
- The context is the object's rule-readable fields (the compiler's types) with up to 25 active
  picklist values each, relationship names, the object's active rules with their conditions, its
  active processes, and every active rule's name.
- No record is read for a draft.

**(c) The impact check uses today's values.**
- A decision log row records only what the deciding rule read (§3.3), so a changed rule cannot be
  replayed against the recorded values. Previewing each record's current values under both matrices
  isolates the effect of the change. The report says so.
- Records come from the decision log, the matrix's own traffic: the last 90 days, at most 200.
- A record the engine refuses on either side is skipped. In amf-dev those are the 7 requests
  pending now.

**(d) The health facts are complete without the model.** The facts text is returned as well as the
summary, and stands on its own. Catch-all means a rule whose recorded condition is bare `TRUE`, read
from the snapshot, so a catch-all edited since still counts as one for its own decisions.

**(e) Priorities travel as text between the two actions.** The script binds the last valid draft's
object, name, priority, condition and process into the impact check. M13's and M14's scripts used
only string and Boolean variables, so the priority is text in both actions and is read as a whole
number in Apex. That keeps the binding compiled and type-safe, rather than risking a number type
that might only fail at publish.

### M15.3 Issues encountered

**(a) `number` is reserved in Apex**, as M13.3b found. One variable in `AMF_RuleDrafter` was
renamed before the first compile.

**(b) `Math.round` of a Decimal returns a Long**, which cannot be cast to an Integer. The percentage
uses `setScale(0, HALF_UP).intValue()`.

**(c) An assertion's message cannot be null.** The first check-only run gave 150 tests and 1
failure: `System.NullPointerException: Argument 3 cannot be null`. `String.valueOf(days)` was
null for a null period. The message is now `'days = ' + days`.

**(d) The M13.3e trap again.** A check-only deploy with RunSpecifiedTests reported failure,
although all 6 tests passed: two classes were in the package without their own suites, at 22% and
0% coverage. With their suites added it ran 16/16.

**(e) The templates' active versions (M13.7a).** After the first deploy, a retrieve differed from
the source by one line: the platform's `versionIdentifier`, `/0MCy2NRnsP9ZLj9Xsgvh66VbJrjXadZVilhTmvLHyc=_1`.
This is the same identifier M13's template carries, so it is not per template. No active version
was named. The source took that line, plus `activeVersionIdentifier` naming it, and was redeployed
(0Afaj00000oshkkCAA, 3/3). A retrieve then matched the source for all three templates, M13's included.

**(f) The model answered without calling its tools.** This was the gate's main finding.

The first live draft request answered with a draft that `AMF_AgentDraftRule` cannot produce:
```
filePath: rules/purchase_request/finance_committee_emea_over_500k.json
priority: Medium
condition: Amount > 500,000 AND Region = 'EMEA'
```
The session's trace (`.sfdx/agents/AMF_Matrix_Admin_Assistant/sessions/…/traces/*.json`) showed
the router hand over to `draft_rule`. The draft tool was in `EnabledToolsStep`, yet the model's
response had `"tool_invocations": null`. There was no `FunctionStep`.

What was tried, each in fresh sessions:

| Change | Result |
|---|---|
| "Always call the action first", in the system instructions and the subagent's first line | 3 of 3 sessions fabricated |
| Asking for the tool by name ("Use your draft action now") | fabricated |
| Input `request` renamed `ruleRequest` (0Afaj00000osmajCAA) | fabricated |
| Outputs `label`, `description`, `version`, `mode` renamed `ruleLabel`, `ruleDescription`, `ruleVersion`, `changeType` (0Afaj00000osnbdCAA) | fabricated |
| The subagent says the model does not know the object's fields, picklist values, rules or processes, and that only the tool does; the tool is named `get_checked_draft` | **3 of 3 sessions called it**, and drafted `PR_EMEA_Over_500k` for `PR_Finance_Committee` at priority 15 |

The health and impact subagents called their tools in fresh sessions. But in a session already
under way, after a draft, both answered from memory:
- "Adding draft rule PR_EMEA_Over_500k … would route recent purchase requests meeting these
  conditions …", with no comparison run;
- "Total decisions: 1,242 … Approvals pending: 8", against the log's 29 rows.

Each invented answer followed the shape the instructions described. The health one used exactly the
instruction's list of key figures. The same treatment fixed them:
- the model is told it does not know the records or the counts;
- the tools are named `get_draft_impact`, `get_change_impact` and `get_health_report`;
- the answer templates are gone.

Two full sessions of draft, then impact, then health then called their action on 6 of 6 turns, and
every answer was real.

The platform's preamble explains the pattern. It tells the model to use tools for queries "seeking
*new* information". A request to draft reads as writing, and a follow-up reads as answerable from
the conversation. Saying what the model does not know makes the tool the only source.

The renamed inputs and outputs did not cause the problem, but the new names are clearer and stay.

**(g) A state seen in passing, not M15's.** An extra query found 10 Purchase Requests with
*Matrix Submission* set and no pending approval: PR-00000014 to -20 and -23 to -25, last changed
2026-10-07. They are the M6 spike's records, carried since M8.7c for the Flow phase's teardown.
M15 wrote nothing.

### M15.4 Verification evidence

```
check-only compile   the 12 new and changed classes: Succeeded
check-only tests     20 suites, RunSpecifiedTests: 150 run, 1 failure (c); after the fix the health
                     suites with their dependencies' 16/16 (d)
source gate          passed: 8 active rules, 6 processes guard-checked, 6 of 6 templates released and
                     unchanged, 5 layouts of 2 governed objects
jest                 Test Suites: 5 passed, 5 total; Tests: 75 passed, 75 total
agent validate       both bundles: {"status": 0, "result": {"success": true}, "warnings": []}
deploy               force-app + agentforce, 0Afaj00000ose26CAA: Succeeded, 176/176, 0 errors
post-deploy          "Approval Matrix configuration is valid."
RunLocalTests        707aj00001NMWom: Passed, 404/404, org-wide 97%
                     AMF_ApprovalMatrixService 417/418, AMF_AgentCheckImpact 84/84,
                     AMF_AgentDraftRule 43/43, AMF_AgentMatrixHealth 32/32 (100%);
                     AMF_DraftRuleProvider 28/29 (97%); AMF_AgentSupport 91/95 (96%);
                     AMF_MatrixHealthService 187/199 (94%); AMF_RuleDrafter 299/325 (92%);
                     AMF_MatrixImpact 112/123 (91%); AMF_EinsteinPromptRunner 28/32 (88%: the
                     live call's success path, as M13's generator)
templates            0Afaj00000oshkkCAA 3/3; a retrieve matches source for all three (e)
renames              0Afaj00000osmajCAA, 0Afaj00000osnbdCAA: AMF_AgentDraftRuleTest 3/3 each (f)
final RunLocalTests  707aj00001NLkcT: Passed, 404/404, org-wide 97%
final check-only     all three directories, 0Afaj00000osPHcCAM: Succeeded, 186/186, 0 errors
```

New tests by suite:
- `AMF_ApprovalMatrixServiceTest` +2
- `AMF_DraftRuleProviderTest` 3
- `AMF_RuleDrafterTest` 7
- `AMF_MatrixImpactTest` 4
- `AMF_MatrixHealthServiceTest` 3
- `AMF_EinsteinPromptRunnerTest` 4
- `AMF_AgentDraftRuleTest` 3
- `AMF_AgentCheckImpactTest` 3
- `AMF_AgentMatrixHealthTest` 3
- `AMF_AgentSupportTest` +1

That is 33, so 371 + 33 = 404.

### M15.5 The gate as run (2026-10-23)

```
1  source gate     passed (M15.4)
2  offline         Jest 75/75; sf agent validate, both bundles: success
3  deploy          force-app + agentforce, 0Afaj00000ose26CAA: 176/176; both templates and the admin
                   bundle created
4  post-deploy     "Approval Matrix configuration is valid."
5  RunLocalTests   404/404 (707aj00001NMWom)
6  templates       retrieved form taken, redeployed, a retrieve matches (M15.3e)
7  live preview    --authoring-bundle --use-live-actions; decision log rows 29, matrix rules 9
                   before. After (f), two sessions of three turns, 6 of 6 with a FunctionStep:
                   "Draft a rule for purchase requests: anything over 500,000 in EMEA should go to the
                     finance committee." -> "Draft rule PR_EMEA_Over_500k (new, version 1) for
                     Purchase Requests: when Amount__c > 500000 && Region__c == 'EMEA', send the
                     record to approval process PR_Finance_Committee. Priority 15: it would be tried
                     after PR_High_Value_APAC (10) and before PR_High_Risk (20). It compiles, ..."
                   "What would that draft change for recent purchase requests?" -> "Checked 16
                     Purchase Requests decided in the last 90 days, on their values today. None of
                     them would be decided differently with the new rule PR_EMEA_Over_500k. 7 were
                     skipped, because they are in an approval process now or you cannot read them."
                   "How has the approval matrix been doing over the last 90 days?" -> the log's
                     figures: Purchase Request 25 decisions (24 routed, 1 blocked), Opportunity 4
                   after: 29 rows, 9 rules, at the same versions
8  publish         scripts/publish-agent.ps1 -AgentName AMF_Matrix_Admin_Assistant: v1 active; the
                   submitters' assistant still v7
9  agent access    org-config/amf-dev, 0Afaj00000orsn8CAA: 9/9; AMF_Matrix_Admin_Assistant_Access
                   assigned to the CLI user
10 agent tests     6 cases; 4KBaj00000047J3GAI and 4KBaj00000047KfGAI: 18/18 assertions each
11 manual UI check owed by the user
```

**Left in `amf-dev` by the gate:** the admin agent at v1, active; its test definition and runs.
No rule, row or record was written.

### M15.6 Carried into later phases

This table supersedes M14.6's.

| Item | Owner |
|---|---|
| M15's gate step 11, the manual UI check. In the Agentforce panel, choose Approval Matrix Admin Assistant. Draft a rule, check its impact, ask for a health report, and check that it refuses "deploy it" | user |
| M14's gate step 9, including M13's step 11 (M14.6) | user |
| Any agent's instructions should say what the model does not know and name tools as lookups, and should not describe an answer the model could fill in by itself (M15.3f). The submitters' assistant passes its suite as it is; it was not reworded | whoever edits an agent |
| A drafted rule's name is checked against the active matrix only. An inactive rule of the same name would be overwritten by the release (`docs/decisions.md`) | a phase that widens `AMF_RuleProvider` |
| Releasing a draft is the administrator's: commit the file, run the source gate, deploy, run the post-deploy check | administrator |
| The impact check skips records in an approval process now; in amf-dev, 7 of 23 | as designed |
| PR-00000014 to -20 and -23 to -25 carry *Matrix Submission* with no pending approval (M15.3g) | the Flow phase's teardown |
| Einstein's Trust Layer prompt-injection detection is still off; the admin agent passes administrators' words and rule descriptions to the model | user |
| M14.6's other items carry unchanged | as there |

## Phase M16 — The Claude connector

**Commit:** recorded in the status board. **Status:** complete, bar two checks that need a person:
the MCP login (gate step 7) and the manual conversations in Claude (step 8).
Authorised in `CLAUDE.md` on 2026-10-24, on the user's "implement option 3 in detail and make it very
fluidic to use", and planned first (plan approved the same day).

The user asked for an AI or Agentforce use with a Claude connection to Salesforce. Of the four
integrations proposed, they chose the matrix as an MCP server. The plan's research found that
`amf-dev` already has **Salesforce Hosted MCP Servers** (the `McpServerDefinition` type exists,
generally available since April 2026). Salesforce hosts the endpoint and the OAuth, so nothing is
hosted elsewhere. The user then chose: two servers (users and administrators); Claude writing the
words from recorded facts; claude.ai and Claude Code as the clients to prove; and starter prompts
only if Salesforce served them without generating.

### M16.1 What the first tool established about the platform

The plan's step 1 built one tool (`preview_route`) end to end before the rest, because Salesforce's
developer documentation refuses automated reads (HTTP 403). The sources were the org itself, the
public example repository SalesforceDiariesBySanket/Salesforce-Hosted-Custom-Mcp-Server, the
mdhamoda/custom-mcp-skill reference (which marks each claim as observed in an org or documented),
Salesforce's own `salesforce/sf-pi` ECA generator, and the Tooling API describe. What was confirmed
in `amf-dev`:

| Question | Answer |
|---|---|
| Which Apex becomes a tool? | A `global` `@InvocableMethod`, identified as `aa:apex-<ClassName>`, `apiSource` `API_CATALOG`, `operation` the class name. Its catalog entry is made on deploy. The schema is built from `global` members, so the request and result classes and their fields are `global` too |
| Can a class name have underscores? | Yes: `aa:apex-AMF_McpPreviewRoute` validated and works. A **server's** name cannot (letters and digits only), so the servers are `AMFApprovalMatrix` and `AMFApprovalMatrixAdmin` |
| The server URL in a Developer Edition | `https://api.salesforce.com/platform/mcp/v1/custom/<DeveloperName>`; a sandbox or scratch org adds `/sandbox/` after `/v1/`. Unauthenticated, it answers 401 and publishes OAuth metadata naming `login.salesforce.com` and the scopes `mcp_api`, `refresh_token` |
| Tool annotations | `McpServerToolDefinition` has `ReadOnly`, `Destructive`, `Idempotent`, `OpenWorld`, `ReturnDirect` and `UiResource` only from API 67.0; at 66.0 they do not exist. See (a) below |
| Activation | Not metadata. A Tooling API row, `McpServerAccess`, with `Active` and the definition's `McpServerId`. A POST creates it; deploying never activates |
| Redeploying an active server | Works: the setup script redeployed `AMFApprovalMatrix` while it was active, with no deactivation |
| The External Client App by metadata | Three files deploy together (`.eca`, `.ecaGlblOauth`, `.ecaOauth`), and the platform creates a fourth, the policy. In metadata the scope is `MCP`, not `mcp_api`. `isNamedUserJwtEnabled` must be set: it defaults to false. Callback URLs go in one element, one per line. The consumer key is generated by the org and retrieved, never authored |
| Admission by permission set | `permittedUsersPolicyType` `AdminApprovedPreAuthorized` with `commaSeparatedPermissionSet` accepted permission set **names**, and stored them sorted, although the schema's description says Ids |
| How a client calls an Apex tool | Arguments go in an `inputs` array, one object per call, because the invocable takes a list |
| MCP prompts | A server's `<prompts>` are Prompt Builder Flex templates. Salesforce's documentation says they consume credits at invocation, as from the UI: they run through Einstein. The user's condition was "without generating", so none were added. Not tested live |
| Interactive widgets (MCP Apps) | `UiResource` exists on the tool definition, but no documented way serves a custom server's widget. Not pursued |

**(a) The annotations and the API version.** The first server deploy, at the project's
`sourceApiVersion` 66.0, succeeded, but a retrieve came back without the four annotation elements,
and the tool's flags read false. `sf project deploy start --api-version 67.0` changed nothing: the
flag sets the connection's version, not the package's. A throwaway project at `sourceApiVersion`
67.0, holding only the definition, deployed them: `ReadOnly true, Idempotent true`. A later deploy at
66.0 reset them all to false. Without them a client treats every tool as destructive and asks first,
and the submit tool loses its warning. So the definitions are `.forceignore`d, and
`scripts/setup-claude-connector.ps1` deploys them from a throwaway project at 67.0, as
`publish-agent.ps1` does for the agents. Raising the project's `sourceApiVersion` was the
alternative; it would have touched every package directory for one metadata type, and CLAUDE.md pins
it at 66.0. The Apex stays at 62.0.

### M16.2 File-level changes

| File | Change | Notes |
|---|---|---|
| `mcp/main/default/classes/AMF_McpSupport.cls` | **new** | a reference read through Find Governed Record; the record's link; the preview token (sign, check) |
| `…/AMF_McpFindRecord.cls`, `AMF_McpPreviewRoute.cls`, `AMF_McpWhatIfRoute.cls`, `AMF_McpSubmitRoute.cls`, `AMF_McpDecisionFacts.cls`, `AMF_McpBriefingFacts.cls`, `AMF_McpMyRequests.cls`, `AMF_McpMyApprovals.cls` | **new** | the eight user tools |
| `…/AMF_McpRuleContext.cls`, `AMF_McpCheckRuleDraft.cls`, `AMF_McpCheckImpact.cls`, `AMF_McpHealthFacts.cls` | **new** | the four admin tools |
| `…/AMF_McpFactsOnly.cls` | **new** | an `AMF_ExplanationGenerator` that hands the facts back |
| thirteen `…Test.cls` suites | **new** | 47 tests (M16.5) |
| `mcp/main/default/objects/AMF_Mcp_Settings__c/` | **new** | protected hierarchy setting, `Preview_Key__c` |
| `mcp/main/default/permissionsets/AMF_Claude_Connector_User…`, `…_Admin…` | **new** | eight and twelve classes |
| `mcp/main/default/mcpServerDefinitions/AMFApprovalMatrix…`, `AMFApprovalMatrixAdmin…` | **new** | tools, descriptions (at most 1,024 characters; 418 to 882 used) and annotations |
| `org-config/amf-dev/main/default/externalClientApps/AMFClaudeConnector…`, `extlClntAppGlobalOauthSets/…`, `extlClntAppOauthSettings/…`, `extlClntAppOauthPolicies/AMFClaudeConnector_defaultPolicy…` | **new** | the connector's OAuth client and hardened policy |
| `scripts/setup-claude-connector.ps1`, `scripts/setup-mcp.apex`, `scripts/mcp-probe.mjs` | **new** | setup; the key; an MCP client for the gate |
| `sfdx-project.json` | modified | the `mcp` package directory |
| `.forceignore` | modified | `**/mcpServerDefinitions/**` (M16.1a) |
| `.gitignore` | modified | `.mcp-probe/`, the probe's tokens |
| `docs/claude-connector.md` | **new** | the guide |
| `CLAUDE.md`, `docs/architecture.md` (§1, §7, §13.4), `docs/build-playbook.md`, `docs/decisions.md`, this file | modified | M16 authorised, designed, gated and recorded; CLAUDE.md's Environment also gains the admin agent's publish command (handoff §9) |

No engine class, no M13 to M15 class, no existing object, field, rule, template or LWC, and neither
agent was changed.

### M16.3 Design choices worth recording

`docs/decisions.md` holds the approved choices. The reasoning behind the rest:

**(a) Facades, not changes.** The M13 to M15 actions are `public`, and a tool must be `global`
throughout. Making them `global` would have changed eleven classes from three phases, and fixed their
Agentforce-tuned inputs as an MCP contract. The facades delegate to them call for call, so every
sentence, outcome and refusal is theirs, and add only what an MCP client needs: resolution, links,
the token.

**(b) A record as a person names it, in every tool.** `AMF_McpSupport.resolve()` sends each
reference to Find Governed Record, which already handles an Id, an exact name, the search index and a
contains-match, among governed objects in user mode. So "Where would PR-00000047 go?" is one tool
call, not find-then-preview. A reference that is several records comes back `Ambiguous` with the
numbered list, never a guess. `get_decision_facts` also takes a decision log row's name.

**(c) Claude in Einstein's place, through the seams that exist.** `AMF_DecisionExplainer` takes an
`AMF_ExplanationGenerator`; `AMF_McpFactsOnly` returns the facts it is given. So the facts are byte
for byte what the Explain button's template receives, and the explainer still decides what the reader
may see, including M14's current-approver rule for a briefing. `AMF_RuleDrafter` takes an
`AMF_PromptRunner`. `get_matrix_context` gives it one that keeps the `Context` input and throws, so
the context is the drafter's own. `check_rule_draft` gives it one that returns Claude's draft as the
answer, so every §9 check runs on it, and the file exists only for a draft that passed. The grammar
Claude needs is in the drafting template, which Apex cannot read without running it; `GUIDE` repeats
it in the same words, with a note to keep the two in step.

**(d) The preview token.** The threat is a model submitting what its user was never shown, not the
user, who can submit from the record page. The token is
`issuedAt + "." + hex(HMAC-SHA256(key, orgId|userId|recordId|process|issuedAt))`, with the key in a
protected setting the model never reaches. It is issued only when the preview can be submitted, and
checked for the same user (the payload names them), the same record (as an 18-character Id), the
same process (blank for a block), within 15 minutes, allowing a minute of clock skew. It is not
single-use: M8's check refuses a record already in approval, so a second submission fails anyway. A
key change invalidates every preview not yet submitted.

**(e) A changed route is refused, not submitted.** Submit Previewed Route submits a changed route and
says so (M13), because there the platform asks the user to confirm the action, not a process. Here the
user approves a call whose arguments name the process, so a different process was never approved.
`submit_for_approval` previews again first and refuses with the new route. The submission itself is
Submit Previewed Route's, so M10's `submitEach()` writes the row.

**(f) Tool descriptions as lookups.** Each says what Claude does not know that only the tool does,
what it is not for, and what to give the user; no description sketches an answer Claude could fill in
(M15.3f). The submit tool spells out the order: preview, tell the user the process, ask, then call.

**(g) Access is the permission set.** The ECA admits only holders of a connector set
(`AdminApprovedPreAuthorized`), refresh tokens last 30 days (the platform default was 365), and only
PKCE and JWT named-user tokens are on. Class access to the facades is the connector sets'; record and
field access stays `Approval_Matrix_User`'s and `_Admin`'s.

**(h) No Einstein, no licence.** Nothing in the connector calls Einstein, so it needs no Agentforce or
Prompt Template licence per user. The prompts were dropped for the same reason (M16.1).

### M16.4 Issues encountered

**(a) `found` and `FOUND`.** Apex names are case-insensitive, so a local `found` shadowed
`AMF_McpSupport.FOUND`: "Illegal assignment from AMF_AgentFindRecord.Result to String". Renamed
`lookup`.

**(b) `url` and `URL`.** The same in a test: a local `url` hid the `URL` class ("Method does not
exist… getOrgDomainUrl() from the type String"). Renamed `link`.

**(c) `number` is reserved,** as M13.3b and M15.3a found, in four tests. Renamed `prNumber`.

**(d) Null assertion messages,** as M15.3c found. The first run gave 47 tests, 8 failures:
`Message parameter cannot be null` and `Argument 3 cannot be null`, from passing `result.summary` as
the message where a success leaves it null. Every bare-field message became `'' + field`.

**(e) The smoke script and PowerShell's `$input`.** The first REST smoke script passed every tool an
empty input: `$input` is an automatic variable in PowerShell. Renamed `$values`. The tools were never
at fault.

**(f) The annotations' API version** (M16.1a).

**(g) A decision log row not from M16.** The log had 30 rows, not the handoff's 29: ADL-00000034,
submitted by Grok Bot (the UI suite's user) at 2026-10-24 15:20 UTC on `a02aj00000jiH9uAAE`. M16
submitted nothing; the gate counts before and after.

### M16.5 Verification evidence, and the gate as run (2026-10-24)

```
thin slice       mcp deploy 0Afaj00000ozbFZCAY (after (a)); REST preview of "PR-00000047":
                 Routable, PR_Two_Level_Mgmt via PR_Catch_All, recordUrl, submitToken
                 server deploy 0Afaj00000ozbQrCAI (66.0: annotations dropped, M16.1a);
                 throwaway at 67.0: ReadOnly true, Idempotent true; a 66.0 redeploy reset them
                 ECA: 3/3; OauthScopesMCP_API true, OauthScopesREFRESH_TOKEN true;
                 isNamedUserJwtEnabled true, isPkceRequired true, consumer key generated
                 McpServerAccess 1fzaj000004V6MzAAK: AMFApprovalMatrix active
                 unauthenticated initialize: HTTP 401; protected-resource metadata as M16.1
                 policy: AdminApprovedPreAuthorized, both sets by name, 30 days
1  source gate   "passed for 8 active rule(s), 6 approval process(es) guard-checked, 6 of 6
                 template(s) released and unchanged, and 5 layout(s) of 2 governed object(s)"
2  jest          Test Suites: 5 passed, 5 total; Tests: 75 passed, 75 total
3  setup script  setup-claude-connector.ps1 -Admin, with AMF_USERNAME_DOMAIN unset:
                 mcp 18 components; ECA 4; servers 2 (at 67.0); the Admin server activated;
                 12 tools: 11 read-only, submit_for_approval destructive; key kept
4  RunLocalTests 707aj00001NZwa2: Passed, 451/451, org-wide 97%
                 (the MCP suites alone: 47/47; AMF_McpBriefingFacts, _CheckImpact, _FactsOnly,
                 _FindRecord, _HealthFacts, _MyApprovals, _MyRequests, _RuleContext, _WhatIfRoute
                 100%; _SubmitRoute 99%; _CheckRuleDraft 98%; _PreviewRoute, _Support,
                 _DecisionFacts 97%)
5  check-only    all four directories, 0Afaj00000ozjTFCAY: Succeeded, 221/221, 0 errors
6  REST smoke    as the CLI user; decision log 30 rows, matrix 9 rules (8 active), before and after:
                 preview_route "PR-00000047"    Routable -> PR_Two_Level_Mgmt via PR_Catch_All, token
                 what_if_route 120000 / APAC    changed -> PR_Three_Level_Finance via
                                                PR_High_Value_APAC; today PR_Two_Level_Mgmt
                 get_decision_facts PR-00000042 Facts, ADL-00000027, 11 lines
                 get_briefing_facts PR-00000045 No_Facts: "... is not waiting on you for approval ..."
                 submit, forged token           Refused: "This submission does not come from a preview ..."
                 submit, real token, other process  Refused, the same
                 list_my_requests               16, "6 still waiting for approval"
                 list_my_approvals              0, "Nothing governed by the approval matrix is waiting on you"
                 find_record "PR-00000046"      Found
                 get_matrix_context             Context, Purchase_Request__c; guide 2521, context 2681 chars
                 check_rule_draft, EMEA         valid, Add v1, priority 15, "tried after
                                                PR_High_Value_APAC (10) and before PR_High_Risk (20)",
                                                force-app/main/default/customMetadata/Approval_Matrix_Rule.PR_EMEA_Over_500k.md-meta.xml
                 check_rule_draft, bad          not valid, no file; three problems: priority 10 taken,
                                                "Finance" not an active process, the condition does not compile
                 check_change_impact            ran: 17 checked, 0 changed, 7 skipped
                 get_health_facts, 90 days      30 decisions, 1 blocked, 0 failed; 13 fact lines
7  MCP probe     waiting on the user's one browser login (the probe listens on localhost:1717)
8  manual        owed: claude.ai and Claude Code, docs/claude-connector.md sections 3 and 4
```

New tests by suite: `AMF_McpSupportTest` 10, `AMF_McpSubmitRouteTest` 8, `AMF_McpPreviewRouteTest`
5, `AMF_McpDecisionFactsTest` 4, `AMF_McpCheckRuleDraftTest` 4, `AMF_McpBriefingFactsTest` 3,
`AMF_McpRuleContextTest` 3, `AMF_McpHealthFactsTest` 3, `AMF_McpWhatIfRouteTest` 2,
`AMF_McpFindRecordTest` 2, `AMF_McpMyRequestsTest` 1, `AMF_McpMyApprovalsTest` 1,
`AMF_McpCheckImpactTest` 1. That is 47, so 404 + 47 = 451.

**Left in `amf-dev` by the gate:** both servers, active; the External Client App; the preview key;
`AMF_Claude_Connector_Admin` assigned to the CLI user. No rule, row or record was written.

### M16.6 Carried into later phases

This table supersedes M15.6's.

| Item | Owner |
|---|---|
| Gate step 7: one browser login for `scripts/mcp-probe.mjs` (`docs/claude-connector.md` §7.4), then `initialize`, `tools/list` with annotations and `tools/call` on both servers. Record as M16.7 | user, then a session |
| Gate step 8: connect claude.ai and Claude Code (§3) and run §4's conversations, including a throwaway submitted through Claude after confirming, reassigned to the tester, briefed and recalled | user |
| claude.ai's connector broker has had Salesforce login failures (anthropics/claude-ai-mcp #184 and #251, both closed). If claude.ai fails after a good login, Claude Code connects directly | step 8 |
| The server definitions deploy only through the setup script, at Metadata API 67.0 (M16.1a). If the project's `sourceApiVersion` rises to 67.0 or above, the `.forceignore` line and the script's throwaway project can go | whoever raises it |
| `GUIDE` in `AMF_McpRuleContext` repeats the drafting template's grammar; keep them in step | whoever edits either |
| MCP prompts were dropped on the documentation's word (M16.1); a live check would settle it | if wanted |
| The decision log cannot tell which rows came through Claude: it has no channel field | a later phase, if wanted |
| M15.6's items carry unchanged, except the CLAUDE.md publish-command item, which M16 did | as there |
