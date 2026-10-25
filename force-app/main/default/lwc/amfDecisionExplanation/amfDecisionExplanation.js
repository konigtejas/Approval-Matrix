import { LightningElement, api } from 'lwc';
import explainDecision from '@salesforce/apex/AMF_DecisionExplainer.explainDecision';
import LOCALE from '@salesforce/i18n/locale';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import { messageOf } from 'c/amfErrors';

/**
 * One decision's plain-English explanation, on the decision timeline: arch doc
 * 8's M13 note. c/amfDecisionTimelineEntry shows it at the top of an entry's
 * details, above the recorded rule, condition and values it explains.
 *
 * ON DEMAND, NEVER STORED. Nothing is written until the reader asks, because a
 * generation takes seconds and most readers only need the recorded facts. The
 * explanation then lives in this component and nowhere else: the decision log
 * stays the only record of why. Every explanation is labelled AI-generated and
 * names the row it was written from, so it is never mistaken for that record.
 *
 * NEVER STALE. The explanation covers where the approval stands, which moves
 * as approvers act. historyKey changes when the timeline's refresh brings a new
 * status or step, and the explanation is then put away rather than left
 * describing a state that has passed; the reader can ask again.
 *
 * Reads can overlap -- a second click on "write it again", or a refresh while a
 * generation is out -- so every request takes a ticket, and only the latest may
 * write the result.
 */
export default class AmfDecisionExplanation extends LightningElement {
    /** The Approval_Decision_Log__c row to explain. */
    @api logId;

    /** AMF_DecisionExplainer.Explanation, once written. */
    explanation;
    error;
    isLoading = false;

    latestRequest = 0;
    _historyKey;

    /**
     * Identifies the state of the approval behind the decision. When it changes,
     * an explanation written before is put away.
     */
    @api
    get historyKey() {
        return this._historyKey;
    }
    set historyKey(value) {
        if (this._historyKey !== undefined && value !== this._historyKey) {
            this.reset();
        }
        this._historyKey = value;
    }

    get showButton() {
        return Boolean(this.logId) && !this.isLoading && !this.explanation && !this.error;
    }

    /** The first generation, with nothing written yet to keep on screen while it runs. */
    get isFirstLoad() {
        return this.isLoading && !this.explanation;
    }

    get ariaBusy() {
        return String(this.isLoading);
    }

    /** A rewrite in progress dims the text it will replace. */
    get textClass() {
        return `amf-explanation__text${this.isLoading ? ' amf-explanation__text_stale' : ''}`;
    }

    /** "Written by Einstein at 14:05 from decision log ADL-00000031. ..." as one string, so no space is lost. */
    get provenance() {
        const at = timeOf(this.explanation?.generatedAt);
        const from = this.explanation?.logName ? ` from decision log ${this.explanation.logName}` : '';
        return `Written by Einstein${at ? ` at ${at}` : ''}${from}. Check it against the recorded details below.`;
    }

    async handleExplain() {
        if (this.isLoading || !this.logId) {
            return;
        }

        const ticket = ++this.latestRequest;
        this.isLoading = true;
        this.error = undefined;

        try {
            const explanation = await explainDecision({ logId: this.logId });
            if (ticket === this.latestRequest) {
                this.explanation = explanation;
            }
        } catch (error) {
            if (ticket === this.latestRequest) {
                // A failed rewrite does not leave the earlier explanation looking current.
                this.explanation = undefined;
                this.error = messageOf(error, 'The explanation could not be written. Try again.');
            }
        } finally {
            if (ticket === this.latestRequest) {
                this.isLoading = false;
            }
        }
    }

    reset() {
        // Any generation still out belongs to the state just put away.
        this.latestRequest++;
        this.explanation = undefined;
        this.error = undefined;
        this.isLoading = false;
    }
}

/** 14:05, or 2:05 PM, in the viewer's Salesforce locale and time zone. */
function timeOf(value) {
    if (!value) {
        return undefined;
    }
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
        return undefined;
    }
    return new Intl.DateTimeFormat(LOCALE, { hour: 'numeric', minute: '2-digit', timeZone: TIME_ZONE }).format(date);
}
