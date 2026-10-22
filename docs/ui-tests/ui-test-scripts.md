# Approval Matrix UI test scripts

**For:** an AI agent that tests through a web browser. **Org:** `amf-dev`. **User:** the agent's own
Salesforce user, `{TESTER}`, set up as the README requires. **Valid for:** the build at M12.6
(`develop`, 2026-10-22). The expected values below are the shipped matrix rules and templates of that
build. A change to a rule or template changes them.

---

## 0. Instructions for the test agent

You test the Approval Matrix framework in Salesforce through the browser, as `{TESTER}`. Run the
steps in order. For each step:

1. do exactly what it says;
2. judge it against its PASS and FAIL conditions;
3. write down what you observed.

At the end, produce the report in section 7. You do not fix, retry, explore or work around anything:
an unexpected result is a FAIL to report, not a problem to solve.

### 0.1 Run parameters (the operator gives you these)

| Parameter | Meaning |
|---|---|
| `TESTER` | The full name of the Salesforce user you log in as, exactly as Salesforce shows it, for example `Grok Bot`. Every expected "by …" and "… , for …" line in the timeline names this user. |
| `RUN` | This run's identifier, for example `R20261022-1405`. Letters, digits and hyphens only. |
| `RUN_U` | `RUN` with every hyphen replaced by an underscore, for example `R20261022_1405`. |
| `LOGIN_URL` | A one-time login link for `amf-dev`. It is a live administrator session: never write it into the report or anywhere else. |
| `RUN_OPTIONAL` | `yes` or `no`. Only `yes` runs section 5 (TC-15, TC-16). Default `no`. |

### 0.2 Hard rules

1. Change only the records you create in TD-01. Never edit, submit, approve, reject or recall any
   other record.
2. Never tick or untick the **Matrix Submission** checkbox yourself, on any form or record. Only the
   framework sets it, and the tests check that it does.
3. Never edit or delete an **Approval Decision Log** record. Its page offers Edit, Delete and Submit
   for Approval buttons: do not click any of them.
4. Never delete any record of any kind.
5. Click **Submit for Approval**, **Approve**, **Reject** or **Recall** only where a step tells you
   to, only once per step, and only on the record that step names. If nothing happens, record a
   FAIL. Never click again, because every click can create an approval and an audit row.
6. Do not open Setup, except in TC-15 and TC-16, and there only for what the step says.
7. Never type a username, a password or a verification code. If Salesforce asks for any of them,
   stop the run (TS-00.1).
8. Do not change user settings, language, locale or time zone.
9. Close a modal or a dialog only with the button the step names. Do not use the browser's Back
   button while a modal is open.

### 0.3 Verdicts

| Verdict | When |
|---|---|
| PASS | Every PASS condition holds within the time allowed. |
| FAIL | Any FAIL condition is observed, or a PASS condition does not hold within the time allowed. |
| NOT OBSERVED | Only for a step marked **transient** (a success toast, which disappears after about 3 seconds): you did not capture it. Not a failure. |
| BLOCKED | You cannot perform the step because a step it depends on failed. Name that step. |

A test case is FAIL if any step FAILed, else BLOCKED if any step was BLOCKED, else PASS. After a FAIL,
continue with the next step of the same test unless the step says **Stop**. If a step says "PASS
with note", record the verdict as PASS and add the note.

### 0.4 Matching text

- **reads exactly** means the same characters, case-sensitive. A line break or a run of spaces counts
  as one space, but a missing space is a difference: `Queue,In approval` does not read exactly
  `Queue, In approval`.
- **contains** means the text appears within the element.
- A few headings are styled in capitals, such as the modal's "VALUES THE RULE READ". Match headings
  ignoring case. Match values and messages exactly.
- `{D1.number}` and similar are values you recorded earlier in the run. `{RUN}` is the run parameter.
- Numbers display with commas, as this user's locale (en_US) writes them: `60,000`, `1,200,000`.
  The modal and the timeline show the number the rule read (`60,000`). A record's Details tab shows
  the same amount as currency (`$60,000.00`). Both are correct.
- The confirmation modal names fields by their API name (`Amount__c`). The timeline names them by
  their label (`Amount`). Both are correct.

### 0.5 Waiting

| What | Wait up to |
|---|---|
| A page to load | 30 seconds |
| A modal, a dialog or a toast after a click | 10 seconds |
| The timeline to show a new submission, without reloading | 15 seconds |

**Reload** means the browser's reload of the current page, then waiting for it to load. **Refresh the
timeline** means clicking the circular-arrow icon in the Approval Timeline card's header, whose
tooltip reads "Refresh".

### 0.6 Where things are

- **Header:** the record's name or number, and its action buttons. Actions that do not fit sit in a
  drop-down at the right end of the buttons. Count both places when a step asks how many there are.
