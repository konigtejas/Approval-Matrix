/**
 * The Claude connector's check_rule_draft tool (M16, administrators): Claude's
 * draft through every check AMF_RuleDrafter runs on a model's answer, and the
 * file only for a draft that passes.
 *
 * Architecture section: 1 (principle 6), 7 (its M15 and M16 notes), 9, 10.
 *
 * Over in-memory rules through the tool's ruleProviderOverride seam, with the
 * active processes through AMF_RuleDrafter's activeProcessesOverride. Each
 * check's own behaviour is AMF_RuleDrafterTest's subject; pinned here is that
 * the draft reaches them as given, and that nothing is written.
 */
@IsTest
private class AMF_McpCheckRuleDraftTest {

    private static void overStub() {
        AMF_McpCheckRuleDraft.ruleProviderOverride = new AMF_RuleBuilder.Stub(
            new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder()
                    .named('PR_High_Value_APAC')
                    .withPriority(10)
                    .withExpression('Amount__c > 100000 && Region__c == \'APAC\'')
                    .routingTo('PR_Three_Level_Finance')
                    .build(),
                new AMF_RuleBuilder()
                    .named('PR_High_Risk')
                    .withPriority(20)
                    .withExpression('Risk_Level__c == \'High\'')
                    .routingTo('PR_Three_Level_Finance')
                    .atVersion(1)
                    .build(),
                new AMF_RuleBuilder().named('PR_Catch_All').withPriority(9999).withExpression('TRUE').routingTo('PR_Two_Level_Mgmt').build()
            }
        );
        AMF_RuleDrafter.activeProcessesOverride = new Map<String, Set<String>>{
            'Purchase_Request__c' => new Set<String>{ 'PR_Two_Level_Mgmt', 'PR_Three_Level_Finance', 'PR_Finance_Committee' }
        };
    }

    private static AMF_McpCheckRuleDraft.Request emeaDraft() {
        AMF_McpCheckRuleDraft.Request request = new AMF_McpCheckRuleDraft.Request();
        request.objectName = 'Purchase Request';
        request.ruleRequest = 'Anything over 500,000 in EMEA should go to the finance committee.';
        request.developerName = 'PR_EMEA_Over_500k';
        request.label = 'PR - EMEA over 500k';
        request.priority = 15;
        request.expression = 'Amount__c > 500000 && Region__c == \'EMEA\'';
        request.processApiName = 'PR_Finance_Committee';
        request.ruleDescription = 'EMEA spend over 500,000 goes to the finance committee.';
        request.assumptions = 'Amounts are in the org currency.';
        return request;
    }

    private static AMF_McpCheckRuleDraft.Result checkOne(AMF_McpCheckRuleDraft.Request request) {
        return AMF_McpCheckRuleDraft.check(new List<AMF_McpCheckRuleDraft.Request>{ request })[0];
    }

    @IsTest
    static void aDraftThatPassesEveryCheckComesBackWithItsFile() {
        overStub();

        Test.startTest();
        AMF_McpCheckRuleDraft.Result result = checkOne(emeaDraft());
        Test.stopTest();

        Assert.isTrue(result.valid, result.summary + '\n' + result.problems);
        Assert.areEqual('Purchase_Request__c', result.objectApiName);
        Assert.areEqual('PR_EMEA_Over_500k', result.developerName);
        Assert.areEqual(15, result.priority);
        Assert.areEqual('PR_Finance_Committee', result.processApiName);
        Assert.areEqual(1, result.ruleVersion);
        Assert.areEqual('Add', result.changeType);
        Assert.areEqual('force-app/main/default/customMetadata/Approval_Matrix_Rule.PR_EMEA_Over_500k.md-meta.xml', result.filePath);
        Assert.isTrue(result.metadataXml.contains('PR_Finance_Committee'), '' + result.metadataXml);
        Assert.isTrue(result.summary.contains('PR_High_Value_APAC (10)'), 'Says where it sits in the order: ' + result.summary);
        Assert.isNull(result.problems);
    }

    @IsTest
    static void aNewVersionOfAnActiveRuleKeepsItsNameAndTakesTheNextVersion() {
        overStub();
        AMF_McpCheckRuleDraft.Request request = emeaDraft();
        request.ruleToChange = 'PR_High_Risk';
        request.developerName = 'PR_High_Risk';
        request.priority = 20;
        request.expression = 'Risk_Level__c IN (\'High\', \'Medium\')';
        request.processApiName = 'PR_Three_Level_Finance';
        request.ruleDescription = 'High and medium risk requests take the three-level finance chain.';

        AMF_McpCheckRuleDraft.Result result = checkOne(request);

        Assert.isTrue(result.valid, result.summary + '\n' + result.problems);
        Assert.areEqual('Replace', result.changeType);
        Assert.areEqual(2, result.ruleVersion);
    }

    @IsTest
    static void aDraftThatFailsAChecksGetsEveryReasonAndNoFile() {
        overStub();
        AMF_McpCheckRuleDraft.Request request = emeaDraft();
        request.priority = 10;
        request.expression = 'Amount > 500,000 AND Region = \'EMEA\'';
        request.processApiName = 'PR_No_Such_Process';

        AMF_McpCheckRuleDraft.Result result = checkOne(request);

        Assert.isFalse(result.valid);
        Assert.isNotNull(result.problems);
        Assert.isTrue(result.problems.split('\n').size() >= 3, 'Each failed check: ' + result.problems);
        Assert.isTrue(result.problems.contains('PR_No_Such_Process'), '' + result.problems);
        Assert.isNull(result.filePath, 'No file for a refused draft');
        Assert.isNull(result.metadataXml);
        Assert.isNull(result.ruleVersion);
    }

    @IsTest
    static void whatCannotBeCheckedIsSaidPlainly() {
        overStub();
        AMF_McpCheckRuleDraft.Request ungoverned = emeaDraft();
        ungoverned.objectName = 'Account';
        AMF_McpCheckRuleDraft.Request noRequest = emeaDraft();
        noRequest.ruleRequest = ' ';

        AMF_McpCheckRuleDraft.Result notGoverned = checkOne(ungoverned);
        AMF_McpCheckRuleDraft.Result notAsked = checkOne(noRequest);

        Assert.isFalse(notGoverned.valid);
        Assert.isTrue(notGoverned.summary.contains('is not a kind of record the approval matrix governs'), '' + notGoverned.summary);
        Assert.isFalse(notAsked.valid);
        Assert.isTrue(notAsked.summary.startsWith('Describe the rule you want'), '' + notAsked.summary);
        Assert.areEqual(0, AMF_McpCheckRuleDraft.check(null).size());
    }
}
