import { createElement } from 'lwc';
import AmfDecisionExplanation from 'c/amfDecisionExplanation';
import explainDecision from '@salesforce/apex/AMF_DecisionExplainer.explainDecision';

jest.mock('@salesforce/apex/AMF_DecisionExplainer.explainDecision', () => ({ default: jest.fn() }), {
    virtual: true
});

// The viewer's Salesforce locale and time zone, unlike the browser's, so a test
// can tell that the component used them.
jest.mock('@salesforce/i18n/locale', () => ({ __esModule: true, default: 'en-US' }), { virtual: true });
jest.mock('@salesforce/i18n/timeZone', () => ({ __esModule: true, default: 'Asia/Kolkata' }), { virtual: true });

const LOG_ID = 'a01000000000011AAA';

/** What AMF_DecisionExplainer.explainDecision returns. 08:35 UTC is 2:05 PM in Kolkata. */
const EXPLANATION = {
    text: 'This purchase request went to PR_Three_Level_Finance because its amount, 2,400,000, is over 100,000 and its region is APAC. It is now waiting on AMF Approver Four.',
    logId: LOG_ID,
    logName: 'ADL-00000011',
    generatedAt: '2026-10-23T08:35:00.000Z'
};

const REWRITTEN = {
    ...EXPLANATION,
    text: 'Rule PR_High_Value_APAC sent this request to PR_Three_Level_Finance. AMF Approver Four is next to decide.',
    generatedAt: '2026-10-23T08:40:00.000Z'
};

/** A promise the test settles when it chooses, to hold a generation in flight. */
function deferred() {
    let resolve;
    let reject;
    const promise = new Promise((res, rej) => {
        resolve = res;
        reject = rej;
    });
    return { promise, resolve, reject };
}

function render({ logId = LOG_ID, historyKey = 'v1' } = {}) {
    const element = createElement('c-amf-decision-explanation', { is: AmfDecisionExplanation });
    element.logId = logId;
    element.historyKey = historyKey;
    document.body.appendChild(element);
    return element;
}

function byId(element, id) {
    return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

function textOf(node) {
    return node.textContent.replace(/\s+/g, ' ').trim();
}

/** Test-only: let every pending promise and re-render settle before asserting. */
function flushPromises() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    return new Promise((resolve) => setTimeout(resolve, 0));
}

async function explainOnce(element, answer = EXPLANATION) {
    explainDecision.mockResolvedValueOnce(answer);
    byId(element, 'explain').click();
    await flushPromises();
}