- **Tabs:** Details and Related on every record. Opportunities also have Activity and Chatter.
- **Approval Timeline:** a card in the right-hand column. Its newest entry sits on top and opens
  expanded. Each entry has a chevron button that shows or hides its details ("Show details" /
  "Hide details").
- **Matrix Submission:** a checkbox field on the Details tab, Information section.
- **Approval History** and **Approval Decisions:** related-list cards on the Related tab. The number
  in brackets after a card's title is its row count.
- **A card's actions:** some show as buttons, and the rest sit in a drop-down at the card's top right
  (a down-arrow, "Show more actions"). A step that says a card "offers" an action, or offers none,
  means both places: check both, as for the header.
- **A card's columns:** a card shows only the first four columns of its list. Approval Decisions
  shows Decision Log Number, Submitted At, Outcome and Matched Rule. The log's other fields are on
  the log record itself.

### 0.7 Evidence

Take a screenshot at every step that says **Screenshot**. Name it `{RUN}-<step id>.png`, for example
`R20261022-1405-TC-03.4.png`. For every FAIL, quote what you actually saw.

---

## 1. TS-00: login and environment

**TS-00.1** Open `LOGIN_URL`.
- PASS: within 30 seconds a Salesforce page loads whose address contains `/lightning/`, with no login
  form.
- FAIL: a login page, a "Verify your identity" page or an error page. **Stop the run** and report
  BLOCKED, quoting the page's heading.

**TS-00.2** Click the profile picture at the top right of the page.
- PASS: the card that opens shows the name **{TESTER}**.
- FAIL: another name. **Stop the run.**
- Then press Escape to close the card.

**TS-00.3** Open the App Launcher (the grid of dots at the top left). Search for `Purchase Requests`,
then for `Approval Decision Logs`.
- PASS: each search lists an item with exactly that name.
- FAIL: either is missing. **Stop the run.**
- Then close the App Launcher.

---

## 2. TD-01: test data, created through the UI

Create these eight records. Leave every field the step does not name empty, and leave **Matrix
Submission** unticked (rule 2). If any TD-01 step FAILs, **stop the run**: every test depends on this
data.

| Record | Object | Values |
|---|---|---|
| D1 | Purchase Request | Amount `60000`, Region `AMER`, Risk Level `Medium` |
| D2 | Purchase Request | Amount `1200000`, Region `AMER`, Risk Level `Low` |
| D3 | Purchase Request | Amount `5000`, Region `EMEA`, Risk Level `Low` |
| A1 | Account | Account Name `UITEST {RUN} Energy Co`, Industry `Energy` |
| A2 | Account | Account Name `UITEST {RUN} Hotels Ltd`, Industry `Hospitality` |
| D5 | Opportunity | Opportunity Name `UITEST {RUN} Energy deal`, Account Name A1, Amount `5000`, Close Date today + 30 days, Stage `Prospecting` |
| D7 | Opportunity | Opportunity Name `UITEST {RUN} Hotels deal`, Account Name A2, Amount `5000`, Close Date today + 30 days, Stage `Prospecting` |
| D8 | Opportunity | Opportunity Name `UITEST {RUN} Large deal`, Account Name A1, Amount `300000`, Close Date today + 30 days, Stage `Prospecting` |

Type the Close Date in the field's own format. For this user it is M/D/YYYY.

**TD-01.1** Open the **Purchase Requests** tab from the App Launcher, click **New**, enter D1's
values, and click **Save**.
- PASS: within 30 seconds the new record opens. Its header shows a number of the form `PR-` plus 8
  digits, and Details shows Amount `$60,000.00`, Region `AMER`, Risk Level `Medium`, and Matrix
  Submission unticked.
- FAIL: an error on save, or any value differs.
- Record: `D1.number` (for example `PR-00000041`), `D1.id` (the 18 characters after
  `/Purchase_Request__c/` in the address) and `D1.url`.

**TD-01.2** Do the same for D2.
- PASS: as TD-01.1, with Amount `$1,200,000.00`, Region `AMER` and Risk Level `Low`.
- FAIL: an error on save, or any value differs.
- Record: `D2.number`, `D2.id` and `D2.url`.

**TD-01.3** Do the same for D3.
- PASS: as TD-01.1, with Amount `$5,000.00`, Region `EMEA` and Risk Level `Low`.
- FAIL: an error on save, or any value differs.
- Record: `D3.number`, `D3.id` and `D3.url`.

**TD-01.4** Open the **Accounts** tab, click **New**, enter A1's values, and save. Repeat for A2.
- PASS: each record opens with its name in the header and its Industry on Details.
- FAIL: an error on save, or a value differs.

