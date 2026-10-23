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
6. **AI assists; it never decides** (M13). The engine selects every route and the platform runs every approval. AI explains decisions already recorded, briefs the approver an approval is waiting on (M14), and lets people preview, try what-ifs and submit in conversation through the same engine paths as every other entry point. It is never asked to choose a route, evaluate a rule, write a log row, approve, or tell an approver what to decide. An explanation or a briefing is presentation: generated on demand, labelled, and never stored. The decision log stays the only record of why.

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

**M11 implementation (2026-10-21): the claim, tested on Opportunity.** Governing a second object,
and a standard one, took configuration and conventions alone, with no engine or LWC change:

- the guard field, with field-level access to it in both permission sets;
- Classic templates whose only entry criterion is the guard, with the object's own clearing field
  update on all three exits (§5.2);
- the framework's quick action in place of the standard button on every layout of the object
  (§6.3);
- the rules;
- a lookup on the decision log for the related list, which the log writer finds by describe;
- a record page carrying the timeline (§8).

What surfaced lay outside the engine, as expected:

- A standard object's layouts already list the standard Submit button. They are org-owned
  metadata, and they tie the source to the org they came from. M12 moved them to an org package
  directory (§6.3).
- Approvers need a license that includes the object, and the platform does not check that when it
  assigns them (§11).
- SOQL does not enforce the relationship limit the validator was going to count against (§4.4).

Technical log M11 has the details.

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

**M9 implementation (2026-10-08).** The whole grammar above is built except `DATETIME` literals,
which wait on DateTime fields (§4.3). Three readings were settled while building it
(`docs/decisions.md`):

- **`NOT` takes a whole comparison.** The productions make `NOT`'s operand a `unary_expr`, which
  can be a comparison, so `NOT a == b && c` is `(NOT (a == b)) && c`. "`NOT` binds tightest" means
  tightest of the logical operators; `(NOT a) == b` would apply `NOT` to a non-Boolean.
- **`TODAY()`** with empty parentheses is accepted as `TODAY`. The offset is a whole number of days,
  at most 36,500 either way.
- **`NOT IN` is exactly `NOT (… IN …)`**, and `IN` is `==` against any one value of the list.

Keywords are reserved: `AND`, `OR`, `NOT`, `IN`, `CONTAINS`, `STARTS_WITH`, `TODAY`, `TRUE`, `FALSE`,
`NULL`. The parser emits each operator in one canonical spelling (`&&`, `||`, `!`, `IN`, `NOT IN`,
`CONTAINS`, `STARTS_WITH`), because Apex `switch on` a String is case-sensitive.

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

**M9 implementation (2026-10-08).** What the table leaves open, settled (`docs/decisions.md`):

| Construct | Semantics as built |
|---|---|
| `IN` / `NOT IN` | Every single-valued type: numeric, date, Boolean, text. `NULL` is refused in the list and as the operand, which keeps "`IN` with a null operand is false" exact; `NOT IN` of a null operand is therefore true |
| `CONTAINS` / `STARTS_WITH` | Text only, case-insensitive like text equality; either side may be a field. A null on either side is false |
| Multipicklist | Compared only with a text literal listing values separated by `;`. `==` / `!=` are an exact set match, in any order and case; `CONTAINS 'A;B'` means every listed value is selected (membership, never substring). A literal naming no values is a compile error: a blank multipicklist reads `NULL`. `IN`, `STARTS_WITH` and ordering are refused |
| `TODAY` / `TODAY(±n)` | Compared with Date fields. Resolved once per transaction to the running user's local date (`Date.today()`), the submitter's for a submission. The date it resolved to is recorded in `Evaluated_Values__c` under the key `TODAY`, because the decision depended on it (§3.3) |
| DateTime | **Still not supported**; a DateTime field is a compile error naming its type |

**A broken relationship path is *unknown*, not false.** Before `NOT` the two were indistinguishable.
With it, `NOT (Account__r.Name == NULL)` would be true for a record with no Account, which is the
silent presence check the relationship-path rule exists to forbid. So a comparison over a broken
path is unknown, and `AND`, `OR` and `NOT` follow three-valued (Kleene) logic, as in SQL. A rule
matches only when its expression is definitely true. Every expression written before M9 evaluates
exactly as it did, and the unknown is confined to broken paths: a null *leaf* value is an
ordinary value under the rules above.

### 4.4 Field path resolution

`AMF_FieldPathResolver` collects the union of every field path across all rules for an object and builds **one** dynamic SOQL query covering them, executed once per object per transaction. Relationship traversal uses `__r` dot notation, capped at 4 hops (platform limit), enforced at compile time.

**M9 implementation (2026-10-08).** The cap is **four segments**: a field reached through three
relationship hops, such as `Account__r.Owner.Profile.Name`. That reads "4 hops" in the unit §13.3
uses, where `Account__r.Region__c` is two. "Platform limit" was wrong: SOQL allows **five**
relationship hops (six segments) and refuses a sixth ("cannot query foreign key relationships
more than 5 levels away from the root SObject", measured in `amf-dev`). The cap is one constant,
`AMF_ExprCompiler.MAX_PATH_SEGMENTS`, which the resolver also enforces.

**Corrected in M11 (2026-10-21).** This note went on to say that a query may name at most 55
child-to-parent relationships across the union of an object's rules, the limit Salesforce
documents. Measured in `amf-dev`, Apex does not enforce it. One dynamic query at API 62 joined 142
distinct relationships from `WorkOrder` and returned its row; another joined 400 relationship paths
from Opportunity. The validator therefore runs each object's union query rather than counting
against a number (§9).

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

**M12 implementation (2026-10-22): the convention is enforced.** `config/template-releases.json`
lists every released template with a fingerprint. The fingerprint is the SHA-256 of the
template's XML, without `<active>`, with insignificant whitespace dropped and line endings
normalised. The source gate (§9) fails:

- a released template whose fingerprint has changed;
- a template in source that is not released;
- a released template missing from source;
- a superseded version that is still active (`X_v2` supersedes `X`, and `X_v3` supersedes both);
- a rule that names a superseded version.

Activation is the one change a released template may undergo. Releasing a template is one
deliberate line in the manifest, which the gate prints, fingerprint included.

Source is kept in the form a retrieve returns, so that a retrieve does not disturb a fingerprint.
On deploy, the platform drops `rejectBehavior` from a template's first step, and appends `Owner`
to a custom object's approval page fields. All six templates now carry those forms (technical log
M12). The gate reads source, not the org. M12's gate also retrieved every template once and
matched each against the manifest.

