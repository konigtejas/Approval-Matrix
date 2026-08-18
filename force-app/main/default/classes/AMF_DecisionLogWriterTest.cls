/**
 * The audit artefact's own suite: one row per outcome, and the single
 * post-insert stamp Lock_Decision_Log permits.
 *
 * Architecture section: 3.3, 6.1 steps 8 and 11, 8.
 *
 * AMF_DecisionLogLockTest (M1) covers the validation rule from the rule's side.
 * This covers it from the writer's -- that the engine's one legitimate update
 * passes, and that the row shapes it produces are the ones 3.3 describes.
 */
@IsTest
private class AMF_DecisionLogWriterTest {

    private static final String OBJECT_NAME = 'Purchase_Request__c';

    private static AMF_RuleDefinition rule() {
        return new AMF_RuleBuilder()
            .named('PR_High_Value_APAC')
            .withExpression('Amount__c > 100000 && Region__c == \'APAC\'')
            .routingTo('PR_Three_Level_Finance')
            .atVersion(7)
            .build();
    }

    /**
     * The seeded amfu1, who holds neither permission set and therefore not
     * AMF_Bypass_Log_Lock. Same subject AMF_DecisionLogLockTest uses, for the
     * same reason (M1.10).
     */
    private static User subjectWithoutBypass() {
        List<User> seeded = [SELECT Id FROM User WHERE Alias = 'amfu1' AND IsActive = TRUE LIMIT 1];
        Assert.areEqual(
            1,
            seeded.size(),
            'Seeded user amfu1 is missing; run scripts/seed-data.apex against this org first'
        );
        return seeded[0];
    }

    private static Purchase_Request__c governedRecord() {
        Purchase_Request__c record = new Purchase_Request__c(
            Amount__c = 250000,
            Region__c = 'APAC',
            Risk_Level__c = 'Low'
        );
        insert record;
        return record;
    }

    @IsTest
    static void aSubmittedRowSnapshotsTheRuleRatherThanReferencingIt() {
        Purchase_Request__c record = governedRecord();

        Approval_Decision_Log__c row = AMF_DecisionLogWriter.forSubmission(
            record.Id,
            OBJECT_NAME,
            rule(),
            '{"Amount__c":250000,"Region__c":"APAC"}'
        );
        AMF_DecisionLogWriter.save(new List<Approval_Decision_Log__c>{ row });

        Approval_Decision_Log__c saved = [
            SELECT
                Record_Id__c,
                Object_API_Name__c,
                Matched_Rule__c,
                Rule_Version__c,
                Expression_Snapshot__c,
                Selected_Process__c,
                Evaluated_Values__c,
                Execution_Ref_Id__c,
                Outcome__c,
                Submitted_By__c,
                Submitted_At__c
            FROM Approval_Decision_Log__c
            WHERE Id = :row.Id
        ];

        Assert.areEqual('Submitted', saved.Outcome__c);
        Assert.areEqual(String.valueOf(record.Id), saved.Record_Id__c);
        Assert.areEqual(OBJECT_NAME, saved.Object_API_Name__c);
        Assert.areEqual('PR_High_Value_APAC', saved.Matched_Rule__c);
        Assert.areEqual(7, saved.Rule_Version__c);
        Assert.areEqual(
            'Amount__c > 100000 && Region__c == \'APAC\'',
            saved.Expression_Snapshot__c,
            '3.3: the expression text as evaluated, so a later edit cannot rewrite history'
        );
        Assert.areEqual('PR_Three_Level_Finance', saved.Selected_Process__c);
        Assert.areEqual('{"Amount__c":250000,"Region__c":"APAC"}', saved.Evaluated_Values__c);
        Assert.areEqual(UserInfo.getUserId(), saved.Submitted_By__c);
        Assert.isNotNull(saved.Submitted_At__c);
        Assert.isNull(saved.Execution_Ref_Id__c, 'Written before submit, so blank until step 11');
    }

    @IsTest
    static void aNoMatchRowNamesNoRuleAndNoProcess() {
        Purchase_Request__c record = governedRecord();

        Approval_Decision_Log__c row = AMF_DecisionLogWriter.forNoMatch(
            record.Id,
            OBJECT_NAME,
            '{"Risk_Level__c":"Low"}',
            'No active rule matched.'
        );
        AMF_DecisionLogWriter.save(new List<Approval_Decision_Log__c>{ row });

        Approval_Decision_Log__c saved = [
            SELECT Outcome__c, Matched_Rule__c, Selected_Process__c, Evaluated_Values__c, Failure_Detail__c
            FROM Approval_Decision_Log__c
            WHERE Id = :row.Id
        ];

        Assert.areEqual('Blocked_No_Match', saved.Outcome__c);
        Assert.isNull(saved.Matched_Rule__c);
        Assert.isNull(saved.Selected_Process__c);
        Assert.areEqual('No active rule matched.', saved.Failure_Detail__c);
        Assert.areEqual(
            '{"Risk_Level__c":"Low"}',
            saved.Evaluated_Values__c,
            'With no winner, the row still shows what the engine read'
        );
    }

    @IsTest
    static void aFailedRowNamesTheRuleThatWasUnderEvaluation() {
        Purchase_Request__c record = governedRecord();

        Approval_Decision_Log__c row = AMF_DecisionLogWriter.forFailure(
            record.Id,
            OBJECT_NAME,
            rule(),
            '{}',
            'System.SObjectException: SObject row was retrieved via SOQL without querying Amount__c'
        );
        AMF_DecisionLogWriter.save(new List<Approval_Decision_Log__c>{ row });

        Approval_Decision_Log__c saved = [
            SELECT Outcome__c, Matched_Rule__c, Rule_Version__c, Expression_Snapshot__c, Failure_Detail__c
            FROM Approval_Decision_Log__c
            WHERE Id = :row.Id
        ];

        Assert.areEqual('Failed', saved.Outcome__c);
        Assert.areEqual('PR_High_Value_APAC', saved.Matched_Rule__c);
        Assert.areEqual(7, saved.Rule_Version__c);
        Assert.isTrue(
            saved.Failure_Detail__c.contains('SObjectException'),
            '4.6: the exception text is kept, not summarised away'
        );
    }

