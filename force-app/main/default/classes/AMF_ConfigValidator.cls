/**
 * Validates the active Approval Matrix configuration before it is used.
 *
 * Architecture section: 9 (configuration validator), 4.6 (fail loudly), 10
 * (testability). A metadata deploy cannot execute Apex itself, so the release
 * pipeline runs scripts/validate-config.apex immediately after deployment.
 * This class is also an invocable action for an admin-owned post-deploy flow.
 *
 * CURRENT SCOPE: the MVP has Classic execution only, so this implementation
 * checks active Classic ProcessDefinition records. Flow validation joins this
 * class when the Flow strategy and Execution_Type__c are introduced.
 *
 * The entry-criteria guard is intentionally not inferred from ProcessDefinition:
 * Salesforce does not expose approval-process entry criteria to Apex SOQL. The
 * companion source gate validates the deployed XML's explicit guard predicate.
 */
public without sharing class AMF_ConfigValidator {

    @TestVisible
    private static final String GUARD_FIELD = 'Matrix_Submission__c';

    /** One concrete, administrator-actionable configuration defect. */
    public class Finding {
        public String code { get; private set; }
        public String message { get; private set; }

        private Finding(String code, String message) {
            this.code = code;
            this.message = message;
        }

        public String render() {
            return '[' + code + '] ' + message;
        }
    }

    /** Optional Flow input. Set true only when the caller wants an exception. */
    public class InvocationRequest {
        @InvocableVariable(
            label='Fail when configuration is invalid'
            description='When true, the action throws AMF_ConfigurationException if it finds errors.'
            required=false
        )
        public Boolean failOnError;
    }

    /** One Flow result per InvocationRequest. */
    public class InvocationResult {
        @InvocableVariable(label='Configuration is valid')
        public Boolean isValid;

        @InvocableVariable(label='Error count')
        public Integer errorCount;

        @InvocableVariable(label='Validation errors')
        public String errors;

        private InvocationResult(List<Finding> findings) {
            this.isValid = findings.isEmpty();
            this.errorCount = findings.size();
            this.errors = AMF_ConfigValidator.render(findings);
        }
    }

    /**
     * Test seam for the static entry points, which construct their own
     * validator: tests set this so validateOrThrow() and the invocable run
     * against in-memory fixtures instead of the org's deployed matrix. Always
     * null in production.
     */
    @TestVisible
    private static AMF_ConfigValidator entryPointOverride;

    private final AMF_RuleProvider ruleProvider;
    private final AMF_ApprovalProcessProvider approvalProcessProvider;

    /** Production wiring. */
    public AMF_ConfigValidator() {
        this(new AMF_CmdtRuleProvider(), new AMF_ClassicApprovalProcessProvider());
    }

    /** Test seam: unit tests supply in-memory rules and a process catalog stub. */
    public AMF_ConfigValidator(
        AMF_RuleProvider ruleProvider,
        AMF_ApprovalProcessProvider approvalProcessProvider
    ) {
        this.ruleProvider = ruleProvider;
        this.approvalProcessProvider = approvalProcessProvider;
    }

    /**
     * Runs every live-org check and returns all defects together, so an admin
     * can repair a configuration in one pass instead of discovering errors one
     * deploy at a time. This collection is a validator report, not an evaluator
     * fallback: no invalid rule is ever treated as false or allowed to route.
     */
    public List<Finding> validate() {
        List<Finding> findings = new List<Finding>();
        List<AMF_RuleDefinition> activeRules = ruleProvider.getActiveRules();

        if (activeRules == null) {
            findings.add(new Finding(
                'RULE_PROVIDER_RETURNED_NULL',
                'AMF_RuleProvider.getActiveRules() returned null; providers must return an empty list.'
            ));
            return findings;
        }

        Map<String, List<AMF_RuleDefinition>> rulesByObject = new Map<String, List<AMF_RuleDefinition>>();

        for (AMF_RuleDefinition rule : activeRules) {
            if (rule == null) {
                findings.add(new Finding(
                    'NULL_RULE',
                    'AMF_RuleProvider returned a null rule definition.'
                ));
                continue;
            }
            if (rule.isActive != true) {
                findings.add(new Finding(
                    'INACTIVE_RULE_RETURNED',
                    'AMF_RuleProvider returned inactive rule ' + nameOf(rule) + '.'
                ));
                continue;
            }
            if (String.isBlank(rule.objectApiName)) {
                findings.add(new Finding(
                    'OBJECT_API_NAME_MISSING',
                    'Rule ' + nameOf(rule) + ' has no Object_API_Name__c.'
                ));
                continue;
            }

            if (!rulesByObject.containsKey(rule.objectApiName)) {
                rulesByObject.put(rule.objectApiName, new List<AMF_RuleDefinition>());
            }
            rulesByObject.get(rule.objectApiName).add(rule);
        }

        List<String> objectApiNames = new List<String>(rulesByObject.keySet());
        objectApiNames.sort();

        for (String objectApiName : objectApiNames) {
            List<AMF_RuleDefinition> objectRules = rulesByObject.get(objectApiName);
            objectRules.sort();

            Boolean objectExists = validateGuardField(objectApiName, findings);
            validateRulesForObject(objectApiName, objectRules, findings);

            // A nonexistent object already has the useful root-cause finding.
            // Querying ProcessDefinition for it would only add noisy follow-ons.
            if (objectExists) {
                validateProcessesForObject(objectApiName, objectRules, findings);
            }
        }

        return findings;
    }

    /** Throws one complete report, for anonymous Apex and CI post-deploy gates. */
    public void assertValid() {
        List<Finding> findings = validate();
        if (!findings.isEmpty()) {
            throw new AMF_ConfigurationException(render(findings));
        }
    }

    /** Convenience entry point for scripts/validate-config.apex. */
    public static void validateOrThrow() {
        forEntryPoint().assertValid();
    }

    /**
     * Invocable form for a post-deploy Flow. It returns the report by default;
     * a caller can deliberately set failOnError to make the Flow fail fast.
     */
    @InvocableMethod(
        label='Validate Approval Matrix Configuration'
        description='Checks active matrix rules, their expressions, guard fields and active Classic approval processes.'
    )
    public static List<InvocationResult> validateFromFlow(List<InvocationRequest> requests) {
        List<InvocationResult> results = new List<InvocationResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        List<Finding> findings = forEntryPoint().validate();
        Boolean isValid = findings.isEmpty();

        for (InvocationRequest request : requests) {
            if (!isValid && request != null && request.failOnError == true) {
                throw new AMF_ConfigurationException(render(findings));
            }
            results.add(new InvocationResult(findings));
        }
        return results;
    }

    private static AMF_ConfigValidator forEntryPoint() {
        return entryPointOverride == null ? new AMF_ConfigValidator() : entryPointOverride;
    }

    /** @return True only when the governed type exists; guard defects are reported in either case. */
    private static Boolean validateGuardField(String objectApiName, List<Finding> findings) {
        Schema.SObjectType objectType = Schema.getGlobalDescribe().get(objectApiName);
        if (objectType == null) {
            findings.add(new Finding(
                'OBJECT_NOT_FOUND',
                'Governed object ' + objectApiName + ' does not exist or is not visible to the validator.'
            ));
            return false;
        }

        Schema.SObjectField guard = objectType.getDescribe().fields.getMap().get(GUARD_FIELD);
        if (guard == null) {
            findings.add(new Finding(
                'GUARD_FIELD_MISSING',
                'Governed object ' + objectApiName + ' lacks the required Checkbox field ' + GUARD_FIELD + '.'
            ));
            return true;
        }

        if (guard.getDescribe().getType() != Schema.DisplayType.BOOLEAN) {
            findings.add(new Finding(
                'GUARD_FIELD_WRONG_TYPE',
                'Field ' + objectApiName + '.' + GUARD_FIELD + ' must be a Checkbox.'
            ));
        }
        return true;
    }

    private static void validateRulesForObject(
        String objectApiName,
        List<AMF_RuleDefinition> rules,
        List<Finding> findings
    ) {
        Map<Integer, List<String>> namesByPriority = new Map<Integer, List<String>>();

        for (AMF_RuleDefinition rule : rules) {
            if (rule.priority == null) {
                findings.add(new Finding(
                    'PRIORITY_MISSING',
                    'Rule ' + nameOf(rule) + ' on ' + objectApiName + ' has no Priority__c.'
                ));
            } else {
                if (!namesByPriority.containsKey(rule.priority)) {
                    namesByPriority.put(rule.priority, new List<String>());
                }
                namesByPriority.get(rule.priority).add(nameOf(rule));
            }

            try {
                AMF_ExprCompiler.compile(objectApiName, rule.expression);
            } catch (AMF_ExpressionException e) {
                findings.add(new Finding(
                    'EXPRESSION_INVALID',
                    'Rule ' + nameOf(rule) + ' on ' + objectApiName + ' does not compile: ' + e.getMessage()
                ));
            }
        }

        List<Integer> priorities = new List<Integer>(namesByPriority.keySet());
        priorities.sort();
        for (Integer priority : priorities) {
            List<String> names = namesByPriority.get(priority);
            names.sort();
            if (names.size() > 1) {
                findings.add(new Finding(
                    'DUPLICATE_PRIORITY',
                    'Active rules ' + String.join(names, ', ') + ' on ' + objectApiName +
                    ' share Priority__c ' + priority + '. Active priorities must be unique.'
                ));
            }
        }
    }

    private void validateProcessesForObject(
        String objectApiName,
        List<AMF_RuleDefinition> rules,
        List<Finding> findings
    ) {
        Set<String> requestedNames = new Set<String>();

        for (AMF_RuleDefinition rule : rules) {
            if (String.isBlank(rule.processApiName)) {
                findings.add(new Finding(
                    'PROCESS_API_NAME_MISSING',
                    'Rule ' + nameOf(rule) + ' on ' + objectApiName + ' has no Process_API_Name__c.'
                ));
                continue;
            }
            if (rule.processApiName != rule.processApiName.trim()) {
                findings.add(new Finding(
                    'PROCESS_API_NAME_WHITESPACE',
                    'Rule ' + nameOf(rule) + ' on ' + objectApiName +
                    ' has leading or trailing whitespace in Process_API_Name__c.'
                ));
                continue;
            }
            requestedNames.add(rule.processApiName);
        }

        Set<String> activeNames = approvalProcessProvider.getActiveApprovalProcessNames(
            objectApiName,
            requestedNames
        );

        for (AMF_RuleDefinition rule : rules) {
            if (String.isBlank(rule.processApiName) || rule.processApiName != rule.processApiName.trim()) {
                continue;
            }
            if (!activeNames.contains(rule.processApiName)) {
                findings.add(new Finding(
                    'PROCESS_NOT_ACTIVE',
                    'Rule ' + nameOf(rule) + ' on ' + objectApiName + ' names ' +
                    rule.processApiName + ', but no active Approval Process with that DeveloperName exists for this object.'
                ));
            }
        }
    }

    private static String nameOf(AMF_RuleDefinition rule) {
        return String.isBlank(rule.developerName) ? '(unnamed rule)' : rule.developerName;
    }

    private static String render(List<Finding> findings) {
        if (findings == null || findings.isEmpty()) {
            return '';
        }

        List<String> lines = new List<String>{ 'Approval Matrix configuration is invalid:' };
        for (Finding finding : findings) {
            lines.add('- ' + finding.render());
        }
        return String.join(lines, '\n');
    }
}
