/**
 * The Approval Matrix Admin Assistant's Check Rule Impact action (M15): what a
 * change to the matrix would do to the object's recently decided records,
 * before it is released.
 *
 * Architecture section: 7 (entry points, and its M15 note), 6.4 (preview, and
 * its M15 note), 1 (principle 6).
 *
 * AMF_MatrixImpact does the work: the engine previews each record under the
 * live matrix and under the matrix with the change, and the two are compared.
 * This action turns what the administrator asked into that change:
 *   - Add: a new rule, at version 1;
 *   - Replace: a new version of an active rule; fields left blank keep the live
 *     rule's, and the version is one more than the live one;
 *   - Deactivate: an active rule taken out.
 * Left blank, the change is inferred: a new name is an Add, an active rule's
 * name with a condition is a Replace, and an active rule's name with none is a
 * Deactivate. A condition that does not compile is refused before anything is
 * previewed, with the compiler's message.
 *
 * Nothing is changed, submitted or recorded. Granted by Approval_Matrix_Admin alone.
 */
public with sharing class AMF_AgentCheckImpact {

    @TestVisible
    private static final String ADD = 'Add';
    @TestVisible
    private static final String REPLACE = 'Replace';
    @TestVisible
    private static final String DEACTIVATE = 'Deactivate';

    /** One change to check. */
    public class Request {
        @InvocableVariable(
            label='Object'
            description='The kind of record the rule governs, such as Purchase Request or Opportunity.'
            required=true
        )
        public String objectName;

        @InvocableVariable(label='Rule Name' description='The DeveloperName of the rule to add, change or take out.' required=true)
        public String ruleName;

        @InvocableVariable(
            label='Change'
            description='Optional: Add, Replace or Deactivate. Left empty, it is worked out from the rule name and whether a condition is given.'
        )
        public String change;

        /** As text, as the agent carries a draft's priority; read as a whole number here. */
        @InvocableVariable(label='Priority' description='The rule\'s priority, as a whole number. Needed for a new rule; for a change, empty keeps the live one.')
        public String priority;

        @InvocableVariable(label='Condition' description='The rule\'s condition. Needed for a new rule; empty for taking a rule out.')
        public String expression;

        @InvocableVariable(label='Process' description='The approval process the rule sends records to. Needed for a new rule; for a change, empty keeps the live one.')
        public String processApiName;
    }

    /** What the change would do. */
    public class Result {
        @InvocableVariable(label='Ran' description='True when the comparison ran; false when Summary says why it could not.')
        public Boolean ran;

        @InvocableVariable(label='Summary' description='The comparison in plain English, ready to give the administrator.')
        public String summary;

        @InvocableVariable(label='Checked' description='How many records were compared.')
        public Integer checked;

        @InvocableVariable(label='Changed' description='How many would be decided differently.')
        public Integer changed;

        @InvocableVariable(label='Skipped' description='How many were skipped: in an approval process now, or unreadable.')
        public Integer skipped;

        @InvocableVariable(label='Changes' description='A numbered list of the records that would be decided differently, each with its Id, today\'s decision and the changed one.')
        public String changes;
    }

    /**
     * Test seam: tests set this so the action reads in-memory rules. Always null
     * in production.
     */
    @TestVisible
    private static AMF_RuleProvider ruleProviderOverride;

    /**
     * @param requests One per change.
     * @return One result per request, in the same order. Never throws for a request.
     */
    @InvocableMethod(
        label='Check Rule Impact'
        description='Shows how a new rule, a new version of a rule, or taking a rule out would change the decisions on recently decided records, using the approval matrix engine. Changes nothing.'
        category='Approval Matrix'
    )
    public static List<Result> checkImpact(List<Request> requests) {
        List<Result> results = new List<Result>();

        if (requests == null) {
            return results;
        }
        for (Request request : requests) {
            results.add(checkOne(request));
        }
        return results;
    }

    private static Result checkOne(Request request) {
        AMF_RuleProvider live = provider();
        String objectApiName = AMF_AgentSupport.governedObjectNamed(request?.objectName, live);

        if (objectApiName == null) {
            return refused(
                (String.isBlank(request?.objectName) ? 'No object was named' : '"' + request.objectName.trim().abbreviate(60) + '" is not a kind of record the approval matrix governs') +
                ', so there is nothing to check. Name a governed object, such as Purchase Request or Opportunity.'
            );
        }

        String ruleName = request.ruleName == null ? '' : request.ruleName.trim();
        if (String.isBlank(ruleName)) {
            return refused('Name the rule to add, change or take out.');
        }

        AMF_RuleDefinition existing = null;
        for (AMF_RuleDefinition rule : live.getActiveRules(objectApiName)) {
            if (rule.developerName == ruleName) {
                existing = rule;
            }
        }

        String change = changeOf(request.change, existing, request.expression);
        if (change == null) {
            return refused('The change must be Add, Replace or Deactivate, not "' + request.change.trim().abbreviate(40) + '".');
        }
        if (change != ADD && existing == null) {
            return refused('No active rule named ' + ruleName + ' governs ' + objectApiName + ', so it cannot be changed or taken out.');
        }
        if (change == ADD && existing != null) {
            return refused(ruleName + ' is already an active rule. Check a new version of it, or a rule with a new name.');
        }

        if (change == DEACTIVATE) {
            return resultOf(new AMF_MatrixImpact(live).check(objectApiName, ruleName, null, 'rule ' + ruleName + ' taken out'));
        }

        Integer priority = existing?.priority;
        if (String.isNotBlank(request.priority)) {
            try {
                priority = Integer.valueOf(request.priority.trim());
            } catch (Exception e) {
                return refused('The priority must be a whole number, not "' + request.priority.trim().abbreviate(20) + '".');
            }
        }
        String processApiName = String.isNotBlank(request.processApiName) ? request.processApiName.trim() : existing?.processApiName;
        String expression = String.isNotBlank(request.expression) ? request.expression.trim() : existing?.expression;

        if (priority == null || String.isBlank(processApiName) || String.isBlank(expression)) {
            return refused('A new rule needs a priority, a condition and an approval process.');
        }

        try {
            AMF_ExprCompiler.compile(objectApiName, expression);
        } catch (AMF_ExpressionException e) {
            return refused('The condition does not compile, so its impact cannot be checked: ' + e.getMessage());
        }

        Integer version = change == ADD ? 1 : (existing.version == null ? 1 : existing.version) + 1;
        AMF_RuleDefinition added = new AMF_RuleDefinition(
            ruleName,
            objectApiName,
            priority,
            expression,
            processApiName,
            existing?.description,
            version,
            true
        );

        String label = change == ADD ? 'the new rule ' + ruleName : 'version ' + version + ' of rule ' + ruleName;
        return resultOf(new AMF_MatrixImpact(live).check(objectApiName, change == REPLACE ? ruleName : null, added, label));
    }

    /** The change asked for, or the one the request implies; null for one that is not a change. */
    private static String changeOf(String asked, AMF_RuleDefinition existing, String expression) {
        if (String.isNotBlank(asked)) {
            for (String change : new List<String>{ ADD, REPLACE, DEACTIVATE }) {
                if (change.equalsIgnoreCase(asked.trim())) {
                    return change;
                }
            }
            return null;
        }
        if (existing == null) {
            return ADD;
        }
        return String.isBlank(expression) ? DEACTIVATE : REPLACE;
    }

    private static Result resultOf(AMF_MatrixImpact.Report report) {
        Result result = new Result();
        result.ran = report.ran;
        result.summary = report.summary;
        result.checked = report.checked;
        result.changed = report.changed;
        result.skipped = report.skipped;
        result.changes = report.changes.isEmpty() ? null : String.join(report.changes, '\n');
        return result;
    }

    private static Result refused(String reason) {
        Result result = new Result();
        result.ran = false;
        result.checked = 0;
        result.changed = 0;
        result.skipped = 0;
        result.summary = AMF_AgentSupport.asSentence(reason) + ' Nothing was changed.';
        return result;
    }

    private static AMF_RuleProvider provider() {
        return ruleProviderOverride == null ? new AMF_CmdtRuleProvider() : ruleProviderOverride;
    }
}
