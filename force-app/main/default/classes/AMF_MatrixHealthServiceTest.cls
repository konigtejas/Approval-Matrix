/**
 * The matrix-health report (M15): every figure counted in Apex, the model given
 * those facts alone, and the facts kept when it cannot summarise them.
 *
 * Architecture section: 8, 3.3, 1 (principle 6), 10.
 *
 * Decision log rows are inserted directly, shaped as AMF_DecisionLogWriter
 * writes them, in this period and the one before. The matrix is in memory
 * (CLAUDE.md), the pending approvals come through the pendingOverride seam
 * because a ProcessInstance needs a real approval, and the model is a stub.
 */
@IsTest
private class AMF_MatrixHealthServiceTest {

    private static final String TWO_LEVEL = 'PR_Two_Level_Mgmt';
    private static final String THREE_LEVEL = 'PR_Three_Level_Finance';

    private class RunnerStub implements AMF_PromptRunner {
        public Map<String, String> asked;
        public String template;
        public Exception failWith;

        public String run(String templateName, Map<String, String> inputs) {
            template = templateName;
            asked = inputs;
            if (failWith != null) {
                throw failWith;
            }
            return 'The matrix is healthy; the catch-all routes a third of requests.';
        }
    }

    private static List<AMF_RuleDefinition> matrix() {
        return new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder().named('PR_High_Value_APAC').withPriority(10).withExpression('Amount__c > 100000 && Region__c == \'APAC\'').routingTo(THREE_LEVEL).build(),
            new AMF_RuleBuilder().named('PR_High_Risk').withPriority(20).withExpression('Risk_Level__c == \'High\'').routingTo(THREE_LEVEL).build(),
            new AMF_RuleBuilder().named('PR_Catch_All').withPriority(9999).withExpression('TRUE').routingTo(TWO_LEVEL).build(),
            new AMF_RuleBuilder().named('OPP_Catch_All').forObject('Opportunity').withPriority(9999).withExpression('TRUE').routingTo('OPP_Manager_Approval').build()
        };
    }

    private static Approval_Decision_Log__c row(Id recordId, String outcome, String rule, String expression, Datetime submittedAt) {
        return new Approval_Decision_Log__c(
            Record_Id__c = String.valueOf(recordId),
            Object_API_Name__c = 'Purchase_Request__c',
            Outcome__c = outcome,
            Matched_Rule__c = rule,
            Expression_Snapshot__c = expression,
            Evaluated_Values__c = '{}',
            Selected_Process__c = rule == null ? null : TWO_LEVEL,
            Failure_Detail__c = outcome == 'Failed' ? 'Approval process PR_Two_Level_Mgmt refused the submission: NO_APPLICABLE_PROCESS\nstack' : null,
            Submitted_By__c = UserInfo.getUserId(),
            Submitted_At__c = submittedAt
        );
    }

    private static ProcessInstance pending(Id recordId, String process, Datetime createdAt) {
        return (ProcessInstance) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'attributes' => new Map<String, Object>{ 'type' => 'ProcessInstance' },
                    'TargetObjectId' => recordId,
                    'CreatedDate' => createdAt,
                    'ProcessDefinition' => new Map<String, Object>{
                        'attributes' => new Map<String, Object>{ 'type' => 'ProcessDefinition' },
                        'DeveloperName' => process
                    }
                }
            ),
            ProcessInstance.class
        );
    }

    private static void assertContains(String text, String expected) {
        Assert.isTrue(text != null && text.contains(expected), 'Expected "' + expected + '" in:\n' + text);
    }

    @IsTest
    static void countsEveryFactAndGivesTheModelThoseFactsAlone() {
        Purchase_Request__c record = new Purchase_Request__c(Amount__c = 500, Region__c = 'EMEA', Risk_Level__c = 'Low');
        insert record;
        Datetime recently = Datetime.now().addDays(-3);
        Datetime earlier = Datetime.now().addDays(-40);

        insert new List<Approval_Decision_Log__c>{
            row(record.Id, 'Submitted', 'PR_Catch_All', 'TRUE', recently),
            row(record.Id, 'Submitted', 'PR_High_Value_APAC', 'Amount__c > 100000 && Region__c == \'APAC\'', recently),
            row(record.Id, 'Submitted', 'PR_High_Value_APAC', 'Amount__c > 100000 && Region__c == \'APAC\'', recently),
            row(record.Id, 'Blocked_No_Match', null, null, recently),
            row(record.Id, 'Failed', 'PR_Catch_All', 'TRUE', recently),
            row(record.Id, 'Submitted', 'PR_Catch_All', 'TRUE', earlier),
            row(record.Id, 'Blocked_No_Match', null, null, earlier)
        };

        Datetime nine = Datetime.now().addDays(-10);
        AMF_MatrixHealthService.pendingOverride = new List<ProcessInstance>{
            pending(record.Id, THREE_LEVEL, nine),
            pending(record.Id, THREE_LEVEL, Datetime.now().addDays(-2))
        };
        RunnerStub runner = new RunnerStub();

        Test.startTest();
        AMF_MatrixHealthService.Report report = new AMF_MatrixHealthService(new AMF_RuleBuilder.Stub(matrix()), runner)
            .report(30, null, null);
        Test.stopTest();

        Assert.areEqual(30, report.days);
        Assert.areEqual(5, report.decisions);
        Assert.areEqual(1, report.blocked);
        Assert.areEqual(1, report.failed);
        Assert.areEqual('The matrix is healthy; the catch-all routes a third of requests.', report.narrative);

        String facts = report.facts;
        assertContains(facts, 'Period: the last 30 days, ');
        assertContains(facts, 'Purchase Request (Purchase_Request__c):');
        assertContains(
            facts,
            '- Decisions recorded: 5 (previous period: 2). Routed 3, blocked 1, failed 1 (previous period: routed 1, blocked 1, failed 0).'
        );
        assertContains(
            facts,
            '- Routed decisions by rule: PR_Catch_All 1 (33%, a catch-all: its condition is TRUE); PR_High_Value_APAC 2 (67%).'
        );
        assertContains(facts, '- Catch-all share of routed decisions: 33%.');
        assertContains(facts, '- Active rules that routed nothing in the period: PR_High_Risk (priority 20).');
        assertContains(
            facts,
            '- Most common recorded failure reasons: "Approval process PR_Two_Level_Mgmt refused the submission: NO_APPLICABLE_PROCESS" (1).'
        );
        assertContains(facts, '- Approvals pending now: PR_Three_Level_Finance 2, the oldest waiting since ' + AMF_AgentSupport.whenOf(nine) + ' (10 days).');
        assertContains(facts, 'Opportunity (Opportunity):');
        assertContains(facts, '- Decisions recorded: 0 (previous period: 0).');

        Assert.areEqual('AMF_Summarize_Matrix_Health', runner.template);
        Assert.areEqual(facts, runner.asked.get('Facts'), 'The model is given the counted facts, and nothing else');
        Assert.areEqual(AMF_MatrixHealthService.DEFAULT_QUESTION, runner.asked.get('Question'));
    }

    @IsTest
    static void keepsTheFactsWhenEinsteinCannotSummariseThem() {
        RunnerStub runner = new RunnerStub();
        runner.failWith = new AMF_PromptException('Einstein is not available for this right now.');

        AMF_MatrixHealthService.Report report = new AMF_MatrixHealthService(new AMF_RuleBuilder.Stub(matrix()), runner)
            .report(7, 'Purchase_Request__c', '  Is the catch-all doing too much?  ');

        Assert.isNull(report.narrative);
        Assert.areEqual('Einstein is not available for this right now.', report.narrativeProblem);
        Assert.areEqual(7, report.days);
        assertContains(report.facts, 'Period: the last 7 days, ');
        assertContains(report.facts, '- Approvals pending now: none.');
        Assert.isFalse(report.facts.contains('Opportunity'), 'One object asked for, one reported');
        Assert.areEqual('Is the catch-all doing too much?', runner.asked.get('Question'), 'The question, as asked');
    }

    @IsTest
    static void aPeriodOutOfRangeIsTheDefaultAndOnlyTrueIsACatchAll() {
        AMF_MatrixHealthService service = new AMF_MatrixHealthService(new AMF_RuleBuilder.Stub(matrix()), new RunnerStub());

        for (Integer days : new List<Integer>{ null, 0, -5, AMF_MatrixHealthService.MAX_DAYS + 1 }) {
            Assert.areEqual(AMF_MatrixHealthService.DEFAULT_DAYS, service.factsOf(days, null).days, 'days = ' + days);
        }
        Assert.areEqual(AMF_MatrixHealthService.MAX_DAYS, service.factsOf(AMF_MatrixHealthService.MAX_DAYS, null).days);

        Assert.isTrue(AMF_MatrixHealthService.isCatchAll('TRUE'));
        Assert.isTrue(AMF_MatrixHealthService.isCatchAll('  true '));
        Assert.isFalse(AMF_MatrixHealthService.isCatchAll('TRUE && Amount__c > 0'));
        Assert.isFalse(AMF_MatrixHealthService.isCatchAll(null));

        AMF_MatrixHealthService.Report ungoverned = service.factsOf(30, 'Account');
        assertContains(ungoverned.facts, 'No governed object called Account has active rules.');
    }
}
