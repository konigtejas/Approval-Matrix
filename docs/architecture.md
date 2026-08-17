# Approval Matrix Framework — Technical Architecture

**Version 3.0 — consolidated and self-contained.** Supersedes v1.0, v2.0 and v2.1. This is the only architecture document; nothing here defers to an earlier version. Where a design changed, Appendix B records what was abandoned and why, because commit `a69e3c9` contains code built to the v1.0 design.

**What the framework is:** an **approval process selection engine**. Prioritised rules held in Custom Metadata are matched against a record by an expression evaluator; the winning rule names a **template** — a real, pre-built Salesforce approval process — and the engine submits the record into it. Salesforce executes everything: steps, approvers, queues, locking, history, notifications. The framework decides *which process* and records *why*.

**Lineage:** the matrix-selects-template pattern was proven in a prior ISV-based implementation. That version was simple because the ISV supplied both the approval engine and the expression evaluator. On vanilla Salesforce the evaluator is ours to build, and three flaws in the original are corrected by design: **no priority ordering** (§3.1), **silent evaluation failures** (§4.6), and **history destroyed by re-evaluation overwriting the template field** (§8).

---

## 0. How to read this document

| Section | Status |
|---|---|
| §1–§12 | Target design |
| §13 | **MVP scope — what is being built right now.** Anything in §1–§12 not listed in §13 is out of scope until the MVP demo passes |
| Appendix A | Spike findings, with confidence labels |
| Appendix B | Superseded designs — do not build |

MVP is **Classic execution only**. Flow execution (§5.3, §6.2) is designed but not built.

---

## 1. Design Principles

1. **Configuration over code.** Routing lives in Custom Metadata. A new rule or a changed rule is a config release, never an Apex change.
2. **Select, don't resolve.** The framework picks a process. It does not resolve approver chains, advance levels, or manage approval state. Depth, queues, groups, escalation and parallelism are properties of the template.
3. **Explain every decision.** Native history answers *who* and *when*. The decision log answers *why*, and is immutable.
4. **Fail loudly.** A malformed expression fails at deployment. A runtime evaluation error blocks the submission and logs it. Never fall through to a wrong template — a stopped approval is recoverable, a mis-routed one is a finding.
5. **Testable and portable.** All Custom Metadata access behind an interface with test injection; all submission behind a strategy interface. Deploys to a new org with zero code changes.

---

## 2. Component Overview

```
Entry points
  Submit quick action (LWC) · Invocable · REST
        │
        ▼
AMF_ApprovalMatrixService          (facade, bulk-safe)
   ├── RuleProvider (interface) ◄── AMF_CmdtRuleProvider | test stub
   ├── AMF_ExprCache            ──► AMF_ExprCompiler ──► AMF_Lexer, AMF_Parser
   ├── AMF_Evaluator                (AST + record → Boolean + evaluated values)
   ├── AMF_FieldPathResolver        (union of paths → ONE dynamic SOQL per object)
   ├── AMF_DecisionLogWriter
   └── SubmissionStrategy (interface)
         ├── AMF_ClassicProcessStrategy   ── Approval.process(
         │                                     setProcessDefinitionNameOrId(name))
         └── AMF_FlowApprovalStrategy     ── launches named Approval Orchestration
        │
        ▼
Template — a native approval process (Classic process OR Flow orchestration)
        │
        ▼
Approval_Decision_Log__c  ──joins──►  ProcessInstance (Classic)
                                      ApprovalSubmission / ApprovalWorkItem (Flow)
```

---

## 3. Data Model

Three artefacts total: one Custom Metadata type, one custom object, one field per governed object.

### 3.1 `Approval_Matrix_Rule__mdt` — the matrix

One row is one complete routing statement: *when this expression is true, use that process.*

| Field | Type | Purpose |
|---|---|---|
| `Object_API_Name__c` | Text(80) | Target object |
| `Priority__c` | Number(5,0) | Lower wins. Ties broken by DeveloperName, so ordering is always deterministic |
| `Expression__c` | Long Text Area(2000) | `Amount__c > 100000 && Account__r.Owner.Region__c == 'APAC'` |
| `Execution_Type__c` | Picklist | `Classic` \| `Flow` |
| `Process_API_Name__c` | Text(80) | Classic: `ProcessDefinition` DeveloperName. Flow: API name of the Approval Orchestration |
| `Description__c` | Text(255) | "High-value APAC → 3-level credit chain" |
| `Version__c` | Number(4,0) | Incremented on any change; stamped into every decision log row |
| `Active__c` | Checkbox | |

