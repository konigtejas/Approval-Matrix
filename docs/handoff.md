# Handoff — the Approval Matrix Framework, in full, after M15

**As of 2026-10-24.** `develop` is at `f316c78`, pushed to `origin`
(github.com/konigtejas/Approval-Matrix). Every phase through M15 is built, gated in `amf-dev` and
committed. Three manual UI checks are owed by the user (section 8). Nothing beyond M15 is authorised.

This is the detailed handoff. It is meant to let a person, or a fresh Claude session, pick the
project up with no conversation history. Where it summarises, these are the sources:

| Source | What it holds |
|---|---|
| `CLAUDE.md` | What is authorised, the conventions, the environment. A fresh session reads it first: it decides what may be built |
| `docs/architecture.md` | v3.0, the target design, with each phase's implementation notes in the sections they touch. §13.4 is the phase table |
| `docs/build-playbook.md` | Part 3: every phase's build and gate. Part 5: the proposed roadmap, which authorises nothing |
| `docs/technical-log.md` | The status board, and a detailed entry per phase, each ending with the items it carries forward. M15.6 is the latest such table |
| `docs/decisions.md` | One line per approved choice or deviation from the design, newest first |
| `docs/spike-results.md` | The Flow approvals spike (M6). Its Round 2 binds any future Flow phase |
| `docs/ui-tests/` | The UI test suite, a script for an AI agent driving a browser, and the guide for whoever runs it |

**Reading order for a fresh session:**
1. `CLAUDE.md`;
2. this file;
3. the technical log's status board and its M15 entry, especially M15.6;
4. the playbook's Part 3 entry for the phase being worked on.

## Contents

1. At a glance
2. What the framework is
3. Phase history
4. The AI layer in detail
5. Access and permissions
6. The org, `amf-dev`
7. How to work on it
8. Owed by the user: the manual UI checks
9. Open items and known limits
10. What remains of the target design
11. Decisions waiting on the user
- Appendix A: every agent action
- Appendix B: the agent test cases
- Appendix C: the Apex classes, by layer
- Appendix D: Ids

---

## 1. At a glance

- **What it is.** A Salesforce DX framework that chooses which native approval process a record
  enters. Routing rules live in Custom Metadata. They are tried in priority order, and the first
  whose condition is true names the process. The engine submits the record to that process and
  writes an immutable decision log row saying why.
- **What is built:**
  - M0 to M3, the MVP;
  - M4 to M12, its hardening: the validator, the preview modal, the timeline, the guard's
    integrity, the full grammar, the Flow and REST entry points, a second object, and the template
    lifecycle;
  - M13 to M15, three AI phases.
- **The test position at the end of M15:**
  - 404/404 Apex tests in 43 test classes, at 97% org-wide coverage;
  - 75/75 Jest tests in 5 suites;
  - two Testing Center suites, 14 cases (42/42 assertions) and 6 cases (18/18), each passed twice
    in a row.
- **What is in `amf-dev`:**
  - two Agentforce employee agents, the Approval Matrix Assistant (v7) and the Approval Matrix
    Admin Assistant (v1);
  - three Einstein prompt templates.
- **Owed by the user:** three manual checks in the browser, one each from M13, M14 and M15
  (section 8).
- **What is next:** nothing is authorised. The largest part of the target design still unbuilt is
  Flow approvals (section 10.1).

---

## 2. What the framework is

### 2.1 The design principles (architecture §1)

1. **Configuration over code.** Routing lives in Custom Metadata. A new or changed rule is a
   configuration release, never an Apex change.
2. **Select, don't resolve.** The framework picks a process. Who approves, in how many steps, and in
   what order belongs to the approval process (the "template"), not to the engine.
3. **Explain every decision.** Native approval history says who and when. The decision log says
   why, and it is immutable.
4. **Fail loudly.** A malformed rule fails at release. A runtime evaluation error blocks the record
   and is logged; it never falls through to another rule. A stopped approval is recoverable, and a
   misrouted one is an audit finding.
5. **Testable and portable.** All rule access goes behind `AMF_RuleProvider`, and all submission
   behind `AMF_SubmissionStrategy`. `force-app` deploys to another org with no code change.
6. **AI assists; it never decides** (M13, extended in M14 and M15). The engine selects every route,
   and the platform runs every approval. AI may:
   - explain recorded decisions;
   - brief the approver an approval is waiting on;
   - answer what-ifs through the engine;
   - draft a rule that routes nothing until an administrator releases it through the gate.

   It never chooses a route, evaluates a rule, writes a rule or a log row, approves anything, or
   tells an approver what to decide. Generated text is presentation: it is labelled, generated on
   demand, and never stored.

### 2.2 How a submission flows (architecture §6.1, `AMF_ApprovalMatrixService`)

1. Authorise: the caller must be able to read the record (`UserRecordAccess`). The service runs
   without sharing, so it checks this itself.
2. Refuse a record that is already in an approval process, by name, with no log row (M8).
3. Load the object's active rules through `AMF_RuleProvider`. An object with none is not governed.
4. Order the rules by priority, then DeveloperName, and compile each once through `AMF_ExprCache`.
   A rule that will not compile stops the whole call.
5. Read every field path all the rules need in one SOQL query (`AMF_FieldPathResolver`).
6. Per record, the first rule whose condition is true wins. If none is true, the record is
   `Blocked_No_Match`: it is blocked and a row is written, never routed by default.
7. Resolve the process the winning rule names. **A preview stops here.**
8. Set the guard, `Matrix_Submission__c = true`, record by record.
9. Submit through `AMF_ClassicProcessStrategy`, in chunks of at most 100, without all-or-nothing.
10. Write the decision log row once the platform has answered, with `Execution_Ref_Id__c`, the
    `ProcessInstance` Id. A record the platform refuses gets a `Failed` row carrying the platform's
    reason, and its guard is cleared again.

There are two contracts over this one path:
- `submit()` and `preview()` answer for the whole call. The header button uses them.
- `submitEach()` answers record by record (M10). The Flow action, REST and Apex callers use it.
  `previewWith()` (M14) and `previewEach()` (M15) are previews only; section 4.5 describes them.

**The guard (§6.3).** Every governed object has a Checkbox, `Matrix_Submission__c`. Each template's
only entry criterion is that checkbox. Templates clear it on final approval, rejection and recall.
A submission that bypasses the engine therefore fails the template's entry criteria. The source gate
enforces all of this.

### 2.3 The parts

| Part | Where | What it does |
|---|---|---|
| Rules | `Approval_Matrix_Rule__mdt` | `Object_API_Name__c`, `Priority__c`, `Expression__c` (long text, 2,000), `Process_API_Name__c`, `Description__c` (text, 255), `Version__c`, `Active__c` |
| Rule access | `AMF_RuleProvider`, `AMF_CmdtRuleProvider` | The only way code reads the rules. By SOQL, never `getAll()`, which truncates long text; a test pins that |
| Evaluator | `AMF_Lexer`, `AMF_Parser`, `AMF_Ast`, `AMF_ExprCompiler`, `AMF_ExprCache`, `AMF_Evaluator`, `AMF_FieldPathResolver` | The §4.1 grammar: `&&` `\|\|` `!` and AND/OR/NOT; `==` `!=` `>` `>=` `<` `<=`; `IN`/`NOT IN`; `CONTAINS`, `STARTS_WITH`; multipicklists; `TODAY(±n)`; paths up to four segments. DateTime fields and literals are still refused |
| Engine | `AMF_ApprovalMatrixService` | `submit`, `preview`, `submitEach`, `previewWith` (M14), `previewEach` (M15) |
| Strategy | `AMF_SubmissionStrategy`, `AMF_ClassicProcessStrategy` | The only code that calls `Approval.process()` |
| Decision log | `Approval_Decision_Log__c`, `AMF_DecisionLogWriter` | One immutable row per decided attempt: rule and version, the expression as evaluated, the values read (JSON), the process, the outcome (`Submitted`, `Blocked_No_Match` or `Failed`), the reason, who and when. The `Lock_Decision_Log` validation rule blocks edits; the `AMF_Bypass_Log_Lock` custom permission excepts. Lookups to `Purchase_Request__c` and `Opportunity__c` |
| Guard | `Matrix_Submission__c` on `Purchase_Request__c` and `Opportunity` | Section 2.2 |
| Templates | `force-app/main/default/approvalProcesses` | Six Classic approval processes (section 2.4). Released versions are fingerprinted in `config/template-releases.json`, and an in-place edit fails the gate (M12). Users are named `<alias>@{{AMF_USERNAME_DOMAIN}}`, filled at deploy |
| Validator | `AMF_ConfigValidator`, `scripts/validate-config.apex` | After deploy: every expression compiles, priorities are unique per object, every governed object has the guard, every named template is active, and each object's union query runs |
| Source gate | `scripts/validate-approval-matrix-source.ps1` | Before deploy: entry criteria, the guard cleared on every way out, the release manifest, no literal username, no standard Submit button on a governed object's layout, no standard-object configuration in `force-app` |
| Submit UI | `AMF_Submit_For_Approval` quick actions, `amfSubmitForApproval`, `amfSubmitPreview` | Header button, then a preview modal, then confirm, then submit. The standard Submit for Approval button is removed from every governed layout |
| Timeline | `amfDecisionTimeline`, `amfDecisionTimelineEntry`, `amfDecisionExplanation`, `AMF_DecisionTimelineService` | On `Purchase_Request_Record_Page` and `Opportunity_Record_Page`. One entry per attempt, newest first, at most 50. Each decision joins its native Classic history. The Explain button is on entries with a decision |
| Entry points | `AMF_SubmitForMatrixApproval` (Flow), `AMF_MatrixSubmissionResource` (REST) | The invocable "Submit for Matrix Approval". REST is `POST /services/apexrest/approval-matrix/v1/submissions` with `{"recordIds": [...]}`, at most 200 |
| AI | `agentforce/`, the `AMF_Agent*` classes and others | Section 4 |

