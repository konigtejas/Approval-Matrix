/**
 * What a change to the matrix would do to real records, before it is released
 * (M15): the object's recently decided records, previewed by the engine under
 * the live matrix and under the matrix with the change, compared.
 *
 * Architecture section: 6.4 (preview, and its M15 note), 3.1 (the matrix),
 * 1 (principle 6), 7 (its M15 note).
 *
 * THE ENGINE DECIDES BOTH SIDES. AMF_ApprovalMatrixService.previewEach() runs
 * steps 1 to 7 for each record, writing nothing, over AMF_CmdtRuleProvider and
 * then over AMF_DraftRuleProvider. No model takes part: the comparison is
 * deterministic, and every route in it is one the engine would take.
 *
 * WHICH RECORDS. The distinct records of the object with a decision log row in
 * the last 90 days, newest first, at most 200: the matrix's own recent traffic,
 * read in user mode, so an administrator sees every row (View All, 11). They
 * are evaluated on their values today, not on the values recorded at the time,
 * because a row records only what the deciding rule read (3.3), and a changed
 * rule may read something else. The report says so.
 *
 * WHAT IS SKIPPED. A record the engine refuses on either side -- one in an
 * approval process now, or one the administrator cannot read -- is counted as
 * skipped, not compared. If the change leaves the matrix unable to decide at
 * all (its last rule taken out, a condition that does not compile), the report
 * says what the engine said, for every record.
 */
