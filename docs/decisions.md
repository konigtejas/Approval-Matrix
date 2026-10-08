# Architecture Decisions

Log of approved deviations from `docs/architecture.md`. When a phase reveals a real
gap in the doc, fix the doc first, then append one line here — see the "When
Things Go Wrong" section of `docs/build-playbook.md`.

Format: `YYYY-MM-DD — <what changed> — <why>`

---

2026-10-08 — **A broken relationship path is *unknown*, under three-valued (Kleene) logic, not false** (§4.3, M9 note) — extends the 2026-08-18 entry below. "False" sufficed while expressions could only `&&` and `||` a comparison; `NOT` would turn it into a match (`NOT (Account__r.Name == NULL)` true for a record with no Account), the very presence check that entry forbids. `AND`/`OR`/`NOT` now treat it as SQL treats unknown, and a rule matches only on a definite true. No pre-M9 expression changes its result; a null *leaf* stays two-valued.

2026-10-08 — §4.1's **"NOT binds tightest, then comparisons" is read through its productions**: `NOT`'s operand is a `unary_expr`, so `NOT a == b && c` is `(NOT (a == b)) && c`. The prose's literal reading, `(NOT a) == b`, would apply `NOT` to a non-Boolean.

2026-10-08 — **`NULL` is refused in an `IN` comparison, in the list and as its operand** (§4.3, M9 note) — otherwise `Field__c IN ('A', NULL)` would be true for a blank field, contradicting §4.3's "`IN` with a null operand is false". `IN` is accepted for every single-valued type, not only the text types §4.3's table names, because it is defined as `==` against any one value.

2026-10-08 — **Multipicklists compare only with a `;`-separated text literal** (§4.3, M9 note): `==`/`!=` an exact set match in any order and case, `CONTAINS` membership of every listed value. Field-to-field, `IN`, `STARTS_WITH` and ordering on a multipicklist are refused, and a literal naming no values is a compile error — §4.3 defines none of them, and a guess would be a silent mis-route.

2026-10-08 — **`TODAY` is recorded in `Evaluated_Values__c` under the key `TODAY`** (§3.3, §4.3 M9 note) — a decision that depended on the date must say which date; `Submitted_At__c` alone cannot, because `TODAY` is the submitter's local date and their time zone is not recorded. `TODAY` is a reserved word, so the key cannot collide with a field path; the timeline and the preview show it as recorded.

2026-10-08 — §4.4's **path cap is four segments (three hops), and "platform limit" was wrong** — §4.1's "max 4 hops" is read in §13.3's unit, where `Account__r.Region__c` is two hops; SOQL itself allows five relationship hops (six segments), measured in `amf-dev`. One constant, `AMF_ExprCompiler.MAX_PATH_SEGMENTS`, now shared by the resolver, raises it.

2026-10-08 — **Supersedes the 2026-08-18 word-forms entry below:** `AND`, `OR` and `NOT` are accepted alongside `&&`, `||` and `!`, as §4.1 specifies — M9 authorised the full grammar, and the entry's own premise was that enabling them was "two entries and no parser change".

2026-10-08 — §5.2 **corrected: recall actions re-arm the guard too.** It named only the final approval and rejection actions, and both templates were built to it, so a recalled request kept `Matrix_Submission__c = true` and a submission bypassing the engine passed entry criteria unlogged (technical log M7.8). Both templates now clear the guard on recall, and the source gate fails any template that does not clear it on all three ways out of a process.

2026-10-08 — A **record already in an approval process is refused for the whole call, before step 1, with no decision log row** (§6.1, M8 note) — chosen by the user over a new `Outcome__c` value: nothing was decided, as with a record the caller cannot read, and a new value would change a restricted picklist that the lock rule and every report rely on. The check runs after authorisation, so it reveals nothing about a record the caller cannot read. Like the read-access check it condemns the whole call; per-record handling belongs with bulk entry points, if they are built.

2026-10-08 — §8's timeline names the matched rule by its **DeveloperName and version**, not by its description as §8's example sentence does ("Matched **High-value APAC** v3") — the log snapshots only `Matched_Rule__c`, and reading today's description from the live matrix into a past decision would let a later edit rewrite the explanation of an earlier one, which is the flaw §8 exists to fix; `Approval_Matrix_User` cannot read the matrix either (§11). Showing descriptions would take a new snapshot field on the log, not a timeline change.