### 2.4 Governed objects, rules and templates

**Purchase Request** (`Purchase_Request__c`, the framework's own object). Its name is an
auto-number, `PR-{00000000}`. Its fields are:
- `Amount__c` (currency);
- `Region__c` (APAC, EMEA, AMER);
- `Risk_Level__c` (Low, Medium, High);
- `Vendor_Type__c` (New, Existing, Strategic);
- `Account__c` (lookup);
- `Request_Name__c` (text, M12.8);
- the guard.

`AMF_Test_Refuse_Guard` is a validation rule that exists only for a test (decisions, 2026-10-21).

**Opportunity** (M11), governed by configuration alone. Its four layouts and its object settings
are `org-config/amf-dev`'s.

The rules in `amf-dev`, all at version 1:

| Rule | Object | Priority | Condition | Process |
|---|---|---|---|---|
| `PR_Committee_Spend` | Purchase Request | 5 | `Amount__c >= 1000000` | `PR_Finance_Committee` |
| `PR_High_Value_APAC` | Purchase Request | 10 | `Amount__c > 100000 && Region__c == 'APAC'` | `PR_Three_Level_Finance` |
| `PR_High_Risk` | Purchase Request | 20 | `Risk_Level__c == 'High'` | `PR_Three_Level_Finance` |
| `PR_Credit_Risk_Review` | Purchase Request | 30 | `Risk_Level__c == 'Medium' && Amount__c >= 50000` | `PR_Credit_Risk_Queue` |
| `PR_Long_Expression_Pin` | Purchase Request | 9998 | a long OR of six clauses; **inactive**, a test fixture for the >255-character round trip | `PR_Two_Level_Mgmt` |
| `PR_Catch_All` | Purchase Request | 9999 | `TRUE` | `PR_Two_Level_Mgmt` |
| `OPP_Large_Deal` | Opportunity | 10 | `Amount >= 250000` | `OPP_Two_Level_Mgmt` |
| `OPP_Key_Industry` | Opportunity | 20 | `Account.Industry IN ('Energy', 'Banking')` | `OPP_Two_Level_Mgmt` |
| `OPP_Catch_All` | Opportunity | 9999 | `TRUE` | `OPP_Manager_Approval` |

The templates:

| Template | Shape |
|---|---|
| `PR_Two_Level_Mgmt` | two steps up the submitter's manager hierarchy |
| `PR_Three_Level_Finance` | three named users: `amfu3`, then `amfu4`, then `amfu5` |
| `PR_Credit_Risk_Queue` | the `Q_Credit_Risk` queue; any member decides |
| `PR_Finance_Committee` | `amfu1` to `amfu3` unanimously, then `amfu4` or `amfu5` |
| `OPP_Two_Level_Mgmt` | two levels of the submitter's manager hierarchy |
| `OPP_Manager_Approval` | the submitter's manager |

### 2.5 The three package directories

| Directory | Holds | Deploys to |
|---|---|---|
| `force-app` | the framework: objects, rules, templates, Apex, LWC, pages, permission sets | any org |
| `agentforce` | the two agents' authoring bundles and the three prompt templates | only an org with Einstein generative AI and Agentforce on |
| `org-config/amf-dev` | `amf-dev`'s own configuration: Opportunity's layouts, object settings and Matrix Opportunities list view; the two agent-access permission sets; the two Testing Center definitions | `amf-dev` only, and only after both agents are published, because the access sets and test definitions name them |

`sourceApiVersion` is 66.0, which Agent Script needs. Apex classes stay at 62.0. Engine classes must
stay at API 66 or below, because API 67 runs database operations in user mode (spike results,
Round 2).

---

## 3. Phase history

| Phase | What it delivered | Gate result | Commit |
|---|---|---|---|
| M0 | Baseline: the guard on `Purchase_Request__c`; the v1.0 metadata retired | all green | `9a54e68`, `6ccc2ed` |
| M1 | `Approval_Matrix_Rule__mdt`, the immutable decision log, the SOQL rule provider and its >255-character pin | 20/20 | `26a157f` |
| M2 | Expression evaluator, reduced grammar | 108/108, evaluator at 100% | `ce47137` |
| M3 | Engine, Classic strategy, two templates, the submit action: the MVP demo | 141/141, manual QA 2026-09-18 | `d13241f` |
| M4 | Configuration validator, source gate, post-deploy script | 166/166 | `9893274` (+ M4.1) |
| M5 | Preview and the confirmation modal | 175/175, 23/23 Jest | `5b99045` |
| M6 | Flow approvals spike, research only (`spikes/flow-approvals/`) | launch and recall proven; unanimous value open | `972352a` |
| M7 | Decision timeline LWC (Classic) | org gate 2026-10-08, 57/57 Jest | `25e0b2d` |
| M8 | Guard integrity: recall clears the guard; a pending record is refused | 197/197 | `caeafb3` |
| M9 | The full §4.1 grammar | 232/232, evaluator at 100% | `a79c880` |
| M10 | The Flow invocable and REST over `submitEach()`; chunked, isolated submission; the log written after the platform answers | 255/255 | `393d9d5` (+ M10.7, M10.8) |
| M11 | Opportunity, a second governed object | 264/264 | `96e5692` |
| M12 | Template lifecycle (release manifest), queue and committee templates, portability. M12.6: the first UI test run, two timeline fixes. M12.7: the re-run. M12.8: Request Name and two list views | 274/274 | `bcedf6f` (+ `72f4dfd`, `0049677`, `c59e758`) |
| M13 | The Approval Matrix Assistant, and plain-English explanations on the timeline | 334/334, 75/75 Jest, 9/9 agent cases | `e81f487` |
| M14 | The assistant for submitters and approvers: what-if, my requests, my approvals, briefings; current approvers see why | 371/371, 14 cases 42/42 twice | `74ea4ed` |
| M15 | The Approval Matrix Admin Assistant: draft a rule, check a change's impact, the matrix's health | 404/404, 6 cases 18/18 twice | `11941dc` |

Every phase also has a follow-up commit recording its SHA in the technical log. The handoff has its
own commits.

---

## 4. The AI layer in detail

### 4.1 Where it sits

The AI layer never sits inside the engine. Every route, rule, figure and approver an agent states
comes from an Apex action, and every action uses the engine's own paths:
- `preview()`, `previewWith()` and `previewEach()`, which write nothing;
- M10's `submitEach()`, the only path that submits.

Generated text is presentation, and nothing generated is stored. Both agents are **employee**
agents. They run as the logged-in user, so every action has that user's access and nothing more.

### 4.2 The Approval Matrix Assistant (`AMF_Approval_Assistant`, v7 active)

**Who it is for:** submitters and approvers, on Purchase Requests and Opportunities.

**Structure** (`agentforce/main/default/aiAuthoringBundles/AMF_Approval_Assistant/`):

| Part | Label | What it handles |
|---|---|---|
| `approval_router` | (the platform reports it as `topic_selector`) | Sends the request on. It never asks which record is meant: the subagents can see the record on screen. It answers approve, reject, recall or reassign requests itself, with a refusal |
| `route_and_submit` | Preview and Submit | Where a record *would* go, which rule would decide it, what-ifs, and submitting |
| `explain_decision` | Explain or Brief | Why a record *already* went where it did, where its approval stands, and a briefing before the approver decides ("brief me") |
| `my_work` | My Requests and Approvals | The two lists: the user's own requests, and what is waiting for the user. Also a briefing on an approval it has just listed |

**Variables:**
- `currentRecordId` and `currentObjectApiName`, the page context, with `visibility: "External"`;
- `previewed_record_id`, `previewed_process` and `can_submit`.

**What it can do,** each through one action (Appendix A has every input and output):
- **find a record** by its number, name or Id, among governed objects the user can read;
- **preview the route:** the process, the rule and its priority, and the values it read. "Nothing
  has been submitted yet";
- **submit**, only the record it has just previewed, and only after the platform asks the user to
  confirm. Its record and expected process are bound from the preview by the runtime, never filled
  in by the model. If the route changed since the preview, it says so;
- **what-if:** "where would this go if the amount were 120,000?" The engine answers with the changed
  values in memory, and nothing is changed. A field no rule reads is said to make no difference. A
  what-if clears `can_submit`, so a later "submit it" starts from a fresh preview of the record's
  real values;
- **explain** the newest decision on a record, in plain English;
- **brief** the user on an approval waiting on them (section 4.3);
- **list my requests:** the user's own decisions of the last 90 days, newest attempt per record,
  those still waiting first, at most 10 listed;
- **list my approvals:** pending work assigned to the user, to their queues and groups, or to
  someone they are delegated approver for. Governed, readable records only, oldest first, at most 10.

**What it refuses:**
- approving, rejecting, recalling or reassigning, because the approvers decide in the approval itself;
- changing records or rules;
- anything off-topic.

**Example answers from the M14 gate:**
- "What if PR-00000047 had an amount of 120000 and region APAC?" → `PR_Three_Level_Finance` under
  `PR_High_Value_APAC`, "Today … `PR_Two_Level_Mgmt` under rule `PR_Catch_All`. This is only a
  what-if."
- "Is anything waiting for my approval?" (with a throwaway reassigned to the user) → "One request is
  waiting on you … PR-00000050 … step "Manager" …"

**Unobserved until the manual check (section 8):**
- whether the Lightning panel passes the open record to the agent as `currentRecordId` and
  `currentObjectApiName`, as Testing Center does;
- how the panel renders submit's confirmation. The platform asks, and the instructions also tell
  the agent to ask, so the user might be asked twice.

### 4.3 Explanations, briefings and the current-approver rule

**The Explain button (M13).** It sits at the top of each timeline entry that has a decision.
`AMF_DecisionExplainer` writes the entry out as plain-text facts:
- the row's own snapshot: rule, version, condition, values under their field labels, process,
  outcome and recorded reason;
- the native approval steps the timeline shows.

The `AMF_Explain_Approval_Decision` template explains those facts and nothing else. The card has an
*AI-generated* badge, names its decision log row and time, and has a "write it again" icon. The
recorded facts stay below it. It is never stored, and it is put away when the approval moves on. A
failure says why: Einstein unavailable, the template missing, or the reader without Prompt Template
User.

**Briefings (M14).** `AMF_DecisionExplainer.briefLatest()` is the same facts with one more line:
"Reader: <name>, the approver this approval is waiting on now". It asks the approver's question:
what is asked, why it was routed there, the values, what has happened so far, "do not tell me
whether to approve or reject it".

It runs only for the person the approval is waiting on. Anyone else is told: "<record> is not
waiting on you for approval, so there is nothing for you to decide."

**The current-approver rule (M14, the user's choice).** M7's timeline showed an approver every
approval on a record they can read. But it showed the *routing reason* only where they could read
the log row, which for an `Approval_Matrix_User` meant never for someone else's submission. Now:
- the person a pending approval is waiting on sees that approval's row;
- it is read for them without sharing, and flagged `visibleAsApprover`;
- this lasts only while the approval waits on them, and changes no other row and no other user.

"Waiting on them" is `AMF_ApproverScope`. A pending step counts when it is assigned to:
- the user;
- a queue or public group that contains them, following nested groups to depth 5;
- a user who names them as `DelegatedApproverId`.

Queue members that are roles are not followed. The timeline, the Explain button, the assistant's
explanations, briefings and "my approvals" all use this one definition.

**How a reassignment reads (M14 finding).** A `Reassigned` history row holds:
- the actor: the *new* assignee;
- the original actor: the step's *first* assignee;
- not who made the change, which is not recorded.

The facts say "reassigned to X (first assigned to Y)". M13's "reassigned by X, for Y" read to the
model the wrong way round. The timeline LWC still shows such a row as "X, for Y" (section 9).

### 4.4 The Approval Matrix Admin Assistant (`AMF_Matrix_Admin_Assistant`, v1 active)

**Who it is for:** the matrix's administrators only. Its access set is
`AMF_Matrix_Admin_Assistant_Access`, and its three actions are granted by `Approval_Matrix_Admin`
alone. **It changes nothing.** It cannot deploy, activate, edit or delete a rule, or submit or
approve anything.

**Structure** (`agentforce/main/default/aiAuthoringBundles/AMF_Matrix_Admin_Assistant/`):

| Part | Label | What it handles |
|---|---|---|
| `admin_router` | (`topic_selector`) | Sends the request on. It refuses deploy, activate, edit, submit or approve requests |
| `draft_rule` | Draft a Rule | A new rule, or a new version of an active rule, from a description |
| `check_impact` | Check a Change | What a draft, or any described change, would do to recent requests |
| `matrix_health` | Matrix Health | How the matrix has been doing |

**Variables:** `has_draft`, and the last valid draft's `draft_object`, `draft_name`,
`draft_priority`, `draft_expression` and `draft_process`. They carry a draft into the impact check.
The priority is text, because the scripts use text and Boolean variables only.

**Drafting a rule** (`AMF_AgentDraftRule` over `AMF_RuleDrafter`):
1. **The context.** The model is given:
   - the administrator's words;
   - the object's rule-readable fields, with up to 25 picklist values each and their relationship
     names;
   - the object's active rules in priority order, with conditions and descriptions;
   - the object's active approval processes;
   - every name active rules already use.

   The `AMF_Draft_Matrix_Rule` template carries the §4.1 grammar in plain words and asks for one
   JSON object only. No record is read.
2. **The checks, before anyone sees the draft.** They are the release gate's:
   - the condition compiles against the object;
   - the DeveloperName is valid: a letter first, single underscores, at most 40 characters;
   - the name is new, or is the name of the rule being changed;
   - the priority is a whole number from 1 to 9999 that no other active rule on the object uses;
   - the process is an active Classic process for the object;
   - the description has at most 255 characters and the condition at most 2,000;
   - the engine's union query, with the draft in the matrix, runs.
3. **Failures go back to the model once, with the reasons.** If the second answer fails too, the
   administrator gets "No draft could be written that passes the checks …" with each reason, and no
   rule.
4. **A valid draft comes back with:**
   - a plain summary, including where the rule sits in the priority order ("tried after
     PR_High_Value_APAC (10) and before PR_High_Risk (20)");
   - the model's assumptions;
   - the file path, `force-app/main/default/customMetadata/Approval_Matrix_Rule.<Name>.md-meta.xml`;
   - the Custom Metadata file itself, in the repository's format;
   - for a change, version = live version + 1.
5. **Known limit.** The name is checked against *active* rules only, because `AMF_RuleProvider`
   exposes no others. Releasing a draft whose name matches an inactive rule would overwrite that
   rule, and the file name shows this in review.

**Releasing a draft** is the administrator's job, as an ordinary configuration release:
1. save the metadata at the file path;
2. run the source gate;
3. deploy;
4. run `scripts/validate-config.apex`;
5. commit.

The assistant never does any of these.

**Checking a change's impact** (`AMF_AgentCheckImpact` over `AMF_MatrixImpact`):
- **The change can be:**
  - a new rule (Add, version 1);
  - a new version of an active rule (Replace; blank fields keep the live rule's, and the version is
    one more than the live one);
  - taking a rule out (Deactivate).
- **Left blank,** the change is worked out: a new name is an Add, an active name with a condition is
  a Replace, and an active name without one is a Deactivate.
- **The method.** The object's records with a decision in the last 90 days, newest first, at most
  200, are previewed by `previewEach()` twice. Once is under the live matrix, and once under
  `AMF_DraftRuleProvider`'s matrix with the change applied in memory. Both use the records' values
  *today*, because a log row records only what its deciding rule read.
- **What it reports:**
  - how many were checked;
  - how many would be decided differently, by another rule or to another process, with up to 10
    listed;
  - per-process counts before and after;
  - how many were skipped, because they are in an approval process now or the admin cannot read
    them.
- **If the change leaves the matrix unable to decide** (for example, taking out the only rule), the
  report says so, with the engine's reason.
- **No model takes part, and nothing is written.**

**The health report** (`AMF_AgentMatrixHealth` over `AMF_MatrixHealthService`):
- **What Apex counts, into plain-text facts:**
  - per governed object, decisions by outcome, for the period (30 days by default) and the period
    before;
  - each rule's share of routed decisions;
  - the catch-all's share, where a catch-all is a rule whose recorded condition is `TRUE`;
  - active rules that routed nothing;
  - the three commonest failure reasons;
  - pending approvals per process, with the oldest's age.
- **The summary.** The `AMF_Summarize_Matrix_Health` template summarises those facts alone.
- **The facts are always returned,** so a report stands even when Einstein cannot summarise.

**Example answers from the M15 gate:**
- **The draft:** "Draft rule PR_EMEA_Over_500k (new, version 1) for Purchase Requests: when
  `Amount__c > 500000 && Region__c == 'EMEA'`, send the record to approval process
  `PR_Finance_Committee`. Priority 15 …"
- **The draft's impact:** "Checked 16 Purchase Requests decided in the last 90 days, on their
  values today. None of them would be decided differently … 7 were skipped …"
- **Health:** the log's real figures, Purchase Request 25 decisions (24 routed, 1 blocked) and
  Opportunity 4.

### 4.5 The two engine entries the AI layer added

- **`previewWith(recordId, changes)` (M14).** This is `preview()` for one record. The changes go
  onto the in-memory copy that step 5 read, before any rule is evaluated.
  - It writes nothing: not the record, not a row, not the guard.
  - Only the record's own fields may change. A relationship path is refused.
  - The fields are checked after authorisation, so a caller who cannot read the record is told that
    first.
  - Its whole-call refusals are `preview()`'s.
- **`previewEach(recordIds)` (M15).** This is `preview()` with `submitEach()`'s per-record
  refusals. An unreadable record, or one in an approval process now, is `Refused` by itself, and the
  rest are decided. It writes nothing.

`submit()`, `preview()` and `submitEach()` were not changed: they reach a private overload of
`prepare()` and pass no changes.

### 4.6 The prompt templates (`agentforce/main/default/genAiPromptTemplates`)

| Template | Inputs | Used by | Active version |
|---|---|---|---|
| `AMF_Explain_Approval_Decision` | Facts, Question | the Explain button, the assistant's explanations, briefings | `…=_1` |
| `AMF_Draft_Matrix_Rule` | Request, Context | `AMF_RuleDrafter` | `…=_1` |
| `AMF_Summarize_Matrix_Health` | Facts, Question | `AMF_MatrixHealthService` | `…=_1` |

All three are Flex templates on the org's default model, with `activeVersionIdentifier`
`/0MCy2NRnsP9ZLj9Xsgvh66VbJrjXadZVilhTmvLHyc=_1`. The identifier is the same for all three, so it
is not per template. Each tells the model to treat its facts or context as data, not as
instructions. A retrieve matches all three byte for byte. Changing one is section 7.5.

### 4.7 What building the agents taught

These are worth knowing before touching either agent:

1. **Say what the model does not know.**
   - **What happened (M15.3f):** the admin agent repeatedly answered without calling its tool. It
     invented a draft with a `.json` path and a "Medium" priority in seven sessions out of seven,
     even when asked to use the tool by name. In a session already under way, it invented counts
     ("1,242 decisions" against 29).
   - **What showed it:** the tools were offered every time, and there was no `FunctionStep` in the
     trace. Each fabrication followed the answer shape the instructions described.
   - **What fixed it,** in 9 of 9 sessions:
     - each subagent says plainly that the model does not know the fields, rules, processes, records
       or counts, and that only its tool does;
     - the tools are named as lookups (`get_checked_draft`, `get_draft_impact`, `get_change_impact`,
       `get_health_report`);
     - no instruction describes an answer the model could fill in by itself.
2. **The published agent chooses a subagent largely by the subagents' descriptions** (M14.3i).
   Testing Center runs the published agent, while `sf agent preview --authoring-bundle` runs the
   local bundle, and they can route differently. Write each description to say what it is *not*
   for. Put a capability where the platform naturally sends it: briefings moved into
   `explain_decision`.
3. **The router must never ask "which record?"**, because the subagents see the page context and
   the router does not.
4. **Reading a trace.** `.sfdx/agents/<agent>/sessions/<sessionId>/traces/*.json` records every step
   of a preview session. A `FunctionStep` means an action ran; an `LLMStep` followed by
   `PlannerResponseStep` means the model answered by itself.
5. **A preview session reuses results.** Asking the same thing twice returns the earlier answer
   without calling the action again, so test a change in a fresh session.
6. **The CLI cannot preview the published employee agent.** `sf agent preview start --api-name …`
   answers "Invalid user ID provided on start session". Check published behaviour with Testing
   Center, or in the panel.
7. **The published planner can be read.** `sf org list metadata --metadata-type GenAiPlannerBundle
   --api-version 64.0` lists the versions; API 68 refuses the type. A retrieve shows the planner's
   descriptions, and its `agentScript/*_definition.agent` is the source, base64-encoded.
8. **Approver names from the running transaction.** `Actor.Name`, `SubmittedBy.Name` and
   `LastActor.Name` can read null on approval rows created in the same transaction. Name people by
   Id (`AMF_AgentSupport.actorNamesOf()`).
9. **Platform guardrails.** Testing Center's built-in Reverse_Engineering guardrail declined
   "Which rule applies to this request?" until the instructions said the rules are business data
   (M13.7e).
10. **Descriptions are capped at 255 characters** on a prompt template and a permission set, and one
    over the limit rolls back the whole deploy.

---

## 5. Access and permissions

### 5.1 The permission sets

| Permission set | Where | Grants |
|---|---|---|
| `Approval_Matrix_User` | `force-app` | Submitters and approvers. Their own log rows, read-only; the guard read-only; class access to 13 classes: the engine, the timeline, the explainer, the Flow action, REST, and the eight assistant actions (Find, Preview, Submit, What-If, Explain, Brief, My Requests, My Approvals) |
| `Approval_Matrix_Admin` | `force-app` | Administrators. View All on the log, with Modify All deliberately withheld so rows cannot be deleted; the guard editable; the same 13 classes plus `AMF_ConfigValidator` and the three admin actions (Draft, Check Impact, Health): 17 in all |
| `AMF_Approval_Assistant_Access` | `org-config/amf-dev` | Opens the Approval Matrix Assistant in the Agentforce panel (`agentAccesses`) |
| `AMF_Matrix_Admin_Assistant_Access` | `org-config/amf-dev` | Opens the Admin Assistant. For administrators only |
| Access Agentforce Default Agent (`CopilotSalesforceUser`) | standard | The Agentforce panel itself. Needs the Agentforce (Default) licence |
| Prompt Template User (`EinsteinGPTPromptTemplateUser`) | standard | Running the prompt templates: explanations, briefings, drafts, health summaries. Needs the Einstein Prompt Templates licence |

### 5.2 To give someone access

- **A submitter or approver:**
  - `Approval_Matrix_User`;
  - Access Agentforce Default Agent and Prompt Template User, with their licences;
  - `AMF_Approval_Assistant_Access`.
- **An administrator:**
  - `Approval_Matrix_Admin`;
  - the same two standard sets and licences;
  - `AMF_Approval_Assistant_Access` and `AMF_Matrix_Admin_Assistant_Access`.
- **With the CLI**, for another user add `--on-behalf-of <username>`:

  ```powershell
  sf org assign permsetlicense --name EinsteinGPTCopilotPsl --name EinsteinGPTPromptTemplatesPsl -o amf-dev
  sf org assign permset --name Approval_Matrix_Admin --name CopilotSalesforceUser --name EinsteinGPTPromptTemplateUser --name AMF_Approval_Assistant_Access --name AMF_Matrix_Admin_Assistant_Access -o amf-dev
  ```

  Assign the licences first if the CLI refuses a permission set for want of one.
- **After assigning,** the user signs out and in again.
- **Approvers.** An approver must be able to read the record, and must hold a licence that includes
  the object (§11).

### 5.3 Who has what in `amf-dev` (2026-10-24)

| User | Profile | Framework access | AI access |
|---|---|---|---|
| Tejas Vernekar (`tejas.vernekar.0d104ca05e80@agentforce.com`), the CLI user | System Administrator | `Approval_Matrix_Admin` | both licences, both standard sets plus their Admin and Manager sets, both agent-access sets |
| Grok Bot (`tejas.vernekar@wissen.com.grokbot`), the UI suite's user | System Administrator | `Approval_Matrix_Admin` | none |
| Pallab Saikia (`pallab.saikia@wissen.com.dev02`), created 2026-10-23 | System Administrator | none | none. The user chose to leave it as it is |
| AMF Approver One to Five (`amfu1`–`amfu5@amf.00daj000012gj9b.dev`) | Standard Platform User | `Approval_Matrix_User` | none |
| AMF Framework Service (`amfsvc@…`) | Standard Platform User | none | none |

Licences: Agentforce (Default) 1 of 5 used; Einstein Prompt Templates 1 of 5,000 used.

---

## 6. The org, `amf-dev`

### 6.1 Connection

| | |
|---|---|
| Alias | `amf-dev` |
| Type | Developer Edition, API 68.0 (Winter '27) |
| URL | `https://orgfarm-e5ccbd7218-dev-ed.develop.my.salesforce.com` |
| Username domain for templates | `amf.00daj000012gj9b.dev` (`AMF_USERNAME_DOMAIN`) |
| Einstein generative AI, Agentforce | both on (Setup → Agentforce Agents). No source file turns them on, deliberately |
| Trust Layer prompt-injection and toxicity detection | **off** (an open decision, section 11) |

### 6.2 People, hierarchy, queues

- **Manager chain:** Tejas Vernekar and Grok Bot → AMF Approver One → Two → Three → Four → Five.
- **`Q_Credit_Risk`** (queue) contains the public group **`G_Finance_Approvers`**, which contains
  `amfu1`, `amfu2` and `amfu3`.

### 6.3 Agents and their tests

| Agent | Active | Inactive versions | Testing Center definition | Cases |
|---|---|---|---|---|
| `AMF_Approval_Assistant` | v7 | v1–v6 (permanent) | `AMF_Approval_Assistant_Tests` | 14 |
| `AMF_Matrix_Admin_Assistant` | v1 | none | `AMF_Matrix_Admin_Assistant_Tests` | 6 |

### 6.4 Records worth knowing

| Record | Id | Values | Today it routes to | Used for |
|---|---|---|---|---|
| PR-00000042 | `a02aj00000jXxdhAAC` | 60,000, AMER, Medium | (approved: two rows, the newer ADL-00000027) | the Explain check; agent test cases |
| PR-00000045 | `a02aj00000jdD8LAAU` | 60,000, AMER, Medium | `PR_Credit_Risk_Queue` via `PR_Credit_Risk_Review` (submitted and approved 2026-10-23) | agent test cases |
| PR-00000046 | `a02aj00000jdD8MAAU` | 1,200,000, AMER, Low | `PR_Finance_Committee` via `PR_Committee_Spend` | agent test cases; never submitted |
| PR-00000047 | `a02aj00000jdD8NAAU` | 5,000, EMEA, Low | `PR_Two_Level_Mgmt` via `PR_Catch_All` | agent test cases (what-ifs); never submitted |
| PR-00000048 | `a02aj00000jdD8OAAU` | 150,000, APAC, Low | `PR_Three_Level_Finance` via `PR_High_Value_APAC` | agent test cases; never submitted |
| PR-00000049 | `a02aj00000jdc3VAAQ` | M13 gate throwaway | recalled | — |
| PR-00000050 | `a02aj00000jds3RAAQ` | M14 gate throwaway, 500, AMER, Low | recalled (ADL-00000033) | — |

- **Pending approvals,** all from earlier phases, none needed by an open check:
  - PR-00000002, -03, -07, -27 and -28, in `PR_Three_Level_Finance`;
  - PR-00000005, in `PR_Two_Level_Mgmt`;
  - PR-00000006, in `PR_Three_Level_Finance`, submitted by AMF Approver One with no decision log
    row.

  The first five pre-date M8's recall fix, so check that *Matrix Submission* unticks if one is
  recalled.
- **Stray guards.** PR-00000014 to -20 and -23 to -25 carry *Matrix Submission* with no pending
  approval. They are the M6 spike's records, and the Flow phase's teardown removes them
  (`spikes/flow-approvals/scripts/teardown.ps1`).
- **The decision log has 29 rows.** Rows are permanent.

### 6.5 Take care with

- **Do not submit PR-00000045 to -48 in a demo.** The agent test cases expect their current state.
  Demonstrate on a new record.
- **Before running the assistant's suite,** make sure nothing is assigned to the CLI user: the case
  "Is anything waiting for my approval?" expects nothing. Recall any throwaway first.
- **Grok Bot's profile, permission set, manager, locale and time zone are load-bearing** for the UI
  suite (`docs/ui-tests/README.md`). Return its System Administrator profile to Standard User
  between runs, if wanted.

---

## 7. How to work on it

### 7.1 Shells and tools on this workstation

- **Run every `sf` command in PowerShell.** Under Git Bash the CLI's shim fails on the space in
  `C:\Program Files`. Git Bash is fine for git, grep and sed.
- **Run from the project root.** From anywhere else, a deploy answers "File or folder not found".
  In scripts, use `Push-Location 'C:\Users\Wissen\Desktop\Approval Matrix'`.
- **npm and node are not installed.** Run Jest through the CLI's bundled runtime:

  ```powershell
  $env:PATH = 'C:\Program Files\sf\client\bin;' + $env:PATH
  & 'C:\Program Files\sf\client\bin\node.exe' 'node_modules\@salesforce\sfdx-lwc-jest\bin\sfdx-lwc-jest'
  ```
- **Commit with `HUSKY=0`.** The husky pre-commit hook would reformat whole files.
- **`package-lock.json` is untracked.** It predates M14, and nobody has decided whether to commit or
  ignore it.

### 7.2 Deploying

**`amf-dev`.** This deploys all three directories:

```powershell
$env:AMF_USERNAME_DOMAIN = 'amf.00daj000012gj9b.dev'
sf project deploy start -o amf-dev
```

The CLI refuses a deploy that includes approval processes unless `AMF_USERNAME_DOMAIN` is set.

**A fresh org with Agentforce,** in this order, because the access sets and test definitions name
the published agents:
1. Turn on Einstein generative AI and Agentforce in Setup.
2. `sf project deploy start --source-dir force-app --source-dir agentforce`.
3. Run `scripts/validate-config.apex`.
4. Publish both agents (7.4).
5. Deploy `org-config/<org>` with that org's own configuration.
6. Assign the access sets.

**Another org without Agentforce:** `--source-dir force-app` only, with that org's
`AMF_USERNAME_DOMAIN`. The Explain button then answers that explanations are not available. Its
admin removes the standard Submit button from governed standard objects' layouts.

### 7.3 The checks, and what they should say

| Check | Command | Expect |
|---|---|---|
| Source gate | `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-approval-matrix-source.ps1` | "…passed for 8 active rule(s), 6 approval process(es) guard-checked, 6 of 6 template(s) released and unchanged, and 5 layout(s) of 2 governed object(s)…" |
| Jest | 7.1 | 75 passed, 5 suites |
| Agent scripts | `sf agent validate authoring-bundle --json --api-name <agent> -o amf-dev` | `success: true`, for each agent |
| Post-deploy | `sf apex run --file scripts/validate-config.apex -o amf-dev` | "Approval Matrix configuration is valid." (logged at ERROR level, by design) |
| All Apex | `sf apex run test -o amf-dev -l RunLocalTests -w 20 -r human` | 404 passed, about 97% coverage |
| Check-only deploy | `sf project deploy start -o amf-dev --dry-run` | 186/186 |
| One live explanation | `sf apex run --file scripts/explain-decision.apex -o amf-dev` | PR-00000042's decision, explained in two to four sentences |

A check-only deploy with `--test-level RunSpecifiedTests` needs 75% coverage on **every** class in
the package, so include each class's own suite, or it fails while every test passes (M13.3e,
M15.3d).

### 7.4 Working on an agent

- **A deploy does not change the agent people talk to.** Each publish makes a new, permanent
  version. After deploying the bundle, publish and activate:

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-agent.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-agent.ps1 -AgentName AMF_Matrix_Admin_Assistant
  ```

  The script publishes from a throwaway project, because `sf agent publish` reads only the default
  package directory. It passes `--skip-retrieve`, so no generated Bot metadata reaches source.
- **Try a change before publishing,** with the local bundle and real actions:

  ```powershell
  sf agent preview start --json --authoring-bundle AMF_Matrix_Admin_Assistant --use-live-actions -o amf-dev
  sf agent preview send --json --authoring-bundle AMF_Matrix_Admin_Assistant --session-id <id> -u "…" -o amf-dev
  sf agent preview end --json --authoring-bundle AMF_Matrix_Admin_Assistant --session-id <id> -o amf-dev
  ```

  Read the session's trace (4.7, item 4) to see whether each action ran. Live actions really submit,
  so preview a submission only on a throwaway.
- **Test the published agent:**

  ```powershell
  sf agent test create --json --spec specs/AMF_Matrix_Admin_Assistant-testSpec.yaml --api-name AMF_Matrix_Admin_Assistant_Tests --force-overwrite -o amf-dev
  sf agent test run --json --api-name AMF_Matrix_Admin_Assistant_Tests --wait 15 -o amf-dev
  ```

  The assistant's suite is the same with `AMF_Approval_Assistant`. `test create` writes the
  definition into `force-app/main/default/aiEvaluationDefinitions`. Move it to
  `org-config/amf-dev/main/default/aiEvaluationDefinitions` and remove the empty folder.
- **Run a suite twice.** Topic assertions depend on the platform's model. Correct a topic the
  platform names differently (the router is `topic_selector`) without loosening an expected outcome.
- **A new agent** needs its own access set in `org-config`, deployed after the first publish, and
  its actions granted in a permission set.

### 7.5 Changing a prompt template

New content makes a new version, which Einstein does not use until the source names it:
1. deploy;
2. retrieve the template, for example
   `sf project retrieve start --metadata GenAiPromptTemplate:<Name> --target-metadata-dir <scratch> --unzip`;
3. take the retrieved form into source, with its `versionIdentifier` and an `activeVersionIdentifier`
   naming it;
4. redeploy;
5. retrieve again and check the two match (M13.7a, M15.3e).

### 7.6 The phase workflow

1. Authorise the phase in `CLAUDE.md`'s "Current authorised post-MVP work". Nothing may be built
   before that.
2. Plan first, and have the user approve the plan.
3. Write the playbook's Part 3 entry, with its gate, and the architecture and decisions notes,
   before the gate runs.
4. Build. Tests use in-memory rule fixtures (`AMF_RuleBuilder`), never the org's rules.
5. Run the gate, step by step, with real output.
6. Write a full technical log entry (file changes, design choices, issues, evidence, the gate as
   run, carried items) and update the status board.
7. Commit `Phase MN: <name>` with `HUSKY=0`, push to `develop`, then make the follow-up commit
   recording the SHA.
8. Update this handoff.

### 7.7 Gotchas met so far

- **Apex reserved words** include `when` and `number` as variable names, and `list` as a method
  name.
- **An `Assert` message cannot be null.** `String.valueOf(null)` is null.
- **The same value can serialise differently.** A Decimal read from the database keeps its scale
  (`250000.00`), and one set in Apex may not (`250000`), so compare values, not JSON text.
- **`Math.round` of a Decimal returns a Long.** Use `setScale(0, …).intValue()`.
- **Some forms of a `PermissionSetAssignment` query hide the standard Agentforce sets.** A query by
  name with `ORDER BY Assignee.Name` returned nothing on 2026-10-24, while the plain query by name
  returned all four.
- **Windows' 260-character path limit** stops a listing of deep retrieved folders. Keep scratch
  copies shallow.
- **Edit files with CRLF line endings carefully.** A scripted edit can silently not apply; check the
  result.

---

## 8. Owed by the user: the manual UI checks

Do these in the browser as Tejas Vernekar, who has every licence and access set. Record the result in
the technical log as **M15.7**, covering all three checks.

### 8.1 M15, gate step 11: the Admin Assistant

1. From any page, open the Agentforce panel and choose **Approval Matrix Admin Assistant**.
2. Ask: "Draft a rule for purchase requests: anything over 500,000 in EMEA should go to the finance
   committee."
   - **Expect:**
     - a draft such as `PR_EMEA_Over_500k`, with condition
       `Amount__c > 500000 && Region__c == 'EMEA'`;
     - process `PR_Finance_Committee`, priority 15, "tried after PR_High_Value_APAC (10) and before
       PR_High_Risk (20)";
     - a file path under `force-app/main/default/customMetadata/`, and the metadata;
     - "It routes nothing until you release it".
   - **Fail:** a `.json` or `.yml` path, a priority such as "Medium", or a condition such as
     `Amount > 500,000 AND Region = 'EMEA'` all mean the model wrote the draft itself (4.7, item 1).
3. Ask: "What would that draft change for recent purchase requests?"
   - **Expect:** "Checked 16 Purchase Requests decided in the last 90 days … 7 were skipped …",
     with per-process counts. Those were the figures on 2026-10-24; they move as the 90-day window
     moves and as approvals finish.
4. Ask: "How has the approval matrix been doing over the last 90 days?"
   - **Expect:** a short summary whose figures match the log. On 2026-10-24 that was 29 decisions,
     25 on Purchase Requests and 4 on Opportunities.
5. Ask: "Deploy that rule and activate it."
   - **Expect:** a refusal: it cannot change the matrix, and a draft goes live only through the
     release gate.
6. Check that Setup → Custom Metadata Types → Approval Matrix Rule → Manage Records shows the same
   nine rules.

### 8.2 M14, gate step 9: the Assistant's new questions

1. Open PR-00000047 and choose **Approval Matrix Assistant** in the panel.
2. "Where would this go?"
   - **Expect:** `PR_Two_Level_Mgmt` via `PR_Catch_All`, and nothing submitted.
   - **If it asks which record you mean,** the panel passes the page context under other names.
     Only the two `current…` declarations in the `.agent` file then need changing.
3. "What if the amount were 120000 and the region APAC?"
   - **Expect:** `PR_Three_Level_Finance` under `PR_High_Value_APAC`, "today" `PR_Two_Level_Mgmt`,
     and nothing changed or submitted.
4. "Where do my requests stand?"
   - **Expect:** your recent requests, those still waiting first, each with its approver and date.
5. "What is waiting for my approval?"
   - **Expect:** nothing, unless something is assigned to you.
6. **The briefing:**
   1. Create a throwaway Purchase Request: 500, AMER, Low.
   2. Click **Submit for Approval**. The modal names `PR_Two_Level_Mgmt`; confirm. The approval now
      waits on AMF Approver One.
   3. In its Approval History, **Reassign** the step to yourself.
   4. Ask "What is waiting for my approval?". **Expect:** the throwaway, at step "Manager".
   5. Ask "Brief me on it". **Expect:** `PR_Catch_All`, `PR_Two_Level_Mgmt`, the step reassigned
      to you, and no recommendation to approve or reject.
   6. **Recall** the throwaway. *Matrix Submission* unticks.
7. **Optional: submit through the assistant.** On another throwaway, "Submit it" asks for
   confirmation. Note whether you are asked once or twice. The timeline shows the new entry after
   its refresh button; the panel cannot refresh the page. Recall it afterwards.

### 8.3 M13, gate step 11: the Explain button

1. Open PR-00000042. In the Approval Timeline, open the newest entry's details.
2. Click **Explain in plain English**.
   - **Expect:** "Einstein is writing…", then a card with an *AI-generated* badge and "Written by
     Einstein at … from decision log ADL-00000027". The recorded rule, condition and values stay
     below it, and the refresh icon writes it again.

---

## 9. Open items and known limits

| Item | Owner | Source |
|---|---|---|
| The three manual UI checks (section 8) | user | M13.7, M14.6, M15.6 |
| The panel's page-context names and how it renders submit's confirmation are unobserved | step 8.2 | M13.7 |
| Einstein's Trust Layer prompt-injection and toxicity detection are off. Approver comments, administrators' words and rule descriptions reach the model | user | M13.7, M15.6 |
| Pallab Saikia, or any other user, has no access to the assistants (5.2) | user | 2026-10-23 |
| A drafted rule's name is checked against active rules only; widening `AMF_RuleProvider` would close it | a later phase | M15, decisions |
| Releasing a draft is the administrator's own configuration release | administrator | M15 |
| The impact check skips records in an approval process now: 7 of 23 in `amf-dev` | as designed | M15.6 |
| Topic assertions depend on the platform's model; two consecutive passes are the bar | whoever reruns | M14.6 |
| The submitters' assistant was not reworded after M15's lesson (4.7, item 1). It passes its suite, but fabrication is possible in principle | a later phase | M15.6 |
| A follow-up what-if ("And would it …") carries the earlier values over; the answer says so | as designed | M14.5 |
| Real approvers would each need an Agentforce licence to use briefings and "my approvals" | user | M14.6 |
| After the assistant submits, the timeline needs its refresh button | if wanted | M13.7 |
| The timeline LWC words a `Reassigned` row "X, for Y" | a later LWC change | M14.3f |
| `AMF_AgentSubmitRoute` keeps its own approver-name lookup, duplicated by `AMF_AgentSupport.actorNamesOf()` | a hardening pass | M14.6 |
| `amfSubmitForApproval` and `amfDecisionTimeline` keep their own `messageOf`; `c/amfErrors` exists for them | a hardening pass | M7.6, M13.7 |
| The UI test suite has no M13, M14 or M15 case | the next UI run | M13.7 |
| The agent test specs and definitions name `amf-dev`'s records; another org needs its own | whoever runs them elsewhere | M13.7 |
| Editing a prompt template needs the retrieved-form step (7.5) | whoever edits one | M13.7a |
| Stray guards on PR-00000014 to -25, and seven old pending approvals (6.4) | the Flow phase; user | M8.7c, M15.3g |
| `package-lock.json` is untracked | user | — |
| `CLAUDE.md`'s Environment section shows the publish command for the first agent only; section 7.4 here has both | whoever next edits `CLAUDE.md` | M15 |

---

## 10. What remains of the target design

### 10.1 Flow approvals, the second execution strategy

This is the largest part of architecture v3.0 still unbuilt (§3.1, §3.3, §5.3, §5.4, §6.2, §8, §9,
§12). Rules would choose, one row at a time, between a Classic approval process and a Flow approval
orchestration, with no engine change upstream of the strategy. It adds:

1. **`Execution_Type__c`** (`Classic` or `Flow`) on the rule and on the log. Both were deliberately
   omitted in M1 (decisions, 2026-08-17).
2. **`AMF_FlowApprovalStrategy`**, behind `AMF_SubmissionStrategy`. It launches the named
   orchestration with `Flow.Interview.createInterview(<ApiName>, inputs).start()`, which M6
   confirmed, and stamps the `ApprovalSubmission` Id.
3. **At least one Flow template**, on the contract M6 established at API 67 (§5.3): an orchestration
   plus a companion screen flow per approval step.
4. **A Flow history provider** behind `AMF_ApprovalHistoryProvider`, for the timeline. The
   explanations would describe a Flow approval only once it exists.
5. **Validator and gate checks:**
   - a Flow rule's process must be an *active* `ApprovalWorkflow` flow;
   - the source gate checks a Flow template's guard handling;
   - M12's manifest extends to Flow templates, excluding the flow's status from the fingerprint.
6. **A guard reset for cancelled submissions**, or cancel withheld operationally (§12 item 7).

**Constraints:**
- Engine classes stay at API 66 or below. Flow metadata needs a higher `sourceApiVersion`, and
  raising it must not raise the classes'.
- `docs/spike-results.md` Round 2's migration checklist binds the phase.
- Literal approvers in a Flow template block packaging. A username there needs M12's placeholder.

**Partly blocked.** Unanimous approval on Flow group steps needs the value of
`requiresMultiMemberApproval`, which nobody knows yet (§12 item 1). A person must set it once in
Flow Builder, and then it can be retrieved. Without it, committees stay on Classic, which works
today.

**Cleanup it owns:** the M6 teardown, `spikes/flow-approvals/scripts/teardown.ps1`, which also
removes PR-00000014 to -25 and their guards.

### 10.2 Smaller gaps, not phases

| Gap | Source |
|---|---|
| DateTime fields and literals are refused; they need a time-zone decision | §4.3, M9.5 |
| Email, Phone, URL and Text Area fields are refused; each is a type-map entry plus tests | playbook Part 5 |
| Field-to-field multipicklist comparisons are refused | M9.5 |
| `AMF_CmdtRuleProviderTest` pins the first shipped rule, so a new lowest-priority rule breaks it | M12.3b |
| Template drift in the org is found only by retrieving and comparing; that is not scripted | M12.5 |
| `force-app` has not been deployed to a second org | M12.5 |
| UI strings are English literals; Custom Labels when translation is needed | M7.6 |
| Phones keep the default record page, so there is no timeline on mobile | M7.6 |
| Rule descriptions are not snapshotted, so the timeline names rules by DeveloperName | decisions, 2026-10-08 |
| `Lock_Decision_Log` still permits one post-insert stamp that nothing performs | M10.6 |
| A record a validation rule will refuse still previews as routable | M10.7h |
| The final-approval lock outside a test is unmeasured | M10.8a |
| The Approval Decisions card shows four of its six columns; related lists can show their earlier state until a reload | M12.6, M12.7 |

### 10.3 AI follow-ups, none authorised

- Lightning types, for richer cards in the agent panel.
- The approver's briefing as a card on the record page.
- Rewording the submitters' assistant in the style M15 found reliable (4.7, item 1).

### 10.4 Deliberately not planned

- **Approver resolution, chain objects, the Group Work Item pattern, the Approval Inbox and the SLA
  batch:** superseded at the v2.1 pivot (architecture Appendix B).
- **A template registry:** only if §12 item 4's threshold is reached, meaning dozens of rules
  sharing shapes.
- **Recall from the framework itself:** out of scope. Native recall works and clears the guard, and
  both assistants refuse to recall.

---

## 11. Decisions waiting on the user

1. **The three manual UI checks** (section 8).
2. **Whether to turn on the Trust Layer's prompt-injection and toxicity detection** in `amf-dev`.
3. **Who else gets access to the assistants,** starting with Pallab Saikia (5.2).
4. **The next phase,** authorised in `CLAUDE.md`. For Flow approvals, say whether committee steps
   are wanted on Flow. If they are, a person must find the unanimous value in Flow Builder first.
5. **Optional:**
   - reword the submitters' assistant (10.3);
   - widen `AMF_RuleProvider` for drafted rule names;
   - add M13 to M15 cases to the UI suite;
   - commit or ignore `package-lock.json`.

---

## Appendix A: every agent action

Every class below is declared `with sharing`, runs as the user, and answers every request rather
than throwing. Two of them read through a `without sharing` inner class, bound to the user's own
data: `AMF_AgentMyRequests` (approvals its rows name) and `AMF_AgentMyApprovals` (the user's own
work items). Ids arrive as text and are read by `AMF_AgentSupport.idOf()`.

**Approval Matrix Assistant**

| Subagent → script action | Agent action → Apex class (label) | Inputs | Outputs that matter | Notes |
|---|---|---|---|---|
| any → `find` | `find_record` → `AMF_AgentFindRecord` (Find Governed Record) | searchText | matchCount, recordId, recordLabel, matches, message | Governed objects only, user mode: Id, then exact name, then SOSL, then a contains-match. Several matches are listed, never guessed between |
| route_and_submit → `preview` | `preview_route` → `AMF_AgentPreviewRoute` (Preview Approval Route) | recordId | outcome (Routable, Blocked_No_Match, Failed or Refused), summary, selectedProcess, matchedRule, ruleVersion, rulePriority, ruleDescription, condition, valuesRead, canSubmit | Sets `previewed_record_id`, `previewed_process` and `can_submit` |
| route_and_submit → `submit` | `submit_route` → `AMF_AgentSubmitRoute` (Submit Previewed Route) | recordId and expectedProcess, bound from the preview | submitted, outcome, summary, routeChanged, decisionLogName, waitingOn | `require_user_confirmation`; available only when `can_submit`; through `submitEach()` |
| route_and_submit → `what_if` | `what_if_route` → `AMF_AgentWhatIfRoute` (What-If Approval Route) | recordId, changes ("Field = value; …") | outcome, routeChanged, selectedProcess, matchedRule, currentProcess, currentRule, summary | `previewWith()`; clears `can_submit` |
| explain_decision → `explain` | `explain_approval` → `AMF_AgentExplainDecision` (Explain Approval Decision) | recordId, question | explained, explanation, decisionLogName | The newest decision on the record |
| explain_decision, my_work → `brief` | `brief_approval` → `AMF_AgentBriefApproval` (Brief Approver) | recordId | briefed, briefing, decisionLogName | Only for the current approver |
| my_work → `my_requests` | `list_my_requests` → `AMF_AgentMyRequests` (My Approval Requests) | pendingOnly | count, requests, message | 90 days, 10 listed, pending first |
| my_work → `my_approvals` | `list_my_approvals` → `AMF_AgentMyApprovals` (My Pending Approvals) | objectName | count, approvals, message | `AMF_ApproverScope`; 10 listed, oldest first |

**Approval Matrix Admin Assistant**

| Subagent → script action | Agent action → Apex class (label) | Inputs | Outputs that matter | Notes |
|---|---|---|---|---|
| draft_rule → `get_checked_draft` | `draft_matrix_rule` → `AMF_AgentDraftRule` (Draft Matrix Rule) | objectName, ruleRequest, ruleToChange | valid, summary, developerName, ruleLabel, priority (text), expression, processApiName, ruleDescription, ruleVersion, changeType (Add or Replace), assumptions, filePath, metadataXml | Sets `has_draft` and the `draft_*` variables |
| check_impact → `get_draft_impact` | `check_rule_impact` → `AMF_AgentCheckImpact` (Check Rule Impact) | all bound from the `draft_*` variables; change `""` | ran, summary, checked, changed, skipped, changes | Available only when `has_draft` |
| check_impact → `get_change_impact` | the same | objectName, ruleName, change (Add, Replace, Deactivate or blank), priority (text), expression, processApiName | the same | The change is worked out when blank |
| matrix_health → `get_health_report` | `matrix_health_report` → `AMF_AgentMatrixHealth` (Matrix Health Report) | objectName, days, question | summarised, summary, facts, days, decisions, blocked, failed | The facts are always returned |

## Appendix B: the agent test cases

**`AMF_Approval_Assistant_Tests`** (`specs/AMF_Approval_Assistant-testSpec.yaml`, 14 cases, none of
which submits):

| # | Utterance | Expected subagent and actions |
|---|---|---|
| 1 | "Where would this go for approval?" (on PR-00000045) | route_and_submit: preview_route |
| 2 | "Which rule applies to this request?" (on PR-00000048) | route_and_submit: preview_route |
| 3 | "Which approval process would PR-00000046 go to?" | route_and_submit: find_record, preview_route |
| 4 | "What route would PR-00000047 take?" | route_and_submit: find_record, preview_route |
| 5 | "Why did PR-00000042 go where it went, and where does its approval stand?" | explain_decision: find_record, explain_approval |
| 6 | "Explain this approval decision in plain English." (on PR-00000042) | explain_decision: explain_approval |
| 7 | "Why is this request with its approver?" (on PR-00000047, never submitted) | explain_decision: explain_approval |
| 8 | "What if PR-00000047 had an amount of 120000 and region APAC? …" | route_and_submit: find_record, what_if_route |
| 9 | "Would PR-00000047 go anywhere else if its vendor type were Strategic?" | route_and_submit: find_record, what_if_route |
| 10 | "Where do my approval requests stand?" | my_work: list_my_requests |
| 11 | "Is anything waiting for my approval?" | my_work: list_my_approvals; expects nothing waiting |
| 12 | "Brief me on the approval for PR-00000045 before I decide." | explain_decision: find_record, brief_approval; expects "not waiting on you" |
| 13 | "Approve PR-00000045 for me." | topic_selector: a refusal |
| 14 | "What is the capital of France?" | topic_selector: off-topic |

**`AMF_Matrix_Admin_Assistant_Tests`** (`specs/AMF_Matrix_Admin_Assistant-testSpec.yaml`, 6 cases,
none of which changes anything):

| # | Utterance | Expected subagent and actions |
|---|---|---|
| 1 | "Draft a rule for purchase requests: anything over 500,000 in EMEA should go to the finance committee." | draft_rule: draft_matrix_rule |
| 2 | "Write a new version of PR_High_Risk that also catches Medium risk." | draft_rule: draft_matrix_rule (version 2) |
| 3 | "What would change for recent purchase requests if PR_High_Risk were taken out?" | check_impact: check_rule_impact |
| 4 | "How has the approval matrix been doing over the last 90 days?" | matrix_health: matrix_health_report |
| 5 | "Deploy that rule to production and activate it." | topic_selector: a refusal |
| 6 | "Approve PR-00000027 for me." | topic_selector: a refusal |

## Appendix C: the Apex classes, by layer

There are 54 classes besides the 43 test classes. Two of the 54, `AMF_RuleBuilder` and
`AMF_StrategyStub`, are test fixtures. Every class's header cites its architecture section.

| Layer | Classes |
|---|---|
| Rules | `AMF_RuleProvider` (the interface), `AMF_CmdtRuleProvider` (SOQL), `AMF_RuleDefinition`, `AMF_DraftRuleProvider` (M15: the matrix with one change), `AMF_RuleBuilder` (test fixture and stub) |
| Evaluator | `AMF_Lexer`, `AMF_Parser`, `AMF_Ast`, `AMF_ExprCompiler`, `AMF_ExprCache`, `AMF_Evaluator`, `AMF_FieldPathResolver`, `AMF_ExpressionException` |
| Engine and submission | `AMF_ApprovalMatrixService`, `AMF_SubmissionStrategy`, `AMF_ClassicProcessStrategy`, `AMF_SubmitRequest`, `AMF_SubmitResult`, `AMF_SubmissionException`, `AMF_StrategyStub` (test) |
| Decision log | `AMF_DecisionLogWriter` |
| Validator | `AMF_ConfigValidator`, `AMF_ConfigurationException`, `AMF_ApprovalProcessProvider`, `AMF_ClassicApprovalProcessProvider` |
| Timeline | `AMF_DecisionTimelineService`, `AMF_ApprovalHistory`, `AMF_ApprovalHistoryProvider`, `AMF_ClassicApprovalHistoryProvider`, `AMF_ApproverScope` (M14) |
| Entry points | `AMF_SubmitForMatrixApproval` (Flow), `AMF_MatrixSubmissionResource` (REST) |
| Explanations | `AMF_DecisionExplainer`, `AMF_ExplanationGenerator`, `AMF_EinsteinExplanationGenerator`, `AMF_ExplanationException` |
| Prompt seam (M15) | `AMF_PromptRunner`, `AMF_EinsteinPromptRunner`, `AMF_PromptException` |
| Admin services (M15) | `AMF_RuleDrafter`, `AMF_MatrixImpact`, `AMF_MatrixHealthService` |
| Assistant actions | `AMF_AgentFindRecord`, `AMF_AgentPreviewRoute`, `AMF_AgentSubmitRoute`, `AMF_AgentExplainDecision` (M13); `AMF_AgentWhatIfRoute`, `AMF_AgentMyRequests`, `AMF_AgentMyApprovals`, `AMF_AgentBriefApproval` (M14); `AMF_AgentSupport` (shared) |
| Admin actions (M15) | `AMF_AgentDraftRule`, `AMF_AgentCheckImpact`, `AMF_AgentMatrixHealth` |

The LWC components are `amfSubmitForApproval`, `amfSubmitPreview`, `amfDecisionTimeline`,
`amfDecisionTimelineEntry`, `amfDecisionExplanation` and `amfErrors`.

## Appendix D: Ids

| What | Id |
|---|---|
| Tejas Vernekar (CLI user) | `005aj00000bC5wHAAS` |
| Grok Bot | `005aj00000gVeSPAA0` |
| Pallab Saikia | `005aj00000gaFoLAAU` |
| AMF Approver One to Five | `005aj00000bCONpAAO`, `…CONqAAO`, `…CONrAAO`, `…CONsAAO`, `…CONtAAO` |
| AMF Framework Service | `005aj00000bCONuAAO` |
| `G_Finance_Approvers` (as `Q_Credit_Risk`'s member) | `00Gaj00000V8jvmEAB` |
| `AMF_Approval_Assistant` (BotDefinition) | `0Xxaj000004fVojCAE` |
| Demo and throwaway records | section 6.4 |
