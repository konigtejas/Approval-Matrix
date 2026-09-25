# Building the Approval Matrix MVP with Claude Code — Phased Playbook

Four phases, **M0–M3**, each small enough to review in one sitting and each built in its
own chat session. Every phase has a goal, a paste-able prompt, machine-checkable
acceptance criteria, and a manual QA step **you** do in the org before committing.

`docs/architecture.md` (**v3.0**) is the single source of truth. Every prompt below points
Claude Code at specific § sections instead of restating the design, which is what keeps the
phases consistent with each other. §13 of that document is the MVP scope; anything in
§1–§12 that §13 does not list is **not built yet**.

> **This file replaces the v1.0 nine-phase plan.** That plan built chained single-step
> approval processes, approver resolution, the Group Work Item pattern, an Approval Inbox
> and an SLA batch — all of which left the design at the v2.1 pivot and are recorded in
> `docs/architecture.md` Appendix B. Phases 0 and 1 of the old plan are history, at commits
> `e3ac256` and `a69e3c9`; Phases 2–8 were cancelled and never built.

---

## Part 1 — Working Rhythm (applies to every phase)

**The loop per phase:**

1. `/clear` — start each phase with a clean context. Claude Code re-reads `CLAUDE.md`,
   `docs/architecture.md` and the most recent `docs/technical-log.md` entry; carrying four
   phases of conversation history degrades output and spends context on stale detail.
2. **Plan mode first** (Shift+Tab). Paste the phase prompt, let it produce a plan, and
   *read the plan* before approving. This is where you catch it inventing schema or drifting
   from the doc — two minutes here saves an hour of unwinding.
3. **Implement** — approve the plan, let it work.
4. **Gate** — Claude Code runs the acceptance commands itself and shows you passing output.
   Never accept "this should work."
5. **Manual QA** — you click through the org check listed in the phase. Claude Code cannot
   see the approval UI; work items, record locking and email notifications need human eyes.
6. **Log and commit** — a full `docs/technical-log.md` entry, the status board updated, then
   one commit per phase, message `Phase MN: <name>`, pushed to `develop`. If a phase went
   sideways, `git checkout .` and re-running it with a sharper prompt beats asking it to
   patch a mess.

**Guardrails to state once and enforce:**

- Never edit files outside the phase scope — each prompt lists allowed paths.
- Never "improve" the architecture. Deviations are proposed as questions, not committed as
  code. An approved one gets a line in `docs/decisions.md` and a fix to the doc itself.
