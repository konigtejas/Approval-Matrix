/**
 * The Claude connector's submit_for_approval tool (M16): a submission only of
 * what its user has just previewed, by the route they confirmed.
 *
 * Architecture section: 6.1, 6.4, 7 (its M16 note), 11, 10.
 *
 * Runs over in-memory rules and AMF_StrategyStub through the same seams as the
 * assistant's tests: Preview Approval Route's engineOverride for the second
 * look, and the M10 action's entryPointOverride for the submission itself.
 * Every refusal is pinned to write nothing -- no decision log row, no guard,
 * no call to the strategy.
 */
@IsTest
private class AMF_McpSubmitRouteTest {

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

    private static AMF_StrategyStub over(List<AMF_RuleDefinition> rules) {
        AMF_StrategyStub strategy = new AMF_StrategyStub();
        AMF_AgentPreviewRoute.engineOverride = new AMF_ApprovalMatrixService(new AMF_RuleBuilder.Stub(rules), strategy);
        AMF_SubmitForMatrixApproval.entryPointOverride = new AMF_ApprovalMatrixService(new AMF_RuleBuilder.Stub(rules), strategy);
        AMF_AgentFindRecord.ruleProviderOverride = new AMF_RuleBuilder.Stub(rules);
        return strategy;
    }