**TD-01.5** Open the **Opportunities** tab, click **New**, enter D5's values, and save. Repeat for D7
and D8. Fill the fields in this order: Opportunity Name, Amount, Close Date, Stage, and Account Name
last. For Account Name, type the account's name and choose it from the suggestions.
- PASS: each record opens with its name in the header, and its Amount and Account Name on Details.
- FAIL: an error on save, or a value differs.
- Record: `D5.url`, `D7.url`, `D8.url`, and the Close Date shown on D7 as `D7.closeDate`.

---

## 3. Purchase Request tests

### TC-01: the record page before any submission

Covers: a single Submit for Approval action (M3), the timeline's empty state (M7), and the Approval
Decisions list without New or Change Owner (M12). Uses D1. Depends on TD-01.1.

**TC-01.1** Open `D1.url`, Details tab.
- PASS: Matrix Submission is unticked.
- FAIL: it is ticked.

**TC-01.2** Look at the header buttons, then open the header's drop-down of further actions, if
there is one. **Screenshot.**
- PASS: exactly one action labelled **Submit for Approval** exists, counting the buttons and the
  drop-down together.
- FAIL: none, or two or more.
- Then close the drop-down without choosing anything.

**TC-01.3** Look at the right-hand column.
- PASS: a card titled **Approval Timeline**, with a refresh icon in its header, whose body reads
  exactly: "This record has not been submitted for approval. When it is, this timeline shows which
  rule routed it, why, and every approval step that follows."
- FAIL: the card is missing, shows red error text, or reads anything else.

**TC-01.4** Open the Related tab and find the **Approval Decisions** card. **Screenshot.**
- PASS: its title reads `Approval Decisions (0)`, and it offers no **New** button and no **Change
  Owner** button, including in its own drop-down if it has one.
- FAIL: either button is offered, or the count is not 0.

**TC-01.5** On the same tab, find the **Approval History** card.
- PASS: it shows no approval rows and offers no actions.
- FAIL: it shows a row, or offers any action, such as Submit for Approval.

### TC-02: a preview that is cancelled writes nothing

Covers: the preview and confirmation modal (M5). Uses D3. Depends on TD-01.3.

**TC-02.1** Open `D3.url` and click **Submit for Approval** in the header, once. **Screenshot.**
- PASS: within 10 seconds a modal titled **Confirm approval route** opens, showing:
  - "This record will be submitted to", followed by `PR_Two_Level_Mgmt`;
  - Matched rule `PR_Catch_All`;
  - Description: "Everything else takes two levels of management. Deactivate this row and unmatched
    records block with a Blocked_No_Match log entry instead of routing silently.";
  - Priority `9999`, Version `1`, Condition `TRUE`;
  - under the heading "Values the rule read": "This rule's condition reads no fields, so it matches
    every record.";
  - the buttons **Cancel** and **Submit for Approval**.
- FAIL: no modal within 10 seconds, a toast instead, or any value differs.

**TC-02.2** Click **Cancel**.
- PASS: the modal closes, and no toast appears within 5 seconds.
- FAIL: a toast appears, or the modal stays open.

**TC-02.3** Reload the page.
- PASS: the timeline reads the empty-state text of TC-01.3, Matrix Submission is unticked, and on
  Related `Approval Decisions (0)` and Approval History show no rows.
- FAIL: a timeline entry, a row in either card, or a ticked box.

### TC-03: the queue route, end to end

Covers: the modal (M5), the timeline's live update (M7), the queue template (M12) and the guard.
Uses D1. Depends on TD-01.1. TC-04 to TC-08 depend on this test.

**TC-03.1** Open `D1.url` and click **Submit for Approval**, once. **Screenshot.**
- PASS: within 10 seconds the **Confirm approval route** modal opens, showing:
  - "This record will be submitted to", followed by `PR_Credit_Risk_Queue`;
  - Matched rule `PR_Credit_Risk_Review`;
  - Description: "Medium-risk spend of 50,000 or more goes to the credit-risk queue, where the first
    member to act decides.";
  - Priority `30`, Version `1`;
  - Condition `Risk_Level__c == 'Medium' && Amount__c >= 50000`;
  - under "Values the rule read", a table with exactly two rows: Field `Amount__c`, Value `60,000`,
    and Field `Risk_Level__c`, Value `Medium`.
- FAIL: no modal, or any value differs. If the modal names another process, click **Cancel** and
  mark TC-04 to TC-08 BLOCKED.

**TC-03.2** **Transient.** Click the modal's **Submit for Approval**, once.
- PASS: a toast titled "Submitted for approval", reading "Matched PR_Credit_Risk_Review (v1) and
  routed to PR_Credit_Risk_Queue."
- FAIL: a toast titled "Not submitted", "Could not submit for approval" or "Submitted, by a different
  route than previewed"; or the modal still open after 10 seconds.
