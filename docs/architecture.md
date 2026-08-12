# Hybrid Approval Matrix Framework — Technical Architecture

**Version:** 1.0 draft · **Scope:** 2–3 objects, unlimited approval depth, user/queue/group approvers
**Execution layer:** Native Salesforce Approval Process (chained single-step pattern), with a pluggable strategy seam for Flow Approval Orchestration

---

## 1. Design Principles

1. **Configuration over code.** All routing logic lives in Custom Metadata. Onboarding a new rule, or changing an existing one, is a config release — no Apex changes.
2. **Enhance native, don't replace it.** Salesforce executes the approvals: record locking, work items, notifications, approval history. The framework decides *who* and *in what order*; the platform handles *how*.
3. **Unlimited depth via chaining, not steps.** One generic single-step Approval Process per object, invoked once per level. Depth is data (chain records), not design (process steps), so it is genuinely unbounded.
4. **Every decision is explainable.** The engine persists the matched rule, the field values it evaluated, and the planned vs. actual approver chain. Native approval history answers *who/when*; the decision log answers *why*.
5. **Testable and portable.** All Custom Metadata access sits behind an interface with test injection. All `Approval.process()` calls sit behind a submission strategy interface. The framework deploys to a new org with zero code changes.

---

## 2. Component Overview

```
┌────────────────────────────────────────────────────────────────────┐
│  ENTRY POINTS                                                       │
│  Quick Action (LWC) · Invocable (Flow) · Apex API · REST wrapper    │
└────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌────────────────────────────────────────────────────────────────────┐
│  APEX ENGINE                                                        │
│                                                                      │
│  ApprovalMatrixService (facade, bulk-safe)                          │
│    ├── RuleProvider (interface) ── CmdtRuleProvider / TestStub      │
│    ├── ConditionEvaluator  — typed matching + logic expressions     │
│    ├── FieldPathResolver   — cross-object paths via dynamic SOQL    │
│    ├── ApproverResolver    — user / queue / group / manager chain   │
│    ├── ChainManager        — creates + advances chain state         │
│    └── SubmissionStrategy (interface)                               │
│          ├── NativeProcessStrategy   (this document)                │
│          └── OrchestrationStrategy   (future seam, §14)             │
└────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌────────────────────────────────────────────────────────────────────┐
│  EXECUTION LAYER (per object)                                       │
│  Generic 1-step Approval Process  ──  Current_Approver__c           │
│  Record-triggered Flow "Chain Advancer" on step outcome             │
└────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌────────────────────────────────────────────────────────────────────┐
│  AUDIT LAYER                                                        │
│  Approval_Chain__c + Approval_Chain_Step__c  (decision log + state) │
└────────────────────────────────────────────────────────────────────┘
```

---

## 3. Data Model

### 3.1 Configuration (Custom Metadata Types)

**`Approval_Object_Config__mdt`** — one per governed object

| Field | Type | Purpose |
|---|---|---|
| `Object_API_Name__c` | Text | e.g. `Purchase_Request__c` |
| `Process_API_Name__c` | Text | DeveloperName of that object's generic process |
| `Fallback_Approver__c` | Text (username) | Used when a resolved approver is inactive |
| `No_Match_Behavior__c` | Picklist | `Block` \| `Route_To_Fallback` \| `Auto_Approve` |
| `Rejection_Behavior__c` | Picklist | `Terminate` \| `Return_To_Submitter` |
| `Recall_Reevaluates__c` | Checkbox | Re-run rules on resubmit after recall |
| `Active__c` | Checkbox | Kill switch per object |

**`Approval_Rule__mdt`** — one per routing scenario

| Field | Type | Purpose |
|---|---|---|
| `Object_API_Name__c` | Text | Rule's target object |
| `Priority__c` | Number | Lower wins; ties broken by DeveloperName (deterministic) |
| `Logic_Expression__c` | Text | e.g. `1 AND (2 OR 3)`; blank = AND of all conditions |
| `Version__c` | Number | Incremented on change; stamped into the decision log |
| `Active__c` | Checkbox | |

**`Approval_Rule_Condition__mdt`** — child of rule (metadata relationship)

