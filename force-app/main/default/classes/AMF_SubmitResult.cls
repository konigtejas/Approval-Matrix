/**
 * What a submission strategy hands back: the record it submitted, and the
 * execution reference that submission produced.
 *
 * Architecture section: 6.2 (submission strategies), 6.1 step 11, 8 (the join).
 *
 * executionRefId is a String rather than an Id on purpose. Execution_Ref_Id__c
 * is Text(18) holding a ProcessInstance.Id under Classic and would hold an
 * ApprovalSubmission.Id under Flow (3.3), and typing it as a String is what
 * keeps that second case additive. 8 is emphatic that this value is a
 * provenance stamp and must not be "optimised" away, so a strategy that cannot
 * produce one has failed rather than succeeded quietly.
 */
public class AMF_SubmitResult {

    /** The record that was submitted. */
    public Id recordId { get; private set; }

    /** ProcessInstance.Id for Classic. Stamped onto the decision log row. */
    public String executionRefId { get; private set; }

    /**
     * @param recordId       The record that was submitted.
     * @param executionRefId The execution reference the platform returned.
     */
    public AMF_SubmitResult(Id recordId, String executionRefId) {
        this.recordId = recordId;
        this.executionRefId = executionRefId;
    }
}
