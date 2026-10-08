# Approval Matrix Framework — MVP

Salesforce DX. The matrix selects WHICH native approval process a record enters.
Custom Metadata rules → expression evaluator → priority match → submit by process
name → decision log explains why.

## Source of truth
docs/architecture.md (v3.0) defines the full target design; its §13 is this MVP scope.
WE ARE BUILDING THE MVP SUBSET ONLY (see MVP SCOPE). If the doc describes something
not in MVP scope, do NOT build it. If a task seems to conflict with the doc, STOP and
ask. docs/build-playbook.md carries the phase plan (M0–M8) and the gate for each.

**Current authorised post-MVP work:** M0–M3 have passed their gates. M4 added the
configuration validator in architecture §9, its source-metadata companion gate, and the
post-deploy script. M5 adds the §6.4 preview and the submit action's confirmation modal
(§7's UI row: headless action → preview → confirm → submit). These explicitly supersede
the MVP-only restriction for the config validator and the preview modal alone; all other
items in the out-of-scope list remain deferred. M6 is a Flow approvals technical spike:
research only, artefacts under spikes/flow-approvals/ and never in force-app. It authorises
no product build — the Flow strategy, Execution_Type__c and Flow templates stay out of scope.
Its findings (docs/spike-results.md, Round 2) bind any future Flow phase, including: keep
engine Apex classes at API ≤ 66, because API 67 runs database operations in user mode.
M7 adds the §8 decision timeline LWC: a read-only view on the governed record that joins
each decision log row to its native Classic approval history (ProcessInstance and its
steps), plus the record page that hosts it. It supersedes the MVP-only restriction for the
timeline LWC alone; it is Classic-only, like the validator, and changes no engine behaviour.
M8 closes two gaps in the guard. Both Classic templates clear Matrix_Submission__c on recall as
well as on final approval and rejection, and the source gate enforces it. The engine also refuses a
record that is already in an approval process, in preview and submit, without writing a log row.
It supersedes "recall handling" on the out-of-scope list for the templates' recall actions alone;
recall from the framework itself (an action, an API, Flow recall) stays out of scope.

## MVP SCOPE — build ONLY these
- One object: Purchase_Request__c (Amount__c, Region__c, Risk_Level__c)
- One CMDT: Approval_Matrix_Rule__mdt (§3.1)
- One custom object: Approval_Decision_Log__c
- One guard checkbox: Matrix_Submission__c
- Expression evaluator, REDUCED GRAMMAR (see below)
- Engine: priority-ordered first match, log write, submit
- ClassicProcessStrategy only
- Two Classic approval processes
- Submit quick action, no preview modal

## EXPLICITLY OUT OF MVP — do not build, do not stub, do not mention
Flow strategy / Execution_Type__c / FlowApprovalStrategy · queue or committee
templates · preview modal · timeline LWC · config validator · bulk chunking ·
recall handling · second object · _v2 template cloning · TemplateRegistry ·
ApproverResolver · chain objects

## MVP GRAMMAR — reduced
Supported: && || ( ) == != > >= < <= ; field paths up to 2 hops (Account__r.Region__c);
types Number/Currency, String, Picklist, Boolean, Date; literals NUMBER, 'STRING',
TRUE, FALSE, NULL, YYYY-MM-DD; bare TRUE as a complete expression (catch-all rules).
NOT supported yet: IN, NOT IN, CONTAINS, STARTS_WITH, NOT/!, TODAY(±n), multipicklist,
3+ hop paths. Structure the lexer/parser/AST so these are additive later — do not
special-case around their absence.

## Non-negotiable conventions
- CMDT access ONLY via RuleProvider interface. Engine classes never query __mdt.
- CRITICAL: CmdtRuleProvider must use SOQL, never getAll()/getInstance().
  Those truncate Long Text Area fields to 255 chars and would silently corrupt
  Expression__c. CMDT SOQL is governor-free. Pin this with a test.
- All Approval.process() calls ONLY via SubmissionStrategy interface.
- Tests use in-memory rule fixtures — zero dependence on org CMDT rows.
- Evaluation errors FAIL LOUDLY (block + log). Never catch-and-return-false.
- Naming: AMF_ on Apex classes, amf on LWC. ApexDoc header cites its § section.

## Environment
- Org alias: amf-dev. Deploy: sf project deploy start -o amf-dev
- Tests: sf apex run test -o amf-dev -l RunLocalTests -w 10 -r human
- API 62.0. LWC only.

## Scope discipline
Only touch files the current phase allows. Never refactor previous phases.
Never create metadata the current phase doesn't require.
