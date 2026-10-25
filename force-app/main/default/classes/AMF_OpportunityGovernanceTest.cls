/**
 * Opportunity, the second governed object, against the real platform (M11).
 *
 * Architecture section: 3.2 (governing an object is configuration plus
 * conventions), 5.2 (Classic templates), 6.1, 6.3 (the guard), 8 (the join and
 * the timeline), 9 (the validator), 10 ("one thin integration test per
 * template exercises the real path").
 *
 * WHAT THIS CLASS PROVES: that the engine, the Classic strategy, the decision
 * log writer, the timeline and the validator never knew they were serving
 * Purchase_Request__c. Every test runs code M11 did not change against an
 * object M11 only configured -- a guard field, two templates, a lookup on the
 * log, field-level access. A failure here is a failure of 3.2's claim.
 *
 * ORG DEPENDENCE IS DELIBERATE AND LOCAL, as in AMF_SubmissionIntegrationTest.
 * Both templates are repo metadata and must be active. They assign the
 * SUBMITTER's manager, so each test's submitter is a Standard User created to
 * report to the running user: the approver is then a user every org has, with a
 * full license and access to Opportunities. The seeded approvers could not
 * serve: they hold Salesforce Platform licenses, which grant no Opportunity
 * access. OPP_Two_Level_Mgmt's second step would go to the running user's own
 * manager, which is org configuration, so no test goes past its first step. The
 * RULES are in-memory copies of the shipped OPP rows, so CLAUDE.md's "zero
 * dependence on org CMDT rows" holds.
 */
@IsTest
private class AMF_OpportunityGovernanceTest {

    private static final String MANAGER_APPROVAL = 'OPP_Manager_Approval';
    private static final String TWO_LEVEL = 'OPP_Two_Level_Mgmt';
    private static final String THREE_LEVEL_FINANCE = 'PR_Three_Level_Finance';

    @IsTest
    static void anOpportunitySubmittedThroughTheEngineEntersItsTemplateAndJoinsBack() {
        requireActiveProcess(MANAGER_APPROVAL);
        User submitter = submitterReportingToMe();
        Opportunity deal = deal(1000, null);
        AMF_ApprovalMatrixService.Outcome outcome;

        Test.startTest();
        System.runAs(submitter) {
            insert deal;
            outcome = shippedMatrix().submit(new List<Id>{ deal.Id })[0];
        }
        Test.stopTest();

        Assert.isTrue(
            outcome.submitted,
            'The platform refused the submission: ' + outcome.outcome + ' / ' + outcome.message
        );
        Assert.areEqual('OPP_Catch_All', outcome.matchedRule);
        Assert.areEqual(MANAGER_APPROVAL, outcome.selectedProcess);
        Assert.isTrue(
            guardOf(deal.Id),
            '6.3: the engine staged the guard, which is how the template\'s entry criteria passed'
        );

        ProcessInstance instance = [
            SELECT Id, Status, TargetObjectId, ProcessDefinition.DeveloperName
            FROM ProcessInstance
            WHERE Id = :outcome.executionRefId
        ];
        Assert.areEqual('Pending', instance.Status);
        Assert.areEqual(deal.Id, instance.TargetObjectId);
        Assert.areEqual(MANAGER_APPROVAL, instance.ProcessDefinition.DeveloperName);
        Assert.areEqual(
            UserInfo.getUserId(),
            [SELECT ActorId FROM ProcessInstanceWorkitem WHERE ProcessInstanceId = :instance.Id].ActorId,
            'Its one step is with the submitter\'s manager'
        );

        Approval_Decision_Log__c row = [
            SELECT
                Object_API_Name__c,
                Record_Id__c,
                Opportunity__c,
                Purchase_Request__c,
                Outcome__c,
                Execution_Ref_Id__c
            FROM Approval_Decision_Log__c
            WHERE Id = :outcome.decisionLogId
        ];
        Assert.areEqual('Opportunity', row.Object_API_Name__c);
        Assert.areEqual(String.valueOf(deal.Id), row.Record_Id__c, 'The provenance, as for every object (3.3)');
        Assert.areEqual(
            deal.Id,
            row.Opportunity__c,
            'The navigational lookup, which the log writer found by describe: no code names it (M3.12)'
        );
        Assert.isNull(row.Purchase_Request__c, 'And not the other object\'s lookup');
        Assert.areEqual('Submitted', row.Outcome__c);
        Assert.areEqual(String.valueOf(instance.Id), row.Execution_Ref_Id__c, '8: the row joins to the native history');
    }

