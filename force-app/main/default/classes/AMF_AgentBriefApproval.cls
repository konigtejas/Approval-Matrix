/**
 * The Approval Matrix Assistant's Brief Approver action (M14): a plain-English
 * briefing for the person a record's approval is waiting on, before they decide.
 *
 * Architecture section: 8 (auditability, and its M13 and M14 notes), 7 (its
 * M14 note), 11 (security).
 *
 * AMF_DecisionExplainer.briefLatest() writes it from the timeline's view of the
 * pending approval -- which, since M14, shows its current approver the row that
 * explains the route -- through the same prompt template as every explanation.
 * The briefing describes the request, the route and the approval so far. It
 * never says whether to approve: the approver decides, in the approval itself.
 *
 * Every request is answered: a record the user cannot read, one not waiting on
 * them, or a briefing Einstein could not give comes back with Briefed false and
 * the reason in Briefing, for the agent to pass on. Nothing is written or stored.
 */
public with sharing class AMF_AgentBriefApproval {

    /** One record whose pending approval to brief the user on. */
    public class Request {
        @InvocableVariable(
            label='Record ID'
            description='The Salesforce Id of the record whose approval is waiting on the user.'
            required=true
        )
        public String recordId;
    }

    /** The briefing, or why there is none. */
    public class Result {
        @InvocableVariable(label='Briefed' description='True when Briefing describes an approval waiting on the user; false when it says why it cannot.')
        public Boolean briefed;

        @InvocableVariable(
            label='Briefing'
            description='The briefing in plain English, ready to give the user, or the reason none could be given.'
        )
        public String briefing;

        @InvocableVariable(label='Decision Log' description='The decision log row the briefing was written from, such as ADL-00000031. Empty when there is none.')
        public String decisionLogName;
    }

    /**
     * Test seam: tests set this so the action briefs over in-memory history with
     * a stub generator instead of Einstein. Always null in production.
     */
    @TestVisible
    private static AMF_DecisionExplainer explainerOverride;

    /**
     * @param requests One per record.
     * @return One result per request, in the same order. Never throws for a record.
     */
    @InvocableMethod(
        label='Brief Approver'
        description='Briefs the user in plain English on an approval that is waiting on them: what is asked, why the approval matrix routed it to them, and what has happened so far. Never recommends a decision.'
        category='Approval Matrix'
    )
    public static List<Result> brief(List<Request> requests) {
        List<Result> results = new List<Result>();

        if (requests == null) {
            return results;
        }
        for (Request request : requests) {
            results.add(briefOne(request));
        }
        return results;
    }

    private static Result briefOne(Request request) {
        Result result = new Result();
        result.briefed = false;

        Id recordId = AMF_AgentSupport.idOf(request?.recordId);
        if (recordId == null) {
            result.briefing = 'There is no briefing: ' + AMF_AgentSupport.notAnId(request?.recordId);
            return result;
        }

        try {
            AMF_DecisionExplainer.Explanation briefing = explainer().briefLatest(recordId);
            result.briefed = true;
            result.briefing = briefing.text;
            result.decisionLogName = briefing.logName;
        } catch (AMF_ExplanationException e) {
            result.briefing = e.getMessage();
        }
        return result;
    }

    private static AMF_DecisionExplainer explainer() {
        return explainerOverride == null ? new AMF_DecisionExplainer() : explainerOverride;
    }
}
