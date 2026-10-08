import { LightningElement, api } from 'lwc';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import getTimeline from '@salesforce/apex/AMF_DecisionTimelineService.getTimeline';

/**
 * The decision timeline: arch doc 8's "read-only timeline LWC [that] renders
 * both halves as one narrative" -- why the matrix routed each submission where
 * it did, and what has happened to it since -- on the governed record's page.
 *
 * This component owns the data and its freshness; c/amfDecisionTimelineEntry
 * renders each entry. Newest first, the newest entry open.
 *
 * ALWAYS CURRENT, NEVER CACHED. getTimeline is deliberately not cacheable, for
 * the reason arch doc 6.4 gives for the preview: a cached audit view outlives
 * the next decision on the record. So it is called imperatively, and re-read
 * on three occasions:
 *   - when the component connects;
 *   - when the record page refreshes (lightning/refresh), which
 *     c/amfSubmitForApproval raises after every submission attempt, so a new
 *     entry appears without a page reload;
 *   - when the user clicks refresh, e.g. after an approver acted elsewhere.
 *
 * Reads can overlap -- a page refresh while the first load is still out -- so
 * every read takes a ticket, and only the latest ticket may write the result.
 * An older answer arriving late must not overwrite a newer one.
 */
export default class AmfDecisionTimeline extends LightningElement {
    @api recordId;

    entries = [];
    hasMore = false;
    error;
    isLoading = false;
    hasLoaded = false;

    latestRequest = 0;
    refreshHandlerId;

    connectedCallback() {
        this.refreshHandlerId = registerRefreshHandler(this, this.refreshHandler.bind(this));
        this.load();
    }

    disconnectedCallback() {
        unregisterRefreshHandler(this.refreshHandlerId);
    }

    /** lightning/refresh's contract: resolve true once the data has been re-read. */
    refreshHandler() {
        return this.load().then(() => true);
    }

    handleRefresh() {
        this.load();
    }

    /** Never rejects: a failed read becomes the error state. */
    async load() {
        const ticket = ++this.latestRequest;
        this.isLoading = true;

        try {
            const timeline = await getTimeline({ recordId: this.recordId });
            if (ticket === this.latestRequest) {
                this.entries = timeline?.entries ?? [];
                this.hasMore = Boolean(timeline?.hasMore);
                this.error = undefined;
            }
        } catch (error) {
            if (ticket === this.latestRequest) {
                // An audit view that cannot be read says so, rather than going
                // on showing what it read last time as if it were current.
                this.entries = [];
                this.hasMore = false;
                this.error = messageOf(error);
            }
        } finally {
            if (ticket === this.latestRequest) {
                this.isLoading = false;
                this.hasLoaded = true;
            }
        }
    }

    get items() {
        return this.entries.map((entry, index) => ({
            key: entry.key,
            entry,
            expanded: index === 0
        }));
    }

    get hasEntries() {
        return this.entries.length > 0;
    }

    get isEmpty() {
        return this.hasLoaded && !this.error && this.entries.length === 0;
    }
}

/**
 * Apex errors reach LWC in several shapes depending on how they were raised.
 * Falling back through them keeps the service's own sentence -- for instance,
 * that the user needs read access to the record -- in front of the user.
 */
function messageOf(error) {
    return (
        error?.body?.message ||
        error?.body?.pageErrors?.[0]?.message ||
        error?.message ||
        'The approval timeline could not be loaded.'
    );
}
