# Handoff — what's next after M11

**As of 2026-10-21.** `develop` holds three changes from one session, each with its gate run in
`amf-dev`:

- **M10's org gate**, closed as M10.8 (`a0273e9`).
- **The Opportunity baseline**, retrieved from the org and committed unchanged (`6e3079d`).
- **Phase M11**, a second governed object (`96e5692`).

Only M11's manual UI check is owed.

This is the short version. The sources are:

- `docs/technical-log.md`: the status board, M10.8, M11, and M11.5's table of open items;
- `docs/build-playbook.md`: Part 3's gates, Part 5's roadmap;
- `docs/architecture.md`: v3.0, the target design this document measures progress against.

A fresh session reads `CLAUDE.md` first: it decides what is authorised.

---

## 1. Owed by the user — nothing to build

### M11's manual UI check (playbook M11 gate, step 8)

As the admin, on a throwaway Opportunity:

1. The record page's first header button is **Submit for Approval**, and there is no second one.
2. Choose it. The modal names the route: a 5,000 deal goes to `OPP_Manager_Approval` by
   `OPP_Catch_All`; a deal of 250,000 or more goes to `OPP_Two_Level_Mgmt` by `OPP_Large_Deal`.
3. Submit. The timeline in the sidebar shows the entry without a reload, and *Matrix Submission*
   is ticked.
4. The approval is with `amfu1`, your manager. That user's Platform license cannot open
   Opportunities, so approve or recall it yourself from Approval History. *Matrix Submission*
   unticks.

Record the result in the technical log as **M11.6**.

### Also open

- **M8's manual UI check (step 6), technical log M8.7d.** PR-00000027, pending since M10.8, serves
  it from its second step: submit again (refused by name, no modal, no new log row), recall
  (*Matrix Submission* unticks), resubmit (it routes).
- **Optional, M9's manual check:** a throwaway rule using the new grammar, previewed in the UI.
  Technical log M9.4.

---

## 2. What M11 found

Governing Opportunity took configuration only; no engine class or LWC changed. The surprises were
where the playbook expected them:

- **Opportunity's four stock layouts listed the standard Submit button.** The source gate now
  fails any governed object's layout that keeps it, or that has no explicit action list (§6.3).
- **The platform assigns an approval to a user whose license excludes the object.** It sent both
  Opportunity work items to `amfu1`. So both Opportunity templates follow the submitter's manager
  hierarchy, and §11 now requires approvers to be licensed for the object.
- **SOQL's documented limit of 55 child-to-parent relationships is not enforced in Apex.** One
  query joined 142 and returned its row. The validator therefore runs each object's real union
  query, instead of the count M9.5 proposed.
- **The source is now tied to `amf-dev` twice over** (see 4.1 D).

The M10.8 fixture finding still stands: under `System.runAs`, the lock a final approval leaves did
not stop the guard update.

---

## 3. Where the build stands: twelve phases

| Phase | Delivered | Status |
|---|---|---|
| **M0** | Baseline: the `Matrix_Submission__c` guard on `Purchase_Request__c`; the v1.0 metadata retired | Complete |
| **M1** | Data model: `Approval_Matrix_Rule__mdt`, the immutable `Approval_Decision_Log__c`, the SOQL rule provider and its >255-character pin | Complete |
| **M2** | Expression evaluator, reduced grammar: lexer, parser, compiler, cache, evaluator, field-path resolver | Complete |
| **M3** | Engine, Classic strategy, two Purchase Request templates, the submit action: the MVP demo | Complete |
| **M4** | Configuration validator, the source gate, the post-deploy script | Complete |
| **M5** | Preview, and the submit action's confirmation modal | Complete |
| **M6** | Flow approvals spike, research only (`spikes/flow-approvals/`) | Complete; the unanimous value is still open |
| **M7** | Decision timeline LWC, Classic half | Complete |
| **M8** | Guard integrity: recall clears the guard; a record already in approval is refused | Complete; manual UI check owed |
| **M9** | The full §4.1 grammar | Complete |
| **M10** | The Flow invocable and REST entry points, and per-record bulk submission (M10.7: the guard staged per record; M10.8: the gate) | Complete |
| **M11** | A second governed object, Opportunity | Complete; manual UI check owed |

The MVP was M0–M3; M4–M11 are post-MVP. **Nothing after M11 is numbered or authorised.** Playbook
Part 5 proposes M12 by name and lists Flow approvals without a number. Two to three more phases
would complete architecture v3.0's target design:

- **M12:** sections 4.1 B, C and D below.
- **Flow approvals:** section 4.1 A, probably two phases, which would be M13 and M14. The numbers
  are a proposal.

---

## 4. What remains of the target design

`CLAUDE.md`'s out-of-scope list has been partly superseded:

