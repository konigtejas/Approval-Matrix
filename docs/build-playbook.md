# Building the Approval Matrix Framework with Claude Code — Phased Playbook

Nine phases, each small enough to review in one sitting. Every phase has a goal, a paste-able prompt, machine-checkable acceptance criteria, and a manual QA step **you** do in the org before committing. The architecture document (`docs/architecture.md`) is the single source of truth — every prompt points Claude Code at specific sections instead of restating the design, which keeps the phases consistent with each other.

---

## Part 1 — Working Rhythm (applies to every phase)

**The loop per phase:**

1. `/clear` — start each phase with a clean context. Claude Code re-reads `CLAUDE.md` and the architecture doc; carrying 4 phases of conversation history degrades output and wastes context on stale detail.
2. **Plan mode first** (Shift+Tab). Paste the phase prompt, let it produce a plan, and *read the plan* before approving. This is where you catch it inventing schema or drifting from the doc — 2 minutes here saves an hour of unwinding.
3. **Implement** — approve the plan, let it work.
4. **Gate** — Claude Code must run the acceptance commands itself (deploy + tests) and show you passing output. Don't accept "this should work."
5. **Manual QA** — you click through the org check listed in the phase. Claude Code cannot see the approval UI; work items, lock behavior, and email notifications need human eyes.
6. **Commit** — one commit per phase, message `Phase N: <name>`. If a phase went sideways, `git checkout .` and re-run the phase with a sharper prompt beats asking it to patch a mess.

**Guardrails to state once and enforce:**

- It must **never edit files outside the phase scope** — the prompt for each phase lists allowed paths.
- It must **not "improve" the architecture**. Deviations are proposed as questions, not committed as code.
- All org interaction through `sf` CLI against the dev org alias, never a prod alias in the project config.

---

## Part 2 — One-Time Setup

### 2.1 Repo layout

```
approval-matrix/
├── CLAUDE.md
├── docs/
│   ├── architecture.md          — the architecture document
│   └── decisions.md             — Claude Code appends here when you approve a deviation
├── force-app/main/default/      — shared core
├── force-app/objects/           — per-object add-ons (Phase 8 splits this out)
├── scripts/
│   ├── seed-data.apex           — users/queues/groups/test records
│   └── validate-config.apex
└── sfdx-project.json
```

### 2.2 CLAUDE.md (paste this in, adjust org alias)

```markdown
# Approval Matrix Framework

Salesforce DX project. Hybrid approval routing framework: Custom Metadata rules,
Apex evaluation engine, chained single-step native Approval Processes.

## Source of truth
docs/architecture.md defines ALL schema, class responsibilities, and patterns.
Section references (§) in tasks point there. If a task seems to conflict with the
doc, or the doc is ambiguous, STOP and ask — never guess, never redesign.
Approved deviations get one line in docs/decisions.md.

## Environment
- Org alias: amf-dev (Developer Edition). Deploy: sf project deploy start -o amf-dev
- Run tests: sf apex run test -o amf-dev -l RunLocalTests -w 10 -r human
- Apex API version 62.0. LWC only (no Aura).

## Non-negotiable conventions
- All CMDT access via RuleProvider interface (§4.4). Engine classes NEVER query __mdt directly.
- All Approval.process()/unlock() calls via SubmissionStrategy (§11). Never inline.
- Unit tests use RuleBuilder + stub providers — zero dependence on org CMDT rows.
- Bulk-safe everywhere: List<Id> inputs, no SOQL/DML in loops.
- Every class: ApexDoc header stating its §section in the architecture doc.
- Naming: AMF_ prefix on all Apex classes; amf prefix on LWC.

## Scope discipline
Only touch files the current task allows. Do not refactor previous phases.
Do not create metadata the current phase doesn't require.
```

### 2.3 Kickoff prompt (once, before Phase 0)

> Read CLAUDE.md and docs/architecture.md fully. Summarize back to me: the chained single-step execution pattern (§6), the RuleProvider testability seam (§4.4), and the Group Work Item pattern (§5.1). List anything in the doc you find ambiguous or contradictory. Do not write any code.

If its summary is wrong, fix the doc *now* — a misreading here compounds through every phase.

---

## Part 3 — The Phases

### Phase 0 — Scaffold & connectivity

**Goal:** DX project, org connected, CI-able test command, empty-but-deploying package.

**Prompt:**
> Phase 0. Create the SFDX project scaffold per the repo layout in the playbook. Configure sfdx-project.json for API 62.0 with force-app as default package dir. Verify org connectivity by running `sf org display -o amf-dev` and a trivial deploy (a placeholder AMF_Ping class with one test). Create scripts/seed-data.apex that creates: 5 test users with a ManagerId chain (U1→U2→U3→U4→U5), one queue Q_Credit_Risk, one public group G_Finance_Approvers with 3 members, and the framework service user. Acceptance: deploy green, test run green, seed script runs without error. Touch nothing else.

**You verify:** log into the org, confirm the users/queue/group exist, manager chain is wired.

---

### Phase 1 — Data model

**Goal:** All CMDT types, chain objects, and per-object fields for the pilot object.

