/**
 * Explains a recorded approval decision in plain English: why the matrix sent
 * a record where it did, and where that approval stands now.
 *
 * Architecture section: 8 (auditability, and its M13 note), 11 (security),
 * 6.4 (why nothing is cached), 4.6 (where failing loudly applies).
 *
 * AI AROUND THE ENGINE, NEVER INSIDE IT (M13). The decision was made by the
 * engine and recorded before anything here runs. This class reads that record
 * and asks a model to say what it means. It decides nothing, writes nothing,
 * and stores nothing it is given: the decision log stays the only record of
 * why, and the timeline shows it beside every explanation.
 *
 * THE FACTS ARE THE TIMELINE'S, AND NOTHING ELSE. The model is handed one
 * entry of AMF_DecisionTimelineService's timeline, written out as plain text:
 *   - the row's own snapshot -- rule DeveloperName, version, expression, the
 *     values read, the process, the outcome and its recorded reason -- never
 *     today's matrix, for the reason 8 exists (its M7 note);
 *   - the native approval history the timeline shows with it.
 * The timeline has already applied both of 8's visibility rules -- record read
 * access, then the log row in user mode -- so an explanation can only contain
 * what the reader could already open. A routing reason the reader cannot see
 * is said to be not visible, not guessed at.
 *
 * NOT CACHED, for 6.4's reason: the history half moves as approvers act, and
 * an explanation of yesterday's state presented as today's would mislead.
 *
 * FAILURE. An explanation is presentation, so 4.6's fail-loudly rule is met by
 * telling the reader plainly that none could be given, and why -- never by
 * showing a guess. Nothing about the route or the row depends on it.
 */
