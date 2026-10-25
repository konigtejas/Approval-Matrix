/**
 * Flow approvals spike (M6): what an approval orchestration does inside an Apex test.
 *
 * Discovery, not a regression test. Each method gathers observations and ends in
 * Assert.fail('REPORT: ...') so the test result carries them back. It is deployed only
 * for the spike and deleted from the org afterwards, because it depends on spike flows
 * and seeded users and must never join RunLocalTests.
 */
@IsTest
private class AMF_FlowApprovalSpikeTest {

    @IsTest
    static void orchestrationLifecycleInTestContext() {
        Purchase_Request__c record = new Purchase_Request__c(
            Amount__c = 1, Region__c = 'EMEA', Risk_Level__c = 'Low', Matrix_Submission__c = true
        );
        insert record;
        List<String> report = new List<String>();

        Test.startTest();
        try {
            Flow.Interview interview = Flow.Interview.createInterview('AMF_Spike_User', new Map<String, Object>{
                'recordId' => String.valueOf(record.Id),
                'submitter' => UserInfo.getUserId(),
                'submissionComments' => 'Spike test context',
                'firstApprover' => null
            });
            interview.start();
            report.add('start=ok');
        } catch (Exception e) {
            report.add('start threw ' + e.getTypeName() + ': ' + e.getMessage());
        }

        List<ApprovalSubmission> subs = [SELECT Id, Status FROM ApprovalSubmission WHERE RelatedRecordId = :record.Id];
        List<ApprovalWorkItem> items = [SELECT Id, Status, AssignedToId FROM ApprovalWorkItem WHERE RelatedRecordId = :record.Id];
        report.add('inTest submissions=' + subs.size() + (subs.isEmpty() ? '' : ' status=' + subs[0].Status)
            + ' items=' + items.size());

        if (!items.isEmpty()) {
            User approver = [SELECT Id FROM User WHERE Username LIKE 'amfu1@%' LIMIT 1];
            report.add('approverReadAccess=' + [
                SELECT RecordId, HasReadAccess FROM UserRecordAccess WHERE UserId = :approver.Id AND RecordId = :record.Id
            ].HasReadAccess);
            System.runAs(approver) {
                report.add('reviewAsAssignee ' + review(items[0].Id, 'Approve'));
            }
        }
        Test.stopTest();

        subs = [SELECT Id, Status FROM ApprovalSubmission WHERE RelatedRecordId = :record.Id];
        items = [SELECT Id, Status, ReviewedById FROM ApprovalWorkItem WHERE RelatedRecordId = :record.Id];
        report.add('afterStopTest submissions=' + subs.size() + (subs.isEmpty() ? '' : ' status=' + subs[0].Status)
            + (items.isEmpty() ? '' : ' itemStatus=' + items[0].Status));
        report.add('guard=' + [SELECT Matrix_Submission__c FROM Purchase_Request__c WHERE Id = :record.Id].Matrix_Submission__c);

        Assert.fail('REPORT: ' + String.join(report, ' | '));
    }

    /**
     * Record locking (shouldLock), a non-admin submitter starting the approval, and who
     * may decide a work item. amfu2 is an ordinary user (Approval_Matrix_User, no Modify
     * All, no Run Flows on the profile) who owns the records; amfu1 is the assignee.
     */
    @IsTest
    static void lockingAndPermissionsInTestContext() {
        User owner = [SELECT Id FROM User WHERE Username LIKE 'amfu2@%' LIMIT 1];
        User assignee = [SELECT Id FROM User WHERE Username LIKE 'amfu1@%' LIMIT 1];
        List<String> report = new List<String>();
        Purchase_Request__c submitted = new Purchase_Request__c(
            Amount__c = 10, Region__c = 'EMEA', Risk_Level__c = 'Low', Matrix_Submission__c = true
        );
        Purchase_Request__c control = new Purchase_Request__c(Amount__c = 11, Region__c = 'EMEA', Risk_Level__c = 'Low');
        // API 67.0: DML runs in USER mode by default. Matrix_Submission__c is read-only for
        // Approval_Matrix_User, so a plain insert as the owner is refused; setup says system.
        System.runAs(owner) {
            insert as system new List<Purchase_Request__c>{ submitted, control };
        }

        Test.startTest();
        System.runAs(owner) {
            try {
                start('AMF_Spike_User', submitted.Id, owner.Id);
                report.add('startAsNonAdminSubmitter=ok');
            } catch (Exception e) {
                report.add('startAsNonAdminSubmitter threw ' + e.getTypeName() + ': ' + e.getMessage());
            }
        }
        if ([SELECT COUNT() FROM ApprovalSubmission WHERE RelatedRecordId = :submitted.Id] == 0) {
            start('AMF_Spike_User', submitted.Id, owner.Id);
            report.add('startedAsTestRunnerInstead');
        }

        System.runAs(owner) {
            report.add('ownerEditWhilePending ' + tryUpdate(submitted.Id, 12));
            report.add('ownerEditUnsubmittedControl ' + tryUpdate(control.Id, 13));
        }

        ApprovalWorkItem item = [
            SELECT Id FROM ApprovalWorkItem WHERE RelatedRecordId = :submitted.Id AND Status = 'Assigned' LIMIT 1
        ];
        System.runAs(owner) {
            report.add('reviewByNonAssignee ' + review(item.Id, 'Approve'));
        }
        System.runAs(assignee) {
            report.add('reviewByAssignee ' + review(item.Id, 'Approve'));
        }
        Test.stopTest();

        System.runAs(owner) {
            report.add('ownerEditAfterApproval ' + tryUpdate(submitted.Id, 14));
        }
        report.add('finalStatus=' + [SELECT Status FROM ApprovalSubmission WHERE RelatedRecordId = :submitted.Id LIMIT 1].Status);

        Assert.fail('REPORT: ' + String.join(report, ' | '));
    }

    private static void start(String flowName, Id recordId, Id submitterId) {
        Flow.Interview.createInterview(flowName, new Map<String, Object>{
            'recordId' => String.valueOf(recordId),
            'submitter' => String.valueOf(submitterId),
            'submissionComments' => 'Spike locking test',
            'firstApprover' => null
        }).start();
    }

    private static String tryUpdate(Id recordId, Decimal amount) {
        try {
            // System mode, so field security cannot be mistaken for the record lock.
            update as system new Purchase_Request__c(Id = recordId, Amount__c = amount);
            return 'ok';
        } catch (DmlException e) {
            return 'refused ' + e.getDmlType(0) + ': ' + e.getDmlMessage(0);
        }
    }

    private static String review(Id workItemId, String decision) {
        Invocable.Action action = Invocable.Action.createStandardAction('reviewApprovalWorkItem');
        // Invocable.Action parameters are typed: an Id is refused (INVALID_ARGUMENT_TYPE).
        action.setInvocationParameter('approvalWorkItemId', String.valueOf(workItemId));
        action.setInvocationParameter('approvalDecision', decision);
        Invocable.Action.Result result = action.invoke()[0];
        List<String> errors = new List<String>();
        for (Invocable.Action.Error e : result.getErrors()) {
            errors.add(e.getCode() + ': ' + e.getMessage());
        }
        return 'success=' + result.isSuccess() + (errors.isEmpty() ? '' : ' errors=' + errors);
    }
}
