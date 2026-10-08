/**
 * The engine's unit suite: 6.1 steps 1-11 driven entirely through in-memory
 * rules and a stub strategy, so nothing here depends on an org CMDT row or runs
 * a real approval.
 *
 * Architecture section: 6.1, 6.3, 6.4, 4.6, 10, 11.
 *
 * The real Approval.process() path is covered separately and thinly by
 * AMF_SubmissionIntegrationTest, per 10.
 */
@IsTest
private class AMF_ApprovalMatrixServiceTest {

    private static final String TWO_LEVEL = 'PR_Two_Level_Mgmt';
    private static final String THREE_LEVEL = 'PR_Three_Level_Finance';

    /**
     * The shipped matrix's shape, in memory: high-value APAC and high-risk take
     * the three-level chain, everything else falls through to the catch-all.
     */
    private static List<AMF_RuleDefinition> shippedShape() {
        return new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder()
                .named('PR_High_Value_APAC')
                .withPriority(10)
                .withExpression('Amount__c > 100000 && Region__c == \'APAC\'')
                .routingTo(THREE_LEVEL)
                .atVersion(3)
                .describedAs('High-value APAC spend')
                .build(),
            new AMF_RuleBuilder()
                .named('PR_High_Risk')
                .withPriority(20)
                .withExpression('Risk_Level__c == \'High\'')
                .routingTo(THREE_LEVEL)
                .atVersion(1)
                .build(),
            new AMF_RuleBuilder()
                .named('PR_Catch_All')
                .withPriority(9999)
                .withExpression('TRUE')
                .routingTo(TWO_LEVEL)
                .atVersion(1)
                .build()
        };
    }

    private static Purchase_Request__c request(Decimal amount, String region, String risk) {
        return new Purchase_Request__c(
            Amount__c = amount,
            Region__c = region,
            Risk_Level__c = risk
        );
    }

    private static AMF_ApprovalMatrixService serviceWith(
        List<AMF_RuleDefinition> rules,
        AMF_StrategyStub strategy
    ) {
        return new AMF_ApprovalMatrixService(new AMF_RuleBuilder.Stub(rules), strategy);
    }

    private static List<Approval_Decision_Log__c> logsFor(Id recordId) {
        return [
            SELECT
                Record_Id__c,
                Object_API_Name__c,
                Matched_Rule__c,
                Rule_Version__c,
                Expression_Snapshot__c,
                Evaluated_Values__c,
                Selected_Process__c,
                Execution_Ref_Id__c,
                Outcome__c,
                Failure_Detail__c,
                Submitted_By__c,
                Submitted_At__c
            FROM Approval_Decision_Log__c
            WHERE Record_Id__c = :String.valueOf(recordId)
        ];
    }

    @IsTest
    static void firstMatchingRuleInPriorityOrderWins() {
        // Matches BOTH PR_High_Value_APAC (priority 10) and PR_High_Risk (20).
        // 6.1 step 5 is first-true-wins, so priority decides, not specificity.
        Purchase_Request__c record = request(250000, 'APAC', 'High');
        insert record;

        AMF_StrategyStub strategy = new AMF_StrategyStub();

        Test.startTest();
        List<AMF_ApprovalMatrixService.Outcome> outcomes = serviceWith(shippedShape(), strategy)
            .submit(new List<Id>{ record.Id });
        Test.stopTest();

        Assert.areEqual(1, outcomes.size(), 'One record in, one outcome out');

        AMF_ApprovalMatrixService.Outcome outcome = outcomes[0];
        Assert.isTrue(outcome.submitted, 'The record should have been submitted');
        Assert.areEqual('Submitted', outcome.outcome);
        Assert.areEqual('PR_High_Value_APAC', outcome.matchedRule, 'Priority 10 beats priority 20');
        Assert.areEqual(3, outcome.ruleVersion);
        Assert.areEqual(THREE_LEVEL, outcome.selectedProcess);
        Assert.areEqual(THREE_LEVEL, strategy.processFor(record.Id), 'The strategy was told which process');
    }

    @IsTest
    static void theCatchAllRoutesWhateverNothingElseClaims() {
        // The M3 demo record: ordinary spend, non-APAC, low risk.
        Purchase_Request__c record = request(500, 'EMEA', 'Low');
        insert record;

        AMF_StrategyStub strategy = new AMF_StrategyStub();

        Test.startTest();
        List<AMF_ApprovalMatrixService.Outcome> outcomes = serviceWith(shippedShape(), strategy)
            .submit(new List<Id>{ record.Id });
        Test.stopTest();

        Assert.areEqual('PR_Catch_All', outcomes[0].matchedRule);
        Assert.areEqual(TWO_LEVEL, outcomes[0].selectedProcess);
    }

    @IsTest
    static void aRuleFlipRoutesTheSameRecordSomewhereElseWithNoCodeChange() {
        // 13's one-sentence claim, proved at the seam a CMDT edit acts on: the
        // ONLY difference between these two runs is Process_API_Name__c.
        Purchase_Request__c record = request(500, 'EMEA', 'Low');
        insert record;

        List<AMF_RuleDefinition> before = new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder()
                .named('PR_Catch_All')
                .withPriority(9999)
                .withExpression('TRUE')
                .routingTo(TWO_LEVEL)
                .atVersion(1)
                .build()
        };
        List<AMF_RuleDefinition> after = new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder()
                .named('PR_Catch_All')
                .withPriority(9999)
                .withExpression('TRUE')
                .routingTo(THREE_LEVEL)
                .atVersion(2)
                .build()
        };

        AMF_StrategyStub firstStrategy = new AMF_StrategyStub();
        serviceWith(before, firstStrategy).submit(new List<Id>{ record.Id });

        // Re-arm the guard the way a completed approval's final action does (5.2).
        update new Purchase_Request__c(Id = record.Id, Matrix_Submission__c = false);

        AMF_StrategyStub secondStrategy = new AMF_StrategyStub();
        serviceWith(after, secondStrategy).submit(new List<Id>{ record.Id });

        Assert.areEqual(TWO_LEVEL, firstStrategy.processFor(record.Id));
        Assert.areEqual(THREE_LEVEL, secondStrategy.processFor(record.Id), 'One CMDT field changed the routing');

        List<Approval_Decision_Log__c> rows = logsFor(record.Id);
        Assert.areEqual(2, rows.size(), 'One record accumulates one row per submission (3.3)');

        Set<String> processes = new Set<String>();
        Set<String> expressions = new Set<String>();
        for (Approval_Decision_Log__c row : rows) {
            processes.add(row.Selected_Process__c);
            expressions.add(row.Expression_Snapshot__c);
        }
        Assert.areEqual(
            new Set<String>{ TWO_LEVEL, THREE_LEVEL },
            processes,
            'Two rows, two processes -- the history was not rewritten'
        );
        Assert.areEqual(
            new Set<String>{ 'TRUE' },
            expressions,
            'Same expression on both rows: only the destination moved'
        );
    }

    @IsTest
    static void theGuardIsTrueBeforeTheStrategyRunsAndTheRecordCarriesIt() {
        // 6.1 step 9 and 6.3. The stub reads the record from inside submit(),
        // so this asserts the ORDERING, not just the end state.
        Purchase_Request__c record = request(500, 'EMEA', 'Low');
        insert record;
        Assert.isFalse(
            [SELECT Matrix_Submission__c FROM Purchase_Request__c WHERE Id = :record.Id]
            .Matrix_Submission__c,
            'Guard starts false'
        );

        AMF_StrategyStub strategy = new AMF_StrategyStub();

        Test.startTest();
        serviceWith(shippedShape(), strategy).submit(new List<Id>{ record.Id });
        Test.stopTest();

        Assert.isTrue(
            strategy.guardAtSubmit.get(record.Id),
            'Matrix_Submission__c must already be true when the strategy is called'
        );
        Purchase_Request__c reloaded = [
            SELECT Matrix_Submission__c
            FROM Purchase_Request__c
            WHERE Id = :record.Id
        ];
        Assert.isTrue(reloaded.Matrix_Submission__c, 'And it stays set until the template clears it');
    }

    @IsTest
    static void theDecisionLogRowExplainsTheRoutingAndIsStampedAfterSubmit() {
        Purchase_Request__c record = request(250000, 'APAC', 'Low');
        insert record;

        AMF_StrategyStub strategy = new AMF_StrategyStub();

        Test.startTest();
        List<AMF_ApprovalMatrixService.Outcome> outcomes = serviceWith(shippedShape(), strategy)
            .submit(new List<Id>{ record.Id });
        Test.stopTest();

        List<Approval_Decision_Log__c> rows = logsFor(record.Id);
        Assert.areEqual(1, rows.size());

        Approval_Decision_Log__c row = rows[0];
        Assert.areEqual('Submitted', row.Outcome__c);
        Assert.areEqual('Purchase_Request__c', row.Object_API_Name__c);
        Assert.areEqual('PR_High_Value_APAC', row.Matched_Rule__c);
        Assert.areEqual(3, row.Rule_Version__c);
        Assert.areEqual(
            'Amount__c > 100000 && Region__c == \'APAC\'',
            row.Expression_Snapshot__c,
            'The expression as evaluated, verbatim (3.3)'
        );
        Assert.areEqual(THREE_LEVEL, row.Selected_Process__c);
        Assert.areEqual(UserInfo.getUserId(), row.Submitted_By__c);
        Assert.isNotNull(row.Submitted_At__c);

        // 6.1's M10 note: the row is written once the platform has answered, so
        // it carries the reference from its insert, with no update after it.
        Assert.areEqual(
            outcomes[0].executionRefId,
            row.Execution_Ref_Id__c,
            'Execution_Ref_Id__c is on the row the submission wrote'
        );
        Assert.isNotNull(row.Execution_Ref_Id__c);

        // 3.3 and 8: the row says WHY, not just what.
        Map<String, Object> evaluated = (Map<String, Object>) JSON.deserializeUntyped(
            row.Evaluated_Values__c
        );
        Assert.areEqual(250000, ((Decimal) evaluated.get('Amount__c')).intValue());
        Assert.areEqual('APAC', (String) evaluated.get('Region__c'));
    }

    @IsTest
    static void noMatchBlocksAndLeavesARowThatSurvivesTheTransaction() {
        // 6.1 step 6 and 3.2. The row persisting is the point: an exception here
        // would roll back the very evidence the submitter is told to go and read.
        Purchase_Request__c record = request(500, 'EMEA', 'Low');
        insert record;

        List<AMF_RuleDefinition> noCatchAll = new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder()
                .named('PR_High_Risk')
                .withPriority(20)
                .withExpression('Risk_Level__c == \'High\'')
                .routingTo(THREE_LEVEL)
                .build()
        };
        AMF_StrategyStub strategy = new AMF_StrategyStub();

        Test.startTest();
        List<AMF_ApprovalMatrixService.Outcome> outcomes = serviceWith(noCatchAll, strategy)
            .submit(new List<Id>{ record.Id });
        Test.stopTest();

        AMF_ApprovalMatrixService.Outcome outcome = outcomes[0];
        Assert.isFalse(outcome.submitted, 'Nothing routes silently');
        Assert.areEqual('Blocked_No_Match', outcome.outcome);
        Assert.isNull(outcome.matchedRule);
        Assert.isTrue(
            outcome.message.contains('catch-all'),
            'The message points at 3.2\'s remedy, got: ' + outcome.message
        );
        Assert.areEqual(0, strategy.calls, 'The strategy is never reached');

        List<Approval_Decision_Log__c> rows = logsFor(record.Id);
        Assert.areEqual(1, rows.size(), 'The blocked row persists');
        Assert.areEqual('Blocked_No_Match', rows[0].Outcome__c);
        Assert.isNull(rows[0].Selected_Process__c);
        Assert.areEqual(
            rows[0].Id,
            outcome.decisionLogId,
            'The outcome points the caller at the row that explains it'
        );

        // Even with no winner the row says what the engine looked at.
        Map<String, Object> evaluated = (Map<String, Object>) JSON.deserializeUntyped(
            rows[0].Evaluated_Values__c
        );
        Assert.areEqual('Low', (String) evaluated.get('Risk_Level__c'));

        Purchase_Request__c reloaded = [
            SELECT Matrix_Submission__c
            FROM Purchase_Request__c
            WHERE Id = :record.Id
        ];
        Assert.isFalse(reloaded.Matrix_Submission__c, 'A blocked record never gets the guard');
    }

    @IsTest
    static void aRuleThatWillNotCompileStopsEverythingRatherThanFallingThrough() {
        // 4.6, at its sharpest. If the priority-10 rule cannot be evaluated,
        // nobody can say a record would not have matched it, so routing that
        // record to priority 20 is precisely the silent misrouting this
        // framework exists to prevent. 9's validator catches this at release
        // time (M4); a matrix deployed without the gate surfaces it here.
        Purchase_Request__c record = request(500, 'EMEA', 'Low');
        insert record;

        List<AMF_RuleDefinition> withBrokenRule = new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder()
                .named('PR_Broken')
                .withPriority(10)
                .withExpression('Nonexistent__c == \'x\'')
                .routingTo(THREE_LEVEL)
                .build(),
            new AMF_RuleBuilder()
                .named('PR_Catch_All')
                .withPriority(9999)
                .withExpression('TRUE')
                .routingTo(TWO_LEVEL)
                .build()
        };
        AMF_StrategyStub strategy = new AMF_StrategyStub();
        Boolean threw = false;

        Test.startTest();
        try {
            serviceWith(withBrokenRule, strategy).submit(new List<Id>{ record.Id });
        } catch (AMF_ExpressionException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('position'),
                'The error keeps 4.2\'s character position, got: ' + e.getMessage()
            );
        }
        Test.stopTest();

        Assert.isTrue(threw, 'A rule that will not compile must block the call');
        Assert.areEqual(0, strategy.calls, 'The catch-all must NOT pick the record up');
        Assert.areEqual(0, logsFor(record.Id).size(), 'Nothing routed, so nothing is logged');
    }

    @IsTest
    static void aMatchedRuleNamingNoProcessFailsThatRecordAndOnlyThatRecord() {
        // 6.1 step 7. Process_API_Name__c is Text with no referential check
        // (3.1), so a rule that names nothing is a runtime fault -- and per-record
        // isolation means the second record still routes.
        Purchase_Request__c broken = request(500, 'EMEA', 'High');
        Purchase_Request__c fine = request(500, 'EMEA', 'Low');
        insert new List<Purchase_Request__c>{ broken, fine };

        List<AMF_RuleDefinition> rules = new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder()
                .named('PR_High_Risk')
                .withPriority(20)
                .withExpression('Risk_Level__c == \'High\'')
                .routingTo(null)
                .build(),
            new AMF_RuleBuilder()
                .named('PR_Catch_All')
                .withPriority(9999)
                .withExpression('TRUE')
                .routingTo(TWO_LEVEL)
                .build()
        };
        AMF_StrategyStub strategy = new AMF_StrategyStub();

        Test.startTest();
        List<AMF_ApprovalMatrixService.Outcome> outcomes = serviceWith(rules, strategy)
            .submit(new List<Id>{ broken.Id, fine.Id });
        Test.stopTest();

        Assert.areEqual('Failed', outcomes[0].outcome);
        Assert.isFalse(outcomes[0].submitted);
        Assert.isTrue(
            outcomes[0].message.contains('Process_API_Name__c'),
            'The message names the field to go and fix, got: ' + outcomes[0].message
        );

        Assert.areEqual('Submitted', outcomes[1].outcome, 'One bad rule must not condemn the other record');
        Assert.areEqual(TWO_LEVEL, strategy.processFor(fine.Id));

        List<Approval_Decision_Log__c> failedRows = logsFor(broken.Id);
        Assert.areEqual(1, failedRows.size());
        Assert.areEqual('Failed', failedRows[0].Outcome__c);
        Assert.areEqual('PR_High_Risk', failedRows[0].Matched_Rule__c, 'The row names the rule that failed');
        Assert.isTrue(
            failedRows[0].Failure_Detail__c.contains('Process_API_Name__c'),
            '4.6: the exception text lands in Failure_Detail__c'
        );

        Purchase_Request__c reloaded = [
            SELECT Matrix_Submission__c
            FROM Purchase_Request__c
            WHERE Id = :broken.Id
        ];
        Assert.isFalse(reloaded.Matrix_Submission__c, 'A failed record never gets the guard');
    }

    @IsTest
    static void anObjectWithNoActiveRulesIsNotGoverned() {
        // 3.2: governed means the object has active rules, and deactivating them
        // all is the framework's kill switch.
        Purchase_Request__c record = request(500, 'EMEA', 'Low');
        insert record;

        List<AMF_RuleDefinition> allInactive = new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder().named('PR_Catch_All').withExpression('TRUE').inactive().build()
        };

        Test.startTest();
        try {
            serviceWith(allInactive, new AMF_StrategyStub()).submit(new List<Id>{ record.Id });
            Assert.fail('An ungoverned object must not submit');
        } catch (AMF_SubmissionException e) {
            Assert.isTrue(
                e.getMessage().contains('not governed'),
                'Got: ' + e.getMessage()
            );
        }
        Test.stopTest();

        Assert.areEqual(0, logsFor(record.Id).size());
    }

    @IsTest
    static void everyRuleIsCompiledOnceHoweverManyRecordsAreSubmitted() {
        // 6.1 steps 3 and 4, and 4.5. Three rules, three records: three
        // compilations, and ONE query for the union of paths.
        List<Purchase_Request__c> records = new List<Purchase_Request__c>{
            request(250000, 'APAC', 'Low'),
            request(500, 'EMEA', 'High'),
            request(500, 'AMER', 'Low')
        };
        insert records;

        AMF_ExprCache.reset();
        List<Id> recordIds = new List<Id>(new Map<Id, Purchase_Request__c>(records).keySet());

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        serviceWith(shippedShape(), new AMF_StrategyStub()).submit(recordIds);
        Integer queriesAfter = Limits.getQueries();
        Test.stopTest();

        Assert.areEqual(3, AMF_ExprCache.getCompilations(), 'One compilation per rule, not per record');
        Assert.isTrue(
            queriesAfter - queriesBefore <= 4,
            'One union query plus authorisation, the pending-approval check (M8) and the ' +
            'stub read, not one per rule (4.4). Queries used: ' + (queriesAfter - queriesBefore)
        );
    }

    @IsTest
    static void eachRecordGetsItsOwnAnswerInOneCall() {
        List<Purchase_Request__c> records = new List<Purchase_Request__c>{
            request(250000, 'APAC', 'Low'),
            request(500, 'EMEA', 'High'),
            request(500, 'AMER', 'Low')
        };
        insert records;

        AMF_StrategyStub strategy = new AMF_StrategyStub();
        List<Id> recordIds = new List<Id>{ records[0].Id, records[1].Id, records[2].Id };

        Test.startTest();
        List<AMF_ApprovalMatrixService.Outcome> outcomes = serviceWith(shippedShape(), strategy)
            .submit(recordIds);
        Test.stopTest();

        Assert.areEqual(3, outcomes.size());
        Assert.areEqual('PR_High_Value_APAC', outcomes[0].matchedRule);
        Assert.areEqual('PR_High_Risk', outcomes[1].matchedRule);
        Assert.areEqual('PR_Catch_All', outcomes[2].matchedRule);
        Assert.areEqual(
            recordIds,
            new List<Id>{ outcomes[0].recordId, outcomes[1].recordId, outcomes[2].recordId },
            'Outcomes come back in the order supplied'
        );
        Assert.areEqual(1, strategy.calls, 'One strategy call for the whole batch');
        Assert.areEqual(3, strategy.received.size());
    }

    @IsTest
    static void aStrategyFailureIsNotSwallowed() {
        // 4.6 at the engine's own boundary. A strategy that throws has failed as
        // a whole (6.2's M10 note), so the exception reaches the caller and the
        // call is rolled back with it: no row, and no guard left staged.
        Purchase_Request__c record = request(500, 'EMEA', 'Low');
        insert record;

        AMF_StrategyStub strategy = new AMF_StrategyStub();
        strategy.failWith = new AMF_SubmissionException('the platform said no');

        Test.startTest();
        try {
            serviceWith(shippedShape(), strategy).submit(new List<Id>{ record.Id });
            Assert.fail('The engine must not swallow a failed submission');
        } catch (AMF_SubmissionException e) {
            Assert.areEqual('the platform said no', e.getMessage());
        }
        Test.stopTest();

        Assert.areEqual(0, logsFor(record.Id).size(), 'Nothing is logged for a call that failed');
        Assert.isFalse(guardOf(record.Id), 'And the guard staged before submit is rolled back');
    }

    @IsTest
    static void aSubmissionWithoutAnExecutionReferenceIsAContradiction() {
        // 8: Execution_Ref_Id__c is a provenance stamp that must not be optimised
        // away, so "submitted, reference unknown" is a failure, not a result.
        Purchase_Request__c record = request(500, 'EMEA', 'Low');
        insert record;

        AMF_StrategyStub strategy = new AMF_StrategyStub();
        strategy.returnBlankReference = true;

        Test.startTest();
        try {
            serviceWith(shippedShape(), strategy).submit(new List<Id>{ record.Id });
            Assert.fail('A blank execution reference must not pass');
        } catch (AMF_SubmissionException e) {
            Assert.isTrue(
                e.getMessage().contains('no execution reference'),
                'Got: ' + e.getMessage()
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void emptyAndNullInputAreRefused() {
        for (List<Id> input : new List<List<Id>>{ null, new List<Id>() }) {
            try {
                new AMF_ApprovalMatrixService(
                        new AMF_RuleBuilder.Stub(shippedShape()),
                        new AMF_StrategyStub()
                    )
                    .submit(input);
                Assert.fail('Expected a refusal for input: ' + input);
            } catch (AMF_SubmissionException e) {
                Assert.isTrue(e.getMessage().contains('No records'), 'Got: ' + e.getMessage());
            }
        }
    }

    @IsTest
    static void oneSubmissionCoversOneObject() {
        Purchase_Request__c record = request(500, 'EMEA', 'Low');
        insert record;
        Account account = new Account(Name = 'Mixed batch');
        insert account;

        try {
            serviceWith(shippedShape(), new AMF_StrategyStub())
                .submit(new List<Id>{ record.Id, account.Id });
            Assert.fail('A mixed batch must be refused rather than partitioned');
        } catch (AMF_SubmissionException e) {
            Assert.isTrue(e.getMessage().contains('one object'), 'Got: ' + e.getMessage());
            Assert.isTrue(e.getMessage().contains('Account'), 'It names what was mixed');
        }
    }

    @IsTest
    static void aNullRecordIdIsRefused() {
        try {
            serviceWith(shippedShape(), new AMF_StrategyStub()).submit(new List<Id>{ null });
            Assert.fail('A null Id must be refused');
        } catch (AMF_SubmissionException e) {
            Assert.isTrue(e.getMessage().contains('null record Id'), 'Got: ' + e.getMessage());
        }
    }

    @IsTest
    static void anObjectWithoutTheGuardFieldCannotBeGoverned() {
        // 3.2: the guard is a convention, so an object lacking it is
        // misconfigured. Said early, before a log row has been written.
        Account account = new Account(Name = 'Ungoverned');
        insert account;

        try {
            serviceWith(shippedShape(), new AMF_StrategyStub()).submit(new List<Id>{ account.Id });
            Assert.fail('An object with no guard field must be refused');
        } catch (AMF_SubmissionException e) {
            Assert.isTrue(
                e.getMessage().contains('Matrix_Submission__c'),
                'Got: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void submissionRequiresReadAccessToTheRecord() {
        // 11: the service runs without sharing and therefore authorises
        // explicitly. Purchase_Request__c is Private, so a user with the record
        // neither owned nor shared cannot submit it.
        Purchase_Request__c record = request(500, 'EMEA', 'Low');
        insert record;

        User stranger = strangerUser();

        Test.startTest();
        System.runAs(stranger) {
            try {
                serviceWith(shippedShape(), new AMF_StrategyStub()).submit(new List<Id>{ record.Id });
                Assert.fail('A record the caller cannot read must not be submitted');
            } catch (AMF_SubmissionException e) {
                Assert.isTrue(
                    e.getMessage().contains('read access'),
                    'Got: ' + e.getMessage()
                );
            }
        }
        Test.stopTest();

        Assert.areEqual(0, logsFor(record.Id).size(), 'And nothing is logged on an unauthorised call');
    }

    @IsTest
    static void theAuraEntryPointSurfacesTheRealMessage() {
        // 7's UI row. Exercised through the real production wiring -- the CMDT
        // provider and the Classic strategy -- only as far as its guard clauses,
        // because an Account has no Matrix_Submission__c and so never reaches
        // Approval.process().
        Account account = new Account(Name = 'Not governed');
        insert account;

        Test.startTest();
        try {
            AMF_ApprovalMatrixService.submitRecord(account.Id);
            Assert.fail('Expected the ungoverned object to be refused');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().contains('Matrix_Submission__c'),
                'The LWC must receive the real message, not "Script-thrown exception". Got: ' +
                e.getMessage()
            );
        }
        Test.stopTest();
    }

    // ---------------------------------------------------------------------
    // 6.4 -- preview. Steps 1-7 on the same path as submit(), nothing written.
    // ---------------------------------------------------------------------

    @IsTest
    static void aPreviewNamesTheRouteAndTheReasonAndWritesNothing() {
        // Matches both PR_High_Value_APAC (10) and PR_High_Risk (20): the preview
        // must apply the same first-true-wins walk a submission does.
        Purchase_Request__c record = request(250000, 'APAC', 'High');
        insert record;

        AMF_StrategyStub strategy = new AMF_StrategyStub();

        Test.startTest();
        Integer dmlBefore = Limits.getDmlStatements();
        List<AMF_ApprovalMatrixService.Outcome> previews = serviceWith(shippedShape(), strategy)
            .preview(new List<Id>{ record.Id });
        Integer dmlUsed = Limits.getDmlStatements() - dmlBefore;
        Test.stopTest();

        Assert.areEqual(1, previews.size(), 'One record in, one preview out');

        AMF_ApprovalMatrixService.Outcome preview = previews[0];
        Assert.areEqual(record.Id, preview.recordId);
        Assert.areEqual('Submitted', preview.outcome, 'The verdict a submission would record');
        Assert.isFalse(preview.submitted, 'A preview never submits');
        Assert.areEqual('PR_High_Value_APAC', preview.matchedRule, 'Priority 10 beats priority 20');
        Assert.areEqual(10, preview.rulePriority);
        Assert.areEqual(3, preview.ruleVersion);
        Assert.areEqual('High-value APAC spend', preview.matchedRuleDescription);
        Assert.areEqual(THREE_LEVEL, preview.selectedProcess);
        Assert.areEqual('Amount__c > 100000 && Region__c == \'APAC\'', preview.matchedExpression);

        Map<String, Object> evaluated = (Map<String, Object>) JSON.deserializeUntyped(
            preview.evaluatedValuesJson
        );
        Assert.areEqual(250000, ((Decimal) evaluated.get('Amount__c')).intValue());
        Assert.areEqual('APAC', (String) evaluated.get('Region__c'));

        Assert.isNull(preview.decisionLogId, 'No row was written, so there is none to point at');
        Assert.isNull(preview.executionRefId);
        Assert.isNull(preview.message);

        Assert.areEqual(0, dmlUsed, 'A preview performs no DML at all');
        Assert.areEqual(0, strategy.calls, 'The strategy is never reached');
        Assert.areEqual(0, logsFor(record.Id).size(), 'No decision log row');
        Assert.isFalse(
            [SELECT Matrix_Submission__c FROM Purchase_Request__c WHERE Id = :record.Id]
            .Matrix_Submission__c,
            'The guard is never staged by a preview'
        );
    }

    @IsTest
    static void aPreviewShowsExactlyWhatTheSubmissionThenRecords() {
        // Same code path, so what the submitter confirms is what the engine does
        // and what the audit row says -- byte for byte, not merely similar.
        Purchase_Request__c record = request(250000, 'APAC', 'Low');
        insert record;

        AMF_ApprovalMatrixService service = serviceWith(shippedShape(), new AMF_StrategyStub());

        Test.startTest();
        AMF_ApprovalMatrixService.Outcome preview = service.preview(new List<Id>{ record.Id })[0];
        AMF_ApprovalMatrixService.Outcome submitted = service.submit(new List<Id>{ record.Id })[0];
        Test.stopTest();

        Assert.isTrue(submitted.submitted);
        Assert.areEqual(submitted.matchedRule, preview.matchedRule);
        Assert.areEqual(submitted.ruleVersion, preview.ruleVersion);
        Assert.areEqual(submitted.rulePriority, preview.rulePriority);
        Assert.areEqual(submitted.selectedProcess, preview.selectedProcess);
        Assert.areEqual(submitted.matchedExpression, preview.matchedExpression);
        Assert.areEqual(submitted.evaluatedValuesJson, preview.evaluatedValuesJson);

        Approval_Decision_Log__c row = logsFor(record.Id)[0];
        Assert.areEqual(row.Expression_Snapshot__c, preview.matchedExpression);
        Assert.areEqual(row.Evaluated_Values__c, preview.evaluatedValuesJson);
        Assert.areEqual(row.Selected_Process__c, preview.selectedProcess);
    }

    @IsTest
    static void aPreviewOfTheCatchAllReadsNoFields() {
        // A TRUE expression reads nothing, and the modal says so rather than
        // showing an empty table; the JSON must be an empty object, not null.
        Purchase_Request__c record = request(500, 'EMEA', 'Low');
        insert record;

        Test.startTest();
        AMF_ApprovalMatrixService.Outcome preview = serviceWith(shippedShape(), new AMF_StrategyStub())
            .preview(new List<Id>{ record.Id })[0];
        Test.stopTest();

        Assert.areEqual('PR_Catch_All', preview.matchedRule);
        Assert.areEqual(9999, preview.rulePriority);
        Assert.areEqual('TRUE', preview.matchedExpression);
        Assert.areEqual('{}', preview.evaluatedValuesJson);
    }

    @IsTest
    static void aBlockedPreviewSaysWhyAndLeavesNoRow() {
        // The preview itself writes nothing (6.4). The Blocked_No_Match row is
        // the SUBMISSION's job, which is why the quick action goes on to submit
        // a blocked record rather than asking the user to confirm nothing.
        Purchase_Request__c record = request(500, 'EMEA', 'Low');
        insert record;

        List<AMF_RuleDefinition> noCatchAll = new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder()
                .named('PR_High_Risk')
                .withPriority(20)
                .withExpression('Risk_Level__c == \'High\'')
                .routingTo(THREE_LEVEL)
                .build()
        };
        AMF_StrategyStub strategy = new AMF_StrategyStub();

        Test.startTest();
        AMF_ApprovalMatrixService.Outcome preview = serviceWith(noCatchAll, strategy)
            .preview(new List<Id>{ record.Id })[0];
        Test.stopTest();

        Assert.areEqual('Blocked_No_Match', preview.outcome);
        Assert.isFalse(preview.submitted);
        Assert.isNull(preview.matchedRule);
        Assert.isNull(preview.selectedProcess);
        Assert.isTrue(preview.message.contains('catch-all'), 'Got: ' + preview.message);

        Map<String, Object> evaluated = (Map<String, Object>) JSON.deserializeUntyped(
            preview.evaluatedValuesJson
        );
        Assert.areEqual('Low', (String) evaluated.get('Risk_Level__c'), 'It still shows what was read');

        Assert.areEqual(0, strategy.calls);
        Assert.areEqual(0, logsFor(record.Id).size(), 'A preview never writes the blocked row');
    }

    @IsTest
    static void aFailedPreviewSaysWhyAndLeavesNoRow() {
        Purchase_Request__c record = request(500, 'EMEA', 'High');
        insert record;

        List<AMF_RuleDefinition> rules = new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder()
                .named('PR_High_Risk')
                .withPriority(20)
                .withExpression('Risk_Level__c == \'High\'')
                .routingTo(null)
                .build()
        };
        AMF_StrategyStub strategy = new AMF_StrategyStub();

        Test.startTest();
        AMF_ApprovalMatrixService.Outcome preview = serviceWith(rules, strategy)
            .preview(new List<Id>{ record.Id })[0];
        Test.stopTest();

        Assert.areEqual('Failed', preview.outcome);
        Assert.isFalse(preview.submitted);
        Assert.isTrue(
            preview.message.contains('Process_API_Name__c'),
            'The message names the field to go and fix, got: ' + preview.message
        );
        Assert.areEqual(0, strategy.calls);
        Assert.areEqual(0, logsFor(record.Id).size(), 'A preview never writes the failed row');
    }

    @IsTest
    static void aPreviewFailsLoudlyOnARuleThatWillNotCompile() {
        // 4.6 holds for the preview too: it must not quietly show the catch-all's
        // route when a higher-priority rule cannot be evaluated.
        Purchase_Request__c record = request(500, 'EMEA', 'Low');
        insert record;

        List<AMF_RuleDefinition> withBrokenRule = new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder()
                .named('PR_Broken')
                .withPriority(10)
                .withExpression('Nonexistent__c == \'x\'')
                .routingTo(THREE_LEVEL)
                .build(),
            new AMF_RuleBuilder()
                .named('PR_Catch_All')
                .withPriority(9999)
                .withExpression('TRUE')
                .routingTo(TWO_LEVEL)
                .build()
        };

        Test.startTest();
        try {
            serviceWith(withBrokenRule, new AMF_StrategyStub()).preview(new List<Id>{ record.Id });
            Assert.fail('A rule that will not compile must block the preview');
        } catch (AMF_ExpressionException e) {
            Assert.isTrue(e.getMessage().contains('position'), 'Got: ' + e.getMessage());
        }
        Test.stopTest();
    }

    @IsTest
    static void aPreviewRequiresReadAccessToTheRecord() {
        // 11. The preview returns the values the rule read, so it is held to the
        // same authorisation as a submission, on the same path.
        Purchase_Request__c record = request(500, 'EMEA', 'Low');
        insert record;

        User stranger = strangerUser();

        Test.startTest();
        System.runAs(stranger) {
            try {
                serviceWith(shippedShape(), new AMF_StrategyStub()).preview(new List<Id>{ record.Id });
                Assert.fail('A record the caller cannot read must not be previewed');
            } catch (AMF_SubmissionException e) {
                Assert.isTrue(e.getMessage().contains('read access'), 'Got: ' + e.getMessage());
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void aPreviewRefusesWhatASubmissionRefuses() {
        try {
            serviceWith(shippedShape(), new AMF_StrategyStub()).preview(new List<Id>());
            Assert.fail('An empty preview must be refused');
        } catch (AMF_SubmissionException e) {
            Assert.isTrue(e.getMessage().contains('No records'), 'Got: ' + e.getMessage());
        }
    }

    @IsTest
    static void thePreviewAuraEntryPointSurfacesTheRealMessage() {
        // Production wiring, as far as the guard clause only -- an Account has
        // no Matrix_Submission__c -- so no org CMDT row is ever evaluated.
        Account account = new Account(Name = 'Not governed');
        insert account;

        Test.startTest();
        try {
            AMF_ApprovalMatrixService.previewRecord(account.Id);
            Assert.fail('Expected the ungoverned object to be refused');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().contains('Matrix_Submission__c'),
                'The modal must receive the real message, not "Script-thrown exception". Got: ' +
                e.getMessage()
            );
        }
        Test.stopTest();
    }

    // ---------------------------------------------------------------------
    // M10 -- the log written after the platform answers, and submitEach()'s
    // record-by-record contract (6.1 and 6.2's M10 notes).
    // ---------------------------------------------------------------------

    @IsTest
    static void aPlatformRefusalIsLoggedFailedAndTheOtherRecordStillSubmits() {
        // 6.2's M10 note. The strategy answers per record, so a refusal is that
        // record's Failed row -- the rule and process the matrix chose, and the
        // platform's reason -- while the other record's submission stands.
        Purchase_Request__c refusedRecord = request(250000, 'APAC', 'Low');
        Purchase_Request__c enteredRecord = request(500, 'EMEA', 'Low');
        insert new List<Purchase_Request__c>{ refusedRecord, enteredRecord };

        AMF_StrategyStub strategy = new AMF_StrategyStub();
        strategy.refuse.add(refusedRecord.Id);

        Test.startTest();
        List<AMF_ApprovalMatrixService.Outcome> outcomes = serviceWith(shippedShape(), strategy)
            .submitEach(new List<Id>{ refusedRecord.Id, enteredRecord.Id });
        Test.stopTest();

        Assert.areEqual(1, strategy.calls, 'Both records went to the strategy in one call');
        Assert.isTrue(strategy.guardAtSubmit.get(refusedRecord.Id), 'It was submitted with the guard staged');

        AMF_ApprovalMatrixService.Outcome refused = outcomes[0];
        Assert.areEqual('Failed', refused.outcome);
        Assert.isFalse(refused.submitted);
        Assert.areEqual('PR_High_Value_APAC', refused.matchedRule, 'The matrix still decided');
        Assert.areEqual(THREE_LEVEL, refused.selectedProcess);
        Assert.isNull(refused.executionRefId);
        Assert.areEqual(
            'Approval process ' + THREE_LEVEL + ' refused the submission: ' + strategy.refusalMessage,
            refused.message
        );

        List<Approval_Decision_Log__c> failedRows = logsFor(refusedRecord.Id);
        Assert.areEqual(1, failedRows.size());
        Assert.areEqual(failedRows[0].Id, refused.decisionLogId);
        Assert.areEqual('Failed', failedRows[0].Outcome__c);
        Assert.areEqual('PR_High_Value_APAC', failedRows[0].Matched_Rule__c);
        Assert.areEqual(3, failedRows[0].Rule_Version__c);
        Assert.areEqual(THREE_LEVEL, failedRows[0].Selected_Process__c);
        Assert.areEqual(refused.evaluatedValuesJson, failedRows[0].Evaluated_Values__c);
        Assert.areEqual(refused.message, failedRows[0].Failure_Detail__c, 'The platform\'s reason, on record');
        Assert.isNull(failedRows[0].Execution_Ref_Id__c);
        Assert.isFalse(guardOf(refusedRecord.Id), 'A refused record\'s guard is re-armed (6.3)');

        AMF_ApprovalMatrixService.Outcome entered = outcomes[1];
        Assert.isTrue(entered.submitted, 'A refusal must not undo another record\'s submission');
        Assert.areEqual('Submitted', entered.outcome);
        Assert.areEqual(entered.executionRefId, logsFor(enteredRecord.Id)[0].Execution_Ref_Id__c);
        Assert.isTrue(guardOf(enteredRecord.Id), 'Its guard stays set for the life of the approval');
    }

    @IsTest
    static void aPlatformRefusalThroughSubmitLeavesAFailedRowInsteadOfNothing() {
        // The one thing M10 changes on the header button's path (docs/decisions.md,
        // 2026-10-08). Before it, a refusal rolled the call back and left no
        // trace; now it is logged like any other failure, and answered.
        Purchase_Request__c record = request(500, 'EMEA', 'Low');
        insert record;

        AMF_StrategyStub strategy = new AMF_StrategyStub();
        strategy.refuse.add(record.Id);

        Test.startTest();
        AMF_ApprovalMatrixService.Outcome outcome = serviceWith(shippedShape(), strategy)
            .submit(new List<Id>{ record.Id })[0];
        Test.stopTest();

        Assert.areEqual('Failed', outcome.outcome);
        Assert.isFalse(outcome.submitted);
        Assert.isTrue(outcome.message.contains(strategy.refusalMessage), 'Got: ' + outcome.message);

        List<Approval_Decision_Log__c> rows = logsFor(record.Id);
        Assert.areEqual(1, rows.size());
        Assert.areEqual('Failed', rows[0].Outcome__c);
        Assert.areEqual(rows[0].Id, outcome.decisionLogId);
        Assert.isFalse(guardOf(record.Id), 'Re-armed');
    }

    @IsTest
    static void submitEachRefusesARecordTheCallerCannotReadAndSubmitsTheRest() {
        // 11, record by record. Purchase_Request__c is Private, so the submitter
        // can read the record they own and not the one they do not.
        Purchase_Request__c notTheirs = request(500, 'EMEA', 'Low');
        insert notTheirs;

        User submitter = submitterUser();
        Purchase_Request__c theirs = request(500, 'EMEA', 'Low');
        AMF_StrategyStub strategy = new AMF_StrategyStub();
        List<AMF_ApprovalMatrixService.Outcome> outcomes;

        Test.startTest();
        System.runAs(submitter) {
            insert theirs;
            outcomes = serviceWith(shippedShape(), strategy)
                .submitEach(new List<Id>{ notTheirs.Id, theirs.Id });
        }
        Test.stopTest();

        AMF_ApprovalMatrixService.Outcome refused = outcomes[0];
        Assert.areEqual(notTheirs.Id, refused.recordId);
        Assert.areEqual('Refused', refused.outcome);
        Assert.isFalse(refused.submitted);
        Assert.isTrue(refused.message.contains('read access'), 'Got: ' + refused.message);
        Assert.isNull(refused.matchedRule, 'Nothing about the record was read');
        Assert.isNull(refused.evaluatedValuesJson);
        Assert.isNull(refused.decisionLogId, 'Nothing was decided, so nothing is logged');
        Assert.areEqual(0, logsFor(notTheirs.Id).size());
        Assert.isNull(strategy.processFor(notTheirs.Id), 'It never reached the strategy');

        Assert.isTrue(outcomes[1].submitted, 'The record the caller can read still goes: ' + outcomes[1].message);
        Assert.areEqual(1, logsFor(theirs.Id).size());
    }

    @IsTest
    static void submitEachAnswersEveryObjectInTheCall() {
        // The rule set and the union query are per object, so submitEach() takes
        // one object at a time. An object the matrix cannot govern is refused
        // record by record, and the other object's records still go through.
        Purchase_Request__c record = request(500, 'EMEA', 'Low');
        insert record;
        Account account = new Account(Name = 'Mixed batch');
        insert account;

        AMF_StrategyStub strategy = new AMF_StrategyStub();

        Test.startTest();
        List<AMF_ApprovalMatrixService.Outcome> outcomes = serviceWith(shippedShape(), strategy)
            .submitEach(new List<Id>{ account.Id, record.Id });
        Test.stopTest();

        Assert.areEqual(2, outcomes.size());
        Assert.areEqual(account.Id, outcomes[0].recordId, 'In the order supplied');
        Assert.areEqual('Refused', outcomes[0].outcome);
        Assert.isTrue(
            outcomes[0].message.contains('Matrix_Submission__c'),
            'It says why the object cannot be governed. Got: ' + outcomes[0].message
        );
        Assert.areEqual(0, logsFor(account.Id).size());

        Assert.areEqual(record.Id, outcomes[1].recordId);
        Assert.isTrue(outcomes[1].submitted);
    }

    @IsTest
    static void submitEachRefusesEveryRecordOfAnObjectWhoseRuleWillNotCompile() {
        // 4.6 still holds: none of the object's records may route past a rule
        // that nobody can evaluate. What changes is that the call is answered,
        // record by record, instead of thrown, so other objects are answered too.
        Purchase_Request__c first = request(500, 'EMEA', 'Low');
        Purchase_Request__c second = request(250000, 'APAC', 'High');
        insert new List<Purchase_Request__c>{ first, second };
        Account account = new Account(Name = 'Another object');
        insert account;

        List<AMF_RuleDefinition> withBrokenRule = new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder()
                .named('PR_Broken')
                .withPriority(10)
                .withExpression('Nonexistent__c == \'x\'')
                .routingTo(THREE_LEVEL)
                .build(),
            new AMF_RuleBuilder()
                .named('PR_Catch_All')
                .withPriority(9999)
                .withExpression('TRUE')
                .routingTo(TWO_LEVEL)
                .build()
        };
        AMF_StrategyStub strategy = new AMF_StrategyStub();

        Test.startTest();
        List<AMF_ApprovalMatrixService.Outcome> outcomes = serviceWith(withBrokenRule, strategy)
            .submitEach(new List<Id>{ first.Id, account.Id, second.Id });
        Test.stopTest();

        for (Integer i : new List<Integer>{ 0, 2 }) {
            Assert.areEqual('Refused', outcomes[i].outcome);
            Assert.isTrue(
                outcomes[i].message.contains('position'),
                'The positioned compile error (4.2). Got: ' + outcomes[i].message
            );
        }
        Assert.areEqual('Refused', outcomes[1].outcome, 'The Account is answered for its own reason');
        Assert.isTrue(outcomes[1].message.contains('Matrix_Submission__c'), 'Got: ' + outcomes[1].message);

        Assert.areEqual(0, strategy.calls, 'The catch-all must NOT pick either record up');
        Assert.areEqual(0, [SELECT COUNT() FROM Approval_Decision_Log__c], 'Nothing was decided, so nothing is logged');
    }

    @IsTest
    static void submitEachRecordsABlockAndAFailureJustAsSubmitDoes() {
        // Only Refused is new. Every decided outcome keeps its row and its meaning.
        Purchase_Request__c blocked = request(500, 'EMEA', 'Low');
        Purchase_Request__c failed = request(500, 'EMEA', 'High');
        insert new List<Purchase_Request__c>{ blocked, failed };

        List<AMF_RuleDefinition> rules = new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder()
                .named('PR_High_Risk')
                .withPriority(20)
                .withExpression('Risk_Level__c == \'High\'')
                .routingTo(null)
                .build()
        };
        AMF_StrategyStub strategy = new AMF_StrategyStub();

        Test.startTest();
        List<AMF_ApprovalMatrixService.Outcome> outcomes = serviceWith(rules, strategy)
            .submitEach(new List<Id>{ blocked.Id, failed.Id });
        Test.stopTest();

        Assert.areEqual('Blocked_No_Match', outcomes[0].outcome);
        Assert.areEqual('Blocked_No_Match', logsFor(blocked.Id)[0].Outcome__c);
        Assert.areEqual(logsFor(blocked.Id)[0].Id, outcomes[0].decisionLogId);

        Assert.areEqual('Failed', outcomes[1].outcome);
        Assert.isTrue(outcomes[1].message.contains('Process_API_Name__c'), 'Got: ' + outcomes[1].message);
        Assert.areEqual('Failed', logsFor(failed.Id)[0].Outcome__c);

        Assert.areEqual(0, strategy.calls, 'Neither was routed');
    }

    @IsTest
    static void submitEachSubmitsARecordSuppliedTwiceOnceAndAnswersBoth() {
        Purchase_Request__c record = request(500, 'EMEA', 'Low');
        Purchase_Request__c other = request(500, 'AMER', 'Low');
        insert new List<Purchase_Request__c>{ record, other };

        AMF_StrategyStub strategy = new AMF_StrategyStub();

        Test.startTest();
        List<AMF_ApprovalMatrixService.Outcome> outcomes = serviceWith(shippedShape(), strategy)
            .submitEach(new List<Id>{ record.Id, other.Id, record.Id });
        Test.stopTest();

        Assert.areEqual(3, outcomes.size(), 'One answer per request');
        Assert.areEqual(record.Id, outcomes[2].recordId);
        Assert.isTrue(outcomes[0].submitted);
        Assert.isTrue(outcomes[2].submitted);
        Assert.areEqual(outcomes[0].decisionLogId, outcomes[2].decisionLogId, 'The same answer, not a second submission');
        Assert.areEqual(outcomes[0].executionRefId, outcomes[2].executionRefId);
        Assert.areEqual(2, strategy.received.size(), 'Each record submitted once');
        Assert.areEqual(1, logsFor(record.Id).size(), 'And logged once');
    }

    @IsTest
    static void submitRefusesARecordSuppliedTwice() {
        // submit() answers for the whole call, and a duplicate would be submitted
        // twice: the second refused by the platform, and the guard of the first,
        // by then pending, re-armed (docs/decisions.md, 2026-10-08).
        Purchase_Request__c record = request(500, 'EMEA', 'Low');
        insert record;

        AMF_StrategyStub strategy = new AMF_StrategyStub();

        try {
            serviceWith(shippedShape(), strategy).submit(new List<Id>{ record.Id, record.Id });
            Assert.fail('A record supplied twice must be refused');
        } catch (AMF_SubmissionException e) {
            Assert.isTrue(e.getMessage().contains('more than once'), 'Got: ' + e.getMessage());
            Assert.isTrue(e.getMessage().contains(String.valueOf(record.Id)), 'It names the record');
        }

        Assert.areEqual(0, strategy.calls);
        Assert.areEqual(0, logsFor(record.Id).size());
    }

    @IsTest
    static void submitEachAnswersANullIdByItselfAndAnEmptyCallWithNothing() {
        Purchase_Request__c record = request(500, 'EMEA', 'Low');
        insert record;

        AMF_ApprovalMatrixService service = serviceWith(shippedShape(), new AMF_StrategyStub());

        List<AMF_ApprovalMatrixService.Outcome> outcomes = service.submitEach(new List<Id>{ null, record.Id });

        Assert.areEqual(2, outcomes.size());
        Assert.isNull(outcomes[0].recordId);
        Assert.areEqual('Refused', outcomes[0].outcome);
        Assert.isTrue(outcomes[0].message.contains('record Id is required'), 'Got: ' + outcomes[0].message);
        Assert.isTrue(outcomes[1].submitted, 'A null beside it does not stop the record');

        Assert.areEqual(0, service.submitEach(null).size(), 'Nothing in, nothing out -- not an exception');
        Assert.areEqual(0, service.submitEach(new List<Id>()).size());
    }

    @IsTest
    static void aStrategyThatLeavesARecordUnansweredFailsTheCallAndLeavesNothingBehind() {
        // 6.2's M10 note: one answer per request. A record with none has an
        // unknown fate, so there is nothing true to log. The engine rolls the
        // call back itself, so even a caller that catches the exception -- a
        // Flow fault path -- keeps no staged guard and no submission.
        Purchase_Request__c answered = request(500, 'EMEA', 'Low');
        Purchase_Request__c unanswered = request(500, 'AMER', 'Low');
        insert new List<Purchase_Request__c>{ answered, unanswered };

        AMF_StrategyStub strategy = new AMF_StrategyStub();
        strategy.omit.add(unanswered.Id);

        Test.startTest();
        try {
            serviceWith(shippedShape(), strategy).submitEach(new List<Id>{ answered.Id, unanswered.Id });
            Assert.fail('A request the strategy did not answer must fail the call');
        } catch (AMF_SubmissionException e) {
            Assert.isTrue(e.getMessage().contains('no answer'), 'Got: ' + e.getMessage());
            Assert.isTrue(e.getMessage().contains(String.valueOf(unanswered.Id)), 'It names the record');
        }
        Test.stopTest();

        Assert.isTrue(strategy.guardAtSubmit.get(answered.Id), 'Precondition: the guard was staged before submit');
        Assert.isFalse(guardOf(answered.Id), 'The staged guard was rolled back');
        Assert.isFalse(guardOf(unanswered.Id));
        Assert.areEqual(0, [SELECT COUNT() FROM Approval_Decision_Log__c], 'And nothing was logged');
    }

    @IsTest
    static void twoHundredRecordsCostTheEngineWhatThreeDo() {
        // 4.4 and 4.5 at a Flow batch's size. The engine's queries are per call,
        // not per record: authorisation (one per 200 records), the pending check,
        // the union load and the stub's read. The real platform at this size is
        // AMF_SubmissionIntegrationTest's job.
        List<Purchase_Request__c> records = new List<Purchase_Request__c>();

        for (Integer i = 0; i < 200; i++) {
            records.add(request(250000 + i, Math.mod(i, 2) == 0 ? 'APAC' : 'EMEA', 'Low'));
        }
        insert records;

        List<Id> recordIds = new List<Id>();

        for (Purchase_Request__c record : records) {
            recordIds.add(record.Id);
        }

        AMF_StrategyStub strategy = new AMF_StrategyStub();

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        List<AMF_ApprovalMatrixService.Outcome> outcomes = serviceWith(shippedShape(), strategy)
            .submitEach(recordIds);
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Test.stopTest();

        Assert.areEqual(200, outcomes.size());
        for (AMF_ApprovalMatrixService.Outcome outcome : outcomes) {
            Assert.isTrue(outcome.submitted, outcome.recordId + ': ' + outcome.message);
        }
        Assert.areEqual(1, strategy.calls, 'One strategy call; chunking for the platform is the strategy\'s job');
        Assert.areEqual(
            200,
            [SELECT COUNT() FROM Approval_Decision_Log__c WHERE Execution_Ref_Id__c != NULL],
            'Every row written once, with its reference'
        );
        Assert.isTrue(queriesUsed <= 4, 'The same four queries as for three records. Used: ' + queriesUsed);
    }

    @IsTest
    static void moreThanTwoHundredRecordsAreAuthorisedInChunks() {
        // UserRecordAccess answers for at most 200 records per query, and an Apex
        // caller of submitEach() is not held to the REST cap. 201 records take
        // two access queries, not an exception.
        List<Purchase_Request__c> records = new List<Purchase_Request__c>();

        for (Integer i = 0; i < 201; i++) {
            records.add(request(500, 'EMEA', 'Low'));
        }
        insert records;

        List<Id> recordIds = new List<Id>();

        for (Purchase_Request__c record : records) {
            recordIds.add(record.Id);
        }

        Test.startTest();
        Integer queriesBefore = Limits.getQueries();
        List<AMF_ApprovalMatrixService.Outcome> outcomes = serviceWith(shippedShape(), new AMF_StrategyStub())
            .submitEach(recordIds);
        Integer queriesUsed = Limits.getQueries() - queriesBefore;
        Test.stopTest();

        Integer submitted = 0;
        for (AMF_ApprovalMatrixService.Outcome outcome : outcomes) {
            submitted += outcome.submitted ? 1 : 0;
        }
        Assert.areEqual(201, submitted, 'Every record the caller can read is authorised');
        Assert.isTrue(queriesUsed <= 5, 'Two access queries, then the same three. Used: ' + queriesUsed);
    }

    private static Boolean guardOf(Id recordId) {
        return [SELECT Matrix_Submission__c FROM Purchase_Request__c WHERE Id = :recordId]
        .Matrix_Submission__c;
    }

    /** A Standard User with no framework permission set and no access to the test's records. */
    private static User strangerUser() {
        User stranger = standardUser('amfstr', 'Stranger');
        // User is a setup object: inserting one in the same transaction as a
        // Purchase_Request__c is MIXED_DML_OPERATION without this wrapper.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert stranger;
        }
        return stranger;
    }

    /**
     * A Standard User holding Approval_Matrix_User: a real submitter, who reads
     * the Purchase Requests they own and, the object being Private, no others.
     */
    private static User submitterUser() {
        User submitter = standardUser('amfsub', 'Submitter');
        PermissionSet matrix = [SELECT Id FROM PermissionSet WHERE Name = 'Approval_Matrix_User' LIMIT 1];

        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert submitter;
            insert new PermissionSetAssignment(AssigneeId = submitter.Id, PermissionSetId = matrix.Id);
        }
        return submitter;
    }

    private static User standardUser(String alias, String lastName) {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String name = 'amf.' + lastName.toLowerCase();
        return new User(
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
    }
}
