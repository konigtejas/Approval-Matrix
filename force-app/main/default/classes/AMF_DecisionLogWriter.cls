/**
 * Builds and persists Approval_Decision_Log__c rows: the immutable answer to
 * WHY a record routed where it did.
 *
 * Architecture section: 3.3 (the audit artefact), 6.1 steps 8 and 11, 8
 * (auditability), 4.6 (fail loudly).
 *
 * 8 names the flaw this object exists to fix. In the prior implementation
 * re-evaluation overwrote the template field, so the mechanism that kept
 * routing current destroyed the historical record. Here every submission
 * attempt writes a permanent row and the current answer and the historical
 * answer are different records -- which only holds if the row is written for
 * every outcome, including the ones nobody wants. A blocked submission that
 * leaves no trace is the same silent failure in a different costume, so
 * forNoMatch and forFailure are as much a part of this class as forSubmission.
 *
 * Declared without sharing, and the CRUD picture is deliberate. The log object
 * is Private, Approval_Matrix_User grants read but NOT create, and
 * Matrix_Submission__c is read-only there (3.3, 11) -- yet the engine's DML
 * runs in system mode and is unaffected, which is precisely the intent: only
 * the framework writes the audit trail, and it writes it on behalf of a
 * submitter who could not have written it themselves.
 */