- NOT OBSERVED: no toast captured.

**TC-03.3** Do not reload. Watch the Approval Timeline for up to 15 seconds. **Screenshot.**
- PASS: it shows exactly one entry:
  - title "Routed to PR_Credit_Risk_Queue";
  - badge "In approval";
  - summary "Matched PR_Credit_Risk_Review v1 because Amount = 60,000 and Risk Level = Medium."
- FAIL: no entry within 15 seconds, or any text differs. If there is no entry, reload, and record
  whether it appears after the reload. The step stays FAIL, because the update without a reload is
  what it tests.

**TC-03.4** Read the entry's details, which are open by default; if they are not, click its chevron.
**Screenshot.**
- PASS:
  - Rule `PR_Credit_Risk_Review v1`;
  - Condition `Risk_Level__c == 'Medium' && Amount__c >= 50000`;
  - Values read: `Amount = 60,000` and `Risk Level = Medium`;
  - Submitted by `{TESTER}`;
  - Decision log: a link of the form `ADL-` plus 8 digits;
  - the line "Approval history: PR_Credit_Risk_Queue, In approval";
  - two steps, in this order: "Submitted" with "by {TESTER}", then "Credit Risk Review, Pending"
    with "Waiting on Credit Risk".
- FAIL: any item differs or is missing, or red error text appears in the card.
- Record: `D1.log1`, the ADL number in the link, and `D1.time1`, the time at the entry's top right.

**TC-03.5** Open the Details tab.
- PASS: Matrix Submission is ticked. If it shows unticked, reload once: ticked after the reload is a
  PASS with note "needed reload".
- FAIL: unticked after the reload.

**TC-03.6** Open the Related tab. **Screenshot.**
- PASS:
  - `Approval Decisions (1)`, with one row: Decision Log Number `{D1.log1}`, Outcome `Submitted`
    and Matched Rule `PR_Credit_Risk_Review`. The card shows no more columns than these and Submitted
    At (section 0.6); TC-04 checks the rest on the log record;
  - the Approval Decisions card offers no New and no Change Owner action;
  - Approval History shows a pending approval that names **Credit Risk**, and offers Approve, Reject,
    Reassign and Recall;
  - the time Approval History shows for the submission is `D1.time1`, or one minute later. The
    timeline writes the hour with two digits, so `02:19 AM` there matches `2:19 AM` here.
- FAIL: any of these differs. For the time, quote both values.

### TC-04: the decision log row explains the route

Covers: the audit row behind the timeline (M1, M3, M7). Uses `D1.log1`. Depends on TC-03.4.

**TC-04.1** In D1's timeline entry, click the Decision log link `{D1.log1}`.
- PASS: within 30 seconds the Approval Decision Log record `{D1.log1}` opens, in this browser tab or
  a new one.
- FAIL: an error, or another record opens.

**TC-04.2** Read its Details tab without clicking anything on it (rule 3). **Screenshot.**
- PASS:
  - Outcome `Submitted`;
  - Selected Process `PR_Credit_Risk_Queue`;
  - Matched Rule `PR_Credit_Risk_Review`;
  - Rule Version `1`;
  - Execution Ref Id: 18 characters, beginning `04g`;
  - Expression Snapshot `Risk_Level__c == 'Medium' && Amount__c >= 50000`;
  - Evaluated Values `{"Amount__c":60000.00,"Risk_Level__c":"Medium"}`;
  - Failure Detail empty;
  - Purchase Request: a link reading `{D1.number}`;
  - Record Id `{D1.id}`;
  - Opportunity empty;
  - Object API Name `Purchase_Request__c`;
  - Submitted By `{TESTER}`.
- FAIL: any value differs.

**TC-04.3** Open `D1.url` again.
- PASS: D1 opens.
- FAIL: it does not.

### TC-05: a record already in approval is refused by name

Covers: guard integrity (M8). Uses D1, pending since TC-03. Depends on TC-03.6.

**TC-05.1** Click **Submit for Approval**, once. **Screenshot.**
- PASS: no modal opens. Within 10 seconds an error toast titled "Could not submit for approval"
  appears, reading exactly "A record that is already in an approval process cannot be submitted
  again until that request is recalled or completes. Already pending: {D1.id} in
  PR_Credit_Risk_Queue". The toast stays until closed.
- FAIL: a modal opens (click its **Cancel**, and do not submit), the toast reads anything else, or no
  toast appears within 10 seconds.
- Take the screenshot while the toast is showing, then close the toast with its X.

**TC-05.2** Reload the page.
- PASS: the timeline still has exactly one entry, with badge "In approval", and Related shows
  `Approval Decisions (1)`.
- FAIL: a second entry or a second row.

### TC-06: a recall clears the guard

Covers: the recall exit (M8). Uses D1. Depends on TC-05.

