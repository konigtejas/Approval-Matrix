// Flow approvals spike (M6), experiment E1 - launch from Apex (Q1).
// Mirrors the engine's own sequence in ONE transaction: stage the guard (6.1 step 9),
// start the named approval orchestration (step 10), then read back what exists -
// without that, step 11 (stamp Execution_Ref_Id__c) has nothing to stamp.
Id recordId = 'RECORD_ID';
String flowName = 'FLOW_NAME';

update new Purchase_Request__c(Id = recordId, Matrix_Submission__c = true);

Integer queriesBefore = Limits.getQueries();
Integer dmlBefore = Limits.getDmlStatements();
Flow.Interview interview = Flow.Interview.createInterview(flowName, new Map<String, Object>{
    'recordId' => String.valueOf(recordId),
    'submitter' => UserInfo.getUserId(),
    'submissionComments' => 'Spike E1 via Flow.Interview',
    'firstApprover' => null
});
interview.start();
System.debug(LoggingLevel.ERROR, 'E1 started ' + flowName + '; cost: queries=' + (Limits.getQueries() - queriesBefore)
    + ' dml=' + (Limits.getDmlStatements() - dmlBefore) + ' cpu=' + Limits.getCpuTime());

List<ApprovalSubmission> subs = [
    SELECT Id, Status, SubmittedById, FlowOrchestrationInstanceId
    FROM ApprovalSubmission WHERE RelatedRecordId = :recordId ORDER BY CreatedDate DESC LIMIT 1
];
System.debug(LoggingLevel.ERROR, 'E1 same-transaction submission: ' + (subs.isEmpty() ? 'NONE' : subs[0].Id + ' status=' + subs[0].Status
    + ' by=' + subs[0].SubmittedById + ' orchestration=' + subs[0].FlowOrchestrationInstanceId));
System.debug(LoggingLevel.ERROR, 'E1 same-transaction work items: ' + [SELECT COUNT() FROM ApprovalWorkItem WHERE RelatedRecordId = :recordId]
    + '; locked=' + lockState(recordId));

// Approval.isLocked() needs the org preference "Enable record locking and unlocking in
// Apex" (Process Automation Settings); without it, it throws NoAccessException. The
// spike reports that rather than changing an org-wide setting.
static String lockState(Id recordId) {
    try {
        return String.valueOf(Approval.isLocked(recordId));
    } catch (NoAccessException e) {
        return 'unknown (lock API preference off)';
    }
}