| Field | Type | Purpose |
|---|---|---|
| `Rule__c` | MD relationship | Parent rule |
| `Index__c` | Number | Referenced by the logic expression |
| `Field_Path__c` | Text | `Amount__c` or `Account__r.Owner.Region__c` (max 4 hops) |
| `Operator__c` | Picklist | `equals, not_equals, greater, greater_equal, less, less_equal, in, not_in, contains, starts_with, is_null, is_not_null` |
| `Value__c` | Text | Comparison value; comma-separated for `in`; ISO format for dates |

**`Approval_Route_Step__mdt`** — child of rule; one per level

| Field | Type | Purpose |
|---|---|---|
| `Rule__c` | MD relationship | Parent rule |
| `Level__c` | Number | 1..N — no ceiling; depth is data |
| `Approver_Type__c` | Picklist | `Named_User` \| `Related_User_Field` \| `Manager_Chain` \| `Queue` \| `Public_Group` |
| `Approver_Reference__c` | Text | Username, field path, queue/group DeveloperName, or chain depth for `Manager_Chain` |
| `Group_Completion__c` | Picklist | `Any_Member` \| `Unanimous` (queue/group only) |
| `SLA_Hours__c` | Number | Optional; drives escalation (§7.5) |
| `Skip_If_Same_As_Previous__c` | Checkbox | De-dupe when manager chain converges |

### 3.2 Runtime State (Custom Objects)

**`Approval_Chain__c`** — one per submission; doubles as the decision log

| Field | Purpose |
|---|---|
| `Record_Id__c` (Text, indexed, ext id) | Polymorphic pointer to the governed record |
| `Object_API_Name__c` | For reporting and the Chain Advancer |
| `Matched_Rule__c` / `Rule_Version__c` | Which rule fired, at which version |
| `Evaluated_Values__c` (Long Text, JSON) | Snapshot of every field value the engine compared |
| `Status__c` | `In_Progress` \| `Approved` \| `Rejected` \| `Recalled` \| `Failed` |
| `Current_Level__c` / `Total_Levels__c` | Progress |
| `Submitted_By__c`, timestamps | Audit |

**`Approval_Chain_Step__c`** — one per level (created up front = the *planned* chain)

| Field | Purpose |
|---|---|
| `Chain__c` (Master-Detail) | Parent |
| `Level__c` | Sequence |
| `Planned_Approver_Type__c` / `Planned_Approver__c` | What the rule resolved |
| `Assigned_User__c` (Lookup User) | Concrete user the work item went to |
| `Actual_Approver__c` (Lookup User) | Who actioned it (≠ assigned when reassigned or group-actioned) |
| `Outcome__c`, `Comments__c`, `Actioned_At__c` | Result |
| `Group_Members_Snapshot__c` (JSON) | Queue/group membership at assignment time (SOX) |

### 3.3 Per-Object Fields (added to each governed object)

| Field | Purpose |
|---|---|
| `Current_Approver__c` (Lookup User) | Related User field the generic process reads |
| `Active_Chain__c` (Lookup Approval_Chain__c) | Joins record → chain; entry-criteria guard |
| `Chain_Step_Outcome__c` (Picklist) | Written by process field updates; fires the Chain Advancer |

---

## 4. Rule Evaluation Engine

### 4.1 Evaluation Algorithm

```
submit(recordIds):
  1. Load Approval_Object_Config__mdt; abort per config if inactive
  2. RuleProvider.getActiveRules(objectApiName) ordered by Priority, DeveloperName
  3. Collect the union of all Field_Path__c across all rules
  4. FieldPathResolver builds ONE dynamic SOQL per object covering every path
     (relationship dot-notation; 4-hop platform limit enforced at config validation)
  5. For each record, for each rule in priority order:
       evaluate each condition (typed, §4.2)
       feed boolean results into the logic-expression evaluator (§4.3)
       FIRST match wins — stop
  6. No match → apply No_Match_Behavior__c
  7. ApproverResolver expands route steps to concrete assignees (§5)
  8. ChainManager writes Approval_Chain__c + all Approval_Chain_Step__c rows
  9. SubmissionStrategy.submit(level 1)  — same transaction, before lock
```

### 4.2 Typed Comparison