**TC-06.1** Open the Related tab. In the Approval History card, click **Recall**: a button on the
card, or an item in its drop-down. In the dialog, type `UITEST {RUN} recall` into the comments box,
then click the dialog's **Recall** button.
- PASS: the dialog closes without an error message.
- FAIL: the card offers no Recall, or an error is shown.

**TC-06.2** Reload the page and open the Details tab.
- PASS: Matrix Submission is unticked.
- FAIL: it is ticked.

**TC-06.3** Refresh the timeline. Read its entry, and open its details if they are closed.
**Screenshot.**
- PASS:
  - the badge reads "Recalled";
  - the "Approval history:" line names `PR_Credit_Risk_Queue`, then `Recalled` (TC-03.4 checks its
    exact text);
  - the last step reads "Recalled", with "by {TESTER}" and the comment `UITEST {RUN} recall`;
  - no step reads "Pending".
- FAIL: the badge still reads "In approval", or a pending step remains.

**TC-06.4** Look at the Related tab.
- PASS: `Approval Decisions (1)`, and Approval History offers no Recall, Approve or Reject.
- FAIL: either differs.

### TC-07: a recalled request routes again

Covers: the guard re-armed by the recall (M8). Uses D1. Depends on TC-06.

**TC-07.1** Click **Submit for Approval**, once.
- PASS: the modal opens with the same content as in TC-03.1.
- FAIL: no modal, a toast, or any value differs.

**TC-07.2** **Transient.** Click the modal's **Submit for Approval**, once.
- PASS: the toast of TC-03.2.
- FAIL: an error or warning toast, or the modal still open after 10 seconds.
- NOT OBSERVED: no toast captured.

**TC-07.3** Do not reload. Watch the timeline for up to 15 seconds. **Screenshot.**
- PASS: exactly two entries. The top one reads "Routed to PR_Credit_Risk_Queue" with badge "In
  approval". The second reads "Routed to PR_Credit_Risk_Queue" with badge "Recalled".
- FAIL: one entry after 15 seconds, or other text.
- Record: `D1.log2`, the ADL number in the top entry's Decision log link.

**TC-07.4** Check the Details tab, then the Related tab.
- PASS: Matrix Submission is ticked (a reload is allowed, as in TC-03.5), and Related shows
  `Approval Decisions (2)`.
- FAIL: unticked after a reload, or another count.

### TC-08: approving the queue step

Covers: the queue template's approval (M12), the true actor in the timeline (M7), and the guard
cleared on final approval. Uses D1. Depends on TC-07.

**TC-08.1** On the Related tab, in Approval History, click **Approve**. Type `UITEST {RUN} approve`
into the comments box, then click the dialog's **Approve** button.
- PASS: the dialog closes without an error.
- FAIL: the card offers no Approve, or an error is shown.

**TC-08.2** Reload the page and open the Details tab.
- PASS: Matrix Submission is unticked.
- FAIL: it is ticked.

**TC-08.3** Refresh the timeline. Read the top entry. **Screenshot.**
- PASS:
  - the badge reads "Approved";
  - the "Approval history:" line names `PR_Credit_Risk_Queue`, then `Approved`;
  - the steps read "Submitted" with "by {TESTER}", then "Credit Risk Review, Approved" with
    "{TESTER}, for Credit Risk" and the comment `UITEST {RUN} approve`.
- FAIL: any of these differs.

**TC-08.4** Look at the Related tab.
- PASS: Approval History offers no Approve, Reject or Recall, and Related shows
  `Approval Decisions (2)`, with Outcome `Submitted` on both rows. The log records the route the
  matrix chose, not the approval's result, and nothing changes a row once written.
- FAIL: any of these differs.

### TC-09: the committee route

Covers: the committee template (M12). Uses D2. Depends on TD-01.2. Leave D2 pending at the end:
CL-01 recalls it.

**TC-09.1** Open `D2.url` and click **Submit for Approval**, once. **Screenshot.**
- PASS: the modal shows:
  - "This record will be submitted to", followed by `PR_Finance_Committee`;
  - Matched rule `PR_Committee_Spend`;
  - Description: "Spend of a million or more goes to the finance committee, all three members, then
    either finance leader, whatever the region or risk.";
  - Priority `5`, Version `1`;
  - Condition `Amount__c >= 1000000`;
  - one value row: Field `Amount__c`, Value `1,200,000`.
- FAIL: no modal, or any value differs. Click **Cancel** if the process differs.

**TC-09.2** **Transient.** Click the modal's **Submit for Approval**, once.
- PASS: a toast "Submitted for approval", reading "Matched PR_Committee_Spend (v1) and routed to
  PR_Finance_Committee."
- FAIL: an error or warning toast, or the modal still open after 10 seconds.
- NOT OBSERVED: no toast captured.

