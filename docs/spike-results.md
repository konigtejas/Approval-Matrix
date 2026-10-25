# Flow Approval Processes — Spike Findings

Two rounds against `amf-dev` (Developer Edition, `00Daj000012Gj9BEAS`). Round 2 supersedes
Round 1 wherever they differ; Round 1 is kept below as history.

Every claim is labelled **CONFIRMED** (observed in the org), **INFERRED** (follows from observed
evidence but not executed), or **OPEN** (not established). Experiment ids (E1…, T1…) refer to
the scripts and flows under `spikes/flow-approvals/`.

---

## Round 2 — M6 spike (2026-10-07, Summer '26, API 67.0)

**Scope:** close Round 1's open questions (Q1 launch, Q3 group semantics, Q4 recall execution)
and find every trap in moving from Classic approval processes to Flow approvals, before any
`FlowApprovalStrategy` is designed. Nothing in `force-app` changed; every artefact lives under
`spikes/flow-approvals/` and was deployed in MDAPI format at API 67.0.

**Method.** Desk research first (practitioner sources, release notes; Salesforce Help and
developer.salesforce.com refuse automated fetches), then the org's own Metadata API WSDL as the
schema authority, then hands-on experiments: 11 spike flows, one throwaway Apex test class and
anonymous Apex, on dedicated spike records (PR-00000011 onward). Approvers: `amfu1`/`amfu2` and
three spike groups (`AMF_Spike_Any`, `AMF_Spike_All`, `AMF_Spike_Queue`, each = admin + `amfu1`).

| Id | What | Flow |
|---|---|---|
| E1 | Launch from Apex; same-transaction read-back | `AMF_Spike_User` |
| E2 | Admin decides an item assigned to `amfu1`; approve path, final stage | `AMF_Spike_User` |
| E3 | Reject path on a single level | `AMF_Spike_User` |
| E4 | Recall from Apex | `AMF_Spike_User` |
| E5 | Cancel from Apex | `AMF_Spike_User` |
| E6 | Group, default settings | `AMF_Spike_Group_Any` |
| E7 | Group, "unanimous" | `AMF_Spike_Group_All` |
| E8 | Queue | `AMF_Spike_Queue` |
| E9 | Two levels, no gate: reject level 1, then approve level 2 | `AMF_Spike_Two_Level` |
| E10 / E10b | Gated two levels: reject at level 1 (before / after fixing the gate) | `AMF_Spike_Two_Level_Gated` |
| E11 / E11b | Gated two levels: approve, approve (before / after fixing the gate) | `AMF_Spike_Two_Level_Gated` |
| E12 | What the step's `approvalDecision` output holds | `AMF_Spike_Output_Probe` |
| E13 | `Resource` assignee given a username, then a User Id; literal User Id | `AMF_Spike_Resource`, `AMF_Spike_User_Id` |
| T1 | Full lifecycle inside an Apex test | `AMF_FlowApprovalSpikeTest` |
| T2 | Locking, non-admin submitter, non-assignee decision | `AMF_FlowApprovalSpikeTest` |

### Headline

1. **Q1 is answered: `Flow.Interview.createInterview(...).start()` launches a Flow approval, and
   the `ApprovalSubmission` and first work item exist synchronously, in the caller's
   transaction.** The engine can stamp `Execution_Ref_Id__c` exactly as it does for Classic.
2. **A rejection does NOT stop a Flow approval.** Later stages still run — a level-2 approver is
   asked to approve a request level 1 already rejected. Every level after the first must be gated
   on the previous step's `approvalDecision`. Classic stops at the first rejection.
3. **The obvious way to gate is broken.** Mapping the step's `approvalDecision` into a variable
   (`outputParameters`) leaves it **null**; a gate built on it silently approved a request after
   level 1 only. The working form is a direct reference, `<Step>.Outputs.approvalDecision`.
4. **Apex API 67.0 runs database operations in user mode by default.** Moving any of the engine's
   classes to API 67 — tempting "for Flow approvals" — would break guard staging and the decision
   log. Not a Flow finding, but found here, and the most dangerous one for the product.
