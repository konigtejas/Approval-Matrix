# Phase 4a Spike — Flow Approval Processes

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

## Q1 — How Apex launches a Flow Approval Process

### The template contract — CONFIRMED

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

### Step action types — CONFIRMED

| Value | Result |
|---|---|
| `stepInteractive` | **Rejected**: *"You can't use the Step Interactive action type in flows with the Flow Approval Processes process type."* |
| `stepApproval` | **Accepted** |
| omitted | Deploys as `Draft`, rejected on activation: *"You must specify an actionType"* |

**Draft deploys are not validated to activation standard.** The first version deployed clean as
`Draft` and only failed when `status` flipped to `Active`. Any config validator that checks
"the flow exists" must also check it is **active**, or a broken template passes validation.

### Each approval step needs a companion flow — CONFIRMED

Activating with `actionType stepApproval` fails with *"Specify a flow for this step."* An
approval step delegates to a screen flow that the approver runs. **This is unbudgeted work in
v2.1 §3.4's template library**: each Flow template is not one flow but an orchestration *plus*
at least one screen flow per approval step.

### The launch call itself — INFERRED, NOT EXECUTED

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

## Q2 — Timeline join shape — CONFIRMED

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

## Q3 — Group step any-member / unanimous semantics — OPEN

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

## Q4 — Recall path — CONFIRMED, and it contradicts v2.1 §3.3

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

## Summary

| Question | Status |
|---|---|
| Q1 template contract (`ApprovalWorkflow`, 3 input variables, `stepApproval`) | **CONFIRMED** |
| Q1 Apex launch call | **INFERRED** — blocked on companion screen flow |
| Q2 timeline join shape | **CONFIRMED** |
| Q3 group any-member / unanimous | **OPEN** — the highest-risk gap |
| Q4 recall/cancel/reassign/review reachable from Apex | **CONFIRMED as available**, execution untested |

### Changes this implies for v2.1

1. **§3.3 points 1–2 and the Phase 5 screen-flow recall design** — revisit; the actions exist.
2. **§3.4 template library** — a Flow template is an orchestration **plus** a screen flow per
   approval step. Budget accordingly.
3. **§5 validator** — must check the referenced flow is **active**, not merely present, because
   a structurally invalid orchestration deploys cleanly as Draft.
4. **§3.2 decision-log join** — `Execution_Ref_Id__c` holds `ApprovalSubmission.Id`; the
   timeline reads `ApprovalWorkItem` filtered on `ApprovalSubmissionId`, and `ReviewedById`
   supplies the true actor that v1 tracked manually.

### Artifacts

The throwaway orchestration `AMF_Spike_Approval` is deployed to `amf-dev` as **Draft**. It is
not project source and should be deleted before Phase 4b, or completed into the first real
template. Its working XML is reproduced above.
