/**
 * The Claude connector's check_rule_draft tool (M16, administrators): runs every
 * release check on a matrix rule Claude has drafted, and returns the Custom
 * Metadata file to commit only when it passes. It routes nothing and writes
 * nothing.
 *
 * Architecture section: 1 (principle 6), 7 (its M15 and M16 notes), 9 (the
 * checks, and their M15 note).
 *
 * CLAUDE'S DRAFT, THE DRAFTER'S CHECKS. AMF_RuleDrafter (M15) checks a model's
 * JSON answer exactly as the release gate would: the condition compiles against
 * the object; the DeveloperName is valid and new, or the rule being changed; the
 * priority is a free whole number from 1 to 9999; the process is an active
 * Classic process for the object; the description and condition are within the
 * metadata's limits; and the engine's union query, with the draft in the
 * matrix, runs. Here the answer is Claude's: a runner hands the drafter the
 * draft as its model's answer, so every one of those checks runs unchanged, and
 * the file exists only for a draft that passed them. The administrator then
 * releases it through source, the source gate, a deploy and the post-deploy
 * check (principle 1); nothing here can.
 *
 * Known limit, as for the Admin Assistant: a name is checked against active
 * rules only, because AMF_RuleProvider exposes no others (decisions, M15).
 */
global with sharing class AMF_McpCheckRuleDraft {

    /** Test seam: the matrix, as in-memory rules. Always null in production. */
    @TestVisible
    private static AMF_RuleProvider ruleProviderOverride;

    /** A draft to check. */
    global class Request {
        @InvocableVariable(label='Object' description='The kind of record the rule is for, such as Purchase Request, or its API name.' required=true)
        global String objectName;

        @InvocableVariable(label='Request' description='What the administrator asked for, in their words.' required=true)
        global String ruleRequest;

        @InvocableVariable(
            label='Rule To Change'
            description='Optional: the DeveloperName of the active rule this draft is a new version of. Empty for a new rule.'
        )
        global String ruleToChange;

        @InvocableVariable(label='Developer Name' description='The rule\'s DeveloperName, such as PR_EMEA_Over_500k.' required=true)
        global String developerName;

        @InvocableVariable(label='Label' description='The rule\'s label, at most 40 characters.')
        global String label;

        @InvocableVariable(label='Priority' description='The rule\'s priority, a whole number from 1 to 9998.' required=true)
        global Integer priority;

        @InvocableVariable(label='Condition' description='The rule\'s condition, in the matrix\'s expression language.' required=true)
        global String expression;

        @InvocableVariable(label='Process' description='The API name of the approval process the rule sends records to.' required=true)
        global String processApiName;

        @InvocableVariable(label='Description' description='One sentence, at most 255 characters, saying what the rule is for.' required=true)
        global String ruleDescription;

        @InvocableVariable(label='Assumptions' description='Optional: what was assumed in drafting it, or None.')
        global String assumptions;
    }

    /** The checked draft. */
    global class Result {
        @InvocableVariable(label='Valid' description='True only when the draft passed every release check.')
        global Boolean valid;

        @InvocableVariable(
            label='Summary'
            description='The checked draft in plain English, with where it would sit in the priority order; or why it was refused.'
        )
        global String summary;

        @InvocableVariable(label='Problems' description='When not valid: each check it failed, one per line. Correct every one and check again.')
        global String problems;

        @InvocableVariable(label='Object API Name' description='The governed object the rule is for.')
        global String objectApiName;

        @InvocableVariable(label='Developer Name' description='The rule\'s DeveloperName.')
        global String developerName;

        @InvocableVariable(label='Label' description='The rule\'s label.')
        global String label;

        @InvocableVariable(label='Priority' description='The rule\'s priority.')
        global Integer priority;

        @InvocableVariable(label='Condition' description='The rule\'s condition.')
        global String expression;

        @InvocableVariable(label='Process' description='The approval process the rule sends records to.')
        global String processApiName;

        @InvocableVariable(label='Description' description='What the rule is for.')
        global String ruleDescription;

        @InvocableVariable(label='Version' description='1 for a new rule; one more than the live version for a change.')
        global Integer ruleVersion;

        @InvocableVariable(label='Change Type' description='Add for a new rule, Replace for a new version of an active one.')
        global String changeType;

        @InvocableVariable(label='File Path' description='Where the Custom Metadata file goes in the repository. Set only when valid.')
        global String filePath;

        @InvocableVariable(label='Metadata' description='The Custom Metadata file to commit, in the repository\'s format. Set only when valid.')
        global String metadataXml;
    }

    /**
     * @param requests One per draft; an MCP call sends one.
     * @return One result per request, in the same order.
     */
    @InvocableMethod(
        label='Check Rule Draft (Claude)'
        description='Runs every release check on a drafted approval matrix rule and returns its Custom Metadata file only when it passes. Changes nothing: the administrator releases the rule through source.'
        category='Approval Matrix'
    )
    global static List<Result> check(List<Request> requests) {
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
        Result result = new Result();
        result.valid = false;

        AMF_RuleProvider provider = provider();
        String objectApiName = AMF_AgentSupport.governedObjectNamed(request?.objectName, provider);
        if (objectApiName == null) {
            result.summary =
                (String.isBlank(request?.objectName)
                    ? 'No object was named'
                    : '"' + request.objectName.trim().abbreviate(60) + '" is not a kind of record the approval matrix governs') +
                ', so the draft was not checked. Name a governed object, such as Purchase Request or Opportunity.';
            return result;
        }
        result.objectApiName = objectApiName;

        String answer = JSON.serialize(
            new Map<String, Object>{
                'developerName' => request.developerName,
                'label' => request.label,
                'priority' => request.priority,
                'expression' => request.expression,
                'processApiName' => request.processApiName,
                'description' => request.ruleDescription,
                'assumptions' => request.assumptions
            }
        );

        AMF_RuleDrafter.Draft draft;
        try {
            draft = new AMF_RuleDrafter(provider, new GivenAnswer(answer))
                .draft(objectApiName, request.ruleRequest, request.ruleToChange);
        } catch (AMF_PromptException e) {
            result.summary = e.getMessage();
            return result;
        }

        result.valid = draft.valid == true;
        result.summary = draft.summary;
        result.problems = draft.problems == null || draft.problems.isEmpty() ? null : String.join(draft.problems, '\n');
        result.developerName = draft.developerName;
        result.label = draft.label;
        result.priority = draft.priority;
        result.expression = draft.expression;
        result.processApiName = draft.processApiName;
        result.ruleDescription = draft.description;
        if (result.valid) {
            result.ruleVersion = draft.version;
            result.changeType = draft.mode;
            result.filePath = draft.filePath;
            result.metadataXml = draft.metadataXml;
        }
        return result;
    }

    private static AMF_RuleProvider provider() {
        return ruleProviderOverride == null ? new AMF_CmdtRuleProvider() : ruleProviderOverride;
    }

    /**
     * Claude's draft, given to the drafter as its model's answer. The drafter
     * asks again with the reasons when a draft fails; the answer is the same,
     * so the second check refuses it for the same reasons, and Claude corrects
     * them in a new call.
     */
    private class GivenAnswer implements AMF_PromptRunner {
        private final String answer;

        private GivenAnswer(String answer) {
            this.answer = answer;
        }

        public String run(String templateName, Map<String, String> inputs) {
            return answer;
        }
    }
}