5. **Q3 is half answered.** A group or queue step is "any member" (one shared work item; one
   decision completes it). "Require unanimous approval" exists (Summer '26) but its metadata value
   could not be found: **every value tried was silently dropped**, leaving the step any-member.

### Q1 — Launching from Apex — CONFIRMED (E1, T1, T2)

| Fact | Evidence |
|---|---|
| `Flow.Interview.createInterview('<ApiName>', inputs).start()` starts an autolaunched approval process | E1 |
| **Synchronous:** after `start()`, in the same transaction, the `ApprovalSubmission` exists (`Status = InProgress`, `SubmittedById` = submitter, `FlowOrchestrationInstanceId` set) and so does the first `ApprovalWorkItem` | E1 |
| Cost to the caller's limits: 0 SOQL, 0 DML (CPU ~110–170 ms) | E1 |
| Works in Apex tests: the same records exist before `Test.stopTest()`; an approver decides under `System.runAs`; final status and background stages are observable after `stopTest()` | T1 |
| Works for a non-admin submitter (Standard Platform User, **no** Run Flows permission) | T2 |
| No standard invocable action starts a Flow approval. The org's approval actions are `recallApprovalSubmission`, `cancelApprovalSubmission`, `reassignApprovalWorkItem`, `reviewApprovalWorkItem`; `requestApproval` appears in the Metadata API's action-type list but not among the org's standard actions | REST describe, WSDL |
| A fault at start (e.g. a Resource assignee given as a User Id) throws `System.FlowException: An unhandled fault has occurred in this flow` **synchronously** and rolls back the whole transaction — nothing half-submitted, but the message names nothing | E13 |

### The template contract at API 67 — CONFIRMED (deploy and activation errors)

Round 1's contract has moved. A Flow approval process (`processType` `ApprovalWorkflow`) now needs:

| Requirement | Platform message when missing |
|---|---|
| **Four** String inputs: `recordId`, `submitter`, `submissionComments` **and `firstApprover`** (new since Round 1's API 62; the name the Spring '26 Request Approval component uses — INFERRED to be its origin) | *"…you must define a variable that uses the "firstApprover" API name and the Text data type…"* |
| `<runInMode>SystemModeWithoutSharing</runInMode>` | *"Because you're running this automaton in API version 60.0 … you must select System Context Without Sharing—Access All Data or specify API version 59.0 or earlier"* |
| Background steps use `actionType` **`stepBackground`**, not `flow` | *"You can't use the Flows action type in flows with the Flow Approval Processes process type."* |
| Approval steps: `actionType stepApproval`, `stepSubtype ApprovalStep`, `actionName` = a screen flow that outputs `approvalDecision` and `approvalComments`. This spike also passed `ActionInput__RecordId` (the record the work item belongs to) and the screen flow's `recordId`; deployed and ran, not proven individually required | Round 1; E1 |
| Recall path: a `start.scheduledPaths` entry with `pathType` **`ApprovalRecall`**, connected to a stage of background steps | WSDL; E4 |
| Per-step record lock: `shouldLock` (boolean) | WSDL; T2 |

Also: Salesforce ships templates in the `standard_approvals` namespace (`EvaluateApproval` —
"Approvals Workflow: Evaluate Approval Requests"; `ProcSimpleAppvl` — "Process Simple Approval"),
but neither the Metadata API nor the Tooling API will return them. Every deploy creates a new
flow version, and a flow holds at most **50**.

### Assignees — CONFIRMED (E1, E6, E8, E13; activation error)

| Form | Result |
|---|---|
| Literal `User` given as a **username** | Resolves to the right user at runtime |
| Literal `User` given as a **User Id** | **Activation fails:** *"The assigned user 005… in the assignee field doesn't exist or is inactive."* |
| Literal `Group` / `Queue` | Their DeveloperName |
| `Resource` (a variable, e.g. `firstApprover`) holding a **username** | Resolves |
| `Resource` holding a **User Id** | `start()` throws the generic `FlowException` above |
| Any literal `User`/`Group`/`Queue` | *"You can't package an orchestration that contains a step with assignee type set to User, Group, or Queue."* — literal approvers make a template org-specific |

`ApprovalWorkItem.ApprovalConditionName` (unexplained in Round 1) is the approval step's **label**.

### Q3 — Groups and queues

| Question | Result | Status |
|---|---|---|
| Group step, default settings | **One** work item assigned to the group; one member's decision completes the step, the submission and the orchestration; `ReviewedById` names who decided | **CONFIRMED** (E6) |
| Queue step | Same shape and behaviour; the record's owner does not change | **CONFIRMED** (E8) |
| "Require unanimous approval" (Summer '26: every member gets their own item; one rejection withdraws the rest; items cannot be reassigned) | The step field is `requiresMultiMemberApproval` (xsd:string). `true`, `TRUE`, `True`, `Unanimous`, `Yes`, `AllMembers` and `All` were each accepted by the deploy **and silently dropped** — absent on retrieve, null in the Tooling API, and the step ran any-member (E7). The Tooling API drops it too | **OPEN** — needs the value Flow Builder writes |

`ParentWorkItemId` stayed null in every experiment; no hierarchy appeared for groups or queues.

### Decisions, outcomes and the rejection trap — CONFIRMED (E2, E3, E9–E12)

- **`reviewApprovalWorkItem` takes `Approve` / `Reject`.** Its own description says the valid
  values are "approve, reject"; `approve` is refused with `INVALID_INPUT`.
- **`Invocable.Action` parameters are typed:** passing an `Id` where the action declares a String
  is refused (`INVALID_ARGUMENT_TYPE`); pass `String.valueOf(id)`.
- **`ReviewedById` is the actual decider; `AssignedToId` the assignee.** A System Administrator
  can decide an item assigned to someone else (E2); a standard user who is not the assignee
  cannot, and the error says only *"UNKNOWN_EXCEPTION: Orchestrator Event: Event payload value is
  invalid: StepInstanceId"* (T2).
- **A rejection does not end the orchestration (E3, E9).** After a level-1 rejection the level-2
  work item was created and assigned to `amfu2`, and the submission stayed `InProgress`. When the
  run finally completed it was `Rejected` — any rejected item makes the final status `Rejected` —
  but only after the next approver had been asked to approve something already rejected.
- **The gate that works (E10b, E11b):** a Decision between levels on
  `Approve_L1.Outputs.approvalDecision` equal to `Approve`. Rejection ends the run at once;
  approval reaches level 2, and the submission is `Approved` only when level 2 approves.
- **The gate that silently fails (E11, E12):** the step's `outputParameters` mapping of
  `approvalDecision` to a variable leaves the variable **null** for both outcomes. A gate on it
  routes everything to its default path — with an "end" default, a request was **Approved after
  level 1 only**. (Decisions here came through `reviewApprovalWorkItem`; the screen-flow path
  could not be tested without a browser — INFERRED to behave no better, since the direct
  reference is what Flow Builder generates.)

### Record locking — CONFIRMED (T2)

- `shouldLock = true` locks the record **synchronously at start**: the owner's edit was refused
  with `ENTITY_IS_LOCKED`, even from system-mode Apex. An unsubmitted control record edited fine,
  and the lock lifted when the approval completed.
- A background stage after the approval step updated the record (the guard reset) without a lock
  error (E2, E3).
- `Approval.isLocked()` / `lock()` / `unlock()` in Apex need the org preference **"Enable record
  locking and unlocking in Apex"** (Process Automation Settings). It is off in `amf-dev`, so even
  *checking* a lock throws `NoAccessException`. Left off; locking was proved by behaviour instead.

### Q4 — Recall and cancel — CONFIRMED by execution (E4, E5)

| Action (from Apex) | Submission / item | Orchestration | `ApprovalRecall` path | Guard |
|---|---|---|---|---|
| `recallApprovalSubmission` | `Recalled` / `Recalled` | `Canceled`; pending stage `Canceled` | **Runs** | Reset |
| `cancelApprovalSubmission` | `Canceled` / `Canceled` | `Canceled` | **Does not run** | **Left `true`** |

### Visibility, audit and email

- **Flow approvals create no `ProcessInstance`:** 15 Flow submissions, 0 `ProcessInstance` rows.
  The standard **Approval History** related list, which reads those, therefore has nothing to show for Flow-routed records (INFERRED from the data — not viewed in the UI) — the
  Approval Trace component (or the planned timeline) is what shows them. — CONFIRMED
- **Assignment grants the approver no access to the record** (`amfu1`: read = false), exactly as
  for Classic (technical log M3.10). Through the API the assignee could still decide (T1). — CONFIRMED
- **Step emails are sent as the Automated Process User**, and this org has no email set for it:
  *"Because the Automated Process User has no valid email address, this orchestration can't send
  emails for steps."* `DoesSendApprovalEmail` is `true` on every submission regardless. — CONFIRMED
  (platform message); delivery not observed.
- **Approval orchestrations run without sharing** (the `runInMode` requirement above). — CONFIRMED

### Platform-wide: Apex API 67.0 defaults to user mode — CONFIRMED

Summer '26: from Apex **API 67.0**, SOQL, SOSL, DML and `Database` methods run in **user mode by
default** — sharing, field-level security and object permissions of the running user — whatever
the class's sharing keyword. Observed in T2: a plain `insert` as an `Approval_Matrix_User` was
refused (*"fields being inaccessible on Sobject Purchase_Request__c"*, the read-only guard field).
The engine stages that guard, writes decision-log rows submitters cannot create and reads fields
regardless of the submitter's access — all system-mode by design (arch §11). **The product's
classes must stay at API ≤ 66, or every intended system-mode operation must say so explicitly.**
The release notes add that `WITH SECURITY_ENFORCED` is removed at 67.0 (not observed here). Note the split: Flow templates need a newer
*Metadata* API version to deploy, which is the project's `sourceApiVersion`; each Apex class
keeps its own `apiVersion` — but the CLI generates new classes at the project version.

### Summary

| # | Question | Round 1 | Round 2 |
|---|---|---|---|
| Q1 | Template contract | CONFIRMED (3 inputs) | **CONFIRMED, changed:** 4 inputs, `runInMode`, `stepBackground` |
| Q1 | Apex launch call | INFERRED | **CONFIRMED** — `Flow.Interview…start()`, synchronous submission and work item |
| Q2 | Timeline join shape | CONFIRMED | Unchanged; `ApprovalConditionName` = step label; no `ProcessInstance` |
| Q3 | Group / queue any-member | OPEN | **CONFIRMED** — one shared item, first decision completes |
| Q3 | Unanimous | OPEN | **OPEN** — metadata value unknown; wrong values silently dropped |
| Q4 | Recall / cancel from Apex | CONFIRMED as available | **CONFIRMED executed** — recall runs the recall path; cancel does not |
| new | Rejection stops the process? | — | **CONFIRMED: no** — gate every later level |
| new | Locking | — | **CONFIRMED** — `shouldLock`, synchronous, released on completion |
| new | Apex API 67 user mode | — | **CONFIRMED** — pin engine classes or use explicit system mode |

### Migration checklist — Classic approval process → Flow approval

Each line is a mistake this spike either made, saw the platform refuse, or saw it silently accept.

1. **Gate every level after the first** with a Decision on `<PreviousStep>.Outputs.approvalDecision`
   = `Approve`. Classic stops on rejection; Flow does not.
2. **Never gate on an `outputParameters` mapping** of `approvalDecision` — it stays null.
3. **Test the approve path as well as the reject path** for every gate: a broken gate can look
   right on rejection and approve on level 1 alone.
4. **Use the exact strings `Approve` / `Reject`** — in screen flows, decisions and
   `reviewApprovalWorkItem`, whatever the action's description says.
5. **Declare all four inputs** (`recordId`, `submitter`, `submissionComments`, `firstApprover`) and
   **`runInMode` = `SystemModeWithoutSharing`**.
6. **Background steps are `stepBackground`** — and they replace Classic's final approval, final
   rejection and recall field updates (here: resetting `Matrix_Submission__c`).
7. **Locking is opt-in** (`shouldLock`). Classic locks on submit; a Flow approval locks only the
   steps you mark — lock only the first stage of parallel work (practitioner guidance: concurrent
   locks error).
8. **Approvers are usernames**, not Ids — literal or via a variable. A literal Id fails activation;
   an Id in a variable fails at launch with a message that names nothing.
9. **Literal approvers are not portable** and block packaging; resolve approvers through variables
   for anything meant to deploy to another org unchanged.
10. **Retrieve after deploy and compare** for any setting you cannot see fail:
    `requiresMultiMemberApproval` and possibly others are dropped without an error.
11. **Recall re-arms; cancel does not.** Either forbid cancel operationally or add a reset for
    cancelled submissions — a stale guard would let a Classic template's entry criteria pass.
12. **Approval History goes empty** for Flow-routed records: add the Approval Trace component,
    or the timeline. Reports on `ProcessInstance` see nothing; use `ApprovalSubmission`,
    `ApprovalWorkItem`, `ApprovalSubmissionDetail`.
13. **Set the Automated Process User's email** (Process Automation Settings) or no approver is
    notified.
14. **Approvers still need record access** from the sharing model; assignment grants none.
15. **Who may override:** System Administrators can decide anyone's items. Govern that.
16. **Keep Apex classes at API ≤ 66** unless every system-mode operation is explicit; raise the
    project's `sourceApiVersion` for Flow templates without letting it raise class versions.
17. **Budget versions:** 50 per flow, one per deploy.
18. **Apex lock checks need an org preference**; detect "already in approval" with SOQL on
    `ApprovalSubmission` / `ProcessInstance` instead.

### Still open

- **The `requiresMultiMemberApproval` value.** Needs a person in Flow Builder: open
  `AMF Spike Group All`, select the *Unanimous Approval* step, tick **Require unanimous
  approval**, save as a new version. Its stored value is then readable through the Tooling API,
  and E7 can be re-run against it.
- **Lock icon, Approval Trace and the screen-flow decision path in the UI.** Browser automation
  stopped working on this workstation between 2026-09-25 and 2026-10-07: Edge 154 and Chrome 153
  close as soon as the Salesforce sign-in page loads — consistent with a security policy. It was
  not worked around.
- **Groups or queues through a `Resource` assignee** (value format) — not tested.

### Artefacts

`spikes/flow-approvals/` — `mdapi/flows/` (11 flows; `AMF_Spike_User_Id` is a negative test that
must fail activation), `mdapi/classes/AMF_FlowApprovalSpikeTest` (deleted from the org after the
run), `scripts/` (setup, deploy, run, inspect, launch, action and teardown helpers). In `amf-dev`
the spike flows and groups remain for the unanimous check; `scripts/teardown.ps1 -DeleteFlows
-DeleteGroups -DeleteRecords` removes them.

---

## Round 1 — Phase 4a spike (2026-08-14, API 62.0)

**Date:** 2026-08-14 · **Org:** `amf-dev` (Developer Edition, `00Daj000012Gj9BEAS`) · **API 62.0**
**Scope:** the four questions in Architecture v2.1 §6, phase 4a.

Every claim below is labelled **CONFIRMED** (observed in the org), **INFERRED** (follows from
observed evidence but not executed), or **OPEN** (not established). No project source was
changed by this spike; the throwaway orchestration was deployed from a scratchpad directory in
MDAPI format.

**Headline: one finding contradicts the architecture.** v2.1 §3.3 states that recall, cancel and
reassign "are not supported in autolaunched flows" and concludes that the framework's recall
entry point must be a screen flow. The org exposes all of them as **standard invocable
actions** — see Q4. §3.3 points 1–2 and the Phase 5 recall design should be revisited.

---

### Q1 — How Apex launches a Flow Approval Process

#### The template contract — CONFIRMED

A Flow Approval Process is a `Flow` whose `processType` is **`ApprovalWorkflow`**. The
Metadata API's own error text calls this process type **"Flow Approval Processes"**.

It requires exactly three input variables, all `dataType` **String**, all `isInput=true`.
Each was discovered by deploy rejection, one at a time:

| Variable | Metadata API error when missing |
|---|---|
| `recordId` | *"you must define a variable that uses the `recordId` API name and the Text data type. The variable must be available for input."* |
| `submitter` | same wording, `submitter` |
| `submissionComments` | same wording, `submissionComments` |

Note the third is `submissionComments`, **not** `comments` — a plausible guess that the
platform rejects.

Minimum skeleton that deploys (status `Draft`):

```xml
<Flow xmlns="http://soap.sforce.com/2006/04/metadata">
    <apiVersion>62.0</apiVersion>
    <environments>Default</environments>
    <interviewLabel>...</interviewLabel>
    <label>...</label>
    <processType>ApprovalWorkflow</processType>
    <start><connector><targetReference>Stage_1</targetReference></connector></start>
    <orchestratedStages>
        <name>Stage_1</name>
        <label>Stage 1</label>
        <stageSteps>
            <name>Step_1</name>
            <label>Step 1</label>
            <actionType>stepApproval</actionType>
            <assignees>
                <assignee><stringValue>005...</stringValue></assignee>
                <assigneeType>User</assigneeType>
            </assignees>
            <stepSubtype>ApprovalStep</stepSubtype>
        </stageSteps>
    </orchestratedStages>
    <status>Draft</status>
    <variables>... recordId / submitter / submissionComments ...</variables>
</Flow>
```

#### Step action types — CONFIRMED

| Value | Result |
|---|---|
| `stepInteractive` | **Rejected**: *"You can't use the Step Interactive action type in flows with the Flow Approval Processes process type."* |
| `stepApproval` | **Accepted** |
| omitted | Deploys as `Draft`, rejected on activation: *"You must specify an actionType"* |

**Draft deploys are not validated to activation standard.** The first version deployed clean as
`Draft` and only failed when `status` flipped to `Active`. Any config validator that checks
"the flow exists" must also check it is **active**, or a broken template passes validation.

#### Each approval step needs a companion flow — CONFIRMED

Activating with `actionType stepApproval` fails with *"Specify a flow for this step."* An
approval step delegates to a screen flow that the approver runs. **This is unbudgeted work in
v2.1 §3.4's template library**: each Flow template is not one flow but an orchestration *plus*
at least one screen flow per approval step.

#### The launch call itself — INFERRED, NOT EXECUTED

- **No standard invocable action launches an orchestration.** All 55 standard actions were
  enumerated; **zero** match orchestration. The `submit` action (`SUBMITAPPROVAL`) reports
  `"category": "Legacy Approvals"` and its description is *"Submit a Salesforce record for
  approval"* — that is the **Classic** path, and it is what `ClassicProcessStrategy` should use.
- Therefore `FlowApprovalStrategy` cannot launch via an invocable action. Given the three
  mandated input variables, the launch is almost certainly
  `Flow.Interview.createInterview('<ApiName>', new Map<String,Object>{'recordId'=>…,
  'submitter'=>…, 'submissionComments'=>…}).start()`.
- **This was not executed**, because starting the orchestration requires it to be `Active`,
  which requires the companion screen flow above. Resolving this is the first task of any
  continuation.

---

### Q2 — Timeline join shape — CONFIRMED

Both objects exist and are queryable in this org.

**`ApprovalSubmission`** — `Id`, `OwnerId`, `Name`, `RelatedRecordId`,
`RelatedRecordObjectName`, `FlowOrchestrationInstanceId`, `Status`, `SubmittedById`,
`Comments`, `DoesSendApprovalEmail`, plus standard audit fields.

**`ApprovalWorkItem`** — `Id`, `Name`, `ApprovalSubmissionId`, `RelatedRecordId`,
`RelatedRecordObjectName`, `FlowOrchestrationWorkItemId`, `Status`, `AssignedToId`,
`ReviewedById`, `ReviewedDate`, `Comments`, `ApprovalConditionName`, `ParentWorkItemId`.

**The join for the decision log and timeline LWC:**

```
Approval_Decision_Log__c.Execution_Ref_Id__c  ==  ApprovalSubmission.Id      (Execution_Type__c = 'Flow')
SELECT Id, Status, AssignedToId, ReviewedById, ReviewedDate, Comments, ParentWorkItemId
FROM   ApprovalWorkItem
WHERE  ApprovalSubmissionId = :executionRefId
ORDER BY CreatedDate
```

Four consequences for the design:

1. **`ReviewedById` is the actual approver, natively.** v1 built `Actual_Approver__c` and the
   entire Group Work Item pattern to capture this. The platform now provides it. This is direct
   evidence for v2.1 §3.2's claim that Flow execution removes the need for that pattern.
2. **`ApprovalSubmission.RelatedRecordId` points back at the governed record**, so submissions
   are reachable from the record without the decision log. `Execution_Ref_Id__c` therefore
   earns its place as an immutable provenance stamp, not as the only join path — worth stating
   in the architecture so nobody "optimises" it away.
3. **`ParentWorkItemId` implies hierarchical work items**, which is the likely mechanism for
   multi-approver and unanimous steps. Confirming this is the core of Q3.
4. **`ApprovalConditionName`** appears to tie a work item to a named condition inside the
   orchestration. Unexplained; may be useful for rendering *why* a step ran.

---

### Q3 — Group step any-member / unanimous semantics — OPEN

Not established. Requires an active orchestration with a group- or queue-assigned approval
step, which is blocked behind the companion screen flow from Q1.

What is known: `assigneeType` accepts `User` (deployed successfully). Group and queue
assignee types were not tested. `ParentWorkItemId` on `ApprovalWorkItem` is the structure to
examine — the hypothesis is that a group step creates a parent work item with child items per
member, and that any-member vs unanimous is a property of the parent.

**This matters more than the other three questions**, because v2.1 §3.4 routes *every*
queue/group step to Flow on the strength of native any-member behaviour, and eliminates two
Classic template shapes on that basis. It is currently an untested assumption.

---

### Q4 — Recall path — CONFIRMED, and it contradicts v2.1 §3.3

The org exposes these as **standard invocable actions**, each with a REST endpoint under
`/services/data/v62.0/actions/standard/`:

| Label | Name | Type |
|---|---|---|
| Recall Approval Submission | `recallApprovalSubmission` | `RECALL_APPROVAL_SUBMISSION` |
| Cancel Approval Submission | `cancelApprovalSubmission` | `CANCEL_APPROVAL_SUBMISSION` |
| Reassign Approval Work Item | `reassignApprovalWorkItem` | `REASSIGN_APPROVAL_WORK_ITEM` |
| Review Approval Work Item | `reviewApprovalWorkItem` | `REVIEW_APPROVAL_WORK_ITEM` |

v2.1 §3.3 point 1 asserts these "work in screen flows but are not supported in autolaunched
flows", that "the Apex surface lacks parity", and that community workarounds "resort to
callouts" — concluding that recall must be a screen flow, which then drives the Phase 5 design
and §3.3 point 2.

Standard invocable actions are callable from Apex via
`Invocable.Action.createStandardAction('recallApprovalSubmission')`. On that basis the
constraint appears not to hold in this org at API 62.0.

**Verified:** the actions exist, are standard, and are exposed with REST endpoints.
**Not verified:** actually executing one, which needs a live submission (blocked with Q1/Q3).

`reviewApprovalWorkItem` is the approve/reject action, which also means actioning a work item
from Apex is supported — relevant if an inbox-style LWC is ever wanted.

**Recommendation:** do not rewrite §3.3 on this evidence alone, but do not build a screen-flow
recall path on the strength of §3.3 either, until one of these actions has been executed
against a live submission.

---

### Summary

| Question | Status |
|---|---|
| Q1 template contract (`ApprovalWorkflow`, 3 input variables, `stepApproval`) | **CONFIRMED** |
| Q1 Apex launch call | **INFERRED** — blocked on companion screen flow |
| Q2 timeline join shape | **CONFIRMED** |
| Q3 group any-member / unanimous | **OPEN** — the highest-risk gap |
| Q4 recall/cancel/reassign/review reachable from Apex | **CONFIRMED as available**, execution untested |

#### Changes this implies for v2.1

1. **§3.3 points 1–2 and the Phase 5 screen-flow recall design** — revisit; the actions exist.
2. **§3.4 template library** — a Flow template is an orchestration **plus** a screen flow per
   approval step. Budget accordingly.
3. **§5 validator** — must check the referenced flow is **active**, not merely present, because
   a structurally invalid orchestration deploys cleanly as Draft.
4. **§3.2 decision-log join** — `Execution_Ref_Id__c` holds `ApprovalSubmission.Id`; the
   timeline reads `ApprovalWorkItem` filtered on `ApprovalSubmissionId`, and `ReviewedById`
   supplies the true actor that v1 tracked manually.

#### Artifacts

The throwaway orchestration `AMF_Spike_Approval` is deployed to `amf-dev` as **Draft**. It is
not project source and should be deleted before Phase 4b, or completed into the first real
template. Its working XML is reproduced above.
