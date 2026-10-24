/**
 * The Claude connector's what_if_route tool (M16): the assistant's what-if, for
 * a record named as a person names it. Never submittable.
 *
 * Architecture section: 6.4 (its M14 note), 7 (its M16 note), 10.
 *
 * Over in-memory rules through What-If Approval Route's engineOverride and
 * ruleProviderOverride seams, and Find Governed Record's. The comparison's
 * sentences are AMF_AgentWhatIfRouteTest's; pinned here is the facade.
 */
@IsTest
private class AMF_McpWhatIfRouteTest {

    private static final String THREE_LEVEL = 'PR_Three_Level_Finance';
    private static final String TWO_LEVEL = 'PR_Two_Level_Mgmt';

    private static void overShippedShape() {
        List<AMF_RuleDefinition> rules = new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder()
                .named('PR_High_Value_APAC')
                .withPriority(10)
                .withExpression('Amount__c > 100000 && Region__c == \'APAC\'')
                .routingTo(THREE_LEVEL)
                .build(),
            new AMF_RuleBuilder().named('PR_Catch_All').withPriority(9999).withExpression('TRUE').routingTo(TWO_LEVEL).build()
        };
        AMF_AgentWhatIfRoute.engineOverride = new AMF_ApprovalMatrixService(new AMF_RuleBuilder.Stub(rules), new AMF_StrategyStub());
        AMF_AgentWhatIfRoute.ruleProviderOverride = new AMF_RuleBuilder.Stub(rules);
        AMF_AgentFindRecord.ruleProviderOverride = new AMF_RuleBuilder.Stub(rules);
    }

    private static AMF_McpWhatIfRoute.Result tryOne(String reference, String changes) {
        AMF_McpWhatIfRoute.Request request = new AMF_McpWhatIfRoute.Request();
        request.record = reference;
        request.changes = changes;
        return AMF_McpWhatIfRoute.whatIf(new List<AMF_McpWhatIfRoute.Request>{ request })[0];
    }

    @IsTest
    static void triesTheValuesOnARecordNamedByItsNumberAndChangesNothing() {
        overShippedShape();
        Purchase_Request__c record = new Purchase_Request__c(Amount__c = 5000, Region__c = 'EMEA', Risk_Level__c = 'Low');
        insert record;
        String prNumber = [SELECT Name FROM Purchase_Request__c WHERE Id = :record.Id].Name;

        Test.startTest();
        AMF_McpWhatIfRoute.Result result = tryOne(prNumber, 'Amount = 120000; Region = APAC');
        Test.stopTest();

        Assert.areEqual('Routable', result.outcome, '' + result.summary);
        Assert.isTrue(result.routeChanged);
        Assert.areEqual(THREE_LEVEL, result.selectedProcess);
        Assert.areEqual('PR_High_Value_APAC', result.matchedRule);
        Assert.areEqual(TWO_LEVEL, result.currentProcess);
        Assert.areEqual('PR_Catch_All', result.currentRule);
        Assert.areEqual(String.valueOf(record.Id), result.recordId);
        Assert.areEqual('Purchase Request ' + prNumber, result.recordLabel);
        Assert.areEqual(AMF_McpSupport.recordUrlOf(record.Id), result.recordUrl);
        Assert.isTrue(result.summary.contains('This is only a what-if: nothing was changed or submitted.'), '' + result.summary);

        Purchase_Request__c stored = [SELECT Amount__c, Region__c, Matrix_Submission__c FROM Purchase_Request__c WHERE Id = :record.Id];
        Assert.areEqual(5000, stored.Amount__c, 'Nothing was changed');
        Assert.areEqual('EMEA', stored.Region__c);
        Assert.isFalse(stored.Matrix_Submission__c, 'Nothing was submitted');
        Assert.areEqual(0, [SELECT COUNT() FROM Approval_Decision_Log__c], 'Nothing was recorded');
    }

    @IsTest
    static void aReferenceThatIsNotOneRecordIsAnsweredNotGuessed() {
        overShippedShape();

        AMF_McpWhatIfRoute.Result result = tryOne('PR-99999999', 'Amount = 1');

        Assert.areEqual(AMF_McpSupport.NOT_FOUND, result.outcome);
        Assert.isFalse(result.routeChanged);
        Assert.isNull(result.recordId);
        Assert.isTrue(result.summary.contains('PR-99999999'), '' + result.summary);
        Assert.areEqual(0, AMF_McpWhatIfRoute.whatIf(null).size());
    }
}
