/**
 * The Approval Matrix Assistant's Submit Previewed Route action (M13): submits
 * the record the assistant has just previewed, through the same per-record
 * path as Flow and REST, and says what happened in words the agent can repeat.
 *
 * Architecture section: 6.1 (submitEach, and its M10 note), 7 (entry points,
 * and its M13 note), 6.4 (a route that changed after its preview), 11.
 *
 * THE ENGINE DECIDES AGAIN, AND ITS ANSWER IS THE ONE THAT COUNTS. The
 * submission re-runs the matrix through AMF_SubmitForMatrixApproval.submitEach
 * -- the M10 action's own path -- so the agent's submission writes exactly the
 * decision log row a Flow or the REST resource would. Expected Process is the
 * route the user was shown. When the record or the matrix changed after the
 * preview, the route taken can differ, and Route Changed says so, as the
 * header button's warning toast does (M5). It is a comparison of two names
 * here, in Apex, not a judgement left to the model.
 *
 * ONLY THE PREVIEWED RECORD. The agent's script binds Record ID to the record
 * it last previewed and offers this action only after a preview that reached a
 * decision. That is the agent's half of 7's "preview, confirm, submit"; this
 * class submits whatever it is given, exactly as the M10 action does.
 *
 * Declared with sharing, though it reads little itself: the engine runs
 * without sharing and authorises every record against the running user (11).
 */
