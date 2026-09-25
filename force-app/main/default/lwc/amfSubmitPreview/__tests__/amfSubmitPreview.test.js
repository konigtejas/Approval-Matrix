import { createElement } from 'lwc';
import AmfSubmitPreview from 'c/amfSubmitPreview';

const HIGH_VALUE_APAC = {
    outcome: 'Submitted',
    submitted: false,
    matchedRule: 'PR_High_Value_APAC',
    ruleVersion: 3,
    rulePriority: 10,
    matchedRuleDescription: 'High-value APAC spend',
    matchedExpression: "Amount__c > 100000 && Region__c == 'APAC'",
    evaluatedValuesJson: '{"Amount__c":250000,"Region__c":"APAC"}',
    selectedProcess: 'PR_Three_Level_Finance'
};

const CATCH_ALL = {
    outcome: 'Submitted',
    submitted: false,
    matchedRule: 'PR_Catch_All',
    ruleVersion: 1,
    rulePriority: 9999,
    matchedExpression: 'TRUE',
    evaluatedValuesJson: '{}',
    selectedProcess: 'PR_Two_Level_Mgmt'
};

function render(preview) {
    const element = createElement('c-amf-submit-preview', { is: AmfSubmitPreview });
    element.preview = preview;
    document.body.appendChild(element);
    return element;
}

function byId(element, id) {
    return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

describe('c-amf-submit-preview', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    it('names the process, the rule that chose it, and the rule\'s condition', () => {
        const element = render(HIGH_VALUE_APAC);

        expect(byId(element, 'process').textContent).toBe('PR_Three_Level_Finance');
        expect(byId(element, 'rule').textContent).toBe('PR_High_Value_APAC');
        expect(byId(element, 'description').textContent).toBe('High-value APAC spend');
        expect(byId(element, 'priority').textContent).toBe('10');
        expect(byId(element, 'version').textContent).toBe('3');
        expect(byId(element, 'expression').textContent).toBe("Amount__c > 100000 && Region__c == 'APAC'");
    });

    it('shows each value the rule read, numbers formatted for the viewer\'s locale', () => {
        const element = render(HIGH_VALUE_APAC);

        const rows = element.shadowRoot.querySelectorAll('[data-id="value-row"]');
        expect(rows).toHaveLength(2);

        const amountCells = rows[0].querySelectorAll('td');
        expect(amountCells[0].textContent).toBe('Amount__c');
        const amount = amountCells[1].querySelector('lightning-formatted-number');
        expect(amount).not.toBeNull();
        expect(amount.value).toBe(250000);

        const regionCells = rows[1].querySelectorAll('td');
        expect(regionCells[0].textContent).toBe('Region__c');
        expect(regionCells[1].querySelector('lightning-formatted-number')).toBeNull();
        expect(regionCells[1].textContent).toBe('APAC');

        expect(byId(element, 'no-values')).toBeNull();
    });

    it('shows a blank value that decided a route rather than hiding it, and booleans as TRUE/FALSE', () => {
        const element = render({
            ...HIGH_VALUE_APAC,
            evaluatedValuesJson: '{"Region__c":null,"Account__r.Is_Strategic__c":false}'
        });

        const cells = [...element.shadowRoot.querySelectorAll('[data-id="value-row"] td')].map(
            (cell) => cell.textContent
        );
        expect(cells).toEqual(['Region__c', '(blank)', 'Account__r.Is_Strategic__c', 'FALSE']);
    });

    it('says the catch-all reads no fields instead of showing an empty table', () => {
        const element = render(CATCH_ALL);

        expect(byId(element, 'values')).toBeNull();
        expect(byId(element, 'no-values')).not.toBeNull();
        expect(byId(element, 'expression').textContent).toBe('TRUE');
    });

    it('leaves out the description row when the rule has no description', () => {
        const element = render(CATCH_ALL);

        expect(byId(element, 'description')).toBeNull();
    });

    it('resolves with submit only when the user confirms', () => {
        const element = render(HIGH_VALUE_APAC);
        const closed = jest.fn();
        element.addEventListener('close', (event) => closed(event.detail));

        byId(element, 'submit').click();

        expect(closed).toHaveBeenCalledTimes(1);
        expect(closed).toHaveBeenCalledWith('submit');
    });

    it('resolves with cancel when the user backs out', () => {
        const element = render(HIGH_VALUE_APAC);
        const closed = jest.fn();
        element.addEventListener('close', (event) => closed(event.detail));

        byId(element, 'cancel').click();

        expect(closed).toHaveBeenCalledTimes(1);
        expect(closed).toHaveBeenCalledWith('cancel');
    });
});
