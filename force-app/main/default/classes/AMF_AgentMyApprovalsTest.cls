/**
 * The assistant's My Pending Approvals action (M14): governed records waiting
 * on the user, directly, through a queue, or as delegated approver -- each
 * once, oldest first, and only records the user can read.
 *
 * Architecture section: 7 (its M14 note), 8 (its M14 note), 11, 10.
 *
 * One test runs a real Classic approval, as AMF_AgentSubmitRouteTest does, and
 * makes the running user the first approver's delegate, because that is the
 * one way to put real work in their scope without depending on amf-dev's
 * users. The rest read in-memory work items through the workOverride seam, and
 * learn the governed objects from in-memory rules.
 */
@IsTest
private class AMF_AgentMyApprovalsTest {

    private static final String THREE_LEVEL = 'PR_Three_Level_Finance';

    private static List<AMF_RuleDefinition> rulesFor(List<String> objectApiNames) {
        List<AMF_RuleDefinition> rules = new List<AMF_RuleDefinition>();
        for (String objectApiName : objectApiNames) {
            rules.add(
                new AMF_RuleBuilder()
                    .named(objectApiName.left(20).replace('__c', '') + '_Catch_All')
                    .forObject(objectApiName)
                    .withPriority(9999)
                    .withExpression('TRUE')
                    .routingTo(THREE_LEVEL)
                    .build()
            );
        }
        return rules;
    }

    private static Purchase_Request__c insertRequest() {
        Purchase_Request__c record = new Purchase_Request__c(Amount__c = 60000, Region__c = 'EMEA', Risk_Level__c = 'High');
        insert record;
        return record;
    }