**Platform constraint — mandatory.** Apex `getAll()` and `getInstance()` truncate Long Text Area fields to 255 characters. `AMF_CmdtRuleProvider` must load rules by **SOQL**, never the cached accessors, or long expressions corrupt silently. CMDT SOQL consumes no query limits. Pin this with a test whose expression exceeds 255 characters, and state it in the class ApexDoc.

Priority ordering is applied in Apex after load rather than relying on CMDT SOQL ordering.

### 3.2 Conventions replacing per-object configuration

There is no object-config metadata type. Three conventions replace it:

- **Guard field** is always `Matrix_Submission__c` (Checkbox) on every governed object. A framework convention, not a configurable name.
- **No-match** blocks and writes a `Blocked_No_Match` log row. An org wanting default routing adds a visible catch-all rule: priority 9999, expression `TRUE`. The default path then appears *in the matrix*, in priority order, where an auditor reads it — better than a hidden config switch.
- **Governed** ⇔ the object has active rules. Deactivating an object's rules is the kill switch.

### 3.3 `Approval_Decision_Log__c` — the audit artefact

| Field | Type | Purpose |
|---|---|---|
| `Record_Id__c` | Text(18), External Id, **not unique** | Governed record. One record accumulates one row per submission; rows are never deleted |
| `Object_API_Name__c` | Text(80) | |
| `Matched_Rule__c` | Text(80) | Rule DeveloperName. **Platform-forced:** no relationship exists from a custom object to a custom metadata record |
| `Rule_Version__c` | Number(4,0) | |
| `Expression_Snapshot__c` | Long Text(2000) | The expression text as evaluated — survives later edits to the rule |
| `Evaluated_Values__c` | Long Text(32k) | JSON of every field value the evaluator read |
| `Selected_Process__c` | Text(80) | |
| `Execution_Type__c` | Picklist | `Classic` \| `Flow` — tells the timeline which objects to query. **Not built in MVP** (§13.2): with Classic the only execution path the column would carry one constant value. Adding it is a field plus a default, with no engine change |
| `Execution_Ref_Id__c` | Text(18) | `ProcessInstance.Id` (Classic) or `ApprovalSubmission.Id` (Flow) |
| `Outcome__c` | Picklist | `Submitted` \| `Blocked_No_Match` \| `Failed` |
| `Failure_Detail__c` | Long Text(4000) | Exception text when `Failed` |
| `Submitted_By__c` | Lookup(User) | |
| `Submitted_At__c` | DateTime | |

**Immutability.** A validation rule blocks edits after creation. The exception is the **`AMF_Bypass_Log_Lock` custom permission**, not a named profile — a profile name hardcoded into a validation rule does not survive deployment to another org.

**Permission sets.** `Approval_Matrix_Admin` deliberately withholds Modify All on the log object: the platform makes Modify All depend on Delete, and the log must not be deletable. View All plus edit gives admins what they need without opening the audit trail to deletion.

Final approval status is **not** duplicated onto the log — it lives on `ProcessInstance` / `ApprovalSubmission` and is reportable through `Execution_Ref_Id__c`.

### 3.4 Per-object fields

`Matrix_Submission__c` (Checkbox). That is the entire per-object field footprint.

---

## 4. Expression Evaluator

The centrepiece build. What the ISV supplied for free in the prior implementation is ours to own here.

### 4.1 Grammar

```
expression   := or_expr
or_expr      := and_expr ( ('||' | 'OR') and_expr )*
and_expr     := unary_expr ( ('&&' | 'AND') unary_expr )*
unary_expr   := ('!' | 'NOT') unary_expr
              | '(' expression ')'
              | comparison
              | bool_atom
comparison   := operand comp_op operand
              | operand ('IN' | 'NOT IN') list
              | operand ('CONTAINS' | 'STARTS_WITH') operand
comp_op      := '==' | '!=' | '>' | '>=' | '<' | '<='
bool_atom    := TRUE | FALSE | boolean_field_path
operand      := field_path | literal
field_path   := IDENT ( '.' IDENT )*                    // max 4 hops, __r traversal
literal      := NUMBER | 'STRING' | DATE | DATETIME
              | TRUE | FALSE | NULL | TODAY | TODAY(±n)
list         := '(' literal ( ',' literal )* ')'
```

