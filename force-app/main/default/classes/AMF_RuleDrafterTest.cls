/**
 * The rule drafter's unit suite (M15): what the model is given, the checks a
 * draft must pass before anyone sees it, the one corrected attempt, and the
 * Custom Metadata file a valid draft becomes.
 *
 * Architecture section: 1 (principle 6), 3.1, 4.1, 9, 10.
 *
 * The model is a stub that hands back prepared answers and records what it was
 * asked. The matrix is in memory (CLAUDE.md) and so are the active approval
 * processes, because a ProcessDefinition cannot be created in a test. Nothing
 * here writes a rule.
 */
@IsTest
private class AMF_RuleDrafterTest {

    private static final String COMMITTEE = 'PR_Finance_Committee';
    private static final String THREE_LEVEL = 'PR_Three_Level_Finance';
    private static final String TWO_LEVEL = 'PR_Two_Level_Mgmt';
    private static final String QUEUE = 'PR_Credit_Risk_Queue';

    /** The model, replaced by prepared answers, in order. */
    private class RunnerStub implements AMF_PromptRunner {
        private final List<String> answers;
        public List<Map<String, String>> asked = new List<Map<String, String>>();
        public String template;

        private RunnerStub(List<String> answers) {
            this.answers = answers;
        }

        public String run(String templateName, Map<String, String> inputs) {
            template = templateName;
            asked.add(inputs);
            return answers.remove(0);
        }
    }

    private static List<AMF_RuleDefinition> matrix() {
        return new List<AMF_RuleDefinition>{
            new AMF_RuleBuilder().named('PR_Committee_Spend').withPriority(5).withExpression('Amount__c >= 1000000').routingTo(COMMITTEE).build(),
            new AMF_RuleBuilder()
                .named('PR_High_Value_APAC')
                .withPriority(10)
                .withExpression('Amount__c > 100000 && Region__c == \'APAC\'')
                .routingTo(THREE_LEVEL)
                .describedAs('High-value APAC spend')
                .atVersion(3)
                .build(),
            new AMF_RuleBuilder().named('PR_High_Risk').withPriority(20).withExpression('Risk_Level__c == \'High\'').routingTo(THREE_LEVEL).build(),
            new AMF_RuleBuilder().named('PR_Catch_All').withPriority(9999).withExpression('TRUE').routingTo(TWO_LEVEL).build(),
            new AMF_RuleBuilder().named('OPP_Catch_All').forObject('Opportunity').withPriority(9999).withExpression('TRUE').routingTo('OPP_Manager_Approval').build()
        };
    }

    private static AMF_RuleDrafter drafter(RunnerStub runner) {
        AMF_RuleDrafter.activeProcessesOverride = new Map<String, Set<String>>{
            'Purchase_Request__c' => new Set<String>{ COMMITTEE, THREE_LEVEL, TWO_LEVEL, QUEUE }
        };
        return new AMF_RuleDrafter(new AMF_RuleBuilder.Stub(matrix()), runner);
    }

    /** A draft the checks accept. */
    private static Map<String, Object> emeaLarge() {
        return new Map<String, Object>{
            'developerName' => 'PR_EMEA_Large',
            'label' => 'PR - EMEA Large',
            'priority' => 15,
            'expression' => 'Amount__c > 500000 && Region__c == \'EMEA\'',
            'processApiName' => COMMITTEE,
            'description' => 'EMEA spend over 500,000 goes to the finance committee.',
            'assumptions' => 'Amounts are in the org currency.'
        };
    }

    private static Map<String, Object> with(Map<String, Object> answer, String key, Object value) {
        Map<String, Object> changed = answer.clone();
        changed.put(key, value);
        return changed;
    }

    private static void assertContains(String text, String expected) {
        Assert.isTrue(text != null && text.contains(expected), 'Expected "' + expected + '" in:\n' + text);
    }

