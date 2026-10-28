/**
 * The plain-English explanation's unit suite (M13): what reaches the model,
 * and what the reader is told when nothing can.
 *
 * Architecture section: 8 (auditability, and its M13 note), 10, 11.
 *
 * The model is a stub that records the facts and the question it was given, so
 * these tests pin exactly what an explanation can be built from: the
 * timeline's view of one decision and nothing else. Log rows are inserted
 * directly, shaped as AMF_DecisionLogWriter writes them, and the native half
 * comes from an in-memory history, as in AMF_DecisionTimelineServiceTest. No
 * rule is evaluated and Einstein is never called.
 */
@IsTest
private class AMF_DecisionExplainerTest {

    private static final Datetime NINE = Datetime.newInstanceGmt(2026, 9, 25, 9, 0, 0);
    private static final String THREE_LEVEL = 'PR_Three_Level_Finance';

    /** What the platform would have returned, without running an approval. */
    private class HistoryStub implements AMF_ApprovalHistoryProvider {

        private final List<AMF_ApprovalHistory.Instance> instances;

        public HistoryStub(List<AMF_ApprovalHistory.Instance> instances) {
            this.instances = instances;
        }

        public List<AMF_ApprovalHistory.Instance> getHistory(Id recordId, Integer maxInstances) {
            return instances;
        }
    }

    /** The model, replaced by a recorder. */
    private class GeneratorStub implements AMF_ExplanationGenerator {

        public String facts;
        public String question;
        public Integer calls = 0;
        public Exception failWith;
        public String answer = 'It went to the finance chain because it is a large APAC request.';

        public String generate(String facts, String question) {
            calls++;
            this.facts = facts;
            this.question = question;
            if (failWith != null) {
                throw failWith;
            }
            return answer;
        }
    }

    private static AMF_DecisionExplainer explainer(List<AMF_ApprovalHistory.Instance> history, GeneratorStub generator) {
        return new AMF_DecisionExplainer(new AMF_DecisionTimelineService(new HistoryStub(history)), generator);
    }

    private static Purchase_Request__c insertRequest() {
        Purchase_Request__c record = new Purchase_Request__c(
            Amount__c = 250000,
            Region__c = 'APAC',
            Risk_Level__c = 'Low'
        );
        insert record;
        return record;
    }

    private static String labelOf(Purchase_Request__c record) {
        return Purchase_Request__c.SObjectType.getDescribe().getLabel() +
            ' ' +
            [SELECT Name FROM Purchase_Request__c WHERE Id = :record.Id].Name;
    }

    /** A well-formed Id of the given object that names no record. */
    private static Id fakeId(Schema.SObjectType type, Integer n) {
        return Id.valueOf(type.getDescribe().getKeyPrefix() + String.valueOf(n).leftPad(12, '0'));
    }

    private static AMF_ApprovalHistory.Step step(Integer n, String status, Boolean pending, String stepName, String actor, Datetime occurredAt) {
        AMF_ApprovalHistory.Step step = new AMF_ApprovalHistory.Step();
        step.id = fakeId(ProcessInstanceStep.SObjectType, n);
        step.status = status;
        step.isPending = pending;
        step.stepName = stepName;
        step.actorId = fakeId(User.SObjectType, n);
        step.actorName = actor;
        step.originalActorId = step.actorId;
        step.originalActorName = actor;
        step.occurredAt = occurredAt;
        return step;
    }

    /** A pending approval: submitted, one step approved with a comment, the next waiting. */
    private static AMF_ApprovalHistory.Instance pendingApproval(Integer n) {
        AMF_ApprovalHistory.Instance instance = new AMF_ApprovalHistory.Instance();
        instance.id = fakeId(ProcessInstance.SObjectType, n);
        instance.processName = THREE_LEVEL;
        instance.status = 'Pending';
        instance.submittedAt = NINE;

        instance.steps.add(step(1, 'Started', false, null, 'Ann Submitter', NINE));
        AMF_ApprovalHistory.Step analyst = step(2, 'Approved', false, 'Finance Analyst', 'AMF Approver Three', NINE.addHours(2));
        analyst.comments = 'Within budget,\n  approved.';
        instance.steps.add(analyst);
        instance.steps.add(step(3, 'Pending', true, 'Finance Controller', 'AMF Approver Four', NINE.addHours(2)));
        return instance;
    }