Keywords are case-insensitive. Both symbol and word forms of and/or/not are accepted, so admins may write `AND` and developers `&&`. A bare `TRUE`, `FALSE`, or Checkbox field path is a complete valid expression — this is what makes catch-all rules expressible.

Operator precedence: `NOT` binds tightest, then comparisons, then `AND`, then `OR`. `a || b && c` parses as `a || (b && c)`.

### 4.2 Pipeline

```
Expression__c ──► AMF_Lexer ──► AMF_Parser ──► AST ──► AMF_ExprCompiler ──► CompiledExpression
                                                                                    │ cached by
                                                                                    │ rule + version
Record + CompiledExpression ──► AMF_Evaluator ──► Boolean + Map<String,Object>
```

| Class | Responsibility |
|---|---|
| `AMF_Lexer` | String → token stream, tracking character position for error messages: `Unexpected token ']' at position 34` |
| `AMF_Parser` | Recursive descent → AST. Node types: `BinaryNode`, `UnaryNode`, `ComparisonNode`, `FieldNode`, `LiteralNode`, `ListNode`. Fails with position and expected-token detail |
| `AMF_ExprCompiler` | Parse **plus static analysis against the schema**: every field path resolves via describe, ≤4 hops, operator/type compatibility enforced. `CONTAINS` on a Currency field is a compile error, not a runtime false. Output: AST + field-path list + describe map |
| `AMF_ExprCache` | Static map keyed by rule DeveloperName + `Version__c` → `CompiledExpression`. Each expression compiles once per transaction regardless of record count |
| `AMF_Evaluator` | AST + SObject → Boolean, and emits the evaluated-values map for the decision log |

### 4.3 Type semantics

| Field type | Comparison | Notes |
|---|---|---|
| Currency, Number, Percent | Decimal | Literal must lex as NUMBER or it is a compile error |
| Date, DateTime | Chronological | Literals `2026-01-31`, ISO datetime, `TODAY`, `TODAY(±n)` |
| Boolean | Identity | Only `==` / `!=` permitted, compile-enforced |
| Picklist, String, Id, Reference | Case-insensitive equality; `CONTAINS`, `STARTS_WITH`, `IN` |
| Multipicklist | `CONTAINS` = set membership; `==` = exact set match |

**Null rules**, stated once and tested exhaustively: `null == null` is true; `null` against `>`, `>=`, `<`, `<=` is false and never throws; `IN` with a null operand is false; null anywhere in a relationship path makes the comparison false. Presence checks are written `Field__c == NULL` / `Field__c != NULL`.

### 4.4 Field path resolution

`AMF_FieldPathResolver` collects the union of every field path across all rules for an object and builds **one** dynamic SOQL query covering them, executed once per object per transaction. Relationship traversal uses `__r` dot notation, capped at 4 hops (platform limit), enforced at compile time.

### 4.5 Caching

Compilation is the expensive step; evaluation is cheap. The cache key includes `Version__c` so a rule edit invalidates naturally without a flush mechanism.

### 4.6 Failure behaviour — the anti-Sitetracker rule

The prior implementation wrapped evaluation in `try { … } catch { return false; }`. A malformed criteria string therefore never matched, forever, silently. Here:

- **Compile errors cannot reach runtime.** The config validator (§9) compiles every active expression at deploy time and fails the deployment with position-annotated messages.
- **Runtime errors** (schema drift after deploy — a referenced field deleted) mark the submission `Failed`, write the exception to `Failure_Detail__c`, and **block**. They never fall through to the next rule.

No catch block in the evaluator package may swallow an exception into a boolean.

### 4.7 Test strategy

