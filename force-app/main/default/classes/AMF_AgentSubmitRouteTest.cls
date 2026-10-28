/**
 * The assistant's Submit Previewed Route action (M13): the M10 per-record path,
 * a summary the agent repeats, and a changed route caught in Apex.
 *
 * Architecture section: 6.1 (submitEach), 6.4 (a route that changed after its
 * preview), 7 (its M13 note), 10.
 *
 * Most tests run over in-memory rules and AMF_StrategyStub through the M10
 * action's entryPointOverride seam, so they prove the agent's submission takes
 * exactly the path a Flow does. One test lets Approval.process() run, as
 * AMF_SubmissionIntegrationTest does, because only a real approval has a work
 * item to say who it is waiting on. Its rules are in-memory too.
 */
@IsTest
private class AMF_AgentSubmitRouteTest {

    private static final String THREE_LEVEL = 'PR_Three_Level_Finance';
    private static final String TWO_LEVEL = 'PR_Two_Level_Mgmt';

    private static List<AMF_RuleDefinition> highRiskRules() {
        return new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder()
                .named('PR_High_Risk')
                .withPriority(20)
                .withExpression('Risk_Level__c == \'High\'')
                .routingTo(THREE_LEVEL)
                .atVersion(2)
                .build()
        };
    }

    private static AMF_StrategyStub overStub() {
        AMF_StrategyStub strategy = new AMF_StrategyStub();
        AMF_SubmitForMatrixApproval.entryPointOverride = new AMF_ApprovalMatrixService(
            new AMF_RuleBuilder.Stub(highRiskRules()),
            strategy
        );
        return strategy;
    }

    private static Purchase_Request__c insertRequest(String risk) {
        Purchase_Request__c record = new Purchase_Request__c(Amount__c = 60000, Region__c = 'EMEA', Risk_Level__c = risk);
        insert record;
        return record;
    }

    private static String labelOf(Id recordId) {
        return Purchase_Request__c.SObjectType.getDescribe().getLabel() +
            ' ' +
            [SELECT Name FROM Purchase_Request__c WHERE Id = :recordId].Name;
    }

    private static AMF_AgentSubmitRoute.Request requestFor(String recordId, String expectedProcess) {
        AMF_AgentSubmitRoute.Request request = new AMF_AgentSubmitRoute.Request();
        request.recordId = recordId;
        request.expectedProcess = expectedProcess;
        return request;
    }

    private static AMF_AgentSubmitRoute.Result submitOne(String recordId, String expectedProcess) {
        return AMF_AgentSubmitRoute.submit(
            new List<AMF_AgentSubmitRoute.Request>{ requestFor(recordId, expectedProcess) }
        )[0];
    }

    private static String logNameOf(Id recordId) {
        return [SELECT Name FROM Approval_Decision_Log__c WHERE Record_Id__c = :String.valueOf(recordId)].Name;
    }

    @IsTest
    static void submitsThePreviewedRouteThroughTheFlowPathAndSaysWhereItWent() {
        Purchase_Request__c record = insertRequest('High');
        AMF_StrategyStub strategy = overStub();

        Test.startTest();
        AMF_AgentSubmitRoute.Result result = submitOne(record.Id, THREE_LEVEL);
        Test.stopTest();

        Assert.isTrue(result.submitted, result.summary);
        Assert.areEqual('Submitted', result.outcome);
        Assert.areEqual(THREE_LEVEL, result.selectedProcess);
        Assert.areEqual('PR_High_Risk', result.matchedRule);
        Assert.areEqual(2, result.ruleVersion);
        Assert.isFalse(result.routeChanged);
        Assert.areEqual(logNameOf(record.Id), result.decisionLogName, 'The row the M10 path wrote');
        Assert.isNull(result.waitingOn, 'The stub starts no real approval, so nothing is waiting');
        Assert.areEqual(
            'Submitted. ' + labelOf(record.Id) + ' entered approval process ' + THREE_LEVEL +
            '. Rule PR_High_Risk (version 2) decided the route. Decision log: ' + result.decisionLogName + '.',
            result.summary
        );
        Assert.areEqual(1, strategy.calls);
        Assert.isTrue(strategy.guardAtSubmit.get(record.Id), 'The guard staged before submit, as for any entry point');
    }

    @IsTest
    static void namesARuleWithNoRecordedVersionWithoutInventingOne() {
        Purchase_Request__c record = insertRequest('High');
        AMF_SubmitForMatrixApproval.entryPointOverride = new AMF_ApprovalMatrixService(
            new AMF_RuleBuilder.Stub(
                new List<AMF_RuleDefinition>{
                    new AMF_RuleBuilder()
                        .named('PR_High_Risk')
                        .withExpression('Risk_Level__c == \'High\'')
                        .routingTo(THREE_LEVEL)
                        .atVersion(null)
                        .build()
                }
            ),
            new AMF_StrategyStub()
        );

        AMF_AgentSubmitRoute.Result result = submitOne(record.Id, THREE_LEVEL);

        Assert.isTrue(result.submitted, result.summary);
        Assert.isTrue(result.summary.contains('. Rule PR_High_Risk decided the route.'), result.summary);
    }

    @IsTest
    static void saysSoInApexWhenTheRouteChangedAfterThePreview() {
        Purchase_Request__c record = insertRequest('High');
        overStub();

        AMF_AgentSubmitRoute.Result result = submitOne(record.Id, '  ' + TWO_LEVEL + ' ');

        Assert.isTrue(result.submitted);
        Assert.isTrue(result.routeChanged);
        Assert.isTrue(result.summary.startsWith('Submitted, but by a different route than previewed. '), result.summary);
        Assert.isTrue(
            result.summary.contains(
                ' The preview had shown ' + TWO_LEVEL + ': the record or the approval matrix changed after it.'
            ),
            result.summary
        );
    }

    @IsTest
    static void aBlockedSubmissionIsRecordedAndSaidToBeSo() {
        Purchase_Request__c record = insertRequest('Low');
        overStub();

        AMF_AgentSubmitRoute.Result result = submitOne(record.Id, null);

        Assert.isFalse(result.submitted);
        Assert.areEqual('Blocked_No_Match', result.outcome);
        Assert.isFalse(result.routeChanged, 'The preview showed no route either');
        Assert.areEqual(
            'Not submitted. No active rule matched ' + labelOf(record.Id) + ', so the approval matrix blocked it ' +
            'instead of routing it by default. The attempt is recorded in decision log ' + logNameOf(record.Id) + '.',
            result.summary
        );
    }

    @IsTest
    static void aPreviewThatShowedABlockAndThenFindsARouteSaysTheRouteChanged() {
        Purchase_Request__c record = insertRequest('High');
        overStub();

        AMF_AgentSubmitRoute.Result result = submitOne(record.Id, '');

        Assert.isTrue(result.submitted, result.summary);
        Assert.isTrue(result.routeChanged, 'A blank expected process is the block the user confirmed');
        Assert.isTrue(result.summary.startsWith('Submitted, but by a different route than previewed. '), result.summary);
        Assert.isTrue(result.summary.contains('would not enter an approval process'), result.summary);
    }

    @IsTest
    static void aRecordThatNoLongerMatchesTheRoutePreviewedIsAChangedRoute() {
        Purchase_Request__c record = insertRequest('Low');
        overStub();

        AMF_AgentSubmitRoute.Result result = submitOne(record.Id, THREE_LEVEL);

        Assert.areEqual('Blocked_No_Match', result.outcome);
        Assert.isTrue(result.routeChanged);
        Assert.isTrue(result.summary.contains('The preview had shown ' + THREE_LEVEL), result.summary);
    }

    @IsTest
    static void aPlatformRefusalIsAFailedAttemptWithThePlatformsReason() {
        Purchase_Request__c record = insertRequest('High');
        AMF_StrategyStub strategy = overStub();
        strategy.refuse.add(record.Id);

        AMF_AgentSubmitRoute.Result result = submitOne(record.Id, THREE_LEVEL);

        Assert.isFalse(result.submitted);
        Assert.areEqual('Failed', result.outcome);
        Assert.isFalse(result.routeChanged, 'The matrix chose the route previewed; the platform refused it');
        Assert.areEqual(
            'Not submitted. Approval process ' + THREE_LEVEL + ' refused the submission: ' + strategy.refusalMessage +
            '. The attempt is recorded in decision log ' + logNameOf(record.Id) + '.',
            result.summary
        );
    }

    @IsTest
    static void aRecordTheMatrixCannotActOnIsRefusedAndNothingIsRecorded() {
        Account account = new Account(Name = 'Not governed');
        insert account;
        overStub();

        AMF_AgentSubmitRoute.Result result = submitOne(account.Id, THREE_LEVEL);

        Assert.isFalse(result.submitted);
        Assert.areEqual(AMF_AgentSubmitRoute.REFUSED, result.outcome);
        Assert.isFalse(result.routeChanged);
        Assert.isNull(result.decisionLogName);
        Assert.isTrue(result.summary.startsWith('Not submitted. '), result.summary);
        Assert.isTrue(result.summary.endsWith(' Nothing was recorded.'), result.summary);
        Assert.areEqual(0, [SELECT COUNT() FROM Approval_Decision_Log__c]);
    }

    @IsTest
    static void textThatIsNotARecordIdIsRefusedAndTheOthersStillGo() {
        Purchase_Request__c record = insertRequest('High');
        overStub();

        List<AMF_AgentSubmitRoute.Result> results = AMF_AgentSubmitRoute.submit(
            new List<AMF_AgentSubmitRoute.Request>{
                requestFor('PR-00000045', THREE_LEVEL),
                requestFor(record.Id, THREE_LEVEL)
            }
        );

        Assert.areEqual(2, results.size());
        Assert.areEqual(AMF_AgentSubmitRoute.REFUSED, results[0].outcome);
        Assert.isNull(results[0].recordId);
        Assert.isTrue(results[0].summary.contains('"PR-00000045" is not a Salesforce record Id'), results[0].summary);
        Assert.isTrue(results[1].submitted, results[1].summary);
        Assert.isTrue(AMF_AgentSubmitRoute.submit(null).isEmpty());
        Assert.isTrue(AMF_AgentSubmitRoute.submit(new List<AMF_AgentSubmitRoute.Request>()).isEmpty());
    }

    @IsTest
    static void aRealApprovalSaysWhoItIsWaitingOn() {
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM ProcessDefinition WHERE DeveloperName = :THREE_LEVEL AND State = 'Active'],
            THREE_LEVEL + ' must be active in the org for this test'
        );
        Purchase_Request__c record = insertRequest('High');
        AMF_SubmitForMatrixApproval.entryPointOverride = new AMF_ApprovalMatrixService(
            new AMF_RuleBuilder.Stub(highRiskRules()),
            new AMF_ClassicProcessStrategy()
        );

        Test.startTest();
        AMF_AgentSubmitRoute.Result result = submitOne(record.Id, THREE_LEVEL);
        Test.stopTest();

        Assert.isTrue(result.submitted, result.summary);
        // By ActorId: in this transaction the platform returns Actor.Name as null,
        // which is why the action names approvers the same way.
        Id actorId = [
            SELECT ActorId
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId = :record.Id
            LIMIT 1
        ]
        .ActorId;
        String approver = [SELECT Name FROM User WHERE Id = :actorId].Name;
        Assert.isNotNull(approver, 'The template names a user for its first step');
        Assert.areEqual(approver, result.waitingOn);
        Assert.isTrue(
            result.summary.contains(' entered approval process ' + THREE_LEVEL + ' and is now waiting on ' + approver + '.'),
            result.summary
        );
    }
}
