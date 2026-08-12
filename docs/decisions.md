# Architecture Decisions

Log of approved deviations from `docs/architecture.md`. When a phase reveals a real
gap in the doc, fix the doc first, then append one line here — see the "When
Things Go Wrong" section of `docs/build-playbook.md`.

Format: `YYYY-MM-DD — <what changed> — <why>`

---

2026-08-12 — §3.2 chain timestamps named `Submitted_At__c` + `Completed_At__c` — the table said only "timestamps"; two DateTime fields cover chain start and terminal transition without duplicating the per-step `Actioned_At__c`.

2026-08-12 — §3.2 `Approval_Chain_Step__c.Outcome__c` gains a `Pending` value — the doc named no values, but §7.5 scans "open steps", which requires a state meaning not-yet-actioned.

2026-08-12 — §3.2 `Matched_Rule__c` is Text holding the rule DeveloperName, not a lookup — platform-forced: no relationship exists from a custom object to a custom metadata record.

2026-08-12 — §3.2 `Record_Id__c` is an external id but deliberately NOT unique — chains are never deleted, so one governed record accumulates one chain per submission.

2026-08-12 — §8 lock exception is the `AMF_Bypass_Chain_Lock` custom permission, not a named integration profile — a profile name hardcoded into a validation rule does not survive deployment to another org.

2026-08-12 — `Approval_Matrix_Admin` withholds Modify All on the chain objects — the platform makes Modify All depend on Delete, and §8 forbids deleting chain records; View All plus edit gives admins what they need without opening the audit trail to deletion.
