/**
 * The Approval Matrix Assistant's Explain Approval Decision action (M13): the
 * newest approval attempt on a record, explained in plain English.
 *
 * Architecture section: 8 (auditability, and its M13 note), 7 (its M13 note),
 * 11 (security).
 *
 * The same explanation the record page's Explain button gives: AMF_DecisionExplainer
 * reads the timeline's view of the decision -- the recorded snapshot and the
 * native history the user can already see -- and has Einstein put it into words.
 * The user's question goes with it, so "why is this with the committee?" is
 * answered as asked. Nothing is decided, written or stored.
 *
 * Every request is answered: a record the user cannot read, one never
 * submitted, or an explanation Einstein could not give comes back with
 * Explained false and the reason in Explanation, for the agent to pass on.
 */
public with sharing class AMF_AgentExplainDecision {

    /** One record whose approval to explain. */
    public class Request {
        @InvocableVariable(
            label='Record ID'
            description='The Salesforce Id of the record whose approval to explain: the record on the user\'s screen, or the one Find Governed Record returned.'
            required=true
        )
        public String recordId;

        @InvocableVariable(
            label='Question'
            description='The user\'s question about the approval, in their own words. Optional.'
        )
        public String question;
    }

    /** The explanation, or why there is none. */
    public class Result {
        @InvocableVariable(label='Explained' description='True when Explanation explains a recorded decision; false when it says why it cannot.')
        public Boolean explained;

        @InvocableVariable(
            label='Explanation'
            description='The explanation in plain English, or the reason none could be given. Give it to the user as it is.'
        )
        public String explanation;

        @InvocableVariable(label='Decision Log' description='The decision log row explained, such as ADL-00000031. Empty when the reason is not visible to the user.')
        public String decisionLogName;
    }

    /**
     * Test seam: tests set this so the action explains over in-memory history
     * with a stub generator instead of Einstein. Always null in production.
     */
    @TestVisible
    private static AMF_DecisionExplainer explainerOverride;

    /**
     * @param requests One per record.
     * @return One result per request, in the same order. Never throws for a record.
     */
    @InvocableMethod(
        label='Explain Approval Decision'
        description='Explains in plain English why the approval matrix sent a record where it did, and where its approval stands now, from the recorded decision and the approval history the user can see.'
        category='Approval Matrix'
    )
    public static List<Result> explain(List<Request> requests) {
        List<Result> results = new List<Result>();

        if (requests == null) {
            return results;
        }
        for (Request request : requests) {
            results.add(explainOne(request));
        }
        return results;
    }

    private static Result explainOne(Request request) {
        Result result = new Result();
        result.explained = false;

        Id recordId = AMF_AgentSupport.idOf(request?.recordId);
        if (recordId == null) {
            result.explanation = 'The approval cannot be explained: ' + AMF_AgentSupport.notAnId(request?.recordId);
            return result;
        }

        try {
            AMF_DecisionExplainer.Explanation explanation = explainer().explainLatest(recordId, request.question);
            result.explained = true;
            result.explanation = explanation.text;
            result.decisionLogName = explanation.logName;
        } catch (AMF_ExplanationException e) {
            result.explanation = e.getMessage();
        }
        return result;
    }

    private static AMF_DecisionExplainer explainer() {
        return explainerOverride == null ? new AMF_DecisionExplainer() : explainerOverride;
    }
}
