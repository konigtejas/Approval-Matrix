# Handoff — what's next after M10

**As of 2026-10-21.** `develop` is at `e9af7be`: Phase M10 (`393d9d5`) plus the commit recording its
SHA. Nothing has landed since, so M10's org gate has not been recorded as run.

This is the short version. The sources are `docs/technical-log.md` (the status board, M10.5 and
M10.6) and `docs/build-playbook.md` (Part 3's M10 gate, Part 5's roadmap). A fresh session reads
`CLAUDE.md` first: it decides what is authorised.

---

## 1. Gates owed by the user — nothing to build

### M10's org gate — run this first

Two of its tests depend on platform behaviour that could not be run when M10 was built: the
200-record submission staying within governor limits, and a submitter with no manager being
refused by `PR_Two_Level_Mgmt`.

1. `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-approval-matrix-source.ps1`
2. `sf project deploy start -o amf-dev`
3. `sf apex run --file scripts/validate-config.apex -o amf-dev`
4. `sf apex run test -o amf-dev -l RunLocalTests -w 10 -r human` — expect **253/253**. If the
   200-record test fails on a governor limit, report which limit it names: that is a finding
   about bulk size, not a flake.
5. Jest: `$env:PATH = "C:\Program Files\sf\client\bin;$env:PATH"; node node_modules\jest\bin\jest.js --ci`
   — expect 59/59.
6. **The Flow action**, through the platform's invocable framework, in anonymous Apex on a
   throwaway Purchase Request:
   ```apex
   Invocable.Action action = Invocable.Action.createCustomAction('apex', 'AMF_SubmitForMatrixApproval');
   action.setInvocationParameter('recordId', '<throwaway Id>');
   System.debug(action.invoke()[0].getOutputParameters());
   ```
   The first run returns `submitted` true with a decision log row Id. A second run on the same
   record returns `Refused`, naming the process it is already in.
7. **REST:**
   `sf api request rest /services/apexrest/approval-matrix/v1/submissions --method POST --body '{"recordIds":["<pending Id>","<another throwaway Id>"]}' -o amf-dev`
   It answers 200 with `{"results": [...]}`, one result per Id: `Refused` for the pending one,
   `Submitted` for the other. An empty body answers 400.

Record the results in the technical log as M10.7, the way M7.7 and M8.7 record theirs.

### Also open

- **M8's manual UI check (step 6):** on a throwaway record, submit; submit again (refused by
  name, no modal, no new log row); recall (*Matrix Submission* unticks); resubmit (it routes).
  Technical log M8.7d.
- **Optional, M9's manual check:** a throwaway rule using the new grammar, previewed in the UI.
  Technical log M9.4.

---

## 2. A small follow-up that finishes M10 — per-record guard staging (M10.3b)

**The problem.** Step 9 sets `Matrix_Submission__c` on every routed record of an object in one
all-or-nothing update. If one record cannot be updated — it fails a validation rule, or a final
approval left it locked (`finalApprovalRecordLock`) — the update throws, the engine rolls that
object's work back, and the whole call fails instead of that one record.

**A correction to the log.** M10.3b says no test can reproduce this without test-only metadata or
an org setting. A fixture probably exists with what is already deployed: inside the test, approve
a record through `PR_Three_Level_Finance`'s three named approvers so that it ends up locked, then
resubmit it as a non-admin. This is unconfirmed. It assumes an approval lock blocks a non-admin's
Apex update, which is the usual platform behaviour, so check it in the org first.

**The fix.** Stage the guard with `Database.update(records, false)`. Each record whose update
fails gets a `Failed` outcome and decision log row carrying the platform's reason, and is left out
of the submission. The rest are submitted as now.

**Scope.** A follow-up commit, not a phase. It falls under M10's authorisation in `CLAUDE.md`: a
record that cannot be submitted gets its own outcome while the rest still go through. Land it
before M11, because validation rules are common on Opportunity.

---

## 3. The next phase — M11, a second governed object

**Goal** (playbook Part 5): prove §3.2's claim that governing a new object is configuration and
conventions only, with no engine change. That means a guard field; templates with the entry
criterion and the three clearing actions; the standard Submit for Approval button removed (§6.3);
rules; permission-set entries; and the timeline on the object's record page.

**Needs from the user:** authorisation in `CLAUDE.md`, and one decision — which object.

**Recommendation: Opportunity.** A standard object has no `__c`, has required fields (StageName,
CloseDate), record types, its own Submit for Approval button and its own sharing. That exposes
more hidden `Purchase_Request__c` assumptions in the source gate, the validator, the timeline page
and the tests, and finding them is the point of the phase. A second custom object would mostly
repeat what M3 already proved.

**Can ride along:** the validator check for SOQL's limit of 55 child-to-parent relationships
across the union of an object's rules (M9.5). It is small.

**Before building:** write M11's entry in playbook Part 3, with its gate, as M10 did.

---

## 4. After M11

- **M12 — template lifecycle, and queue and committee templates.** The source gate enforces §5.1's
  `_v2` versioning convention. Decide first how "never edited in place" is detected, and whether
  committee steps go on Classic now or wait for Flow.
- **Flow approvals** — the second execution strategy, and the largest item. It is partly blocked
  on the unanimous-approval metadata value (§12 item 1), bound by `docs/spike-results.md` Round 2
  and by engine classes staying at API ≤ 66, and it owns the M6 teardown.
- **Smaller items:** playbook Part 5's "Smaller items, not phases" table, and the technical log's
  M10.6 carried table. That table includes tightening `Lock_Decision_Log`, and a caution for any
  record-triggered Flow that calls the action: the engine's guard update re-triggers it, so its
  entry conditions must exclude that update.

---

## Decisions waiting on the user

1. Run M10's org gate (and M8's step 6), and report the results.
2. A go-ahead for the M10.3b follow-up.
3. Authorise M11 and choose its object (recommended: Opportunity).
