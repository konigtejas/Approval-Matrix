# Approval Matrix Framework — Functional Documentation

| | |
|---|---|
| **Describes** | The framework as built through phase M16.7: `develop` at commit `b3f0703`, 24 October 2026 |
| **Written for** | Business owners, process owners, business analysts, auditors and project sponsors |
| **Companion documents** | [Technical documentation](technical-documentation.md) · [User guide](user-guide.md) · [Claude connector guide](claude-connector.md) · [Architecture: the target design](architecture.md) |

This document explains what the framework does, who uses it, and the business rules it follows.
It describes behaviour, not code. The technical documentation covers how it is built, and the
user guide covers how to use it day to day.

## Contents

1. [Introduction](#1-introduction)
2. [Key concepts](#2-key-concepts)
3. [Design principles](#3-design-principles)
4. [Roles and responsibilities](#4-roles-and-responsibilities)
5. [Business processes](#5-business-processes)
6. [Capabilities](#6-capabilities)
7. [Business rules](#7-business-rules)
8. [The configured matrix](#8-the-configured-matrix)
9. [Audit, compliance and controls](#9-audit-compliance-and-controls)
10. [AI assistance and its limits](#10-ai-assistance-and-its-limits)
11. [Access and licences](#11-access-and-licences)
12. [Quality characteristics](#12-quality-characteristics)
13. [Assumptions, constraints and limitations](#13-assumptions-constraints-and-limitations)
14. [Glossary](#14-glossary)
- [Appendix A: Outcomes at a glance](#appendix-a-outcomes-at-a-glance)
- [Appendix B: Release history](#appendix-b-release-history)

---

## 1. Introduction

### 1.1 The business problem

Most organisations approve the same kind of request in different ways depending on its details.
A small purchase goes to a line manager, a large one to finance, and a risky one to a credit
committee. Standard Salesforce supports this by giving each approval process its own entry
criteria and trying the processes in a fixed order. That works for two or three routes, but it
becomes hard to manage as the policy grows:

- **The policy cannot be read in one place.** It is spread across the entry criteria of many
  approval processes.
- **Changing a threshold is a technical change.** Someone has to edit an approval process, with
  all the release risk that brings.
- **Nobody can say afterwards why a request went where it did.** Approval history records who
  approved and when, not which condition sent the request there.
- **Mistakes are silent.** A condition that is wrong or broken simply never matches, and requests
  drift to whichever process catches them.
- **Routing can be bypassed.** The standard Submit for Approval button submits a record without
  any central check.

### 1.2 What the framework does

The Approval Matrix Framework **chooses which approval process a record enters, and records why.**

The routing policy is kept as a list of rules, called the *approval matrix*. Each rule says: *when
this condition is true, use that approval process*. When someone submits a record, the framework
tries the rules in priority order. The first rule whose condition is true names the approval
process. The framework submits the record to it, and writes a permanent *decision log* entry. The
entry says which rule decided, what the rule's condition was at that moment, and which field values
it read.

From then on, Salesforce's own approval process does the rest, exactly as it would without the
framework: the steps, the approvers, the notifications, the record locking and the approval
history.

The framework exists to make one promise true:

> **An administrator changes one rule, the next submission goes to a different approval process,
> and the decision log explains why. No code changes.**

### 1.3 What it deliberately does not do

- **It does not decide who approves.** The approval process the matrix selects decides how many
  steps there are, who approves each one, and whether a queue or a committee decides.
- **It does not approve, reject, recall or reassign.** People do that in Salesforce, as they
  always have.
- **It does not route by default.** If no rule matches, the submission is stopped and recorded.
  An organisation that wants a default route adds a visible *catch-all* rule to the matrix.
- **It does not guess.** If a rule cannot be evaluated, the submission stops and the failure is
  recorded. The record is never passed on to the next rule.
- **Its AI features never decide.** They explain, brief, preview and draft. The matrix chooses
  every route, and people make every approval decision.

### 1.4 Where it is used today

Two kinds of record are governed by the matrix:

- **Purchase Requests:** the framework's own object, for internal spend requests;
- **Opportunities:** the standard Salesforce sales object, governed to prove that a new object can
  be added by configuration alone.

---

## 2. Key concepts

| Term | Meaning |
|---|---|
| **Governed object** | A kind of record whose approvals the matrix routes. Today: Purchase Request and Opportunity. An object is governed exactly when it has at least one active rule |
| **Approval matrix** | The full list of routing rules, for all governed objects |
| **Rule** | One routing statement: *when this condition is true, use that approval process*. Each rule has an object, a priority, a condition, an approval process, a description, a version number and an active flag |
| **Condition** | A short formula over the record's fields, such as `Amount__c > 100000 && Region__c == 'APAC'` ("the amount is over 100,000 and the region is APAC") |
| **Priority** | A whole number that sets the order in which rules are tried: lower numbers first. No two active rules on the same object may share a priority |
| **First match** | The first rule, in priority order, whose condition is true decides the route. Later rules are not considered |
| **Catch-all rule** | A rule whose condition is simply `TRUE`, placed last (priority 9999). It is the default route, and it is visible in the matrix where anyone reviewing it can see it |
| **Approval process** | A standard Salesforce approval process, with its own steps and approvers. The matrix chooses one and does not change it. Technical material also calls it a *template* |
| **Shape** | An approval process's structure: its steps and who approves each one, such as "two levels of management" or "a committee, then a leader" |
| **Decision log** | The permanent record of every submission attempt. Each entry records who submitted and when, the rule and its version, its condition as it stood, the field values it read, the chosen approval process, and the outcome with any reason. Entries are numbered `ADL-00000001` onwards and cannot be edited or deleted by ordinary users |
| **Matrix Submission (the guard)** | A checkbox on every governed record. Only the framework ticks it, at the moment it submits. Every governed approval process accepts a record only when it is ticked, and unticks it when the approval ends. This makes the matrix the only way in |
| **Preview** | Shows where a record would go and why, without submitting or recording anything |
| **Outcome** | What happened to a submission attempt: *Submitted*, *Blocked* (no rule matched), *Failed* (the record did not enter its approval process) or *Refused* (nothing was decided). [Appendix A](#appendix-a-outcomes-at-a-glance) has the details |
| **Approval Timeline** | A panel on the record page. It lists every submission attempt, why it went where it did, and what has happened in its approval since |

---

## 3. Design principles

Six principles shape every behaviour described in this document.

| # | Principle | What it means for the business |
|---|---|---|
| 1 | **Configuration over code** | The routing policy is configuration. A new or changed rule is a configuration release, checked and deployed like any other, never a development project |
| 2 | **Select, don't resolve** | The matrix chooses *which* approval process. The process decides *who* approves and how. Approver structures stay where Salesforce administrators already manage them |
| 3 | **Explain every decision** | Salesforce's approval history says who approved and when. The decision log says why the request went there. It is permanent and cannot be rewritten |
| 4 | **Fail loudly** | A broken rule stops submissions, and the failure is recorded, rather than requests being misrouted. A stopped approval can be fixed and resubmitted; a misrouted one is an audit finding |
| 5 | **Testable and portable** | The framework is tested automatically and deploys to another Salesforce org without code changes |
| 6 | **AI assists; it never decides** | AI can explain, brief, preview, try what-ifs and draft rules. It never chooses a route, evaluates a rule, writes a rule or a log entry, approves anything, or tells an approver what to decide |

---

## 4. Roles and responsibilities

| Role | Typical people | What they do with the framework | What they need |
|---|---|---|---|
| **Submitter** | Employees raising purchase requests; sales staff submitting deals | Create and edit records; preview and submit them; follow progress on the Approval Timeline; recall a pending request; ask the assistants | The *Approval Matrix User* permission set; read access to their records |
| **Approver** | Managers; finance analysts, controllers and directors; credit-risk queue members; finance committee members | Decide approval requests in Salesforce; see why a request was routed to them; get a briefing before deciding | Read access to the record, and a Salesforce licence that includes the object. *Approval Matrix User* for the timeline and assistants |
| **Matrix administrator** | The process owner, or the Salesforce administrator who owns the routing policy | Maintain the rules; check a change's impact before release; monitor the matrix's health; read every decision log entry | The *Approval Matrix Admin* permission set |
| **Release manager or developer** | The team that deploys Salesforce changes | Release rule changes and approval processes through the release checks; maintain the approval processes | Deployment rights, and *Approval Matrix Admin* to run the post-deployment check |
| **Auditor** | Internal audit, compliance | Review why requests were routed where they were, and who decided | Read access to the decision log. Today this comes through the administrator permission set or through reports an administrator shares; there is no separate read-only auditor permission set |
| **Automation or integration** | A Salesforce Flow, or an external system | Submit records in bulk and receive one result per record | A user with *Approval Matrix User* or *Admin* and read access to the records |

**What submitters cannot do,** by design:
- tick or untick Matrix Submission themselves (it is read-only for them);
- see the matrix's rules directly. They see the rule that decided their own request, in the
  preview and on the timeline;
- read other people's decision log entries, unless they are the approver a pending approval is
  waiting on (section 9.3).

---

## 5. Business processes

### 5.1 Submitting a record

```
 SUBMITTER                     APPROVAL MATRIX                        SALESFORCE APPROVAL PROCESS
 ─────────                     ───────────────                        ───────────────────────────
 1. Opens the record and
    clicks Submit for
    Approval ────────────────► 2. Checks the user can read the record
                               3. Refuses if it is already in an
                                  approval process
                               4. Tries the rules in priority order;
                                  the first true condition names
                                  the approval process
 5. Sees the process, the  ◄── (a preview: nothing is written yet)
    rule and the values it
    read, and confirms ──────► 6. Ticks Matrix Submission
                               7. Submits the record to the ────────► 8. Accepts it, because Matrix
                                  named process                          Submission is ticked
                               9. Writes the decision log entry       10. Runs its steps: approvers,
                                                                          notifications, locking, history
 11. Sees a confirmation ◄────                                        12. On final approval, rejection or
     and a new entry on the                                               recall, unticks Matrix Submission
     Approval Timeline
```

The confirmation window (step 5) appears only when the matrix has found a route. If the record would
be blocked, or the matrix cannot decide, there is nothing to confirm. The framework then records the
attempt straight away and tells the submitter why (section 5.4).

Between the preview and the submission, the matrix decides again from scratch. If the record or the
rules changed in the meantime and the route is now different, the record goes by the new route and
the submitter is told so plainly.

### 5.2 How the matrix decides

1. Only **active** rules for the record's object are considered.
2. They are tried in **ascending priority**: 5 before 10, and 10 before 9999.
3. Each rule's condition is checked against the record's **current** values.
4. The **first** rule whose condition is true decides. Later rules are not looked at, even if they
   would also match.
5. The approval process that rule names is the route.
6. If no rule is true, the submission is **blocked** and recorded.

**A worked example.** Take a Purchase Request for 150,000, in the APAC region, at Low risk. The
Purchase Request rules (section 8.1) are tried in this order:

| Order | Rule | Condition, in words | Result |
|---|---|---|---|
| 1 | `PR_Committee_Spend` (priority 5) | The amount is 1,000,000 or more | False: 150,000 is less |
| 2 | `PR_High_Value_APAC` (priority 10) | The amount is over 100,000 and the region is APAC | **True: this rule decides** |
| 3 | `PR_High_Risk` (priority 20) | The risk level is High | Not considered |
| 4 | `PR_Credit_Risk_Review` (priority 30) | The risk level is Medium and the amount is 50,000 or more | Not considered |
| 5 | `PR_Catch_All` (priority 9999) | Always true | Not considered |

The request goes to **`PR_Three_Level_Finance`**. The decision log entry records `PR_High_Value_APAC`,
version 1, its condition `Amount__c > 100000 && Region__c == 'APAC'`, and the values it read:
Amount = 150,000 and Region = APAC.

**Some consequences of first match:**
- **Order is policy.** A 1,500,000 request in APAC at High risk goes to the finance committee, because
  `PR_Committee_Spend` (5) is tried before `PR_High_Value_APAC` (10) and `PR_High_Risk` (20).
- **Boundaries are exact.** A request for exactly 100,000 in APAC is *not* "over 100,000", so it falls
  through to the catch-all.
- **Blank values never satisfy a comparison.** A request with no amount entered is not "over
  100,000" and not "1,000,000 or more". It falls through to a later rule.

Section 8.1 has more scenarios.

### 5.3 What happens after submission

Once the record is submitted, the selected Salesforce approval process takes over:

- **The record is locked** while the approval is pending, and only administrators can edit it.
- **Approvers are asked to decide**, through Salesforce's own approval notifications and lists. They
  approve, reject, or reassign where their organisation allows it.
- **A rejection at any step rejects the whole request.**
- **After final approval,** a Purchase Request stays locked. An Opportunity is unlocked, so that an
  approved deal can still be worked on.
- **After rejection,** the record is unlocked so that it can be corrected and submitted again.
- **The submitter can recall** a pending request.
- **On final approval, final rejection and recall, Matrix Submission is unticked.** The record can
  then enter an approval process again only through the matrix.

### 5.4 When a submission does not go through

| Outcome | What it means | Recorded in the decision log? | Typical cause | What to do |
|---|---|---|---|---|
| **Blocked** | No active rule matched | **Yes**, as "Blocked - No Match", with every value the matrix read | The object has no catch-all rule, and the record fits no other rule | Correct the record if its data is wrong, or ask the matrix administrator for a rule that covers it |
| **Failed** | The record did not enter its approval process. Either the matrix could not decide, or it decided but Salesforce refused the submission | **Yes**, as "Failed", with the reason | A rule refers to a field that has since been removed; the submitter has no manager for a manager-approval process ("MANAGER_NOT_DEFINED"); a validation rule stopped the Matrix Submission tick | Fix the cause and submit again. The reason in the log entry says what it is |
| **Refused** | Nothing was decided, so nothing is recorded | No | The record is already in an approval process (the message names it); the user cannot read the record; the object is not governed | Wait for the pending approval to finish, or recall it; ask for access; ask the matrix administrator |

**A broken rule stops everything for its object.** If a rule cannot be read at all, for example
because it mentions a field that does not exist, the matrix cannot say whether a record would have
matched it. So it routes no record of that object until the rule is fixed, rather than letting
later rules catch records the broken rule should have caught. The release checks (section 6.11) stop
such a rule from reaching the live matrix.

### 5.5 Recalling and resubmitting

- A submitter recalls a pending request from the record's Approval History, using Salesforce's own
  Recall action. The framework has no recall feature of its own, and the assistants cannot recall.
- Recall, like final approval and rejection, unticks Matrix Submission.
- The submitter can then correct the record and submit it again. The matrix decides again from the
  record's current values.
- Every attempt has its own decision log entry. The Approval Timeline shows them all, newest first.

### 5.6 Automated and bulk submission

Records can also be submitted without anyone clicking the button:

- **From a Salesforce Flow**, with the *Submit for Matrix Approval* action. A record-triggered or
  scheduled flow can submit many records at once.
- **From an external system**, through the framework's REST API, up to 200 records per call.

Both use the same rules, the same checks and the same decision log as the button. Each record gets
its own result: its outcome, a message when it did not go through, the rule and process, and its
decision log entry. A problem with one record does not stop the others.

A flow or an integration acts as the user it runs as. That user needs read access to every record it
submits. A rule that uses `TODAY` takes that user's local date, so an integration user should have
the business's time zone. The date used is recorded in each decision log entry.

### 5.7 Changing the routing policy

A change to the matrix is a configuration release:

1. **Decide the change.** For example: "EMEA spend over 500,000 should go to the finance committee."
2. **Write the rule:** by hand, or with the Admin Assistant or Claude, which draft it and check it
   against the release checks before anyone sees it (section 6.8).
3. **Check its impact** on recent requests: how many of the last 90 days' requests would now go
   somewhere else (recommended).
4. **Release it.** The release runs a check of the configuration before deployment, the deployment
   itself, and a validation in the org afterwards. Any failure stops the release.
5. **From then on,** every submission uses the new matrix. Earlier decisions keep the rule, version,
   condition and values they recorded. History is never rewritten.

When a rule changes, its version number goes up, so each decision log entry says exactly which
version of the rule decided.

Changing *who approves* is a different kind of change: it means a new version of an approval process
(section 6.12), and normally involves the release team.

### 5.8 Switching the matrix off for an object

Deactivating every rule of an object switches the matrix off for it. Its Submit for Approval action
then refuses, with a message that the object is not governed. Two safeguards stay in place: the
standard Submit for Approval button stays removed, and the approval processes still require Matrix
Submission. So records of that object cannot be submitted at all until a rule is active again. This
is a deliberate kill switch.

---

## 6. Capabilities

### 6.1 Rule-based routing

- **What it does:** chooses the approval process for each submission from the approval matrix, by
  priority and first match (section 5.2).
- **Who uses it:** everyone who submits, whichever way they submit.
- **Conditions can test:**
  - numbers, currency and percentages;
  - text and picklist values;
  - multi-select picklists;
  - checkboxes;
  - dates, including dates relative to today ("within the last 30 days");
  - fields of related records, up to three relationships away, such as the account's industry.
- **Conditions can combine tests** with AND, OR and NOT, with lists ("the region is APAC or
  EMEA"), and with text tests ("the account name starts with 'Acme'").
- **Text comparisons ignore upper and lower case.**

### 6.2 Preview and confirmation

- **What it does:** before anything is submitted, shows the submitter where the record will go, which
  rule decides it, that rule's priority, version, description and condition, and the values it read.
- **Who uses it:** submitters, through the Submit for Approval action.
- **Behaviour:**
  - nothing is written or submitted until the submitter confirms; cancelling leaves no trace;
  - the route is decided again at submission, and the submitter is warned if it changed after the
    preview;
  - a record that would be blocked, or that the matrix cannot decide, skips the window and is
    recorded straight away, so that the attempt is on record.

### 6.3 Submission guard

- **What it does:** makes the matrix the only way into a governed approval process.
- **How:**
  - Matrix Submission is ticked only by the framework, at the moment it submits;
  - every governed approval process accepts a record only when Matrix Submission is ticked;
  - every way out of an approval (final approval, final rejection, recall) unticks it;
  - the standard Submit for Approval button is removed from every governed object's page layouts.
- **Enforced:** the release checks reject an approval process that breaks any of these rules, and a
  governed object's layout that still shows the standard button.

### 6.4 Decision log

- **What it does:** keeps a permanent record of every submission attempt the matrix decided.
- **What each entry holds:**

  | Item | Example |
  |---|---|
  | Decision log number | ADL-00000027 |
  | Outcome | Submitted, Blocked - No Match, or Failed |
  | Rule and version | `PR_Credit_Risk_Review`, version 1 |
  | The condition as it was evaluated | `Risk_Level__c == 'Medium' && Amount__c >= 50000` |
  | The values the rule read | Risk Level = Medium, Amount = 60,000 |
  | The approval process chosen | `PR_Credit_Risk_Queue` |
  | The reason, when it did not go through | "Approval process … refused the submission: …" |
  | Submitted by, and when | the user, and the date and time |
  | The governed record | a link to the Purchase Request or Opportunity, and its Id |
  | The approval it started | the Salesforce approval instance, for joining to approval history |

- **Behaviour:**
  - entries cannot be edited, except by holders of a special permission, which the administrator
    permission set includes;
  - entries are never deleted, and survive the deletion of the record or user they refer to;
  - later changes to a rule never change an earlier entry.

### 6.5 Approval Timeline

- **What it does:** tells each record's approval story on its page, in one place. Each submission
  attempt shows why it was routed where it was, and the approval steps that followed: who submitted,
  who approved or rejected and when, who it is waiting on now, and their comments.
- **Who uses it:** submitters, approvers, administrators and auditors.
- **Behaviour:**
  - newest first, up to the 50 most recent attempts; the related lists hold the full history;
  - updates by itself after a submission, and has a refresh button for when an approver has acted
    elsewhere;
  - shows only what the viewer may see (section 9.3), and only what was recorded. It never
    re-explains an old decision with today's rules;
  - times are shown in the viewer's own Salesforce time zone.

### 6.6 Plain-English explanations

- **What it does:** on request, Salesforce Einstein explains a recorded decision in two to four
  plain sentences: why the record went where it did, and where its approval stands.
- **Who uses it:** anyone viewing the Approval Timeline, through its **Explain in plain English**
  button.
- **Behaviour:**
  - the explanation is built only from what the timeline already shows the viewer;
  - it is labelled *AI-generated* and names the decision log entry it was written from;
  - it is generated on demand and never stored, and it is put away when the approval moves on;
  - the recorded facts stay on screen below it.

### 6.7 Approval Matrix Assistant (Agentforce)

An assistant in Salesforce's Agentforce panel, for submitters and approvers. In conversation, it can:

- **find** a Purchase Request or Opportunity by its number, name or Id;
- **preview** where a record would go, and why;
- **try a what-if:** "where would this go if the amount were 120,000 and the region APAC?" Nothing
  is changed;
- **submit** a record, but only the one it has just previewed, and only after the user confirms;
- **explain** why a record went where it did;
- **list the user's own requests** of the last 90 days and where each stands, those still waiting
  first;
- **list what is waiting for the user's approval**, directly, through a queue, or as a delegated
  approver, oldest first;
- **brief an approver** before they decide: what is asked, why it was routed to them, and what has
  happened so far. It never recommends approving or rejecting.

It cannot approve, reject, recall or reassign, and it cannot change records or rules.

### 6.8 Approval Matrix Admin Assistant (Agentforce)

A second assistant, for matrix administrators only. It changes nothing. It can:

- **draft a rule** from a description, such as "anything over 500,000 in EMEA should go to the
  finance committee". The draft is shown only after it passes the same checks a release would run:
  - the condition is valid for the object;
  - the name is valid and new;
  - the priority is free;
  - the approval process is active;
  - the matrix still works with the draft in it.

  The administrator receives the rule's file, ready to release, and an explanation of where it sits
  in the priority order. A draft routes nothing until the administrator releases it;
- **check a change's impact:** how a new rule, a new version of a rule, or the removal of a rule
  would change the decisions on the requests of the last 90 days, worked out by the matrix itself;
- **report the matrix's health:**
  - decisions by outcome against the previous period;
  - each rule's share, and the catch-all's share;
  - rules that routed nothing;
  - the commonest failure reasons;
  - the oldest pending approvals.

### 6.9 Claude connector

People who use Claude (claude.ai, Claude Desktop, the Claude mobile apps or Claude Code) can work
with the matrix from there, through two Salesforce-hosted connectors:

- **Approval Matrix**, for everyone: find, preview, what-if, submit after confirmation, the facts
  behind a decision or a briefing, my requests, my approvals;
- **Approval Matrix Admin**, for administrators: the matrix's context for drafting, release checks
  on a drafted rule, a change's impact, and the health facts.

Claude signs in as the user and sees only what they can. Salesforce supplies the facts and runs every
check; Claude writes the words. A submission through Claude also needs a preview of the same record,
by the same user, within the last 15 minutes, and it is refused if the route has changed since. The
[Claude connector guide](claude-connector.md) covers setup and use.

### 6.10 Automation and integration

- **Flow action**, *Submit for Matrix Approval*: per-record results, for use in any flow.
- **REST API**: up to 200 records per call, with per-record results.
- **A configuration check as a Flow action**, *Validate Approval Matrix Configuration*, for an
  administrator's post-release flow.

### 6.11 Release checks

Every release of the matrix passes two checks, and either one stops it:

1. **Before deployment**, a check of the configuration files:
   - every approval process a rule names exists, is active, and accepts a record only when Matrix
     Submission is ticked;
   - every governed approval process unticks Matrix Submission on approval, rejection and recall;
   - no released approval process has been edited in place (section 6.12);
   - no approval process names a user in a way that ties it to a single org;
   - no governed object's layout shows the standard Submit for Approval button.
2. **After deployment**, a validation in the org:
   - every active rule's condition is valid;
   - no two active rules on an object share a priority;
   - every governed object has Matrix Submission;
   - every approval process a rule names is active for that object;
   - the database query the matrix will run for each object is accepted.

All problems are reported together, each with a code and a message an administrator can act on.

### 6.12 Approval-process versioning

- Once an approval process has been released, it is never edited in place.
- A change is made as a new version (for example `PR_Three_Level_Finance_v2`). The rules are
  repointed to it, and the old version is deactivated but kept, so that approvals already under way
  finish as they started and history stays accurate.
- The release checks enforce this. They fingerprint every released approval process, refuse any edit
  other than deactivation, and refuse a superseded version that is still active or still named by a
  rule.

### 6.13 Governing more objects

A new kind of record can be governed by configuration alone, with no change to the framework's
logic. It needs:

- the Matrix Submission checkbox;
- approval processes that follow the guard rules;
- the framework's Submit for Approval action in place of the standard button;
- rules;
- a link from the decision log for its related list;
- a record page with the Approval Timeline.

Opportunity was added this way.

---

## 7. Business rules

### Routing

| # | Rule |
|---|---|
| BR-01 | An object is governed when it has at least one active rule. A record of an object that is not governed cannot be submitted through the framework |
| BR-02 | Active rules are tried in ascending priority. Should two ever share a priority, they are tried in order of rule name, so the order is always the same |
| BR-03 | No two active rules on the same object may share a priority. The release checks refuse it |
| BR-04 | The first rule whose condition is definitely true decides the route. No later rule is considered |
| BR-05 | When no rule matches, the submission is blocked and recorded. There is no hidden default route; a default route is a catch-all rule in the matrix |
| BR-06 | A rule that cannot be evaluated for a record makes that attempt *Failed*. It never passes the record on to the next rule |
| BR-07 | A rule that is not valid at all stops every submission for its object until it is fixed. The release checks keep such a rule out of the live matrix |
| BR-08 | Text and picklist comparisons ignore upper and lower case |
| BR-09 | A blank field equals `NULL`. It is never greater or less than anything, never in a list, and never contains anything |
| BR-10 | When a related record is missing (for example, an Opportunity with no Account), a condition on that related record's fields is *unknown*, and an unknown condition never matches: not even "is blank", and not when negated with NOT |
| BR-11 | `TODAY` in a condition is the submitting user's local date, fixed once per submission. The date used is recorded in the decision log entry |
| BR-12 | Every approval process a rule names must be an active approval process for the rule's object. The release checks refuse anything else |

### Submission

| # | Rule |
|---|---|
| BR-13 | The submitting user must be able to read the record |
| BR-14 | A record that is already in an approval process cannot be submitted again until that approval is approved, rejected or recalled. The message names the process, and nothing is recorded |
| BR-15 | Only the framework ticks Matrix Submission. It is read-only for submitters |
| BR-16 | Every governed approval process accepts a record only when Matrix Submission is ticked, so a submission that bypasses the matrix fails |
| BR-17 | Every way out of a governed approval process (final approval, final rejection and recall) unticks Matrix Submission |
| BR-18 | The standard Submit for Approval button is removed from every governed object's layouts. The framework's Submit for Approval action replaces it |
| BR-19 | A preview writes nothing and submits nothing. The route is decided again at submission, and if it differs from the preview, the user is told |
| BR-20 | In a bulk submission, every record is answered by itself; one record's problem does not stop the others. A record listed twice is submitted once, and both requests receive the same answer |
| BR-21 | A REST call submits at most 200 records |

### Audit

| # | Rule |
|---|---|
| BR-22 | Every attempt the matrix decided writes exactly one decision log entry: *Submitted*, *Blocked* or *Failed*. A *Refused* attempt writes none, because nothing was decided |
| BR-23 | Decision log entries cannot be edited, except by holders of the *AMF Bypass Log Lock* permission, and are never deleted |
| BR-24 | An entry records the rule's name and version, the condition as evaluated, the values read, the process chosen, the outcome and reason, the submitter and the time. Later changes to the rule do not change it |
| BR-25 | Submitters can read their own entries, and administrators can read all of them. The approver a pending approval is waiting on can read that approval's entry, for as long as it waits |
| BR-26 | Anyone who can read a record can see its approval history on the Approval Timeline |

### Configuration

| # | Rule |
|---|---|
| BR-27 | A rule change is released as configuration through the release checks |
| BR-28 | A changed rule takes a new version number |
| BR-29 | A released approval process is never edited in place. A change is a new version; the rules are repointed and the old version is deactivated, never deleted |
| BR-30 | Approval processes name individual approvers through a placeholder that the deployment fills in for each org, so the same configuration deploys anywhere |

### AI assistance

| # | Rule |
|---|---|
| BR-31 | AI never chooses a route, evaluates a rule, writes a rule or a decision log entry, approves anything, or recommends an approval decision |
| BR-32 | AI-generated text is labelled, generated on demand and never stored |
| BR-33 | The Agentforce assistant submits only the record it has just previewed, and only after the user confirms |
| BR-34 | Through Claude, a submission needs a preview of the same record and approval process by the same user within 15 minutes, and is refused if the route has changed since |
| BR-35 | A drafted rule is shown only if it passes the release checks, and it routes nothing until an administrator releases it |
| BR-36 | Every AI feature acts with the signed-in user's own access, and nothing more |

---

## 8. The configured matrix

This is the configuration shipped in the framework's source for this build.

### 8.1 Purchase Request

**Fields:**

| Field | Type | Values | Read by a rule today? |
|---|---|---|---|
| Purchase Request Number | Auto-number, `PR-00000001` onwards | | No |
| Request Name | Text, 80 characters | A short name for the request | No |
| Amount | Currency | | Yes |
| Region | Picklist | APAC, EMEA, AMER | Yes |
| Risk Level | Picklist | Low, Medium, High | Yes |
| Vendor Type | Picklist | New, Existing, Strategic | No |
| Account | Lookup to Account | | No |
| Matrix Submission | Checkbox | Set by the framework only | No: it is the guard |

**Rules:**

| Priority | Rule | Condition | In words | Approval process |
|---|---|---|---|---|
| 5 | `PR_Committee_Spend` | `Amount__c >= 1000000` | Spend of a million or more | `PR_Finance_Committee` |
| 10 | `PR_High_Value_APAC` | `Amount__c > 100000 && Region__c == 'APAC'` | Over 100,000 in APAC | `PR_Three_Level_Finance` |
| 20 | `PR_High_Risk` | `Risk_Level__c == 'High'` | Any high-risk request | `PR_Three_Level_Finance` |
| 30 | `PR_Credit_Risk_Review` | `Risk_Level__c == 'Medium' && Amount__c >= 50000` | Medium risk, 50,000 or more | `PR_Credit_Risk_Queue` |
| 9999 | `PR_Catch_All` | `TRUE` | Everything else | `PR_Two_Level_Mgmt` |

A sixth rule, `PR_Long_Expression_Pin`, is shipped *inactive*. It is a technical test fixture and
routes nothing.

**Scenarios:**

| Amount | Region | Risk | Deciding rule | Approval process | Why |
|---|---|---|---|---|---|
| 1,200,000 | AMER | Low | `PR_Committee_Spend` | `PR_Finance_Committee` | A million or more |
| 1,500,000 | APAC | High | `PR_Committee_Spend` | `PR_Finance_Committee` | Priority 5 is tried before 10 and 20 |
| 150,000 | APAC | Low | `PR_High_Value_APAC` | `PR_Three_Level_Finance` | Over 100,000 in APAC |
| 200,000 | APAC | Medium | `PR_High_Value_APAC` | `PR_Three_Level_Finance` | Priority 10 is tried before the medium-risk rule at 30 |
| 100,000 | APAC | Low | `PR_Catch_All` | `PR_Two_Level_Mgmt` | Exactly 100,000 is not *over* 100,000 |
| 20,000 | EMEA | High | `PR_High_Risk` | `PR_Three_Level_Finance` | High risk, whatever the amount |
| 60,000 | AMER | Medium | `PR_Credit_Risk_Review` | `PR_Credit_Risk_Queue` | Medium risk and 50,000 or more |
| 40,000 | AMER | Medium | `PR_Catch_All` | `PR_Two_Level_Mgmt` | Medium risk, but under 50,000 |
| 5,000 | EMEA | Low | `PR_Catch_All` | `PR_Two_Level_Mgmt` | No earlier rule applies |
| (blank) | APAC | (blank) | `PR_Catch_All` | `PR_Two_Level_Mgmt` | Blank values satisfy no comparison |

### 8.2 Opportunity

Opportunity's own fields are untouched. The framework adds only Matrix Submission.

| Priority | Rule | Condition | In words | Approval process |
|---|---|---|---|---|
| 10 | `OPP_Large_Deal` | `Amount >= 250000` | A deal of 250,000 or more | `OPP_Two_Level_Mgmt` |
| 20 | `OPP_Key_Industry` | `Account.Industry IN ('Energy', 'Banking')` | The account's industry is Energy or Banking | `OPP_Two_Level_Mgmt` |
| 9999 | `OPP_Catch_All` | `TRUE` | Every other deal | `OPP_Manager_Approval` |

| Amount | Account's industry | Deciding rule | Approval process |
|---|---|---|---|
| 300,000 | Technology | `OPP_Large_Deal` | `OPP_Two_Level_Mgmt` |
| 50,000 | Banking | `OPP_Key_Industry` | `OPP_Two_Level_Mgmt` |
| 50,000 | Retail | `OPP_Catch_All` | `OPP_Manager_Approval` |
| 50,000 | (no account) | `OPP_Catch_All` | `OPP_Manager_Approval`: with no account, the industry test is unknown, so it does not match |

### 8.3 Approval processes

| Approval process | Object | Steps and approvers | After final approval |
|---|---|---|---|
| `PR_Two_Level_Mgmt` | Purchase Request | 1. **Manager:** the submitter's manager. 2. **Manager's Manager:** that manager's manager | Locked |
| `PR_Three_Level_Finance` | Purchase Request | 1. **Finance Analyst**, 2. **Finance Controller**, 3. **Finance Director**: three named people, in turn | Locked |
| `PR_Credit_Risk_Queue` | Purchase Request | 1. **Credit Risk Review:** the Credit Risk queue. The first member to act decides, including members who belong through a group | Locked |
| `PR_Finance_Committee` | Purchase Request | 1. **Finance Committee:** three named members, *all* of whom must approve; one rejection ends the request. 2. **Finance Leadership:** either of two leaders; the first to respond decides | Locked |
| `OPP_Two_Level_Mgmt` | Opportunity | 1. **Manager**, 2. **Manager's Manager**, up the submitter's management chain | Unlocked: an approved deal stays editable |
| `OPP_Manager_Approval` | Opportunity | 1. **Manager:** the submitter's manager | Unlocked |

**Common to all six:**
- they accept a record only when Matrix Submission is ticked;
- the submitter can recall a pending request;
- only administrators can edit the record while it is pending;
- a rejection at any step rejects the request, and the record is unlocked afterwards;
- final approval, final rejection and recall all untick Matrix Submission.

In the development org, the named approvers are five seeded test users with a management chain. In
another org, the deployment fills in that org's own users.

---

## 9. Audit, compliance and controls

### 9.1 The evidence for any approval

Every approval has two halves of evidence, kept together:

- **Why**: the decision log entry. Which rule decided, its version, its condition as it was, the
  values it read, the process it chose, and who submitted and when.
- **Who and when**: Salesforce's native approval history. Each step, each approver's decision, their
  comments, and who it is waiting on.

The decision log entry records which approval it started, so the two always join. The Approval
Timeline shows them side by side.

### 9.2 History is never rewritten

The framework replaced a design whose flaw was that re-evaluating a record overwrote its routing
record, destroying the history. Here:

- every attempt writes a new entry, and an entry is never updated afterwards;
- an entry snapshots the rule's condition and process, so a later change to the rule cannot change
  what the entry says;
- the timeline explains every decision from its entry alone, never from today's rules;
- when a record is resubmitted, its earlier entries stay, so the record's whole approval story
  remains.

To answer "why did request X go to process Y?", open the record, find the attempt on its Approval
Timeline, and read the rule, its condition and the values it read. Alternatively, open the decision
log entry itself.

### 9.3 Who can see what

| Who | Approval history (who and when) | Decision log entry (why) |
|---|---|---|
| Anyone who can read the record | Yes | Only their own submissions' entries |
| The approver a pending approval is waiting on (directly, through a queue or group, or as delegated approver) | Yes | That approval's entry, for as long as it waits |
| Matrix administrators | Yes | All entries |

When the viewer cannot see an approval's entry, the timeline still shows the approval and labels it
as unexplained to them, rather than hiding it or guessing. The same visibility applies to every
explanation, briefing and assistant answer, because they are all built from the timeline's view.

### 9.4 Controls

| Risk | Control | Kind |
|---|---|---|
| A broken rule misroutes requests | The validation at release; at run time, the attempt fails and is recorded instead of being passed to another rule | Preventive and detective |
| Submissions bypass the matrix | Matrix Submission; the approval processes' entry rule; the standard button removed; each checked at release | Preventive |
| Two rules compete for the same place in the order | Unique priorities, checked at release | Preventive |
| A rule routes to a process that does not exist or is inactive | Checked at release | Preventive |
| Someone edits or deletes audit records | Entries locked by a validation rule; deletion not granted to anyone | Preventive |
| No one can explain a past routing | One decision log entry per attempt, with snapshots | Detective |
| An approval process is changed silently | Released approval processes fingerprinted; any edit other than deactivation fails the release | Preventive |
| AI makes or influences a decision | Principle 6; every route and figure comes from Salesforce logic, not the model; confirmation before any submission; a signed preview for Claude | Preventive |
| People see records they should not | Every read runs with the user's own access; the one exception is the current approver's view of the entry for their own pending approval | Preventive |

### 9.5 Retention

- The framework never deletes decision log entries, and no permission set allows deleting them.
- If a governed record or a user is deleted, the entry keeps the record's Id and loses only its link.

### 9.6 Gaps an auditor should know about

- The decision log records who submitted, not *how*: it does not distinguish the button, a flow, the
  REST API, the Agentforce assistant or Claude.
- A rule's description is not recorded in the entry. The timeline names a rule by its technical name
  and version, not by its current description, so that a later edit cannot rewrite the explanation.
- Administrators hold the permission that allows editing an entry, so that a genuine error can be
  corrected. Grant the administrator permission set with that in mind.

---

## 10. AI assistance and its limits

### 10.1 What is available, and where

| Capability | Record page | Approval Matrix Assistant | Admin Assistant | Claude connector |
|---|---|---|---|---|
| Explain a recorded decision | Explain in plain English | Yes | | Yes |
| Preview a route | Submit for Approval (its preview) | Yes | | Yes |
| What-if | | Yes | | Yes |
| Submit | Submit for Approval | Yes, after confirmation | | Yes, after confirmation and a fresh preview |
| My requests | | Yes | | Yes |
| What is waiting for my approval | | Yes | | Yes |
| Briefing for the current approver | | Yes | | Yes |
| Draft a rule | | | Yes | Yes, admin connector |
| Impact of a change | | | Yes | Yes, admin connector |
| Matrix health | | | Yes | Yes, admin connector |

### 10.2 The boundary

| AI may | AI may not |
|---|---|
| Explain a decision already recorded | Choose a route or evaluate a rule |
| Brief the approver an approval is waiting on | Recommend approving or rejecting |
| Answer a what-if, by asking the matrix | Change a record, a rule or an approval process |
| Submit a record the user has just previewed and confirmed | Submit anything the user has not seen and confirmed |
| Draft a rule for an administrator to review and release | Release, activate or deactivate a rule |
| Summarise counts that Salesforce has calculated | Invent figures, rules, approvers or reasons |

### 10.3 How this is achieved

- **Every fact comes from Salesforce logic.** Routes, rules, values, approvers and counts are worked
  out by the framework. The AI is given those facts and puts them into words.
- **Sensitive steps are fixed in logic, not left to the model.** The assistant can submit only the
  record it previewed, with the process that preview found, and only after the user confirms.
  Through Claude, a signed preview token adds the same guarantee.
- **Generated text is presentation.** It is labelled, generated when asked, and never stored. The
  decision log remains the only record of why.
- **Everything runs as the user.** The AI sees only what the user could open themselves.
- **Data handling.** Einstein features pass through Salesforce's Einstein Trust Layer, like any prompt
  in the org. Through the Claude connector, Claude receives the same facts and writes the answer;
  nothing generated is stored in Salesforce.

---

## 11. Access and licences

| Person | Permission sets | Salesforce licences |
|---|---|---|
| Submitter or approver, core use | *Approval Matrix User* | A licence that includes the object. For Opportunity that is a full Salesforce licence: a Salesforce Platform licence grants no access to Opportunities |
| + plain-English explanations | + *Prompt Template User* | + Einstein Prompt Templates |
| + Approval Matrix Assistant | + *Access Agentforce Default Agent* and *Approval Matrix Assistant Access* | + Agentforce |
| + Claude | + *Approval Matrix Claude Connector User* | None extra; the user's profile needs API access |
| Matrix administrator | *Approval Matrix Admin*, plus the same extras as needed, plus *Approval Matrix Admin Assistant Access* and *Approval Matrix Claude Connector Admin* | As above |

**Approvers also need read access to the records they approve,** through the role hierarchy, sharing
rules or another sharing mechanism. Salesforce does not share a record with an approver
automatically, and it does not check access or licence when it assigns an approval. The framework
deliberately leaves the organisation's sharing model as it is.

---

## 12. Quality characteristics

| Characteristic | How the framework meets it |
|---|---|
| **Performance and volume** | All fields the rules need are read in one query per object. Rules are prepared once per transaction, however many records are submitted. Submissions go to Salesforce in batches of 100. A REST call takes up to 200 records |
| **Reliability** | Records are isolated from each other in bulk submissions. If the submission machinery itself fails, everything in the call is rolled back, so no record enters an approval without its decision log entry |
| **Security** | Every read and action runs with the user's access. The framework checks read access itself before it decides anything (section 9.3) |
| **Auditability** | One permanent entry per decided attempt, joined to native approval history (section 9) |
| **Maintainability** | The policy is configuration. Release checks catch mistakes before they go live, and approval processes are versioned |
| **Portability** | The framework package deploys to any Salesforce org. Org-specific settings are kept separately, and approver usernames are filled in at deployment |
| **Testability** | At the last release: 451 automated Apex tests (97% code coverage), 75 user-interface component tests, two Agentforce test suites (20 test cases), and a scripted UI test suite run by an AI browser agent |
| **Usability and accessibility** | Standard Salesforce Lightning design; screen-reader labels; explanations announced to screen readers as they arrive; times shown in the user's time zone and numbers in their locale |
| **Localisation** | Screen text is English only today. Numbers, dates and times follow the user's locale and time zone |

---

## 13. Assumptions, constraints and limitations

**Platform scope:**
- Only standard (Classic) Salesforce approval processes are supported. Salesforce's newer Flow-based
  approval orchestrations are not.
- The AI features need Einstein generative AI and Agentforce turned on, and the matching licences.
- The Claude connector needs Salesforce Hosted MCP Servers: Enterprise Edition and above, or
  Developer Edition.

**Rules:**
- Conditions cannot use date-and-time fields, long text or text-area fields, or email, phone and URL
  fields.
- Two multi-select picklist fields cannot be compared with each other.
- Picklist values in conditions are not checked against the field's list. A misspelt value is not
  an error; the rule simply never matches.

**Approvers and submitters:**
- Approvers need read access to the record and a licence that includes the object. Salesforce does
  not check either when it assigns an approval.
- A submitter routed to a manager-approval process needs a manager. Without one, the attempt fails
  with "MANAGER_NOT_DEFINED".

**Behaviour:**
- A record that a validation rule would refuse still previews as routable. The problem appears at
  submission, as a *Failed* attempt with the reason.
- The framework does not recall, approve, reject or reassign. Native Salesforce approval actions do.

**Screens:**
- The Approval Timeline is on the desktop record page only; phones show the standard page.
- Screen text is not yet translatable.

**Records and access:**
- The decision log does not record which entry point made an attempt (section 9.6).
- In a new org, removing the standard Submit for Approval button from a governed *standard* object's
  layouts is that org's administrator's task, because those layouts belong to the org.
- To use briefings and "my approvals" in Agentforce, each approver needs an Agentforce licence. The
  Claude connector needs none.

**Open decisions in the development org:**
- Einstein Trust Layer's prompt-injection and toxicity detection are switched off. Approver comments,
  administrators' descriptions and rule descriptions can reach the AI model.
- Who else receives access to the assistants and the Claude connector.

---

## 14. Glossary

| Term | Meaning |
|---|---|
| **ADL** | The prefix of decision log numbers (Approval Decision Log), such as ADL-00000027 |
| **Agentforce** | Salesforce's AI assistant platform, which hosts the two Approval Matrix assistants |
| **Approval history** | Salesforce's native record of an approval: each step, decision, approver and comment |
| **Approval process** | A native Salesforce approval process with steps and approvers. The matrix selects one per submission |
| **Catch-all** | A rule whose condition is `TRUE`, placed last, that routes whatever no earlier rule caught |
| **Claude connector** | The integration that lets Claude work with the matrix through Salesforce-hosted MCP servers |
| **Committee step** | An approval step with several named approvers who must all approve |
| **Condition** | The formula in a rule that decides whether it applies to a record |
| **Decision log** | The permanent record of every attempt the matrix decided |
| **Delegated approver** | A person a user has nominated in Salesforce to approve on their behalf |
| **Entry criteria** | The condition an approval process requires before it accepts a record. For every governed process: Matrix Submission is ticked |
| **First match** | The rule that the first true condition in priority order decides the route |
| **Governed object** | An object with at least one active rule |
| **Guard** | The Matrix Submission checkbox, and the rules around it that make the matrix the only way in |
| **Kill switch** | Deactivating all of an object's rules, which stops all of its submissions |
| **MCP** | Model Context Protocol: the standard Claude uses to connect to tools such as Salesforce |
| **Preview** | Seeing where a record would go, and why, without submitting it |
| **Priority** | The number that sets a rule's place in the order; lower is tried first |
| **Queue step** | An approval step assigned to a queue, where the first member to act decides |
| **Release checks** | The checks before and after deployment that a matrix change must pass |
| **Release manifest** | The list of released approval processes with their fingerprints, used to refuse in-place edits |
| **Rule** | One row of the matrix: object, priority, condition, approval process, description, version, active |
| **Shape** | An approval process's structure of steps and approvers |
| **Template** | Another name for an approval process the matrix can select |
| **Timeline** | The Approval Timeline panel on a governed record's page |
| **Version** | A rule's change number, recorded in every decision it makes |
| **What-if** | A preview with some field values changed in memory only, to see whether the route would change |

---

## Appendix A: Outcomes at a glance

| Outcome | Shown on the record page as | Entered an approval process? | Decision log entry | Matrix Submission afterwards |
|---|---|---|---|---|
| **Submitted** | "Submitted for approval", and a timeline entry "Routed to …" | Yes | Yes: rule, version, condition, values, process, and the approval it started | Ticked, until the approval ends |
| **Blocked** | "Not submitted", and a timeline entry "Not submitted: no rule matched" | No | Yes: "Blocked - No Match", with every value read across all rules | Unticked |
| **Failed** | "Not submitted", and a timeline entry "Not submitted: the attempt failed" | No | Yes: the rule and process if one was chosen, and the reason | Unticked. If the framework had already ticked it, it unticks it again at once |
| **Refused** | "Could not submit for approval" | No | No: nothing was decided | Unchanged |

Every way of submitting can produce each outcome. A *Refused* record ends the whole attempt when it
comes from the Submit for Approval button. From a flow, the REST API or an assistant, it is that one
record's result, and the other records go ahead.

---

## Appendix B: Release history

| Phase | Completed | What it added for the business |
|---|---|---|
| M0 to M3 | August to September 2026 | The core: the rules, the decision log, the condition language, the engine, two approval processes and the Submit for Approval action. The founding promise demonstrated on 18 September 2026 |
| M4 | September 2026 | Release checks for the matrix's configuration |
| M5 | 25 September 2026 | The preview and confirmation window |
| M6 | 7 October 2026 | Research into Salesforce Flow approvals. No change to the product |
| M7 | 8 October 2026 | The Approval Timeline |
| M8 | 8 October 2026 | Recall closes the guard; a record already in approval is refused by name |
| M9 | 8 October 2026 | The full condition language: NOT, lists, text tests, multi-select picklists, relative dates, deeper relationships |
| M10 | 21 October 2026 | The Flow action and REST API, with bulk submission and per-record results |
| M11 | 21 October 2026 | Opportunity governed by configuration alone |
| M12 | 22 to 23 October 2026 | Versioned approval processes; queue and committee approval processes; deployment to any org; the Request Name field and list views |
| M13 | 23 October 2026 | The Approval Matrix Assistant and plain-English explanations |
| M14 | 23 October 2026 | What-ifs, "my requests", "my approvals", approver briefings; the current approver can see why |
| M15 | 23 October 2026 | The Admin Assistant: rule drafting, impact checks and health reports |
| M16 | 24 October 2026 | The Claude connector |
