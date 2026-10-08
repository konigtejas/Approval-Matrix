/**
 * The decision timeline's unit suite: the join, the order, the cap, the labels
 * and the two visibility rules, driven through real decision log rows and an
 * in-memory approval history.
 *
 * Architecture section: 8 (the timeline, and its M7 note), 3.3, 10, 11.
 *
 * Log rows are inserted directly, shaped as AMF_DecisionLogWriter writes them;
 * Lock_Decision_Log polices updates, not inserts. No rule is evaluated and no
 * approval runs here: the native half comes from HistoryStub, because a
 * ProcessInstance cannot be created without a real Approval.process(). The
 * real read is covered once, by AMF_ClassicApprovalHistoryProviderTest.
 */
@IsTest
private class AMF_DecisionTimelineServiceTest {

    private static final Datetime NINE = Datetime.newInstanceGmt(2026, 9, 25, 9, 0, 0);

    /** What the platform would have returned, without running an approval. */
    private class HistoryStub implements AMF_ApprovalHistoryProvider {

        private final List<AMF_ApprovalHistory.Instance> instances;

        public Integer calls = 0;
        public Id askedFor;
        public Integer askedMax;

        public HistoryStub(List<AMF_ApprovalHistory.Instance> instances) {
            this.instances = instances;
        }

        public List<AMF_ApprovalHistory.Instance> getHistory(Id recordId, Integer maxInstances) {
            calls++;
            askedFor = recordId;
            askedMax = maxInstances;
            return instances;
        }
    }

    private static HistoryStub history(List<AMF_ApprovalHistory.Instance> instances) {
        return new HistoryStub(instances);
    }

    private static HistoryStub noHistory() {
        return new HistoryStub(new List<AMF_ApprovalHistory.Instance>());
    }

    private static Purchase_Request__c insertRequest() {
        Purchase_Request__c record = new Purchase_Request__c(
            Amount__c = 250000,
            Region__c = 'APAC',
            Risk_Level__c = 'Low'
        );
        insert record;
        return record;
    }

    /** A well-formed 18-character Id: lowercase-and-digit, so its suffix is AAA. */
    private static Id fakeId(String keyPrefix, Integer n) {
        return Id.valueOf(keyPrefix + String.valueOf(n).leftPad(12, '0') + 'AAA');
    }

    /** A ProcessInstance-shaped approval, holding the step that records its submission. */
    private static AMF_ApprovalHistory.Instance approval(Integer n, String status, Datetime submittedAt) {
        AMF_ApprovalHistory.Instance instance = new AMF_ApprovalHistory.Instance();
        instance.id = fakeId('04g', n);
        instance.processName = 'PR_Three_Level_Finance';
        instance.status = status;
        instance.submittedAt = submittedAt;

        AMF_ApprovalHistory.Step submission = new AMF_ApprovalHistory.Step();
        submission.id = fakeId('04h', n);
        submission.status = 'Started';
        submission.isPending = false;
        submission.actorId = UserInfo.getUserId();
        submission.actorName = UserInfo.getName();
        submission.occurredAt = submittedAt;
        instance.steps.add(submission);

        return instance;
    }

    /** A Submitted row as the engine leaves it: written, then stamped (6.1 steps 8 and 11). */
    private static Approval_Decision_Log__c submittedRow(Id recordId, String executionRefId, Datetime submittedAt) {
        return new Approval_Decision_Log__c(
            Record_Id__c = String.valueOf(recordId),
            Object_API_Name__c = 'Purchase_Request__c',
            Outcome__c = 'Submitted',
            Matched_Rule__c = 'PR_High_Value_APAC',
            Rule_Version__c = 3,
            Expression_Snapshot__c = 'Amount__c > 100000 && Region__c == \'APAC\'',
            Evaluated_Values__c = '{"Amount__c":250000.00,"Region__c":"APAC"}',
            Selected_Process__c = 'PR_Three_Level_Finance',
            Execution_Ref_Id__c = executionRefId,
            Submitted_By__c = UserInfo.getUserId(),
            Submitted_At__c = submittedAt
        );
    }

