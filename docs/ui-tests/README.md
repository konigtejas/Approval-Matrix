# UI test scripts for an AI test agent

`ui-test-scripts.md` hands the framework's manual UI checks to an AI agent that drives a browser. It
runs 16 test cases in `amf-dev`, as the agent's own Salesforce user (Grok Bot), on records it creates
itself:

- 14 always run, and 2 optional ones change Setup or open Flow Builder;
- there are 75 steps, or 67 without the optional tests;
- every step has a PASS condition and a FAIL condition the agent can observe.

This file is for the person who runs the agent. Give the agent `ui-test-scripts.md` only.

## Where the expected values come from

Every expected string was read from the build at Phase M12 (2026-10-22), not written from memory:

- **Modal, toast and timeline wording:** the LWC templates and their Jest tests
  (`amfSubmitPreview`, `amfSubmitForApproval`, `amfDecisionTimelineEntry`).
- **Rules, priorities, conditions and descriptions:** the shipped rows in
  `force-app/main/default/customMetadata`.
- **Header actions, related-list buttons and columns, and the page layouts:** the UI API in
  `amf-dev`, for the System Administrator profile's layouts.
- **Approval history wording:** real requests from the M12 gate (PR-00000029 and PR-00000030).
- **Refusal messages:** a live REST call that changes nothing.

A change to a rule, a template, or one of those components changes these values. Update the script
in the same phase.

The UI API checks ran as Tejas Vernekar, because the CLI is signed in as that user, not as Grok Bot.
On 2026-10-22, Grok Bot was given the same profile, permission set, manager, locale and time zone, so
it sees the same layouts, buttons and routes. The one value that differs is the user's name, which
the script takes as `TESTER`. The first run as Grok Bot (R20261022-1412) confirmed it: every route,
action and name matched.

That run also corrected three things the UI API does not tell you:
- a related-list card shows only the first four columns of its layout's list;
- a card puts some of its actions in a drop-down, such as Recall on Approval History;
- a currency field reads `$60,000.00` on Details, where the modal and the timeline read `60,000`.

It found two defects in the Approval Timeline, which M12.6 fixed (technical log M12.6):
- its times followed the browser's time zone, not the user's Salesforce one, so they read 3 hours
  ahead of the rest of the page for an agent whose browser was on UTC−4;
- its "Approval history:" line had no space after the comma.

TC-03.4 and TC-03.6 check the fixes. TC-03.6's time check only bites when the agent's browser is
not on Pacific time, Grok Bot's Salesforce time zone.

The re-run (R20261022-1856) confirmed both fixes (technical log M12.7). It also found that the
Approval Decisions card can show its count from before a submission until the page reloads, though
the log row is written and the timeline links it at once. The script now allows that reload, as it
already did for Matrix Submission.

## Before a run

1. **The build.** `amf-dev` holds `develop` at M12.6 or later, with the source gate and the org
   validator green.
2. **The agent's user.** Grok Bot (`tejas.vernekar@wissen.com.grokbot`), set up on 2026-10-22. Each
   setting below is load-bearing; change one and the expected values change with it.

   | Setting | Value | Why the script needs it |
   |---|---|---|
   | Profile | System Administrator | TC-08 and TC-10 approve and reject on an approver's behalf; TC-15 and TC-16 open Setup; it also fixes which Opportunity layout the agent sees |
   | Permission set | `Approval_Matrix_Admin` | Access to Purchase Requests, the decision log and the submit action's classes |
   | Manager | AMF Approver One (`amfu1`) | The two-level routes go to the submitter's manager. With no manager, the platform refuses those submissions |
   | Locale | English (United States) | Numbers display as `1,200,000`, and dates are typed M/D/YYYY |

   Grok Bot now holds full administrator rights in `amf-dev`, including the right to edit decision
   log rows. Keep its credentials out of the repository. Deactivate it, or return it to Standard
   User, when it is not running tests.
3. **The browser.** At least 1440 pixels wide, so the Approval Timeline sits in the right-hand
   column.
4. **The login link.** A login link signs the agent in with no password and no verification code.
   Salesforce asks for a verification code when a user signs in from a new browser, and Grok Bot's
   codes are emailed to `tejas.vernekar@wissen.com`.
   - **Once:** authorise Grok Bot in the CLI, signing in as Grok Bot in the browser that opens:
     `sf org login web --alias amf-bot --instance-url https://orgfarm-e5ccbd7218-dev-ed.develop.my.salesforce.com`
   - **Each run:** run `sf org open -o amf-bot --url-only`, and give the agent the URL it prints.

   The link carries a live administrator session. Treat it as a password: give it to the agent at
   run time only, and never put it into the scripts, a commit or the report. It stops working when
   the session ends.
