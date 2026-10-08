/**
 * 7's Flow row (M10): the Submit for Matrix Approval action.
 *
 * Architecture section: 7 (entry points, and its M10 note), 6.1 (submitEach
 * and its M10 note), 11 (security).
 *
 * One request per record and one result per request, in the order received --
 * the contract Flow holds an invocable action to. Each record is answered by
 * itself: a record that cannot be submitted gets its own result (Refused,
 * Failed or Blocked_No_Match, with the reason in message) instead of failing
 * the interview, so a record-triggered flow over 200 records still submits the
 * ones that can go. A strategy that fails as a whole is the one exception: it
 * rolls back that object's submissions and fails the action.
 *
 * submitEach() is also what AMF_MatrixSubmissionResource answers with, so a
 * Flow and an integration see one result shape.
 *
 * Declared with sharing, though it reads nothing itself: the engine runs
 * without sharing and authorises every record against the running user (11).
 */
public with sharing class AMF_SubmitForMatrixApproval {

    /** One record to submit. */
    public class Request {
        @InvocableVariable(
            label='Record ID'
            description='The record to route through the approval matrix and submit.'
            required=true
        )
        public Id recordId;
    }

    /** What happened to one record. */
    public class Result {
        @InvocableVariable(label='Record ID' description='The record this result is about.')
        public Id recordId;

        @InvocableVariable(
            label='Submitted'
            description='True only when the record entered an approval process.'
        )
        public Boolean submitted;

        @InvocableVariable(
            label='Outcome'
            description='Submitted, Blocked_No_Match, Failed or Refused. Refused means nothing was decided, so no decision log row was written.'
        )
        public String outcome;

        @InvocableVariable(
            label='Message'
            description='Why the record was not submitted. Empty when it was.'
        )
        public String message;

        @InvocableVariable(
            label='Matched Rule'
            description='DeveloperName of the rule that routed the record. Empty when none did.'
        )
        public String matchedRule;

        @InvocableVariable(label='Rule Version' description='Version of the matched rule.')
        public Integer ruleVersion;

        @InvocableVariable(
            label='Selected Process'
            description='The approval process the matrix chose for the record.'
        )
        public String selectedProcess;

        @InvocableVariable(
            label='Decision Log ID'
            description='The Approval Decision Log row that explains this result. Empty when the outcome is Refused.'
        )
        public Id decisionLogId;

        @InvocableVariable(
            label='Approval Instance ID'
            description='The ProcessInstance the record entered. Empty unless it was submitted.'
        )
        public String executionRefId;
    }

    /**
     * Test seam: tests set this so the action runs over in-memory rules and the
     * stub strategy instead of the org's matrix and real approvals. Always null
     * in production.
     */
    @TestVisible
    private static AMF_ApprovalMatrixService entryPointOverride;

    /**
     * @param requests One per record, as Flow batches them.
     * @return One result per request, in the same order.
     * @throws AMF_SubmissionException Only when the strategy fails as a whole.
     */
    @InvocableMethod(
        label='Submit for Matrix Approval'
        description='Routes each record through the approval matrix and submits it to the approval process its first matching rule names. Each record gets its own result.'
        category='Approval Matrix'
    )
    public static List<Result> submit(List<Request> requests) {
        List<Id> recordIds = new List<Id>();

        if (requests != null) {
            for (Request request : requests) {
                recordIds.add(request?.recordId);
            }
        }
        return submitEach(recordIds);
    }

    /**
     * The engine's per-record submission, as results. Shared with
     * AMF_MatrixSubmissionResource.
     *
     * @param recordIds The records to submit, of any objects, duplicates allowed.
     * @return One result per Id, in the same order.
     */
    public static List<Result> submitEach(List<Id> recordIds) {
        List<Result> results = new List<Result>();

        for (AMF_ApprovalMatrixService.Outcome outcome : engine().submitEach(recordIds)) {
            results.add(resultOf(outcome));
        }
        return results;
    }

    private static AMF_ApprovalMatrixService engine() {
        return entryPointOverride == null ? new AMF_ApprovalMatrixService() : entryPointOverride;
    }

    private static Result resultOf(AMF_ApprovalMatrixService.Outcome outcome) {
        Result result = new Result();
        result.recordId = outcome.recordId;
        result.submitted = outcome.submitted;
        result.outcome = outcome.outcome;
        result.message = outcome.message;
        result.matchedRule = outcome.matchedRule;
        result.ruleVersion = outcome.ruleVersion;
        result.selectedProcess = outcome.selectedProcess;
        result.decisionLogId = outcome.decisionLogId;
        result.executionRefId = outcome.executionRefId;
        return result;
    }
}