Table-driven: a static list of `(expression, field values, expected)` triples covering every operator against every supported type, all null rules, precedence, both keyword forms, whitespace variants, multi-hop paths, and bare boolean atoms. Plus a malformed-input suite — unbalanced parens, unknown field, over-deep path, bad literal, type mismatch, empty `IN` list — asserting each throws with the correct character position. Target ≥95% coverage on the evaluator package with zero dependence on org CMDT rows.

---

## 5. Template Layer

Templates are approval processes **authored as metadata and versioned in the repo**. They are deliverables, not org clicks.

### 5.1 Versioning convention

A live template is never edited in place. Changes clone to `_v2`, the rule's `Process_API_Name__c` is repointed, and the previous version is deactivated. In-flight instances and historical accuracy both survive.

Naming: `<OBJ>_<Shape>`, e.g. `PR_Three_Level_Finance`.

### 5.2 Classic templates

Native Approval Processes as metadata XML.

- **Entry criteria on every template**: `Matrix_Submission__c = true`. This is the guard (§6.3).
- **Final approval and rejection actions** reset `Matrix_Submission__c = false`, re-arming the guard.
- Steps, approvers, parallel approvers and static queue steps are configured natively.

### 5.3 Flow templates

A Flow Approval Process is a `Flow` with `processType` **`ApprovalWorkflow`**. Confirmed contract (Appendix A, Q1):

- Requires exactly three input variables, all String, all `isInput=true`: **`recordId`**, **`submitter`**, **`submissionComments`**. The third is not `comments` — that spelling is rejected.
- Approval steps use `actionType` **`stepApproval`**. `stepInteractive` is rejected for this process type.
- **Each approval step delegates to a companion screen flow** that the approver runs. A Flow template is therefore an orchestration *plus* at least one screen flow per approval step. Budget accordingly.
- **A structurally invalid orchestration deploys cleanly as `Draft`** and only fails on activation. Existence checks must verify *active*, not merely present (§9).

Launch is via `AMF_FlowApprovalStrategy`; the exact Apex call is unconfirmed (Appendix A, Q1) — no standard invocable action starts an orchestration, so the likely mechanism is `Flow.Interview.createInterview` with the three inputs. The strategy interface isolates whichever lands.

### 5.4 Choosing Classic or Flow per rule

| Classic | Flow |
|---|---|
| Simple sequential user chains | Any queue or group step — `ReviewedById` gives the true actor natively |
| Existing org standards require it | Multi-stage flows, background steps, conditional stages, sub-flow reuse |
| Fewer moving parts (no companion screen flows) | Platform direction; no automation-credit consumption |

**Open risk:** the case for routing every group step to Flow rests on native any-member/unanimous semantics that are **not yet verified** (Appendix A, Q3). Do not commit the template library to that assumption until it is tested.

### 5.5 The shape-count trade

Conditions are unlimited configuration; **shapes are processes**. "Route to APAC vs EMEA credit queue" is two templates, because the queue is a design-time step property. The framework keeps this honest by making shapes cheap (metadata in the repo, cloned in minutes) and visible (the matrix lists every process in use). If an org ever needs more approver-*shape* variability than approver-*condition* variability, the `SubmissionStrategy` seam is where a chain-resolving execution would plug in without touching the evaluator or the matrix.

---

## 6. Engine

### 6.1 Submission flow

```
submit(List<Id> recordIds):
 1. Load rules via RuleProvider for the object; none active → not governed, error
 2. Order by Priority__c, then DeveloperName
 3. Compile all expressions once via AMF_ExprCache
 4. Union of field paths → ONE dynamic SOQL (§4.4)
 5. Per record, rules in priority order → FIRST true expression wins
 6. No match → write Blocked_No_Match log row, throw a clear error
 7. Resolve template: Process_API_Name__c + Execution_Type__c
 8. Write Approval_Decision_Log__c (rule, version, expression snapshot,
    evaluated values JSON, selected process)
 9. Set Matrix_Submission__c = true — same transaction, before submit
10. SubmissionStrategy.submit(...) per Execution_Type__c; chunk ≤100 per
    Approval.process() call
11. Stamp Execution_Ref_Id__c onto the log row
```

### 6.2 Submission strategies

```apex
public interface SubmissionStrategy {
    // returns the execution reference id (ProcessInstance or ApprovalSubmission)
    List<SubmitResult> submit(List<SubmitRequest> requests);
}
```

