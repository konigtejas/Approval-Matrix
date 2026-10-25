/**
 * The assistant's What-If Approval Route action (M14): changed values tried by
 * the engine and compared with today, values read as a person writes them, and
 * every change it cannot read answered with what it can.
 *
 * Architecture section: 6.4 (its M14 note), 7 (its M14 note), 10.
 *
 * Both seams carry in-memory rules -- the engine the action previews with, and
 * the provider it learns the rule-read fields from -- so nothing depends on the
 * org's matrix (CLAUDE.md). Nothing here is submitted or written.
 */
@IsTest
private class AMF_AgentWhatIfRouteTest {

    private static final String TWO_LEVEL = 'PR_Two_Level_Mgmt';
    private static final String THREE_LEVEL = 'PR_Three_Level_Finance';

    private static List<AMF_RuleDefinition> shippedShape() {
        return new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder()
                .named('PR_High_Value_APAC')
                .withPriority(10)
                .withExpression('Amount__c > 100000 && Region__c == \'APAC\'')
                .routingTo(THREE_LEVEL)
                .build(),
            new AMF_RuleBuilder()
                .named('PR_High_Risk')
                .withPriority(20)
                .withExpression('Risk_Level__c == \'High\'')
                .routingTo(THREE_LEVEL)
                .build(),
            new AMF_RuleBuilder().named('PR_Catch_All').withPriority(9999).withExpression('TRUE').routingTo(TWO_LEVEL).build()
        };
    }

    private static void overRules(List<AMF_RuleDefinition> rules) {
        AMF_AgentWhatIfRoute.engineOverride = new AMF_ApprovalMatrixService(
            new AMF_RuleBuilder.Stub(rules),
            new AMF_StrategyStub()
        );
        AMF_AgentWhatIfRoute.ruleProviderOverride = new AMF_RuleBuilder.Stub(rules);
    }

    private static Purchase_Request__c insertRequest(Decimal amount, String region, String risk) {
        Purchase_Request__c record = new Purchase_Request__c(Amount__c = amount, Region__c = region, Risk_Level__c = risk);
        insert record;
        return record;
    }

    private static String labelOf(Id recordId) {
        return 'Purchase Request ' + [SELECT Name FROM Purchase_Request__c WHERE Id = :recordId].Name;
    }

    private static AMF_AgentWhatIfRoute.Result tryOne(String recordId, String changes) {
        AMF_AgentWhatIfRoute.Request request = new AMF_AgentWhatIfRoute.Request();
        request.recordId = recordId;
        request.changes = changes;
        return AMF_AgentWhatIfRoute.whatIf(new List<AMF_AgentWhatIfRoute.Request>{ request })[0];
    }

    private static void assertContains(String text, String expected) {
        Assert.isTrue(text != null && text.contains(expected), 'Expected "' + expected + '" in:\n' + text);
    }

    @IsTest
    static void triesTheChangedValuesAndComparesThemWithToday() {
        Purchase_Request__c record = insertRequest(500, 'EMEA', 'Low');
        overRules(shippedShape());

        Test.startTest();
        // A label, a lower-case picklist value and a k suffix, as a person writes them.
        AMF_AgentWhatIfRoute.Result result = tryOne(record.Id, 'Amount = 250k; region = apac');
        Test.stopTest();

        Assert.areEqual(AMF_AgentWhatIfRoute.ROUTABLE, result.outcome, result.summary);
        Assert.isTrue(result.routeChanged);
        Assert.areEqual(THREE_LEVEL, result.selectedProcess);
        Assert.areEqual('PR_High_Value_APAC', result.matchedRule);
        Assert.areEqual(TWO_LEVEL, result.currentProcess);
        Assert.areEqual('PR_Catch_All', result.currentRule);
        Assert.areEqual(labelOf(record.Id), result.recordLabel);

        assertContains(
            result.summary,
            'If Amount were ' + Decimal.valueOf(250000).format() + ' (now ' + Decimal.valueOf(500).format() +
            ') and Region were APAC (now EMEA), ' + labelOf(record.Id) + ' would go to approval process ' + THREE_LEVEL +
            '. Rule PR_High_Value_APAC (priority 10) would decide it, because '
        );
        assertContains(result.summary, 'Today it would go to approval process ' + TWO_LEVEL + ', under rule PR_Catch_All.');
        Assert.isTrue(
            result.summary.endsWith(
                'This is only a what-if: nothing was changed or submitted. To submit with these values, change the record, then preview it again.'
            ),
            result.summary
        );

        Purchase_Request__c stored = [SELECT Amount__c, Region__c, Matrix_Submission__c FROM Purchase_Request__c WHERE Id = :record.Id];
        Assert.areEqual(500, stored.Amount__c, 'Nothing was changed');
        Assert.areEqual('EMEA', stored.Region__c);
        Assert.isFalse(stored.Matrix_Submission__c, 'Nothing was submitted');
        Assert.areEqual(0, [SELECT COUNT() FROM Approval_Decision_Log__c], 'Nothing was recorded');
    }

    @IsTest
    static void saysSoWhenTheChangeLeavesTheRouteAlone() {
        Purchase_Request__c record = insertRequest(500, 'EMEA', 'Low');
        overRules(shippedShape());

        AMF_AgentWhatIfRoute.Result result = tryOne(record.Id, 'Amount__c: 600');

        Assert.isFalse(result.routeChanged);
        Assert.areEqual(TWO_LEVEL, result.selectedProcess);
        assertContains(result.summary, 'That is the same as today.');
    }

    @IsTest
    static void triesAFieldNoRuleReadsAndSaysItMakesNoDifference() {
        Purchase_Request__c record = insertRequest(500, 'EMEA', 'Low');
        overRules(shippedShape());

        AMF_AgentWhatIfRoute.Result result = tryOne(record.Id, 'Request Name to "New laptops"');

        Assert.isFalse(result.routeChanged);
        assertContains(result.summary, 'If Request Name were New laptops (now (blank))');
        assertContains(result.summary, 'No active rule reads Request Name, so changing it makes no difference to the route.');
    }

    @IsTest
    static void aWhatIfThatMatchesNoRuleWouldBeBlocked() {
        Purchase_Request__c record = insertRequest(250000, 'APAC', 'Low');
        overRules(new List<AMF_RuleDefinition>{ shippedShape()[0] });

        AMF_AgentWhatIfRoute.Result result = tryOne(record.Id, 'Region = EMEA');

        Assert.areEqual('Blocked_No_Match', result.outcome);
        Assert.isNull(result.selectedProcess);
        Assert.isTrue(result.routeChanged);
        assertContains(result.summary, 'would match no active rule, so the approval matrix would block a submission instead of routing it.');
        assertContains(result.summary, 'Today it would go to approval process ' + THREE_LEVEL + ', under rule PR_High_Value_APAC.');
    }

    @IsTest
    static void answersEveryChangeItCannotReadWithWhatItCan() {
        Purchase_Request__c record = insertRequest(500, 'EMEA', 'Low');
        overRules(shippedShape());

        Map<String, String> answers = new Map<String, String>{
            'Colour = red' => 'Purchase Request has no field called "Colour". Its rules read Amount, Region and Risk Level.',
            'Region = Mars' => '"Mars" is not a Region value. Region can be APAC, EMEA, AMER.',
            'Amount = a great deal' => 'Amount is a number, so try it as one',
            'Account__r.Name = Acme' => 'not Account__r.Name, which belongs to a related record',
            'make it bigger' => 'does not say which value to try',
            '  ' => 'say which field and value to try',
            'Amount = 1; amount__c = 2' => 'Amount is given more than once',
            'Matrix Submission = maybe' => 'Matrix Submission is a checkbox'
        };

        for (String changes : answers.keySet()) {
            AMF_AgentWhatIfRoute.Result result = tryOne(record.Id, changes);
            Assert.areEqual(AMF_AgentWhatIfRoute.REFUSED, result.outcome, changes + ': ' + result.summary);
            Assert.isFalse(result.routeChanged);
            assertContains(result.summary, answers.get(changes));
            assertContains(result.summary, 'Nothing was changed or submitted.');
        }
    }

    @IsTest
    static void refusesWhatItCannotRunWithTheReason() {
        Purchase_Request__c record = insertRequest(500, 'EMEA', 'Low');

        overRules(new List<AMF_RuleDefinition>());
        assertContains(tryOne(record.Id, 'Amount = 1').summary, 'the approval matrix does not govern Purchase Requests');

        overRules(shippedShape());
        assertContains(tryOne('PR-00000045', 'Amount = 1').summary, 'is not a Salesforce record Id');
        Assert.isTrue(AMF_AgentWhatIfRoute.whatIf(null).isEmpty());
    }

    @IsTest
    static void readsValuesAsAPersonWritesThem() {
        Schema.DescribeFieldResult amount = Purchase_Request__c.Amount__c.getDescribe();
        Assert.areEqual(Decimal.valueOf('1200.50'), (Decimal) AMF_AgentWhatIfRoute.valueFor(amount, '$1,200.50'));
        Assert.areEqual(Decimal.valueOf('120000'), (Decimal) AMF_AgentWhatIfRoute.valueFor(amount, '120K'));
        Assert.areEqual(Decimal.valueOf('1200000'), (Decimal) AMF_AgentWhatIfRoute.valueFor(amount, '1.2m'));
        Assert.areEqual(Decimal.valueOf('3000'), (Decimal) AMF_AgentWhatIfRoute.valueFor(amount, '3 thousand'));
        Assert.areEqual(Decimal.valueOf('2500000'), (Decimal) AMF_AgentWhatIfRoute.valueFor(amount, 'USD 2.5 million'));
        Assert.isNull(AMF_AgentWhatIfRoute.valueFor(amount, 'none'), 'A blank value can be tried');

        Schema.DescribeFieldResult risk = Purchase_Request__c.Risk_Level__c.getDescribe();
        Assert.areEqual('High', AMF_AgentWhatIfRoute.valueFor(risk, '\'high\''), 'A picklist value as the field holds it');

        Schema.DescribeFieldResult guard = Purchase_Request__c.Matrix_Submission__c.getDescribe();
        Assert.areEqual(true, AMF_AgentWhatIfRoute.valueFor(guard, 'Yes'));
        Assert.areEqual(false, AMF_AgentWhatIfRoute.valueFor(guard, 'unchecked'));

        Schema.DescribeFieldResult closeDate = Opportunity.CloseDate.getDescribe();
        Assert.areEqual(Date.newInstance(2026, 12, 31), AMF_AgentWhatIfRoute.valueFor(closeDate, '2026-12-31'));
        try {
            AMF_AgentWhatIfRoute.valueFor(closeDate, 'soon');
            Assert.fail('Not a date');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains('try it as YYYY-MM-DD'), e.getMessage());
        }

        Schema.DescribeFieldResult account = Purchase_Request__c.Account__c.getDescribe();
        try {
            AMF_AgentWhatIfRoute.valueFor(account, 'Acme');
            Assert.fail('Not an Id');
        } catch (Exception e) {
            Assert.isTrue(e.getMessage().contains('holds a record Id'), e.getMessage());
        }
    }
}
