/**
 * The decision timeline: one record's approval story, told from both halves --
 * WHY it routed where it did, from Approval_Decision_Log__c, and WHO did WHAT
 * since, from the native approval history -- for the amfDecisionTimeline LWC on
 * the governed record's page.
 *
 * Architecture section: 8 (auditability, and its M7 note), 3.3 (the log and
 * the Execution_Ref_Id__c join), 11 (security), 6.4 (why nothing is cached).
 *
 * ONE ENTRY PER SUBMISSION ATTEMPT, NEWEST FIRST. Each decision log row is an
 * entry. A Submitted row carries the approval its Execution_Ref_Id__c names; a
 * blocked or failed row carries none, because it never entered a process. An
 * approval with no row this user can read becomes an entry of its own, so part
 * of a record's history is never silently dropped.
 *
 * ONLY WHAT WAS RECORDED. The why is the row's own snapshot -- rule
 * DeveloperName, version, expression, evaluated values, process -- and never a
 * join to the live matrix. 8 exists because the prior implementation let the
 * current configuration overwrite the historical answer; reading today's rule
 * into yesterday's decision would make the same mistake from the other side.
 *
 * READ-ONLY, AND SECURED BY TWO RULES THE PLATFORM ALREADY APPLIES.
 *   - Log rows are read WITH USER_MODE, so the user sees exactly the rows they
 *     could open anyway: their own as an Approval_Matrix_User, every row with
 *     View All (11).
 *   - Native history is shown to anyone who can read the record, which is when
 *     the Approval History related list shows it. That read access is checked
 *     first, explicitly, because the Classic provider reads without sharing.
 *
 * A READ PATH DEGRADES WHERE ROUTING WOULD FAIL. 4.6's fail-loudly rule governs
 * routing, where a silent fallback misroutes a record. Here the cost runs the
 * other way: a field deleted since a decision was made, or a values snapshot
 * that cannot be parsed, must not hide the audit trail. So a label falls back
 * to the recorded path, and unparseable values are shown exactly as recorded.
 */