### 5.2 Classic templates

Native Approval Processes as metadata XML.

- **Entry criteria on every template**: `Matrix_Submission__c = true`. This is the guard (§6.3).
- **Final approval, final rejection and recall actions** reset `Matrix_Submission__c = false`,
  re-arming the guard. A request can leave the process by any of the three, and the guard must be
  cleared on each. Recall was missing until M8 (2026-10-08): a recalled record kept the guard set,
  so a submission bypassing the engine passed entry criteria (technical log M7.8). The source gate
  now requires the clearing action on all three.
- Steps, approvers, parallel approvers and static queue steps are configured natively.

**M12 implementation (2026-10-22): queue and committee shapes.**

- `PR_Credit_Risk_Queue` assigns its one step to the queue `Q_Credit_Risk`. Any member decides,
  including a member of a public group that the queue holds. Someone outside the queue cannot,
  whatever their access to the record.
- `PR_Finance_Committee` lists `amfu1` to `amfu3` in one step, `Unanimous`, then `amfu4` and
  `amfu5`, `FirstResponse`. Classic cannot name a public group as an approver, so a committee
  names its members as users, and a group reaches a step only through a queue.
  - Unanimous gives each member a work item, and one rejection ends the request.
  - First response withdraws the other work items, which history records as `NoResponse`.
- Templates name users as `<alias>@{{AMF_USERNAME_DOMAIN}}` (§11).

### 5.3 Flow templates

A Flow Approval Process is a `Flow` with `processType` **`ApprovalWorkflow`**. Confirmed contract at Summer '26 / API 67.0 (Appendix A; detail and evidence in `docs/spike-results.md`, Round 2):

- Requires **four** input variables, all String, all `isInput=true`: **`recordId`**, **`submitter`**, **`submissionComments`**, **`firstApprover`**. The third is not `comments` — that spelling is rejected. (Round 1's Draft deploy at API 62.0 asked for only the first three.)
- Must declare `runInMode` **`SystemModeWithoutSharing`**: approval orchestrations run without sharing.
- Approval steps use `actionType` **`stepApproval`**; `stepInteractive` is rejected. Background steps use **`stepBackground`**; `flow` is rejected.
- **Each approval step delegates to a companion screen flow** that outputs `approvalDecision` (`Approve` / `Reject`, exact spelling) and `approvalComments`. A Flow template is therefore an orchestration *plus* at least one screen flow per approval step. Budget accordingly.
- **A structurally invalid orchestration deploys cleanly as `Draft`** and only fails on activation. Existence checks must verify *active*, not merely present (§9). Some invalid values are worse: `requiresMultiMemberApproval` is dropped **silently** even from an active deploy.
- **Approvers are usernames**, literal or through a `Resource` variable; a User Id fails activation (literal) or launch (variable). Literal `User`/`Group`/`Queue` assignees block packaging, so a portable template resolves approvers through variables.
- **Rejection does not stop the orchestration.** Later stages still run. Every level after the first is gated by a Decision on `<PreviousStep>.Outputs.approvalDecision` — never on an `outputParameters` mapping, which stays null.
- **Locking is per step** (`shouldLock`), applied synchronously at launch and released on completion. Classic's lock-on-submit is not the default.
- **Final actions are background stages**; the recall path is a start-element scheduled path of type `ApprovalRecall`. Recall runs it; **cancel does not**.

Launch is via `AMF_FlowApprovalStrategy`, and the Apex call is now **confirmed**: `Flow.Interview.createInterview(<ApiName>, inputs).start()`. The `ApprovalSubmission` and first `ApprovalWorkItem` exist synchronously, in the caller's transaction, so step 11 stamps `ApprovalSubmission.Id` exactly as it stamps `ProcessInstance.Id` for Classic. No standard invocable action starts an orchestration. A launch fault throws `System.FlowException` synchronously and rolls the transaction back.

### 5.4 Choosing Classic or Flow per rule

| Classic | Flow |
|---|---|
| Simple sequential user chains | Any queue or group step — `ReviewedById` gives the true actor natively |
| Existing org standards require it | Multi-stage flows, background steps, conditional stages, sub-flow reuse |
| Fewer moving parts (no companion screen flows) | Platform direction; no automation-credit consumption |

**Open risk:** the case for routing every group step to Flow rests on native group semantics. **Any-member is now confirmed** for groups and queues (Appendix A, Q3); **unanimous is not**, because the metadata value for "Require unanimous approval" is unknown. Do not commit committee templates to Flow until it is tested.

**M12 (2026-10-22): committees on Classic now.** Classic carries queue and committee steps until
Flow's unanimous value is known. A committee rule can then move to Flow one row at a time
(§12 item 5). The case for Flow on group steps is also narrower than the table suggests, because
Classic history records the true actor too. On a queue step, `ProcessInstanceStep.ActorId` is the
member who decided and `OriginalActorId` is the queue, and the timeline shows both (§8).

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

**M8 implementation (2026-10-08): a record already in an approval process is refused.** After
authorisation and before step 1, the engine looks for a pending `ProcessInstance` on each record.
If it finds one, it refuses the whole call with a message naming the process. That covers the
preview as well, so the confirmation modal never offers a route the platform would then refuse
with `ALREADY_IN_PROCESS`. It writes no decision log row: nothing was decided, exactly as for a
record the caller cannot read. Running the check after authorisation means it reveals nothing about
records the caller cannot read.

**M10 implementation (2026-10-08): one record at a time, and the log after the answer.**

- **Two contracts, one path.** `submit()` and `preview()` keep the whole-call contract the header
  button relies on: a record the caller cannot read, or one already in approval, refuses the call.
  `submitEach()`, behind the bulk entry points (§7), answers per record instead:
  - such a record gets a `Refused` outcome and no log row;
  - a duplicate Id is answered once;
  - records are grouped by object, and a fault that condemns one object's records (not governed,
    no guard field, a rule that will not compile) refuses only those records.

  Steps 1–7 are one step that writes nothing, `prepare()`, shared by all three entries; the preview
  is that step alone.
