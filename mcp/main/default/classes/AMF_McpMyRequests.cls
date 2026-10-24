/**
 * The Claude connector's list_my_requests tool (M16): where the user's own
 * approval requests stand, newest attempt per record, those still waiting first.
 *
 * Architecture section: 7 (its M14 and M16 notes), 11.
 *
 * A facade over the assistant's My Approval Requests (M14): the user's own
 * decision log rows of the last 90 days, read in user mode, at most ten listed.
 * Each listed record's number works as the record for every other tool.
 */
global with sharing class AMF_McpMyRequests {

    /** What to list. Every field is optional. */
    global class Request {
        @InvocableVariable(label='Pending Only' description='Optional: true to list only requests still waiting for approval.')
        global Boolean pendingOnly;
    }

    /** The user's requests. */
    global class Result {
        @InvocableVariable(label='Count' description='How many governed records the user submitted in the last 90 days.')
        global Integer count;

        @InvocableVariable(
            label='Requests'
            description='A numbered list, still-waiting first: each record, its process, where its approval stands, who it waits on and since when.'
        )
        global String requests;

        @InvocableVariable(label='Message' description='What was found, in plain English, ready to give the user.')
        global String message;
    }

    /**
     * @param requests One per listing; an MCP call sends one.
     * @return One result per request, in the same order.
     */
    @InvocableMethod(
        label='My Requests (Claude)'
        description='Lists where the user\'s own approval requests of the last 90 days stand, those still waiting first, with who each waits on.'
        category='Approval Matrix'
    )
    global static List<Result> listRequests(List<Request> requests) {
        List<Result> results = new List<Result>();

        if (requests == null) {
            return results;
        }

        List<AMF_AgentMyRequests.Request> asked = new List<AMF_AgentMyRequests.Request>();
        for (Request request : requests) {
            AMF_AgentMyRequests.Request listing = new AMF_AgentMyRequests.Request();
            listing.pendingOnly = request?.pendingOnly;
            asked.add(listing);
        }

        for (AMF_AgentMyRequests.Result listed : AMF_AgentMyRequests.listRequests(asked)) {
            Result result = new Result();
            result.count = listed.count;
            result.requests = listed.requests;
            result.message = listed.message;
            results.add(result);
        }
        return results;
    }
}