**TC-09.3** Do not reload. Watch the timeline for up to 15 seconds.
- PASS: one entry, with title "Routed to PR_Finance_Committee", badge "In approval", and summary
  "Matched PR_Committee_Spend v1 because Amount = 1,200,000."
- FAIL: no entry within 15 seconds, or other text.

**TC-09.4** Read the entry's details. **Screenshot.**
- PASS: the step "Submitted" with "by {TESTER}", then exactly three steps reading "Finance
  Committee, Pending". They wait on `AMF Approver One`, `AMF Approver Two` and `AMF Approver Three`,
  one each, in any order. No step reads "Finance Leadership".
- FAIL: a different number of pending steps, another approver, or a Finance Leadership step.

**TC-09.5** Check the Details tab, then the Related tab.
- PASS:
  - Matrix Submission is ticked (a reload is allowed);
  - `Approval Decisions (1)`, whose row shows Outcome `Submitted` and Matched Rule
    `PR_Committee_Spend`;
  - Approval History shows three pending items, assigned to AMF Approver One, AMF Approver Two and
    AMF Approver Three.
- FAIL: any of these differs.

### TC-10: a rejection clears the guard

Covers: the rejection exit (M8) on the two-level template. Uses D3. Depends on TC-02.

**TC-10.1** Open `D3.url` and click **Submit for Approval**, once.
- PASS: the modal of TC-02.1 (`PR_Two_Level_Mgmt` by `PR_Catch_All`).
- FAIL: no modal, or any value differs.

**TC-10.2** **Transient.** Click the modal's **Submit for Approval**, once.
- PASS: a toast "Submitted for approval", reading "Matched PR_Catch_All (v1) and routed to
  PR_Two_Level_Mgmt."
- FAIL: an error or warning toast, or the modal still open after 10 seconds.
- NOT OBSERVED: no toast captured.

**TC-10.3** Do not reload. Watch the timeline for up to 15 seconds, then read the entry's details.
- PASS:
  - title "Routed to PR_Two_Level_Mgmt" and badge "In approval";
  - summary "Matched PR_Catch_All v1, whose condition reads no fields, so it matches every record.";
  - the steps "Submitted" with "by {TESTER}", then "Manager, Pending" with "Waiting on AMF
    Approver One".
- FAIL: no entry within 15 seconds, or any of these differs.

**TC-10.4** On the Related tab, in Approval History, click **Reject**. Type `UITEST {RUN} reject` into
the comments box, then click the dialog's **Reject** button.
- PASS: the dialog closes without an error.
- FAIL: the card offers no Reject, or an error is shown.

**TC-10.5** Reload the page and open the Details tab.
- PASS: Matrix Submission is unticked.
- FAIL: it is ticked.

**TC-10.6** Refresh the timeline and read its entry. **Screenshot.**
- PASS:
  - the badge reads "Rejected";
  - the "Approval history:" line names `PR_Two_Level_Mgmt`, then `Rejected`;
  - a step reads "Manager, Rejected", with "{TESTER}, for AMF Approver One" and the comment
    `UITEST {RUN} reject`;
  - no step reads "Manager's Manager" or "Pending".
- FAIL: any of these differs.

---

## 4. Opportunity tests

### TC-11: the Opportunity record page before any submission

Covers: the second governed object (M11), and the related-list buttons (M12). Uses D7. Depends on
TD-01.5.

**TC-11.1** Open `D7.url`. Look at the header buttons and the header's drop-down. **Screenshot.**
- PASS: exactly one action labelled **Submit for Approval**, counting both places.
- FAIL: none, or two or more.

**TC-11.2** Look at the right-hand column.
- PASS: the **Approval Timeline** card, reading the empty-state text of TC-01.3.
- FAIL: the card is missing, or reads anything else.

**TC-11.3** Open the Details tab.
- PASS: Matrix Submission is unticked.
- FAIL: it is ticked.

**TC-11.4** Open the Related tab.
- PASS: `Approval Decisions (0)`, offering no New and no Change Owner action. Approval History shows
  no rows and offers no actions.
- FAIL: any of these differs.

### TC-12: the Opportunity catch-all, previewed and cancelled

Covers: the Opportunity matrix's default route (M11), and a preview that writes nothing (M5). Uses
D7. Depends on TC-11.

**TC-12.1** Click **Submit for Approval**, once. **Screenshot.**
- PASS: the modal shows:
  - "This record will be submitted to", followed by `OPP_Manager_Approval`;
  - Matched rule `OPP_Catch_All`;
  - Description: "Every other deal goes to the submitter's manager: the default route, visible in the
    matrix in priority order (arch doc 3.2).";
  - Priority `9999`, Version `1`, Condition `TRUE`;
  - "This rule's condition reads no fields, so it matches every record."
