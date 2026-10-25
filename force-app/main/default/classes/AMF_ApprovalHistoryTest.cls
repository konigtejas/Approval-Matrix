/**
 * The step-ordering rule behind every approval the timeline shows, proved on
 * in-memory steps.
 *
 * Architecture section: 8 (auditability), 10 (testability).
 *
 * The rule matters because CreatedDate ties are normal, not rare: the
 * submission and its first work item are written in one transaction, as is
 * each decision and the work item it hands on to. A timeline that ordered by
 * time alone would show an approval as pending before it was submitted
 * whenever the database returned the rows that way round.
 */
@IsTest
private class AMF_ApprovalHistoryTest {

    private static final Datetime NINE = Datetime.newInstanceGmt(2026, 9, 25, 9, 0, 0);

    private static Integer sequence = 0;

    private static AMF_ApprovalHistory.Step step(String status, Boolean isPending, Datetime occurredAt) {
        sequence++;

        AMF_ApprovalHistory.Step built = new AMF_ApprovalHistory.Step();
        // A ProcessInstanceStep-shaped Id; numbering follows creation in this test.
        built.id = Id.valueOf('04h' + String.valueOf(sequence).leftPad(12, '0') + 'AAA');
        built.status = status;
        built.isPending = isPending;
        built.occurredAt = occurredAt;
        return built;
    }

    private static List<String> statusesOf(List<AMF_ApprovalHistory.Step> steps) {
        List<String> statuses = new List<String>();
        for (AMF_ApprovalHistory.Step each : steps) {
            statuses.add(each.status);
        }
        return statuses;
    }

    @IsTest
    static void stepsSortByWhenTheyHappenedWhateverOrderTheyArriveIn() {
        List<AMF_ApprovalHistory.Step> steps = new List<AMF_ApprovalHistory.Step>{
            step('Approved', false, NINE.addHours(2)),
            step('Started', false, NINE),
            step('Rejected', false, NINE.addHours(5)),
            step('Approved', false, NINE.addHours(1))
        };

        AMF_ApprovalHistory.sortChronologically(steps);

        Assert.areEqual(
            new List<String>{ 'Started', 'Approved', 'Approved', 'Rejected' },
            statusesOf(steps)
        );
        Assert.areEqual(NINE.addHours(1), steps[1].occurredAt, 'Earlier decision first');
    }

    @IsTest
    static void withinOneSecondTheSubmissionLeadsAndTheOpenWorkItemTrails() {
        // One Approval.process() writes the submission and the first work item;
        // one approval writes the decision and the next work item. Both pairs
        // share a CreatedDate, so the order must come from what they are.
        List<AMF_ApprovalHistory.Step> steps = new List<AMF_ApprovalHistory.Step>{
            step('Pending', true, NINE.addMinutes(30)),
            step('Pending', true, NINE),
            step('Approved', false, NINE.addMinutes(30)),
            step('Started', false, NINE)
        };

        AMF_ApprovalHistory.sortChronologically(steps);

        Assert.areEqual(
            new List<String>{ 'Started', 'Pending', 'Approved', 'Pending' },
            statusesOf(steps),
            'Submitted, the first item, the decision on it, then the item it handed on to'
        );
        Assert.areEqual(NINE, steps[1].occurredAt);
        Assert.isTrue(steps[3].isPending, 'What is still open comes last');
    }

    @IsTest
    static void idSettlesWhatTimeAndStageCannot() {
        // Two approvers working one step in parallel: two open items, one instant.
        AMF_ApprovalHistory.Step first = step('Pending', true, NINE);
        AMF_ApprovalHistory.Step second = step('Pending', true, NINE);

        List<AMF_ApprovalHistory.Step> steps = new List<AMF_ApprovalHistory.Step>{ second, first };
        AMF_ApprovalHistory.sortChronologically(steps);

        Assert.areEqual(first.id, steps[0].id, 'A deterministic order, so two reads never disagree');
        Assert.areEqual(second.id, steps[1].id);
    }

    @IsTest
    static void missingValuesSortLastRatherThanThrowing() {
        AMF_ApprovalHistory.Step undated = step('Approved', false, null);
        AMF_ApprovalHistory.Step alsoUndated = step('Rejected', false, null);
        AMF_ApprovalHistory.Step dated = step('Approved', false, NINE);
        AMF_ApprovalHistory.Step noId = step('Approved', false, NINE);
        noId.id = null;
        AMF_ApprovalHistory.Step alsoNoId = step('Approved', false, NINE);
        alsoNoId.id = null;

        List<AMF_ApprovalHistory.Step> steps = new List<AMF_ApprovalHistory.Step>{
            undated,
            noId,
            alsoUndated,
            dated,
            alsoNoId
        };
        AMF_ApprovalHistory.sortChronologically(steps);

        Assert.areEqual(dated.id, steps[0].id);
        Assert.isNull(steps[1].id, 'A step without an Id sorts after its peers');
        Assert.isNull(steps[2].id);
        Assert.isNull(steps[3].occurredAt, 'A step without a time sorts after every dated step');
        Assert.isNull(steps[4].occurredAt);

        // And a null list is simply nothing to sort.
        AMF_ApprovalHistory.sortChronologically(null);
    }
}