| Status | Items |
|---|---|
| Superseded, now built | preview modal (M5), timeline LWC (M7), config validator (M4), bulk chunking (M10), recall handling for the templates' recall actions (M8), second object, for Opportunity (M11) |
| Still out of scope | Flow strategy and `Execution_Type__c`, queue and committee templates, `_v2` template cloning, the template registry, approver resolution, chain objects, recall from the framework itself |

### 4.1 Major functionality

#### A. Flow approvals: the second execution strategy

Architecture §3.1, §3.3, §5.3, §5.4, §6.2, §8, §9 and §12. The largest item by far, probably two
phases. Rules would choose, one row at a time, whether a record enters a Classic approval process
or a Flow approval orchestration, with no engine change upstream of the strategy.

It adds:

1. **`Execution_Type__c`** (`Classic` | `Flow`) on `Approval_Matrix_Rule__mdt` and on
   `Approval_Decision_Log__c`. Both were omitted in M1 (`docs/decisions.md`, 2026-08-17). Adding
   them is a field plus a default; the engine then picks the strategy per rule at steps 7 and 10.
2. **`AMF_FlowApprovalStrategy`**, behind `AMF_SubmissionStrategy`. It launches the named
   orchestration with `Flow.Interview.createInterview(<ApiName>, inputs).start()`, which M6
   confirmed. The `ApprovalSubmission` exists synchronously, so step 11 stamps its Id exactly as
   Classic stamps `ProcessInstance.Id`. A launch fault throws `System.FlowException`.
3. **At least one Flow template**, on the contract M6 established at API 67:
   - `processType` `ApprovalWorkflow`;
   - four String inputs: `recordId`, `submitter`, `submissionComments`, `firstApprover`;
   - `runInMode` `SystemModeWithoutSharing`;
   - `stepApproval` steps, each delegating to a companion screen flow that outputs
     `approvalDecision` and `approvalComments`;
   - every level after the first gated on the previous step's `approvalDecision`, because a
     rejection does not stop later stages;
   - approvers as usernames, literal or through a resource variable (literal assignees block
     packaging);
   - locking per step (`shouldLock`);
   - final actions as background stages;
   - the recall path as an `ApprovalRecall` scheduled path.
4. **A Flow history provider** behind `AMF_ApprovalHistoryProvider`, so the timeline reads
   `ApprovalSubmission` and `ApprovalWorkItem`, where `ReviewedById` is the true approver (§8,
   M7.6).
5. **Validator checks.** A Flow rule's process must be an *active* flow of `processType`
   `ApprovalWorkflow`, not merely present, because a Draft deploys clean (§9). The source gate
   needs its own checks of a Flow template's guard handling.
6. **A guard reset for cancelled submissions.** Cancel does not run the recall path (§12 item 7),
   so either a reset is built or cancel is withheld operationally.

Constraints:

- **API versions.** Engine classes stay at API ≤ 66, because API 67 runs database operations in
  user mode (§12 item 6). Flow metadata needs a newer `sourceApiVersion`, and raising it must not
  raise the classes' versions.
- **The spike's checklist.** `docs/spike-results.md` Round 2's migration checklist binds the
  phase.

**Blocked, in part:** unanimous approval on group steps. The metadata value for "Require unanimous
approval" (`requiresMultiMemberApproval`) is unknown, and every value tried was dropped silently
(§12 item 1). Finding it needs one change made by hand in Flow Builder, then retrieved. This blocks
only committee templates on Flow. Any-member group and queue steps are confirmed.

**Cleanup it owns:** the M6 teardown, `spikes/flow-approvals/scripts/teardown.ps1`. It removes the
spike flows, the `AMF_Spike_Any` / `_All` / `_Queue` groups, and the spike records, including
PR-00000014 to PR-00000025 and the guards they still carry (M8.7c).

#### B. Template versioning: §5.1's `_v2` convention (proposed M12)

A live template is never edited in place. A change clones it to `_v2`, the rule's
`Process_API_Name__c` is repointed, and the previous version is deactivated, so in-flight
approvals and history both survive. Nothing enforces this today: all four templates (two Purchase
Request, two Opportunity) are v1 and can be edited in place (M3.8).

The source gate would check that:

- every rule points at an active template;
- a superseded version is inactive;
- a released template's content never changes.

**Decide first:** how "never edited in place" is detected. Recommended: a committed manifest of
released templates' fingerprints, which the gate compares against; it is deterministic and works
offline. The alternative, a git diff against a release baseline, ties the gate to branch history.

#### C. Queue and committee templates (proposed M12)

Today the templates have manager-hierarchy and named-user steps only. Classic supports queue
approvers and multi-approver steps, either unanimous or first-response (§5.4, §5.5). The org
already has the seeded queue `Q_Credit_Risk`, which supports `Purchase_Request__c`, and the public
group `G_Finance_Approvers` (`amfu1` to `amfu3`).