    @IsTest
    static void aFailureWithNoRuleYetStillGetsARow() {
        Purchase_Request__c record = governedRecord();

        Approval_Decision_Log__c row = AMF_DecisionLogWriter.forFailure(
            record.Id,
            OBJECT_NAME,
            null,
            '{}',
            'Failed before any rule was reached'
        );
        AMF_DecisionLogWriter.save(new List<Approval_Decision_Log__c>{ row });

        Approval_Decision_Log__c saved = [
            SELECT Outcome__c, Matched_Rule__c, Expression_Snapshot__c
            FROM Approval_Decision_Log__c
            WHERE Id = :row.Id
        ];

        Assert.areEqual('Failed', saved.Outcome__c);
        Assert.isNull(saved.Matched_Rule__c);
        Assert.isNull(saved.Expression_Snapshot__c);
    }

    @IsTest
    static void anOverlongFailureIsTruncatedRatherThanRejectedByTheField() {
        // Failure_Detail__c is Long Text(4000); a stack trace is not bounded.
        // Losing the row to a STRING_TOO_LONG would be the worst of both worlds.
        Purchase_Request__c record = governedRecord();

        Approval_Decision_Log__c row = AMF_DecisionLogWriter.forFailure(
            record.Id,
            OBJECT_NAME,
            rule(),
            '{}',
            'x'.repeat(5000)
        );
        AMF_DecisionLogWriter.save(new List<Approval_Decision_Log__c>{ row });

        Approval_Decision_Log__c saved = [
            SELECT Failure_Detail__c
            FROM Approval_Decision_Log__c
            WHERE Id = :row.Id
        ];
        Assert.areEqual(4000, saved.Failure_Detail__c.length(), 'Truncated to the field width');
    }

    @IsTest
    static void stampWritesTheExecutionReferenceAndNothingElse() {
        // 6.1 step 11 against M1.3's lock, and the M1.10 carried item stated as
        // a test: the stamp is built from scratch -- a fresh SObject carrying
        // only Id and Execution_Ref_Id__c -- so it cannot dirty a field the
        // validation rule watches, however the caller has handled the row since.
        //
        // RUN WITHOUT THE BYPASS, deliberately. Approval_Matrix_Admin grants
        // AMF_Bypass_Log_Lock (M1.6e), so a test running as the deploying admin
        // would pass whether or not the stamp were legal -- the lock would
        // simply never fire. Only a user without the permission proves that
        // step 11 survives the rule in the conditions a real submitter meets.
        Purchase_Request__c record = governedRecord();

        Approval_Decision_Log__c row = AMF_DecisionLogWriter.forSubmission(
            record.Id,
            OBJECT_NAME,
            rule(),
            '{}'
        );
        AMF_DecisionLogWriter.save(new List<Approval_Decision_Log__c>{ row });

        Test.startTest();
        System.runAs(subjectWithoutBypass()) {
            AMF_DecisionLogWriter.stamp(new Map<Id, String>{ row.Id => '04g000000000001AAA' });
        }
        Test.stopTest();

        Approval_Decision_Log__c saved = [
            SELECT Execution_Ref_Id__c, Outcome__c, Matched_Rule__c, Selected_Process__c
            FROM Approval_Decision_Log__c
            WHERE Id = :row.Id
        ];
        Assert.areEqual('04g000000000001AAA', saved.Execution_Ref_Id__c);
        Assert.areEqual('Submitted', saved.Outcome__c, 'Untouched by the stamp');
        Assert.areEqual('PR_High_Value_APAC', saved.Matched_Rule__c, 'Untouched by the stamp');
        Assert.areEqual('PR_Three_Level_Finance', saved.Selected_Process__c, 'Untouched by the stamp');
    }

    // A SECOND STAMP is not asserted here on purpose. Lock_Decision_Log's own
    // semantics -- one blank-to-populated update and no more -- are owned by
    // AMF_DecisionLogLockTest, which M1 built for exactly that and which already
    // runs every case as a user without the bypass. Re-asserting it from this
    // side would duplicate that coverage and add a second dependency on the
    // seeded org user for no new information.

    @IsTest
    static void aBlankReferenceIsRefusedWithTheEnginesOwnMessage() {
        Purchase_Request__c record = governedRecord();

        Approval_Decision_Log__c row = AMF_DecisionLogWriter.forSubmission(
            record.Id,
            OBJECT_NAME,
            rule(),
            '{}'
        );
        AMF_DecisionLogWriter.save(new List<Approval_Decision_Log__c>{ row });

        try {
            AMF_DecisionLogWriter.stamp(new Map<Id, String>{ row.Id => null });
            Assert.fail('A blank reference must be refused before it reaches the lock rule');
        } catch (AMF_SubmissionException e) {
            Assert.isTrue(
                e.getMessage().contains('blank execution reference'),
                'Got: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void emptyWorkIsNotWork() {
        AMF_DecisionLogWriter.save(null);
        AMF_DecisionLogWriter.save(new List<Approval_Decision_Log__c>());
        AMF_DecisionLogWriter.stamp(null);
        AMF_DecisionLogWriter.stamp(new Map<Id, String>());

        Assert.areEqual(
            0,
            [SELECT COUNT() FROM Approval_Decision_Log__c],
            'No rows, no DML, no exception'
        );
    }
}
