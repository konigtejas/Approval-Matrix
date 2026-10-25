/**
 * In-memory view of one Approval_Matrix_Rule__mdt row: a complete routing
 * statement, "when this expression is true, use that process".
 *
 * Architecture section: 3.1 (the matrix), 6.1 step 2 (priority-ordered match).
 *
 * The DTO deliberately knows nothing about Custom Metadata. Mapping a __mdt row
 * onto this type is AMF_CmdtRuleProvider's job, and that separation is what lets
 * every other test build rules in memory (arch doc 10) without an org CMDT row
 * in sight -- which matters because Custom Metadata cannot be inserted in a test.
 *
 * Ordering lives here in compareTo rather than in the provider: arch doc 6.1
 * step 2 is "priority-ordered first match", so the order has to be deterministic
 * at every call site, and CMDT SOQL cannot supply it (technical log 1.4f).
 */
public class AMF_RuleDefinition implements Comparable {

    public String developerName { get; private set; }
    public String objectApiName { get; private set; }
    public Integer priority { get; private set; }
    public String expression { get; private set; }
    public String processApiName { get; private set; }
    public String description { get; private set; }
    public Integer version { get; private set; }
    public Boolean isActive { get; private set; }

    public AMF_RuleDefinition(
        String developerName,
        String objectApiName,
        Integer priority,
        String expression,
        String processApiName,
        String description,
        Integer version,
        Boolean isActive
    ) {
        this.developerName = developerName;
        this.objectApiName = objectApiName;
        this.priority = priority;
        this.expression = expression;
        this.processApiName = processApiName;
        this.description = description;
        this.version = version;
        this.isActive = isActive;
    }

    /**
     * Lower priority wins; equal priorities break on DeveloperName. That makes
     * the order total and reproducible across transactions, which is what arch
     * doc 3.1 means by "ordering is always deterministic".
     *
     * Nulls sort last rather than throwing. Priority__c and Version__c are
     * required on the CMDT so the provider cannot produce a null, but a
     * comparator that can NPE inside List.sort() is a landmine, and a total
     * order is not the same thing as swallowing an error.
     *
     * @param other The AMF_RuleDefinition to compare this one against.
     * @return Negative, zero or positive per the Comparable contract.
     */
    public Integer compareTo(Object other) {
        AMF_RuleDefinition that = (AMF_RuleDefinition) other;

        if (this.priority != that.priority) {
            if (this.priority == null) {
                return 1;
            }
            if (that.priority == null) {
                return -1;
            }
            return this.priority < that.priority ? -1 : 1;
        }

        if (this.developerName == that.developerName) {
            return 0;
        }
        if (this.developerName == null) {
            return 1;
        }
        if (that.developerName == null) {
            return -1;
        }
        return this.developerName.compareTo(that.developerName);
    }
}
