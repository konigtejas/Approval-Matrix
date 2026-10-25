/**
 * Who a user may act for on a Classic approval (M14): the people and queues
 * whose pending approval work that user can decide.
 *
 * Architecture section: 8 (auditability, and its M14 note), 11 (security, M14).
 *
 * WHY IT EXISTS. Since M14 the current approver of a pending approval may read
 * the decision log row that explains why it was routed to them, which their
 * own sharing does not show them (docs/decisions.md, 2026-10-23). "Current
 * approver" has to mean what the platform means when it lets someone decide a
 * Classic work item, and that is more than the work item's ActorId:
 *   - the user the step is assigned to;
 *   - a member of the queue it is assigned to, directly or through a public
 *     group that is itself a member, followed to MAX_GROUP_DEPTH;
 *   - the delegated approver of the user it is assigned to.
 * The timeline service, the approver briefing and the "what is waiting for me"
 * action all ask this one class, so the three cannot disagree about who is
 * deciding.
 *
 * NOT FOLLOWED: a queue whose member is a role, or a role and its subordinates.
 * Membership through a role is implicit, not a GroupMember row, and the
 * framework's templates name users, queues and groups only (5.2). A role-based
 * approver still decides their work item natively; they simply do not get the
 * routing reason from this rule.
 *
 * Declared without sharing: GroupMember rows and other users' delegated
 * approver settings are read to answer a question about the running user, not
 * shown to them. Nothing here reveals another user's data.
 */
public without sharing class AMF_ApproverScope {

    /** How deep nested public groups are followed. Templates nest one level (5.2); five is ample. */
    @TestVisible
    private static final Integer MAX_GROUP_DEPTH = 5;

    /** A transaction asks about the same user several times; GroupMember is read once per user. */
    private static final Map<Id, Set<Id>> ACTORS_BY_USER = new Map<Id, Set<Id>>();

    /**
     * @param userId The user.
     * @return The user, every queue and public group that contains them directly
     *         or through nested groups, and every user who names them delegated
     *         approver. Empty for a null user.
     */
    public static Set<Id> actorsFor(Id userId) {
        if (userId == null) {
            return new Set<Id>();
        }
        if (ACTORS_BY_USER.containsKey(userId)) {
            return ACTORS_BY_USER.get(userId);
        }

        Set<Id> actors = new Set<Id>{ userId };
        Set<Id> frontier = new Set<Id>{ userId };

        for (Integer depth = 0; depth < MAX_GROUP_DEPTH && !frontier.isEmpty(); depth++) {
            Set<Id> next = new Set<Id>();

            for (GroupMember member : [SELECT GroupId FROM GroupMember WHERE UserOrGroupId IN :frontier]) {
                if (actors.add(member.GroupId)) {
                    next.add(member.GroupId);
                }
            }
            frontier = next;
        }

        for (User delegator : [SELECT Id FROM User WHERE DelegatedApproverId = :userId]) {
            actors.add(delegator.Id);
        }

        ACTORS_BY_USER.put(userId, actors);
        return actors;
    }

    /**
     * @param approval One approval, as AMF_ApprovalHistoryProvider returns it.
     * @param actors   What actorsFor() returned for the reader.
     * @return True when the approval is pending and one of its pending steps is
     *         assigned to someone in actors.
     */
    public static Boolean isWaitingOn(AMF_ApprovalHistory.Instance approval, Set<Id> actors) {
        if (approval == null || approval.status != 'Pending' || approval.steps == null || actors == null) {
            return false;
        }
        for (AMF_ApprovalHistory.Step step : approval.steps) {
            if (step.isPending == true && step.actorId != null && actors.contains(step.actorId)) {
                return true;
            }
        }
        return false;
    }

    /** Test seam: a test that changes group membership mid-transaction reads it again. */
    @TestVisible
    private static void reset() {
        ACTORS_BY_USER.clear();
    }
}
