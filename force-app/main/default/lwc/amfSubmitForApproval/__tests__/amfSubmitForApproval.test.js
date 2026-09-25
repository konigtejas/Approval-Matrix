import { createElement } from 'lwc';
import AmfSubmitForApproval from 'c/amfSubmitForApproval';
import AmfSubmitPreview from 'c/amfSubmitPreview';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import previewRecord from '@salesforce/apex/AMF_ApprovalMatrixService.previewRecord';
import submitRecord from '@salesforce/apex/AMF_ApprovalMatrixService.submitRecord';

jest.mock(
    '@salesforce/apex/AMF_ApprovalMatrixService.previewRecord',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    '@salesforce/apex/AMF_ApprovalMatrixService.submitRecord',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

jest.mock(
    'lightning/uiRecordApi',
    () => ({ notifyRecordUpdateAvailable: jest.fn() }),
    { virtual: true }
);

const RECORD_ID = 'a01000000000001AAA';

/** What previewRecord returns for a record the matrix can route (6.4). */
const ROUTE = {
    recordId: RECORD_ID,
    outcome: 'Submitted',
    submitted: false,
    matchedRule: 'PR_High_Value_APAC',
    ruleVersion: 3,
    rulePriority: 10,
    matchedExpression: "Amount__c > 100000 && Region__c == 'APAC'",
    evaluatedValuesJson: '{"Amount__c":250000,"Region__c":"APAC"}',
    selectedProcess: 'PR_Three_Level_Finance'
};

/** What submitRecord returns when that route was taken. */
const SUBMITTED = {
    recordId: RECORD_ID,
    submitted: true,
    outcome: 'Submitted',
    matchedRule: 'PR_High_Value_APAC',
    ruleVersion: 3,
    selectedProcess: 'PR_Three_Level_Finance'
};

const NO_MATCH = {
    recordId: RECORD_ID,
    submitted: false,
    outcome: 'Blocked_No_Match',
    message: 'No active rule matched this Purchase_Request__c.'
};

describe('c-amf-submit-for-approval', () => {
    let element;
    let toasts;
    let openModal;

    beforeEach(() => {
        element = createElement('c-amf-submit-for-approval', { is: AmfSubmitForApproval });
        element.recordId = RECORD_ID;
        document.body.appendChild(element);

        toasts = [];
        element.addEventListener('lightning__showtoast', (event) => toasts.push(event.detail));

        openModal = jest.spyOn(AmfSubmitPreview, 'open');
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
        jest.restoreAllMocks();
    });

    it('renders nothing itself: it is headless, and the confirmation is a separate modal', () => {
        expect(element.shadowRoot.children.length).toBe(0);
    });

    it('previews the route and shows it in the modal before submitting anything', async () => {
        previewRecord.mockResolvedValue(ROUTE);
        openModal.mockResolvedValue('cancel');

        await element.invoke();

        expect(previewRecord).toHaveBeenCalledWith({ recordId: RECORD_ID });
        expect(openModal).toHaveBeenCalledTimes(1);
        expect(openModal).toHaveBeenCalledWith(expect.objectContaining({ preview: ROUTE, size: 'small' }));
        expect(openModal.mock.calls[0][0].label).toBeTruthy();
    });

    it('submits only after the user confirms, and reports the matched rule and process', async () => {
        previewRecord.mockResolvedValue(ROUTE);
        openModal.mockResolvedValue('submit');
        submitRecord.mockResolvedValue(SUBMITTED);

        await element.invoke();

        expect(submitRecord).toHaveBeenCalledWith({ recordId: RECORD_ID });
        expect(toasts).toHaveLength(1);
        expect(toasts[0].variant).toBe('success');
        expect(toasts[0].title).toBe('Submitted for approval');
        expect(toasts[0].message).toContain('PR_High_Value_APAC');
        expect(toasts[0].message).toContain('v3');
        expect(toasts[0].message).toContain('PR_Three_Level_Finance');
    });

    it.each([
        ['Cancel', 'cancel'],
        ['the X or Escape', undefined]
    ])('submits nothing, says nothing and refreshes nothing when the user backs out with %s', async (_, answer) => {
        previewRecord.mockResolvedValue(ROUTE);
        openModal.mockResolvedValue(answer);

        await element.invoke();

        expect(submitRecord).not.toHaveBeenCalled();
        expect(toasts).toHaveLength(0);
        expect(notifyRecordUpdateAvailable).not.toHaveBeenCalled();
    });

    it.each([['Blocked_No_Match'], ['Failed']])(
        'skips the modal for a %s preview and submits, so the attempt is logged and explained',
        async (outcome) => {
            // Nothing to confirm; 6.1 step 6 wants the row, and only a
            // submission writes it.
            previewRecord.mockResolvedValue({ ...NO_MATCH, outcome });
            submitRecord.mockResolvedValue({ ...NO_MATCH, outcome });

            await element.invoke();

            expect(openModal).not.toHaveBeenCalled();
            expect(submitRecord).toHaveBeenCalledWith({ recordId: RECORD_ID });
            expect(toasts).toHaveLength(1);
            expect(toasts[0].variant).toBe('error');
            expect(toasts[0].title).toBe('Not submitted');
            expect(toasts[0].message).toBe('No active rule matched this Purchase_Request__c.');
            expect(toasts[0].mode).toBe('sticky');
        }
    );

    it('says so when the submission took a different route than the preview showed', async () => {
        // The record or the matrix changed between preview and confirm; the
        // engine re-evaluates, and the user must not be told the preview held.
        previewRecord.mockResolvedValue(ROUTE);
        openModal.mockResolvedValue('submit');
        submitRecord.mockResolvedValue({
            ...SUBMITTED,
            matchedRule: 'PR_Catch_All',
            ruleVersion: 1,
            selectedProcess: 'PR_Two_Level_Mgmt'
        });

        await element.invoke();

        expect(toasts).toHaveLength(1);
        expect(toasts[0].variant).toBe('warning');
        expect(toasts[0].mode).toBe('sticky');
        expect(toasts[0].message).toContain('PR_Catch_All');
        expect(toasts[0].message).toContain('PR_Two_Level_Mgmt');
    });

    it('treats a new rule version as a changed route even when the process is the same', async () => {
        previewRecord.mockResolvedValue(ROUTE);
        openModal.mockResolvedValue('submit');
        submitRecord.mockResolvedValue({ ...SUBMITTED, ruleVersion: 4 });

        await element.invoke();

        expect(toasts[0].variant).toBe('warning');
    });

    it('surfaces a submission blocked after a routable preview as an error', async () => {
        previewRecord.mockResolvedValue(ROUTE);
        openModal.mockResolvedValue('submit');
        submitRecord.mockResolvedValue(NO_MATCH);

        await element.invoke();

        expect(toasts).toHaveLength(1);
        expect(toasts[0].variant).toBe('error');
        expect(toasts[0].title).toBe('Not submitted');
        expect(toasts[0].mode).toBe('sticky');
    });

    it('keeps the positioned Apex message when the preview throws, and submits nothing', async () => {
        // Arch doc 4.2 went to the trouble of producing a character position;
        // the toast must not replace it with "[object Object]".
        previewRecord.mockRejectedValue({
            body: { message: "Unexpected token ')' at position 34" }
        });

        await element.invoke();

        expect(openModal).not.toHaveBeenCalled();
        expect(submitRecord).not.toHaveBeenCalled();
        expect(toasts).toHaveLength(1);
        expect(toasts[0].variant).toBe('error');
        expect(toasts[0].mode).toBe('sticky');
        expect(toasts[0].message).toBe("Unexpected token ')' at position 34");
        expect(notifyRecordUpdateAvailable).not.toHaveBeenCalled();
    });

    it('keeps the positioned Apex message when the submission throws', async () => {
        previewRecord.mockResolvedValue(ROUTE);
        openModal.mockResolvedValue('submit');
        submitRecord.mockRejectedValue({ body: { message: 'ALREADY_IN_PROCESS' } });

        await element.invoke();

        expect(toasts).toHaveLength(1);
        expect(toasts[0].variant).toBe('error');
        expect(toasts[0].message).toBe('ALREADY_IN_PROCESS');
    });

    it('falls back to a readable message when the error carries no body', async () => {
        previewRecord.mockRejectedValue({});

        await element.invoke();

        expect(toasts[0].message).toBe('An unexpected error prevented the submission.');
    });

    it('submits nothing if the modal cannot open', async () => {
        previewRecord.mockResolvedValue(ROUTE);
        openModal.mockRejectedValue(new Error('modal failed to open'));

        await element.invoke();

        expect(submitRecord).not.toHaveBeenCalled();
        expect(toasts).toHaveLength(1);
        expect(toasts[0].variant).toBe('error');
        expect(toasts[0].message).toBe('modal failed to open');
    });

    it('refreshes the record however a submission ended', async () => {
        // Matrix_Submission__c and the record lock both moved on success, and on
        // failure the user needs to see that nothing did.
        previewRecord.mockResolvedValue(ROUTE);
        openModal.mockResolvedValue('submit');
        submitRecord.mockResolvedValue(SUBMITTED);
        await element.invoke();
        expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([{ recordId: RECORD_ID }]);

        notifyRecordUpdateAvailable.mockClear();

        submitRecord.mockRejectedValue({ body: { message: 'nope' } });
        await element.invoke();
        expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([{ recordId: RECORD_ID }]);
    });

    it('ignores a second click while the first is still in flight, then works again', async () => {
        let resolvePreview;
        previewRecord.mockReturnValueOnce(
            new Promise((resolve) => {
                resolvePreview = resolve;
            })
        );
        openModal.mockResolvedValue('cancel');

        const first = element.invoke();
        await element.invoke();
        expect(previewRecord).toHaveBeenCalledTimes(1);

        resolvePreview(ROUTE);
        await first;
        expect(openModal).toHaveBeenCalledTimes(1);

        previewRecord.mockResolvedValue(ROUTE);
        await element.invoke();
        expect(previewRecord).toHaveBeenCalledTimes(2);
        expect(openModal).toHaveBeenCalledTimes(2);
    });
});