public with sharing class AMF_AgentSubmitRoute {

    private static final String SUBMITTED = 'Submitted';
    private static final String BLOCKED_NO_MATCH = 'Blocked_No_Match';
    @TestVisible
    private static final String REFUSED = 'Refused';

    /** One record to submit. */
    public class Request {
        @InvocableVariable(
            label='Record ID'
            description='The record to submit: the one Preview Approval Route just previewed.'
            required=true
        )
        public String recordId;

        @InvocableVariable(
            label='Expected Process'
            description='The approval process the preview showed the user. Empty when the preview found no route.'
        )
        public String expectedProcess;
    }

    /** What the submission did. */
    public class Result {
        @InvocableVariable(label='Record ID' description='The record this result is about.')
        public String recordId;

        @InvocableVariable(label='Submitted' description='True only when the record entered an approval process.')
        public Boolean submitted;

        @InvocableVariable(
            label='Outcome'
            description='Submitted, Blocked_No_Match, Failed or Refused. Refused means nothing was decided or recorded.'
        )
        public String outcome;

        @InvocableVariable(
            label='Summary'
            description='What happened, in plain English, complete and ready to give the user.'
        )
        public String summary;

        @InvocableVariable(label='Selected Process' description='The approval process the record entered, or the one the matrix chose.')
        public String selectedProcess;

        @InvocableVariable(label='Matched Rule' description='DeveloperName of the rule that decided the route.')
        public String matchedRule;

        @InvocableVariable(label='Rule Version' description='Version of the matched rule.')
        public Integer ruleVersion;

        @InvocableVariable(
            label='Route Changed'
            description='True when the route taken differs from Expected Process, because the record or the matrix changed after the preview.'
        )
        public Boolean routeChanged;

        @InvocableVariable(label='Decision Log' description='The decision log row that records this attempt, such as ADL-00000031. Empty when Refused.')
        public String decisionLogName;

        @InvocableVariable(label='Waiting On' description='Who the approval is waiting on now. Empty unless Submitted.')
        public String waitingOn;
    }

    /**
     * @param requests One per record.
     * @return One result per request, in the same order.
     * @throws AMF_SubmissionException Only when the strategy fails as a whole, as for the M10 action.
     */
    @InvocableMethod(
        label='Submit Previewed Route'
        description='Submits a record that Preview Approval Route has just previewed. The approval matrix decides the route again and records the decision; the result says whether the route still matched the preview.'
        category='Approval Matrix'
    )
    public static List<Result> submit(List<Request> requests) {
        List<Result> results = new List<Result>();

        if (requests == null || requests.isEmpty()) {
            return results;
        }

        // Every valid Id goes to the engine in one call: submitEach answers each
        // record by itself, so one bad record cannot sink the rest (M10).
        List<Id> toSubmit = new List<Id>();
        for (Request request : requests) {
            Id recordId = AMF_AgentSupport.idOf(request?.recordId);
            if (recordId != null) {
                toSubmit.add(recordId);
            }
        }

        Map<Id, AMF_SubmitForMatrixApproval.Result> outcomeById = new Map<Id, AMF_SubmitForMatrixApproval.Result>();
        if (!toSubmit.isEmpty()) {
            for (AMF_SubmitForMatrixApproval.Result outcome : AMF_SubmitForMatrixApproval.submitEach(toSubmit)) {
                outcomeById.put(outcome.recordId, outcome);
            }
        }

        Map<Id, String> logNames = logNamesOf(outcomeById.values());
        Map<String, String> waitingOn = waitingOnOf(outcomeById.values());

        for (Request request : requests) {
            Id recordId = AMF_AgentSupport.idOf(request?.recordId);

            if (recordId == null) {
                results.add(refused(null, 'This record', AMF_AgentSupport.notAnId(request?.recordId)));
                continue;
            }
            results.add(
                resultOf(
                    request.expectedProcess,
                    AMF_DecisionExplainer.recordLabelOf(recordId),
                    outcomeById.get(recordId),
                    logNames,
                    waitingOn
                )
            );
        }
        return results;
    }

    private static Result resultOf(
        String expectedProcess,
        String label,
        AMF_SubmitForMatrixApproval.Result outcome,
        Map<Id, String> logNames,
        Map<String, String> waitingOn
    ) {
        if (outcome.outcome == REFUSED) {
            return refused(outcome.recordId, label, outcome.message);
        }

        Result result = new Result();
        result.recordId = String.valueOf(outcome.recordId);
        result.submitted = outcome.submitted == true;
        result.outcome = outcome.outcome;
        result.selectedProcess = outcome.selectedProcess;
        result.matchedRule = outcome.matchedRule;
        result.ruleVersion = outcome.ruleVersion;
        result.decisionLogName = logNames.get(outcome.decisionLogId);
        result.waitingOn = waitingOn.get(outcome.executionRefId);
        result.routeChanged = String.isNotBlank(expectedProcess) && outcome.selectedProcess != expectedProcess.trim();

        String logged = result.decisionLogName == null
            ? ' The attempt is recorded in the decision log.'
            : ' The attempt is recorded in decision log ' + result.decisionLogName + '.';
        String changed = result.routeChanged
            ? ' The preview had shown ' + expectedProcess.trim() + ': the record or the approval matrix changed after it.'
            : '';

        if (result.submitted) {
            result.summary =
                (result.routeChanged ? 'Submitted, but by a different route than previewed. ' : 'Submitted. ') +
                label +
                ' entered approval process ' +
                result.selectedProcess +
                (String.isBlank(result.waitingOn) ? '' : ' and is now waiting on ' + result.waitingOn) +
                '. Rule ' +
                result.matchedRule +
                (result.ruleVersion == null ? '' : ' (version ' + result.ruleVersion + ')') +
                ' decided the route.' +
                changed +
                ' Decision log: ' +
                (result.decisionLogName == null ? 'recorded' : result.decisionLogName) +
                '.';
        } else if (result.outcome == BLOCKED_NO_MATCH) {
            result.summary =
                'Not submitted. No active rule matched ' +
                label +
                ', so the approval matrix blocked it instead of routing it by default.' +
                changed +
                logged;
        } else {
            result.summary = 'Not submitted. ' + AMF_AgentSupport.asSentence(outcome.message) + changed + logged;
        }
        return result;
    }

    private static Result refused(Id recordId, String label, String reason) {
        Result result = new Result();
        result.recordId = recordId == null ? null : String.valueOf(recordId);
        result.submitted = false;
        result.outcome = REFUSED;
        result.routeChanged = false;
        result.summary =
            'Not submitted. ' +
            label +
            ' cannot be submitted: ' +
            AMF_AgentSupport.asSentence(reason) +
            ' Nothing was recorded.';
        return result;
    }

    /**
     * Each decision log row's auto-number, read in user mode: the submitter can
     * read their own rows (11), and the name is what they can search for.
     */
    private static Map<Id, String> logNamesOf(List<AMF_SubmitForMatrixApproval.Result> outcomes) {
        Set<Id> logIds = new Set<Id>();
        for (AMF_SubmitForMatrixApproval.Result outcome : outcomes) {
            if (outcome.decisionLogId != null) {
                logIds.add(outcome.decisionLogId);
            }
        }

        Map<Id, String> names = new Map<Id, String>();
        if (logIds.isEmpty()) {
            return names;
        }
        for (Approval_Decision_Log__c row : [
            SELECT Id, Name
            FROM Approval_Decision_Log__c
            WHERE Id IN :logIds
            WITH USER_MODE
        ]) {
            names.put(row.Id, row.Name);
        }
        return names;
    }

    /**
     * Who each new approval is waiting on: the open work items' assignees, a
     * user or a queue, as the Approval History related list names them. Read
     * only for records just submitted, so the record is one the submitter can
     * read, which is all the native history asks (8's M7 note).
     *
     * Names come from ActorId, not Actor.Name. The work items were created in
     * this same transaction, and for such rows the platform returns Actor.Name
     * as null while ActorId is right (technical log, "Fix --
     * AMF_ClassicApprovalHistoryProviderTest actor-name assertions").
     */
    private static Map<String, String> waitingOnOf(List<AMF_SubmitForMatrixApproval.Result> outcomes) {
        Set<Id> instanceIds = new Set<Id>();
        for (AMF_SubmitForMatrixApproval.Result outcome : outcomes) {
            if (outcome.submitted == true && String.isNotBlank(outcome.executionRefId)) {
                instanceIds.add(Id.valueOf(outcome.executionRefId));
            }
        }

        Map<String, String> waitingOn = new Map<String, String>();
        if (instanceIds.isEmpty()) {
            return waitingOn;
        }

        Map<String, List<Id>> actorsByInstance = new Map<String, List<Id>>();
        Set<Id> actorIds = new Set<Id>();
        for (ProcessInstanceWorkitem item : [
            SELECT ProcessInstanceId, ActorId
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstanceId IN :instanceIds
            ORDER BY CreatedDate, Id
        ]) {
            String key = String.valueOf(item.ProcessInstanceId);
            if (!actorsByInstance.containsKey(key)) {
                actorsByInstance.put(key, new List<Id>());
            }
            actorsByInstance.get(key).add(item.ActorId);
            actorIds.add(item.ActorId);
        }

        Map<Id, String> names = namesOf(actorIds);
        for (String key : actorsByInstance.keySet()) {
            List<String> actors = new List<String>();
            for (Id actorId : actorsByInstance.get(key)) {
                if (names.containsKey(actorId)) {
                    actors.add(names.get(actorId));
                }
            }
            waitingOn.put(key, String.join(actors, ', '));
        }
        return waitingOn;
    }

    /** An approver is a user, or a queue, which is a Group. */
    private static Map<Id, String> namesOf(Set<Id> actorIds) {
        Map<Id, String> names = new Map<Id, String>();
        for (User approver : [SELECT Id, Name FROM User WHERE Id IN :actorIds]) {
            names.put(approver.Id, approver.Name);
        }
        for (Group queue : [SELECT Id, Name FROM Group WHERE Id IN :actorIds]) {
            names.put(queue.Id, queue.Name);
        }
        return names;
    }
}
