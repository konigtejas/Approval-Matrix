/**
 * The Claude connector's check_change_impact tool (M16, administrators): what a
 * rule change would do to recent records, before it is released. No model
 * takes part, and nothing is written.
 *
 * Architecture section: 6.4 (previewEach, and its M15 note), 7 (its M15 and M16
 * notes).
 *
 * A facade over the Admin Assistant's Check Rule Impact (M15): a new rule, a new
 * version of a rule, or a rule taken out, applied in memory by
 * AMF_DraftRuleProvider; the object's records decided in the last 90 days, at
 * most 200, previewed by previewEach() under the live matrix and the changed
 * one, on their values today, and compared.
 */
global with sharing class AMF_McpCheckImpact {

    /** The change to check. */
    global class Request {
        @InvocableVariable(label='Object' description='The kind of record the rule governs, such as Purchase Request or Opportunity.')
        global String objectName;

        @InvocableVariable(label='Rule Name' description='The DeveloperName of the rule to add, change or take out.' required=true)
        global String ruleName;

        @InvocableVariable(
            label='Change'
            description='Optional: Add, Replace or Deactivate. Left empty, it is worked out from the rule name and whether a condition is given.'
        )
        global String change;

        @InvocableVariable(label='Priority' description='The rule\'s priority, as a whole number. Needed for a new rule; for a change, empty keeps the live one.')
        global Integer priority;

        @InvocableVariable(label='Condition' description='The rule\'s condition. Needed for a new rule; empty for taking a rule out.')
        global String expression;

        @InvocableVariable(label='Process' description='The approval process the rule sends records to. Needed for a new rule; for a change, empty keeps the live one.')
        global String processApiName;
    }

    /** The comparison. */
    global class Result {
        @InvocableVariable(label='Ran' description='True when the comparison ran; false when Summary says why it could not.')
        global Boolean ran;

        @InvocableVariable(label='Summary' description='The comparison in plain English, ready to give the administrator.')
        global String summary;

        @InvocableVariable(label='Checked' description='How many records were compared.')
        global Integer checked;

        @InvocableVariable(label='Changed' description='How many would be decided differently.')
        global Integer changed;

        @InvocableVariable(label='Skipped' description='How many were skipped: in an approval process now, or unreadable.')
        global Integer skipped;

        @InvocableVariable(
            label='Changes'
            description='A numbered list of the records that would be decided differently, each with today\'s decision and the changed one.'
        )
        global String changes;
    }

    /**
     * @param requests One per change; an MCP call sends one.
     * @return One result per request, in the same order.
     */
    @InvocableMethod(
        label='Check Change Impact (Claude)'
        description='Compares how recent records are decided today with how they would be under a rule change, before it is released. Changes nothing.'
        category='Approval Matrix'
    )
    global static List<Result> checkImpact(List<Request> requests) {
        List<Result> results = new List<Result>();

        if (requests == null) {
            return results;
        }

        List<AMF_AgentCheckImpact.Request> asked = new List<AMF_AgentCheckImpact.Request>();
        for (Request request : requests) {
            AMF_AgentCheckImpact.Request change = new AMF_AgentCheckImpact.Request();
            change.objectName = request?.objectName;
            change.ruleName = request?.ruleName;
            change.change = request?.change;
            change.priority = request?.priority == null ? null : String.valueOf(request.priority);
            change.expression = request?.expression;
            change.processApiName = request?.processApiName;
            asked.add(change);
        }

        for (AMF_AgentCheckImpact.Result compared : AMF_AgentCheckImpact.checkImpact(asked)) {
            Result result = new Result();
            result.ran = compared.ran == true;
            result.summary = compared.summary;
            result.checked = compared.checked;
            result.changed = compared.changed;
            result.skipped = compared.skipped;
            result.changes = compared.changes;
            results.add(result);
        }
        return results;
    }
}
