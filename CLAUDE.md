# Approval Matrix Framework — MVP

Salesforce DX. The matrix selects WHICH native approval process a record enters.
Custom Metadata rules → expression evaluator → priority match → submit by process
name → decision log explains why.

## Source of truth
docs/architecture.md (v3.0) defines the full target design; its §13 is this MVP scope.
WE ARE BUILDING THE MVP SUBSET ONLY (see MVP SCOPE). If the doc describes something
not in MVP scope, do NOT build it. If a task seems to conflict with the doc, STOP and
ask. docs/build-playbook.md carries the phase plan (M0–M11) and the gate for each. Its Part 5
is a PROPOSED roadmap only: a phase there is not authorised until the paragraph below names it.

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
M9 builds the full §4.1 grammar, superseding the MVP GRAMMAR section below: every construct it
lists as not supported yet, plus the word forms AND / OR / NOT. It is confined to the evaluator
package and changes no object, field, engine class or LWC. DateTime fields and literals stay out.
M10 adds §7's remaining entry points: the AMF_SubmitForMatrixApproval invocable action and a REST
resource, both over a new per-record engine entry, submitEach(). There a record that cannot be
submitted (unreadable, already pending, refused by the platform, or of an object the matrix cannot
govern) gets its own outcome while the rest still go through. The engine now writes the decision
log after the platform answers, and the Classic strategy submits in chunks of at most 100 without
all-or-nothing. It supersedes "bulk chunking" on the out-of-scope list. The header button keeps
its whole-call contract.
M11 governs a second object, Opportunity, by configuration and conventions alone (§3.2): its
Matrix_Submission__c guard; two Classic templates on the submitter's manager hierarchy that clear
the guard on approval, rejection and recall; the framework's submit action in place of the
standard button on all four of its layouts; its matrix rules; an Opportunity__c lookup on the
decision log; field-level access in both permission sets; and a record page with the timeline.
It supersedes "second object" on the out-of-scope list for Opportunity alone and changes no
engine class or LWC. Two gate checks join it: the source gate fails a governed object's layout
that keeps the standard Submit for Approval button (§6.3), and the validator runs each governed
object's union query, in place of M9.5's 55-relationship count, which the platform does not
enforce (technical log M11).
M12 (authorised 2026-10-22) has three parts and one rider. Template lifecycle (§5.1): the source
gate compares every released template with its fingerprint in config/template-releases.json, and
only its active flag may change. A superseded version must be inactive, and no rule may name one.
Guard checks run on every active template, not only those a rule names. Queue and committee
templates, on Classic: PR_Credit_Risk_Queue (the Q_Credit_Risk queue, any member decides) and
PR_Finance_Committee (amfu1 to amfu3 unanimously, then amfu4 or amfu5), each with one rule.
Portability: templates name users as <alias>@{{AMF_USERNAME_DOMAIN}}, which a sfdx-project.json
replacement fills from that environment variable at deploy, and the gate refuses a literal
username. Opportunity's layouts and object settings are amf-dev's own configuration, so they move
to a second package directory, org-config/amf-dev, and force-app keeps no layout or object settings
of a standard object. The rider: New and Mass Change Owner leave the Approval Decisions related
list on every layout. M12 supersedes "queue or committee templates" and "_v2 template cloning" on
the out-of-scope list and changes no engine class or LWC. The template registry stays out
(§12 item 4), and committee steps on Flow wait for the unanimous value (§12 item 1).

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
**M9 (2026-10-08) built all of the above**, plus AND / OR / NOT, with paths up to four
segments (three hops). Semantics: architecture §4.1 and §4.3, M9 notes. Still unsupported:
DateTime fields and literals.

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
- Org alias: amf-dev. Deploy: sf project deploy start -o amf-dev, which deploys both package
  directories (force-app, org-config/amf-dev). It needs AMF_USERNAME_DOMAIN set first, to
  amf.00daj000012gj9b.dev for amf-dev (PowerShell: $env:AMF_USERNAME_DOMAIN = '...'); without it
  the CLI refuses the deploy. Another org: deploy --source-dir force-app only, with that org's domain.
- Tests: sf apex run test -o amf-dev -l RunLocalTests -w 10 -r human
- API 62.0. LWC only.

## Scope discipline
Only touch files the current phase allows. Never refactor previous phases.
Never create metadata the current phase doesn't require.
