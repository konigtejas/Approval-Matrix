import { api } from 'lwc';
import LightningModal from 'lightning/modal';

/**
 * close() results. c/amfSubmitForApproval submits only on SUBMIT; anything
 * else, including undefined from the header's X or Escape, submits nothing.
 */
const SUBMIT = 'submit';
const CANCEL = 'cancel';

/**
 * The confirmation modal behind the Submit for Approval action: arch doc 6.4
 * and 7's UI row ("headless LWC quick action -> preview -> confirm -> submit").
 *
 * WHY A LightningModal, OPENED FROM THE HEADLESS ACTION. The quick action is a
 * headless LWC action, and the org refuses to change an existing LWC action's
 * type to a screen action (technical log M3.4a). 7 asks for a headless action
 * anyway, so c/amfSubmitForApproval stays headless and opens this modal itself.
 *
 * PRESENTATION ONLY. It is handed the Outcome that
 * AMF_ApprovalMatrixService.preview() returned, and it only ever shows a
 * routable one: a blocked or failed preview has nothing to confirm, so the
 * action submits it directly to write the decision log row 6.1 step 6 requires.
 * The modal calls no Apex and resolves with SUBMIT or CANCEL; the action does
 * the submitting, so there is exactly one place that submits.
 *
 * Everything shown comes from fields the submitter can already read on their
 * own decision log row (Approval_Matrix_User), and every value is rendered as
 * text by the template, never as markup.
 */
export default class AmfSubmitPreview extends LightningModal {
    /** The AMF_ApprovalMatrixService.Outcome preview() returned for this record. */
    @api preview;

    get hasDescription() {
        return Boolean(this.preview?.matchedRuleDescription);
    }

    /**
     * One row per value the winning rule read, in the order the JSON carries
     * them. Numbers are handed to lightning-formatted-number so they read in
     * the viewer's locale; a blank field reads as "(blank)" rather than as
     * nothing, because a null that decided a route is worth seeing.
     */
    get values() {
        const json = this.preview?.evaluatedValuesJson;
        const parsed = json ? JSON.parse(json) : {};

        return Object.keys(parsed).map((path) => {
            const value = parsed[path];
            return {
                path,
                value,
                isNumber: typeof value === 'number',
                display: displayOf(value)
            };
        });
    }

    get hasValues() {
        return this.values.length > 0;
    }

    handleSubmit() {
        this.close(SUBMIT);
    }

    handleCancel() {
        this.close(CANCEL);
    }
}

function displayOf(value) {
    if (value === null || value === undefined) {
        return '(blank)';
    }
    if (typeof value === 'boolean') {
        return value ? 'TRUE' : 'FALSE';
    }
    return String(value);
}