2026-10-08 — The timeline shows **native approval history to anyone who can read the record, and a decision log row only to those who can read that row** — §11 gives `Approval_Matrix_User` its own rows, and the native half follows the rule the Approval History related list already applies. An approver therefore sees every approval and its steps, but the routing reason only for submissions whose row they can read; any other approval is shown and labelled as unexplained, not hidden. Letting approvers read the reason would be a sharing decision for `Approval_Decision_Log__c`, not a timeline change.

2026-10-07 — §5.3, §5.4, §12 and Appendix A **corrected to the M6 Flow spike's findings** (`docs/spike-results.md`, Round 2): the Flow template contract at API 67 (four inputs, `runInMode`, `stepBackground`, username approvers), the launch call confirmed as `Flow.Interview…start()` with a synchronous `ApprovalSubmission`, rejection not stopping later stages, recall running the recall path while cancel does not, and Apex API 67's user-mode default — because the platform moved between Round 1 (API 62) and Round 2, and §5.3 stated facts that no longer hold. No design decision changes: the Flow strategy remains unbuilt and out of scope, and unanimous group semantics remain open.

2026-09-18 — §9's configuration validator is a **source gate plus a required
post-deploy Apex gate**, not a literal metadata-deploy hook: Salesforce deploys cannot execute
Apex. `scripts/validate-approval-matrix-source.ps1` checks the source template's active state
and exact `Matrix_Submission__c = TRUE` entry criterion; `AMF_ConfigValidator` checks the
deployed active rules, expression compilation, duplicate priorities, Checkbox guard and active
Classic `ProcessDefinition` target. This split is necessary because `ProcessDefinition` exposes
no entry-criteria field to Apex SOQL. The post-deploy script throws on findings, making CI fail
before the new configuration is accepted.

2026-08-18 — §6.1 step 6's "throw a clear error" is implemented as a **per-record blocked Outcome**, not an exception; `AMF_ApprovalMatrixService.submit` throws only for faults condemning the whole call — nothing to submit, a mixed-object batch, a record the caller cannot read, an object with no active rules or no guard field, a rule that will not compile, a failed `Approval.process()`. The two halves of step 6 are mutually exclusive in Apex: an exception escaping the top of a request rolls back every DML before it, so throwing would erase the `Blocked_No_Match` row §3.3 exists to create. Catching it in every caller would preserve the row but make the audit trail depend on caller discipline, and would abort a batch at its first blocked record. This is not §4.6's forbidden catch-and-return-false — the evaluator still swallows nothing, the record still does not route, and the trace now outlives the transaction. Pinned by `AMF_ApprovalMatrixServiceTest.noMatchBlocksAndLeavesARowThatSurvivesTheTransaction`.

2026-08-18 — A rule that will **not compile blocks every record in the call**, rather than being skipped so lower-priority rules can still match — §4.6 at its sharpest, and the one place the MVP is stricter than a literal reading of §6.1. If the priority-10 rule cannot be evaluated, nobody can say a record would not have matched it, so letting the priority-20 rule pick it up is precisely the silent misrouting the framework exists to prevent. §9's config validator would move this to deploy time; §9 is out of MVP scope (§13.2), so it surfaces at submit. Pinned by `AMF_ApprovalMatrixServiceTest.aRuleThatWillNotCompileStopsEverythingRatherThanFallingThrough`.

2026-08-20 — §6.3's removal of the standard Submit for Approval button, and the placement of the framework's own action, are **both** `<platformActionList>` — not `<quickActionList>`. The standard button is the entry `Submit` / `StandardButton`; omitting it from `platformActionList` is the removal, and the platform re-adds it to the action bar whenever an approval process exists unless that list overrides it. An LWC quick action also **can** be deployed there, as `<actionType>QuickAction</actionType>`, though `quickActionList` refuses one outright ("You can't add QuickActionType LightningWebComponent to a QuickActionList", confirmed at API 62.0 and 64.0). The layout round-trips: retrieve and redeploy both preserve it.

