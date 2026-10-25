/**
 * The Approval Matrix Assistant's Preview Approval Route action (M13): 6.4's
 * preview of one record, answered in words the agent can repeat.
 *
 * Architecture section: 6.4 (preview), 7 (entry points, and its M13 note),
 * 11 (security).
 *
 * THE ENGINE'S PREVIEW, UNCHANGED. Each request runs
 * AMF_ApprovalMatrixService.preview() for one record -- steps 1 to 7, nothing
 * written -- exactly as the submit action's confirmation modal does. The
 * agent shows the route; it never works one out. Summary is a complete,
 * deterministic sentence built here from the engine's answer, so what the user
 * reads does not depend on the model paraphrasing a rule correctly.
 *
 * OUTCOME IS THE PREVIEW'S, RENAMED FOR A READER WHO HAS NOT SUBMITTED. The
 * engine calls a routable preview Submitted, because that is what a submission
 * would record (6.4); here it is Routable, so that nothing in the agent's
 * context suggests the record has gone anywhere. A whole-call fault the
 * preview throws -- a record the user cannot read, one already in an approval
 * process, an object the matrix does not govern, a rule that will not compile
 * -- is Refused, with the engine's own reason. Nothing was written either way.
 *
 * ONE RECORD PER REQUEST, each previewed by itself, because the assistant
 * previews the record it is talking about. Each costs a handful of queries.
 *
 * Declared with sharing, though it reads nothing itself: the engine runs
 * without sharing and authorises the record against the running user (11).
 */
