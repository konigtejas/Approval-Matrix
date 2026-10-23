/**
 * Runs a Flex prompt template through Einstein for the admin assistant (M15).
 *
 * Architecture section: 7 (its M15 note), 11 (security).
 *
 * The same call M13's AMF_EinsteinExplanationGenerator makes, for any template
 * and any text inputs: ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate,
 * a real generation rather than a preview, the first generation's text. The
 * templates ship in the agentforce package directory, because only an org with
 * Einstein generative AI can deploy one; this class names them and deploys
 * anywhere.
 *
 * The call runs as the user, so it needs the Prompt Template User permission
 * set, and Einstein's Trust Layer applies as to any prompt in the org. Nothing
 * it returns is stored.
 */
public with sharing class AMF_EinsteinPromptRunner implements AMF_PromptRunner {

    /** Identifies these generations in Einstein's audit and feedback data, as M13's call does. */
    private static final String APPLICATION_NAME = 'PromptTemplateGenerationsInvocable';

    /** How a Flex template names an input it declares. */
    @TestVisible
    private static final String INPUT_PREFIX = 'Input:';

    /**
     * @param templateName DeveloperName of a Flex prompt template.
     * @param inputs       Each input's API name to its text.
     * @return Einstein's text, trimmed.
     * @throws AMF_PromptException When Einstein is unavailable or returns nothing.
     */
    public String run(String templateName, Map<String, String> inputs) {
        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation output;

        try {
            output = ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate(templateName, inputFor(inputs));
        } catch (Exception e) {
            throw new AMF_PromptException(unavailable(templateName, e.getMessage()));
        }

        String text = textOf(output);
        if (String.isBlank(text)) {
            throw new AMF_PromptException('Einstein returned nothing for ' + templateName + '. Try again in a moment.');
        }
        return text.trim();
    }

    /** The template's inputs, for a real generation rather than a preview of the prompt. */
    @TestVisible
    private static ConnectApi.EinsteinPromptTemplateGenerationsInput inputFor(Map<String, String> inputs) {
        ConnectApi.EinsteinPromptTemplateGenerationsInput input = new ConnectApi.EinsteinPromptTemplateGenerationsInput();
        input.isPreview = false;
        input.inputParams = new Map<String, ConnectApi.WrappedValue>();

        if (inputs != null) {
            for (String name : inputs.keySet()) {
                ConnectApi.WrappedValue wrapped = new ConnectApi.WrappedValue();
                wrapped.value = inputs.get(name);
                input.inputParams.put(INPUT_PREFIX + name, wrapped);
            }
        }

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

    /** The platform's refusal, with what an administrator can check. */
    @TestVisible
    private static String unavailable(String templateName, String reason) {
        return 'Einstein is not available for this right now. Einstein said: ' +
            (String.isBlank(reason) ? 'no reason given.' : reason) +
            ' Nothing was changed. An administrator can check that you have the Prompt Template User ' +
            'permission set and that ' +
            templateName +
            ' is deployed with an active version.';
    }
}