    /** A Blocked_No_Match row as the engine writes it (3.2). */
    private static Approval_Decision_Log__c blockedRow(Id recordId, Datetime submittedAt) {
        return new Approval_Decision_Log__c(
            Record_Id__c = String.valueOf(recordId),
            Object_API_Name__c = 'Purchase_Request__c',
            Outcome__c = 'Blocked_No_Match',
            Evaluated_Values__c = '{"Risk_Level__c":"Low"}',
            Failure_Detail__c = 'No active rule matched this Purchase_Request__c.',
            Submitted_By__c = UserInfo.getUserId(),
            Submitted_At__c = submittedAt
        );
    }

    private static Map<String, AMF_DecisionTimelineService.Value> byPath(
        List<AMF_DecisionTimelineService.Value> values
    ) {
        Map<String, AMF_DecisionTimelineService.Value> indexed = new Map<String, AMF_DecisionTimelineService.Value>();
        for (AMF_DecisionTimelineService.Value value : values) {
            indexed.put(value.path, value);
        }
        return indexed;
    }

    @IsTest
    static void aSubmittedDecisionIsJoinedToTheApprovalItStarted() {
        Purchase_Request__c record = insertRequest();
        AMF_ApprovalHistory.Instance started = approval(1, 'Pending', NINE);
        insert submittedRow(record.Id, String.valueOf(started.id), NINE);

        HistoryStub nativeHistory = history(new List<AMF_ApprovalHistory.Instance>{ started });

        Test.startTest();
        AMF_DecisionTimelineService.Timeline timeline = new AMF_DecisionTimelineService(nativeHistory)
            .build(record.Id);
        Test.stopTest();

        Assert.areEqual(1, timeline.entries.size(), 'One submission is one entry, not one per source');
        Assert.isFalse(timeline.hasMore);

        AMF_DecisionTimelineService.Entry entry = timeline.entries[0];
        AMF_DecisionTimelineService.Decision decision = entry.decision;
        Assert.isNotNull(decision, 'The why');
        Assert.areEqual(started.id, entry.approval?.id, 'The who-and-when, joined through Execution_Ref_Id__c');
        Assert.areEqual(String.valueOf(decision.logId), entry.key);
        Assert.areEqual(NINE, entry.occurredAt);

        Assert.areEqual('Submitted', decision.outcome);
        Assert.areEqual('PR_High_Value_APAC', decision.matchedRule);
        Assert.areEqual(3, decision.ruleVersion);
        Assert.areEqual('Amount__c > 100000 && Region__c == \'APAC\'', decision.expression);
        Assert.areEqual('PR_Three_Level_Finance', decision.selectedProcess);
        Assert.areEqual(UserInfo.getUserId(), decision.submittedById);
        Assert.areEqual(UserInfo.getName(), decision.submittedByName);
        Assert.areEqual(NINE, decision.submittedAt);
        Assert.isNull(decision.detail, 'A routed record has nothing to explain away');
        Assert.isTrue(
            decision.logName.startsWith('ADL-'),
            'The auto-number the related list shows, got: ' + decision.logName
        );

        Assert.areEqual(record.Id, nativeHistory.askedFor);
        Assert.areEqual(
            AMF_DecisionTimelineService.MAX_ENTRIES + 1,
            nativeHistory.askedMax,
            'Asked for one past the cap, so the window stays honest across the join'
        );
    }

