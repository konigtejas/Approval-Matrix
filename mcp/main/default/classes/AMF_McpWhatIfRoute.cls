/**
 * The Claude connector's what_if_route tool (M16): where a record would go if
 * some of its values were different, against where it goes today. Changes
 * nothing, writes nothing and can never be submitted.
 *
 * Architecture section: 6.4 (previewWith, and its M14 note), 7 (its M16 note).
 *
 * A facade over the assistant's What-If Approval Route (M14), for the record as
 * the user names it. It deliberately returns no submit token: a what-if's
 * values are not the record's, so a submission always starts from
 * preview_route's preview of the record as it is.
 */
global with sharing class AMF_McpWhatIfRoute {

    /** One record, and the values to try on it. */
    global class Request {
        @InvocableVariable(
            label='Record'
            description='The record to try the values on, as the user names it: a number such as PR-00000047, a name, or an Id.'
            required=true
        )
        global String record;

        @InvocableVariable(
            label='Changes'
            description='The values to try instead of the record\'s own, as "Field = value" separated by semicolons, such as "Amount = 120000; Region = APAC". Fields may be named by their label.'
            required=true
        )
        global String changes;
    }

    /** The route with the changed values, against today's. Nothing changed. */
    global class Result {
        @InvocableVariable(
            label='Outcome'
            description='Routable, Blocked_No_Match, Failed or Refused, for the changed values; or Ambiguous or Not_Found when the reference is not exactly one governed record.'
        )
        global String outcome;

        @InvocableVariable(label='Summary' description='The comparison in plain English, complete and ready to give the user. It says nothing was changed.')
        global String summary;

        @InvocableVariable(label='Record ID' description='The record tried, as an 18-character Id.')
        global String recordId;

        @InvocableVariable(label='Record' description='The record as a person names it.')
        global String recordLabel;

        @InvocableVariable(label='Record URL' description='A link that opens the record in Salesforce.')
        global String recordUrl;

        @InvocableVariable(label='Route Changed' description='True when the changed values would send the record somewhere other than today.')
        global Boolean routeChanged;

        @InvocableVariable(label='Selected Process' description='The approval process the record would enter with the changed values.')
        global String selectedProcess;

        @InvocableVariable(label='Matched Rule' description='The rule that would decide the route with the changed values.')
        global String matchedRule;

        @InvocableVariable(label='Current Process' description='The approval process the record would enter today, with its own values.')
        global String currentProcess;

        @InvocableVariable(label='Current Rule' description='The rule that decides the route today.')
        global String currentRule;

        @InvocableVariable(label='Matches' description='When Outcome is Ambiguous: a numbered list of the matching records to choose from.')
        global String matches;
    }

    /**
     * @param requests One per record; an MCP call sends one.
     * @return One result per request, in the same order. Never throws for a record.
     */
    @InvocableMethod(
        label='What-If Route (Claude)'
        description='Shows where a record would go for approval if some of its values were different, against where it goes today. Changes nothing and submits nothing.'
        category='Approval Matrix'
    )
    global static List<Result> whatIf(List<Request> requests) {
        List<Result> results = new List<Result>();

        if (requests == null) {
            return results;
        }
        for (Request request : requests) {
            results.add(whatIfOne(request));
        }
        return results;
    }

    private static Result whatIfOne(Request request) {
        Result result = new Result();

        AMF_McpSupport.Resolution resolution = AMF_McpSupport.resolve(request?.record);
        if (resolution.outcome != AMF_McpSupport.FOUND) {
            result.outcome = resolution.outcome;
            result.summary = resolution.message;
            result.matches = resolution.matches;
            result.routeChanged = false;
            return result;
        }

        AMF_AgentWhatIfRoute.Request tried = new AMF_AgentWhatIfRoute.Request();
        tried.recordId = String.valueOf(resolution.recordId);
        tried.changes = request.changes;
        AMF_AgentWhatIfRoute.Result answer = AMF_AgentWhatIfRoute.whatIf(new List<AMF_AgentWhatIfRoute.Request>{ tried })[0];

        result.outcome = answer.outcome;
        result.summary = answer.summary;
        result.recordId = answer.recordId;
        result.recordLabel = answer.recordLabel;
        result.recordUrl = AMF_McpSupport.recordUrlOf(resolution.recordId);
        result.routeChanged = answer.routeChanged == true;
        result.selectedProcess = answer.selectedProcess;
        result.matchedRule = answer.matchedRule;
        result.currentProcess = answer.currentProcess;
        result.currentRule = answer.currentRule;
        return result;
    }
}
