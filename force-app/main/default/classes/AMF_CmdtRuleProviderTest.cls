/**
 * Unit test for AMF_CmdtRuleProvider, and the home of Phase M1's headline gate.
 *
 * Architecture section: 3.1, 10.
 *
 * Two kinds of test live here, deliberately labelled:
 *
 *  1. The SOQL-versus-getAll pin. This is the ONE place in the package allowed to
 *     read a deployed Custom Metadata row, because it proves a platform
 *     behaviour -- Long Text Area truncation -- that no in-memory fixture can
 *     demonstrate. It reads PR_Long_Expression_Pin, which ships in this repo,
 *     is inactive by design, and therefore routes nothing.
 *  2. Contract tests, asserted against both AMF_RuleProvider implementations, so
 *     the in-memory stub every later phase relies on cannot quietly drift from
 *     the real provider.
 *
 * If longExpressionSurvivesSoqlLoad ever passes while AMF_CmdtRuleProvider uses
 * getAll(), the test is wrong -- which is exactly what
 * getAllTruncatesWhereSoqlDoesNot exists to make impossible.
 */
@IsTest
private class AMF_CmdtRuleProviderTest {

    private static final String GOVERNED_OBJECT = 'Purchase_Request__c';
    private static final String PIN_RULE = 'PR_Long_Expression_Pin';

    /**
     * The pin fixture's expression, reproduced here character for character.
     * Duplication is the point: if someone edits the CMDT record, this test
     * fails and tells them the pin moved.
     */
    private static final String PIN_EXPRESSION =
        '(Amount__c > 100000 && Region__c == \'APAC\')'
        + ' || (Amount__c > 250000 && Region__c == \'EMEA\')'
        + ' || (Amount__c > 500000 && Region__c == \'AMER\')'
        + ' || (Risk_Level__c == \'High\' && Amount__c > 50000)'
        + ' || (Risk_Level__c == \'Medium\' && Amount__c > 150000)'
        + ' || (Risk_Level__c == \'Low\' && Amount__c > 750000)';

    /**
     * PHASE M1 GATE. A Long Text Area expression longer than 255 characters must
     * survive the trip through the provider intact.
     */
    @IsTest
    static void longExpressionSurvivesSoqlLoad() {
        Assert.isTrue(
            PIN_EXPRESSION.length() > 255,
            'The fixture itself must exceed 255 characters or this test proves nothing; it is '
                + PIN_EXPRESSION.length()
        );

        List<AMF_RuleDefinition> rules = AMF_CmdtRuleProvider.load(GOVERNED_OBJECT, false);
        AMF_RuleDefinition pin = ruleNamed(rules, PIN_RULE);

        Assert.isNotNull(
            pin,
            'PR_Long_Expression_Pin must be deployed; it ships in force-app/main/default/customMetadata'
        );
        Assert.areEqual(
            PIN_EXPRESSION.length(),
            pin.expression.length(),
            'Expression__c came back a different length, which is what Long Text Area truncation looks like'
        );
        Assert.areEqual(
            PIN_EXPRESSION,
            pin.expression,
            'Expression__c must round trip through the provider byte for byte'
        );
    }

    /**
     * The negative half of the gate: proves the truncation being guarded against
     * is real in this org and this API version, rather than folklore inherited
     * from the architecture doc.
     */
    @IsTest
    static void getAllTruncatesWhereSoqlDoesNot() {
        Approval_Matrix_Rule__mdt viaGetAll = Approval_Matrix_Rule__mdt.getAll().get(PIN_RULE);
        Approval_Matrix_Rule__mdt viaGetInstance = Approval_Matrix_Rule__mdt.getInstance(PIN_RULE);

        Assert.isNotNull(viaGetAll, 'The pin record must be readable by getAll to make this comparison');

        Assert.areEqual(
            255,
            viaGetAll.Expression__c.length(),
            'getAll() is expected to truncate Long Text Area at 255 characters'
        );
        Assert.areEqual(
            255,
            viaGetInstance.Expression__c.length(),
            'getInstance() truncates identically to getAll()'
        );
        Assert.areNotEqual(
            PIN_EXPRESSION,
            viaGetAll.Expression__c,
            'getAll() must NOT return the full expression, or the SOQL requirement would be pointless'
        );

        List<AMF_RuleDefinition> rules = AMF_CmdtRuleProvider.load(GOVERNED_OBJECT, false);
        Assert.areEqual(
            PIN_EXPRESSION,
            ruleNamed(rules, PIN_RULE).expression,
            'The provider must return what getAll() could not'
        );
    }

