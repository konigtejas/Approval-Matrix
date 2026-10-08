import { createElement } from 'lwc';
import AmfDecisionTimelineEntry from 'c/amfDecisionTimelineEntry';
import { mockNavigation } from 'lightning/navigation';

// The sfdx-lwc-jest stub's Navigate and GenerateUrl record nothing, so this one
// remembers each page reference it is given.
jest.mock(
    'lightning/navigation',
    () => {
        const Navigate = Symbol('Navigate');
        const GenerateUrl = Symbol('GenerateUrl');
        const calls = { navigate: [], generateUrl: [] };
        const NavigationMixin = (Base) =>
            class extends Base {
                [Navigate](pageReference) {
                    calls.navigate.push(pageReference);
                }

                [GenerateUrl](pageReference) {
                    calls.generateUrl.push(pageReference);
                    return Promise.resolve(`/lightning/r/${pageReference.attributes.recordId}/view`);
                }
            };
        NavigationMixin.Navigate = Navigate;
        NavigationMixin.GenerateUrl = GenerateUrl;
        return { NavigationMixin, mockNavigation: calls };
    },
    { virtual: true }
);

const SUBMITTER = '005000000000001AAA';
const ANALYST = '005000000000003AAA';
const CONTROLLER = '005000000000004AAA';
const LOG_ID = 'a01000000000011AAA';

/** What AMF_DecisionTimelineService returns for the M5.7 rehearsal, one step further on. */
const ROUTED = {
    key: LOG_ID,
    occurredAt: '2026-09-25T09:00:00.000Z',
    decision: {
        logId: LOG_ID,
        logName: 'ADL-00000011',
        outcome: 'Submitted',
        matchedRule: 'PR_High_Value_APAC',
        ruleVersion: 3,
        expression: "Amount__c > 100000 && Region__c == 'APAC'",
        values: [
            { path: 'Amount__c', label: 'Amount', kind: 'number', text: '2400000.00' },
            { path: 'Region__c', label: 'Region', kind: 'text', text: 'APAC' }
        ],
        selectedProcess: 'PR_Three_Level_Finance',
        submittedById: SUBMITTER,
        submittedByName: 'Ann Submitter',
        submittedAt: '2026-09-25T09:00:00.000Z'
    },
    approval: {
        id: '04g000000000001AAA',
        processName: 'PR_Three_Level_Finance',
        status: 'Pending',
        submittedAt: '2026-09-25T09:00:00.000Z',
        steps: [
            {
                id: '04h000000000001AAA',
                status: 'Started',
                isPending: false,
                actorId: SUBMITTER,
                actorName: 'Ann Submitter',
                originalActorId: SUBMITTER,
                originalActorName: 'Ann Submitter',
                occurredAt: '2026-09-25T09:00:00.000Z'
            },
            {
                id: '04h000000000002AAA',
                status: 'Approved',
                isPending: false,
                stepName: 'Finance Analyst',
                actorId: ANALYST,
                actorName: 'AMF Approver Three',
                originalActorId: ANALYST,
                originalActorName: 'AMF Approver Three',
                comments: 'Within budget',
                occurredAt: '2026-09-25T11:02:00.000Z'
            },
            {
                id: '04i000000000003AAA',
                status: 'Pending',
                isPending: true,
                stepName: 'Finance Controller',
                actorId: CONTROLLER,
                actorName: 'AMF Approver Four',
                originalActorId: CONTROLLER,
                originalActorName: 'AMF Approver Four',
                occurredAt: '2026-09-25T11:02:00.000Z'
            }
        ]
    }
};

const BLOCKED = {
    key: 'a01000000000005AAA',
    occurredAt: '2026-09-07T10:00:00.000Z',
    decision: {
        logId: 'a01000000000005AAA',
        logName: 'ADL-00000005',
        outcome: 'Blocked_No_Match',
        values: [{ path: 'Risk_Level__c', label: 'Risk Level', kind: 'text', text: 'Low' }],
        detail: 'No active rule matched this Purchase_Request__c. 2 active rule(s) were evaluated and none was true.',
        submittedByName: 'Ann Submitter'
    }
};

