/**
 * The engine. Runs the matrix over a set of records and submits each one to the
 * approval process its highest-priority matching rule names.
 *
 * Architecture section: 6.1 (submission flow, steps 1-11), 6.3 (the guard),
 * 6.4 (preview), 4.6 (fail loudly), 11 (security), 7 (entry points).
 *
 * PREVIEW (6.4, added in M5) is this same path stopped after step 7: it
 * answers "where would this go, and why" with nothing written or submitted,
 * and drives the quick action's confirmation modal.
 *
 * WHAT THIS CLASS EXISTS TO PROVE (13): an admin changes one Custom Metadata
 * row, the next submission routes to a different approval process, and a log
 * record explains why. Nothing here knows a process name, an approver or a
 * threshold -- all three live in Approval_Matrix_Rule__mdt, which is why the
 * change that reroutes an org is a config release rather than a code release.
 *
 * 6.1 IN FULL, and the step numbers below are that list:
 *
 *    1. Load rules via AMF_RuleProvider; none active means not governed
 *    2. Order by Priority__c, then DeveloperName
 *    3. Compile every expression once, via AMF_ExprCache
 *    4. Union of field paths to ONE dynamic SOQL (4.4)
 *    5. Per record, rules in priority order, FIRST true expression wins
 *    6. No match writes a Blocked_No_Match row and blocks
 *    7. Resolve the template from Process_API_Name__c
 *    8. Write the decision log
 *    9. Set Matrix_Submission__c = true, same transaction, BEFORE submit
 *   10. AMF_SubmissionStrategy.submit(...)
 *   11. Stamp Execution_Ref_Id__c back onto the row
 *
 * FAILURE, AND WHY THIS CLASS RETURNS OUTCOMES RATHER THAN THROWING PER RECORD.
 * 6.1 step 6 reads "write a Blocked_No_Match log row, throw a clear error", and
 * in Apex those two instructions fight: an exception that escapes the top of a
 * request rolls back every DML before it, so throwing would erase the row 3.3
 * exists to create. This class therefore blocks per-record faults by RECORDING
 * them -- log row written, Outcome not Submitted, record not submitted, reason
 * in the message -- and reserves exceptions for faults that condemn the whole
 * call: nothing to submit, a record the caller cannot read, an object with no
 * active rules, a rule that will not compile, a submission that failed. That is
 * not 4.6's forbidden catch-and-return-false; the evaluator still never
 * swallows anything, and a blocked record leaves a louder trace than an
 * exception would, because the trace survives the transaction. Recorded in
 * docs/decisions.md, 2026-08-18.
 *
 * A RULE THAT WILL NOT COMPILE STOPS EVERYTHING (4.6). 9's config validator
 * would catch that at deploy time, but 9 is out of MVP scope (13.2), so a
 * compile error surfaces here instead -- as a positioned AMF_ExpressionException
 * that blocks the entire call. It must, and this is the anti-Sitetracker rule
 * at its sharpest: if the priority-10 rule cannot be evaluated, nobody can say
 * that a record would not have matched it, so routing that record to the
 * priority-20 rule is exactly the silent misrouting this framework was built to
 * make impossible.
 *
 * Declared without sharing per 11 -- it is infrastructure, and it writes an
 * audit row and stages a guard field that the submitter has no FLS to write
 * themselves -- but it authorises explicitly: submission requires read access
 * to the record, checked against UserRecordAccess before anything else happens.
 */