    /** A pending work item as the platform would return it, without running an approval. */
    private static ProcessInstanceWorkitem workItem(Integer n, Id recordId, Id actorId, Datetime createdAt) {
        String instanceId = '04g' + String.valueOf(n).leftPad(12, '0') + 'AAA';
        return (ProcessInstanceWorkitem) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'attributes' => new Map<String, Object>{ 'type' => 'ProcessInstanceWorkitem' },
                    'Id' => '04i' + String.valueOf(n).leftPad(12, '0') + 'AAA',
                    'ActorId' => actorId,
                    'CreatedDate' => createdAt,
                    'ProcessInstanceId' => instanceId,
                    'ProcessInstance' => new Map<String, Object>{
                        'attributes' => new Map<String, Object>{ 'type' => 'ProcessInstance' },
                        'Id' => instanceId,
                        'TargetObjectId' => recordId,
                        'ProcessDefinition' => new Map<String, Object>{
                            'attributes' => new Map<String, Object>{ 'type' => 'ProcessDefinition' },
                            'DeveloperName' => 'PR_Credit_Risk_Queue'
                        },
                        'SubmittedById' => UserInfo.getUserId()
                    }
                }
            ),
            ProcessInstanceWorkitem.class
        );
    }

    private static String labelOf(Id recordId) {
        return 'Purchase Request ' + [SELECT Name FROM Purchase_Request__c WHERE Id = :recordId].Name;
    }

    private static AMF_AgentMyApprovals.Result listFor(String objectName) {
        AMF_AgentMyApprovals.Request request = new AMF_AgentMyApprovals.Request();
        request.objectName = objectName;
        return AMF_AgentMyApprovals.listApprovals(new List<AMF_AgentMyApprovals.Request>{ request })[0];
    }

    @IsTest
    static void aRealApprovalWaitingOnSomeoneTheUserIsDelegateForIsListed() {
        Assert.areEqual(
            1,
            [SELECT COUNT() FROM ProcessDefinition WHERE DeveloperName = :THREE_LEVEL AND State = 'Active'],
            THREE_LEVEL + ' must be active in the org for this test'
        );
        Purchase_Request__c record = insertRequest();
        new AMF_ApprovalMatrixService(
            new AMF_RuleBuilder.Stub(new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder().named('PR_High_Risk').withPriority(20).withExpression('Risk_Level__c == \'High\'').routingTo(THREE_LEVEL).build()
            }),
            new AMF_ClassicProcessStrategy()
        ).submit(new List<Id>{ record.Id });

        Id approverId = [SELECT ActorId FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :record.Id LIMIT 1].ActorId;
        User approver = [SELECT Id, Name FROM User WHERE Id = :approverId];
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = approver.Id, DelegatedApproverId = UserInfo.getUserId());
        }
        AMF_AgentMyApprovals.ruleProviderOverride = new AMF_RuleBuilder.Stub(rulesFor(new List<String>{ 'Purchase_Request__c' }));

        Test.startTest();
        AMF_AgentMyApprovals.Result result = listFor(null);
        Test.stopTest();

        Assert.areEqual(1, result.count, result.message);
        Assert.areEqual('One request is waiting on you for approval.', result.message);
        Assert.isTrue(
            result.approvals.startsWith('1. ' + labelOf(record.Id) + ' (Id ' + record.Id + '): approval process ' + THREE_LEVEL),
            result.approvals
        );
        Assert.isTrue(
            result.approvals.contains(', submitted by ' + UserInfo.getName() + ', waiting on ' + approver.Name + ', as their delegated approver, since '),
            result.approvals
        );
    }

    @IsTest
    static void workForAQueueTheUserIsInIsListedOnceOldestFirst() {
        Group queue = new Group(Name = 'AMF Pending Queue', DeveloperName = 'AMF_Pending_Queue', Type = 'Queue');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert queue;
            insert new GroupMember(GroupId = queue.Id, UserOrGroupId = UserInfo.getUserId());
        }
        Purchase_Request__c older = insertRequest();
        Purchase_Request__c newer = insertRequest();
        Datetime nine = Datetime.newInstanceGmt(2026, 10, 21, 9, 0, 0);

        AMF_AgentMyApprovals.ruleProviderOverride = new AMF_RuleBuilder.Stub(rulesFor(new List<String>{ 'Purchase_Request__c' }));
        AMF_AgentMyApprovals.workOverride = new List<ProcessInstanceWorkitem>{
            workItem(1, older.Id, queue.Id, nine),
            // A committee step: the same record twice. Listed once.
            workItem(2, older.Id, UserInfo.getUserId(), nine.addMinutes(1)),
            workItem(3, newer.Id, UserInfo.getUserId(), nine.addHours(1))
        };

        AMF_AgentMyApprovals.Result result = listFor('purchase requests');

        Assert.areEqual(2, result.count);
        Assert.areEqual('2 requests are waiting on you for approval, oldest first.', result.message);
        List<String> lines = result.approvals.split('\n');
        Assert.areEqual(2, lines.size(), result.approvals);
        Assert.areEqual(
            '1. ' + labelOf(older.Id) + ' (Id ' + older.Id + '): approval process PR_Credit_Risk_Queue, submitted by ' + UserInfo.getName() + ', ' +
            'waiting on the AMF Pending Queue queue, which you are in, since ' + nine.format('d MMM yyyy, HH:mm') + '.',
            lines[0]
        );
        Assert.isTrue(lines[1].contains('waiting on you since ' + nine.addHours(1).format('d MMM yyyy, HH:mm') + '.'), lines[1]);
    }

    @IsTest
    static void onlyGovernedRecordsTheUserCanReadAreListed() {
        Purchase_Request__c record = insertRequest();
        Account ungoverned = new Account(Name = 'Not governed');
        insert ungoverned;
        Datetime nine = Datetime.newInstanceGmt(2026, 10, 21, 9, 0, 0);

        AMF_AgentMyApprovals.ruleProviderOverride = new AMF_RuleBuilder.Stub(rulesFor(new List<String>{ 'Purchase_Request__c' }));
        AMF_AgentMyApprovals.workOverride = new List<ProcessInstanceWorkitem>{
            workItem(1, ungoverned.Id, UserInfo.getUserId(), nine),
            workItem(2, record.Id, UserInfo.getUserId(), nine)
        };

        Assert.areEqual(1, listFor(null).count, 'The Account is not the matrix\'s');
        Assert.areEqual(
            '"Contracts" is not a kind of record the approval matrix governs.',
            listFor('Contracts').message
        );

        User stranger = new User(
            Alias = 'amfmya',
            Email = 'amf.myapprovals@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Approvals',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey = 'GMT',
            Username = 'amf.myapprovals.' + String.valueOf(Datetime.now().getTime()) + '@amf.test.invalid'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert stranger;
        }

        AMF_AgentMyApprovals.Result unreadable;
        System.runAs(stranger) {
            unreadable = listFor(null);
        }
        Assert.areEqual(0, unreadable.count, 'A record they cannot read is not listed');
        Assert.areEqual('Nothing governed by the approval matrix is waiting on you for approval.', unreadable.message);
    }

    @IsTest
    static void aLongListShowsTheOldestAndCountsTheRest() {
        List<Purchase_Request__c> records = new List<Purchase_Request__c>();
        for (Integer i = 0; i <= AMF_AgentMyApprovals.MAX_LISTED; i++) {
            records.add(new Purchase_Request__c(Amount__c = 500, Region__c = 'EMEA', Risk_Level__c = 'Low'));
        }
        insert records;

        List<ProcessInstanceWorkitem> work = new List<ProcessInstanceWorkitem>();
        for (Integer i = 0; i < records.size(); i++) {
            work.add(workItem(i + 1, records[i].Id, UserInfo.getUserId(), Datetime.newInstanceGmt(2026, 10, 1 + i, 9, 0, 0)));
        }
        AMF_AgentMyApprovals.ruleProviderOverride = new AMF_RuleBuilder.Stub(rulesFor(new List<String>{ 'Purchase_Request__c' }));
        AMF_AgentMyApprovals.workOverride = work;

        AMF_AgentMyApprovals.Result result = AMF_AgentMyApprovals.listApprovals(null)[0];

        Assert.areEqual(AMF_AgentMyApprovals.MAX_LISTED + 1, result.count);
        Assert.areEqual(AMF_AgentMyApprovals.MAX_LISTED, result.approvals.split('\n').size());
        Assert.areEqual(
            (AMF_AgentMyApprovals.MAX_LISTED + 1) + ' requests are waiting on you for approval; the ' +
            AMF_AgentMyApprovals.MAX_LISTED + ' oldest are listed.',
            result.message
        );
        Assert.isFalse(result.approvals.contains(records[AMF_AgentMyApprovals.MAX_LISTED].Id), 'The newest is the one left out');
    }
}
