/**
 * The Claude connector's preview_route tool (M16): where a record would go for
 * approval, which rule decides it and why, for the record as the user names it.
 * Writes nothing and submits nothing.
 *
 * Architecture section: 6.4 (preview), 7 (entry points, and its M16 note), 11.
 *
 * A facade over two existing actions: AMF_McpSupport.resolve() reads the
 * reference through Find Governed Record, and the assistant's Preview Approval
 * Route (M13) runs the engine's preview(). Nothing here decides anything: the
 * answer is that action's, sentence for sentence, with three additions an MCP
 * client needs -- the record's link, a resolution outcome for a reference that
 * is not exactly one record, and the signed token submit_for_approval requires
 * (AMF_McpSupport's class comment).
 *
 * Global, with every member global: Salesforce Hosted MCP Servers expose only a
 * global invocable, and read its schema from global members alone (technical
 * log M16.1).
 */
global with sharing class AMF_McpPreviewRoute {

    /** One record to preview. */
    global class Request {
        @InvocableVariable(
            label='Record'
            description='The record to preview, as the user names it: a number such as PR-00000047, a name, or a Salesforce Id.'
            required=true
        )
        global String record;
    }

    /** Where the record would go, and why. Nothing has been submitted. */
    global class Result {
        @InvocableVariable(
            label='Outcome'
            description='Routable: a rule matched and the record would enter Selected Process. Blocked_No_Match: no rule matched. Failed: the matrix could not decide. Refused: the record cannot be submitted. Ambiguous or Not_Found: the reference is not exactly one governed record.'
        )
        global String outcome;

        @InvocableVariable(
            label='Summary'
            description='The preview in plain English, complete and ready to give the user. It says that nothing has been submitted.'
        )
        global String summary;

        @InvocableVariable(label='Record ID' description='The record previewed, as an 18-character Id.')
        global String recordId;

        @InvocableVariable(label='Record' description='The record as a person names it, such as Purchase Request PR-00000047.')
        global String recordLabel;

        @InvocableVariable(label='Record URL' description='A link that opens the record in Salesforce.')
        global String recordUrl;

        @InvocableVariable(label='Selected Process' description='The approval process the record would enter. Empty unless Outcome is Routable.')
        global String selectedProcess;

        @InvocableVariable(label='Matched Rule' description='DeveloperName of the rule that matched. Empty when none did.')
        global String matchedRule;

        @InvocableVariable(label='Rule Version' description='Version of the matched rule.')
        global Integer ruleVersion;

        @InvocableVariable(label='Rule Priority' description='Priority of the matched rule. Rules are tried lowest number first.')
        global Integer rulePriority;

        @InvocableVariable(label='Rule Description' description='What the matched rule is for, as its administrator described it.')
        global String ruleDescription;

        @InvocableVariable(label='Condition' description='The matched rule\'s condition, exactly as written in the matrix.')
        global String condition;

        @InvocableVariable(
            label='Values Read'
            description='The field values the decision rested on, by field label, such as Risk Level = Medium and Amount = 60,000.'
        )
        global String valuesRead;

        @InvocableVariable(
            label='Can Submit'
            description='True when submit_for_approval may be offered for this preview, after the user confirms.'
        )
        global Boolean canSubmit;

        @InvocableVariable(
            label='Submit Token'
            description='Pass this unchanged to submit_for_approval, with Record ID and Selected Process, if the user confirms. Valid for 15 minutes, and only for this user, record, process, rule and the values this preview showed. Empty when the record cannot be submitted.'
        )
        global String submitToken;

        @InvocableVariable(
            label='Matches'
            description='When Outcome is Ambiguous: a numbered list of the matching records for the user to choose from.'
        )
        global String matches;
    }

    /**
     * @param requests One per record; an MCP call sends one.
     * @return One result per request, in the same order. Never throws for a record.
     */
    @InvocableMethod(
        label='Preview Route (Claude)'
        description='Shows which approval process the approval matrix would send a record to, which rule decides it and why, for a record named by number, name or Id. Writes nothing and submits nothing.'
        category='Approval Matrix'
    )
    global static List<Result> preview(List<Request> requests) {
        List<Result> results = new List<Result>();

        if (requests == null) {
            return results;
        }
        for (Request request : requests) {
            results.add(previewOne(request?.record));
        }
        return results;
    }

    private static Result previewOne(String reference) {
        Result result = new Result();

        AMF_McpSupport.Resolution resolution = AMF_McpSupport.resolve(reference);
        if (resolution.outcome != AMF_McpSupport.FOUND) {
            result.outcome = resolution.outcome;
            result.summary = resolution.message;
            result.matches = resolution.matches;
            result.canSubmit = false;
            return result;
        }

        AMF_AgentPreviewRoute.Request request = new AMF_AgentPreviewRoute.Request();
        request.recordId = String.valueOf(resolution.recordId);
        AMF_AgentPreviewRoute.Result previewed = AMF_AgentPreviewRoute.preview(
            new List<AMF_AgentPreviewRoute.Request>{ request }
        )[0];

        result.outcome = previewed.outcome;
        result.summary = previewed.summary;
        result.recordId = previewed.recordId;
        result.recordLabel = previewed.recordLabel;
        result.recordUrl = AMF_McpSupport.recordUrlOf(resolution.recordId);
        result.selectedProcess = previewed.selectedProcess;
        result.matchedRule = previewed.matchedRule;
        result.ruleVersion = previewed.ruleVersion;
        result.rulePriority = previewed.rulePriority;
        result.ruleDescription = previewed.ruleDescription;
        result.condition = previewed.condition;
        result.valuesRead = previewed.valuesRead;
        result.canSubmit = previewed.canSubmit == true;
        if (result.canSubmit) {
            AMF_McpSupport.ShownDecision shown = new AMF_McpSupport.ShownDecision();
            shown.processName = previewed.selectedProcess;
            shown.ruleName = previewed.matchedRule;
            shown.ruleVersion = previewed.ruleVersion;
            shown.valuesJson = previewed.evaluatedValuesJson;
            result.submitToken = AMF_McpSupport.tokenFor(resolution.recordId, shown);
        }
        return result;
    }
}
