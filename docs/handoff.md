# Handoff — what's next after M10

**As of 2026-10-21.** `develop` holds Phase M10 (`393d9d5`) and the M10.3b follow-up, **M10.7**
(`548cd59`), merged on 2026-10-21 by fast-forward from `claude/handoff-review-repo-scan-j30kbi`.
**Update, 2026-10-21:** M10's org gate has now run and passed (technical log M10.8). Its two
locked-record tests failed as section 1 warned they might, and their fixture was replaced by a
test-only validation rule; 255/255. The user then authorised M11 for Opportunity.

This is the short version. The sources are `docs/technical-log.md` (the status board, M10.5, and
M10.7, which amends M10.5's gate and holds the current table of open items) and
`docs/build-playbook.md` (Part 3's M10 gate, Part 5's roadmap). A fresh session reads `CLAUDE.md`
first: it decides what is authorised.

---

## 1. Gates owed by the user — nothing to build

### ~~M10's org gate, with M10.7 — run this first~~ Passed 2026-10-21 (technical log M10.8)

Four of its tests depend on platform behaviour no session has run: the 200-record submission
staying within governor limits, a submitter with no manager being refused by `PR_Two_Level_Mgmt`,
and M10.7's two tests, which assume that the lock a final approval leaves stops a non-admin's
update from Apex running without sharing.

1. `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-approval-matrix-source.ps1`
2. `sf project deploy start -o amf-dev`
3. `sf apex run --file scripts/validate-config.apex -o amf-dev`
4. `sf apex run test -o amf-dev -l RunLocalTests -w 10 -r human` — expect **255/255**. If the
   200-record test fails on a governor limit, report which limit it names: that is a finding
   about bulk size, not a flake. If a locked-record test fails on its first assertion, report the
   outcome it shows: that is a finding about the approval lock, and the engine change stands.
5. Jest: `$env:PATH = "C:\Program Files\sf\client\bin;$env:PATH"; node node_modules\jest\bin\jest.js --ci`
   — expect 59/59.
6. **The Flow action**, through the platform's invocable framework, in anonymous Apex on a
   throwaway Purchase Request with **`Risk_Level__c = High`**, so it routes to the named-user
   template. Your user has no manager (M3.7), so a record reaching the catch-all's
   `PR_Two_Level_Mgmt` would answer `Failed` (`MANAGER_NOT_DEFINED`): correct, but not what this
   step checks.
   ```apex
   Invocable.Action action = Invocable.Action.createCustomAction('apex', 'AMF_SubmitForMatrixApproval');
   action.setInvocationParameter('recordId', '<throwaway Id>');
   System.debug(action.invoke()[0].getOutputParameters());
   ```
   The first run returns `submitted` true with a decision log row Id. A second run on the same
   record returns `Refused`, naming the process it is already in.
7. **REST**, with a second `Risk_Level__c = High` throwaway. Windows PowerShell strips the double
   quotes inside an argument it passes to `sf` (the M6.6 trap), so escape them:
   `sf api request rest /services/apexrest/approval-matrix/v1/submissions --method POST --body '{\"recordIds\":[\"<pending Id>\",\"<another throwaway Id>\"]}' -o amf-dev`
   or use Workbench's REST Explorer. It answers 200 with `{"results": [...]}`, one result per Id:
   `Refused` for the pending one, `Submitted` for the other. `--body '{}'` answers 400; do not
   test with `''`, which PowerShell drops.

Record the results in the technical log as **M10.8**, the way M7.7 and M8.7 record theirs.

### Also open

- **M8's manual UI check (step 6):** on a throwaway record, submit; submit again (refused by
  name, no modal, no new log row); recall (*Matrix Submission* unticks); resubmit (it routes).
  Technical log M8.7d. Step 6's throwaway, pending after the gate, can serve for everything after
  the first submit.
- **Optional, M9's manual check:** a throwaway rule using the new grammar, previewed in the UI.
  Technical log M9.4.

---

## 2. Done: per-record guard staging (M10.3b, built as M10.7)

Step 9 now sets `Matrix_Submission__c` with `Database.update(records, false)`. A record the
platform will not let it set (a validation rule it fails, or the lock a final approval left)
gets a `Failed` outcome and decision log row carrying the platform's reason, and is not
submitted; the rest go ahead. The header button gets the same answer instead of an exception.
Re-arming a refused record stays all-or-nothing. Two real-platform tests cover it, over a record
approved through `PR_Three_Level_Finance` and resubmitted by a non-admin. Technical log M10.7 has
the design, the fixture's assumption, and the evidence.

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
repeat what M3 already proved. Production Apex and LWC hard-code no object, so expect the
surprises in metadata, the gates and the tests. Opportunity usually carries triggers: since M10.7
a partial guard failure saves the other records in a second attempt that runs their triggers
again, so check that they tolerate it.

**Can ride along:** the validator check for SOQL's limit of 55 child-to-parent relationships
across the union of an object's rules (M9.5). It is small.

**Before building:** write M11's entry in playbook Part 3, with its gate, as M10 did.

---

## 4. After M11

- **M12 — template lifecycle, and queue and committee templates.** The source gate enforces §5.1's
  `_v2` versioning convention. Decide first how "never edited in place" is detected, and whether
  committee steps go on Classic now or wait for Flow. The templates' org-bound approver usernames
  (M10.7 carried) belong here too: the source deploys only to `amf-dev`.
- **Flow approvals** — the second execution strategy, and the largest item. It is partly blocked
  on the unanimous-approval metadata value (§12 item 1), bound by `docs/spike-results.md` Round 2
  and by engine classes staying at API ≤ 66, and it owns the M6 teardown.
- **Smaller items:** playbook Part 5's "Smaller items, not phases" table, and the technical log's
  M10.7 carried table. That table includes tightening `Lock_Decision_Log`, husky's pre-commit hook
  (it would reformat whole files), and a caution for any record-triggered Flow that calls the
  action: the engine's guard update re-triggers it, so its entry conditions must exclude that
  update.

---

## Decisions waiting on the user

1. Run M10's org gate (and M8's step 6) against `develop`, and report the results.
2. Authorise M11 and choose its object (recommended: Opportunity).
