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
     * Submits each request and returns its execution reference.
     *
     * Failure is an exception, never a short or empty result list. A strategy
     * that cannot submit must say so loudly: the engine has already written a
     * decision log row claiming Submitted by the time this runs, and 4.6 plus
     * the M1.3 lock design require that a post-write failure roll the whole
     * transaction back rather than leave a row asserting something that did not
     * happen.
     *
     * @param requests The records to submit and the process selected for each.
     * @return One result per request, in any order -- the engine matches them
     *         back by recordId. Empty only when requests was empty.
     */
    List<AMF_SubmitResult> submit(List<AMF_SubmitRequest> requests);
}
