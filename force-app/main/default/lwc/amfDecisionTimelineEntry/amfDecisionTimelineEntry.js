import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import LOCALE from '@salesforce/i18n/locale';

/** Outcome__c values (arch doc 3.3). */
const SUBMITTED = 'Submitted';
const BLOCKED = 'Blocked_No_Match';
const FAILED = 'Failed';

/** StepStatus values that are events in the approval rather than decisions on a step. */
const SUBMISSION = 'Started';
const RECALL = 'Removed';

/** AMF_DecisionTimelineService.Value kinds. */
const NUMBER = 'number';
const BOOLEAN = 'boolean';
const BLANK = 'blank';
const UNPARSED = 'unparsed';

/** ProcessInstance.Status, as a person reads it. Anything else is shown as the platform names it. */
const APPROVAL_STATUS = {
    Pending: { label: 'In approval' },
    Approved: { label: 'Approved', className: 'slds-theme_success' },
    Rejected: { label: 'Rejected', className: 'slds-theme_error' },
    Removed: { label: 'Recalled' }
};

/** StepStatus, as a person reads it, with its icon in the step list. */
const STEP_STATUS = {
    Started: { label: 'Submitted', icon: 'utility:send' },
    Pending: { label: 'Pending', icon: 'utility:clock', variant: 'warning' },
    Approved: { label: 'Approved', icon: 'utility:check', variant: 'success' },
    Rejected: { label: 'Rejected', icon: 'utility:close', variant: 'error' },
    Removed: { label: 'Recalled', icon: 'utility:undo' },
    Reassigned: { label: 'Reassigned', icon: 'utility:change_owner' },
    NoResponse: { label: 'No response', icon: 'utility:clock' },
    Held: { label: 'Held', icon: 'utility:pause' },
    Fault: { label: 'Fault', icon: 'utility:error', variant: 'error' }
};

/**
 * One entry in the decision timeline: one submission attempt, told as arch
 * doc 8's narrative -- "Matched PR_High_Value_APAC v3 because Amount =
 * 24,00,000 and Region = APAC -> PR_Three_Level_Finance -> [native step
 * history]".
 *
 * PRESENTATION ONLY. It is handed one AMF_DecisionTimelineService.Entry and
 * calls no Apex. The entry has up to two halves, and either may be missing:
 *   - decision: the log row, i.e. why. Absent when the viewer cannot read it.
 *   - approval: the native history, i.e. who and when. Absent when the
 *     attempt was blocked or failed and so never entered a process.
 * The collapsed item says what happened in one sentence; expanding it shows
 * the rule, the condition, the values read and the approval's steps.
 *
 * Only what was recorded is shown. The rule is named by the DeveloperName
 * the row snapshotted, never by today's description of it (arch doc 8's M7
 * note), and every value is rendered as template text, never as markup.
 */
export default class AmfDecisionTimelineEntry extends NavigationMixin(LightningElement) {
    view = {};
    logUrl;

    _entry;
    _expanded = false;
    connected = false;

    /** The AMF_DecisionTimelineService.Entry to show. */
    @api
    get entry() {
        return this._entry;
    }
    set entry(value) {
        this._entry = value;
        this.view = viewOf(value);
        this.logUrl = undefined;
        if (this.connected) {
            this.generateLogUrl();
        }
    }

    /** Whether the details start open. The user's toggling wins after that. */
    @api
    get expanded() {
        return this._expanded;
    }
    set expanded(value) {
        this._expanded = Boolean(value);
    }

    connectedCallback() {
        this.connected = true;
        this.generateLogUrl();
    }

    disconnectedCallback() {
        this.connected = false;
    }

    get itemClass() {
        return `slds-timeline__item_expandable amf-timeline__item${this._expanded ? ' slds-is-open' : ''}`;
    }

    get ariaExpanded() {
        return String(this._expanded);
    }

    get toggleIcon() {
        return this._expanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get toggleLabel() {
        return this._expanded ? 'Hide details' : 'Show details';
    }

    /** A real href, so the link can be opened in a new tab, and is focusable before it resolves. */
    get logHref() {
        return this.logUrl || '#';
    }

    handleToggle() {
        this._expanded = !this._expanded;
    }

    handleOpenLog(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate](logPageOf(this.view.decision.logId));
    }

    async generateLogUrl() {
        const logId = this.view.decision?.logId;
        if (!logId) {
            return;
        }
        try {
            const url = await this[NavigationMixin.GenerateUrl](logPageOf(logId));
            // The entry may have been replaced while the URL was being generated.
            if (this.view.decision?.logId === logId) {
                this.logUrl = url;
            }
        } catch {
            // The click handler navigates without it; the href is a convenience.
        }
    }
}

function logPageOf(recordId) {
    return {
        type: 'standard__recordPage',
        attributes: {
            recordId,
            objectApiName: 'Approval_Decision_Log__c',
            actionName: 'view'
        }
    };
}

/** The whole entry, shaped for the template once, when it is set. */
function viewOf(entry) {
    const decision = entry?.decision ? decisionViewOf(entry.decision) : undefined;
    const approval = entry?.approval ? approvalViewOf(entry.approval) : undefined;

    return {
        occurredAt: entry?.occurredAt,
        decision,
        approval,
        approvalMissing: decision?.outcome === SUBMITTED && !approval,
        ...headlineOf(decision, approval)
    };
}

