/**
 * The admin assistant's Draft Matrix Rule action (M15): a valid draft with its
 * file, a refused one with its reasons only, and every other request answered
 * rather than thrown.
 *
 * Architecture section: 7 (its M15 note), 9, 10.
 *
 * What a draft must pass is AMF_RuleDrafterTest's subject; this pins the
 * action's contract with the agent. In-memory rules, a stub model.
 */
@IsTest
private class AMF_AgentDraftRuleTest {

    private class RunnerStub implements AMF_PromptRunner {
        private final List<String> answers;

        private RunnerStub(List<String> answers) {
            this.answers = answers;
        }

        public String run(String templateName, Map<String, String> inputs) {
            return answers.remove(0);
        }
    }

    private static void overStub(List<String> answers) {
        AMF_RuleBuilder.Stub rules = new AMF_RuleBuilder.Stub(
            new List<AMF_RuleDefinition>{
                new AMF_RuleBuilder().named('PR_Catch_All').withPriority(9999).withExpression('TRUE').routingTo('PR_Two_Level_Mgmt').build(),
                new AMF_RuleBuilder().named('OPP_Catch_All').forObject('Opportunity').withPriority(9999).withExpression('TRUE').routingTo('OPP_Manager_Approval').build()
            }
        );
        AMF_RuleDrafter.activeProcessesOverride = new Map<String, Set<String>>{
            'Purchase_Request__c' => new Set<String>{ 'PR_Two_Level_Mgmt', 'PR_Finance_Committee' }
        };
        AMF_AgentDraftRule.drafterOverride = new AMF_RuleDrafter(rules, new RunnerStub(answers));
        AMF_AgentDraftRule.ruleProviderOverride = rules;
    }

    private static String answer(String processApiName) {
        return JSON.serialize(
            new Map<String, Object>{
                'developerName' => 'PR_EMEA_Large',
                'label' => 'PR - EMEA Large',
                'priority' => 15,
                'expression' => 'Amount__c > 500000 && Region__c == \'EMEA\'',
                'processApiName' => processApiName,
                'description' => 'EMEA spend over 500,000 goes to the finance committee.',
                'assumptions' => 'Amounts are in the org currency.'
            }
        );
    }

    private static AMF_AgentDraftRule.Result draftOne(String objectName, String request, String ruleToChange) {
        AMF_AgentDraftRule.Request input = new AMF_AgentDraftRule.Request();
        input.objectName = objectName;
        input.ruleRequest = request;
        input.ruleToChange = ruleToChange;
        return AMF_AgentDraftRule.draftRules(new List<AMF_AgentDraftRule.Request>{ input })[0];
    }

    @IsTest
    static void returnsAValidDraftWithTheFileToCommit() {
        overStub(new List<String>{ answer('PR_Finance_Committee') });

        Test.startTest();
        AMF_AgentDraftRule.Result result = draftOne('purchase requests', 'EMEA spend over 500k to the committee', null);
        Test.stopTest();

        Assert.isTrue(result.valid, result.summary);
        Assert.areEqual('Purchase_Request__c', result.objectApiName);
        Assert.areEqual('PR_EMEA_Large', result.developerName);
        Assert.areEqual('15', result.priority, 'As text, for the agent to carry');
        Assert.areEqual(1, result.ruleVersion);
        Assert.areEqual('Add', result.changeType);
        Assert.areEqual('PR_Finance_Committee', result.processApiName);
        Assert.areEqual('Amounts are in the org currency.', result.assumptions);
        Assert.areEqual('force-app/main/default/customMetadata/Approval_Matrix_Rule.PR_EMEA_Large.md-meta.xml', result.filePath);
        Assert.isTrue(result.metadataXml.startsWith('<?xml version="1.0" encoding="UTF-8"?>'), result.metadataXml);
        Assert.isTrue(result.summary.contains('It routes nothing until you release it'), result.summary);
        Assert.areEqual(0, [SELECT COUNT() FROM Approval_Decision_Log__c], 'A draft records nothing');
    }

    @IsTest
    static void aRefusedDraftCarriesItsReasonsAndNoRule() {
        overStub(new List<String>{ answer('PR_Old_Process'), answer('PR_Old_Process') });

        AMF_AgentDraftRule.Result result = draftOne('Purchase_Request__c', 'EMEA spend over 500k', null);

        Assert.isFalse(result.valid);
        Assert.isTrue(result.summary.startsWith('No draft could be written that passes the checks.'), result.summary);
        Assert.isTrue(result.summary.contains('PR_Old_Process is not an active approval process'), result.summary);
        Assert.isNull(result.developerName, 'A refused draft shows no rule');
        Assert.isNull(result.metadataXml);
    }

    @IsTest
    static void answersEveryOtherRequestWithoutThrowing() {
        overStub(new List<String>());

        Assert.isTrue(draftOne('Contracts', 'Anything', null).summary.startsWith('"Contracts" is not a kind of record the approval matrix governs'));
        Assert.isTrue(draftOne(null, 'Anything', null).summary.startsWith('No object was named'));

        AMF_AgentDraftRule.Result unknownRule = draftOne('Purchase Request', 'Change it', 'PR_Nope');
        Assert.isFalse(unknownRule.valid);
        Assert.isTrue(unknownRule.summary.startsWith('No active rule named PR_Nope governs Purchase Requests'), unknownRule.summary);

        Assert.isTrue(AMF_AgentDraftRule.draftRules(null).isEmpty());
    }
}