- **The log is written after the platform answers.** Step 10 now runs before step 8, and step 11
  folds into it. Each row is written once: with the `ProcessInstance` Id, or, when the platform
  refuses a record, as a `Failed` row carrying the platform's reason, with that record's guard
  re-armed in the same transaction. Before M10 the row came first, so a refusal had to roll back
  the whole call, and every other record's row with it. This also changes the header button: a
  platform refusal there now leaves a `Failed` row instead of nothing.
- **The guard is staged record by record** (M10.3b, 2026-10-21). Step 9 sets
  `Matrix_Submission__c` without all-or-nothing. A record the platform will not let it set,
  because it fails a validation rule for example, becomes a `Failed` row carrying the platform's
  reason and is never submitted, while the others go ahead. The header button gets the same
  answer, where the update used to throw. Re-arming a refused record's guard stays
  all-or-nothing: a record left with its guard set and in no process is the bypass §6.3 closes,
  so the call fails instead. The lock a final approval leaves is **not** a case to count on: in
  an Apex test it did not stop a non-admin's guard update (technical log M10.8).
- **Duplicates.** `submit()` refuses a record Id that appears twice; `submitEach()` submits it once
  and answers every request.

### 6.2 Submission strategies

```apex
public interface SubmissionStrategy {
    // returns the execution reference id (ProcessInstance or ApprovalSubmission)
    List<SubmitResult> submit(List<SubmitRequest> requests);
}
```

`AMF_ClassicProcessStrategy` calls `Approval.process()` with `ProcessSubmitRequest.setProcessDefinitionNameOrId(processApiName)` and returns `ProcessInstance` Ids. `AMF_FlowApprovalStrategy` launches the named orchestration and returns `ApprovalSubmission` Ids. Nothing upstream of step 10 knows which is in play.

**M10 implementation (2026-10-08).** A strategy answers per record: one `AMF_SubmitResult` for every
request, either succeeded with the execution reference or not succeeded with the platform's reason.
A refusal is data, not an exception; an exception means the strategy itself failed, and the call
rolls back. `AMF_ClassicProcessStrategy` submits in chunks of at most 100 requests per
`Approval.process()` call with `allOrNone` false, so one refused record does not undo the others.

### 6.3 The guard

The standard **Submit for Approval** button is removed from every governed object's layouts. Every Classic template's entry criteria require `Matrix_Submission__c = true`, which only the engine sets, and only in the same transaction as its own submission. A submission that bypasses the engine therefore fails entry criteria loudly rather than routing silently.

Flow templates need no entry-criteria dance — an autolaunched orchestration runs only when explicitly launched — but the guard field is still set, for uniform decision-log semantics and as defence against a record-triggered orchestration someone adds later.

**M11 implementation (2026-10-21): the removal is enforced.** On Lightning layouts the standard
button is the action-list entry `Submit` / `StandardButton`. A layout with no action list shows the
platform's default set, which includes the button once an approval process exists (technical log
M3.9). All four of Opportunity's stock layouts listed it explicitly. The source gate (§9) now
fails any layout of a governed object that keeps it or has no explicit list, and fails a governed
object with no layout in source, because a layout that exists only in the org cannot be checked.
The UI API confirmed the result on the record page. It also showed that the Approval History
related list offers no submit action, so the layout's action list is the only place to remove the
button.

**M12 (2026-10-22): a standard object's layouts are the org's.** They reference the org's own
fields, and deploying them overwrites the adopting org's pages. So they live in an org package
directory, `org-config/amf-dev`, which is deployed only to that org, together with the object's
own settings. The framework package, `force-app`, holds neither, and the source gate fails either
there. In another org, removing the standard button from a governed standard object's layouts is
a deployment step for that org's admin. The gate can show it only once those layouts are in that
org's own package directory.

### 6.4 Preview

`preview(List<Id>)` runs steps 1–7 and returns matched rule, description and template name **without** writing a log row or submitting. Same code path, `commit = false`. This drives the submit action's confirmation modal.