`Value__c` is stored as text; the engine coerces using `Schema.DisplayType` from the field describe of the *final* field in the path:

| DisplayType | Coercion | Notes |
|---|---|---|
| CURRENCY, DOUBLE, PERCENT, INTEGER | `Decimal.valueOf` | Locale-independent (dot decimal) |
| DATE / DATETIME | `Date/Datetime.valueOf` ISO | Reject ambiguous formats at config validation |
| BOOLEAN | `Boolean.valueOf` | |
| PICKLIST / STRING / ID / REFERENCE | Case-insensitive string | `in` splits on comma, trims |
| MULTIPICKLIST | Set semantics | `contains` = includes value |

Null handling is explicit: `greater/less` against null → `false` (never throws); use `is_null` / `is_not_null` for presence checks.

### 4.3 Logic Expression Evaluator

Grammar: integers reference condition `Index__c`; operators `AND`, `OR`, `NOT`; parentheses. Implementation: tokenizer → shunting-yard → RPN evaluation. Expressions are **validated at config-deploy time** by a validation utility (checks: all indices exist, balanced parens, no orphan conditions), so runtime never sees a malformed expression.

### 4.4 RuleProvider Interface (testability — non-negotiable)

```apex
public interface RuleProvider {
    List<RuleDefinition> getActiveRules(String objectApiName);
    ObjectConfig getObjectConfig(String objectApiName);
}
```

`CmdtRuleProvider` maps CMDT rows into plain-Apex `RuleDefinition` DTOs. Tests inject a stub via `@TestVisible static RuleProvider instance`. **Custom Metadata cannot be inserted in unit tests** — without this seam every test depends on org config and the framework is not portable. DTOs also mean the engine never touches `__mdt` types directly, which keeps the Orchestration strategy and any future rule source (e.g., a custom-object rule store for sandbox experimentation) drop-in.

---

## 5. Approver Resolution

| Approver_Type | Resolution |
|---|---|
| `Named_User` | Username → active User lookup |
| `Related_User_Field` | Field path on the record (e.g. `Account__r.OwnerId`) resolved in the same consolidated query |
| `Manager_Chain` | Walk `User.ManagerId` N hops from submitter (or from a field-path user); reference format `SUBMITTER:2` = manager's manager |
| `Queue` | Queue DeveloperName → members expanded (§5.1) |
| `Public_Group` | Group DeveloperName → members expanded recursively (nested groups, roles) |

Every resolved user passes an **active check**; inactive → `Fallback_Approver__c`, and the substitution is recorded on the chain step. `Skip_If_Same_As_Previous__c` collapses converged manager chains.

### 5.1 Queue / Public Group Levels Under the Native Constraint

This is the honest hard part. A Related User field must be a **user** lookup, and a native process step can only target a queue *statically at design time* — dynamic per-record queue assignment is not possible through approver fields. The framework handles group levels with the **Group Work Item pattern**:

1. `ApproverResolver` snapshots the group membership into `Group_Members_Snapshot__c`.
2. The work item is assigned to a designated **framework service user** (`Current_Approver__c` = service user), so the native machinery — lock, history, timing — still runs.
3. Members see the pending item in a custom **Approval Inbox LWC** (home page + record page), driven by `Approval_Chain_Step__c` where the running user is in the membership snapshot.
4. When a member actions it, Apex (system context, after re-verifying membership) calls `Approval.process()` with a `ProcessWorkitemRequest` on the service user's work item and stamps `Actual_Approver__c` = the member. Standard email notifications are supplemented by a framework notification (custom notification + email alert) to all members at assignment.
5. `Group_Completion__c = Unanimous` keeps the step open, tracking member votes on a child JSON structure until all approve; any rejection closes it.

Trade-off stated plainly: native approval history shows the service user as the actor; the *true* actor lives on the chain step, which is the SOX artifact anyway. **Spike (3 days, before build):** validate whether `ProcessSubmitRequest.nextApproverIds` accepts queue IDs for custom objects with queues enabled — documentation is ambiguous, and if it works, queue levels simplify to native queue work items and the Inbox LWC becomes optional for `Any_Member` semantics.

---

## 6. Execution Layer — Chained Single-Step Process

### 6.1 Why Chained