    private static Approval_Decision_Log__c submittedRow(Id recordId, Id executionRefId, Datetime submittedAt) {
        return new Approval_Decision_Log__c(
            Record_Id__c = String.valueOf(recordId),
            Object_API_Name__c = 'Purchase_Request__c',
            Outcome__c = 'Submitted',
            Matched_Rule__c = 'PR_High_Value_APAC',
            Rule_Version__c = 3,
            Expression_Snapshot__c = 'Amount__c > 100000 && Region__c == \'APAC\'',
            Evaluated_Values__c = '{"Amount__c":250000.00,"Region__c":"APAC"}',
            Selected_Process__c = THREE_LEVEL,
            Execution_Ref_Id__c = executionRefId == null ? null : String.valueOf(executionRefId),
            Submitted_By__c = UserInfo.getUserId(),
            Submitted_At__c = submittedAt
        );
    }

    private static Approval_Decision_Log__c blockedRow(Id recordId, Datetime submittedAt) {
        return new Approval_Decision_Log__c(
            Record_Id__c = String.valueOf(recordId),
            Object_API_Name__c = 'Purchase_Request__c',
            Outcome__c = 'Blocked_No_Match',
            Evaluated_Values__c = '{"Risk_Level__c":"Low"}',
            Failure_Detail__c = 'No active rule matched this Purchase_Request__c. 2 active rule(s) were evaluated and none was true.',
            Submitted_By__c = UserInfo.getUserId(),
            Submitted_At__c = submittedAt
        );
    }

    private static void assertContains(String text, String expected) {
        Assert.isTrue(text.contains(expected), 'Expected "' + expected + '" in:\n' + text);
    }

    private static void assertLacks(String text, String unexpected) {
        Assert.isFalse(text.contains(unexpected), 'Did not expect "' + unexpected + '" in:\n' + text);
    }

    @IsTest
    static void explainsARoutedDecisionFromTheRecordedSnapshotAndTheHistoryThatFollowed() {
        Purchase_Request__c record = insertRequest();
        AMF_ApprovalHistory.Instance approval = pendingApproval(1);
        Approval_Decision_Log__c row = submittedRow(record.Id, approval.id, NINE);
        insert row;
        GeneratorStub generator = new GeneratorStub();

        Test.startTest();
        AMF_DecisionExplainer.Explanation explanation = explainer(
                new List<AMF_ApprovalHistory.Instance>{ approval },
                generator
            )
            .explain(row.Id);
        Test.stopTest();

        Assert.areEqual(generator.answer, explanation.text, 'The model\'s words, as written');
        Assert.areEqual(row.Id, explanation.logId);
        Assert.areEqual([SELECT Name FROM Approval_Decision_Log__c WHERE Id = :row.Id].Name, explanation.logName);
        Assert.isNotNull(explanation.generatedAt);
        Assert.areEqual(1, generator.calls);
        Assert.areEqual(AMF_DecisionExplainer.DEFAULT_QUESTION, generator.question);

        String facts = generator.facts;
        assertContains(facts, 'Record: ' + labelOf(record));
        assertContains(facts, 'Decision log row: ' + explanation.logName + ', recorded ');
        assertContains(facts, ' by ' + UserInfo.getName());
        assertContains(facts, 'Outcome: Submitted. The matrix routed the record to approval process ' + THREE_LEVEL + ', and the record entered it.');
        assertContains(facts, 'Rule that decided the route: PR_High_Value_APAC, version 3');
        assertContains(facts, 'Rule condition, as recorded: Amount__c > 100000 && Region__c == \'APAC\'');
        assertContains(
            facts,
            'Field values the rule read: Amount (Amount__c) = ' + Decimal.valueOf(250000).format() + '; Region (Region__c) = APAC'
        );
        assertContains(facts, 'Approval process: ' + THREE_LEVEL + ', status: in approval, still pending');
        assertContains(facts, '- Submitted by Ann Submitter, ');
        assertContains(facts, '- Step "Finance Analyst": approved by AMF Approver Three, ');
        assertContains(facts, 'Comment: "Within budget, approved."');
        assertContains(facts, '- Step "Finance Controller": waiting on AMF Approver Four since ');
        assertLacks(facts, 'Recorded reason');
    }

