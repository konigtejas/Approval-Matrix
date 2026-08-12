/*
 * scripts/seed-data.apex — Phase 0 org seed (docs/build-playbook.md, Phase 0)
 *
 * Creates the fixture identities every later phase's manual QA depends on:
 *   - 5 test users with a manager chain U1 -> U2 -> U3 -> U4 -> U5
 *   - the framework service user (§5.1 Group Work Item pattern)
 *   - queue        Q_Credit_Risk       (route target of sample rule (b), §3.1)
 *   - public group G_Finance_Approvers with 3 members (U1, U2, U3)
 *
 * Idempotent: re-running only creates what is missing and re-points the manager
 * chain if it drifted. Safe to run again after Phase 1 adds Purchase_Request__c —
 * the queue picks up that object automatically once it exists.
 *
 * Run: sf apex run --file scripts/seed-data.apex -o amf-dev
 *
 * NOTE: anonymous Apex cannot declare classes or methods, so this script is
 * deliberately linear rather than factored into helpers.
 */

// ── 0. Naming ────────────────────────────────────────────────────────────────
// Usernames must be globally unique across all Salesforce orgs, so they carry
// this org's Id as their domain.
String orgKey = UserInfo.getOrganizationId().substring(0, 15).toLowerCase();
String userDomain = '@amf.' + orgKey + '.dev';
List<String> aliases = new List<String>{ 'amfu1', 'amfu2', 'amfu3', 'amfu4', 'amfu5', 'amfsvc' };
Map<String, String> lastNameByAlias = new Map<String, String>{
    'amfu1' => 'Approver One',
    'amfu2' => 'Approver Two',
    'amfu3' => 'Approver Three',
    'amfu4' => 'Approver Four',
    'amfu5' => 'Approver Five',
    'amfsvc' => 'Framework Service'
};
List<String> report = new List<String>();

// ── 1. Profile + licence pre-flight ──────────────────────────────────────────
// Prefer the Platform licence so the org's scarce full Salesforce seats stay free.
List<Profile> profiles = [
    SELECT Id, Name, UserLicenseId
    FROM Profile
    WHERE Name IN ('Standard Platform User', 'Standard User')
    ORDER BY Name ASC
    LIMIT 1
];
if (profiles.isEmpty()) {
    throw new System.IllegalArgumentException(
        'AMF SEED: neither "Standard Platform User" nor "Standard User" profile exists in this org.'
    );
}
Profile seedProfile = profiles[0];
UserLicense seedLicense = [
    SELECT Name, TotalLicenses, UsedLicenses
    FROM UserLicense
    WHERE Id = :seedProfile.UserLicenseId
];

// ── 2. Users ─────────────────────────────────────────────────────────────────
String usernamePattern = '%' + userDomain;
Map<String, User> userByAlias = new Map<String, User>();
for (User existing : [
    SELECT Id, Alias, Username, ManagerId, IsActive
    FROM User
    WHERE Username LIKE :usernamePattern
]) {
    userByAlias.put(existing.Alias, existing);
}

List<User> newUsers = new List<User>();
for (String alias : aliases) {
    if (userByAlias.containsKey(alias)) {
        continue;
    }
    newUsers.add(
        new User(
            Alias = alias,
            Username = alias + userDomain,
            LastName = lastNameByAlias.get(alias),
            FirstName = 'AMF',
            Email = UserInfo.getUserEmail(),
            ProfileId = seedProfile.Id,
            TimeZoneSidKey = UserInfo.getTimeZone().getID(),
            LocaleSidKey = UserInfo.getLocale(),
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = UserInfo.getLanguage(),
            IsActive = true,
            // Profiles auto-grant these feature licences, which are far scarcer than
            // the user licence in a Developer Edition org. The framework needs none
            // of them, so switch them off rather than burn the org's allocation.
            UserPermissionsSFContentUser = false,
            UserPermissionsKnowledgeUser = false,
            UserPermissionsMarketingUser = false,
            UserPermissionsInteractionUser = false,
            UserPermissionsSupportUser = false
        )
    );
}

if (!newUsers.isEmpty()) {
    Integer available = seedLicense.TotalLicenses < 0
        ? 9999
        : seedLicense.TotalLicenses - seedLicense.UsedLicenses;
    if (available < newUsers.size()) {
        throw new System.IllegalArgumentException(
            'AMF SEED: need ' + newUsers.size() + ' free "' + seedLicense.Name +
            '" licences but only ' + available + ' remain (' + seedLicense.UsedLicenses +
            '/' + seedLicense.TotalLicenses + ' used). Free seats or deactivate unused users, then re-run.'
        );
    }
    insert newUsers;
    for (User created : newUsers) {
        userByAlias.put(created.Alias, created);
    }
}
report.add('Users: ' + newUsers.size() + ' created, ' + (aliases.size() - newUsers.size()) + ' already present');

