/**
 * The Claude connector's get_briefing_facts tool (M16): the briefing's facts,
 * for the approver an approval is waiting on and nobody else.
 *
 * Architecture section: 8 (its M14 note), 7 (its M16 note), 10.
 *
 * Real decision log rows, an in-memory approval history through the tool's
 * timelineOverride seam, and Find Governed Record over in-memory rules, as
 * AMF_AgentBriefApprovalTest briefs. Who counts as the approver is
 * AMF_ApproverScopeTest's subject.
 */
@IsTest
private class AMF_McpBriefingFactsTest {

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

    /** An approval whose pending step is assigned to actorId. */
    private static AMF_ApprovalHistory.Instance pendingWith(Id actorId) {
        AMF_ApprovalHistory.Instance instance = new AMF_ApprovalHistory.Instance();
        instance.id = INSTANCE_ID;
        instance.processName = 'PR_Three_Level_Finance';
        instance.status = 'Pending';
        instance.submittedAt = NINE;

        AMF_ApprovalHistory.Step step = new AMF_ApprovalHistory.Step();
        step.status = 'Pending';
        step.isPending = true;
        step.stepName = 'Finance Analyst';
        step.actorId = actorId;
        step.actorName = 'Someone';
        step.occurredAt = NINE;
        instance.steps.add(step);
        return instance;
    }

    private static void over(List<AMF_ApprovalHistory.Instance> history) {
        AMF_McpBriefingFacts.timelineOverride = new AMF_DecisionTimelineService(new HistoryStub(history));
        AMF_AgentFindRecord.ruleProviderOverride = new AMF_RuleBuilder.Stub(
            new List<AMF_RuleDefinition>{ new AMF_RuleBuilder().named('PR_High_Value_APAC').withPriority(10).build() }
        );
    }

    private static Purchase_Request__c insertRequestWithRow() {
        Purchase_Request__c record = new Purchase_Request__c(Amount__c = 250000, Region__c = 'APAC', Risk_Level__c = 'Low');
        insert record;
        insert new Approval_Decision_Log__c(
            Record_Id__c = String.valueOf(record.Id),
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
        return [SELECT Id, Name FROM Purchase_Request__c WHERE Id = :record.Id];
    }

    private static AMF_McpBriefingFacts.Result briefingOf(String reference) {
        AMF_McpBriefingFacts.Request request = new AMF_McpBriefingFacts.Request();
        request.record = reference;
        return AMF_McpBriefingFacts.getFacts(new List<AMF_McpBriefingFacts.Request>{ request })[0];
    }

    @IsTest
    static void givesTheApproverItIsWaitingOnTheFactsAndSaysWhoIsReading() {
        over(new List<AMF_ApprovalHistory.Instance>{ pendingWith(UserInfo.getUserId()) });
        Purchase_Request__c record = insertRequestWithRow();

        Test.startTest();
        AMF_McpBriefingFacts.Result result = briefingOf(record.Name);
        Test.stopTest();

        Assert.areEqual(AMF_McpBriefingFacts.WITH_FACTS, result.outcome, '' + result.summary);
        Assert.isTrue(result.facts.contains('PR_High_Value_APAC'), '' + result.facts);
        Assert.isTrue(
            result.facts.endsWith('\nReader: ' + UserInfo.getName() + ', the approver this approval is waiting on now.'),
            result.facts
        );
        Assert.areEqual(
            [SELECT Name FROM Approval_Decision_Log__c WHERE Record_Id__c = :String.valueOf(record.Id)].Name,
            result.decisionLogName
        );
        Assert.areEqual(AMF_McpSupport.recordUrlOf(record.Id), result.recordUrl);
    }

    @IsTest
    static void someoneElsesApprovalHasNoBriefing() {
        over(new List<AMF_ApprovalHistory.Instance>{ pendingWith(Id.valueOf('005000000000001AAA')) });
        Purchase_Request__c record = insertRequestWithRow();

        AMF_McpBriefingFacts.Result result = briefingOf(record.Name);

        Assert.areEqual(AMF_McpBriefingFacts.WITHOUT_FACTS, result.outcome);
        Assert.isTrue(result.summary.contains('is not waiting on you for approval'), '' + result.summary);
        Assert.isNull(result.facts);
        Assert.isNull(result.decisionLogName);
        Assert.areEqual(String.valueOf(record.Id), result.recordId);
    }

    @IsTest
    static void aReferenceThatIsNotOneRecordIsAnswered() {
        over(new List<AMF_ApprovalHistory.Instance>());

        AMF_McpBriefingFacts.Result result = briefingOf('PR-99999999');

        Assert.areEqual(AMF_McpSupport.NOT_FOUND, result.outcome);
        Assert.isNull(result.facts);
        Assert.areEqual(0, AMF_McpBriefingFacts.getFacts(null).size());
    }
}