- All org interaction through the `sf` CLI against `amf-dev`, never another alias.
- Out-of-MVP items (`CLAUDE.md`'s exclusion list) are not built, not stubbed, not mentioned
  in code comments as "future".

**Machine environment notes (this workstation):**

- `sf data query` fails under the Bash tool with `'C:\Program' is not recognized` — a
  Windows path-quoting failure in the Git Bash shim, not a CLI or org problem. When the
  PowerShell tool is available, verification queries go through it; when it is not,
  they go through anonymous Apex (`sf apex run --file`). `sf org display`,
  `sf org list metadata`, `sf project deploy` and `sf apex run` all work under Bash.
- `sf data query -t` is `--use-tooling-api`, not a table-format flag. Querying a `__mdt`
  through Tooling reports fields as missing that are present.

---

## Part 2 — What the MVP has to prove

One sentence, from §13: **an admin changes one Custom Metadata row, the next submission
routes to a different approval process, and a log record explains why.**

Everything else — Flow execution, the preview modal, the timeline LWC, the config
validator, bulk chunking, recall, a second object — is hardening, and is out of scope
until that demo passes.

The MVP's moving parts:

```
Submit quick action (LWC)
      ▼
AMF_ApprovalMatrixService
   ├── RuleProvider ◄── AMF_CmdtRuleProvider (SOQL, never getAll)  §3.1
   ├── AMF_ExprCache ► AMF_ExprCompiler ► AMF_Lexer, AMF_Parser     §4.2
   ├── AMF_Evaluator                                                §4.2
   ├── AMF_FieldPathResolver  (one dynamic SOQL per object)         §4.4
   ├── AMF_DecisionLogWriter                                        §3.3
   └── SubmissionStrategy ◄── AMF_ClassicProcessStrategy            §6.2
      ▼
PR_Two_Level_Mgmt  |  PR_Three_Level_Finance     (native Classic processes, §5.2)
```

---

## Part 3 — The Phases

### M0 — Baseline & cleanup

**Goal:** the repo and `amf-dev` both hold exactly the surviving Phase 0/1 work plus the
guard field, and nothing from the v1.0 design. Nothing new is designed in this phase.

**Prompt:**
> Phase M0. Bring repo and org to the v3.0 baseline. (1) Add `Matrix_Submission__c`
> (Checkbox, default false) to `Purchase_Request__c` per §3.4, with read/edit FLS in both
> permission sets — §1.4d of the technical log establishes that a field deployed without
> FLS is invisible even to the deploying admin, so FLS is a runtime prerequisite, not
> packaging. (2) Retire the last v1.0 metadata: `Approval_Chain__c` and its
> `Lock_Terminal_Chain` validation rule, and the `AMF_Bypass_Chain_Lock` custom permission
> with its grant in `Approval_Matrix_Admin` — from the repo and destructively from the org.
> (3) Delete the `AMF_Spike_Approval` draft flow from the org; Appendix A says to delete or
> complete it and Flow execution is out of MVP scope. (4) Re-run `scripts/seed-data.apex`
> and confirm it is still idempotent and that `Q_Credit_Risk` still supports
> `Purchase_Request__c`. Allowed paths: `force-app`, `docs`, `CLAUDE.md`. Do not create the
> CMDT, the decision log, or any Apex.
>
> Acceptance: full-package deploy green; `Approval_Chain__c` absent from
> `sf org list metadata -m CustomObject`; anonymous-Apex describe confirms
> `Matrix_Submission__c` exists as a Checkbox and is visible to the running user; seed
> reports zero creations.

**Gate:** deploy + seed green, guard field describes clean.

**You verify:** before this phase can finish, erase the soft-deleted
`Purchase_Request__c.Active_Chain_del__c` — Setup → Object Manager → Purchase Request →
Fields & Relationships → Deleted Fields → **Erase**. It holds a relationship to
`Approval_Chain__c` from the recycle bin, where the Metadata API cannot see it, and it is
the reason the object survived the v2.1 revert.

---

### M1 — Data model

**Goal:** the matrix itself, the audit artefact, and the only sanctioned way to read
Custom Metadata.

**Prompt:**
> Phase M1. Build §3 for the MVP, §13.1's subset only. (1) `Approval_Matrix_Rule__mdt`
> with every field in the §3.1 table **except `Execution_Type__c`** (see
> `docs/decisions.md` — Classic-only in MVP), plus an `All` list view surfacing every
> field. (2) `Approval_Decision_Log__c` with every field in the §3.3 table except
> `Execution_Type__c`, the immutability validation rule, and the `AMF_Bypass_Log_Lock`
> custom permission it excepts — a custom permission, not a profile name, per §3.3.
> (3) Extend both permission sets to the new object and CMDT with explicit FLS;
> `Approval_Matrix_Admin` takes View All plus edit and **no** Modify All, because the
> platform makes Modify All depend on Delete and the log must not be deletable (§3.3).
> (4) `RuleProvider` interface, `AMF_RuleDefinition` DTO, and `AMF_CmdtRuleProvider`
> loading rules by **SOQL** — never `getAll()`/`getInstance()`, which truncate Long Text
> Area to 255 characters and would silently corrupt `Expression__c` (§3.1). Sort by
> `Priority__c` then `DeveloperName` **in Apex**, not SOQL: CMDT SOQL rejects `ORDER BY` on
> a parent relationship field and Apex ordering is what makes §6.1 step 2 deterministic.
> (5) Three sample rules as deployable CMDT records, written as expressions:
> high-value APAC, high-risk, and a priority-9999 `TRUE` catch-all (§3.2).
> Allowed paths: `force-app`, `docs`.
>
> Acceptance: deploy green; a test whose `Expression__c` **exceeds 255 characters** round
> trips through `AMF_CmdtRuleProvider` intact — this is the phase's headline gate; the
> provider is covered by tests that inject in-memory rules and touch no org CMDT row.

**Gate:** the >255-character expression test passes. If it passes with `getAll()`, the
test is wrong.

**You verify:** open the three CMDT records in Setup. They should read like a routing
matrix a bank admin would recognise, in priority order, with the catch-all visibly last.

---

### M2 — Expression evaluator

**Goal:** the hard part. The reduced grammar, compiled and evaluated, with zero dependence
on org configuration.

**Prompt:**
> Phase M2. Implement §4 at the §13.3 reduced grammar: `&&`, `||`, parentheses,
> `== != > >= < <=`; field paths up to 2 segments (`Account__r.Name`); types
> Number/Currency, String, Picklist, Boolean, Date; literals NUMBER, `'STRING'`, TRUE,
> FALSE, NULL, `YYYY-MM-DD`; bare `TRUE` as a complete expression, which is what makes the
> catch-all rule expressible. Classes: `AMF_Lexer` (tracking character position for error
> messages), `AMF_Parser` (recursive descent → AST), `AMF_ExprCompiler` (parse plus static
> analysis against the schema — every path resolves via describe, operator/type
> compatibility enforced at compile time, not runtime false), `AMF_ExprCache` (static map
> keyed by rule DeveloperName + `Version__c`), `AMF_Evaluator` (AST + SObject → Boolean
> plus the evaluated-values map), `AMF_FieldPathResolver` (union of paths → one dynamic
> SOQL per object, §4.4). Precedence per §4.1: comparisons bind tighter than `AND`, which
> binds tighter than `OR`. Null semantics per §4.3, exhaustively. §4.6 is
> non-negotiable: **no catch block anywhere in this package may swallow an exception into a
> boolean.** `IN`, `CONTAINS`, `STARTS_WITH`, `NOT`, `TODAY(±n)`, multipicklist and 3+ hop
> paths are deferred — structure the lexer, parser and AST so they are purely additive, and
> do not special-case around their absence. Delete `AMF_Ping`/`AMF_PingTest`, whose only job
> was to prove the deploy loop before real classes existed.
> Allowed paths: `force-app/main/default/classes`, `docs`.
>
> Acceptance: ≥90% coverage on the evaluator package (§13.4); table-driven suite of
> `(expression, field values, expected)` triples covering every operator against every
> supported type, all null rules, precedence, whitespace variants, two-segment paths and
> bare `TRUE`; plus a malformed-input suite — unbalanced parens, unknown field, over-deep
> path, bad literal, type mismatch — each asserting the **character position** in the
> error. Zero dependence on org CMDT rows.

**Gate:** ≥90% evaluator coverage, both suites green.

**You verify:** read `AMF_Evaluator` and `AMF_ExprCompiler` yourself. These are the classes
an architect will review and the one place subtle type bugs hide. Then run one anonymous
Apex evaluation against a real `Purchase_Request__c` and eyeball the evaluated-values JSON.

---

### M3 — Engine, templates, submit action

**Goal:** the demo. End to end, one rule change away from different routing.

**Prompt:**
> Phase M3. Implement §6 steps 1–11, Classic branch only, plus §5.2 and §7's UI row.
> (1) `SubmissionStrategy` interface + `AMF_ClassicProcessStrategy`, the **only** place in
> the codebase that calls `Approval.process()`, via
> `ProcessSubmitRequest.setProcessDefinitionNameOrId(processApiName)`, returning
> `ProcessInstance` Ids. (2) `AMF_ApprovalMatrixService.submit(List<Id>)` running §6.1
> exactly: rules by priority → first true expression wins → no match writes a
> `Blocked_No_Match` log row and throws a clear error → write the decision log with rule,
> version, expression snapshot and evaluated-values JSON → set `Matrix_Submission__c = true`
> in the same transaction, before submit → submit → stamp `Execution_Ref_Id__c` back onto
> the log row. A runtime evaluation error marks the row `Failed`, writes the exception to
> `Failure_Detail__c`, and **blocks** — it never falls through to the next rule (§4.6).
> (3) `AMF_DecisionLogWriter`. (4) Two Classic approval processes as metadata XML per §5.2:
> `PR_Two_Level_Mgmt` — two steps up the Manager hierarchy; `PR_Three_Level_Finance` —
> three named-user steps (`amfu3` → `amfu4` → `amfu5`). Both carry entry criteria
> `Matrix_Submission__c = true` (the §6.3 guard) and both reset it to false in their final
> approval *and* rejection actions, re-arming the guard. (5) The `amfSubmitForApproval`
> headless LWC quick action — **no preview modal** (§13.1); it submits and reports the
> matched rule and process. Remove the standard **Submit for Approval** button from the
> `Purchase_Request__c` layout (§6.3). Bulk chunking is out of MVP scope.
> Allowed paths: `force-app`, `docs`.
>
> Acceptance: deploy green; unit tests use a stub `SubmissionStrategy` asserting the staged
> guard field and the selected process name without executing a real approval; one thin
> integration test exercises the real `Approval.process()` path; Jest test for the LWC.

**Gate — the MVP's whole point, and it is manual:** submit a record that routes to
`PR_Two_Level_Mgmt`. Then edit that rule's `Process_API_Name__c` in Custom Metadata to
`PR_Three_Level_Finance`, redeploy the CMDT record **only**, and submit an identical
record. It must route to the three-level process **with no Apex changed and no deploy of
code**. Read both decision log rows side by side: same expression, different process, and
each row explains itself.

**You verify, in this order:**

1. Submit a matching record → correct process, work item lands with the right approver,
   record locks.
2. Open the `Approval_Decision_Log__c` row → matched rule, version, expression snapshot,
   evaluated values JSON, `Execution_Ref_Id__c` populated and joining to `ProcessInstance`.
3. Approve through to the end → `Matrix_Submission__c` is back to false.
4. Reject instead, on a second record → also back to false.
5. Submit a record that matches no rule with the catch-all deactivated → blocked, with a
   `Blocked_No_Match` row explaining it. Nothing routes silently.
6. Try to edit a decision log row → blocked by the immutability rule.
7. The rule-flip demo above.

Budget an hour for this phase's QA. It is the heart of the framework and the only place the
"config release, not a code release" claim is actually proven.

---

### M4 — Configuration validator (post-MVP)

**Goal:** fail a release before an invalid active matrix rule can reach a submission.

**Build:** `AMF_ConfigValidator` compiles every active rule; rejects duplicate priorities;
requires the Checkbox `Matrix_Submission__c` guard; and verifies every referenced Classic
process is active for the governed object. `AMF_ApprovalProcessProvider` isolates the
`ProcessDefinition` query so unit tests use an in-memory process catalog. Expose the validator
as an invocable action and add `scripts/validate-config.apex` as the post-deploy CI gate.

Salesforce does not expose an approval process's entry criteria on `ProcessDefinition`, so the
repository-side `scripts/validate-approval-matrix-source.ps1` validates each active rule's
referenced template file, activation state, and exact `Matrix_Submission__c = TRUE` guard
formula before the metadata deploy.

**Gate, in order:**

1. `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-approval-matrix-source.ps1`
2. Deploy the package.
3. `sf apex run --file scripts/validate-config.apex -o amf-dev`
4. Run `sf apex run test -o amf-dev -l RunLocalTests -w 10 -r human`.

Acceptance: both gates pass against the shipped matrix; unit tests cover a valid matrix, an
invalid expression with its character position, duplicate priorities, an absent process, an
absent guard field, and the throwing pipeline path.

---

## Part 4 — When Things Go Wrong

- **Claude Code invents schema** (a field not in §3): stop it, point at the doc, restate
  the `CLAUDE.md` rule. If it happens twice in a phase, `/clear` and re-run the phase — a
  context that has argued with you produces worse code than a fresh one.
- **A phase reveals a real doc gap:** fix `docs/architecture.md` first, log one line in
  `docs/decisions.md`, then continue. The doc stays truthful or the later phases rot.
- **A deploy fails with `UNKNOWN_EXCEPTION` and zero component errors:** do not retry it —
  **split it**. Deploy `--source-dir` per group until the API attributes real errors. This
  cost most of an afternoon in Phase 1 and hid two genuine bugs.
- **Fields describe as missing but `FieldDefinition` says they exist:** it is FLS, not a
  stale describe cache. Assign one of the two permission sets to the running user.
- **Tests pass but org behavior is wrong:** most likely in M3, where approval mechanics
  resist unit testing. Trust your manual QA over the green run, and hand Claude Code the
  *observed* org behavior verbatim as the bug report.
- **Context feels degraded** (repeating itself, forgetting conventions): `/clear` costs
  nothing. `CLAUDE.md`, the architecture doc and the technical log carry the state — the
  conversation does not.
