/**
 * The admin assistant's Matrix Health Report action (M15): Einstein's summary
 * when there is one, the counted facts always, and an unknown object answered.
 *
 * Architecture section: 7 (its M15 note), 8, 10.
 *
 * What is counted is AMF_MatrixHealthServiceTest's subject. In-memory rules, a
 * stub model.
 */
@IsTest
private class AMF_AgentMatrixHealthTest {

    private class RunnerStub implements AMF_PromptRunner {
        public Exception failWith;

        public String run(String templateName, Map<String, String> inputs) {
            if (failWith != null) {
                throw failWith;
            }
            return 'Nothing was decided recently, so there is nothing to worry about yet.';
        }
    }

    private static RunnerStub overStub() {
        AMF_RuleBuilder.Stub rules = new AMF_RuleBuilder.Stub(
            new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder().named('PR_Catch_All').withPriority(9999).withExpression('TRUE').routingTo('PR_Two_Level_Mgmt').build()
            }
        );
        RunnerStub runner = new RunnerStub();
        AMF_AgentMatrixHealth.serviceOverride = new AMF_MatrixHealthService(rules, runner);
        AMF_AgentMatrixHealth.ruleProviderOverride = rules;
        return runner;
    }

    private static AMF_AgentMatrixHealth.Result reportOn(String objectName, Integer days) {
        AMF_AgentMatrixHealth.Request request = new AMF_AgentMatrixHealth.Request();
        request.objectName = objectName;
        request.days = days;
        return AMF_AgentMatrixHealth.reportHealth(new List<AMF_AgentMatrixHealth.Request>{ request })[0];
    }

    @IsTest
    static void givesEinsteinsSummaryAndTheFactsItWasWrittenFrom() {
        overStub();

        AMF_AgentMatrixHealth.Result result = reportOn('Purchase Requests', 14);

        Assert.isTrue(result.summarised);
        Assert.areEqual('Nothing was decided recently, so there is nothing to worry about yet.', result.summary);
        Assert.areEqual(14, result.days);
        Assert.areEqual(0, result.decisions);
        Assert.isTrue(result.facts.contains('Purchase Request (Purchase_Request__c):'), result.facts);
    }

    @IsTest
    static void keepsTheFactsWhenEinsteinCannotSummarise() {
        RunnerStub runner = overStub();
        runner.failWith = new AMF_PromptException('Einstein is not available for this right now');

        AMF_AgentMatrixHealth.Result result = AMF_AgentMatrixHealth.reportHealth(null)[0];

        Assert.isFalse(result.summarised);
        Assert.areEqual('Einstein is not available for this right now. The counted facts are below.', result.summary);
        Assert.areEqual(30, result.days, 'The default period');
        Assert.isNotNull(result.facts);
    }

    @IsTest
    static void answersAnObjectTheMatrixDoesNotGovern() {
        overStub();

        AMF_AgentMatrixHealth.Result result = reportOn('Contracts', null);

        Assert.isFalse(result.summarised);
        Assert.isTrue(result.summary.startsWith('"Contracts" is not a kind of record the approval matrix governs.'), result.summary);
        Assert.isNull(result.facts);
    }
}
