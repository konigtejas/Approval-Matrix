/**
 * The Einstein call behind every explanation (M13): what it sends, what it
 * reads back, and what it tells the reader when Einstein says no.
 *
 * Architecture section: 8 (its M13 note), 10.
 *
 * A generation is not deterministic, and whether one runs in an Apex test
 * depends on the org, so no test here asserts what Einstein writes. The live
 * call is checked once in the org, as part of M13's gate. What is pinned here
 * is everything around it: the template's two inputs, the first generation's
 * text, and a refusal that keeps the platform's reason.
 */
@IsTest
private class AMF_EinsteinExplanationGeneratorTest {

    @IsTest
    static void sendsTheFactsAndTheQuestionAsTheTemplatesTwoInputsForARealGeneration() {
        ConnectApi.EinsteinPromptTemplateGenerationsInput input = AMF_EinsteinExplanationGenerator.inputFor(
            'Record: Purchase Request PR-00000001',
            'Why?'
        );

        Assert.isFalse(input.isPreview, 'A preview resolves the prompt and generates nothing');
        Assert.areEqual(2, input.inputParams.size());
        Assert.areEqual(
            'Record: Purchase Request PR-00000001',
            input.inputParams.get(AMF_EinsteinExplanationGenerator.FACTS_INPUT).value
        );
        Assert.areEqual('Why?', input.inputParams.get(AMF_EinsteinExplanationGenerator.QUESTION_INPUT).value);
        Assert.areEqual('Input:Facts', AMF_EinsteinExplanationGenerator.FACTS_INPUT, 'The name the template declares');
        Assert.areEqual('Input:Question', AMF_EinsteinExplanationGenerator.QUESTION_INPUT, 'The name the template declares');
        Assert.isNotNull(input.additionalConfig.applicationName);
    }

    @IsTest
    static void readsTheFirstGenerationAndTreatsNoneAsNothing() {
        Assert.isNull(AMF_EinsteinExplanationGenerator.textOf(null));

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation output = new ConnectApi.EinsteinPromptTemplateGenerationsRepresentation();
        Assert.isNull(AMF_EinsteinExplanationGenerator.textOf(output), 'No generations list');

        output.generations = new List<ConnectApi.EinsteinLLMGenerationItemOutput>();
        Assert.isNull(AMF_EinsteinExplanationGenerator.textOf(output), 'An empty generations list');

        ConnectApi.EinsteinLLMGenerationItemOutput first = new ConnectApi.EinsteinLLMGenerationItemOutput();
        first.text = 'It went to the finance chain.';
        ConnectApi.EinsteinLLMGenerationItemOutput second = new ConnectApi.EinsteinLLMGenerationItemOutput();
        second.text = 'An alternative nobody asked for.';
        output.generations.add(first);
        output.generations.add(second);
        Assert.areEqual('It went to the finance chain.', AMF_EinsteinExplanationGenerator.textOf(output));
    }

    @IsTest
    static void aRefusalKeepsThePlatformsReasonAndSaysWhatAnAdministratorCanCheck() {
        String message = AMF_EinsteinExplanationGenerator.unavailable('You do not have permission to run prompt templates.');

        Assert.isTrue(message.startsWith('Plain-English explanations are not available right now.'), message);
        Assert.isTrue(message.contains('Einstein said: You do not have permission to run prompt templates.'), message);
        Assert.isTrue(message.contains('Prompt Template User'), message);
        Assert.isTrue(message.contains(AMF_EinsteinExplanationGenerator.TEMPLATE_NAME), message);
        Assert.isTrue(message.contains('The recorded decision itself is unaffected'), message);

        Assert.isTrue(AMF_EinsteinExplanationGenerator.unavailable(null).contains('Einstein said: no reason given.'));
    }

    @IsTest
    static void aGenerationEitherExplainsOrSaysWhyItCannot() {
        // Whether Einstein runs inside an Apex test depends on the org. Either
        // answer is acceptable here; an unexplained exception is not.
        try {
            String text = new AMF_EinsteinExplanationGenerator().generate('Record: Purchase Request PR-00000001', 'Why?');
            Assert.isFalse(String.isBlank(text), 'A generation that succeeds returns text');
        } catch (AMF_ExplanationException e) {
            Assert.isTrue(
                e.getMessage().startsWith('Plain-English explanations are not available right now.') ||
                e.getMessage().startsWith('Einstein returned no explanation'),
                e.getMessage()
            );
        }
    }
}
