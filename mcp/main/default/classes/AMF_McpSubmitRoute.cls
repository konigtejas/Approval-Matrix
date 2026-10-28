/**
 * The Claude connector's submit_for_approval tool (M16): submits a record its
 * user has just previewed through preview_route, once they have confirmed the
 * route they were shown.
 *
 * Architecture section: 6.1 (submitEach), 6.4 (a route that changed after its
 * preview), 7 (entry points, and its M16 note), 11.
 *
 * THREE CHECKS, ALL IN APEX, BEFORE ANYTHING IS WRITTEN:
 *   1. The token: AMF_McpSupport.checkToken() accepts only a signature
 *      preview_route made for this user and this record within 15 minutes, and
 *      the call's Expected Process has to be the process that signature names.
 *      A model that never previewed, or previewed another record or another
 *      route, has no such token, and nothing is submitted.
 *   2. The decision now: the engine previews the record again. If the process,
 *      the rule or the values differ from what the token signed, nothing is
 *      submitted and the answer says what would happen instead. The same
 *      process over different values was not what the user confirmed. This is
 *      stricter than the assistant's Submit Previewed Route, which submits and
 *      says the route changed (M13).
 *   3. Whether the record can be submitted at all, which is the engine's own
 *      refusal (already pending, unreadable, ungoverned).
 *
 * Then the assistant's Submit Previewed Route submits it, through
 * AMF_SubmitForMatrixApproval.submitEach -- M10's per-record path -- so the
 * decision log row is exactly the one a Flow, REST or the agent would write.
 *
 * The user's half of "preview, confirm, submit" (7) is the client's: the tool
 * is annotated destructive, so Claude asks before calling it, and the call's
 * arguments name the record and the process.
 */
