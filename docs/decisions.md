# Architecture Decisions

Log of approved deviations from `docs/architecture.md`. When a phase reveals a real
gap in the doc, fix the doc first, then append one line here — see the "When
Things Go Wrong" section of `docs/build-playbook.md`.

Format: `YYYY-MM-DD — <what changed> — <why>`

---

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
