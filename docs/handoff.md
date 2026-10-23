# Handoff — what's next after M12

**As of 2026-10-23.** `develop` holds Phase M12 and its follow-ups M12.6 to M12.8, with every gate
run in `amf-dev`:
- M8's, M11's and M12's owed manual UI checks passed in the first run of the UI test suite, which an
  AI agent ran in the browser.
- That run found two display defects in the timeline, which M12.6 fixed.
- The suite's re-run confirmed both fixes (M12.7). No check is owed.
- M12.8 gave Purchase Requests a Request Name field, and added it to the All Purchase Requests
  list view. Opportunity gained a Matrix Opportunities list view.

This is the short version. The sources are:

- `docs/technical-log.md`: the status board, M12 to M12.8, and M12.7's table of open items;
- `docs/ui-tests/`: the UI test suite, and the guide for whoever runs it;
- `docs/build-playbook.md`: Part 3's gates, Part 5's roadmap;
- `docs/architecture.md`: v3.0, the target design this document measures progress against.

A fresh session reads `CLAUDE.md` first: it decides what is authorised.

**Deploying changed in M12.** Set `AMF_USERNAME_DOMAIN` first, to `amf.00daj000012gj9b.dev` for
`amf-dev`, or the CLI refuses any deploy that includes an approval process. In PowerShell:

```powershell
$env:AMF_USERNAME_DOMAIN = 'amf.00daj000012gj9b.dev'
sf project deploy start -o amf-dev
```

That deploys both package directories: `force-app`, the framework, and `org-config/amf-dev`, this
org's own configuration.

---

## 1. Owed by the user — nothing

No check is owed. Run the UI suite again whenever a rule, a template or a component changes, as
`docs/ui-tests/README.md` describes, and record each run as a sub-entry of the latest phase. With
`RUN_OPTIONAL` set to `yes`, a run also answers M9's optional check (TC-15) and lists the Flow
actions (TC-16).

### Also open

- **Grok Bot holds System Administrator in `amf-dev`**, for the suite. Deactivate it, or return it
  to Standard User, between runs.
- **PR-00000027** has been pending since M10.8 to serve M8's check, which is closed. It can be
  recalled.

---

## 2. What M12 found

- **The platform rewrites a template on deploy.** It drops `rejectBehavior` from the first step
  and appends `Owner` to a custom object's approval page fields. Fingerprints taken from the
  authored source would have broken on the next retrieve. All six templates' source now takes
  the retrieved form, and a retrieve of the org's six matches the manifest exactly.
- **A public group reaches a Classic step only through a queue.** Classic cannot assign a step to
  a group. A queue that holds the group as a member works: a group member decided the queue's
  step in a real-platform test. The seed now makes `G_Finance_Approvers` a member of
  `Q_Credit_Risk`.
- **Classic records the true actor too.** On a queue step, `ActorId` is the member who decided and
  `OriginalActorId` is the queue. On a first-response step, the approvers who did not act get a
  `NoResponse` history row, which the timeline already labels. §5.4's case for Flow on group
  steps is narrower than its table said.
- **Portability is proven offline only.** `force-app` converts with another org's domain, and it
  holds no `amf-dev` value. The playbook's guardrail allows `amf-dev` alone, so no second org was
  used.

**The first UI run (M12.6) found:**

- **The timeline's times followed the browser's time zone.** Given no zone,
  `lightning-formatted-date-time` uses the device's, not the user's Salesforce setting. The agent's
  browser was on UTC−4 and Grok Bot on Pacific, so the timeline read 3 hours ahead of the related
  lists. Fixed in M12.6.
- **The LWC compiler drops a line break between text and a tag,** and a space with it, where HTML
  would render one. The "Approval history:" heading lost the space after its comma. Fixed in
  M12.6, and no other template has the pattern.
- **A related-list card shows four columns.** The Approval Decisions card shows Decision Log
  Number, Submitted At, Outcome and Matched Rule. Rule Version and Selected Process are on the log
  record and in the timeline.
