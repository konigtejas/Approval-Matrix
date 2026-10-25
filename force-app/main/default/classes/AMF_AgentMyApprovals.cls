/**
 * The Approval Matrix Assistant's My Pending Approvals action (M14): the
 * governed records whose approval is waiting on the user, oldest first.
 *
 * Architecture section: 7 (entry points, and its M14 note), 8 (its M14 note),
 * 11 (security).
 *
 * "Waiting on the user" is AMF_ApproverScope's answer, the one the timeline and
 * the briefing use: work items assigned to the user, to a queue or group they
 * belong to, or to someone whose delegated approver they are. Only governed
 * objects -- the objects the matrix has active rules for -- and only records
 * the user can read are listed. Each line carries the record's Id, so the
 * agent can brief the user on any of them next.
 *
 * Read-only. The work items are read without sharing, bound to the user's own
 * scope, because the question is about the user's own work.
 */
public with sharing class AMF_AgentMyApprovals {

    /** Most records listed. The oldest come first; the rest are counted. */
    @TestVisible
    private static final Integer MAX_LISTED = 10;

    /** Work items read at most, before filtering to governed, readable records. */
    private static final Integer MAX_WORK_ITEMS = 1000;

    /** UserRecordAccess answers for at most 200 records per query. */
    private static final Integer ACCESS_QUERY_LIMIT = 200;

    /** Which approvals to list. */
    public class Request {
        @InvocableVariable(
            label='Object'
            description='Optional: list only one kind of record, such as Purchase Request or Opportunity. Leave empty for every kind.'
        )
        public String objectName;
    }

    /** The approvals waiting on the user. */
    public class Result {
        @InvocableVariable(label='Count' description='How many governed records are waiting on the user for approval.')
        public Integer count;

        @InvocableVariable(
            label='Approvals'
            description='A numbered list of the records waiting on the user, oldest first, each with its Id, process, step, submitter and how long it has waited.'
        )
        public String approvals;

        @InvocableVariable(label='Message' description='What is waiting, in plain English, ready to give the user.')
        public String message;
    }

    /** One record waiting on the user. */
    private class Waiting {
        private Id recordId;
        private Id instanceId;
        private String processName;
        private Id submittedById;
        private Id actorId;
        private Datetime since;
    }

    /**
     * Test seams: tests set these so the action learns the governed objects
     * from in-memory rules and reads in-memory work. Always null in production.
     */
    @TestVisible
    private static AMF_RuleProvider ruleProviderOverride;
    @TestVisible
    private static List<ProcessInstanceWorkitem> workOverride;

    /**
     * @param requests Usually one, with or without an object.
     * @return One result per request, in the same order.
     */
    @InvocableMethod(
        label='My Pending Approvals'
        description='Lists the governed records whose approval is waiting on the user, directly, through a queue, or as delegated approver, oldest first. Reads only.'
        category='Approval Matrix'
    )
    public static List<Result> listApprovals(List<Request> requests) {
        List<Result> results = new List<Result>();

        if (requests == null || requests.isEmpty()) {
            requests = new List<Request>{ new Request() };
        }
        for (Request request : requests) {
            results.add(listOne(request?.objectName));
        }
        return results;
    }

    private static Result listOne(String objectName) {
        Set<String> governed = governedObjects();
        String only = null;

        if (String.isNotBlank(objectName)) {
            only = objectNamed(objectName, governed);
            if (only == null) {
                Result result = answer(0, null, '"' + objectName.abbreviate(60) + '" is not a kind of record the approval matrix governs.');
                return result;
            }
        }

        Set<Id> actors = AMF_ApproverScope.actorsFor(UserInfo.getUserId());
        List<Waiting> waiting = waitingFor(actors, governed, only);

        if (waiting.isEmpty()) {
            return answer(0, null, 'Nothing governed by the approval matrix is waiting on you for approval.');
        }

        List<Waiting> listed = new List<Waiting>();
        Set<Id> recordIds = new Set<Id>();
        Set<Id> instanceIds = new Set<Id>();
        Set<Id> actorIds = new Set<Id>();

        for (Integer i = 0; i < Math.min(MAX_LISTED, waiting.size()); i++) {
            listed.add(waiting[i]);
            recordIds.add(waiting[i].recordId);
            instanceIds.add(waiting[i].instanceId);
            actorIds.add(waiting[i].actorId);
            actorIds.add(waiting[i].submittedById);
        }

        Map<Id, String> labels = AMF_AgentSupport.labelsOf(recordIds);
        Map<Id, String> steps = new WorkReader().stepNamesOf(instanceIds);
        Map<Id, String> actorNames = AMF_AgentSupport.actorNamesOf(actorIds);
        List<String> lines = new List<String>();

        for (Integer i = 0; i < listed.size(); i++) {
            Waiting item = listed[i];
            lines.add(
                (i + 1) + '. ' + labels.get(item.recordId) + ' (Id ' + item.recordId + '): approval process ' +
                item.processName +
                (steps.containsKey(item.instanceId) ? ', step "' + steps.get(item.instanceId) + '"' : '') +
                ', submitted by ' + (actorNames.containsKey(item.submittedById) ? actorNames.get(item.submittedById) : 'an unknown user') +
                ', waiting on ' + onWhom(item.actorId, actorNames) +
                ' since ' + AMF_AgentSupport.whenOf(item.since) + '.'
            );
        }

        String message =
            waiting.size() == 1
                ? 'One request is waiting on you for approval.'
                : waiting.size() + ' requests are waiting on you for approval' +
                  (waiting.size() > MAX_LISTED ? '; the ' + MAX_LISTED + ' oldest are listed.' : ', oldest first.');
        return answer(waiting.size(), String.join(lines, '\n'), message);
    }

    /** "you", "the Credit Risk queue, which you are in", or "Ann Lee, as their delegated approver". */
    private static String onWhom(Id actorId, Map<Id, String> actorNames) {
        if (actorId == UserInfo.getUserId()) {
            return 'you';
        }
        String name = actorNames.containsKey(actorId) ? actorNames.get(actorId) : String.valueOf(actorId);
        if (actorId.getSObjectType() == Group.SObjectType) {
            return 'the ' + name + ' queue, which you are in,';
        }
        return name + ', as their delegated approver,';
    }

    /**
     * Pending work in the user's scope, one entry per record, on governed
     * objects the user can read, oldest first.
     */
    private static List<Waiting> waitingFor(Set<Id> actors, Set<String> governed, String only) {
        List<Waiting> waiting = new List<Waiting>();
        Set<Id> seen = new Set<Id>();

        for (ProcessInstanceWorkitem item : workOverride != null ? workOverride : new WorkReader().pendingFor(actors)) {
            Id recordId = item.ProcessInstance.TargetObjectId;
            String objectApiName = recordId == null ? null : String.valueOf(recordId.getSObjectType());

            if (recordId == null || !governed.contains(objectApiName) || (only != null && only != objectApiName)) {
                continue;
            }
            // A committee step gives one record several work items; it is listed once.
            if (!seen.add(recordId)) {
                continue;
            }

            Waiting one = new Waiting();
            one.recordId = recordId;
            one.instanceId = item.ProcessInstanceId;
            one.processName = item.ProcessInstance.ProcessDefinition?.DeveloperName;
            one.submittedById = item.ProcessInstance.SubmittedById;
            one.actorId = item.ActorId;
            one.since = item.CreatedDate;
            waiting.add(one);
        }

        Set<Id> readable = readableAmong(seen);
        List<Waiting> visible = new List<Waiting>();
        for (Waiting one : waiting) {
            if (readable.contains(one.recordId)) {
                visible.add(one);
            }
        }
        return visible;
    }

    /** The records the user can read, asked of UserRecordAccess 200 at a time. */
    private static Set<Id> readableAmong(Set<Id> recordIds) {
        Set<Id> readable = new Set<Id>();
        List<Id> all = new List<Id>(recordIds);

        for (Integer start = 0; start < all.size(); start += ACCESS_QUERY_LIMIT) {
            List<Id> chunk = new List<Id>();
            for (Integer i = start; i < Math.min(start + ACCESS_QUERY_LIMIT, all.size()); i++) {
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

    /** The objects the matrix has active rules for. */
    private static Set<String> governedObjects() {
        Set<String> governed = new Set<String>();
        AMF_RuleProvider provider = ruleProviderOverride == null ? new AMF_CmdtRuleProvider() : ruleProviderOverride;
        for (AMF_RuleDefinition rule : provider.getActiveRules()) {
            if (String.isNotBlank(rule.objectApiName)) {
                governed.add(rule.objectApiName);
            }
        }
        return governed;
    }

    /** A governed object named by its API name, label or plural label, in any case. */
    private static String objectNamed(String name, Set<String> governed) {
        String wanted = name.trim().toLowerCase();
        for (String apiName : governed) {
            Schema.SObjectType sobjectType = Schema.getGlobalDescribe().get(apiName);
            if (sobjectType == null) {
                continue;
            }
            Schema.DescribeSObjectResult described = sobjectType.getDescribe();
            if (
                described.getName().toLowerCase() == wanted ||
                described.getLabel().toLowerCase() == wanted ||
                described.getLabelPlural().toLowerCase() == wanted
            ) {
                return described.getName();
            }
        }
        return null;
    }

    private static Result answer(Integer count, String approvals, String message) {
        Result result = new Result();
        result.count = count;
        result.approvals = approvals;
        result.message = message;
        return result;
    }

    /**
     * Reads the user's own pending work outside sharing. Every query is bound to
     * the user's approver scope or to approvals already found in it.
     */
    private without sharing class WorkReader {

        private List<ProcessInstanceWorkitem> pendingFor(Set<Id> actors) {
            return [
                SELECT
                    Id,
                    ActorId,
                    CreatedDate,
                    ProcessInstanceId,
                    ProcessInstance.TargetObjectId,
                    ProcessInstance.ProcessDefinition.DeveloperName,
                    ProcessInstance.SubmittedById
                FROM ProcessInstanceWorkitem
                WHERE ActorId IN :actors AND ProcessInstance.Status = 'Pending'
                ORDER BY CreatedDate ASC, Id ASC
                LIMIT :MAX_WORK_ITEMS
            ];
        }

        /** The name of each approval's pending step. */
        private Map<Id, String> stepNamesOf(Set<Id> instanceIds) {
            Map<Id, String> names = new Map<Id, String>();
            for (ProcessInstanceNode node : [
                SELECT ProcessInstanceId, ProcessNodeName
                FROM ProcessInstanceNode
                WHERE ProcessInstanceId IN :instanceIds AND NodeStatus = 'Pending'
            ]) {
                names.put(node.ProcessInstanceId, node.ProcessNodeName);
            }
            return names;
        }
    }
}
