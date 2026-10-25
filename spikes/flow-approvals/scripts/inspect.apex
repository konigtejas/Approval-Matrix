// Flow approvals spike (M6): read-only snapshot of one record's Flow approval state.
// Usage: replace RECORD_ID below (scripts/run.ps1 does this), then
//   sf apex run --file <copy> -o amf-dev
Id recordId = 'RECORD_ID';

System.debug(LoggingLevel.ERROR, 'SNAP locked=' + lockState(recordId)
    + ' guard=' + [SELECT Matrix_Submission__c FROM Purchase_Request__c WHERE Id = :recordId].Matrix_Submission__c);

for (ApprovalSubmission s : [
    SELECT Id, Status, SubmittedById, Comments, FlowOrchestrationInstanceId, CreatedDate
    FROM ApprovalSubmission WHERE RelatedRecordId = :recordId ORDER BY CreatedDate
]) {
    System.debug(LoggingLevel.ERROR, 'SNAP submission ' + s.Id + ' status=' + s.Status + ' by=' + s.SubmittedById
        + ' orchestration=' + s.FlowOrchestrationInstanceId + ' comments=' + s.Comments);
}
for (ApprovalWorkItem w : [
    SELECT Id, Status, AssignedToId, ReviewedById, ReviewedDate, Comments, ParentWorkItemId,
           ApprovalSubmissionId, ApprovalConditionName, CreatedDate
    FROM ApprovalWorkItem WHERE RelatedRecordId = :recordId ORDER BY CreatedDate
]) {
    System.debug(LoggingLevel.ERROR, 'SNAP workitem ' + w.Id + ' status=' + w.Status + ' assignedTo=' + w.AssignedToId
        + ' reviewedBy=' + w.ReviewedById + ' parent=' + w.ParentWorkItemId + ' submission=' + w.ApprovalSubmissionId
        + ' condition=' + w.ApprovalConditionName + ' comments=' + w.Comments);
}
for (FlowOrchestrationInstance i : [
    SELECT Id, Status FROM FlowOrchestrationInstance
    WHERE Id IN (SELECT FlowOrchestrationInstanceId FROM ApprovalSubmission WHERE RelatedRecordId = :recordId)
]) {
    System.debug(LoggingLevel.ERROR, 'SNAP orchestration ' + i.Id + ' status=' + i.Status);
}
for (FlowOrchestrationStageInstance st : [
    SELECT Id, Label, Status, OrchestrationInstanceId FROM FlowOrchestrationStageInstance
    WHERE OrchestrationInstanceId IN (SELECT FlowOrchestrationInstanceId FROM ApprovalSubmission WHERE RelatedRecordId = :recordId)
    ORDER BY CreatedDate
]) {
    System.debug(LoggingLevel.ERROR, 'SNAP stage ' + st.Label + ' status=' + st.Status);
}
for (User u : [SELECT Id, Username FROM User WHERE Username LIKE 'amfu1@%']) {
    UserRecordAccess a = [SELECT RecordId, HasReadAccess, HasEditAccess FROM UserRecordAccess WHERE UserId = :u.Id AND RecordId = :recordId];
    System.debug(LoggingLevel.ERROR, 'SNAP amfu1 ' + u.Id + ' read=' + a.HasReadAccess + ' edit=' + a.HasEditAccess);
}

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