/**
 * The Classic approval history read, against one real submission.
 *
 * Architecture section: 8 (who and when are native), 10 ("one thin integration
 * test" for what only the real platform can show), 3.3 (the join).
 *
 * ORG DEPENDENCE IS DELIBERATE AND LOCAL, exactly as in
 * AMF_SubmissionIntegrationTest: a ProcessInstance only exists after a real
 * Approval.process(), so this class needs PR_Three_Level_Finance active in the
 * org -- repo metadata, deployed with the engine -- and its named approvers.
 * The rule is still an in-memory fixture, and the submission goes through the
 * engine and AMF_ClassicProcessStrategy, the only path that may call
 * Approval.process().
 *
 * Everything the timeline does with this history is proved in
 * AMF_DecisionTimelineServiceTest against in-memory instances; what only a real
 * submission can prove is that this query reads back the shape those tests
 * assume.
 */
@IsTest
private class AMF_ClassicApprovalHistoryProviderTest {

    private static final String THREE_LEVEL = 'PR_Three_Level_Finance';

    @IsTest
    static void aRealSubmissionReadsBackAsTheStepsApprovalHistoryShows() {
        requireActiveProcess(THREE_LEVEL);

        Purchase_Request__c record = new Purchase_Request__c(
            Amount__c = 250000,
            Region__c = 'APAC',
            Risk_Level__c = 'High'
        );
        insert record;

        AMF_ApprovalMatrixService engine = new AMF_ApprovalMatrixService(
            new AMF_RuleBuilder.Stub(
                new List<AMF_RuleDefinition>{
                    new AMF_RuleBuilder()
                        .named('PR_Catch_All')
                        .withPriority(9999)
                        .withExpression('TRUE')
                        .routingTo(THREE_LEVEL)
                        .atVersion(1)
                        .build()
                }
            ),
            new AMF_ClassicProcessStrategy()
        );

        Test.startTest();
        AMF_ApprovalMatrixService.Outcome outcome = engine.submit(new List<Id>{ record.Id })[0];
        Test.stopTest();

        Assert.isTrue(
            outcome.submitted,
            'The platform refused the submission. Outcome: ' + outcome.outcome + ' / ' + outcome.message
        );

        List<AMF_ApprovalHistory.Instance> history = new AMF_ClassicApprovalHistoryProvider()
            .getHistory(record.Id, 5);

        Assert.areEqual(1, history.size(), 'One submission, one approval');

        AMF_ApprovalHistory.Instance instance = history[0];
        Assert.areEqual(
            outcome.executionRefId,
            String.valueOf(instance.id),
            'The approval the decision log row names in Execution_Ref_Id__c (3.3, 8)'
        );
        Assert.areEqual(THREE_LEVEL, instance.processName, 'The DeveloperName the matrix routed to');
        Assert.areEqual('Pending', instance.status);
        Assert.isNotNull(instance.submittedAt);

        Assert.areEqual(2, instance.steps.size(), 'The submission, and the work item it opened');

        AMF_ApprovalHistory.Step submission = instance.steps[0];
        Assert.areEqual('Started', submission.status, 'The submission leads, even sharing its second');
        Assert.isFalse(submission.isPending);
        Assert.isNull(submission.stepName, 'The submission belongs to no approval step');
        Assert.areEqual(UserInfo.getUserId(), submission.actorId, 'Submitted by the running user');
        Assert.areEqual(UserInfo.getName(), submission.actorName);

        AMF_ApprovalHistory.Step waiting = instance.steps[1];
        Assert.areEqual('Pending', waiting.status);
        Assert.isTrue(waiting.isPending, 'Still with its approver');
        Assert.areEqual('Finance Analyst', waiting.stepName, 'The first step of the three-level template (5.2)');
        Assert.isNotNull(waiting.actorId, 'Assigned to the template\'s named approver');
        Assert.isTrue(String.isNotBlank(waiting.actorName), 'With a name the timeline can show');
    }

    @IsTest
    static void aRecordThatNeverEnteredAnApprovalHasNoHistory() {
        Purchase_Request__c record = new Purchase_Request__c(
            Amount__c = 500,
            Region__c = 'EMEA',
            Risk_Level__c = 'Low'
        );
        insert record;

        Assert.areEqual(0, new AMF_ClassicApprovalHistoryProvider().getHistory(record.Id, 5).size());
    }

    @IsTest
    static void nothingToAskCostsNoQuery() {
        AMF_ClassicApprovalHistoryProvider provider = new AMF_ClassicApprovalHistoryProvider();
        Id anyRecord = UserInfo.getUserId();
        Integer queriesBefore = Limits.getQueries();

        Assert.areEqual(0, provider.getHistory(null, 5).size());
        Assert.areEqual(0, provider.getHistory(anyRecord, 0).size());
        Assert.areEqual(0, provider.getHistory(anyRecord, null).size());

        Assert.areEqual(queriesBefore, Limits.getQueries(), 'Nothing to ask, so nothing asked');
    }

    /**
     * Turns a missing or deactivated template into a sentence rather than into a
     * cryptic DmlException from the submission.
     */
    private static void requireActiveProcess(String developerName) {
        List<ProcessDefinition> definitions = [
            SELECT Id, State
            FROM ProcessDefinition
            WHERE DeveloperName = :developerName AND Type = 'Approval'
        ];

        Assert.areEqual(
            1,
            definitions.size(),
            'Approval process ' +
            developerName +
            ' is not in this org. It is repo metadata (5.2) -- deploy before running tests.'
        );
        Assert.areEqual(
            'Active',
            definitions[0].State,
            'Approval process ' + developerName + ' is deployed but not active.'
        );
    }
}
