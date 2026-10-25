/**
 * 7's Integration row (M10): POST /services/apexrest/approval-matrix/v1/submissions.
 *
 * Architecture section: 7 (entry points, and its M10 note), 6.1 (submitEach),
 * 11 (security).
 *
 *   Request:  {"recordIds": ["<record Id>", ...]}, at most 200 Ids.
 *   200:      {"results": [...]}, one result per Id in the order sent -- the
 *             shape AMF_SubmitForMatrixApproval returns to Flow.
 *   400:      {"message": "..."} for a body that is missing, not JSON, has no
 *             recordIds array, is empty, holds more than 200 Ids, or holds
 *             something that is not a record Id.
 *
 * A record that cannot be submitted is answered in its own result, exactly as
 * in Flow, so a 200 does not mean every record went in: read each outcome.
 *
 * The 400s are decided before anything is read or written. Any other fault is
 * left to escape, so the platform answers 500 and rolls the call back --
 * catching it here would end the request normally and commit whatever had
 * happened before it.
 *
 * Global because @RestResource requires it. With sharing, though it reads
 * nothing itself: the engine authorises every record against the caller (11).
 */
@RestResource(urlMapping='/approval-matrix/v1/submissions')
global with sharing class AMF_MatrixSubmissionResource {

    /**
     * Ids per call. 200 is the size a real submission is tested at in one
     * transaction (AMF_SubmissionIntegrationTest), and a Flow's batch size.
     */
    @TestVisible
    private static final Integer MAX_RECORDS = 200;

    private static final String EXPECTED = 'Send {"recordIds": ["<record Id>", ...]} with 1 to ' + MAX_RECORDS + ' Ids.';

    /** Answers the request in RestContext.response. */
    @HttpPost
    global static void submit() {
        RestResponse response = RestContext.response;
        response.addHeader('Content-Type', 'application/json');

        List<Id> recordIds;

        try {
            recordIds = recordIdsOf(RestContext.request.requestBody);
        } catch (BadRequestException e) {
            response.statusCode = 400;
            response.responseBody = Blob.valueOf(
                JSON.serialize(new Map<String, String>{ 'message' => e.getMessage() })
            );
            return;
        }

        response.statusCode = 200;
        response.responseBody = Blob.valueOf(
            JSON.serialize(
                new Map<String, Object>{
                    'results' => AMF_SubmitForMatrixApproval.submitEach(recordIds)
                }
            )
        );
    }

    private static List<Id> recordIdsOf(Blob body) {
        String text;

        try {
            text = body == null ? '' : body.toString();
        } catch (StringException e) {
            throw new BadRequestException('The request body is not UTF-8 text. ' + EXPECTED);
        }

        if (String.isBlank(text)) {
            throw new BadRequestException('The request body is empty. ' + EXPECTED);
        }

        Object parsed;

        try {
            parsed = JSON.deserializeUntyped(text);
        } catch (JSONException e) {
            throw new BadRequestException('The request body is not valid JSON. ' + EXPECTED);
        }

        Object values = parsed instanceof Map<String, Object>
            ? ((Map<String, Object>) parsed).get('recordIds')
            : null;

        if (!(values instanceof List<Object>)) {
            throw new BadRequestException('The request body has no "recordIds" array. ' + EXPECTED);
        }

        List<Object> items = (List<Object>) values;

        if (items.isEmpty()) {
            throw new BadRequestException('"recordIds" is empty. ' + EXPECTED);
        }
        if (items.size() > MAX_RECORDS) {
            throw new BadRequestException(
                '"recordIds" holds ' + items.size() + ' Ids; one call takes at most ' + MAX_RECORDS + '.'
            );
        }

        List<Id> recordIds = new List<Id>();

        for (Object item : items) {
            recordIds.add(idOf(item));
        }
        return recordIds;
    }

    private static Id idOf(Object item) {
        if (item instanceof String) {
            try {
                return Id.valueOf((String) item);
            } catch (StringException e) {
                throw notAnId(item);
            }
        }
        throw notAnId(item);
    }

    private static BadRequestException notAnId(Object item) {
        return new BadRequestException(
            '"recordIds" holds ' + JSON.serialize(item) + ', which is not a record Id. ' + EXPECTED
        );
    }

    /** A request the resource refuses before reading or writing anything: a 400. */
    private class BadRequestException extends Exception {
    }
}