    @IsTest
    static void theShippedMatrixSendsLargeDealsAndKeyIndustriesToTwoLevelsAndTheRestToTheManager() {
        requireActiveProcess(MANAGER_APPROVAL);
        requireActiveProcess(TWO_LEVEL);
        User submitter = submitterReportingToMe();
        List<AMF_ApprovalMatrixService.Outcome> outcomes;

        Test.startTest();
        System.runAs(submitter) {
            Account energy = new Account(Name = 'AMF M11 Energy', Industry = 'Energy');
            Account hotels = new Account(Name = 'AMF M11 Hotels', Industry = 'Hospitality');
            insert new List<Account>{ energy, hotels };

            // The amount decides the first: OPP_Large_Deal is priority 10, ahead of
            // the industry rule, and the account is not a key industry anyway.
            Opportunity large = deal(300000, hotels.Id);
            Opportunity keyIndustry = deal(1000, energy.Id);
            Opportunity ordinary = deal(1000, hotels.Id);
            insert new List<Opportunity>{ large, keyIndustry, ordinary };

            outcomes = shippedMatrix().submitEach(new List<Id>{ large.Id, keyIndustry.Id, ordinary.Id });
        }
        Test.stopTest();

        assertRouted(outcomes[0], 'OPP_Large_Deal', TWO_LEVEL);
        assertRouted(outcomes[1], 'OPP_Key_Industry', TWO_LEVEL);
        assertRouted(outcomes[2], 'OPP_Catch_All', MANAGER_APPROVAL);

        // A standard relationship, read through the union query and recorded under
        // the path the rule wrote: no __r anywhere, and nothing special-cased.
        Map<String, Object> read = (Map<String, Object>) JSON.deserializeUntyped(outcomes[1].evaluatedValuesJson);
        Assert.areEqual('Energy', read.get('Account.Industry'), outcomes[1].evaluatedValuesJson);
        Assert.isTrue(
            ((Map<String, Object>) JSON.deserializeUntyped(outcomes[0].evaluatedValuesJson)).containsKey('Amount'),
            outcomes[0].evaluatedValuesJson
        );
    }

    @IsTest
    static void bypassingTheEngineFailsEntryCriteriaOnBothTemplates() {
        // 6.3 on the second object. A submission that did not come through the
        // engine reaches the template with the guard unset, and is refused.
        requireActiveProcess(MANAGER_APPROVAL);
        requireActiveProcess(TWO_LEVEL);
        User submitter = submitterReportingToMe();
        Opportunity deal = deal(1000, null);
        List<String> refusedBy = new List<String>();

        Test.startTest();
        System.runAs(submitter) {
            insert deal;
            for (String process : new List<String>{ MANAGER_APPROVAL, TWO_LEVEL }) {
                if (!bypass(deal.Id, process).isSuccess()) {
                    refusedBy.add(process);
                }
            }
        }
        Test.stopTest();

        Assert.areEqual(
            new List<String>{ MANAGER_APPROVAL, TWO_LEVEL },
            refusedBy,
            'Both templates must refuse a submission with the guard unset. A template missing here lost its ' +
            'Matrix_Submission__c entry criterion.'
        );
        Assert.areEqual(0, [SELECT COUNT() FROM ProcessInstance WHERE TargetObjectId = :deal.Id], 'And nothing routed');
    }