// Manager chain: U1 -> U2 -> U3 -> U4 -> U5 (U5 tops the chain).
List<User> managerUpdates = new List<User>();
for (Integer i = 0; i < 4; i++) {
    User subordinate = userByAlias.get(aliases[i]);
    User manager = userByAlias.get(aliases[i + 1]);
    if (subordinate.ManagerId != manager.Id) {
        managerUpdates.add(new User(Id = subordinate.Id, ManagerId = manager.Id));
    }
}
if (!managerUpdates.isEmpty()) {
    update managerUpdates;
}
report.add('Manager chain: ' + managerUpdates.size() + ' link(s) set (amfu1 -> amfu2 -> amfu3 -> amfu4 -> amfu5)');

// ── 3. Queue Q_Credit_Risk ───────────────────────────────────────────────────
List<Group> queues = [SELECT Id, DeveloperName FROM Group WHERE DeveloperName = 'Q_Credit_Risk' AND Type = 'Queue'];
Group creditRiskQueue;
if (queues.isEmpty()) {
    creditRiskQueue = new Group(Name = 'Credit Risk', DeveloperName = 'Q_Credit_Risk', Type = 'Queue');
    insert creditRiskQueue;
    report.add('Queue Q_Credit_Risk: created');
} else {
    creditRiskQueue = queues[0];
    report.add('Queue Q_Credit_Risk: already present');
}

// Supported objects. Case is the Phase 0 placeholder (Purchase_Request__c does not
// exist until Phase 1); once it does, a re-run adds it without touching anything else.
Set<String> queueObjects = new Set<String>();
for (QueueSobject qso : [SELECT SobjectType FROM QueueSobject WHERE QueueId = :creditRiskQueue.Id]) {
    queueObjects.add(qso.SobjectType);
}
List<String> wantedQueueObjects = new List<String>{ 'Case' };
if (Schema.getGlobalDescribe().containsKey('purchase_request__c')) {
    wantedQueueObjects.add('Purchase_Request__c');
}
List<QueueSobject> newQueueObjects = new List<QueueSobject>();
for (String sobjType : wantedQueueObjects) {
    if (!queueObjects.contains(sobjType)) {
        newQueueObjects.add(new QueueSobject(QueueId = creditRiskQueue.Id, SobjectType = sobjType));
    }
}
if (!newQueueObjects.isEmpty()) {
    insert newQueueObjects;
}
report.add('Queue supported objects: ' + String.join(wantedQueueObjects, ', ') + ' (' + newQueueObjects.size() + ' added)');

// ── 4. Public group G_Finance_Approvers ──────────────────────────────────────
List<Group> publicGroups = [
    SELECT Id, DeveloperName
    FROM Group
    WHERE DeveloperName = 'G_Finance_Approvers' AND Type = 'Regular'
];
Group financeApprovers;
if (publicGroups.isEmpty()) {
    financeApprovers = new Group(Name = 'Finance Approvers', DeveloperName = 'G_Finance_Approvers', Type = 'Regular');
    insert financeApprovers;
    report.add('Public group G_Finance_Approvers: created');
} else {
    financeApprovers = publicGroups[0];
    report.add('Public group G_Finance_Approvers: already present');
}

Set<Id> currentMembers = new Set<Id>();
for (GroupMember gm : [SELECT UserOrGroupId FROM GroupMember WHERE GroupId = :financeApprovers.Id]) {
    currentMembers.add(gm.UserOrGroupId);
}
List<GroupMember> newMembers = new List<GroupMember>();
for (String alias : new List<String>{ 'amfu1', 'amfu2', 'amfu3' }) {
    Id memberId = userByAlias.get(alias).Id;
    if (!currentMembers.contains(memberId)) {
        newMembers.add(new GroupMember(GroupId = financeApprovers.Id, UserOrGroupId = memberId));
    }
}
if (!newMembers.isEmpty()) {
    insert newMembers;
}
report.add('Group members: ' + newMembers.size() + ' added (target: amfu1, amfu2, amfu3)');

// ── 5. Report ────────────────────────────────────────────────────────────────
report.add('Service user (§5.1): ' + userByAlias.get('amfsvc').Username);
report.add('Username domain: ' + userDomain);
System.debug(LoggingLevel.ERROR, '=== AMF SEED COMPLETE ===\n' + String.join(report, '\n'));