    @IsTest
    static void draftsANewRuleThatPassesEveryCheckFromAChattyFencedAnswer() {
        RunnerStub runner = new RunnerStub(
            new List<String>{ 'Here is the rule:\n```json\n' + JSON.serialize(emeaLarge()) + '\n```\nAnything else?' }
        );

        Test.startTest();
        AMF_RuleDrafter.Draft draft = drafter(runner).draft('Purchase_Request__c', '  EMEA spend over 500k to the committee  ', null);
        Test.stopTest();

        Assert.isTrue(draft.valid, String.join(draft.problems, ' | '));
        Assert.areEqual('Add', draft.mode);
        Assert.areEqual(1, draft.version);
        Assert.areEqual('PR_EMEA_Large', draft.developerName);
        Assert.areEqual(15, draft.priority);
        Assert.areEqual(COMMITTEE, draft.processApiName);
        Assert.areEqual('Amounts are in the org currency.', draft.assumptions);
        Assert.areEqual('force-app/main/default/customMetadata/Approval_Matrix_Rule.PR_EMEA_Large.md-meta.xml', draft.filePath);

        assertContains(
            draft.summary,
            'Draft rule PR_EMEA_Large (new, version 1) for Purchase Requests: when Amount__c > 500000 && Region__c == \'EMEA\', ' +
            'send the record to approval process PR_Finance_Committee. Priority 15: it would be tried after ' +
            'PR_High_Value_APAC (10) and before PR_High_Risk (20).'
        );
        assertContains(draft.summary, 'It routes nothing until you release it');

        // The file, in the form the repository's rules take.
        assertContains(draft.metadataXml, '<label>PR - EMEA Large</label>');
        assertContains(draft.metadataXml, '<value xsi:type="xsd:string">Purchase_Request__c</value>');
        assertContains(draft.metadataXml, '<value xsi:type="xsd:double">15.0</value>');
        assertContains(draft.metadataXml, '<value xsi:type="xsd:string">Amount__c &gt; 500000 &amp;&amp; Region__c == \'EMEA\'</value>');
        assertContains(draft.metadataXml, '<value xsi:type="xsd:double">1.0</value>');
        assertContains(draft.metadataXml, '<value xsi:type="xsd:boolean">true</value>');

        // What the model was given.
        Assert.areEqual(1, runner.asked.size(), 'A valid first draft needs no second');
        Assert.areEqual('AMF_Draft_Matrix_Rule', runner.template);
        Assert.areEqual('EMEA spend over 500k to the committee', runner.asked[0].get('Request'));
        String context = runner.asked[0].get('Context');
        assertContains(context, 'Object: Purchase Request (API name Purchase_Request__c)');
        assertContains(context, '- Amount__c: Amount (currency)');
        assertContains(context, '- Region__c: Region (picklist: APAC, EMEA, AMER)');
        assertContains(context, '- Account__c: Account (lookup to Account; read its fields through Account__r, such as Account__r.Name)');
        assertContains(context, '- PR_High_Value_APAC: priority 10, version 3, condition Amount__c > 100000 && Region__c == \'APAC\', process PR_Three_Level_Finance. High-value APAC spend');
        assertContains(context, 'Active approval processes for this object: PR_Credit_Risk_Queue, PR_Finance_Committee, PR_Three_Level_Finance, PR_Two_Level_Mgmt');
        assertContains(context, 'Names active rules already use, on every object: OPP_Catch_All, PR_Catch_All, PR_Committee_Spend, PR_High_Risk, PR_High_Value_APAC');
        assertContains(context, 'This is a new rule: give it a new developerName.');
    }

    @IsTest
    static void correctsADraftOnceWithTheCompilersReason() {
        RunnerStub runner = new RunnerStub(
            new List<String>{
                JSON.serialize(with(emeaLarge(), 'expression', 'Amount__c > 500000 && Regio__c == \'EMEA\'')),
                JSON.serialize(emeaLarge())
            }
        );

        AMF_RuleDrafter.Draft draft = drafter(runner).draft('Purchase_Request__c', 'EMEA spend over 500k to the committee', null);

        Assert.isTrue(draft.valid, String.join(draft.problems, ' | '));
        Assert.areEqual(2, runner.asked.size(), 'One corrected attempt');
        String second = runner.asked[1].get('Request');
        Assert.isTrue(second.startsWith('EMEA spend over 500k to the committee\n\nYour previous draft was refused'), second);
        assertContains(second, 'The condition does not compile: ');
        assertContains(second, 'Regio__c');
    }