A native process has design-time steps (max 30). "Unlimited depth" therefore requires **one generic single-step process per object, invoked once per level**. Depth becomes chain data. Each cycle is its own transaction, so a 40-level chain has identical governor cost per level as a 2-level chain.

### 6.2 The Generic Process (per object, built once, never edited again)

| Element | Setting |
|---|---|
| Entry criteria | `Current_Approver__c != null AND Active_Chain__c != null` — **this is the guard**: a standard-button or rogue-code submission fails entry because the engine never populated the fields |
| Step 1 approver | Automatically assign to Related User: `Current_Approver__c` |
| Approval actions | Field update `Chain_Step_Outcome__c = 'Approved'`; keep record locked |
| Rejection actions | Field update `Chain_Step_Outcome__c = 'Rejected'`; keep locked (engine decides unlock) |
| Recall actions | Field update `Chain_Step_Outcome__c = 'Recalled'` |
| Initial submit | Lock record |

### 6.3 The Chain Advancer

A record-triggered Flow on the governed object (after-save, fires on `Chain_Step_Outcome__c` change) calls a single invocable, which routes to `ChainManager.advance()`:

```
advance(recordId, outcome):
  APPROVED  → close current Approval_Chain_Step__c
              more levels?  → resolve next approver (re-check active),
                               set Current_Approver__c,
                               Approval.unlock() → Approval.process() next cycle
              last level?   → Chain Status = Approved, final unlock,
                               clear Current_Approver__c, completion actions
  REJECTED  → Chain Status = Rejected, apply Rejection_Behavior__c, unlock
  RECALLED  → Chain Status = Recalled, unlock; resubmission re-evaluates
              rules if Recall_Reevaluates__c
```

`Approval.unlock()` requires the **Enable record locking/unlocking in Apex** org setting — a documented prerequisite. The advance runs in the approval transaction's after-save; the resubmit is done via a Queueable to keep each cycle's transaction clean and to survive mixed-DML edges around user-context operations.

### 6.4 Lock Lifecycle

Locked at first submit → stays locked across cycles (unlock/resubmit happens inside one engine call, milliseconds of exposure, acceptable; if the resubmit Queueable fails, the record remains locked and the chain is flagged `Failed` for admin retry) → unlocked at terminal state only.

---

## 7. Chain Lifecycle Rules

1. **One active chain per record.** Enforced by `Active_Chain__c` + engine check; a second submit while `In_Progress` is rejected with a clear error.
2. **Reassignment** (native "Reassign" on the work item) is detected by the Advancer comparing work-item actor vs. `Assigned_User__c`, stamped into `Actual_Approver__c`.
3. **Approver deactivated mid-chain:** the next `advance()` re-checks active status *at each hop*, not just at submit; substitution → fallback, logged.
4. **Record edited mid-chain:** locked, so only admins can edit. Admin edits do **not** re-trigger evaluation (rules matched at submit time — the evaluated snapshot is the audit truth). Re-evaluation requires recall + resubmit.
5. **SLA escalation:** a scheduled batch scans open steps past `SLA_Hours__c`; behavior per step config — remind, auto-reassign to fallback, or skip level (each action logged).
6. **Data-load safety:** entry points are explicit (no record-trigger auto-submit in v1), so bulk loads cannot accidentally start chains.

---

## 8. Decision Log & SOX Posture

The chain objects **are** the audit artifact:

* *Why this path:* `Matched_Rule__c` + `Rule_Version__c` + `Evaluated_Values__c` JSON.
* *Who was supposed to approve:* planned steps, written before the first work item exists.
* *Who actually did:* `Actual_Approver__c`, incl. group actor and reassignments.
* *What the group looked like:* membership snapshot at assignment time.
* Chain objects are **never deleted**; terminal chains are locked via a validation rule (edits blocked once `Status__c` is terminal, integration profile excepted).
* Config governance: CMDT changes deploy through the normal release pipeline — the framework removes *code* releases for rule changes, not change control. Rule `Version__c` ties every historical chain to the rule text that produced it.

---

## 9. Entry Points & Standard-Button Lockdown

