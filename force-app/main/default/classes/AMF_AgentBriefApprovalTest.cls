/**
 * The assistant's Brief Approver action (M14): a briefing for the approver an
 * approval is waiting on, and every other case answered rather than thrown.
 *
 * Architecture section: 8 (its M14 note), 7 (its M14 note), 10.
 *
 * The action briefs through its explainerOverride seam: real log rows, an
 * in-memory history and a generator stub. What reaches the model is
 * AMF_DecisionExplainerTest's subject; what is pinned here is the action's
 * contract with the agent.
 */
@IsTest
private class AMF_AgentBriefApprovalTest {

    private static final Datetime NINE = Datetime.newInstanceGmt(2026, 10, 21, 9, 0, 0);

    private class HistoryStub implements AMF_ApprovalHistoryProvider {
        private final List<AMF_ApprovalHistory.Instance> instances;

        private HistoryStub(List<AMF_ApprovalHistory.Instance> instances) {
            this.instances = instances;
        }

        public List<AMF_ApprovalHistory.Instance> getHistory(Id recordId, Integer maxInstances) {
            return instances;
        }
    }

    private class GeneratorStub implements AMF_ExplanationGenerator {
        public String question;
        public Exception failWith;

        public String generate(String facts, String question) {
            this.question = question;
            if (failWith != null) {
                throw failWith;
            }
            return 'Ann asks for 250,000 of APAC spend; rule PR_High_Value_APAC sent it to the finance chain.';
        }
    }

    /** An approval whose pending step is assigned to actorId. */
    private static AMF_ApprovalHistory.Instance pendingWith(Id actorId) {
        AMF_ApprovalHistory.Instance instance = new AMF_ApprovalHistory.Instance();
        instance.id = Id.valueOf('04g000000000001AAA');
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

    private static GeneratorStub overStub(List<AMF_ApprovalHistory.Instance> history) {
        GeneratorStub generator = new GeneratorStub();
        AMF_AgentBriefApproval.explainerOverride = new AMF_DecisionExplainer(
            new AMF_DecisionTimelineService(new HistoryStub(history)),
            generator
        );
        return generator;
    }

    private static Purchase_Request__c insertRequestWithRow(Id executionRefId) {
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
            Execution_Ref_Id__c = String.valueOf(executionRefId),
            Submitted_By__c = UserInfo.getUserId(),
            Submitted_At__c = NINE
        );
        return record;
    }

    private static AMF_AgentBriefApproval.Result briefOne(String recordId) {
        AMF_AgentBriefApproval.Request request = new AMF_AgentBriefApproval.Request();
        request.recordId = recordId;
        return AMF_AgentBriefApproval.brief(new List<AMF_AgentBriefApproval.Request>{ request })[0];
    }

    @IsTest
    static void briefsTheUserAnApprovalIsWaitingOn() {
        AMF_ApprovalHistory.Instance pending = pendingWith(UserInfo.getUserId());
        Purchase_Request__c record = insertRequestWithRow(pending.id);
        GeneratorStub generator = overStub(new List<AMF_ApprovalHistory.Instance>{ pending });

        Test.startTest();
        AMF_AgentBriefApproval.Result result = briefOne(record.Id);
        Test.stopTest();

        Assert.isTrue(result.briefed, result.briefing);
        Assert.isTrue(result.briefing.startsWith('Ann asks for 250,000'), result.briefing);
        Assert.areEqual(
            [SELECT Name FROM Approval_Decision_Log__c WHERE Record_Id__c = :String.valueOf(record.Id)].Name,
            result.decisionLogName
        );
        Assert.areEqual(AMF_DecisionExplainer.BRIEFING_QUESTION, generator.question);
    }

    @IsTest
    static void saysSoWhenTheApprovalIsNotWaitingOnTheUser() {
        AMF_ApprovalHistory.Instance pending = pendingWith(Id.valueOf('005000000000001AAA'));
        Purchase_Request__c record = insertRequestWithRow(pending.id);
        GeneratorStub generator = overStub(new List<AMF_ApprovalHistory.Instance>{ pending });

        AMF_AgentBriefApproval.Result result = briefOne(record.Id);

        Assert.isFalse(result.briefed);
        Assert.isTrue(result.briefing.contains('is not waiting on you for approval'), result.briefing);
        Assert.isNull(result.decisionLogName);
        Assert.isNull(generator.question, 'Nothing was asked of the model');
    }

    @IsTest
    static void answersTextThatIsNotARecordIdAndAModelThatCannotBrief() {
        AMF_ApprovalHistory.Instance pending = pendingWith(UserInfo.getUserId());
        Purchase_Request__c record = insertRequestWithRow(pending.id);
        GeneratorStub generator = overStub(new List<AMF_ApprovalHistory.Instance>{ pending });
        generator.failWith = new AMF_ExplanationException('Plain-English explanations are not available right now.');

        AMF_AgentBriefApproval.Result notAnId = briefOne('PR-00000045');
        AMF_AgentBriefApproval.Result refused = briefOne(record.Id);

        Assert.isFalse(notAnId.briefed);
        Assert.isTrue(notAnId.briefing.contains('is not a Salesforce record Id'), notAnId.briefing);
        Assert.isFalse(refused.briefed);
        Assert.areEqual('Plain-English explanations are not available right now.', refused.briefing);
        Assert.isTrue(AMF_AgentBriefApproval.brief(null).isEmpty());
    }
}
