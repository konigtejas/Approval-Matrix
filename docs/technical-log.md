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
| M1 | Data model — `Approval_Matrix_Rule__mdt`, `Approval_Decision_Log__c`, SOQL provider | Not started | |
| M2 | Expression evaluator, reduced grammar | Not started | |
| M3 | Engine, two Classic templates, submit action | Not started | |

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
