# Approval Matrix — User Guide

| | |
|---|---|
| **Applies to** | The framework as built through phase M16.7, 24 October 2026 |
| **Written for** | People who submit and approve Purchase Requests and Opportunities, and the administrators who look after the approval matrix |
| **Related guides** | [Functional documentation](functional-documentation.md) · [Technical documentation](technical-documentation.md) · [Claude connector guide](claude-connector.md) |

**How to use this guide:**
- **Everyone:** read section 1.
- **Submitters:** sections 3 to 5.
- **Approvers:** section 6.
- **The AI assistants and Claude:** sections 7 and 8.
- **Matrix administrators:** section 9.
- **When something goes wrong:** section 10 and Appendix B.

Record numbers such as PR-00000123 in this guide are examples.

## Contents

1. [The approval matrix in two minutes](#1-the-approval-matrix-in-two-minutes)
2. [Getting access](#2-getting-access)
3. [Submitting a record for approval](#3-submitting-a-record-for-approval)
4. [Reading the Approval Timeline](#4-reading-the-approval-timeline)
5. [Plain-English explanations](#5-plain-english-explanations)
6. [For approvers](#6-for-approvers)
7. [The Approval Matrix Assistant](#7-the-approval-matrix-assistant)
8. [Using Claude](#8-using-claude)
9. [For matrix administrators](#9-for-matrix-administrators)
10. [Troubleshooting and questions](#10-troubleshooting-and-questions)
- [Appendix A: Condition language quick reference](#appendix-a-condition-language-quick-reference)
- [Appendix B: Messages and what they mean](#appendix-b-messages-and-what-they-mean)

---

## 1. The approval matrix in two minutes

When you click **Submit for Approval** on a Purchase Request or an Opportunity:

1. **The matrix checks the record.** The approval matrix, a list of routing rules your administrators
   look after, reads the record's values.
2. **It picks the route.** It tries the rules in order, and the first one that fits picks the
   approval process: for example "two levels of management" or "the finance committee".
3. **You confirm.** It shows you that route, the rule that chose it and the values it read, before
   anything happens.
4. **Salesforce takes over.** The record goes into that approval process, exactly as before:
   approvers receive the request, the record is locked, and the approval history builds up.
5. **The reason is kept.** A permanent *decision log* entry records which rule decided and why, so
   anyone allowed to can see later why the request went where it did.

**Words you will see:**

| Word | What it means for you |
|---|---|
| **Approval process** | The route: who approves, and in what order. Its name looks like `PR_Two_Level_Mgmt` |
| **Rule** | One line of the matrix: "when this is true, use that approval process". Its name looks like `PR_High_Risk` |
| **Matrix Submission** | A checkbox the framework ticks when it submits your record. You cannot tick it yourself, and you never need to |
| **Approval Timeline** | The panel on the record page that shows every submission, why it went where it did, and what has happened since |
| **Decision log** | The permanent record of each submission, numbered `ADL-00000001` and onwards |

**Three things to know:**
- **You do not choose the route; the matrix does,** from the record's values. If a route looks
  wrong, check the values first, then ask your matrix administrator.
- **If no rule fits, the record is not submitted,** and the attempt is recorded. Today both kinds of
  record have a catch-all rule, so this happens only if the rules change.
- **The AI features explain and preview. They never decide** a route or an approval.

---

## 2. Getting access

Ask your Salesforce administrator for what you need:

| You want to | You need |
|---|---|
| Submit records and follow them on the timeline | The **Approval Matrix User** permission set |
| Approve requests | **Approval Matrix User**, read access to the records you approve, and a licence that covers the object. Opportunities need a full Salesforce licence |
| Use **Explain in plain English** | Also the **Prompt Template User** permission set, with an Einstein Prompt Templates licence |
| Use the **Approval Matrix Assistant** | Also **Access Agentforce Default Agent** and **Approval Matrix Assistant Access**, with an Agentforce licence |
| Use **Claude** | Also **Approval Matrix Claude Connector User**. No extra licence; your profile needs API access |
| Look after the matrix | **Approval Matrix Admin**, plus **Approval Matrix Admin Assistant Access** and **Approval Matrix Claude Connector Admin** for the AI tools |

After a permission set is assigned to you, sign out and sign in again.

---

## 3. Submitting a record for approval

### 3.1 Before you submit

**What the matrix reads today:**

| Record | Fields the rules read | Other fields |
|---|---|---|
| Purchase Request | **Amount**, **Region** (APAC, EMEA, AMER), **Risk Level** (Low, Medium, High) | **Request Name** (a short name that says what the request is for), Vendor Type, Account |
| Opportunity | **Amount**, and the **Account's Industry** | |

Before you click the button:
- **Save your changes first.** The matrix reads the values saved on the record at the moment you
  submit.
- **Check the record is not already waiting for approval.** A record can be in only one approval at a
  time.
- **For a route that goes to your manager,** make sure your Salesforce user record names one.

### 3.2 Step by step

1. **Open the record.**
2. **Click Submit for Approval** in the action bar at the top of the page. This is the framework's
   own action: the standard Salesforce button has been removed from these records.
3. **Read the Confirm approval route window:**
   - **"This record will be submitted to"**, followed by the approval process's name;
   - **Matched rule**, **Description**, **Priority**, **Version** and **Condition**: the rule that
     chose the route;
   - **Values the rule read**: each field, by its technical name such as `Amount__c`, and its value.
     An empty field shows as `(blank)`;
   - the note at the bottom: "Rules are checked in priority order, and the first one whose condition
     is true decides the route. Nothing has been submitted yet."
4. **Check it.** Is that the route you expected, and are the values right?
5. **Decide:**
   - click **Submit for Approval** to go ahead; or
   - click **Cancel** (or close the window) to stop. Nothing is recorded when you cancel.
6. **Read the message** that confirms the result (section 3.3). The Approval Timeline adds the new
   entry by itself.

> If the record would be blocked, or the matrix cannot decide, the window does not open: there is no
> route to confirm. The attempt is recorded straight away, and a message tells you why.

### 3.3 What the messages mean

| You see | It means | What to do |
|---|---|---|
| **Submitted for approval.** Matched `PR_Catch_All` (v1) and routed to `PR_Two_Level_Mgmt`. | Done | Nothing. Follow it on the timeline |
| **Submitted, by a different route than previewed.** The record or the matrix changed after the preview. Matched … | Something changed between the preview and your confirmation, and the record went by the new route. It is recorded | Check the timeline. If the route is wrong, recall the request (section 3.5) and talk to your matrix administrator |
| **Not submitted.** No active rule matched this Purchase_Request__c. … | Blocked: no rule fits the record. It is recorded | Check the record's values. If they are right, ask your matrix administrator |
| **Not submitted.** Approval process `PR_Two_Level_Mgmt` refused the submission: MANAGER_NOT_DEFINED: Manager undefined. | Failed: Salesforce refused the submission. It is recorded | Here, ask your administrator to set your manager, then submit again |
| **Not submitted.** Matrix_Submission__c could not be set, so the record was not submitted to … | Failed: another rule on the record, such as a validation rule, stopped it. It is recorded | Fix what the message describes, then submit again |
| **Could not submit for approval.** A record that is already in an approval process cannot be submitted again … Already pending: … in `<process>` | It is already waiting for approval. Nothing is recorded | Wait for it to finish, or recall it |
| **Could not submit for approval.** Submission requires read access to the record. … | You cannot read this record | Ask your administrator |
| **Could not submit for approval.** … is not governed by the approval matrix … | The matrix has been switched off for this kind of record | Ask your matrix administrator |
| **Could not submit for approval.** A message ending "at position" followed by a number, or mentioning "Unknown field" | A rule is broken, or you cannot see a field a rule reads | Send the message to your matrix administrator |

### 3.4 After you submit

- **Matrix Submission is ticked,** on the Details tab. You may need to reload the page to see it.
- **The record is locked.** While it waits for approval, only administrators can edit it.
- **The approvers are told,** according to your organisation's approval notification settings.
- **The related lists update.** On the Related tab, **Approval History** shows the approval and
  **Approval Decisions** shows the decision log entry. These cards can need a page reload to catch
  up; the timeline updates by itself.
- **When the approval ends:**
  - **Approved:** a Purchase Request stays locked; an Opportunity is unlocked so the deal can still
    be worked on.
  - **Rejected:** the record is unlocked, so you can correct it and submit it again.
  - Either way, Matrix Submission is unticked.

### 3.5 Recalling a request

1. **Open the record** and go to the **Related** tab.
2. **On the Approval History card, choose Recall.** It may be in the card's drop-down menu: the small
   down-arrow at its top right.
3. **Matrix Submission unticks.** Reload the page to see it.

You can now edit the record and submit it again. The matrix decides afresh, and the new attempt gets
its own entry. The assistants and Claude cannot recall a request for you.

### 3.6 Submitting again

After a rejection or a recall, correct the record if needed and click **Submit for Approval** again.
Every attempt is recorded separately, and the timeline shows them all, newest first.

### 3.7 Opportunities

Opportunities work the same way, with the same action and the same timeline. Their rules today:
- deals of 250,000 or more go to two levels of management;
- so do deals whose account is in the Energy or Banking industry;
- every other deal goes to your manager.

All three routes follow your management chain, so your user record must name your manager.

### 3.8 Finding your records

- **Purchase Requests tab → All Purchase Requests:** each request's name, amount, region, risk level,
  Matrix Submission and owner.
- **Approval Decision Logs tab → All Decisions:** the decision log entries you can see. That is your
  own, or every entry for an administrator.
- **Opportunities → Matrix Opportunities,** in the development org.

---

## 4. Reading the Approval Timeline

**Where it is.** The Approval Timeline sits in the right-hand column of a Purchase Request or
Opportunity page, on a desktop browser. In a narrow window it can appear below the main content.
Phones show the standard page, without the timeline.

**What it shows.** One entry for each submission attempt, newest first, with the newest opened. It
shows the 50 most recent entries; the Approval Decisions and Approval History related lists hold
everything.

### 4.1 An entry, from top to bottom

1. **A headline,** with the date and time in your own Salesforce time zone:

   | Headline | Meaning |
   |---|---|
   | **Routed to** `<process>` | The matrix routed it. The badge says where the approval stands |
   | **Not submitted: no rule matched** | Blocked |
   | **Not submitted: the attempt failed** | Failed. The line underneath gives the reason |
   | **Submitted to** `<process>`, with "The decision log row that explains this route is not visible to you." | You can see the approval but not the reason: it is someone else's submission, and the approval is not waiting on you |

2. **A badge:** *In approval*, *Approved*, *Rejected*, *Recalled*, *Blocked* or *Failed*.
3. **A one-line reason,** such as: "Matched PR_Credit_Risk_Review v1 because Risk Level = Medium and
   Amount = 60,000."
4. **The details,** opened with the arrow next to the entry (*Show details* / *Hide details*):
   - the **Explain in plain English** button (section 5);
   - **Rule**: the rule's name and version;
   - **Condition**: the rule's condition, exactly as it was when the decision was made;
   - **Values read**: each field's label and value. Hover over one to see the field's technical name;
   - **Why it was not submitted**, for a blocked or failed attempt;
   - **Submitted by**;
   - **Decision log**: a link to the entry, such as ADL-00000027;
   - **Approval history**: the approval process and its status, then each step:

   | Step line | Meaning |
   |---|---|
   | **Submitted** · by `<name>` | The submission |
   | `<Step name>`, **Approved** (or **Rejected**) · `<name>` · date | A decision, with its comments underneath |
   | `<Step name>`, **Pending** · Waiting on `<name>` | The step is pending with this person or queue |
   | `<name>`, for `<name>` | Someone acted for the person or queue the step was assigned to: a queue member deciding for the queue, a delegated approver, or an administrator on someone's behalf. A reassigned step also reads this way |
   | `<Step name>`, **No response** | Another approver decided first, so this request was withdrawn |
   | **Recalled** · by `<name>` | The submitter recalled it |

### 4.2 Other things it may say

| Text | Meaning |
|---|---|
| "This record has not been submitted for approval. When it is, this timeline shows which rule routed it, why, and every approval step that follows." | No attempts yet |
| "Only the most recent entries are shown. The Approval Decisions and Approval History related lists hold the full record." | More than 50 attempts |
| "The approval history for this submission is not available." | The decision is recorded, but its approval could not be found. Tell your administrator |
| "You need read access to this record to see its approval timeline." | You cannot read the record |

**Refresh.** The circular-arrow button in the card's top right reads everything again. Use it when an
approver has acted elsewhere, or after the assistant has submitted for you.

**The condition is shown as it was.** If an administrator has changed the rule since, an old entry
still shows the old condition and version. This is deliberate: a past decision is always explained by
the rule that actually made it.

### 4.3 Who sees what

| You are | You see |
|---|---|
| The submitter | Everything about your own submissions |
| The person an approval is waiting on (directly, through a queue or group you belong to, or as a delegated approver) | Everything about that approval, while it waits on you |
| Anyone else who can read the record | The approval steps, but not the routing reason |
| A matrix administrator | Everything |

---

## 5. Plain-English explanations

1. **Expand** a timeline entry that has a decision.
2. **Click Explain in plain English.**
3. **Wait a few seconds.** "Einstein is writing a plain-English explanation of this decision." is
   shown while it works.
4. **Read the card.** A card headed **In plain English**, with an **AI-generated** badge, explains in
   two to four sentences why the record went where it did and where the approval stands. Underneath:
   "Written by Einstein at `<time>` from decision log ADL-…. Check it against the recorded details
   below."
5. **For a fresh version,** use the circular arrow on the card (*Write it again*).

**Things to know:**
- **It uses only what the timeline shows you.** If you cannot see the routing reason, the explanation
  says so rather than guessing.
- **It is never saved.** If you come back later, ask again. When the approval moves on (an approver
  acts, say), the explanation is put away, because it would be out of date.
- **It is an aid, not the record.** The recorded details underneath it are the official record.
- **If it cannot be written,** the card says why, with a **Try again** link. Appendix B lists the
  messages.

---

## 6. For approvers

### 6.1 Knowing what is waiting for you

- **Salesforce tells you** about approval requests through your organisation's usual approval
  notifications and lists.
- **The assistant and Claude can list them:** ask "What is waiting for my approval?". You get the
  requests assigned to you, to queues or groups you belong to, or to someone whose delegated approver
  you are. They are listed oldest first, up to 10, each with its approval process, step, submitter and
  how long it has waited.

### 6.2 Why a request came to you

Open the record. While the approval is waiting on you, the timeline shows you the full reason: the
rule, its condition and the values it read, even if someone else submitted it. This applies whether
it is waiting on you directly, through a queue or group you are in, or because you are the delegated
approver.

Once you have acted, or the request has moved to the next approver, you still see the approval steps,
but no longer the routing reason, unless you are also the submitter or an administrator.

### 6.3 A briefing before you decide

- **In the assistant:** open the record and say "Brief me on this before I decide", or name it: "Brief
  me on PR-00000123".
- **In Claude:** "Brief me on PR-00000123."

The briefing covers:
- what is being asked;
- why the matrix sent it to this approval process;
- the values the rule read;
- what has happened in the approval so far.

**It never tells you whether to approve or reject.** That decision is yours. A briefing is available
only to the person the approval is waiting on. Anyone else is told: "`<record>` is not waiting on you
for approval, so there is nothing for you to decide. You can still ask why it went where it did."

### 6.4 Deciding

- **Decide in Salesforce, as usual:** approve, reject, or reassign where your organisation allows it,
  from your approval request or the record's Approval History card.
- **Nothing in the framework can decide for you.** It, the assistants and Claude cannot approve,
  reject, recall or reassign.
- **Comments you add** appear in the timeline's approval history.
- **A rejection at any step** rejects the whole request and unlocks the record for the submitter.

### 6.5 How each approval process behaves

| Approval process | What to expect as an approver |
|---|---|
| `PR_Two_Level_Mgmt`, `OPP_Two_Level_Mgmt` | You are either the submitter's manager (step *Manager*) or that manager's manager (step *Manager's Manager*) |
| `OPP_Manager_Approval` | One step: the submitter's manager |
| `PR_Three_Level_Finance` | Three named approvers in turn: *Finance Analyst*, *Finance Controller*, *Finance Director* |
| `PR_Credit_Risk_Queue` | Assigned to the Credit Risk queue. Any member can decide, including members through the Finance Approvers group. The first to act decides for everyone |
| `PR_Finance_Committee` | The *Finance Committee* step goes to three members, and all must approve: one rejection ends the request. Then *Finance Leadership*: either of two leaders, and the first to respond decides. The other leader's request is withdrawn and shown as *No response* |

### 6.6 If you cannot open the record

Salesforce assigns approvals without checking whether the approver can open the record. If you are
asked to approve a record you cannot see, tell your administrator; they need to give you access.

---

## 7. The Approval Matrix Assistant

The Approval Matrix Assistant is an Agentforce assistant for submitters and approvers.

### 7.1 Opening it

Open the **Agentforce** panel and choose **Approval Matrix Assistant**. It works best with a Purchase
Request or Opportunity open: say "this" or "it", and it uses the record on your screen. Otherwise,
name the record by its number (PR-00000123), its request name, or the opportunity's name. If several
records match, it lists them and asks which one you mean.

It greets you with: "Hi! I can show where a record's approval will go, try what-if changes, submit it
for you, show where your requests stand and what is waiting for your approval, and explain any
approval decision in plain English. …"

### 7.2 What to ask

| To | Say, for example | You get |
|---|---|---|
| See where it would go | "Where would this go for approval?" or "Which rule applies to PR-00000123?" | The approval process, the deciding rule and its priority, the values it read, and "Nothing has been submitted yet." |
| Try a what-if | "What if the amount were 120k and the region APAC?" | Where it would go with those values, compared with where it would go today. Nothing changes |
| Submit | "Submit it." | A preview, then a submission once you confirm (section 7.3) |
| Understand a decision | "Why did this go to the credit-risk queue?" or "Explain this approval decision in plain English." | A plain-English explanation of the newest decision on the record |
| Check your requests | "Where do my approval requests stand?" or "Which of my requests are still waiting?" | Your requests from the last 90 days: those still waiting first, then the rest, up to 10 |
| See what is waiting for you | "Is anything waiting for my approval?" | Your pending approvals, oldest first, up to 10 |
| Get a briefing | "Brief me on this before I decide." | A briefing (section 6.3) |

### 7.3 Submitting through the assistant

The assistant follows strict steps, and the most important ones are enforced by Salesforce rather
than left to the AI:

- **It always previews first.** It may describe the route in its own words, such as "two-level
  management approval", rather than give the approval process's name, its rule and the values it
  read. To see those before you confirm, ask "Where would it go?" first.
- **It can submit only the record it has just previewed,** to the route that preview found.
- **You confirm once, in the chat.** The assistant says it is about to submit the record, and
  nothing is submitted until you reply "yes". There is no separate confirmation button.
- **If the record or the matrix changed** since the preview, it submits by the new route and says so
  clearly. Claude refuses instead (section 8).
- **If the preview shows the record would be blocked or would fail,** it tells you that submitting
  would only record the attempt, and submits only if you still want that.
- **After it submits,** click the timeline's refresh button to see the new entry. The panel cannot
  refresh the page for you.

### 7.4 Writing a what-if

- **Fields:** name them by their label or technical name: "Amount", "Region", "Risk Level".
- **Several changes:** separate them with semicolons: "Amount = 120000; Region = APAC".
- **Numbers** can be written `120000`, `120,000`, `$120,000`, `120k` or `1.2m`.
- **Picklists:** use one of the field's own values, in any case: "apac" works. If you use a value
  that does not exist, it tells you the allowed values.
- **Checkboxes:** yes or no, true or false. **Dates:** 2026-12-31. **Blank:** "blank" or "none".
- **Only the record's own fields** can change, not those of a related record such as the account's
  industry.
- **A field no rule reads** makes no difference, and the assistant tells you so.
- **A what-if never changes the record.** To submit with those values, edit the record first, then
  ask the assistant to preview and submit it.
- **A follow-up what-if** ("and would it …") keeps the values you tried before, and the answer says
  so.

### 7.5 What it will not do

- Approve, reject, recall or reassign.
- Change records or rules.
- Tell you whether to approve or reject.
- Answer questions unrelated to approvals.

### 7.6 Tips

- **It sees only what you can see in Salesforce.**
- **If an answer seems stale,** start a new conversation: the assistant may reuse an earlier answer
  within one conversation.
- **Every route, rule, value and approver it states comes from Salesforce, not from the AI.** If an
  answer looks invented, start a new conversation and tell your administrator.

---

## 8. Using Claude

If your organisation has set it up, you can use the matrix from Claude: in claude.ai, Claude Desktop,
the Claude mobile apps or Claude Code. There are two connectors:
- **Approval Matrix**, for everyone;
- **Approval Matrix Admin**, for matrix administrators.

- **Connecting** takes a few minutes, once. Your administrator gives you the connector's address and
  an OAuth client ID. The [Claude connector guide, section 3](claude-connector.md#3-connecting-claude-each-person-once)
  has the steps.
- **What to ask:** the same kinds of questions as the assistant:
  - "Where would PR-00000123 go for approval?"
  - "What if it were 120,000 and in APAC?"
  - "Why did PR-00000123 go to the credit-risk queue?"
  - "What is waiting for my approval?"
  - "Brief me on PR-00000123."
  - "Submit PR-00000123."
- **How a submission stays safe:**
  - Claude asks your permission before it submits. Keep `submit_for_approval` on **Needs approval**
    in the connector's settings.
  - Salesforce then checks that you previewed the same record and route within the last 15 minutes.
  - If the route has changed since, nothing is submitted, and Claude tells you the new route.
- **What Claude cannot do:** approve, reject, recall or reassign. It cannot change records or rules.
  Claude writes the words, but every fact comes from Salesforce, and it sees only what you can.
- **If something goes wrong,** see the [connector guide's troubleshooting table](claude-connector.md#6-troubleshooting).

---

## 9. For matrix administrators

### 9.1 How the matrix decides

1. **Only active rules for the record's object** are considered.
2. **They are tried in ascending priority:** 5, then 10, then 9999.
3. **The first rule whose condition is definitely true decides,** and its approval process is the
   route. Later rules are never considered.
4. **If no rule is true, the submission is blocked** and recorded. There is no hidden default; the
   catch-all rule (`TRUE`, priority 9999) is the default.
5. **A broken rule stops things rather than misrouting.** If a rule fails while a record is checked,
   that attempt fails and is recorded. If a rule cannot be read at all, every submission for that
   object is refused until it is fixed. The release checks catch both before they go live.
6. **Past decisions keep the rule, version, condition and values they recorded,** whatever you
   change later.

### 9.2 Where the rules live

- **The source of truth is the rule files in source control,** one file per rule:
  `force-app/main/default/customMetadata/Approval_Matrix_Rule.<RuleName>.md-meta.xml`. They reach the
  org through the release process (section 9.7).
- **To look at the live rules in the org:** Setup → **Custom Metadata Types** → **Approval Matrix
  Rule** → **Manage Approval Matrix Rules**.
- **Do not edit rules directly in Setup in a production org.** That skips the release checks, and the
  next deployment overwrites your edit. In a sandbox, Setup edits are fine for experiments; run the
  post-deployment validation (section 9.7, step 4) afterwards.

### 9.3 What a rule contains

| Field | What to put |
|---|---|
| **Label** | A readable name, such as `PR - EMEA Over 500k` |
| **Name** | A unique technical name. Letters and digits joined by single underscores, starting with the object's prefix (`PR_`, `OPP_`), at most 40 characters. Never reuse a name |
| **Object API Name** | `Purchase_Request__c` or `Opportunity` |
| **Priority** | A whole number. Lower is tried first. No two active rules on the same object may share one |
| **Expression** | The condition (section 9.4) |
| **Process API Name** | The approval process's technical name, such as `PR_Finance_Committee`. It must be active for that object |
| **Description** | One sentence, at most 255 characters, saying what the rule is for. Submitters see it in the preview |
| **Version** | 1 for a new rule; add 1 on every change |
| **Active** | Only active rules route. New rules start inactive |

### 9.4 Writing conditions

A condition compares the record's fields with values.

**Fields** are written by their technical (API) names:
- custom fields end in `__c`, such as `Amount__c`;
- standard fields have plain names, such as Opportunity's `Amount`;
- fields of a related record are reached through the relationship name: `Account__r.Name` for
  Purchase Request's custom Account lookup, `Account.Industry` for Opportunity's standard one. You
  can go up to three relationships deep, such as `Account__r.Owner.Profile.Name`.

| Purchase Request field | Write it as | Values |
|---|---|---|
| Amount | `Amount__c` | A number |
| Region | `Region__c` | `'APAC'`, `'EMEA'`, `'AMER'` |
| Risk Level | `Risk_Level__c` | `'Low'`, `'Medium'`, `'High'` |
| Vendor Type | `Vendor_Type__c` | `'New'`, `'Existing'`, `'Strategic'` |
| Account | `Account__c`, or its fields through `Account__r.` | |

**Values:**
- **Numbers** are written plainly: `100000`, `1250.50`, `-5`. No commas, no currency signs.
- **Text and picklist values** go in single quotes: `'APAC'`. Upper and lower case do not matter.
- **Dates** are written `2026-12-31`. `TODAY` is today's date; `TODAY(30)` is 30 days ahead and
  `TODAY(-30)` 30 days ago.
- **Checkboxes** take `TRUE` or `FALSE`. **Blank** is `NULL`.

**Operators:**

| Operator | Meaning | Works on |
|---|---|---|
| `==` and `!=` | Equals, does not equal | Everything |
| `>` `>=` `<` `<=` | Greater than, and so on | Numbers and dates only |
| `IN ('A', 'B')` and `NOT IN ('A', 'B')` | Is one of, is none of | Numbers, dates, text, picklists, checkboxes |
| `CONTAINS 'x'` | Contains the text | Text and picklists |
| `STARTS_WITH 'x'` | Starts with the text | Text and picklists |
| `&&` or `AND` | Both must be true | |
| `\|\|` or `OR` | Either may be true | |
| `!` or `NOT` | The opposite | |
| `( … )` | Group conditions | |

**Order of operations.** `NOT` applies first, then comparisons, then `AND`, then `OR`. So `A || B &&
C` means `A || (B && C)`. When you mix `AND` and `OR`, add brackets to say what you mean.

**Multi-select picklists** compare with one text of values separated by semicolons:
- `Field__c CONTAINS 'Hardware;Software'` means both values are selected;
- `Field__c == 'Software;Hardware'` means exactly those two, in any order.

**Field types a condition cannot use:**
- date-and-time fields;
- long text and text area fields;
- email, phone and URL fields.

**Examples:**

| You want | Condition |
|---|---|
| Spend of a million or more | `Amount__c >= 1000000` |
| Over 100,000 in APAC | `Amount__c > 100000 && Region__c == 'APAC'` |
| The same, in words | `Amount__c > 100000 AND Region__c == 'APAC'` |
| APAC or EMEA | `Region__c IN ('APAC', 'EMEA')` |
| Medium or high risk, over 50,000 | `Risk_Level__c IN ('Medium', 'High') && Amount__c > 50000` |
| Either of two situations | `(Region__c == 'APAC' && Amount__c > 100000) \|\| Risk_Level__c == 'High'` |
| New vendors only | `Vendor_Type__c == 'New'` |
| An account whose name starts with Acme | `Account__r.Name STARTS_WITH 'Acme'` |
| No account chosen | `Account__c == NULL` |
| A risk level has been chosen | `Risk_Level__c != NULL` |
| An Opportunity closing in the next 30 days | `CloseDate >= TODAY && CloseDate <= TODAY(30)` |
| An Opportunity in a key industry | `Account.Industry IN ('Energy', 'Banking')` |
| Everything else: the catch-all | `TRUE` |

**Watch out for:**

| Mistake | Example | What happens |
|---|---|---|
| Commas in numbers | `Amount__c > 100,000` | The release check fails: "Unexpected token ','" |
| A single `=` | `Region__c = 'APAC'` | "Unexpected character '='". Use `==` |
| Double quotes | `Region__c == "APAC"` | "Unexpected character '"'". Use single quotes |
| A field's label instead of its name | `Amount > 5000` on a Purchase Request | "Unknown field 'Amount'". Use `Amount__c` |
| Greater-than on a picklist | `Risk_Level__c > 'Low'` | "Operator '>' is not supported for text values". Use `IN ('Medium', 'High')` |
| A misspelt picklist value | `Region__c == 'ASIA'` | **No error: the rule simply never matches.** Copy values exactly from the field's list |
| Forgetting the blank case | `Vendor_Type__c != 'Strategic'` | Also true when Vendor Type is blank |
| Testing a related record that may not exist | `Account__r.Name == NULL`, meant as "no account" | Never matches when there is no account: a missing related record makes the whole comparison unknown. Use `Account__c == NULL` |
| `AND` and `OR` without brackets | `A OR B AND C` | Means `A OR (B AND C)` |
| A date-and-time field | `CreatedDate > 2026-01-01` | "… is of type DATETIME, which the expression grammar does not support" |

**Blank values never satisfy a comparison.** A blank amount is neither greater nor less than
anything, and a blank field is never "in" a list. Only `== NULL` and `!= NULL` test for blanks.

**A new field needs access.** If a rule starts reading a field no rule read before, ask the release
team to make sure every submitter can read that field. Otherwise the rule fails for anyone who
cannot, with "Unknown field".

### 9.5 Choosing priorities

- **Order is policy.** Put narrow, specific rules before broad ones. Today *Committee Spend* (5)
  comes before *High Value APAC* (10), so a million-plus APAC request goes to the committee.
- **Leave gaps** (5, 10, 20, 30), so new rules fit between existing ones.
- **Keep the catch-all at 9999.**
- **No two active rules on one object may share a priority.** The release check refuses it.
- **A draft from the Admin Assistant states where it sits,** "tried after … and before …", which is
  an easy way to check its place.

### 9.6 Changing a rule safely

- **To change a rule,** edit its file, change what you need, add 1 to **Version**, and keep its
  **Name**.
- **To retire a rule,** set **Active** to false. Deactivate rather than delete.
- **Check the impact first.** Ask the Admin Assistant: "What would change for recent purchase requests
  if PR_High_Risk were taken out?"
- **When a change takes effect.** It applies to submissions made after the release. Approvals already
  under way are unaffected, and past decisions keep what they recorded.
- **Removing the catch-all** means records no other rule fits will be blocked.
- **Switching the matrix off for an object** means deactivating all of its rules. Every submission
  for that object is then refused, and none can be made until a rule is active again. Use this with
  care.

### 9.7 Releasing a change

A rule change goes live through the release process:

1. **Save the rule file** (written by hand, or taken from the Admin Assistant's draft) in
   `force-app/main/default/customMetadata/`.
2. **Run the source check:**
   `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-approval-matrix-source.ps1`
3. **Deploy:** set `AMF_USERNAME_DOMAIN` for the target org, then
   `sf project deploy start -o <org alias>`.
4. **Validate in the org:** `sf apex run --file scripts/validate-config.apex -o <org alias>`. It
   should log "Approval Matrix configuration is valid."
5. **Commit the change** to source control.

Your release team may run steps 2 to 5 for you. Tell them as well if your change alters a route that
the UI test script or the assistants' test cases rely on, so that those can be updated.

### 9.8 The Admin Assistant

Open the Agentforce panel and choose **Approval Matrix Admin Assistant**. It greets you with: "Hi! I
can draft an approval matrix rule from a description, check what a change would do to recent requests
before you release it, and report how the matrix has been doing. I never change the matrix myself."

**Draft a rule.**
- **Ask:** "Draft a rule for purchase requests: anything over 500,000 in EMEA should go to the finance
  committee." For a new version of an existing rule: "Write a new version of PR_High_Risk that also
  catches Medium risk."
- **You get:**
  - a summary: the rule's name, condition, approval process and priority, and where it sits in the
    order;
  - the assistant's assumptions;
  - the file path, and the file's contents ready to commit;
  - the reminder that it routes nothing until you release it.
- **The checks behind it:** a draft is shown only after it passes the same checks as a release: the
  condition is valid, the name is new, the priority is free, the process is active, and the matrix
  still works with it.
- **If no draft passes,** you get "No draft could be written that passes the checks …", with the
  reasons.

**Check a change's impact.**
- **Ask:** "What would that draft change for recent purchase requests?" or "What would change if
  PR_High_Risk were taken out?"
- **You get:**
  - how many records from the last 90 days were checked, on their values today;
  - how many would be decided differently, with up to 10 listed;
  - the counts per approval process, before and after;
  - how many were skipped, because they are in an approval now or you cannot read them.

**See how the matrix is doing.**
- **Ask:** "How has the approval matrix been doing over the last 90 days?" or "Is any active rule
  routing nothing?"
- **You get** a short summary plus the counted facts:
  - decisions by outcome, against the previous period;
  - each rule's share, and the catch-all's share;
  - rules that routed nothing;
  - the commonest failure reasons;
  - the oldest pending approvals.

**What it will not do.** It cannot deploy, activate, edit or delete rules, or submit or approve
anything.

**A sign of a bad draft.** If a draft shows a `.json` or `.yml` path, a priority such as "Medium", or
a condition such as `Amount > 500,000 AND Region = 'EMEA'`, the AI wrote it itself instead of using
its checked tool. Ask again in a new conversation.

**Known limit.** A draft's name is checked against *active* rules only. If it matches an inactive
rule, releasing it would overwrite that rule; check the file name before you release.

The **Approval Matrix Admin** connector in Claude offers the same three abilities. See the
[connector guide](claude-connector.md#4-things-to-ask).

### 9.9 Changing who approves

The matrix only picks the approval process. To change the steps or the approvers, the release team
makes a **new version** of the approval process (for example `PR_Three_Level_Finance_v2`), points
the rules at it, and deactivates the old one. A released approval process is never edited in place,
and the release check refuses an edit.

A new route shape, such as a different queue, is a new approval process plus a rule that names it.
Every approval process the matrix uses must:
- accept only records with Matrix Submission ticked;
- untick it on approval, rejection and recall.

### 9.10 Keeping an eye on the matrix

- **The Approval Decision Logs tab → All Decisions** list view shows you every entry.
- **Reports** on Approval Decision Logs, which are reportable.
- **The Admin Assistant's health report,** or Claude's admin connector.

Look out for:
- blocked or failed attempts;
- a large catch-all share, which may mean the specific rules miss cases;
- rules that route nothing;
- approvals pending for a long time;
- records with Matrix Submission ticked but no approval pending.

### 9.11 Correcting a decision log entry

Decision log entries are locked. The **Approval Matrix Admin** permission set includes the
**AMF Bypass Log Lock** permission, which allows an administrator to edit an entry. Use it only to
correct a genuine error, and note why. Entries cannot be deleted.

### 9.12 Validation findings

`scripts/validate-config.apex` reports every problem at once, each as `[CODE] message`:

| Code | Meaning | Fix |
|---|---|---|
| `EXPRESSION_INVALID` | A condition is not valid; the message gives the position | Correct the condition (section 9.4) |
| `DUPLICATE_PRIORITY` | Two active rules on one object share a priority | Give one a different priority |
| `PROCESS_NOT_ACTIVE` | The named approval process is not active for the object, or does not exist | Correct the name, or have the process activated |
| `PROCESS_API_NAME_MISSING` / `PROCESS_API_NAME_WHITESPACE` | The process name is empty, or has spaces around it | Correct it |
| `PRIORITY_MISSING` | A rule has no priority | Add one |
| `OBJECT_API_NAME_MISSING` / `OBJECT_NOT_FOUND` | The object is missing or misspelt | Correct it |
| `GUARD_FIELD_MISSING` / `GUARD_FIELD_WRONG_TYPE` | The object lacks a Matrix Submission checkbox | The release team adds it |
| `UNION_QUERY_INVALID` | Salesforce refuses the combined field query the rules need | Simplify the relationship paths; the message gives Salesforce's reason |

The source check prints its own sentences, such as "… does not clear Matrix_Submission__c in its
recall actions …" or "… has changed since it was released …". Each says what to fix.

### 9.13 Adding a new kind of record

Governing another object is done by configuration, but it needs the release team: a Matrix Submission
field, approval processes, the Submit for Approval action on its layouts, a decision log link, a
record page with the timeline, and rules. The
[technical documentation, section 17.3](technical-documentation.md#173-govern-a-new-object) has the
checklist.

---

## 10. Troubleshooting and questions

**Submitting**

- **The Submit for Approval action is missing.** You may lack the Approval Matrix User permission set.
  Ask your administrator.
- **I see two Submit for Approval buttons.** There should be only one: the standard Salesforce button
  is meant to be removed. Tell your administrator.
- **The route in the preview is not what I expected.** Check **Values the rule read**: a wrong or
  blank value is the usual cause. Cancel, correct the record, and try again. If the values are right,
  ask your matrix administrator.
- **I cannot tick Matrix Submission.** That is by design. Only the framework sets it.
- **I submitted the wrong record, or need to change it after submitting.** Recall it (section 3.5),
  edit it, and submit again. The matrix may then choose a different route.
- **It failed with "MANAGER_NOT_DEFINED".** Your user record has no manager. Ask your administrator to
  set one.
- **Can I submit an approved request again?** Ask your process owner whether that is allowed. Each
  attempt is recorded separately.

**The timeline**

- **My new submission does not appear.** Click the timeline's refresh button, or reload the page.
- **Matrix Submission, or a related list, looks out of date.** Reload the page. Those parts of the
  page refresh only on reload.
- **The timeline says the reason is not visible to me.** That is expected for someone else's
  submission that is not waiting on you.
- **The condition on an old entry differs from today's rule.** That is deliberate: each decision
  shows the rule as it was when it was made.
- **The times look wrong.** The timeline uses your Salesforce time zone, under your personal settings.
- **There is no timeline on my phone.** It is shown on desktop only.

**Approving**

- **The briefing says the request is not waiting on me.** It may have moved on, or you may already
  have acted. Requests assigned through a role, rather than to you, a queue, a group or as delegate,
  are not recognised.
- **Can the assistant or Claude approve for me?** No. Approve or reject in Salesforce.
- **An approved Purchase Request is still locked.** That is by design. Ask an administrator if it must
  change.

**The AI features**

- **Explain says explanations are not available.** You may lack the Prompt Template User permission
  set, or Einstein may be unavailable. Ask your administrator.
- **The assistant keeps asking which record I mean.** Name the record, or open it first.
- **An assistant's answer looks made up.** Every fact should come from Salesforce. Start a new
  conversation, ask again, and tell your administrator.

---

## Appendix A: Condition language quick reference

```
FIELDS     Amount__c   Region__c   Account__r.Name   Account.Industry      (up to 3 relationships deep)
VALUES     100000   1250.50   -5   'APAC'   2026-12-31   TODAY   TODAY(30)   TODAY(-30)   TRUE   FALSE   NULL
COMPARE    ==   !=   >   >=   <   <=                     (> and < only for numbers and dates)
LISTS      Region__c IN ('APAC', 'EMEA')        Region__c NOT IN ('AMER')
TEXT       Account__r.Name CONTAINS 'Bank'      Account__r.Name STARTS_WITH 'Acme'
COMBINE    &&  AND     ||  OR     !  NOT     ( … )        order: NOT, comparisons, AND, OR
BLANKS     Field == NULL      Field != NULL
MULTI      Field CONTAINS 'A;B'   (both selected)       Field == 'A;B'   (exactly these)
CATCH-ALL  TRUE
```

- Text comparisons ignore upper and lower case.
- A blank never satisfies `>`, `<`, `IN`, `CONTAINS` or `STARTS_WITH`.
- A missing related record makes its comparison unknown, which never matches.
- Strings use single quotes. Write `\'` for a quote inside one, and `\\` for a backslash.

## Appendix B: Messages and what they mean

**From Submit for Approval**

| Message | Meaning |
|---|---|
| Submitted for approval | It went to the approval process shown |
| Submitted, by a different route than previewed | The record or the matrix changed after the preview; it went by the new route |
| Not submitted (no active rule matched …) | Blocked; recorded |
| Not submitted (… refused the submission: …) | Failed: Salesforce refused it; recorded |
| Not submitted (Matrix_Submission__c could not be set …) | Failed: another rule on the record stopped it; recorded |
| Could not submit for approval (already in an approval process …) | It is already waiting for approval; nothing recorded |
| Could not submit for approval (requires read access …) | You cannot read the record |
| Could not submit for approval (… is not governed …) | The matrix is switched off for this kind of record |
| Could not submit for approval (… at position *n*, or Unknown field …) | A rule is broken, or you cannot see a field it reads: tell your matrix administrator |

**From the Approval Timeline and Explain**

| Message | Meaning |
|---|---|
| The decision log row that explains this route is not visible to you. | You may see the approval, not its reason |
| The approval history for this submission is not available. | The approval could not be found; tell your administrator |
| You need read access to this record to see its approval timeline. | No access to the record |
| Plain-English explanations are not available right now. Einstein said: … | Einstein, or your access to it, is unavailable; the recorded decision is unaffected |
| This decision is not visible to you, so it cannot be explained. | You cannot read that decision log entry |
| This decision is not among the most recent ones on the record, so it cannot be explained here. … | It is older than the timeline's 50 entries; open the decision log entry instead |
| Einstein returned no explanation for this decision. Try again in a moment. | Try again |

**From the assistants and Claude**

| Message | Meaning |
|---|---|
| … is not waiting on you for approval, so there is nothing for you to decide. … | Briefings are only for the current approver |
| … has not been submitted for approval yet, so there is no decision to explain. | No decision exists yet |
| Nothing governed by the approval matrix is waiting on you for approval. | Nothing is pending for you |
| You have not submitted anything through the approval matrix in the last 90 days. | No recent requests |
| No draft could be written that passes the checks. … | The Admin Assistant's draft failed the release checks twice; the reasons follow |
| This submission does not come from a preview of this record, so nothing was submitted. … | Claude: preview the record again first |
| The preview is more than 15 minutes old, so nothing was submitted. … | Claude: preview again, then confirm |
| Submitting through Claude is not set up in this org yet. … | Claude: an administrator must finish setting up the connector |
