/**
 * Puts a recorded approval decision into plain English with Einstein, through
 * the AMF_Explain_Approval_Decision prompt template.
 *
 * Architecture section: 8 (auditability, and its M13 note), 11 (security).
 *
 * THE TEMPLATE IS A FLEX TEMPLATE WITH TWO TEXT INPUTS, Facts and Question,
 * rather than a record input it could ground itself. AMF_DecisionExplainer
 * builds Facts from the timeline's view of the decision, which has already
 * applied 8's and 11's rules: the record readable, the log row readable in user
 * mode, the native history shown only with the record. A template that read
 * the record or the log itself would need those rules again, in a second
 * place. The template ships in the agentforce package directory, because only
 * an org with Einstein generative AI can deploy one; this class names it by
 * DeveloperName and deploys anywhere.
 *
 * The call runs as the reader, so it needs the Prompt Template User permission
 * set, and Einstein's Trust Layer applies to it as to any prompt in the org.
 * Nothing it returns is stored: an explanation is presentation, and the
 * decision log stays the only record of why.
 */
public with sharing class AMF_EinsteinExplanationGenerator implements AMF_ExplanationGenerator {

    /** DeveloperName of the prompt template (agentforce/main/default/genAiPromptTemplates). */
    @TestVisible
    private static final String TEMPLATE_NAME = 'AMF_Explain_Approval_Decision';

    /** The template's inputs, as the template names them. */
    @TestVisible
    private static final String FACTS_INPUT = 'Input:Facts';

    @TestVisible
    private static final String QUESTION_INPUT = 'Input:Question';

    /**
     * Identifies these generations in Einstein's audit and feedback data as
     * prompt template runs, as the platform's own invocable action does.
     */
    private static final String APPLICATION_NAME = 'PromptTemplateGenerationsInvocable';

    /**
     * @param facts    The decision as recorded, in plain text.
     * @param question What the reader asked.
     * @return Einstein's explanation, trimmed.
     * @throws AMF_ExplanationException When Einstein is unavailable to this
     *         reader or returns nothing, with the platform's reason.
     */
    public String generate(String facts, String question) {
        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation output;

        try {
            output = ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(
                TEMPLATE_NAME,
                inputFor(facts, question)
            );
        } catch (Exception e) {
            throw new AMF_ExplanationException(unavailable(e.getMessage()));
        }

        String text = textOf(output);

        if (String.isBlank(text)) {
            throw new AMF_ExplanationException(
                'Einstein returned no explanation for this decision. Try again in a moment.'
            );
        }
        return text.trim();
    }

    /** The template's two inputs, for a real generation rather than a preview of the prompt. */
    @TestVisible
    private static ConnectApi.EinsteinPromptTemplateGenerationsInput inputFor(String facts, String question) {
        ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        input.isPreview = false;
        input.inputParams = new Map<String, ConnectApi.WrappedValue>{
            FACTS_INPUT => wrap(facts),
            QUESTION_INPUT => wrap(question)
        };
        input.additionalConfig = new ConnectApi.EinsteinLlmAdditionalConfigInput();
        input.additionalConfig.applicationName = APPLICATION_NAME;
        return input;
    }

    /** The first generation's text; null when Einstein returned none. */
    @TestVisible
    private static String textOf(ConnectApi.EinsteinPromptTemplateGenerationsRepresentation output) {
        if (output == null || output.generations == null || output.generations.isEmpty()) {
            return null;
        }
        return output.generations[0]?.text;
    }

    /**
     * The platform's refusal, prefixed with what it means for the reader. The
     * platform's own words stay in, because they are what an administrator
     * needs: a missing permission set, Einstein turned off, a template not
     * deployed.
     */
    @TestVisible
    private static String unavailable(String reason) {
        return 'Plain-English explanations are not available right now. ' +
            'Einstein said: ' +
            (String.isBlank(reason) ? 'no reason given.' : reason) +
            ' The recorded decision itself is unaffected; an administrator can check that you have the ' +
            'Prompt Template User permission set and that ' +
            TEMPLATE_NAME +
            ' is deployed.';
    }

    private static ConnectApi.WrappedValue wrap(String value) {
        ConnectApi.WrappedValue wrapped = new ConnectApi.WrappedValue();
        wrapped.value = value;
        return wrapped;
    }
}