    @IsTest
    static void explainsABlockedAttemptAsNeverSubmittedWithItsRecordedReason() {
        Purchase_Request__c record = insertRequest();
        Approval_Decision_Log__c row = blockedRow(record.Id, NINE);
        insert row;
        GeneratorStub generator = new GeneratorStub();

        explainer(new List<AMF_ApprovalHistory.Instance>(), generator).explain(row.Id);

        String facts = generator.facts;
        assertContains(facts, 'Outcome: Blocked. No active rule matched, so the matrix blocked the submission instead of routing it by default.');
        assertContains(facts, 'The record did not enter an approval process.');
        assertContains(facts, 'Field values the matrix read while checking every rule: Risk Level (Risk_Level__c) = Low');
        assertContains(facts, 'Recorded reason: No active rule matched this Purchase_Request__c.');
        assertLacks(facts, 'Approval process:');
        assertLacks(facts, 'Rule that decided');
    }

    @IsTest
    static void explainsAFailedAttemptByTheFirstLineOfItsReasonAndTheRuleItWasApplying() {
        Purchase_Request__c record = insertRequest();
        Approval_Decision_Log__c row = new Approval_Decision_Log__c(
            Record_Id__c = String.valueOf(record.Id),
            Object_API_Name__c = 'Purchase_Request__c',
            Outcome__c = 'Failed',
            Matched_Rule__c = 'PR_High_Risk',
            Rule_Version__c = 2,
            Selected_Process__c = THREE_LEVEL,
            Evaluated_Values__c = '{"Risk_Level__c":"High"}',
            Failure_Detail__c = 'Approval process ' + THREE_LEVEL + ' refused the submission: NO_APPLICABLE_PROCESS: none\nClass.AMF_ClassicProcessStrategy.submit: line 1',
            Submitted_By__c = UserInfo.getUserId(),
            Submitted_At__c = NINE
        );
        insert row;
        GeneratorStub generator = new GeneratorStub();

        explainer(new List<AMF_ApprovalHistory.Instance>(), generator).explain(row.Id);

        String facts = generator.facts;
        assertContains(facts, 'Outcome: Failed. The record did not enter an approval process.');
        assertContains(facts, 'Rule the matrix was applying: PR_High_Risk, version 2');
        assertContains(facts, 'Approval process the matrix chose: ' + THREE_LEVEL);
        assertContains(facts, 'Recorded reason: Approval process ' + THREE_LEVEL + ' refused the submission: NO_APPLICABLE_PROCESS: none');
        assertLacks(facts, 'Class.AMF_ClassicProcessStrategy');
        assertLacks(facts, 'Approval history: not available');
    }

    @IsTest
    static void tellsTheModelWhatTheCatchAllReadAndWhatAnUnreadableSnapshotHeld() {
        Purchase_Request__c record = insertRequest();
        Approval_Decision_Log__c catchAll = submittedRow(record.Id, null, NINE);
        catchAll.Matched_Rule__c = 'PR_Catch_All';
        catchAll.Rule_Version__c = null;
        catchAll.Expression_Snapshot__c = 'TRUE';
        catchAll.Evaluated_Values__c = '{}';
        Approval_Decision_Log__c garbled = submittedRow(record.Id, null, NINE.addMinutes(-5));
        garbled.Evaluated_Values__c = 'not json';
        insert new List<Approval_Decision_Log__c>{ catchAll, garbled };
        GeneratorStub generator = new GeneratorStub();
        AMF_DecisionExplainer subject = explainer(new List<AMF_ApprovalHistory.Instance>(), generator);

        subject.explain(catchAll.Id);
        assertContains(generator.facts, 'Rule that decided the route: PR_Catch_All\n');
        assertContains(generator.facts, 'Field values the rule read: none. Its condition reads no fields, so it matches every record.');
        assertContains(generator.facts, 'Approval history: not available.');

        subject.explain(garbled.Id);
        assertContains(generator.facts, 'Field values the rule read: as recorded, not json');
    }