2026-08-20 — **Supersedes the 2026-08-18 entry below on the same subject, which was wrong.** That entry claimed an empty `<quickActionList/>` suppressed the platform's default action set and therefore satisfied §6.3, and that a layout carrying the framework's action could not be redeployed. Neither holds: `quickActionList` and `platformActionList` are unrelated lists, `Submit` has never lived in the former, and the empty list removed nothing. It was reasoning by analogy from a stock `Account` layout rather than from an observed action bar, and it survived because M3 shipped before anyone looked at the record page — where the standard button and the framework's own action then appeared side by side under identical labels. *A claim about a UI, verified only by deploy status.*

~~2026-08-18 — An **LWC quick action cannot be placed in a page layout's `quickActionList` through the Metadata API** — the platform refuses with "You can't add QuickActionType LightningWebComponent to a QuickActionList", confirmed at API 62.0 and 64.0. The layout therefore ships with an **empty** `<quickActionList/>`, which is what satisfies §6.3's removal of the standard Submit for Approval button (declaring the list at all suppresses the platform's default set; `Edit`/`Delete`/`Clone` render as standard buttons and are absent from `quickActionList` on stock layouts too). Placing `AMF_Submit_For_Approval` on the layout is a Setup step, and a layout retrieved after that step is **not redeployable**, so the repo keeps the empty list deliberately rather than round-tripping the org's state.~~

2026-08-18 — The submit quick action is `<type>LightningWebComponent</type>` with `<lightningWebComponent>`, **not** §7's implied `LightningComponent`/`<lightningComponent>` pair — that pair resolves against Aura bundles only and fails with "Unable to retrieve lightning component by namespace/developer name" however the LWC is declared. Recorded because the error names the component rather than the element, which points the reader at the wrong file.

2026-08-18 — Word forms of the logical operators (`AND`, `OR`) are **not accepted** in the MVP; only `&&` and `||` are — §4.1 says both symbol and word forms are accepted "so admins may write `AND` and developers `&&`", while §13.3 and `CLAUDE.md` both list only the symbols, and `CLAUDE.md` is the override document. `TRUE AND FALSE` fails with `Unexpected token 'AND' at position 5` rather than routing on a half-read expression. `AMF_Lexer.KEYWORDS` is a table, so enabling the word forms later is two entries and no parser change. `NOT` / `!` stays deferred either way — §13.3 lists it explicitly.

2026-08-18 — §4.1's `bool_atom` is supported **in full**: `TRUE`, `FALSE` **and a bare Checkbox field path** are each a complete expression — §13.3 names only "bare `TRUE`" as in scope, but a boolean field path is absent from its deferred list, so it is part of the grammar rather than an extension of it. It costs no special-casing: a primary not followed by a comparison operator is a boolean atom, and `AMF_ExprCompiler` rejects it if the path is not Boolean-typed. `Amount__c` alone is a compile error naming the type.

2026-08-18 — When an **intermediate** step of a relationship path is null, the whole comparison is **false for every operator** — including `Account__r.Name == NULL` and `!= NULL`, which are both false when the record has no Account — while a leaf that resolves to null follows the ordinary null rules. §4.3 states both "null == null is true" and "null anywhere in a relationship path makes the comparison false"; the two collide on exactly this case and the second sentence wins. A path the engine could not resolve then routes nothing at all, rather than quietly satisfying a presence check. Pinned by `AMF_EvaluatorTest.relationshipPathsResolveAndBreakSafely`.

2026-08-18 — `Lock_Decision_Log` permits **exactly one** post-insert update — `Execution_Ref_Id__c` moving blank → populated with no other governed field changed — rather than freezing the row outright. §3.3 says the log "blocks edits after creation" while §6.1 step 11 requires the engine to stamp `Execution_Ref_Id__c` *after* submit; a blanket freeze would have made M3 impossible. Rows that never get stamped (`Blocked_No_Match`, `Failed`) freeze on insert. Known residual: that single stamping update could also alter the three Long Text Area fields, because `ISCHANGED` does not support that type. Pinned by `AMF_DecisionLogLockTest`.

