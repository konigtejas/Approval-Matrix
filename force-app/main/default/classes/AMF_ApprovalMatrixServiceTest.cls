/**
 * The engine's unit suite: 6.1 steps 1-11 driven entirely through in-memory
 * rules and a stub strategy, so nothing here depends on an org CMDT row or runs
 * a real approval.
 *
 * Architecture section: 6.1, 6.3, 4.6, 10, 11.
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

        // 6.1 step 11, and the one post-insert update Lock_Decision_Log allows.
        Assert.areEqual(
            outcomes[0].executionRefId,
            row.Execution_Ref_Id__c,
            'Execution_Ref_Id__c is stamped back onto the row after submit'
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
        // framework exists to prevent. 9's validator would catch this at deploy
        // time; 9 is out of MVP scope (13.2), so it surfaces here.
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
            'One union query plus authorisation and the stub read, not one per rule ' +
            '(4.4). Queries used: ' + (queriesAfter - queriesBefore)
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
        // 4.6 at the engine's own boundary. The strategy throwing must reach the
        // caller, because the decision log rows already say Submitted and
        // Lock_Decision_Log will not let the engine walk that back (M1.3).
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

    private static User strangerUser() {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User stranger = new User(
            Alias = 'amfstr',
            Email = 'amf.stranger@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Stranger',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standard.Id,
            TimeZoneSidKey = 'GMT',
            Username = 'amf.stranger.' +
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
}
