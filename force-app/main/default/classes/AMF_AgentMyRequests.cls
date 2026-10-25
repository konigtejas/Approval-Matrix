/**
 * The Approval Matrix Assistant's My Requests action (M14): where the user's
 * own recent submissions stand, one line per record.
 *
 * Architecture section: 7 (entry points, and its M14 note), 8 (auditability),
 * 11 (security).
 *
 * THE DECISION LOG IS THE LIST. Every attempt the user made through the matrix
 * left a row they submitted (3.3), read here WITH USER_MODE, so it is exactly
 * the rows they could open: as an Approval_Matrix_User, their own. The newest
 * attempt per record is joined, through Execution_Ref_Id__c, to the approval it
 * started, for where it stands now: waiting on whom and since when, or how it
 * ended. A blocked or failed attempt says so. Records the user can no longer
 * read are left out.
 *
 * Each line is a deterministic sentence built here; the agent repeats it. Each
 * carries the record's Id, so the agent can explain any of them next.
 */
public with sharing class AMF_AgentMyRequests {

    /** How far back the list looks. */
    @TestVisible
    private static final Integer DAYS = 90;

    /** Most records listed: those still in approval first, then the newest. */
    @TestVisible
    private static final Integer MAX_LISTED = 10;

    /** Rows read at most, before taking the newest per record. */
    private static final Integer MAX_ROWS = 500;

    /** ProcessInstance.Status, as the end of a sentence. */
    private static final Map<String, String> ENDED = new Map<String, String>{
        'Approved' => 'approved',
        'Rejected' => 'rejected',
        'Removed' => 'recalled',
        'Held' => 'on hold'
    };

    /** Which requests to list. */
    public class Request {
        @InvocableVariable(
            label='Pending Only'
            description='Optional: true to list only requests still waiting for approval.'
        )
        public Boolean pendingOnly;
    }

    /** The user's requests. */
    public class Result {
        @InvocableVariable(label='Count' description='How many governed records the user submitted in the period listed.')
        public Integer count;

        @InvocableVariable(
            label='Requests'
            description='A numbered list of the user\'s records, each with its Id and where its approval stands.'
        )
        public String requests;

        @InvocableVariable(label='Message' description='What was found, in plain English, ready to give the user.')
        public String message;
    }

    /** One record's newest attempt and, once read, its approval. */
    private class Attempt {
        private Approval_Decision_Log__c row;
        private Id recordId;
        private ProcessInstance approval;
    }

    /**
     * @param requests Usually one.
     * @return One result per request, in the same order.
     */
    @InvocableMethod(
        label='My Approval Requests'
        description='Lists the governed records the user submitted for approval in the last 90 days and where each one stands: waiting on whom, approved, rejected, recalled, blocked or failed. Reads only.'
        category='Approval Matrix'
    )
    public static List<Result> listRequests(List<Request> requests) {
        List<Result> results = new List<Result>();

        if (requests == null || requests.isEmpty()) {
            requests = new List<Request>{ new Request() };
        }
        for (Request request : requests) {
            results.add(listOne(request?.pendingOnly == true));
        }
        return results;
    }

    private static Result listOne(Boolean pendingOnly) {
        List<Attempt> attempts = newestAttempts();

        if (attempts.isEmpty()) {
            return answer(0, null, 'You have not submitted anything through the approval matrix in the last ' + DAYS + ' days.');
        }

        joinApprovals(attempts);

        List<Attempt> pending = new List<Attempt>();
        List<Attempt> rest = new List<Attempt>();
        for (Attempt attempt : attempts) {
            if (attempt.approval?.Status == 'Pending') {
                pending.add(attempt);
            } else if (!pendingOnly) {
                rest.add(attempt);
            }
        }

        List<Attempt> ordered = new List<Attempt>(pending);
        ordered.addAll(rest);

        if (ordered.isEmpty()) {
            return answer(0, null, 'None of your requests from the last ' + DAYS + ' days is waiting for approval.');
        }

        Set<Id> recordIds = new Set<Id>();
        Set<Id> actorIds = new Set<Id>();
        for (Integer i = 0; i < Math.min(MAX_LISTED, ordered.size()); i++) {
            recordIds.add(ordered[i].recordId);
            for (ProcessInstanceWorkitem item : workOf(ordered[i])) {
                actorIds.add(item.ActorId);
            }
            if (ordered[i].approval?.LastActorId != null) {
                actorIds.add(ordered[i].approval.LastActorId);
            }
        }

        Map<Id, String> labels = AMF_AgentSupport.labelsOf(recordIds);
        Map<Id, String> actorNames = AMF_AgentSupport.actorNamesOf(actorIds);
        List<String> lines = new List<String>();

        for (Integer i = 0; i < Math.min(MAX_LISTED, ordered.size()); i++) {
            Attempt attempt = ordered[i];
            lines.add((i + 1) + '. ' + labels.get(attempt.recordId) + ' (Id ' + attempt.recordId + '): ' + standingOf(attempt, actorNames));
        }

        String message =
            (pendingOnly
                ? ordered.size() + ' of your requests ' + (ordered.size() == 1 ? 'is' : 'are') + ' waiting for approval'
                : 'You submitted ' + ordered.size() + ' record' + (ordered.size() == 1 ? '' : 's') + ' in the last ' + DAYS + ' days, ' +
                  pending.size() + ' still waiting for approval') +
            (ordered.size() > MAX_LISTED ? '. The first ' + MAX_LISTED + ' are listed, those still waiting first.' : '.');
        return answer(ordered.size(), String.join(lines, '\n'), message);
    }

    /** "in approval process X, waiting on Y since ...", or how it ended. */
    private static String standingOf(Attempt attempt, Map<Id, String> actorNames) {
        Approval_Decision_Log__c row = attempt.row;
        String submitted = AMF_AgentSupport.whenOf(row.Submitted_At__c);

        switch on row.Outcome__c {
            when 'Blocked_No_Match' {
                return 'blocked on ' + submitted + ': no rule matched, so it was not submitted (decision log ' + row.Name + ').';
            }
            when 'Failed' {
                return 'failed on ' + submitted + ', so it did not enter an approval process: ' +
                    AMF_AgentSupport.asSentence(firstLineOf(row.Failure_Detail__c)) + ' (decision log ' + row.Name + ')';
            }
        }

        if (attempt.approval == null) {
            return 'submitted to approval process ' + row.Selected_Process__c + ' on ' + submitted + '; its approval history is not available.';
        }

        ProcessInstance approval = attempt.approval;
        if (approval.Status == 'Pending') {
            List<String> names = new List<String>();
            Datetime since = null;
            for (ProcessInstanceWorkitem item : workOf(attempt)) {
                names.add(actorNames.containsKey(item.ActorId) ? actorNames.get(item.ActorId) : String.valueOf(item.ActorId));
                since = since == null || item.CreatedDate < since ? item.CreatedDate : since;
            }
            return 'in approval process ' + row.Selected_Process__c +
                (names.isEmpty() ? '' : ', waiting on ' + String.join(names, ', ') + ' since ' + AMF_AgentSupport.whenOf(since)) +
                ' (submitted ' + submitted + ').';
        }

        // Named by Id, as approvers are: LastActor.Name can read null in the
        // transaction that decided the approval.
        String ended = ENDED.containsKey(approval.Status) ? ENDED.get(approval.Status) : approval.Status.toLowerCase();
        String lastActor = actorNames.get(approval.LastActorId);
        return ended + ' in approval process ' + row.Selected_Process__c +
            (approval.CompletedDate == null ? '' : ' on ' + AMF_AgentSupport.whenOf(approval.CompletedDate)) +
            (approval.Status == 'Removed' || String.isBlank(lastActor) ? '' : ', last acted on by ' + lastActor) +
            ' (submitted ' + submitted + ').';
    }

    /** The user's own rows in the period, newest attempt per record, records they can still read. */
    private static List<Attempt> newestAttempts() {
        Datetime since = Datetime.now().addDays(-DAYS);
        Id me = UserInfo.getUserId();
        List<Attempt> attempts = new List<Attempt>();
        Set<String> seen = new Set<String>();

        for (Approval_Decision_Log__c row : [
            SELECT Id, Name, Record_Id__c, Outcome__c, Selected_Process__c, Execution_Ref_Id__c, Failure_Detail__c, Submitted_At__c
            FROM Approval_Decision_Log__c
            WHERE Submitted_By__c = :me AND Submitted_At__c >= :since
            WITH USER_MODE
            ORDER BY Submitted_At__c DESC, CreatedDate DESC, Id DESC
            LIMIT :MAX_ROWS
        ]) {
            Id recordId = AMF_AgentSupport.idOf(row.Record_Id__c);
            if (recordId == null || !seen.add(String.valueOf(recordId))) {
                continue;
            }
            Attempt attempt = new Attempt();
            attempt.row = row;
            attempt.recordId = recordId;
            attempts.add(attempt);
        }

        Set<Id> recordIds = new Set<Id>();
        for (Attempt attempt : attempts) {
            recordIds.add(attempt.recordId);
        }
        Set<Id> readable = readableAmong(recordIds);

        List<Attempt> visible = new List<Attempt>();
        for (Attempt attempt : attempts) {
            if (readable.contains(attempt.recordId)) {
                visible.add(attempt);
            }
        }
        return visible;
    }

    /** Each Submitted attempt's approval, through Execution_Ref_Id__c. */
    private static void joinApprovals(List<Attempt> attempts) {
        Set<Id> refs = new Set<Id>();
        for (Attempt attempt : attempts) {
            Id ref = AMF_AgentSupport.idOf(attempt.row.Execution_Ref_Id__c);
            if (attempt.row.Outcome__c == 'Submitted' && ref != null) {
                refs.add(ref);
            }
        }
        if (refs.isEmpty()) {
            return;
        }

        Map<Id, ProcessInstance> approvals = new ApprovalReader().approvalsOf(refs);
        for (Attempt attempt : attempts) {
            Id ref = AMF_AgentSupport.idOf(attempt.row.Execution_Ref_Id__c);
            if (ref != null) {
                attempt.approval = approvals.get(ref);
            }
        }
    }

    private static List<ProcessInstanceWorkitem> workOf(Attempt attempt) {
        return attempt.approval == null || attempt.approval.Workitems == null
            ? new List<ProcessInstanceWorkitem>()
            : attempt.approval.Workitems;
    }

    /** The records the user can read, asked of UserRecordAccess 200 at a time. */
    private static Set<Id> readableAmong(Set<Id> recordIds) {
        Set<Id> readable = new Set<Id>();
        List<Id> all = new List<Id>(recordIds);

        for (Integer start = 0; start < all.size(); start += 200) {
            List<Id> chunk = new List<Id>();
            for (Integer i = start; i < Math.min(start + 200, all.size()); i++) {
                chunk.add(all[i]);
            }
            for (UserRecordAccess access : [
                SELECT RecordId
                FROM UserRecordAccess
                WHERE UserId = :UserInfo.getUserId() AND RecordId IN :chunk AND HasReadAccess = TRUE
            ]) {
                readable.add(access.RecordId);
            }
        }
        return readable;
    }

    private static String firstLineOf(String text) {
        return String.isBlank(text) ? '' : text.split('\r?\n')[0].trim().abbreviate(300);
    }

    private static Result answer(Integer count, String requests, String message) {
        Result result = new Result();
        result.count = count;
        result.requests = requests;
        result.message = message;
        return result;
    }

    /**
     * Reads the approvals the user's own rows name, outside sharing: the Ids
     * come from rows the user could read, on records they can read.
     */
    private without sharing class ApprovalReader {

        private Map<Id, ProcessInstance> approvalsOf(Set<Id> instanceIds) {
            return new Map<Id, ProcessInstance>([
                SELECT Id, Status, CompletedDate, LastActorId, (SELECT ActorId, CreatedDate FROM Workitems ORDER BY CreatedDate)
                FROM ProcessInstance
                WHERE Id IN :instanceIds
            ]);
        }
    }
}
