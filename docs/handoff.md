# Handoff — what's next after M13

**As of 2026-10-23.** `develop` holds Phase M13, AI around the engine (commit `e81f487`). Gate steps
0 to 10 passed in `amf-dev` (technical log M13.7); only step 11, the manual UI check, is owed. M13
added two things, and neither decides anything (architecture §1, principle 6: AI assists; it never
decides):
- **The Approval Matrix Assistant**, an Agentforce employee agent. It finds a governed record,
  previews its route, submits it once the user confirms, and explains it, all through the engine's
  own paths. It cannot approve, reject, recall or reassign.
- **Plain-English explanations** on the decision timeline: an Explain button on each entry with a
  decision. Einstein writes the explanation from the recorded facts alone. It is labelled
  AI-generated and never stored.

M12 and its follow-ups M12.6 to M12.8 are complete, with no check owed.

This is the short version. The sources are:

- `docs/technical-log.md`: the status board, M13, and M13.7's table of open items;
- `docs/decisions.md`: M13's design choices, dated 2026-10-23;
- `docs/ui-tests/`: the UI test suite, and the guide for whoever runs it;
- `docs/build-playbook.md`: Part 3's gates, including M13's step 11, and Part 5's roadmap;
- `docs/architecture.md`: v3.0, the target design this document measures progress against.

A fresh session reads `CLAUDE.md` first: it decides what is authorised.

**Deploying changed in M13.** There are now three package directories:
- `force-app`, the framework, which deploys to any org;
- `agentforce`, the agent and the prompt template, which deploy only where Einstein generative AI
  and Agentforce are on;
- `org-config/amf-dev`, this org's own configuration.

Set `AMF_USERNAME_DOMAIN` first, as since M12, or the CLI refuses the deploy. In PowerShell:

```powershell
$env:AMF_USERNAME_DOMAIN = 'amf.00daj000012gj9b.dev'
sf project deploy start -o amf-dev
```

That deploys all three. In another org, deploy `--source-dir force-app` with that org's domain, and
add `--source-dir agentforce` only where Einstein generative AI and Agentforce are on.

Two kinds of change need a step after the deploy:
- **The agent.** A deploy does not change the agent people talk to. After editing the `.agent`
  file, deploy it, then publish and activate it:

  ```powershell
  powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-agent.ps1
  sf agent test run --api-name AMF_Approval_Assistant_Tests --wait 10 -o amf-dev
  ```

  Every publish is a new, permanent version; v2 is active now. The tests should pass 9 of 9.
- **The prompt template.** Editing its content makes a new version, which Einstein does not use
  until the source names it. Deploy, retrieve the template, and take the retrieved form, with its
  `activeVersionIdentifier`, into source (technical log M13.7a).

---

## 1. Owed by the user — M13's manual UI check

### Gate step 11 (playbook M13)

As the admin, in the browser:

1. **The Explain button.** On PR-00000042, open the newest Approval Timeline entry. Its details
   open with **Explain in plain English**. Click it:
   - "Einstein is writing…" shows first;
   - then a card with an *AI-generated* badge and "Written by Einstein at … from decision log
     ADL-00000027";
   - the recorded rule, condition and values stay below the card;
   - the refresh icon writes it again.
2. **The assistant.** Create a throwaway Purchase Request: Amount 60,000, Region AMER, Risk Level
   Medium. Do not use PR-00000045 to -48, because the agent tests read them. Open the Agentforce
   panel and choose **Approval Matrix Assistant**:
   - "Where would this go?" names `PR_Credit_Risk_Queue`, decided by `PR_Credit_Risk_Review`, and
     submits nothing.
   - "Submit it" asks for confirmation. Confirm, and it reports the process and that it is waiting
     on Credit Risk.
   - The timeline's refresh button shows the new entry. The panel cannot refresh the page itself.
   - "Why did it go there?" explains it.
   - Recall the throwaway afterwards. *Matrix Submission* unticks.

The assistant check also settles two things the CLI could not show (technical log M13.7):
- **The page context.** Testing Center passed the open record to the agent as `currentRecordId`
  and `currentObjectApiName`. If the assistant asks which record "this" is, the panel probably
  passes other names. Then only the two declarations in the `.agent` file change.
- **The confirmation.** The platform asks before submit runs, and the agent's instructions also
  tell it to ask. If you are asked twice, the two prompts need merging into one.

Record the result in the technical log as **M13.8**.

### Also open

- **Grok Bot holds System Administrator in `amf-dev`**, for the UI suite. Deactivate it, or return
  it to Standard User, between runs.
