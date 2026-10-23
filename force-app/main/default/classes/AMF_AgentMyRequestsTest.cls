/**
 * The assistant's My Approval Requests action (M14): the user's own attempts,
 * the newest per record, and where each one stands.
 *
 * Architecture section: 7 (its M14 note), 8, 11, 10.
 *
 * Blocked, failed and unjoinable rows are inserted directly, shaped as
 * AMF_DecisionLogWriter writes them. One test lets Approval.process() run over
 * in-memory rules, as AMF_AgentSubmitRouteTest does, because only a real
 * approval is pending, rejected, or waiting on someone.
 */
@IsTest
private class AMF_AgentMyRequestsTest {

    private static final String THREE_LEVEL = 'PR_Three_Level_Finance';

    private static Purchase_Request__c insertRequest(String risk) {
        Purchase_Request__c record = new Purchase_Request__c(Amount__c = 60000, Region__c = 'EMEA', Risk_Level__c = risk);
        insert record;
        return record;
    }

    private static Approval_Decision_Log__c row(Id recordId, String outcome, Datetime submittedAt) {
        return new Approval_Decision_Log__c(
            Record_Id__c = String.valueOf(recordId),
            Object_API_Name__c = 'Purchase_Request__c',
            Outcome__c = outcome,
            Selected_Process__c = outcome == 'Blocked_No_Match' ? null : THREE_LEVEL,
            Failure_Detail__c = outcome == 'Failed' ? 'Approval process ' + THREE_LEVEL + ' refused the submission: NO_APPLICABLE_PROCESS\nat line 1' : null,
            Submitted_By__c = UserInfo.getUserId(),
            Submitted_At__c = submittedAt
        );
    }

    private static String labelOf(Id recordId) {
        return 'Purchase Request ' + [SELECT Name FROM Purchase_Request__c WHERE Id = :recordId].Name;
    }

    private static AMF_AgentMyRequests.Result listOne(Boolean pendingOnly) {
        AMF_AgentMyRequests.Request request = new AMF_AgentMyRequests.Request();
        request.pendingOnly = pendingOnly;
        return AMF_AgentMyRequests.listRequests(new List<AMF_AgentMyRequests.Request>{ request })[0];
    }

    private static void assertContains(String text, String expected) {
        Assert.isTrue(text != null && text.contains(expected), 'Expected "' + expected + '" in:\n' + text);
    }

    @IsTest
    static void listsTheNewestAttemptOnEachRecordAndHowItEnded() {
        Datetime now = Datetime.now();
        Purchase_Request__c retried = insertRequest('Low');
        Purchase_Request__c unjoined = insertRequest('Low');
        Purchase_Request__c someoneElses = insertRequest('Low');

        Approval_Decision_Log__c otherUsers = row(someoneElses.Id, 'Blocked_No_Match', now);
        otherUsers.Submitted_By__c = [SELECT Id FROM User WHERE IsActive = TRUE AND Id != :UserInfo.getUserId() LIMIT 1].Id;
        Approval_Decision_Log__c submitted = row(unjoined.Id, 'Submitted', now.addMinutes(-5));
        submitted.Execution_Ref_Id__c = '04g000000000001AAA';

        insert new List<Approval_Decision_Log__c>{
            row(retried.Id, 'Blocked_No_Match', now.addHours(-2)),
            row(retried.Id, 'Failed', now.addHours(-1)),
            submitted,
            otherUsers
        };

        Test.startTest();
        AMF_AgentMyRequests.Result result = listOne(false);
        Test.stopTest();

        Assert.areEqual(2, result.count, 'Two records of the user\'s own, each once: ' + result.requests);
        assertContains(result.message, 'You submitted 2 records in the last 90 days, 0 still waiting for approval.');

        List<String> lines = result.requests.split('\n');
        Assert.areEqual(2, lines.size(), result.requests);
        Assert.isTrue(lines[0].startsWith('1. ' + labelOf(unjoined.Id) + ' (Id ' + unjoined.Id + '): submitted to approval process ' + THREE_LEVEL), lines[0]);
        assertContains(lines[0], 'its approval history is not available.');
        Assert.isTrue(lines[1].startsWith('2. ' + labelOf(retried.Id) + ' (Id ' + retried.Id + '): failed on '), lines[1]);
        assertContains(lines[1], 'so it did not enter an approval process: Approval process ' + THREE_LEVEL + ' refused the submission: NO_APPLICABLE_PROCESS. (decision log ADL-');
        Assert.isFalse(result.requests.contains(someoneElses.Id), 'Another user\'s attempt is not the user\'s request');
    }