**Prompt:**
> Phase 1. Build the complete data model from §3 of docs/architecture.md exactly as specified — every CMDT type and field from §3.1, both chain objects from §3.2 with all fields, and a pilot custom object Purchase_Request__c (Amount__c currency, Region__c picklist [APAC, EMEA, AMER], Risk_Level__c picklist [Low, Medium, High], Vendor_Type__c picklist, Account__c lookup) with queues enabled, plus the three per-object fields from §3.3. Add the validation rule from §8 locking terminal chains. Create the two permission sets from §12 with object/field access. Also create 3 sample Approval_Rule__mdt records with conditions and route steps as deployable CMDT records: (a) Amount > 100000 AND Region = APAC → 3 user levels, (b) Risk_Level = High OR Vendor_Type = New → 2 levels ending in the Q_Credit_Risk queue, (c) catch-all priority 999 → 1 level manager chain. Allowed paths: force-app only. Acceptance: deploy green; describe calls in anonymous Apex confirm every field from §3 exists with correct types.

**You verify:** open the CMDT records in Setup, sanity-check the sample rules read like the matrix a bank admin would write.

---

### Phase 2 — Rule engine core (pure Apex, no submission)

**Goal:** The hard 60% — evaluator, expression parser, field-path resolver — fully unit-tested with zero org-config dependence.

**Prompt:**
> Phase 2. Implement §4 of docs/architecture.md: RuleProvider interface + RuleDefinition/ObjectConfig DTOs + CmdtRuleProvider (§4.4); AMF_ConditionEvaluator with the full typed-comparison table (§4.2) including all null semantics; AMF_LogicExpressionEvaluator (tokenizer → shunting-yard → RPN, grammar per §4.3) with deploy-time validation utility; AMF_FieldPathResolver that collects the union of field paths across rules and builds ONE consolidated dynamic SOQL per object (§4.1 step 3–4), enforcing the 4-hop limit. Implement AMF_RuleBuilder test fixture for in-memory rules. Evaluation must return: matched rule, per-condition results, and the evaluated-values map (this becomes Evaluated_Values__c later). NO approver resolution, NO chain writes, NO Approval.process in this phase. Tests: ≥95% coverage on evaluator/parser classes; must include — every operator × every DisplayType in the §4.2 table, expression edge cases (NOT, nested parens, blank expression = AND-all, malformed expressions rejected by the validator), null comparisons, multipicklist contains, cross-object path against standard objects (Account.Owner.Alias) per §11. Allowed paths: force-app/main/default/classes only.

**You verify:** read `AMF_ConditionEvaluator` yourself — this is the class an architect will review, and the one place subtle type bugs hide. Run one anonymous-Apex evaluation against a real Purchase_Request__c record and eyeball the evaluated-values JSON.

---

### Phase 3 — Approver resolution

**Goal:** Route steps → concrete users, per the §5 table.

**Prompt:**
> Phase 3. Implement AMF_ApproverResolver per §5: all five Approver_Type resolutions including Manager_Chain with the SUBMITTER:N reference format, recursive public-group expansion (nested groups and role members), queue member expansion, the active-user check with Fallback_Approver__c substitution + substitution flagging, and Skip_If_Same_As_Previous__c de-duplication. Group/queue levels resolve to a member snapshot structure (users + resolved-at timestamp) per §3.2 Group_Members_Snapshot__c — do NOT implement the work-item mechanics (that is Phase 6). Bulk-safe: resolve for 200 records in one pass, group/queue membership queried once per unique group. Tests with test users created in test setup (not org users), covering: 4-deep manager chain, chain shorter than requested hops (falls back + flags), inactive named user → fallback, nested group expansion, convergent chain de-dup. Allowed paths: classes only.

**You verify:** anonymous Apex resolving rule (b) — confirm the queue snapshot lists the right members.

---

### Phase 4 — Execution layer (the risky one)

**Goal:** Chained single-step process, ChainManager, SubmissionStrategy, Chain Advancer. **Do the §15 spike first, inside this phase.**

**Prompt (4a — spike):**
> Phase 4a, spike only. In the org, using anonymous Apex and a throwaway 1-step approval process on Purchase_Request__c, empirically answer: (1) does ProcessSubmitRequest.nextApproverIds accept a queue Id for a custom object with queues enabled, and what does the work item look like if so; (2) confirm Approval.unlock() then immediate re-submit works in one transaction and what happens if the second submit fails (is the record left unlocked?). Write findings to docs/spike-results.md with the exact code used. Change no project source.

Read the spike results with Claude Code before 4b — if queues work natively, §5.1 simplifies and you should adjust the architecture doc before continuing.