    @IsTest
    static void describesEveryKindOfStepAsTheTimelineNamesIt() {
        Purchase_Request__c record = insertRequest();
        AMF_ApprovalHistory.Instance approval = new AMF_ApprovalHistory.Instance();
        approval.id = fakeId(ProcessInstance.SObjectType, 2);
        approval.processName = THREE_LEVEL;
        approval.status = 'Rejected';
        approval.steps.add(step(10, 'Started', false, null, 'Ann Submitter', NINE));
        approval.steps.add(step(11, 'Removed', false, null, 'Ann Submitter', NINE.addMinutes(1)));
        approval.steps.add(step(12, 'NoResponse', false, 'Committee', 'AMF Approver Two', NINE.addMinutes(2)));
        AMF_ApprovalHistory.Step delegated = step(13, 'Rejected', false, 'Committee', 'Dee Legate', NINE.addMinutes(3));
        delegated.originalActorId = fakeId(User.SObjectType, 99);
        delegated.originalActorName = 'AMF Approver One';
        approval.steps.add(delegated);
        AMF_ApprovalHistory.Step anonymous = step(14, null, false, null, null, null);
        approval.steps.add(anonymous);
        insert submittedRow(record.Id, approval.id, NINE);
        GeneratorStub generator = new GeneratorStub();

        explainer(new List<AMF_ApprovalHistory.Instance>{ approval }, generator).explainLatest(record.Id, null);

        String facts = generator.facts;
        assertContains(facts, 'status: rejected, final');
        assertContains(facts, '- Recalled by Ann Submitter, ');
        assertContains(facts, '- Step "Committee": no response from AMF Approver Two; another approver decided the step, ');
        assertContains(facts, '- Step "Committee": rejected by Dee Legate, for AMF Approver One, ');
        assertContains(facts, '- unknown by an unknown user, at an unknown time');
    }

    @IsTest
    static void explainsTheNewestAttemptOnARecordAndPassesTheQuestionOnAsAsked() {
        Purchase_Request__c record = insertRequest();
        AMF_ApprovalHistory.Instance approval = pendingApproval(3);
        Approval_Decision_Log__c older = blockedRow(record.Id, NINE.addDays(-1));
        Approval_Decision_Log__c newer = submittedRow(record.Id, approval.id, NINE);
        insert new List<Approval_Decision_Log__c>{ older, newer };
        GeneratorStub generator = new GeneratorStub();

        AMF_DecisionExplainer.Explanation explanation = explainer(
                new List<AMF_ApprovalHistory.Instance>{ approval },
                generator
            )
            .explainLatest(record.Id, '  Why is it\n  with   finance?  ');

        Assert.areEqual(newer.Id, explanation.logId, 'The newest attempt');
        Assert.areEqual('Why is it with finance?', generator.question, 'The question, tidied but not reworded');
        assertContains(generator.facts, 'Outcome: Submitted.');
        assertLacks(generator.facts, 'Outcome: Blocked.');
    }

    @IsTest
    static void defaultsABlankQuestionAndCutsALongOne() {
        Purchase_Request__c record = insertRequest();
        insert blockedRow(record.Id, NINE);
        GeneratorStub generator = new GeneratorStub();
        AMF_DecisionExplainer subject = explainer(new List<AMF_ApprovalHistory.Instance>(), generator);

        subject.explainLatest(record.Id, '   ');
        Assert.areEqual(AMF_DecisionExplainer.DEFAULT_QUESTION, generator.question);

        subject.explainLatest(record.Id, 'w'.repeat(AMF_DecisionExplainer.MAX_QUESTION_LENGTH + 100));
        Assert.areEqual(AMF_DecisionExplainer.MAX_QUESTION_LENGTH, generator.question.length());
    }

