/**
 * The queue and committee templates, against the real platform (M12).
 *
 * Architecture section: 5.2 (Classic templates), 5.4 (queue and group steps),
 * 5.5 (shapes are processes), 6.3 (the guard), 8 (who acted), 9 (the
 * validator), 10 ("one thin integration test per template exercises the real
 * path"), 11 (approvers need read access to the record).
 *
 * WHAT THIS CLASS PROVES: that the two approver shapes M12 adds behave as their
 * templates say, and that nothing upstream of the template had to know. The
 * engine routes to PR_Credit_Risk_Queue and PR_Finance_Committee exactly as to
 * any other process; what differs is the platform's, and that is what is
 * tested: a queue step that any member decides, and only a member, directly
 * or through a public group; a committee step that needs every member,
 * followed by a step that needs any one leader; one committee rejection that
 * ends the request; and the guard re-armed on every way out of both.
 *
 * ORG DEPENDENCE IS DELIBERATE AND LOCAL, as in AMF_SubmissionIntegrationTest.
 * Both templates are repo metadata and must be active. The queue template names
 * the queue Q_Credit_Risk, so each queue test adds its own member, a user it
 * creates, rather than relying on the seeded membership. The committee template
 * names the seeded users amfu1 to amfu5 by username, which is the shape
 * (Classic cannot assign a step to a public group), so its tests act as
 * whichever users the platform assigned, read from the work items. Every
 * approver is given read access to the record first, as 11 requires of an
 * adopting org: assignment creates no share. The RULES are in-memory copies of
 * the shipped PR rows, so CLAUDE.md's "zero dependence on org CMDT rows" holds.
 *
 * Actor names are not asserted: inside a test transaction the platform returns
 * them null for history it has just written (technical log, the fix after M8).
 */
@IsTest
private class AMF_TemplateShapesTest {

    private static final String QUEUE_TEMPLATE = 'PR_Credit_Risk_Queue';
    private static final String COMMITTEE_TEMPLATE = 'PR_Finance_Committee';
    private static final String CREDIT_RISK_QUEUE = 'Q_Credit_Risk';

    @IsTest
    static void theShippedMatrixPutsCommitteeSpendFirstAndMediumRiskToTheQueue() {
        // The two new rows in their places among the shipped ones: a million
        // outranks every other rule, and the queue takes medium risk before the
        // catch-all does. A preview, so nothing is submitted or written.
        List<Purchase_Request__c> requests = new List<Purchase_Request__c>{
            request(1200000, 'APAC', 'High'),
            request(150000, 'APAC', 'Low'),
            request(60000, 'AMER', 'Medium'),
            request(40000, 'AMER', 'Medium'),
            request(60000, 'AMER', 'High')
        };
        insert requests;
        List<Id> ids = new List<Id>();
        for (Purchase_Request__c record : requests) {
            ids.add(record.Id);
        }

        Test.startTest();
        List<AMF_ApprovalMatrixService.Outcome> outcomes = shippedMatrix().preview(ids);
        Test.stopTest();

        assertPreviewed(outcomes[0], 'PR_Committee_Spend', COMMITTEE_TEMPLATE);
        assertPreviewed(outcomes[1], 'PR_High_Value_APAC', 'PR_Three_Level_Finance');
        assertPreviewed(outcomes[2], 'PR_Credit_Risk_Review', QUEUE_TEMPLATE);
        assertPreviewed(outcomes[3], 'PR_Catch_All', 'PR_Two_Level_Mgmt');
        assertPreviewed(outcomes[4], 'PR_High_Risk', 'PR_Three_Level_Finance');
        Assert.areEqual(0, [SELECT COUNT() FROM Approval_Decision_Log__c], 'A preview writes nothing (6.4)');
    }

    @IsTest
    static void aQueueStepIsWithTheQueueAndAMemberDecidesIt() {
        requireActiveProcess(QUEUE_TEMPLATE);
        Id queueId = creditRiskQueueId();
        User member = matrixUser('amfq1', 'Queue Member');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new GroupMember(GroupId = queueId, UserOrGroupId = member.Id);
        }

        Purchase_Request__c record = request(60000, 'AMER', 'Medium');
        insert record;
        shareWith(record.Id, new Set<Id>{ member.Id });
        AMF_ApprovalMatrixService.Outcome outcome = shippedMatrix().submit(new List<Id>{ record.Id })[0];

