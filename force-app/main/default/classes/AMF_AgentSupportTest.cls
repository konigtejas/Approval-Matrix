/**
 * What the assistant's actions share (M13): reading an Id the model passes as
 * text, and writing recorded values as a sentence.
 *
 * Architecture section: 7 (its M13 note), 8 (values read as the timeline shows them), 10.
 */
@IsTest
private class AMF_AgentSupportTest {

    @IsTest
    static void readsAnIdInEitherLengthAndNothingElse() {
        Account account = new Account(Name = 'Any record');
        insert account;
        String eighteen = String.valueOf(account.Id);

        Assert.areEqual(account.Id, AMF_AgentSupport.idOf(eighteen));
        Assert.areEqual(account.Id, AMF_AgentSupport.idOf('  ' + eighteen.left(15) + ' '), 'Trimmed, and 15 characters accepted');

        Assert.isNull(AMF_AgentSupport.idOf(null));
        Assert.isNull(AMF_AgentSupport.idOf('   '));
        Assert.isNull(AMF_AgentSupport.idOf('PR-00000045'), 'A record number is not an Id');
        Assert.isNull(AMF_AgentSupport.idOf('this is eighteen!!'), 'Eighteen characters, not an Id');
        Assert.isNull(AMF_AgentSupport.idOf('zz9000000000001'), 'Shaped like an Id, of no object in this org');
    }

    @IsTest
    static void saysWhyTextCannotBeUsedAsARecord() {
        Assert.areEqual(
            'no record was given. Open the record, or say its name or number so that it can be looked up.',
            AMF_AgentSupport.notAnId(' ')
        );
        Assert.areEqual(
            '"PR-45" is not a Salesforce record Id. Look the record up by its name or number first.',
            AMF_AgentSupport.notAnId(' PR-45 ')
        );
        Assert.isTrue(AMF_AgentSupport.notAnId('x'.repeat(200)).startsWith('"' + 'x'.repeat(77) + '..."'));
    }

    @IsTest
    static void endsAReasonAsASentenceOnce() {
        Assert.areEqual('Refused.', AMF_AgentSupport.asSentence('Refused'));
        Assert.areEqual('Refused.', AMF_AgentSupport.asSentence(' Refused. '));
        Assert.areEqual('Really?', AMF_AgentSupport.asSentence('Really?'));
        Assert.areEqual('Stop!', AMF_AgentSupport.asSentence('Stop!'));
        Assert.areEqual('No reason was given.', AMF_AgentSupport.asSentence(null));
    }

    @IsTest
    static void writesRecordedValuesAsTheTimelineLabelsThem() {
        Schema.SObjectType request = Purchase_Request__c.SObjectType;
        String amount = Purchase_Request__c.Amount__c.getDescribe().getLabel();
        String region = Purchase_Request__c.Region__c.getDescribe().getLabel();
        String risk = Purchase_Request__c.Risk_Level__c.getDescribe().getLabel();

        Assert.isNull(AMF_AgentSupport.sentenceOf(null, request), 'Nothing read');
        Assert.isNull(AMF_AgentSupport.sentenceOf('{}', request), 'A catch-all reads nothing');
        Assert.areEqual(risk + ' = Medium', AMF_AgentSupport.sentenceOf('{"Risk_Level__c":"Medium"}', request));
        Assert.areEqual(
            amount + ' = ' + Decimal.valueOf(60000).format() + ' and ' + risk + ' = Medium',
            AMF_AgentSupport.sentenceOf('{"Amount__c":60000.00,"Risk_Level__c":"Medium"}', request)
        );
        Assert.areEqual(
            amount + ' = ' + Decimal.valueOf(60000).format() + ', ' + region + ' = (blank) and Gone__c = x',
            AMF_AgentSupport.sentenceOf('{"Amount__c":60000,"Region__c":null,"Gone__c":"x"}', request),
            'A blank says so, and a path that no longer resolves reads as recorded'
        );
        Assert.areEqual('not json', AMF_AgentSupport.sentenceOf('not json', request), 'An unreadable snapshot, as recorded');
    }

    @IsTest
    static void namesSeveralRecordsApproversAndTimesAsTheListsWriteThem() {
        Purchase_Request__c record = new Purchase_Request__c(Amount__c = 500, Region__c = 'EMEA', Risk_Level__c = 'Low');
        insert record;
        Id missing = Id.valueOf(Purchase_Request__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001');
        Group queue = new Group(Name = 'AMF Support Queue', Type = 'Queue');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert queue;
        }

        Integer before = Limits.getQueries();
        Map<Id, String> labels = AMF_AgentSupport.labelsOf(new Set<Id>{ record.Id, missing, null });
        Assert.areEqual(1, Limits.getQueries() - before, 'One query for the object, however many records');

        Assert.areEqual(
            'Purchase Request ' + [SELECT Name FROM Purchase_Request__c WHERE Id = :record.Id].Name,
            labels.get(record.Id)
        );
        Assert.areEqual('Purchase Request ' + missing, labels.get(missing), 'A record that cannot be read is named by its Id');

        Map<Id, String> names = AMF_AgentSupport.actorNamesOf(new Set<Id>{ UserInfo.getUserId(), queue.Id });
        Assert.areEqual(UserInfo.getName(), names.get(UserInfo.getUserId()));
        Assert.areEqual('AMF Support Queue', names.get(queue.Id));
        Assert.isTrue(AMF_AgentSupport.actorNamesOf(null).isEmpty());

        Datetime nine = Datetime.newInstanceGmt(2026, 10, 23, 9, 5, 0);
        Assert.areEqual(nine.format('d MMM yyyy, HH:mm'), AMF_AgentSupport.whenOf(nine));
        Assert.areEqual('an unknown time', AMF_AgentSupport.whenOf(null));
    }

    @IsTest
    static void namesAGovernedObjectAsAPersonNamesIt() {
        AMF_RuleBuilder.Stub rules = new AMF_RuleBuilder.Stub(
            new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder().named('PR_Catch_All').withPriority(9999).withExpression('TRUE').routingTo('PR_Two_Level_Mgmt').build(),
                new AMF_RuleBuilder().named('OPP_Catch_All').forObject('Opportunity').withPriority(9999).withExpression('TRUE').routingTo('OPP_Manager_Approval').build()
            }
        );

        Assert.areEqual('Purchase_Request__c', AMF_AgentSupport.governedObjectNamed(' purchase requests ', rules), 'Plural label');
        Assert.areEqual('Purchase_Request__c', AMF_AgentSupport.governedObjectNamed('Purchase Request', rules), 'Label');
        Assert.areEqual('Opportunity', AMF_AgentSupport.governedObjectNamed('OPPORTUNITY', rules), 'API name, in any case');
        Assert.isNull(AMF_AgentSupport.governedObjectNamed('Account', rules), 'An object the matrix does not govern');
        Assert.isNull(AMF_AgentSupport.governedObjectNamed(null, rules));
    }
}