describe('c-amf-decision-explanation', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('offers to explain the decision, and asks Einstein for nothing until the reader does', () => {
        const element = render();

        const button = byId(element, 'explain');
        expect(button).not.toBeNull();
        expect(button.label).toBe('Explain in plain English');
        expect(button.iconName).toBe('utility:einstein');
        expect(byId(element, 'result')).toBeNull();
        expect(explainDecision).not.toHaveBeenCalled();
    });

    it('says Einstein is writing, then shows the explanation, labelled AI-generated and traced to its row', async () => {
        const pending = deferred();
        explainDecision.mockReturnValueOnce(pending.promise);
        const element = render();

        byId(element, 'explain').click();
        await flushPromises();

        expect(explainDecision).toHaveBeenCalledWith({ logId: LOG_ID });
        expect(byId(element, 'loading')).not.toBeNull();
        expect(byId(element, 'region').contains(byId(element, 'loading'))).toBe(true);
        expect(byId(element, 'explain')).toBeNull();

        pending.resolve(EXPLANATION);
        await flushPromises();

        expect(byId(element, 'loading')).toBeNull();
        expect(textOf(byId(element, 'text'))).toBe(EXPLANATION.text);
        expect(byId(element, 'badge').label).toBe('AI-generated');
        expect(textOf(byId(element, 'provenance'))).toBe(
            'Written by Einstein at 2:05 PM from decision log ADL-00000011. Check it against the recorded details below.'
        );
        expect(byId(element, 'region').contains(byId(element, 'result'))).toBe(true);
        expect(byId(element, 'result').getAttribute('aria-busy')).toBe('false');
    });

    it('announces what happens from a live region that is there before anything happens', () => {
        const element = render();

        expect(byId(element, 'region').getAttribute('aria-live')).toBe('polite');
    });

    it('writes it again on request, keeping the earlier text dimmed until the new one arrives', async () => {
        const element = render();
        await explainOnce(element);

        const pending = deferred();
        explainDecision.mockReturnValueOnce(pending.promise);
        byId(element, 'regenerate').click();
        await flushPromises();

        expect(textOf(byId(element, 'text'))).toBe(EXPLANATION.text);
        expect(byId(element, 'text').classList.contains('amf-explanation__text_stale')).toBe(true);
        expect(byId(element, 'regenerate').disabled).toBe(true);
        expect(byId(element, 'result').getAttribute('aria-busy')).toBe('true');
        expect(byId(element, 'loading')).toBeNull();

        pending.resolve(REWRITTEN);
        await flushPromises();

        expect(textOf(byId(element, 'text'))).toBe(REWRITTEN.text);
        expect(byId(element, 'text').classList.contains('amf-explanation__text_stale')).toBe(false);
        expect(byId(element, 'regenerate').disabled).toBe(false);
        expect(explainDecision).toHaveBeenCalledTimes(2);
    });

    it("says why when no explanation can be written, in the server's own words, and lets the reader try again", async () => {
        const reason =
            'Plain-English explanations are not available right now. Einstein said: insufficient access. The recorded decision itself is unaffected.';
        explainDecision.mockRejectedValueOnce({ body: { message: reason } });
        const element = render();

        byId(element, 'explain').click();
        await flushPromises();

        expect(byId(element, 'error').getAttribute('role')).toBe('alert');
        expect(textOf(byId(element, 'error-text'))).toBe(reason);
        expect(byId(element, 'explain')).toBeNull();

        explainDecision.mockResolvedValueOnce(EXPLANATION);
        byId(element, 'retry').click();
        await flushPromises();

        expect(byId(element, 'error')).toBeNull();
        expect(textOf(byId(element, 'text'))).toBe(EXPLANATION.text);
    });

    it('falls back to a sentence of its own when the error carries no text', async () => {
        explainDecision.mockRejectedValueOnce({});
        const element = render();

        byId(element, 'explain').click();
        await flushPromises();

        expect(textOf(byId(element, 'error-text'))).toBe('The explanation could not be written. Try again.');
    });

    it('does not leave an earlier explanation looking current when a rewrite fails', async () => {
        const element = render();
        await explainOnce(element);

        explainDecision.mockRejectedValueOnce(new Error('Einstein is not available.'));
        byId(element, 'regenerate').click();
        await flushPromises();

        expect(byId(element, 'result')).toBeNull();
        expect(textOf(byId(element, 'error-text'))).toBe('Einstein is not available.');
    });

    it('puts the explanation away when the approval moves on, and offers to explain again', async () => {
        const element = render({ historyKey: 'pending|3' });
        await explainOnce(element);
        expect(byId(element, 'result')).not.toBeNull();

        element.historyKey = 'pending|3';
        await flushPromises();
        expect(byId(element, 'result')).not.toBeNull();

        element.historyKey = 'approved|4';
        await flushPromises();

        expect(byId(element, 'result')).toBeNull();
        expect(byId(element, 'explain')).not.toBeNull();
    });

    it('ignores an explanation that arrives after the approval moved on', async () => {
        const pending = deferred();
        explainDecision.mockReturnValueOnce(pending.promise);
        const element = render({ historyKey: 'pending|3' });

        byId(element, 'explain').click();
        await flushPromises();

        element.historyKey = 'approved|4';
        pending.resolve(EXPLANATION);
        await flushPromises();

        expect(byId(element, 'result')).toBeNull();
        expect(byId(element, 'loading')).toBeNull();
        expect(byId(element, 'explain')).not.toBeNull();
    });

    it('ignores a failure that arrives after the approval moved on', async () => {
        const pending = deferred();
        explainDecision.mockReturnValueOnce(pending.promise);
        const element = render({ historyKey: 'pending|3' });

        byId(element, 'explain').click();
        await flushPromises();

        element.historyKey = 'approved|4';
        pending.reject({ body: { message: 'Too late to matter.' } });
        await flushPromises();

        expect(byId(element, 'error')).toBeNull();
        expect(byId(element, 'explain')).not.toBeNull();
    });

    it('names no time or row it was not given', async () => {
        const element = render();
        await explainOnce(element, { text: 'Blocked: no rule matched.' });

        expect(textOf(byId(element, 'provenance'))).toBe(
            'Written by Einstein. Check it against the recorded details below.'
        );
    });

    it('offers nothing when there is no decision to explain', () => {
        // null, not undefined: undefined would take render()'s default Id.
        const element = render({ logId: null });

        expect(byId(element, 'explain')).toBeNull();
        expect(explainDecision).not.toHaveBeenCalled();
    });
});