    /**
     * The same gate on the configuration-wide path the M4 validator reads. A
     * second query is a second place truncation could creep back in.
     */
    @IsTest
    static void longExpressionSurvivesTheConfigurationWideLoad() {
        AMF_RuleDefinition pin = ruleNamed(AMF_CmdtRuleProvider.loadAll(false), PIN_RULE);

        Assert.isNotNull(
            pin,
            'PR_Long_Expression_Pin must be deployed; it ships in force-app/main/default/customMetadata'
        );
        Assert.areEqual(
            PIN_EXPRESSION,
            pin.expression,
            'Expression__c must round trip through the configuration-wide load byte for byte'
        );
    }

    @IsTest
    static void cmdtProviderHonoursTheProviderContract() {
        assertProviderContract(new AMF_CmdtRuleProvider(), GOVERNED_OBJECT);
    }

    @IsTest
    static void cmdtProviderHonoursTheConfigurationWideContract() {
        List<AMF_RuleDefinition> active = new AMF_CmdtRuleProvider().getActiveRules();

        assertConfigurationWideContract(active);
        Assert.isNull(
            ruleNamed(active, PIN_RULE),
            'PR_Long_Expression_Pin is Active__c = false, so the validator must never see it'
        );
        Assert.isNotNull(
            ruleNamed(active, 'PR_Catch_All'),
            'The configuration-wide read must include the shipped active rules'
        );
    }

    @IsTest
    static void stubHonoursTheSameConfigurationWideContract() {
        AMF_RuleProvider stub = new AMF_RuleBuilder.Stub(new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder().named('Catch_All').withPriority(9999).build(),
            new AMF_RuleBuilder().named('Switched_Off').withPriority(1).inactive().build(),
            new AMF_RuleBuilder().named('Other_Object').withPriority(5).forObject('Account').build(),
            null
        });

        List<AMF_RuleDefinition> active = stub.getActiveRules();

