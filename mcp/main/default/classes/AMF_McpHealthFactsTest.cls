/**
 * The Claude connector's get_health_facts tool (M16, administrators): the
 * matrix-health facts alone, for Claude to summarise. No summary is generated.
 *
 * Architecture section: 7 (its M15 and M16 notes), 10.
 *
 * Over in-memory rules through the tool's ruleProviderOverride and
 * serviceOverride seams. What is counted is AMF_MatrixHealthServiceTest's
 * subject; pinned here is that the facts come back with no model asked.
 */
@IsTest
private class AMF_McpHealthFactsTest {

    /** Fails the test if anything asks for a summary. */
    private class NoModel implements AMF_PromptRunner {
        public String run(String templateName, Map<String, String> inputs) {
            Assert.fail('No model is asked: Claude summarises the facts');
            return null;
        }
    }

    private static void overStub() {
        AMF_RuleBuilder.Stub rules = new AMF_RuleBuilder.Stub(
            new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder().named('PR_Catch_All').withPriority(9999).withExpression('TRUE').routingTo('PR_Two_Level_Mgmt').build()
            }
        );
        AMF_McpHealthFacts.serviceOverride = new AMF_MatrixHealthService(rules, new NoModel());
        AMF_McpHealthFacts.ruleProviderOverride = rules;
    }

    @IsTest
    static void givesTheCountedFactsForThePeriodWithNoModelAsked() {
        overStub();
        AMF_McpHealthFacts.Request request = new AMF_McpHealthFacts.Request();
        request.objectName = 'Purchase Requests';
        request.days = 14;

        AMF_McpHealthFacts.Result result = AMF_McpHealthFacts.getFacts(new List<AMF_McpHealthFacts.Request>{ request })[0];

        Assert.isTrue(result.reported, '' + result.summary);
        Assert.areEqual(14, result.days);
        Assert.areEqual(0, result.decisions);
        Assert.areEqual(0, result.blocked);
        Assert.areEqual(0, result.failed);
        Assert.isTrue(result.facts.contains('Purchase Request (Purchase_Request__c):'), '' + result.facts);
    }

    @IsTest
    static void defaultsToEveryObjectOverThirtyDays() {
        overStub();

        AMF_McpHealthFacts.Result result = AMF_McpHealthFacts.getFacts(null)[0];

        Assert.isTrue(result.reported);
        Assert.areEqual(30, result.days);
        Assert.isNotNull(result.facts);
    }

    @IsTest
    static void answersAnObjectTheMatrixDoesNotGovern() {
        overStub();
        AMF_McpHealthFacts.Request request = new AMF_McpHealthFacts.Request();
        request.objectName = 'Account';

        AMF_McpHealthFacts.Result result = AMF_McpHealthFacts.getFacts(new List<AMF_McpHealthFacts.Request>{ request })[0];

        Assert.isFalse(result.reported);
        Assert.isTrue(result.summary.contains('is not a kind of record the approval matrix governs'), '' + result.summary);
        Assert.isNull(result.facts);
    }
}