    @IsTest
    static void blockedAndFailedAttemptsAreEntriesWithNoApproval() {
        Purchase_Request__c record = insertRequest();
        Approval_Decision_Log__c failed = new Approval_Decision_Log__c(
            Record_Id__c = String.valueOf(record.Id),
            Object_API_Name__c = 'Purchase_Request__c',
            Outcome__c = 'Failed',
            Matched_Rule__c = 'PR_High_Risk',
            Rule_Version__c = 2,
            Expression_Snapshot__c = 'Risk_Level__c == \'High\'',
            Selected_Process__c = 'PR_Three_Level_Finance',
            Evaluated_Values__c = '{}',
            Failure_Detail__c = 'Routing failed while evaluating rule PR_High_Risk: field deleted',
            Submitted_By__c = UserInfo.getUserId(),
            Submitted_At__c = NINE.addMinutes(5)
        );
        insert new List<Approval_Decision_Log__c>{ blockedRow(record.Id, NINE), failed };

        AMF_DecisionTimelineService.Timeline timeline = new AMF_DecisionTimelineService(noHistory())
            .build(record.Id);

        Assert.areEqual(2, timeline.entries.size());

        AMF_DecisionTimelineService.Entry newest = timeline.entries[0];
        Assert.areEqual('Failed', newest.decision.outcome);
        Assert.isNull(newest.approval, 'A failed attempt never entered a process');
        Assert.areEqual('PR_High_Risk', newest.decision.matchedRule, 'The rule under evaluation when it failed');
        Assert.areEqual(2, newest.decision.ruleVersion);
        Assert.isTrue(newest.decision.detail.contains('field deleted'), 'Got: ' + newest.decision.detail);
        Assert.areEqual(0, newest.decision.values.size(), 'Nothing had been read when it failed');

        AMF_DecisionTimelineService.Entry blocked = timeline.entries[1];
        Assert.areEqual('Blocked_No_Match', blocked.decision.outcome);
        Assert.isNull(blocked.approval);
        Assert.isNull(blocked.decision.matchedRule, 'Nothing matched');
        Assert.isNull(blocked.decision.ruleVersion);
        Assert.areEqual('No active rule matched this Purchase_Request__c.', blocked.decision.detail);
        Assert.areEqual(1, blocked.decision.values.size(), 'What the engine read before it gave up');
        Assert.areEqual('Risk Level', blocked.decision.values[0].label);
    }

    @IsTest
    static void anApprovalWithNoReadableRowIsShownRatherThanDropped() {
        Purchase_Request__c record = insertRequest();
        AMF_ApprovalHistory.Instance unexplained = approval(7, 'Approved', NINE);

        AMF_DecisionTimelineService.Timeline timeline = new AMF_DecisionTimelineService(
                history(new List<AMF_ApprovalHistory.Instance>{ unexplained })
            )
            .build(record.Id);

        Assert.areEqual(1, timeline.entries.size());

        AMF_DecisionTimelineService.Entry entry = timeline.entries[0];
        Assert.isNull(entry.decision, 'No readable row: the why is absent, never invented');
        Assert.areEqual(unexplained.id, entry.approval.id);
        Assert.areEqual(String.valueOf(unexplained.id), entry.key);
        Assert.areEqual(NINE, entry.occurredAt);
        Assert.areEqual(1, entry.approval.steps.size(), 'Its steps come through untouched');
    }

    @IsTest
    static void entriesAreNewestFirstAcrossBothSources() {
        Purchase_Request__c record = insertRequest();
        AMF_ApprovalHistory.Instance latest = approval(3, 'Pending', NINE.addHours(3));
        AMF_ApprovalHistory.Instance unexplained = approval(2, 'Rejected', NINE.addHours(2));

        insert new List<Approval_Decision_Log__c>{
            blockedRow(record.Id, NINE.addHours(1)),
            submittedRow(record.Id, String.valueOf(latest.id), NINE.addHours(3)),
            // Stamped with an approval the history does not return.
            submittedRow(record.Id, String.valueOf(fakeId('04g', 99)), NINE)
        };

        AMF_DecisionTimelineService.Timeline timeline = new AMF_DecisionTimelineService(
                history(new List<AMF_ApprovalHistory.Instance>{ latest, unexplained })
            )
            .build(record.Id);

        Assert.areEqual(4, timeline.entries.size());

        Assert.areEqual(NINE.addHours(3), timeline.entries[0].occurredAt);
        Assert.areEqual(latest.id, timeline.entries[0].approval.id);
        Assert.isNotNull(timeline.entries[0].decision);

        Assert.areEqual(unexplained.id, timeline.entries[1].approval.id);
        Assert.isNull(timeline.entries[1].decision);

        Assert.areEqual('Blocked_No_Match', timeline.entries[2].decision.outcome);

        Assert.areEqual('Submitted', timeline.entries[3].decision.outcome);
        Assert.isNull(
            timeline.entries[3].approval,
            'An approval the history does not return leaves its decision standing alone'
        );
    }