**Decide first:** committee steps on Classic now, which works today, or wait for Flow. §5.4 prefers
Flow for group steps, because `ReviewedById` gives the true actor natively, but Flow's unanimous
mode is unresolved (A). Recommended: Classic now.

Under §11, queue and group members need a license that includes the object, as well as read
access to the record. The seeded members hold Platform licenses, so they can serve Purchase Request
templates but not Opportunity ones.

#### D. Portability: the source deploys only to `amf-dev` (proposed M12)

This must be fixed before any CI pipeline or second org. There are two causes:

1. **Usernames.** `PR_Three_Level_Finance` names `amfu3` to `amfu5` by username, with this org's
   domain (`@amf.00daj000012gj9b.dev`). The seed script already derives the domain per org; the
   template does not. A `replacements` entry in `sfdx-project.json` is one fix.
2. **Org fields.** The four Opportunity layouts reference this org's sample fields:
   `OrderNumber__c`, `CurrentGenerators__c`, `TrackingNumber__c`, `MainCompetitors__c`,
   `DeliveryInstallationStatus__c`, and the `DeliveryStatus` link. **Decide:** keep them in the
   package as this org's configuration, or move org configuration into its own package directory,
   deployed only to `amf-dev`.

### 4.2 Smaller gaps, not phases

| Gap | Detail | Source |
|---|---|---|
| DateTime fields and literals | Refused at compile; needs a time-zone decision | §4.3, M9.5 |
| Email, Phone, URL, Text Area fields | Refused; each is a type-map entry plus tests | playbook Part 5 |
| Field-to-field multipicklist comparisons | Refused | M9.5 |
| UI strings | English literals; Custom Labels when translation is needed | M7.6 |
| Mobile | Phones keep the default record page, so no timeline there | M7.6 |
| Rule descriptions | Not snapshotted, so the timeline names rules by DeveloperName; would need a log field | `docs/decisions.md`, 2026-10-08 |
| Approvers and the routing reason | Approvers cannot read other submitters' log rows; a sharing decision, not code | `docs/decisions.md`, 2026-10-08 |
| `Lock_Decision_Log` | Still permits one post-insert stamp that nothing performs; forbidding every update also closes M1.10's long-text hole | M10.6 |
| Approval Decisions related list | Offers New and Mass Change Owner on both objects' layouts; `excludeButtons` removes them | M11.5 |
| Preview and guard failures | A record a validation rule will refuse still previews as routable | M10.7h |
| The final-approval lock outside a test | Unmeasured; `Approval.isLocked()` needs the "Apex approval lock/unlock api" preference | M10.8a |
| LWC tidy-up | `messageOf` duplicated in two LWCs; `.prettierrc` indents 2, the code 4 | M7.6 |
| husky pre-commit | Would reformat whole files; commits run with `HUSKY=0` | M10.7 |
| A record-triggered Flow calling the action | Re-triggered by the guard updates; its entry conditions must exclude them | M10.6 |

### 4.3 Deliberately not planned

- **Approver resolution, chain objects, the Group Work Item pattern, the Approval Inbox and the
  SLA batch.** Superseded at the v2.1 pivot (architecture Appendix B): approver shapes are template
  properties, and the platform runs the approval.
- **A template registry.** Only if §12 item 4's threshold is reached: dozens of rules sharing
  shapes. Until then, the validator's existence checks catch stale references.
- **Recall from the framework itself** (an action, an API, Flow recall). Out of scope in
  `CLAUDE.md`. Classic's native recall works and clears the guard (M8). Flow recall from Apex was
  proven in the spike (Appendix A, Q4), but no product path is designed (§7).

---

## 5. Suggested order, and what each step needs

1. **The owed UI checks** (section 1): M11's, then M8's. About fifteen minutes in the browser.
2. **M12: B, C and D.** It needs three decisions: how in-place edits are detected, Classic or Flow
   for committee steps, and where standard-object layouts live. Why before Flow:
   - lifecycle rules are simpler to set on Classic templates and then extend to Flow ones;
   - portability blocks CI and any second org;
   - Flow is partly blocked;
   - playbook Part 5 placed it after M11 so that its rules are written against two objects'
     templates.
3. **Flow approvals: A.** It needs the unanimous value found by a person in Flow Builder, if
   committee steps are wanted on Flow; otherwise it can be built with named and any-member steps.
4. **A hardening pass** for 4.2 whenever convenient. The related-list buttons and
   `Lock_Decision_Log` could ride along with M12.

---

## Decisions waiting on the user

1. Run M11's manual UI check, and M8's, and report the results.
2. Choose the next phase, and authorise it in `CLAUDE.md` with the decisions it needs: for M12,
   the three above.
