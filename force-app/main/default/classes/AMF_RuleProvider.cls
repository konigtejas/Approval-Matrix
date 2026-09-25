/**
 * The only sanctioned way for framework code to read the routing matrix.
 *
 * Architecture section: 3.1 (the matrix), 10 (testability).
 *
 * Engine classes depend on this interface and never query Approval_Matrix_Rule__mdt
 * directly. Custom Metadata cannot be inserted in a test, so this indirection is
 * what makes the engine testable at all -- arch doc 10 calls it non-negotiable
 * rather than a nicety, and CLAUDE.md repeats it as a hard convention.
 *
 * Implementations: AMF_CmdtRuleProvider in production, AMF_RuleBuilder.Stub in tests.
 */
public interface AMF_RuleProvider {

    /**
     * @return Every active rule across every governed object, in deterministic
     *         order. This lets configuration-wide tooling inspect the same CMDT
     *         view as the engine without bypassing this interface.
     */
    List<AMF_RuleDefinition> getActiveRules();

    /**
     * @param objectApiName API name of the governed object.
     * @return That object's active rules, ascending by Priority__c with ties
     *         broken on DeveloperName. Empty list when the object has no active
     *         rules, which is also how arch doc 3.2 defines "not governed" --
     *         never null.
     */
    List<AMF_RuleDefinition> getActiveRules(String objectApiName);
}