| Path | Mechanism |
|---|---|
| UI | Headless LWC Quick Action per object → `ApprovalMatrixService.submit()` (shows resolved chain preview before confirm — strong demo moment) |
| Flow | Invocable `SubmitForMatrixApproval` |
| Apex | Direct service call |
| Integration | `@RestResource` wrapper |

Standard **Submit for Approval** removed from all layouts *and*, as defense in depth, the process entry criteria (§6.2) reject any submission the engine didn't stage. A stray standard submit therefore fails loudly instead of silently bypassing routing.

---

## 10. Bulkification & Limits

* `submit()` accepts `List<Id>`; `Approval.process()` takes up to 100 requests per call — the engine chunks and, above a configurable threshold, defers to a Queueable.
* CMDT reads are limit-free; the **one consolidated dynamic SOQL per object** (§4.1) is the only per-transaction query cost of evaluation.
* Expression parsing is O(conditions) per rule; rules are evaluated in priority order with early exit.
* Each chain cycle is a separate transaction — depth never accumulates governor cost.

---

## 11. Testability Architecture

* `RuleProvider` stub — in-memory rule definitions (builder pattern: `RuleBuilder.forObject(...).condition(...).route(...)`).
* `SubmissionStrategy` stub — asserts staged approver + guard fields without executing a real process (real `Approval.process` covered by a thin integration test per object against a test-only process).
* `FieldPathResolver` tested against standard objects to avoid org-specific schema coupling.
* Target: engine logic ≥ 90% covered with zero dependence on org CMDT rows.

---

## 12. Security Model

* Engine runs `without sharing` for chain writes and work-item actions (it is infrastructure), but **authorizes explicitly**: submit requires read access on the record; group actions re-verify live membership before actioning.
* Approval Inbox LWC enforces membership server-side (never trusts the client list).
* Chain objects: read for approvers/submitter via sharing rules; create/edit restricted to the framework's permission set. Two permission sets ship: `Approval_Matrix_User`, `Approval_Matrix_Admin`.

---

## 13. Packaging & Object Onboarding (2–3 objects)

**Shared core (unmanaged package / repo module):** all Apex, LWC, CMDT type definitions, chain objects, permission sets.
**Per-object add-on (checklist, ~half a day each):**

1. Create the three per-object fields (§3.3)
2. Clone the generic 1-step Approval Process from the template spec
3. Create the record-triggered Chain Advancer flow (template)
4. Add the Quick Action + layout changes; remove standard submit
5. One `Approval_Object_Config__mdt` row
6. Run the config validator; smoke-test with a 2-level rule

---

## 14. Known Constraints & Trade-Offs (state these to stakeholders)

1. **Approval history is per-cycle.** A 5-level chain shows 5 process instances, not one 5-step history. The chain record page (with a timeline LWC) is the human-readable view; this is a presentation cost of unlimited depth.
2. **Group levels show the service user in native history.** True actor is on the chain step (§5.1).
3. **`Approval.unlock()` org setting** must be enabled.
4. **Delegated approvers** (native `DelegatedApproverId`) work per cycle but the delegate is recorded as actual approver — matches SOX expectations, but confirm with compliance.
5. **Platform direction:** Salesforce's investment is in Flow Approval Orchestration; legacy processes have no announced retirement but the trajectory is clear. The `SubmissionStrategy` seam exists precisely so the execution layer can be swapped to an `OrchestrationStrategy` (which would natively solve queue/group work items and the history-fragmentation trade-off) without touching the rule engine, config schema, or decision log. Position this in the deck as a deliberate migration path, not a risk.

---

## 15. Recommended Build Sequence

| Phase | Content |
|---|---|
| **Spike (wk 0)** | `nextApproverIds` + queue validation (§5.1); `Approval.unlock` behavior across cycles |
| **Phase 1 (wks 1–3)** | Object #1: CMDT schema, engine (evaluator, resolver — users + manager chain), chain objects, single-step process, Advancer, decision log. Demo: admin edits a rule in config → next submission routes differently → chain record explains why |
| **Phase 2 (wks 4–5)** | Group Work Item pattern + Approval Inbox LWC; SLA escalation batch |
| **Phase 3 (wk 6)** | Objects #2–3 via the onboarding checklist (proves portability); config validator; hardening + bulk tests |
