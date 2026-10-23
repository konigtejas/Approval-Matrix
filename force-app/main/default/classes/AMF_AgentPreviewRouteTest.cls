/**
 * The assistant's Preview Approval Route action (M13): the engine's preview,
 * in words the agent repeats, with nothing written.
 *
 * Architecture section: 6.4, 7 (its M13 note), 10.
 *
 * The action runs over in-memory rules and AMF_StrategyStub through its
 * engineOverride seam, as the M10 action's tests do. What the engine decides is
 * AMF_ApprovalMatrixServiceTest's; what is pinned here is the agent's reading
 * of it: the outcome renamed for a reader who has not submitted, the summary,
 * and that a preview writes nothing.
 */
@IsTest
private class AMF_AgentPreviewRouteTest {

    private static final String THREE_LEVEL = 'PR_Three_Level_Finance';

    private static AMF_StrategyStub over(List<AMF_RuleDefinition> rules) {
        AMF_StrategyStub strategy = new AMF_StrategyStub();
        AMF_AgentPreviewRoute.engineOverride = new AMF_ApprovalMatrixService(new AMF_RuleBuilder.Stub(rules), strategy);
        return strategy;
    }

    private static AMF_RuleDefinition highRisk() {
        return new AMF_RuleBuilder()
            .named('PR_High_Risk')
            .withPriority(20)
            .withExpression('Risk_Level__c == \'High\'')
            .routingTo(THREE_LEVEL)
            .describedAs('Any high-risk request takes the three-level finance chain, whatever the amount')
            .atVersion(2)
            .build();
    }

    private static Purchase_Request__c insertRequest(String risk) {
        Purchase_Request__c record = new Purchase_Request__c(Amount__c = 60000, Region__c = 'EMEA', Risk_Level__c = risk);
        insert record;
        return record;
    }

    private static String labelOf(Id recordId) {
        return Purchase_Request__c.SObjectType.getDescribe().getLabel() +
            ' ' +
            [SELECT Name FROM Purchase_Request__c WHERE Id = :recordId].Name;
    }

    private static AMF_AgentPreviewRoute.Result previewOf(String recordId) {
        AMF_AgentPreviewRoute.Request request = new AMF_AgentPreviewRoute.Request();
        request.recordId = recordId;
        return AMF_AgentPreviewRoute.preview(new List<AMF_AgentPreviewRoute.Request>{ request })[0];
    }

    @IsTest
    static void aRoutableRecordIsShownItsProcessRuleAndReasonWithNothingWritten() {
        Purchase_Request__c record = insertRequest('High');
        AMF_StrategyStub strategy = over(new List<AMF_RuleDefinition>{ highRisk() });

        Test.startTest();
        AMF_AgentPreviewRoute.Result result = previewOf(String.valueOf(record.Id).left(15));
        Test.stopTest();

        Assert.areEqual(String.valueOf(record.Id), result.recordId, 'A 15-character Id comes back as the 18-character one');
        Assert.areEqual(labelOf(record.Id), result.recordLabel);
        Assert.areEqual(AMF_AgentPreviewRoute.ROUTABLE, result.outcome, 'Not "Submitted": nothing has been');
        Assert.isTrue(result.canSubmit);
        Assert.areEqual(THREE_LEVEL, result.selectedProcess);
        Assert.areEqual('PR_High_Risk', result.matchedRule);
        Assert.areEqual(2, result.ruleVersion);
        Assert.areEqual(20, result.rulePriority);
        Assert.areEqual('Risk_Level__c == \'High\'', result.condition);
        Assert.areEqual('Risk Level = High', result.valuesRead);
        Assert.areEqual(
            labelOf(record.Id) +
            ' would go to approval process ' + THREE_LEVEL + '. Rule PR_High_Risk (priority 20, version 2) decides it, ' +
            'because Risk Level = High. The rule\'s description: Any high-risk request takes the three-level finance ' +
            'chain, whatever the amount. Nothing has been submitted yet.',
            result.summary
        );

        Assert.areEqual(0, [SELECT COUNT() FROM Approval_Decision_Log__c], 'A preview writes no decision log row');
        Assert.areEqual(0, strategy.calls, 'A preview submits nothing');
        Assert.isFalse(
            [SELECT Matrix_Submission__c FROM Purchase_Request__c WHERE Id = :record.Id].Matrix_Submission__c,
            'A preview stages no guard'
        );
    }

    @IsTest
    static void theCatchAllIsShownAsTheDefaultRouteItIs() {
        Purchase_Request__c record = insertRequest('Low');
        over(
            new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder()
                    .named('PR_Catch_All')
                    .withPriority(9999)
                    .withExpression('TRUE')
                    .describedAs(null)
                    .atVersion(null)
                    .build()
            }
        );

        AMF_AgentPreviewRoute.Result result = previewOf(record.Id);

