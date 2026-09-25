/**
 * Unit tests for AMF_ConfigValidator. Rules and approval processes are both
 * injected in memory, so the tests prove validator behavior without depending
 * on deployed CMDT rows or ProcessDefinition records.
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