    @IsTest
    static void showsNoRuleWhenTheCorrectedDraftFailsToo() {
        String failing = JSON.serialize(with(with(emeaLarge(), 'priority', 20), 'processApiName', 'PR_Old_Process'));
        RunnerStub runner = new RunnerStub(new List<String>{ failing, failing });

        AMF_RuleDrafter.Draft draft = drafter(runner).draft('Purchase_Request__c', 'EMEA spend over 500k', null);

        Assert.isFalse(draft.valid);
        Assert.areEqual(2, runner.asked.size(), 'Two attempts and no third');
        Assert.isNull(draft.metadataXml, 'An invalid draft is never shown');
        Assert.isNull(draft.version);
        assertContains(draft.summary, 'No draft could be written that passes the checks.');
        assertContains(draft.summary, 'Priority 20 is already used by rule PR_High_Risk.');
        assertContains(
            draft.summary,
            'PR_Old_Process is not an active approval process for Purchase_Request__c. The active ones are: ' +
            'PR_Credit_Risk_Queue, PR_Finance_Committee, PR_Three_Level_Finance, PR_Two_Level_Mgmt.'
        );
        Assert.isTrue(draft.summary.endsWith('Nothing was changed.'), draft.summary);
    }

    @IsTest
    static void writesANewVersionOfTheRuleItIsAskedToChange() {
        Map<String, Object> answer = with(
            with(emeaLarge(), 'developerName', 'PR_High_Value_APAC'),
            'expression',
            'Amount__c > 150000 && Region__c == \'APAC\''
        );
        answer.put('priority', 10);
        answer.put('processApiName', THREE_LEVEL);
        RunnerStub runner = new RunnerStub(new List<String>{ JSON.serialize(answer) });

        AMF_RuleDrafter.Draft draft = drafter(runner).draft('Purchase_Request__c', 'Raise the APAC threshold to 150k', 'PR_High_Value_APAC');

        Assert.isTrue(draft.valid, String.join(draft.problems, ' | '));
        Assert.areEqual('Replace', draft.mode);
        Assert.areEqual(4, draft.version, 'One more than the live version 3');
        assertContains(draft.summary, 'Draft version 4 of rule PR_High_Value_APAC for Purchase Requests');
        assertContains(draft.summary, 'it would be tried after PR_Committee_Spend (5) and before PR_High_Risk (20).');
        assertContains(draft.metadataXml, '<value xsi:type="xsd:double">4.0</value>');
        assertContains(runner.asked[0].get('Context'), 'The rule to change: PR_High_Value_APAC. Keep its developerName; it gets a new version.');
    }

