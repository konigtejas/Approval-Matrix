/**
 * Guard-clause and contract coverage for the Classic strategy.
 *
 * Architecture section: 6.2, 10.
 *
 * The real Approval.process() call is deliberately NOT exercised here -- that is
 * AMF_SubmissionIntegrationTest's single job, per 10's "one thin integration
 * test". What this class pins is everything around the platform call: the
 * contract for empty input, and the refusals that must happen before a request
 * is ever handed to the platform.
 */
@IsTest
private class AMF_ClassicProcessStrategyTest {

    @IsTest
    static void emptyInputSubmitsNothingAndReturnsNothing() {
        AMF_ClassicProcessStrategy strategy = new AMF_ClassicProcessStrategy();

        Assert.areEqual(0, strategy.submit(null).size(), 'Null in, empty out -- not an exception');
        Assert.areEqual(
            0,
            strategy.submit(new List<AMF_SubmitRequest>()).size(),
            'Empty in, empty out'
        );
    }

    @IsTest
    static void aRequestWithNoRecordIdIsRefusedBeforeThePlatformIsCalled() {
        try {
            new AMF_ClassicProcessStrategy()
                .submit(new List<AMF_SubmitRequest>{ new AMF_SubmitRequest(null, 'PR_Two_Level_Mgmt') });
            Assert.fail('A request with no record Id must be refused');
        } catch (AMF_SubmissionException e) {
            Assert.isTrue(e.getMessage().contains('without a record Id'), 'Got: ' + e.getMessage());
        }
    }

    @IsTest
    static void aRequestNamingNoProcessIsRefusedBeforeThePlatformIsCalled() {
        Purchase_Request__c record = new Purchase_Request__c(
            Amount__c = 500,
            Region__c = 'EMEA',
            Risk_Level__c = 'Low'
        );
        insert record;

        for (String processApiName : new List<String>{ null, '', '   ' }) {
            try {
                new AMF_ClassicProcessStrategy()
                    .submit(
                        new List<AMF_SubmitRequest>{ new AMF_SubmitRequest(record.Id, processApiName) }
                    );
                Assert.fail('Expected a refusal for process name: ' + processApiName);
            } catch (AMF_SubmissionException e) {
                Assert.isTrue(
                    e.getMessage().contains('No approval process was named'),
                    'Got: ' + e.getMessage()
                );
            }
        }
    }

    @IsTest
    static void theRequestDtosCarryWhatTheyWereGiven() {
        // Small, but these two types are the whole of 6.2's contract and the seam
        // a Flow strategy will arrive through.
        Purchase_Request__c record = new Purchase_Request__c(
            Amount__c = 500,
            Region__c = 'EMEA',
            Risk_Level__c = 'Low'
        );
        insert record;

        AMF_SubmitRequest request = new AMF_SubmitRequest(record.Id, 'PR_Three_Level_Finance');
        Assert.areEqual(record.Id, request.recordId);
        Assert.areEqual('PR_Three_Level_Finance', request.processApiName);

        AMF_SubmitResult result = new AMF_SubmitResult(record.Id, '04g000000000001AAA');
        Assert.areEqual(record.Id, result.recordId);
        Assert.areEqual('04g000000000001AAA', result.executionRefId);
    }
}