**M5 implementation (2026-09-25).** `submit()` and `preview()` both call one private
`run(recordIds, commitDecision)`; the flag is not named `commit` because Apex reserves the word.
A preview returns the same `Outcome` a submission does, plus the rule's priority, its expression
and the evaluated-values JSON — the fields `Expression_Snapshot__c` and `Evaluated_Values__c`
would record, which the submitter can already read on their own log rows. `previewRecord` is
deliberately not `cacheable`: a cached route could outlive an edit to the record or the matrix.

The quick action stays headless and opens the modal itself as a `LightningModal`
(`amfSubmitPreview`); the org refuses to change an existing LWC action's type to a screen action.
Only a routable preview opens the modal. A `Blocked_No_Match` or `Failed` preview has nothing to
confirm, so the action submits it directly — the submission, not the preview, writes the row
§6.1 step 6 requires. Submit re-runs the engine, and if the route it takes differs from the one
previewed, the user is told so rather than shown the preview's answer.

**M14 implementation (2026-10-23): the what-if.** `previewWith(recordId, changes)` is `preview()` for
one record, with some field values replaced on the in-memory copy that step 4 read, before step 5
evaluates any rule. Rule order, compilation and the first-match walk stay the engine's own, so a
what-if cannot drift from the route a submission would take. Nothing is written: not the record, not
a row, not the guard. Only fields of the record itself may be changed, because replacing a
relationship path would answer a question about a different parent. The fields are checked after the
record is authorised, so a caller who cannot read it is told that first, as by `preview()`. A
private overload of `prepare()` carries the changes; `submit()`, `preview()` and `submitEach()` pass
none and run exactly as before.

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
| Agentforce | The Approval Matrix Assistant, an employee agent (M13): find → preview → confirm → submit, and explain |

**M10 implementation (2026-10-08).** The Flow, Apex and Integration rows are built over
`submitEach()` (§6.1):

- **Flow:** the **Submit for Matrix Approval** action, `AMF_SubmitForMatrixApproval`. It returns
  one result per request, in order: record Id, submitted, outcome (`Submitted`,
  `Blocked_No_Match`, `Failed` or `Refused`), message, matched rule and version, selected process,
  decision log row Id and approval instance Id.
- **Integration:** `POST /services/apexrest/approval-matrix/v1/submissions` with
  `{"recordIds": [...]}`, at most 200, answers `{"results": [...]}`: the same results, one per Id, in
  order. A missing, malformed, empty or oversized body is a 400 with a message, before anything is
  read or written; any other fault is a 500 and rolls the call back.
- **Apex:** `new AMF_ApprovalMatrixService().submitEach(recordIds)`.

`TODAY` is the running user's date for every entry point (`docs/decisions.md`), and each row records
the date it used, so an integration user should carry the business's time zone. Both permission
sets grant both classes; authorisation is still checked per record.

**M13 implementation (2026-10-23): the Approval Matrix Assistant.** An Agentforce employee agent,
written in Agent Script (`agentforce/main/default/aiAuthoringBundles/AMF_Approval_Assistant`), is a
fifth way in. It runs as the user, so every action runs under that user's access. Its four actions
are invocable classes over the paths the other entry points already use:

- **Find Governed Record** (`AMF_AgentFindRecord`) turns what a user calls a record (a number, a
  name, an Id) into its Id. It searches only the governed objects, which it learns from the rules
  (§3.2), in user mode: an Id, then an exact name, then the search index, then a contains-match.
  Several matches are listed for the user to choose from.
- **Preview Approval Route** (`AMF_AgentPreviewRoute`) is §6.4's `preview()` for one record. Its
  outcome renames the engine's `Submitted` to `Routable`, because nothing has been submitted, and
  its summary is a deterministic sentence the agent repeats rather than composes.
- **Submit Previewed Route** (`AMF_AgentSubmitRoute`) submits through
  `AMF_SubmitForMatrixApproval.submitEach`, M10's per-record path, so it writes exactly the row a
  Flow would. The script offers it only after a preview that reached a decision, and binds its record
  and expected process to what was previewed: the model fills in neither. The platform asks the user
  to confirm before it runs. Route Changed compares the process taken with the one previewed, in
  Apex, as M5's warning toast does in the UI.
- **Explain Approval Decision** (`AMF_AgentExplainDecision`) is §8's M13 explanation of the
  record's newest attempt, with the user's question passed on.

The agent never works out a route, a rule or an approver; it states what its actions return. A
blocked or failed preview may still be submitted, as the header button submits one (M5), so that
the attempt is recorded, but only once the user has been told that and still wants it.

**M14 implementation (2026-10-23): the assistant for submitters and approvers.** Four more actions,
each read-only, each answering in deterministic sentences built in Apex:

- **What-If Approval Route** (`AMF_AgentWhatIfRoute`) runs §6.4's `preview()` and `previewWith()`
  for one record and compares the two. Fields are named by label or API name, and values as a person
  writes them: `Amount = 120k; Region = apac`. A picklist value must be one of the field's own. A
  field no active rule reads is accepted, and the answer says it cannot change the route. A what-if
  clears the script's `can_submit`, so a submission afterwards starts from a fresh preview of the
  record's real values, never from the values tried.
- **My Approval Requests** (`AMF_AgentMyRequests`) lists the user's own decision log rows of the
  last 90 days, read in user mode: the newest attempt per readable record, joined to its approval,
  those still waiting first.
- **My Pending Approvals** (`AMF_AgentMyApprovals`) lists the pending work items on governed
  records that `AMF_ApproverScope` says are the user's (§8's M14 note), oldest first, on records the
  user can read.
- **Brief Approver** (`AMF_AgentBriefApproval`) is §8's explanation, written for the approver the
  approval is waiting on and asked their question. It never recommends a decision.

