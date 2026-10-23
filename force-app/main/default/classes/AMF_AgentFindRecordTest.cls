/**
 * The assistant's Find Governed Record action (M13): from what a user calls a
 * record to its Id, among the governed records they can see.
 *
 * Architecture section: 3.2 (governed means the object has active rules), 7
 * (its M13 note), 10.
 *
 * The governed objects come from in-memory rules through the action's
 * ruleProviderOverride seam, as CLAUDE.md requires of every test. The search
 * index is empty in an Apex test unless Test.setFixedSearchResults fills it,
 * which is how the search pass is exercised.
 */
@IsTest
private class AMF_AgentFindRecordTest {

    private static void governing(List<String> objectApiNames) {
        List<AMF_RuleDefinition> rules = new List<AMF_RuleDefinition>();
        Integer priority = 10;
        for (String objectApiName : objectApiNames) {
            rules.add(new AMF_RuleBuilder().named('Rule_' + priority).forObject(objectApiName).withPriority(priority++).build());
        }
        AMF_AgentFindRecord.ruleProviderOverride = new AMF_RuleBuilder.Stub(rules);
    }

    private static void governingBoth() {
        governing(new List<String>{ 'Purchase_Request__c', 'Opportunity' });
    }

    private static Purchase_Request__c insertRequest(String requestName) {
        Purchase_Request__c record = new Purchase_Request__c(
            Amount__c = 60000,
            Region__c = 'APAC',
            Risk_Level__c = 'Medium',
            Request_Name__c = requestName
        );
        insert record;
        return [SELECT Id, Name FROM Purchase_Request__c WHERE Id = :record.Id];
    }

    private static Opportunity insertDeal(String name) {
        Opportunity deal = new Opportunity(Name = name, StageName = 'Prospecting', CloseDate = Date.today().addDays(30));
        insert deal;
        return deal;
    }

    private static String prLabel() {
        return Purchase_Request__c.SObjectType.getDescribe().getLabel();
    }

    private static AMF_AgentFindRecord.Result find(String searchText) {
        AMF_AgentFindRecord.Request request = new AMF_AgentFindRecord.Request();
        request.searchText = searchText;
        return AMF_AgentFindRecord.find(new List<AMF_AgentFindRecord.Request>{ request })[0];
    }

    @IsTest
    static void findsARequestByItsNumberExactly() {
        governingBoth();
        Purchase_Request__c record = insertRequest(null);
        insertRequest(null);

        Test.startTest();
        AMF_AgentFindRecord.Result result = find('  ' + record.Name + ' ');
        Test.stopTest();

        Assert.areEqual(1, result.matchCount);
        Assert.areEqual(String.valueOf(record.Id), result.recordId);
        Assert.areEqual(prLabel() + ' ' + record.Name, result.recordLabel);
        Assert.areEqual('Found ' + prLabel() + ' ' + record.Name + '.', result.message);
        Assert.isNull(result.matches);
    }

    @IsTest
    static void findsARecordByItsId() {
        governingBoth();
        Opportunity deal = insertDeal('DEMO Energy deal');

        AMF_AgentFindRecord.Result result = find(String.valueOf(deal.Id).left(15));

        Assert.areEqual(1, result.matchCount);
        Assert.areEqual(String.valueOf(deal.Id), result.recordId);
        Assert.areEqual('Opportunity DEMO Energy deal', result.recordLabel);
    }

    @IsTest
    static void saysWhenAnIdBelongsToAnObjectTheMatrixDoesNotGovern() {
        governingBoth();
        Account account = new Account(Name = 'Not governed');
        insert account;

        AMF_AgentFindRecord.Result result = find(account.Id);

        Assert.areEqual(0, result.matchCount);
        Assert.isNull(result.recordId);
        Assert.areEqual('That Id belongs to the Account object, which the approval matrix does not govern.', result.message);
    }

    @IsTest
    static void findsARequestByItsRequestNameThroughTheSearchIndex() {
        governingBoth();
        Purchase_Request__c record = insertRequest('Laptops for the APAC team');
        Test.setFixedSearchResults(new List<Id>{ record.Id });

        AMF_AgentFindRecord.Result result = find('APAC laptops');

        Assert.areEqual(1, result.matchCount);
        Assert.areEqual(String.valueOf(record.Id), result.recordId);
    }