    @IsTest
    static void explainsAnApprovalWhoseReasonTheReaderCannotSeeWithoutGuessingIt() {
        Purchase_Request__c record = insertRequest();
        GeneratorStub generator = new GeneratorStub();

        AMF_DecisionExplainer.Explanation explanation = explainer(
                new List<AMF_ApprovalHistory.Instance>{ pendingApproval(4) },
                generator
            )
            .explainLatest(record.Id, null);

        Assert.isNull(explanation.logId);
        Assert.isNull(explanation.logName);
        assertContains(generator.facts, 'Routing decision: not visible to the reader.');
        assertContains(generator.facts, 'Approval process: ' + THREE_LEVEL);
        assertLacks(generator.facts, 'Rule that decided');
    }

    @IsTest
    static void saysSoWhenARecordWasNeverSubmittedAndAsksTheModelNothing() {
        Purchase_Request__c record = insertRequest();
        GeneratorStub generator = new GeneratorStub();

        try {
            explainer(new List<AMF_ApprovalHistory.Instance>(), generator).explainLatest(record.Id, null);
            Assert.fail('Expected AMF_ExplanationException');
        } catch (AMF_ExplanationException e) {
            Assert.areEqual(
                labelOf(record) + ' has not been submitted for approval yet, so there is no decision to explain.',
                e.getMessage()
            );
        }
        Assert.areEqual(0, generator.calls);
    }

    @IsTest
    static void refusesADecisionTheReaderCannotOpen() {
        GeneratorStub generator = new GeneratorStub();

        try {
            explainer(new List<AMF_ApprovalHistory.Instance>(), generator)
                .explain(fakeId(Approval_Decision_Log__c.SObjectType, 1));
            Assert.fail('Expected AMF_ExplanationException');
        } catch (AMF_ExplanationException e) {
            Assert.areEqual('This decision is not visible to you, so it cannot be explained.', e.getMessage());
        }
        Assert.areEqual(0, generator.calls);
    }

    @IsTest
    static void refusesARecordTheReaderCannotReadInWordsAboutExplaining() {
        GeneratorStub generator = new GeneratorStub();

        try {
            explainer(new List<AMF_ApprovalHistory.Instance>(), generator)
                .explainLatest(fakeId(Purchase_Request__c.SObjectType, 1), null);
            Assert.fail('Expected AMF_ExplanationException');
        } catch (AMF_ExplanationException e) {
            Assert.areEqual('You need read access to this record to have its approval explained.', e.getMessage());
        }
    }

    @IsTest
    static void refusesARowThatNamesNoReadableRecord() {
        Approval_Decision_Log__c row = blockedRow(insertRequest().Id, NINE);
        row.Record_Id__c = 'not-a-record';
        insert row;

        try {
            explainer(new List<AMF_ApprovalHistory.Instance>(), new GeneratorStub()).explain(row.Id);
            Assert.fail('Expected AMF_ExplanationException');
        } catch (AMF_ExplanationException e) {
            Assert.areEqual(
                'This decision does not name a record that can be read, so it cannot be explained.',
                e.getMessage()
            );
        }
    }

    @IsTest
    static void saysSoWhenADecisionIsOlderThanTheTimelineReads() {
        Purchase_Request__c record = insertRequest();
        List<Approval_Decision_Log__c> rows = new List<Approval_Decision_Log__c>();
        for (Integer i = 0; i <= AMF_DecisionTimelineService.MAX_ENTRIES; i++) {
            rows.add(blockedRow(record.Id, NINE.addMinutes(-i)));
        }
        insert rows;
        Approval_Decision_Log__c oldest = rows[rows.size() - 1];

        try {
            explainer(new List<AMF_ApprovalHistory.Instance>(), new GeneratorStub()).explain(oldest.Id);
            Assert.fail('Expected AMF_ExplanationException');
        } catch (AMF_ExplanationException e) {
            Assert.isTrue(e.getMessage().startsWith('This decision is not among the most recent ones'), e.getMessage());
        }
    }

