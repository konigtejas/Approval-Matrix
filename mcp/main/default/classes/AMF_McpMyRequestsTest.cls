/**
 * The Claude connector's list_my_requests tool (M16): the assistant's My
 * Approval Requests, unchanged.
 *
 * Architecture section: 7 (its M14 and M16 notes), 10.
 *
 * What is listed, and how, is AMF_AgentMyRequestsTest's subject. Pinned here is
 * that the facade passes the filter through and the answer back.
 */
@IsTest
private class AMF_McpMyRequestsTest {

    private static AMF_McpMyRequests.Result listOne(Boolean pendingOnly) {
        AMF_McpMyRequests.Request request = new AMF_McpMyRequests.Request();
        request.pendingOnly = pendingOnly;
        return AMF_McpMyRequests.listRequests(new List<AMF_McpMyRequests.Request>{ request })[0];
    }

    @IsTest
    static void listsTheUsersOwnRequestsAndHonoursPendingOnly() {
        Purchase_Request__c record = new Purchase_Request__c(Amount__c = 5000, Region__c = 'EMEA', Risk_Level__c = 'Low');
        insert record;
        insert new Approval_Decision_Log__c(
            Record_Id__c = String.valueOf(record.Id),
            Object_API_Name__c = 'Purchase_Request__c',
            Outcome__c = 'Blocked_No_Match',
            Submitted_By__c = UserInfo.getUserId(),
            Submitted_At__c = Datetime.now()
        );
        String prNumber = [SELECT Name FROM Purchase_Request__c WHERE Id = :record.Id].Name;

        AMF_McpMyRequests.Result all = listOne(null);
        AMF_McpMyRequests.Result waiting = listOne(true);

        Assert.areEqual(1, all.count);
        Assert.isTrue(all.requests.contains(prNumber), '' + all.requests);
        Assert.isNotNull(all.message);
        Assert.areEqual(0, waiting.count, 'A blocked attempt is not waiting for anyone');
        Assert.isNotNull(waiting.message);
        Assert.areEqual(0, AMF_McpMyRequests.listRequests(null).size());
    }
}