- **The demo requests PR-00000045 to -48** (M12.8) now also serve the agent tests. PR-00000045 was
  submitted and approved on 2026-10-23; -46 to -48 have never been submitted. Submitting any of
  them in a demo changes what the tests expect, so demonstrate submission on a new record.
- **Seven approvals are pending, all left by earlier phases:**
  - PR-00000002, -03, -05, -06 and -07, from M3 to M5;
  - PR-00000027 and -28, from M10.8.

  No open check needs them. Recall any that are not wanted for demos. The first five entered their
  process before M8 gave recall its guard-clearing action, so check that *Matrix Submission*
  unticks on those. M7.8's query finds any record left with the guard set.

---

## 2. What M13 found

- **Agentforce is turned on by a person, in Setup** (gate step 0). Source holds no settings file
  that would switch it on, so a routine deploy never does. While it is off, the agent bundle
  refuses to deploy: "Not available for deploy for this organization".
- **A deployed prompt template has no active version unless its source names one.** Einstein
  answered "No active template version" until the source took the retrieved form, with
  `activeVersionIdentifier`.
- **`sf agent publish authoring-bundle` reads only the default package directory,** and takes no
  path. With the bundle in `force-app`, `force-app` would no longer deploy to an org without
  Agentforce, so `scripts/publish-agent.ps1` publishes from a throwaway project instead.
- **`sf agent test create` writes its definition into `force-app`.** The definition names
  `amf-dev`'s records and needs the published agent, so it lives in `org-config/amf-dev`. Move it
  there again after every `test create`.
- **Testing Center has its own names and guardrails.**
  - It reports the router as `topic_selector`, and each subagent by its own name.
  - Its built-in **Reverse_Engineering** guardrail declined "Which rule applies to this request?"
    as an attempt to extract the agent's own rules. The agent's instructions now say that the
    matrix's rules are business data, which the actions read.
- **`Actor.Name` is null on approval rows created in the same transaction.** That would have left
  the agent unable to say who a new approval waits on, in production as well as in tests. Names are
  resolved from `ActorId` against User and Group.
- **Descriptions are capped at 255 characters** on a prompt template and on a permission set. One
  over the limit rolls back the whole deploy.
- **An `AuraHandledException` thrown outside an Aura or Visualforce request becomes a
  `LimitException`,** which hides the real error. Scripts call `explain()`, not the `@AuraEnabled`
  wrapper.

M12's findings, such as the platform rewriting a template on deploy, are in the technical log,
M12.3 to M12.7.

---

## 3. Where the build stands: fourteen phases

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
| **M13** | AI around the engine: the Approval Matrix Assistant, an Agentforce employee agent, and plain-English explanations on the timeline | Complete, bar the manual UI check (step 11) |

The MVP was M0–M3; M4–M13 are post-MVP. M13 also extended the design itself: architecture §1
gained principle 6. What is left of architecture v3.0's target design is Flow approvals, probably
two more phases, which are now proposals with no number, plus the smaller gaps in 4.2. Three more AI
use cases are proposed (4.3).

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

- Engine classes stay at API ≤ 66 (§12 item 6). Flow metadata needs a `sourceApiVersion` above
  M13's 66.0, and raising it must not raise the classes' versions.
- `docs/spike-results.md` Round 2's migration checklist binds the phase.
- Literal approvers in a Flow template block packaging (§5.3), and a username there needs M12's
  placeholder too.
- The explanations read a decision's approval history from the timeline. For a Flow decision they
  would describe the approval only once the Flow history provider (item 4) exists.

**Blocked, in part:** unanimous approval on Flow group steps. The value for
`requiresMultiMemberApproval` is unknown (§12 item 1). Finding it needs one change made by hand in
Flow Builder, then retrieved. Without it, committees stay on Classic, which M12 made possible.

**Cleanup it owns:** the M6 teardown, `spikes/flow-approvals/scripts/teardown.ps1`. It removes the
spike flows, groups and records, including PR-00000014 to PR-00000025 and their guards.

### 4.2 Smaller gaps, not phases

