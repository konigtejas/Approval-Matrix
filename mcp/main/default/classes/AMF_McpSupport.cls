/**
 * What the Claude connector's tools share (M16): reading a record the way a
 * person names it, a link to that record, and the signed preview token that
 * lets submit_for_approval submit only what preview_route has just shown.
 *
 * Architecture section: 7 (entry points, and its M16 note), 11 (security).
 *
 * A PERSON'S WORDS, NOT IDS. Claude is asked about "PR-00000047" or "the Dell
 * laptops request", never about an Id. resolve() hands every reference to the
 * assistant's Find Governed Record action (M13), which searches only governed
 * objects, in user mode, and lists several matches rather than guess between
 * them. A tool that cannot resolve its record says so in a sentence and stops.
 *
 * THE PREVIEW TOKEN. In Agentforce, the agent's script binds Submit to the
 * record it has just previewed (M13). An MCP client has no script, so Apex
 * binds it: preview_route signs, with a key Claude never sees, the organisation,
 * the user, the record, the process it showed and when; submit_for_approval
 * accepts only a signature this class made, for that same user, record and
 * process, within TOKEN_MINUTES. The threat is a model submitting something its
 * user was never shown, not the user, who may submit in the UI anyway. The
 * client's own approval of the call is the user's half of "preview, confirm,
 * submit" (7); this is the server's.
 *
 * The key is AMF_Mcp_Settings__c's Preview_Key__c, seeded by
 * scripts/setup-mcp.apex. Without it a preview still works and carries no
 * token, and a submission says how to finish setting up.
 */
public with sharing class AMF_McpSupport {

    /** Resolution outcomes, beside the engine's own outcomes in each tool's answer. */
    public static final String FOUND = 'Found';
    public static final String AMBIGUOUS = 'Ambiguous';
    public static final String NOT_FOUND = 'Not_Found';

    /** How long a preview may be submitted for. */
    public static final Integer TOKEN_MINUTES = 15;

    /** A clock running slightly behind the server's is not a forgery. */
    private static final Long SKEW_MILLIS = 60 * 1000;

    private static final String MAC_ALGORITHM = 'HmacSHA256';

    @TestVisible
    private static final String NOT_SET_UP =
        'Submitting through Claude is not set up in this org yet. An administrator runs scripts/setup-mcp.apex once; ' +
        'until then, submit from the record page.';

    @TestVisible
    private static final String NOT_PREVIEWED =
        'This submission does not come from a preview of this record, so nothing was submitted. ' +
        'Preview the record first, show the user where it would go, and submit once they confirm.';

    @TestVisible
    private static final String EXPIRED =
        'The preview is more than ' + TOKEN_MINUTES + ' minutes old, so nothing was submitted. ' +
        'Preview the record again and submit once the user confirms.';

    /** Test seam: the time tokens are issued and checked at. Always null in production. */
    @TestVisible
    private static Datetime nowOverride;

    /** A reference read as a record. */
    public class Resolution {
        /** Found, Ambiguous or Not_Found. */
        public String outcome;
        /** Set only when Found. */
        public Id recordId;
        /** What was found, ready to give the user; set unless Found. */
        public String message;
        /** When Ambiguous: the numbered matches, each with its Id. */
        public String matches;
    }

    /**
     * @param reference A record's number, name or Id, as the user gave it.
     * @return The record, or why there is not exactly one.
     */
    public static Resolution resolve(String reference) {
        AMF_AgentFindRecord.Request request = new AMF_AgentFindRecord.Request();
        request.searchText = reference;
        // Not "found": Apex names are case-insensitive, and FOUND is this class's constant.
        AMF_AgentFindRecord.Result lookup = AMF_AgentFindRecord.find(new List<AMF_AgentFindRecord.Request>{ request })[0];

        Resolution resolution = new Resolution();
        Id recordId = AMF_AgentSupport.idOf(lookup.recordId);

        if (lookup.matchCount == 1 && recordId != null) {
            resolution.outcome = FOUND;
            resolution.recordId = recordId;
        } else if (lookup.matchCount != null && lookup.matchCount > 1) {
            resolution.outcome = AMBIGUOUS;
            resolution.matches = lookup.matches;
            resolution.message = lookup.message;
        } else {
            resolution.outcome = NOT_FOUND;
            resolution.message = lookup.message;
        }
        return resolution;
    }

    /**
     * @param recordId A record.
     * @return Its address in this org, which opens its record page; null for no record.
     */
    public static String recordUrlOf(Id recordId) {
        return recordId == null ? null : URL.getOrgDomainUrl().toExternalForm() + '/' + recordId;
    }

    /**
     * @param recordId The record previewed.
     * @param process  The process the preview showed; blank when it showed a block.
     * @return The token to submit with, or null when the org has no key yet.
     */
    public static String tokenFor(Id recordId, String process) {
        Blob key = keyOf();
        if (key == null || recordId == null) {
            return null;
        }
        Long issuedAt = now().getTime();
        return issuedAt + '.' + signatureOf(key, recordId, process, issuedAt);
    }

    /**
     * @param token    What preview_route returned, as Claude passes it back.
     * @param recordId The record to submit.
     * @param process  The process the user confirmed; blank for a block.
     * @return Null when the token lets this user submit this record now;
     *         otherwise why not, ready to give the user.
     */
    public static String tokenProblem(String token, Id recordId, String process) {
        Blob key = keyOf();
        if (key == null) {
            return NOT_SET_UP;
        }

        List<String> parts = String.isBlank(token) ? new List<String>() : token.trim().split('\\.');
        if (recordId == null || parts.size() != 2 || !parts[0].isNumeric() || parts[0].length() > 18) {
            return NOT_PREVIEWED;
        }

        Long issuedAt = Long.valueOf(parts[0]);
        if (signatureOf(key, recordId, process, issuedAt) != parts[1]) {
            return NOT_PREVIEWED;
        }

        Long age = now().getTime() - issuedAt;
        if (age < -SKEW_MILLIS || age > TOKEN_MINUTES * 60 * 1000) {
            return EXPIRED;
        }
        return null;
    }

    private static String signatureOf(Blob key, Id recordId, String process, Long issuedAt) {
        String payload = String.join(
            new List<String>{
                UserInfo.getOrganizationId(),
                UserInfo.getUserId(),
                String.valueOf(recordId),
                process == null ? '' : process.trim(),
                String.valueOf(issuedAt)
            },
            '|'
        );
        return EncodingUtil.convertToHex(Crypto.generateMac(MAC_ALGORITHM, Blob.valueOf(payload), key));
    }

    private static Blob keyOf() {
        String encoded = AMF_Mcp_Settings__c.getOrgDefaults()?.Preview_Key__c;
        if (String.isBlank(encoded)) {
            return null;
        }
        try {
            return EncodingUtil.base64Decode(encoded.trim());
        } catch (Exception e) {
            return null;
        }
    }

    private static Datetime now() {
        return nowOverride == null ? Datetime.now() : nowOverride;
    }
}
