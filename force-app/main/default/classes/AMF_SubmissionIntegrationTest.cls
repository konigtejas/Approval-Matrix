/**
 * The engine against real approvals: the tests that let Approval.process() run.
 *
 * Architecture section: 10 ("one thin integration test per template exercises
 * the real path"), 6.1 steps 9-11 and its M8 note, 6.3 (the guard), 5.2
 * (Classic templates), 8 (the join).
 *
 * Thin on purpose. Everything the engine decides is proved in
 * AMF_ApprovalMatrixServiceTest against AMF_StrategyStub, which is fast,
 * deterministic and free of org state. What only a real submission can prove is
 * the seam between them: that the process name the matrix produced is one the
 * platform accepts, that entry criteria pass BECAUSE the engine staged the
 * guard first, and that Execution_Ref_Id__c really does join to a
 * ProcessInstance the way 8 promises. Since M8, also the two things only a live
 * approval can show: that a recall re-arms the guard, and that a record already
 * in an approval process is refused before anything is decided.
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

    @IsTest
    static void aRecallClearsTheGuardSoABypassIsRefusedAgain() {
        // M8, and technical log M7.8. A recall unlocks the record. Before M8 it
        // left Matrix_Submission__c true, so a submission that bypassed the
        // engine passed entry criteria and routed with no decision log row. The
        // template's recall action now clears the guard (5.2), and the bypass
        // fails exactly as it does on a record that was never submitted.
        requireActiveProcess(THREE_LEVEL);
        Purchase_Request__c record = highValueApac();
        insert record;

        Test.startTest();
        AMF_ApprovalMatrixService.Outcome outcome = engineRoutingTo(THREE_LEVEL)
            .submit(new List<Id>{ record.Id })[0];
        Assert.isTrue(outcome.submitted, 'Precondition: the record entered the process. ' + outcome.message);

        // The submitter recalls it, as the Recall button on Approval History does.
        // A person's action, simulated; the engine itself never recalls (6.5).
        Approval.ProcessWorkitemRequest recall = new Approval.ProcessWorkitemRequest();
        recall.setAction('Removed');
        recall.setWorkitemId(
            [SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstanceId = :outcome.executionRefId LIMIT 1]
            .Id
        );
        Approval.ProcessResult recalled = Approval.process(recall);
        Test.stopTest();

        Assert.isTrue(recalled.isSuccess(), 'The recall itself must succeed: ' + recalled.getErrors());
        Assert.areEqual(
            'Removed',
            [SELECT Status FROM ProcessInstance WHERE Id = :outcome.executionRefId].Status,
            'Recalled'
        );
        Assert.isFalse(
            [SELECT Matrix_Submission__c FROM Purchase_Request__c WHERE Id = :record.Id].Matrix_Submission__c,
            'A recall must re-arm the guard (5.2). If this fails, the template lost its recall action.'
        );

        Approval.ProcessSubmitRequest bypass = new Approval.ProcessSubmitRequest();
        bypass.setObjectId(record.Id);
        bypass.setProcessDefinitionNameOrId(THREE_LEVEL);
        Boolean refused = false;
        try {
            Approval.process(bypass, true);
        } catch (Exception e) {
            refused = true;
        }
        Assert.isTrue(
            refused,
            'With the guard re-armed, a submission that bypasses the engine fails entry criteria again (6.3)'
        );
    }

    @IsTest
    static void aRecordAlreadyInApprovalIsRefusedByNameAndNothingIsLogged() {
        // 6.1's M8 note. The platform would refuse a second submission at step 10
        // with ALREADY_IN_PROCESS. The engine refuses first, naming the process,
        // and the preview refuses too, so the confirmation modal never offers a
        // route that cannot be taken.
        requireActiveProcess(THREE_LEVEL);
        Purchase_Request__c record = highValueApac();
        insert record;

        AMF_ApprovalMatrixService engine = engineRoutingTo(THREE_LEVEL);
        List<String> refusals = new List<String>();

        Test.startTest();
        Assert.isTrue(
            engine.submit(new List<Id>{ record.Id })[0].submitted,
            'Precondition: the record is now pending'
        );

        for (Boolean isPreview : new List<Boolean>{ true, false }) {
            try {
                if (isPreview) {
                    engine.preview(new List<Id>{ record.Id });
                } else {
                    engine.submit(new List<Id>{ record.Id });
                }
                Assert.fail((isPreview ? 'A preview' : 'A submission') + ' of a pending record must be refused');
            } catch (AMF_SubmissionException e) {
                refusals.add(e.getMessage());
            }
        }
        Test.stopTest();

        Assert.areEqual(2, refusals.size(), 'Both the preview and the submission are refused');
        for (String message : refusals) {
            Assert.isTrue(message.contains('already in an approval process'), 'Got: ' + message);
            Assert.isTrue(message.contains(THREE_LEVEL), 'The refusal names the process. Got: ' + message);
        }
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM Approval_Decision_Log__c WHERE Record_Id__c = :String.valueOf(record.Id)],
            'Only the first submission is on record: a refusal decides nothing, so it logs nothing'
        );
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM ProcessInstance WHERE TargetObjectId = :record.Id],
            'And nothing new routed'
        );
    }

    @IsTest
    static void aCallerWhoCannotReadTheRecordHearsAboutAccessNotTheApproval() {
        // 11. The pending check runs after authorise(), so a caller who cannot
        // read the record learns nothing about the approval it is in.
        requireActiveProcess(THREE_LEVEL);
        Purchase_Request__c record = highValueApac();
        insert record;

        AMF_ApprovalMatrixService engine = engineRoutingTo(THREE_LEVEL);
        Assert.isTrue(
            engine.submit(new List<Id>{ record.Id })[0].submitted,
            'Precondition: the record is now pending'
        );

        User stranger = strangerUser();

        Test.startTest();
        System.runAs(stranger) {
            try {
                engine.preview(new List<Id>{ record.Id });
                Assert.fail('A record the caller cannot read must be refused');
            } catch (AMF_SubmissionException e) {
                Assert.isTrue(e.getMessage().contains('read access'), 'Got: ' + e.getMessage());
                Assert.isFalse(
                    e.getMessage().contains(THREE_LEVEL),
                    'Nothing about the approval reaches a caller who cannot read the record'
                );
            }
        }
        Test.stopTest();
    }

    private static Purchase_Request__c highValueApac() {
        return new Purchase_Request__c(Amount__c = 250000, Region__c = 'APAC', Risk_Level__c = 'High');
    }

    /** The real Classic strategy behind an in-memory catch-all: one real route, no org CMDT. */
    private static AMF_ApprovalMatrixService engineRoutingTo(String processApiName) {
        return new AMF_ApprovalMatrixService(
            new AMF_RuleBuilder.Stub(
                new List<AMF_RuleDefinition>{
                    new AMF_RuleBuilder()
                        .named('PR_Catch_All')
                        .withPriority(9999)
                        .withExpression('TRUE')
                        .routingTo(processApiName)
                        .atVersion(1)
                        .build()
                }
            ),
            new AMF_ClassicProcessStrategy()
        );
    }

    /** A Standard User with no framework permission set and no access to the test's records. */
    private static User strangerUser() {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User stranger = new User(
            Alias = 'amfint',
            Email = 'amf.integration.stranger@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Stranger',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standard.Id,
            TimeZoneSidKey = 'GMT',
            Username = 'amf.integration.stranger.' +
                String.valueOf(Datetime.now().getTime()) +
                '@amf.test.invalid'
        );
        // User is a setup object: inserting one in the same transaction as a
        // Purchase_Request__c is MIXED_DML_OPERATION without this wrapper.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert stranger;
        }
        return stranger;
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
