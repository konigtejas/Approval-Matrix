/**
 * A governed record's native approval history, as plain values: one Instance
 * per approval the record entered, each holding the Steps that happened in it.
 *
 * Architecture section: 8 (auditability -- "who and when" is native), 10
 * (testability).
 *
 * Plain values rather than ProcessInstance rows, for the reason 10 gives for
 * every seam in this codebase: a ProcessInstance cannot be inserted in a test,
 * and only exists after a real Approval.process(). The timeline reads these
 * through AMF_ApprovalHistoryProvider, so AMF_DecisionTimelineServiceTest
 * builds them in memory and only AMF_ClassicApprovalHistoryProviderTest needs a
 * real approval.
 *
 * Every field is @AuraEnabled because the timeline hands these to the LWC as
 * they are. Nothing here goes beyond what the native Approval History related
 * list already shows to anyone who can read the record.
 */
public class AMF_ApprovalHistory {

    /** StepStatus of the step that records the submission itself. */
    @TestVisible
    private static final String SUBMISSION_STATUS = 'Started';

    /** One approval the record entered: a ProcessInstance, for Classic. */
    public class Instance {

        /** The instance's Id: the value 6.1 step 11 stamps into Execution_Ref_Id__c. */
        @AuraEnabled
        public Id id;

        /** DeveloperName of the approval process: the name a matrix rule routes to. */
        @AuraEnabled
        public String processName;

        /** Pending, Approved, Rejected, Removed (recalled), and the platform's rarer values. */
        @AuraEnabled
        public String status;

        /** When the record entered this approval. */
        @AuraEnabled
        public Datetime submittedAt;

        /** Everything that happened in it, in the order it happened (sortChronologically). */
        @AuraEnabled
        public List<Step> steps = new List<Step>();
    }

    /** One step of an instance: the submission, a decision, or an open work item. */
    public class Step {

        /** The step's or the open work item's Id. */
        @AuraEnabled
        public Id id;

        /** StepStatus: Started for the submission, Pending for an open work item, then the decision. */
        @AuraEnabled
        public String status;

        /** True for a work item still waiting on its approver. */
        @AuraEnabled
        public Boolean isPending;

        /** The approval step's name. Null for the submission and for a recall. */
        @AuraEnabled
        public String stepName;

        /** Who acted: the submitter, the approver who decided, or the assignee still to decide. */
        @AuraEnabled
        public Id actorId;

        @AuraEnabled
        public String actorName;

        /** Who the step was assigned to. Differs from the actor when someone acted for them. */
        @AuraEnabled
        public Id originalActorId;

        @AuraEnabled
        public String originalActorName;

        /** The approver's comment, as entered. */
        @AuraEnabled
        public String comments;

        /** When the step happened, or when the work item was opened. */
        @AuraEnabled
        public Datetime occurredAt;
    }

    /**
     * Puts steps in the order they happened.
     *
     * Time alone cannot do it. The submission and its first work item are written
     * in one transaction, and so is each decision and the work item it hands on
     * to, so ties to the second are normal rather than rare. Within one instant
     * the submission therefore comes first and anything still pending comes last,
     * which is the only order those events can have happened in. Id settles
     * whatever remains, so the order never varies between reads.
     *
     * @param steps Sorted in place. Null is ignored.
     */
    public static void sortChronologically(List<Step> steps) {
        if (steps != null) {
            steps.sort(new Chronological());
        }
    }

    private class Chronological implements Comparator<Step> {

        public Integer compare(Step left, Step right) {
            Integer byTime = compareTimes(left.occurredAt, right.occurredAt);
            if (byTime != 0) {
                return byTime;
            }

            Integer byStage = stageOf(left) - stageOf(right);
            if (byStage != 0) {
                return byStage;
            }

            return compareIds(left.id, right.id);
        }
    }

    /** 0 for the submission, 1 for anything decided, 2 for a work item still open. */
    private static Integer stageOf(Step step) {
        if (step.status == SUBMISSION_STATUS) {
            return 0;
        }
        return step.isPending == true ? 2 : 1;
    }

    /** Earlier first; a step with no time sorts after every step that has one. */
    private static Integer compareTimes(Datetime left, Datetime right) {
        if (left == right) {
            return 0;
        }
        if (left == null) {
            return 1;
        }
        if (right == null) {
            return -1;
        }
        return left < right ? -1 : 1;
    }

    private static Integer compareIds(Id left, Id right) {
        if (left == right) {
            return 0;
        }
        if (left == null) {
            return 1;
        }
        if (right == null) {
            return -1;
        }
        return String.valueOf(left).compareTo(String.valueOf(right));
    }
}
