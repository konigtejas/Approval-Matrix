/**
 * Starts native Classic approval processes. THE ONLY PLACE IN THIS CODEBASE
 * THAT CALLS Approval.process().
 *
 * Architecture section: 6.2 (submission strategies), 5.2 (Classic templates),
 * 6.3 (the guard), 6.1 step 10.
 *
 * That exclusivity is a CLAUDE.md convention rather than a preference. The
 * platform call is the one part of the engine a unit test cannot exercise
 * safely, so confining it to a class behind AMF_SubmissionStrategy is what
 * lets every other engine test run against AMF_StrategyStub (10).
 *
 * ENTRY CRITERIA ARE NEVER SKIPPED. setSkipEntryCriteria(false) is set
 * explicitly, not left to the default, because it is the load-bearing half of
 * 6.3: every Classic template requires Matrix_Submission__c = true, the engine
 * stages that flag in the same transaction immediately before this call, and a
 * submission that arrived any other way therefore fails entry criteria loudly
 * instead of routing silently. Skipping entry criteria here would disarm the
 * guard for the one caller it exists to police.
 *
 * Sharing is inherited rather than declared, for the reason 11 gives: the
 * service is the place that decides -- it runs without sharing and authorises
 * the submitter explicitly -- and a library class that forced its own answer
 * would take that decision away from the caller making it.
 */
public inherited sharing class AMF_ClassicProcessStrategy implements AMF_SubmissionStrategy {

    /**
     * @param requests The records to submit and the process selected for each.
     * @return One AMF_SubmitResult per request, carrying the ProcessInstance Id.
     * @throws AMF_SubmissionException On a malformed request, or a platform
     *         result that carried no ProcessInstance Id.
     * @throws System.DmlException If any submission fails -- see allOrNone below.
     */
    public List<AMF_SubmitResult> submit(List<AMF_SubmitRequest> requests) {
        List<AMF_SubmitResult> results = new List<AMF_SubmitResult>();

        if (requests == null || requests.isEmpty()) {
            return results;
        }

        List<Approval.ProcessSubmitRequest> platformRequests = new List<Approval.ProcessSubmitRequest>();

        for (AMF_SubmitRequest request : requests) {
            validate(request);

            Approval.ProcessSubmitRequest platformRequest = new Approval.ProcessSubmitRequest();
            platformRequest.setObjectId(request.recordId);

            // 6.2: the process is named, not inferred. Salesforce still evaluates
            // that process's entry criteria, which is exactly what 6.3 wants --
            // the matrix chooses the shape, the guard proves the engine chose it.
            platformRequest.setProcessDefinitionNameOrId(request.processApiName);
            platformRequest.setSkipEntryCriteria(false);

            platformRequests.add(platformRequest);
        }

        // allOrNone = true, deliberately. By the time this runs the engine has
        // already inserted decision log rows saying Submitted and staged the
        // guard field. Lock_Decision_Log permits exactly one post-insert update
        // -- Execution_Ref_Id__c, blank to populated -- and explicitly not a
        // change to Outcome__c (M1.3), so there is no way to walk a row back
        // from Submitted to Failed after the fact. A partial success would
        // therefore leave the audit trail lying. Failing the whole transaction
        // rolls the rows, the guard and the submissions back together, which is
        // what the M1.10 carried item requires.
        List<Approval.ProcessResult> platformResults = Approval.process(platformRequests, true);

        for (Integer i = 0; i < platformResults.size(); i++) {
            AMF_SubmitRequest request = requests[i];
            String executionRefId = platformResults[i].getInstanceId();

            // 8: Execution_Ref_Id__c is a provenance stamp that must not be
            // optimised away, so a submission that reports success without one
            // is a contradiction rather than a partial result.
            if (String.isBlank(executionRefId)) {
                throw new AMF_SubmissionException(
                    'Approval process ' +
                    request.processApiName +
                    ' accepted ' +
                    request.recordId +
                    ' but returned no ProcessInstance Id'
                );
            }

            results.add(new AMF_SubmitResult(request.recordId, executionRefId));
        }

        return results;
    }

    private void validate(AMF_SubmitRequest request) {
        if (request == null || request.recordId == null) {
            throw new AMF_SubmissionException(
                'A submission request reached the Classic strategy without a record Id'
            );
        }
        if (String.isBlank(request.processApiName)) {
            throw new AMF_SubmissionException(
                'No approval process was named for record ' + request.recordId
            );
        }
    }
}