    @IsTest
    static void checksEveryFieldOfADraftBeforeAnyoneSeesIt() {
        AMF_RuleDrafter subject = drafter(new RunnerStub(new List<String>()));
        Schema.SObjectType request = Purchase_Request__c.SObjectType;
        List<AMF_RuleDefinition> live = new AMF_RuleBuilder.Stub(matrix()).getActiveRules('Purchase_Request__c');
        Set<String> processes = new Set<String>{ COMMITTEE, THREE_LEVEL, TWO_LEVEL, QUEUE };
        AMF_RuleDefinition highRisk = live[2];

        Map<String, String> refusals = new Map<String, String>{
            'name with a space' => 'is not a valid name',
            'double underscore' => 'is not a valid name',
            'trailing underscore' => 'is not a valid name',
            'taken name' => 'PR_High_Risk is already the name of an active rule',
            'no description' => 'has no description',
            'long description' => 'longer than 255 characters',
            'priority zero' => 'whole number from 1 to 9999',
            'priority too high' => 'whole number from 1 to 9999',
            'priority not whole' => 'whole number from 1 to 9999',
            'priority not a number' => 'whole number from 1 to 9999',
            'no condition' => 'has no condition',
            'no process' => 'names no approval process'
        };
        Map<String, Map<String, Object>> answers = new Map<String, Map<String, Object>>{
            'name with a space' => with(emeaLarge(), 'developerName', 'PR EMEA'),
            'double underscore' => with(emeaLarge(), 'developerName', 'PR__EMEA'),
            'trailing underscore' => with(emeaLarge(), 'developerName', 'PR_EMEA_'),
            'taken name' => with(emeaLarge(), 'developerName', 'PR_High_Risk'),
            'no description' => with(emeaLarge(), 'description', ' '),
            'long description' => with(emeaLarge(), 'description', 'x'.repeat(256)),
            'priority zero' => with(emeaLarge(), 'priority', 0),
            'priority too high' => with(emeaLarge(), 'priority', 10000),
            'priority not whole' => with(emeaLarge(), 'priority', 12.5),
            'priority not a number' => with(emeaLarge(), 'priority', 'high'),
            'no condition' => with(emeaLarge(), 'expression', ''),
            'no process' => with(emeaLarge(), 'processApiName', null)
        };

        for (String scenario : refusals.keySet()) {
            AMF_RuleDrafter.Draft draft = subject.checked(request, answers.get(scenario), live, processes, null);
            Assert.isFalse(draft.valid, scenario);
            Assert.isTrue(
                String.join(draft.problems, ' | ').contains(refusals.get(scenario)),
                scenario + ': ' + String.join(draft.problems, ' | ')
            );
        }

        AMF_RuleDrafter.Draft renamed = subject.checked(request, with(emeaLarge(), 'developerName', 'PR_High_Risk_2'), live, processes, highRisk);
        assertContains(String.join(renamed.problems, ' | '), 'A new version of PR_High_Risk must keep the name PR_High_Risk.');

        AMF_RuleDrafter.Draft notJson = subject.checked(request, null, live, processes, null);
        Assert.areEqual(new List<String>{ 'The answer was not a rule draft in JSON.' }, notJson.problems);

        AMF_RuleDrafter.Draft priorityAsText = subject.checked(request, with(emeaLarge(), 'priority', ' 15 '), live, processes, null);
        Assert.isTrue(priorityAsText.valid, 'A priority written as text is still a priority: ' + String.join(priorityAsText.problems, ' | '));
    }

    @IsTest
    static void refusesWhatItCannotDraftForWithoutAskingTheModel() {
        RunnerStub runner = new RunnerStub(new List<String>());
        AMF_RuleDrafter subject = drafter(runner);

        Map<List<String>, String> refusals = new Map<List<String>, String>{
            new List<String>{ 'Purchase_Request__c', ' ', null } => 'Describe the rule you want',
            new List<String>{ 'Account', 'Big accounts to the board', null } => 'Account is not governed by the approval matrix',
            new List<String>{ 'Purchase_Request__c', 'Change it', 'PR_Nope' } => 'No active rule named PR_Nope governs Purchase Requests'
        };

        for (List<String> call : refusals.keySet()) {
            try {
                subject.draft(call[0], call[1], call[2]);
                Assert.fail('Expected a refusal for ' + call);
            } catch (AMF_PromptException e) {
                assertContains(e.getMessage(), refusals.get(call));
            }
        }
        Assert.isTrue(runner.asked.isEmpty(), 'Nothing is asked of the model');
    }

    @IsTest
    static void findsTheJsonObjectInAnAnswerAndNothingElse() {
        Assert.isNull(AMF_RuleDrafter.parse(null));
        Assert.isNull(AMF_RuleDrafter.parse('No JSON here.'));
        Assert.isNull(AMF_RuleDrafter.parse('[1, 2]'), 'A list is not a draft');
        Assert.isNull(AMF_RuleDrafter.parse('{"developerName": "PR_X",'), 'Broken JSON');
        Assert.areEqual('PR_X', AMF_RuleDrafter.parse('Sure! {"developerName": "PR_X"} Done.').get('developerName'));
    }
}
