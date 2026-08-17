# Approval Matrix Framework — MVP

Salesforce DX. The matrix selects WHICH native approval process a record enters.
Custom Metadata rules → expression evaluator → priority match → submit by process
name → decision log explains why.

## Source of truth
docs/architecture.md (v3.0) defines the full target design; its §13 is this MVP scope.
WE ARE BUILDING THE MVP SUBSET ONLY (see MVP SCOPE). If the doc describes something
not in MVP scope, do NOT build it. If a task seems to conflict with the doc, STOP and
ask. docs/build-playbook.md carries the phase plan (M0–M3) and the gate for each.

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