**Prompt (4b — build):**
> Phase 4b. Implement §6 and §7: the generic single-step Approval Process for Purchase_Request__c as metadata XML exactly per the §6.2 table including the entry-criteria guard; SubmissionStrategy interface + AMF_NativeProcessStrategy wrapping all Approval.process/unlock calls; AMF_ChainManager implementing advance() per §6.3 with the Queueable resubmit and the failed-resubmit → chain Failed + record-stays-locked behavior (§6.4); the record-triggered Chain Advancer flow on Chain_Step_Outcome__c change calling one invocable; chain lifecycle rules §7.1 (one active chain), §7.3 (re-check active at each hop), §7.4 (no re-eval on admin edit). Wire ApprovalMatrixService.submit(List<Id>) end to end: evaluate → resolve → write chain + steps → stage guard fields → submit level 1, per §4.1. Tests: stub strategy for unit tests; ONE integration test that runs a real 2-level chain end to end. Allowed paths: classes, flows, approvalProcesses, one invocable.

**You verify (the big one):** submit a record matching rule (a). As U1, approve from the work item; confirm the record stays locked, chain advances, U2 gets a work item. Reject at level 2; confirm chain = Rejected, record unlocked, outcomes on chain steps. Then try the standard Submit for Approval button on a fresh record — it must fail entry criteria. Budget an hour here; this is the heart of the framework.

---

### Phase 5 — Entry points

**Prompt:**
> Phase 5. Implement §9: headless LWC quick action amfSubmitForApproval on Purchase_Request__c that calls a preview method (evaluate + resolve WITHOUT submitting) and shows the matched rule + resolved chain in a modal before the user confirms submission; the SubmitForMatrixApproval invocable; the @RestResource wrapper. Server-side: preview and submit share one code path with a commit flag. Enforce §12 (read access required to submit). Remove standard Submit for Approval from the Purchase_Request__c layout. Jest tests for the LWC; Apex tests for invocable + REST. Allowed paths: classes, lwc, layouts.

**You verify:** the preview modal — this is your demo money shot. Check it renders a queue-level chain sensibly.

---

### Phase 6 — Group Work Item pattern + Approval Inbox

**Prompt:**
> Phase 6. Implement §5.1 (adjusted per docs/spike-results.md if the spike changed it): service-user work-item assignment for Queue/Public_Group levels; amfApprovalInbox LWC (home + record page) listing open group steps where the running user is in the membership snapshot, server-side membership re-verification (§12) before actioning; system-context ProcessWorkitemRequest actioning with Actual_Approver__c stamping; Group_Completion__c Any_Member and Unanimous semantics per §5.1 point 5 (unanimous vote tracking, any rejection closes); custom notification + email alert to members on assignment. Tests: membership spoofing rejected, unanimous partial-vote state, group actor stamped correctly. Allowed paths: classes, lwc, notifications, email alerts.

**You verify:** log in as a Q_Credit_Risk member and as a non-member. Member sees + can action the inbox item; non-member sees nothing and direct Apex actioning is rejected. Confirm `Actual_Approver__c` = the member, not the service user.

---

### Phase 7 — SLA escalation + config validator

**Prompt:**
> Phase 7. Implement §7.5: schedulable batch AMF_SlaEscalationBatch scanning open steps past SLA_Hours__c, executing per-step behavior (remind / reassign-to-fallback / skip-level), every action logged on the chain step. Implement scripts/validate-config.apex + AMF_ConfigValidator per §4.3 and §13.6: all expression indices exist, balanced parens, field paths resolve against real schema, ≤4 hops, route levels contiguous from 1, referenced queues/groups/users exist and active, no two active rules with equal priority on one object. Validator output: human-readable report of violations. Tests for batch behaviors and each validator rule. Allowed paths: classes, scripts.

**You verify:** deliberately break a CMDT rule (bad index, dead username) and confirm the validator names both violations clearly.

---

### Phase 8 — Portability proof + hardening

**Prompt:**
> Phase 8. (1) Onboard a second object (Vendor_Contract__c — create it with 3 fields) following the §13 checklist EXACTLY, restructuring the repo into force-app/main (shared core) and force-app/objects (per-object). If any step requires touching core code, STOP — that is an architecture violation to discuss, not fix silently. (2) Hardening: bulk test submitting 200 records in one call (chunked Approval.process per §10); recall + resubmit with Recall_Reevaluates__c both ways (§7 / §6.3); approver deactivated mid-chain (§7.3); second-submit-while-active rejected (§7.1). (3) A chain timeline LWC on the Approval_Chain__c record page addressing §14.1. Full regression: all tests green.

**You verify:** run the whole flow on Vendor_Contract__c yourself — if the second object works without touching core, the accelerator claim is real. Note the wall-clock time; that's your "half a day per object" evidence for the deck.

---

## Part 4 — When Things Go Wrong

- **Claude Code invents schema** (a field not in §3): stop it, point at the doc, restate the CLAUDE.md rule. If it happens twice in a phase, `/clear` and re-run the phase — a context that has argued with you produces worse code than a fresh one.
- **A phase reveals a real doc gap:** fix `docs/architecture.md` first, log one line in `docs/decisions.md`, then continue. The doc stays truthful or the later phases rot.
- **Tests pass but org behavior is wrong:** this happens most in Phase 4 (approval mechanics are hard to unit test). Trust your manual QA over the green run; give Claude Code the *observed* org behavior verbatim as the bug report.
- **Context feels degraded** (repeating itself, forgetting conventions): `/clear` costs nothing — CLAUDE.md and the doc carry the state, not the conversation.
