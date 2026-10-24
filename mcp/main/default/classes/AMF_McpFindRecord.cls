/**
 * The Claude connector's find_record tool (M16): finds the records the approval
 * matrix governs by number, name or Id, among those the user can see.
 *
 * Architecture section: 7 (entry points, and its M13 and M16 notes), 11.
 *
 * A facade over the assistant's Find Governed Record (M13), with a link for each
 * single match. Every other tool resolves its own record the same way, so this
 * one is for when the user is looking for a record rather than asking about one.
 */
global with sharing class AMF_McpFindRecord {

    /** What to look for. */
    global class Request {
        @InvocableVariable(
            label='Search Text'
            description='The record\'s number, name or Id as the user gave it, such as PR-00000045, a request name or an opportunity name.'
            required=true
        )
        global String searchText;
    }

    /** What was found. */
    global class Result {
        @InvocableVariable(label='Outcome' description='Found (exactly one), Ambiguous (several) or Not_Found.')
        global String outcome;

        @InvocableVariable(label='Message' description='What was found, in plain English, ready to give the user.')
        global String message;

        @InvocableVariable(label='Match Count' description='How many records matched, up to six.')
        global Integer matchCount;

        @InvocableVariable(label='Record ID' description='The matching record\'s Id, when exactly one matched.')
        global String recordId;

        @InvocableVariable(label='Record' description='The matching record as a person names it, when exactly one matched.')
        global String recordLabel;

        @InvocableVariable(label='Record URL' description='A link that opens the matching record, when exactly one matched.')
        global String recordUrl;

        @InvocableVariable(label='Matches' description='When several matched: a numbered list of them, each with its Id, for the user to choose from.')
        global String matches;
    }

    /**
     * @param requests One per search; an MCP call sends one.
     * @return One result per request, in the same order.
     */
    @InvocableMethod(
        label='Find Record (Claude)'
        description='Finds records the approval matrix governs, such as Purchase Requests and Opportunities, by number, name or Id, among the records the user can see.'
        category='Approval Matrix'
    )
    global static List<Result> find(List<Request> requests) {
        List<Result> results = new List<Result>();

        if (requests == null) {
            return results;
        }

        List<AMF_AgentFindRecord.Request> searches = new List<AMF_AgentFindRecord.Request>();
        for (Request request : requests) {
            AMF_AgentFindRecord.Request search = new AMF_AgentFindRecord.Request();
            search.searchText = request?.searchText;
            searches.add(search);
        }

        for (AMF_AgentFindRecord.Result found : AMF_AgentFindRecord.find(searches)) {
            Result result = new Result();
            Id recordId = AMF_AgentSupport.idOf(found.recordId);
            result.matchCount = found.matchCount;
            result.message = found.message;
            result.matches = found.matches;
            result.recordId = found.recordId;
            result.recordLabel = found.recordLabel;
            result.recordUrl = AMF_McpSupport.recordUrlOf(recordId);
            result.outcome = found.matchCount == 1 && recordId != null
                ? AMF_McpSupport.FOUND
                : (found.matchCount != null && found.matchCount > 1 ? AMF_McpSupport.AMBIGUOUS : AMF_McpSupport.NOT_FOUND);
            results.add(result);
        }
        return results;
    }
}
