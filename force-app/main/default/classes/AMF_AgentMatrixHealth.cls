/**
 * The Approval Matrix Admin Assistant's Matrix Health Report action (M15): how
 * the matrix has been doing, counted in Apex and summarised by Einstein.
 *
 * Architecture section: 7 (entry points, and its M15 note), 8 (auditability),
 * 1 (principle 6).
 *
 * AMF_MatrixHealthService counts the facts and asks for the summary. This
 * action reads the object the administrator named, if any, and always returns
 * the counted facts, so a report stands even when Einstein cannot summarise
 * it. Read-only. Granted by Approval_Matrix_Admin alone.
 */
public with sharing class AMF_AgentMatrixHealth {

    /** What to report on. */
    public class Request {
        @InvocableVariable(
            label='Object'
            description='Optional: report on one kind of record, such as Purchase Request. Leave empty for every governed object.'
        )
        public String objectName;

        @InvocableVariable(label='Days' description='Optional: the period, in days back from today. Leave empty for 30.')
        public Integer days;

        @InvocableVariable(label='Question' description='Optional: what the administrator wants to know about the matrix, in their own words.')
        public String question;
    }

    /** The report. */
    public class Result {
        @InvocableVariable(label='Summarised' description='True when Summary is Einstein\'s summary; false when it says why there is none.')
        public Boolean summarised;

        @InvocableVariable(label='Summary' description='The report in plain English, ready to give the administrator.')
        public String summary;

        @InvocableVariable(label='Facts' description='Every counted fact the summary was written from, one per line.')
        public String facts;

        @InvocableVariable(label='Days' description='The period reported on, in days.')
        public Integer days;

        @InvocableVariable(label='Decisions' description='Decisions recorded in the period.')
        public Integer decisions;

        @InvocableVariable(label='Blocked' description='Of those, blocked because no rule matched.')
        public Integer blocked;

        @InvocableVariable(label='Failed' description='Of those, failed.')
        public Integer failed;
    }

    /**
     * Test seams: tests set these so the action reports over in-memory rules
     * with a stub model. Always null in production.
     */
    @TestVisible
    private static AMF_MatrixHealthService serviceOverride;
    @TestVisible
    private static AMF_RuleProvider ruleProviderOverride;

    /**
     * @param requests Usually one.
     * @return One result per request, in the same order.
     */
    @InvocableMethod(
        label='Matrix Health Report'
        description='Reports how the approval matrix has been doing: decisions by outcome and by rule, the catch-all share, rules that routed nothing, failure reasons and pending approvals, with a plain-English summary. Reads only.'
        category='Approval Matrix'
    )
    public static List<Result> reportHealth(List<Request> requests) {
        List<Result> results = new List<Result>();

        if (requests == null || requests.isEmpty()) {
            requests = new List<Request>{ new Request() };
        }
        for (Request request : requests) {
            results.add(reportOne(request == null ? new Request() : request));
        }
        return results;
    }

    private static Result reportOne(Request request) {
        Result result = new Result();
        result.summarised = false;

        String objectApiName = null;
        if (String.isNotBlank(request.objectName)) {
            objectApiName = AMF_AgentSupport.governedObjectNamed(request.objectName, provider());
            if (objectApiName == null) {
                result.summary =
                    '"' + request.objectName.trim().abbreviate(60) + '" is not a kind of record the approval matrix ' +
                    'governs. Name a governed object, such as Purchase Request, or ask about all of them.';
                return result;
            }
        }

        AMF_MatrixHealthService.Report report = service().report(request.days, objectApiName, request.question);
        result.facts = report.facts;
        result.days = report.days;
        result.decisions = report.decisions;
        result.blocked = report.blocked;
        result.failed = report.failed;

        if (String.isNotBlank(report.narrative)) {
            result.summarised = true;
            result.summary = report.narrative;
        } else {
            result.summary = AMF_AgentSupport.asSentence(report.narrativeProblem) + ' The counted facts are below.';
        }
        return result;
    }

    private static AMF_MatrixHealthService service() {
        return serviceOverride == null ? new AMF_MatrixHealthService() : serviceOverride;
    }

    private static AMF_RuleProvider provider() {
        return ruleProviderOverride == null ? new AMF_CmdtRuleProvider() : ruleProviderOverride;
    }
}