public with sharing class AMF_DecisionTimelineService {

    /** Entries per timeline: the most recent, newest first. The related lists hold the rest. */
    @TestVisible
    private static final Integer MAX_ENTRIES = 50;

    /** Value.kind: how the LWC should present a recorded value. */
    @TestVisible
    private static final String KIND_NUMBER = 'number';
    @TestVisible
    private static final String KIND_BOOLEAN = 'boolean';
    @TestVisible
    private static final String KIND_TEXT = 'text';
    @TestVisible
    private static final String KIND_BLANK = 'blank';

    /** The whole recorded snapshot, when it could not be read as field values. */
    @TestVisible
    private static final String KIND_UNPARSED = 'unparsed';

    /** Raised for a call the timeline refuses outright. */
    public class TimelineException extends Exception {
    }

    /** What getTimeline returns. */
    public class Timeline {

        /** Newest first, at most MAX_ENTRIES. */
        @AuraEnabled
        public List<Entry> entries = new List<Entry>();

        /** True when older entries exist beyond the ones returned. */
        @AuraEnabled
        public Boolean hasMore = false;
    }

    /**
     * One submission attempt. At least one half is always set: a blocked or
     * failed decision has no approval, and an approval whose log row the user
     * cannot read has no decision.
     */
    public class Entry {

        /** Unique within the timeline: the log row's Id, else the approval's. */
        @AuraEnabled
        public String key;

        /** When the attempt was made. Entries are ordered by it. */
        @AuraEnabled
        public Datetime occurredAt;

        /** Why it routed where it did. Null when the user cannot read the row. */
        @AuraEnabled
        public Decision decision;

        /** What happened next, natively. Null when it never entered a process. */
        @AuraEnabled
        public AMF_ApprovalHistory.Instance approval;
    }

    /** A decision log row, as recorded (3.3). */
    public class Decision {

        @AuraEnabled
        public Id logId;

        /** The row's auto-number, ADL-00000000. */
        @AuraEnabled
        public String logName;

        /** Submitted, Blocked_No_Match or Failed. */
        @AuraEnabled
        public String outcome;

        /** DeveloperName of the rule that matched -- or, on a Failed row, the rule being evaluated. */
        @AuraEnabled
        public String matchedRule;

        @AuraEnabled
        public Integer ruleVersion;

        /** The expression exactly as evaluated: Expression_Snapshot__c. */
        @AuraEnabled
        public String expression;

        /** Evaluated_Values__c, one entry per field path, in the order recorded. */
        @AuraEnabled
        public List<Value> values = new List<Value>();

        @AuraEnabled
        public String selectedProcess;

        /** Failure_Detail__c: why a blocked or failed attempt did not route. */
        @AuraEnabled
        public String detail;

        @AuraEnabled
        public Id submittedById;

        @AuraEnabled
        public String submittedByName;

        @AuraEnabled
        public Datetime submittedAt;
    }

    /** One value the evaluator read, as recorded in Evaluated_Values__c. */
    public class Value {

        /** The field path as the rule wrote it, e.g. Account__r.Region__c. Null for KIND_UNPARSED. */
        @AuraEnabled
        public String path;

        /** The path in field labels, e.g. Account > Region; the path itself when it no longer resolves. */
        @AuraEnabled
        public String label;

        /** number, boolean, text, blank or unparsed. */
        @AuraEnabled
        public String kind;

        /** The value as text: a plain decimal for a number, true/false for a boolean, null when blank. */
        @AuraEnabled
        public String text;
    }

    private final AMF_ApprovalHistoryProvider historyProvider;

    /** Production wiring: Classic approval history. */
    public AMF_DecisionTimelineService() {
        this(new AMF_ClassicApprovalHistoryProvider());
    }

    /**
     * The seam 10 asks for. Tests inject an in-memory history, because a
     * ProcessInstance cannot be created without running a real approval.
     *
     * @param historyProvider Where native approval history comes from.
     */
    public AMF_DecisionTimelineService(AMF_ApprovalHistoryProvider historyProvider) {
        this.historyProvider = historyProvider;
    }

    /**
     * The entry point behind amfDecisionTimeline.
     *
     * Deliberately NOT cacheable=true, for 6.4's reason: a cached timeline would
     * outlive the next decision on the record, and a stale audit view is worse
     * than a slower one. The component calls it imperatively and re-reads when
     * the page refreshes.
     *
     * @param recordId The governed record whose timeline to show.
     * @return Its timeline.
     * @throws AuraHandledException Carrying the real message, when the user
     *         cannot read the record or the read fails.
     */
    @AuraEnabled
    public static Timeline getTimeline(Id recordId) {
        try {
            return new AMF_DecisionTimelineService().build(recordId);
        } catch (Exception e) {
            // setMessage as well as the constructor, as in AMF_ApprovalMatrixService:
            // without it the client sees "Script-thrown exception".
            AuraHandledException handled = new AuraHandledException(e.getMessage());
            handled.setMessage(e.getMessage());
            throw handled;
        }
    }

    /**
     * Builds one record's timeline.
     *
     * Both sources are read one row past MAX_ENTRIES and the merged list is cut
     * afterwards. That keeps the window honest across the join: a row and its
     * approval are written in the same transaction, so a row too old to be
     * fetched belongs to an approval too old to survive the cut, and the reverse
     * holds too. An approval is therefore never shown as unexplained merely
     * because its row fell outside a fetch.
     *
     * @param recordId The governed record.
     * @return Its timeline.
     * @throws TimelineException For a null record, or one the user cannot read.
     */
    public Timeline build(Id recordId) {
        if (recordId == null) {
            throw new TimelineException('A record is required to show its approval timeline.');
        }
        authorise(recordId);

        List<Approval_Decision_Log__c> rows = readableDecisions(recordId, MAX_ENTRIES + 1);
        List<AMF_ApprovalHistory.Instance> approvals = historyProvider.getHistory(
            recordId,
            MAX_ENTRIES + 1
        );

        // Keyed by the 18-character Id, which is the form 6.1 step 11 stamps.
        // Each row claims its approval by removing it, so whatever is left at the
        // end is an approval with no row this user can read.
        Map<String, AMF_ApprovalHistory.Instance> unclaimed = new Map<String, AMF_ApprovalHistory.Instance>();
        for (AMF_ApprovalHistory.Instance approval : approvals) {
            unclaimed.put(String.valueOf(approval.id), approval);
        }

        FieldLabels labels = new FieldLabels(recordId.getSObjectType());
        List<Entry> entries = new List<Entry>();

        for (Approval_Decision_Log__c row : rows) {
            Entry entry = new Entry();
            entry.key = row.Id;
            entry.decision = toDecision(row, labels);
            entry.occurredAt = entry.decision.submittedAt;

            if (String.isNotBlank(row.Execution_Ref_Id__c)) {
                entry.approval = unclaimed.remove(row.Execution_Ref_Id__c);
            }
            entries.add(entry);
        }

        for (AMF_ApprovalHistory.Instance approval : unclaimed.values()) {
            Entry entry = new Entry();
            entry.key = approval.id;
            entry.occurredAt = approval.submittedAt;
            entry.approval = approval;
            entries.add(entry);
        }

        entries.sort(new NewestFirst());

        Timeline timeline = new Timeline();
        timeline.hasMore = entries.size() > MAX_ENTRIES;

        for (Integer i = 0; i < Math.min(entries.size(), MAX_ENTRIES); i++) {
            timeline.entries.add(entries[i]);
        }
        return timeline;
    }

    /**
     * 11. The Classic provider reads without sharing, so the record-level
     * question is asked here, explicitly, before anything is read. Same shape
     * as AMF_ApprovalMatrixService.authorise: UserRecordAccess refuses a query
     * that selects a Has*Access field while filtering on one (M3.10).
     */
    private static void authorise(Id recordId) {
        List<UserRecordAccess> readable = [
            SELECT RecordId
            FROM UserRecordAccess
            WHERE UserId = :UserInfo.getUserId() AND RecordId = :recordId AND HasReadAccess = TRUE
        ];

        if (readable.isEmpty()) {
            throw new TimelineException(
                'You need read access to this record to see its approval timeline.'
            );
        }
    }

    /**
     * The record's decision log rows, newest first, WITH USER_MODE: sharing, CRUD
     * and FLS are the user's own. Filtered on Record_Id__c, the provenance
     * reference (3.3), which every row carries for every governed object; the
     * navigational lookup exists only for objects the log has a lookup field to.
     */
    private static List<Approval_Decision_Log__c> readableDecisions(Id recordId, Integer maxRows) {
        String recordKey = String.valueOf(recordId);

        return [
            SELECT
                Id,
                Name,
                Outcome__c,
                Matched_Rule__c,
                Rule_Version__c,
                Expression_Snapshot__c,
                Evaluated_Values__c,
                Selected_Process__c,
                Execution_Ref_Id__c,
                Failure_Detail__c,
                Submitted_By__c,
                Submitted_By__r.Name,
                Submitted_At__c,
                CreatedDate
            FROM Approval_Decision_Log__c
            WHERE Record_Id__c = :recordKey
            WITH USER_MODE
            ORDER BY Submitted_At__c DESC NULLS LAST, CreatedDate DESC, Id DESC
            LIMIT :maxRows
        ];
    }

    private static Decision toDecision(Approval_Decision_Log__c row, FieldLabels labels) {
        Decision decision = new Decision();
        decision.logId = row.Id;
        decision.logName = row.Name;
        decision.outcome = row.Outcome__c;
        decision.matchedRule = row.Matched_Rule__c;
        decision.ruleVersion = row.Rule_Version__c == null ? null : row.Rule_Version__c.intValue();
        decision.expression = row.Expression_Snapshot__c;
        decision.values = valuesOf(row.Evaluated_Values__c, labels);
        decision.selectedProcess = row.Selected_Process__c;
        decision.detail = row.Failure_Detail__c;
        decision.submittedById = row.Submitted_By__c;
        decision.submittedByName = row.Submitted_By__r?.Name;
        // The engine always stamps Submitted_At__c (3.3); CreatedDate only stands
        // in for a row written some other way.
        decision.submittedAt = row.Submitted_At__c != null ? row.Submitted_At__c : row.CreatedDate;
        return decision;
    }

    /**
     * Evaluated_Values__c as a list: a JSON object of field path to value,
     * written by AMF_Evaluator.Result.toJson. Anything else is returned whole, as
     * KIND_UNPARSED, rather than failing the timeline.
     */
    private static List<Value> valuesOf(String snapshot, FieldLabels labels) {
        List<Value> values = new List<Value>();

        if (String.isBlank(snapshot)) {
            return values;
        }

        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(snapshot);
        } catch (JSONException e) {
            parsed = null;
        }

        if (!(parsed instanceof Map<String, Object>)) {
            Value whole = new Value();
            whole.kind = KIND_UNPARSED;
            whole.text = snapshot;
            values.add(whole);
            return values;
        }

        Map<String, Object> byPath = (Map<String, Object>) parsed;
        for (String path : byPath.keySet()) {
            values.add(valueOf(path, labels.labelOf(path), byPath.get(path)));
        }
        return values;
    }

    private static Value valueOf(String path, String label, Object raw) {
        Value value = new Value();
        value.path = path;
        value.label = label;

        if (raw == null) {
            value.kind = KIND_BLANK;
        } else if (raw instanceof Boolean) {
            value.kind = KIND_BOOLEAN;
            value.text = String.valueOf(raw);
        } else if (raw instanceof Decimal || raw instanceof Integer || raw instanceof Long || raw instanceof Double) {
            value.kind = KIND_NUMBER;
            value.text = String.valueOf(raw);
        } else if (raw instanceof String) {
            value.kind = KIND_TEXT;
            value.text = (String) raw;
        } else {
            // A nested object or list: the evaluator writes neither, but showing
            // it as JSON is honest where guessing a presentation would not be.
            value.kind = KIND_TEXT;
            value.text = JSON.serialize(raw);
        }
        return value;
    }

    /** Newest first; the key settles a tie, so the order never varies between reads. */
    private class NewestFirst implements Comparator<Entry> {

        public Integer compare(Entry left, Entry right) {
            Long leftTime = left.occurredAt == null ? 0L : left.occurredAt.getTime();
            Long rightTime = right.occurredAt == null ? 0L : right.occurredAt.getTime();

            if (leftTime != rightTime) {
                return leftTime > rightTime ? -1 : 1;
            }
            return right.key.compareTo(left.key);
        }
    }

    /**
     * Field path to the label a person reads -- Account__r.Region__c becomes
     * Account > Region -- resolved against the CURRENT schema by describe, once
     * per path per call.
     *
     * Presentation only: the recorded path is the provenance, and the LWC keeps
     * it on screen. A path that no longer resolves, such as a field deleted since
     * the decision, is returned as recorded rather than failing the timeline.
     */
    private class FieldLabels {

        private final Schema.SObjectType rootType;
        private final Map<String, String> labelByPath = new Map<String, String>();
        private final Map<Schema.SObjectType, Map<String, Schema.DescribeFieldResult>> relationshipsByType = new Map<Schema.SObjectType, Map<String, Schema.DescribeFieldResult>>();

        public FieldLabels(Schema.SObjectType rootType) {
            this.rootType = rootType;
        }

        public String labelOf(String path) {
            if (!labelByPath.containsKey(path)) {
                labelByPath.put(path, resolve(path));
            }
            return labelByPath.get(path);
        }

        private String resolve(String path) {
            List<String> segments = path.split('\\.');
            List<String> labels = new List<String>();
            Schema.SObjectType current = rootType;

            for (Integer i = 0; i < segments.size(); i++) {
                Boolean isLast = i == segments.size() - 1;
                Schema.DescribeFieldResult field = isLast
                    ? fieldNamed(current, segments[i])
                    : relationshipNamed(current, segments[i]);

                if (field == null) {
                    return path;
                }

                if (isLast) {
                    labels.add(field.getLabel());
                } else {
                    labels.add(relationshipLabel(field));
                    current = field.getReferenceTo()[0];
                }
            }
            return String.join(labels, ' > ');
        }

        private Schema.DescribeFieldResult fieldNamed(Schema.SObjectType type, String fieldName) {
            Schema.SObjectField field = type.getDescribe().fields.getMap().get(fieldName);
            return field == null ? null : field.getDescribe();
        }

        /** Account__r on the governed object finds the Account__c lookup, case-insensitively. */
        private Schema.DescribeFieldResult relationshipNamed(Schema.SObjectType type, String relationshipName) {
            if (!relationshipsByType.containsKey(type)) {
                Map<String, Schema.DescribeFieldResult> byName = new Map<String, Schema.DescribeFieldResult>();

                for (Schema.SObjectField field : type.getDescribe().fields.getMap().values()) {
                    Schema.DescribeFieldResult described = field.getDescribe();
                    if (described.getRelationshipName() != null) {
                        byName.put(described.getRelationshipName().toLowerCase(), described);
                    }
                }
                relationshipsByType.put(type, byName);
            }
            return relationshipsByType.get(type).get(relationshipName.toLowerCase());
        }

        /**
         * A standard lookup is labelled for its Id -- OwnerId is "Owner ID" -- which
         * reads badly as the first half of a path, so the suffix is dropped. Custom
         * lookups are labelled for the record already.
         */
        private String relationshipLabel(Schema.DescribeFieldResult field) {
            String label = field.getLabel();
            return field.isCustom() ? label : label.removeEnd(' ID');
        }
    }
}