        Assert.areEqual(AMF_AgentPreviewRoute.ROUTABLE, result.outcome);
        Assert.isNull(result.valuesRead);
        Assert.isTrue(result.summary.contains('Rule PR_Catch_All (priority 9999) decides it'), 'No "version null": ' + result.summary);
        Assert.isTrue(
            result.summary.contains('and its condition reads no fields, so it matches every record that no earlier rule did.'),
            result.summary
        );
        Assert.isFalse(result.summary.contains('description'), result.summary);
    }

    @IsTest
    static void aRecordNoRuleMatchesIsToldItWouldOnlyBeRecordedAsBlocked() {
        Purchase_Request__c record = insertRequest('Low');
        over(new List<AMF_RuleDefinition>{ highRisk() });

        AMF_AgentPreviewRoute.Result result = previewOf(record.Id);

        Assert.areEqual('Blocked_No_Match', result.outcome);
        Assert.isTrue(result.canSubmit, 'The header button submits a blocked record so the attempt is recorded; so may the agent');
        Assert.isNull(result.selectedProcess);
        Assert.areEqual(
            'No active rule matches ' + labelOf(record.Id) + ', so the approval matrix would block a submission instead ' +
            'of routing it by default. It read Risk Level = Low. Submitting it would not start an approval: it would ' +
            'only record the blocked attempt in the decision log. Nothing has been submitted yet.',
            result.summary
        );
        Assert.areEqual(0, [SELECT COUNT() FROM Approval_Decision_Log__c]);
    }

    @IsTest
    static void aRouteTheMatrixCannotDecideIsShownWithTheEnginesReason() {
        Purchase_Request__c record = insertRequest('High');
        over(
            new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder().named('PR_No_Process').withPriority(5).withExpression('TRUE').routingTo(null).build()
            }
        );

        AMF_AgentPreviewRoute.Result result = previewOf(record.Id);

        Assert.areEqual('Failed', result.outcome);
        Assert.isTrue(result.canSubmit);
        Assert.isTrue(result.summary.startsWith('The approval matrix could not decide a route for ' + labelOf(record.Id) + ': '), result.summary);
        Assert.isTrue(result.summary.contains('names no approval process'), result.summary);
        Assert.isTrue(result.summary.endsWith('Nothing has been submitted yet.'), result.summary);
    }

    @IsTest
    static void aRecordTheMatrixCannotActOnIsRefusedWithTheEnginesReason() {
        Account account = new Account(Name = 'Not governed');
        insert account;
        over(new List<AMF_RuleDefinition>{ highRisk() });

        AMF_AgentPreviewRoute.Result result = previewOf(account.Id);

        Assert.areEqual(AMF_AgentPreviewRoute.REFUSED, result.outcome);
        Assert.isFalse(result.canSubmit);
        Assert.areEqual(String.valueOf(account.Id), result.recordId);
        Assert.isTrue(result.summary.contains(' cannot be submitted: '), result.summary);
        Assert.isTrue(result.summary.contains('Matrix_Submission__c'), result.summary);
        Assert.isTrue(result.summary.endsWith(' Nothing has been submitted.'), result.summary);
    }

    @IsTest
    static void aRuleThatWillNotCompileRefusesRatherThanFallingThrough() {
        Purchase_Request__c record = insertRequest('High');
        over(
            new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder().named('PR_Broken').withPriority(1).withExpression('Amount__c >').build(),
                highRisk()
            }
        );

        AMF_AgentPreviewRoute.Result result = previewOf(record.Id);

        Assert.areEqual(AMF_AgentPreviewRoute.REFUSED, result.outcome, '4.6: no route is shown past a rule that cannot be read');
        Assert.isFalse(result.canSubmit);
        Assert.isNull(result.selectedProcess);
    }

    @IsTest
    static void textThatIsNotARecordIdIsAnsweredNotThrown() {
        over(new List<AMF_RuleDefinition>{ highRisk() });

        AMF_AgentPreviewRoute.Result named = previewOf('PR-00000045');
        Assert.areEqual(AMF_AgentPreviewRoute.REFUSED, named.outcome);
        Assert.isNull(named.recordId);
        Assert.areEqual(
            'This record cannot be submitted: "PR-00000045" is not a Salesforce record Id. Look the record up by its ' +
            'name or number first. Nothing has been submitted.',
            named.summary
        );

        AMF_AgentPreviewRoute.Result blank = previewOf('  ');
        Assert.isTrue(blank.summary.contains('no record was given'), blank.summary);
    }

    @IsTest
    static void answersEachRequestInOrderAndNothingForNoRequests() {
        Purchase_Request__c high = insertRequest('High');
        Purchase_Request__c low = insertRequest('Low');
        over(new List<AMF_RuleDefinition>{ highRisk() });

        AMF_AgentPreviewRoute.Request first = new AMF_AgentPreviewRoute.Request();
        first.recordId = low.Id;
        AMF_AgentPreviewRoute.Request second = new AMF_AgentPreviewRoute.Request();
        second.recordId = high.Id;

        List<AMF_AgentPreviewRoute.Result> results = AMF_AgentPreviewRoute.preview(
            new List<AMF_AgentPreviewRoute.Request>{ first, second }
        );

        Assert.areEqual(2, results.size());
        Assert.areEqual('Blocked_No_Match', results[0].outcome);
        Assert.areEqual(AMF_AgentPreviewRoute.ROUTABLE, results[1].outcome);
        Assert.isTrue(AMF_AgentPreviewRoute.preview(null).isEmpty());
    }
}
