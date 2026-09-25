/**
 * Production catalog of active Classic approval processes.
 *
 * Architecture section: 9. ProcessDefinition exposes the process
 * DeveloperName, target object, type and activation state required for the
 * validator's live-org check. It deliberately returns only active records:
 * a deactivated template cannot be a safe routing destination.
 */
public without sharing class AMF_ClassicApprovalProcessProvider
    implements AMF_ApprovalProcessProvider {

    public Set<String> getActiveApprovalProcessNames(
        String objectApiName,
        Set<String> developerNames
    ) {
        Set<String> activeNames = new Set<String>();

        if (String.isBlank(objectApiName) || developerNames == null || developerNames.isEmpty()) {
            return activeNames;
        }

        for (ProcessDefinition definition : [
            SELECT DeveloperName
            FROM ProcessDefinition
            WHERE TableEnumOrId = :objectApiName
              AND Type = 'Approval'
              AND State = 'Active'
              AND DeveloperName IN :developerNames
        ]) {
            activeNames.add(definition.DeveloperName);
        }

        return activeNames;
    }
}
