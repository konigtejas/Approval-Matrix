/**
 * The impact check (M15): the engine previews recently decided records under
 * the live matrix and under the changed one, and the two are compared.
 *
 * Architecture section: 6.4 (its M15 note), 3.1, 10.
 *
 * The matrix is in memory (CLAUDE.md). The decision log rows that say which
 * records were recently decided are inserted directly, shaped as
 * AMF_DecisionLogWriter writes them. Nothing is submitted.
 */
@IsTest
private class AMF_MatrixImpactTest {

    private static final String TWO_LEVEL = 'PR_Two_Level_Mgmt';
    private static final String COMMITTEE = 'PR_Finance_Committee';

    private static List<AMF_RuleDefinition> catchAllOnly() {
        return new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder().named('PR_Catch_All').withPriority(9999).withExpression('TRUE').routingTo(TWO_LEVEL).build()
        };
    }

    private static AMF_RuleDefinition emeaLarge() {
        return new AMF_RuleBuilder()
            .named('PR_EMEA_Large')
            .withPriority(15)
            .withExpression('Amount__c > 500000 && Region__c == \'EMEA\'')
            .routingTo(COMMITTEE)
            .build();
    }

    /** Requests, each with a recent decision log row, as the matrix's own traffic. */
    private static List<Purchase_Request__c> decided(List<Decimal> amounts) {
        List<Purchase_Request__c> records = new List<Purchase_Request__c>();
        for (Decimal amount : amounts) {
            records.add(new Purchase_Request__c(Amount__c = amount, Region__c = 'EMEA', Risk_Level__c = 'Low'));
        }
        insert records;

        List<Approval_Decision_Log__c> rows = new List<Approval_Decision_Log__c>();
        for (Purchase_Request__c record : records) {
            rows.add(rowFor(record.Id, Datetime.now().addDays(-2)));
        }
        insert rows;
        return records;
    }

    private static Approval_Decision_Log__c rowFor(Id recordId, Datetime submittedAt) {
        return new Approval_Decision_Log__c(
            Record_Id__c = String.valueOf(recordId),
            Object_API_Name__c = 'Purchase_Request__c',
            Outcome__c = 'Submitted',
            Matched_Rule__c = 'PR_Catch_All',
            Rule_Version__c = 1,
            Expression_Snapshot__c = 'TRUE',
            Evaluated_Values__c = '{}',
            Selected_Process__c = TWO_LEVEL,
            Submitted_By__c = UserInfo.getUserId(),
            Submitted_At__c = submittedAt
        );
    }

    private static void assertContains(String text, String expected) {
        Assert.isTrue(text != null && text.contains(expected), 'Expected "' + expected + '" in:\n' + text);
    }

    @IsTest
    static void aNewRuleChangesTheDecisionOnlyOnTheRecordsItCatches() {
        List<Purchase_Request__c> records = decided(new List<Decimal>{ 600000, 500 });
        String large = 'Purchase Request ' + [SELECT Name FROM Purchase_Request__c WHERE Id = :records[0].Id].Name;

        Test.startTest();
        AMF_MatrixImpact.Report report = new AMF_MatrixImpact(new AMF_RuleBuilder.Stub(catchAllOnly()))
            .check('Purchase_Request__c', null, emeaLarge(), 'the new rule PR_EMEA_Large');
        Test.stopTest();

        Assert.isTrue(report.ran, report.summary);
        Assert.areEqual(2, report.checked);
        Assert.areEqual(1, report.changed, 'Only the 600,000 request is caught');
        Assert.areEqual(0, report.skipped);
        Assert.areEqual(
            new List<String>{
                '1. ' + large + ' (Id ' + records[0].Id + '): today PR_Catch_All sends it to PR_Two_Level_Mgmt; ' +
                'with the change PR_EMEA_Large sends it to PR_Finance_Committee.'
            },
            report.changes
        );
        assertContains(report.summary, 'Checked 2 Purchase Requests decided in the last 90 days, on their values today.');
        assertContains(report.summary, '1 would be decided differently with the new rule PR_EMEA_Large (by another rule, or to another process).');
        assertContains(report.summary, 'Today: PR_Two_Level_Mgmt 2. With the change: PR_Finance_Committee 1, PR_Two_Level_Mgmt 1.');
        Assert.isTrue(report.summary.endsWith('Nothing was changed, submitted or recorded.'), report.summary);

        Assert.areEqual(2, [SELECT COUNT() FROM Approval_Decision_Log__c], 'No row added');
        Assert.areEqual(0, [SELECT COUNT() FROM Purchase_Request__c WHERE Matrix_Submission__c = TRUE], 'No guard set');
    }

    @IsTest
    static void takingOutTheOnlyRuleLeavesTheMatrixUnableToDecideAnyRecord() {
        decided(new List<Decimal>{ 600000, 500 });

        AMF_MatrixImpact.Report report = new AMF_MatrixImpact(new AMF_RuleBuilder.Stub(catchAllOnly()))
            .check('Purchase_Request__c', 'PR_Catch_All', null, 'rule PR_Catch_All taken out');

        Assert.isTrue(report.ran);
        Assert.areEqual(2, report.changed, 'Every record it would reach');
        assertContains(report.summary, 'With rule PR_Catch_All taken out, the approval matrix could not decide any of the 2 Purchase Requests');
        assertContains(report.summary, 'not governed by the approval matrix');
    }

    @IsTest
    static void aRecordTheAdministratorCannotReadIsSkippedNotCompared() {
        User reader = new User(
            Alias = 'amfimp',
            Email = 'amf.impact@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Impact',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey = 'GMT',
            Username = 'amf.impact.' + String.valueOf(Datetime.now().getTime()) + '@amf.test.invalid'
        );
        PermissionSet matrix = [SELECT Id FROM PermissionSet WHERE Name = 'Approval_Matrix_User' LIMIT 1];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert reader;
            insert new PermissionSetAssignment(AssigneeId = reader.Id, PermissionSetId = matrix.Id);
        }

        Purchase_Request__c theirs = new Purchase_Request__c(Amount__c = 600000, Region__c = 'EMEA', Risk_Level__c = 'Low', OwnerId = reader.Id);
        Purchase_Request__c notTheirs = new Purchase_Request__c(Amount__c = 600000, Region__c = 'EMEA', Risk_Level__c = 'Low');
        insert new List<Purchase_Request__c>{ theirs, notTheirs };
        // Both rows are the reader's, so they can see that both were decided.
        List<Approval_Decision_Log__c> rows = new List<Approval_Decision_Log__c>{
            rowFor(theirs.Id, Datetime.now().addDays(-1)),
            rowFor(notTheirs.Id, Datetime.now().addDays(-1))
        };
        for (Approval_Decision_Log__c row : rows) {
            row.OwnerId = reader.Id;
        }
        insert rows;

        AMF_MatrixImpact.Report report;
        System.runAs(reader) {
            report = new AMF_MatrixImpact(new AMF_RuleBuilder.Stub(catchAllOnly()))
                .check('Purchase_Request__c', null, emeaLarge(), 'the new rule PR_EMEA_Large');
        }

        Assert.areEqual(1, report.checked, report.summary);
        Assert.areEqual(1, report.skipped);
        assertContains(report.summary, '1 were skipped, because they are in an approval process now or you cannot read them.');
    }

    @IsTest
    static void saysSoWhenThereIsNothingToCompareOrNoChangeToMake() {
        AMF_MatrixImpact impact = new AMF_MatrixImpact(new AMF_RuleBuilder.Stub(catchAllOnly()));

        AMF_MatrixImpact.Report none = impact.check('Purchase_Request__c', null, emeaLarge(), 'the new rule PR_EMEA_Large');
        Assert.isTrue(none.ran);
        Assert.areEqual(
            'No Purchase Requests were decided by the approval matrix in the last 90 days, so there is nothing to ' +
            'compare the new rule PR_EMEA_Large against. Nothing was changed.',
            none.summary
        );

        // An old decision is outside the period.
        Purchase_Request__c old = new Purchase_Request__c(Amount__c = 600000, Region__c = 'EMEA', Risk_Level__c = 'Low');
        insert old;
        insert rowFor(old.Id, Datetime.now().addDays(-(AMF_MatrixImpact.DAYS + 1)));
        Assert.areEqual(0, impact.check('Purchase_Request__c', null, emeaLarge(), 'x').checked);

        AMF_MatrixImpact.Report noChange = impact.check('Purchase_Request__c', ' ', null, 'nothing');
        Assert.isFalse(noChange.ran);
        assertContains(noChange.summary, 'needs a rule to add, replace or take out');

        AMF_MatrixImpact.Report noObject = impact.check('No_Such_Object__c', null, emeaLarge(), 'x');
        Assert.isFalse(noObject.ran);
        assertContains(noObject.summary, 'There is no object called No_Such_Object__c');
    }
}
