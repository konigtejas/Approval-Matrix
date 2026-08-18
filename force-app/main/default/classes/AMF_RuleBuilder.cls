/**
 * Fluent in-memory fixture for AMF_RuleDefinition, plus the stub AMF_RuleProvider
 * that serves those fixtures to code under test.
 *
 * Architecture section: 10 (testability).
 *
 * Custom Metadata cannot be inserted in a test, so without this pair every test
 * of the engine would depend on whichever rules happen to be deployed to the
 * org. CLAUDE.md states the rule flatly: tests use in-memory rule fixtures, with
 * zero dependence on org CMDT rows. The single exception is
 * AMF_CmdtRuleProviderTest, which has to read a real row to prove the >255
 * character SOQL round trip -- a platform behaviour no in-memory fixture can
 * demonstrate.
 *
 * Annotated @IsTest so it ships no production surface and cannot be called from
 * live code by accident. M2 and M3 build their engine fixtures on top of it.
 *
 * Usage:
 *   AMF_RuleDefinition r = new AMF_RuleBuilder()
 *       .named('High_Value')
 *       .withPriority(10)
 *       .withExpression('Amount__c > 100000')
 *       .build();
 */
@IsTest
public class AMF_RuleBuilder {

    private String developerName = 'Test_Rule';
    private String objectApiName = 'Purchase_Request__c';
    private Integer priority = 100;
    private String expression = 'TRUE';
    private String processApiName = 'PR_Two_Level_Mgmt';
    private String description = 'In-memory fixture rule.';
    private Integer version = 1;
    private Boolean isActive = true;

    public AMF_RuleBuilder named(String value) {
        this.developerName = value;
        return this;
    }

    public AMF_RuleBuilder forObject(String value) {
        this.objectApiName = value;
        return this;
    }

    public AMF_RuleBuilder withPriority(Integer value) {
        this.priority = value;
        return this;
    }

    public AMF_RuleBuilder withExpression(String value) {
        this.expression = value;
        return this;
    }

    public AMF_RuleBuilder routingTo(String value) {
        this.processApiName = value;
        return this;
    }

    public AMF_RuleBuilder describedAs(String value) {
        this.description = value;
        return this;
    }

    public AMF_RuleBuilder atVersion(Integer value) {
        this.version = value;
        return this;
    }

    public AMF_RuleBuilder inactive() {
        this.isActive = false;
        return this;
    }

    public AMF_RuleDefinition build() {
        return new AMF_RuleDefinition(
            developerName,
            objectApiName,
            priority,
            expression,
            processApiName,
            description,
            version,
            isActive
        );
    }

    /**
     * An AMF_RuleProvider backed by a list held in memory. Honours the same
     * contract as AMF_CmdtRuleProvider -- active rules for the requested object,
     * priority order -- so a test that swaps one for the other is testing its own
     * subject rather than the difference between two providers.
     */
    public class Stub implements AMF_RuleProvider {

        private final List<AMF_RuleDefinition> rules;

        public Stub(List<AMF_RuleDefinition> rules) {
            this.rules = rules == null ? new List<AMF_RuleDefinition>() : rules;
        }

        public List<AMF_RuleDefinition> getActiveRules(String objectApiName) {
            List<AMF_RuleDefinition> matched = new List<AMF_RuleDefinition>();
            for (AMF_RuleDefinition rule : rules) {
                if (rule.isActive == true && rule.objectApiName == objectApiName) {
                    matched.add(rule);
                }
            }
            matched.sort();
            return matched;
        }
    }
}
