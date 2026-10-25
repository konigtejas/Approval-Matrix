/**
 * The assistant's Explain Approval Decision action (M13): the record page's
 * explanation, asked as the user asked it, with every failure answered rather
 * than thrown.
 *
 * Architecture section: 8 (its M13 note), 7 (its M13 note), 10.
 *
 * The action explains through its explainerOverride seam: real log rows, an
 * in-memory history and a generator stub. What reaches the model is
 * AMF_DecisionExplainerTest's subject; what is pinned here is the action's
 * contract with the agent.
 */
@IsTest
private class AMF_AgentExplainDecisionTest {

    private class HistoryStub implements AMF_ApprovalHistoryProvider {
        public List<AMF_ApprovalHistory.Instance> getHistory(Id recordId, Integer maxInstances) {
            return new List<AMF_ApprovalHistory.Instance>();
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
            return 'No rule matched this request, so it was not submitted.';
        }
    }

    private static GeneratorStub overStub() {
        GeneratorStub generator = new GeneratorStub();
        AMF_AgentExplainDecision.explainerOverride = new AMF_DecisionExplainer(
            new AMF_DecisionTimelineService(new HistoryStub()),
            generator
        );
        return generator;
    }

    private static Purchase_Request__c insertRequest() {
        Purchase_Request__c record = new Purchase_Request__c(Amount__c = 500, Region__c = 'EMEA', Risk_Level__c = 'Low');
        insert record;
        return record;
    }

    private static Approval_Decision_Log__c insertBlockedRow(Id recordId) {
        Approval_Decision_Log__c row = new Approval_Decision_Log__c(
            Record_Id__c = String.valueOf(recordId),
            Object_API_Name__c = 'Purchase_Request__c',
            Outcome__c = 'Blocked_No_Match',
            Evaluated_Values__c = '{"Risk_Level__c":"Low"}',
            Failure_Detail__c = 'No active rule matched this Purchase_Request__c.',
            Submitted_By__c = UserInfo.getUserId(),
            Submitted_At__c = Datetime.now()
        );
        insert row;
        return row;
    }

    private static AMF_AgentExplainDecision.Result explainOne(String recordId, String question) {
        AMF_AgentExplainDecision.Request request = new AMF_AgentExplainDecision.Request();
        request.recordId = recordId;
        request.question = question;
        return AMF_AgentExplainDecision.explain(new List<AMF_AgentExplainDecision.Request>{ request })[0];
    }

    @IsTest
    static void explainsTheNewestDecisionAsTheUserAskedAndNamesItsRow() {
        Purchase_Request__c record = insertRequest();
        Approval_Decision_Log__c row = insertBlockedRow(record.Id);
        GeneratorStub generator = overStub();

        Test.startTest();
        AMF_AgentExplainDecision.Result result = explainOne(record.Id, 'Why was this not sent for approval?');
        Test.stopTest();

        Assert.isTrue(result.explained);
        Assert.areEqual('No rule matched this request, so it was not submitted.', result.explanation);
        Assert.areEqual([SELECT Name FROM Approval_Decision_Log__c WHERE Id = :row.Id].Name, result.decisionLogName);
        Assert.areEqual('Why was this not sent for approval?', generator.question);
    }

    @IsTest
    static void aRecordNeverSubmittedIsAnsweredWithTheReason() {
        Purchase_Request__c record = insertRequest();
        overStub();

        AMF_AgentExplainDecision.Result result = explainOne(record.Id, null);

        Assert.isFalse(result.explained);
        Assert.isTrue(result.explanation.endsWith('has not been submitted for approval yet, so there is no decision to explain.'), result.explanation);
        Assert.isNull(result.decisionLogName);
    }

    @IsTest
    static void aModelThatCannotAnswerIsReportedNotThrown() {
        Purchase_Request__c record = insertRequest();
        insertBlockedRow(record.Id);
        GeneratorStub generator = overStub();
        generator.failWith = new AMF_ExplanationException('Plain-English explanations are not available right now.');

        AMF_AgentExplainDecision.Result result = explainOne(record.Id, null);

        Assert.isFalse(result.explained);
        Assert.areEqual('Plain-English explanations are not available right now.', result.explanation);
    }

    @IsTest
    static void textThatIsNotARecordIdIsAnsweredNotThrown() {
        overStub();

        AMF_AgentExplainDecision.Result result = explainOne('the APAC laptops request', null);

        Assert.isFalse(result.explained);
        Assert.areEqual(
            'The approval cannot be explained: "the APAC laptops request" is not a Salesforce record Id. Look the ' +
            'record up by its name or number first.',
            result.explanation
        );
        Assert.isTrue(AMF_AgentExplainDecision.explain(null).isEmpty());
    }

    @IsTest
    static void theProductionWiringRefusesARecordTheUserCannotReadBeforeAskingAnyModel() {
        // No override: the explainer as the agent gets it. A record that does not
        // exist is one the user cannot read, so Einstein is never reached.
        Id missing = Id.valueOf(Purchase_Request__c.SObjectType.getDescribe().getKeyPrefix() + '000000000001');

        AMF_AgentExplainDecision.Result result = explainOne(missing, null);

        Assert.isFalse(result.explained);
        Assert.areEqual('You need read access to this record to have its approval explained.', result.explanation);
    }
}