    @IsTest
    static void approvalRejectionAndRecallEachReArmTheGuard() {
        // 5.2: a request can leave a template three ways, and each must clear the
        // guard, or a later submission that bypasses the engine would pass entry
        // criteria. The manager decides two; the submitter recalls the third.
        // People's actions, simulated: the engine never approves or recalls (6.5).
        requireActiveProcess(MANAGER_APPROVAL);
        User submitter = submitterReportingToMe();
        Opportunity approved = deal(1000, null);
        Opportunity rejected = deal(1000, null);
        Opportunity recalled = deal(1000, null);
        List<AMF_ApprovalMatrixService.Outcome> outcomes;

        System.runAs(submitter) {
            insert new List<Opportunity>{ approved, rejected, recalled };
            outcomes = shippedMatrix().submitEach(new List<Id>{ approved.Id, rejected.Id, recalled.Id });
        }
        for (AMF_ApprovalMatrixService.Outcome outcome : outcomes) {
            Assert.isTrue(outcome.submitted, 'Precondition: ' + outcome.message);
            Assert.isTrue(guardOf(outcome.recordId), 'Precondition: the guard is set while the request is pending');
        }

        Approval.ProcessResult recall;
        Approval.ProcessResult bypassAfterRecall;

        Test.startTest();
        Assert.isTrue(decide(outcomes[0], 'Approve').isSuccess(), 'The manager approves');
        Assert.isTrue(decide(outcomes[1], 'Reject').isSuccess(), 'The manager rejects');
        System.runAs(submitter) {
            recall = decide(outcomes[2], 'Removed');
            bypassAfterRecall = bypass(recalled.Id, MANAGER_APPROVAL);
        }
        Test.stopTest();

        Assert.isTrue(recall.isSuccess(), 'The submitter recalls: ' + recall.getErrors());

        Map<Id, String> statusByRecord = new Map<Id, String>();
        for (ProcessInstance instance : [
            SELECT TargetObjectId, Status
            FROM ProcessInstance
            WHERE TargetObjectId IN :new List<Id>{ approved.Id, rejected.Id, recalled.Id }
        ]) {
            statusByRecord.put(instance.TargetObjectId, instance.Status);
        }
        Assert.areEqual('Approved', statusByRecord.get(approved.Id));
        Assert.areEqual('Rejected', statusByRecord.get(rejected.Id));
        Assert.areEqual('Removed', statusByRecord.get(recalled.Id), 'Recalled');

        Assert.isFalse(guardOf(approved.Id), 'Final approval must re-arm the guard (5.2)');
        Assert.isFalse(guardOf(rejected.Id), 'Final rejection must re-arm the guard (5.2)');
        Assert.isFalse(guardOf(recalled.Id), 'Recall must re-arm the guard (5.2)');
        Assert.isFalse(
            bypassAfterRecall.isSuccess(),
            'With the guard re-armed, a submission that bypasses the engine fails entry criteria again (6.3)'
        );
    }

    @IsTest
    static void oneCallAnswersAPurchaseRequestAndAnOpportunityEachByItsOwnMatrix() {
        // 6.1's M10 note across objects: submitEach() takes one object at a time,
        // each with its own rules, union query, template and log lookup.
        requireActiveProcess(MANAGER_APPROVAL);
        requireActiveProcess(THREE_LEVEL_FINANCE);
        User submitter = submitterReportingToMe();
        Opportunity deal = deal(1000, null);
        Purchase_Request__c request = new Purchase_Request__c(
            Amount__c = 250000,
            Region__c = 'APAC',
            Risk_Level__c = 'High'
        );

        List<AMF_RuleDefinition> rules = shippedOpportunityRules();
        rules.add(
            new AMF_RuleBuilder()
                .named('PR_High_Risk')
                .withPriority(20)
                .withExpression('Risk_Level__c == \'High\'')
                .routingTo(THREE_LEVEL_FINANCE)
                .atVersion(1)
                .build()
        );
        List<AMF_ApprovalMatrixService.Outcome> outcomes;

        Test.startTest();
        System.runAs(submitter) {
            insert deal;
            insert request;
            outcomes = engine(rules).submitEach(new List<Id>{ deal.Id, request.Id });
        }
        Test.stopTest();

        Assert.areEqual(2, outcomes.size(), 'One answer per record, in the order supplied');
        Assert.areEqual(deal.Id, outcomes[0].recordId);
        assertRouted(outcomes[0], 'OPP_Catch_All', MANAGER_APPROVAL);
        Assert.areEqual(request.Id, outcomes[1].recordId);
        // A successful outcome's message is null, and Assert refuses a null message.
        Assert.isTrue(outcomes[1].submitted, 'PR: ' + outcomes[1].outcome + ' / ' + outcomes[1].message);
        Assert.areEqual('PR_High_Risk', outcomes[1].matchedRule);
        Assert.areEqual(THREE_LEVEL_FINANCE, outcomes[1].selectedProcess);

        Map<Id, Approval_Decision_Log__c> rows = new Map<Id, Approval_Decision_Log__c>([
            SELECT Id, Object_API_Name__c, Opportunity__c, Purchase_Request__c
            FROM Approval_Decision_Log__c
            WHERE Id IN :new List<Id>{ outcomes[0].decisionLogId, outcomes[1].decisionLogId }
        ]);
        Approval_Decision_Log__c dealRow = rows.get(outcomes[0].decisionLogId);
        Approval_Decision_Log__c requestRow = rows.get(outcomes[1].decisionLogId);

        Assert.areEqual('Opportunity', dealRow.Object_API_Name__c);
        Assert.areEqual(deal.Id, dealRow.Opportunity__c);
        Assert.isNull(dealRow.Purchase_Request__c);
        Assert.areEqual('Purchase_Request__c', requestRow.Object_API_Name__c);
        Assert.areEqual(request.Id, requestRow.Purchase_Request__c);
        Assert.isNull(requestRow.Opportunity__c, 'Each row carries its own object\'s lookup, chosen by describe');
    }

