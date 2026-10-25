/**
 * The Approval Matrix Assistant's What-If Route action (M14): where a record's
 * approval would go if some of its field values were different, answered by
 * the engine, with nothing changed or submitted.
 *
 * Architecture section: 6.4 (preview, and its M14 note), 7 (its M14 note),
 * 1 (principle 6), 11 (security).
 *
 * THE ENGINE ANSWERS, TWICE. AMF_ApprovalMatrixService.preview() gives the
 * route the record would take today, and previewWith() the route it would take
 * with the changed values, put on the in-memory copy the rules read. Both run
 * the engine's own steps 1 to 7; the agent never works out a route. Summary is
 * a complete, deterministic sentence built here from the two answers.
 *
 * WHAT CAN BE TRIED. Fields of the record itself, named by label or API name,
 * with values written as a person would write them: "Amount = 120k; Region =
 * EMEA". A picklist value must be one of the field's own; a field no active
 * rule reads is accepted, and the summary says it cannot change the route.
 * Anything the action cannot read is answered with what it can, not guessed.
 *
 * NEVER SUBMITTED. A what-if is a question, not a record: the agent offers no
 * submission from it. To submit with different values, the user changes the
 * record and previews it again.
 */
public with sharing class AMF_AgentWhatIfRoute {

    /** Outcome values, as the preview action names them (M13). */
    @TestVisible
    private static final String ROUTABLE = 'Routable';
    private static final String BLOCKED_NO_MATCH = 'Blocked_No_Match';
    private static final String FAILED = 'Failed';
    @TestVisible
    private static final String REFUSED = 'Refused';

    /** Words that ask for an empty value. */
    private static final Set<String> BLANK_WORDS = new Set<String>{ 'blank', 'empty', 'none', 'null', 'nothing' };
    private static final Set<String> TRUE_WORDS = new Set<String>{ 'true', 'yes', 'y', 'checked', 'ticked', 'on' };
    private static final Set<String> FALSE_WORDS = new Set<String>{ 'false', 'no', 'n', 'unchecked', 'unticked', 'off' };

    /** Most picklist values listed when a value is not one of them. */
    private static final Integer MAX_VALUES_LISTED = 15;

    /** One record, and the values to try on it. */
    public class Request {
        @InvocableVariable(
            label='Record ID'
            description='The Salesforce Id of the record to try the values on.'
            required=true
        )
        public String recordId;

        @InvocableVariable(
            label='Changes'
            description='The field values to try instead of the record\'s own, as "Field = value", separated by semicolons, such as "Amount = 120000; Region = EMEA". Fields may be named by their label.'
            required=true
        )
        public String changes;
    }

    /** The two routes, and the sentence that compares them. */
    public class Result {
        @InvocableVariable(label='Record ID' description='The record tried, as an 18-character Id.')
        public String recordId;

        @InvocableVariable(label='Record' description='The record as a person names it, such as Purchase Request PR-00000045.')
        public String recordLabel;

        @InvocableVariable(
            label='Outcome'
            description='What the matrix would do with the changed values: Routable, Blocked_No_Match or Failed. Refused when the what-if could not be run.'
        )
        public String outcome;

        @InvocableVariable(label='Route Changed' description='True when the changed values would send the record somewhere other than today.')
        public Boolean routeChanged;

        @InvocableVariable(label='Selected Process' description='The approval process the record would enter with the changed values.')
        public String selectedProcess;

        @InvocableVariable(label='Matched Rule' description='The rule that would decide the route with the changed values.')
        public String matchedRule;

        @InvocableVariable(label='Current Process' description='The approval process the record would enter today, with its own values.')
        public String currentProcess;

        @InvocableVariable(label='Current Rule' description='The rule that decides the route today.')
        public String currentRule;

        @InvocableVariable(
            label='Summary'
            description='The what-if in plain English, complete and ready to give the user. It says nothing was changed or submitted.'
        )
        public String summary;
    }

    /** One change the user asked for, once read. */
    private class Change {
        private String apiName;
        private String label;
        private Object value;
        private Boolean readByRule;
    }

    /** Why a change could not be read, worded for the user. */
    private class WhatIfException extends Exception {
    }

    /**
     * Test seams: tests set these so the action runs over in-memory rules
     * instead of the org's matrix. Always null in production.
     */
    @TestVisible
    private static AMF_ApprovalMatrixService engineOverride;
    @TestVisible
    private static AMF_RuleProvider ruleProviderOverride;

    /**
     * @param requests One per record.
     * @return One result per request, in the same order. Never throws for a record.
     */
    @InvocableMethod(
        label='What-If Approval Route'
        description='Shows where a record\'s approval would go if some of its field values were different, and how that compares with today. Changes nothing and submits nothing.'
        category='Approval Matrix'
    )
    public static List<Result> whatIf(List<Request> requests) {
        List<Result> results = new List<Result>();

        if (requests == null) {
            return results;
        }
        for (Request request : requests) {
            results.add(whatIfOne(request));
        }
        return results;
    }

    private static Result whatIfOne(Request request) {
        Id recordId = AMF_AgentSupport.idOf(request?.recordId);

        if (recordId == null) {
            return refused(null, null, AMF_AgentSupport.notAnId(request?.recordId));
        }

        String label = AMF_DecisionExplainer.recordLabelOf(recordId);
        Schema.SObjectType sobjectType = recordId.getSObjectType();
        List<Change> changes;

        try {
            changes = changesOf(request.changes, sobjectType, fieldsRulesRead(sobjectType));
        } catch (WhatIfException e) {
            return refused(recordId, label, e.getMessage());
        } catch (AMF_ExpressionException e) {
            return refused(recordId, label, 'the approval matrix cannot be run: ' + e.getMessage());
        }

        Map<String, Object> typed = new Map<String, Object>();
        for (Change change : changes) {
            typed.put(change.apiName, change.value);
        }

        AMF_ApprovalMatrixService.Outcome today;
        AMF_ApprovalMatrixService.Outcome tried;

        try {
            today = engine().preview(new List<Id>{ recordId })[0];
            tried = engine().previewWith(recordId, typed);
        } catch (AMF_SubmissionException e) {
            return refused(recordId, label, e.getMessage());
        } catch (AMF_ExpressionException e) {
            return refused(recordId, label, e.getMessage());
        }

        return resultOf(recordId, label, changes, currentValuesOf(recordId, changes), today, tried);
    }

    // ── Reading the changes ────────────────────────────────────────────────────

    /**
     * The direct fields any active rule for the object reads, by API name. The
     * rules come through AMF_RuleProvider and compile through AMF_ExprCache, as
     * the engine's do, so this is the engine's own view of what matters.
     */
    private static Set<String> fieldsRulesRead(Schema.SObjectType sobjectType) {
        String objectApiName = sobjectType.getDescribe().getName();
        List<AMF_RuleDefinition> rules = ruleProvider().getActiveRules(objectApiName);

        if (rules == null || rules.isEmpty()) {
            throw new WhatIfException(
                'the approval matrix does not govern ' + sobjectType.getDescribe().getLabelPlural() + ', so there is no route to try.'
            );
        }

        Map<String, Schema.SObjectField> fields = sobjectType.getDescribe().fields.getMap();
        Set<String> read = new Set<String>();

        for (AMF_RuleDefinition rule : rules) {
            for (String path : AMF_ExprCache.get(rule).fieldPaths) {
                if (!path.contains('.') && fields.containsKey(path)) {
                    read.add(fields.get(path).getDescribe().getName());
                }
            }
        }
        return read;
    }

    private static List<Change> changesOf(String text, Schema.SObjectType sobjectType, Set<String> readByRules) {
        List<String> parts = new List<String>();
        for (String part : (text == null ? '' : text).split('[;\\n]')) {
            if (String.isNotBlank(part)) {
                parts.add(part.trim());
            }
        }

        if (parts.isEmpty()) {
            throw new WhatIfException(
                'say which field and value to try, such as "Amount = 120000".' + fieldsHint(sobjectType, readByRules)
            );
        }

        Map<String, Schema.SObjectField> byName = sobjectType.getDescribe().fields.getMap();
        Map<String, Schema.SObjectField> byLabel = new Map<String, Schema.SObjectField>();
        for (Schema.SObjectField field : byName.values()) {
            byLabel.put(field.getDescribe().getLabel().toLowerCase(), field);
        }

        List<Change> changes = new List<Change>();
        Set<String> seen = new Set<String>();

        for (String part : parts) {
            List<String> pair = pairOf(part);
            if (pair == null) {
                throw new WhatIfException(
                    '"' + part.abbreviate(80) + '" does not say which value to try. Write each change as Field = value.'
                );
            }

            String fieldText = unquote(pair[0]);
            if (fieldText.contains('.')) {
                throw new WhatIfException(
                    'a what-if can change only the record\'s own fields, not ' + fieldText + ', which belongs to a related record.'
                );
            }

            Schema.SObjectField field = byName.containsKey(fieldText)
                ? byName.get(fieldText)
                : byLabel.get(fieldText.toLowerCase());

            if (field == null) {
                throw new WhatIfException(
                    sobjectType.getDescribe().getLabel() + ' has no field called "' + fieldText.abbreviate(80) + '".' +
                    fieldsHint(sobjectType, readByRules)
                );
            }

            Schema.DescribeFieldResult described = field.getDescribe();
            if (!seen.add(described.getName())) {
                throw new WhatIfException(described.getLabel() + ' is given more than once. Give each field one value.');
            }

            Change change = new Change();
            change.apiName = described.getName();
            change.label = described.getLabel();
            change.value = valueFor(described, pair[1]);
            change.readByRule = readByRules.contains(described.getName());
            changes.add(change);
        }
        return changes;
    }

    /** "Amount = 120000", "Amount: 120000" or "Amount to 120000", as field and value. */
    private static List<String> pairOf(String part) {
        Integer at = part.indexOf('=');
        if (at < 0) {
            at = part.indexOf(':');
        }
        if (at > 0) {
            return new List<String>{ part.substring(0, at).trim(), part.substring(at + 1).trim() };
        }

        Matcher worded = Pattern.compile('(?i)^(.+?)\\s+(?:to|as|of|is|were|was|at)\\s+(.+)$').matcher(part);
        if (worded.matches()) {
            return new List<String>{ worded.group(1).trim(), worded.group(2).trim() };
        }
        return null;
    }

    /**
     * The value as the field holds it. Anything that cannot be read as the
     * field's type is refused with what would be accepted, never coerced.
     */
    @TestVisible
    private static Object valueFor(Schema.DescribeFieldResult field, String raw) {
        String text = unquote(raw);

        if (String.isBlank(text) || BLANK_WORDS.contains(text.toLowerCase())) {
            return null;
        }

        switch on field.getType() {
            when CURRENCY, DOUBLE, PERCENT {
                return numberOf(field, text);
            }
            when INTEGER {
                return numberOf(field, text).intValue();
            }
            when LONG {
                return numberOf(field, text).longValue();
            }
            when BOOLEAN {
                String word = text.toLowerCase();
                if (TRUE_WORDS.contains(word)) {
                    return true;
                }
                if (FALSE_WORDS.contains(word)) {
                    return false;
                }
                throw new WhatIfException(field.getLabel() + ' is a checkbox, so try it as true or false, not "' + text.abbreviate(40) + '".');
            }
            when DATE {
                return dateOf(field, text);
            }
            when PICKLIST {
                return picklistValueOf(field, text);
            }
            when MULTIPICKLIST {
                List<String> chosen = new List<String>();
                for (String one : text.split(',')) {
                    if (String.isNotBlank(one)) {
                        chosen.add(picklistValueOf(field, one.trim()));
                    }
                }
                return String.join(chosen, ';');
            }
            when REFERENCE {
                Id asId = AMF_AgentSupport.idOf(text);
                if (asId == null) {
                    throw new WhatIfException(field.getLabel() + ' holds a record Id, and "' + text.abbreviate(40) + '" is not one.');
                }
                return asId;
            }
            when STRING, TEXTAREA, EMAIL, PHONE, URL {
                return text;
            }
            when else {
                throw new WhatIfException(field.getLabel() + ' cannot be tried in a what-if.');
            }
        }
    }

    /** 120000, 120,000, $120,000, 120k, 1.2m or 1.2 million. */
    private static Decimal numberOf(Schema.DescribeFieldResult field, String text) {
        String compact = text.toLowerCase().replaceAll('[\\s,]', '');
        Decimal multiplier = 1;

        if (compact.endsWith('million')) {
            multiplier = 1000000;
            compact = compact.removeEnd('million');
        } else if (compact.endsWith('thousand')) {
            multiplier = 1000;
            compact = compact.removeEnd('thousand');
        } else if (compact.endsWith('k')) {
            multiplier = 1000;
            compact = compact.removeEnd('k');
        } else if (compact.endsWith('m')) {
            multiplier = 1000000;
            compact = compact.removeEnd('m');
        }

        // A currency sign or code in front, and a percent sign behind.
        compact = compact.replaceAll('^[^0-9.\\-]+', '').removeEnd('%');

        try {
            return Decimal.valueOf(compact) * multiplier;
        } catch (Exception e) {
            throw new WhatIfException(field.getLabel() + ' is a number, so try it as one, such as 120000, not "' + text.abbreviate(40) + '".');
        }
    }

    private static Date dateOf(Schema.DescribeFieldResult field, String text) {
        try {
            return Date.valueOf(text);
        } catch (Exception e) {
            try {
                return Date.parse(text);
            } catch (Exception again) {
                throw new WhatIfException(field.getLabel() + ' is a date, so try it as YYYY-MM-DD, such as 2026-12-31.');
            }
        }
    }

    /** One of the field's own values, by value or label, in any case. */
    private static String picklistValueOf(Schema.DescribeFieldResult field, String text) {
        List<String> offered = new List<String>();

        for (Schema.PicklistEntry entry : field.getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            if (entry.getValue().equalsIgnoreCase(text) || entry.getLabel().equalsIgnoreCase(text)) {
                return entry.getValue();
            }
            if (offered.size() < MAX_VALUES_LISTED) {
                offered.add(entry.getLabel());
            }
        }

        throw new WhatIfException(
            '"' + text.abbreviate(40) + '" is not a ' + field.getLabel() + ' value. ' + field.getLabel() + ' can be ' +
            String.join(offered, ', ') + '.'
        );
    }

    private static String unquote(String text) {
        String trimmed = text == null ? '' : text.trim();
        if (trimmed.length() >= 2 && (trimmed.startsWith('\'') && trimmed.endsWith('\'') || trimmed.startsWith('"') && trimmed.endsWith('"'))) {
            return trimmed.substring(1, trimmed.length() - 1).trim();
        }
        return trimmed;
    }

    /** " Its rules read Amount, Region and Risk Level." -- what is worth trying. */
    private static String fieldsHint(Schema.SObjectType sobjectType, Set<String> readByRules) {
        if (readByRules.isEmpty()) {
            return ' Its rules read no fields, so no change to it can change its route.';
        }
        Map<String, Schema.SObjectField> fields = sobjectType.getDescribe().fields.getMap();
        List<String> labels = new List<String>();
        for (String apiName : readByRules) {
            labels.add(fields.get(apiName).getDescribe().getLabel());
        }
        labels.sort();
        return ' Its rules read ' + joined(labels) + '.';
    }

    // ── The answer ─────────────────────────────────────────────────────────────

    /** The record's own values of the changed fields, read in user mode, by API name. */
    private static Map<String, Object> currentValuesOf(Id recordId, List<Change> changes) {
        List<String> fields = new List<String>();
        for (Change change : changes) {
            fields.add(change.apiName);
        }

        Map<String, Object> values = new Map<String, Object>();
        try {
            List<SObject> rows = Database.query(
                'SELECT ' + String.join(fields, ', ') + ' FROM ' + recordId.getSObjectType().getDescribe().getName() +
                ' WHERE Id = :recordId LIMIT 1',
                AccessLevel.USER_MODE
            );
            if (!rows.isEmpty()) {
                for (String field : fields) {
                    values.put(field, rows[0].get(field));
                }
            }
        } catch (Exception e) {
            // Without today's values the summary leaves out "(now ...)", nothing more.
        }
        return values;
    }

    private static Result resultOf(
        Id recordId,
        String label,
        List<Change> changes,
        Map<String, Object> current,
        AMF_ApprovalMatrixService.Outcome today,
        AMF_ApprovalMatrixService.Outcome tried
    ) {
        Result result = new Result();
        result.recordId = String.valueOf(recordId);
        result.recordLabel = label;
        result.currentProcess = today.outcome == 'Submitted' ? today.selectedProcess : null;
        result.currentRule = today.matchedRule;
        result.selectedProcess = tried.outcome == 'Submitted' ? tried.selectedProcess : null;
        result.matchedRule = tried.matchedRule;
        result.outcome = tried.outcome == 'Submitted' ? ROUTABLE : (tried.outcome == BLOCKED_NO_MATCH ? BLOCKED_NO_MATCH : FAILED);
        result.routeChanged = today.outcome != tried.outcome || today.selectedProcess != tried.selectedProcess;

        Schema.SObjectType sobjectType = recordId.getSObjectType();
        String condition = 'If ' + conditionOf(changes, current, sobjectType) + ', ' + label;
        String summary;

        switch on tried.outcome {
            when 'Submitted' {
                String because = AMF_AgentSupport.sentenceOf(tried.evaluatedValuesJson, sobjectType);
                summary =
                    condition + ' would go to approval process ' + tried.selectedProcess + '. Rule ' + tried.matchedRule +
                    ' (priority ' + tried.rulePriority + ') would decide it, ' +
                    (String.isBlank(because)
                        ? 'and its condition reads no fields, so it matches every record that no earlier rule did.'
                        : 'because ' + because + '.');
            }
            when 'Blocked_No_Match' {
                summary =
                    condition +
                    ' would match no active rule, so the approval matrix would block a submission instead of routing it.';
            }
            when else {
                summary = condition + ' could not be routed: ' + AMF_AgentSupport.asSentence(tried.message);
            }
        }

        summary += ' ' + todayOf(today, result.routeChanged);

        List<String> ignored = new List<String>();
        for (Change change : changes) {
            if (!change.readByRule) {
                ignored.add(change.label);
            }
        }
        if (!ignored.isEmpty()) {
            summary +=
                ' No active rule reads ' + joined(ignored) + ', so changing ' + (ignored.size() == 1 ? 'it' : 'them') +
                ' makes no difference to the route.';
        }

        result.summary =
            summary +
            ' This is only a what-if: nothing was changed or submitted. To submit with these values, change the ' +
            'record, then preview it again.';
        return result;
    }

    /** "Amount were 120,000 (now 60,000) and Region were EMEA (now AMER)". */
    private static String conditionOf(List<Change> changes, Map<String, Object> current, Schema.SObjectType sobjectType) {
        Map<String, Object> tried = new Map<String, Object>();
        for (Change change : changes) {
            tried.put(change.apiName, change.value);
        }

        Map<String, String> nowByField = displayed(current, sobjectType);
        Map<String, String> triedByField = displayed(tried, sobjectType);
        List<String> parts = new List<String>();

        for (Change change : changes) {
            String part = change.label + ' were ' + triedByField.get(change.apiName);
            if (current.containsKey(change.apiName)) {
                part += ' (now ' + nowByField.get(change.apiName) + ')';
            }
            parts.add(part);
        }
        return joined(parts);
    }

    /** Values as the timeline shows them: 120,000 for a number, (blank) for nothing. */
    private static Map<String, String> displayed(Map<String, Object> values, Schema.SObjectType sobjectType) {
        Map<String, String> shown = new Map<String, String>();
        if (values.isEmpty()) {
            return shown;
        }
        for (AMF_DecisionTimelineService.Value value : AMF_DecisionTimelineService.describeValues(JSON.serialize(values), sobjectType)) {
            shown.put(value.path, AMF_DecisionExplainer.displayOf(value));
        }
        return shown;
    }

    private static String todayOf(AMF_ApprovalMatrixService.Outcome today, Boolean changed) {
        if (!changed) {
            return 'That is the same as today.';
        }
        switch on today.outcome {
            when 'Submitted' {
                return 'Today it would go to approval process ' + today.selectedProcess + ', under rule ' + today.matchedRule + '.';
            }
            when 'Blocked_No_Match' {
                return 'Today no active rule matches it, so a submission would be blocked.';
            }
            when else {
                return 'Today the approval matrix cannot decide a route for it: ' + AMF_AgentSupport.asSentence(today.message);
            }
        }
    }

    private static String joined(List<String> parts) {
        if (parts.isEmpty()) {
            return '';
        }
        String sentence = parts[0];
        for (Integer i = 1; i < parts.size(); i++) {
            sentence += (i == parts.size() - 1 ? ' and ' : ', ') + parts[i];
        }
        return sentence;
    }

    private static Result refused(Id recordId, String label, String reason) {
        Result result = new Result();
        result.recordId = recordId == null ? null : String.valueOf(recordId);
        result.recordLabel = label;
        result.outcome = REFUSED;
        result.routeChanged = false;
        result.summary =
            'The what-if could not be run for ' +
            (label == null ? 'this record' : label) +
            ': ' +
            AMF_AgentSupport.asSentence(reason) +
            ' Nothing was changed or submitted.';
        return result;
    }

    private static AMF_ApprovalMatrixService engine() {
        return engineOverride == null ? new AMF_ApprovalMatrixService() : engineOverride;
    }

    private static AMF_RuleProvider ruleProvider() {
        return ruleProviderOverride == null ? new AMF_CmdtRuleProvider() : ruleProviderOverride;
    }
}
