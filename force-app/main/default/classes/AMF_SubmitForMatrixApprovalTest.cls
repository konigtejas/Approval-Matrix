/**
 * The Submit for Matrix Approval action (M10): one result per request, in the
 * order received, carrying what a Flow needs to act on each record.
 *
 * Architecture section: 7 (and its M10 note), 10.
 *
 * The action runs over in-memory rules and AMF_StrategyStub through its
 * entryPointOverride seam, so nothing here depends on an org CMDT row or runs a
 * real approval. That the platform's invocable framework calls it is M10's
 * manual gate step; what the engine decides is AMF_ApprovalMatrixServiceTest's.
 */
@IsTest
private class AMF_SubmitForMatrixApprovalTest {

    private static final String THREE_LEVEL = 'PR_Three_Level_Finance';

    /** The action over one in-memory rule -- high risk to the three-level chain -- and the stub. */
    private static AMF_StrategyStub overHighRiskRule() {
        AMF_StrategyStub strategy = new AMF_StrategyStub();
        AMF_SubmitForMatrixApproval.entryPointOverride = new AMF_ApprovalMatrixService(
            new AMF_RuleBuilder.Stub(
                new List<AMF_RuleDefinition>{
                    new AMF_RuleBuilder()
                        .named('PR_High_Risk')
                        .withPriority(20)
                        .withExpression('Risk_Level__c == \'High\'')
                        .routingTo(THREE_LEVEL)
                        .atVersion(2)
                        .build()
                }
            ),
            strategy
        );
        return strategy;
    }

    private static AMF_SubmitForMatrixApproval.Request requestFor(Id recordId) {
        AMF_SubmitForMatrixApproval.Request request = new AMF_SubmitForMatrixApproval.Request();
        request.recordId = recordId;
        return request;
    }

    private static Purchase_Request__c record(String risk) {
        return new Purchase_Request__c(Amount__c = 500, Region__c = 'EMEA', Risk_Level__c = risk);
    }

    @IsTest
    static void eachRequestGetsItsOwnResultInTheOrderReceived() {
        Purchase_Request__c routed = record('High');
        Purchase_Request__c blocked = record('Low');
        insert new List<Purchase_Request__c>{ routed, blocked };

        AMF_StrategyStub strategy = overHighRiskRule();

        Test.startTest();
        List<AMF_SubmitForMatrixApproval.Result> results = AMF_SubmitForMatrixApproval.submit(
            new List<AMF_SubmitForMatrixApproval.Request>{
                requestFor(blocked.Id),
                requestFor(routed.Id),
                requestFor(null)
            }
        );
        Test.stopTest();

        Assert.areEqual(3, results.size(), 'One result per request');

        AMF_SubmitForMatrixApproval.Result noMatch = results[0];
        Assert.areEqual(blocked.Id, noMatch.recordId);
        Assert.isFalse(noMatch.submitted);
        Assert.areEqual('Blocked_No_Match', noMatch.outcome);
        Assert.isTrue(noMatch.message.contains('catch-all'), 'Got: ' + noMatch.message);
        Assert.isNotNull(noMatch.decisionLogId, 'The row that explains the block');
        Assert.isNull(noMatch.executionRefId);

        AMF_SubmitForMatrixApproval.Result submitted = results[1];
        Assert.areEqual(routed.Id, submitted.recordId);
        Assert.isTrue(submitted.submitted);
        Assert.areEqual('Submitted', submitted.outcome);
        Assert.isNull(submitted.message);
        Assert.areEqual('PR_High_Risk', submitted.matchedRule);
        Assert.areEqual(2, submitted.ruleVersion);
        Assert.areEqual(THREE_LEVEL, submitted.selectedProcess);
        Assert.isNotNull(submitted.executionRefId);
        Assert.areEqual(
            submitted.executionRefId,
            [SELECT Execution_Ref_Id__c FROM Approval_Decision_Log__c WHERE Id = :submitted.decisionLogId]
            .Execution_Ref_Id__c,
            'The result points at the row that records this submission'
        );

        AMF_SubmitForMatrixApproval.Result missing = results[2];
        Assert.isNull(missing.recordId);
        Assert.isFalse(missing.submitted);
        Assert.areEqual('Refused', missing.outcome, 'A request with no record is answered, not thrown');
        Assert.isNull(missing.decisionLogId);

        Assert.areEqual(1, strategy.calls);
    }

    @IsTest
    static void aRecordThePlatformRefusesGetsItsOwnResultAndTheOtherStillGoes() {
        Purchase_Request__c refused = record('High');
        Purchase_Request__c accepted = record('High');
        insert new List<Purchase_Request__c>{ refused, accepted };

        AMF_StrategyStub strategy = overHighRiskRule();
        strategy.refuse.add(refused.Id);

        Test.startTest();
        List<AMF_SubmitForMatrixApproval.Result> results = AMF_SubmitForMatrixApproval.submit(
            new List<AMF_SubmitForMatrixApproval.Request>{ requestFor(refused.Id), requestFor(accepted.Id) }
        );
        Test.stopTest();

        Assert.areEqual('Failed', results[0].outcome);
        Assert.isFalse(results[0].submitted);
        Assert.isTrue(results[0].message.contains(strategy.refusalMessage), 'Got: ' + results[0].message);
        Assert.isNotNull(results[0].decisionLogId, 'The matrix decided, so the refusal is logged');
        Assert.isNull(results[0].executionRefId);

        Assert.isTrue(results[1].submitted, 'One refusal does not fail the interview: ' + results[1].message);
    }

    @IsTest
    static void theProductionWiringAnswersAnUngovernedObjectWithoutThrowing() {
        // No override: the engine as Flow gets it. An Account has no guard field,
        // so it is refused before any rule is read -- no org CMDT row is evaluated.
        Account account = new Account(Name = 'Not governed');
        insert account;

        Test.startTest();
        List<AMF_SubmitForMatrixApproval.Result> results = AMF_SubmitForMatrixApproval.submit(
            new List<AMF_SubmitForMatrixApproval.Request>{ requestFor(account.Id) }
        );
        Test.stopTest();

        Assert.areEqual(1, results.size());
        Assert.areEqual('Refused', results[0].outcome);
        Assert.isTrue(results[0].message.contains('Matrix_Submission__c'), 'Got: ' + results[0].message);
    }

    @IsTest
    static void noRequestsMeansNoResults() {
        overHighRiskRule();

        Assert.areEqual(
            0,
            AMF_SubmitForMatrixApproval.submit(new List<AMF_SubmitForMatrixApproval.Request>()).size()
        );
        Assert.areEqual(0, AMF_SubmitForMatrixApproval.submit(null).size());
    }
}