- FAIL: no modal, or any value differs.

**TC-12.2** Click **Cancel**.
- PASS: the modal closes, and no toast appears within 5 seconds.
- FAIL: a toast appears, or the modal stays open.

**TC-12.3** Reload the page.
- PASS: the timeline reads the empty-state text, Matrix Submission is unticked, and Related shows
  `Approval Decisions (0)`.
- FAIL: any of these differs.

### TC-13: a lower priority number wins

Covers: rule priority across Opportunity rules (M11). D8 is on an Energy account, so it matches two
rules: `OPP_Large_Deal` at priority 10 and `OPP_Key_Industry` at priority 20. Uses D8. Depends on
TD-01.5.

**TC-13.1** Open `D8.url` and click **Submit for Approval**, once. **Screenshot.**
- PASS: the modal shows:
  - "This record will be submitted to", followed by `OPP_Two_Level_Mgmt`;
  - Matched rule `OPP_Large_Deal`;
  - Description: "A deal of 250,000 or more takes two levels of management, whatever the account.";
  - Priority `10`, Version `1`;
  - Condition `Amount >= 250000`;
  - one value row: Field `Amount`, Value `300,000`.
- FAIL: no modal, or any value differs. Matched rule `OPP_Key_Industry` is a FAIL: priority 20 must
  not win over 10.

**TC-13.2** Click **Cancel**, then reload the page.
- PASS: no toast, the timeline reads the empty-state text, and Related shows
  `Approval Decisions (0)`.
- FAIL: a toast, a timeline entry, or a row.

### TC-14: the key-industry route, end to end

Covers: Opportunity governed by configuration alone (M11), the `IN` operator over a standard
relationship (M9), and the timeline's live update (M7). Uses D5. Depends on TD-01.5. Leave D5 pending
at the end: CL-01 recalls it.

**TC-14.1** Open `D5.url` and click **Submit for Approval**, once. **Screenshot.**
- PASS: the modal shows:
  - "This record will be submitted to", followed by `OPP_Two_Level_Mgmt`;
  - Matched rule `OPP_Key_Industry`;
  - Description: "A deal with an Energy or Banking account takes two levels of management, whatever
    the amount.";
  - Priority `20`, Version `1`;
  - Condition `Account.Industry IN ('Energy', 'Banking')`;
  - one value row: Field `Account.Industry`, Value `Energy`.
- FAIL: no modal, or any value differs.

**TC-14.2** **Transient.** Click the modal's **Submit for Approval**, once.
- PASS: a toast "Submitted for approval", reading "Matched OPP_Key_Industry (v1) and routed to
  OPP_Two_Level_Mgmt."
- FAIL: an error or warning toast, or the modal still open after 10 seconds.
- NOT OBSERVED: no toast captured.

**TC-14.3** Do not reload. Watch the timeline for up to 15 seconds. **Screenshot.**
- PASS: one entry, with title "Routed to OPP_Two_Level_Mgmt", badge "In approval", and summary
  "Matched OPP_Key_Industry v1 because Account > Industry = Energy."
- FAIL: no entry within 15 seconds (reload and note whether it appears; the step stays FAIL), or
  other text.

**TC-14.4** Read the entry's details.
- PASS: the steps "Submitted" with "by {TESTER}", then "Manager, Pending" with "Waiting on AMF
  Approver One".
- FAIL: any difference.

**TC-14.5** Check the Details tab, then the Related tab.
- PASS:
  - Matrix Submission is ticked (a reload is allowed);
  - `Approval Decisions (1)`, whose row shows Outcome `Submitted` and Matched Rule
    `OPP_Key_Industry`;
  - the card offers no New and no Change Owner action.
- FAIL: any of these differs.

---

## 5. Optional tests: only when `RUN_OPTIONAL` is `yes`

Otherwise record TC-15 and TC-16 as NOT RUN, and go to section 6.

### TC-15: a rule in the full grammar, added in Setup and removed

Covers: M9's grammar, written by an admin in Setup with no deploy. It changes the org's configuration
for a few minutes. TC-15.4 is the cleanup: if it fails, the report must say so first. Uses D7.
Depends on TC-12.

**TC-15.1** Open Setup from the gear icon. In Quick Find, type `Custom Metadata Types` and open it.
Click **Approval Matrix Rule**, then **Manage Approval Matrix Rules**, then **New**. Enter these
values, replacing any value the form pre-fills, and click **Save**:

| Field | Value |
|---|---|
| Label | `UITEST {RUN} Grammar` |
| Approval Matrix Rule Name | `UITEST_{RUN_U}_Grammar` |
| Object API Name | `Opportunity` |
| Priority | `15` |
| Expression | `Name STARTS_WITH 'UITEST' AND NOT (Account.Industry IN ('Energy', 'Banking')) AND CloseDate <= TODAY(+60)` |
| Process API Name | `OPP_Manager_Approval` |
| Description | `UI test rule. Delete after the run.` |
| Version | `1` |
| Active | ticked |

