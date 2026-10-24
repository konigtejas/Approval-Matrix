/**
 * The Claude connector's get_matrix_context tool (M16, administrators): the
 * drafter's own context and the matrix's grammar, for Claude to draft from.
 *
 * Architecture section: 4.1, 7 (its M15 and M16 notes), 9, 10.
 *
 * Over in-memory rules through the tool's ruleProviderOverride seam, with the
 * active processes through AMF_RuleDrafter's activeProcessesOverride. What the
 * context contains is AMF_RuleDrafterTest's subject; pinned here is that it is
 * the drafter's, captured before any model is asked, and that nothing is
 * generated.
 */
@IsTest
private class AMF_McpRuleContextTest {

    private static void overStub() {
        AMF_McpRuleContext.ruleProviderOverride = new AMF_RuleBuilder.Stub(
            new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder()
                    .named('PR_High_Risk')
                    .withPriority(20)
                    .withExpression('Risk_Level__c == \'High\'')
                    .routingTo('PR_Three_Level_Finance')
                    .describedAs('Any high-risk request takes the three-level finance chain.')
                    .build(),
                new AMF_RuleBuilder().named('PR_Catch_All').withPriority(9999).withExpression('TRUE').routingTo('PR_Two_Level_Mgmt').build()
            }
        );
        AMF_RuleDrafter.activeProcessesOverride = new Map<String, Set<String>>{
            'Purchase_Request__c' => new Set<String>{ 'PR_Two_Level_Mgmt', 'PR_Three_Level_Finance', 'PR_Finance_Committee' }
        };
    }

    private static AMF_McpRuleContext.Result contextOf(String objectName, String ruleToChange) {
        AMF_McpRuleContext.Request request = new AMF_McpRuleContext.Request();
        request.objectName = objectName;
        request.ruleToChange = ruleToChange;
        return AMF_McpRuleContext.getContext(new List<AMF_McpRuleContext.Request>{ request })[0];
    }

    @IsTest
    static void givesTheGrammarAndTheDraftersOwnContextForTheObject() {
        overStub();

        AMF_McpRuleContext.Result result = contextOf('Purchase Request', null);

        Assert.areEqual(AMF_McpRuleContext.WITH_CONTEXT, result.outcome, '' + result.summary);
        Assert.areEqual('Purchase_Request__c', result.objectApiName);
        Assert.areEqual(AMF_McpRuleContext.GUIDE, result.guide);
        Assert.isTrue(result.guide.contains('The expression language:'), '' + result.guide);
        Assert.isTrue(result.guide.contains('check_rule_draft'), 'The guide sends the draft to be checked');
        for (String expected : new List<String>{ 'Amount__c', 'Region__c', 'PR_High_Risk', 'PR_Catch_All', 'PR_Finance_Committee' }) {
            Assert.isTrue(result.context.contains(expected), 'Expected ' + expected + ' in:\n' + result.context);
        }
        Assert.isNull(result.summary);
    }

    @IsTest
    static void aRuleToChangeIsNamedInTheContext() {
        overStub();

        AMF_McpRuleContext.Result result = contextOf('Purchase_Request__c', 'PR_High_Risk');

        Assert.areEqual(AMF_McpRuleContext.WITH_CONTEXT, result.outcome, '' + result.summary);
        Assert.isTrue(result.context.contains('PR_High_Risk'), '' + result.context);
    }

    @IsTest
    static void whatCannotBeDraftedForIsSaidPlainly() {
        overStub();

        AMF_McpRuleContext.Result ungoverned = contextOf('Account', null);
        AMF_McpRuleContext.Result unnamed = contextOf(' ', null);
        AMF_McpRuleContext.Result inactive = contextOf('Purchase Request', 'PR_No_Such_Rule');

        Assert.areEqual(AMF_McpRuleContext.WITHOUT_CONTEXT, ungoverned.outcome);
        Assert.isTrue(ungoverned.summary.contains('is not a kind of record the approval matrix governs'), '' + ungoverned.summary);
        Assert.isNull(ungoverned.context);
        Assert.areEqual(AMF_McpRuleContext.WITHOUT_CONTEXT, unnamed.outcome);
        Assert.isTrue(unnamed.summary.startsWith('No object was named'), '' + unnamed.summary);
        Assert.areEqual(AMF_McpRuleContext.WITHOUT_CONTEXT, inactive.outcome);
        Assert.isTrue(inactive.summary.contains('No active rule named PR_No_Such_Rule'), '' + inactive.summary);
        Assert.isNull(inactive.guide);
        Assert.areEqual(0, AMF_McpRuleContext.getContext(null).size());
    }
}
