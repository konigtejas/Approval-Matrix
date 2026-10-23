/**
 * The Approval Matrix Assistant's Find Governed Record action (M13): turns what
 * a user calls a record -- PR-00000045, "the APAC laptops request", an Id --
 * into the record Id the other actions need.
 *
 * Architecture section: 3.2 (governed means the object has active rules),
 * 7 (its M13 note), 11 (security).
 *
 * OBJECT-AGNOSTIC, AS 3.2 REQUIRES. It searches every object the matrix
 * governs, and it learns which those are from the rules, through
 * AMF_RuleProvider -- the only sanctioned read of the matrix -- never from a
 * list of names here. Governing a third object needs no change to it.
 *
 * IN USER MODE THROUGHOUT. Every query and search runs as the user, so it
 * finds exactly the records they could open, and says so when it finds none.
 *
 * THREE PASSES, NARROWEST FIRST, so an exact answer is never buried under fuzzy
 * ones: an Id; then an exact name, which an auto-number such as PR-00000045 is;
 * then a search of every text field, which finds a request by its Request Name;
 * then, when the search index has nothing (a record created moments ago is not
 * indexed yet), a contains-match on the name. One match is the answer. Several
 * are listed for the user to choose from: picking one is never the agent's
 * guess.
 */
public with sharing class AMF_AgentFindRecord {

    /** Most matches listed for the user to choose from. */
    @TestVisible
    private static final Integer MAX_MATCHES = 5;

    /** SOSL's reserved characters, each escaped with a backslash in a search term. */
    private static final List<String> SOSL_RESERVED = new List<String>{
        '\\', '?', '&', '|', '!', '{', '}', '[', ']', '(', ')', '^', '~', '*', ':', '"', '\'', '+', '-'
    };

    /** What the user called the record. */
    public class Request {
        @InvocableVariable(
            label='Search Text'
            description='The record\'s name, number or Id as the user gave it, such as PR-00000045 or the name of an opportunity.'
            required=true
        )
        public String searchText;
    }

    /** The record found, or the candidates to choose from. */
    public class Result {
        @InvocableVariable(label='Match Count' description='How many records matched, up to six.')
        public Integer matchCount;

        @InvocableVariable(label='Record ID' description='The matching record\'s Id, when exactly one matched. Empty otherwise.')
        public String recordId;

        @InvocableVariable(label='Record' description='The matching record as a person names it, when exactly one matched.')
        public String recordLabel;

        @InvocableVariable(
            label='Matches'
            description='When several records matched: a numbered list of them, each with its Id, for the user to choose from.'
        )
        public String matches;

        @InvocableVariable(label='Message' description='What was found, in plain English, ready to give the user.')
        public String message;
    }

    /** One record found. */
    private class Match {
        private final Id recordId;
        private final String label;

        private Match(Id recordId, String label) {
            this.recordId = recordId;
            this.label = label;
        }
    }

    /** A governed object, with what searching it needs. */
    private class Governed {
        private final String apiName;
        private final String label;
        private final String nameField;

        private Governed(Schema.DescribeSObjectResult described, String nameField) {
            this.apiName = described.getName();
            this.label = described.getLabel();
            this.nameField = nameField;
        }
    }

    /**
     * Test seam: tests set this so the action learns the governed objects from
     * in-memory rules instead of the org's matrix. Always null in production.
     */
    @TestVisible
    private static AMF_RuleProvider ruleProviderOverride;

    /**
     * @param requests One per record the user named.
     * @return One result per request, in the same order.
     */
    @InvocableMethod(
        label='Find Governed Record'
        description='Finds records the approval matrix governs, such as Purchase Requests and Opportunities, by name, number or Id, among the records the user can see.'
        category='Approval Matrix'
    )
    public static List<Result> find(List<Request> requests) {
        List<Result> results = new List<Result>();

        if (requests == null || requests.isEmpty()) {
            return results;
        }

        List<Governed> governed = governedObjects();
        for (Request request : requests) {
            results.add(findOne(request?.searchText, governed));
        }
        return results;
    }

    private static Result findOne(String searchText, List<Governed> governed) {
        String text = searchText == null ? '' : searchText.normalizeSpace();

        if (String.isBlank(text)) {
            return answer(text, new List<Match>(), governed, 'Say which record you mean: its name, number or Id.');
        }
        if (governed.isEmpty()) {
            return answer(text, new List<Match>(), governed, 'The approval matrix governs no objects yet, so there is nothing to find.');
        }

        Id asId = AMF_AgentSupport.idOf(text);
        if (asId != null) {
            return byId(text, asId, governed);
        }

        List<Match> found = byExactName(text, governed);
        if (found.isEmpty()) {
            found = bySearch(text, governed);
        }
        if (found.isEmpty()) {
            found = byNameContaining(text, governed);
        }
        return answer(text, found, governed, null);
    }

    /** An Id: the record itself, if its object is governed and the user can read it. */
    private static Result byId(String text, Id recordId, List<Governed> governed) {
        String objectName = String.valueOf(recordId.getSObjectType());

        for (Governed candidate : governed) {
            if (candidate.apiName == objectName) {
                List<Match> found = query(
                    candidate,
                    'SELECT Id, ' + candidate.nameField + ' FROM ' + candidate.apiName + ' WHERE Id = :bound',
                    recordId,
                    1
                );
                return answer(text, found, governed, null);
            }
        }

        return answer(
            text,
            new List<Match>(),
            governed,
            'That Id belongs to the ' +
            recordId.getSObjectType().getDescribe().getLabel() +
            ' object, which the approval matrix does not govern.'
        );
    }

    private static List<Match> byExactName(String text, List<Governed> governed) {
        List<Match> found = new List<Match>();
        for (Governed candidate : governed) {
            found.addAll(
                query(
                    candidate,
                    'SELECT Id, ' + candidate.nameField + ' FROM ' + candidate.apiName +
                    ' WHERE ' + candidate.nameField + ' = :bound ORDER BY ' + candidate.nameField,
                    text,
                    MAX_MATCHES + 1
                )
            );
        }
        return found;
    }

    /** Every text field, through the search index: finds a request by its Request Name. */
    private static List<Match> bySearch(String text, List<Governed> governed) {
        List<Match> found = new List<Match>();

        // SOSL refuses a one-character term.
        if (text.length() < 2) {
            return found;
        }

        List<String> returning = new List<String>();
        for (Governed candidate : governed) {
            returning.add(
                candidate.apiName + '(Id, ' + candidate.nameField + ' ORDER BY ' + candidate.nameField +
                ' LIMIT ' + (MAX_MATCHES + 1) + ')'
            );
        }

        List<List<SObject>> hits;
        try {
            hits = Search.query(
                'FIND \'' + escapeSosl(text) + '\' IN ALL FIELDS RETURNING ' + String.join(returning, ', '),
                AccessLevel.USER_MODE
            );
        } catch (Exception e) {
            // A term the search engine refuses is a term to try as a name instead.
            return found;
        }

        for (Integer i = 0; i < hits.size() && i < governed.size(); i++) {
            for (SObject record : hits[i]) {
                found.add(matchOf(governed[i], record));
            }
        }
        return found;
    }

    private static List<Match> byNameContaining(String text, List<Governed> governed) {
        String pattern = '%' + text.replace('\\', '\\\\').replace('%', '\\%').replace('_', '\\_') + '%';
        List<Match> found = new List<Match>();

        for (Governed candidate : governed) {
            found.addAll(
                query(
                    candidate,
                    'SELECT Id, ' + candidate.nameField + ' FROM ' + candidate.apiName +
                    ' WHERE ' + candidate.nameField + ' LIKE :bound ORDER BY ' + candidate.nameField,
                    pattern,
                    MAX_MATCHES + 1
                )
            );
        }
        return found;
    }

    /**
     * One query in user mode, with its one value bound rather than spliced in.
     * Field and object names come from describe, never from the user.
     */
    private static List<Match> query(Governed candidate, String soql, Object bound, Integer maxRows) {
        List<Match> found = new List<Match>();

        for (SObject record : Database.queryWithBinds(
            soql + ' LIMIT ' + maxRows,
            new Map<String, Object>{ 'bound' => bound },
            AccessLevel.USER_MODE
        )) {
            found.add(matchOf(candidate, record));
        }
        return found;
    }

    private static Match matchOf(Governed candidate, SObject record) {
        Object name = record.get(candidate.nameField);
        return new Match(
            record.Id,
            candidate.label + ' ' + (name == null ? String.valueOf(record.Id) : String.valueOf(name))
        );
    }

    private static Result answer(String text, List<Match> found, List<Governed> governed, String explanation) {
        Result result = new Result();
        result.matchCount = found.size();

        if (explanation != null) {
            result.message = explanation;
        } else if (found.isEmpty()) {
            result.message =
                'No ' +
                labelsOf(governed) +
                ' that you can see matches "' +
                text.abbreviate(80) +
                '". Check the name or number, or open the record and ask again.';
        } else if (found.size() == 1) {
            result.recordId = String.valueOf(found[0].recordId);
            result.recordLabel = found[0].label;
            result.message = 'Found ' + found[0].label + '.';
        } else {
            List<String> lines = new List<String>();
            for (Integer i = 0; i < Math.min(found.size(), MAX_MATCHES); i++) {
                lines.add((i + 1) + '. ' + found[i].label + ' (Id ' + found[i].recordId + ')');
            }
            result.matches = String.join(lines, '\n');
            result.message =
                (found.size() > MAX_MATCHES ? 'More than ' + MAX_MATCHES : String.valueOf(found.size())) +
                ' records match "' +
                text.abbreviate(80) +
                '". Ask which one is meant.';
        }
        return result;
    }

    /** "Purchase Request or Opportunity", for a message that names what was searched. */
    private static String labelsOf(List<Governed> governed) {
        List<String> labels = new List<String>();
        for (Governed candidate : governed) {
            labels.add(candidate.label);
        }
        if (labels.isEmpty()) {
            return 'record';
        }

        String joined = labels[0];
        for (Integer i = 1; i < labels.size(); i++) {
            joined += (i == labels.size() - 1 ? ' or ' : ', ') + labels[i];
        }
        return joined;
    }

    /**
     * The objects the matrix governs (3.2: those with active rules), in
     * alphabetical order so results come back in a stable order. An object that
     * no longer exists, or has no name field to search, is left out.
     */
    private static List<Governed> governedObjects() {
        Set<String> names = new Set<String>();
        for (AMF_RuleDefinition rule : ruleProvider().getActiveRules()) {
            if (String.isNotBlank(rule.objectApiName)) {
                names.add(rule.objectApiName);
            }
        }

        List<String> sorted = new List<String>(names);
        sorted.sort();

        Map<String, Schema.SObjectType> globalDescribe = Schema.getGlobalDescribe();
        List<Governed> governed = new List<Governed>();

        for (String name : sorted) {
            Schema.SObjectType type = globalDescribe.get(name);
            if (type == null) {
                continue;
            }
            Schema.DescribeSObjectResult described = type.getDescribe();
            String nameField = nameFieldOf(described);
            if (nameField != null) {
                governed.add(new Governed(described, nameField));
            }
        }
        return governed;
    }

    private static String nameFieldOf(Schema.DescribeSObjectResult described) {
        for (Schema.SObjectField field : described.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (fieldDescribe.isNameField()) {
                return fieldDescribe.getName();
            }
        }
        return null;
    }

    private static String escapeSosl(String text) {
        String escaped = text;
        for (String reserved : SOSL_RESERVED) {
            escaped = escaped.replace(reserved, '\\' + reserved);
        }
        return escaped;
    }

    private static AMF_RuleProvider ruleProvider() {
        return ruleProviderOverride == null ? new AMF_CmdtRuleProvider() : ruleProviderOverride;
    }
}