public with sharing class AMF_MatrixImpact {

    @TestVisible
    private static final Integer DAYS = 90;

    @TestVisible
    private static final Integer MAX_RECORDS = 200;

    @TestVisible
    private static final Integer MAX_LISTED = 10;

    private static final String REFUSED = 'Refused';

    /** What the change would do. */
    public class Report {
        /** False when the comparison could not run at all; Summary says why. */
        public Boolean ran = false;
        /** Records compared. */
        public Integer checked = 0;
        /** Of those, how many would be decided differently: another rule, or another process. */
        public Integer changed = 0;
        /** Records skipped: in an approval process now, or unreadable. */
        public Integer skipped = 0;
        /** One line per changed record, at most MAX_LISTED, each with its Id. */
        public List<String> changes = new List<String>();
        /** The comparison in plain English. */
        public String summary;
    }

    private final AMF_RuleProvider live;

    /** Production wiring: the deployed matrix. */
    public AMF_MatrixImpact() {
        this(new AMF_CmdtRuleProvider());
    }

    /** @param live The matrix the change is compared against. */
    public AMF_MatrixImpact(AMF_RuleProvider live) {
        this.live = live;
    }

    /**
     * @param objectApiName The governed object.
     * @param removedRule   DeveloperName of the active rule to take out, or null.
     * @param addedRule     The rule to put in, or null. Same name as removedRule
     *                      for a new version; it must then carry a new version.
     * @param changeLabel   The change as a person names it, for the summary.
     * @return The comparison. Never throws for the engine's answers.
     */
    public Report check(String objectApiName, String removedRule, AMF_RuleDefinition addedRule, String changeLabel) {
        Report report = new Report();
        Schema.SObjectType sobjectType = String.isBlank(objectApiName) ? null : Schema.getGlobalDescribe().get(objectApiName);

        if (sobjectType == null) {
            report.summary = 'There is no object called ' + objectApiName + ' to check. Nothing was changed.';
            return report;
        }

        String plural = sobjectType.getDescribe().getLabelPlural();
        AMF_DraftRuleProvider draft;
        try {
            draft = new AMF_DraftRuleProvider(live, removedRule, addedRule);
        } catch (AMF_ConfigurationException e) {
            report.summary = e.getMessage() + ' Nothing was changed.';
            return report;
        }

        List<Id> recordIds = recentlyDecided(objectApiName);
        report.ran = true;

        if (recordIds.isEmpty()) {
            report.summary =
                'No ' + plural + ' were decided by the approval matrix in the last ' + DAYS +
                ' days, so there is nothing to compare ' + changeLabel + ' against. Nothing was changed.';
            return report;
        }

        List<AMF_ApprovalMatrixService.Outcome> today;
        try {
            today = engineOver(live).previewEach(recordIds);
        } catch (Exception e) {
            report.ran = false;
            report.summary = 'The live matrix itself cannot decide ' + plural + ' right now: ' +
                AMF_AgentSupport.asSentence(e.getMessage()) + ' Nothing was changed.';
            return report;
        }

        List<AMF_ApprovalMatrixService.Outcome> drafted;
        try {
            drafted = engineOver(draft).previewEach(recordIds);
        } catch (Exception e) {
            // The change leaves the matrix unable to decide: every record it would
            // reach is affected, and the engine's own reason says why.
            report.checked = recordIds.size();
            report.changed = recordIds.size();
            report.summary =
                'With ' + changeLabel + ', the approval matrix could not decide any of the ' + recordIds.size() + ' ' +
                plural + ' decided in the last ' + DAYS + ' days: ' + AMF_AgentSupport.asSentence(e.getMessage()) +
                ' Nothing was changed.';
            return report;
        }

        compare(report, recordIds, today, drafted);
        report.summary = summaryOf(report, plural, changeLabel, today, drafted);
        return report;
    }

    /** The object's records with a decision in the period, newest first, each once. */
    private static List<Id> recentlyDecided(String objectApiName) {
        Datetime since = Datetime.now().addDays(-DAYS);
        Schema.SObjectType sobjectType = Schema.getGlobalDescribe().get(objectApiName);
        List<Id> recordIds = new List<Id>();
        Set<Id> seen = new Set<Id>();

        for (Approval_Decision_Log__c row : [
            SELECT Record_Id__c
            FROM Approval_Decision_Log__c
            WHERE Object_API_Name__c = :objectApiName AND Submitted_At__c >= :since
            WITH USER_MODE
            ORDER BY Submitted_At__c DESC, Id DESC
            LIMIT 2000
        ]) {
            Id recordId = AMF_AgentSupport.idOf(row.Record_Id__c);
            if (recordId != null && recordId.getSObjectType() == sobjectType && seen.add(recordId)) {
                recordIds.add(recordId);
                if (recordIds.size() == MAX_RECORDS) {
                    break;
                }
            }
        }
        return recordIds;
    }

    private static void compare(
        Report report,
        List<Id> recordIds,
        List<AMF_ApprovalMatrixService.Outcome> today,
        List<AMF_ApprovalMatrixService.Outcome> drafted
    ) {
        List<Integer> changedAt = new List<Integer>();

        for (Integer i = 0; i < recordIds.size(); i++) {
            if (today[i].outcome == REFUSED || drafted[i].outcome == REFUSED) {
                report.skipped++;
                continue;
            }
            report.checked++;
            if (routeOf(today[i]) != routeOf(drafted[i]) || today[i].matchedRule != drafted[i].matchedRule) {
                report.changed++;
                changedAt.add(i);
            }
        }

        Set<Id> listed = new Set<Id>();
        for (Integer i = 0; i < Math.min(MAX_LISTED, changedAt.size()); i++) {
            listed.add(recordIds[changedAt[i]]);
        }
        Map<Id, String> labels = AMF_AgentSupport.labelsOf(listed);

        for (Integer i = 0; i < Math.min(MAX_LISTED, changedAt.size()); i++) {
            Integer at = changedAt[i];
            report.changes.add(
                (i + 1) + '. ' + labels.get(recordIds[at]) + ' (Id ' + recordIds[at] + '): today ' +
                decisionOf(today[at]) + '; with the change ' + decisionOf(drafted[at]) + '.'
            );
        }
    }

    /** "PR_Catch_All sends it to PR_Two_Level_Mgmt", "no rule matches", or the failure. */
    private static String decisionOf(AMF_ApprovalMatrixService.Outcome outcome) {
        switch on outcome.outcome {
            when 'Submitted' {
                return outcome.matchedRule + ' sends it to ' + outcome.selectedProcess;
            }
            when 'Blocked_No_Match' {
                return 'no rule matches, so it would be blocked';
            }
            when else {
                return 'it could not be routed (' + AMF_AgentSupport.asSentence(outcome.message).removeEnd('.') + ')';
            }
        }
    }

    private static String routeOf(AMF_ApprovalMatrixService.Outcome outcome) {
        return outcome.outcome == 'Submitted' ? outcome.selectedProcess : outcome.outcome;
    }

    private static String summaryOf(
        Report report,
        String plural,
        String changeLabel,
        List<AMF_ApprovalMatrixService.Outcome> today,
        List<AMF_ApprovalMatrixService.Outcome> drafted
    ) {
        String summary =
            'Checked ' + report.checked + ' ' + plural + ' decided in the last ' + DAYS + ' days, on their values today. ';

        summary += report.changed == 0
            ? 'None of them would be decided differently with ' + changeLabel + '.'
            : report.changed + ' would be decided differently with ' + changeLabel +
              ' (by another rule, or to another process)' +
              (report.changed > MAX_LISTED ? '; the first ' + MAX_LISTED + ' are listed.' : '.');

        if (report.skipped > 0) {
            summary += ' ' + report.skipped + ' were skipped, because they are in an approval process now or you cannot read them.';
        }

        summary += ' Today: ' + countsOf(today) + '. With the change: ' + countsOf(drafted) + '.';
        return summary + ' Nothing was changed, submitted or recorded.';
    }

    /** "PR_Two_Level_Mgmt 5, PR_Finance_Committee 2, blocked 1", over the records compared. */
    private static String countsOf(List<AMF_ApprovalMatrixService.Outcome> outcomes) {
        Map<String, Integer> counts = new Map<String, Integer>();
        for (AMF_ApprovalMatrixService.Outcome outcome : outcomes) {
            if (outcome.outcome == REFUSED) {
                continue;
            }
            String key = outcome.outcome == 'Submitted' ? outcome.selectedProcess : (outcome.outcome == 'Blocked_No_Match' ? 'blocked' : 'failed');
            counts.put(key, (counts.containsKey(key) ? counts.get(key) : 0) + 1);
        }

        List<String> keys = new List<String>(counts.keySet());
        keys.sort();
        List<String> parts = new List<String>();
        for (String key : keys) {
            parts.add(key + ' ' + counts.get(key));
        }
        return parts.isEmpty() ? 'none' : String.join(parts, ', ');
    }

    private static AMF_ApprovalMatrixService engineOver(AMF_RuleProvider provider) {
        // The strategy is never reached: a preview stops after step 7.
        return new AMF_ApprovalMatrixService(provider, new AMF_ClassicProcessStrategy());
    }
}
