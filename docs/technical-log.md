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

## ⚠ ARCHITECTURE SUPERSEDED — BUILD PAUSED (2026-08-13)

`docs/architecture.md` in this repo is **v1.0** and is no longer the design. It is
superseded by **Architecture v2.1 (Option A, Single CMDT, Dual Execution)**, which itself
supersedes a v2.0 that is **not yet in this repo**.

**Do not start Phase 2, and do not treat the v1.0 doc or the phase rows below as current.**

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

**Blocked on:** v2.0, which v2.1 defers to for the expression evaluator design, the 11-step
engine flow, the `Approval_Decision_Log__c` schema, template conventions and entry points.
Writing the revised phases without it would mean inventing the design, which `CLAUDE.md`
forbids.

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

**Agreed plan once v2.0 is supplied:** reconcile v2.0 + v2.1 into a new `docs/architecture.md`;
move the current file to `docs/archive/architecture-v1.md`; rewrite `docs/build-playbook.md`
phases per v2.1 §6; remove the superseded metadata from the repo and destructively delete it
from `amf-dev`; rebuild Phase 1 against the v2.1 data model.

---

## Phase status board

Each phase is built in its own chat session, so this table is the resume point: it, plus the
"Carried into later phases" table at the end of the most recent entry, is everything a fresh
session needs. Update the row when a phase completes.

| Phase | Name | Status | Commit |
|---|---|---|---|
Rows below are the **v1.0 plan** and are retained only as a record of what was built.
The v2.1 phase plan replaces them once v2.0 arrives — see the banner above.

| Phase | Name | Status | Commit |
|---|---|---|---|
| 0 | Scaffold & connectivity | Complete — survives v2.1 | `e3ac256` |
| 1 | Data model (v1.0) | Built, then **superseded** by v2.1 | `ea308b1` |
| 2–8 | v1.0 plan | **Cancelled** — replaced by the v2.1 phase plan | |

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

- [ ] **Enable record locking and unlocking in Apex** (Setup → Process Automation
      Settings). Required by §6.3 for `Approval.unlock()`. Phase 4 fails without it.

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