5. **The run parameters:**
   - `TESTER`: `Grok Bot`, the user's full name as Salesforce shows it;
   - `RUN`: a fresh identifier such as `R20261022-1405`;
   - `RUN_U`: the same, with underscores in place of hyphens;
   - `RUN_OPTIONAL`: `no` unless you want TC-15 and TC-16.

## Coverage

| Test | What it proves | Phase | Playbook manual check it answers |
|---|---|---|---|
| TC-01 | One Submit for Approval action; the timeline's empty state; no New or Change Owner on Approval Decisions | M3, M7, M12 | M12 step 11, in part |
| TC-02 | A cancelled preview writes nothing | M5 | |
| TC-03 | Queue route: modal, toast, timeline without reload and in the user's time zone, guard ticked | M5, M7, M12 | M12 step 11 |
| TC-04 | The decision log row's content | M1, M3, M7 | |
| TC-05 | A pending record is refused by name, with no log row | M8 | M8 step 6 |
| TC-06 | A recall clears the guard | M8 | M8 step 6 |
| TC-07 | The recalled request routes again | M8 | M8 step 6 |
| TC-08 | The queue step approved; the timeline names the true actor; the log rows unchanged | M7, M12 | |
| TC-09 | The committee: three approvers pending at once | M12 | |
| TC-10 | A rejection clears the guard | M8 | |
| TC-11 | Opportunity: one Submit for Approval, the timeline, no New or Change Owner | M11, M12 | M11 step 8, in part |
| TC-12 | Opportunity's catch-all, previewed and cancelled | M5, M11 | |
| TC-13 | Priority 10 wins over priority 20 | M11 | |
| TC-14 | Opportunity routed by `IN` on `Account.Industry`; timeline without reload; guard ticked | M9, M11 | M11 step 8 |
| TC-15 | Optional: a full-grammar rule added in Setup, previewed, removed | M9 | M9's optional check |
| TC-16 | Optional: both Flow actions are listed in Flow Builder | M4, M10 | |

## What the UI suite does not cover

These are covered elsewhere, and the agent should not try them.

| Behaviour | Where it is proven |
|---|---|
| The source gate, the release manifest, the org validator script, portability | The CLI gates, run by a person (playbook M4, M12) |
| REST, the Flow action's results, 200 records in one call | Apex tests; technical log M10.8 and M12.4 |
| A blocked (no-match) and a failed submission | Apex and Jest tests. Showing them in the UI means deactivating a live rule |
| The committee approved member by member, then one leader | `AMF_TemplateShapesTest`, and technical log M12.4 in the org |
| Approval by a queue member, or through a public group | `AMF_TemplateShapesTest`. The agent approves as an administrator, on the queue's behalf |
| Flow approvals | Not built |

## Reading the report

- **FAIL** means the UI did not do what the build promises. The step quotes what the agent saw.
- **BLOCKED** means an earlier step failed first. Fix that one before reading anything into it.
- **NOT OBSERVED** applies only to success toasts. They disappear after about 3 seconds, so an agent
  can miss one. The persistent checks in the following steps decide the test.
- **"needed reload"** on a Matrix Submission check, or on a related-list card after a submission, is
  a PASS. The data is right, but the page did not refresh it by itself.
- A timeline that updates only after a reload is a FAIL: M7 and M11 promise the update without one.

## After a run

- The run leaves eight records named `UITEST {RUN}` or numbered `PR-…`, plus their decision log rows.
  Every approval has been completed or recalled. Nothing needs deleting, and log rows are never
  deleted.
- Record the results in `docs/technical-log.md`, as a numbered sub-entry of the latest phase: the
  run's identifier, each test's verdict, and the cause of every FAIL. The first run is in M12.6,
  which closed M8's, M11's and M12's manual checks. TC-15, if run, answers M9's optional check.
- If the report starts with **CLEANUP FAILED**, delete the named rule in Setup by hand: **Custom
  Metadata Types > Approval Matrix Rule > Manage Approval Matrix Rules**.

## A UI quirk the agent is told to avoid

An Approval Decision Log record's page offers **Submit for Approval**, **Edit** and **Delete**:
- The log has no approval process, so Submit for Approval leads nowhere.
- Edit would succeed for the agent's user, because `Approval_Matrix_Admin` grants the
  `AMF_Bypass_Log_Lock` permission.

The script forbids all three (hard rule 3). An explicit action list on the log's layout would remove
them, in a later hardening pass.