- **A related-list card can lag a submission** (the re-run, M12.7). The Approval Decisions card
  read (0) until a reload, while the timeline already linked the new row. The submit action's
  `RefreshEvent` reached the timeline but not the card, and in the first run the card was current.
  The suite allows the reload.

---

## 3. Where the build stands: thirteen phases

| Phase | Delivered | Status |
|---|---|---|
| **M0** | Baseline: the `Matrix_Submission__c` guard on `Purchase_Request__c`; the v1.0 metadata retired | Complete |
| **M1** | Data model: `Approval_Matrix_Rule__mdt`, the immutable `Approval_Decision_Log__c`, the SOQL rule provider and its >255-character pin | Complete |
| **M2** | Expression evaluator, reduced grammar | Complete |
| **M3** | Engine, Classic strategy, two Purchase Request templates, the submit action: the MVP demo | Complete |
| **M4** | Configuration validator, the source gate, the post-deploy script | Complete |
| **M5** | Preview, and the submit action's confirmation modal | Complete |
| **M6** | Flow approvals spike, research only (`spikes/flow-approvals/`) | Complete; the unanimous value is still open |
| **M7** | Decision timeline LWC, Classic half | Complete; two display fixes in M12.6 |
| **M8** | Guard integrity: recall clears the guard; a record already in approval is refused | Complete |
| **M9** | The full §4.1 grammar | Complete |
| **M10** | The Flow invocable and REST entry points, and per-record bulk submission | Complete |
| **M11** | A second governed object, Opportunity | Complete |
| **M12** | Template lifecycle (release manifest), queue and committee templates, portability; M12.6, the first UI run and two timeline fixes; M12.7, the re-run; M12.8, a Request Name field and two list views | Complete |

The MVP was M0–M3; M4–M12 are post-MVP. **Nothing after M12.8 is numbered or authorised.** What is
left of architecture v3.0's target design is Flow approvals, probably two phases (M13 and M14, as a
proposal), plus the smaller gaps in 4.2.

---

## 4. What remains of the target design

`CLAUDE.md`'s out-of-scope list has been partly superseded:

| Status | Items |
|---|---|
| Superseded, now built | preview modal (M5), timeline LWC (M7), config validator (M4), bulk chunking (M10), recall handling for the templates' recall actions (M8), second object for Opportunity (M11), queue and committee templates on Classic (M12), `_v2` template versioning (M12) |
| Still out of scope | Flow strategy and `Execution_Type__c`, the template registry, approver resolution, chain objects, recall from the framework itself |

### 4.1 Major functionality: Flow approvals, the second execution strategy

Architecture §3.1, §3.3, §5.3, §5.4, §6.2, §8, §9 and §12. Rules would choose, one row at a time,
whether a record enters a Classic approval process or a Flow approval orchestration, with no
engine change upstream of the strategy. It adds:

1. **`Execution_Type__c`** (`Classic` | `Flow`) on the rule and on the log. Both were omitted in
   M1 (`docs/decisions.md`, 2026-08-17).
2. **`AMF_FlowApprovalStrategy`**, behind `AMF_SubmissionStrategy`. It launches the named
   orchestration with `Flow.Interview.createInterview(<ApiName>, inputs).start()`, which M6
   confirmed, and stamps the `ApprovalSubmission` Id at step 11.
3. **At least one Flow template**, on the contract M6 established at API 67 (§5.3). It is an
   orchestration plus a companion screen flow per approval step.
4. **A Flow history provider** behind `AMF_ApprovalHistoryProvider` for the timeline.
5. **Validator and gate checks:**
   - a Flow rule's process must be an *active* `ApprovalWorkflow` flow;
   - the source gate checks a Flow template's guard handling;
   - M12's release manifest extends to Flow templates. Their fingerprint needs its own
     exclusion, the flow's status, in place of `<active>`.
6. **A guard reset for cancelled submissions**, or cancel withheld operationally (§12 item 7).

