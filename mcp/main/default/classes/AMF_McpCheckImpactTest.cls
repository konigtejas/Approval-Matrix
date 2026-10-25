/**
 * The Claude connector's check_change_impact tool (M16, administrators): the
 * Admin Assistant's Check Rule Impact, with the priority as a number.
 *
 * Architecture section: 6.4 (its M15 note), 7 (its M15 and M16 notes), 10.
 *
 * Over in-memory rules through Check Rule Impact's ruleProviderOverride seam.
 * The comparison is AMF_MatrixImpactTest's subject.
 */
@IsTest
private class AMF_McpCheckImpactTest {

    private static final String TWO_LEVEL = 'PR_Two_Level_Mgmt';

    @IsTest
    static void comparesRecentDecisionsUnderTheChangeAndWritesNothing() {
        AMF_AgentCheckImpact.ruleProviderOverride = new AMF_RuleBuilder.Stub(
            new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder().named('PR_Catch_All').withPriority(9999).withExpression('TRUE').routingTo(TWO_LEVEL).build()
            }
        );
        List<Purchase_Request__c> records = new List<Purchase_Request__c>{
            new Purchase_Request__c(Amount__c = 600000, Region__c = 'EMEA', Risk_Level__c = 'Low'),
            new Purchase_Request__c(Amount__c = 500, Region__c = 'EMEA', Risk_Level__c = 'Low')
        };
        insert records;
        List<Approval_Decision_Log__c> rows = new List<Approval_Decision_Log__c>();
        for (Purchase_Request__c record : records) {
            rows.add(
                new Approval_Decision_Log__c(
                    Record_Id__c = String.valueOf(record.Id),
                    Object_API_Name__c = 'Purchase_Request__c',
                    Outcome__c = 'Submitted',
                    Matched_Rule__c = 'PR_Catch_All',
                    Expression_Snapshot__c = 'TRUE',
                    Selected_Process__c = TWO_LEVEL,
                    Submitted_By__c = UserInfo.getUserId(),
                    Submitted_At__c = Datetime.now().addDays(-1)
                )
            );
        }
        insert rows;

        AMF_McpCheckImpact.Request request = new AMF_McpCheckImpact.Request();
        request.objectName = 'Purchase Request';
        request.ruleName = 'PR_EMEA_Large';
        request.priority = 15;
        request.expression = 'Amount__c > 500000 && Region__c == \'EMEA\'';
        request.processApiName = 'PR_Finance_Committee';

        Test.startTest();
        AMF_McpCheckImpact.Result result = AMF_McpCheckImpact.checkImpact(new List<AMF_McpCheckImpact.Request>{ request })[0];
        Test.stopTest();

        Assert.isTrue(result.ran, '' + result.summary);
        Assert.areEqual(2, result.checked);
        Assert.areEqual(1, result.changed);
        Assert.areEqual(0, result.skipped);
        Assert.isTrue(result.changes.contains('PR_Finance_Committee'), '' + result.changes);
        Assert.areEqual(2, [SELECT COUNT() FROM Approval_Decision_Log__c], 'Nothing recorded');
        Assert.areEqual(0, AMF_McpCheckImpact.checkImpact(null).size());
    }
}