    @IsTest
    static void theTimelineExplainsAnOpportunityWithItsNativeSteps() {
        // 8 on the second object: the decision, labelled from Opportunity's own
        // describe, joined to its ProcessInstance and that instance's steps.
        requireActiveProcess(TWO_LEVEL);
        User submitter = submitterReportingToMe();
        Opportunity large = deal(300000, null);
        AMF_DecisionTimelineService.Timeline timeline;

        System.runAs(submitter) {
            insert large;
            AMF_ApprovalMatrixService.Outcome outcome = shippedMatrix().submit(new List<Id>{ large.Id })[0];
            Assert.isTrue(outcome.submitted, 'Precondition: ' + outcome.message);
        }

        Test.startTest();
        System.runAs(submitter) {
            timeline = AMF_DecisionTimelineService.getTimeline(large.Id);
        }
        Test.stopTest();

        Assert.areEqual(1, timeline.entries.size(), 'One submission, one entry');
        AMF_DecisionTimelineService.Entry entry = timeline.entries[0];
        Assert.areEqual('Submitted', entry.decision.outcome);
        Assert.areEqual('OPP_Large_Deal', entry.decision.matchedRule);
        Assert.areEqual(TWO_LEVEL, entry.decision.selectedProcess);

        Assert.isNotNull(entry.approval, 'The row joined to its ProcessInstance through Execution_Ref_Id__c (8)');
        Assert.areEqual(TWO_LEVEL, entry.approval.processName);
        Assert.areEqual('Pending', entry.approval.status);
        Assert.isFalse(entry.approval.steps.isEmpty(), 'The native steps: the submission, and who it is with now');

        Assert.areEqual(1, entry.decision.values.size(), 'The one value the winning rule read');
        Assert.areEqual('Amount', entry.decision.values[0].path);
        Assert.areEqual(
            Opportunity.Amount.getDescribe().getLabel(),
            entry.decision.values[0].label,
            'Labelled from the governed object\'s describe, not Purchase_Request__c\'s'
        );
    }

    @IsTest
    static void theValidatorPassesTheOpportunityMatrixAgainstTheRealCatalog() {
        // 9 against the org: the guard is a Checkbox on Opportunity, both
        // templates are active ProcessDefinitions for it, and its union query,
        // across a standard relationship, runs.
        requireActiveProcess(MANAGER_APPROVAL);
        requireActiveProcess(TWO_LEVEL);

        Test.startTest();
        List<AMF_ConfigValidator.Finding> findings = new AMF_ConfigValidator(
            new AMF_RuleBuilder.Stub(shippedOpportunityRules()),
            new AMF_ClassicApprovalProcessProvider()
        ).validate();
        Test.stopTest();

        List<String> rendered = new List<String>();
        for (AMF_ConfigValidator.Finding finding : findings) {
            rendered.add(finding.render());
        }
        Assert.areEqual(0, findings.size(), String.join(rendered, '\n'));
    }