global with sharing class AMF_McpSubmitRoute {

    private static final String REFUSED = 'Refused';

    /** One previewed record to submit. */
    global class Request {
        @InvocableVariable(
            label='Record ID'
            description='The Record ID that preview_route returned for the record the user confirmed.'
            required=true
        )
        global String recordId;

        @InvocableVariable(
            label='Expected Process'
            description='The Selected Process that preview_route showed and the user confirmed. Empty when the preview showed a block.'
        )
        global String expectedProcess;

        @InvocableVariable(
            label='Submit Token'
            description='The Submit Token that preview_route returned with that preview, unchanged.'
            required=true
        )
        global String submitToken;
    }

    /** What the submission did. */
    global class Result {
        @InvocableVariable(label='Submitted' description='True only when the record entered an approval process.')
        global Boolean submitted;

        @InvocableVariable(
            label='Outcome'
            description='Submitted, Blocked_No_Match, Failed or Refused. Refused means nothing was submitted or recorded.'
        )
        global String outcome;

        @InvocableVariable(label='Summary' description='What happened, in plain English, complete and ready to give the user.')
        global String summary;

        @InvocableVariable(label='Record ID' description='The record this result is about.')
        global String recordId;

        @InvocableVariable(label='Record' description='The record as a person names it.')
        global String recordLabel;

        @InvocableVariable(label='Record URL' description='A link that opens the record in Salesforce.')
        global String recordUrl;

        @InvocableVariable(label='Selected Process' description='The approval process the record entered, or would now enter.')
        global String selectedProcess;

        @InvocableVariable(label='Matched Rule' description='The rule that decided the route.')
        global String matchedRule;

        @InvocableVariable(label='Rule Version' description='Version of the matched rule.')
        global Integer ruleVersion;

        @InvocableVariable(
            label='Route Changed'
            description='True when the record would now go somewhere other than Expected Process, so nothing was submitted.'
        )
        global Boolean routeChanged;

        @InvocableVariable(label='Decision Log' description='The decision log row that records this attempt, such as ADL-00000031. Empty when Refused.')
        global String decisionLogName;

        @InvocableVariable(label='Waiting On' description='Who the approval is waiting on now. Empty unless Submitted.')
        global String waitingOn;
    }

    /**
     * @param requests One per record; an MCP call sends one.
     * @return One result per request, in the same order.
     * @throws AMF_SubmissionException Only when the strategy fails as a whole, as for the M10 action.
     */
    @InvocableMethod(
        label='Submit Previewed Route (Claude)'
        description='Submits a record that preview_route has just previewed, to the process the user confirmed, with the token that preview returned. Refuses, and writes nothing, without a valid token or when the route has changed since.'
        category='Approval Matrix'
    )
    global static List<Result> submit(List<Request> requests) {
        List<Result> results = new List<Result>();

        if (requests == null) {
            return results;
        }
        for (Request request : requests) {
            results.add(submitOne(request));
        }
        return results;
    }

    private static Result submitOne(Request request) {
        Id recordId = AMF_AgentSupport.idOf(request?.recordId);
        String expected = request?.expectedProcess == null ? '' : request.expectedProcess.trim();

        if (recordId == null) {
            return refused(null, 'This record cannot be submitted: ' + AMF_AgentSupport.notAnId(request?.recordId));
        }

        AMF_McpSupport.TokenCheck check = AMF_McpSupport.checkToken(request.submitToken, recordId);
        if (check.problem != null) {
            return refused(recordId, check.problem);
        }
        String signedProcess = check.shown.processName == null ? '' : check.shown.processName;
        if (signedProcess != expected) {
            return refused(recordId, AMF_McpSupport.NOT_PREVIEWED);
        }

        AMF_AgentPreviewRoute.Request previewRequest = new AMF_AgentPreviewRoute.Request();
        previewRequest.recordId = String.valueOf(recordId);
        AMF_AgentPreviewRoute.Result now = AMF_AgentPreviewRoute.preview(
            new List<AMF_AgentPreviewRoute.Request>{ previewRequest }
        )[0];

        if (now.canSubmit != true) {
            return refused(recordId, now.summary);
        }

        if (!AMF_McpSupport.sameDecision(check.shown, now.selectedProcess, now.matchedRule, now.ruleVersion, now.evaluatedValuesJson)) {
            Result changed = refused(recordId, routeChangedSummary(now, expected));
            changed.routeChanged = true;
            changed.selectedProcess = now.selectedProcess;
            changed.matchedRule = now.matchedRule;
            changed.ruleVersion = now.ruleVersion;
            return changed;
        }

        AMF_AgentSubmitRoute.Request submitRequest = new AMF_AgentSubmitRoute.Request();
        submitRequest.recordId = String.valueOf(recordId);
        submitRequest.expectedProcess = expected;
        AMF_AgentSubmitRoute.Result done = AMF_AgentSubmitRoute.submit(
            new List<AMF_AgentSubmitRoute.Request>{ submitRequest }
        )[0];

        Result result = new Result();
        result.submitted = done.submitted == true;
        result.outcome = done.outcome;
        result.summary = done.summary;
        result.recordId = done.recordId;
        result.recordLabel = AMF_DecisionExplainer.recordLabelOf(recordId);
        result.recordUrl = AMF_McpSupport.recordUrlOf(recordId);
        result.selectedProcess = done.selectedProcess;
        result.matchedRule = done.matchedRule;
        result.ruleVersion = done.ruleVersion;
        result.routeChanged = done.routeChanged == true;
        result.decisionLogName = done.decisionLogName;
        result.waitingOn = done.waitingOn;
        return result;
    }

    private static String routeChangedSummary(AMF_AgentPreviewRoute.Result now, String expected) {
        String nowProcess = now.selectedProcess == null ? '' : now.selectedProcess;
        if (nowProcess == expected) {
            String still = String.isBlank(nowProcess) ? 'would still not enter an approval process' : 'would still go to approval process ' + nowProcess + ' under rule ' + now.matchedRule;
            return 'Nothing was submitted. ' +
                now.recordLabel +
                ' ' +
                still +
                ', but the rule or the values are not what the preview showed. ' +
                'The record or the approval matrix changed after the preview. ' +
                'Preview it again and submit once the user confirms the new route.';
        }

        // The two are never both blank: the caller found them different.
        String nowRoute = String.isBlank(now.selectedProcess)
            ? 'would now be blocked or fail instead of going to ' + expected
            : 'would now go to approval process ' + now.selectedProcess + ' under rule ' + now.matchedRule +
              (String.isBlank(expected) ? ' instead of being blocked' : ', not ' + expected);
        return 'Nothing was submitted. ' +
            now.recordLabel +
            ' ' +
            nowRoute +
            ', because the record or the approval matrix changed after the preview. ' +
            'Preview it again and submit once the user confirms the new route.';
    }

    private static Result refused(Id recordId, String summary) {
        Result result = new Result();
        result.submitted = false;
        result.outcome = REFUSED;
        result.summary = summary;
        result.recordId = recordId == null ? null : String.valueOf(recordId);
        result.recordLabel = recordId == null ? null : AMF_DecisionExplainer.recordLabelOf(recordId);
        result.recordUrl = AMF_McpSupport.recordUrlOf(recordId);
        result.routeChanged = false;
        return result;
    }
}
