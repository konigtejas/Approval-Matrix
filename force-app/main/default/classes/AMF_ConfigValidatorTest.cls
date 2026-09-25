/**
 * Unit tests for AMF_ConfigValidator. Rules and approval processes are both
 * injected in memory, so the tests prove validator behavior without depending
 * on deployed CMDT rows or ProcessDefinition records. The static entry points
 * are driven through AMF_ConfigValidator.entryPointOverride for the same reason.
 *
 * Architecture section: 9, 10.
 */
@IsTest
private class AMF_ConfigValidatorTest {

    private static final String OBJECT_NAME = 'Purchase_Request__c';
    private static final String VALID_PROCESS = 'PR_Two_Level_Mgmt';

    @IsTest
    static void aValidClassicMatrixProducesNoFindings() {
        List<AMF_ConfigValidator.Finding> findings = validator(
            new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder()
                    .named('PR_Catch_All')
                    .withPriority(9999)
                    .withExpression('TRUE')
                    .routingTo(VALID_PROCESS)
                    .build()
            },
            activeProcesses(OBJECT_NAME, new Set<String>{ VALID_PROCESS })
        ).validate();

        Assert.areEqual(0, findings.size(), render(findings));
    }

    @IsTest
    static void invalidExpressionsAreReportedWithTheirRuleAndPosition() {
        List<AMF_ConfigValidator.Finding> findings = validator(
            new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder()
                    .named('PR_Broken')
                    .withExpression('Not_A_Field__c == \'x\'')
                    .routingTo(VALID_PROCESS)
                    .build()
            },
            activeProcesses(OBJECT_NAME, new Set<String>{ VALID_PROCESS })
        ).validate();

        AMF_ConfigValidator.Finding finding = findingWithCode(findings, 'EXPRESSION_INVALID');
        Assert.isNotNull(finding, render(findings));
        Assert.isTrue(finding.message.contains('PR_Broken'), finding.message);
        Assert.isTrue(finding.message.contains('position'), finding.message);
    }

    @IsTest
    static void duplicatePrioritiesAndMissingProcessesAreBothReported() {
        List<AMF_ConfigValidator.Finding> findings = validator(
            new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder()
                    .named('PR_First')
                    .withPriority(10)
                    .routingTo('Missing_Process')
                    .build(),
                new AMF_RuleBuilder()
                    .named('PR_Second')
                    .withPriority(10)
                    .routingTo(VALID_PROCESS)
                    .build()
            },
            activeProcesses(OBJECT_NAME, new Set<String>{ VALID_PROCESS })
        ).validate();

        AMF_ConfigValidator.Finding duplicate = findingWithCode(findings, 'DUPLICATE_PRIORITY');
        Assert.isNotNull(duplicate, render(findings));
        Assert.isTrue(duplicate.message.contains('PR_First'), duplicate.message);
        Assert.isTrue(duplicate.message.contains('PR_Second'), duplicate.message);

        AMF_ConfigValidator.Finding missing = findingWithCode(findings, 'PROCESS_NOT_ACTIVE');
        Assert.isNotNull(missing, render(findings));
        Assert.isTrue(missing.message.contains('Missing_Process'), missing.message);
    }

    @IsTest
    static void missingPrioritiesAndWhitespaceInProcessNamesAreRejected() {
        List<AMF_ConfigValidator.Finding> findings = validator(
            new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder()
                    .named('PR_Unordered')
                    .withPriority(null)
                    .routingTo(' ' + VALID_PROCESS + ' ')
                    .build()
            },
            activeProcesses(OBJECT_NAME, new Set<String>{ VALID_PROCESS })
        ).validate();

        Assert.isNotNull(findingWithCode(findings, 'PRIORITY_MISSING'), render(findings));
        Assert.isNotNull(findingWithCode(findings, 'PROCESS_API_NAME_WHITESPACE'), render(findings));
        Assert.isNull(
            findingWithCode(findings, 'PROCESS_NOT_ACTIVE'),
            'Whitespace must be reported as the root cause rather than as a misleading missing process.'
        );
    }

    @IsTest
    static void aGovernedObjectWithoutTheGuardFieldIsRejected() {
        List<AMF_ConfigValidator.Finding> findings = validator(
            new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder()
                    .named('Account_Rule')
                    .forObject('Account')
                    .withExpression('Name == \'Acme\'')
                    .routingTo('Account_Approval')
                    .build()
            },
            activeProcesses('Account', new Set<String>{ 'Account_Approval' })
        ).validate();

        AMF_ConfigValidator.Finding finding = findingWithCode(findings, 'GUARD_FIELD_MISSING');
        Assert.isNotNull(finding, render(findings));
        Assert.isTrue(finding.message.contains('Account'), finding.message);
    }

    @IsTest
    static void assertValidFailsWithTheCompleteReport() {
        AMF_ConfigValidator validator = validator(
            new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder()
                    .named('PR_No_Process')
                    .routingTo(null)
                    .build()
            },
            activeProcesses(OBJECT_NAME, new Set<String>())
        );

        try {
            validator.assertValid();
            Assert.fail('An invalid matrix must fail the post-deploy gate.');
        } catch (AMF_ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('PROCESS_API_NAME_MISSING'), e.getMessage());
            Assert.isTrue(e.getMessage().contains('PR_No_Process'), e.getMessage());
        }
    }

    @IsTest
    static void anUnknownObjectIsReportedAtItsRootWithoutProcessNoise() {
        List<AMF_ConfigValidator.Finding> findings = validator(
            new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder()
                    .named('Ghost_Rule')
                    .forObject('Not_An_Object__c')
                    .build()
            },
            activeProcesses(OBJECT_NAME, new Set<String>{ VALID_PROCESS })
        ).validate();

        Assert.isNotNull(findingWithCode(findings, 'OBJECT_NOT_FOUND'), render(findings));
        Assert.isNull(
            findingWithCode(findings, 'PROCESS_NOT_ACTIVE'),
            'A missing object is the root cause; a follow-on process finding would only be noise.'
        );
    }

    @IsTest
    static void aProviderThatBreaksItsContractIsReportedRatherThanTrusted() {
        List<AMF_ConfigValidator.Finding> findings = new AMF_ConfigValidator(
            new RawRuleProvider(new List<AMF_RuleDefinition>{
                null,
                new AMF_RuleBuilder().named('PR_Switched_Off').inactive().build(),
                new AMF_RuleBuilder().named('PR_No_Object').forObject(' ').build()
            }),
            activeProcesses(OBJECT_NAME, new Set<String>{ VALID_PROCESS })
        ).validate();

        Assert.isNotNull(findingWithCode(findings, 'NULL_RULE'), render(findings));
        Assert.isNotNull(findingWithCode(findings, 'INACTIVE_RULE_RETURNED'), render(findings));
        Assert.isNotNull(findingWithCode(findings, 'OBJECT_API_NAME_MISSING'), render(findings));
        Assert.areEqual(3, findings.size(), render(findings));
    }

    @IsTest
    static void aProviderThatReturnsNullIsReportedRatherThanDereferenced() {
        List<AMF_ConfigValidator.Finding> findings = new AMF_ConfigValidator(
            new RawRuleProvider(null),
            activeProcesses(OBJECT_NAME, new Set<String>())
        ).validate();

        Assert.areEqual(1, findings.size(), render(findings));
        Assert.areEqual('RULE_PROVIDER_RETURNED_NULL', findings[0].code);
    }

    @IsTest
    static void validateOrThrowFailsTheCiGateWithTheCompleteReport() {
        AMF_ConfigValidator.entryPointOverride = invalidMatrix();

        try {
            AMF_ConfigValidator.validateOrThrow();
            Assert.fail('scripts/validate-config.apex must fail on an invalid matrix.');
        } catch (AMF_ConfigurationException e) {
            Assert.isTrue(
                e.getMessage().startsWith('Approval Matrix configuration is invalid:'),
                e.getMessage()
            );
            Assert.isTrue(e.getMessage().contains('PROCESS_NOT_ACTIVE'), e.getMessage());
        }
    }

    @IsTest
    static void validateOrThrowPassesAValidMatrix() {
        AMF_ConfigValidator.entryPointOverride = validMatrix();

        AMF_ConfigValidator.validateOrThrow();

        Assert.isTrue(true, 'Reaching this line is the assertion: a valid matrix must not throw.');
    }

    @IsTest
    static void theFlowActionReturnsTheReportByDefault() {
        AMF_ConfigValidator.entryPointOverride = invalidMatrix();

        AMF_ConfigValidator.InvocationRequest unset = new AMF_ConfigValidator.InvocationRequest();
        AMF_ConfigValidator.InvocationRequest explicitFalse = new AMF_ConfigValidator.InvocationRequest();
        explicitFalse.failOnError = false;

        List<AMF_ConfigValidator.InvocationResult> results = AMF_ConfigValidator.validateFromFlow(
            new List<AMF_ConfigValidator.InvocationRequest>{ unset, explicitFalse }
        );

        Assert.areEqual(2, results.size(), 'The invocable must return one result per request.');
        for (AMF_ConfigValidator.InvocationResult result : results) {
            Assert.isFalse(result.isValid);
            Assert.areEqual(1, result.errorCount, result.errors);
            Assert.isTrue(result.errors.contains('PROCESS_NOT_ACTIVE'), result.errors);
        }
    }

    @IsTest
    static void theFlowActionReportsAValidMatrix() {
        AMF_ConfigValidator.entryPointOverride = validMatrix();

        List<AMF_ConfigValidator.InvocationResult> results = AMF_ConfigValidator.validateFromFlow(
            new List<AMF_ConfigValidator.InvocationRequest>{ new AMF_ConfigValidator.InvocationRequest() }
        );

        Assert.areEqual(1, results.size());
        Assert.isTrue(results[0].isValid);
        Assert.areEqual(0, results[0].errorCount);
        Assert.areEqual('', results[0].errors);
    }

    @IsTest
    static void theFlowActionThrowsWhenAskedToFailOnError() {
        AMF_ConfigValidator.entryPointOverride = invalidMatrix();

        AMF_ConfigValidator.InvocationRequest request = new AMF_ConfigValidator.InvocationRequest();
        request.failOnError = true;

        try {
            AMF_ConfigValidator.validateFromFlow(
                new List<AMF_ConfigValidator.InvocationRequest>{ request }
            );
            Assert.fail('failOnError = true must fail the post-deploy Flow on an invalid matrix.');
        } catch (AMF_ConfigurationException e) {
            Assert.isTrue(e.getMessage().contains('PROCESS_NOT_ACTIVE'), e.getMessage());
        }
    }

    @IsTest
    static void theFlowActionDoesNothingForAnEmptyCall() {
        AMF_ConfigValidator.entryPointOverride = invalidMatrix();

        Assert.areEqual(0, AMF_ConfigValidator.validateFromFlow(null).size());
        Assert.areEqual(
            0,
            AMF_ConfigValidator.validateFromFlow(new List<AMF_ConfigValidator.InvocationRequest>()).size()
        );
    }

    @IsTest
    static void productionWiringConstructsWithoutQuerying() {
        AMF_ConfigValidator production = new AMF_ConfigValidator();

        Assert.isNotNull(production);
        Assert.areEqual(0, Limits.getQueries(), 'Construction must be free; queries belong to validate().');
    }

    private static AMF_ConfigValidator validMatrix() {
        return validator(
            new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder().named('PR_Catch_All').withPriority(9999).routingTo(VALID_PROCESS).build()
            },
            activeProcesses(OBJECT_NAME, new Set<String>{ VALID_PROCESS })
        );
    }

    private static AMF_ConfigValidator invalidMatrix() {
        return validator(
            new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder().named('PR_Catch_All').withPriority(9999).routingTo('Missing_Process').build()
            },
            activeProcesses(OBJECT_NAME, new Set<String>{ VALID_PROCESS })
        );
    }

    private static AMF_ConfigValidator validator(
        List<AMF_RuleDefinition> rules,
        AMF_ApprovalProcessProvider processProvider
    ) {
        return new AMF_ConfigValidator(new AMF_RuleBuilder.Stub(rules), processProvider);
    }

    private static AMF_ApprovalProcessProvider activeProcesses(
        String objectApiName,
        Set<String> processNames
    ) {
        return new ApprovalProcessStub(
            new Map<String, Set<String>>{ objectApiName => processNames }
        );
    }

    private static AMF_ConfigValidator.Finding findingWithCode(
        List<AMF_ConfigValidator.Finding> findings,
        String code
    ) {
        for (AMF_ConfigValidator.Finding finding : findings) {
            if (finding.code == code) {
                return finding;
            }
        }
        return null;
    }

    private static String render(List<AMF_ConfigValidator.Finding> findings) {
        List<String> messages = new List<String>();
        for (AMF_ConfigValidator.Finding finding : findings) {
            messages.add(finding.render());
        }
        return String.join(messages, '\n');
    }

    /**
     * Returns its list verbatim -- nulls, inactive rules and all -- so the
     * validator's defences against a contract-breaking provider can be proven.
     * AMF_RuleBuilder.Stub honours the contract and so cannot reach them.
     */
    private class RawRuleProvider implements AMF_RuleProvider {
        private final List<AMF_RuleDefinition> rules;

        private RawRuleProvider(List<AMF_RuleDefinition> rules) {
            this.rules = rules;
        }

        public List<AMF_RuleDefinition> getActiveRules() {
            return rules;
        }

        public List<AMF_RuleDefinition> getActiveRules(String objectApiName) {
            return rules;
        }
    }

    private class ApprovalProcessStub implements AMF_ApprovalProcessProvider {
        private final Map<String, Set<String>> activeByObject;

        private ApprovalProcessStub(Map<String, Set<String>> activeByObject) {
            this.activeByObject = activeByObject;
        }

        public Set<String> getActiveApprovalProcessNames(
            String objectApiName,
            Set<String> developerNames
        ) {
            Set<String> matching = new Set<String>();
            Set<String> active = activeByObject.get(objectApiName);

            if (active == null || developerNames == null) {
                return matching;
            }

            for (String developerName : developerNames) {
                if (active.contains(developerName)) {
                    matching.add(developerName);
                }
            }
            return matching;
        }
    }
}
