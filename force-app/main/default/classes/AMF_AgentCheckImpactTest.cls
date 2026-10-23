/**
 * The admin assistant's Check Rule Impact action (M15): a change read from what
 * the administrator asked, checked by the engine, and every request it cannot
 * check answered with why.
 *
 * Architecture section: 7 (its M15 note), 6.4 (its M15 note), 10.
 *
 * The comparison itself is AMF_MatrixImpactTest's subject. In-memory rules
 * (CLAUDE.md), and decision log rows inserted directly. Nothing is submitted.
 */
@IsTest
private class AMF_AgentCheckImpactTest {

    private static final String TWO_LEVEL = 'PR_Two_Level_Mgmt';
    private static final String THREE_LEVEL = 'PR_Three_Level_Finance';

    private static void overStub() {
        AMF_AgentCheckImpact.ruleProviderOverride = new AMF_RuleBuilder.Stub(
            new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder().named('PR_High_Risk').withPriority(20).withExpression('Risk_Level__c == \'High\'').routingTo(THREE_LEVEL).atVersion(2).build(),
                new AMF_RuleBuilder().named('PR_Catch_All').withPriority(9999).withExpression('TRUE').routingTo(TWO_LEVEL).build()
            }
        );
    }

    /** Two low-risk requests with a recent decision each. */
    private static List<Purchase_Request__c> decided() {
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
        return records;
    }

    private static AMF_AgentCheckImpact.Result checkOne(String ruleName, String change, String priority, String expression, String process) {
        AMF_AgentCheckImpact.Request request = new AMF_AgentCheckImpact.Request();
        request.objectName = 'Purchase Request';
        request.ruleName = ruleName;
        request.change = change;
        request.priority = priority;
        request.expression = expression;
        request.processApiName = process;
        return AMF_AgentCheckImpact.checkImpact(new List<AMF_AgentCheckImpact.Request>{ request })[0];
    }

    private static void assertContains(String text, String expected) {
        Assert.isTrue(text != null && text.contains(expected), 'Expected "' + expected + '" in:\n' + text);
    }

    @IsTest
    static void aNewNameIsAnAddAndItsImpactIsReported() {
        decided();
        overStub();

        Test.startTest();
        AMF_AgentCheckImpact.Result result = checkOne(
            'PR_EMEA_Large',
            null,
            '15',
            'Amount__c > 500000 && Region__c == \'EMEA\'',
            'PR_Finance_Committee'
        );
        Test.stopTest();

        Assert.isTrue(result.ran, result.summary);
        Assert.areEqual(2, result.checked);
        Assert.areEqual(1, result.changed);
        Assert.areEqual(0, result.skipped);
        assertContains(result.summary, 'with the new rule PR_EMEA_Large');
        assertContains(result.changes, 'with the change PR_EMEA_Large sends it to PR_Finance_Committee.');
        Assert.areEqual(2, [SELECT COUNT() FROM Approval_Decision_Log__c], 'Nothing recorded');
    }

    @IsTest
    static void anActiveRulesNameIsAReplaceWithAConditionAndADeactivateWithout() {
        decided();
        overStub();

        AMF_AgentCheckImpact.Result widened = checkOne('PR_High_Risk', null, null, 'Risk_Level__c IN (\'High\', \'Low\')', null);
        Assert.isTrue(widened.ran, widened.summary);
        Assert.areEqual(2, widened.changed, 'Both low-risk requests now match it');
        assertContains(widened.summary, 'with version 3 of rule PR_High_Risk');
        assertContains(widened.changes, 'with the change PR_High_Risk sends it to PR_Three_Level_Finance.');

        AMF_AgentCheckImpact.Result takenOut = checkOne('PR_High_Risk', null, null, null, null);
        Assert.isTrue(takenOut.ran, takenOut.summary);
        Assert.areEqual(0, takenOut.changed);
        assertContains(takenOut.summary, 'None of them would be decided differently with rule PR_High_Risk taken out.');

        AMF_AgentCheckImpact.Result explicit = checkOne('PR_High_Risk', 'deactivate', null, null, null);
        Assert.isTrue(explicit.ran, 'The change named in any case');
    }

    @IsTest
    static void answersEveryChangeItCannotCheckWithWhy() {
        overStub();

        Map<String, AMF_AgentCheckImpact.Result> results = new Map<String, AMF_AgentCheckImpact.Result>{
            'a change that is not one' => checkOne('PR_High_Risk', 'Remove', null, null, null),
            'a change to a rule that is not active' => checkOne('PR_Nope', 'Replace', null, 'TRUE', null),
            'a new rule with an active rule\'s name' => checkOne('PR_High_Risk', 'Add', '15', 'TRUE', TWO_LEVEL),
            'a new rule without a process' => checkOne('PR_EMEA_Large', null, '15', 'TRUE', null),
            'a condition that does not compile' => checkOne('PR_EMEA_Large', null, '15', 'Amount__c > \'lots\'', TWO_LEVEL),
            'a priority that is not a number' => checkOne('PR_EMEA_Large', null, 'high', 'TRUE', TWO_LEVEL),
            'no rule' => checkOne(' ', null, null, null, null)
        };
        Map<String, String> expected = new Map<String, String>{
            'a change that is not one' => 'The change must be Add, Replace or Deactivate, not "Remove".',
            'a change to a rule that is not active' => 'No active rule named PR_Nope governs Purchase_Request__c',
            'a new rule with an active rule\'s name' => 'PR_High_Risk is already an active rule.',
            'a new rule without a process' => 'A new rule needs a priority, a condition and an approval process.',
            'a condition that does not compile' => 'The condition does not compile, so its impact cannot be checked:',
            'a priority that is not a number' => 'The priority must be a whole number, not "high".',
            'no rule' => 'Name the rule to add, change or take out.'
        };

        for (String scenario : results.keySet()) {
            AMF_AgentCheckImpact.Result result = results.get(scenario);
            Assert.isFalse(result.ran, scenario);
            assertContains(result.summary, expected.get(scenario));
            Assert.isTrue(result.summary.endsWith('Nothing was changed.'), scenario + ': ' + result.summary);
        }

        AMF_AgentCheckImpact.Request ungoverned = new AMF_AgentCheckImpact.Request();
        ungoverned.objectName = 'Contracts';
        ungoverned.ruleName = 'X';
        assertContains(
            AMF_AgentCheckImpact.checkImpact(new List<AMF_AgentCheckImpact.Request>{ ungoverned })[0].summary,
            '"Contracts" is not a kind of record the approval matrix governs'
        );
        Assert.isTrue(AMF_AgentCheckImpact.checkImpact(null).isEmpty());
    }
}