public without sharing class AMF_ApprovalMatrixService {

    /**
     * The framework's per-object guard field, a convention rather than
     * configuration (3.2). Every governed object carries it; nothing configures
     * its name.
     */
    @TestVisible
    private static final String GUARD_FIELD = 'Matrix_Submission__c';

    /**
     * One record's answer: what happened, and everything needed to explain it.
     *
     * preview() returns the same shape (6.4). There, outcome is the verdict a
     * submission would record, and nothing has been submitted or written:
     * submitted is false and decisionLogId and executionRefId are null.
     */
    public class Outcome {

        /** The record this outcome is about. */
        @AuraEnabled
        public Id recordId;

        /** True only when the record actually entered an approval process. Never true in a preview. */
        @AuraEnabled
        public Boolean submitted = false;

        /** Outcome__c as written to the log: Submitted, Blocked_No_Match or Failed. */
        @AuraEnabled
        public String outcome;

        /** DeveloperName of the winning rule; null when nothing matched. */
        @AuraEnabled
        public String matchedRule;

        /** Version__c of the winning rule at the moment it matched. */
        @AuraEnabled
        public Integer ruleVersion;

        /** Priority__c of the winning rule: the order 6.1 step 5 tried it in. */
        @AuraEnabled
        public Integer rulePriority;

        /** The winning rule's Description__c -- what a submitter is shown. */
        @AuraEnabled
        public String matchedRuleDescription;

        /** The winning rule's expression, exactly as Expression_Snapshot__c records it. */
        @AuraEnabled
        public String matchedExpression;

        /**
         * The values the decision rested on, as the same JSON Evaluated_Values__c
         * records: the winning rule's values on a match, everything read otherwise.
         * The submitter can already read that field on their own log rows
         * (Approval_Matrix_User), so returning it discloses nothing new.
         */
        @AuraEnabled
        public String evaluatedValuesJson;

        /** The process the matrix selected. */
        @AuraEnabled
        public String selectedProcess;

        /** ProcessInstance Id, once submitted. */
        @AuraEnabled
        public String executionRefId;

        /** The Approval_Decision_Log__c row written for this record. Always set by submit(); null from preview(). */
        @AuraEnabled
        public Id decisionLogId;

        /** Why this record did not route. Null when it did. */
        @AuraEnabled
        public String message;
    }

    private final AMF_RuleProvider ruleProvider;
    private final AMF_SubmissionStrategy strategy;

    /** Production wiring: the SOQL-based CMDT provider and the Classic strategy. */
    public AMF_ApprovalMatrixService() {
        this(new AMF_CmdtRuleProvider(), new AMF_ClassicProcessStrategy());
    }

    /**
     * The seam 10 is built on. Tests inject AMF_RuleBuilder.Stub and
     * AMF_StrategyStub, so no engine test depends on an org CMDT row or runs a
     * real approval.
     *
     * @param ruleProvider Where the matrix comes from.
     * @param strategy     How a submission is started.
     */
    public AMF_ApprovalMatrixService(AMF_RuleProvider ruleProvider, AMF_SubmissionStrategy strategy) {
        this.ruleProvider = ruleProvider;
        this.strategy = strategy;
    }

    /**
     * 7's UI row: the entry point behind the amfSubmitForApproval quick action.
     *
     * Returns the Outcome rather than throwing when a record is blocked -- the
     * LWC renders message as an error toast. An exception escaping an
     * @AuraEnabled method rolls its transaction back, so throwing on a block
     * would destroy the decision log row the submitter is about to be told
     * to go and read.
     *
     * @param recordId The record to submit.
     * @return Its outcome.
     * @throws AuraHandledException On a fault that condemns the whole call, where
     *         rolling back IS the correct answer and there is no row to lose.
     */
    @AuraEnabled
    public static Outcome submitRecord(Id recordId) {
        try {
            return new AMF_ApprovalMatrixService().submit(new List<Id>{ recordId })[0];
        } catch (Exception e) {
            // setMessage as well as the constructor: without it the client sees
            // "Script-thrown exception" instead of the positioned, actionable
            // text 4.2 went to the trouble of producing.
            AuraHandledException handled = new AuraHandledException(e.getMessage());
            handled.setMessage(e.getMessage());
            throw handled;
        }
    }

    /**
     * 7's UI row, first half: the preview that drives the quick action's
     * confirmation modal (6.4). Nothing is written, so a fault here has no row
     * to lose and is thrown, exactly as submitRecord throws its whole-call faults.
     *
     * Deliberately NOT cacheable=true. A cached answer would outlive an edit
     * to the record or the matrix and confirm a route the submission would not
     * take; the preview is only worth showing if it is the answer right now.
     *
     * @param recordId The record about to be submitted.
     * @return The outcome a submission would have, with nothing written.
     * @throws AuraHandledException On a fault that condemns the whole call.
     */
    @AuraEnabled
    public static Outcome previewRecord(Id recordId) {
        try {
            return new AMF_ApprovalMatrixService().preview(new List<Id>{ recordId })[0];
        } catch (Exception e) {
            AuraHandledException handled = new AuraHandledException(e.getMessage());
            handled.setMessage(e.getMessage());
            throw handled;
        }
    }

    /**
     * 6.1, steps 1-11.
     *
     * @param recordIds The governed records to submit. All must be the same
     *                  object: the rule set and the union query are both per
     *                  object, and 6.1 step 1 loads rules for "the object".
     * @return One Outcome per record, in the order supplied.
     * @throws AMF_SubmissionException On a fault condemning the whole call.
     * @throws AMF_ExpressionException If any active rule will not compile.
     */
    public List<Outcome> submit(List<Id> recordIds) {
        return run(recordIds, true);
    }

    /**
     * 6.4: steps 1-7 exactly as submit() runs them, then stop -- no decision
     * log row, no guard, no Approval.process(). Same code path rather than a
     * parallel one, so the answer a submitter confirms cannot drift from the
     * answer the engine then acts on: the authorisation, the rule order, the
     * compiled expressions and the first-match walk are all shared.
     *
     * Whole-call faults throw exactly as they do from submit(), and for the
     * same reasons: a record the caller cannot read, an ungoverned object, a
     * rule that will not compile.
     *
     * @param recordIds The governed records to preview. One object per call, as for submit().
     * @return One Outcome per record, in the order supplied. Nothing is written.
     * @throws AMF_SubmissionException On a fault condemning the whole call.
     * @throws AMF_ExpressionException If any active rule will not compile.
     */
    public List<Outcome> preview(List<Id> recordIds) {
        return run(recordIds, false);
    }

    /**
     * The one engine path behind submit() and preview().
     *
     * @param recordIds      The governed records.
     * @param commitDecision False for 6.4's preview: stop after step 7. 6.4 names
     *                       this flag commit, which Apex reserves.
     * @return One Outcome per record, in the order supplied.
     */
    private List<Outcome> run(List<Id> recordIds, Boolean commitDecision) {
        if (recordIds == null || recordIds.isEmpty()) {
            throw new AMF_SubmissionException('No records were supplied to submit');
        }

        String objectApiName = objectTypeOf(recordIds);
        authorise(recordIds);
        requireGuardField(objectApiName);

        // Step 1. An object with no active rules is not governed (3.2), and
        // deactivating an object's rules is the framework's kill switch -- so
        // this is a deliberate configuration state, reported as such.
        List<AMF_RuleDefinition> provided = ruleProvider.getActiveRules(objectApiName);

        if (provided == null || provided.isEmpty()) {
            throw new AMF_SubmissionException(
                objectApiName +
                ' is not governed by the approval matrix: it has no active ' +
                'Approval_Matrix_Rule__mdt rows. Activate a rule for it, or submit ' +
                'through a path that does not use the matrix.'
            );
        }

        // Step 2. Every AMF_RuleProvider already promises this order, and both
        // implementations deliver it. Sorting a copy anyway costs nothing and
        // makes step 5's determinism a property of the ENGINE rather than of
        // provider discipline -- 3.1 calls the ordering always deterministic,
        // and a future provider should not be able to quietly break that.
        List<AMF_RuleDefinition> rules = new List<AMF_RuleDefinition>(provided);
        rules.sort();

        // Step 3. Once per rule per transaction, keyed on DeveloperName +
        // Version__c. A compile fault throws out of here and stops the call.
        Map<String, AMF_ExprCompiler.CompiledExpression> compiledByRule = new Map<String, AMF_ExprCompiler.CompiledExpression>();
        List<AMF_ExprCompiler.CompiledExpression> compiled = new List<AMF_ExprCompiler.CompiledExpression>();

        for (AMF_RuleDefinition rule : rules) {
            AMF_ExprCompiler.CompiledExpression expression = AMF_ExprCache.get(rule);
            compiledByRule.put(rule.developerName, expression);
            compiled.add(expression);
        }

        // Step 4. ONE query for the union of every path across every rule (4.4).
        // A matrix of catch-alls reads no fields and costs nothing here.
        Map<Id, SObject> recordsById = AMF_FieldPathResolver.load(
            objectApiName,
            AMF_FieldPathResolver.unionPaths(compiled),
            new Set<Id>(recordIds)
        );

        List<Outcome> outcomes = new List<Outcome>();
        List<Approval_Decision_Log__c> rows = new List<Approval_Decision_Log__c>();
        List<Outcome> outcomeByRow = new List<Outcome>();
        List<AMF_SubmitRequest> submitRequests = new List<AMF_SubmitRequest>();
        List<Outcome> outcomeByRequest = new List<Outcome>();
        Set<Id> guardIds = new Set<Id>();

        for (Id recordId : recordIds) {
            Outcome result = new Outcome();
            result.recordId = recordId;
            outcomes.add(result);

            Approval_Decision_Log__c row = match(
                recordId,
                objectApiName,
                rules,
                compiledByRule,
                recordsById,
                result
            );

            rows.add(row);
            outcomeByRow.add(result);

            if (result.outcome == 'Submitted') {
                guardIds.add(recordId);
                submitRequests.add(new AMF_SubmitRequest(recordId, result.selectedProcess));
                outcomeByRequest.add(result);
            }
        }

        // 6.4. A preview ends here, with steps 1-7 run exactly as a submission
        // runs them and nothing written: the rows built above are discarded
        // unsaved, and the guard and the strategy are never reached.
        if (!commitDecision) {
            return outcomes;
        }

        // Step 8. Every record gets a row, whatever happened to it.
        AMF_DecisionLogWriter.save(rows);

        for (Integer i = 0; i < rows.size(); i++) {
            outcomeByRow[i].decisionLogId = rows[i].Id;
        }

        if (submitRequests.isEmpty()) {
            return outcomes;
        }

        // Step 9. Same transaction, before submit. This is the guard (6.3): the
        // engine is the only thing that sets it, the templates require it as
        // entry criteria, and a submission that bypassed the matrix therefore
        // fails entry criteria loudly rather than routing silently.
        stageGuard(objectApiName, guardIds);

        // Step 10. The only route to Approval.process(), through the interface.
        List<AMF_SubmitResult> submitted = strategy.submit(submitRequests);

        Map<Id, String> executionRefByRecordId = new Map<Id, String>();
        for (AMF_SubmitResult submitResult : submitted) {
            executionRefByRecordId.put(submitResult.recordId, submitResult.executionRefId);
        }

        // Step 11. Stamp the provenance reference back onto each row.
        Map<Id, String> executionRefByLogId = new Map<Id, String>();

        for (Outcome result : outcomeByRequest) {
            String executionRefId = executionRefByRecordId.get(result.recordId);

            if (String.isBlank(executionRefId)) {
                throw new AMF_SubmissionException(
                    'Record ' +
                    result.recordId +
                    ' was submitted to ' +
                    result.selectedProcess +
                    ' but the strategy returned no execution reference for it'
                );
            }

            result.executionRefId = executionRefId;
            result.submitted = true;
            executionRefByLogId.put(result.decisionLogId, executionRefId);
        }

        AMF_DecisionLogWriter.stamp(executionRefByLogId);
        return outcomes;
    }

    /**
     * Steps 5 to 7 for one record: first true expression wins, then the process
     * that rule names.
     *
     * The whole rule walk sits inside one try. 4.6 is the reason: a runtime
     * evaluation error must mark the record Failed and BLOCK, never fall
     * through to the next rule, so the catch is outside the loop rather than
     * inside it. Reaching it in the MVP means schema drift -- a field the
     * compiler resolved through describe and something has since removed -- or
     * a rule that names no process.
     *
     * @param result Populated in place with the verdict.
     * @return The decision log row for this record. Never null.
     */
    private Approval_Decision_Log__c match(
        Id recordId,
        String objectApiName,
        List<AMF_RuleDefinition> rules,
        Map<String, AMF_ExprCompiler.CompiledExpression> compiledByRule,
        Map<Id, SObject> recordsById,
        Outcome result
    ) {
        // Accumulated across every rule tried, so a Blocked_No_Match row can
        // show what the engine actually read. A matched row uses the winning
        // rule's own map instead -- 8's narrative sentence is about the rule
        // that won, not about the ones that were considered.
        Map<String, Object> valuesRead = new Map<String, Object>();
        AMF_RuleDefinition current = null;

        try {
            SObject record = recordsById.get(recordId);

            for (AMF_RuleDefinition rule : rules) {
                current = rule;

                AMF_Evaluator.Result evaluation = AMF_Evaluator.evaluate(
                    compiledByRule.get(rule.developerName),
                    record
                );
                valuesRead.putAll(evaluation.evaluatedValues);

                if (evaluation.matched != true) {
                    continue;
                }

                // Step 7. Resolve the template. Process_API_Name__c is Text with
                // no referential check (3.1) and 9's validator is out of MVP
                // scope, so a rule that names nothing is caught here.
                if (String.isBlank(rule.processApiName)) {
                    throw new AMF_SubmissionException(
                        'Rule ' +
                        rule.developerName +
                        ' matched ' +
                        recordId +
                        ' but names no approval process in Process_API_Name__c'
                    );
                }

                // One JSON string for both the outcome and the row, so what a
                // preview shows is byte for byte what the log would record.
                String evaluatedValuesJson = evaluation.toJson();

                result.outcome = 'Submitted';
                result.matchedRule = rule.developerName;
                result.ruleVersion = rule.version;
                result.rulePriority = rule.priority;
                result.matchedRuleDescription = rule.description;
                result.matchedExpression = rule.expression;
                result.evaluatedValuesJson = evaluatedValuesJson;
                result.selectedProcess = rule.processApiName;

                return AMF_DecisionLogWriter.forSubmission(
                    recordId,
                    objectApiName,
                    rule,
                    evaluatedValuesJson
                );
            }
        } catch (Exception e) {
            result.outcome = 'Failed';
            result.message =
                'Routing ' +
                recordId +
                ' failed while evaluating rule ' +
                (current == null ? '(none)' : current.developerName) +
                ': ' +
                e.getMessage();
            result.evaluatedValuesJson = JSON.serialize(valuesRead);

            return AMF_DecisionLogWriter.forFailure(
                recordId,
                objectApiName,
                current,
                result.evaluatedValuesJson,
                result.message + '\n' + e.getStackTraceString()
            );
        }

        // Step 6. 3.2: no-match blocks rather than defaulting. An org that wants
        // default routing adds a catch-all rule at priority 9999 with expression
        // TRUE, so the default appears IN the matrix where an auditor reads it,
        // rather than hiding in a config switch.
        result.outcome = 'Blocked_No_Match';
        result.message =
            'No active rule matched this ' +
            objectApiName +
            '. ' +
            rules.size() +
            ' active rule(s) were evaluated and none was true. The matrix blocks ' +
            'rather than routing by default; add a catch-all rule (priority 9999, ' +
            'expression TRUE) if this object should have default routing.';
        result.evaluatedValuesJson = JSON.serialize(valuesRead);

        return AMF_DecisionLogWriter.forNoMatch(
            recordId,
            objectApiName,
            result.evaluatedValuesJson,
            result.message
        );
    }

    /**
     * Step 9. Stages the guard on every record about to be submitted.
     *
     * Written through newSObject/put rather than a typed field so the engine
     * stays object-agnostic -- 3.2 makes Matrix_Submission__c a convention on
     * every governed object, and hardcoding Purchase_Request__c here would make
     * the second object a code change.
     */
    private void stageGuard(String objectApiName, Set<Id> recordIds) {
        Schema.SObjectType sobjectType = Schema.getGlobalDescribe().get(objectApiName);
        List<SObject> staged = new List<SObject>();

        for (Id recordId : recordIds) {
            SObject record = sobjectType.newSObject(recordId);
            record.put(GUARD_FIELD, true);
            staged.add(record);
        }

        update staged;
    }

    /**
     * 11: the service runs without sharing, so it authorises explicitly.
     * UserRecordAccess answers the record-level question that CRUD and FLS
     * checks cannot, and it answers it for a user whose sharing this class has
     * deliberately stepped outside of.
     */
    private void authorise(List<Id> recordIds) {
        Set<Id> readable = new Set<Id>();

        for (UserRecordAccess access : [
            SELECT RecordId
            FROM UserRecordAccess
            WHERE UserId = :UserInfo.getUserId() AND RecordId IN :recordIds AND HasReadAccess = TRUE
        ]) {
            readable.add(access.RecordId);
        }

        List<String> denied = new List<String>();

        for (Id recordId : recordIds) {
            if (!readable.contains(recordId)) {
                denied.add(String.valueOf(recordId));
            }
        }

        if (!denied.isEmpty()) {
            throw new AMF_SubmissionException(
                'Submission requires read access to the record. ' +
                UserInfo.getUsername() +
                ' cannot read: ' +
                String.join(denied, ', ')
            );
        }
    }

    /**
     * One object per call. Both the rule set (step 1) and the union query
     * (step 4) are per object, so a mixed list is a caller error rather than
     * something to silently partition.
     */
    private String objectTypeOf(List<Id> recordIds) {
        Set<String> objectApiNames = new Set<String>();

        for (Id recordId : recordIds) {
            if (recordId == null) {
                throw new AMF_SubmissionException('A null record Id was supplied to submit');
            }
            objectApiNames.add(String.valueOf(recordId.getSObjectType()));
        }

        if (objectApiNames.size() > 1) {
            List<String> sorted = new List<String>(objectApiNames);
            sorted.sort();
            throw new AMF_SubmissionException(
                'One submission covers one object. This call mixed: ' + String.join(sorted, ', ')
            );
        }

        return new List<String>(objectApiNames)[0];
    }

    /**
     * 3.2 makes the guard a convention, which means an object without it is
     * misconfigured rather than differently configured. Said plainly here
     * because the alternative is a field-not-found deep inside step 9, after
     * the decision log has already been written.
     */
    private void requireGuardField(String objectApiName) {
        Schema.SObjectType sobjectType = Schema.getGlobalDescribe().get(objectApiName);

        if (sobjectType == null || !sobjectType.getDescribe().fields.getMap().containsKey(GUARD_FIELD)) {
            throw new AMF_SubmissionException(
                objectApiName +
                ' cannot be governed by the approval matrix: it has no ' +
                GUARD_FIELD +
                ' field. Every governed object carries the guard (arch doc 3.2, 6.3).'
            );
        }
    }
}