public with sharing class AMF_DecisionExplainer {

    /** What an explanation answers when the reader asks nothing in particular. */
    public static final String DEFAULT_QUESTION = 'Why did this record go where it went, and where does its approval stand now?';

    /** Longest question passed on to the model. The rest is cut, not refused. */
    @TestVisible
    private static final Integer MAX_QUESTION_LENGTH = 500;

    /** Longest recorded reason or approver comment written into the facts. */
    @TestVisible
    private static final Integer MAX_TEXT_LENGTH = 500;

    /** Outcome__c values (3.3). The switch statements below repeat them as literals, which Apex requires. */
    private static final String SUBMITTED = 'Submitted';
    private static final String BLOCKED_NO_MATCH = 'Blocked_No_Match';

    /** The AMF_DecisionTimelineService.Value kind for a snapshot that was not field values. */
    private static final String KIND_UNPARSED = 'unparsed';

    /** ProcessInstance.Status, as a person reads it. */
    private static final Map<String, String> APPROVAL_STATUS = new Map<String, String>{
        'Pending' => 'in approval, still pending',
        'Approved' => 'approved, final',
        'Rejected' => 'rejected, final',
        'Removed' => 'recalled'
    };

    /** What explainDecision and the agent's action return. */
    public class Explanation {

        /** The explanation, as the model wrote it. */
        @AuraEnabled
        public String text;

        /** The decision log row explained. Null when the reader cannot see the row. */
        @AuraEnabled
        public Id logId;

        /** That row's auto-number, ADL-00000000. */
        @AuraEnabled
        public String logName;

        /** When the explanation was written. */
        @AuraEnabled
        public Datetime generatedAt;
    }

    private final AMF_DecisionTimelineService timeline;
    private final AMF_ExplanationGenerator generator;

    /** Production wiring: Classic approval history, explained by Einstein. */
    public AMF_DecisionExplainer() {
        this(new AMF_DecisionTimelineService(), new AMF_EinsteinExplanationGenerator());
    }

    /**
     * The seam 10 asks for: tests inject a timeline over in-memory history and a
     * generator that records what it was given.
     *
     * @param timeline  Where the decision and its history are read from.
     * @param generator What puts them into plain English.
     */
    public AMF_DecisionExplainer(AMF_DecisionTimelineService timeline, AMF_ExplanationGenerator generator) {
        this.timeline = timeline;
        this.generator = generator;
    }

    /**
     * The entry point behind amfDecisionExplanation, the timeline entry's
     * Explain button.
     *
     * Deliberately not cacheable=true: see the class comment.
     *
     * @param logId The decision log row to explain.
     * @return Its explanation.
     * @throws AuraHandledException Carrying the reason, written for the reader,
     *         when the decision is not visible or no explanation could be given.
     */
    @AuraEnabled
    public static Explanation explainDecision(Id logId) {
        try {
            return new AMF_DecisionExplainer().explain(logId);
        } catch (Exception e) {
            // setMessage as well as the constructor, as in AMF_ApprovalMatrixService:
            // without it the client sees "Script-thrown exception".
            AuraHandledException handled = new AuraHandledException(e.getMessage());
            handled.setMessage(e.getMessage());
            throw handled;
        }
    }

    /**
     * Explains one recorded decision.
     *
     * @param logId The decision log row.
     * @return The explanation of that row and of the approval it started.
     * @throws AMF_ExplanationException When the row or its record is not
     *         visible to the reader, or no explanation could be generated.
     */
    public Explanation explain(Id logId) {
        if (logId == null) {
            throw new AMF_ExplanationException('A decision is required to explain.');
        }

        // In user mode: a row the reader cannot open is a row they cannot have
        // explained, which is the timeline's own rule (8's M7 note).
        List<Approval_Decision_Log__c> rows = [
            SELECT Id, Record_Id__c
            FROM Approval_Decision_Log__c
            WHERE Id = :logId
            WITH USER_MODE
            LIMIT 1
        ];

        if (rows.isEmpty()) {
            throw new AMF_ExplanationException('This decision is not visible to you, so it cannot be explained.');
        }

        Id recordId = recordIdOf(rows[0].Record_Id__c);

        for (AMF_DecisionTimelineService.Entry entry : timelineOf(recordId).entries) {
            if (entry.decision != null && entry.decision.logId == logId) {
                return explain(recordId, entry, DEFAULT_QUESTION);
            }
        }

        // The row is readable but older than the newest entries the timeline reads.
        throw new AMF_ExplanationException(
            'This decision is not among the most recent ones on the record, so it cannot be explained here. ' +
            'Its decision log row still holds everything that was recorded.'
        );
    }

    /**
     * Explains the newest approval attempt on a record: the agent's question,
     * "why is this where it is?", asked of the record on screen.
     *
     * @param recordId The governed record.
     * @param question What the reader asked; blank for DEFAULT_QUESTION.
     * @return The explanation of the newest timeline entry.
     * @throws AMF_ExplanationException When the record is not visible, has
     *         never been submitted, or no explanation could be generated.
     */
    public Explanation explainLatest(Id recordId, String question) {
        if (recordId == null) {
            throw new AMF_ExplanationException('A record is required to explain its approval.');
        }

        AMF_DecisionTimelineService.Timeline story = timelineOf(recordId);

        if (story.entries.isEmpty()) {
            throw new AMF_ExplanationException(
                recordLabelOf(recordId) +
                ' has not been submitted for approval yet, so there is no decision to explain.'
            );
        }
        return explain(recordId, story.entries[0], questionOf(question));
    }

    private Explanation explain(Id recordId, AMF_DecisionTimelineService.Entry entry, String question) {
        Explanation explanation = new Explanation();
        explanation.text = generator.generate(factsOf(recordLabelOf(recordId), entry), question);
        explanation.logId = entry.decision?.logId;
        explanation.logName = entry.decision?.logName;
        explanation.generatedAt = Datetime.now();
        return explanation;
    }

    /** The timeline, with its refusal reworded for someone who asked for an explanation. */
    private AMF_DecisionTimelineService.Timeline timelineOf(Id recordId) {
        try {
            return timeline.build(recordId);
        } catch (AMF_DecisionTimelineService.TimelineException e) {
            throw new AMF_ExplanationException(
                'You need read access to this record to have its approval explained.'
            );
        }
    }

    private static Id recordIdOf(String recorded) {
        try {
            return Id.valueOf(recorded);
        } catch (Exception e) {
            throw new AMF_ExplanationException(
                'This decision does not name a record that can be read, so it cannot be explained.'
            );
        }
    }

    private static String questionOf(String question) {
        String asked = question == null ? '' : question.normalizeSpace();
        return String.isBlank(asked) ? DEFAULT_QUESTION : asked.left(MAX_QUESTION_LENGTH);
    }

    // ── The facts ──────────────────────────────────────────────────────────────

    /**
     * One timeline entry as the plain text the model is given. Deterministic, so
     * a test can pin exactly what reaches the model; labelled line by line, so
     * the template can tell the model which line answers what.
     *
     * @param recordLabel The record as a person names it: Purchase Request PR-00000045.
     * @param entry       One submission attempt, as the timeline built it.
     * @return The facts, one per line.
     */
    @TestVisible
    private static String factsOf(String recordLabel, AMF_DecisionTimelineService.Entry entry) {
        List<String> lines = new List<String>();
        lines.add('Record: ' + recordLabel);
        lines.add('Times are in the reader\'s time zone, ' + UserInfo.getTimeZone().getID() + '.');

        if (entry.decision == null) {
            lines.add(
                'Routing decision: not visible to the reader. The decision log row that explains why this ' +
                'record went to this approval process is not shared with them, so the reason cannot be given.'
            );
        } else {
            addDecision(lines, entry.decision);
        }

        if (entry.approval != null) {
            addApproval(lines, entry.approval);
        } else if (entry.decision?.outcome == SUBMITTED) {
            lines.add('Approval history: not available.');
        }
        return String.join(lines, '\n');
    }

    private static void addDecision(List<String> lines, AMF_DecisionTimelineService.Decision decision) {
        lines.add(
            'Decision log row: ' +
            decision.logName +
            ', recorded ' +
            timeOf(decision.submittedAt) +
            ' by ' +
            (String.isBlank(decision.submittedByName) ? 'an unknown user' : decision.submittedByName)
        );

        String rule = ruleOf(decision);

        switch on decision.outcome {
            when 'Submitted' {
                lines.add(
                    'Outcome: Submitted. The matrix routed the record to approval process ' +
                    decision.selectedProcess +
                    ', and the record entered it.'
                );
                lines.add('Rule that decided the route: ' + rule);
            }
            when 'Blocked_No_Match' {
                lines.add(
                    'Outcome: Blocked. No active rule matched, so the matrix blocked the submission ' +
                    'instead of routing it by default. The record did not enter an approval process.'
                );
            }
            when 'Failed' {
                lines.add('Outcome: Failed. The record did not enter an approval process.');
                if (rule != null) {
                    lines.add('Rule the matrix was applying: ' + rule);
                }
                if (String.isNotBlank(decision.selectedProcess)) {
                    lines.add('Approval process the matrix chose: ' + decision.selectedProcess);
                }
            }
            when else {
                lines.add(
                    'Outcome: ' +
                    (String.isBlank(decision.outcome) ? 'none was recorded.' : decision.outcome + '.')
                );
            }
        }

        if (String.isNotBlank(decision.expression)) {
            lines.add('Rule condition, as recorded: ' + decision.expression);
        }

        String values = valuesOf(decision.values);
        if (values != null) {
            lines.add(
                (decision.outcome == BLOCKED_NO_MATCH
                    ? 'Field values the matrix read while checking every rule: '
                    : 'Field values the rule read: ') + values
            );
        } else if (decision.outcome == SUBMITTED) {
            lines.add('Field values the rule read: none. Its condition reads no fields, so it matches every record.');
        }

        if (decision.outcome != SUBMITTED && String.isNotBlank(decision.detail)) {
            lines.add('Recorded reason: ' + firstLineOf(decision.detail));
        }
    }

    private static void addApproval(List<String> lines, AMF_ApprovalHistory.Instance approval) {
        String status = APPROVAL_STATUS.containsKey(approval.status)
            ? APPROVAL_STATUS.get(approval.status)
            : approval.status;

        lines.add('Approval process: ' + approval.processName + ', status: ' + status);

        if (approval.steps == null || approval.steps.isEmpty()) {
            return;
        }

        lines.add('Approval steps, oldest first:');
        for (AMF_ApprovalHistory.Step step : approval.steps) {
            lines.add('- ' + stepOf(step));
        }
    }

    /** One approval step as a sentence fragment: what happened, who, and when. */
    private static String stepOf(AMF_ApprovalHistory.Step step) {
        String actor = String.isBlank(step.actorName) ? 'an unknown user' : step.actorName;
        String occurred = timeOf(step.occurredAt);
        String named = String.isBlank(step.stepName) ? '' : 'Step "' + step.stepName + '": ';
        String text;

        if (step.status == 'Started') {
            text = 'Submitted by ' + actor + ', ' + occurred;
        } else if (step.isPending == true) {
            text = named + 'waiting on ' + actor + ' since ' + occurred;
        } else if (step.status == 'Removed') {
            text = 'Recalled by ' + actor + ', ' + occurred;
        } else if (step.status == 'NoResponse') {
            text = named + 'no response from ' + actor + '; another approver decided the step, ' + occurred;
        } else {
            text = named + (String.isBlank(step.status) ? 'unknown' : step.status.toLowerCase()) + ' by ' + actor;
            // A delegate, or an admin acting on someone's behalf: whose step it was.
            if (step.originalActorId != null && step.originalActorId != step.actorId && String.isNotBlank(step.originalActorName)) {
                text += ', for ' + step.originalActorName;
            }
            text += ', ' + occurred;
        }

        if (String.isNotBlank(step.comments)) {
            text += '. Comment: "' + step.comments.normalizeSpace().abbreviate(MAX_TEXT_LENGTH) + '"';
        }
        return text;
    }

    /** PR_High_Value_APAC, version 3: the name and version the row recorded. */
    private static String ruleOf(AMF_DecisionTimelineService.Decision decision) {
        if (String.isBlank(decision.matchedRule)) {
            return null;
        }
        return decision.ruleVersion == null
            ? decision.matchedRule
            : decision.matchedRule + ', version ' + decision.ruleVersion;
    }

    /**
     * "Risk Level (Risk_Level__c) = Medium; Amount (Amount__c) = 60,000". The
     * label lets the model speak as the page does; the path lets it match each
     * value to the recorded condition, which is written in paths.
     */
    @TestVisible
    private static String valuesOf(List<AMF_DecisionTimelineService.Value> values) {
        if (values == null || values.isEmpty()) {
            return null;
        }

        List<String> parts = new List<String>();
        for (AMF_DecisionTimelineService.Value value : values) {
            if (value.kind == KIND_UNPARSED) {
                parts.add('as recorded, ' + value.text);
                continue;
            }
            String label = String.isBlank(value.label) || value.label == value.path
                ? value.path
                : value.label + ' (' + value.path + ')';
            parts.add(label + ' = ' + displayOf(value));
        }
        return String.join(parts, '; ');
    }

    /**
     * A recorded value as it reads. Shared with the agent's preview, so a value
     * reads the same before a submission as after it.
     */
    public static String displayOf(AMF_DecisionTimelineService.Value value) {
        switch on value.kind {
            when 'number' {
                return numberOf(value.text);
            }
            when 'boolean' {
                return value.text == 'true' ? 'TRUE' : 'FALSE';
            }
            when 'blank' {
                return '(blank)';
            }
            when else {
                return value.text == null ? '' : value.text;
            }
        }
    }

    /** 2400000.00 as 2,400,000 and 12.50 as 12.5, in the reader's locale. */
    private static String numberOf(String text) {
        if (String.isBlank(text)) {
            return '';
        }
        try {
            Decimal amount = Decimal.valueOf(text).stripTrailingZeros();
            if (amount.scale() < 0) {
                amount = amount.setScale(0);
            }
            return amount.format();
        } catch (Exception e) {
            return text;
        }
    }

    /** The first line of a recorded reason: the message, without any stack trace after it. */
    private static String firstLineOf(String text) {
        return text.split('\r?\n')[0].trim().abbreviate(MAX_TEXT_LENGTH);
    }

    private static String timeOf(Datetime value) {
        return value == null ? 'at an unknown time' : value.format('d MMM yyyy, HH:mm');
    }

    /**
     * The record as a person names it, read in user mode: "Purchase Request
     * PR-00000045". Falls back to the Id, which still identifies it, when the
     * object has no name field or the name cannot be read.
     */
    public static String recordLabelOf(Id recordId) {
        Schema.DescribeSObjectResult described = recordId.getSObjectType().getDescribe();
        String nameField = nameFieldOf(described);

        if (nameField != null) {
            try {
                List<SObject> rows = Database.query(
                    'SELECT ' + nameField + ' FROM ' + described.getName() + ' WHERE Id = :recordId LIMIT 1',
                    AccessLevel.USER_MODE
                );
                if (!rows.isEmpty() && rows[0].get(nameField) != null) {
                    return described.getLabel() + ' ' + String.valueOf(rows[0].get(nameField));
                }
            } catch (Exception e) {
                // An unreadable name is not a reason to withhold the explanation.
            }
        }
        return described.getLabel() + ' ' + recordId;
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
