/**
 * What the Approval Matrix Assistant's actions share (M13): reading the record
 * Id the agent passes as text, and writing a decision's values as a sentence.
 * M14's listing actions add three: several records' labels at once, approvers'
 * names, and a time as the explanations write it.
 *
 * Architecture section: 7 (entry points, and its M13 note).
 *
 * The agent passes record Ids as text, because that is how Agent Script hands
 * over the page's record and what the model copies from one action's output to
 * the next action's input. A model can also pass a name where an Id belongs,
 * so every action reads its input through idOf() and answers a non-Id plainly
 * instead of failing.
 */
public with sharing class AMF_AgentSupport {

    /** The Value kind the timeline gives a snapshot that is not field values. */
    private static final String KIND_UNPARSED = 'unparsed';

    /**
     * @param reference Text that should be a 15- or 18-character record Id.
     * @return The Id, or null when the text is not the Id of an object in this org.
     */
    public static Id idOf(String reference) {
        if (String.isBlank(reference)) {
            return null;
        }

        String trimmed = reference.trim();
        if (trimmed.length() != 15 && trimmed.length() != 18) {
            return null;
        }

        try {
            Id parsed = Id.valueOf(trimmed);
            return parsed.getSObjectType() == null ? null : parsed;
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * Why a reference could not be used, written to follow "cannot be
     * submitted: " or "cannot be explained: ".
     */
    public static String notAnId(String reference) {
        return String.isBlank(reference)
            ? 'no record was given. Open the record, or say its name or number so that it can be looked up.'
            : '"' + reference.trim().abbreviate(80) + '" is not a Salesforce record Id. Look the record up by its name or number first.';
    }

    /**
     * A reason the engine or the platform gave, ended as a sentence, so that the
     * sentence a summary adds after it does not run on from it.
     */
    public static String asSentence(String text) {
        String trimmed = text == null ? '' : text.trim();
        if (String.isBlank(trimmed)) {
            return 'No reason was given.';
        }
        return trimmed.endsWith('.') || trimmed.endsWith('!') || trimmed.endsWith('?') ? trimmed : trimmed + '.';
    }

    /**
     * "Risk Level = Medium and Amount = 60,000": the values a decision rested
     * on, labelled and formatted as the record page's timeline shows them.
     *
     * @param valuesJson The decision's evaluated values, as 3.3 records them.
     * @param rootType   The governed object the field paths start from.
     * @return The sentence, or null when nothing was read.
     */
    public static String sentenceOf(String valuesJson, Schema.SObjectType rootType) {
        List<String> parts = new List<String>();

        for (AMF_DecisionTimelineService.Value value : AMF_DecisionTimelineService.describeValues(valuesJson, rootType)) {
            if (value.kind == KIND_UNPARSED) {
                parts.add(value.text);
            } else {
                parts.add(
                    (String.isBlank(value.label) ? value.path : value.label) +
                    ' = ' +
                    AMF_DecisionExplainer.displayOf(value)
                );
            }
        }

        if (parts.isEmpty()) {
            return null;
        }

        String sentence = parts[0];
        for (Integer i = 1; i < parts.size(); i++) {
            sentence += (i == parts.size() - 1 ? ' and ' : ', ') + parts[i];
        }
        return sentence;
    }

    /**
     * Several records as people name them, "Purchase Request PR-00000045", read
     * in user mode with one query per object (M14): the bulk form of
     * AMF_DecisionExplainer.recordLabelOf, for actions that list records. A
     * record whose name cannot be read is named by its object and Id.
     */
    public static Map<Id, String> labelsOf(Set<Id> recordIds) {
        Map<Id, String> labels = new Map<Id, String>();
        Map<Schema.SObjectType, Set<Id>> idsByType = new Map<Schema.SObjectType, Set<Id>>();

        for (Id recordId : recordIds) {
            if (recordId == null) {
                continue;
            }
            Schema.SObjectType sobjectType = recordId.getSObjectType();
            if (!idsByType.containsKey(sobjectType)) {
                idsByType.put(sobjectType, new Set<Id>());
            }
            idsByType.get(sobjectType).add(recordId);
            labels.put(recordId, sobjectType.getDescribe().getLabel() + ' ' + recordId);
        }

        for (Schema.SObjectType sobjectType : idsByType.keySet()) {
            Schema.DescribeSObjectResult described = sobjectType.getDescribe();
            String nameField = nameFieldOf(described);
            if (nameField == null) {
                continue;
            }

            Set<Id> bound = idsByType.get(sobjectType);
            try {
                for (SObject row : Database.query(
                    'SELECT Id, ' + nameField + ' FROM ' + described.getName() + ' WHERE Id IN :bound',
                    AccessLevel.USER_MODE
                )) {
                    if (row.get(nameField) != null) {
                        labels.put(row.Id, described.getLabel() + ' ' + String.valueOf(row.get(nameField)));
                    }
                }
            } catch (Exception e) {
                // An unreadable name is not a reason to withhold the list.
            }
        }
        return labels;
    }

    /**
     * Approvers as people name them: a user's name or a queue's (M14). Read by
     * Id, never through Actor.Name, which the platform leaves null on work items
     * created in the running transaction (docs/decisions.md, 2026-10-23).
     */
    public static Map<Id, String> actorNamesOf(Set<Id> actorIds) {
        Map<Id, String> names = new Map<Id, String>();
        if (actorIds == null || actorIds.isEmpty()) {
            return names;
        }
        for (User person : [SELECT Id, Name FROM User WHERE Id IN :actorIds]) {
            names.put(person.Id, person.Name);
        }
        for (Group queue : [SELECT Id, Name FROM Group WHERE Id IN :actorIds]) {
            names.put(queue.Id, queue.Name);
        }
        return names;
    }

    /** A time as the explanations write it, in the reader's time zone: 23 Oct 2026, 10:17. */
    public static String whenOf(Datetime value) {
        return value == null ? 'an unknown time' : value.format('d MMM yyyy, HH:mm');
    }

    private static String nameFieldOf(Schema.DescribeSObjectResult described) {
        for (Schema.SObjectField field : described.fields.getMap().values()) {
            if (field.getDescribe().isNameField()) {
                return field.getDescribe().getName();
            }
        }
        return null;
    }
}
