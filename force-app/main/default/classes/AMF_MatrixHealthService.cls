/**
 * How the approval matrix has been doing (M15): counted from the decision log
 * and the approvals pending now, then summarised in plain English.
 *
 * Architecture section: 8 (auditability), 3.3 (the log), 1 (principle 6),
 * 7 (its M15 note).
 *
 * THE NUMBERS ARE APEX'S; THE WORDS ARE THE MODEL'S. Every figure is counted
 * here, deterministically, into plain-text facts:
 *   - decisions per governed object, by outcome, this period and the one before;
 *   - each rule's share of the object's routed decisions, and the catch-all's
 *     (a rule whose recorded condition is TRUE);
 *   - active rules that decided nothing in the period;
 *   - the most common recorded failure reasons;
 *   - the approvals pending now, per process, and how long the oldest has waited.
 * The AMF_Summarize_Matrix_Health template is then given those facts alone, and
 * asked what an administrator should look at. If Einstein cannot answer, the
 * counted facts still come back: the report never depends on the model.
 *
 * Read WITH USER_MODE, so an administrator with View All (11) sees every row.
 * The pending approvals are counted without sharing, as counts per process: no
 * record is named.
 */
public with sharing class AMF_MatrixHealthService {

    @TestVisible
    private static final Integer DEFAULT_DAYS = 30;

    @TestVisible
    private static final Integer MAX_DAYS = 365;

    /** Rows read per period at most; the facts say so when the limit is reached. */
    @TestVisible
    private static final Integer MAX_ROWS = 2000;

    @TestVisible
    private static final String TEMPLATE_NAME = 'AMF_Summarize_Matrix_Health';

    /** What a report answers when the administrator asks nothing in particular. */
    public static final String DEFAULT_QUESTION = 'How is the approval matrix doing, and what should an administrator look at?';

    private static final Integer MAX_REASONS = 3;
    private static final Integer MAX_REASON_LENGTH = 150;

    /** The report. */
    public class Report {
        public Integer days;
        /** The decisions counted in the period, across the objects reported on. */
        public Integer decisions = 0;
        public Integer blocked = 0;
        public Integer failed = 0;
        /** Every counted fact, one per line: what the summary was written from. */
        public String facts;
        /** Einstein's summary, or null when none could be written. */
        public String narrative;
        /** Why there is no summary, when there is none. */
        public String narrativeProblem;
    }

    /** One governed object's counts. */
    private class ObjectCounts {
        private final String apiName;
        private Integer total = 0;
        private Integer submitted = 0;
        private Integer blocked = 0;
        private Integer failed = 0;
        private Integer catchAll = 0;
        private Integer previousTotal = 0;
        private Integer previousSubmitted = 0;
        private Integer previousBlocked = 0;
        private Integer previousFailed = 0;
        private final Map<String, Integer> byRule = new Map<String, Integer>();
        private final Set<String> catchAllRules = new Set<String>();
        private final Map<String, Integer> reasons = new Map<String, Integer>();

        private ObjectCounts(String apiName) {
            this.apiName = apiName;
        }
    }

    private final AMF_RuleProvider rules;
    private final AMF_PromptRunner runner;

    /** Test seam: the pending approvals, because a ProcessInstance needs a real approval. Always null in production. */
    @TestVisible
    private static List<ProcessInstance> pendingOverride;

    /** Production wiring: the deployed matrix, summarised by Einstein. */
    public AMF_MatrixHealthService() {
        this(new AMF_CmdtRuleProvider(), new AMF_EinsteinPromptRunner());
    }

    public AMF_MatrixHealthService(AMF_RuleProvider rules, AMF_PromptRunner runner) {
        this.rules = rules;
        this.runner = runner;
    }

    /**
     * The counted facts, and Einstein's summary of them.
     *
     * @param days          The period, in days back from now; blank or out of
     *                      range for DEFAULT_DAYS.
     * @param objectApiName One governed object, or blank for all of them.
     * @param question      What the administrator asked; blank for DEFAULT_QUESTION.
     * @return The report. Its facts are always set.
     */
    public Report report(Integer days, String objectApiName, String question) {
        Report report = factsOf(days, objectApiName);
        try {
            report.narrative = runner.run(
                TEMPLATE_NAME,
                new Map<String, String>{
                    'Facts' => report.facts,
                    'Question' => String.isBlank(question) ? DEFAULT_QUESTION : question.normalizeSpace().left(500)
                }
            );
        } catch (AMF_PromptException e) {
            report.narrativeProblem = e.getMessage();
        }
        return report;
    }

    /**
     * The counted facts alone.
     *
     * @param days          The period, in days back from now.
     * @param objectApiName One governed object, or blank for all of them.
     * @return The report, without a summary.
     */
    public Report factsOf(Integer days, String objectApiName) {
        Report report = new Report();
        report.days = days == null || days < 1 || days > MAX_DAYS ? DEFAULT_DAYS : days;

        Datetime now = Datetime.now();
        Datetime start = now.addDays(-report.days);
        Datetime previousStart = start.addDays(-report.days);

        Map<String, List<AMF_RuleDefinition>> rulesByObject = new Map<String, List<AMF_RuleDefinition>>();
        for (AMF_RuleDefinition rule : rules.getActiveRules()) {
            if (String.isBlank(objectApiName) || rule.objectApiName == objectApiName) {
                if (!rulesByObject.containsKey(rule.objectApiName)) {
                    rulesByObject.put(rule.objectApiName, new List<AMF_RuleDefinition>());
                }
                rulesByObject.get(rule.objectApiName).add(rule);
            }
        }

        List<String> objects = new List<String>(rulesByObject.keySet());
        objects.sort();

        Map<String, ObjectCounts> countsByObject = new Map<String, ObjectCounts>();
        for (String apiName : objects) {
            countsByObject.put(apiName, new ObjectCounts(apiName));
        }

        Boolean capped = countPeriod(countsByObject, start, report);
        countPreviousPeriod(countsByObject, previousStart, start);

        List<String> lines = new List<String>();
        lines.add(
            'Period: the last ' + report.days + ' days, ' + AMF_AgentSupport.whenOf(start) + ' to ' +
            AMF_AgentSupport.whenOf(now) + ', compared with the ' + report.days + ' days before. Times are in ' +
            UserInfo.getTimeZone().getID() + '.'
        );
        if (objects.isEmpty()) {
            lines.add('No governed object' + (String.isBlank(objectApiName) ? '' : ' called ' + objectApiName) + ' has active rules.');
        }
        if (capped) {
            lines.add('Only the newest ' + MAX_ROWS + ' decisions of the period were counted.');
        }

        Map<String, List<String>> pendingByObject = pendingLines(new Set<String>(objects), now);

        for (String apiName : objects) {
            lines.addAll(objectLines(countsByObject.get(apiName), rulesByObject.get(apiName), pendingByObject.get(apiName)));
        }

        report.facts = String.join(lines, '\n');
        return report;
    }

    /** @return True when the period held more rows than were read. */
    private static Boolean countPeriod(Map<String, ObjectCounts> countsByObject, Datetime start, Report report) {
        Set<String> objects = countsByObject.keySet();
        List<Approval_Decision_Log__c> rows = [
            SELECT Object_API_Name__c, Outcome__c, Matched_Rule__c, Expression_Snapshot__c, Failure_Detail__c
            FROM Approval_Decision_Log__c
            WHERE Submitted_At__c >= :start AND Object_API_Name__c IN :objects
            WITH USER_MODE
            ORDER BY Submitted_At__c DESC
            LIMIT :MAX_ROWS
        ];

        for (Approval_Decision_Log__c row : rows) {
            ObjectCounts counts = countsByObject.get(row.Object_API_Name__c);
            if (counts == null) {
                continue;
            }
            counts.total++;
            report.decisions++;

            switch on row.Outcome__c {
                when 'Submitted' {
                    counts.submitted++;
                    String rule = String.isBlank(row.Matched_Rule__c) ? '(unnamed)' : row.Matched_Rule__c;
                    counts.byRule.put(rule, (counts.byRule.containsKey(rule) ? counts.byRule.get(rule) : 0) + 1);
                    if (isCatchAll(row.Expression_Snapshot__c)) {
                        counts.catchAll++;
                        counts.catchAllRules.add(rule);
                    }
                }
                when 'Blocked_No_Match' {
                    counts.blocked++;
                    report.blocked++;
                }
                when 'Failed' {
                    counts.failed++;
                    report.failed++;
                    String reason = reasonOf(row.Failure_Detail__c);
                    counts.reasons.put(reason, (counts.reasons.containsKey(reason) ? counts.reasons.get(reason) : 0) + 1);
                }
            }
        }
        return rows.size() == MAX_ROWS;
    }

    private static void countPreviousPeriod(Map<String, ObjectCounts> countsByObject, Datetime previousStart, Datetime start) {
        Set<String> objects = countsByObject.keySet();
        for (AggregateResult result : [
            SELECT Object_API_Name__c objectName, Outcome__c outcome, COUNT(Id) decisions
            FROM Approval_Decision_Log__c
            WHERE Submitted_At__c >= :previousStart AND Submitted_At__c < :start AND Object_API_Name__c IN :objects
            WITH USER_MODE
            GROUP BY Object_API_Name__c, Outcome__c
        ]) {
            ObjectCounts counts = countsByObject.get((String) result.get('objectName'));
            if (counts == null) {
                continue;
            }
            Integer decisions = (Integer) result.get('decisions');
            counts.previousTotal += decisions;
            switch on (String) result.get('outcome') {
                when 'Submitted' {
                    counts.previousSubmitted += decisions;
                }
                when 'Blocked_No_Match' {
                    counts.previousBlocked += decisions;
                }
                when 'Failed' {
                    counts.previousFailed += decisions;
                }
            }
        }
    }

    private static List<String> objectLines(ObjectCounts counts, List<AMF_RuleDefinition> active, List<String> pending) {
        Schema.SObjectType sobjectType = Schema.getGlobalDescribe().get(counts.apiName);
        String label = sobjectType == null ? counts.apiName : sobjectType.getDescribe().getLabel() + ' (' + counts.apiName + ')';
        List<String> lines = new List<String>{ label + ':' };

        lines.add(
            '- Decisions recorded: ' + counts.total + ' (previous period: ' + counts.previousTotal + '). Routed ' +
            counts.submitted + ', blocked ' + counts.blocked + ', failed ' + counts.failed + ' (previous period: routed ' +
            counts.previousSubmitted + ', blocked ' + counts.previousBlocked + ', failed ' + counts.previousFailed + ').'
        );

        if (counts.submitted > 0) {
            List<String> ruleNames = new List<String>(counts.byRule.keySet());
            ruleNames.sort();
            List<String> parts = new List<String>();
            for (String rule : ruleNames) {
                Integer decided = counts.byRule.get(rule);
                parts.add(
                    rule + ' ' + decided + ' (' + percentOf(decided, counts.submitted) + '%' +
                    (counts.catchAllRules.contains(rule) ? ', a catch-all: its condition is TRUE' : '') + ')'
                );
            }
            lines.add('- Routed decisions by rule: ' + String.join(parts, '; ') + '.');
            lines.add('- Catch-all share of routed decisions: ' + percentOf(counts.catchAll, counts.submitted) + '%.');
        }

        List<String> idle = new List<String>();
        for (AMF_RuleDefinition rule : active) {
            if (!counts.byRule.containsKey(rule.developerName)) {
                idle.add(rule.developerName + ' (priority ' + rule.priority + ')');
            }
        }
        lines.add(
            '- Active rules that routed nothing in the period: ' + (idle.isEmpty() ? 'none' : String.join(idle, ', ')) + '.'
        );

        if (!counts.reasons.isEmpty()) {
            lines.add('- Most common recorded failure reasons: ' + topReasons(counts.reasons) + '.');
        }

        lines.add(
            '- Approvals pending now: ' + (pending == null || pending.isEmpty() ? 'none' : String.join(pending, '; ')) + '.'
        );
        return lines;
    }

    /** "PR_Three_Level_Finance 5, the oldest waiting since 26 Aug 2026 (58 days)", per object. */
    private static Map<String, List<String>> pendingLines(Set<String> objects, Datetime now) {
        Map<String, List<String>> linesByObject = new Map<String, List<String>>();
        if (objects.isEmpty()) {
            return linesByObject;
        }

        Map<String, Integer> countByProcess = new Map<String, Integer>();
        Map<String, Datetime> oldestByProcess = new Map<String, Datetime>();
        Map<String, String> objectByProcess = new Map<String, String>();

        for (ProcessInstance instance : pendingOverride != null ? pendingOverride : new PendingReader().pendingFor(objects)) {
            String process = instance.ProcessDefinition?.DeveloperName;
            String objectName = instance.TargetObjectId == null ? null : String.valueOf(instance.TargetObjectId.getSObjectType());
            if (process == null || !objects.contains(objectName)) {
                continue;
            }
            countByProcess.put(process, (countByProcess.containsKey(process) ? countByProcess.get(process) : 0) + 1);
            if (!oldestByProcess.containsKey(process) || instance.CreatedDate < oldestByProcess.get(process)) {
                oldestByProcess.put(process, instance.CreatedDate);
            }
            objectByProcess.put(process, objectName);
        }

        List<String> processes = new List<String>(countByProcess.keySet());
        processes.sort();
        for (String process : processes) {
            String objectName = objectByProcess.get(process);
            if (!linesByObject.containsKey(objectName)) {
                linesByObject.put(objectName, new List<String>());
            }
            Datetime oldest = oldestByProcess.get(process);
            Integer waited = oldest == null ? 0 : oldest.date().daysBetween(now.date());
            linesByObject.get(objectName).add(
                process + ' ' + countByProcess.get(process) + ', the oldest waiting since ' +
                AMF_AgentSupport.whenOf(oldest) + ' (' + waited + ' day' + (waited == 1 ? '' : 's') + ')'
            );
        }
        return linesByObject;
    }

    private static String topReasons(Map<String, Integer> reasons) {
        List<String> remaining = new List<String>(reasons.keySet());
        remaining.sort();
        List<String> parts = new List<String>();

        while (!remaining.isEmpty() && parts.size() < MAX_REASONS) {
            Integer best = 0;
            for (Integer i = 1; i < remaining.size(); i++) {
                if (reasons.get(remaining[i]) > reasons.get(remaining[best])) {
                    best = i;
                }
            }
            parts.add('"' + remaining[best] + '" (' + reasons.get(remaining[best]) + ')');
            remaining.remove(best);
        }
        return String.join(parts, '; ');
    }

    @TestVisible
    private static Boolean isCatchAll(String expression) {
        return expression != null && expression.trim().equalsIgnoreCase('TRUE');
    }

    private static String reasonOf(String detail) {
        if (String.isBlank(detail)) {
            return 'no reason recorded';
        }
        return detail.split('\r?\n')[0].trim().abbreviate(MAX_REASON_LENGTH);
    }

    private static Integer percentOf(Integer part, Integer whole) {
        if (whole == null || whole == 0) {
            return 0;
        }
        return (Decimal.valueOf(part) * 100 / whole).setScale(0, System.RoundingMode.HALF_UP).intValue();
    }

    /** Counts pending approvals per process; names no record. */
    private without sharing class PendingReader {

        private List<ProcessInstance> pendingFor(Set<String> objects) {
            return [
                SELECT TargetObjectId, CreatedDate, ProcessDefinition.DeveloperName
                FROM ProcessInstance
                WHERE Status = 'Pending' AND ProcessDefinition.TableEnumOrId IN :objects
                ORDER BY CreatedDate ASC
                LIMIT 2000
            ];
        }
    }
}