    private static void withKey() {
        insert new AMF_Mcp_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Preview_Key__c = EncodingUtil.base64Encode(Crypto.generateAesKey(256))
        );
    }

    private static Purchase_Request__c insertRequest(String risk) {
        Purchase_Request__c record = new Purchase_Request__c(Amount__c = 60000, Region__c = 'EMEA', Risk_Level__c = risk);
        insert record;
        return [SELECT Id, Name FROM Purchase_Request__c WHERE Id = :record.Id];
    }

    private static AMF_McpPreviewRoute.Result previewOf(Id recordId) {
        AMF_McpPreviewRoute.Request request = new AMF_McpPreviewRoute.Request();
        request.record = String.valueOf(recordId);
        return AMF_McpPreviewRoute.preview(new List<AMF_McpPreviewRoute.Request>{ request })[0];
    }

    private static AMF_McpSubmitRoute.Result submitOf(String recordId, String expectedProcess, String token) {
        AMF_McpSubmitRoute.Request request = new AMF_McpSubmitRoute.Request();
        request.recordId = recordId;
        request.expectedProcess = expectedProcess;
        request.submitToken = token;
        return AMF_McpSubmitRoute.submit(new List<AMF_McpSubmitRoute.Request>{ request })[0];
    }

    private static void assertNothingWritten(Id recordId, AMF_StrategyStub strategy) {
        Assert.areEqual(0, [SELECT COUNT() FROM Approval_Decision_Log__c], 'No decision log row');
        Assert.areEqual(0, strategy.calls, 'The strategy was never asked');
        if (recordId != null) {
            Assert.isFalse(
                [SELECT Matrix_Submission__c FROM Purchase_Request__c WHERE Id = :recordId].Matrix_Submission__c,
                'No guard'
            );
        }
    }

    @IsTest
    static void submitsWhatWasPreviewedByTheRouteTheUserConfirmed() {
        withKey();
        AMF_StrategyStub strategy = over(highRiskRules());
        Purchase_Request__c record = insertRequest('High');
        AMF_McpPreviewRoute.Result preview = previewOf(record.Id);

        Test.startTest();
        AMF_McpSubmitRoute.Result result = submitOf(preview.recordId, preview.selectedProcess, preview.submitToken);
        Test.stopTest();

        Assert.isTrue(result.submitted, '' + result.summary);
        Assert.areEqual('Submitted', result.outcome);
        Assert.areEqual(THREE_LEVEL, result.selectedProcess);
        Assert.areEqual('PR_High_Risk', result.matchedRule);
        Assert.areEqual(2, result.ruleVersion);
        Assert.isFalse(result.routeChanged);
        Assert.areEqual('Purchase Request ' + record.Name, result.recordLabel);
        Assert.areEqual(AMF_McpSupport.recordUrlOf(record.Id), result.recordUrl);
        Assert.areEqual(
            [SELECT Name FROM Approval_Decision_Log__c WHERE Record_Id__c = :String.valueOf(record.Id)].Name,
            result.decisionLogName,
            'The row M10\'s path wrote'
        );
        Assert.isTrue(result.summary.startsWith('Submitted. '), '' + result.summary);
        Assert.areEqual(1, strategy.calls);
        Assert.isTrue(strategy.guardAtSubmit.get(record.Id), 'The guard staged before submit, as for every entry point');
    }

    @IsTest
    static void aSubmissionWithNoPreviewIsRefusedAndWritesNothing() {
        withKey();
        AMF_StrategyStub strategy = over(highRiskRules());
        Purchase_Request__c record = insertRequest('High');

        AMF_McpSubmitRoute.Result missing = submitOf(String.valueOf(record.Id), THREE_LEVEL, null);
        AMF_McpSubmitRoute.Result invented = submitOf(String.valueOf(record.Id), THREE_LEVEL, '1792856211156.abc123');

        for (AMF_McpSubmitRoute.Result result : new List<AMF_McpSubmitRoute.Result>{ missing, invented }) {
            Assert.isFalse(result.submitted);
            Assert.areEqual('Refused', result.outcome);
            Assert.areEqual(AMF_McpSupport.NOT_PREVIEWED, result.summary);
            Assert.isNull(result.decisionLogName);
        }
        assertNothingWritten(record.Id, strategy);
    }

    @IsTest
    static void aPreviewOfOneRouteDoesNotSubmitAnother() {
        withKey();
        AMF_StrategyStub strategy = over(highRiskRules());
        Purchase_Request__c record = insertRequest('High');
        Purchase_Request__c other = insertRequest('High');
        AMF_McpPreviewRoute.Result preview = previewOf(record.Id);

        AMF_McpSubmitRoute.Result anotherProcess = submitOf(preview.recordId, TWO_LEVEL, preview.submitToken);
        AMF_McpSubmitRoute.Result anotherRecord = submitOf(String.valueOf(other.Id), THREE_LEVEL, preview.submitToken);

        Assert.areEqual(AMF_McpSupport.NOT_PREVIEWED, anotherProcess.summary);
        Assert.areEqual(AMF_McpSupport.NOT_PREVIEWED, anotherRecord.summary);
        assertNothingWritten(record.Id, strategy);
    }

    @IsTest
    static void anExpiredPreviewIsRefused() {
        withKey();
        AMF_StrategyStub strategy = over(highRiskRules());
        Purchase_Request__c record = insertRequest('High');
        Datetime issued = Datetime.now();
        AMF_McpSupport.nowOverride = issued;
        AMF_McpPreviewRoute.Result preview = previewOf(record.Id);

        AMF_McpSupport.nowOverride = issued.addMinutes(AMF_McpSupport.TOKEN_MINUTES + 1);
        AMF_McpSubmitRoute.Result result = submitOf(preview.recordId, preview.selectedProcess, preview.submitToken);

        Assert.areEqual('Refused', result.outcome);
        Assert.areEqual(AMF_McpSupport.EXPIRED, result.summary);
        assertNothingWritten(record.Id, strategy);
    }

    @IsTest
    static void aRouteThatChangedSinceThePreviewIsNotSubmitted() {
        withKey();
        AMF_StrategyStub strategy = over(highRiskRules());
        Purchase_Request__c record = insertRequest('High');
        AMF_McpPreviewRoute.Result preview = previewOf(record.Id);
        update new Purchase_Request__c(Id = record.Id, Risk_Level__c = 'Low');

        AMF_McpSubmitRoute.Result result = submitOf(preview.recordId, preview.selectedProcess, preview.submitToken);

        Assert.isFalse(result.submitted);
        Assert.areEqual('Refused', result.outcome);
        Assert.isTrue(result.routeChanged);
        Assert.isNull(result.selectedProcess, 'No rule matches it now');
        Assert.areEqual(
            'Nothing was submitted. Purchase Request ' + record.Name + ' would now be blocked or fail instead of going to ' +
            THREE_LEVEL + ', because the record or the approval matrix changed after the preview. ' +
            'Preview it again and submit once the user confirms the new route.',
            result.summary
        );
        assertNothingWritten(record.Id, strategy);
    }

    @IsTest
    static void aRouteThatMovedToAnotherProcessSaysWhereItWouldGoNow() {
        withKey();
        AMF_StrategyStub strategy = over(highRiskRules());
        Purchase_Request__c record = insertRequest('High');
        AMF_McpPreviewRoute.Result preview = previewOf(record.Id);

        List<AMF_RuleDefinition> changed = new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder().named('PR_Catch_All').withPriority(9999).withExpression('TRUE').routingTo(TWO_LEVEL).build()
        };
        AMF_AgentPreviewRoute.engineOverride = new AMF_ApprovalMatrixService(new AMF_RuleBuilder.Stub(changed), strategy);

        AMF_McpSubmitRoute.Result result = submitOf(preview.recordId, preview.selectedProcess, preview.submitToken);

        Assert.isTrue(result.routeChanged);
        Assert.areEqual(TWO_LEVEL, result.selectedProcess);
        Assert.areEqual('PR_Catch_All', result.matchedRule);
        Assert.isTrue(
            result.summary.contains('would now go to approval process ' + TWO_LEVEL + ' under rule PR_Catch_All, not ' + THREE_LEVEL),
            result.summary
        );
        assertNothingWritten(record.Id, strategy);
    }

    @IsTest
    static void aBlockedPreviewSubmittedRecordsTheBlockAndStartsNoApproval() {
        withKey();
        AMF_StrategyStub strategy = over(highRiskRules());
        Purchase_Request__c record = insertRequest('Low');
        AMF_McpPreviewRoute.Result preview = previewOf(record.Id);

        AMF_McpSubmitRoute.Result result = submitOf(preview.recordId, '', preview.submitToken);

        Assert.isFalse(result.submitted);
        Assert.areEqual('Blocked_No_Match', result.outcome);
        Assert.isNotNull(result.decisionLogName, 'The blocked attempt is recorded, as the header button records it (M5)');
        Assert.areEqual(0, strategy.calls, 'Nothing was routed');
    }

    @IsTest
    static void anOrgWithNoKeyAndTextThatIsNotAnIdAreAnsweredPlainly() {
        AMF_StrategyStub strategy = over(highRiskRules());
        Purchase_Request__c record = insertRequest('High');

        AMF_McpSubmitRoute.Result notSetUp = submitOf(String.valueOf(record.Id), THREE_LEVEL, '1.ab');
        AMF_McpSubmitRoute.Result notAnId = submitOf(record.Name, THREE_LEVEL, '1.ab');

        Assert.areEqual(AMF_McpSupport.NOT_SET_UP, notSetUp.summary);
        Assert.areEqual('Refused', notAnId.outcome);
        Assert.isTrue(notAnId.summary.contains('is not a Salesforce record Id'), '' + notAnId.summary);
        Assert.isNull(notAnId.recordId);
        assertNothingWritten(record.Id, strategy);
        Assert.areEqual(0, AMF_McpSubmitRoute.submit(null).size());
    }
}
