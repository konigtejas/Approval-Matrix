/**
 * Unit test for AMF_RuleDefinition, in particular the ordering that arch doc
 * 6.1 step 2 depends on.
 *
 * Architecture section: 3.1, 6.1 step 2, 10.
 *
 * Entirely in-memory. The comparator is where "priority-ordered first match"
 * actually lives, so it is worth testing without a single CMDT row involved.
 */
@IsTest
private class AMF_RuleDefinitionTest {

    @IsTest
    static void sortsByPriorityAscending() {
        List<AMF_RuleDefinition> rules = new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder().named('Catch_All').withPriority(9999).build(),
            new AMF_RuleBuilder().named('High_Value').withPriority(10).build(),
            new AMF_RuleBuilder().named('High_Risk').withPriority(20).build()
        };

        rules.sort();

        Assert.areEqual(
            new List<String>{ 'High_Value', 'High_Risk', 'Catch_All' },
            namesOf(rules),
            'Lower priority must win, so the catch-all sorts last'
        );
    }

    @IsTest
    static void tiesBreakOnDeveloperNameAscending() {
        List<AMF_RuleDefinition> rules = new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder().named('Zulu').withPriority(50).build(),
            new AMF_RuleBuilder().named('Alpha').withPriority(50).build(),
            new AMF_RuleBuilder().named('Mike').withPriority(50).build()
        };

        rules.sort();

        Assert.areEqual(
            new List<String>{ 'Alpha', 'Mike', 'Zulu' },
            namesOf(rules),
            'Equal priorities must break on DeveloperName, which is what makes the order total'
        );
    }

    @IsTest
    static void orderingIsStableAcrossInputPermutations() {
        List<AMF_RuleDefinition> ascending = new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder().named('A').withPriority(10).build(),
            new AMF_RuleBuilder().named('B').withPriority(10).build(),
            new AMF_RuleBuilder().named('C').withPriority(20).build()
        };
        List<AMF_RuleDefinition> shuffled = new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder().named('C').withPriority(20).build(),
            new AMF_RuleBuilder().named('B').withPriority(10).build(),
            new AMF_RuleBuilder().named('A').withPriority(10).build()
        };

        ascending.sort();
        shuffled.sort();

        Assert.areEqual(
            namesOf(ascending),
            namesOf(shuffled),
            'The same rules in a different input order must produce the same output order'
        );
    }

    @IsTest
    static void nullPrioritySortsLastRatherThanThrowing() {
        List<AMF_RuleDefinition> rules = new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder().named('No_Priority').withPriority(null).build(),
            new AMF_RuleBuilder().named('Normal').withPriority(10).build()
        };

        rules.sort();

        Assert.areEqual(
            new List<String>{ 'Normal', 'No_Priority' },
            namesOf(rules),
            'A null priority must sort last; a comparator that throws inside List.sort is a landmine'
        );
    }

    @IsTest
    static void identicalRulesCompareEqual() {
        AMF_RuleDefinition left = new AMF_RuleBuilder().named('Same').withPriority(10).build();
        AMF_RuleDefinition right = new AMF_RuleBuilder().named('Same').withPriority(10).build();

        Assert.areEqual(0, left.compareTo(right), 'Same priority and same name must compare equal');
    }

    @IsTest
    static void builderCarriesEveryFieldThrough() {
        AMF_RuleDefinition rule = new AMF_RuleBuilder()
            .named('High_Value_APAC')
            .forObject('Purchase_Request__c')
            .withPriority(10)
            .withExpression('Amount__c > 100000 && Region__c == \'APAC\'')
            .routingTo('PR_Three_Level_Finance')
            .describedAs('High-value APAC spend.')
            .atVersion(3)
            .inactive()
            .build();

        Assert.areEqual('High_Value_APAC', rule.developerName, 'developerName');
        Assert.areEqual('Purchase_Request__c', rule.objectApiName, 'objectApiName');
        Assert.areEqual(10, rule.priority, 'priority');
        Assert.areEqual('Amount__c > 100000 && Region__c == \'APAC\'', rule.expression, 'expression');
        Assert.areEqual('PR_Three_Level_Finance', rule.processApiName, 'processApiName');
        Assert.areEqual('High-value APAC spend.', rule.description, 'description');
        Assert.areEqual(3, rule.version, 'version');
        Assert.areEqual(false, rule.isActive, 'isActive');
    }

    private static List<String> namesOf(List<AMF_RuleDefinition> rules) {
        List<String> names = new List<String>();
        for (AMF_RuleDefinition rule : rules) {
            names.add(rule.developerName);
        }
        return names;
    }
}
