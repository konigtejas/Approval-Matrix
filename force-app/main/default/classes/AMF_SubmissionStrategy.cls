/**
 * The only sanctioned way for framework code to start an approval.
 *
 * Architecture section: 6.2 (submission strategies), 10 (testability).
 *
 * CLAUDE.md states the rule flatly: all Approval.process() calls go through
 * this interface. In the MVP there is exactly one implementation,
 * AMF_ClassicProcessStrategy, and that is the single place in the codebase
 * where the platform call appears.
 *
 * Two things justify an interface with one implementation. First, testability
 * (10): approval mechanics resist unit testing, so every engine test swaps in
 * AMF_StrategyStub and asserts the staged guard field and the selected process
 * without a real approval running -- one thin integration test covers the real
 * path. Second, 6.2's boundary: step 10 is the only step that knows how a
 * process runs, so a Flow strategy lands here later without the evaluator, the
 * matrix or the decision log noticing.
 *
 * Named AMF_SubmissionStrategy rather than 6.2's bare SubmissionStrategy per
 * docs/decisions.md 2026-08-18 -- CLAUDE.md's "AMF_ on Apex classes" is the
 * override document and an interface is an Apex class file.
 *
 * Implementations: AMF_ClassicProcessStrategy in production,
 * AMF_StrategyStub in tests.
 */
public interface AMF_SubmissionStrategy {

    /**
     * Submits each request and answers for each one (6.2's M10 note).
     *
     * A record the platform refuses is a result that did not succeed, carrying
     * the platform's reason -- never an exception, and never a missing result.
     * The engine writes that record a Failed decision log row and lets the other
     * records' submissions stand, which it can do because it writes no row until
     * this method has answered.
     *
     * An exception means the strategy itself failed: a malformed request, or a
     * platform answer that contradicts itself. The engine rolls the whole call
     * back on it, submissions included, so nothing enters a process without the
     * row that explains it.
     *
     * @param requests The records to submit and the process selected for each.
     * @return Exactly one result per request, in any order -- the engine matches
     *         them back by recordId. Empty only when requests was empty.
     */
    List<AMF_SubmitResult> submit(List<AMF_SubmitRequest> requests);
}
