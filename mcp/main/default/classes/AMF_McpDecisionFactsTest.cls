/**
 * The Claude connector's get_decision_facts tool (M16), and AMF_McpFactsOnly:
 * the facts the Explain button's template is given, handed to Claude instead.
 *
 * Architecture section: 8 (its M13 and M14 notes), 7 (its M16 note), 10.
 *
 * Real decision log rows, an in-memory approval history through the tool's
 * timelineOverride seam, and Find Governed Record over in-memory rules. What
 * the facts say is AMF_DecisionExplainerTest's subject; pinned here is that
 * they arrive unwritten, from a record or a row's name, and that every case
 * without facts is answered rather than thrown.
 */
@IsTest
private class AMF_McpDecisionFactsTest {

    private static final Datetime NINE = Datetime.newInstanceGmt(2026, 10, 21, 9, 0, 0);
    private static final Id INSTANCE_ID = Id.valueOf('04g000000000001AAA');

    private class HistoryStub implements AMF_ApprovalHistoryProvider {
        private final List<AMF_ApprovalHistory.Instance> instances;

        private HistoryStub(List<AMF_ApprovalHistory.Instance> instances) {
            this.instances = instances;
        }

        public List<AMF_ApprovalHistory.Instance> getHistory(Id recordId, Integer maxInstances) {
            return instances;
        }
    }

    private static AMF_ApprovalHistory.Instance approved() {
        AMF_ApprovalHistory.Instance instance = new AMF_ApprovalHistory.Instance();
        instance.id = INSTANCE_ID;
        instance.processName = 'PR_Three_Level_Finance';
        instance.status = 'Approved';
        instance.submittedAt = NINE;
        return instance;
    }

    private static void over(List<AMF_ApprovalHistory.Instance> history) {
        AMF_McpDecisionFacts.timelineOverride = new AMF_DecisionTimelineService(new HistoryStub(history));
        AMF_AgentFindRecord.ruleProviderOverride = new AMF_RuleBuilder.Stub(
            new List<AMF_RuleDefinition>{ new AMF_RuleBuilder().named('PR_High_Value_APAC').withPriority(10).build() }
        );
    }

    private static Purchase_Request__c insertRequest() {
        Purchase_Request__c record = new Purchase_Request__c(Amount__c = 250000, Region__c = 'APAC', Risk_Level__c = 'Low');
        insert record;
        return [SELECT Id, Name FROM Purchase_Request__c WHERE Id = :record.Id];
    }

    private static Approval_Decision_Log__c insertRow(Id recordId) {
        Approval_Decision_Log__c row = new Approval_Decision_Log__c(
            Record_Id__c = String.valueOf(recordId),
            Object_API_Name__c = 'Purchase_Request__c',
            Outcome__c = 'Submitted',
            Matched_Rule__c = 'PR_High_Value_APAC',
            Rule_Version__c = 1,
            Expression_Snapshot__c = 'Amount__c > 100000 && Region__c == \'APAC\'',
            Evaluated_Values__c = '{"Amount__c":250000,"Region__c":"APAC"}',
            Selected_Process__c = 'PR_Three_Level_Finance',
            Execution_Ref_Id__c = String.valueOf(INSTANCE_ID),
            Submitted_By__c = UserInfo.getUserId(),
            Submitted_At__c = NINE
        );
        insert row;
        return [SELECT Id, Name FROM Approval_Decision_Log__c WHERE Id = :row.Id];
    }

    private static AMF_McpDecisionFacts.Result factsOf(String reference) {
        AMF_McpDecisionFacts.Request request = new AMF_McpDecisionFacts.Request();
        request.record = reference;
        return AMF_McpDecisionFacts.getFacts(new List<AMF_McpDecisionFacts.Request>{ request })[0];
    }

    @IsTest
    static void givesTheNewestDecisionsFactsUnwrittenForARecordNamedByItsNumber() {
        over(new List<AMF_ApprovalHistory.Instance>{ approved() });
        Purchase_Request__c record = insertRequest();
        Approval_Decision_Log__c row = insertRow(record.Id);

        Test.startTest();
        AMF_McpDecisionFacts.Result result = factsOf(record.Name);
        Test.stopTest();

        Assert.areEqual(AMF_McpDecisionFacts.WITH_FACTS, result.outcome, '' + result.summary);
        Assert.areEqual(row.Name, result.decisionLogName);
        Assert.areEqual(String.valueOf(record.Id), result.recordId);
        Assert.areEqual('Purchase Request ' + record.Name, result.recordLabel);
        Assert.areEqual(AMF_McpSupport.recordUrlOf(record.Id), result.recordUrl);
        Assert.isTrue(result.facts.startsWith('Record: Purchase Request ' + record.Name + '\n'), '' + result.facts);
        Assert.isTrue(result.facts.contains('Decision log row: ' + row.Name), '' + result.facts);
        Assert.isTrue(result.facts.contains('PR_High_Value_APAC'), '' + result.facts);
        Assert.isTrue(result.facts.contains('PR_Three_Level_Finance'), '' + result.facts);
        Assert.isNull(result.summary);
    }

    @IsTest
    static void aDecisionLogRowsNameNamesThatDecision() {
        over(new List<AMF_ApprovalHistory.Instance>{ approved() });
        Purchase_Request__c record = insertRequest();
        Approval_Decision_Log__c row = insertRow(record.Id);

        AMF_McpDecisionFacts.Result result = factsOf(' ' + row.Name.toLowerCase() + ' ');

        Assert.areEqual(AMF_McpDecisionFacts.WITH_FACTS, result.outcome, '' + result.summary);
        Assert.areEqual(row.Name, result.decisionLogName);
        Assert.areEqual(String.valueOf(record.Id), result.recordId);
        Assert.isTrue(result.facts.contains('Decision log row: ' + row.Name), '' + result.facts);
    }

    @IsTest
    static void everyCaseWithoutFactsIsAnsweredNotThrown() {
        over(new List<AMF_ApprovalHistory.Instance>());
        Purchase_Request__c neverSubmitted = insertRequest();

        AMF_McpDecisionFacts.Result notSubmitted = factsOf(neverSubmitted.Name);
        AMF_McpDecisionFacts.Result noSuchRow = factsOf('ADL-99999999');
        AMF_McpDecisionFacts.Result noSuchRecord = factsOf('PR-99999999');

        Assert.areEqual(AMF_McpDecisionFacts.WITHOUT_FACTS, notSubmitted.outcome);
        Assert.isTrue(notSubmitted.summary.contains('has not been submitted for approval yet'), '' + notSubmitted.summary);
        Assert.areEqual(String.valueOf(neverSubmitted.Id), notSubmitted.recordId);
        Assert.isNull(notSubmitted.facts);

        Assert.areEqual(AMF_McpDecisionFacts.WITHOUT_FACTS, noSuchRow.outcome);
        Assert.isTrue(noSuchRow.summary.contains('ADL-99999999 is not visible to you'), '' + noSuchRow.summary);
        Assert.isNull(noSuchRow.recordId);

        Assert.areEqual(AMF_McpSupport.NOT_FOUND, noSuchRecord.outcome);
        Assert.areEqual(0, AMF_McpDecisionFacts.getFacts(null).size());
    }

    @IsTest
    static void theGeneratorHandsTheFactsBackUnwritten() {
        Assert.areEqual('Record: X\nOutcome: Submitted.', new AMF_McpFactsOnly().generate('Record: X\nOutcome: Submitted.', 'Why?'));
    }
}