    @IsTest
    static void aRealApprovalIsListedFirstWithWhoItIsWaitingOnAndAFinishedOneByHowItEnded() {
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM ProcessDefinition WHERE DeveloperName = :THREE_LEVEL AND State = 'Active'],
            THREE_LEVEL + ' must be active in the org for this test'
        );
        Purchase_Request__c waiting = insertRequest('High');
        Purchase_Request__c rejected = insertRequest('High');
        AMF_ApprovalMatrixService engine = new AMF_ApprovalMatrixService(
            new AMF_RuleBuilder.Stub(new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder().named('PR_High_Risk').withPriority(20).withExpression('Risk_Level__c == \'High\'').routingTo(THREE_LEVEL).build()
            }),
            new AMF_ClassicProcessStrategy()
        );

        Test.startTest();
        engine.submit(new List<Id>{ rejected.Id });
        engine.submit(new List<Id>{ waiting.Id });

        Approval.ProcessWorkitemRequest reject = new Approval.ProcessWorkitemRequest();
        reject.setAction('Reject');
        reject.setWorkitemId([SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :rejected.Id LIMIT 1].Id);
        Approval.process(reject);

        AMF_AgentMyRequests.Result all = listOne(false);
        AMF_AgentMyRequests.Result pendingOnly = listOne(true);
        Test.stopTest();

        Id approverId = [SELECT ActorId FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :waiting.Id LIMIT 1].ActorId;
        String approver = [SELECT Name FROM User WHERE Id = :approverId].Name;

        List<String> lines = all.requests.split('\n');
        Assert.areEqual(2, lines.size(), all.requests);
        Assert.isTrue(
            lines[0].startsWith('1. ' + labelOf(waiting.Id) + ' (Id ' + waiting.Id + '): in approval process ' + THREE_LEVEL + ', waiting on ' + approver + ' since '),
            'Still waiting comes first: ' + lines[0]
        );
        Assert.isTrue(lines[1].startsWith('2. ' + labelOf(rejected.Id) + ' (Id ' + rejected.Id + '): rejected in approval process ' + THREE_LEVEL + ' on '), lines[1]);
        assertContains(lines[1], ', last acted on by ' + UserInfo.getName());
        assertContains(all.message, '1 still waiting for approval.');

        Assert.areEqual(1, pendingOnly.count);
        Assert.isFalse(pendingOnly.requests.contains(rejected.Id), pendingOnly.requests);
        assertContains(pendingOnly.message, '1 of your requests is waiting for approval.');
    }

    @IsTest
    static void saysSoWhenThereIsNothingToList() {
        AMF_AgentMyRequests.Result none = AMF_AgentMyRequests.listRequests(null)[0];
        Assert.areEqual(0, none.count);
        Assert.isNull(none.requests);
        Assert.areEqual('You have not submitted anything through the approval matrix in the last 90 days.', none.message);

        Purchase_Request__c blocked = insertRequest('Low');
        insert row(blocked.Id, 'Blocked_No_Match', Datetime.now());
        AMF_AgentMyRequests.Result nonePending = listOne(true);
        Assert.areEqual('None of your requests from the last 90 days is waiting for approval.', nonePending.message);

        AMF_AgentMyRequests.Result blockedOnly = listOne(false);
        assertContains(blockedOnly.requests, ': blocked on ');
        assertContains(blockedOnly.requests, 'no rule matched, so it was not submitted (decision log ADL-');
    }

    @IsTest
    static void aRecordTheUserCanNoLongerReadIsLeftOut() {
        User submitter = new User(
            Alias = 'amfmyr',
            Email = 'amf.myrequests@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Requests',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey = 'GMT',
            Username = 'amf.myrequests.' + String.valueOf(Datetime.now().getTime()) + '@amf.test.invalid'
        );
        PermissionSet matrix = [SELECT Id FROM PermissionSet WHERE Name = 'Approval_Matrix_User' LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert submitter;
            insert new PermissionSetAssignment(AssigneeId = submitter.Id, PermissionSetId = matrix.Id);
        }

        // Their own row, on a record owned by someone else and not shared with them.
        Purchase_Request__c record = insertRequest('Low');
        Approval_Decision_Log__c theirs = row(record.Id, 'Blocked_No_Match', Datetime.now());
        theirs.Submitted_By__c = submitter.Id;
        theirs.OwnerId = submitter.Id;
        insert theirs;

        AMF_AgentMyRequests.Result result;
        System.runAs(submitter) {
            result = listOne(false);
        }

        Assert.areEqual(0, result.count, 'A record they cannot read is not listed: ' + result.requests);
    }
}
