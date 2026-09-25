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
| A preview does not know a record is already in an approval process: it shows the route, and the submission then fails with the platform's error, as before M5. A lock check in the preview would say so up front | post-M5 |
| ~~The action sits in the ▼ overflow menu (M5.3b)~~ | **closed in M5.6** — first in `platformActionList`, now a header button |
| `AMF_ApprovalMatrixService`'s header still says §9 is out of MVP scope; stale since M4 | next change to that class |

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