`AMF_ClassicProcessStrategy` calls `Approval.process()` with `ProcessSubmitRequest.setProcessDefinitionNameOrId(processApiName)` and returns `ProcessInstance` Ids. `AMF_FlowApprovalStrategy` launches the named orchestration and returns `ApprovalSubmission` Ids. Nothing upstream of step 10 knows which is in play.

### 6.3 The guard

The standard **Submit for Approval** button is removed from every governed object's layouts. Every Classic template's entry criteria require `Matrix_Submission__c = true`, which only the engine sets, and only in the same transaction as its own submission. A submission that bypasses the engine therefore fails entry criteria loudly rather than routing silently.

Flow templates need no entry-criteria dance — an autolaunched orchestration runs only when explicitly launched — but the guard field is still set, for uniform decision-log semantics and as defence against a record-triggered orchestration someone adds later.

### 6.4 Preview

`preview(List<Id>)` runs steps 1–7 and returns matched rule, description and template name **without** writing a log row or submitting. Same code path, `commit = false`. This drives the submit action's confirmation modal.

### 6.5 What the engine does not do

No approver resolution. No chain advancement. No lock management. No mid-flight state. Recall, reassignment, delegation and escalation are the template's and the platform's concern. The engine's runtime responsibility ends at step 11.

---

## 7. Entry Points

| Path | Mechanism |
|---|---|
| UI | `amfSubmitForApproval` headless LWC quick action → preview → confirm → submit |
| Flow | `AMF_SubmitForMatrixApproval` invocable |
| Apex | Direct service call |
| Integration | `@RestResource` wrapper |

**Recall.** For Classic submissions, native recall applies. For Flow submissions, `recallApprovalSubmission`, `cancelApprovalSubmission`, `reassignApprovalWorkItem` and `reviewApprovalWorkItem` exist as standard invocable actions with REST endpoints, callable from Apex via `Invocable.Action.createStandardAction(...)` — but none has been executed against a live submission (Appendix A, Q4). Do not design a screen-flow-only recall path, and do not build the Apex path either, until one has been proven.

---

## 8. Auditability

- **Why** — `Approval_Decision_Log__c`: matched rule, version, expression snapshot, evaluated values. Immutable, never deleted.
- **Who and when** — native. Classic: `ProcessInstance` / `ProcessInstanceStep`. Flow: `ApprovalSubmission` / `ApprovalWorkItem`, where `ReviewedById` is the actual approver natively.

```
Approval_Decision_Log__c.Execution_Ref_Id__c == ApprovalSubmission.Id   (Flow)

SELECT Id, Status, AssignedToId, ReviewedById, ReviewedDate, Comments, ParentWorkItemId
FROM   ApprovalWorkItem
WHERE  ApprovalSubmissionId = :executionRefId
ORDER BY CreatedDate
```

`ApprovalSubmission.RelatedRecordId` points back at the governed record, so submissions are reachable without the log. `Execution_Ref_Id__c` therefore earns its place as an immutable provenance stamp rather than the only join path — it must not be "optimised" away.

A read-only timeline LWC renders both halves as one narrative: *"Matched **High-value APAC** v3 because Amount = 24,00,000 and Region = APAC → PR_Three_Level_Finance → [native step history]"*.

**This fixes the prior implementation's deepest flaw.** There, re-evaluation overwrote the template field, so the mechanism that kept routing current destroyed the historical record. Here every submission writes a permanent row; the current answer and the historical answer are different records.

---

## 9. Config Validator

Runs at deploy time and is also exposed as an invocable for post-deploy pipeline checks. Deployment fails when:

- Any active expression fails to compile (message includes character position)
- A `Classic` rule's `Process_API_Name__c` has no **active** `ProcessDefinition` of type Approval for that object
- A `Flow` rule's `Process_API_Name__c` has no **active** flow of `processType` `ApprovalWorkflow` — active, not merely present, because Draft orchestrations deploy clean (§5.3)
- Two active rules share the same object and priority
- A governed object lacks `Matrix_Submission__c`
- A Classic template's entry criteria omit the guard

---

## 10. Testability