/** An approval whose decision log row the viewer cannot read (arch doc 8, M7 note). */
const UNEXPLAINED = {
    key: '04g000000000009AAA',
    occurredAt: '2026-09-20T08:00:00.000Z',
    approval: {
        id: '04g000000000009AAA',
        processName: 'PR_Two_Level_Mgmt',
        status: 'Approved',
        steps: [
            {
                id: '04h000000000009AAA',
                status: 'Started',
                isPending: false,
                actorName: 'Someone Else',
                occurredAt: '2026-09-20T08:00:00.000Z'
            }
        ]
    }
};

function render(entry, expanded = false) {
    const element = createElement('c-amf-decision-timeline-entry', { is: AmfDecisionTimelineEntry });
    element.entry = entry;
    element.expanded = expanded;
    document.body.appendChild(element);
    return element;
}

function byId(element, id) {
    return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

function allById(element, id) {
    return Array.from(element.shadowRoot.querySelectorAll(`[data-id="${id}"]`));
}

function textOf(node) {
    return node.textContent.replace(/\s+/g, ' ').trim();
}

/** jsdom has no structuredClone; the fixtures are plain JSON, as Apex returns them. */
function clone(value) {
    return JSON.parse(JSON.stringify(value));
}

/** Test-only: let every pending promise and re-render settle before asserting. */
function flushPromises() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    return new Promise((resolve) => setTimeout(resolve, 0));
}

/**
 * The log link's href arrives asynchronously, from NavigationMixin.GenerateUrl,
 * after the entry renders. Wait for the expected href rather than for a fixed
 * number of ticks; if it never arrives, the href is returned as it stands and
 * the assertion that follows fails.
 */
async function hrefOnceSettled(element, expected, attempts = 10) {
    for (let attempt = 0; attempt < attempts; attempt++) {
        if (byId(element, 'log-link')?.getAttribute('href') === expected) {
            break;
        }
        // eslint-disable-next-line no-await-in-loop
        await flushPromises();
    }
    return byId(element, 'log-link')?.getAttribute('href');
}

