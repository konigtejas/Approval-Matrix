/**
 * An AMF_SubmissionStrategy that records what the engine asked for instead of
 * running an approval.
 *
 * Architecture section: 10 (testability), 6.2 (submission strategies).
 *
 * 10 names exactly this: "SubmissionStrategy stub asserts the staged guard
 * field and the selected process without executing a real approval". Both
 * halves matter. The selected process is the matrix's whole output, and the
 * guard is 6.3's entry-criteria contract -- 6.1 step 9 requires
 * Matrix_Submission__c to be true in the same transaction BEFORE step 10, and
 * the only honest place to prove that ordering is inside step 10 itself. So
 * this stub re-queries each record as it is "submitted" and remembers what the
 * guard held at that instant. A stub that merely recorded the requests could
 * not tell a guard set before submit from one set after.
 *
 * Annotated @IsTest, like AMF_RuleBuilder, so it ships no production surface.
 */
@IsTest
public class AMF_StrategyStub implements AMF_SubmissionStrategy {

    /** Every request the engine handed over, in order. */
    public List<AMF_SubmitRequest> received = new List<AMF_SubmitRequest>();

    /** Matrix_Submission__c as it stood at the moment of submission, per record. */
    public Map<Id, Boolean> guardAtSubmit = new Map<Id, Boolean>();

    /** How many times the engine called submit(). Should be one per submit(). */
    public Integer calls = 0;

    /** When set, submit() throws it -- for proving the engine does not swallow it. */
    public Exception failWith;

    /** When true, submit() returns results with no execution reference. */
    public Boolean returnBlankReference = false;

    private Integer counter = 0;

    /**
     * @param requests The records the engine selected processes for.
     * @return One result per request, carrying a synthetic ProcessInstance Id.
     */
    public List<AMF_SubmitResult> submit(List<AMF_SubmitRequest> requests) {
        calls++;
        received.addAll(requests);

        if (failWith != null) {
            throw failWith;
        }

        captureGuard(requests);

        List<AMF_SubmitResult> results = new List<AMF_SubmitResult>();

        for (AMF_SubmitRequest request : requests) {
            results.add(
                new AMF_SubmitResult(
                    request.recordId,
                    returnBlankReference ? null : nextExecutionRef()
                )
            );
        }
        return results;
    }

    /** @return The process the engine chose for a record, or null if it never asked. */
    public String processFor(Id recordId) {
        for (AMF_SubmitRequest request : received) {
            if (request.recordId == recordId) {
                return request.processApiName;
            }
        }
        return null;
    }

    /**
     * Reads the guard through dynamic SOQL rather than a typed query, for the
     * same reason the engine stages it dynamically: 3.2 makes the guard a
     * convention on every governed object, and a stub hardcoded to
     * Purchase_Request__c would stop being usable the moment a second object
     * appears.
     */
    private void captureGuard(List<AMF_SubmitRequest> requests) {
        Set<Id> recordIds = new Set<Id>();

        for (AMF_SubmitRequest request : requests) {
            recordIds.add(request.recordId);
        }
        if (recordIds.isEmpty()) {
            return;
        }

        String objectApiName = String.valueOf(new List<Id>(recordIds)[0].getSObjectType());
        String soql =
            'SELECT Id, Matrix_Submission__c FROM ' + objectApiName + ' WHERE Id IN :recordIds';

        for (SObject record : Database.query(soql)) {
            guardAtSubmit.put(record.Id, (Boolean) record.get('Matrix_Submission__c'));
        }
    }

    /**
     * A synthetic 18-character ProcessInstance-shaped reference. Execution_Ref_Id__c
     * is Text(18) and AMF_SubmitResult carries a String, so no real Id is needed --
     * which is the point of not running a real approval.
     */
    private String nextExecutionRef() {
        counter++;
        return '04g' + String.valueOf(counter).leftPad(12, '0') + 'AAA';
    }
}