    @IsTest
    static void refusesNothingToExplain() {
        AMF_DecisionExplainer subject = explainer(new List<AMF_ApprovalHistory.Instance>(), new GeneratorStub());

        try {
            subject.explain(null);
            Assert.fail('Expected AMF_ExplanationException for a null decision');
        } catch (AMF_ExplanationException e) {
            Assert.areEqual('A decision is required to explain.', e.getMessage());
        }
        try {
            subject.explainLatest(null, null);
            Assert.fail('Expected AMF_ExplanationException for a null record');
        } catch (AMF_ExplanationException e) {
            Assert.areEqual('A record is required to explain its approval.', e.getMessage());
        }
    }

    @IsTest
    static void passesTheModelsRefusalToTheReaderAsItIs() {
        Purchase_Request__c record = insertRequest();
        Approval_Decision_Log__c row = blockedRow(record.Id, NINE);
        insert row;
        GeneratorStub generator = new GeneratorStub();
        generator.failWith = new AMF_ExplanationException('Einstein is switched off in this org.');

        try {
            explainer(new List<AMF_ApprovalHistory.Instance>(), generator).explain(row.Id);
            Assert.fail('Expected AMF_ExplanationException');
        } catch (AMF_ExplanationException e) {
            Assert.areEqual('Einstein is switched off in this org.', e.getMessage());
        }
    }

    @IsTest
    static void theRecordPageGetsTheReasonAsAHandledErrorItCanShow() {
        // Production wiring, stopped before any model is called: the row is not visible.
        try {
            AMF_DecisionExplainer.explainDecision(fakeId(Approval_Decision_Log__c.SObjectType, 2));
            Assert.fail('Expected AuraHandledException');
        } catch (AuraHandledException e) {
            Assert.areEqual('This decision is not visible to you, so it cannot be explained.', e.getMessage());
        }
    }

    @IsTest
    static void namesARecordByItsNameAndFallsBackToItsId() {
        Purchase_Request__c record = insertRequest();
        Id missing = fakeId(Purchase_Request__c.SObjectType, 7);

        Assert.areEqual(labelOf(record), AMF_DecisionExplainer.recordLabelOf(record.Id));
        Assert.areEqual(
            Purchase_Request__c.SObjectType.getDescribe().getLabel() + ' ' + missing,
            AMF_DecisionExplainer.recordLabelOf(missing)
        );
    }

    @IsTest
    static void readsRecordedValuesAsTheTimelineShowsThem() {
        AMF_DecisionTimelineService.Value value = new AMF_DecisionTimelineService.Value();

        value.kind = 'number';
        value.text = '2400000.00';
        Assert.areEqual(Decimal.valueOf(2400000).format(), AMF_DecisionExplainer.displayOf(value));
        value.text = '12.50';
        Assert.areEqual(Decimal.valueOf('12.5').format(), AMF_DecisionExplainer.displayOf(value));
        value.text = 'not a number';
        Assert.areEqual('not a number', AMF_DecisionExplainer.displayOf(value));
        value.text = null;
        Assert.areEqual('', AMF_DecisionExplainer.displayOf(value));

        value.kind = 'boolean';
        value.text = 'true';
        Assert.areEqual('TRUE', AMF_DecisionExplainer.displayOf(value));
        value.text = 'false';
        Assert.areEqual('FALSE', AMF_DecisionExplainer.displayOf(value));

        value.kind = 'blank';
        Assert.areEqual('(blank)', AMF_DecisionExplainer.displayOf(value));

        value.kind = 'unresolved';
        Assert.areEqual('(no related record)', AMF_DecisionExplainer.displayOf(value));

        value.kind = 'text';
        value.text = 'APAC';
        Assert.areEqual('APAC', AMF_DecisionExplainer.displayOf(value));
    }

    // ── M14: the approver's briefing ───────────────────────────────────────────