        assertRouted(outcome, 'PR_Credit_Risk_Review', QUEUE_TEMPLATE);
        List<ProcessInstanceWorkitem> items = workItems(outcome);
        Assert.areEqual(1, items.size(), 'One work item, shared by the whole queue');
        Assert.areEqual(queueId, items[0].ActorId, 'The step is assigned to the queue, not to a person (5.4)');

        Test.startTest();
        Approval.ProcessResult decision;
        System.runAs(member) {
            decision = decide(items[0].Id, 'Approve');
        }
        Test.stopTest();

        Assert.isTrue(decision.isSuccess(), 'A queue member decides the queue\'s step: ' + decision.getErrors());
        Assert.areEqual('Approved', statusOf(outcome), 'One member\'s decision completes the one step');
        Assert.isFalse(guardOf(record.Id), 'Final approval re-arms the guard (5.2)');

        // 8: who acted is the member, on the queue's behalf, as the timeline reads it.
        AMF_ApprovalHistory.Step approval = onlyStepWithStatus(timelineOf(record.Id), 'Approved');
        Assert.areEqual(member.Id, approval.actorId, 'The true actor: the member who decided');
        Assert.areEqual(queueId, approval.originalActorId, 'On behalf of the queue the step was assigned to');
    }

    @IsTest
    static void aMemberThroughAPublicGroupCanDecideAQueueStep() {
        // Classic cannot assign a step to a public group, but a queue can hold
        // one. The seed script relies on this: it makes G_Finance_Approvers the
        // queue's member. Here a group of the test's own stands in for it. The
        // member rejects, so this is also the queue template's rejection exit.
        requireActiveProcess(QUEUE_TEMPLATE);
        Id queueId = creditRiskQueueId();
        User member = matrixUser('amfq2', 'Group Member');
        Group finance = new Group(Name = 'AMF M12 Test Group', DeveloperName = 'AMF_M12_Test_Group', Type = 'Regular');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert finance;
            insert new List<GroupMember>{
                new GroupMember(GroupId = finance.Id, UserOrGroupId = member.Id),
                new GroupMember(GroupId = queueId, UserOrGroupId = finance.Id)
            };
        }

        Purchase_Request__c record = request(60000, 'AMER', 'Medium');
        insert record;
        shareWith(record.Id, new Set<Id>{ member.Id });
        AMF_ApprovalMatrixService.Outcome outcome = shippedMatrix().submit(new List<Id>{ record.Id })[0];
        assertRouted(outcome, 'PR_Credit_Risk_Review', QUEUE_TEMPLATE);

        Test.startTest();
        Approval.ProcessResult decision;
        System.runAs(member) {
            decision = decide(workItems(outcome)[0].Id, 'Reject');
        }
        Test.stopTest();

        Assert.isTrue(decision.isSuccess(), 'A member of a group the queue holds decides its step: ' + decision.getErrors());
        Assert.areEqual('Rejected', statusOf(outcome));
        Assert.isFalse(guardOf(record.Id), 'Final rejection re-arms the guard (5.2)');
    }

    @IsTest
    static void aUserOutsideTheQueueCannotDecideItsStep() {
        // Any member is not anyone: read access to the record is not enough.
        requireActiveProcess(QUEUE_TEMPLATE);
        User outsider = matrixUser('amfq3', 'Outsider');
        Purchase_Request__c record = request(60000, 'AMER', 'Medium');
        insert record;
        shareWith(record.Id, new Set<Id>{ outsider.Id });
        AMF_ApprovalMatrixService.Outcome outcome = shippedMatrix().submit(new List<Id>{ record.Id })[0];
        assertRouted(outcome, 'PR_Credit_Risk_Review', QUEUE_TEMPLATE);

        Test.startTest();
        Boolean refused = false;
        System.runAs(outsider) {
            try {
                refused = !decide(workItems(outcome)[0].Id, 'Approve', false).isSuccess();
            } catch (Exception platformRefusal) {
                refused = true;
            }
        }
        Test.stopTest();

        Assert.isTrue(refused, 'Someone outside the queue must not be able to decide its step');
        Assert.areEqual('Pending', statusOf(outcome), 'And the request is still with the queue');
        Assert.isTrue(guardOf(record.Id), 'With the guard still set');
    }

    @IsTest
    static void theCommitteeNeedsEveryMemberThenAnyOneLeader() {
        requireActiveProcess(COMMITTEE_TEMPLATE);
        Purchase_Request__c record = request(1200000, 'AMER', 'Low');
        insert record;
        AMF_ApprovalMatrixService.Outcome outcome = shippedMatrix().submit(new List<Id>{ record.Id })[0];
        assertRouted(outcome, 'PR_Committee_Spend', COMMITTEE_TEMPLATE);

        List<ProcessInstanceWorkitem> committee = workItems(outcome);
        Set<Id> members = actorsOf(committee);
        Assert.areEqual(3, committee.size(), 'Unanimous: one work item for each of the three members');
        Assert.areEqual(3, members.size(), 'Each with a different member');
        shareWith(record.Id, members);

        Test.startTest();
        approveAs(committee[0]);
        approveAs(committee[1]);
        List<ProcessInstanceWorkitem> stillOpen = workItems(outcome);
        Assert.areEqual('Pending', statusOf(outcome), 'Two of three is not unanimous');
        Assert.areEqual(1, stillOpen.size(), 'The third member\'s work item is still open');
        Assert.areEqual(committee[2].Id, stillOpen[0].Id);

        approveAs(committee[2]);
        List<ProcessInstanceWorkitem> leadership = workItems(outcome);
        Set<Id> leaders = actorsOf(leadership);
        Assert.areEqual(2, leadership.size(), 'The last member\'s approval hands on to the two leaders');
        Assert.areEqual(2, leaders.size());
        Assert.isFalse(leaders.removeAll(members), 'The leaders are not committee members');
        shareWith(record.Id, leaders);

        approveAs(leadership[0]);
        Test.stopTest();

        Assert.areEqual('Approved', statusOf(outcome), 'First response: one leader\'s approval completes the request');
        Assert.areEqual(0, workItems(outcome).size(), 'The other leader\'s work item is withdrawn');
        Assert.isFalse(guardOf(record.Id), 'Final approval re-arms the guard (5.2)');
    }

    @IsTest
    static void oneCommitteeRejectionRejectsTheWholeRequest() {
        requireActiveProcess(COMMITTEE_TEMPLATE);
        Purchase_Request__c record = request(1200000, 'AMER', 'Low');
        insert record;
        AMF_ApprovalMatrixService.Outcome outcome = shippedMatrix().submit(new List<Id>{ record.Id })[0];
        assertRouted(outcome, 'PR_Committee_Spend', COMMITTEE_TEMPLATE);
        List<ProcessInstanceWorkitem> committee = workItems(outcome);
        shareWith(record.Id, actorsOf(committee));

        Test.startTest();
        approveAs(committee[0]);
        Approval.ProcessResult rejection;
        System.runAs(new User(Id = committee[1].ActorId)) {
            rejection = decide(committee[1].Id, 'Reject');
        }
        Test.stopTest();

        Assert.isTrue(rejection.isSuccess(), 'A committee member rejects: ' + rejection.getErrors());
        Assert.areEqual('Rejected', statusOf(outcome), 'Unanimous: one rejection ends the request');
        Assert.areEqual(0, workItems(outcome).size(), 'The third member is no longer asked');
        Assert.isFalse(guardOf(record.Id), 'Final rejection re-arms the guard (5.2)');
    }

    @IsTest
    static void theTimelineListsEveryCommitteeMemberStillToDecide() {
        // 8: a committee's pending step is three people, and the timeline says
        // so: one pending row for each, assigned to that member.
        requireActiveProcess(COMMITTEE_TEMPLATE);
        Purchase_Request__c record = request(1200000, 'AMER', 'Low');
        insert record;
        AMF_ApprovalMatrixService.Outcome outcome = shippedMatrix().submit(new List<Id>{ record.Id })[0];
        assertRouted(outcome, 'PR_Committee_Spend', COMMITTEE_TEMPLATE);

        Test.startTest();
        AMF_DecisionTimelineService.Entry entry = timelineOf(record.Id);
        Test.stopTest();

        Assert.areEqual(COMMITTEE_TEMPLATE, entry.approval.processName);
        Set<Id> pendingActors = new Set<Id>();
        for (AMF_ApprovalHistory.Step step : entry.approval.steps) {
            if (step.isPending == true) {
                pendingActors.add(step.actorId);
                Assert.areEqual(step.actorId, step.originalActorId, 'Nobody has acted for anyone yet');
            }
        }
        Assert.areEqual(actorsOf(workItems(outcome)), pendingActors, 'One pending row per member, each with that member');
    }

    @IsTest
    static void bypassingTheEngineFailsEntryCriteriaOnBothTemplates() {
        // 6.3 on the new shapes: with the guard unset, neither template admits
        // the record, so neither can be entered except through the engine.
        requireActiveProcess(QUEUE_TEMPLATE);
        requireActiveProcess(COMMITTEE_TEMPLATE);
        Purchase_Request__c record = request(1200000, 'AMER', 'Medium');
        insert record;
        List<String> refusedBy = new List<String>();

        Test.startTest();
        for (String process : new List<String>{ QUEUE_TEMPLATE, COMMITTEE_TEMPLATE }) {
            if (!bypass(record.Id, process).isSuccess()) {
                refusedBy.add(process);
            }
        }
        Test.stopTest();

        Assert.areEqual(
            new List<String>{ QUEUE_TEMPLATE, COMMITTEE_TEMPLATE },
            refusedBy,
            'Both templates must refuse a submission with the guard unset. A template missing here lost its ' +
            'Matrix_Submission__c entry criterion.'
        );
        Assert.areEqual(0, [SELECT COUNT() FROM ProcessInstance WHERE TargetObjectId = :record.Id], 'And nothing routed');
    }

    @IsTest
    static void aRecallFromEitherTemplateReArmsTheGuard() {
        // 5.2's third way out, on both templates. The submitter recalls; the
        // engine never does (6.5).
        requireActiveProcess(QUEUE_TEMPLATE);
        requireActiveProcess(COMMITTEE_TEMPLATE);
        Purchase_Request__c queued = request(60000, 'AMER', 'Medium');
        Purchase_Request__c committeeSpend = request(1200000, 'AMER', 'Low');
        insert new List<Purchase_Request__c>{ queued, committeeSpend };
        List<AMF_ApprovalMatrixService.Outcome> outcomes = shippedMatrix()
            .submitEach(new List<Id>{ queued.Id, committeeSpend.Id });
        assertRouted(outcomes[0], 'PR_Credit_Risk_Review', QUEUE_TEMPLATE);
        assertRouted(outcomes[1], 'PR_Committee_Spend', COMMITTEE_TEMPLATE);

        Test.startTest();
        for (AMF_ApprovalMatrixService.Outcome outcome : outcomes) {
            Approval.ProcessResult recall = decide(workItems(outcome)[0].Id, 'Removed');
            Assert.isTrue(recall.isSuccess(), 'The submitter recalls: ' + recall.getErrors());
        }
        Approval.ProcessResult bypassAfterRecall = bypass(queued.Id, QUEUE_TEMPLATE);
        Test.stopTest();

        for (AMF_ApprovalMatrixService.Outcome outcome : outcomes) {
            Assert.areEqual('Removed', statusOf(outcome), 'Recalled');
            Assert.isFalse(guardOf(outcome.recordId), 'Recall re-arms the guard (5.2): ' + outcome.selectedProcess);
        }
        Assert.isFalse(
            bypassAfterRecall.isSuccess(),
            'With the guard re-armed, a submission that bypasses the engine fails entry criteria again (6.3)'
        );
    }

    @IsTest
    static void theValidatorPassesTheShippedPurchaseRequestMatrixAgainstTheRealCatalog() {
        // 9 against the org: every shipped PR rule compiles, and each names an
        // active Purchase_Request__c process, the two new templates included.
        requireActiveProcess(QUEUE_TEMPLATE);
        requireActiveProcess(COMMITTEE_TEMPLATE);

        Test.startTest();
        List<AMF_ConfigValidator.Finding> findings = new AMF_ConfigValidator(
            new AMF_RuleBuilder.Stub(shippedPurchaseRequestRules()),
            new AMF_ClassicApprovalProcessProvider()
        ).validate();
        Test.stopTest();

        List<String> rendered = new List<String>();
        for (AMF_ConfigValidator.Finding finding : findings) {
            rendered.add(finding.render());
        }
        Assert.areEqual(0, findings.size(), String.join(rendered, '\n'));
    }

    /** In-memory copies of the five active shipped PR rows, field for field. */
    private static List<AMF_RuleDefinition> shippedPurchaseRequestRules() {
        return new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder()
                .named('PR_Committee_Spend')
                .withPriority(5)
                .withExpression('Amount__c >= 1000000')
                .routingTo(COMMITTEE_TEMPLATE)
                .atVersion(1)
                .build(),
            new AMF_RuleBuilder()
                .named('PR_High_Value_APAC')
                .withPriority(10)
                .withExpression('Amount__c > 100000 && Region__c == \'APAC\'')
                .routingTo('PR_Three_Level_Finance')
                .atVersion(1)
                .build(),
            new AMF_RuleBuilder()
                .named('PR_High_Risk')
                .withPriority(20)
                .withExpression('Risk_Level__c == \'High\'')
                .routingTo('PR_Three_Level_Finance')
                .atVersion(1)
                .build(),
            new AMF_RuleBuilder()
                .named('PR_Credit_Risk_Review')
                .withPriority(30)
                .withExpression('Risk_Level__c == \'Medium\' && Amount__c >= 50000')
                .routingTo(QUEUE_TEMPLATE)
                .atVersion(1)
                .build(),
            new AMF_RuleBuilder()
                .named('PR_Catch_All')
                .withPriority(9999)
                .withExpression('TRUE')
                .routingTo('PR_Two_Level_Mgmt')
                .atVersion(1)
                .build()
        };
    }

    /** The real Classic strategy behind in-memory rules: real routes, no org CMDT. */
    private static AMF_ApprovalMatrixService shippedMatrix() {
        return new AMF_ApprovalMatrixService(
            new AMF_RuleBuilder.Stub(shippedPurchaseRequestRules()),
            new AMF_ClassicProcessStrategy()
        );
    }

    private static Purchase_Request__c request(Decimal amount, String region, String risk) {
        return new Purchase_Request__c(Amount__c = amount, Region__c = region, Risk_Level__c = risk);
    }

    private static void assertPreviewed(AMF_ApprovalMatrixService.Outcome outcome, String rule, String process) {
        Assert.isFalse(outcome.submitted, 'A preview never submits');
        Assert.areEqual(rule, outcome.matchedRule, outcome.evaluatedValuesJson);
        Assert.areEqual(process, outcome.selectedProcess);
    }

    /** Submitted to its template, through the engine, with the guard set for the life of the approval. */
    private static void assertRouted(AMF_ApprovalMatrixService.Outcome outcome, String rule, String process) {
        Assert.isTrue(outcome.submitted, rule + ': ' + outcome.outcome + ' / ' + outcome.message);
        Assert.areEqual(rule, outcome.matchedRule);
        Assert.areEqual(process, outcome.selectedProcess);
        Assert.isTrue(guardOf(outcome.recordId), 'The engine staged the guard, which is how entry criteria passed (6.3)');
    }

    private static List<ProcessInstanceWorkitem> workItems(AMF_ApprovalMatrixService.Outcome outcome) {
        return [
            SELECT Id, ActorId
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstanceId = :outcome.executionRefId
            ORDER BY Id
        ];
    }

    private static Set<Id> actorsOf(List<ProcessInstanceWorkitem> items) {
        Set<Id> actors = new Set<Id>();
        for (ProcessInstanceWorkitem item : items) {
            actors.add(item.ActorId);
        }
        return actors;
    }

    private static String statusOf(AMF_ApprovalMatrixService.Outcome outcome) {
        return [SELECT Status FROM ProcessInstance WHERE Id = :outcome.executionRefId].Status;
    }

    /** A work item decided by the user it is assigned to. */
    private static void approveAs(ProcessInstanceWorkitem item) {
        Approval.ProcessResult result;
        System.runAs(new User(Id = item.ActorId)) {
            result = decide(item.Id, 'Approve');
        }
        Assert.isTrue(result.isSuccess(), 'The assigned approver approves: ' + result.getErrors());
    }

    /** Acts on a work item: Approve, Reject, or Removed (a recall). People's actions, simulated (6.5). */
    private static Approval.ProcessResult decide(Id workItemId, String action) {
        return decide(workItemId, action, true);
    }

    private static Approval.ProcessResult decide(Id workItemId, String action, Boolean allOrNone) {
        Approval.ProcessWorkitemRequest request = new Approval.ProcessWorkitemRequest();
        request.setAction(action);
        request.setWorkitemId(workItemId);
        return Approval.process(request, allOrNone);
    }

    /** A submission straight to a template, as the standard button would make it: no engine, no guard. */
    private static Approval.ProcessResult bypass(Id recordId, String processApiName) {
        Approval.ProcessSubmitRequest request = new Approval.ProcessSubmitRequest();
        request.setObjectId(recordId);
        request.setProcessDefinitionNameOrId(processApiName);
        return Approval.process(request, false);
    }

    /**
     * Read access for each approver, as 11 requires of an adopting org: the
     * object is Private, and assigning a work item creates no share.
     */
    private static void shareWith(Id recordId, Set<Id> userOrGroupIds) {
        List<Purchase_Request__Share> shares = new List<Purchase_Request__Share>();
        for (Id userOrGroupId : userOrGroupIds) {
            shares.add(
                new Purchase_Request__Share(
                    ParentId = recordId,
                    UserOrGroupId = userOrGroupId,
                    AccessLevel = 'Read',
                    RowCause = Schema.Purchase_Request__Share.RowCause.Manual
                )
            );
        }
        insert shares;
    }

    private static AMF_DecisionTimelineService.Entry timelineOf(Id recordId) {
        AMF_DecisionTimelineService.Timeline timeline = AMF_DecisionTimelineService.getTimeline(recordId);
        Assert.areEqual(1, timeline.entries.size(), 'One submission, one entry');
        Assert.isNotNull(timeline.entries[0].approval, 'Joined to its ProcessInstance (8)');
        return timeline.entries[0];
    }

    private static AMF_ApprovalHistory.Step onlyStepWithStatus(AMF_DecisionTimelineService.Entry entry, String status) {
        List<AMF_ApprovalHistory.Step> matching = new List<AMF_ApprovalHistory.Step>();
        for (AMF_ApprovalHistory.Step step : entry.approval.steps) {
            if (step.status == status) {
                matching.add(step);
            }
        }
        Assert.areEqual(1, matching.size(), 'Exactly one ' + status + ' step in ' + JSON.serialize(entry.approval.steps));
        return matching[0];
    }

    private static Id creditRiskQueueId() {
        List<Group> queues = [SELECT Id FROM Group WHERE DeveloperName = :CREDIT_RISK_QUEUE AND Type = 'Queue'];
        Assert.areEqual(
            1,
            queues.size(),
            'Queue ' + CREDIT_RISK_QUEUE + ' is not in this org. PR_Credit_Risk_Queue names it: run scripts/seed-data.apex.'
        );
        return queues[0].Id;
    }

    /** A Standard User holding Approval_Matrix_User, as every approver and submitter here does. */
    private static User matrixUser(String alias, String lastName) {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        PermissionSet matrix = [SELECT Id FROM PermissionSet WHERE Name = 'Approval_Matrix_User' LIMIT 1];
        String name = 'amf.m12.' + alias;
        User person = new User(
            Alias = alias,
            Email = name + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = lastName,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standard.Id,
            TimeZoneSidKey = 'GMT',
            Username = name + '.' + String.valueOf(Datetime.now().getTime()) + '@amf.test.invalid'
        );

        // User is a setup object: inserting one beside a Purchase_Request__c is
        // MIXED_DML_OPERATION without this wrapper.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert person;
            insert new PermissionSetAssignment(AssigneeId = person.Id, PermissionSetId = matrix.Id);
        }
        return person;
    }

    private static Boolean guardOf(Id recordId) {
        return [SELECT Matrix_Submission__c FROM Purchase_Request__c WHERE Id = :recordId].Matrix_Submission__c;
    }

    /** A missing or deactivated template, said in a sentence rather than as a refusal fifty lines later. */
    private static void requireActiveProcess(String developerName) {
        List<ProcessDefinition> definitions = [
            SELECT State
            FROM ProcessDefinition
            WHERE DeveloperName = :developerName AND Type = 'Approval'
        ];
        Assert.areEqual(
            1,
            definitions.size(),
            'Approval process ' + developerName + ' is not in this org. It is repo metadata (5.2): deploy before running tests.'
        );
        Assert.areEqual('Active', definitions[0].State, 'Approval process ' + developerName + ' is deployed but not active.');
    }
}
