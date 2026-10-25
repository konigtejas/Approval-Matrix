// Flow approvals spike (M6) - setup. Creates the spike's own approver groups so the
// seeded Q_Credit_Risk / G_Finance_Approvers are never touched. Idempotent.
//
//   AMF_Spike_Any    public group  - default approval semantics
//   AMF_Spike_All    public group  - "require unanimous approval"
//   AMF_Spike_Queue  queue (Purchase_Request__c)
//
// Members of each: the running admin (so decisions can be made as a MEMBER from
// anonymous Apex) and amfu1 (a second member who is NOT the running user).
//
// Run: sf apex run --file spikes/flow-approvals/scripts/01-setup-groups.apex -o amf-dev

Id adminId = UserInfo.getUserId();
Id amfu1Id = [SELECT Id FROM User WHERE Username LIKE 'amfu1@%' LIMIT 1].Id;

Map<String, String> typeByName = new Map<String, String>{
    'AMF_Spike_Any' => 'Regular',
    'AMF_Spike_All' => 'Regular',
    'AMF_Spike_Queue' => 'Queue'
};

Map<String, Group> existing = new Map<String, Group>();
for (Group g : [SELECT Id, DeveloperName FROM Group WHERE DeveloperName IN :typeByName.keySet()]) {
    existing.put(g.DeveloperName, g);
}

List<Group> toCreate = new List<Group>();
for (String name : typeByName.keySet()) {
    if (!existing.containsKey(name)) {
        toCreate.add(new Group(Name = name, DeveloperName = name, Type = typeByName.get(name)));
    }
}
insert toCreate;
for (Group g : toCreate) {
    existing.put(g.DeveloperName, g);
}

Id queueId = existing.get('AMF_Spike_Queue').Id;
if ([SELECT COUNT() FROM QueueSobject WHERE QueueId = :queueId AND SobjectType = 'Purchase_Request__c'] == 0) {
    insert new QueueSobject(QueueId = queueId, SobjectType = 'Purchase_Request__c');
}

Set<String> present = new Set<String>();
List<Group> spikeGroups = existing.values();
for (GroupMember m : [SELECT GroupId, UserOrGroupId FROM GroupMember WHERE GroupId IN :spikeGroups]) {
    present.add(m.GroupId + ':' + m.UserOrGroupId);
}
List<GroupMember> members = new List<GroupMember>();
for (Group g : existing.values()) {
    for (Id userId : new List<Id>{ adminId, amfu1Id }) {
        if (!present.contains(g.Id + ':' + userId)) {
            members.add(new GroupMember(GroupId = g.Id, UserOrGroupId = userId));
        }
    }
}
insert members;

for (Group g : [SELECT Id, DeveloperName, Type, (SELECT UserOrGroupId FROM GroupMembers) FROM Group WHERE DeveloperName IN :typeByName.keySet()]) {
    System.debug(LoggingLevel.ERROR, 'SPIKE GROUP ' + g.DeveloperName + ' ' + g.Type + ' ' + g.Id + ' members=' + g.GroupMembers.size());
}
