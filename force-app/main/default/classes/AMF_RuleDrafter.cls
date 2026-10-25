/**
 * Drafts one approval matrix rule from an administrator's description (M15), and
 * shows it only once it passes the checks the release gate would run.
 *
 * Architecture section: 1 (principle 6), 3.1 (the matrix), 4.1 (grammar),
 * 9 (configuration validator), 7 (its M15 note).
 *
 * A DRAFT ROUTES NOTHING. The model proposes a rule; this class decides whether
 * anyone sees it. Nothing here writes a rule, deploys metadata or activates
 * anything: the administrator releases the draft as an ordinary configuration
 * release, through source, the source gate, a deploy and the post-deploy check
 * (principle 1). The draft comes back as the Custom Metadata file to commit.
 *
 * WHAT THE MODEL IS GIVEN: the administrator's words, and the facts it may
 * draw on -- the object's rule-readable fields with their picklist values, the
 * object's active rules in priority order, its active approval processes, and
 * the names rules already use. The template carries the grammar (4.1) and
 * says to treat the context as data and to invent no field or process.
 *
 * WHAT IS CHECKED BEFORE ANYONE SEES IT, deterministically, as 9 checks a release:
 *   - the condition compiles against the object (AMF_ExprCompiler, 4.2);
 *   - the DeveloperName is a valid Custom Metadata name, new, or the name of
 *     the rule being changed;
 *   - the priority is a whole number from 1 to 9999 that no other active rule
 *     on the object uses;
 *   - the process is an active Classic approval process for the object;
 *   - the description fits Description__c and the condition fits Expression__c;
 *   - the one query the engine would run for the matrix with the draft in it
 *     is accepted by the platform (AMF_FieldPathResolver, 4.4).
 * A draft that fails goes back to the model once, with the reasons. If it
 * fails again, the administrator is told why, and shown no rule.
 *
 * KNOWN LIMIT: the name is checked against the active matrix, which is all
 * AMF_RuleProvider exposes (CLAUDE.md: Custom Metadata is read only through the
 * provider). An inactive rule of the same name would be overwritten by the
 * release; the draft's file name makes that visible in review.
 */
