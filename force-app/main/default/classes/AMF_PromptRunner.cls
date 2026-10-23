/**
 * The seam between the admin assistant's deterministic work and the model that
 * writes words around it (M15): a rule draft's first attempt, and a health
 * report's summary.
 *
 * Architecture section: 7 (its M15 note), 10 (testability).
 *
 * Production: AMF_EinsteinPromptRunner, which runs a Flex prompt template.
 * Tests inject a stub, for the reason 10 gives for every seam in this
 * codebase: a generation is neither deterministic nor available to an Apex
 * test. What the framework owes -- what the model is given, and what is
 * checked before anyone sees its answer -- is decided outside this call.
 *
 * Separate from M13's AMF_ExplanationGenerator, which keeps its own two inputs
 * and its own messages; neither depends on the other.
 */
public interface AMF_PromptRunner {

    /**
     * @param templateName DeveloperName of a Flex prompt template.
     * @param inputs       Each input's API name, as the template declares it
     *                     (Request, not Input:Request), to its text.
     * @return The first generation's text, trimmed. Never blank.
     * @throws AMF_PromptException When no text could be generated, with the reason.
     */
    String run(String templateName, Map<String, String> inputs);
}
