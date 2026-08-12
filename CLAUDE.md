# Approval Matrix Framework

Salesforce DX project. Hybrid approval routing framework: Custom Metadata rules,
Apex evaluation engine, chained single-step native Approval Processes.

## Source of truth
docs/architecture.md defines ALL schema, class responsibilities, and patterns.
Section references (§) in tasks point there. If a task seems to conflict with the
doc, or the doc is ambiguous, STOP and ask — never guess, never redesign.
Approved deviations get one line in docs/decisions.md.

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
