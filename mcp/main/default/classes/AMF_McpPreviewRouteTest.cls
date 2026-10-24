/**
 * The Claude connector's preview_route tool (M16): the assistant's preview, for
 * a record named as a person names it, with its link and a signed token.
 *
 * Architecture section: 6.4, 7 (its M16 note), 10.
 *
 * Runs over in-memory rules and AMF_StrategyStub through Preview Approval
 * Route's engineOverride and Find Governed Record's ruleProviderOverride seams.
 * What the engine decides is AMF_ApprovalMatrixServiceTest's, and the preview's
 * sentences AMF_AgentPreviewRouteTest's; pinned here is what the facade adds,
 * and that it writes nothing.
 */
@IsTest
private class AMF_McpPreviewRouteTest {

    private static final String THREE_LEVEL = 'PR_Three_Level_Finance';

    private static void over(List<AMF_RuleDefinition> rules) {
        AMF_AgentPreviewRoute.engineOverride = new AMF_ApprovalMatrixService(new AMF_RuleBuilder.Stub(rules), new AMF_StrategyStub());
        AMF_AgentFindRecord.ruleProviderOverride = new AMF_RuleBuilder.Stub(rules);
    }

    private static AMF_RuleDefinition highRisk() {
        return new AMF_RuleBuilder()
            .named('PR_High_Risk')
            .withPriority(20)
            .withExpression('Risk_Level__c == \'High\'')
            .routingTo(THREE_LEVEL)
            .atVersion(2)
            .build();
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

    private static AMF_McpPreviewRoute.Result previewOf(String reference) {
        AMF_McpPreviewRoute.Request request = new AMF_McpPreviewRoute.Request();
        request.record = reference;
        return AMF_McpPreviewRoute.preview(new List<AMF_McpPreviewRoute.Request>{ request })[0];
    }

    @IsTest
    static void previewsARecordNamedByItsNumberWithItsLinkAndASignedToken() {
        withKey();
        over(new List<AMF_RuleDefinition>{ highRisk() });
        Purchase_Request__c record = insertRequest('High');

        Test.startTest();
        AMF_McpPreviewRoute.Result result = previewOf(record.Name);
        Test.stopTest();

        Assert.areEqual('Routable', result.outcome);
        Assert.areEqual(String.valueOf(record.Id), result.recordId);
        Assert.areEqual('Purchase Request ' + record.Name, result.recordLabel);
        Assert.areEqual(AMF_McpSupport.recordUrlOf(record.Id), result.recordUrl);
        Assert.areEqual(THREE_LEVEL, result.selectedProcess);
        Assert.areEqual('PR_High_Risk', result.matchedRule);
        Assert.areEqual(2, result.ruleVersion);
        Assert.areEqual(20, result.rulePriority);
        Assert.areEqual('Risk_Level__c == \'High\'', result.condition);
        Assert.areEqual('Risk Level = High', result.valuesRead);
        Assert.isTrue(result.summary.endsWith('Nothing has been submitted yet.'), '' + result.summary);
        Assert.isTrue(result.canSubmit);
        Assert.isNull(AMF_McpSupport.tokenProblem(result.submitToken, record.Id, THREE_LEVEL), 'The token is for this route');
        Assert.isNull(result.matches);

        Assert.areEqual(0, [SELECT COUNT() FROM Approval_Decision_Log__c], 'A preview writes no decision log row');
        Assert.isFalse(
            [SELECT Matrix_Submission__c FROM Purchase_Request__c WHERE Id = :record.Id].Matrix_Submission__c,
            'A preview sets no guard'
        );
    }

    @IsTest
    static void aBlockedPreviewIsSignedForTheBlockAlone() {
        withKey();
        over(new List<AMF_RuleDefinition>{ highRisk() });
        Purchase_Request__c record = insertRequest('Low');

        AMF_McpPreviewRoute.Result result = previewOf(String.valueOf(record.Id));

        Assert.areEqual('Blocked_No_Match', result.outcome);
        Assert.isTrue(result.canSubmit, 'A block can still be recorded, as the header button records one (M5)');
        Assert.isNull(result.selectedProcess);
        Assert.isNull(AMF_McpSupport.tokenProblem(result.submitToken, record.Id, ''));
        Assert.areEqual(AMF_McpSupport.NOT_PREVIEWED, AMF_McpSupport.tokenProblem(result.submitToken, record.Id, THREE_LEVEL));
    }

    @IsTest
    static void anIdOfAnObjectTheMatrixDoesNotGovernIsNotPreviewed() {
        withKey();
        over(new List<AMF_RuleDefinition>{ highRisk() });
        Account account = new Account(Name = 'Not governed');
        insert account;

        AMF_McpPreviewRoute.Result result = previewOf(String.valueOf(account.Id));

        Assert.areEqual(AMF_McpSupport.NOT_FOUND, result.outcome);
        Assert.isFalse(result.canSubmit);
        Assert.isNull(result.submitToken);
        Assert.isNotNull(result.summary);
    }

    @IsTest
    static void anOrgWithNoKeyStillPreviewsButOffersNoToken() {
        over(new List<AMF_RuleDefinition>{ highRisk() });
        Purchase_Request__c record = insertRequest('High');

        AMF_McpPreviewRoute.Result result = previewOf(record.Name);

        Assert.areEqual('Routable', result.outcome);
        Assert.isTrue(result.canSubmit);
        Assert.isNull(result.submitToken);
    }

    @IsTest
    static void aReferenceThatIsNotOneRecordIsAnsweredNotGuessed() {
        withKey();
        over(new List<AMF_RuleDefinition>{ highRisk() });

        AMF_McpPreviewRoute.Result nothing = previewOf('PR-99999999');

        Assert.areEqual(AMF_McpSupport.NOT_FOUND, nothing.outcome);
        Assert.isFalse(nothing.canSubmit);
        Assert.isNull(nothing.submitToken);
        Assert.isNull(nothing.recordId);
        Assert.isTrue(nothing.summary.contains('PR-99999999'), '' + nothing.summary);

        Assert.areEqual(0, AMF_McpPreviewRoute.preview(null).size());
        Assert.areEqual(1, AMF_McpPreviewRoute.preview(new List<AMF_McpPreviewRoute.Request>{ null }).size());
    }
}
