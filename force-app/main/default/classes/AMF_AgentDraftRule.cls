/**
 * The Approval Matrix Admin Assistant's Draft Matrix Rule action (M15): one rule
 * drafted from an administrator's description, returned only if it passes the
 * checks the release gate would run.
 *
 * Architecture section: 7 (entry points, and its M15 note), 1 (principle 6),
 * 9 (configuration validator).
 *
 * AMF_RuleDrafter does the work: the model's draft, then the compiler, the
 * name, the priority, the process and the engine's query, with one corrected
 * attempt. This action reads the object the administrator named, and answers
 * every request: a refusal comes back with Valid false and the reasons in
 * Summary. Nothing is written or deployed. A valid draft carries the Custom
 * Metadata file to commit, and the administrator releases it through source.
 *
 * Granted by Approval_Matrix_Admin alone.
 */
public with sharing class AMF_AgentDraftRule {

    /** One rule to draft. */
    public class Request {
        @InvocableVariable(
            label='Object'
            description='The kind of record the rule is for, such as Purchase Request or Opportunity.'
            required=true
        )
        public String objectName;

        @InvocableVariable(
            label='Request'
            description='The rule the administrator wants, in their own words: which records it should catch, and which approval process they should go to.'
            required=true
        )
        public String ruleRequest;

        @InvocableVariable(
            label='Rule To Change'
            description='Optional: the DeveloperName of an active rule to write a new version of. Leave empty for a new rule.'
        )
        public String ruleToChange;
    }

    /** The checked draft, or why there is none. */
    public class Result {
        @InvocableVariable(label='Valid' description='True when the draft passed every check; false when Summary says why there is none.')
        public Boolean valid;

        @InvocableVariable(label='Summary' description='The draft, or the refusal, in plain English, ready to give the administrator.')
        public String summary;

        @InvocableVariable(label='Object API Name' description='The object the rule governs.')
        public String objectApiName;

        @InvocableVariable(label='Rule Name' description='The rule\'s DeveloperName.')
        public String developerName;

        @InvocableVariable(label='Label' description='The rule\'s label.')
        public String ruleLabel;

        /** As text, so the agent can carry it into Check Rule Impact through a text variable. */
        @InvocableVariable(label='Priority' description='The rule\'s priority, as a whole number. Rules are tried lowest number first.')
        public String priority;

        @InvocableVariable(label='Condition' description='The rule\'s condition, in the matrix\'s expression language.')
        public String expression;

        @InvocableVariable(label='Process' description='The approval process the rule sends records to.')
        public String processApiName;

        @InvocableVariable(label='Description' description='What the rule is for.')
        public String ruleDescription;

        @InvocableVariable(label='Version' description='The rule\'s version: 1 for a new rule, one more than the live version for a change.')
        public Integer ruleVersion;

        @InvocableVariable(label='Change' description='Add for a new rule, Replace for a new version of an active rule.')
        public String changeType;

        @InvocableVariable(label='Assumptions' description='What the model assumed in drafting, in its own words, for the administrator to check.')
        public String assumptions;

        @InvocableVariable(label='File Path' description='Where the rule\'s Custom Metadata file goes in source.')
        public String filePath;

        @InvocableVariable(label='Metadata' description='The rule\'s Custom Metadata file, ready to commit.')
        public String metadataXml;
    }

    /**
     * Test seams: tests set these so the action drafts over in-memory rules with
     * a stub model. Always null in production.
     */
    @TestVisible
    private static AMF_RuleDrafter drafterOverride;
    @TestVisible
    private static AMF_RuleProvider ruleProviderOverride;

    /**
     * @param requests One per rule.
     * @return One result per request, in the same order. Never throws for a request.
     */
    @InvocableMethod(
        label='Draft Matrix Rule'
        description='Drafts one approval matrix rule from a description, and returns it only if it compiles and passes the release checks. Changes nothing: the administrator releases the draft through source.'
        category='Approval Matrix'
    )
    public static List<Result> draftRules(List<Request> requests) {
        List<Result> results = new List<Result>();

        if (requests == null) {
            return results;
        }
        for (Request request : requests) {
            results.add(draftOne(request));
        }
        return results;
    }

    private static Result draftOne(Request request) {
        Result result = new Result();
        result.valid = false;

        String objectApiName = AMF_AgentSupport.governedObjectNamed(request?.objectName, provider());
        if (objectApiName == null) {
            result.summary =
                (String.isBlank(request?.objectName) ? 'No object was named' : '"' + request.objectName.trim().abbreviate(60) + '" is not a kind of record the approval matrix governs') +
                ', so no rule was drafted. Name a governed object, such as Purchase Request or Opportunity. Nothing was changed.';
            return result;
        }

        AMF_RuleDrafter.Draft draft;
        try {
            draft = drafter().draft(objectApiName, request.ruleRequest, request.ruleToChange);
        } catch (AMF_PromptException e) {
            result.objectApiName = objectApiName;
            result.summary = e.getMessage();
            return result;
        }

        result.valid = draft.valid;
        result.summary = draft.summary;
        result.objectApiName = draft.objectApiName;
        if (draft.valid) {
            result.developerName = draft.developerName;
            result.ruleLabel = draft.label;
            result.priority = String.valueOf(draft.priority);
            result.expression = draft.expression;
            result.processApiName = draft.processApiName;
            result.ruleDescription = draft.description;
            result.ruleVersion = draft.version;
            result.changeType = draft.mode;
            result.assumptions = draft.assumptions;
            result.filePath = draft.filePath;
            result.metadataXml = draft.metadataXml;
        }
        return result;
    }

    private static AMF_RuleDrafter drafter() {
        return drafterOverride == null ? new AMF_RuleDrafter() : drafterOverride;
    }

    private static AMF_RuleProvider provider() {
        return ruleProviderOverride == null ? new AMF_CmdtRuleProvider() : ruleProviderOverride;
    }
}
