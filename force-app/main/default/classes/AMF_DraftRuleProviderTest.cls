/**
 * The live matrix with one change (M15): a rule added, a new version of a rule,
 * a rule taken out -- and the change it refuses.
 *
 * Architecture section: 3.1, 6.4 (its M15 note), 10.
 */
@IsTest
private class AMF_DraftRuleProviderTest {

    private static List<AMF_RuleDefinition> live() {
        return new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder().named('PR_High_Risk').withPriority(20).withExpression('Risk_Level__c == \'High\'').routingTo('PR_Three_Level_Finance').atVersion(2).build(),
            new AMF_RuleBuilder().named('PR_Catch_All').withPriority(9999).withExpression('TRUE').routingTo('PR_Two_Level_Mgmt').build(),
            new AMF_RuleBuilder().named('OPP_Catch_All').forObject('Opportunity').withPriority(9999).withExpression('TRUE').routingTo('OPP_Manager_Approval').build()
        };
    }

    private static List<String> namesOf(List<AMF_RuleDefinition> rules) {
        List<String> names = new List<String>();
        for (AMF_RuleDefinition rule : rules) {
            names.add(rule.developerName + ' v' + rule.version);
        }
        return names;
    }

    @IsTest
    static void addsARuleInPriorityOrderForItsObjectOnly() {
        AMF_RuleDefinition added = new AMF_RuleBuilder()
            .named('PR_EMEA_Large')
            .withPriority(15)
            .withExpression('Amount__c > 500000 && Region__c == \'EMEA\'')
            .routingTo('PR_Finance_Committee')
            .build();
        AMF_DraftRuleProvider draft = new AMF_DraftRuleProvider(new AMF_RuleBuilder.Stub(live()), null, added);

        Assert.areEqual(
            new List<String>{ 'PR_EMEA_Large v1', 'PR_High_Risk v2', 'PR_Catch_All v1' },
            namesOf(draft.getActiveRules('Purchase_Request__c'))
        );
        Assert.areEqual(new List<String>{ 'OPP_Catch_All v1' }, namesOf(draft.getActiveRules('Opportunity')), 'Other objects untouched');
        Assert.areEqual(4, draft.getActiveRules().size(), 'Every object, with the change');
    }

    @IsTest
    static void replacesARuleWithItsNewVersionAndTakesOneOut() {
        AMF_RuleDefinition version3 = new AMF_RuleBuilder()
            .named('PR_High_Risk')
            .withPriority(25)
            .withExpression('Risk_Level__c IN (\'High\', \'Medium\')')
            .routingTo('PR_Three_Level_Finance')
            .atVersion(3)
            .build();

        AMF_DraftRuleProvider replaced = new AMF_DraftRuleProvider(new AMF_RuleBuilder.Stub(live()), 'PR_High_Risk', version3);
        List<AMF_RuleDefinition> rules = replaced.getActiveRules('Purchase_Request__c');
        Assert.areEqual(new List<String>{ 'PR_High_Risk v3', 'PR_Catch_All v1' }, namesOf(rules));
        Assert.areEqual(25, rules[0].priority, 'The new version, not the live one');

        AMF_DraftRuleProvider takenOut = new AMF_DraftRuleProvider(new AMF_RuleBuilder.Stub(live()), 'PR_High_Risk', null);
        Assert.areEqual(new List<String>{ 'PR_Catch_All v1' }, namesOf(takenOut.getActiveRules('Purchase_Request__c')));
    }

    @IsTest
    static void refusesNoChangeAndANewVersionAtTheLiveVersion() {
        // AMF_ExprCache keys on DeveloperName and version: the same version would
        // be served the live rule's compiled expression.
        AMF_RuleDefinition sameVersion = new AMF_RuleBuilder()
            .named('PR_High_Risk')
            .withPriority(20)
            .withExpression('Risk_Level__c == \'Medium\'')
            .routingTo('PR_Three_Level_Finance')
            .atVersion(2)
            .build();

        try {
            new AMF_DraftRuleProvider(new AMF_RuleBuilder.Stub(live()), 'PR_High_Risk', sameVersion);
            Assert.fail('A replacement must carry a new version');
        } catch (AMF_ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('version other than the live one, 2'), e.getMessage());
        }

        try {
            new AMF_DraftRuleProvider(new AMF_RuleBuilder.Stub(live()), ' ', null);
            Assert.fail('No change');
        } catch (AMF_ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('needs a rule'), e.getMessage());
        }
    }
}
