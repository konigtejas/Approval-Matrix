/**
 * The seam between an approval decision's recorded facts and the model that
 * puts them into plain English.
 *
 * Architecture section: 8 (auditability, and its M13 note), 10 (testability).
 *
 * Production: AMF_EinsteinExplanationGenerator, which runs the
 * AMF_Explain_Approval_Decision prompt template through Einstein. Tests inject
 * a stub, for the reason 10 gives for every seam in this codebase: a
 * generation is neither deterministic nor available to an Apex test. What the
 * framework owes is decided before the call -- which facts the model is given,
 * and that it is given nothing else -- and that is what the tests pin.
 *
 * The model never decides anything. It is handed a decision the engine has
 * already made and recorded, and the native history that followed, and asked
 * to say what they mean.
 */
public interface AMF_ExplanationGenerator {

    /**
     * @param facts    The decision as recorded, in plain text: everything the
     *                 model may explain, and nothing it may not.
     * @param question What the reader asked, in their words, or
     *                 AMF_DecisionExplainer.DEFAULT_QUESTION.
     * @return The explanation, as the model wrote it. Never blank.
     * @throws AMF_ExplanationException When no explanation could be generated.
     */
    String generate(String facts, String question);
}