- `RuleProvider` stub with a fluent `AMF_RuleBuilder` fixture — no test depends on org CMDT rows.
- `SubmissionStrategy` stub asserts the staged guard field and selected process without executing a real approval; one thin integration test per template exercises the real path.
- Evaluator tested against standard objects where possible to avoid org-specific schema coupling.
- Custom Metadata cannot be inserted in tests. This is why the provider interface is non-negotiable rather than a nicety.

---

## 11. Security

- The service runs `without sharing` (it is infrastructure) but authorises explicitly: submission requires read access to the record.
- Two permission sets: `Approval_Matrix_User` (submit, read own logs), `Approval_Matrix_Admin` (read all logs, manage config — Modify All deliberately withheld, §3.3).
- Flow approvals additionally require access to `ApprovalSubmission` and `ApprovalWorkItem`, and edit on the submitted object; Run Flows may be required depending on context.

---

## 12. Known Constraints and Open Questions

1. **Group any-member / unanimous semantics on Flow steps are unverified** (Appendix A, Q3). §5.4's guidance depends on them. Highest-priority open item.
2. **The Flow launch call is inferred, not executed** (Appendix A, Q1).
3. **Flow templates cost more than one flow each** — orchestration plus a companion screen flow per approval step.
4. **Retiring a shape** means editing every rule that references it; there is no template registry. The validator makes stale references a deployment failure. If an org ever has dozens of rules sharing shapes, a registry reintroduces additively with no engine change.
5. **Classic remains fully supported** and Flow Approval Processes consume no automation credits. The dual-strategy design is the hedge: rules migrate `Classic` → `Flow` one row at a time with zero engine change.

---

## 13. MVP Scope

The MVP proves one thing: **an admin changes one Custom Metadata row, the next submission routes to a different approval process, and a log record explains why.** Everything else is hardening.

### 13.1 In scope

- One object: `Purchase_Request__c` (`Amount__c`, `Region__c`, `Risk_Level__c`)
- `Approval_Matrix_Rule__mdt` — **without `Execution_Type__c`** (Classic-only)
- `Approval_Decision_Log__c` — also **without `Execution_Type__c`**, for the same reason — and `Matrix_Submission__c`
- `RuleProvider` + `AMF_CmdtRuleProvider` (SOQL-based, §3.1)
- Expression evaluator, **reduced grammar** (§13.3)
- Engine steps 1–11, Classic branch only
- `SubmissionStrategy` + `AMF_ClassicProcessStrategy`
- Two Classic templates, whose shapes this document originally left unstated and which are now
  fixed as: `PR_Two_Level_Mgmt` — two steps up the **Manager hierarchy**, which is what the
  seeded `amfu1 → amfu5` chain exists for; `PR_Three_Level_Finance` — three **named-user** steps,
  `amfu3 → amfu4 → amfu5`. Two visibly different shapes, so the rule-flip demo is unmistakable
- Submit quick action, **no preview modal**

### 13.2 Out of scope — do not build, do not stub

Flow strategy · `Execution_Type__c` · queue or committee templates · preview modal · timeline LWC · config validator · bulk chunking · recall handling · second object · `_v2` cloning · template registry.

### 13.3 Reduced MVP grammar

Supported: `&&`, `||`, parentheses, `== != > >= < <=`; field paths up to 2 hops; types Number/Currency, String, Picklist, Boolean, Date; literals NUMBER, `'STRING'`, TRUE, FALSE, NULL, `YYYY-MM-DD`; bare `TRUE` as a complete expression.

Deferred: `IN`, `NOT IN`, `CONTAINS`, `STARTS_WITH`, `NOT`/`!`, `TODAY(±n)`, multipicklist, 3+ hop paths.

The lexer, parser and AST must be structured so these are **additive** — no special-casing around their absence.

### 13.4 Phases

| Phase | Content | Gate |
|---|---|---|
| **M0** | Scaffold, org connectivity, `Purchase_Request__c`, guard field, seed users with manager chain | Deploy + seed green |
| **M1** | Single CMDT, decision log, three sample rules, SOQL-based provider | Long-expression (>255 char) test passes |
| **M2** | Evaluator, reduced grammar, table-driven + malformed-input suites | ≥90% coverage, zero org dependence |
| **M3** | Engine, Classic strategy, two templates, log write, submit action | **Manual QA:** change a rule's process in CMDT, redeploy, watch routing change with no code touched |