public with sharing class AMF_RuleDrafter {

    @TestVisible
    private static final String TEMPLATE_NAME = 'AMF_Draft_Matrix_Rule';

    /** One draft, and one corrected draft. A third would be guessing. */
    @TestVisible
    private static final Integer MAX_ATTEMPTS = 2;

    private static final Integer MAX_FIELDS = 150;
    private static final Integer MAX_VALUES = 25;
    private static final Integer MAX_REQUEST = 2000;
    private static final Integer MAX_NAME = 40;
    private static final Integer MAX_LABEL = 40;
    private static final Integer MAX_DESCRIPTION = 255;
    private static final Integer MAX_EXPRESSION = 2000;
    private static final Integer MIN_PRIORITY = 1;
    private static final Integer MAX_PRIORITY = 9999;

    /** A letter first; letters and digits, joined by single underscores; no trailing underscore. */
    private static final Pattern DEVELOPER_NAME = Pattern.compile('^[A-Za-z][A-Za-z0-9]*(_[A-Za-z0-9]+)*$');

    /** The field types a rule can read (4.3), as AMF_ExprCompiler accepts them. */
    private static final Set<Schema.DisplayType> READABLE_TYPES = new Set<Schema.DisplayType>{
        Schema.DisplayType.CURRENCY,
        Schema.DisplayType.DOUBLE,
        Schema.DisplayType.INTEGER,
        Schema.DisplayType.LONG,
        Schema.DisplayType.PERCENT,
        Schema.DisplayType.STRING,
        Schema.DisplayType.PICKLIST,
        Schema.DisplayType.ID,
        Schema.DisplayType.REFERENCE,
        Schema.DisplayType.BOOLEAN,
        Schema.DisplayType.DATE,
        Schema.DisplayType.MULTIPICKLIST
    };

    /** Mode values. */
    @TestVisible
    private static final String ADD = 'Add';
    @TestVisible
    private static final String REPLACE = 'Replace';

    /** A drafted rule, checked, and what to do with it. */
    public class Draft {
        /** True only when every check passed; then the rest describes the rule. */
        public Boolean valid = false;
        public String objectApiName;
        public String developerName;
        public String label;
        public Integer priority;
        public String expression;
        public String processApiName;
        public String description;
        public Integer version;
        /** Add, or Replace for a new version of an active rule. */
        public String mode;
        /** What the model assumed, in its own words: for the administrator to check. */
        public String assumptions;
        /** The Custom Metadata file to commit, and where. */
        public String metadataXml;
        public String filePath;
        /** Why the draft was refused. Empty when valid. */
        public List<String> problems = new List<String>();
        /** The draft, or the refusal, in plain English. */
        public String summary;
    }

    private final AMF_RuleProvider rules;
    private final AMF_PromptRunner runner;

    /**
     * Test seam: the active approval processes per object, because a
     * ProcessDefinition cannot be created in a test. Always null in production.
     */
    @TestVisible
    private static Map<String, Set<String>> activeProcessesOverride;

    /** Production wiring: the deployed matrix, drafted by Einstein. */
    public AMF_RuleDrafter() {
        this(new AMF_CmdtRuleProvider(), new AMF_EinsteinPromptRunner());
    }

    /**
     * @param rules  The live matrix.
     * @param runner What writes the first attempt.
     */
    public AMF_RuleDrafter(AMF_RuleProvider rules, AMF_PromptRunner runner) {
        this.rules = rules;
        this.runner = runner;
    }

    /**
     * Drafts one rule.
     *
     * @param objectApiName The governed object the rule is for.
     * @param request       What the administrator wants, in their words.
     * @param ruleToChange  DeveloperName of an active rule to write a new version
     *                      of, or blank for a new rule.
     * @return The checked draft: valid, or refused with its reasons.
     * @throws AMF_PromptException For no request, an ungoverned object, a rule
     *         to change that is not active on the object, or no generation.
     */
    public Draft draft(String objectApiName, String request, String ruleToChange) {
        if (String.isBlank(request)) {
            throw new AMF_PromptException(
                'Describe the rule you want: which records it should catch, and which approval process they should go to.'
            );
        }

        Schema.SObjectType sobjectType = String.isBlank(objectApiName) ? null : Schema.getGlobalDescribe().get(objectApiName);
        List<AMF_RuleDefinition> live = sobjectType == null ? new List<AMF_RuleDefinition>() : rules.getActiveRules(objectApiName);

        if (live.isEmpty()) {
            throw new AMF_PromptException(
                (String.isBlank(objectApiName) ? 'That object' : objectApiName) +
                ' is not governed by the approval matrix, so a rule cannot be drafted for it here. Governing a new ' +
                'object takes its guard field and approval processes first (arch doc 3.2).'
            );
        }

        AMF_RuleDefinition changing = null;
        if (String.isNotBlank(ruleToChange)) {
            for (AMF_RuleDefinition rule : live) {
                if (rule.developerName == ruleToChange.trim()) {
                    changing = rule;
                }
            }
            if (changing == null) {
                throw new AMF_PromptException(
                    'No active rule named ' + ruleToChange.trim() + ' governs ' +
                    sobjectType.getDescribe().getLabelPlural() + '. Name an active rule to change, or describe a new one.'
                );
            }
        }

        Set<String> processes = activeProcesses(objectApiName);
        String context = contextFor(sobjectType, live, processes, changing);
        String asked = request.trim().left(MAX_REQUEST);

        Draft result;
        List<String> problems = new List<String>();

        for (Integer attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
            String answer = runner.run(
                TEMPLATE_NAME,
                new Map<String, String>{ 'Request' => asked + feedbackOf(problems), 'Context' => context }
            );
            result = checked(sobjectType, parse(answer), live, processes, changing);
            if (result.valid) {
                break;
            }
            problems = result.problems;
        }
        return result;
    }

    // ── The context the model is given ─────────────────────────────────────────

    @TestVisible
    private String contextFor(
        Schema.SObjectType sobjectType,
        List<AMF_RuleDefinition> live,
        Set<String> processes,
        AMF_RuleDefinition changing
    ) {
        Schema.DescribeSObjectResult described = sobjectType.getDescribe();
        List<String> lines = new List<String>();

        lines.add('Object: ' + described.getLabel() + ' (API name ' + described.getName() + ')');
        lines.add('Fields a rule can read, as API name: label (type):');
        lines.addAll(fieldLines(described));

        lines.add('Active rules for this object, tried lowest priority first:');
        for (AMF_RuleDefinition rule : live) {
            lines.add(
                '- ' + rule.developerName + ': priority ' + rule.priority + ', version ' + rule.version +
                ', condition ' + rule.expression + ', process ' + rule.processApiName +
                (String.isBlank(rule.description) ? '' : '. ' + rule.description)
            );
        }

        List<String> processNames = new List<String>(processes);
        processNames.sort();
        lines.add(
            'Active approval processes for this object: ' +
            (processNames.isEmpty() ? 'none' : String.join(processNames, ', '))
        );

        List<String> names = new List<String>();
        for (AMF_RuleDefinition rule : rules.getActiveRules()) {
            names.add(rule.developerName);
        }
        names.sort();
        lines.add('Names active rules already use, on every object: ' + String.join(names, ', '));

        lines.add(
            changing == null
                ? 'This is a new rule: give it a new developerName.'
                : 'The rule to change: ' + changing.developerName + '. Keep its developerName; it gets a new version.'
        );
        return String.join(lines, '\n');
    }

    private static List<String> fieldLines(Schema.DescribeSObjectResult described) {
        List<Schema.DescribeFieldResult> readable = new List<Schema.DescribeFieldResult>();
        for (Schema.SObjectField field : described.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();
            if (READABLE_TYPES.contains(fieldDescribe.getType()) && fieldDescribe.isAccessible()) {
                readable.add(fieldDescribe);
            }
        }

        List<String> lines = new List<String>();
        Map<String, Schema.DescribeFieldResult> byName = new Map<String, Schema.DescribeFieldResult>();
        for (Schema.DescribeFieldResult fieldDescribe : readable) {
            byName.put(fieldDescribe.getName(), fieldDescribe);
        }
        List<String> fieldNames = new List<String>(byName.keySet());
        fieldNames.sort();

        for (String name : fieldNames) {
            if (lines.size() >= MAX_FIELDS) {
                break;
            }
            Schema.DescribeFieldResult fieldDescribe = byName.get(name);
            lines.add('- ' + name + ': ' + fieldDescribe.getLabel() + ' (' + typeOf(fieldDescribe) + ')');
        }
        return lines;
    }

    private static String typeOf(Schema.DescribeFieldResult fieldDescribe) {
        switch on fieldDescribe.getType() {
            when PICKLIST, MULTIPICKLIST {
                List<String> values = new List<String>();
                for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
                    if (entry.isActive() && values.size() < MAX_VALUES) {
                        values.add(entry.getValue());
                    }
                }
                return (fieldDescribe.getType() == Schema.DisplayType.MULTIPICKLIST ? 'multi-select picklist' : 'picklist') +
                    ': ' + String.join(values, ', ');
            }
            when REFERENCE {
                List<String> targets = new List<String>();
                for (Schema.SObjectType target : fieldDescribe.getReferenceTo()) {
                    targets.add(target.getDescribe().getName());
                }
                String relationship = fieldDescribe.getRelationshipName();
                return 'lookup to ' + String.join(targets, ' or ') +
                    (String.isBlank(relationship) ? '' : '; read its fields through ' + relationship + ', such as ' + relationship + '.Name');
            }
            when else {
                return String.valueOf(fieldDescribe.getType()).toLowerCase();
            }
        }
    }

    // ── Reading and checking the answer ────────────────────────────────────────

    /** The JSON object in the answer, fenced or not; null when there is none. */
    @TestVisible
    private static Map<String, Object> parse(String answer) {
        if (String.isBlank(answer)) {
            return null;
        }
        Integer start = answer.indexOf('{');
        Integer finish = answer.lastIndexOf('}');
        if (start < 0 || finish <= start) {
            return null;
        }
        try {
            Object parsed = JSON.deserializeUntyped(answer.substring(start, finish + 1));
            return parsed instanceof Map<String, Object> ? (Map<String, Object>) parsed : null;
        } catch (JSONException e) {
            return null;
        }
    }

    private static String feedbackOf(List<String> problems) {
        if (problems == null || problems.isEmpty()) {
            return '';
        }
        return '\n\nYour previous draft was refused by the checks, for these reasons. Correct it, and answer ' +
            'with the JSON object only:\n- ' + String.join(problems, '\n- ');
    }

    @TestVisible
    private Draft checked(
        Schema.SObjectType sobjectType,
        Map<String, Object> answer,
        List<AMF_RuleDefinition> live,
        Set<String> processes,
        AMF_RuleDefinition changing
    ) {
        Draft draft = new Draft();
        String objectApiName = sobjectType.getDescribe().getName();
        draft.objectApiName = objectApiName;

        if (answer == null) {
            draft.problems.add('The answer was not a rule draft in JSON.');
            return refused(draft);
        }

        draft.developerName = textOf(answer.get('developerName'));
        draft.label = textOf(answer.get('label'));
        draft.priority = wholeNumberOf(answer.get('priority'));
        draft.expression = textOf(answer.get('expression'));
        draft.processApiName = textOf(answer.get('processApiName'));
        draft.description = textOf(answer.get('description'));
        draft.assumptions = textOf(answer.get('assumptions'));

        checkName(draft, changing);
        checkPriority(draft, live, changing, objectApiName);
        checkProcess(draft, processes, objectApiName);
        checkDescription(draft);
        AMF_ExprCompiler.CompiledExpression compiled = checkCondition(draft, objectApiName);
        if (compiled != null) {
            checkQuery(draft, compiled, live, changing, objectApiName);
        }

        if (!draft.problems.isEmpty()) {
            return refused(draft);
        }

        draft.mode = changing == null ? ADD : REPLACE;
        draft.version = changing == null ? 1 : (changing.version == null ? 1 : changing.version) + 1;
        if (String.isBlank(draft.label)) {
            draft.label = draft.developerName.replace('_', ' ');
        }
        draft.label = draft.label.left(MAX_LABEL);
        draft.filePath = 'force-app/main/default/customMetadata/Approval_Matrix_Rule.' + draft.developerName + '.md-meta.xml';
        draft.metadataXml = xmlOf(draft);
        draft.valid = true;
        draft.summary = summaryOf(draft, live, changing, sobjectType);
        return draft;
    }

    private void checkName(Draft draft, AMF_RuleDefinition changing) {
        if (String.isBlank(draft.developerName)) {
            draft.problems.add('The draft has no developerName.');
            return;
        }
        if (draft.developerName.length() > MAX_NAME || !DEVELOPER_NAME.matcher(draft.developerName).matches()) {
            draft.problems.add(
                'developerName ' + draft.developerName + ' is not a valid name: it must start with a letter, use ' +
                'only letters, digits and single underscores, not end with an underscore, and be at most ' +
                MAX_NAME + ' characters.'
            );
            return;
        }
        if (changing != null) {
            if (draft.developerName != changing.developerName) {
                draft.problems.add('A new version of ' + changing.developerName + ' must keep the name ' + changing.developerName + '.');
            }
            return;
        }
        for (AMF_RuleDefinition rule : rules.getActiveRules()) {
            if (rule.developerName == draft.developerName) {
                draft.problems.add(
                    draft.developerName + ' is already the name of an active rule. Choose a new name, or say that ' +
                    'you want to change ' + draft.developerName + '.'
                );
                return;
            }
        }
    }

    private static void checkPriority(Draft draft, List<AMF_RuleDefinition> live, AMF_RuleDefinition changing, String objectApiName) {
        if (draft.priority == null || draft.priority < MIN_PRIORITY || draft.priority > MAX_PRIORITY) {
            draft.problems.add('The priority must be a whole number from ' + MIN_PRIORITY + ' to ' + MAX_PRIORITY + '.');
            return;
        }
        for (AMF_RuleDefinition rule : live) {
            if (rule.priority == draft.priority && (changing == null || rule.developerName != changing.developerName)) {
                draft.problems.add(
                    'Priority ' + draft.priority + ' is already used by rule ' + rule.developerName +
                    '. Active priorities on ' + objectApiName + ' must be unique.'
                );
                return;
            }
        }
    }

    private static void checkProcess(Draft draft, Set<String> processes, String objectApiName) {
        if (String.isBlank(draft.processApiName) || !processes.contains(draft.processApiName)) {
            List<String> names = new List<String>(processes);
            names.sort();
            draft.problems.add(
                (String.isBlank(draft.processApiName) ? 'The draft names no approval process' : draft.processApiName + ' is not an active approval process for ' + objectApiName) +
                '. The active ones are: ' + (names.isEmpty() ? 'none' : String.join(names, ', ')) + '.'
            );
        }
    }

    private static void checkDescription(Draft draft) {
        if (String.isBlank(draft.description)) {
            draft.problems.add('The draft has no description. Say in one sentence what the rule is for.');
        } else if (draft.description.length() > MAX_DESCRIPTION) {
            draft.problems.add('The description is longer than ' + MAX_DESCRIPTION + ' characters. Shorten it.');
        }
    }

    private static AMF_ExprCompiler.CompiledExpression checkCondition(Draft draft, String objectApiName) {
        if (String.isBlank(draft.expression)) {
            draft.problems.add('The draft has no condition.');
            return null;
        }
        if (draft.expression.length() > MAX_EXPRESSION) {
            draft.problems.add('The condition is longer than ' + MAX_EXPRESSION + ' characters.');
            return null;
        }
        try {
            return AMF_ExprCompiler.compile(objectApiName, draft.expression);
        } catch (AMF_ExpressionException e) {
            draft.problems.add('The condition does not compile: ' + e.getMessage());
            return null;
        }
    }

    /** 9's M11 check: the one query the engine would run for the matrix with the draft in it. */
    private static void checkQuery(
        Draft draft,
        AMF_ExprCompiler.CompiledExpression compiled,
        List<AMF_RuleDefinition> live,
        AMF_RuleDefinition changing,
        String objectApiName
    ) {
        List<AMF_ExprCompiler.CompiledExpression> all = new List<AMF_ExprCompiler.CompiledExpression>{ compiled };
        try {
            for (AMF_RuleDefinition rule : live) {
                if (changing == null || rule.developerName != changing.developerName) {
                    all.add(AMF_ExprCache.get(rule));
                }
            }
        } catch (AMF_ExpressionException e) {
            draft.problems.add('An active rule on ' + objectApiName + ' does not compile, so no draft can be checked: ' + e.getMessage());
            return;
        }

        String soql = AMF_FieldPathResolver.buildQuery(objectApiName, AMF_FieldPathResolver.unionPaths(all));
        // The bind the query's text names. Empty: the platform parses and checks
        // the query, and it reads nothing.
        Set<Id> recordIds = new Set<Id>();
        try {
            Database.query(soql);
        } catch (QueryException e) {
            draft.problems.add('The query the engine would run with this rule is refused by the platform: ' + e.getMessage());
        }
    }

    private static Draft refused(Draft draft) {
        draft.valid = false;
        draft.summary =
            'No draft could be written that passes the checks. ' +
            String.join(draft.problems, ' ') +
            ' Nothing was changed.';
        return draft;
    }

    // ── What the administrator gets ────────────────────────────────────────────

    private static String summaryOf(Draft draft, List<AMF_RuleDefinition> live, AMF_RuleDefinition changing, Schema.SObjectType sobjectType) {
        String objectLabel = sobjectType.getDescribe().getLabelPlural();
        String which = changing == null
            ? 'Draft rule ' + draft.developerName + ' (new, version 1)'
            : 'Draft version ' + draft.version + ' of rule ' + draft.developerName;

        return which + ' for ' + objectLabel + ': when ' + draft.expression + ', send the record to approval process ' +
            draft.processApiName + '. Priority ' + draft.priority + ': ' + orderOf(draft, live, changing) +
            ' It compiles, its priority is free, ' + draft.processApiName + ' is an active approval process for ' +
            objectLabel + ', and the engine\'s query for the matrix with it runs. It routes nothing until you ' +
            'release it: add the file ' + draft.filePath + ' to source, run the source gate, deploy, and run the ' +
            'post-deploy check.';
    }

    /** "it would be tried after PR_High_Value_APAC (10) and before PR_High_Risk (20)." */
    private static String orderOf(Draft draft, List<AMF_RuleDefinition> live, AMF_RuleDefinition changing) {
        AMF_RuleDefinition before = null;
        AMF_RuleDefinition after = null;

        for (AMF_RuleDefinition rule : live) {
            if (changing != null && rule.developerName == changing.developerName) {
                continue;
            }
            if (rule.priority < draft.priority) {
                before = rule;
            } else if (after == null) {
                after = rule;
            }
        }

        if (before == null && after == null) {
            return 'it would be the object\'s only rule.';
        }
        if (before == null) {
            return 'it would be tried first, before ' + after.developerName + ' (' + after.priority + ').';
        }
        if (after == null) {
            return 'it would be tried last, after ' + before.developerName + ' (' + before.priority + ').';
        }
        return 'it would be tried after ' + before.developerName + ' (' + before.priority + ') and before ' +
            after.developerName + ' (' + after.priority + ').';
    }

    /** The rule as a Custom Metadata file, in the form the repository's rules take. */
    @TestVisible
    private static String xmlOf(Draft draft) {
        List<String> lines = new List<String>{
            '<?xml version="1.0" encoding="UTF-8"?>',
            '<CustomMetadata xmlns="http://soap.sforce.com/2006/04/metadata" xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">',
            '    <label>' + escaped(draft.label) + '</label>',
            '    <protected>false</protected>'
        };
        lines.addAll(valueOf('Object_API_Name__c', 'xsd:string', draft.objectApiName));
        lines.addAll(valueOf('Priority__c', 'xsd:double', draft.priority + '.0'));
        lines.addAll(valueOf('Expression__c', 'xsd:string', draft.expression));
        lines.addAll(valueOf('Process_API_Name__c', 'xsd:string', draft.processApiName));
        lines.addAll(valueOf('Description__c', 'xsd:string', draft.description));
        lines.addAll(valueOf('Version__c', 'xsd:double', draft.version + '.0'));
        lines.addAll(valueOf('Active__c', 'xsd:boolean', 'true'));
        lines.add('</CustomMetadata>');
        return String.join(lines, '\n');
    }

    private static List<String> valueOf(String field, String xsdType, String value) {
        return new List<String>{
            '    <values>',
            '        <field>' + field + '</field>',
            '        <value xsi:type="' + xsdType + '">' + escaped(value) + '</value>',
            '    </values>'
        };
    }

    /** As the platform writes it: ampersands and angle brackets escaped, quotes left as they are. */
    private static String escaped(String value) {
        return value == null ? '' : value.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;');
    }

    private static String textOf(Object value) {
        return value == null ? null : String.valueOf(value).trim();
    }

    private static Integer wholeNumberOf(Object value) {
        if (value instanceof Integer) {
            return (Integer) value;
        }
        try {
            Decimal given = value instanceof Decimal ? (Decimal) value : Decimal.valueOf(String.valueOf(value).trim());
            return given == given.round(System.RoundingMode.DOWN) ? given.intValue() : null;
        } catch (Exception e) {
            return null;
        }
    }

    /** The object's active Classic approval processes, by DeveloperName. */
    private static Set<String> activeProcesses(String objectApiName) {
        if (activeProcessesOverride != null) {
            return activeProcessesOverride.containsKey(objectApiName)
                ? activeProcessesOverride.get(objectApiName)
                : new Set<String>();
        }
        return new ProcessReader().activeFor(objectApiName);
    }

    /** ProcessDefinition, read as the validator's catalog reads it (9). */
    private without sharing class ProcessReader {

        private Set<String> activeFor(String objectApiName) {
            Set<String> names = new Set<String>();
            for (ProcessDefinition definition : [
                SELECT DeveloperName
                FROM ProcessDefinition
                WHERE TableEnumOrId = :objectApiName AND Type = 'Approval' AND State = 'Active'
            ]) {
                names.add(definition.DeveloperName);
            }
            return names;
        }
    }
}