In the script, a briefing belongs to the explain subagent, because it is an explanation written for
the approver; a `my_work` subagent holds the two lists, and briefs only an approval from a list it has
just given. The published agent chooses a subagent largely by the subagents' descriptions, so each
description says what it is not for ("would go" against "already went"), and the router never asks
which record is meant: the subagents can see the record on screen (technical log M14).

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

**M7 implementation (2026-10-08).** `amfDecisionTimeline` sits on the governed record's
Lightning page and reads `AMF_DecisionTimelineService.getTimeline`. It is **Classic only**, like
§9's validator.

- **One entry per submission attempt, newest first.** Each decision log row becomes an entry.
  A `Submitted` row is joined through `Execution_Ref_Id__c` to its `ProcessInstance`, and the
  entry then shows that instance's native steps (`StepsAndWorkitems`) in the order they
  happened: the submission, each decision, then the approver it is now with. A
  `Blocked_No_Match` or `Failed` row has no native half, because it never entered a process.
- **Two visibility rules, each one the platform already applies.** Log rows are read
  `WITH USER_MODE`, so the timeline shows exactly the rows the viewer could open anyway: their
  own as an `Approval_Matrix_User`, every row as an admin with View All (§11). Native history
  is shown to anyone who can read the record, checked against `UserRecordAccess` first. That
  is the rule the Approval History related list already follows. An approver therefore sees
  every approval on a record they can read, but sees the routing reason only where they can
  read the log row. An approval without a readable row is shown and labelled as such, rather
  than hidden or explained by guesswork.
- **Only what was recorded.** The "why" comes from the row's snapshots: rule DeveloperName,
  version, expression, evaluated values and selected process. It never comes from the live
  matrix, because joining today's rule would let a later edit rewrite the explanation of an
  earlier decision, which is the flaw this section exists to fix. The narrative therefore
  names a rule by its DeveloperName, not by its current description. Values read are shown
  under their current field labels, which is presentation only: the recorded path is each
  value's tooltip and appears verbatim in the condition. A path that no longer resolves is
  shown as recorded, because a deleted field must not hide the audit trail.
- **Bounded.** The 50 most recent entries. The two related lists hold everything.
- **Current.** `getTimeline` is not cacheable, for §6.4's reason. The component reads on
  load, when the record page refreshes (`lightning/refresh`, which the submit action now
  raises after every submission attempt), and from its own refresh button.

`AMF_ApprovalHistoryProvider` isolates the `ProcessInstance` read, as
`AMF_ApprovalProcessProvider` does for §9, because a `ProcessInstance` can only exist after a
real `Approval.process()`. The service's tests use an in-memory history, and the Classic
provider is tested once against a real submission.

**M13 implementation (2026-10-23): decisions in plain English.** A timeline entry with a decision
opens its details with an **Explain in plain English** button (`amfDecisionExplanation`).
`AMF_DecisionExplainer` writes the entry out as plain-text facts: the row's own snapshot (rule,
version, condition, values read under their field labels, process, outcome, recorded reason) and the
native steps the timeline shows with it. The `AMF_Explain_Approval_Decision` prompt template then
has Einstein explain them, answering the reader's question when there is one; the assistant (§7)
passes the user's.

- **Only what the reader can see.** The facts come from `AMF_DecisionTimelineService`'s view,
  which has already applied both of this section's visibility rules. A routing reason the reader
  cannot see is said to be not visible, never guessed.
- **Only what was recorded.** No live rule is read, for the reason this section exists. The
  template is told that only the deciding rule is recorded, to say nothing about other rules, to
  treat the facts as data, and to keep every name exactly as written.
- **Presentation, never record.** An explanation is generated on demand, labelled AI-generated,
  names the row it was written from, and is stored nowhere. It sits above the recorded facts it
  explains, which stay on screen. When the approval moves on, the component puts it away rather
  than leave it describing a state that has passed.
- **Not cached**, for §6.4's reason. A failure says why (Einstein unavailable, the template
  missing, the reader without the Prompt Template User permission set), and the decision itself is
  untouched.

`AMF_ExplanationGenerator` is the seam. Production runs the template through
`ConnectApi.EinsteinLLM`; tests inject a stub, because a generation is neither deterministic nor
available in an Apex test.

**M14 implementation (2026-10-23): the current approver sees why.** M7's visibility rules left an
approver seeing every approval on a record they can read, but the routing reason only where they
could read the row, which for an `Approval_Matrix_User` meant never for someone else's submission.
The timeline adds one rule: a pending approval that no readable row explains, and that is waiting on
the reader, has its own row read for them without sharing and flagged `visibleAsApprover`.

- **Waiting on the reader** is `AMF_ApproverScope`'s answer, which every M14 surface shares: a
  pending step assigned to the reader, to a queue or public group that contains them (nested groups
  followed to depth 5), or to a user who names them delegated approver. Membership through a role is
  not followed; the framework's templates name users, queues and groups (§5.2).
- **Only that row, only while it waits.** The reader is the person deciding. Once the approval moves
  on, the rule no longer applies and the row is hidden from them again. No other row is affected, and
  no record is shared.
- **Everything built on the timeline inherits it:** the Explain button, the assistant's explanations
  and M14's briefing, which `AMF_DecisionExplainer.briefLatest()` writes from the same facts plus one
  line naming the reader as the approver it waits on.
- **A reassigned step is described by whom it went to.** A `Reassigned` history row's actor is the new
  assignee and its original actor the step's first one; who made the change is not recorded. The
  facts therefore say "reassigned to X (first assigned to Y)". M13's "reassigned by X, for Y" read to
  the model as X handing the step to Y, the wrong way round (technical log M14).


