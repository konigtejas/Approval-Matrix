/**
 * Production read of a record's Classic approval history: every ProcessInstance
 * that targeted it, with the steps and open work items that Salesforce's own
 * Approval History related list shows.
 *
 * Architecture section: 8 (auditability), 3.3 (Execution_Ref_Id__c holds a
 * ProcessInstance Id), 11 (security).
 *
 * StepsAndWorkitems is ProcessInstanceHistory: completed steps and open work
 * items in one relationship, which is the whole native story of one submission
 * -- the submission itself (StepStatus Started), each decision, and the
 * approver it is waiting on now (IsPending).
 *
 * Declared without sharing, deliberately, like AMF_ClassicApprovalProcessProvider.
 * It answers for one record, and its caller, AMF_DecisionTimelineService, has
 * already checked that the user can read that record -- which is the rule under
 * which the Approval History related list shows this same history. Running
 * without sharing keeps the answer independent of whatever sharing mode a
 * caller happens to be in.
 */
public without sharing class AMF_ClassicApprovalHistoryProvider implements AMF_ApprovalHistoryProvider {

    /**
     * @param recordId     The governed record.
     * @param maxInstances The most instances to return; the newest are kept.
     * @return Newest first, each instance's steps in the order they happened.
     *         Empty, without a query, for a null record or a limit below 1.
     */
    public List<AMF_ApprovalHistory.Instance> getHistory(Id recordId, Integer maxInstances) {
        List<AMF_ApprovalHistory.Instance> instances = new List<AMF_ApprovalHistory.Instance>();

        if (recordId == null || maxInstances == null || maxInstances < 1) {
            return instances;
        }

        for (ProcessInstance source : [
            SELECT
                Id,
                Status,
                CreatedDate,
                ProcessDefinition.DeveloperName,
                (
                    SELECT
                        Id,
                        StepStatus,
                        IsPending,
                        Comments,
                        CreatedDate,
                        ActorId,
                        Actor.Name,
                        OriginalActorId,
                        OriginalActor.Name,
                        ProcessNode.Name
                    FROM StepsAndWorkitems
                )
            FROM ProcessInstance
            WHERE TargetObjectId = :recordId
            ORDER BY CreatedDate DESC, Id DESC
            LIMIT :maxInstances
        ]) {
            instances.add(toInstance(source));
        }

        return instances;
    }

    private static AMF_ApprovalHistory.Instance toInstance(ProcessInstance source) {
        AMF_ApprovalHistory.Instance instance = new AMF_ApprovalHistory.Instance();
        instance.id = source.Id;
        instance.processName = source.ProcessDefinition?.DeveloperName;
        instance.status = source.Status;
        instance.submittedAt = source.CreatedDate;

        for (ProcessInstanceHistory row : source.StepsAndWorkitems) {
            instance.steps.add(toStep(row));
        }

        // The subquery is left unordered on purpose: CreatedDate ties are normal
        // here, and the tie-break is the provider contract's, not the database's.
        AMF_ApprovalHistory.sortChronologically(instance.steps);
        return instance;
    }

    private static AMF_ApprovalHistory.Step toStep(ProcessInstanceHistory row) {
        AMF_ApprovalHistory.Step step = new AMF_ApprovalHistory.Step();
        step.id = row.Id;
        step.status = row.StepStatus;
        step.isPending = row.IsPending;
        step.stepName = row.ProcessNode?.Name;
        step.actorId = row.ActorId;
        step.actorName = row.Actor?.Name;
        step.originalActorId = row.OriginalActorId;
        step.originalActorName = row.OriginalActor?.Name;
        step.comments = row.Comments;
        step.occurredAt = row.CreatedDate;
        return step;
    }
}
