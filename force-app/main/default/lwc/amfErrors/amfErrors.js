/**
 * The text of an error, whatever shape it reached the component in.
 *
 * Apex errors reach LWC in several shapes depending on how they were raised,
 * and a component that reads only one of them shows "[object Object]" for the
 * rest. Falling back through them keeps the server's own sentence -- written
 * for the person reading it -- in front of them.
 *
 * Started in M13 so that components share one copy. amfSubmitForApproval
 * still carries its own (technical log M7.6).
 *
 * @param {*} error What a rejected Apex call or a thrown error delivered.
 * @param {string} fallback What to say when the error carries no text.
 * @returns {string} The message to show.
 */
export function messageOf(error, fallback) {
    return error?.body?.message || error?.body?.pageErrors?.[0]?.message || error?.message || fallback;
}
