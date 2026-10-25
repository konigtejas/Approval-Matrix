import { LightningElement } from 'lwc';

/**
 * Jest stand-in for lightning/modal (LightningModal), mapped in jest.config.js.
 *
 * @salesforce/sfdx-lwc-jest 7.9.0 stubs lightning/modalHeader, modalBody and
 * modalFooter but not lightning/modal itself, so without this a LightningModal
 * subclass cannot even be imported in a test. It lives outside force-app so it
 * can never be picked up by a deploy.
 *
 * open() resolves undefined, as the real one does when the modal is dismissed;
 * tests spy on it to choose the user's answer. close(result) is what a subclass
 * calls to finish, and here it dispatches a `close` event carrying the result,
 * so a test can observe which answer the modal gave.
 *
 * No decorators: the jest-mocks lint config uses the plain parser, and nothing
 * sets the real component's public properties (size, label, description,
 * disableClose) on an instance in these tests.
 */
export default class LightningModal extends LightningElement {
    static open() {
        return Promise.resolve(undefined);
    }

    close(result) {
        this.dispatchEvent(new CustomEvent('close', { detail: result }));
    }
}