public with sharing class AMF_AgentPreviewRoute {

    /** Outcome values. ROUTABLE replaces the engine's Submitted; see the class comment. */
    @TestVisible
    private static final String ROUTABLE = 'Routable';
    private static final String BLOCKED_NO_MATCH = 'Blocked_No_Match';
    private static final String FAILED = 'Failed';
    @TestVisible
    private static final String REFUSED = 'Refused';

    /** One record to preview. */
    public class Request {
        @InvocableVariable(
            label='Record ID'
            description='The Salesforce Id of the record to preview: the record on the user\'s screen, or the one Find Governed Record returned.'
            required=true
        )
        public String recordId;
    }

    /** Where the record would go, and why. Nothing has been submitted. */
    public class Result {
        @InvocableVariable(
            label='Record ID'
            description='The record previewed, as an 18-character Id. Empty when the Id given was not valid.'
        )
        public String recordId;

        @InvocableVariable(label='Record' description='The record as a person names it, such as Purchase Request PR-00000045.')
        public String recordLabel;

        @InvocableVariable(
            label='Can Submit'
            description='True when the matrix reached a decision, so Submit Previewed Route may be offered. False when the record cannot be submitted at all.'
        )
        public Boolean canSubmit;

        @InvocableVariable(
            label='Outcome'
            description='Routable: a rule matched and the record would enter Selected Process. Blocked_No_Match: no rule matched, so a submission would only record the block. Failed: the matrix could not decide. Refused: the record cannot be submitted, for the reason in Summary.'
        )
        public String outcome;

        @InvocableVariable(
            label='Summary'
            description='The preview in plain English, complete and ready to give the user. It says that nothing has been submitted.'
        )
        public String summary;

        @InvocableVariable(
            label='Selected Process'
            description='The approval process the record would enter. Empty unless Outcome is Routable.'
        )
        public String selectedProcess;

        @InvocableVariable(label='Matched Rule' description='DeveloperName of the rule that matched. Empty when none did.')
        public String matchedRule;

        @InvocableVariable(label='Rule Version' description='Version of the matched rule.')
        public Integer ruleVersion;

        @InvocableVariable(label='Rule Priority' description='Priority of the matched rule. Rules are tried lowest number first.')
        public Integer rulePriority;

        @InvocableVariable(label='Rule Description' description='What the matched rule is for, as its administrator described it.')
        public String ruleDescription;

        @InvocableVariable(label='Condition' description='The matched rule\'s condition, exactly as written in the matrix.')
        public String condition;

        @InvocableVariable(
            label='Values Read'
            description='The field values the decision rested on, by field label, such as Risk Level = Medium and Amount = 60,000.'
        )
        public String valuesRead;
    }

    /**
     * Test seam: tests set this so the action runs over in-memory rules instead
     * of the org's matrix. Always null in production.
     */
    @TestVisible
    private static AMF_ApprovalMatrixService engineOverride;

    /**
     * @param requests One per record.
     * @return One result per request, in the same order. Never throws for a record.
     */
    @InvocableMethod(
        label='Preview Approval Route'
        description='Shows which approval process the approval matrix would send a record to, which rule decides it and why. Writes nothing and submits nothing.'
        category='Approval Matrix'
    )
    public static List<Result> preview(List<Request> requests) {
        List<Result> results = new List<Result>();

        if (requests == null) {
            return results;
        }
        for (Request request : requests) {
            results.add(previewOne(request?.recordId));
        }
        return results;
    }

    private static Result previewOne(String recordReference) {
        Id recordId = AMF_AgentSupport.idOf(recordReference);

        if (recordId == null) {
            return refused(null, null, AMF_AgentSupport.notAnId(recordReference));
        }

        String label = AMF_DecisionExplainer.recordLabelOf(recordId);
        AMF_ApprovalMatrixService.Outcome outcome;

        try {
            outcome = engine().preview(new List<Id>{ recordId })[0];
        } catch (AMF_SubmissionException e) {
            return refused(recordId, label, e.getMessage());
        } catch (AMF_ExpressionException e) {
            return refused(recordId, label, e.getMessage());
        }

        return resultOf(recordId, label, outcome);
    }

    private static Result resultOf(Id recordId, String label, AMF_ApprovalMatrixService.Outcome outcome) {
        Result result = new Result();
        result.recordId = String.valueOf(recordId);
        result.recordLabel = label;
        result.matchedRule = outcome.matchedRule;
        result.ruleVersion = outcome.ruleVersion;
        result.rulePriority = outcome.rulePriority;
        result.ruleDescription = outcome.matchedRuleDescription;
        result.condition = outcome.matchedExpression;
        result.valuesRead = AMF_AgentSupport.sentenceOf(outcome.evaluatedValuesJson, recordId.getSObjectType());
        // A blocked or failed preview still reaches a decision, and the header
        // button submits it so the attempt is recorded (6.1 step 6, M5). The
        // agent may do the same, once the user says so.
        result.canSubmit = true;

        switch on outcome.outcome {
            when 'Submitted' {
                result.outcome = ROUTABLE;
                result.selectedProcess = outcome.selectedProcess;
                result.summary = routableSummary(label, result);
            }
            when 'Blocked_No_Match' {
                result.outcome = BLOCKED_NO_MATCH;
                result.summary =
                    'No active rule matches ' +
                    label +
                    ', so the approval matrix would block a submission instead of routing it by default.' +
                    (String.isBlank(result.valuesRead) ? '' : ' It read ' + result.valuesRead + '.') +
                    ' Submitting it would not start an approval: it would only record the blocked attempt in the ' +
                    'decision log. Nothing has been submitted yet.';
            }
            when else {
                result.outcome = FAILED;
                result.summary =
                    'The approval matrix could not decide a route for ' +
                    label +
                    ': ' +
                    AMF_AgentSupport.asSentence(outcome.message) +
                    ' Submitting it would not start an approval: it would only record the failed attempt for an ' +
                    'administrator. Nothing has been submitted yet.';
            }
        }
        return result;
    }

    private static String routableSummary(String label, Result result) {
        String summary =
            label +
            ' would go to approval process ' +
            result.selectedProcess +
            '. Rule ' +
            result.matchedRule +
            ' (priority ' +
            result.rulePriority +
            (result.ruleVersion == null ? '' : ', version ' + result.ruleVersion) +
            ') decides it, ' +
            (String.isBlank(result.valuesRead)
                ? 'and its condition reads no fields, so it matches every record that no earlier rule did.'
                : 'because ' + result.valuesRead + '.');

        if (String.isNotBlank(result.ruleDescription)) {
            summary += ' The rule\'s description: ' + result.ruleDescription;
            if (!result.ruleDescription.trim().endsWith('.')) {
                summary += '.';
            }
        }
        return summary + ' Nothing has been submitted yet.';
    }

    private static Result refused(Id recordId, String label, String reason) {
        Result result = new Result();
        result.recordId = recordId == null ? null : String.valueOf(recordId);
        result.recordLabel = label;
        result.canSubmit = false;
        result.outcome = REFUSED;
        result.summary =
            (label == null ? 'This record' : label) +
            ' cannot be submitted: ' +
            AMF_AgentSupport.asSentence(reason) +
            ' Nothing has been submitted.';
        return result;
    }

    private static AMF_ApprovalMatrixService engine() {
        return engineOverride == null ? new AMF_ApprovalMatrixService() : engineOverride;
    }
}
