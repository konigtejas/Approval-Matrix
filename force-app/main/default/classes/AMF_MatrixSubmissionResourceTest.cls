/**
 * POST /services/apexrest/approval-matrix/v1/submissions (M10): one result per
 * Id in the order sent, and a 400 for every way to send a bad body.
 *
 * Architecture section: 7 (and its M10 note), 10.
 *
 * The resource is called directly, with RestContext set up as the platform
 * would set it, over in-memory rules and AMF_StrategyStub through
 * AMF_SubmitForMatrixApproval's seam. That the endpoint answers a real call is
 * M10's manual gate step.
 */
@IsTest
private class AMF_MatrixSubmissionResourceTest {

    /** The resource over an in-memory catch-all and the stub. */
    private static AMF_StrategyStub overCatchAll() {
        AMF_StrategyStub strategy = new AMF_StrategyStub();
        AMF_SubmitForMatrixApproval.entryPointOverride = new AMF_ApprovalMatrixService(
            new AMF_RuleBuilder.Stub(
                new List<AMF_RuleDefinition>{
                    new AMF_RuleBuilder()
                        .named('PR_Catch_All')
                        .withPriority(9999)
                        .withExpression('TRUE')
                        .routingTo('PR_Two_Level_Mgmt')
                        .atVersion(1)
                        .build()
                }
            ),
            strategy
        );
        return strategy;
    }

    private static RestResponse post(String body) {
        RestRequest request = new RestRequest();
        request.requestURI = '/services/apexrest/approval-matrix/v1/submissions';
        request.httpMethod = 'POST';
        if (body != null) {
            request.requestBody = Blob.valueOf(body);
        }
        RestContext.request = request;
        RestContext.response = new RestResponse();

        AMF_MatrixSubmissionResource.submit();
        return RestContext.response;
    }

    private static Map<String, Object> bodyOf(RestResponse response) {
        return (Map<String, Object>) JSON.deserializeUntyped(response.responseBody.toString());
    }

    private static Purchase_Request__c governedRecord() {
        return new Purchase_Request__c(Amount__c = 500, Region__c = 'EMEA', Risk_Level__c = 'Low');
    }

    @IsTest
    static void answersEveryIdInTheOrderSent() {
        Purchase_Request__c first = governedRecord();
        Purchase_Request__c second = governedRecord();
        insert new List<Purchase_Request__c>{ first, second };
        Account account = new Account(Name = 'Not governed');
        insert account;

        AMF_StrategyStub strategy = overCatchAll();

        // The first Id goes in its 15-character form, as some integrations send it.
        String body = JSON.serialize(
            new Map<String, Object>{
                'recordIds' => new List<String>{
                    String.valueOf(second.Id),
                    String.valueOf(account.Id),
                    String.valueOf(first.Id).left(15)
                }
            }
        );

        Test.startTest();
        RestResponse response = post(body);
        Test.stopTest();

        Assert.areEqual(200, response.statusCode);
        Assert.areEqual('application/json', response.headers.get('Content-Type'));

        List<Object> results = (List<Object>) bodyOf(response).get('results');
        Assert.areEqual(3, results.size(), 'One result per Id');

        Map<String, Object> secondResult = (Map<String, Object>) results[0];
        Assert.areEqual(String.valueOf(second.Id), secondResult.get('recordId'), 'In the order sent');
        Assert.areEqual(true, secondResult.get('submitted'));
        Assert.areEqual('Submitted', secondResult.get('outcome'));
        Assert.areEqual('PR_Catch_All', secondResult.get('matchedRule'));
        Assert.areEqual('PR_Two_Level_Mgmt', secondResult.get('selectedProcess'));
        Assert.isNotNull(secondResult.get('decisionLogId'));
        Assert.isNotNull(secondResult.get('executionRefId'));

        Map<String, Object> accountResult = (Map<String, Object>) results[1];
        Assert.areEqual('Refused', accountResult.get('outcome'), 'Answered in its own result, not as an error');
        Assert.areEqual(false, accountResult.get('submitted'));
        Assert.isTrue(
            ((String) accountResult.get('message')).contains('Matrix_Submission__c'),
            'Got: ' + accountResult.get('message')
        );

        Map<String, Object> firstResult = (Map<String, Object>) results[2];
        Assert.areEqual(String.valueOf(first.Id), firstResult.get('recordId'), 'A 15-character Id is the same record');
        Assert.areEqual(true, firstResult.get('submitted'));

        Assert.areEqual(2, strategy.received.size());
    }

    @IsTest
    static void aBadBodyIsA400WithAMessageAndSubmitsNothing() {
        Purchase_Request__c record = governedRecord();
        insert record;
        String recordId = String.valueOf(record.Id);

        AMF_StrategyStub strategy = overCatchAll();

        List<String> tooMany = new List<String>();
        for (Integer i = 0; i <= AMF_MatrixSubmissionResource.MAX_RECORDS; i++) {
            tooMany.add(recordId);
        }

        Map<String, String> expectedByBody = new Map<String, String>{
            '' => 'is empty',
            '   ' => 'is empty',
            '{"recordIds": [' => 'not valid JSON',
            '["' + recordId + '"]' => 'no "recordIds" array',
            '{"ids": ["' + recordId + '"]}' => 'no "recordIds" array',
            '{"recordIds": "' + recordId + '"}' => 'no "recordIds" array',
            '{"recordIds": []}' => 'is empty',
            '{"recordIds": ["not-an-id"]}' => 'not a record Id',
            '{"recordIds": [42]}' => 'not a record Id',
            '{"recordIds": [null]}' => 'not a record Id',
            JSON.serialize(new Map<String, Object>{ 'recordIds' => tooMany }) => 'at most 200'
        };

        Test.startTest();
        for (String body : expectedByBody.keySet()) {
            RestResponse response = post(body);
            String message = (String) bodyOf(response).get('message');

            Assert.areEqual(400, response.statusCode, 'Body: ' + body.abbreviate(80));
            Assert.isTrue(
                message.contains(expectedByBody.get(body)),
                'Body: ' + body.abbreviate(80) + ' -- got: ' + message
            );
        }

        RestResponse noBody = post(null);
        Assert.areEqual(400, noBody.statusCode, 'No body at all');
        Assert.isTrue(((String) bodyOf(noBody).get('message')).contains('is empty'));
        Test.stopTest();

        Assert.areEqual(0, strategy.calls, 'A refused request submits nothing');
        Assert.areEqual(0, [SELECT COUNT() FROM Approval_Decision_Log__c], 'And logs nothing');
    }
}
