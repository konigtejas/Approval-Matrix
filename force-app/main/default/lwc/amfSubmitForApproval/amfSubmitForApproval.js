import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import previewRecord from '@salesforce/apex/AMF_ApprovalMatrixService.previewRecord';
import submitRecord from '@salesforce/apex/AMF_ApprovalMatrixService.submitRecord';
import AmfSubmitPreview from 'c/amfSubmitPreview';

/** The only preview verdict with a route to confirm; see AMF_ApprovalMatrixService.Outcome. */
const ROUTABLE = 'Submitted';

/** What c/amfSubmitPreview resolves with when the user confirms. */
const SUBMIT = 'submit';

/**
 * The framework's submit action: arch doc 7's UI row, "headless LWC quick
 * action -> preview -> confirm -> submit".
 *
 * HEADLESS, with the confirmation in a LightningModal it opens itself
 * (c/amfSubmitPreview). The org refuses to change an existing LWC action's
 * type to a screen action (technical log M3.4a), and 7 asks for headless
 * anyway.
 *
 * THE FLOW (M5).
 *   1. previewRecord runs 6.4: steps 1-7, nothing written.
 *   2. A routable preview opens the modal. Only SUBMIT goes on; Cancel, the X
 *      and Escape submit nothing and leave no trace, because nothing happened.
 *   3. A blocked or failed preview skips the modal. There is no route to
 *      confirm, and 6.1 step 6 wants the attempt on record: submitting writes
 *      the Blocked_No_Match or Failed row and reports it, exactly as before M5.
 *   4. submitRecord re-runs the engine for real. If the record or the matrix
 *      changed in between, the route it takes can differ from the preview, and
 *      the toast then says so instead of implying the preview was followed.
 *
 * WHY A BLOCKED SUBMISSION ARRIVES AS DATA RATHER THAN AS AN ERROR. The Apex
 * entry point returns an Outcome instead of throwing when a record is blocked,
 * because an exception escaping an @AuraEnabled method rolls its transaction
 * back and would destroy the Approval_Decision_Log__c row this toast is about
 * to tell the user to go and read (3.3). So `submitted === false` is the normal
 * blocked path, and the catches below are for faults that legitimately rolled
 * back: an ungoverned object, a record the user cannot read, a rule that will
 * not compile.
 */
export default class AmfSubmitForApproval extends LightningElement {
    @api recordId;
    @api objectApiName;

    /**
     * The platform can call invoke() again while an earlier call is still
     * awaiting Apex; without this, a double click previews, and potentially
     * submits, twice.
     */
    isExecuting = false;

    /**
     * The headless quick action entry point. The platform calls this; the only
     * UI is the modal it opens.
     */
    @api
    async invoke() {
        if (this.isExecuting) {
            return;
        }
        this.isExecuting = true;

        try {
            await this.previewThenSubmit();
        } finally {
            this.isExecuting = false;
        }
    }

    async previewThenSubmit() {
        let preview;

        try {
            preview = await previewRecord({ recordId: this.recordId });

            if (preview.outcome === ROUTABLE) {
                const choice = await AmfSubmitPreview.open({
                    size: 'small',
                    label: 'Confirm approval route',
                    description: 'The approval process this record will enter, and why, before it is submitted.',
                    preview
                });
                if (choice !== SUBMIT) {
                    return;
                }
            }
        } catch (error) {
            // Nothing was written by the preview, so nothing needs refreshing.
            this.toast('Could not submit for approval', this.messageOf(error), 'error', 'sticky');
            return;
        }

        await this.submit(preview);
    }

    async submit(preview) {
        try {
            const outcome = await submitRecord({ recordId: this.recordId });

            if (!outcome.submitted) {
                // Blocked or failed. The decision log row explaining it has
                // already been written and survives this message.
                this.toast('Not submitted', outcome.message, 'error', 'sticky');
            } else if (this.routeChanged(preview, outcome)) {
                this.toast(
                    'Submitted, by a different route than previewed',
                    `The record or the matrix changed after the preview. Matched ${outcome.matchedRule} (v${outcome.ruleVersion}) and routed to ${outcome.selectedProcess}.`,
                    'warning',
                    'sticky'
                );
            } else {
                this.toast(
                    'Submitted for approval',
                    `Matched ${outcome.matchedRule} (v${outcome.ruleVersion}) and routed to ${outcome.selectedProcess}.`,
                    'success'
                );
            }
        } catch (error) {
            this.toast('Could not submit for approval', this.messageOf(error), 'error', 'sticky');
        } finally {
            // Matrix_Submission__c and the record's lock state both moved, so
            // the page the user is looking at is now stale either way.
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        }
    }

    routeChanged(preview, outcome) {
        return (
            preview.matchedRule !== outcome.matchedRule ||
            preview.ruleVersion !== outcome.ruleVersion ||
            preview.selectedProcess !== outcome.selectedProcess
        );
    }

    /**
     * Apex errors reach LWC in several shapes depending on how they were
     * raised. Falling back through them keeps arch doc 4.2's positioned,
     * actionable text in front of the admin instead of "[object Object]".
     */
    messageOf(error) {
        return (
            error?.body?.message ||
            error?.body?.pageErrors?.[0]?.message ||
            error?.message ||
            'An unexpected error prevented the submission.'
        );
    }

    toast(title, message, variant, mode = 'dismissable') {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant, mode }));
    }
}
