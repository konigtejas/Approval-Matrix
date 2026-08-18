/**
 * The one test that lets a real Approval.process() run.
 *
 * Architecture section: 10 ("one thin integration test per template exercises
 * the real path"), 6.1 steps 9-11, 6.3 (the guard), 5.2 (Classic templates),
 * 8 (the join).
 *
 * Thin on purpose. Everything the engine decides is proved in
 * AMF_ApprovalMatrixServiceTest against AMF_StrategyStub, which is fast,
 * deterministic and free of org state. What only a real submission can prove is
 * the seam between them: that the process name the matrix produced is one the
 * platform accepts, that entry criteria pass BECAUSE the engine staged the
 * guard first, and that Execution_Ref_Id__c really does join to a
 * ProcessInstance the way 8 promises.
 *
 * ORG DEPENDENCE IS DELIBERATE AND LOCAL. This class needs
 * PR_Three_Level_Finance active in the org -- it is repo metadata, deployed
 * with the engine. It routes to the three named-user template rather than the
 * manager one because PR_Two_Level_Mgmt resolves its approvers from the
 * SUBMITTER's manager chain, and the user running a test may have no manager;
 * that shape is covered by the phase's manual QA instead. The RULES are still
 * in-memory fixtures, so CLAUDE.md's "zero dependence on org CMDT rows" holds.
 */
@IsTest
private class AMF_SubmissionIntegrationTest {

    private static final String THREE_LEVEL = 'PR_Three_Level_Finance';

    @IsTest
    static void aRealSubmissionEntersTheNamedProcessAndJoinsBackToIt() {
        requireActiveProcess(THREE_LEVEL);

        Purchase_Request__c record = new Purchase_Request__c(
            Amount__c = 250000,
            Region__c = 'APAC',
            Risk_Level__c = 'High'
        );
        insert record;

        List<AMF_RuleDefinition> rules = new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder()
                .named('PR_High_Value_APAC')
                .withPriority(10)
                .withExpression('Amount__c > 100000 && Region__c == \'APAC\'')
                .routingTo(THREE_LEVEL)
                .atVersion(1)
                .build()
        };

        // The real strategy. This is the only place in the suite where
        // Approval.process() actually runs.
        AMF_ApprovalMatrixService service = new AMF_ApprovalMatrixService(
            new AMF_RuleBuilder.Stub(rules),
            new AMF_ClassicProcessStrategy()
        );

        Test.startTest();
        List<AMF_ApprovalMatrixService.Outcome> outcomes = service.submit(new List<Id>{ record.Id });
        Test.stopTest();

        AMF_ApprovalMatrixService.Outcome outcome = outcomes[0];
        Assert.isTrue(
            outcome.submitted,
            'The platform refused the submission. Outcome: ' +
            outcome.outcome +
            ' / ' +
            outcome.message
        );
        Assert.areEqual(THREE_LEVEL, outcome.selectedProcess);
        Assert.isNotNull(outcome.executionRefId, '6.1 step 11 must produce a ProcessInstance Id');

        // 6.3: entry criteria are Matrix_Submission__c = true, and the submission
        // above only got in because step 9 staged it in this same transaction.
        Purchase_Request__c reloaded = [
            SELECT Matrix_Submission__c
            FROM Purchase_Request__c
            WHERE Id = :record.Id
        ];
        Assert.isTrue(reloaded.Matrix_Submission__c, 'The guard stays set for the life of the approval');

        // 8: Execution_Ref_Id__c is the provenance join, not decoration.
        List<ProcessInstance> instances = [
            SELECT Id, Status, TargetObjectId, ProcessDefinitionId
            FROM ProcessInstance
            WHERE Id = :outcome.executionRefId
        ];
        Assert.areEqual(1, instances.size(), 'Execution_Ref_Id__c must resolve to a real ProcessInstance');
        Assert.areEqual('Pending', instances[0].Status);
        Assert.areEqual(record.Id, instances[0].TargetObjectId, 'And point back at the governed record');

        // The template's first step produced a work item for a real approver.
        List<ProcessInstanceWorkitem> workItems = [
            SELECT Id, ActorId
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstanceId = :outcome.executionRefId
        ];
        Assert.areEqual(1, workItems.size(), 'Step 1 of the template must have an assignee');

        // And the decision log row joins to the same instance.
        Approval_Decision_Log__c row = [
            SELECT Execution_Ref_Id__c, Outcome__c, Selected_Process__c
            FROM Approval_Decision_Log__c
            WHERE Record_Id__c = :String.valueOf(record.Id)
        ];
        Assert.areEqual('Submitted', row.Outcome__c);
        Assert.areEqual(THREE_LEVEL, row.Selected_Process__c);
        Assert.areEqual(
            String.valueOf(instances[0].Id),
            row.Execution_Ref_Id__c,
            '8: the log row and the native history are joinable'
        );
    }

    @IsTest
    static void bypassingTheEngineFailsEntryCriteriaRatherThanRoutingSilently() {
        // 6.3, stated as a test. The guard is only worth having if a submission
        // that did NOT come through the engine is refused, so this submits
        // directly with Matrix_Submission__c still false.
        requireActiveProcess(THREE_LEVEL);

        Purchase_Request__c record = new Purchase_Request__c(
            Amount__c = 250000,
            Region__c = 'APAC',
            Risk_Level__c = 'High'
        );
        insert record;

        Approval.ProcessSubmitRequest bypass = new Approval.ProcessSubmitRequest();
        bypass.setObjectId(record.Id);
        bypass.setProcessDefinitionNameOrId(THREE_LEVEL);

        Test.startTest();
        Boolean refused = false;
        try {
            Approval.process(bypass, true);
        } catch (Exception e) {
            refused = true;
        }
        Test.stopTest();

        Assert.isTrue(
            refused,
            'A submission with the guard unset must fail entry criteria (6.3). If this ' +
            'assertion fails, the template lost its Matrix_Submission__c entry criteria.'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM ProcessInstance WHERE TargetObjectId = :record.Id],
            'And nothing routed'
        );
    }

    /**
     * Turns a missing or deactivated template into a sentence rather than into a
     * cryptic DmlException fifty lines later.
     */
    private static void requireActiveProcess(String developerName) {
        List<ProcessDefinition> definitions = [
            SELECT Id, State
            FROM ProcessDefinition
            WHERE DeveloperName = :developerName AND Type = 'Approval'
        ];

        Assert.areEqual(
            1,
            definitions.size(),
            'Approval process ' +
            developerName +
            ' is not in this org. It is repo metadata (5.2) -- deploy before running tests.'
        );
        Assert.areEqual(
            'Active',
            definitions[0].State,
            'Approval process ' + developerName + ' is deployed but not active.'
        );
    }
}
