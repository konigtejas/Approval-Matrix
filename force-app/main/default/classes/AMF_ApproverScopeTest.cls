/**
 * Who a user may act for on a Classic approval (M14): the user, the queues and
 * groups that contain them, nested, and the users whose delegated approver they
 * are -- and whether an approval is waiting on any of them.
 *
 * Architecture section: 8 (its M14 note), 11 (security, M14), 10.
 *
 * Groups, queues and users are created here, so nothing depends on amf-dev's
 * own Q_Credit_Risk or G_Finance_Approvers. They are setup objects, so they are
 * inserted as the running user in a runAs block, which keeps them apart from
 * any other DML in the test.
 */
@IsTest
private class AMF_ApproverScopeTest {

    private static User newUser(String alias) {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        String name = 'amf.scope.' + alias;
        return new User(
            Alias = alias,
            Email = name + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Scope ' + alias,
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standard.Id,
            TimeZoneSidKey = 'GMT',
            Username = name + '.' + String.valueOf(Datetime.now().getTime()) + '@amf.test.invalid'
        );
    }

    private static AMF_ApprovalHistory.Instance approval(String status, Id pendingActor) {
        AMF_ApprovalHistory.Instance instance = new AMF_ApprovalHistory.Instance();
        instance.status = status;

        AMF_ApprovalHistory.Step started = new AMF_ApprovalHistory.Step();
        started.status = 'Started';
        started.isPending = false;
        started.actorId = UserInfo.getUserId();
        instance.steps.add(started);

        if (pendingActor != null) {
            AMF_ApprovalHistory.Step waiting = new AMF_ApprovalHistory.Step();
            waiting.status = 'Pending';
            waiting.isPending = true;
            waiting.actorId = pendingActor;
            instance.steps.add(waiting);
        }
        return instance;
    }

    @IsTest
    static void aUserActsForThemselvesAndNoOneElseByDefault() {
        User loner = newUser('amfsc1');
        User other = newUser('amfsc2');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{ loner, other };
        }

        Set<Id> actors = AMF_ApproverScope.actorsFor(loner.Id);

        Assert.areEqual(new Set<Id>{ loner.Id }, actors, 'No group, no delegation: only themselves');
        Assert.isTrue(AMF_ApproverScope.actorsFor(null).isEmpty(), 'No user, no one');
    }

    @IsTest
    static void aQueueReachedThroughANestedGroupCounts() {
        // As amf-dev's Q_Credit_Risk holds G_Finance_Approvers, which holds the approvers.
        User member = newUser('amfsc3');
        Group team = new Group(Name = 'AMF Scope Team', DeveloperName = 'AMF_Scope_Team', Type = 'Regular');
        Group queue = new Group(Name = 'AMF Scope Queue', DeveloperName = 'AMF_Scope_Queue', Type = 'Queue');

        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert member;
            insert new List<Group>{ team, queue };
            insert new List<GroupMember>{
                new GroupMember(GroupId = team.Id, UserOrGroupId = member.Id),
                new GroupMember(GroupId = queue.Id, UserOrGroupId = team.Id)
            };
        }

        Set<Id> actors = AMF_ApproverScope.actorsFor(member.Id);

        Assert.isTrue(actors.contains(member.Id));
        Assert.isTrue(actors.contains(team.Id), 'The group they are in');
        Assert.isTrue(actors.contains(queue.Id), 'The queue that group is in');
        Assert.isTrue(AMF_ApproverScope.isWaitingOn(approval('Pending', queue.Id), actors), 'Work for the queue is theirs');
    }

    @IsTest
    static void aDelegatedApproverActsForWhoeverNamedThem() {
        User delegate = newUser('amfsc4');
        User approver = newUser('amfsc5');

        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert delegate;
            approver.DelegatedApproverId = delegate.Id;
            insert approver;
        }

        Assert.isTrue(AMF_ApproverScope.actorsFor(delegate.Id).contains(approver.Id), 'The delegate may decide for them');
        Assert.isFalse(AMF_ApproverScope.actorsFor(approver.Id).contains(delegate.Id), 'Delegation runs one way');
    }

    @IsTest
    static void nestedGroupsAreFollowedOnlySoDeep() {
        User member = newUser('amfsc6');
        List<Group> chain = new List<Group>();
        for (Integer i = 0; i <= AMF_ApproverScope.MAX_GROUP_DEPTH; i++) {
            chain.add(new Group(Name = 'AMF Scope Level ' + i, DeveloperName = 'AMF_Scope_Level_' + i, Type = 'Regular'));
        }

        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert member;
            insert chain;
            List<GroupMember> members = new List<GroupMember>{ new GroupMember(GroupId = chain[0].Id, UserOrGroupId = member.Id) };
            for (Integer i = 1; i < chain.size(); i++) {
                members.add(new GroupMember(GroupId = chain[i].Id, UserOrGroupId = chain[i - 1].Id));
            }
            insert members;
        }

        Set<Id> actors = AMF_ApproverScope.actorsFor(member.Id);

        Assert.isTrue(actors.contains(chain[AMF_ApproverScope.MAX_GROUP_DEPTH - 1].Id), 'Followed to the limit');
        Assert.isFalse(actors.contains(chain[AMF_ApproverScope.MAX_GROUP_DEPTH].Id), 'And no further');
    }

    @IsTest
    static void anApprovalWaitsOnTheScopeOnlyWhilePendingAndOnlyAtItsPendingStep() {
        Id reader = UserInfo.getUserId();
        Id someoneElse = Id.valueOf('005000000000001AAA');
        Set<Id> actors = new Set<Id>{ reader };

        Assert.isTrue(AMF_ApproverScope.isWaitingOn(approval('Pending', reader), actors));
        Assert.isFalse(AMF_ApproverScope.isWaitingOn(approval('Pending', someoneElse), actors), 'Waiting on someone else');
        Assert.isFalse(AMF_ApproverScope.isWaitingOn(approval('Approved', reader), actors), 'Finished: waiting on no one');
        Assert.isFalse(
            AMF_ApproverScope.isWaitingOn(approval('Pending', null), actors),
            'The submitter of a pending approval is not its approver'
        );
        Assert.isFalse(AMF_ApproverScope.isWaitingOn(null, actors));
        Assert.isFalse(AMF_ApproverScope.isWaitingOn(approval('Pending', reader), null));
    }

    @IsTest
    static void membershipIsReadOncePerUserPerTransaction() {
        User member = newUser('amfsc7');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert member;
        }

        AMF_ApproverScope.actorsFor(member.Id);
        Integer before = Limits.getQueries();
        AMF_ApproverScope.actorsFor(member.Id);
        Assert.areEqual(before, Limits.getQueries(), 'Asked again, answered from memory');

        AMF_ApproverScope.reset();
        AMF_ApproverScope.actorsFor(member.Id);
        Assert.isTrue(Limits.getQueries() > before, 'After a reset, read again');
    }
}