    @IsTest
    static void listsSeveralMatchesForTheUserToChooseFromInsteadOfGuessing() {
        governingBoth();
        Opportunity laptops = insertDeal('Acme Laptop Refresh');
        Opportunity servers = insertDeal('Acme Server Upgrade');

        AMF_AgentFindRecord.Result result = find('Acme');

        Assert.areEqual(2, result.matchCount);
        Assert.isNull(result.recordId, 'Choosing between them is the user\'s call');
        Assert.areEqual('2 records match "Acme". Ask which one is meant.', result.message);
        Assert.areEqual(
            '1. Opportunity Acme Laptop Refresh (Id ' + laptops.Id + ')\n2. Opportunity Acme Server Upgrade (Id ' + servers.Id + ')',
            result.matches
        );
    }

    @IsTest
    static void listsAtMostFiveAndSaysThereAreMore() {
        governingBoth();
        List<Opportunity> deals = new List<Opportunity>();
        for (Integer i = 1; i <= AMF_AgentFindRecord.MAX_MATCHES + 2; i++) {
            deals.add(new Opportunity(Name = 'Bulk deal ' + i, StageName = 'Prospecting', CloseDate = Date.today()));
        }
        insert deals;

        AMF_AgentFindRecord.Result result = find('Bulk deal');

        Assert.areEqual(AMF_AgentFindRecord.MAX_MATCHES + 1, result.matchCount, 'One past the list, to know there are more');
        Assert.areEqual('More than 5 records match "Bulk deal". Ask which one is meant.', result.message);
        Assert.areEqual(AMF_AgentFindRecord.MAX_MATCHES, result.matches.split('\n').size());
    }

    @IsTest
    static void saysPlainlyWhenNothingMatchesAndNamesWhatWasSearched() {
        governingBoth();
        insertDeal('Something else');

        AMF_AgentFindRecord.Result result = find('Nothing like this');

        Assert.areEqual(0, result.matchCount);
        Assert.areEqual(
            'No Opportunity or ' + prLabel() + ' that you can see matches "Nothing like this". Check the name or ' +
            'number, or open the record and ask again.',
            result.message
        );
    }

    @IsTest
    static void searchesOnlyTheObjectsTheMatrixGoverns() {
        governing(new List<String>{ 'Purchase_Request__c' });
        insertDeal('Acme Laptop Refresh');

        AMF_AgentFindRecord.Result result = find('Acme Laptop Refresh');

        Assert.areEqual(0, result.matchCount, 'Opportunity has no active rules here, so it is not governed (3.2)');
    }

    @IsTest
    static void treatsSearchSyntaxAndWildcardsAsPlainText() {
        governingBoth();
        insertDeal('50% off (sale)');
        insertDeal('500 off sale');

        AMF_AgentFindRecord.Result result = find('50% off (sale)');

        Assert.areEqual(1, result.matchCount, 'The % matched itself, not any text');
        Assert.areEqual('Opportunity 50% off (sale)', result.recordLabel);
        Assert.areEqual(0, find('x*y?{z}[w]"\'+-!').matchCount, 'Reserved characters are searched for, not parsed');
        Assert.areEqual(0, find('q').matchCount, 'A one-character term skips the search index and still answers');
    }

    @IsTest
    static void asksWhichRecordWhenGivenNothing() {
        governingBoth();

        AMF_AgentFindRecord.Result result = find('   ');

        Assert.areEqual(0, result.matchCount);
        Assert.areEqual('Say which record you mean: its name, number or Id.', result.message);
        Assert.isTrue(AMF_AgentFindRecord.find(null).isEmpty());
    }

    @IsTest
    static void saysSoWhenTheMatrixGovernsNothing() {
        governing(new List<String>());

        Assert.areEqual(
            'The approval matrix governs no objects yet, so there is nothing to find.',
            find('PR-00000001').message
        );
    }

    @IsTest
    static void leavesOutAGovernedObjectThatNoLongerExists() {
        governing(new List<String>{ 'Purchase_Request__c', 'Gone__c' });
        Purchase_Request__c record = insertRequest(null);

        AMF_AgentFindRecord.Result result = find(record.Name);

        Assert.areEqual(1, result.matchCount);
        Assert.isTrue(find('nothing').message.startsWith('No ' + prLabel() + ' that you can see'), 'Gone__c is not named');
    }
}