    @IsTest
    static void theMostRecentFiftyAreShownAndTheRestIsAdmitted() {
        Purchase_Request__c record = insertRequest();
        Integer total = AMF_DecisionTimelineService.MAX_ENTRIES + 1;

        List<Approval_Decision_Log__c> rows = new List<Approval_Decision_Log__c>();
        for (Integer i = 0; i < total; i++) {
            rows.add(blockedRow(record.Id, NINE.addMinutes(i)));
        }
        insert rows;

        AMF_DecisionTimelineService.Timeline timeline = new AMF_DecisionTimelineService(noHistory())
            .build(record.Id);

        Assert.areEqual(AMF_DecisionTimelineService.MAX_ENTRIES, timeline.entries.size());
        Assert.isTrue(timeline.hasMore, 'The timeline must not claim to be complete when it is not');
        Assert.areEqual(NINE.addMinutes(total - 1), timeline.entries[0].occurredAt, 'The newest is kept');
        Assert.areEqual(
            NINE.addMinutes(1),
            timeline.entries[timeline.entries.size() - 1].occurredAt,
            'Only the oldest is cut'
        );
    }

    @IsTest
    static void valuesCarryTheirLabelsAndTypesAndSurviveADeletedField() {
        Purchase_Request__c record = insertRequest();
        Approval_Decision_Log__c row = submittedRow(record.Id, null, NINE);
        row.Evaluated_Values__c =
            '{"Amount__c":250000.00,"Region__c":"APAC","Matrix_Submission__c":false,' +
            '"Risk_Level__c":null,"Account__r.Name":"Acme","Owner.Name":"Ann",' +
            '"Gone__c":"x","Gone__r.Name":"y","Nested__c":{"a":1}}';
        insert row;

        AMF_DecisionTimelineService.Timeline timeline = new AMF_DecisionTimelineService(noHistory())
            .build(record.Id);
        Map<String, AMF_DecisionTimelineService.Value> values = byPath(timeline.entries[0].decision.values);

        Assert.areEqual(9, values.size(), 'Every recorded path, none dropped');

        AMF_DecisionTimelineService.Value amount = values.get('Amount__c');
        Assert.areEqual('Amount', amount.label);
        Assert.areEqual(AMF_DecisionTimelineService.KIND_NUMBER, amount.kind);
        Assert.areEqual(
            250000,
            Decimal.valueOf(amount.text).intValue(),
            'A plain decimal the LWC formats for the viewer'
        );

        Assert.areEqual('Region', values.get('Region__c').label);
        Assert.areEqual(AMF_DecisionTimelineService.KIND_TEXT, values.get('Region__c').kind);
        Assert.areEqual('APAC', values.get('Region__c').text);

        Assert.areEqual('Matrix Submission', values.get('Matrix_Submission__c').label);
        Assert.areEqual(AMF_DecisionTimelineService.KIND_BOOLEAN, values.get('Matrix_Submission__c').kind);
        Assert.areEqual('false', values.get('Matrix_Submission__c').text);

        Assert.areEqual(AMF_DecisionTimelineService.KIND_BLANK, values.get('Risk_Level__c').kind);
        Assert.isNull(values.get('Risk_Level__c').text, 'A blank that decided a route is kept, as blank');

        Assert.areEqual(
            'Account > Account Name',
            values.get('Account__r.Name').label,
            'A relationship path reads as labels, a custom lookup by its own label'
        );
        Assert.isTrue(
            values.get('Owner.Name').label.startsWith('Owner > '),
            'A standard lookup loses the " ID" its label carries, got: ' + values.get('Owner.Name').label
        );

        Assert.areEqual('Gone__c', values.get('Gone__c').label, 'A field that no longer exists shows as recorded');
        Assert.areEqual('Gone__r.Name', values.get('Gone__r.Name').label, 'So does a relationship');
        Assert.areEqual('x', values.get('Gone__c').text, 'And its value is still shown');

        // The evaluator never records a nested value; one is shown as JSON, not guessed at.
        Assert.areEqual(AMF_DecisionTimelineService.KIND_TEXT, values.get('Nested__c').kind);
        Assert.areEqual('{"a":1}', values.get('Nested__c').text);
    }

