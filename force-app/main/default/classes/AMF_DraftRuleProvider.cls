/**
 * The live matrix with one change applied, in memory (M15): a rule added, a rule
 * replaced by a new version of itself, or a rule taken out.
 *
 * Architecture section: 3.1 (the matrix), 6.4 (preview, and its M15 note),
 * 10 (testability).
 *
 * The admin assistant's impact check previews the same records twice through
 * the engine: once over the live matrix, once over this. The engine then
 * decides both answers by its own rule order, compilation and first-match walk,
 * so the comparison is between two matrices, not between the engine and a
 * second evaluator. Nothing is deployed: the change exists only in this object.
 *
 * A replacement must carry a new Version__c. AMF_ExprCache keys compiled
 * expressions on DeveloperName and version (4.5), so a replacement at the live
 * version would be served the live rule's compiled expression within the same
 * transaction. The constructor refuses one.
 *
 * Reads the live matrix through the AMF_RuleProvider it wraps, so CMDT access
 * stays behind the interface (CLAUDE.md).
 */
public with sharing class AMF_DraftRuleProvider implements AMF_RuleProvider {

    private final AMF_RuleProvider live;
    private final String removedRule;
    private final AMF_RuleDefinition addedRule;

    /**
     * @param live        The matrix the change applies to.
     * @param removedRule DeveloperName of the active rule to take out, or null.
     *                    With addedRule of the same name, a replacement.
     * @param addedRule   The rule to put in, or null to only take one out.
     * @throws AMF_ConfigurationException For no change at all, or a
     *         replacement at the version it replaces.
     */
    public AMF_DraftRuleProvider(AMF_RuleProvider live, String removedRule, AMF_RuleDefinition addedRule) {
        if (String.isBlank(removedRule) && addedRule == null) {
            throw new AMF_ConfigurationException('A draft matrix needs a rule to add, replace or take out.');
        }

        if (addedRule != null && String.isNotBlank(removedRule) && addedRule.developerName == removedRule) {
            for (AMF_RuleDefinition rule : live.getActiveRules(addedRule.objectApiName)) {
                if (rule.developerName == removedRule && rule.version == addedRule.version) {
                    throw new AMF_ConfigurationException(
                        'A new version of ' + removedRule + ' must have a version other than the live one, ' +
                        rule.version + '.'
                    );
                }
            }
        }

        this.live = live;
        this.removedRule = removedRule;
        this.addedRule = addedRule;
    }

    /** @return Every object's active rules, with the change applied, in deterministic order. */
    public List<AMF_RuleDefinition> getActiveRules() {
        return applied(live.getActiveRules(), null);
    }

    /** @return The object's active rules, with the change applied, ascending by priority. */
    public List<AMF_RuleDefinition> getActiveRules(String objectApiName) {
        return applied(live.getActiveRules(objectApiName), objectApiName);
    }

    private List<AMF_RuleDefinition> applied(List<AMF_RuleDefinition> rules, String objectApiName) {
        List<AMF_RuleDefinition> changed = new List<AMF_RuleDefinition>();

        for (AMF_RuleDefinition rule : rules == null ? new List<AMF_RuleDefinition>() : rules) {
            if (rule == null) {
                continue;
            }
            Boolean removed = String.isNotBlank(removedRule) && rule.developerName == removedRule;
            Boolean shadowed = addedRule != null && rule.developerName == addedRule.developerName;
            if (!removed && !shadowed) {
                changed.add(rule);
            }
        }

        if (addedRule != null && (objectApiName == null || addedRule.objectApiName == objectApiName)) {
            changed.add(addedRule);
        }

        changed.sort();
        return changed;
    }
}