- PASS: the record saves, and its page shows these values.
- FAIL: an error on save. Record the error, mark TC-15.2 and TC-15.4 BLOCKED, and still do TC-15.3 if
  a record was created.

**TC-15.2** Open `D7.url` and click **Submit for Approval**, once. **Screenshot.**
- PASS: the modal shows:
  - "This record will be submitted to", followed by `OPP_Manager_Approval`;
  - Matched rule `UITEST_{RUN_U}_Grammar`;
  - Priority `15`, Version `1`;
  - Condition exactly as typed in TC-15.1;
  - three value rows, in any order: Field `Name`, Value `UITEST {RUN} Hotels deal`; Field
    `Account.Industry`, Value `Hospitality`; Field `CloseDate`, Value `{D7.closeDate}` written as
    YYYY-MM-DD.
- FAIL: another matched rule, or any value differs.
- Then click **Cancel**.

**TC-15.3** Return to Setup, open the list of Approval Matrix Rules, click **Del** beside
`UITEST {RUN} Grammar`, and confirm.
- PASS: the rule is no longer listed.
- FAIL: it is still listed.

**TC-15.4** Open `D7.url` and click **Submit for Approval**, once.
- PASS: the modal's Matched rule is `OPP_Catch_All` again.
- FAIL: it is `UITEST_{RUN_U}_Grammar`. Report **CLEANUP FAILED: rule UITEST_{RUN_U}_Grammar is
  still active** at the top of the report.
- Then click **Cancel**.

### TC-16: the Flow actions are available

Covers: the Flow entry point (M10) and the validator's Flow action (M4). Read only: nothing is saved.

**TC-16.1** In Setup, Quick Find `Flows`, click **New Flow**, choose to start from scratch, choose
**Autolaunched Flow (No Trigger)**, and create it.
- PASS: Flow Builder opens on an empty canvas.
- FAIL: an error.

**TC-16.2** Add an element on the canvas, choose **Action**, and search for
`Submit for Matrix Approval`. **Screenshot.**
- PASS: an action named **Submit for Matrix Approval** is listed.
- FAIL: no such action.

**TC-16.3** Clear the search and search for `Validate Approval Matrix Configuration`.
- PASS: an action with that name is listed.
- FAIL: no such action.

**TC-16.4** Cancel the action dialog and close Flow Builder **without saving**, discarding the flow
if asked.
- PASS: Flow Builder closes, and no flow was saved.
- FAIL: a flow was saved. Report its name.

---

## 6. CL-01: cleanup

Recall what is still pending, so that no approver is left with test work. Delete nothing (rule 4).

**CL-01.1** Open `D2.url`, Related tab, Approval History. Click **Recall** (a button, or in the
card's drop-down), type `UITEST {RUN} cleanup`, and confirm with the dialog's **Recall**. Reload.
- PASS: Matrix Submission is unticked, and Approval History offers no Recall.
- FAIL: either differs.

**CL-01.2** Do the same on `D5.url`.
- PASS: Matrix Submission is unticked, and Approval History offers no Recall.
- FAIL: either differs.

**CL-01.3** Open `D1.url` and `D3.url`.
- PASS: neither has a pending approval: Approval History offers no Recall on either.
- FAIL: either one is still pending.

---

## 7. Report

Produce the report in this form. Put any CLEANUP FAILED line first.

```
RUN: {RUN}
Started / finished: <date and time, with time zone>
User: {TESTER}
Optional tests run: yes | no
Records: D1 {D1.number}, D2 {D2.number}, D3 {D3.number}, A1 UITEST {RUN} Energy Co,
         A2 UITEST {RUN} Hotels Ltd, D5 UITEST {RUN} Energy deal, D7 UITEST {RUN} Hotels deal,
         D8 UITEST {RUN} Large deal

Summary
| Test  | Verdict | Steps failed or blocked |
|-------|---------|-------------------------|
| TS-00 | PASS    |                         |
| ...   |         |                         |

Totals: PASS n, FAIL n, BLOCKED n, NOT RUN n; transient steps NOT OBSERVED n

TC-03 (one table per test, every step listed)
| Step    | Verdict | Observed (quote the text; values seen) | Screenshot |
|---------|---------|----------------------------------------|------------|
| TC-03.1 | PASS    | modal: PR_Credit_Risk_Queue, PR_Credit_Risk_Review, 30, 1, ... | R...-TC-03.1.png |

Notes
- anything a step asked you to note ("needed reload"), and anything unexpected you saw, quoted
```
