/**
 * Starts native Classic approval processes. THE ONLY PLACE IN THIS CODEBASE
 * THAT CALLS Approval.process().
 *
 * Architecture section: 6.2 (submission strategies, and its M10 note), 5.2
 * (Classic templates), 6.3 (the guard), 6.1 step 10.
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
 * ONE ANSWER PER RECORD (M10). Requests go to the platform in chunks of at most
 * 100 (6.1 step 10) with allOrNone false, and each record's answer comes back
 * as its own AMF_SubmitResult: the ProcessInstance Id, or the platform's reason
 * for refusing it. One refused record therefore leaves the others' submissions
 * standing, and the engine logs it Failed.
 *
 * Sharing is inherited rather than declared, for the reason 11 gives: the
 * service is the place that decides -- it runs without sharing and authorises
 * the submitter explicitly -- and a library class that forced its own answer
 * would take that decision away from the caller making it.
 */
public inherited sharing class AMF_ClassicProcessStrategy implements AMF_SubmissionStrategy {

    /** Requests per Approval.process() call (6.1 step 10). */
    @TestVisible
    private static final Integer CHUNK_SIZE = 100;

    /**
     * @param requests The records to submit and the process selected for each.
     * @return One AMF_SubmitResult per request, in request order: the
     *         ProcessInstance Id, or the platform's reason for refusing it.
     * @throws AMF_SubmissionException On a malformed request, before anything is
     *         submitted, or on a platform answer that contradicts itself.
     */
    public List<AMF_SubmitResult> submit(List<AMF_SubmitRequest> requests) {
        List<AMF_SubmitResult> results = new List<AMF_SubmitResult>();

        if (requests == null || requests.isEmpty()) {
            return results;
        }

        // Every request is checked before the first chunk goes, so a malformed
        // one stops the call with nothing yet in a process.
        for (AMF_SubmitRequest request : requests) {
            validate(request);
        }

        for (Integer start = 0; start < requests.size(); start += CHUNK_SIZE) {
            List<AMF_SubmitRequest> chunk = new List<AMF_SubmitRequest>();
            List<Approval.ProcessSubmitRequest> platformRequests = new List<Approval.ProcessSubmitRequest>();

            for (Integer i = start; i < Math.min(start + CHUNK_SIZE, requests.size()); i++) {
                chunk.add(requests[i]);
                platformRequests.add(platformRequestFor(requests[i]));
            }

            // allOrNone = false (6.2's M10 note). Before M10 this was true: the
            // engine had already written rows saying Submitted, and the lock rule
            // would not let it walk one back to Failed (M1.3), so one refusal had
            // to roll back every record. The engine now writes no row until this
            // method answers, so a refusal can be what it is -- one record's
            // Failed row -- and the rest go through.
            List<Approval.ProcessResult> platformResults = Approval.process(platformRequests, false);

            if (platformResults.size() != chunk.size()) {
                throw new AMF_SubmissionException(
                    'Approval.process() answered ' +
                    platformResults.size() +
                    ' of ' +
                    chunk.size() +
                    ' submission requests'
                );
            }

            for (Integer i = 0; i < chunk.size(); i++) {
                results.add(resultOf(chunk[i], platformResults[i]));
            }
        }

        return results;
    }

    private Approval.ProcessSubmitRequest platformRequestFor(AMF_SubmitRequest request) {
        Approval.ProcessSubmitRequest platformRequest = new Approval.ProcessSubmitRequest();
        platformRequest.setObjectId(request.recordId);

        // 6.2: the process is named, not inferred. Salesforce still evaluates
        // that process's entry criteria, which is exactly what 6.3 wants --
        // the matrix chooses the shape, the guard proves the engine chose it.
        platformRequest.setProcessDefinitionNameOrId(request.processApiName);
        platformRequest.setSkipEntryCriteria(false);

        return platformRequest;
    }

    private AMF_SubmitResult resultOf(AMF_SubmitRequest request, Approval.ProcessResult platformResult) {
        if (!platformResult.isSuccess()) {
            return AMF_SubmitResult.refused(request.recordId, reasonOf(platformResult.getErrors()));
        }

        String executionRefId = platformResult.getInstanceId();

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

        return new AMF_SubmitResult(request.recordId, executionRefId);
    }

    /**
     * The platform's reason as it gave it, status code first, for example
     * "MANAGER_NOT_DEFINED: Manager undefined." The code is what an admin
     * searches for; the message is what a submitter can act on.
     */
    private static String reasonOf(List<Database.Error> errors) {
        List<String> reasons = new List<String>();

        if (errors != null) {
            for (Database.Error error : errors) {
                reasons.add(String.valueOf(error.getStatusCode()) + ': ' + error.getMessage());
            }
        }

        return reasons.isEmpty() ? 'The platform refused it without giving a reason' : String.join(reasons, '; ');
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
