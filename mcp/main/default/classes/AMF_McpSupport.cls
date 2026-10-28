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
 * the user, the record, the process, the rule, the values it showed and when;
 * submit_for_approval accepts only a signature this class made, for that same
 * user and record, within TOKEN_MINUTES, and only when a fresh preview still
 * shows that same decision. The same process under another rule, or the same
 * rule over different values, was not what the user confirmed. The threat is a
 * model submitting something its user was never shown, not the user, who may
 * submit in the UI anyway. The client's own approval of the call is the user's
 * half of "preview, confirm, submit" (7); this is the server's.
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

    /** Returned when a submit token was not issued for this record and process. */
    public static final String NOT_PREVIEWED =
        'This submission does not come from a preview of this record, so nothing was submitted. ' + 'Preview the record first, show the user where it would go, and submit once they confirm.';

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
     * The decision a preview showed. The token is bound to all of it: the same
     * process reached by another rule, or by the same rule over different
     * values, is a different decision.
     */
    public class ShownDecision {
        /** Blank when the preview showed a block. */
        public String processName;
        /** Blank when no rule matched. */
        public String ruleName;
        public Integer ruleVersion;
        /** Evaluated values as the engine recorded them. Blank when nothing was read. */
        public String valuesJson;
    }

    /** What checkToken found. problem is null only when shown is the signed decision. */
    public class TokenCheck {
        public String problem;
        public ShownDecision shown;
    }

    /**
     * @param recordId The record previewed.
     * @param process  The process the preview showed; blank when it showed a block.
     * @return The token to submit with, or null when the org has no key yet.
     */
    public static String tokenFor(Id recordId, String process) {
        ShownDecision shown = new ShownDecision();
        shown.processName = process;
        return tokenFor(recordId, shown);
    }

    /**
     * @param recordId The record previewed.
     * @param shown    The decision the preview showed.
     * @return The token to submit with, or null when the org has no key yet.
     */
    public static String tokenFor(Id recordId, ShownDecision shown) {
        Blob key = keyOf();
        if (key == null || recordId == null) {
            return null;
        }
        String claim = claimOf(shown, now().getTime());
        // base64Encode inserts line breaks past 76 characters. A token is one line.
        String encoded = EncodingUtil.base64Encode(Blob.valueOf(claim)).replace('\r', '').replace('\n', '');
        return encoded + '.' + signatureOf(key, recordId, claim);
    }

    /**
     * @param token    What preview_route returned, as Claude passes it back.
     * @param recordId The record to submit.
     * @param process  The process the user confirmed; blank for a block.
     * @return Null when the token lets this user submit this record to this
     *         process now; otherwise why not, ready to give the user. The rule
     *         and the values are checked by sameDecision, against a fresh preview.
     */
    public static String tokenProblem(String token, Id recordId, String process) {
        TokenCheck check = checkToken(token, recordId);
        if (check.problem != null) {
            return check.problem;
        }
        String shownProcess = check.shown.processName == null ? '' : check.shown.processName;
        String expected = process == null ? '' : process.trim();
        return shownProcess == expected ? null : NOT_PREVIEWED;
    }

    /**
     * @param token    What preview_route returned.
     * @param recordId The record to submit.
     * @return The signed decision, or why the token is not one this user can use.
     */
    public static TokenCheck checkToken(String token, Id recordId) {
        TokenCheck check = new TokenCheck();
        Blob key = keyOf();
        if (key == null) {
            check.problem = NOT_SET_UP;
            return check;
        }

        String trimmed = token == null ? '' : token.trim().replace('\r', '').replace('\n', '');
        Integer dot = trimmed.indexOf('.');
        if (recordId == null || dot < 1 || dot != trimmed.lastIndexOf('.')) {
            check.problem = NOT_PREVIEWED;
            return check;
        }

        String claim;
        try {
            claim = EncodingUtil.base64Decode(trimmed.substring(0, dot)).toString();
        } catch (Exception e) {
            check.problem = NOT_PREVIEWED;
            return check;
        }
        if (signatureOf(key, recordId, claim) != trimmed.substring(dot + 1)) {
            check.problem = NOT_PREVIEWED;
            return check;
        }

        List<Object> parts;
        try {
            Object parsed = JSON.deserializeUntyped(claim);
            parts = parsed instanceof List<Object> ? (List<Object>) parsed : null;
        } catch (Exception e) {
            parts = null;
        }
        if (parts == null || parts.size() != 5) {
            check.problem = NOT_PREVIEWED;
            return check;
        }

        Long issuedAt;
        try {
            issuedAt = Long.valueOf(String.valueOf(parts[0]));
        } catch (Exception e) {
            check.problem = NOT_PREVIEWED;
            return check;
        }
        Long age = now().getTime() - issuedAt;
        if (age < -SKEW_MILLIS || age > TOKEN_MINUTES * 60 * 1000) {
            check.problem = EXPIRED;
            return check;
        }

        ShownDecision shown = new ShownDecision();
        shown.processName = String.valueOf(parts[1]);
        shown.ruleName = String.valueOf(parts[2]);
        String version = String.valueOf(parts[3]);
        shown.ruleVersion = String.isBlank(version) ? null : Integer.valueOf(version);
        shown.valuesJson = String.valueOf(parts[4]);
        check.shown = shown;
        return check;
    }

    /**
     * @return True when a fresh preview is the decision the token was signed for.
     */
    public static Boolean sameDecision(ShownDecision shown, String processName, String ruleName, Integer ruleVersion, String valuesJson) {
        if (shown == null) {
            return false;
        }
        return normalize(shown.processName) == normalize(processName) &&
            normalize(shown.ruleName) == normalize(ruleName) &&
            shown.ruleVersion == ruleVersion &&
            shown.valuesJson == canonicalValues(valuesJson);
    }

    private static String claimOf(ShownDecision shown, Long issuedAt) {
        return JSON.serialize(
            new List<String>{
                String.valueOf(issuedAt),
                normalize(shown == null ? null : shown.processName),
                normalize(shown == null ? null : shown.ruleName),
                shown == null || shown.ruleVersion == null ? '' : String.valueOf(shown.ruleVersion),
                canonicalValues(shown == null ? null : shown.valuesJson)
            }
        );
    }

    private static String normalize(String value) {
        return value == null ? '' : value.trim();
    }

    /** Object key order is not stable under JSON.serialize, so the signature uses this. */
    private static String canonicalValues(String raw) {
        if (String.isBlank(raw)) {
            return '';
        }
        try {
            Object parsed = JSON.deserializeUntyped(raw);
            if (parsed instanceof Map<String, Object>) {
                return canonicalMap((Map<String, Object>) parsed);
            }
        } catch (Exception e) {
            return raw.trim();
        }
        return raw.trim();
    }

    private static String canonicalMap(Map<String, Object> values) {
        List<String> keys = new List<String>(values.keySet());
        keys.sort();
        List<String> parts = new List<String>();
        for (String key : keys) {
            parts.add(JSON.serialize(key) + ':' + canonicalJson(values.get(key)));
        }
        return '{' + String.join(parts, ',') + '}';
    }

    private static String canonicalJson(Object value) {
        if (value instanceof Map<String, Object>) {
            return canonicalMap((Map<String, Object>) value);
        }
        return JSON.serialize(value);
    }

    private static String signatureOf(Blob key, Id recordId, String claim) {
        String payload = String.join(new List<String>{ UserInfo.getOrganizationId(), UserInfo.getUserId(), String.valueOf(recordId), claim }, '|');
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
