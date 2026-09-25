/**
 * Read seam for the active Classic approval-process catalog.
 *
 * Architecture section: 9 (configuration validator), 10 (testability).
 * The validator must prove that a rule names an active process for its governed
 * object, but ProcessDefinition records cannot be created in a unit test. This
 * interface keeps that platform query behind a replaceable boundary, just as
 * AMF_RuleProvider does for Custom Metadata.
 */
public interface AMF_ApprovalProcessProvider {

    /**
     * @param objectApiName   API name of the governed object.
     * @param developerNames  ProcessDefinition DeveloperNames to check.
     * @return Names from developerNames that are active Approval processes for
     *         objectApiName. Never null.
     */
    Set<String> getActiveApprovalProcessNames(
        String objectApiName,
        Set<String> developerNames
    );
}
