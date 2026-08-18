import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import submitRecord from '@salesforce/apex/AMF_ApprovalMatrixService.submitRecord';

/**
 * The framework's submit action: arch doc 7's UI row.
 *
 * HEADLESS, and that is 13.1 rather than an aesthetic choice. 6.4 describes a
 * preview that returns the matched rule and template without writing or
 * submitting, and drives a confirmation modal from it -- but the preview modal
 * is explicitly out of MVP scope, so this component has no template, no
 * confirmation and no `preview()` call behind it. It submits, and reports what
 * the matrix decided.
 *
 * WHY A BLOCKED SUBMISSION ARRIVES AS DATA RATHER THAN AS AN ERROR. The Apex
 * entry point returns an Outcome instead of throwing when a record is blocked,
 * because an exception escaping an @AuraEnabled method rolls its transaction
 * back and would destroy the Approval_Decision_Log__c row this toast is about
 * to tell the user to go and read (3.3). So `submitted === false` is the normal
 * blocked path and the catch below is for faults that legitimately rolled back:
 * an ungoverned object, a record the user cannot read, a rule that will not
 * compile.
 */
export default class AmfSubmitForApproval extends LightningElement {
    @api recordId;
    @api objectApiName;

    /**
     * The headless quick action entry point. The platform calls this; there is
     * no rendered UI to click through.
     */
    @api
    async invoke() {
        try {
            const outcome = await submitRecord({ recordId: this.recordId });

            if (outcome.submitted) {
                this.toast(
                    'Submitted for approval',
                    `Matched ${outcome.matchedRule} (v${outcome.ruleVersion}) and routed to ${outcome.selectedProcess}.`,
                    'success'
                );
            } else {
                // Blocked or failed. The decision log row explaining it has
                // already been written and survives this message.
                this.toast('Not submitted', outcome.message, 'error', 'sticky');
            }
        } catch (error) {
            this.toast('Could not submit for approval', this.messageOf(error), 'error', 'sticky');
        } finally {
            // Matrix_Submission__c and the record's lock state both moved, so
            // the page the user is looking at is now stale either way.
            notifyRecordUpdateAvailable([{ recordId: this.recordId }]);
        }
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