### 13.5 Repository state

Commit `a69e3c9` contains Phase 0 and Phase 1 built to the **v1.0** design: four Custom Metadata types, chain objects, permission sets, 14 CMDT records, list views. None of it matches this document.

**Reusable:** `sfdx-project.json`, `AMF_Ping`, `scripts/seed-data.apex`, `Purchase_Request__c`.
**Retired:** all four v1 CMDT types, both chain objects, v1 permission sets and list views.

~~Because the v1 metadata is also deployed to `amf-dev`, a fresh Developer Edition org is faster than destructive deploys against Custom Metadata types.~~ **Superseded by events.** The destructive deletes succeeded against `amf-dev` at `71fd786` and in M0, so the MVP builds there and keeps Phase 0's seeded users, queue and group. The one thing that genuinely resisted deletion was `Approval_Chain__c`, held by a soft-deleted `Purchase_Request__c.Active_Chain_del__c` in the recycle bin — a relationship the Metadata API cannot address, cleared by a manual Setup erase rather than a new org.

---

## Appendix A — Spike Findings (2026-08-14, `amf-dev`, API 62.0)

Full detail in `docs/spike-results.md`. Confidence labels are load-bearing.

| # | Question | Status |
|---|---|---|
| Q1 | Flow template contract: `processType ApprovalWorkflow`, three String inputs (`recordId`, `submitter`, `submissionComments`), `actionType stepApproval`, companion screen flow per step, Draft deploys unvalidated | **CONFIRMED** |
| Q1 | Apex launch call for an orchestration | **INFERRED** — no standard invocable exists; `Flow.Interview.createInterview` is the likely mechanism; blocked on completing a companion screen flow |
| Q2 | Timeline join: `ApprovalSubmission` / `ApprovalWorkItem` field shapes; `ReviewedById` supplies the true approver natively | **CONFIRMED** |
| Q3 | Group step any-member / unanimous semantics | **OPEN** — highest-risk gap; `ParentWorkItemId` is the structure to examine |
| Q4 | `recallApprovalSubmission`, `cancelApprovalSubmission`, `reassignApprovalWorkItem`, `reviewApprovalWorkItem` exist as standard invocable actions with REST endpoints | **CONFIRMED as available**, execution untested |

Q4 contradicts the earlier assumption that recall was unavailable to autolaunched flows and must be a screen flow. Neither design should be built until an action has been executed against a live submission.

Artefact: `AMF_Spike_Approval` is deployed to `amf-dev` as Draft. Not project source — delete it or complete it into the first real Flow template.

---

## Appendix B — Superseded Designs (do not build)

The v1.0 design resolved approver chains rather than selecting templates. Everything below was deleted when the architecture changed, and represents roughly 60% of the original build. Code for some of it exists at commit `a69e3c9`.

| Abandoned | Replaced by |
|---|---|
| Chained single-step approval process + Chain Advancer flow | Templates are real multi-step processes; depth lives in the template |
| `Approval.unlock()` re-submit cycling | One submission per record |
| `Approver_1..N__c` / `Current_Approver__c` staging fields | No field-based approver injection |
| `AMF_ApproverResolver` (user/queue/group/manager expansion) | Approvers are configured inside the template |
| Group Work Item pattern, service user, Approval Inbox LWC | Native group work items on Flow templates (pending Q3) |
| `Approval_Chain__c` / `Approval_Chain_Step__c` state machine | Native `ProcessInstance` / `ApprovalSubmission` + decision log |
| Four CMDT types incl. numbered conditions and route steps | One CMDT type with a single expression string |
| SLA escalation batch | Template-level time-dependent actions |
| Template registry CMDT | Direct `Process_API_Name__c` + validator existence checks |

The corresponding entries in `docs/decisions.md` dated 2026-08-12 are historical context for `a69e3c9`, not current design. Four of those decisions survive and are incorporated above: `Matched_Rule__c` as Text (§3.3), `Record_Id__c` non-unique external id (§3.3), custom permission rather than profile for the immutability bypass (§3.3), and Modify All withheld from the admin permission set (§3.3).