2026-08-18 — One **inactive** CMDT record, `PR_Long_Expression_Pin`, is exempt from `CLAUDE.md`'s "zero dependence on org CMDT rows" — the >255-character round trip proves a *platform* behaviour (Long Text Area truncation) that no in-memory fixture can demonstrate, and `Approval_Matrix_Rule__mdt` cannot be inserted in a test (§10). The record ships in the repo rather than being org configuration, is `Active__c = false` so it routes nothing, and exactly one test class reads it. Every other rule test uses `AMF_RuleBuilder` fixtures.

2026-08-18 — The rule-provider interface is named **`AMF_RuleProvider`**, not the bare `RuleProvider` that §2, §10 and the M1 prompt all write — `CLAUDE.md`'s "AMF_ on Apex classes" is the override document and an interface is an Apex class file. Sets the precedent: M3's strategy interface is `AMF_SubmissionStrategy`.

2026-08-17 — Architecture consolidated into **v3.0**, self-contained, superseding v1.0/v2.0/v2.1; `docs/build-playbook.md` rewritten from the v1.0 nine-phase plan to the MVP's **M0–M3** — the old plan built chained single-step approvals, approver resolution, the Group Work Item pattern and an SLA batch, none of which are in the design any more.

2026-08-17 — `Execution_Type__c` omitted from **`Approval_Decision_Log__c`** as well as from `Approval_Matrix_Rule__mdt` — §3.3's table lists it on the log while §13.2 says do not build and do not stub it; with Classic the only MVP execution path the column would hold one constant value, and re-adding it is a field plus a default with no engine change. §3.3 and §13.1 annotated to match.

2026-08-17 — MVP template shapes fixed: `PR_Two_Level_Mgmt` = two Manager-hierarchy steps, `PR_Three_Level_Finance` = three named-user steps (`amfu3` → `amfu4` → `amfu5`) — §13.1 named both templates but specified neither's steps or approvers. Two visibly different shapes make the M3 rule-flip demo unambiguous, and the manager shape finally uses the chain seeded in Phase 0.

2026-08-17 — `Matrix_Submission__c` is **read-only** in `Approval_Matrix_User`, editable only in `Approval_Matrix_Admin` — §6.3 says only the engine sets the guard, so a submitter who can tick the box by hand defeats it. The engine's DML runs in system context and is unaffected by the FLS restriction.

2026-08-17 — `AMF_Bypass_Chain_Lock` retired in M0 rather than renamed — §3.3 of v3.0 calls the immutability bypass `AMF_Bypass_Log_Lock`, custom permissions cannot be renamed in place, and the chain validation rule that consumed it was deleted with `Approval_Chain__c`. The new permission is created in M1 alongside the log object it excepts.

2026-08-13 — Architecture superseded by v2.1 (Option A, Single CMDT, Dual Execution) — the framework becomes an approval-process *selection* engine; chain objects, approver resolution, the Group Work Item pattern and the SLA batch leave the design. Every v1.0 entry below is historical context for `a69e3c9`, not current design. Build paused pending v2.0, which v2.1 defers to for the evaluator, engine flow, decision-log schema, template conventions and entry points.

2026-08-12 — §3.2 chain timestamps named `Submitted_At__c` + `Completed_At__c` — the table said only "timestamps"; two DateTime fields cover chain start and terminal transition without duplicating the per-step `Actioned_At__c`.

2026-08-12 — §3.2 `Approval_Chain_Step__c.Outcome__c` gains a `Pending` value — the doc named no values, but §7.5 scans "open steps", which requires a state meaning not-yet-actioned.

2026-08-12 — §3.2 `Matched_Rule__c` is Text holding the rule DeveloperName, not a lookup — platform-forced: no relationship exists from a custom object to a custom metadata record.

2026-08-12 — §3.2 `Record_Id__c` is an external id but deliberately NOT unique — chains are never deleted, so one governed record accumulates one chain per submission.

2026-08-12 — §8 lock exception is the `AMF_Bypass_Chain_Lock` custom permission, not a named integration profile — a profile name hardcoded into a validation rule does not survive deployment to another org.

2026-08-12 — `Approval_Matrix_Admin` withholds Modify All on the chain objects — the platform makes Modify All depend on Delete, and §8 forbids deleting chain records; View All plus edit gives admins what they need without opening the audit trail to deletion.
