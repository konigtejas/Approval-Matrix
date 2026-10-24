/**
 * The Claude connector's list_my_approvals tool (M16): what is waiting for the
 * user to approve, oldest first.
 *
 * Architecture section: 8 (its M14 note: who an approval is waiting on), 7 (its
 * M14 and M16 notes), 11.
 *
 * A facade over the assistant's My Pending Approvals (M14): pending work on
 * governed records that AMF_ApproverScope says is the user's -- directly,
 * through a queue or group, or as delegated approver -- on records they can
 * read, at most ten listed. The user approves or rejects in Salesforce.
 */
global with sharing class AMF_McpMyApprovals {

    /** What to list. Every field is optional. */
    global class Request {
        @InvocableVariable(
            label='Object'
            description='Optional: list only one kind of record, such as Purchase Request or Opportunity. Leave empty for every kind.'
        )
        global String objectName;
    }

    /** What is waiting on the user. */
    global class Result {
        @InvocableVariable(label='Count' description='How many governed records are waiting on the user for approval.')
        global Integer count;

        @InvocableVariable(
            label='Approvals'
            description='A numbered list, oldest first: each record, its process and step, who submitted it and since when.'
        )
        global String approvals;

        @InvocableVariable(label='Message' description='What is waiting, in plain English, ready to give the user.')
        global String message;
    }

    /**
     * @param requests One per listing; an MCP call sends one.
     * @return One result per request, in the same order.
     */
    @InvocableMethod(
        label='My Approvals (Claude)'
        description='Lists the approvals waiting on the user, directly, through a queue or group, or as delegated approver, oldest first.'
        category='Approval Matrix'
    )
    global static List<Result> listApprovals(List<Request> requests) {
        List<Result> results = new List<Result>();

        if (requests == null) {
            return results;
        }

        List<AMF_AgentMyApprovals.Request> asked = new List<AMF_AgentMyApprovals.Request>();
        for (Request request : requests) {
            AMF_AgentMyApprovals.Request listing = new AMF_AgentMyApprovals.Request();
            listing.objectName = request?.objectName;
            asked.add(listing);
        }

        for (AMF_AgentMyApprovals.Result listed : AMF_AgentMyApprovals.listApprovals(asked)) {
            Result result = new Result();
            result.count = listed.count;
            result.approvals = listed.approvals;
            result.message = listed.message;
            results.add(result);
        }
        return results;
    }
}
