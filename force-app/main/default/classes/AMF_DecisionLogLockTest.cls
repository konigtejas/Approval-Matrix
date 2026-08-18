/**
 * Verifies the Lock_Decision_Log validation rule, which is the mechanism behind
 * arch doc 3.3's "immutable, never deleted" claim.
 *
 * Architecture section: 3.3 (immutability), 6.1 step 11 (the stamp), 8.
 *
 * This rule is not a plain freeze, because two sections of the architecture doc
 * pull against each other: 3.3 says a decision log row cannot be edited after
 * creation, while 6.1 step 11 requires the engine to stamp Execution_Ref_Id__c
 * onto the row AFTER submit. The resolution, agreed before M1 was built and
 * recorded in docs/decisions.md, is that the rule permits exactly one update --
 * Execution_Ref_Id__c moving from blank to populated, with no other governed
 * field changing -- and freezes everything else.
 *
 * M3's engine depends on that contract precisely, so it is pinned here rather
 * than discovered during M3's manual QA.
 *
 * These tests must run as a user WITHOUT AMF_Bypass_Log_Lock. Assigning
 * Approval_Matrix_Admin to yourself grants that permission and disarms the rule
 * completely, which is why the last method below asserts the escape hatch works
 * too -- an admin who tests the lock while holding the bypass will wrongly
 * conclude it is broken.
 */
@IsTest
private class AMF_DecisionLogLockTest {

    private static final String STAMP = '04gaj000000000001A';
    private static final String OTHER_STAMP = '04gaj000000000002B';

    /**
     * A seeded user, deliberately holding neither permission set and therefore
     * not the bypass. Queried rather than inserted: Phase 0 hit
     * LICENSE_LIMIT_EXCEEDED creating users in this org, and these five already
     * exist as the manager chain M3's PR_Two_Level_Mgmt template needs.
     */
    private static User subjectWithoutBypass() {
        List<User> seeded = [SELECT Id FROM User WHERE Alias = 'amfu1' AND IsActive = true LIMIT 1];
        Assert.isFalse(
            seeded.isEmpty(),
            'Seeded user amfu1 is missing; run scripts/seed-data.apex against this org first'
        );
        return seeded[0];
    }

    private static Approval_Decision_Log__c newRow(String outcome) {
        return new Approval_Decision_Log__c(
            Record_Id__c = 'a00aj000000000001A',
            Object_API_Name__c = 'Purchase_Request__c',
            Matched_Rule__c = 'PR_High_Value_APAC',
            Rule_Version__c = 1,
            Expression_Snapshot__c = 'Amount__c > 100000 && Region__c == \'APAC\'',
            Evaluated_Values__c = '{"Amount__c":2400000,"Region__c":"APAC"}',
            Selected_Process__c = 'PR_Three_Level_Finance',
            Outcome__c = outcome,
            Submitted_At__c = System.now()
        );
    }

    /**
     * THE M3 CONTRACT. Insert, then stamp once: that update must succeed, or the
     * engine's step 11 cannot work at all.
     */
    @IsTest
    static void engineMayStampExecutionRefIdOnce() {
        Approval_Decision_Log__c row = newRow('Submitted');

        System.runAs(subjectWithoutBypass()) {
            insert row;

            row.Execution_Ref_Id__c = STAMP;
            update row;
        }

        Assert.areEqual(
            STAMP,
            [SELECT Execution_Ref_Id__c FROM Approval_Decision_Log__c WHERE Id = :row.Id].Execution_Ref_Id__c,
            'The one permitted update is the engine stamping Execution_Ref_Id__c after submit (arch doc 6.1 step 11)'
        );
    }

    /**
     * Once stamped, the row is frozen forever -- including against a second
     * stamp, which is what stops the provenance pointer being rewritten.
     */
    @IsTest
    static void stampedRowCannotBeStampedAgain() {
        Approval_Decision_Log__c row = newRow('Submitted');

        System.runAs(subjectWithoutBypass()) {
            insert row;
            row.Execution_Ref_Id__c = STAMP;
            update row;

            row.Execution_Ref_Id__c = OTHER_STAMP;
            try {
                update row;
                Assert.fail('A second stamp must be blocked; the row is an audit record once stamped');
            } catch (DmlException e) {
                assertLockFired(e);
            }
        }
    }

    /**
     * The stamping update may not smuggle other changes through with it.
     */
    @IsTest
    static void stampMayNotAlsoChangeAGovernedField() {
        Approval_Decision_Log__c row = newRow('Submitted');

        System.runAs(subjectWithoutBypass()) {
            insert row;

            row.Execution_Ref_Id__c = STAMP;
            row.Outcome__c = 'Failed';
            try {
                update row;
                Assert.fail('Changing Outcome__c alongside the stamp must be blocked');
            } catch (DmlException e) {
                assertLockFired(e);
            }
        }
    }

    /**
     * Rows that never get stamped -- Blocked_No_Match and Failed -- are frozen
     * from the moment they are created, because there is no legitimate second
     * write to them at all.
     */
    @IsTest
    static void unstampedRowIsFrozenImmediately() {
        Approval_Decision_Log__c row = newRow('Blocked_No_Match');
        row.Selected_Process__c = null;

        System.runAs(subjectWithoutBypass()) {
            insert row;

            row.Failure_Detail__c = 'Tampering with the audit trail after the fact.';
            try {
                update row;
                Assert.fail('A row with no Execution_Ref_Id__c has no permitted update');
            } catch (DmlException e) {
                assertLockFired(e);
            }
        }
    }

    @IsTest
    static void frozenRowRejectsAnEditToTheMatchedRule() {
        Approval_Decision_Log__c row = newRow('Submitted');

        System.runAs(subjectWithoutBypass()) {
            insert row;
            row.Execution_Ref_Id__c = STAMP;
            update row;

            row.Matched_Rule__c = 'PR_Catch_All';
            try {
                update row;
                Assert.fail('Rewriting which rule matched is exactly what the lock exists to prevent');
            } catch (DmlException e) {
                assertLockFired(e);
            }
        }
    }

    /**
     * The documented escape hatch, and the trap that comes with it: a holder of
     * AMF_Bypass_Log_Lock edits freely. The test-running user holds
     * Approval_Matrix_Admin, which grants it -- so anyone verifying the lock
     * while assigned that permission set will see no error and draw the wrong
     * conclusion.
     */
    @IsTest
    static void bypassPermissionHolderCanCorrectARow() {
        Assert.isTrue(
            FeatureManagement.checkPermission('AMF_Bypass_Log_Lock'),
            'This test assumes the running user holds the bypass via Approval_Matrix_Admin'
        );

        Approval_Decision_Log__c row = newRow('Submitted');
        insert row;

        row.Matched_Rule__c = 'PR_Catch_All';
        row.Outcome__c = 'Failed';
        update row;

        Assert.areEqual(
            'PR_Catch_All',
            [SELECT Matched_Rule__c FROM Approval_Decision_Log__c WHERE Id = :row.Id].Matched_Rule__c,
            'AMF_Bypass_Log_Lock is the sanctioned exception in arch doc 3.3'
        );
    }

    private static void assertLockFired(DmlException e) {
        Assert.isTrue(
            e.getMessage().contains('immutable audit record'),
            'Expected Lock_Decision_Log to fire, but got: ' + e.getMessage()
        );
    }
}
