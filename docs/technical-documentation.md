# Approval Matrix Framework — Technical Documentation

| | |
|---|---|
| **Describes** | The framework as built through phase M16.7: `develop` at commit `b3f0703`, 24 October 2026 |
| **Written for** | Salesforce developers, solution architects, technical administrators and release engineers |
| **Companion documents** | [Functional documentation](functional-documentation.md) · [User guide](user-guide.md) · [Claude connector guide](claude-connector.md) |
| **Design records** | [Architecture v3.0](architecture.md), the target design and its reasoning, section by section · [Decisions](decisions.md), every approved deviation · [Technical log](technical-log.md), each phase's changes and evidence · [Build playbook](build-playbook.md), each phase's gate |

This document describes the system **as built**. `docs/architecture.md` is the target design. Where
the two differ, the architecture describes something not yet built, and this document is the record
of what exists. Section numbers written `§n` refer to the architecture document, which every Apex
class's header also cites.

## Contents

1. [Overview](#1-overview)
2. [Solution architecture](#2-solution-architecture)
3. [Data model](#3-data-model)
4. [Expression language and evaluator](#4-expression-language-and-evaluator)
5. [The engine](#5-the-engine)
6. [Submission strategy](#6-submission-strategy)
7. [Decision log writer](#7-decision-log-writer)
8. [Approval templates](#8-approval-templates)
9. [Release gate](#9-release-gate)
10. [Entry points](#10-entry-points)
11. [Decision timeline](#11-decision-timeline)
12. [AI layer](#12-ai-layer)
13. [Claude connector (MCP)](#13-claude-connector-mcp)
14. [Security model](#14-security-model)
15. [Testing](#15-testing)
16. [Build, deployment and environments](#16-build-deployment-and-environments)
17. [Extending the framework](#17-extending-the-framework)
18. [Operations and troubleshooting](#18-operations-and-troubleshooting)
19. [Known limitations and technical debt](#19-known-limitations-and-technical-debt)
20. [Conventions](#20-conventions)
- [Appendix A: Class reference](#appendix-a-class-reference)
- [Appendix B: Phase history](#appendix-b-phase-history)
- [Appendix C: Repository map](#appendix-c-repository-map)

---

## 1. Overview

### 1.1 What the framework is

An **approval-process selection engine** for Salesforce:

1. Prioritised rules held in a Custom Metadata type are matched against a record by an expression
   evaluator.
2. The winning rule names a **template**: a real, pre-built Classic approval process.
3. The engine submits the record into that template, and writes an immutable decision log row
   explaining why.

Salesforce then executes everything else natively: steps, approvers, queues, locking, notifications
and history. The framework decides *which process*, and records *why*.

### 1.2 Technology stack

| Area | Technology | Version |
|---|---|---|
| Platform | Salesforce. Developed against a Developer Edition org, alias `amf-dev` | Org at API 68.0 |
| Project | Salesforce DX, four package directories | `sourceApiVersion` 66.0 |
| Server logic | Apex: 68 classes plus 56 test classes | Every class at API 62.0 |
| User interface | Lightning Web Components: 6 bundles | API 62.0 |
| Configuration | One Custom Metadata type, Classic approval processes, workflow field updates, a validation rule, two custom permissions | |
| AI | Agentforce employee agents written in Agent Script; Prompt Builder Flex templates run through Einstein | Metadata API 66.0 |
| Claude | Salesforce Hosted MCP Servers; an External Client App | Server definitions deployed at Metadata API 67.0 |
| Tooling | sf CLI; PowerShell scripts; Jest (`@salesforce/sfdx-lwc-jest`) on the CLI's bundled Node | |

### 1.3 Design principles and their technical consequences

| Principle (§1) | What it means in the code |
|---|---|
| Configuration over code | Rules live in `Approval_Matrix_Rule__mdt`. No Apex class names a process, an approver or a threshold |
| Select, don't resolve | The engine stops at `Approval.process()`. It contains no approver logic, no chain advancement and no lock management |
| Explain every decision | An `Approval_Decision_Log__c` row is written for every decided attempt. It carries snapshots, not references, and a validation rule makes it immutable |
| Fail loudly | Nothing in the evaluator package catches an exception and returns false. Compile errors carry a character position. A per-record failure is recorded as a `Failed` row; a whole-call fault throws |
| Testable and portable | Every platform boundary sits behind an interface (section 2.4). Tests use in-memory rules. `force-app` deploys to any org, with approver usernames filled in at deploy |
| AI assists, never decides | AI features call the engine's own entry points. The sentences they repeat are built deterministically in Apex. Generated text is never stored. Agent Script binds sensitive inputs at runtime, so the model never fills them in |

---

## 2. Solution architecture

### 2.1 Component view

```
ENTRY POINTS
  Quick action (LWC)              Flow action                    REST resource                  Apex
  amfSubmitForApproval            AMF_SubmitForMatrixApproval    AMF_MatrixSubmissionResource   new AMF_ApprovalMatrixService()
   └─ amfSubmitPreview (modal)            │ submitEach()                 │ submitEach()
         │ previewRecord / submitRecord   │                              │
         ▼                                ▼                              ▼
┌─────────────────────────── AMF_ApprovalMatrixService  (without sharing) ───────────────────────────┐
│ prepare():  authorise ─ refuse pending ─ load rules ─ sort ─ compile ─ one query ─ first match      │
│ execute():  stage guard ─ submit ─ write the decision log                                          │
│                                                                                                     │
│   AMF_RuleProvider ◄── AMF_CmdtRuleProvider (SOQL)  |  AMF_DraftRuleProvider  |  AMF_RuleBuilder.Stub│
│   AMF_ExprCache ──► AMF_ExprCompiler ──► AMF_Parser ──► AMF_Lexer          (AST: AMF_Ast)           │
│   AMF_FieldPathResolver  ── one dynamic SOQL per object                                             │
│   AMF_Evaluator          ── compiled expression + record ─► matched? + values read                 │
│   AMF_DecisionLogWriter                                                                             │
│   AMF_SubmissionStrategy ◄── AMF_ClassicProcessStrategy (Approval.process, 100 per call) | Stub     │
└─────────────────────────────────────────────────────────────────────────────────────────────────────┘
         │                                              │
         ▼                                              ▼
  Classic approval process ("template")        Approval_Decision_Log__c ── Execution_Ref_Id__c ──► ProcessInstance
  entry criteria: Matrix_Submission__c = TRUE
  final approval, rejection, recall: AMF_Clear_Matrix_Submission

READ SIDE
  amfDecisionTimeline ──► AMF_DecisionTimelineService ──► decision log (WITH USER_MODE)
                                 │                    └──► AMF_ClassicApprovalHistoryProvider (ProcessInstance)
                                 └─ AMF_ApproverScope (who the current approver is)
  amfDecisionExplanation ──► AMF_DecisionExplainer ──► AMF_ExplanationGenerator
                                                          ◄── AMF_EinsteinExplanationGenerator | AMF_McpFactsOnly

AROUND THE ENGINE: AI AND CLAUDE
  Agentforce   AMF_Approval_Assistant ──────► AMF_Agent* actions ──► engine · explainer · timeline
               AMF_Matrix_Admin_Assistant ──► AMF_AgentDraftRule · AMF_AgentCheckImpact · AMF_AgentMatrixHealth
                                               └─► AMF_RuleDrafter · AMF_MatrixImpact · AMF_MatrixHealthService
  Claude (MCP) AMFApprovalMatrix, AMFApprovalMatrixAdmin ──► AMF_Mcp* global facades ──► the same actions and services

RELEASE GATE
  before deploy:  scripts/validate-approval-matrix-source.ps1
  after deploy:   scripts/validate-config.apex ──► AMF_ConfigValidator
```

### 2.2 Layers

| Layer | Classes | Responsibility |
|---|---|---|
| Rules | `AMF_RuleProvider`, `AMF_CmdtRuleProvider`, `AMF_RuleDefinition`, `AMF_DraftRuleProvider` | The only read of the matrix, and its in-memory form |
| Evaluator | `AMF_Lexer`, `AMF_Parser`, `AMF_Ast`, `AMF_ExprCompiler`, `AMF_ExprCache`, `AMF_Evaluator`, `AMF_FieldPathResolver`, `AMF_ExpressionException` | Expression text to a typed, schema-checked AST; evaluation against a record; the one field query |
| Engine | `AMF_ApprovalMatrixService` | Authorisation, rule order, first match, guard staging, submission, logging |
| Submission | `AMF_SubmissionStrategy`, `AMF_ClassicProcessStrategy`, `AMF_SubmitRequest`, `AMF_SubmitResult`, `AMF_SubmissionException` | The only call to `Approval.process()` |
| Audit | `AMF_DecisionLogWriter` | Builds and inserts decision log rows |
| Validation | `AMF_ConfigValidator`, `AMF_ApprovalProcessProvider`, `AMF_ClassicApprovalProcessProvider`, `AMF_ConfigurationException` | The post-deploy half of the release gate |
| Timeline | `AMF_DecisionTimelineService`, `AMF_ApprovalHistory`, `AMF_ApprovalHistoryProvider`, `AMF_ClassicApprovalHistoryProvider`, `AMF_ApproverScope` | The read side: decisions joined to native approval history, with visibility rules |
| Entry points | `AMF_SubmitForMatrixApproval` (Flow), `AMF_MatrixSubmissionResource` (REST) | Per-record bulk submission |
| Explanations | `AMF_DecisionExplainer`, `AMF_ExplanationGenerator`, `AMF_EinsteinExplanationGenerator`, `AMF_ExplanationException` | Plain-English explanations and briefings |
| Prompt seam | `AMF_PromptRunner`, `AMF_EinsteinPromptRunner`, `AMF_PromptException` | Running a prompt template for the drafter and the health report |
| Admin services | `AMF_RuleDrafter`, `AMF_MatrixImpact`, `AMF_MatrixHealthService` | Rule drafting with release checks; impact analysis; health counts |
| Agent actions | `AMF_Agent*` (12 classes, `AMF_AgentSupport` among them) | Invocable actions for the two Agentforce agents |
| Claude tools | `AMF_Mcp*` (14 classes, in `mcp/`) | `global` invocable facades for the Hosted MCP Servers |
| Test fixtures | `AMF_RuleBuilder`, `AMF_StrategyStub` | In-memory rules and a recording submission stub |

LWC bundles: `amfSubmitForApproval`, `amfSubmitPreview`, `amfDecisionTimeline`,
`amfDecisionTimelineEntry`, `amfDecisionExplanation` and `amfErrors`, a shared error helper.

### 2.3 Package directories

| Directory | Contents | Deploys to |
|---|---|---|
| `force-app` (default) | The framework: objects, fields, the rule type and its rows, templates, workflows, Apex, LWC, record pages, quick actions, tabs, list views, the two framework permission sets | Any org |
| `agentforce` | The two agents' authoring bundles (`aiAuthoringBundles`) and the three prompt templates (`genAiPromptTemplates`) | Only an org with Einstein generative AI and Agentforce turned on |
| `mcp` | The Claude connector: the `AMF_Mcp*` classes, the `AMF_Mcp_Settings__c` custom setting, the two connector permission sets, and the two MCP server definitions. The definitions are deployed only by the setup script (section 13.6) | An org with Salesforce Hosted MCP Servers: Enterprise Edition and above, or Developer Edition |
| `org-config/amf-dev` | `amf-dev`'s own configuration: Opportunity's four layouts, its object settings and the Matrix Opportunities list view; the two agent-access permission sets; the two Testing Center definitions; the External Client App `AMFClaudeConnector` | `amf-dev` only, after both agents have been published |

The default package directory is the framework, and the source gate enforces that it holds no layout
or object settings of a standard object (section 9.1).

### 2.4 Seams

Every boundary that a unit test cannot cross, or that might be replaced, is an interface.

| Interface | Boundary | Production implementation | Other implementations |
|---|---|---|---|
| `AMF_RuleProvider` | Reading the matrix (Custom Metadata cannot be inserted in a test) | `AMF_CmdtRuleProvider` | `AMF_DraftRuleProvider`: the live matrix with one change, for impact checks. `AMF_RuleBuilder.Stub`: tests |
| `AMF_SubmissionStrategy` | Starting an approval | `AMF_ClassicProcessStrategy` | `AMF_StrategyStub`: tests |
| `AMF_ApprovalProcessProvider` | The catalogue of active approval processes | `AMF_ClassicApprovalProcessProvider` | Test stubs |
| `AMF_ApprovalHistoryProvider` | Native approval history (a `ProcessInstance` needs a real approval) | `AMF_ClassicApprovalHistoryProvider` | In-memory history in tests |
| `AMF_ExplanationGenerator` | Facts into plain English | `AMF_EinsteinExplanationGenerator` | `AMF_McpFactsOnly`: returns the facts, for Claude. Test stubs |
| `AMF_PromptRunner` | Running a prompt template | `AMF_EinsteinPromptRunner` | `AMF_McpRuleContext.CapturingRunner` and `AMF_McpCheckRuleDraft.GivenAnswer`, for Claude. Test stubs |

Classes that use a seam have a production constructor that wires the default implementation, and an
injection constructor for tests. Classes with static entry points (the Flow action, the validator)
expose a `@TestVisible` override instead.

---

## 3. Data model

The framework adds three artefacts:
- one Custom Metadata type, the matrix;
- one custom object, the decision log;
- one Checkbox field on each governed object, the guard.

Purchase Request is its own pilot object.

### 3.1 `Approval_Matrix_Rule__mdt`: the matrix

Visibility `Public`. One row is one complete routing statement.

| Field | Type | Required | Purpose |
|---|---|---|---|
| `DeveloperName` | | Yes | The rule's identity. Half of the compile-cache key. Recorded on every decision it makes as `Matched_Rule__c` |
| `MasterLabel` | | Yes | Human label, such as `PR - High Value APAC` |
| `Object_API_Name__c` | Text(80) | Yes | The governed object. An object is governed exactly when it has active rules |
| `Priority__c` | Number(5,0) | Yes | Lower is tried first. Must be unique per object among active rules (the validator's check). Sorted in Apex, never in SOQL |
| `Expression__c` | Long Text Area(2000) | | The condition (section 4) |
| `Process_API_Name__c` | Text(80) | Yes | The Classic `ProcessDefinition` DeveloperName |
| `Description__c` | Text(255) | | Plain-language intent, shown in the preview |
| `Version__c` | Number(4,0) | Yes | Incremented on every change. The other half of the cache key; recorded on every decision |
| `Active__c` | Checkbox | Default false | Only active rules are returned by the provider |

> **Platform constraint, pinned by a test.** Apex `getAll()` and `getInstance()` truncate Long Text
> Area fields to 255 characters. `AMF_CmdtRuleProvider` therefore reads rules **by SOQL only**.
> Measured in `amf-dev` against the 290-character expression of the inactive fixture row
> `PR_Long_Expression_Pin`: SOQL returns 290 characters; `getInstance()` and `getAll()` both return
> 255, cut inside `(Risk_Level`. `AMF_CmdtRuleProviderTest` pins both halves. Custom Metadata SOQL
> consumes no query rows and no query count.

### 3.2 `Approval_Decision_Log__c`: the audit record

- **Object:** label *Approval Decision Log*. Auto-number name `ADL-{00000000}`, labelled *Decision
  Log Number*. Sharing model `Private`. Reports enabled; no field history, no feeds.

| Field | Type | Purpose |
|---|---|---|
| `Record_Id__c` | Text(18), External Id, **not unique** | The governed record. One record accumulates one row per attempt; rows are never deleted. The canonical, object-agnostic reference |
| `Object_API_Name__c` | Text(80) | The governed record's object |
| `Purchase_Request__c` | Lookup(Purchase Request), SetNull | Navigational link for the *Approval Decisions* related list. Found by describe (section 7) |
| `Opportunity__c` | Lookup(Opportunity), SetNull | The same, for Opportunity |
| `Matched_Rule__c` | Text(80) | The rule's DeveloperName. Text, because no relationship exists from a custom object to a Custom Metadata record |
| `Rule_Version__c` | Number(4,0) | The rule's `Version__c` at the moment it decided |
| `Expression_Snapshot__c` | Long Text(2000) | The expression exactly as evaluated, so it survives later edits to the rule |
| `Evaluated_Values__c` | Long Text(32,768) | JSON of the values read (section 3.6) |
| `Selected_Process__c` | Text(80) | The process the rule named |
| `Execution_Ref_Id__c` | Text(18) | The `ProcessInstance.Id` the submission produced. The join to native history, and a provenance stamp that must not be optimised away |
| `Outcome__c` | Picklist, restricted, no default | `Submitted`, `Blocked_No_Match` (label *Blocked - No Match*) or `Failed`. Deliberately without a default, so a blank is a visible bug |
| `Failure_Detail__c` | Long Text(4000) | Why a blocked or failed attempt did not route; truncated to 4,000 characters |
| `Submitted_By__c` | Lookup(User), SetNull | The running user |
| `Submitted_At__c` | DateTime | When the engine decided, stamped explicitly rather than read from `CreatedDate` |

**Immutability: the `Lock_Decision_Log` validation rule.**

```
AND(
  NOT(ISNEW()),
  NOT($Permission.AMF_Bypass_Log_Lock),
  OR(
    NOT(ISBLANK(PRIORVALUE(Execution_Ref_Id__c))),
    ISBLANK(Execution_Ref_Id__c),
    ISCHANGED(Record_Id__c), ISCHANGED(Object_API_Name__c), ISCHANGED(Matched_Rule__c),
    ISCHANGED(Rule_Version__c), ISCHANGED(Selected_Process__c), ISCHANGED(Outcome__c),
    ISCHANGED(Submitted_By__c), ISCHANGED(Submitted_At__c)
  )
)
```

- **What it allows:** one post-insert update, `Execution_Ref_Id__c` going from blank to populated
  with no other governed field changed. It was written for an earlier design that stamped the
  reference after insert. Since M10 the engine writes the reference on insert, so nothing performs
  that update any more (section 19).
- **The bypass:** the custom permission `AMF_Bypass_Log_Lock`, granted by `Approval_Matrix_Admin`,
  exempts its holder. It is a custom permission rather than a named profile, so that it survives
  deployment to another org.
- **Deletion:** no permission set grants Delete on the log. `Approval_Matrix_Admin` deliberately
  withholds Modify All, because the platform makes Modify All depend on Delete.
- **Known residual:** `ISCHANGED` does not support Long Text Area fields. In principle, the one
  permitted update could therefore also change the three long text fields.

**UI artefacts:**
- **Layout sections:** *The Decision*, *Why — the evidence*, *The Governed Record*, *Provenance*.
- **List view:** `All_Decisions`.
- **Tab:** an *Approval Decision Logs* tab.
- **Related list:** *Approval Decisions* on each governed record's layout, with New and Mass Change
  Owner excluded.

### 3.3 Governed objects

**`Purchase_Request__c`.** Label *Purchase Request*. Auto-number name `PR-{00000000}`, labelled
*Purchase Request Number*. Sharing model `Private`, which also makes it queue-assignable. Its View
action is overridden on desktop (`formFactor` Large) to the Lightning page
`Purchase_Request_Record_Page`.

| Field | Type | Notes |
|---|---|---|
| `Amount__c` | Currency(16,2) | |
| `Region__c` | Picklist, restricted | APAC, EMEA, AMER |
| `Risk_Level__c` | Picklist, restricted | Low, Medium, High |
| `Vendor_Type__c` | Picklist, restricted | New, Existing, Strategic |
| `Account__c` | Lookup(Account), SetNull | Relationship `Purchase_Requests`. Gives rules a relationship to traverse (`Account__r.…`) |
| `Request_Name__c` | Text(80) | A readable name for demos and list views (M12.8). No rule reads it |
| `Matrix_Submission__c` | Checkbox, default false | The guard |

Also on this object:
- **Workflow field update** `AMF_Clear_Matrix_Submission`: sets `Matrix_Submission__c` to false
  (Literal 0). Every Purchase Request template runs it on final approval, final rejection and recall.
- **Validation rule** `AMF_Test_Refuse_Guard`: *test fixture only*. It refuses setting the guard on
  a Strategic-vendor request, but only for a holder of the custom permission `AMF_Test_Refuse_Guard`.
  No permission set grants that permission, so the rule is inert for real users. Tests grant it at
  runtime to produce a real `FIELD_CUSTOM_VALIDATION_EXCEPTION`.
- **Quick action** `AMF_Submit_For_Approval`: a Lightning Web Component action
  (`amfSubmitForApproval`), labelled *Submit for Approval*.
- **List view** `All_Purchase_Requests`, and a tab.

**`Opportunity`** (M11). The framework adds:
- `Matrix_Submission__c` (Checkbox, default false);
- the workflow field update `AMF_Clear_Matrix_Submission`;
- the quick action `Opportunity.AMF_Submit_For_Approval`;
- the record page `Opportunity_Record_Page`, with the timeline.

Opportunity's four layouts, its object settings (which assign the record page) and the *Matrix
Opportunities* list view are `org-config/amf-dev`'s, because a standard object's layouts are the
org's own configuration.

### 3.4 `AMF_Mcp_Settings__c`

A hierarchy custom setting with `Protected` visibility, in the `mcp` package directory. Its one field,
`Preview_Key__c` (Text 64), holds a random 256-bit key, Base64-encoded, with which the Claude
connector signs preview tokens (section 13.3). `scripts/setup-mcp.apex` seeds the org default once;
replacing the key invalidates every preview not yet submitted.

### 3.5 Conventions that replace per-object configuration

There is no object-configuration metadata. Four conventions stand in for it:

| Convention | Rule |
|---|---|
| The guard | Always `Matrix_Submission__c`, a Checkbox, on every governed object. Not configurable |
| Governed | An object is governed exactly when it has at least one active rule. Deactivating them all is the kill switch |
| No match | Blocks and writes a `Blocked_No_Match` row. A default route is a visible catch-all rule: priority 9999, expression `TRUE` |
| The log's link | `AMF_DecisionLogWriter` finds the decision log's lookup to a governed object by describe: the custom reference fields that point at it, first by API name. A new governed object needs a lookup field, and no code change |

### 3.6 The `Evaluated_Values__c` format

A JSON object of canonical field path to the value read, serialised from the evaluator's map:

```json
{"Amount__c":150000.00,"Region__c":"APAC"}
```

- **For a match:** the winning rule's paths, in compile order. Every path it references is
  recorded, even when `&&` short-circuited before reading it.
- **For `Blocked_No_Match`:** the union of every value read across every rule tried.
- **For an evaluation failure:** whatever had been read by then.
- **When the expression uses `TODAY`:** the resolved date is recorded under the reserved key `TODAY`:
  `{"CloseDate":"2026-11-15","TODAY":"2026-10-24"}`.
- **Number scale:** numbers keep the scale they were read with. A Decimal read from the database
  serialises as `250000.00`; one set in Apex may serialise as `250000`. Compare values, not JSON
  text.

The preview returns the identical string as `Outcome.evaluatedValuesJson`, so what the modal shows is
byte for byte what the row would record.

---

## 4. Expression language and evaluator

### 4.1 Pipeline

```
Expression__c ─► AMF_Lexer ─► tokens ─► AMF_Parser ─► AST ─► AMF_ExprCompiler ─► CompiledExpression
                (positions)            (syntax only)          (schema and type       │ cached by AMF_ExprCache,
                                                               checks via describe)   │ key DeveloperName|Version
                                                                                      ▼
all rules' fieldPaths ─► AMF_FieldPathResolver.unionPaths ─► buildQuery ─► ONE SOQL ─► records
record + CompiledExpression ─► AMF_Evaluator.evaluate ─► Result { matched, evaluatedValues }
```

| Class | Responsibility |
|---|---|
| `AMF_Lexer` | Text to tokens, tracking each token's zero-based character position. Knows no grammar. The `KEYWORDS` table is the grammar's extension point |
| `AMF_Parser` | Recursive descent to an AST, one method per production. A pure syntax machine: it asks the schema nothing |
| `AMF_Ast` | Node types: `BinaryNode`, `UnaryNode`, `ComparisonNode`, `FieldNode`, `LiteralNode`, `ListNode`, `TodayNode`. Value types: `NUMERIC`, `TEXT`, `BOOLEAN_VALUE`, `DATE_VALUE`, `MULTI_SELECT` |
| `AMF_ExprCompiler` | Parse plus static analysis: resolves every path through describe, canonicalises it, enforces the depth cap and operator/type compatibility. Produces a `CompiledExpression`: object, source, root, `fieldPaths`, `describeByPath`, `usesToday` |
| `AMF_ExprCache` | Compiles each rule once per transaction. Failures are never cached |
| `AMF_FieldPathResolver` | The union of every path across an object's rules, as one dynamic SOQL query |
| `AMF_Evaluator` | AST and record to a verdict, plus the values read. No describe work, and no catch block |
| `AMF_ExpressionException` | The package's only error type, always carrying the position and, once known, the expression text |

### 4.2 Lexical structure

| Element | Rule |
|---|---|
| Whitespace | Space, tab, CR, LF |
| Identifier | A letter, then letters, digits or `_`. Field and relationship names are matched case-insensitively and canonicalised to their API spelling |
| Keywords | Case-insensitive and reserved: `TRUE FALSE NULL AND OR NOT IN CONTAINS STARTS_WITH TODAY` |
| Number | Digits, with an optional fraction: `100000`, `1250.50`. A `.` continues a number only when a digit follows it. No sign (a leading `-` is a unary minus in operand position), no exponent, no thousands separators |
| String | Single-quoted. `\'` is a quote and `\\` a backslash; any other backslash is literal |
| Date | `YYYY-MM-DD`, validated as a real calendar date, and not followed by an identifier character |
| Symbols | `&&` `\|\|` `!` `==` `!=` `>` `>=` `<` `<=` `(` `)` `.` `,` `-` `+` |

### 4.3 Grammar and precedence

```
expression := or_expr
or_expr    := and_expr ( ('||' | OR) and_expr )*
and_expr   := unary ( ('&&' | AND) unary )*
unary      := ('!' | NOT) unary | primary
primary    := '(' expression ')' | comparison | bool_atom
comparison := operand comp_op operand
            | operand [NOT] IN list
            | operand (CONTAINS | STARTS_WITH) operand
comp_op    := '==' | '!=' | '>' | '>=' | '<' | '<='
list       := '(' literal ( ',' literal )* ')'
operand    := literal | field_path
literal    := ['-'] NUMBER | 'STRING' | DATE | TRUE | FALSE | NULL | today
today      := TODAY [ '(' [ ['+' | '-'] NUMBER ] ')' ]
field_path := IDENT ( '.' IDENT )*
bool_atom  := TRUE | FALSE | boolean field_path
```

- **Precedence:** `NOT` binds tightest of the logical operators, then comparisons, then `AND`, then
  `OR`. `a || b && c` is `a || (b && c)`.
- **`NOT` takes a whole comparison:** `NOT a == b && c` is `(NOT (a == b)) && c`.
- **`NOT IN` is exactly `NOT (… IN …)`.** `IN` is `==` against any one value of a list of literals.
  A field path inside a list is refused.
- **`TODAY`:** `TODAY()` is accepted as `TODAY`. The offset is a whole number of days, at most
  36,500 either way.
- **Canonical spellings:** the parser emits each operator in one spelling (`&&`, `||`, `!`, `IN`,
  `NOT IN`, `CONTAINS`, `STARTS_WITH`), because Apex `switch on` a String is case-sensitive.
- **A bare operand** is the whole condition. It must be Boolean: `TRUE`, `FALSE` or a Checkbox path.
  This is what makes catch-all rules expressible.

### 4.4 Type system

**Supported field types** (`AMF_ExprCompiler.SUPPORTED_TYPES`):

| `Schema.DisplayType` | Value type |
|---|---|
| `CURRENCY`, `DOUBLE`, `INTEGER`, `LONG`, `PERCENT` | numeric |
| `STRING`, `PICKLIST`, `ID`, `REFERENCE` | text |
| `BOOLEAN` | boolean |
| `DATE` | date |
| `MULTIPICKLIST` | multi-select picklist |

Any other type (`DATETIME`, `TEXTAREA`, `EMAIL`, `PHONE`, `URL` and the rest) is a compile error:
"Field 'CreatedDate' on Purchase_Request__c is of type DATETIME, which the expression grammar does not
support at position 0".

**Literals:**
- `NUMBER` is numeric, `'STRING'` is text, a date or `TODAY` is a date, and `TRUE`/`FALSE` are boolean.
- `NULL` is typeless, and compares with every type through `==` and `!=`.

**Operator compatibility,** checked at compile time:

| Operator | Numeric | Date | Text | Boolean | Multi-select |
|---|---|---|---|---|---|
| `==`, `!=` | Yes | Yes | Yes, case-insensitive | Yes | Only against a `;`-separated text literal: an exact set match |
| `>`, `>=`, `<`, `<=` | Yes | Yes | No | No | No |
| `IN`, `NOT IN` | Yes | Yes | Yes | Yes | No |
| `CONTAINS` | No | No | Yes: a case-insensitive substring | No | Only against a `;`-separated text literal: every listed value selected |
| `STARTS_WITH` | No | No | Yes, case-insensitive | No | No |
| `NOT`, `!` | Its operand must be boolean | | | | |

Further rules:
- Both sides of a comparison must have the same value type. `NULL` matches any type.
- `NULL` is refused with `IN`, `NOT IN`, `CONTAINS` and `STARTS_WITH`, as the operand and as a list
  value. A blank is tested with `== NULL`.
- A multi-select literal must name at least one value.
- Picklist literals are *not* checked against the field's value set. A misspelt value is a
  configuration mistake that never matches, not a compile error.

### 4.5 Semantics

**Null rules**, for a null *leaf* value:

| Expression | Result |
|---|---|
| `null == null` | true |
| `null == value`, `value == null` | false |
| `null != null` | false |
| `null != value` | true |
| `null` with `>`, `>=`, `<`, `<=` | false, never an exception |
| `null IN (…)` | false, so `null NOT IN (…)` is true |
| `null CONTAINS` / `STARTS_WITH`, on either side | false |
| a bare Checkbox path that is null | false |

**Broken relationship paths are *unknown*.** If an intermediate step of a path is null (a Purchase
Request with no Account, read through `Account__r.Name`), the comparison is *unknown*, not false.
This includes `Account__r.Name == NULL` and `!= NULL`. The logical operators follow Kleene's
three-valued logic, as SQL does:

| | Result |
|---|---|
| `NOT unknown` | unknown |
| `unknown && false` | false |
| `unknown && true` | unknown |
| `unknown \|\| true` | true |
| `unknown \|\| false` | unknown |

A rule matches only when its whole expression is **definitely true**. So `NOT (Account__r.Name ==
NULL)` does not match a record with no Account, which would otherwise be a silent presence check. A
null *leaf* stays two-valued, under the null rules above.

**Further semantics:**
- **Text** comparisons (`==`, `!=`, `IN`, `CONTAINS`, `STARTS_WITH`) ignore case.
- **Numbers** are compared as `Decimal`. The project measured that Apex reports every boxed numeric
  as `instanceof Decimal`.
- **Multi-select values** are split on `;`, trimmed, stripped of blanks and lower-cased, then
  compared as sets.
- **`TODAY`** is `Date.today()` for the running user, which for a submission is the submitter's local
  date. It is fixed once per transaction, so every rule and record in a call agrees, and it is
  recorded under the `TODAY` key.
- **Short-circuiting.** `&&` and `||` stop as soon as the result is decided. This is safe because
  evaluation is total under the null rules, and the values map is built from the compiled path list,
  not from the nodes evaluation reached.
- **No catch blocks.** A record queried without a needed field, or a field deleted since deployment,
  throws out of the evaluator. The engine turns that into a `Failed` attempt (section 5.2).

### 4.6 Field paths

- **Depth:** at most four segments (`AMF_ExprCompiler.MAX_PATH_SEGMENTS`), meaning a field three
  relationships away, such as `Account__r.Owner.Profile.Name`. SOQL allows five relationship hops,
  so raising the constant is all a deeper path would need. `AMF_FieldPathResolver` enforces the same
  constant.
- **Relationships:** resolved by relationship name, case-insensitively, through a per-type map built
  once per transaction. Custom lookups traverse as `…__r`, and standard ones by their relationship
  name (`Account`, `Owner`).
- **Polymorphic relationships** are refused: "Relationship 'What' on Task is polymorphic and cannot
  be traversed".
- **Field-level security:** describe runs in the running user's context. As recorded in architecture
  §11 and technical log M1.4d, a field the user has no FLS on is not found, and compiling a rule over
  it fails with `Unknown field` **for that user**. Every field a rule reads, and every guard field,
  must therefore be readable by every user who submits (section 14.6).

### 4.7 Compile errors

Every error ends with `at position N`, a zero-based index into the expression. The validator prefixes
it with the rule: "Rule PR_X on Purchase_Request__c does not compile: …".

| Expression | Error |
|---|---|
| `Amount__c > 100,000` | Unexpected token ',' at position 15 |
| `Region__c = 'APAC'` | Unexpected character '=' at position 10 |
| `Region__c == "APAC"` | Unexpected character '"' at position 13 |
| `(Amount__c > 5` | Expected ')' but found end of expression at position 14 |
| `Amount > 5000` (on Purchase Request) | Unknown field 'Amount' on Purchase_Request__c at position 0 |
| `Region__c > 'APAC'` | Operator '>' is not supported for text values at position 10 |
| `Amount__c == 'big'` | Cannot compare field 'Amount__c' (CURRENCY) with a text literal at position 10 |
| `Amount__c` | field 'Amount__c' (CURRENCY) is not a Boolean and cannot stand alone as a condition at position 0 |
| `Region__c IN ()` | An IN list must name at least one value at position 14 |
| `Region__c IN ('APAC', NULL)` | Operator 'IN' cannot be used with NULL; test for a blank field with '== NULL' at position 22 |
| `Account__r.Owner.Profile.UserLicense.Name` | Field path 'Account__r.Owner.Profile.UserLicense.Name' has 5 segments; the maximum is 4 at position 0 |
| a blank expression | Expression is empty at position 0 |

### 4.8 Caching

`AMF_ExprCache` holds a static map keyed by `DeveloperName + '|' + Version__c`. Each rule compiles
once per transaction, however many records are evaluated.

- **No flush mechanism.** A rule edit invalidates its entry because the version changes. Conversely,
  an expression edited *without* a version bump would be served the old compilation by a transaction
  that has already compiled it. That is one reason every change bumps `Version__c`, and every row
  records `Rule_Version__c`.
- **Failures are not cached.** A compile error throws every time it is asked for.
- **Replacements need a new version.** `AMF_DraftRuleProvider` refuses a replacement rule at the
  version it replaces, for this reason.

### 4.9 Field loading

`AMF_FieldPathResolver.buildQuery()` produces:

```sql
SELECT Id, <every path across the object's rules, sorted, deduplicated> FROM <Object> WHERE Id IN :recordIds
```

- The query text is a pure function of its inputs, so tests assert it directly.
- Every object name and path is re-validated against `^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)*$`
  (case-insensitive) before concatenation: defence in depth against injection.
- A matrix of catch-alls reads no fields.
- The class is `inherited sharing`, so the query runs in the engine's mode (without sharing).
- The platform does **not** enforce SOQL's documented limit of 55 child-to-parent relationships at
  API 62: one query in `amf-dev` joined 142. The validator therefore runs each object's real query
  instead of counting relationships (section 9.2).

---

## 5. The engine

`AMF_ApprovalMatrixService` (`without sharing`) is the facade every entry point uses. It knows no
process name, approver or threshold.

### 5.1 Public API

| Member | Contract | Writes | Used by |
|---|---|---|---|
| `static submitRecord(Id)` `@AuraEnabled` | Whole call, one record. Throws `AuraHandledException` with the real message on a whole-call fault | Yes | `amfSubmitForApproval` |
| `static previewRecord(Id)` `@AuraEnabled`, **not** `cacheable` | Whole call, one record | No | `amfSubmitForApproval` |
| `submit(List<Id>)` | Whole call | Yes | `submitRecord` |
| `preview(List<Id>)` | Whole call; steps 1 to 7 only | No | `previewRecord`, `AMF_AgentPreviewRoute`, `AMF_AgentWhatIfRoute` (today's route) |
| `submitEach(List<Id>)` | Per record (M10) | Yes | The Flow action, REST, `AMF_AgentSubmitRoute`, and through it `AMF_McpSubmitRoute` |
| `previewWith(Id, Map<String, Object>)` | Whole call, one record, field values replaced in memory (M14) | No | `AMF_AgentWhatIfRoute` |
| `previewEach(List<Id>)` | Per-record refusals (M15) | No | `AMF_MatrixImpact` |

**Constructors:**
- `AMF_ApprovalMatrixService()` wires `AMF_CmdtRuleProvider` and `AMF_ClassicProcessStrategy`.
- `AMF_ApprovalMatrixService(AMF_RuleProvider, AMF_SubmissionStrategy)` is the test seam.

`previewRecord` is deliberately not cacheable: a cached route could outlive an edit to the record or
the matrix and confirm a route the submission would not take.

### 5.2 The pipeline

All entries share one private path in two halves.

**`prepare(recordIds, wholeCall, changes)`.** Steps 1 to 7. Writes nothing; the preview is this half
alone.

| Step | What happens | On failure |
|---|---|---|
| a | Input checks: a non-empty list, no null Id, no duplicate, one object | `AMF_SubmissionException` |
| b | **Authorise:** `UserRecordAccess.HasReadAccess` for the running user, one query per 200 records. The service runs without sharing, so it checks access itself before reading anything | Whole call: throw. Per record: `Refused` |
| c | **Guard field present** on the object, by describe | Throw ("cannot be governed … has no Matrix_Submission__c field") |
| d | **Pending check** (M8): `ProcessInstance` with `Status = 'Pending'` on the readable records. Asked only about readable records, so it reveals nothing about records the caller cannot read | Whole call: throw, naming the process. Per record: `Refused` |
| 1 | **Load rules** via `AMF_RuleProvider.getActiveRules(object)`. None means the object is not governed | Throw ("is not governed by the approval matrix …") |
| 2 | **Sort a copy** by `Priority__c`, then DeveloperName (`AMF_RuleDefinition.compareTo`; nulls last). The provider already promises this order; sorting again makes determinism the engine's property | |
| 3 | **Compile** each rule through `AMF_ExprCache` | A positioned `AMF_ExpressionException` stops the whole call, or for `submitEach` all of that object's records |
| 4 | **Load fields:** one query for the union of every rule's paths (section 4.9) | |
| 4a | `previewWith` only: check the changed fields (the record's own fields; no relationship paths; fields the user can see) and put the values on the in-memory copies | Throw |
| 5–7 | **First match**, per record: evaluate rules in order. The first definite true wins; the process it names is the route | See below |

Step 5–7 detail, per record (`match()`), with the whole rule walk inside one `try`:
- **First true rule, and it names a process:** the outcome is `Submitted` (meaning *routable* in a
  preview) and a `forSubmission` row is built.
- **First true rule, but its `Process_API_Name__c` is blank:** this throws inside the walk, giving
  `Failed`.
- **Any exception during the walk** (schema drift, a missing field): the outcome is `Failed`, and a
  `forFailure` row carries the message and stack trace. The walk **never** continues to the next
  rule.
- **No rule true:** the outcome is `Blocked_No_Match`, and a `forNoMatch` row carries every value
  read and the message.

**`execute(plan)`.** Steps 9, 10 and 8, with 11 folded in, under one savepoint:

| Step | What happens |
|---|---|
| 9 | **Stage the guard** on every routed record: `Database.update(rows, false)`, record by record (M10.3b). A record the platform will not update (a validation rule, for example) becomes `Failed`: "Matrix_Submission__c could not be set, so the record was not submitted to `<process>`: `<CODE>: <message>`", and is never submitted |
| 10 | **Submit** through `AMF_SubmissionStrategy.submit(requests)`. The engine checks for exactly one answer per request; a missing answer is a broken strategy and throws |
| 10 → 11 | A **success** sets `submitted = true` and `executionRefId`, and stamps `Execution_Ref_Id__c` on the unsaved row. A success *without* a reference is a contradiction and throws |
| 10 → refusal | A **refusal** becomes `Failed`: "Approval process `<process>` refused the submission: `<CODE>: <message>`". The record's guard is **re-armed** (cleared) in the same transaction, all or nothing |
| 8 | **Write** every decided record's row in one insert (`AMF_DecisionLogWriter.save`), and copy each row's Id into its outcome's `decisionLogId` |

Any exception inside `execute()` rolls back to the savepoint before it is rethrown. So a caller that
catches it, such as a Flow fault path, cannot keep a submission whose row was never written.

**Why the log is written after the platform answers (M10).** Before M10 the row came first, and the
lock rule would not let a `Submitted` row be walked back to `Failed`. One refusal therefore had to
roll back the whole call, erasing every other record's row. Writing after the answer makes each row
the true final outcome, written once.

### 5.3 Two contracts on one path

| Situation | `submit` / `preview` / `previewWith` | `submitEach` | `previewEach` | Row written? |
|---|---|---|---|---|
| Empty list | Throws "No records were supplied to submit" | Returns an empty list | Throws | — |
| A null Id | Throws | `Refused`: "A record Id is required." | Throws | No |
| An Id twice | Throws (submitting twice would re-arm a pending record's guard) | Submitted once; every request gets the same answer | Throws | — |
| Mixed objects | Throws "One submission covers one object …" | Partitioned by object, in first-seen order | Throws | — |
| Caller cannot read a record | Throws, naming the record | `Refused` | `Refused` | No |
| Record already pending | Throws, naming the process | `Refused`, naming the process | `Refused` | No |
| Object has no guard field, is not governed, or has a rule that will not compile | Throws | `Refused`, for that object's records only | Throws | No |
| Evaluation error | `Failed` | `Failed` | `Failed` (in memory) | Yes, except in a preview |
| No rule matched | `Blocked_No_Match` | `Blocked_No_Match` | `Blocked_No_Match` | Yes, except in a preview |
| Guard update refused | `Failed` | `Failed` | — | Yes |
| Platform refuses the submission | `Failed` | `Failed` | — | Yes |
| Strategy fails as a whole | Throws; rolled back | Throws; that object's work rolled back first, and the transaction fails | — | No |

`Refused` is an outcome value, never an `Outcome__c` value. Nothing was decided, so nothing is
logged.

### 5.4 `AMF_ApprovalMatrixService.Outcome`

Every field is `@AuraEnabled`.

| Field | Meaning |
|---|---|
| `recordId` | The record |
| `submitted` | True only when the record entered a process. Never true in a preview |
| `outcome` | `Submitted`, `Blocked_No_Match`, `Failed`, or (per-record entries only) `Refused` |
| `matchedRule` | The winning rule's DeveloperName. On a `Failed` row, the rule being evaluated or whose process refused |
| `ruleVersion`, `rulePriority` | The winning rule's version and priority |
| `matchedRuleDescription` | The rule's `Description__c` |
| `matchedExpression` | The expression, as `Expression_Snapshot__c` records it |
| `evaluatedValuesJson` | The same JSON `Evaluated_Values__c` records |
| `selectedProcess` | The process chosen |
| `executionRefId` | The `ProcessInstance` Id, once submitted |
| `decisionLogId` | The row written. Null in a preview and for `Refused` |
| `message` | Why the record did not route. Null when it did |

### 5.5 The guard in the engine

- **Set by the engine alone,** in the same transaction as its own submission, immediately before
  `Approval.process()`. It is written through `SObjectType.newSObject(id)` and `put()`, so that the
  engine stays object-agnostic.
- **Staging is record by record** (`allOrNone = false`). One record's validation failure fails that
  record alone. When some records fail, the platform saves the rest in a second attempt, which runs
  the object's triggers on them a second time.
- **Re-arming is all or nothing.** A refused record left with its guard set, in no process, would
  pass its template's entry criteria: the very bypass the guard closes. If re-arming fails, the whole
  call fails and rolls back.
- **The lock a final approval leaves is not counted on.** In an Apex test it did not stop a
  non-admin's guard update (technical log M10.8). Outside a test it is unmeasured.

### 5.6 Exceptions and messages

| Type | Raised by | Meaning |
|---|---|---|
| `AMF_SubmissionException` | Engine, strategy, entry points | A whole-call fault, or a broken strategy |
| `AMF_ExpressionException` | Evaluator package | A positioned expression fault, with `position` and `expressionText` |
| `AMF_ConfigurationException` | Validator, `AMF_DraftRuleProvider` | Configuration findings, or an invalid draft matrix |
| `AMF_ExplanationException` | Explainer, Einstein generator | No explanation or briefing could be given; the message is written for the reader |
| `AMF_PromptException` | Prompt runner | A prompt template could not be run |
| `AuraHandledException` | `@AuraEnabled` wrappers | Re-wraps the message with `setMessage`, so the client sees the real text rather than "Script-thrown exception" |

**Why per-record faults are outcomes, not exceptions** (decisions, 2026-08-18). An exception that
escapes the top of a request rolls back every DML statement before it. Throwing on a block would
erase the `Blocked_No_Match` row the audit trail exists to keep. So per-record faults are *recorded*,
and exceptions are reserved for faults that condemn the whole call. This is not §4.6's forbidden
catch-and-return-false: the record still does not route, and the trace outlives the transaction.

### 5.7 Resource use

Per object in a call, independent of the number of records except where noted:

| Operation | Count |
|---|---|
| `UserRecordAccess` query | 1 per 200 records |
| Pending `ProcessInstance` query | 1 |
| Rule SOQL (Custom Metadata, which consumes no query limits) | 1 |
| Field query (the union of paths) | 1 |
| Guard staging update | 1 DML statement |
| `Approval.process()` | 1 call per 100 records |
| Guard re-arm | At most 1 DML statement |
| Decision log insert | 1 DML statement |

Describes are cached per transaction. A real 200-record submission is tested in one transaction
(`AMF_SubmissionIntegrationTest`). Submission also fires the governed object's own automation: the
guard update runs its triggers and validation rules, and the approval process runs its initial
actions, including the record lock.

---

## 6. Submission strategy

`AMF_ClassicProcessStrategy` (`inherited sharing`) is **the only class that calls
`Approval.process()`**.

1. **Validate every request** before the first chunk goes: a record Id and a non-blank process name.
   A malformed request throws with nothing yet submitted.
2. **Build a request per record:**
   - `ProcessSubmitRequest.setObjectId(recordId)`;
   - `setProcessDefinitionNameOrId(processApiName)`: the process is named, not inferred;
   - `setSkipEntryCriteria(false)`, set **explicitly**. This is the load-bearing half of the guard:
     the platform still evaluates the template's entry criteria (`Matrix_Submission__c = TRUE`), so a
     submission that bypassed the engine fails.
3. **Submit in chunks of 100** (`CHUNK_SIZE`) with `Approval.process(requests, false)`: not all or
   nothing.
4. **Answer per record.** Each record gets an `AMF_SubmitResult`:
   - success, carrying `getInstanceId()` as `executionRefId`;
   - or `AMF_SubmitResult.refused(recordId, "CODE: message; …")`, carrying the platform's reason, for
     example `MANAGER_NOT_DEFINED: Manager undefined.`

   A result count different from the chunk size, or a success without an instance Id, throws.

`AMF_SubmitRequest` carries `recordId` and `processApiName` only. It names a process and nothing
about how it runs, so another execution strategy could read the same field differently with no
change upstream. `AMF_SubmitResult.executionRefId` is a `String`, not an `Id`, for the same reason.

---

## 7. Decision log writer

`AMF_DecisionLogWriter` (`without sharing`) builds rows. The engine decides when to save them.

| Factory | Outcome | Fields set beyond the base |
|---|---|---|
| `forSubmission(recordId, object, rule, valuesJson)` | `Submitted` | `Matched_Rule__c`, `Rule_Version__c`, `Expression_Snapshot__c`, `Selected_Process__c`, `Evaluated_Values__c`. The engine adds `Execution_Ref_Id__c` before insert |
| `forNoMatch(recordId, object, valuesJson, detail)` | `Blocked_No_Match` | `Evaluated_Values__c`, `Failure_Detail__c` |
| `forFailure(recordId, object, rule or null, valuesJson, detail)` | `Failed` | `Evaluated_Values__c`, `Failure_Detail__c` (at most 4,000 characters), and the rule's four fields when a rule is known |

- **The base, on every row:** `Record_Id__c`, `Object_API_Name__c`, `Submitted_By__c` (the running
  user) and `Submitted_At__c` (`System.now()`).
- **The governed record's lookup,** found by describe:
  - only *custom* reference fields that point at the object are considered, so `Submitted_By__c` and
    `OwnerId` cannot be mistaken for it;
  - several candidates resolve to the first by API name;
  - the result is cached per transaction;
  - a log with no such lookup still writes `Record_Id__c`, the provenance.
- **`save(rows)`** inserts, and never upserts: `Record_Id__c` is deliberately not unique.

The class runs without sharing deliberately. `Approval_Matrix_User` grants Read on the log but not
Create, and the guard is read-only for submitters. Only the framework writes the audit trail, on
behalf of a submitter who could not.

---

## 8. Approval templates

### 8.1 The template contract

Every Classic approval process the matrix may select must:

1. have `Matrix_Submission__c = TRUE` as its **only** entry criterion;
2. run its object's `AMF_Clear_Matrix_Submission` field update in its **final approval**, **final
   rejection** and, when recall is allowed, **recall** actions;
3. be **active**;
4. name individual users as `<alias>@{{AMF_USERNAME_DOMAIN}}`;
5. be **released** in `config/template-releases.json` and unchanged since.

The source gate checks all five (section 9.1).

Conventions the six templates also share:
- `allowRecall` true;
- `allowedSubmitters` all internal users;
- `recordEditability` `AdminOnly`;
- `finalRejectionRecordLock` false;
- `showApprovalHistory` true.

A first step has no `rejectBehavior`, and later steps have `RejectRequest`. That is the form a
retrieve returns, kept so that a retrieve does not disturb a fingerprint.

### 8.2 The six templates

| Template | Steps (`name`: label) | Approvers | Final approval lock |
|---|---|---|---|
| `Purchase_Request__c.PR_Two_Level_Mgmt` | `Manager_Level_1`: Manager; `Manager_Level_2`: Manager's Manager | `userHierarchyField` on `Manager` (`nextAutomatedApprover`) | Locked |
| `Purchase_Request__c.PR_Three_Level_Finance` | `Finance_Analyst`; `Finance_Controller`; `Finance_Director` | Named users `amfu3`, `amfu4`, `amfu5` | Locked |
| `Purchase_Request__c.PR_Credit_Risk_Queue` | `Credit_Risk_Review` | Queue `Q_Credit_Risk`, `FirstResponse`. The queue holds the public group `G_Finance_Approvers` | Locked |
| `Purchase_Request__c.PR_Finance_Committee` | `Finance_Committee`; `Finance_Leadership` | `amfu1`–`amfu3`, `Unanimous`; then `amfu4` or `amfu5`, `FirstResponse` | Locked |
| `Opportunity.OPP_Two_Level_Mgmt` | `Manager_Level_1`; `Manager_Level_2` | Manager hierarchy | **Unlocked**: an approved deal stays editable |
| `Opportunity.OPP_Manager_Approval` | `Manager` | Manager hierarchy | **Unlocked** |

Notes on the shapes:
- **Committees on Classic.** Classic cannot assign a step to a public group. So a committee names its
  members as users, and a group reaches a step only through a queue.
- **Unanimous steps** give each member a work item, and one rejection ends the request.
- **First-response steps** withdraw the other work items; history records them as `NoResponse`.
- **Opportunity uses the submitter's manager hierarchy,** because approvers need a licence that
  includes the object, and hierarchy templates name no user, so they deploy to any org.

### 8.3 Lifecycle and the release manifest

- **Never edited in place.** A live template is not changed. A change is a new version,
  `<name>_v2` (then `_v3`), released beside it. The rules are repointed, and the old version is
  deactivated, never deleted, so in-flight instances and history survive.
- **Naming.** `<OBJ>_<Shape>`: the first version has no suffix, and `_v0`/`_v1` are refused.
- **The manifest.** `config/template-releases.json` lists every released template with
  `releasedIn` and `sha256`.
- **The fingerprint.** The SHA-256 of the template's XML with its `<active>` element removed,
  insignificant whitespace dropped and line endings normalised (`Get-TemplateFingerprint` in the
  gate). Activation is excluded because superseding a template means deactivating it; everything
  else, the description included, is released content.
- **Releasing.** For an unreleased template, the gate prints the exact manifest line to add.
  Editing a fingerprint by hand defeats the check, and the manifest's own description forbids it.
- **The retrieved form.** Source is kept as a retrieve returns it: the platform drops `rejectBehavior`
  from a first step and appends `Owner` to a custom object's approval page fields. The gate reads
  source, not the org.

### 8.4 Portable usernames

A username is unique across all of Salesforce, so a template that names one deploys to one org.
Templates write `<alias>@{{AMF_USERNAME_DOMAIN}}`, and `sfdx-project.json` fills it at deploy:

```json
"replacements": [
  {
    "glob": "approvalProcesses/*.approvalProcess-meta.xml",
    "stringToReplace": "{{AMF_USERNAME_DOMAIN}}",
    "replaceWithEnv": "AMF_USERNAME_DOMAIN"
  }
]
```

- **The variable is mandatory.** The CLI refuses a deploy that includes approval processes unless
  `AMF_USERNAME_DOMAIN` is set (in `amf-dev`, `amf.00daj000012gj9b.dev`), so a forgotten variable
  fails rather than shipping one org's usernames to another.
- **Queues, groups and roles** are named by DeveloperName and travel unchanged.
- **A retrieve writes real usernames back into source,** and the gate refuses them.

### 8.5 Removing the standard Submit for Approval button

- **Where the button lives.** On a Lightning record page, the standard button is the
  `platformActionList` entry `Submit` / `StandardButton`.
- **A missing list is not enough.** A layout with no `platformActionList` shows the platform's default
  set, which includes the button once an approval process exists.
- **What each governed layout carries:** an explicit list that contains
  `<Object>.AMF_Submit_For_Approval` (`QuickAction`) and omits `Submit`.
- **`quickActionList` cannot host the action:** it refuses an LWC quick action outright.

The gate fails a governed object's layout that keeps the button or has no explicit list. It also
fails a governed object with no layout in source, because a layout that exists only in the org cannot
be checked. In another org, removing the button from a governed *standard* object's layouts is that
org's administrator's step.

---

## 9. Release gate

A Salesforce metadata deploy cannot run Apex, so "fail at deployment" is implemented as a required
two-part gate around the deploy:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-approval-matrix-source.ps1   # before
$env:AMF_USERNAME_DOMAIN = '<this org''s username domain>'
sf project deploy start -o <alias>
sf apex run --file scripts/validate-config.apex -o <alias>                                         # after
```

The split exists because `ProcessDefinition` exposes neither entry criteria nor actions to Apex SOQL.
Template checks therefore read source, and live checks read the org.

### 9.1 The source gate: `scripts/validate-approval-matrix-source.ps1`

Reads every package directory `sfdx-project.json` lists; the default directory is treated as the
framework. `-ProjectRoot` points it at another copy of the project. It collects every failure,
then throws once with the full list.

| Area | Check |
|---|---|
| Rules | Every `Approval_Matrix_Rule.*` record has `Active__c`. Every active rule has an object and a process, without surrounding whitespace, and names a template present in source |
| Guard | For every template a rule names, and every active template: it is active, has `Matrix_Submission__c = TRUE` as its only entry criterion, and clears the guard in its final approval, final rejection and (when recall is allowed) recall actions. A clearing action is recognised by what its field update does (a Literal false on the guard), not by its name |
| Lifecycle | Every template is released in the manifest with a matching fingerprint; every released template is still in source; a superseded version is inactive and named by no active rule; no version suffix below `_v2` |
| Portability | Every user approver or allowed submitter is `<alias>@{{AMF_USERNAME_DOMAIN}}`, and `sfdx-project.json` has the replacement that fills it |
| Layouts | Every governed object has at least one layout in source, each with an explicit `platformActionList` without `Submit` / `StandardButton` |
| Framework package | No standard object's layout or object settings in the default package directory |

On success it prints a single line:

```
Approval Matrix source validation passed for 8 active rule(s), 6 approval process(es) guard-checked,
6 of 6 template(s) released and unchanged, and 5 layout(s) of 2 governed object(s): …
```

### 9.2 The post-deploy validator: `AMF_ConfigValidator`

- **What it reads.** It runs against the deployed org, through `AMF_RuleProvider.getActiveRules()`
  (the configuration-wide read) and `AMF_ApprovalProcessProvider`.
- **Report, don't stop.** It returns every finding in one report rather than stopping at the first.
  The report is a validator report, not an evaluator fallback: no invalid rule is ever treated as
  false.

| Code | Finding |
|---|---|
| `RULE_PROVIDER_RETURNED_NULL` | The provider returned null instead of an empty list |
| `NULL_RULE` | The provider returned a null rule |
| `INACTIVE_RULE_RETURNED` | The provider returned an inactive rule |
| `OBJECT_API_NAME_MISSING` | A rule has no `Object_API_Name__c` |
| `OBJECT_NOT_FOUND` | The governed object does not exist or is not visible |
| `GUARD_FIELD_MISSING` | The governed object lacks `Matrix_Submission__c` |
| `GUARD_FIELD_WRONG_TYPE` | `Matrix_Submission__c` is not a Checkbox |
| `PRIORITY_MISSING` | A rule has no `Priority__c` |
| `EXPRESSION_INVALID` | A rule does not compile; the message carries the position |
| `UNION_QUERY_INVALID` | The query the engine will run for the object's rules is refused by the platform. Checked only when every rule on the object compiles, as the engine does |
| `DUPLICATE_PRIORITY` | Active rules on the same object share a priority |
| `PROCESS_API_NAME_MISSING` | A rule names no process |
| `PROCESS_API_NAME_WHITESPACE` | A process name has leading or trailing whitespace |
| `PROCESS_NOT_ACTIVE` | No active `ProcessDefinition` of type Approval with that DeveloperName exists for the object |

**Entry points:**

| Entry point | Behaviour |
|---|---|
| `validate()` | Returns `List<Finding>`; each finding has `code`, `message` and `render()` = `[CODE] message` |
| `assertValid()`, `static validateOrThrow()` | Throws `AMF_ConfigurationException` with the whole report: "Approval Matrix configuration is invalid:" followed by one line per finding |
| `scripts/validate-config.apex` | Calls `validateOrThrow()` and leaves the exception uncaught, so the CLI run fails. On success it logs "Approval Matrix configuration is valid." at `ERROR` level, deliberately, so that the line shows in the CLI's default output |
| Invocable *Validate Approval Matrix Configuration* | Input *Fail when configuration is invalid* (optional). Outputs *Configuration is valid*, *Error count* and *Validation errors*. Throws instead when asked to fail and findings exist |

Run it as a user holding `Approval_Matrix_Admin`.

---

## 10. Entry points

Every path converges on the engine:
- the Lightning quick action uses `submit()` and `preview()`, the whole-call contract;
- the Flow action, REST, the Agentforce assistant and the Claude connector all submit through
  `submitEach()`, the per-record contract. The assistant goes through
  `AMF_SubmitForMatrixApproval.submitEach`, and the connector through the assistant's Submit action.

So every path writes the same decision log row.

### 10.1 The Lightning quick action

`<Object>.AMF_Submit_For_Approval` is a quick action of type `LightningWebComponent`, which runs
`amfSubmitForApproval`: a headless LWC action (target `lightning__RecordAction`, `actionType`
Action). It is placed in each governed layout's `platformActionList`. The org refuses to change an
existing LWC action into a screen action, so the action stays headless and opens its confirmation as
a `LightningModal` itself.

```
invoke()  (guarded by isExecuting against a double click)
  ├─ previewRecord({recordId})                         nothing written
  │    ├─ outcome == 'Submitted' (routable) ─► AmfSubmitPreview.open({ preview })
  │    │      └─ only a 'submit' result continues; Cancel, the X and Escape stop here, leaving no trace
  │    └─ Blocked_No_Match or Failed ─► no modal; submit straight away, so that the attempt is recorded
  ├─ submitRecord({recordId})                          the engine decides again, for real
  │    └─ route changed? compare matchedRule, ruleVersion and selectedProcess with the preview
  └─ finally: notifyRecordUpdateAvailable([{recordId}]) + RefreshEvent (lightning/refresh)
              so the guard field, the lock state, the related lists and the timeline all refresh
```

| Situation | Toast title | Toast message | Variant, mode |
|---|---|---|---|
| Submitted by the previewed route | Submitted for approval | Matched `<rule>` (v`<n>`) and routed to `<process>`. | success, dismissable |
| Submitted by another route | Submitted, by a different route than previewed | The record or the matrix changed after the preview. Matched `<rule>` (v`<n>`) and routed to `<process>`. | warning, sticky |
| Blocked or failed | Not submitted | The outcome's `message` (the row is already written) | error, sticky |
| A whole-call fault in the preview or the submission | Could not submit for approval | The exception's message | error, sticky |

**`amfSubmitPreview`** (`LightningModal`) is presentation only. It calls no Apex and resolves with
`'submit'` or `'cancel'`.
- **What it shows:**
  - the selected process;
  - the matched rule, its description (when it has one), priority, version and condition;
  - a table of the values the rule read, parsed from `evaluatedValuesJson`.
- **How values render:**
  - numbers through `lightning-formatted-number`;
  - a null as `(blank)`;
  - booleans as `TRUE` and `FALSE`;
  - field names as their API names.
- **A rule that reads no fields** shows "This rule's condition reads no fields, so it matches every
  record."

`messageOf()` falls back through `error.body.message`, `error.body.pageErrors[0].message` and
`error.message`, so the engine's positioned text reaches the user.

### 10.2 The Flow action: `AMF_SubmitForMatrixApproval`

| | |
|---|---|
| Label | **Submit for Matrix Approval**, category *Approval Matrix* |
| Input | `recordId` (*Record ID*, required): one request per record |
| Behaviour | Calls `submitEach()`. One result per request, in order. Throws only when the strategy fails as a whole, after rolling back that object's submissions |

| Output | Label | Meaning |
|---|---|---|
| `recordId` | Record ID | The record |
| `submitted` | Submitted | True only when it entered an approval process |
| `outcome` | Outcome | `Submitted`, `Blocked_No_Match`, `Failed` or `Refused` |
| `message` | Message | Why it was not submitted |
| `matchedRule` | Matched Rule | The rule that routed it |
| `ruleVersion` | Rule Version | The rule's version |
| `selectedProcess` | Selected Process | The process chosen |
| `decisionLogId` | Decision Log ID | The row; empty for `Refused` |
| `executionRefId` | Approval Instance ID | The `ProcessInstance`; empty unless submitted |

The static `AMF_SubmitForMatrixApproval.submitEach(List<Id>)` is shared with the REST resource, so a
flow and an integration see one result shape.

### 10.3 REST: `AMF_MatrixSubmissionResource`

```
POST /services/apexrest/approval-matrix/v1/submissions
Content-Type: application/json
Authorization: Bearer <access token of the user the call runs as>

{"recordIds": ["<record Id>", "<record Id>", ...]}
```

- 1 to 200 Ids per call; records of any governed objects, mixed.
- **200**: `{"results": [ … ]}`, one result per Id in the order sent, in the Flow action's shape. A
  200 does not mean every record went in: read each `outcome`.
- **400**: `{"message": "…"}`, decided before anything is read or written, when the body:
  - is empty or not UTF-8;
  - is not JSON;
  - has no `recordIds` array;
  - has an empty array;
  - holds more than 200 Ids;
  - holds an item that is not a record Id.
- **500**: any other fault. It is left to escape so that the platform rolls the call back; catching
  it would commit whatever had happened before.

```bash
curl -X POST "$INSTANCE_URL/services/apexrest/approval-matrix/v1/submissions" \
  -H "Authorization: Bearer $ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"recordIds": ["<Purchase Request Id>", "<Opportunity Id>"]}'
```

```json
{
  "results": [
    {
      "recordId": "a02…",
      "submitted": true,
      "outcome": "Submitted",
      "message": null,
      "matchedRule": "PR_Catch_All",
      "ruleVersion": 1,
      "selectedProcess": "PR_Two_Level_Mgmt",
      "decisionLogId": "a01…",
      "executionRefId": "04g…"
    },
    {
      "recordId": "006…",
      "submitted": false,
      "outcome": "Refused",
      "message": "This record is already in approval process OPP_Manager_Approval. It cannot be submitted again until that request is recalled or completes.",
      "matchedRule": null,
      "ruleVersion": null,
      "selectedProcess": null,
      "decisionLogId": null,
      "executionRefId": null
    }
  ]
}
```

A 400 looks like:

```json
{"message": "\"recordIds\" is empty. Send {\"recordIds\": [\"<record Id>\", ...]} with 1 to 200 Ids."}
```

From the CLI, as the authenticated user:
`sf api request rest /services/apexrest/approval-matrix/v1/submissions --method POST --body '{"recordIds":["<Id>"]}' -o <alias>`.

### 10.4 Apex

```apex
AMF_ApprovalMatrixService engine = new AMF_ApprovalMatrixService();

// Per record: the contract behind Flow and REST. Never throws for one record's problem.
List<AMF_ApprovalMatrixService.Outcome> outcomes = engine.submitEach(recordIds);

// Where would it go? Writes nothing.
AMF_ApprovalMatrixService.Outcome preview = engine.preview(new List<Id>{ recordId })[0];

// What if? Writes nothing. Values are typed as the field is: a Decimal for currency.
AMF_ApprovalMatrixService.Outcome whatIf = engine.previewWith(
    recordId,
    new Map<String, Object>{ 'Amount__c' => 120000.00, 'Region__c' => 'APAC' }
);
```

Never call `Approval.process()` on a governed record directly. It would fail the template's entry
criteria, which is the guard working as designed.

### 10.5 Conversational entry points

The Approval Matrix Assistant (section 12.3) and the Claude connector (section 13) are entry points
too. Both reach the engine only through the actions described there.

---

## 11. Decision timeline

### 11.1 The service: `AMF_DecisionTimelineService` (`with sharing`)

| Member | Purpose |
|---|---|
| `@AuraEnabled static Timeline getTimeline(Id recordId)` | Behind `amfDecisionTimeline`. Not cacheable: a stale audit view is worse than a slower one |
| `Timeline build(Id recordId)` | The same, without the Aura wrapper |
| `static List<Value> describeValues(String snapshot, SObjectType rootType)` | Labels values exactly as the timeline does. Used by the assistant's preview (M13), so a route reads the same in the agent as on the page |

| Structure | Fields |
|---|---|
| `Timeline` | `entries` (newest first, at most 50), `hasMore` |
| `Entry` | `key` (the row Id, else the approval's), `occurredAt`, `decision` (null when the row is not visible), `approval` (null when the record never entered a process) |
| `Decision` | `logId`, `logName`, `outcome`, `matchedRule`, `ruleVersion`, `expression`, `values`, `selectedProcess`, `detail`, `submittedById`, `submittedByName`, `submittedAt`, `visibleAsApprover` |
| `Value` | `path`; `label` (the path in field labels, such as *Account > Region*, falling back to the path when it no longer resolves); `kind` (`number`, `boolean`, `text`, `blank` or `unparsed`); `text` |
| `AMF_ApprovalHistory.Instance` | `id`, `processName`, `status` (`Pending`, `Approved`, `Rejected`, `Removed`), `submittedAt`, `steps` |
| `AMF_ApprovalHistory.Step` | `id`, `status` (`StepStatus`), `isPending`, `stepName`, `actorId`, `actorName`, `originalActorId`, `originalActorName`, `comments`, `occurredAt` |

### 11.2 How a timeline is built

1. **Authorise:** `UserRecordAccess.HasReadAccess`, or `TimelineException`: "You need read access to
   this record to see its approval timeline."
2. **Read the log rows** for `Record_Id__c`, `WITH USER_MODE`: newest first (`Submitted_At__c DESC
   NULLS LAST, CreatedDate DESC, Id DESC`), at most 51.
3. **Read the native history** through `AMF_ClassicApprovalHistoryProvider` (`without sharing`; the
   caller has already authorised the record): every `ProcessInstance` on the record, newest first, at
   most 51, with `StepsAndWorkitems` (`ProcessInstanceHistory`: the submission, each decision, and
   the open work items).
4. **Join:** each row claims the approval its `Execution_Ref_Id__c` names.
5. **The current-approver rule (M14):**
   - a pending approval that no readable row claimed, and that is waiting on the reader
     (`AMF_ApproverScope`), has its own row read for them;
   - the read is without sharing, through the inner `ApproverRowReader`, bound to that record and
     those approval Ids;
   - the row is flagged `visibleAsApprover`.
6. **Orphans:** any approval still unclaimed becomes an approval-only entry, shown and labelled
   rather than hidden.
7. **Sort and cut:** sort newest first, keep 50, and set `hasMore`.

Reading 51 from both sides keeps the window honest across the join: a row and its approval are
written in the same transaction, so a row too old to fetch belongs to an approval too old to survive
the cut.

**The read side degrades instead of failing.** A field deleted since a decision was made shows under
its recorded path, and an unparseable snapshot is shown verbatim (`unparsed`). Routing fails loudly;
an audit view must not hide the trail.

### 11.3 Visibility rules

1. **Native history** is shown to anyone who can read the record: the same rule the Approval History
   related list follows.
2. **Decision log rows** are read in user mode. An `Approval_Matrix_User` sees their own rows, and an
   administrator with View All sees every row.
3. **The current approver** of a pending approval sees that approval's row, for as long as it waits
   on them. No other row, no other user, and no record share is affected.

The timeline names a rule by the DeveloperName and version the row snapshotted, never by today's
description. It never joins the live matrix, because a later edit must not rewrite the explanation of
an earlier decision. Every surface built on the timeline inherits these rules: the Explain button,
the assistant's explanations and briefings, and the connector's decision and briefing facts.

### 11.4 `AMF_ApproverScope`: who the current approver is

| Member | Behaviour |
|---|---|
| `actorsFor(userId)` | Returns a set of Ids: the user; every queue and public group containing them, following `GroupMember` through nested groups to depth 5; and every user whose `DelegatedApproverId` is them. Cached per user per transaction |
| `isWaitingOn(approval, actors)` | True when the approval is `Pending` and one of its pending steps' `actorId` is in `actors` |

Membership through a role is not followed: the framework's templates name users, queues and groups
only. One definition serves the timeline, briefings and "my approvals", so they cannot disagree. The
class is `without sharing`, because it reads group membership and delegation settings to answer a
question about the running user, never to show them.

### 11.5 The components

**`amfDecisionTimeline`** (target `lightning__RecordPage`) owns the data.
- A `lightning-card` titled *Approval Timeline*, with a refresh button.
- **It reads:** on connect, on the page's `lightning/refresh` (registered with
  `registerRefreshHandler`, and raised by the submit action after every attempt), and on the refresh
  button.
- **Overlapping reads take tickets.** Only the latest may write the result.
- **States:**
  - loading;
  - error, an alert with the service's sentence;
  - empty: "This record has not been submitted for approval. …";
  - the list, with the first entry expanded;
  - a note when `hasMore`.

**`amfDecisionTimelineEntry`** is presentation only.

- **Headline:**
  - *Routed to `<process>`*, with "Matched `<rule vN>` because `<Label = value and …>`.";
  - *Not submitted: no rule matched*;
  - *Not submitted: the attempt failed*, with the first line of the recorded reason;
  - *Submitted to `<process>`*, with "The decision log row that explains this route is not visible
    to you."
- **Badges:** *In approval*, *Approved*, *Rejected*, *Recalled*, *Blocked*, *Failed*.
- **Details:** the explanation component; then the rule, condition, values read, why it was not
  submitted, who submitted, and a link to the log row; then "Approval history: `<process>`,
  `<status>`" with each step.
- **Actor lines:**
  - "by X" for the submission and a recall;
  - "Waiting on X" for a pending step;
  - "X, for Y" when the actor differs from the original actor: a delegate, an administrator acting
    on someone's behalf, or a queue member deciding for the queue;
  - otherwise "X".
- **Formatting:** times in the viewer's Salesforce time zone (`@salesforce/i18n/timeZone`, the M12.6
  fix); numbers grouped for the viewer's locale, keeping their recorded precision.

**`amfDecisionExplanation`** is the Explain button (section 12.2).
- **What it shows:** the explanation card, with its *AI-generated* badge and the line "Written by
  Einstein at `<time>` from decision log `<ADL-…>`. Check it against the recorded details below."
- **When the approval moves on:** the `historyKey` the entry passes changes (status, step count, last
  step), and the component puts the explanation away.
- **Overlapping requests take tickets,** and the region is `aria-live`.

**Record pages.**
- `Purchase_Request_Record_Page` and `Opportunity_Record_Page` use `flexipage:recordHomeTemplateDesktop`:
  a highlights panel, Details and Related tabs, and `amfDecisionTimeline` in the sidebar.
- They are assigned for the desktop form factor only, so phones keep the default page and show no
  timeline.

---

## 12. AI layer

### 12.1 Design constraints

Principle 6 is enforced in the code:

| Constraint | How |
|---|---|
| AI never inside the engine | Actions call `preview()`, `previewWith()`, `previewEach()` and `submitEach()` (through the Flow action's method). No action evaluates a rule itself |
| Facts from Apex, words from the model | Every action returns a deterministic `summary` sentence built in Apex. Explanations, briefings and health summaries are written by a model *from facts Apex builds* |
| Never stored | No generated text is written to any record |
| Runs as the user | Both agents are employee agents. Template calls run in the reader's context. The classes are `with sharing` and read in user mode |
| Sensitive inputs are not the model's to fill | Agent Script binds them from variables, gates actions with `available when`, and requires the user's confirmation |
| Deploys anywhere | Prompt templates and authoring bundles live in `agentforce/`. The Apex that names them (`AMF_EinsteinExplanationGenerator`, `AMF_RuleDrafter`, `AMF_MatrixHealthService`) compiles in any org and reports, at run time, that explanations are unavailable |

### 12.2 Explanations and briefings: `AMF_DecisionExplainer` (`with sharing`)

| Method | Behaviour |
|---|---|
| `@AuraEnabled static explainDecision(Id logId)` | The Explain button. Reads the row `WITH USER_MODE` (otherwise: "This decision is not visible to you, so it cannot be explained."), builds the record's timeline, and explains the entry with that row. A row outside the newest 50 entries gives "This decision is not among the most recent ones on the record, …" |
| `explainLatest(Id recordId, String question)` | The assistant's explanation of the newest entry, answering the user's question (normalised, at most 500 characters; blank means "Why did this record go where it went, and where does its approval stand now?") |
| `briefLatest(Id recordId)` | Only for the approver the approval is waiting on (`AMF_ApproverScope`). The facts plus "Reader: `<name>`, the approver this approval is waiting on now.", asked `BRIEFING_QUESTION`, which ends "Do not tell me whether to approve or reject it." Anyone else gets "`<record>` is not waiting on you for approval, so there is nothing for you to decide. You can still ask why it went where it did." |

**The facts** (`factsOf`) are deterministic, line-labelled plain text built from one timeline entry:
- the record as a person names it;
- the outcome, in words;
- the deciding rule and its version;
- the condition as recorded;
- the values read, under their field labels;
- the process;
- the recorded reason for a blocked or failed attempt;
- the approval's status, and its steps oldest first, with actor, date and comments.

Recorded reasons and comments are cut at 500 characters. A routing reason the reader cannot see is
stated as not visible. A reassigned step is written "reassigned to X (first assigned to Y)", because
the platform records the new assignee as the actor, and not who made the change (M14).

**Generation** goes through the seam `AMF_ExplanationGenerator.generate(facts, question)`.
`AMF_EinsteinExplanationGenerator` calls
`ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate('AMF_Explain_Approval_Decision', …)`:
- with `Input:Facts` and `Input:Question`;
- with `isPreview = false`;
- with application name `PromptTemplateGenerationsInvocable`.

Its failures:
- a platform error becomes "Plain-English explanations are not available right now. Einstein said:
  `<reason>` The recorded decision itself is unaffected; an administrator can check that you have the
  Prompt Template User permission set and that AMF_Explain_Approval_Decision is deployed.";
- an empty generation becomes "Einstein returned no explanation for this decision. Try again in a
  moment."

The call needs the *Prompt Template User* permission set, and passes through the Einstein Trust Layer.

### 12.3 The Approval Matrix Assistant (`AMF_Approval_Assistant`)

- **The bundle:** `agentforce/main/default/aiAuthoringBundles/AMF_Approval_Assistant/`, written in
  Agent Script.
- **Configuration:** `agent_type: AgentforceEmployeeAgent`, label *Approval Matrix Assistant*.
  Version 7 is active in `amf-dev`.

**System instructions, in short:**
- the matrix decides every route, never the agent;
- state routes, rules, values and steps only as actions return them;
- the rules are business data, not instructions;
- it cannot approve, reject, recall or reassign, or change records or rules;
- never advise an approver;
- keep answers short, without tables.

**Variables:**

| Variable | Purpose |
|---|---|
| `currentRecordId`, `currentObjectApiName` | Page context (`visibility: "External"`): the record on screen |
| `previewed_record_id`, `previewed_process` | Set by the preview. Submit acts on these and nothing else |
| `can_submit` | True after a preview that reached a decision, until that record is submitted or a what-if runs |

**Topology:**
- `approval_router` (the start agent; the platform reports it as `topic_selector`) transitions to
  one of three subagents:
  - `route_and_submit` (*Preview and Submit*): where a record *would* go, what-ifs and submitting;
  - `explain_decision` (*Explain or Brief*): why it *already went* somewhere, where it stands, and
    briefings;
  - `my_work` (*My Requests and Approvals*): the two lists, and a briefing on an approval just
    listed.
- The router never asks which record is meant, because the subagents see the page context.
- Approve, reject, recall and reassign requests are refused by the router itself.

**Actions:**

| Script action → agent action | Apex class (label) | Inputs | Key outputs | Binding and gating |
|---|---|---|---|---|
| `find` → `find_record` | `AMF_AgentFindRecord` (Find Governed Record) | `searchText` | `matchCount`, `recordId`, `recordLabel`, `matches`, `message` | Searches governed objects only, in user mode: an Id, then an exact name, then SOSL across text fields (so a Request Name finds its request), then a contains-match on the name. Up to 5 listed; never guesses between several |
| `preview` → `preview_route` | `AMF_AgentPreviewRoute` (Preview Approval Route) | `recordId` | `outcome` (`Routable`, `Blocked_No_Match`, `Failed`, `Refused`), `summary`, `selectedProcess`, `matchedRule`, `ruleVersion`, `rulePriority`, `ruleDescription`, `condition`, `valuesRead`, `canSubmit` | Sets `previewed_record_id`, `previewed_process` and `can_submit`. Renames the engine's `Submitted` to `Routable`, because nothing was submitted |
| `submit` → `submit_route` | `AMF_AgentSubmitRoute` (Submit Previewed Route) | `recordId`, `expectedProcess` | `submitted`, `outcome`, `summary`, `routeChanged`, `decisionLogName`, `waitingOn` | `with recordId = @variables.previewed_record_id`; `with expectedProcess = @variables.previewed_process`; `available when @variables.can_submit == True`; `require_user_confirmation: True`. Submits through `submitEach()`. `routeChanged` is computed in Apex |
| `what_if` → `what_if_route` | `AMF_AgentWhatIfRoute` (What-If Approval Route) | `recordId`, `changes` ("Field = value; …") | `outcome`, `routeChanged`, `selectedProcess`, `matchedRule`, `currentProcess`, `currentRule`, `summary` | Runs `preview()` and `previewWith()` and compares them. Sets `can_submit = False` |
| `explain` → `explain_approval` | `AMF_AgentExplainDecision` (Explain Approval Decision) | `recordId`, `question` | `explained`, `explanation`, `decisionLogName` | `explainLatest` |
| `brief` → `brief_approval` | `AMF_AgentBriefApproval` (Brief Approver) | `recordId` | `briefed`, `briefing`, `decisionLogName` | `briefLatest`; only for the current approver |
| `my_requests` → `list_my_requests` | `AMF_AgentMyRequests` (My Approval Requests) | `pendingOnly` | `count`, `requests`, `message` | The user's own rows of the last 90 days, read in user mode; the newest attempt per readable record, joined to its approval; those still waiting first; at most 10 listed |
| `my_approvals` → `list_my_approvals` | `AMF_AgentMyApprovals` (My Pending Approvals) | `objectName` | `count`, `approvals`, `message` | Pending work items whose actor is in `AMF_ApproverScope`, on governed records the user can read; oldest first; at most 10 listed |

`AMF_AgentMyRequests` and `AMF_AgentMyApprovals` read through a `without sharing` inner class
bound to the user's own data: the approvals their rows name, and their own work items. Every action
answers every request rather than throwing. Ids arrive as text and are read by
`AMF_AgentSupport.idOf()`.

**What-if parsing** (`AMF_AgentWhatIfRoute`):
- **Pairs** are separated by `;` or new lines, each written `Field = value`, `Field: value` or
  `Field to value`.
- **Fields** may be named by label or API name. Only the record's own fields may change.
- **Numbers** may be written `120000`, `120,000`, `$120,000`, `120k`, `1.2m` or `1.2 million`.
- **Dates** are `YYYY-MM-DD` or the user's locale format.
- **Picklists** must take one of the field's active values, by value or label, in any case. The
  error lists up to 15 of them.
- **Checkboxes** take true/yes/on or false/no/off.
- **Blank** is any of blank, empty, none, null or nothing.
- **A field no active rule reads** is accepted, and the answer says it cannot change the route.

### 12.4 The Approval Matrix Admin Assistant (`AMF_Matrix_Admin_Assistant`)

- **For administrators only.** Its access permission set is `AMF_Matrix_Admin_Assistant_Access`, and
  its three actions are granted by `Approval_Matrix_Admin` alone. Version 1 is active.
- **It changes nothing.**
- **Variables:** `has_draft`, plus the last valid draft's `draft_object`, `draft_name`,
  `draft_priority` (text: the scripts use only text and Boolean variables), `draft_expression` and
  `draft_process`.

| Subagent | Script action → agent action | Apex class | Notes |
|---|---|---|---|
| `draft_rule` (*Draft a Rule*) | `get_checked_draft` → `draft_matrix_rule` | `AMF_AgentDraftRule` over `AMF_RuleDrafter` | Sets `has_draft` and the `draft_*` variables |
| `check_impact` (*Check a Change*) | `get_draft_impact` → `check_rule_impact` | `AMF_AgentCheckImpact` over `AMF_MatrixImpact` | Every input bound from the `draft_*` variables; `available when @variables.has_draft == True` |
| | `get_change_impact` → `check_rule_impact` | the same | Any described change |
| `matrix_health` (*Matrix Health*) | `get_health_report` → `matrix_health_report` | `AMF_AgentMatrixHealth` over `AMF_MatrixHealthService` | The counted facts are always returned |

The router (`admin_router`) refuses requests to deploy, activate, edit, submit or approve.

**A lesson the gate taught (M15.3).** The model at first answered without calling its tools,
inventing drafts and counts in the shape the instructions described. What fixed it:
- each subagent now states plainly that the model does not know the fields, rules, processes,
  records or counts, and that only its tool does;
- the tools are named as lookups;
- no instruction describes an answer the model could fill in by itself.

### 12.5 The admin services

**`AMF_RuleDrafter`** drafts one rule, and shows it only once it passes the release checks.

1. **The context given to the model** (template `AMF_Draft_Matrix_Rule`, inputs `Request` and
   `Context`; no record data):
   - the administrator's words, at most 2,000 characters;
   - the object's rule-readable fields (at most 150), each as `API name: label (type)`, with up to 25
     picklist values and their relationship names;
   - the active rules in priority order, with conditions, processes and descriptions;
   - the object's active approval processes;
   - every name active rules use;
   - whether this is a new rule or a change.
2. **The answer** must be one JSON object with the keys `developerName`, `label`, `priority`,
   `expression`, `processApiName`, `description` and `assumptions`.
3. **The checks,** before anyone sees it:
   - the condition compiles against the object (`AMF_ExprCompiler`);
   - the DeveloperName is valid (`^[A-Za-z][A-Za-z0-9]*(_[A-Za-z0-9]+)*$`, at most 40 characters),
     and is new; a new version of an active rule must keep that rule's name;
   - the priority is a whole number from 1 to 9999 that no other active rule on the object uses;
   - the process is an active Classic process for the object;
   - the description is present and at most 255 characters, and the condition present and at most
     2,000;
   - every other active rule on the object compiles, since otherwise no draft can be checked;
   - the engine's union query, with the draft in the matrix, is accepted by the platform.

   The label is cut to 40 characters rather than refused.
4. **Two attempts** (`MAX_ATTEMPTS`). Failures go back to the model once, with the reasons. If the
   second answer fails too, the administrator gets "No draft could be written that passes the checks.
   …", with each reason, and no rule.
5. **A valid draft returns:**
   - a summary that places it in the order ("tried after … and before …");
   - the assumptions;
   - `filePath` (`force-app/main/default/customMetadata/Approval_Matrix_Rule.<Name>.md-meta.xml`);
   - `metadataXml`, in the repository's format;
   - `ruleVersion`: 1 for a new rule, the live version + 1 for a change;
   - `changeType`: `Add` or `Replace`.

**Known limit:** names are checked against *active* rules only, because `AMF_RuleProvider` exposes no
others. A draft named like an inactive rule would overwrite it on release; the file name shows this in
review.

**`AMF_DraftRuleProvider`** is the live matrix with one change applied in memory: a rule added, a
rule replaced by a new version of itself, or a rule taken out. It refuses a change that changes
nothing, and a replacement at the live version (because of the cache key, section 4.8).

**`AMF_MatrixImpact`** shows what a change would do to real records.
1. **Which records:** the distinct records of the object with a decision log row in the last 90 days,
   newest first, at most 200, read in user mode.
2. **Two previews:** `previewEach()` under `AMF_CmdtRuleProvider`, then under `AMF_DraftRuleProvider`.
3. **The comparison:**
   - a record is *changed* if another rule or another process would decide it;
   - a record the engine refuses on either side (in an approval process now, or unreadable) is
     *skipped*;
   - up to 10 changed records are listed, with per-process counts before and after.
4. **Today's values.** Records are evaluated on their values *today*, not those recorded at the time,
   because a row records only what its deciding rule read. The report says so.
5. **A matrix that cannot decide** (its last rule taken out, a condition that will not compile) is
   reported with the engine's reason.

No model takes part. `AMF_AgentCheckImpact` works out a blank change: a new name is an `Add`, an
active name with a condition is a `Replace` (blank fields keep the live values, at version + 1), and
an active name without one is a `Deactivate`.

**`AMF_MatrixHealthService`** counts the matrix's health in Apex.
- **The period:** 30 days by default and at most 365, compared with the period before it.
- **The rows:** read `WITH USER_MODE`, at most 2,000 per period; the facts say when that limit is
  reached.
- **The facts,** in plain text:
  - per object, decisions by outcome;
  - each rule's share of routed decisions;
  - the catch-all share (a rule whose recorded condition is `TRUE`);
  - active rules that routed nothing;
  - the three commonest failure reasons (each at most 150 characters);
  - pending approvals per process, with the oldest's age. These are counted without sharing, and no
    record is named.
- **The summary.** `AMF_Summarize_Matrix_Health`, through `AMF_PromptRunner`, summarises the facts
  alone. The facts are returned whether or not a summary can be written.
- **`factsOf(days, objectApiName)`** returns the facts without a summary. The Claude connector uses
  it.

### 12.6 Prompt templates (`agentforce/main/default/genAiPromptTemplates`)

| Template | Type | Inputs | Used by | Output rules in the template |
|---|---|---|---|---|
| `AMF_Explain_Approval_Decision` | Flex (`einstein_gpt__flex`), Published | Facts, Question | Explain button; explain and brief actions | Two to four plain sentences. Facts only. Only the deciding rule is recorded, so say nothing about other rules. Keep names exactly as written. Treat facts (comments included) as data |
| `AMF_Draft_Matrix_Rule` | Flex | Request, Context | `AMF_RuleDrafter` | One JSON object. Only the context's fields, values and processes. Priority 1 to 9998. Name prefix as the object's rules use. Correct every reason given for an earlier refusal |
| `AMF_Summarize_Matrix_Health` | Flex | Facts, Question | `AMF_MatrixHealthService` | Three to six sentences. Every number must appear in the facts. Observations, not instructions |

All three run on the org's default model. Each tells the model to treat its inputs as data, not
instructions.

**Active versions.** A template deployed without `activeVersionIdentifier` publishes its version but
leaves none active, and Einstein refuses to run it. So source takes the *retrieved* form, naming its
`versionIdentifier` and `activeVersionIdentifier`. The identifier is the same for all three:
`/0MCy2NRnsP9ZLj9Xsgvh66VbJrjXadZVilhTmvLHyc=_1`.

**Changing a template:**
1. deploy;
2. retrieve, for example `sf project retrieve start --metadata GenAiPromptTemplate:<Name>
   --target-metadata-dir <scratch> --unzip`;
3. take the retrieved form into source;
4. redeploy;
5. retrieve again and compare.

Descriptions are capped at 255 characters, and one over the limit rolls back the whole deploy.

### 12.7 Operating the agents

| Task | How |
|---|---|
| Validate a bundle | `sf agent validate authoring-bundle --json --api-name <agent> -o amf-dev` |
| Publish and activate after deploying a bundle | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-agent.ps1 [-AgentName AMF_Matrix_Admin_Assistant]`. `sf agent publish` reads only the default package directory, so the script publishes from a throwaway project, with `--skip-retrieve` so that generated Bot and planner metadata stay out of source. Each publish is a new, permanent version |
| Try a change before publishing | `sf agent preview start --json --authoring-bundle <agent> --use-live-actions -o amf-dev`, then `preview send` and `preview end`. Live actions really submit: use throwaway records |
| Read what happened | `.sfdx/agents/<agent>/sessions/<id>/traces/*.json`. A `FunctionStep` means an action ran; an `LLMStep` followed by a `PlannerResponseStep` means the model answered by itself |
| Test the published agent | `sf agent test create --json --spec specs/<agent>-testSpec.yaml --api-name <agent>_Tests --force-overwrite -o amf-dev`, then `sf agent test run --json --api-name <agent>_Tests --wait 15 -o amf-dev`. Move the generated definition into `org-config/amf-dev/main/default/aiEvaluationDefinitions`. Run each suite twice, because topic assertions depend on the platform's model |
| A fresh org | Publish both agents before deploying `org-config/<org>`, whose access permission sets and test definitions name the agents |

Practical notes from the build:
- **The published agent routes by subagent descriptions.** Write each description to say what it is
  *not* for.
- **A preview session reuses earlier results,** so test a change in a fresh session.
- **The CLI cannot preview the published employee agent.** Use Testing Center or the panel.
- **Name approvers by Id.** `Actor.Name` can read null on approval rows created in the running
  transaction, so approvers are named from their Ids (`AMF_AgentSupport.actorNamesOf()`).

---

## 13. Claude connector (MCP)

[`docs/claude-connector.md`](claude-connector.md) is the setup and usage guide. This section covers
the design.

### 13.1 Architecture

```
Claude (claude.ai · Claude Desktop · mobile · Claude Code)
   │  MCP over HTTPS; OAuth 2.0 with PKCE, as the signed-in Salesforce user
   ▼
Salesforce Hosted MCP Servers
   https://api.salesforce.com/platform/mcp/v1/custom/AMFApprovalMatrix
   https://api.salesforce.com/platform/mcp/v1/custom/AMFApprovalMatrixAdmin
   (a sandbox or scratch org adds /sandbox/ after /v1/)
   │
   ▼
AMF_Mcp* global invocable facades (mcp/)
   ├─► AMF_Agent* actions (find, preview, what-if, submit, my requests, my approvals, check impact)
   ├─► AMF_DecisionExplainer with AMF_McpFactsOnly (decision and briefing facts)
   ├─► AMF_RuleDrafter with CapturingRunner / GivenAnswer (context, release checks)
   └─► AMF_MatrixHealthService.factsOf() (health facts)
            └─► AMF_ApprovalMatrixService (preview, previewWith, previewEach, submitEach)
```

Salesforce hosts the endpoint and its OAuth, so there is nothing else to run. A Hosted MCP Server
offers only `global` invocables as tools, and builds each tool's schema from `global` members alone.
So each tool is a thin `global with sharing` facade, and the M13 to M15 actions stay `public` and
unchanged.

The facades add three things an MCP client needs:

1. **Records as people name them.** Every tool takes a record reference, which
   `AMF_McpSupport.resolve()` passes to Find Governed Record. The answer is `Found`, `Ambiguous`
   (with the numbered matches) or `Not_Found`, and every answer carries the record's URL.
2. **Claude in Einstein's place.** `AMF_McpFactsOnly` is an `AMF_ExplanationGenerator` that returns
   the facts it is given, so the decision and briefing tools return exactly what Einstein would have
   been sent, with every visibility rule applied. For drafting:
   - `AMF_McpRuleContext.CapturingRunner` keeps the context the drafter would have sent a model, and
     stops;
   - `AMF_McpCheckRuleDraft.GivenAnswer` hands the drafter Claude's draft as the model's answer, so
     every release check runs on it unchanged, and the file to commit exists only for a draft that
     passed.

   No Einstein licence is needed, and nothing is generated in Salesforce.
3. **The server's half of "preview, confirm, submit":** the signed preview token (section 13.3).

### 13.2 Tools

| Server | Tool | Facade | Over | Annotations |
|---|---|---|---|---|
| `AMFApprovalMatrix` (*Approval Matrix*) | `find_record` | `AMF_McpFindRecord` | `AMF_AgentFindRecord` | read-only, idempotent |
| | `preview_route` | `AMF_McpPreviewRoute` | `AMF_AgentPreviewRoute`, plus a `submitToken` when the record can be submitted | read-only, idempotent |
| | `what_if_route` | `AMF_McpWhatIfRoute` | `AMF_AgentWhatIfRoute` | read-only, idempotent |
| | `submit_for_approval` | `AMF_McpSubmitRoute` | Token check, then a fresh preview, then `AMF_AgentSubmitRoute` and `submitEach()` | **destructive**, not idempotent |
| | `get_decision_facts` | `AMF_McpDecisionFacts` | `AMF_DecisionExplainer` with `AMF_McpFactsOnly`; by record or by decision log name | read-only, idempotent |
| | `get_briefing_facts` | `AMF_McpBriefingFacts` | `briefLatest()` with `AMF_McpFactsOnly` | read-only, idempotent |
| | `list_my_requests` | `AMF_McpMyRequests` | `AMF_AgentMyRequests` | read-only, idempotent |
| | `list_my_approvals` | `AMF_McpMyApprovals` | `AMF_AgentMyApprovals` | read-only, idempotent |
| `AMFApprovalMatrixAdmin` (*Approval Matrix Admin*) | `get_matrix_context` | `AMF_McpRuleContext` | `AMF_RuleDrafter` and `CapturingRunner`: the grammar guide and the object's context | read-only, idempotent |
| | `check_rule_draft` | `AMF_McpCheckRuleDraft` | `AMF_RuleDrafter` and `GivenAnswer`: every release check; the file only when valid; the problems otherwise | read-only, idempotent |
| | `check_change_impact` | `AMF_McpCheckImpact` | `AMF_AgentCheckImpact` | read-only, idempotent |
| | `get_health_facts` | `AMF_McpHealthFacts` | `AMF_MatrixHealthService.factsOf()` | read-only, idempotent |

Every tool is `openWorld` false. The read-only annotations let clients run the read tools without
asking. `submit_for_approval`'s destructive annotation makes Claude ask the user first.

Tool descriptions follow the M15 lesson: each reads as a lookup, says what Claude does not know that
only the tool does, and says what the tool is not for. A `descriptionOverride` is at most 1,024
characters.

### 13.3 The preview token

In Agentforce, the script binds Submit to the record just previewed. An MCP client has no script, so
Apex binds it (`AMF_McpSupport`):

- **Issued** by `preview_route` when the record can be submitted and the org has a key:
  `<issuedAtMillis>.<hex HMAC-SHA256(key, orgId|userId|recordId|process|issuedAtMillis)>`.
- **The key:** `AMF_Mcp_Settings__c.Preview_Key__c`, 256 random bits, Base64-encoded, in a protected
  custom setting. It is never returned to Claude or logged.
- **Checked** by `submit_for_approval`:

  | Check | Message on failure |
  |---|---|
  | A key exists | "Submitting through Claude is not set up in this org yet. An administrator runs scripts/setup-mcp.apex once; until then, submit from the record page." |
  | Two parts, the first numeric | "This submission does not come from a preview of this record, so nothing was submitted. …" |
  | The signature matches *this* user, this record and the confirmed process | the same |
  | Issued no more than 15 minutes ago, and no more than 60 seconds in the future | "The preview is more than 15 minutes old, so nothing was submitted. …" |

- **Then the matrix decides again.** `AMF_McpSubmitRoute` previews again and refuses if the route
  has moved, because the user approved a call that named the process. The Agentforce assistant, by
  contrast, submits a changed route and says so. Only then does it submit through Submit Previewed
  Route, so `submitEach()` writes the usual row.
- **The threat model** is a model submitting something its user was never shown. It is not the user,
  who may submit in the UI anyway.
- **Rotation:** clear the field in Setup → Custom Settings, then run `scripts/setup-mcp.apex` again.
  Previews not yet submitted become invalid.

### 13.4 OAuth: the External Client App (`org-config/amf-dev`)

| Setting | Value |
|---|---|
| App | `AMFClaudeConnector`, label *Approval Matrix Claude Connector*, distribution Local |
| Scopes | `MCP` and `RefreshToken` in the app's metadata. A client requests them as the OAuth scopes `mcp_api` and `refresh_token` |
| Flow | Authorisation code with PKCE required. The consumer secret is optional. Named-user JWT access tokens |
| Callback URLs | `https://claude.ai/api/mcp/auth_callback`, `https://claude.com/api/mcp/auth_callback`, `http://localhost:38000/callback` (Claude Code), `http://localhost:1717/OauthRedirect` (sf CLI) |
| Permitted users | Admin-approved and pre-authorised: holders of `AMF_Claude_Connector_User` or `AMF_Claude_Connector_Admin` |
| Refresh tokens | 30 days |
| Disabled | Client-credentials, token-exchange and guest flows |

The consumer key is generated by the org, retrieved when needed, and never kept in source. Another org
needs its own copy of the four `AMFClaudeConnector` files in `org-config/<org>`.

### 13.5 Deployment specifics

- **Server definitions at Metadata API 67.0.** Tool annotations (`readOnly`, `destructive`,
  `idempotent`, `openWorld`) exist only from 67.0, and a deploy at the project's 66.0 silently resets
  them to false. So `.forceignore` excludes `**/mcpServerDefinitions/**`, and
  `scripts/setup-claude-connector.ps1` deploys the definitions from a throwaway project at 67.0.
- **Activation is per org.** It is a runtime record (`McpServerAccess`), not metadata, so deploying
  never activates a server.
- **The setup script:**
  1. deploys `mcp`;
  2. deploys the External Client App;
  3. deploys the definitions at 67.0;
  4. activates both servers;
  5. seeds the key (keeping one that exists);
  6. assigns the connector permission set (`-Admin` for the admin set, `-AssignTo` for other users);
  7. prints the URLs, the client ID and the connection steps.

  Other parameters: `-TargetOrg`, `-OrgConfig`, `-SkipDeploy`. It is safe to run again.
- **Propagation.** A new External Client App can take up to 30 minutes before its first login works.
- **Platform rules:**
  - server names are letters and digits only;
  - over the REST Actions API, an Apex tool's arguments go in an `inputs` array;
  - every member of a tool class must be `global`, or the tool's schema breaks.
- **Checking it:**
  - `scripts/mcp-probe.mjs` is an MCP client. It needs one browser login per org, and keeps the
    refresh token in `.mcp-probe/`, which is git-ignored;
  - the same Apex answers over REST, at `/services/data/v66.0/actions/custom/apex/AMF_Mcp*`.
- **No MCP prompts:** a Hosted MCP Server's prompts run Prompt Builder templates through Einstein,
  which the connector deliberately avoids.

---

## 14. Security model

### 14.1 Principles

- **Everything runs as the user.** The one deliberate exception is the engine, which runs
  `without sharing` because it writes an audit row and stages a guard field that the submitter has no
  access to write. It authorises explicitly, through `UserRecordAccess`, before it reads or decides
  anything.
- **Audit reads are in user mode** (`WITH USER_MODE`): the timeline, the explainer, "my requests",
  the impact check and the health report.
- **Every other `without sharing` read is narrow and bounded:**
  - the current approver's row (`ApproverRowReader`), bound to the approvals found waiting on them;
  - group membership and delegation (`AMF_ApproverScope`);
  - the user's own approvals and work items (inner readers in `AMF_AgentMyRequests` and
    `AMF_AgentMyApprovals`);
  - native history, after the record is authorised (`AMF_ClassicApprovalHistoryProvider`);
  - the process catalogue (`AMF_ClassicApprovalProcessProvider`);
  - pending-approval counts (`AMF_MatrixHealthService`, counts only).
- **The framework creates no record shares** and does not alter the org's sharing model.

Appendix A lists each class's sharing declaration.

### 14.2 Permission sets

**`Approval_Matrix_User`** (`force-app`), for submitters and approvers:

| Area | Access |
|---|---|
| `Purchase_Request__c` | Create, Read, Edit. No Delete, View All or Modify All |
| `Purchase_Request__c` fields | Account, Amount, Region, Request Name, Risk Level and Vendor Type: read and edit. **`Matrix_Submission__c`: read only** |
| `Opportunity.Matrix_Submission__c` | Read only |
| `Approval_Decision_Log__c` | Read only, every field. Their own rows, under the Private sharing model |
| Apex classes (13) | `AMF_ApprovalMatrixService`, `AMF_DecisionTimelineService`, `AMF_DecisionExplainer`, `AMF_SubmitForMatrixApproval`, `AMF_MatrixSubmissionResource`, `AMF_AgentFindRecord`, `AMF_AgentPreviewRoute`, `AMF_AgentSubmitRoute`, `AMF_AgentWhatIfRoute`, `AMF_AgentExplainDecision`, `AMF_AgentBriefApproval`, `AMF_AgentMyRequests`, `AMF_AgentMyApprovals` |
| Tabs | Purchase Requests, Approval Decision Logs |
| The matrix | Not exposed. No Custom Metadata access |

**`Approval_Matrix_Admin`** (`force-app`), for administrators:

| Area | Access |
|---|---|
| `Purchase_Request__c` | Full, including View All and Modify All |
| `Approval_Decision_Log__c` | Read, Edit, View All. **No Create, Delete or Modify All**, because Modify All depends on Delete and rows must not be deletable |
| Fields | Every Purchase Request field, both guards and every log field editable. Edits to log rows still pass `Lock_Decision_Log`, which this set bypasses through the custom permission |
| Custom permission | `AMF_Bypass_Log_Lock` |
| Custom Metadata | `Approval_Matrix_Rule__mdt` |
| Apex classes (17) | The 13 above, plus `AMF_ConfigValidator`, `AMF_AgentDraftRule`, `AMF_AgentCheckImpact` and `AMF_AgentMatrixHealth` |
| Tabs | Purchase Requests, Approval Decision Logs |

**The other permission sets:**

| Permission set | Where | Grants |
|---|---|---|
| `AMF_Approval_Assistant_Access` | `org-config/amf-dev` | Opens the Approval Matrix Assistant (`agentAccesses`). Deploys only after the agent is published |
| `AMF_Matrix_Admin_Assistant_Access` | `org-config/amf-dev` | Opens the Admin Assistant. For administrators only |
| `AMF_Claude_Connector_User` | `mcp` | The eight user tools' classes. Admits the holder to `AMFClaudeConnector`. Assign with `Approval_Matrix_User` |
| `AMF_Claude_Connector_Admin` | `mcp` | All twelve tools' classes. Admits the holder. Assign with `Approval_Matrix_Admin` |
| Access Agentforce Default Agent (`CopilotSalesforceUser`) | standard | The Agentforce panel. Needs the Agentforce (Default) licence (`EinsteinGPTCopilotPsl`) |
| Prompt Template User (`EinsteinGPTPromptTemplateUser`) | standard | Running prompt templates: explanations, briefings, drafts, health summaries. Needs the Einstein Prompt Templates licence (`EinsteinGPTPromptTemplatesPsl`) |

To assign them from the CLI, assign the licences first if the CLI refuses a permission set for want of
one:

```powershell
sf org assign permsetlicense --name EinsteinGPTCopilotPsl --name EinsteinGPTPromptTemplatesPsl -o amf-dev
sf org assign permset --name Approval_Matrix_Admin --name CopilotSalesforceUser --name EinsteinGPTPromptTemplateUser --name AMF_Approval_Assistant_Access --name AMF_Matrix_Admin_Assistant_Access -o amf-dev
```

Add `--on-behalf-of <username>` for another user. A user signs out and in again after an assignment.

### 14.3 Prerequisites the platform does not check

- **Approvers need read access to the record:** through the role hierarchy, a sharing rule or Apex
  sharing. Assigning a Classic work item creates no share.
- **Approvers need a licence that includes the object.** The platform assigned an Opportunity approval
  to a Salesforce Platform user, whose licence grants no Opportunity access, without complaint. This
  is why the Opportunity templates follow the submitter's manager hierarchy.
- **A submitter routed to a hierarchy template needs a Manager,** or the platform refuses with
  `MANAGER_NOT_DEFINED`, and the attempt is logged `Failed`.

### 14.4 Field-level security and describe

The engine and the compiler use describe in the running user's context. As recorded in architecture
§11 and technical log M1.4d, a field the user has no FLS on is absent from describe. In consequence:
- **The guard:** without read FLS on `Matrix_Submission__c`, the engine reports that the object
  cannot be governed. Both permission sets grant read on every governed object's guard.
- **Rule fields:** without read FLS on a field a rule reads, the rule fails to compile *for that
  user*, with `Unknown field`. When a rule starts reading a new field, grant read on it to every
  submitter.
- **Tests cannot show this:** `System.runAs` does not enforce FLS.

### 14.5 Audit integrity

- **Immutability:** `Lock_Decision_Log` (section 3.2), with an administrator-only bypass.
- **No deletion:** no permission set grants Delete on the log.
- **Rows outlive their subjects:** all three lookups are `SetNull`.
- **One writer:** rows are written only by `AMF_DecisionLogWriter`, from the engine.
- **The guard:** read-only for submitters, set only by the engine, and cleared by every template exit
  (section 8.1).
- **Template integrity:** fingerprinted releases (section 8.3).

### 14.6 AI and connector security

| Concern | Control |
|---|---|
| Model sees too much | Prompts carry only the timeline's view of one decision (explanations and briefings), configuration and the administrator's words (drafting; never record data), or counts (health) |
| Prompt injection through data | Every template treats its inputs as data. Find escapes SOSL input, and the field-path builder validates identifiers. Approver comments and rule descriptions can still reach a model. In `amf-dev`, the Einstein Trust Layer's prompt-injection and toxicity detection are **off**: an open decision |
| Model acts beyond the user | Employee agents and MCP calls run as the signed-in user. Every action is `with sharing` |
| Model submits without consent | Agentforce: runtime-bound inputs, `available when` and `require_user_confirmation`. MCP: the destructive annotation and the signed preview token |
| Model approves or rejects | No action or tool can approve, reject, recall or reassign |
| Generated text mistaken for record | Labelled *AI-generated*, names its source row, never stored |
| Connector access | Admin-approved, pre-authorised by permission set; PKCE; 30-day refresh tokens; the consumer key not in source |

---

## 15. Testing

### 15.1 Strategy

- **No dependence on org rules.** Engine, validator, timeline and AI tests use `AMF_RuleBuilder`
  fixtures served by `AMF_RuleBuilder.Stub`.
  - The one exception is `AMF_CmdtRuleProviderTest`, which must read the real, *inactive*
    `PR_Long_Expression_Pin` row, because no fixture can show the platform's 255-character
    truncation.
  - Custom Metadata cannot be inserted in a test, which is why the provider seam is non-negotiable.
- **No real approvals in unit tests.** `AMF_StrategyStub` records the requests and the guard's value
  at submit time. It can also refuse, omit an answer, return a blank reference, or throw.
- **Thin real-platform tests** cover what stubs cannot:

  | Test class | Covers |
  |---|---|
  | `AMF_SubmissionIntegrationTest` | Real `Approval.process()`; a 200-record submission; a real per-record refusal through `AMF_Test_Refuse_Guard` |
  | `AMF_TemplateShapesTest` | The queue and committee shapes |
  | `AMF_ClassicApprovalHistoryProviderTest`, `AMF_ClassicApprovalProcessProviderTest` | The real history and catalogue reads |
  | `AMF_OpportunityGovernanceTest` | Opportunity end to end |
  | `AMF_DecisionLogLockTest` | The lock rule |

- **The evaluator** is tested by table-driven suites (every operator against every supported type,
  all null rules, precedence, both keyword forms, whitespace, multi-hop paths, bare atoms) and a
  malformed-input suite (`AMF_ExpressionErrorTest`) that asserts each error and its position. Every
  evaluator class is at 100%.
- **The AI seams are stubbed.** Generations are neither deterministic nor available in an Apex test.

A typical engine test follows this pattern (illustrative):

```apex
@IsTest
static void highValueApacGoesToTheFinanceChain() {
    AMF_RuleProvider rules = new AMF_RuleBuilder.Stub(new List<AMF_RuleDefinition>{
        new AMF_RuleBuilder().named('High_Value_APAC').withPriority(10)
            .withExpression('Amount__c > 100000 && Region__c == \'APAC\'')
            .routingTo('PR_Three_Level_Finance').build(),
        new AMF_RuleBuilder().named('Catch_All').withPriority(9999).build()   // TRUE -> PR_Two_Level_Mgmt
    });
    AMF_StrategyStub strategy = new AMF_StrategyStub();
    Purchase_Request__c request = new Purchase_Request__c(Amount__c = 150000, Region__c = 'APAC');
    insert request;

    AMF_ApprovalMatrixService.Outcome outcome =
        new AMF_ApprovalMatrixService(rules, strategy).submit(new List<Id>{ request.Id })[0];

    Assert.areEqual('High_Value_APAC', outcome.matchedRule);
    Assert.areEqual('PR_Three_Level_Finance', outcome.selectedProcess);
}
```

### 15.2 The suites

| Suite | Size at the M16 gate (2026-10-24) |
|---|---|
| Apex | 451 tests in 56 test classes, all passing; 97% org-wide coverage |
| Jest (LWC) | 75 tests in 5 suites |
| Testing Center | `AMF_Approval_Assistant_Tests`: 14 cases, 42 assertions. `AMF_Matrix_Admin_Assistant_Tests`: 6 cases, 18 assertions. Each passed twice in a row. Specs in `specs/`; definitions in `org-config/amf-dev` |
| UI test script | `docs/ui-tests/ui-test-scripts.md`: 16 cases (75 steps) for an AI agent driving a browser, with the operator's guide in `docs/ui-tests/README.md` |

### 15.3 Running them

```powershell
# Apex
sf apex run test -o amf-dev -l RunLocalTests -w 20 -r human

# Jest, through the CLI's bundled Node (npm is not installed on the build workstation)
$env:PATH = 'C:\Program Files\sf\client\bin;' + $env:PATH
& 'C:\Program Files\sf\client\bin\node.exe' 'node_modules\@salesforce\sfdx-lwc-jest\bin\sfdx-lwc-jest'

# A check-only deploy
sf project deploy start -o amf-dev --dry-run

# The agents
sf agent validate authoring-bundle --json --api-name AMF_Approval_Assistant -o amf-dev
sf agent test run --json --api-name AMF_Approval_Assistant_Tests --wait 15 -o amf-dev
```

- **`RunSpecifiedTests` needs per-class coverage.** A check-only deploy with `--test-level
  RunSpecifiedTests` needs 75% coverage on *every* class in the package, so include each class's own
  suite.
- **The agent suites need their records.** They name `amf-dev`'s records (PR-00000042 and
  PR-00000045 to -48). Do not submit those records in a demo, and make sure nothing is assigned to
  the CLI user before running the assistant's suite.

---

## 16. Build, deployment and environments

### 16.1 Prerequisites

- **The Salesforce CLI** (`sf`), including the agent commands, and PowerShell.
- **The `AMF_USERNAME_DOMAIN` environment variable** for any deploy that includes approval
  processes.
- **Org features:**
  - Einstein generative AI and Agentforce for `agentforce/`, turned on in Setup; no source file turns
    them on, deliberately;
  - Salesforce Hosted MCP Servers for `mcp/`.
- **On the build workstation:**
  - run every `sf` command in PowerShell, because under Git Bash the CLI's shim breaks on the space in
    `C:\Program Files`;
  - run from the project root;
  - commit with `HUSKY=0`, because the husky pre-commit hook would reformat whole files.

### 16.2 The development org, `amf-dev`

| | |
|---|---|
| Type | Developer Edition, API 68.0 |
| Username domain | `amf.00daj000012gj9b.dev` |
| Seeded people | `scripts/seed-data.apex` (idempotent) creates AMF Approver One to Five (`amfu1`–`amfu5`, Standard Platform User), each the manager of the one before (`amfu1`'s manager is `amfu2`, and so on), and AMF Framework Service (`amfsvc`). The administrator users report to `amfu1` |
| Queue and group | Queue `Q_Credit_Risk` contains the public group `G_Finance_Approvers` (`amfu1`, `amfu2`, `amfu3`) |
| Agents | `AMF_Approval_Assistant` v7, `AMF_Matrix_Admin_Assistant` v1, both active |
| MCP servers | `AMFApprovalMatrix` and `AMFApprovalMatrixAdmin`, both active; the preview key seeded |

### 16.3 Deploying to `amf-dev`

```powershell
$env:AMF_USERNAME_DOMAIN = 'amf.00daj000012gj9b.dev'
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-approval-matrix-source.ps1
sf project deploy start -o amf-dev                      # all four package directories, except the MCP server definitions
sf apex run --file scripts/validate-config.apex -o amf-dev
```

- **After an agent bundle changes,** run `scripts/publish-agent.ps1`.
- **After `mcp/` changes,** run `scripts/setup-claude-connector.ps1`.

### 16.4 Deploying to another org

> `force-app` has been shown to convert with another org's username domain, but it has not yet been
> deployed to a second org (technical log M12.5). Treat the first such deployment as a project task.

| Variant | Steps |
|---|---|
| **The framework only** (any org) | 1. Approvers: the shipped templates name `amfu1`–`amfu5` at the org's domain. Either create those users (`scripts/seed-data.apex` creates them with the domain `amf.<15-character org Id, lower case>.dev`, plus the `Q_Credit_Risk` queue and its group), or release new template versions that name the org's own approvers. 2. Set `AMF_USERNAME_DOMAIN` to that domain. 3. `sf project deploy start --source-dir force-app -o <alias>`. 4. Run `scripts/validate-config.apex`. 5. Remove the standard Submit for Approval button from the layouts of any governed standard object (keep those layouts in `org-config/<org>`). 6. Assign the permission sets, and make sure approvers have record access and licences |
| **With Agentforce** | 1. Turn on Einstein generative AI and Agentforce. 2. `sf project deploy start --source-dir force-app --source-dir agentforce -o <alias>`. 3. `scripts/validate-config.apex`. 4. Publish both agents. 5. Deploy `org-config/<org>`, with that org's own configuration. 6. Assign the access sets |
| **With the Claude connector** | Deploy `force-app` and `mcp`. Give the org its own copy of the `AMFClaudeConnector` files in `org-config/<org>`. Then run `scripts/setup-claude-connector.ps1 -TargetOrg <alias> -OrgConfig <org>` |

Without the `agentforce` directory, the Explain button answers that explanations are not available,
and everything else works.

### 16.5 Scripts

| Script | Purpose |
|---|---|
| `scripts/validate-approval-matrix-source.ps1` | The source gate (section 9.1). `-ProjectRoot` checks another copy |
| `scripts/validate-config.apex` | The post-deploy validator (section 9.2) |
| `scripts/seed-data.apex` | Seeds the approvers, the manager chain, the queue and the group. Idempotent |
| `scripts/publish-agent.ps1` | Publishes and activates an agent from a throwaway project. `-AgentName`, `-TargetOrg`, `-SkipActivate` |
| `scripts/setup-claude-connector.ps1` | Sets up the Claude connector end to end (section 13.5) |
| `scripts/setup-mcp.apex` | Seeds the preview key, keeping an existing one |
| `scripts/mcp-probe.mjs` | An MCP client: lists a server's tools with their annotations, and calls one |
| `scripts/explain-decision.apex` | A live check that Einstein explains a real decision. Writes nothing |

### 16.6 API versions

| Item | Version | Why |
|---|---|---|
| Apex classes and LWC | 62.0 | Engine classes must stay at API 66 or below. From API 67, Apex runs database operations in user mode by default, which would break the engine's deliberate system-mode guard staging and log writes (spike results, Round 2) |
| `sourceApiVersion` | 66.0 | Agent Script needs Metadata API 66 or later |
| MCP server definitions | 67.0 | Tool annotations exist only from 67.0 |

---

## 17. Extending the framework

### 17.1 Add or change a rule

A rule is one file: `force-app/main/default/customMetadata/Approval_Matrix_Rule.<DeveloperName>.md-meta.xml`.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
    <label>PR - EMEA Over 500k</label>
    <protected>false</protected>
    <values>
        <field>Object_API_Name__c</field>
        <value xsi:type="xsd:string">Purchase_Request__c</value>
    </values>
    <values>
        <field>Priority__c</field>
        <value xsi:type="xsd:double">15.0</value>
    </values>
    <values>
        <field>Expression__c</field>
        <value xsi:type="xsd:string">Amount__c &gt; 500000 &amp;&amp; Region__c == 'EMEA'</value>
    </values>
    <values>
        <field>Process_API_Name__c</field>
        <value xsi:type="xsd:string">PR_Finance_Committee</value>
    </values>
    <values>
        <field>Description__c</field>
        <value xsi:type="xsd:string">EMEA spend over 500,000 goes to the finance committee.</value>
    </values>
    <values>
        <field>Version__c</field>
        <value xsi:type="xsd:double">1.0</value>
    </values>
    <values>
        <field>Active__c</field>
        <value xsi:type="xsd:boolean">true</value>
    </values>
</CustomMetadata>
```

1. **Choose a free priority** in the right place in the order. Leave gaps; the catch-all stays at 9999.
2. **To change a rule,** keep its DeveloperName and increment `Version__c`. To retire one, set
   `Active__c` to false: deactivate rather than delete.
3. **Optionally,** let the Admin Assistant or Claude draft it and check its impact first.
4. **Release:** run the source gate, deploy, run `validate-config.apex`, and commit.
5. **Keep the dependants in step:**
   - `AMF_CmdtRuleProviderTest` pins the first shipped rule, so a new lowest-priority rule breaks it
     (section 19);
   - `docs/ui-tests/ui-test-scripts.md` and the agent test specs quote today's routes. Update them
     when a route they use changes.

Every field a new rule reads must be readable by every submitter (section 14.4).

### 17.2 Change an approval template

1. **Copy** the template to `<Object>.<Name>_v2.approvalProcess-meta.xml` (or the next free version)
   and make the change there. Keep the guard contract (section 8.1).
2. **Run the source gate.** It prints the manifest line for the new version; add it to
   `config/template-releases.json`.
3. **Repoint** every rule that named the old version, incrementing each rule's version.
4. **Deactivate** the old version (`<active>false</active>`, the one change the gate allows) and keep
   it in source.
5. **Release** as in section 17.1.

The gate fails if the old version stays active, if a rule still names it, or if the original was
edited in place.

### 17.3 Govern a new object

No engine or LWC change is needed. Opportunity (M11) is the worked example.

1. **The guard:** add `Matrix_Submission__c` (Checkbox, default false) to the object.
2. **Field security:** in both permission sets, grant read on the guard (edit in Admin only) and on
   every field the rules will read.
3. **The clearing update:** add a workflow field update `AMF_Clear_Matrix_Submission` on the object:
   Literal false on the guard.
4. **Templates:** build Classic templates that meet the contract (section 8.1). Release them in the
   manifest. Prefer manager-hierarchy or queue approvers for a standard object, because of licences.
5. **The action:** add a quick action `<Object>.AMF_Submit_For_Approval` (type `LightningWebComponent`,
   `amfSubmitForApproval`).
6. **Layouts:** on every layout, an explicit `platformActionList` with that action and without
   `Submit` / `StandardButton`. A custom object's layouts go in `force-app`; a standard object's in
   `org-config/<org>`.
7. **The log lookup:** add a lookup on `Approval_Decision_Log__c` to the object (`SetNull`, relationship
   label *Approval Decisions*). Add it to the log layout and both permission sets, and add the
   *Approval Decisions* related list to the object's layouts, without New or Mass Change Owner.
8. **The record page:** a Lightning page with `amfDecisionTimeline`, assigned for desktop.
9. **Rules:** add the object's rules.
10. **Access:** give approvers record access and licences.
11. **Verify:** run the source gate and the validator, and add a governance test like
    `AMF_OpportunityGovernanceTest`.

Find Governed Record, the timeline and the health report pick up the new object automatically,
because they learn the governed objects from the rules.

### 17.4 Support another field type in expressions

1. **Map the type:** add its `Schema.DisplayType` to `AMF_ExprCompiler.SUPPORTED_TYPES`, with the right
   value type, and confirm the operator rules hold for it.
2. **Evaluate it:** confirm `AMF_Evaluator` compares its values correctly.
3. **Draft with it:** add it to `AMF_RuleDrafter.READABLE_TYPES`.
4. **Test it:** extend the table-driven and malformed-input suites.
5. **Document it:** update the grammar description in `AMF_Draft_Matrix_Rule`, `AMF_McpRuleContext.GUIDE`
   and the user guide.

DateTime needs a time-zone decision first (§4.3).

### 17.5 Add an entry point

- **Build over the engine.** Use `submitEach()` for per-record answers, or `submit()` for a whole-call
  contract. Use `preview()` or `previewEach()` to show a route.
- **Never call `Approval.process()`** and never set the guard yourself.
- **Grant the class** in the permission sets.
- **Map exceptions honestly.** A whole-call exception means nothing was written.

### 17.6 Change the Claude connector, a prompt template or an agent

- **An MCP tool:** follow [the connector guide, section 7.3](claude-connector.md#73-adding-or-changing-a-tool).
- **A prompt template:** follow the retrieved-form steps in section 12.6.
- **An agent:** edit the bundle, validate it, try it in a local preview, deploy, publish, and run its
  Testing Center suite twice. Keep each subagent description saying what it is not for. Never let the
  router ask which record is meant. Say in each subagent what the model does not know (section 12.4).

---

## 18. Operations and troubleshooting

### 18.1 Engine messages

| Message (beginning) | Where it appears | Cause | Remedy |
|---|---|---|---|
| "Submission requires read access to the record. `<user>` cannot read: …" | Whole call (button) | No read access | Fix sharing |
| "Submission requires read access to the record, and `<user>` cannot read it." | Per record (`Refused`) | The same | The same |
| "A record that is already in an approval process cannot be submitted again …" | Whole call | A pending `ProcessInstance` | Wait, or recall it |
| "This record is already in approval process `<P>`. …" | Per record (`Refused`) | The same | The same |
| "`<Object>` is not governed by the approval matrix: it has no active Approval_Matrix_Rule__mdt rows. …" | Both | No active rules: the kill switch, or a mistake | Activate a rule |
| "`<Object>` cannot be governed by the approval matrix: it has no Matrix_Submission__c field. …" | Both | The guard is missing, or the user has no FLS on it | Add the field, or grant read |
| "No active rule matched this `<Object>`. N active rule(s) were evaluated and none was true. …" | `Blocked_No_Match` row | No match | Fix the data, or add a rule or a catch-all |
| "Routing `<Id>` failed while evaluating rule `<R>`: …" | `Failed` row | A runtime evaluation error, such as schema drift | Fix the rule or the schema |
| "Rule `<R>` matched `<Id>` but names no approval process …" | `Failed` row | A blank `Process_API_Name__c` | Fix the rule; the validator also catches this |
| "Matrix_Submission__c could not be set, so the record was not submitted to `<P>`: `<CODE>: …`" | `Failed` row | A validation rule or trigger refused the guard update | Fix the cause |
| "Approval process `<P>` refused the submission: `<CODE>: …`" | `Failed` row | A platform refusal, such as `MANAGER_NOT_DEFINED`, or a process inactive in the org | Fix the cause, then resubmit |
| "One submission covers one object. This call mixed: …" / "Record `<Id>` was supplied more than once. …" / "No records were supplied to submit" | Whole call | A caller error | Use one object per call, or use `submitEach()` |
| "… but the strategy returned no answer / no execution reference for it" | Exception | A broken strategy | A defect: investigate |
| Positioned compile errors (section 4.7) | Whole call / `Refused` | A rule that does not compile reached the org | Fix the rule; run the validator |

### 18.2 Diagnostic queries

```sql
-- Every decision about one record, newest first
SELECT Name, Outcome__c, Matched_Rule__c, Rule_Version__c, Selected_Process__c,
       Expression_Snapshot__c, Evaluated_Values__c, Failure_Detail__c,
       Execution_Ref_Id__c, Submitted_By__r.Name, Submitted_At__c
FROM Approval_Decision_Log__c
WHERE Record_Id__c = '<18-character record Id>'
ORDER BY Submitted_At__c DESC

-- The native history a decision started
SELECT Id, Status, ProcessDefinition.DeveloperName,
       (SELECT StepStatus, ProcessNode.Name, Actor.Name, OriginalActor.Name, Comments, CreatedDate
        FROM StepsAndWorkitems)
FROM ProcessInstance
WHERE Id = '<Execution_Ref_Id__c>'

-- Outcomes by rule over the last 30 days
SELECT Object_API_Name__c, Matched_Rule__c, Outcome__c, COUNT(Id)
FROM Approval_Decision_Log__c
WHERE Submitted_At__c = LAST_N_DAYS:30
GROUP BY Object_API_Name__c, Matched_Rule__c, Outcome__c

-- Guards that are set, to compare against pending approvals (a "stray" guard is set with none pending)
SELECT Id, Name FROM Purchase_Request__c WHERE Matrix_Submission__c = TRUE
SELECT TargetObjectId FROM ProcessInstance WHERE Status = 'Pending' AND TargetObject.Type = 'Purchase_Request__c'
```

The *All Decisions* list view and reports on Approval Decision Logs give the same picture in the UI.
The Admin Assistant's health report, or the connector's `get_health_facts`, summarises it.

### 18.3 Common situations

| Symptom | Likely cause | Resolution |
|---|---|---|
| "Unknown field 'X' on Y" for some users only | They lack FLS on a field a rule reads | Grant read in their permission set (section 14.4) |
| "… cannot be governed … has no Matrix_Submission__c field", though it exists | The user lacks FLS on the guard | Grant read on the guard |
| `Failed` with `MANAGER_NOT_DEFINED` | The submitter has no manager, on a hierarchy template | Set the user's Manager |
| An approver cannot open the record they must approve | No record share | Role hierarchy or a sharing rule |
| An Opportunity approval went to a user who cannot see Opportunities | Their licence | Use a fully licensed approver, or a hierarchy template |
| The standard Submit for Approval button appears on a governed object | The layout lacks an explicit action list, or an org-owned layout was edited | Fix the layout; the gate checks layouts in source |
| Matrix Submission ticked with no pending approval ("stray guard") | A recall before the M8 fix, a spike record, or an administrator's edit | An administrator unticks it, after checking there is no pending approval |
| The timeline shows "The decision log row that explains this route is not visible to you." | The viewer cannot read the row and is not the current approver | Expected; an administrator can read it |
| The timeline shows "The approval history for this submission is not available." | A `Submitted` row whose approval is not in the window or not found | Check `Execution_Ref_Id__c` against `ProcessInstance` |
| Explain says explanations are "not available right now" | No Prompt Template User, Einstein off, or the template missing or without an active version | Section 12.2 and 12.6 |
| A deploy is refused for want of `AMF_USERNAME_DOMAIN` | The variable is not set | Set it in the same PowerShell session |
| The gate says a template "has changed since it was released" | An in-place edit | Restore it; make a `_v2` (section 17.2) |
| The validator reports `UNION_QUERY_INVALID` | The platform refuses the object's union query | Simplify the paths; the message carries the platform's reason |
| An agent answers without calling its action | Instructions that describe an answer shape | Section 12.4's lesson; read the trace (section 12.7) |
| Claude connector login or tool errors | Propagation, a missing permission set, or a missing key | [The connector guide, section 6](claude-connector.md#6-troubleshooting) |

---

## 19. Known limitations and technical debt

**Functional limits:**
- **Classic approval processes only.** Flow approval orchestrations are designed in architecture §5.3
  but not built; `docs/spike-results.md` Round 2 binds any future Flow phase.
- **Unsupported field types:** DateTime fields and literals (they need a time-zone decision), and
  Email, Phone, URL and Text Area fields.
- **Multi-select picklists** cannot be compared field to field.
- **The log does not record the entry point** (button, Flow, REST, agent, Claude), nor the rule's
  description.
- **A record a validation rule would refuse still previews as routable.** The refusal appears at
  submission as `Failed`.
- **The final-approval lock's effect** on the guard update, outside an Apex test, is unmeasured.
- **Drafted rule names** are checked against active rules only.
- **The impact check skips** records that are in an approval process now.
- **The assistant's confirmation can rename the route.** In the M15.7 check it asked once, in the
  chat, with "You're about to submit this record for two-level management approval", and gave no
  rule or values. The record and process are still bound from the preview, and Apex decides the route
  again.
- **No timeline on phones.** UI strings are English literals, with no Custom Labels yet.

**Technical debt:**
- `Lock_Decision_Log` still permits a post-insert stamp that nothing performs since M10.
- `AMF_CmdtRuleProviderTest` pins the first shipped rule, so a new lowest-priority rule breaks it.
- Template drift in an org is found only by retrieving and comparing against the manifest; that is
  not scripted.
- The timeline LWC words a `Reassigned` row "X, for Y". The explainer's facts word it correctly.
- `amfSubmitForApproval` and `amfDecisionTimeline` keep their own `messageOf`; `c/amfErrors` exists
  for them.
- `AMF_AgentSubmitRoute` keeps an approver-name lookup that duplicates
  `AMF_AgentSupport.actorNamesOf()`.
- `AMF_McpRuleContext.GUIDE` repeats the drafting template's grammar; keep the two in step.
- The decision log's record page offers Submit for Approval, Edit and Delete, because its layout has
  no explicit action list.
- The Approval Decisions card shows four of its six columns, and related lists can show their earlier
  state until a reload.
- The MCP server definitions deploy only through the setup script, until `sourceApiVersion` reaches
  67.0.
- The submitters' assistant has not been reworded in the style M15 found reliable. It passes its
  suite, but fabrication is possible in principle.
- Einstein's explanations and briefings can end with a sign-off line, which
  `AMF_Explain_Approval_Decision` does not forbid (M15.7).
- `package-lock.json` is untracked.

**Environment (`amf-dev`):**
- Stray guards on PR-00000014 to -20 and -23 to -25 (the M6 spike's records; its teardown script
  removes them).
- Seven old pending approvals.
- The Trust Layer's detection settings are off.

---

## 20. Conventions

| Convention | Rule |
|---|---|
| Naming | `AMF_` prefix on Apex classes, `amf` on LWC. Every class's ApexDoc header cites the architecture section it implements |
| Rule access | Custom Metadata is read **only** through `AMF_RuleProvider`. `AMF_CmdtRuleProvider` uses SOQL, never `getAll()` or `getInstance()`; a test pins it |
| Submission | `Approval.process()` is called **only** through `AMF_SubmissionStrategy` |
| Tests | In-memory rule fixtures; no dependence on org rule rows (one documented exception) |
| Failure | Evaluation errors fail loudly: block and log. Never catch-and-return-false |
| API versions | Apex and LWC at 62.0; engine classes never above 66 |
| Retrieved form | Approval templates and prompt templates are kept in the form a retrieve returns |
| Packages | `force-app` deploys anywhere; AI metadata in `agentforce`; the connector in `mcp`; the org's own configuration in `org-config/<org>` |
| Process | Work proceeds in phases authorised in `CLAUDE.md`. Each phase is planned, then built, then gated with real output. It ends with a full `docs/technical-log.md` entry and one commit, `Phase MN: <name>`, followed by a commit recording its SHA. An approved deviation from the design gets one line in `docs/decisions.md` and a note in the architecture section it touches |

---

## Appendix A: Class reference

All classes are at API 62.0. Test classes (56) are omitted.

| Class | Package | Sharing | Purpose |
|---|---|---|---|
| `AMF_AgentBriefApproval` | force-app | with | Brief Approver action |
| `AMF_AgentCheckImpact` | force-app | with | Check Rule Impact action |
| `AMF_AgentDraftRule` | force-app | with | Draft Matrix Rule action |
| `AMF_AgentExplainDecision` | force-app | with | Explain Approval Decision action |
| `AMF_AgentFindRecord` | force-app | with | Find Governed Record action |
| `AMF_AgentMatrixHealth` | force-app | with | Matrix Health Report action |
| `AMF_AgentMyApprovals` | force-app | with (without-sharing inner reader) | My Pending Approvals action |
| `AMF_AgentMyRequests` | force-app | with (without-sharing inner reader) | My Approval Requests action |
| `AMF_AgentPreviewRoute` | force-app | with | Preview Approval Route action |
| `AMF_AgentSubmitRoute` | force-app | with | Submit Previewed Route action |
| `AMF_AgentSupport` | force-app | with | Shared helpers: Id parsing, labels, names, dates |
| `AMF_AgentWhatIfRoute` | force-app | with | What-If Approval Route action |
| `AMF_ApprovalHistory` | force-app | — | DTO: approval instance and steps |
| `AMF_ApprovalHistoryProvider` | force-app | interface | Seam: native approval history |
| `AMF_ApprovalMatrixService` | force-app | **without** | The engine |
| `AMF_ApprovalProcessProvider` | force-app | interface | Seam: the active process catalogue |
| `AMF_ApproverScope` | force-app | without | Who a user may act for on a Classic approval |
| `AMF_Ast` | force-app | — | AST nodes and value types |
| `AMF_ClassicApprovalHistoryProvider` | force-app | without | `ProcessInstance` reader |
| `AMF_ClassicApprovalProcessProvider` | force-app | without | `ProcessDefinition` reader |
| `AMF_ClassicProcessStrategy` | force-app | inherited | The only `Approval.process()` caller |
| `AMF_CmdtRuleProvider` | force-app | with | SOQL rule provider |
| `AMF_ConfigValidator` | force-app | without | Post-deploy validator and invocable |
| `AMF_ConfigurationException` | force-app | — | Configuration findings |
| `AMF_DecisionExplainer` | force-app | with | Explanations and briefings |
| `AMF_DecisionLogWriter` | force-app | without | Builds and inserts log rows |
| `AMF_DecisionTimelineService` | force-app | with (without-sharing inner reader) | The timeline |
| `AMF_DraftRuleProvider` | force-app | with | The live matrix with one change |
| `AMF_EinsteinExplanationGenerator` | force-app | with | Einstein explanation generator |
| `AMF_EinsteinPromptRunner` | force-app | with | Einstein prompt runner |
| `AMF_Evaluator` | force-app | — | Evaluates a compiled expression |
| `AMF_ExplanationException` | force-app | — | No explanation could be given |
| `AMF_ExplanationGenerator` | force-app | interface | Seam: facts into words |
| `AMF_ExprCache` | force-app | — | Per-transaction compile cache |
| `AMF_ExprCompiler` | force-app | — | Parse plus schema and type analysis |
| `AMF_ExpressionException` | force-app | — | Positioned expression errors |
| `AMF_FieldPathResolver` | force-app | inherited | One dynamic SOQL per object |
| `AMF_Lexer` | force-app | — | Tokeniser |
| `AMF_MatrixHealthService` | force-app | with | Health facts and summary |
| `AMF_MatrixImpact` | force-app | with | Impact of a matrix change |
| `AMF_MatrixSubmissionResource` | force-app | with (global) | REST resource |
| `AMF_Parser` | force-app | — | Recursive-descent parser |
| `AMF_PromptException` | force-app | — | A prompt could not be run |
| `AMF_PromptRunner` | force-app | interface | Seam: run a prompt template |
| `AMF_RuleBuilder` | force-app | — (`@IsTest`) | Fluent rule fixture and stub provider |
| `AMF_RuleDefinition` | force-app | — | In-memory rule; the ordering |
| `AMF_RuleDrafter` | force-app | with | Rule drafting with release checks |
| `AMF_RuleProvider` | force-app | interface | Seam: reading the matrix |
| `AMF_StrategyStub` | force-app | — (test fixture) | Recording submission stub |
| `AMF_SubmissionException` | force-app | — | Whole-call faults |
| `AMF_SubmissionStrategy` | force-app | interface | Seam: starting an approval |
| `AMF_SubmitForMatrixApproval` | force-app | with | Flow action; shared `submitEach` |
| `AMF_SubmitRequest` | force-app | — | Strategy input |
| `AMF_SubmitResult` | force-app | — | Strategy output, per record |
| `AMF_McpBriefingFacts` | mcp | with (global) | `get_briefing_facts` |
| `AMF_McpCheckImpact` | mcp | with (global) | `check_change_impact` |
| `AMF_McpCheckRuleDraft` | mcp | with (global) | `check_rule_draft` |
| `AMF_McpDecisionFacts` | mcp | with (global) | `get_decision_facts` |
| `AMF_McpFactsOnly` | mcp | with | Explanation generator that returns the facts |
| `AMF_McpFindRecord` | mcp | with (global) | `find_record` |
| `AMF_McpHealthFacts` | mcp | with (global) | `get_health_facts` |
| `AMF_McpMyApprovals` | mcp | with (global) | `list_my_approvals` |
| `AMF_McpMyRequests` | mcp | with (global) | `list_my_requests` |
| `AMF_McpPreviewRoute` | mcp | with (global) | `preview_route` |
| `AMF_McpRuleContext` | mcp | with (global) | `get_matrix_context` |
| `AMF_McpSubmitRoute` | mcp | with (global) | `submit_for_approval` |
| `AMF_McpSupport` | mcp | with | References, links, the preview token |
| `AMF_McpWhatIfRoute` | mcp | with (global) | `what_if_route` |

## Appendix B: Phase history

| Phase | Delivered | Gate | Commit |
|---|---|---|---|
| M0 | Baseline: the guard on `Purchase_Request__c`; the v1.0 metadata retired | All green | `9a54e68`, `6ccc2ed` |
| M1 | `Approval_Matrix_Rule__mdt`, the immutable decision log, the SOQL provider and its >255-character pin | 20/20 | `26a157f` |
| M2 | The expression evaluator, reduced grammar | 108/108; evaluator at 100% | `ce47137` |
| M3 | Engine, Classic strategy, two templates, the submit action (the MVP) | 141/141; manual QA 2026-09-18 | `d13241f` |
| M4 | Configuration validator, source gate, post-deploy script | 166/166 | `9893274` (+ M4.1) |
| M5 | Preview and the confirmation modal | 175/175; 23/23 Jest | `5b99045` |
| M6 | Flow approvals spike, research only (`spikes/flow-approvals/`) | Launch and recall proven; unanimous value open | `972352a` |
| M7 | Decision timeline (Classic) | Org gate 2026-10-08; 57/57 Jest | `25e0b2d` |
| M8 | Guard integrity: recall clears the guard; a pending record is refused | 197/197 | `caeafb3` |
| M9 | The full §4.1 grammar | 232/232; evaluator at 100% | `a79c880` |
| M10 | Flow action and REST over `submitEach()`; chunked, isolated submission; the log after the platform answers | 255/255 | `393d9d5` (+ M10.7, M10.8) |
| M11 | Opportunity, a second governed object, by configuration | 264/264 | `96e5692` |
| M12 | Template lifecycle (release manifest), queue and committee templates, portability; M12.6 timeline fixes; M12.8 Request Name | 274/274 | `bcedf6f` (+ `72f4dfd`, `0049677`, `c59e758`) |
| M13 | The Approval Matrix Assistant; plain-English explanations | 334/334; 75/75 Jest; 9/9 agent cases | `e81f487` |
| M14 | What-if, my requests, my approvals, briefings; the current approver sees why | 371/371; 14 cases, 42/42 twice | `74ea4ed` |
| M15 | The Admin Assistant: drafting, impact, health | 404/404; 6 cases, 18/18 twice | `11941dc` |
| M16 | The Claude connector: two Hosted MCP Servers and a signed preview token | 451/451; REST smoke test; MCP probe on both servers (M16.7) | `a035bdb` (+ `72ad84f`) |

## Appendix C: Repository map

```
CLAUDE.md                     what is authorised; conventions; environment
sfdx-project.json             four package directories; sourceApiVersion 66.0; the username replacement
.forceignore                  keeps the MCP server definitions out of project deploys
config/
  template-releases.json      the release manifest (fingerprints)
  project-scratch-def.json
docs/
  functional-documentation.md, technical-documentation.md, user-guide.md   this documentation set
  architecture.md             v3.0 target design, with each phase's implementation notes
  build-playbook.md           phase plan and gates; Part 5 is a proposed roadmap
  technical-log.md            status board; one detailed entry per phase
  decisions.md                one line per approved deviation
  handoff.md                  the project's state, for a new person or session
  claude-connector.md         Claude connector guide
  spike-results.md            Flow approvals spike (M6)
  ui-tests/                   UI test script for an AI browser agent, and its guide
force-app/main/default/
  approvalProcesses/          six Classic templates
  classes/                    54 classes and their tests
  customMetadata/             the matrix: nine rule rows (eight active)
  customPermissions/          AMF_Bypass_Log_Lock, AMF_Test_Refuse_Guard
  flexipages/                 Purchase Request and Opportunity record pages
  layouts/                    Purchase Request and decision log layouts
  lwc/                        six components and their Jest tests
  objects/                    Purchase_Request__c, Approval_Decision_Log__c, Approval_Matrix_Rule__mdt, Opportunity guard
  permissionsets/             Approval_Matrix_User, Approval_Matrix_Admin
  quickActions/, tabs/, workflows/
agentforce/main/default/
  aiAuthoringBundles/         AMF_Approval_Assistant, AMF_Matrix_Admin_Assistant
  genAiPromptTemplates/       three Flex prompt templates
mcp/main/default/
  classes/                    14 AMF_Mcp* classes and their tests
  mcpServerDefinitions/       AMFApprovalMatrix, AMFApprovalMatrixAdmin (deployed by script at 67.0)
  objects/                    AMF_Mcp_Settings__c
  permissionsets/             the two connector permission sets
org-config/amf-dev/main/default/
  layouts/, objects/          Opportunity's layouts, object settings, Matrix Opportunities list view
  permissionsets/             the two agent-access sets
  aiEvaluationDefinitions/    the two Testing Center definitions
  externalClientApps/, extlClntApp*/   the Claude connector's External Client App
scripts/                      gate, validator, seed, publish, connector setup, probe, live checks
specs/                        Testing Center specs for both agents
spikes/flow-approvals/        M6 research artefacts (never deployed with the product)
```