public without sharing class AMF_DecisionLogWriter {

    /** Outcome__c values (3.3). The picklist is restricted; these are its whole domain. */
    @TestVisible
    private static final String OUTCOME_SUBMITTED = 'Submitted';
    @TestVisible
    private static final String OUTCOME_BLOCKED_NO_MATCH = 'Blocked_No_Match';
    @TestVisible
    private static final String OUTCOME_FAILED = 'Failed';

    /** Failure_Detail__c is Long Text(4000); an exception with a stack trace is not. */
    private static final Integer FAILURE_DETAIL_LIMIT = 4000;

    /**
     * Governed object API name -> the lookup field on this object that points at
     * it, or null when there is none. Resolved by describe, cached per transaction.
     */
    private static final Map<String, String> LOOKUP_BY_OBJECT = new Map<String, String>();

    /**
     * A row for a record the matrix routed. Written BEFORE the submission
     * (6.1 step 8), so Execution_Ref_Id__c is still blank -- stamp() fills it
     * at step 11 and Lock_Decision_Log permits exactly that one update.
     *
     * @param recordId             The governed record.
     * @param objectApiName        Its object.
     * @param rule                 The winning rule.
     * @param evaluatedValuesJson  The winning rule's evaluated values, as JSON.
     * @return The unsaved row.
     */
    public static Approval_Decision_Log__c forSubmission(
        Id recordId,
        String objectApiName,
        AMF_RuleDefinition rule,
        String evaluatedValuesJson
    ) {
        Approval_Decision_Log__c row = base(recordId, objectApiName);
        row.Outcome__c = OUTCOME_SUBMITTED;
        row.Matched_Rule__c = rule.developerName;
        row.Rule_Version__c = rule.version;

        // Snapshotted, not referenced. Editing the rule tomorrow must not rewrite
        // what happened today -- that is the whole of 3.3's Expression_Snapshot__c
        // and Selected_Process__c, and the reason the M3 rule-flip demo can leave
        // two log rows side by side showing the same expression and two processes.
        row.Expression_Snapshot__c = rule.expression;
        row.Selected_Process__c = rule.processApiName;
        row.Evaluated_Values__c = evaluatedValuesJson;
        return row;
    }

    /**
     * A row for a record no active rule matched. 3.2: no-match blocks rather
     * than defaulting, and an org wanting default routing adds a visible
     * catch-all rule at priority 9999 -- so this row is what an auditor reads
     * when the matrix deliberately declined to route something.
     *
     * evaluatedValuesJson here is the union of everything the engine read
     * across EVERY rule it tried, not one rule's values, because with no winner
     * there is no other way to show what the decision was made on.
     *
     * @param recordId            The governed record.
     * @param objectApiName       Its object.
     * @param evaluatedValuesJson Every value read while trying the matrix.
     * @param detail              Why nothing matched, in words.
     * @return The unsaved row.
     */
    public static Approval_Decision_Log__c forNoMatch(
        Id recordId,
        String objectApiName,
        String evaluatedValuesJson,
        String detail
    ) {
        Approval_Decision_Log__c row = base(recordId, objectApiName);
        row.Outcome__c = OUTCOME_BLOCKED_NO_MATCH;
        row.Evaluated_Values__c = evaluatedValuesJson;
        row.Failure_Detail__c = truncate(detail);
        return row;
    }

    /**
     * A row for a record whose routing failed at runtime. 4.6 is the whole
     * point of this method: the error marks the row Failed, lands in
     * Failure_Detail__c and BLOCKS -- it never falls through to the next rule,
     * and it is never caught into a boolean.
     *
     * @param recordId            The governed record.
     * @param objectApiName       Its object.
     * @param rule                The rule under evaluation when it failed, or
     *                            null if the failure preceded any rule.
     * @param evaluatedValuesJson Whatever had been read by then.
     * @param detail              The exception text.
     * @return The unsaved row.
     */
    public static Approval_Decision_Log__c forFailure(
        Id recordId,
        String objectApiName,
        AMF_RuleDefinition rule,
        String evaluatedValuesJson,
        String detail
    ) {
        Approval_Decision_Log__c row = base(recordId, objectApiName);
        row.Outcome__c = OUTCOME_FAILED;
        row.Evaluated_Values__c = evaluatedValuesJson;
        row.Failure_Detail__c = truncate(detail);

        if (rule != null) {
            row.Matched_Rule__c = rule.developerName;
            row.Rule_Version__c = rule.version;
            row.Expression_Snapshot__c = rule.expression;
            row.Selected_Process__c = rule.processApiName;
        }
        return row;
    }

    /**
     * Persists rows. Insert, never upsert: 3.3 makes Record_Id__c an external id
     * that is deliberately NOT unique, because one record accumulates one row
     * per submission and rows are never deleted.
     *
     * @param rows The rows to write. Each carries its Id afterwards.
     */
    public static void save(List<Approval_Decision_Log__c> rows) {
        if (rows == null || rows.isEmpty()) {
            return;
        }
        insert rows;
    }

    /**
     * 6.1 step 11. The one update Lock_Decision_Log allows: Execution_Ref_Id__c
     * moving blank to populated, with no other governed field changed.
     *
     * The rows are rebuilt from scratch rather than re-saving the inserted
     * instances, and that is the M1.10 carried item honoured literally -- an
     * SObject carrying only Id and Execution_Ref_Id__c cannot dirty a field the
     * validation rule is watching, however the caller has handled it since.
     *
     * @param executionRefByLogId Execution reference keyed by decision log Id.
     * @throws AMF_SubmissionException If any reference is blank, which would
     *         trip the lock rule with a confusing message rather than this one.
     */
    public static void stamp(Map<Id, String> executionRefByLogId) {
        if (executionRefByLogId == null || executionRefByLogId.isEmpty()) {
            return;
        }

        List<Approval_Decision_Log__c> stamps = new List<Approval_Decision_Log__c>();

        for (Id logId : executionRefByLogId.keySet()) {
            String executionRefId = executionRefByLogId.get(logId);

            if (String.isBlank(executionRefId)) {
                throw new AMF_SubmissionException(
                    'Decision log ' + logId + ' cannot be stamped with a blank execution reference'
                );
            }
            stamps.add(
                new Approval_Decision_Log__c(Id = logId, Execution_Ref_Id__c = executionRefId)
            );
        }

        update stamps;
    }

    /**
     * The fields every row carries whatever the outcome.
     *
     * Submitted_At__c is stamped explicitly rather than left to CreatedDate, so
     * the audit trail does not depend on a system field (3.3).
     */
    private static Approval_Decision_Log__c base(Id recordId, String objectApiName) {
        Approval_Decision_Log__c row = new Approval_Decision_Log__c(
            Record_Id__c = String.valueOf(recordId),
            Object_API_Name__c = objectApiName,
            Submitted_By__c = UserInfo.getUserId(),
            Submitted_At__c = System.now()
        );

        // The navigational half. Record_Id__c above is the provenance and is always
        // written; this only fires when the log object happens to carry a lookup to
        // the governed object, and its absence is a missing related list rather
        // than a missing audit trail.
        String lookup = lookupFieldFor(objectApiName);
        if (lookup != null) {
            row.put(lookup, recordId);
        }
        return row;
    }

    /**
     * Finds the lookup on Approval_Decision_Log__c that points at the governed
     * object, BY DESCRIBE rather than by a naming convention.
     *
     * That is the whole point of the method. Salesforce has no custom polymorphic
     * lookup, so one lookup binds to one object and a framework governing several
     * needs one field per object. Discovering them by reference type means
     * governing a second object is a new lookup field on this object and NO code
     * change here -- which is the same bargain 3.2 makes for the guard field.
     *
     * Only custom reference fields are considered, so Submitted_By__c and OwnerId
     * can never be mistaken for the governed record. Where more than one lookup
     * points at the same object the first by API name wins, deterministically,
     * because an arbitrary-but-stable answer beats an order that varies between
     * transactions.
     *
     * @param objectApiName The governed object.
     * @return The lookup field's API name, or null when the log carries none.
     */
    private static String lookupFieldFor(String objectApiName) {
        if (LOOKUP_BY_OBJECT.containsKey(objectApiName)) {
            return LOOKUP_BY_OBJECT.get(objectApiName);
        }

        Schema.SObjectType governed = Schema.getGlobalDescribe().get(objectApiName);
        List<String> candidates = new List<String>();

        if (governed != null) {
            Map<String, Schema.SObjectField> fields = Approval_Decision_Log__c.SObjectType.getDescribe()
                .fields.getMap();

            for (Schema.SObjectField field : fields.values()) {
                Schema.DescribeFieldResult described = field.getDescribe();

                if (!described.isCustom() || described.getType() != Schema.DisplayType.REFERENCE) {
                    continue;
                }
                for (Schema.SObjectType referenced : described.getReferenceTo()) {
                    if (referenced == governed) {
                        candidates.add(described.getName());
                    }
                }
            }
        }

        String resolved = null;
        if (!candidates.isEmpty()) {
            candidates.sort();
            resolved = candidates[0];
        }

        LOOKUP_BY_OBJECT.put(objectApiName, resolved);
        return resolved;
    }

    private static String truncate(String detail) {
        if (detail == null || detail.length() <= FAILURE_DETAIL_LIMIT) {
            return detail;
        }
        return detail.abbreviate(FAILURE_DETAIL_LIMIT);
    }
}
