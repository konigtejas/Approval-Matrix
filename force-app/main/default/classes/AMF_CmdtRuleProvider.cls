/**
 * Loads the routing matrix from Approval_Matrix_Rule__mdt, by SOQL.
 *
 * Architecture section: 3.1.
 *
 * CRITICAL -- this class must never use getAll() or getInstance(). Both truncate
 * Long Text Area fields to 255 characters, which would silently corrupt
 * Expression__c: a long expression would come back chopped mid-token, and the
 * framework would either fail to compile it or, worse, compile a shorter
 * expression that means something else. Nothing anywhere would report an error.
 *
 * Measured on amf-dev against the PR_Long_Expression_Pin fixture, whose
 * expression is 290 characters:
 *
 *     SOQL          -> 290 characters, intact
 *     getInstance() -> 255 characters, cut inside "(Risk_Level"
 *     getAll()      -> 255 characters, cut inside "(Risk_Level"
 *
 * AMF_CmdtRuleProviderTest pins both halves of that result. There is no
 * performance argument for the cached accessors either: Custom Metadata SOQL
 * consumes no query rows and no query count.
 *
 * Ordering is applied in Apex, never in SOQL. CMDT SOQL rejects ORDER BY on a
 * parent relationship field (technical log 1.4f), and arch doc 6.1 step 2
 * depends on the order being deterministic, so AMF_RuleDefinition.compareTo owns it.
 */
public with sharing class AMF_CmdtRuleProvider implements AMF_RuleProvider {

    /**
     * @param objectApiName API name of the governed object.
     * @return That object's active rules in priority order. Never null.
     */
    public List<AMF_RuleDefinition> getActiveRules(String objectApiName) {
        return load(objectApiName, true);
    }

    /**
     * Single load path, shared so the active and all-rules cases cannot drift
     * apart in their field list or their ordering.
     *
     * Exposed to tests only so AMF_CmdtRuleProviderTest can reach the inactive
     * PR_Long_Expression_Pin fixture, which exists precisely so that the >255
     * character round trip can be proven without an active rule that routes
     * nowhere. The public interface stays a single method.
     *
     * @param objectApiName API name of the governed object.
     * @param activeOnly    False to include inactive rules.
     * @return Matching rules in priority order. Never null.
     */
    @TestVisible
    private static List<AMF_RuleDefinition> load(String objectApiName, Boolean activeOnly) {
        List<AMF_RuleDefinition> rules = new List<AMF_RuleDefinition>();

        for (Approval_Matrix_Rule__mdt row : [
            SELECT DeveloperName,
                   Object_API_Name__c,
                   Priority__c,
                   Expression__c,
                   Process_API_Name__c,
                   Description__c,
                   Version__c,
                   Active__c
            FROM Approval_Matrix_Rule__mdt
            WHERE Object_API_Name__c = :objectApiName
        ]) {
            if (activeOnly && row.Active__c != true) {
                continue;
            }
            rules.add(new AMF_RuleDefinition(
                row.DeveloperName,
                row.Object_API_Name__c,
                row.Priority__c == null ? null : row.Priority__c.intValue(),
                row.Expression__c,
                row.Process_API_Name__c,
                row.Description__c,
                row.Version__c == null ? null : row.Version__c.intValue(),
                row.Active__c
            ));
        }

        rules.sort();
        return rules;
    }
}