    @IsTest
    static void describesAReassignedStepByWhomItWentToNotByWhoMovedIt() {
        // As amf-dev recorded it (technical log M14): the row's actor is the new
        // assignee, its original actor the step's first one, and who reassigned it
        // is not recorded. "Reassigned by X, for Y" read to the model as X handing
        // the step to Y, the wrong way round.
        Purchase_Request__c record = insertRequest();
        AMF_ApprovalHistory.Instance approval = pendingApproval(4);
        AMF_ApprovalHistory.Step moved = step(20, 'Reassigned', false, 'Manager', 'AMF Approver Two', NINE.addHours(3));
        moved.originalActorId = fakeId(User.SObjectType, 98);
        moved.originalActorName = 'AMF Approver One';
        approval.steps.add(moved);
        AMF_ApprovalHistory.Step unmoved = step(21, 'Reassigned', false, 'Manager', 'AMF Approver Two', NINE.addHours(4));
        approval.steps.add(unmoved);
        insert submittedRow(record.Id, approval.id, NINE);
        GeneratorStub generator = new GeneratorStub();

        explainer(new List<AMF_ApprovalHistory.Instance>{ approval }, generator).explainLatest(record.Id, null);

        assertContains(generator.facts, '- Step "Manager": reassigned to AMF Approver Two (first assigned to AMF Approver One), ');
        assertContains(generator.facts, '- Step "Manager": reassigned to AMF Approver Two, ');
        assertLacks(generator.facts, 'reassigned by');
    }

    @IsTest
    static void briefsTheApproverItWaitsOnFromTheSameFactsWithTheirQuestion() {
        Purchase_Request__c record = insertRequest();
        AMF_ApprovalHistory.Instance pending = pendingApproval(1);
        pending.steps[2].actorId = UserInfo.getUserId();
        pending.steps[2].actorName = UserInfo.getName();
        Approval_Decision_Log__c row = submittedRow(record.Id, pending.id, NINE);
        insert row;

        GeneratorStub generator = new GeneratorStub();

        Test.startTest();
        AMF_DecisionExplainer.Explanation briefing = explainer(
            new List<AMF_ApprovalHistory.Instance>{ pending },
            generator
        ).briefLatest(record.Id);
        Test.stopTest();

        Assert.areEqual(generator.answer, briefing.text);
        Assert.areEqual(row.Id, briefing.logId);
        Assert.isNotNull(briefing.generatedAt);
        Assert.areEqual(AMF_DecisionExplainer.BRIEFING_QUESTION, generator.question, 'The approver\'s question');
        assertContains(generator.question, 'Do not tell me whether to approve or reject');

        assertContains(generator.facts, 'Record: ' + labelOf(record));
        assertContains(generator.facts, 'Rule that decided the route: PR_High_Value_APAC, version 3');
        assertContains(generator.facts, 'Step "Finance Controller": waiting on ' + UserInfo.getName());
        Assert.isTrue(
            generator.facts.endsWith('\nReader: ' + UserInfo.getName() + ', the approver this approval is waiting on now.'),
            generator.facts
        );
    }

    @IsTest
    static void refusesABriefingWhenTheApprovalIsNotWaitingOnTheReader() {
        Purchase_Request__c record = insertRequest();
        AMF_ApprovalHistory.Instance pending = pendingApproval(1);
        insert submittedRow(record.Id, pending.id, NINE);
        GeneratorStub generator = new GeneratorStub();

        try {
            explainer(new List<AMF_ApprovalHistory.Instance>{ pending }, generator).briefLatest(record.Id);
            Assert.fail('Waiting on AMF Approver Four, not on the reader');
        } catch (AMF_ExplanationException e) {
            Assert.areEqual(
                labelOf(record) + ' is not waiting on you for approval, so there is nothing for you to decide. ' +
                'You can still ask why it went where it did.',
                e.getMessage()
            );
        }
        Assert.areEqual(0, generator.calls, 'Nothing is asked of the model');

        try {
            explainer(new List<AMF_ApprovalHistory.Instance>(), generator).briefLatest(null);
            Assert.fail('Expected a refusal');
        } catch (AMF_ExplanationException e) {
            Assert.isTrue(e.getMessage().contains('record is required'), e.getMessage());
        }
    }
}
