/**
 * The Claude connector's explanation generator (M16): hands back the facts it is
 * given, unwritten, so that Claude writes the words instead of Einstein.
 *
 * Architecture section: 8 (explanations, and its M13 and M14 notes), 10.
 *
 * AMF_DecisionExplainer builds an explanation's facts -- the decision log row's
 * own snapshot and the native approval steps -- and passes them to an
 * AMF_ExplanationGenerator, which in the record page is Einstein. Through the
 * connector the model is Claude, outside the transaction, so this generator
 * returns the facts themselves. Everything the explainer decides still holds:
 * which row the reader may see, the current-approver rule for a briefing (M14),
 * and how a reassigned step is described. Nothing is generated or stored here.
 */
public with sharing class AMF_McpFactsOnly implements AMF_ExplanationGenerator {

    /**
     * @param facts    The explanation's facts, as the explainer wrote them.
     * @param question Unused: Claude has the user's question itself.
     * @return The facts, unchanged.
     */
    public String generate(String facts, String question) {
        return facts;
    }
}