describe('c-amf-decision-timeline-entry', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        mockNavigation.navigate.length = 0;
        mockNavigation.generateUrl.length = 0;
    });

    it('tells a routed submission in one sentence: the rule, its version and the values that made it true', () => {
        const element = render(ROUTED);

        expect(textOf(byId(element, 'title'))).toBe('Routed to PR_Three_Level_Finance');
        expect(textOf(byId(element, 'summary'))).toBe(
            'Matched PR_High_Value_APAC v3 because Amount = 2,400,000 and Region = APAC.'
        );
        expect(byId(element, 'badge').label).toBe('In approval');
        expect(byId(element, 'icon').iconName).toBe('standard:approval');
        expect(byId(element, 'date').value).toBe('2026-09-25T09:00:00.000Z');
    });

    it('starts collapsed unless told otherwise, and says so to assistive technology', () => {
        const element = render(ROUTED);

        expect(byId(element, 'details')).toBeNull();
        expect(byId(element, 'toggle').getAttribute('aria-expanded')).toBe('false');
        expect(byId(element, 'toggle').title).toBe('Show details');
    });

    it('opens to show the rule, the condition, the values read and who submitted it', () => {
        const element = render(ROUTED, true);

        expect(byId(element, 'toggle').getAttribute('aria-expanded')).toBe('true');
        expect(textOf(byId(element, 'rule'))).toBe('PR_High_Value_APAC v3');
        expect(textOf(byId(element, 'expression'))).toBe("Amount__c > 100000 && Region__c == 'APAC'");

        const values = allById(element, 'value');
        expect(values.map(textOf)).toEqual(['Amount = 2,400,000', 'Region = APAC']);
        // The recorded path is one hover away; the label is presentation only.
        expect(values[0].title).toBe('Amount__c');

        expect(textOf(byId(element, 'submitter'))).toBe('Ann Submitter');
        expect(textOf(byId(element, 'log-link'))).toBe('ADL-00000011');
        expect(byId(element, 'detail')).toBeNull();
    });

    it('shows the native steps in the order they happened, naming the step, the approver and their comment', () => {
        const element = render(ROUTED, true);

        expect(textOf(byId(element, 'process'))).toBe('PR_Three_Level_Finance');
        expect(textOf(byId(element, 'approval-status'))).toBe('In approval');

        expect(allById(element, 'step-title').map(textOf)).toEqual([
            'Submitted',
            'Finance Analyst',
            'Finance Controller'
        ]);
        expect(allById(element, 'step-status').map(textOf)).toEqual([', Approved', ', Pending']);
        expect(allById(element, 'step-actor').map(textOf)).toEqual([
            'by Ann Submitter',
            'AMF Approver Three',
            'Waiting on AMF Approver Four'
        ]);
        expect(allById(element, 'step-comments').map(textOf)).toEqual(['Within budget']);

        const icons = allById(element, 'step').map((step) => step.querySelector('lightning-icon'));
        expect(icons.map((icon) => icon.iconName)).toEqual(['utility:send', 'utility:check', 'utility:clock']);
        expect(icons[1].alternativeText).toBe('Approved');
        expect(byId(element, 'approval-missing')).toBeNull();
    });

    it('names whose step it was when someone else acted on it', () => {
        const delegated = clone(ROUTED);
        delegated.approval.steps[1].actorId = '005000000000009AAA';
        delegated.approval.steps[1].actorName = 'AMF Admin';

        const element = render(delegated, true);

        expect(allById(element, 'step-actor').map(textOf)[1]).toBe('AMF Admin, for AMF Approver Three');
    });

    it('reads naturally when the rule read a single value', () => {
        const highRisk = clone(ROUTED);
        Object.assign(highRisk.decision, {
            matchedRule: 'PR_High_Risk',
            ruleVersion: 1,
            expression: "Risk_Level__c == 'High'",
            values: [{ path: 'Risk_Level__c', label: 'Risk Level', kind: 'text', text: 'High' }]
        });

        const element = render(highRisk);

        expect(textOf(byId(element, 'summary'))).toBe('Matched PR_High_Risk v1 because Risk Level = High.');
    });

    it('says the catch-all matched every record rather than leaving an empty "because"', () => {
        const catchAll = clone(ROUTED);
        Object.assign(catchAll.decision, {
            matchedRule: 'PR_Catch_All',
            ruleVersion: 1,
            expression: 'TRUE',
            values: [],
            selectedProcess: 'PR_Two_Level_Mgmt'
        });

        const element = render(catchAll, true);

        expect(textOf(byId(element, 'summary'))).toBe(
            'Matched PR_Catch_All v1, whose condition reads no fields, so it matches every record.'
        );
        expect(byId(element, 'values')).toBeNull();
    });

    it('tells a blocked attempt apart: the values read and the recorded reason, and no approval', () => {
        const element = render(BLOCKED, true);

        expect(textOf(byId(element, 'title'))).toBe('Not submitted: no rule matched');
        expect(byId(element, 'icon').iconName).toBe('utility:ban');
        expect(byId(element, 'icon').variant).toBe('error');
        expect(byId(element, 'badge').label).toBe('Blocked');
        expect(textOf(byId(element, 'summary'))).toBe(
            'No active rule matched, so the matrix blocked it rather than routing it by default.'
        );

        expect(byId(element, 'rule')).toBeNull();
        expect(allById(element, 'value').map(textOf)).toEqual(['Risk Level = Low']);
        expect(byId(element, 'detail').textContent).toBe(BLOCKED.decision.detail);
        expect(byId(element, 'approval')).toBeNull();
        expect(byId(element, 'approval-missing')).toBeNull();
    });

    it('tells a failed attempt by the first line of its recorded reason, with the whole failure in the details', () => {
        const failed = {
            key: 'a01000000000006AAA',
            occurredAt: '2026-09-08T10:00:00.000Z',
            decision: {
                logId: 'a01000000000006AAA',
                logName: 'ADL-00000006',
                outcome: 'Failed',
                matchedRule: 'PR_High_Risk',
                ruleVersion: 2,
                expression: "Risk_Level__c == 'High'",
                values: [],
                detail: 'Routing failed while evaluating rule PR_High_Risk: field deleted\nClass.AMF_Evaluator.resolve: line 1',
                submittedByName: 'Ann Submitter'
            }
        };

        const element = render(failed, true);

        expect(textOf(byId(element, 'title'))).toBe('Not submitted: the attempt failed');
        expect(byId(element, 'icon').iconName).toBe('utility:error');
        expect(byId(element, 'badge').label).toBe('Failed');
        expect(textOf(byId(element, 'summary'))).toBe(
            'Routing failed while evaluating rule PR_High_Risk: field deleted'
        );
        expect(textOf(byId(element, 'rule'))).toBe('PR_High_Risk v2');
        expect(byId(element, 'detail').textContent).toBe(failed.decision.detail);
    });

    it('tells a submission the platform refused by the reason it gave, not as a rule that failed', () => {
        const refused = {
            key: 'a01000000000008AAA',
            occurredAt: '2026-10-08T10:00:00.000Z',
            decision: {
                logId: 'a01000000000008AAA',
                logName: 'ADL-00000008',
                outcome: 'Failed',
                matchedRule: 'PR_Catch_All',
                ruleVersion: 1,
                expression: 'TRUE',
                selectedProcess: 'PR_Two_Level_Mgmt',
                values: [],
                detail: 'Approval process PR_Two_Level_Mgmt refused the submission: MANAGER_NOT_DEFINED: Manager undefined.',
                submittedByName: 'Ann Submitter'
            }
        };

        const element = render(refused, true);

        expect(textOf(byId(element, 'title'))).toBe('Not submitted: the attempt failed');
        expect(textOf(byId(element, 'summary'))).toBe(refused.decision.detail);
        expect(textOf(byId(element, 'rule'))).toBe('PR_Catch_All v1');
        expect(byId(element, 'approval')).toBeNull();
        expect(byId(element, 'approval-missing')).toBeNull();
    });

    it('falls back to the rule a failed row names when it recorded no reason', () => {
        const element = render({
            key: 'a01000000000009AAA',
            occurredAt: '2026-09-08T10:00:00.000Z',
            decision: {
                logId: 'a01000000000009AAA',
                outcome: 'Failed',
                matchedRule: 'PR_High_Risk',
                ruleVersion: 2,
                values: []
            }
        });

        expect(textOf(byId(element, 'summary'))).toBe('Routing failed while evaluating PR_High_Risk v2.');
    });

    it('says when routing failed before any rule was evaluated', () => {
        const element = render({
            key: 'a01000000000007AAA',
            occurredAt: '2026-09-08T10:00:00.000Z',
            decision: { logId: 'a01000000000007AAA', outcome: 'Failed', values: [], detail: '  ' }
        });

        expect(textOf(byId(element, 'summary'))).toBe('Routing failed before any rule was evaluated.');
    });

    it('shows an approval whose log row the viewer cannot read, and says why the reason is missing', () => {
        const element = render(UNEXPLAINED, true);

        expect(textOf(byId(element, 'title'))).toBe('Submitted to PR_Two_Level_Mgmt');
        expect(textOf(byId(element, 'summary'))).toBe(
            'The decision log row that explains this route is not visible to you.'
        );
        expect(byId(element, 'badge').label).toBe('Approved');
        expect(byId(element, 'badge').className).toContain('slds-theme_success');
        expect(byId(element, 'decision')).toBeNull();
        expect(allById(element, 'step-actor').map(textOf)).toEqual(['by Someone Else']);
    });

    it('says so when the approval behind a routed submission is not available', () => {
        const element = render({ ...ROUTED, approval: undefined }, true);

        expect(byId(element, 'badge')).toBeNull();
        expect(byId(element, 'approval')).toBeNull();
        expect(byId(element, 'approval-missing')).not.toBeNull();
    });

    it('keeps the precision a number was recorded with, marks a blank, and reads booleans as rules write them', () => {
        const entry = clone(ROUTED);
        entry.decision.values = [
            { path: 'Amount__c', label: 'Amount', kind: 'number', text: '1234.5678' },
            { path: 'Region__c', label: 'Region', kind: 'blank' },
            { path: 'Account__r.Is_Strategic__c', label: 'Account > Strategic', kind: 'boolean', text: 'true' },
            { path: 'Matrix_Submission__c', label: 'Matrix Submission', kind: 'boolean', text: 'false' },
            { path: 'Gone__c', label: 'Gone__c', kind: 'text', text: 'x' },
            { path: 'Odd__c', label: 'Odd', kind: 'number', text: 'not a number' }
        ];

        const element = render(entry, true);

        expect(allById(element, 'value').map(textOf)).toEqual([
            'Amount = 1,234.5678',
            'Region = (blank)',
            'Account > Strategic = TRUE',
            'Matrix Submission = FALSE',
            'Gone__c = x',
            // Shown as recorded rather than as NaN.
            'Odd = not a number'
        ]);
    });

    it('shows a values snapshot it could not read exactly as recorded, without inventing a reason', () => {
        const entry = clone(ROUTED);
        entry.decision.values = [{ kind: 'unparsed', text: 'not json' }];

        const element = render(entry, true);

        expect(textOf(byId(element, 'summary'))).toBe('Matched PR_High_Value_APAC v3.');
        expect(byId(element, 'values')).toBeNull();
        expect(textOf(byId(element, 'raw-values'))).toBe('not json');
    });

    it('shows a row with no outcome rather than hiding it', () => {
        const element = render({
            key: 'a01000000000008AAA',
            occurredAt: '2026-09-08T10:00:00.000Z',
            decision: { logId: 'a01000000000008AAA', values: [] }
        });

        expect(textOf(byId(element, 'title'))).toBe('Decision recorded');
        expect(textOf(byId(element, 'summary'))).toBe('No outcome was recorded.');
    });

    it('falls back to the platform\'s own name for a status it has no wording for', () => {
        const entry = clone(UNEXPLAINED);
        entry.approval.status = 'Held';
        entry.approval.steps.push({
            id: '04h000000000010AAA',
            status: 'SomethingNew',
            isPending: false,
            actorName: 'AMF Approver Three',
            occurredAt: '2026-09-21T08:00:00.000Z'
        });

        const element = render(entry, true);

        expect(byId(element, 'badge').label).toBe('Held');
        expect(allById(element, 'step-title').map(textOf)).toEqual(['Submitted', 'SomethingNew']);
        const icons = allById(element, 'step').map((step) => step.querySelector('lightning-icon'));
        expect(icons[1].iconName).toBe('utility:info');
    });

    it('opens and closes on the toggle, and keeps the user\'s choice', async () => {
        const element = render(ROUTED);
        const toggle = byId(element, 'toggle');

        toggle.click();
        await flushPromises();
        expect(byId(element, 'details')).not.toBeNull();
        expect(toggle.getAttribute('aria-expanded')).toBe('true');
        expect(toggle.title).toBe('Hide details');
        expect(toggle.querySelector('lightning-icon').iconName).toBe('utility:chevrondown');

        toggle.click();
        await flushPromises();
        expect(byId(element, 'details')).toBeNull();
        expect(toggle.getAttribute('aria-expanded')).toBe('false');
    });

    it('links to its decision log row, and opens it in the app', async () => {
        const element = render(ROUTED, true);

        const expected = `/lightning/r/${LOG_ID}/view`;
        expect(await hrefOnceSettled(element, expected)).toBe(expected);

        byId(element, 'log-link').click();

        expect(mockNavigation.navigate).toEqual([
            {
                type: 'standard__recordPage',
                attributes: { recordId: LOG_ID, objectApiName: 'Approval_Decision_Log__c', actionName: 'view' }
            }
        ]);
    });

    it('generates no link for an entry without a decision log row', async () => {
        render(UNEXPLAINED, true);
        await flushPromises();

        expect(mockNavigation.generateUrl).toHaveLength(0);
    });

    it('follows a replaced entry, link included', async () => {
        const element = render(ROUTED, true);
        const first = `/lightning/r/${LOG_ID}/view`;
        expect(await hrefOnceSettled(element, first)).toBe(first);

        element.entry = BLOCKED;

        const replaced = '/lightning/r/a01000000000005AAA/view';
        expect(await hrefOnceSettled(element, replaced)).toBe(replaced);
        expect(textOf(byId(element, 'title'))).toBe('Not submitted: no rule matched');
    });
});
