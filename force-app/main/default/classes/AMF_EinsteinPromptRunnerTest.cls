/**
 * The Einstein call behind the admin assistant's drafts and summaries (M15):
 * what it sends, what it reads back, and what it says when Einstein says no.
 *
 * Architecture section: 7 (its M15 note), 10.
 *
 * As for M13's AMF_EinsteinExplanationGeneratorTest: a generation is not
 * deterministic, and whether one runs in an Apex test depends on the org, so
 * no test here asserts what Einstein writes. The live calls are checked once
 * in the org, in M15's gate.
 */
@IsTest
private class AMF_EinsteinPromptRunnerTest {

    @IsTest
    static void sendsEachInputUnderTheNameTheTemplateDeclaresForARealGeneration() {
        ConnectApi.EinsteinPromptTemplateGenerationsInput input = AMF_EinsteinPromptRunner.inputFor(
            new Map<String, String>{ 'Request' => 'EMEA spend over 500k', 'Context' => 'Object: Purchase Request' }
        );

        Assert.isFalse(input.isPreview, 'A preview resolves the prompt and generates nothing');
        Assert.areEqual(2, input.inputParams.size());
        Assert.areEqual('EMEA spend over 500k', input.inputParams.get('Input:Request').value);
        Assert.areEqual('Object: Purchase Request', input.inputParams.get('Input:Context').value);
        Assert.isNotNull(input.additionalConfig.applicationName);

        Assert.isTrue(AMF_EinsteinPromptRunner.inputFor(null).inputParams.isEmpty());
    }

    @IsTest
    static void readsTheFirstGenerationAndTreatsNoneAsNothing() {
        Assert.isNull(AMF_EinsteinPromptRunner.textOf(null));

        ConnectApi.EinsteinPromptTemplateGenerationsRepresentation output = new ConnectApi.EinsteinPromptTemplateGenerationsRepresentation();
        Assert.isNull(AMF_EinsteinPromptRunner.textOf(output));

        output.generations = new List<ConnectApi.EinsteinLLMGenerationItemOutput>();
        Assert.isNull(AMF_EinsteinPromptRunner.textOf(output));

        ConnectApi.EinsteinLLMGenerationItemOutput first = new ConnectApi.EinsteinLLMGenerationItemOutput();
        first.text = '{"developerName": "PR_EMEA_Large"}';
        output.generations.add(first);
        Assert.areEqual('{"developerName": "PR_EMEA_Large"}', AMF_EinsteinPromptRunner.textOf(output));
    }

    @IsTest
    static void aRefusalKeepsThePlatformsReasonAndSaysNothingChanged() {
        String message = AMF_EinsteinPromptRunner.unavailable('AMF_Draft_Matrix_Rule', 'No active template version');

        Assert.isTrue(message.startsWith('Einstein is not available for this right now.'), message);
        Assert.isTrue(message.contains('Einstein said: No active template version'), message);
        Assert.isTrue(message.contains('Nothing was changed.'), message);
        Assert.isTrue(message.contains('Prompt Template User'), message);
        Assert.isTrue(message.contains('AMF_Draft_Matrix_Rule is deployed with an active version'), message);
        Assert.isTrue(AMF_EinsteinPromptRunner.unavailable('X', null).contains('Einstein said: no reason given.'));
    }

    @IsTest
    static void aGenerationEitherAnswersOrSaysWhyItCannot() {
        try {
            String text = new AMF_EinsteinPromptRunner().run(
                'AMF_Summarize_Matrix_Health',
                new Map<String, String>{ 'Facts' => 'Decisions recorded: 0.', 'Question' => 'How is it doing?' }
            );
            Assert.isFalse(String.isBlank(text), 'A generation that succeeds returns text');
        } catch (AMF_PromptException e) {
            Assert.isTrue(
                e.getMessage().startsWith('Einstein is not available for this right now.') ||
                e.getMessage().startsWith('Einstein returned nothing'),
                e.getMessage()
            );
        }
    }
}