Constraints:

- Engine classes stay at API ≤ 66 (§12 item 6). Flow metadata needs a newer `sourceApiVersion`,
  and raising it must not raise the classes' versions.
- `docs/spike-results.md` Round 2's migration checklist binds the phase.
- Literal approvers in a Flow template block packaging (§5.3), and a username there needs M12's
  placeholder too.

**Blocked, in part:** unanimous approval on Flow group steps. The value for
`requiresMultiMemberApproval` is unknown (§12 item 1). Finding it needs one change made by hand in
Flow Builder, then retrieved. Without it, committees stay on Classic, which M12 made possible.

**Cleanup it owns:** the M6 teardown, `spikes/flow-approvals/scripts/teardown.ps1`. It removes the
spike flows, groups and records, including PR-00000014 to PR-00000025 and their guards.

### 4.2 Smaller gaps, not phases

| Gap | Detail | Source |
|---|---|---|
| A second org | `force-app` has not been deployed to one. In one, the admin also removes the standard Submit button from that org's own layouts | M12.5 |
| Template drift in the org | The gate governs source. A template edited in Setup is found only by retrieving and comparing (M12.4, step 5), which is not scripted | M12.5 |
| `AMF_CmdtRuleProviderTest` | One test reads the org's shipped rules and pins the first one, so a new lowest-priority rule breaks it | M12.3b |
| DateTime fields and literals | Refused at compile; needs a time-zone decision | §4.3, M9.5 |
| Email, Phone, URL, Text Area fields | Refused; each is a type-map entry plus tests | playbook Part 5 |
| Field-to-field multipicklist comparisons | Refused | M9.5 |
| UI strings | English literals; Custom Labels when translation is needed | M7.6 |
| Mobile | Phones keep the default record page, so no timeline there | M7.6 |
| Rule descriptions | Not snapshotted, so the timeline names rules by DeveloperName | `docs/decisions.md`, 2026-10-08 |
| Approvers and the routing reason | Approvers cannot read other submitters' log rows; a sharing decision | `docs/decisions.md`, 2026-10-08 |
| `Lock_Decision_Log` | Still permits one post-insert stamp that nothing performs | M10.6 |
| Preview and guard failures | A record a validation rule will refuse still previews as routable | M10.7h |
| The final-approval lock outside a test | Unmeasured | M10.8a |
| LWC tidy-up | `messageOf` duplicated in two LWCs; `.prettierrc` indents 2, the code 4 | M7.6 |
| The Approval Decisions card | Shows four of its six columns, Lightning's limit for the Related Lists component. Reordering them, or an enhanced list, would bring Selected Process onto it | M12.6 |
| Related lists after a submission | Can show their earlier state until a reload. Finding what refreshes them needs someone in the browser | M12.7 |
| husky pre-commit | Would reformat whole files; commits run with `HUSKY=0` | M10.7 |

### 4.3 Deliberately not planned

- **Approver resolution, chain objects, the Group Work Item pattern, the Approval Inbox and the
  SLA batch.** Superseded at the v2.1 pivot (architecture Appendix B).
- **A template registry.** Only if §12 item 4's threshold is reached: dozens of rules sharing
  shapes. M12's manifest records releases, not routing, and is no registry.
- **Recall from the framework itself.** Out of scope in `CLAUDE.md`. Classic's native recall
  works and clears the guard on all six templates.

---

## 5. Suggested order

1. **Flow approvals (4.1).** Decide first whether committee steps are wanted on Flow. If they are,
   a person must find the unanimous value in Flow Builder before the phase. If not, it can be
   built with named and any-member steps, and committees stay on Classic.
2. **A hardening pass** for 4.2 whenever convenient. `Lock_Decision_Log`, the provider test's
   coupling and a scripted drift check would fit together.

## Decisions waiting on the user

1. Choose the next phase and authorise it in `CLAUDE.md`. For Flow approvals, say whether
   committee steps are wanted on Flow.
