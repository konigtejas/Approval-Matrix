# Approval Matrix Framework

Salesforce DX project. Hybrid approval routing framework: Custom Metadata rules,
Apex evaluation engine, chained single-step native Approval Processes.

## Source of truth
docs/architecture.md defines ALL schema, class responsibilities, and patterns.
Section references (§) in tasks point there. If a task seems to conflict with the
doc, or the doc is ambiguous, STOP and ask — never guess, never redesign.
Approved deviations get one line in docs/decisions.md.

## Change logging (every phase, no exceptions)
Each phase is built in a fresh chat session, so there is no conversation history to
rely on. START HERE: docs/technical-log.md — its phase status board says where the
build is, and the most recent entry's "Carried into later phases" table says what
that phase owes you. Then read the phase prompt in docs/build-playbook.md.

docs/technical-log.md is the running technical record. Append a full entry at the
end of every phase — before the phase commit — and after any out-of-phase fix.
Update the phase status board in the same edit.

## Finishing a phase
When a phase's acceptance gates are green: write the log entry, update the status
board, then COMMIT AND PUSH to the working branch without being asked. One commit
per phase, message `Phase N: <name>`. Do not leave a completed phase uncommitted —
the next phase starts in a fresh session and inherits the repo, not the chat.
An entry covers: file-level change list, reasoning behind non-obvious choices,
every failure hit and how it was resolved, verification evidence (real command
output, never "should work"), and debt carried into later phases. Read it at the
start of a phase: it carries the state that /clear throws away.

## Environment
- Org alias: amf-dev (Developer Edition). Deploy: sf project deploy start -o amf-dev
- Run tests: sf apex run test -o amf-dev -l RunLocalTests -w 10 -r human
- Apex API version 62.0. LWC only (no Aura).

## Non-negotiable conventions
- All CMDT access via RuleProvider interface (§4.4). Engine classes NEVER query __mdt directly.
- All Approval.process()/unlock() calls via SubmissionStrategy (§11). Never inline.
- Unit tests use RuleBuilder + stub providers — zero dependence on org CMDT rows.
- Bulk-safe everywhere: List<Id> inputs, no SOQL/DML in loops.
- Every class: ApexDoc header stating its §section in the architecture doc.
- Naming: AMF_ prefix on all Apex classes; amf prefix on LWC.

## Scope discipline
Only touch files the current task allows. Do not refactor previous phases.
Do not create metadata the current phase doesn't require.
