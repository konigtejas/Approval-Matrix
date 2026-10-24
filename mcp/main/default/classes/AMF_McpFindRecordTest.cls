/**
 * The Claude connector's find_record tool (M16): Find Governed Record, with a
 * link for a single match and an outcome an MCP client can branch on.
 *
 * Architecture section: 7 (its M13 and M16 notes), 10.
 *
 * Over in-memory rules through Find Governed Record's ruleProviderOverride
 * seam. How records are matched is AMF_AgentFindRecordTest's subject.
 */
@IsTest
private class AMF_McpFindRecordTest {

    private static void governingBoth() {
        AMF_AgentFindRecord.ruleProviderOverride = new AMF_RuleBuilder.Stub(
            new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder().named('Rule_10').withPriority(10).build(),
                new AMF_RuleBuilder().named('Rule_11').forObject('Opportunity').withPriority(11).build()
            }
        );
    }

    private static AMF_McpFindRecord.Result findOne(String searchText) {
        AMF_McpFindRecord.Request request = new AMF_McpFindRecord.Request();
        request.searchText = searchText;
        return AMF_McpFindRecord.find(new List<AMF_McpFindRecord.Request>{ request })[0];
    }

    @IsTest
    static void findsOneRecordWithItsLink() {
        governingBoth();
        Purchase_Request__c record = new Purchase_Request__c(Amount__c = 5000, Region__c = 'EMEA', Risk_Level__c = 'Low');
        insert record;
        String prNumber = [SELECT Name FROM Purchase_Request__c WHERE Id = :record.Id].Name;

        AMF_McpFindRecord.Result result = findOne(prNumber);

        Assert.areEqual(AMF_McpSupport.FOUND, result.outcome);
        Assert.areEqual(1, result.matchCount);
        Assert.areEqual(String.valueOf(record.Id), result.recordId);
        Assert.areEqual('Purchase Request ' + prNumber, result.recordLabel);
        Assert.areEqual(AMF_McpSupport.recordUrlOf(record.Id), result.recordUrl);
        Assert.isNotNull(result.message);
    }

    @IsTest
    static void listsSeveralMatchesAndSaysWhenThereAreNone() {
        governingBoth();
        insert new List<Opportunity>{
            new Opportunity(Name = 'Acme Laptop Refresh', StageName = 'Prospecting', CloseDate = Date.today().addDays(30)),
            new Opportunity(Name = 'Acme Server Upgrade', StageName = 'Prospecting', CloseDate = Date.today().addDays(30))
        };

        AMF_McpFindRecord.Result several = findOne('Acme');
        AMF_McpFindRecord.Result none = findOne('Nothing Like It');

        Assert.areEqual(AMF_McpSupport.AMBIGUOUS, several.outcome);
        Assert.areEqual(2, several.matchCount);
        Assert.isNull(several.recordId);
        Assert.isNull(several.recordUrl);
        Assert.isTrue(several.matches.contains('Acme Server Upgrade'), '' + several.matches);

        Assert.areEqual(AMF_McpSupport.NOT_FOUND, none.outcome);
        Assert.isNull(none.recordUrl);
        Assert.isTrue(none.message.contains('Nothing Like It'), '' + none.message);

        Assert.areEqual(0, AMF_McpFindRecord.find(null).size());
    }
}