        assertConfigurationWideContract(active);
        Assert.areEqual(
            new List<String>{ 'Other_Object', 'Catch_All' },
            namesOf(active),
            'The stub must keep every object\'s active rules and drop the inactive and null entries'
        );
    }

    @IsTest
    static void stubHonoursTheSameContractAsTheRealProvider() {
        AMF_RuleProvider stub = new AMF_RuleBuilder.Stub(new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder().named('Catch_All').withPriority(9999).build(),
            new AMF_RuleBuilder().named('Tie_B').withPriority(50).build(),
            new AMF_RuleBuilder().named('Tie_A').withPriority(50).build(),
            new AMF_RuleBuilder().named('Switched_Off').withPriority(1).inactive().build(),
            new AMF_RuleBuilder().named('Other_Object').withPriority(1).forObject('Account').build()
        });

        assertProviderContract(stub, GOVERNED_OBJECT);

        Assert.areEqual(
            new List<String>{ 'Tie_A', 'Tie_B', 'Catch_All' },
            namesOf(stub.getActiveRules(GOVERNED_OBJECT)),
            'The stub must drop the inactive rule and the other object\'s rule, and break the tie on name'
        );
    }

    @IsTest
    static void activeRulesExcludeTheInactivePin() {
        List<AMF_RuleDefinition> active = new AMF_CmdtRuleProvider().getActiveRules(GOVERNED_OBJECT);

        Assert.isNull(
            ruleNamed(active, PIN_RULE),
            'PR_Long_Expression_Pin is Active__c = false, so it must never reach the engine'
        );
        Assert.isNotNull(
            ruleNamed(active, 'PR_Catch_All'),
            'The shipped catch-all rule must be active, or nothing routes by default'
        );
    }

    @IsTest
    static void shippedMatrixComesBackInPriorityOrder() {
        List<String> names = namesOf(new AMF_CmdtRuleProvider().getActiveRules(GOVERNED_OBJECT));

        Assert.areEqual(
            'PR_Catch_All',
            names[names.size() - 1],
            'The priority-9999 catch-all must sort last, or it would shadow every specific rule'
        );
        Assert.areEqual(
            'PR_High_Value_APAC',
            names[0],
            'The priority-10 rule must be evaluated first'
        );
    }

    @IsTest
    static void unknownObjectReturnsEmptyRatherThanNull() {
        List<AMF_RuleDefinition> rules =
            new AMF_CmdtRuleProvider().getActiveRules('Definitely_Not_An_Object__c');

        Assert.isNotNull(rules, 'An ungoverned object returns an empty list, never null');
        Assert.areEqual(0, rules.size(), 'An ungoverned object has no rules');
    }

    /**
     * Every AMF_RuleProvider must satisfy this, whatever backs it: only active
     * rules, only the requested object, ascending priority, ties broken on
     * DeveloperName.
     */
    private static void assertProviderContract(AMF_RuleProvider provider, String objectApiName) {
        List<AMF_RuleDefinition> rules = provider.getActiveRules(objectApiName);
        Assert.isNotNull(rules, 'getActiveRules must never return null');

        AMF_RuleDefinition previous = null;
        for (AMF_RuleDefinition rule : rules) {
            Assert.areEqual(
                true,
                rule.isActive,
                'getActiveRules returned an inactive rule: ' + rule.developerName
            );
            Assert.areEqual(
                objectApiName,
                rule.objectApiName,
                'getActiveRules returned another object\'s rule: ' + rule.developerName
            );
            if (previous != null) {
                Assert.isTrue(
                    previous.compareTo(rule) < 0,
                    'Rules must be strictly ordered, but ' + previous.developerName
                        + ' (priority ' + previous.priority + ') did not sort before '
                        + rule.developerName + ' (priority ' + rule.priority + ')'
                );
            }
            previous = rule;
        }
    }

    /**
     * Every AMF_RuleProvider's no-argument getActiveRules must satisfy this:
     * never null, no null entries, only active rules, strictly ordered.
     */
    private static void assertConfigurationWideContract(List<AMF_RuleDefinition> rules) {
        Assert.isNotNull(rules, 'getActiveRules() must never return null');

        AMF_RuleDefinition previous = null;
        for (AMF_RuleDefinition rule : rules) {
            Assert.isNotNull(rule, 'getActiveRules() must not return a null entry');
            Assert.areEqual(
                true,
                rule.isActive,
                'getActiveRules() returned an inactive rule: ' + rule.developerName
            );
            if (previous != null) {
                Assert.isTrue(
                    previous.compareTo(rule) < 0,
                    'Rules must be strictly ordered, but ' + previous.developerName
                        + ' did not sort before ' + rule.developerName
                );
            }
            previous = rule;
        }
    }

    private static AMF_RuleDefinition ruleNamed(List<AMF_RuleDefinition> rules, String developerName) {
        for (AMF_RuleDefinition rule : rules) {
            if (rule.developerName == developerName) {
                return rule;
            }
        }
        return null;
    }

    private static List<String> namesOf(List<AMF_RuleDefinition> rules) {
        List<String> names = new List<String>();
        for (AMF_RuleDefinition rule : rules) {
            names.add(rule.developerName);
        }
        return names;
    }
}
