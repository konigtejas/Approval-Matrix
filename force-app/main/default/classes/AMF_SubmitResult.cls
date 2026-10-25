/**
 * What a submission strategy hands back for one request: the platform's answer
 * for that record. Either it entered the process, with the execution reference
 * that submission produced, or the platform refused it, with the reason.
 *
 * Architecture section: 6.2 (submission strategies, and its M10 note), 6.1, 8
 * (the join).
 *
 * A REFUSAL IS DATA (6.2's M10 note). Until M10 a strategy answered for the
 * whole batch: every record entered its process, or an exception rolled them
 * all back. Now it answers per record, so the engine can log a refused record
 * as Failed and let the others' submissions stand. An exception is kept for a
 * strategy that failed as a whole.
 *
 * executionRefId is a String rather than an Id on purpose. Execution_Ref_Id__c
 * is Text(18) holding a ProcessInstance.Id under Classic and would hold an
 * ApprovalSubmission.Id under Flow (3.3), and typing it as a String is what
 * keeps that second case additive. 8 is emphatic that this value is a
 * provenance stamp and must not be "optimised" away, so a success that carries
 * none is a contradiction the engine refuses rather than a result it records.
 */
public class AMF_SubmitResult {

    /** The record the request was for. */
    public Id recordId { get; private set; }

    /** True when the record entered the process; false when the platform refused it. */
    public Boolean succeeded { get; private set; }

    /** ProcessInstance.Id for Classic, when succeeded. Written to the decision log row. */
    public String executionRefId { get; private set; }

    /** Why the platform refused the record, in its own words. Null when succeeded. */
    public String errorMessage { get; private set; }

    /**
     * A record that entered its process.
     *
     * @param recordId       The record that was submitted.
     * @param executionRefId The execution reference the platform returned.
     */
    public AMF_SubmitResult(Id recordId, String executionRefId) {
        this.recordId = recordId;
        this.executionRefId = executionRefId;
        this.succeeded = true;
    }

    /**
     * A record the platform refused.
     *
     * @param recordId     The record that was refused.
     * @param errorMessage Why, as the platform reported it.
     * @return A result that did not succeed and carries no execution reference.
     */
    public static AMF_SubmitResult refused(Id recordId, String errorMessage) {
        AMF_SubmitResult result = new AMF_SubmitResult(recordId, null);
        result.succeeded = false;
        result.errorMessage = errorMessage;
        return result;
    }
}