    @IsTest
    static void aMissingOrUnreadableSnapshotNeverHidesTheEntry() {
        Purchase_Request__c record = insertRequest();
        Approval_Decision_Log__c malformed = blockedRow(record.Id, NINE);
        malformed.Evaluated_Values__c = 'not json';
        Approval_Decision_Log__c notAnObject = blockedRow(record.Id, NINE.addMinutes(1));
        notAnObject.Evaluated_Values__c = '[1,2]';
        Approval_Decision_Log__c unrecorded = blockedRow(record.Id, NINE.addMinutes(2));
        unrecorded.Evaluated_Values__c = null;
        insert new List<Approval_Decision_Log__c>{ malformed, notAnObject, unrecorded };

        AMF_DecisionTimelineService.Timeline timeline = new AMF_DecisionTimelineService(noHistory())
            .build(record.Id);

        Assert.areEqual(3, timeline.entries.size(), 'A snapshot that cannot be read must not hide its entry');
        Assert.areEqual(0, timeline.entries[0].decision.values.size(), 'Nothing recorded, nothing shown');

        for (Integer i = 1; i < timeline.entries.size(); i++) {
            List<AMF_DecisionTimelineService.Value> values = timeline.entries[i].decision.values;
            Assert.areEqual(1, values.size(), 'Shown whole, as recorded');
            Assert.areEqual(AMF_DecisionTimelineService.KIND_UNPARSED, values[0].kind);
            Assert.isNull(values[0].path);
        }
        Assert.areEqual('[1,2]', timeline.entries[1].decision.values[0].text);
        Assert.areEqual('not json', timeline.entries[2].decision.values[0].text);
    }

    @IsTest
    static void simultaneousEntriesKeepOneOrderAcrossReads() {
        // Two attempts stamped in the same second -- a double click before the
        // action guarded against one, say. Time cannot order them, so the key
        // does, and the timeline must not reshuffle on every refresh.
        Purchase_Request__c record = insertRequest();
        insert new List<Approval_Decision_Log__c>{ blockedRow(record.Id, NINE), blockedRow(record.Id, NINE) };

        AMF_DecisionTimelineService service = new AMF_DecisionTimelineService(noHistory());
        List<AMF_DecisionTimelineService.Entry> first = service.build(record.Id).entries;
        List<AMF_DecisionTimelineService.Entry> second = service.build(record.Id).entries;

        Assert.areEqual(2, first.size());
        Assert.areNotEqual(first[0].key, first[1].key);
        Assert.areEqual(first[0].key, second[0].key, 'The same order on every read');
        Assert.areEqual(first[1].key, second[1].key);
    }

    @IsTest
    static void aViewerSeesEveryApprovalButOnlyTheReasonsTheyCanRead() {
        // 11: an Approval_Matrix_User reads their own log rows. The viewer owns
        // the record, so they see both approvals on it, but only their own row.
        User viewer = matrixUser();
        Purchase_Request__c record = new Purchase_Request__c(
            Amount__c = 500,
            Region__c = 'EMEA',
            Risk_Level__c = 'Low',
            OwnerId = viewer.Id
        );
        insert record;

        AMF_ApprovalHistory.Instance theirs = approval(1, 'Approved', NINE);
        AMF_ApprovalHistory.Instance someoneElses = approval(2, 'Pending', NINE.addHours(1));

        Approval_Decision_Log__c ownRow = submittedRow(record.Id, String.valueOf(theirs.id), NINE);
        ownRow.OwnerId = viewer.Id;
        ownRow.Submitted_By__c = viewer.Id;
        // Owned by the running user, so Private OWD keeps it from the viewer.
        Approval_Decision_Log__c otherRow = submittedRow(
            record.Id,
            String.valueOf(someoneElses.id),
            NINE.addHours(1)
        );
        insert new List<Approval_Decision_Log__c>{ ownRow, otherRow };

        HistoryStub nativeHistory = history(new List<AMF_ApprovalHistory.Instance>{ someoneElses, theirs });
        AMF_DecisionTimelineService.Timeline seen;

        Test.startTest();
        System.runAs(viewer) {
            seen = new AMF_DecisionTimelineService(nativeHistory).build(record.Id);
        }
        Test.stopTest();

        Assert.areEqual(2, seen.entries.size(), 'Both approvals, whatever the viewer can read of the log');

        Assert.areEqual(someoneElses.id, seen.entries[0].approval.id);
        Assert.isNull(
            seen.entries[0].decision,
            'A row the viewer could not open elsewhere is not shown to them here either'
        );

        Assert.areEqual(theirs.id, seen.entries[1].approval.id);
        Assert.areEqual(ownRow.Id, seen.entries[1].decision?.logId, 'Their own row explains their own submission');
        Assert.areEqual(viewer.Id, seen.entries[1].decision.submittedById);
    }