Runs as a required release gate and is also exposed as an invocable for post-deploy pipeline checks. The gate fails when:

- Any active expression fails to compile (message includes character position)
- A `Classic` rule's `Process_API_Name__c` has no **active** `ProcessDefinition` of type Approval for that object
- A `Flow` rule's `Process_API_Name__c` has no **active** flow of `processType` `ApprovalWorkflow` — active, not merely present, because Draft orchestrations deploy clean (§5.3)
- Two active rules share the same object and priority
- A governed object lacks `Matrix_Submission__c`
- A Classic template's entry criteria omit the guard

**M4 implementation (2026-09-18).** A Salesforce metadata deploy cannot invoke Apex, so
"at deploy time" means a required two-part release gate rather than a hidden deploy hook:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-approval-matrix-source.ps1
sf project deploy start -o amf-dev
sf apex run --file scripts/validate-config.apex -o amf-dev
```

The source gate validates every active rule's referenced Classic template is present and active
in the repository and that its only entry criterion is `Matrix_Submission__c = TRUE`.
`AMF_ConfigValidator` validates the deployed org: all active expressions compile, priorities
are unique per object, every governed object has a Checkbox guard, and every named Classic
template is an active `ProcessDefinition` for the same object. It is also exposed as the
**Validate Approval Matrix Configuration** invocable action for an admin-owned post-deploy
Flow. The invocable returns all findings and can be configured to throw when any are present.

`ProcessDefinition` does not expose entry criteria to Apex SOQL, which is why the guard check
is deliberately source-based rather than an unreliable Apex inference. The current M4
implementation is Classic-only; the Flow-template checks above join it when Flow execution and
`Execution_Type__c` are introduced.

**M11 implementation (2026-10-21): two more checks.**

- **The source gate** fails a governed object's layout that keeps the standard Submit for Approval
  button, and a governed object with no layout in source (§6.3).
- **`AMF_ConfigValidator`** runs each governed object's union query (§4.4), exactly as
  `AMF_FieldPathResolver` builds it for the engine, against no records. It runs only when every
  rule for the object compiles, as the engine does. A query the platform refuses is reported as
  `UNION_QUERY_INVALID` with the platform's reason. This replaces counting relationships against
  SOQL's documented limit, which `amf-dev` does not enforce.

**M12 implementation (2026-10-22): the template lifecycle, and portability.** The source gate
reads every package directory `sfdx-project.json` lists. It adds:

- guard checks on every active template, not only on those a rule names, because an active
  template the matrix does not use can still be entered;
- §5.1's lifecycle, against `config/template-releases.json`;
- no literal username in a template, and a `sfdx-project.json` replacement that fills the
  placeholder (§11);
- no layout or object settings of a standard object in the framework package (§6.3).

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
- **Deployment requirement:** approvers must have read access to the governed record through
  role hierarchy, a sharing rule, or Apex sharing. Assigning a Classic approval work item does
  not create a record share; the framework intentionally does not alter an adopting org's
  sharing model.
- **Approvers must also hold a license that includes the governed object** (M11, 2026-10-21). The
  platform assigned an Opportunity approval to a Salesforce Platform user, whose license grants no
  Opportunity access, without complaint. It checks neither sharing nor license when it resolves
  an approver. That is why the Opportunity templates follow the submitter's manager hierarchy:
  managers of sales users hold sales licenses.
- **Submitters need read access to the guard field.** The engine finds the guard through describe,
  and in a user's context describe leaves out a field the user has no FLS on (technical log M1.4d).
  The engine would then report the object as one it cannot govern. So both permission sets grant
  read on every governed object's guard (M11). Apex tests cannot show this, because `System.runAs`
  does not enforce field-level security.
- **Usernames are per org** (M12, 2026-10-22). A username is unique across all of Salesforce, so
  a template that names one deploys to one org. Templates write `<alias>@{{AMF_USERNAME_DOMAIN}}`,
  and a `sfdx-project.json` replacement fills the domain from the environment variable of that
  name at deploy. The CLI refuses a deploy without it. Queues, groups and roles are named by
  DeveloperName and travel unchanged.
- **The AI features run as the user** (M13, 2026-10-23). The assistant is an employee agent, and the
  explanation's template call runs in the reader's context, so both see exactly what the user could
  open. A prompt carries only the timeline's view of one decision, and passes through Einstein's
  Trust Layer like any prompt in the org. Nothing generated is stored. Besides `Approval_Matrix_User`,
  a user needs the Prompt Template User permission set (`EinsteinGPTPromptTemplateUser`) for
  explanations, Access Agentforce Default Agent (`CopilotSalesforceUser`) for the Agentforce panel,
  and `AMF_Approval_Assistant_Access` for the agent itself.
- **The current approver may read one row their sharing hides** (M14, 2026-10-23): the decision log
  row of a pending approval waiting on them, directly, through a queue or group, or as delegated
  approver (§8's M14 note). It is read without sharing, bound to that approval, and only while it
  waits. This supersedes the 2026-10-08 decision for that case alone; the log's Private sharing model
  and both permission sets are unchanged.

---

## 12. Known Constraints and Open Questions

1. **Unanimous group approval on Flow steps is unresolved** (Appendix A, Q3). Any-member is **confirmed** for groups and queues: one shared work item, and the first decision completes the step. Summer '26's "Require unanimous approval" exists, but the value its metadata field `requiresMultiMemberApproval` takes is unknown, and every value tried was silently dropped. §5.4's committee guidance depends on it. Highest-priority open item; it needs one change made in Flow Builder.
2. ~~**The Flow launch call is inferred, not executed**~~ — **confirmed** in Round 2: `Flow.Interview…start()`, with the submission created synchronously (§5.3).
3. **Flow templates cost more than one flow each** — orchestration plus a companion screen flow per approval step.
4. **Retiring a shape** means editing every rule that references it; there is no template registry. The validator makes stale references a deployment failure. If an org ever has dozens of rules sharing shapes, a registry reintroduces additively with no engine change.
5. **Classic remains fully supported** and Flow Approval Processes consume no automation credits. The dual-strategy design is the hedge: rules migrate `Classic` → `Flow` one row at a time with zero engine change.
6. **Apex API 67.0 runs database operations in user mode by default** (Summer '26). The engine's system-mode operations — guard staging, decision-log writes, field reads beyond the submitter's access (§11) — depend on its classes staying at API ≤ 66, or on stating system mode explicitly. Flow templates need a newer *Metadata* API version (`sourceApiVersion`) to deploy; raising it must not raise class versions.
7. **A Flow approval does not stop on rejection** and **cancel does not run the recall path** (§5.3). Templates gate every later level; the guard needs a reset path for cancelled submissions, or cancel is withheld operationally.
8. **Flow approvals are invisible to Classic surfaces:** no `ProcessInstance`, so the Approval History related list and `ProcessInstance` reports show nothing. Approval Trace or the timeline (§8) replaces them.
9. **The AI features need Einstein generative AI and Agentforce turned on** (M13). Their metadata, the prompt template and the agent's authoring bundle, deploys only to an org that has them, so it lives in its own package directory, `agentforce/`, and `force-app` still deploys to any org. Without the template, the timeline's Explain button says that explanations are not available. Agent Script needs Metadata API 66 or later: `sourceApiVersion` is 66.0, and Apex classes stay at 62.0 (item 6).

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

**Delivered in M9 (2026-10-08)**, additively as required: every deferred item above, plus the word
forms `AND` / `OR` / `NOT`, which the MVP had also withheld. §4.1 and §4.3 carry the M9 notes.
DateTime remains unsupported.

### 13.4 Phases

| Phase | Content | Gate |
|---|---|---|
| **M0** | Scaffold, org connectivity, `Purchase_Request__c`, guard field, seed users with manager chain | Deploy + seed green |
| **M1** | Single CMDT, decision log, three sample rules, SOQL-based provider | Long-expression (>255 char) test passes |
| **M2** | Evaluator, reduced grammar, table-driven + malformed-input suites | ≥90% coverage, zero org dependence |
| **M3** | Engine, Classic strategy, two templates, log write, submit action | **Manual QA:** change a rule's process in CMDT, redeploy, watch routing change with no code touched |
| **M4** | Post-MVP configuration validator and source guard gate | Source gate, deployed-org validator and all Apex tests green |
| **M5** | Post-MVP §6.4 preview and the submit action's confirmation modal | Preview writes nothing (proved in tests and against the org), all Apex and Jest tests green, modal opens from the real action |
| **M6** | Post-MVP Flow approvals technical spike — research only, artefacts under `spikes/` | Round 1's open questions answered or explicitly still open, every claim labelled, product untouched (all Apex tests green) |
| **M7** | Post-MVP §8 decision timeline LWC, Classic only, on the governed record's page | All Apex and Jest tests green; in the real UI the timeline explains a submitted, a blocked and a pending record, and shows a new submission without a page reload |
| **M8** | Post-MVP guard integrity: recall clears the guard (§5.2); a record already in approval is refused (§6.1) | Source gate fails a template that does not clear the guard on approval, rejection and recall; all Apex and Jest tests green; in the real UI a recall unticks `Matrix_Submission__c`, and submitting a pending record is refused by name with no log row |
| **M9** | Post-MVP full §4.1 grammar: `NOT`/`!`, word forms, `IN`/`NOT IN`, `CONTAINS`, `STARTS_WITH`, multipicklist, `TODAY(±n)`, paths to three hops | Every evaluator class at ≥ 95% with zero org-data dependence; each construct in the table-driven and malformed-input suites; the shipped matrix still validates; all Apex and Jest tests green |
| **M10** | Post-MVP §7 entry points: Flow invocable and REST over a per-record engine entry; chunked, isolated submission; the log written after the platform answers | All Apex and Jest tests green, including a real 200-record submission and a real per-record platform refusal; the invocable answers through the platform's invocable framework and the REST endpoint answers a real call |
| **M11** | Post-MVP second governed object, Opportunity, by configuration and conventions alone (§3.2): guard, two manager-hierarchy templates, the button removed from four layouts, rules, a log lookup, the timeline page; the source gate enforces §6.3 and the validator runs each object's union query | Source gate and validator green across both objects and shown to fail broken copies; all Apex and Jest tests green; the UI API shows the framework's action and no standard button; an Opportunity routes, approves and recalls end to end in the org |
| **M12** | Post-MVP §5.1 template lifecycle enforced by a release manifest; Classic queue and committee templates with a rule each; the source portable (usernames by placeholder, the org's own configuration in its own package directory); New and Mass Change Owner off the decision-log related list | Source gate green and shown to fail broken copies, and a correct `_v2` passes; `force-app` converts with another org's domain and holds no `amf-dev` value; the org's templates match the manifest; all Apex and Jest tests green; queue and committee requests route, decide and recall end to end in the org |
| **M13** | Post-MVP AI around the engine (§1 principle 6): the Approval Matrix Assistant, an Agentforce employee agent that finds, previews, submits after confirmation and explains, through the engine's own paths (§7); plain-English explanations of recorded decisions on the timeline (§8) | All Apex and Jest tests green; the agent's script compiles; in the org the template explains a real decision, and the agent previews, submits a throwaway record only after confirmation, and explains it; the agent's test suite passes |
| **M14** | Post-MVP assistant for submitters and approvers (§1 principle 6): a what-if over a new write-nothing engine entry, `previewWith()` (§6.4); the user's own requests; what is waiting for them; a briefing for the current approver; and the current approver's sight of the routing reason (§8, §11) | All Apex and Jest tests green; the agent's script compiles; in the org a what-if writes nothing, the user's requests are listed, and a throwaway reassigned to the user is listed as waiting and briefed; the agent's test suite passes |

### 13.5 Repository state

Commit `a69e3c9` contains Phase 0 and Phase 1 built to the **v1.0** design: four Custom Metadata types, chain objects, permission sets, 14 CMDT records, list views. None of it matches this document.

**Reusable:** `sfdx-project.json`, `AMF_Ping`, `scripts/seed-data.apex`, `Purchase_Request__c`.
**Retired:** all four v1 CMDT types, both chain objects, v1 permission sets and list views.

~~Because the v1 metadata is also deployed to `amf-dev`, a fresh Developer Edition org is faster than destructive deploys against Custom Metadata types.~~ **Superseded by events.** The destructive deletes succeeded against `amf-dev` at `71fd786` and in M0, so the MVP builds there and keeps Phase 0's seeded users, queue and group. The one thing that genuinely resisted deletion was `Approval_Chain__c`, held by a soft-deleted `Purchase_Request__c.Active_Chain_del__c` in the recycle bin — a relationship the Metadata API cannot address, cleared by a manual Setup erase rather than a new org.

---

## Appendix A — Spike Findings (Round 1 2026-08-14, API 62.0 · Round 2 2026-10-07, API 67.0 · `amf-dev`)

Full detail, evidence and the Classic → Flow migration checklist in `docs/spike-results.md`. Confidence labels are load-bearing.

| # | Question | Status |
|---|---|---|
| Q1 | Flow template contract | **CONFIRMED, changed at API 67:** `processType ApprovalWorkflow`; **four** String inputs (`recordId`, `submitter`, `submissionComments`, `firstApprover`); `runInMode SystemModeWithoutSharing`; `stepApproval` / `stepBackground`; companion screen flow per approval step; Draft deploys unvalidated |
| Q1 | Apex launch call for an orchestration | **CONFIRMED** — `Flow.Interview.createInterview(...).start()`; `ApprovalSubmission` and first `ApprovalWorkItem` created synchronously; works for a non-admin submitter and inside Apex tests |
| Q2 | Timeline join: `ApprovalSubmission` / `ApprovalWorkItem`; `ReviewedById` is the true approver | **CONFIRMED** — plus: `ApprovalConditionName` is the step label; Flow approvals create no `ProcessInstance` |
| Q3 | Group / queue step semantics | **Any-member CONFIRMED** (one shared item, first decision completes) · **Unanimous OPEN** — `requiresMultiMemberApproval` value unknown; wrong values dropped silently |
| Q4 | Recall / cancel / reassign / review from Apex | **CONFIRMED executed** — recall runs the `ApprovalRecall` path; cancel does not |
| new | Does rejection stop later stages? | **CONFIRMED: no** — gate on `<Step>.Outputs.approvalDecision`; an `outputParameters` mapping stays null |
| new | Record locking | **CONFIRMED** — opt-in per step (`shouldLock`), synchronous, released on completion |
| new | Approver format | **CONFIRMED** — usernames, literal or via `Resource`; literal assignees block packaging |
| new | Apex API 67.0 user mode by default | **CONFIRMED** — §12 item 6 |

Round 1's artefact `AMF_Spike_Approval` was deleted in M0. Round 2's artefacts are source under `spikes/flow-approvals/` (outside `force-app`); the flows and groups stay in `amf-dev` until the unanimous check, and `spikes/flow-approvals/scripts/teardown.ps1` removes them.

---

## Appendix B — Superseded Designs (do not build)

The v1.0 design resolved approver chains rather than selecting templates. Everything below was deleted when the architecture changed, and represents roughly 60% of the original build. Code for some of it exists at commit `a69e3c9`.

| Abandoned | Replaced by |
|---|---|
| Chained single-step approval process + Chain Advancer flow | Templates are real multi-step processes; depth lives in the template |
| `Approval.unlock()` re-submit cycling | One submission per record |
| `Approver_1..N__c` / `Current_Approver__c` staging fields | No field-based approver injection |
| `AMF_ApproverResolver` (user/queue/group/manager expansion) | Approvers are configured inside the template |
| Group Work Item pattern, service user, Approval Inbox LWC | Native group work items on Flow templates (any-member confirmed; unanimous pending, Q3) |
| `Approval_Chain__c` / `Approval_Chain_Step__c` state machine | Native `ProcessInstance` / `ApprovalSubmission` + decision log |
| Four CMDT types incl. numbered conditions and route steps | One CMDT type with a single expression string |
| SLA escalation batch | Template-level time-dependent actions |
| Template registry CMDT | Direct `Process_API_Name__c` + validator existence checks |

The corresponding entries in `docs/decisions.md` dated 2026-08-12 are historical context for `a69e3c9`, not current design. Four of those decisions survive and are incorporated above: `Matched_Rule__c` as Text (§3.3), `Record_Id__c` non-unique external id (§3.3), custom permission rather than profile for the immutability bypass (§3.3), and Modify All withheld from the admin permission set (§3.3).
