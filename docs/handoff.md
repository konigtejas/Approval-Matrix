# Handoff — what's next after M11

**As of 2026-10-21.** `develop` holds three changes from one session, all with their gates run in
`amf-dev`:

- **M10's org gate**, closed as M10.8 (`a0273e9`).
- **The Opportunity baseline**, retrieved from the org and committed unchanged (`6e3079d`).
- **Phase M11**, a second governed object (`96e5692`).

Only M11's manual UI check is owed.

This is the short version. The sources are `docs/technical-log.md` (the status board, M10.8, M11
and M11.5's table of open items) and `docs/build-playbook.md` (Part 3's M11 gate, Part 5's
roadmap). A fresh session reads `CLAUDE.md` first: it decides what is authorised.

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
- **The source is now tied to `amf-dev` twice over.** `PR_Three_Level_Finance` names this org's
  usernames, and the Opportunity layouts reference this org's sample fields.

The M10.8 fixture finding still stands: under `System.runAs`, the lock a final approval leaves did
not stop the guard update.

---

## 3. The next phase — the user's choice

Playbook Part 5 is a proposal; `CLAUDE.md` authorises nothing beyond M11.

- **M12 — template lifecycle, and queue and committee templates.** The source gate enforces §5.1's
  `_v2` convention. Decide first:
  - how "never edited in place" is detected;
  - whether committee steps go on Classic now or wait for Flow.

  The source-portability items belong here too, because a second org or CI needs both fixed: a
  `replacements` entry for the approver usernames, and a decision on standard-object layouts.
- **Flow approvals** — the second execution strategy, and the largest item. It is partly blocked
  on the unanimous-approval metadata value (§12 item 1), bound by `docs/spike-results.md` Round 2
  and by engine classes staying at API ≤ 66, and it owns the M6 teardown.
- **Smaller items** (Part 5's table, M11.5's carried table):
  - the Approval Decisions related list's New and Mass Change Owner buttons;
  - tightening `Lock_Decision_Log`;
  - husky's pre-commit hook;
  - the remaining field types (DateTime, Email, Phone, URL, Text Area).

---

## Decisions waiting on the user

1. Run M11's manual UI check, and M8's, and report the results.
2. Choose the next phase and authorise it in `CLAUDE.md`.
