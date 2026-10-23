/**
 * Raised when a plain-English explanation of an approval decision cannot be
 * given: the decision is not visible to the reader, or no explanation could be
 * generated.
 *
 * Architecture section: 8 (auditability, and its M13 note).
 *
 * Its message is written for the person who asked, because every caller shows
 * it to them as it is: the record page, as an error under the Explain button,
 * and the Approval Matrix Assistant, as its answer. An explanation is
 * presentation only, so failing to give one never touches a route or a
 * decision log row.
 */
public class AMF_ExplanationException extends Exception {
}