| Gap | Detail | Source |
|---|---|---|
| A second org | `force-app` has not been deployed to one. In one, the admin also removes the standard Submit button from that org's own layouts | M12.5 |
| An org without Einstein | `force-app` deploys, and the Explain button answers "not available" with the platform's reason. Hiding the button there would be a timeline change | M13.7 |
| Template drift in the org | The gate governs source. A template edited in Setup is found only by retrieving and comparing (M12.4, step 5), which is not scripted | M12.5 |
| `AMF_CmdtRuleProviderTest` | One test reads the org's shipped rules and pins the first one, so a new lowest-priority rule breaks it | M12.3b |
| DateTime fields and literals | Refused at compile; needs a time-zone decision | §4.3, M9.5 |
| Email, Phone, URL, Text Area fields | Refused; each is a type-map entry plus tests | playbook Part 5 |
| Field-to-field multipicklist comparisons | Refused | M9.5 |
| UI strings | English literals; Custom Labels when translation is needed | M7.6 |
| Mobile | Phones keep the default record page, so no timeline there | M7.6 |
| Rule descriptions | Not snapshotted, so the timeline names rules by DeveloperName | `docs/decisions.md`, 2026-10-08 |
| Approvers and the routing reason | Approvers cannot read other submitters' log rows; a sharing decision. The explanations inherit it, because they are built from the timeline's view | `docs/decisions.md`, 2026-10-08 |
| `Lock_Decision_Log` | Still permits one post-insert stamp that nothing performs | M10.6 |
| Preview and guard failures | A record a validation rule will refuse still previews as routable, in the modal and in the assistant | M10.7h |
| The final-approval lock outside a test | Unmeasured | M10.8a |
| LWC tidy-up | `c/amfErrors` now holds `messageOf`, but `amfSubmitForApproval` and `amfDecisionTimeline` still carry their own copies; `.prettierrc` indents 2, the code 4 | M7.6, M13.7 |
| The Approval Decisions card | Shows four of its six columns, Lightning's limit for the Related Lists component. Reordering them, or an enhanced list, would bring Selected Process onto it | M12.6 |
| Related lists after a submission | Can show their earlier state until a reload. Finding what refreshes them needs someone in the browser. After the assistant submits, the timeline too needs its refresh button | M12.7, M13.7 |
| The UI test suite | Has no M13 case yet | M13.7 |
| The agent tests | The spec and its definition name `amf-dev`'s records, so they run in this org only | M13.7 |
| husky pre-commit | Would reformat whole files; commits run with `HUSKY=0` | M10.7 |

### 4.3 AI: three more use cases, proposed

The user chose two of five AI use cases for M13. The other three are in the playbook's Part 5, and
each needs its own authorisation. Principle 6 binds them all:
- **A rule-writing assistant.** An admin describes a rule, and a model drafts `Expression__c` and
  a priority. `AMF_ExprCompiler` and the validator must accept the draft before any person sees
  it, and it ships as an ordinary configuration release.
- **An approver briefing** on the work item.
- **A matrix-health report** over the decision log: the catch-all's share, and trends in blocked
  or failed decisions.

Lightning types, for richer cards in the agent panel, are a possible follow-up to M13. They were
left out because they could not be exercised here, and the actions' sentences already carry every
fact (`docs/decisions.md`).

### 4.4 Deliberately not planned

- **Approver resolution, chain objects, the Group Work Item pattern, the Approval Inbox and the
  SLA batch.** Superseded at the v2.1 pivot (architecture Appendix B).
- **A template registry.** Only if §12 item 4's threshold is reached: dozens of rules sharing
  shapes. M12's manifest records releases, not routing, and is no registry.
- **Recall from the framework itself.** Out of scope in `CLAUDE.md`, and the assistant refuses
  it. Classic's native recall works and clears the guard on all six templates.

---

## 5. Suggested order

1. **M13's step 11 (section 1).** It may change the `.agent` file, so it comes before other work.
2. **Flow approvals (4.1).** Decide first whether committee steps are wanted on Flow. If they are,
   a person must find the unanimous value in Flow Builder before the phase. If not, it can be
   built with named and any-member steps, and committees stay on Classic.
3. **A hardening pass** for 4.2 whenever convenient. `Lock_Decision_Log`, the provider test's
   coupling, a scripted drift check and the `messageOf` copies would fit together.
4. **The AI proposals (4.3)**, in whatever order the user chooses, once authorised.

## Decisions waiting on the user

1. M13: the manual UI check, its gate's step 11 (section 1).
2. Whether to turn on Einstein's Trust Layer prompt-injection and toxicity detection in `amf-dev`.
   Both are off, so the template's rule that the facts are data is the only defence against an
   approver comment written as an instruction.
3. Choose the next phase and authorise it in `CLAUDE.md`. For Flow approvals, say whether
   committee steps are wanted on Flow. For AI, say which of 4.3's proposals, if any.