/** The collapsed item: its icon, its one-line title and summary, and its status badge. */
function headlineOf(decision, approval) {
    if (!decision) {
        return {
            assistiveText: 'Approval',
            icon: 'standard:approval',
            title: `Submitted to ${approval?.processName}`,
            summary: 'The decision log row that explains this route is not visible to you.',
            badge: approval?.badge
        };
    }

    switch (decision.outcome) {
        case SUBMITTED:
            return {
                assistiveText: 'Submission',
                icon: 'standard:approval',
                title: `Routed to ${decision.selectedProcess}`,
                summary: reasonOf(decision),
                badge: approval?.badge
            };
        case BLOCKED:
            return {
                assistiveText: 'Blocked submission',
                icon: 'utility:ban',
                iconVariant: 'error',
                title: 'Not submitted: no rule matched',
                summary: 'No active rule matched, so the matrix blocked it rather than routing it by default.',
                badge: { label: 'Blocked', className: 'slds-theme_error' }
            };
        case FAILED:
            return {
                assistiveText: 'Failed submission',
                icon: 'utility:error',
                iconVariant: 'error',
                title: 'Not submitted: routing failed',
                summary: decision.rule
                    ? `Routing failed while evaluating ${decision.rule}.`
                    : 'Routing failed before any rule was evaluated.',
                badge: { label: 'Failed', className: 'slds-theme_error' }
            };
        default:
            // Outcome__c is required on every path the engine writes (arch doc
            // 3.3); a row without one is shown, not hidden, so the gap is visible.
            return {
                assistiveText: 'Decision',
                icon: 'standard:approval',
                title: 'Decision recorded',
                summary: decision.outcome ? `Recorded outcome: ${decision.outcome}.` : 'No outcome was recorded.',
                badge: approval?.badge
            };
    }
}

/** Arch doc 8's sentence: the rule, and the values that made it true. */
function reasonOf(decision) {
    if (decision.hasValues) {
        return `Matched ${decision.rule} because ${sentenceOf(decision.values)}.`;
    }
    if (decision.rawValues) {
        return `Matched ${decision.rule}.`;
    }
    return `Matched ${decision.rule}, whose condition reads no fields, so it matches every record.`;
}

function decisionViewOf(decision) {
    const recorded = decision.values ?? [];
    const values = recorded.filter((value) => value.kind !== UNPARSED).map(valueViewOf);

    return {
        logId: decision.logId,
        logName: decision.logName,
        outcome: decision.outcome,
        rule: ruleOf(decision),
        expression: decision.expression,
        selectedProcess: decision.selectedProcess,
        values,
        hasValues: values.length > 0,
        rawValues: recorded.find((value) => value.kind === UNPARSED)?.text,
        detail: decision.detail,
        submitter: decision.submittedByName || 'Unknown user'
    };
}

/** PR_High_Value_APAC v3: the name and version the row recorded. */
function ruleOf(decision) {
    if (!decision.matchedRule) {
        return undefined;
    }
    return decision.ruleVersion === undefined || decision.ruleVersion === null
        ? decision.matchedRule
        : `${decision.matchedRule} v${decision.ruleVersion}`;
}

function valueViewOf(value) {
    return {
        key: value.path,
        path: value.path,
        label: value.label || value.path,
        display: displayOf(value)
    };
}

/**
 * A recorded value as it reads. A number keeps the precision it was recorded
 * with and is grouped for the viewer's locale; a blank says so, because a blank
 * that decided a route is worth seeing; booleans read as the expression
 * language writes them.
 */
function displayOf(value) {
    switch (value.kind) {
        case NUMBER:
            return formatNumber(value.text);
        case BOOLEAN:
            return value.text === 'true' ? 'TRUE' : 'FALSE';
        case BLANK:
            return '(blank)';
        default:
            return value.text ?? '';
    }
}

function formatNumber(text) {
    const number = Number(text);
    if (!text || !Number.isFinite(number)) {
        return text ?? '';
    }
    const fraction = /\.(\d+)/.exec(text);
    const fractionDigits = Math.min(fraction ? fraction[1].length : 0, 20);
    return new Intl.NumberFormat(LOCALE, { maximumFractionDigits: fractionDigits }).format(number);
}

/** "A = 1", "A = 1 and B = 2", "A = 1, B = 2 and C = 3". */
function sentenceOf(values) {
    const parts = values.map((value) => `${value.label} = ${value.display}`);
    if (parts.length <= 1) {
        return parts.join('');
    }
    return `${parts.slice(0, -1).join(', ')} and ${parts[parts.length - 1]}`;
}

function approvalViewOf(approval) {
    const status = APPROVAL_STATUS[approval.status] ?? { label: approval.status };

    return {
        processName: approval.processName,
        status: status.label,
        badge: status.label ? { label: status.label, className: status.className } : undefined,
        steps: (approval.steps ?? []).map(stepViewOf)
    };
}

function stepViewOf(step, index) {
    const status = STEP_STATUS[step.status] ?? { label: step.status || 'Unknown', icon: 'utility:info' };
    const isEvent = step.status === SUBMISSION || step.status === RECALL;

    return {
        key: step.id || String(index),
        icon: status.icon,
        iconVariant: status.variant,
        statusLabel: status.label,
        // The submission and a recall belong to no approval step; a decision is
        // named for the step it was made on, with its outcome beside it.
        title: isEvent ? status.label : step.stepName || status.label,
        statusText: !isEvent && step.stepName ? status.label : undefined,
        actorLine: actorLineOf(step),
        occurredAt: step.occurredAt,
        comments: step.comments
    };
}

function actorLineOf(step) {
    const actor = step.actorName || 'Unknown user';

    if (step.status === SUBMISSION || step.status === RECALL) {
        return `by ${actor}`;
    }
    if (step.isPending) {
        return `Waiting on ${actor}`;
    }
    // A delegate, or an admin acting on someone's behalf: say whose step it was.
    if (step.originalActorId && step.originalActorId !== step.actorId && step.originalActorName) {
        return `${actor}, for ${step.originalActorName}`;
    }
    return actor;
}
