import { createElement } from 'lwc';
import AmfDecisionTimeline from 'c/amfDecisionTimeline';
import getTimeline from '@salesforce/apex/AMF_DecisionTimelineService.getTimeline';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';

jest.mock(
    '@salesforce/apex/AMF_DecisionTimelineService.getTimeline',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

const RECORD_ID = 'a00000000000001AAA';

/** A minimal entry: a blocked attempt, which needs no approval half. */
function entry(key, occurredAt = '2026-09-25T09:00:00.000Z') {
    return {
        key,
        occurredAt,
        decision: { logId: key, logName: `ADL-${key}`, outcome: 'Blocked_No_Match', values: [] }
    };
}

/** A promise the test settles when it chooses, to hold a read in flight. */
function deferred() {
    let resolve;
    let reject;
    const promise = new Promise((res, rej) => {
        resolve = res;
        reject = rej;
    });
    return { promise, resolve, reject };
}

function render() {
    const element = createElement('c-amf-decision-timeline', { is: AmfDecisionTimeline });
    element.recordId = RECORD_ID;
    document.body.appendChild(element);
    return element;
}

function byId(element, id) {
    return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

function entriesOf(element) {
    return Array.from(element.shadowRoot.querySelectorAll('c-amf-decision-timeline-entry'));
}

/** Test-only: let every pending promise and re-render settle before asserting. */
function flushPromises() {
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-amf-decision-timeline', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
        jest.clearAllMocks();
    });

    it('reads its record\'s timeline as soon as it connects, with a spinner meanwhile', async () => {
        const read = deferred();
        getTimeline.mockReturnValue(read.promise);

        const element = render();

        expect(getTimeline).toHaveBeenCalledWith({ recordId: RECORD_ID });
        await flushPromises();
        expect(byId(element, 'spinner')).not.toBeNull();
        expect(byId(element, 'refresh').disabled).toBe(true);
        expect(byId(element, 'empty')).toBeNull();

        read.resolve({ entries: [entry('a1')], hasMore: false });
        await flushPromises();

        expect(byId(element, 'spinner')).toBeNull();
        expect(byId(element, 'refresh').disabled).toBe(false);
        expect(entriesOf(element)).toHaveLength(1);
    });

    it('renders one entry per submission attempt, in the order given, with only the newest open', async () => {
        getTimeline.mockResolvedValue({
            entries: [entry('newest'), entry('middle'), entry('oldest')],
            hasMore: false
        });

        const element = render();
        await flushPromises();

        const rendered = entriesOf(element);
        expect(rendered.map((child) => child.entry.key)).toEqual(['newest', 'middle', 'oldest']);
        expect(rendered.map((child) => child.expanded)).toEqual([true, false, false]);
        expect(byId(element, 'has-more')).toBeNull();
    });

    it('says the record has not been submitted when there is nothing to show', async () => {
        getTimeline.mockResolvedValue({ entries: [], hasMore: false });

        const element = render();
        await flushPromises();

        expect(byId(element, 'empty')).not.toBeNull();
        expect(byId(element, 'timeline')).toBeNull();
        expect(byId(element, 'error')).toBeNull();
    });

    it('admits it when older entries are not shown', async () => {
        getTimeline.mockResolvedValue({ entries: [entry('a1')], hasMore: true });

        const element = render();
        await flushPromises();

        expect(byId(element, 'has-more')).not.toBeNull();
    });

    it('shows the service\'s own message when a read fails, and drops what it read before', async () => {
        getTimeline.mockResolvedValueOnce({ entries: [entry('a1')], hasMore: true });
        const element = render();
        await flushPromises();
        expect(entriesOf(element)).toHaveLength(1);

        getTimeline.mockRejectedValueOnce({
            body: { message: 'You need read access to this record to see its approval timeline.' }
        });
        byId(element, 'refresh').click();
        await flushPromises();

        expect(byId(element, 'error').textContent).toBe(
            'You need read access to this record to see its approval timeline.'
        );
        expect(entriesOf(element)).toHaveLength(0);
        expect(byId(element, 'has-more')).toBeNull();
        expect(byId(element, 'empty')).toBeNull();
    });

    it('falls back to a readable message when the error carries no body', async () => {
        getTimeline.mockRejectedValue({});

        const element = render();
        await flushPromises();

        expect(byId(element, 'error').textContent).toBe('The approval timeline could not be loaded.');
    });

    it('reads again when the user clicks refresh, and recovers from an earlier failure', async () => {
        getTimeline.mockRejectedValueOnce(new Error('offline'));
        const element = render();
        await flushPromises();
        expect(byId(element, 'error').textContent).toBe('offline');

        getTimeline.mockResolvedValueOnce({ entries: [entry('a1')], hasMore: false });
        byId(element, 'refresh').click();
        await flushPromises();

        expect(getTimeline).toHaveBeenCalledTimes(2);
        expect(byId(element, 'error')).toBeNull();
        expect(entriesOf(element)).toHaveLength(1);
    });

    it('re-reads when the record page refreshes, which is how a new submission appears', async () => {
        getTimeline.mockResolvedValueOnce({ entries: [], hasMore: false });
        const element = render();
        await flushPromises();

        expect(registerRefreshHandler).toHaveBeenCalledTimes(1);
        const refresh = registerRefreshHandler.mock.calls[0][1];

        getTimeline.mockResolvedValueOnce({ entries: [entry('just-submitted')], hasMore: false });
        await expect(refresh()).resolves.toBe(true);
        await flushPromises();

        expect(getTimeline).toHaveBeenCalledTimes(2);
        expect(entriesOf(element).map((child) => child.entry.key)).toEqual(['just-submitted']);
    });

    it('stops taking part in page refreshes when it leaves the page', async () => {
        getTimeline.mockResolvedValue({ entries: [], hasMore: false });
        const element = render();
        await flushPromises();

        const handlerId = registerRefreshHandler.mock.results[0].value;
        document.body.removeChild(element);

        expect(unregisterRefreshHandler).toHaveBeenCalledWith(handlerId);
    });

    it('keeps the newest answer when an older read finishes after it', async () => {
        const first = deferred();
        const second = deferred();
        getTimeline.mockReturnValueOnce(first.promise).mockReturnValueOnce(second.promise);

        const element = render();
        const refresh = registerRefreshHandler.mock.calls[0][1];
        const refreshed = refresh();

        second.resolve({ entries: [entry('current')], hasMore: false });
        await refreshed;
        first.resolve({ entries: [entry('stale')], hasMore: true });
        await flushPromises();

        expect(entriesOf(element).map((child) => child.entry.key)).toEqual(['current']);
        expect(byId(element, 'has-more')).toBeNull();
        expect(byId(element, 'spinner')).toBeNull();
    });

    it('ignores a failure from an older read that finishes after a newer one succeeded', async () => {
        const first = deferred();
        getTimeline.mockReturnValueOnce(first.promise).mockResolvedValueOnce({
            entries: [entry('current')],
            hasMore: false
        });

        const element = render();
        await registerRefreshHandler.mock.calls[0][1]();
        first.reject({ body: { message: 'too late to matter' } });
        await flushPromises();

        expect(byId(element, 'error')).toBeNull();
        expect(entriesOf(element)).toHaveLength(1);
    });
});
