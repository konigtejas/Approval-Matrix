import { LightningElement, api } from 'lwc';
import { registerRefreshHandler, unregisterRefreshHandler } from 'lightning/refresh';
import getTimeline from '@salesforce/apex/AMF_DecisionTimelineService.getTimeline';
import { messageOf } from 'c/amfErrors';

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
 *   - when recordId changes without the component being recreated, which is
 *     how a record page moves from one record to the next;
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
    _recordId;

    /**
     * Set before the component connects, and again when the page navigates to
     * another record without destroying this one. The second case must re-read:
     * connectedCallback does not run again.
     */
    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        const changed = value !== this._recordId;
        this._recordId = value;
        if (changed && this.isConnected) {
            this.load();
        }
    }

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
                this.error = messageOf(error, 'The approval timeline could not be loaded.');
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