    /** In-memory copies of the three shipped OPP rows, field for field. */
    private static List<AMF_RuleDefinition> shippedOpportunityRules() {
        return new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder()
                .named('OPP_Large_Deal')
                .forObject('Opportunity')
                .withPriority(10)
                .withExpression('Amount >= 250000')
                .routingTo(TWO_LEVEL)
                .atVersion(1)
                .build(),
            new AMF_RuleBuilder()
                .named('OPP_Key_Industry')
                .forObject('Opportunity')
                .withPriority(20)
                .withExpression('Account.Industry IN (\'Energy\', \'Banking\')')
                .routingTo(TWO_LEVEL)
                .atVersion(1)
                .build(),
            new AMF_RuleBuilder()
                .named('OPP_Catch_All')
                .forObject('Opportunity')
                .withPriority(9999)
                .withExpression('TRUE')
                .routingTo(MANAGER_APPROVAL)
                .atVersion(1)
                .build()
        };
    }

    private static AMF_ApprovalMatrixService shippedMatrix() {
        return engine(shippedOpportunityRules());
    }

    /** The real Classic strategy behind in-memory rules: real routes, no org CMDT. */
    private static AMF_ApprovalMatrixService engine(List<AMF_RuleDefinition> rules) {
        return new AMF_ApprovalMatrixService(new AMF_RuleBuilder.Stub(rules), new AMF_ClassicProcessStrategy());
    }

    private static Opportunity deal(Decimal amount, Id accountId) {
        return new Opportunity(
            Name = 'AMF M11 deal',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Amount = amount,
            AccountId = accountId
        );
    }

    /** Submitted to its template, with the guard first staged by the engine, and its first step with the manager. */
    private static void assertRouted(AMF_ApprovalMatrixService.Outcome outcome, String rule, String process) {
        Assert.isTrue(outcome.submitted, rule + ': ' + outcome.outcome + ' / ' + outcome.message);
        Assert.areEqual(rule, outcome.matchedRule);
        Assert.areEqual(process, outcome.selectedProcess);
        Assert.isTrue(guardOf(outcome.recordId), 'The guard stays set for the life of the approval');
        Assert.areEqual(
            UserInfo.getUserId(),
            [SELECT ActorId FROM ProcessInstanceWorkitem WHERE ProcessInstanceId = :outcome.executionRefId].ActorId,
            'The first step of either template is with the submitter\'s manager'
        );
    }

    /** A submission straight to a template, as the standard button would make it: no engine, no guard. */
    private static Approval.ProcessResult bypass(Id recordId, String processApiName) {
        Approval.ProcessSubmitRequest request = new Approval.ProcessSubmitRequest();
        request.setObjectId(recordId);
        request.setProcessDefinitionNameOrId(processApiName);
        return Approval.process(request, false);
    }

    /** Acts on a submission's open work item: Approve, Reject, or Removed (a recall). */
    private static Approval.ProcessResult decide(AMF_ApprovalMatrixService.Outcome outcome, String action) {
        Approval.ProcessWorkitemRequest request = new Approval.ProcessWorkitemRequest();
        request.setAction(action);
        request.setWorkitemId(
            [SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstanceId = :outcome.executionRefId LIMIT 1].Id
        );
        return Approval.process(request);
    }

    /**
     * A Standard User holding Approval_Matrix_User, who reports to the running
     * user: the approver both templates resolve first, in any org.
     */
    private static User submitterReportingToMe() {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        PermissionSet matrix = [SELECT Id FROM PermissionSet WHERE Name = 'Approval_Matrix_User' LIMIT 1];
        String name = 'amf.m11.submitter';

        User submitter = new User(
            Alias = 'amfm11',
            Email = name + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Submitter',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ManagerId = UserInfo.getUserId(),
            ProfileId = standard.Id,
            TimeZoneSidKey = 'GMT',
            Username = name + '.' + String.valueOf(Datetime.now().getTime()) + '@amf.test.invalid'
        );

        // User is a setup object: inserting one beside an Opportunity is
        // MIXED_DML_OPERATION without this wrapper.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert submitter;
            insert new PermissionSetAssignment(AssigneeId = submitter.Id, PermissionSetId = matrix.Id);
        }
        return submitter;
    }

    private static Boolean guardOf(Id recordId) {
        return [SELECT Matrix_Submission__c FROM Opportunity WHERE Id = :recordId].Matrix_Submission__c;
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