    @IsTest
    static void aRecordTheUserCannotReadIsRefusedBeforeAnythingIsRead() {
        Purchase_Request__c record = insertRequest();
        insert blockedRow(record.Id, NINE);

        User stranger = strangerUser();
        HistoryStub nativeHistory = noHistory();

        Test.startTest();
        System.runAs(stranger) {
            try {
                new AMF_DecisionTimelineService(nativeHistory).build(record.Id);
                Assert.fail('A record the user cannot read must not show its approval history');
            } catch (AMF_DecisionTimelineService.TimelineException e) {
                Assert.isTrue(e.getMessage().contains('read access'), 'Got: ' + e.getMessage());
            }
        }
        Test.stopTest();

        Assert.areEqual(0, nativeHistory.calls, 'Refused before the native history is read');
    }

    @IsTest
    static void aNullRecordIsRefused() {
        try {
            new AMF_DecisionTimelineService(noHistory()).build(null);
            Assert.fail('Expected a refusal');
        } catch (AMF_DecisionTimelineService.TimelineException e) {
            Assert.isTrue(e.getMessage().contains('record'), 'Got: ' + e.getMessage());
        }
    }

    @IsTest
    static void theAuraEntryPointReadsTheRealHistoryAndSurfacesTheRealMessage() {
        // Production wiring, so the Classic provider runs for real; the record
        // never entered an approval, so it finds nothing and the row stands alone.
        Purchase_Request__c record = insertRequest();
        insert blockedRow(record.Id, NINE);

        Test.startTest();
        AMF_DecisionTimelineService.Timeline timeline = AMF_DecisionTimelineService.getTimeline(record.Id);
        Test.stopTest();

        Assert.areEqual(1, timeline.entries.size());
        Assert.areEqual('Blocked_No_Match', timeline.entries[0].decision.outcome);
        Assert.isNull(timeline.entries[0].approval);

        try {
            AMF_DecisionTimelineService.getTimeline(null);
            Assert.fail('Expected a refusal');
        } catch (AuraHandledException e) {
            Assert.isTrue(
                e.getMessage().contains('record'),
                'The LWC must receive the real message, not "Script-thrown exception". Got: ' +
                e.getMessage()
            );
        }
    }

    /** A Standard User holding Approval_Matrix_User: a submitter or an approver. */
    private static User matrixUser() {
        User user = standardUser('amftlv', 'amf.timeline.viewer');
        PermissionSet matrix = [SELECT Id FROM PermissionSet WHERE Name = 'Approval_Matrix_User' LIMIT 1];

        // User and PermissionSetAssignment are setup objects: inserting them in
        // the same transaction as a Purchase_Request__c is MIXED_DML_OPERATION
        // without this wrapper.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert user;
            insert new PermissionSetAssignment(AssigneeId = user.Id, PermissionSetId = matrix.Id);
        }
        return user;
    }

    /** A Standard User with no framework permission set and no access to the test's records. */
    private static User strangerUser() {
        User user = standardUser('amftls', 'amf.timeline.stranger');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert user;
        }
        return user;
    }

    private static User standardUser(String alias, String usernamePrefix) {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        return new User(
            Alias = alias,
            Email = usernamePrefix + '@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Timeline',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = standard.Id,
            TimeZoneSidKey = 'GMT',
            Username = usernamePrefix + '.' + String.valueOf(Datetime.now().getTime()) + '@amf.test.invalid'
        );
    }
}
