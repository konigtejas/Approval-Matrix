/**
 * The engine's error type: a submission that cannot proceed at all.
 *
 * Architecture section: 6.1 (submission flow), 4.6 (fail loudly).
 *
 * Distinct from AMF_ExpressionException, which belongs to the expression
 * package and always carries a character position. This one covers faults that
 * have no position because they are not about an expression: nothing to submit,
 * a record the caller cannot read, an object with no active rules, a mix of
 * object types in one call.
 *
 * SCOPE, and it is narrow on purpose. This exception is raised only for faults
 * that condemn the WHOLE call. A fault that condemns one record -- no rule
 * matched, the matched rule names no process, evaluation hit schema drift --
 * does not throw: it writes that record's decision log row and returns a
 * blocked Outcome, because an exception escaping the top of an Apex request
 * rolls back every DML before it and would erase the very audit row 3.3 exists
 * to create. Recorded in docs/decisions.md, 2026-08-18.
 */
public class AMF_SubmissionException extends Exception {
}
