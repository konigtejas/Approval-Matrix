import { createElement } from 'lwc';
import AmfSubmitForApproval from 'c/amfSubmitForApproval';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import submitRecord from '@salesforce/apex/AMF_ApprovalMatrixService.submitRecord';

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

describe('c-amf-submit-for-approval', () => {
    let element;
    let toasts;

    beforeEach(() => {
        element = createElement('c-amf-submit-for-approval', { is: AmfSubmitForApproval });
        element.recordId = RECORD_ID;
        document.body.appendChild(element);

        toasts = [];
        element.addEventListener('lightning__showtoast', (event) => toasts.push(event.detail));
    });

    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('renders nothing: it is a headless action (arch doc 13.1, no preview modal)', () => {
        expect(element.shadowRoot.children.length).toBe(0);
    });

    it('reports the matched rule and the process it routed to', async () => {
        submitRecord.mockResolvedValue({
            submitted: true,
            outcome: 'Submitted',
            matchedRule: 'PR_High_Value_APAC',
            ruleVersion: 3,
            selectedProcess: 'PR_Three_Level_Finance'
        });

        await element.invoke();

        expect(submitRecord).toHaveBeenCalledWith({ recordId: RECORD_ID });
        expect(toasts).toHaveLength(1);
        expect(toasts[0].variant).toBe('success');
        expect(toasts[0].message).toContain('PR_High_Value_APAC');
        expect(toasts[0].message).toContain('v3');
        expect(toasts[0].message).toContain('PR_Three_Level_Finance');
    });

    it('surfaces a blocked submission as an error without treating it as a thrown fault', async () => {
        // The Apex entry point returns rather than throws when a record is
        // blocked, so the decision log row survives the transaction (3.3).
        submitRecord.mockResolvedValue({
            submitted: false,
            outcome: 'Blocked_No_Match',
            message: 'No active rule matched this Purchase_Request__c.'
        });

        await element.invoke();

        expect(toasts).toHaveLength(1);
        expect(toasts[0].variant).toBe('error');
        expect(toasts[0].title).toBe('Not submitted');
        expect(toasts[0].message).toBe('No active rule matched this Purchase_Request__c.');
        expect(toasts[0].mode).toBe('sticky');
    });

    it('keeps the positioned Apex message when the call throws', async () => {
        // Arch doc 4.2 went to the trouble of producing a character position;
        // the toast must not replace it with "[object Object]".
        submitRecord.mockRejectedValue({
            body: { message: "Unexpected token ')' at position 34" }
        });

        await element.invoke();

        expect(toasts).toHaveLength(1);
        expect(toasts[0].variant).toBe('error');
        expect(toasts[0].message).toBe("Unexpected token ')' at position 34");
    });

    it('falls back to a readable message when the error carries no body', async () => {
        submitRecord.mockRejectedValue({});

        await element.invoke();

        expect(toasts[0].message).toBe('An unexpected error prevented the submission.');
    });

    it('refreshes the record however the submission ended', async () => {
        // Matrix_Submission__c and the record lock both moved on success, and on
        // failure the user needs to see that nothing did.
        submitRecord.mockResolvedValue({ submitted: true, matchedRule: 'PR_Catch_All' });
        await element.invoke();
        expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([{ recordId: RECORD_ID }]);

        jest.clearAllMocks();

        submitRecord.mockRejectedValue({ body: { message: 'nope' } });
        await element.invoke();
        expect(notifyRecordUpdateAvailable).toHaveBeenCalledWith([{ recordId: RECORD_ID }]);
    });
});
