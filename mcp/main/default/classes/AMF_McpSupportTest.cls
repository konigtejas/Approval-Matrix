/**
 * The Claude connector's shared helpers (M16): the signed preview token, and a
 * record read the way a person names it.
 *
 * Architecture section: 7 (its M16 note), 11, 10.
 *
 * The token is the server's half of "preview, confirm, submit" through an MCP
 * client, so every way it can be wrong is pinned here: another record, another
 * process, another user, too old, altered, malformed, or an org with no key.
 * Records are found through Find Governed Record's ruleProviderOverride seam,
 * over in-memory rules, as CLAUDE.md requires of every test.
 */
@IsTest
private class AMF_McpSupportTest {

    private static final String TWO_LEVEL = 'PR_Two_Level_Mgmt';
    private static final String THREE_LEVEL = 'PR_Three_Level_Finance';

    private static void withKey() {
        insert new AMF_Mcp_Settings__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Preview_Key__c = EncodingUtil.base64Encode(Crypto.generateAesKey(256))
        );
    }

    private static void governing(List<String> objectApiNames) {
        List<AMF_RuleDefinition> rules = new List<AMF_RuleDefinition>();
        Integer priority = 10;
        for (String objectApiName : objectApiNames) {
            rules.add(new AMF_RuleBuilder().named('Rule_' + priority).forObject(objectApiName).withPriority(priority++).build());
        }
        AMF_AgentFindRecord.ruleProviderOverride = new AMF_RuleBuilder.Stub(rules);
    }

    private static Purchase_Request__c insertRequest() {
        Purchase_Request__c record = new Purchase_Request__c(Amount__c = 5000, Region__c = 'EMEA', Risk_Level__c = 'Low');
        insert record;
        return record;
    }

    private static User anotherUser() {
        User other = new User(
            Alias = 'amfmcp',
            Email = 'amf.mcp@example.invalid',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Connector',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey = 'GMT',
            Username = 'amf.mcp.' + String.valueOf(Datetime.now().getTime()) + '@amf.test.invalid'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert other;
        }
        return other;
    }

    @IsTest
    static void aTokenIsAcceptedForItsOwnRecordAndProcessOnly() {
        withKey();
        Purchase_Request__c previewed = insertRequest();
        Purchase_Request__c another = insertRequest();

        String token = AMF_McpSupport.tokenFor(previewed.Id, TWO_LEVEL);

        Assert.isNotNull(token);
        Assert.isNull(AMF_McpSupport.tokenProblem(token, previewed.Id, TWO_LEVEL));
        Assert.isNull(AMF_McpSupport.tokenProblem('  ' + token + ' ', previewed.Id, ' ' + TWO_LEVEL + ' '), 'Spaces around either are not a difference');
        Assert.isNull(
            AMF_McpSupport.tokenProblem(token, Id.valueOf(String.valueOf(previewed.Id).left(15)), TWO_LEVEL),
            'A 15-character Id is the same record'
        );
        Assert.areEqual(AMF_McpSupport.NOT_PREVIEWED, AMF_McpSupport.tokenProblem(token, another.Id, TWO_LEVEL), 'Another record');
        Assert.areEqual(AMF_McpSupport.NOT_PREVIEWED, AMF_McpSupport.tokenProblem(token, previewed.Id, THREE_LEVEL), 'Another process');
        Assert.areEqual(AMF_McpSupport.NOT_PREVIEWED, AMF_McpSupport.tokenProblem(token, previewed.Id, ''), 'A block is not this route');
        Assert.areEqual(AMF_McpSupport.NOT_PREVIEWED, AMF_McpSupport.tokenProblem(token, null, TWO_LEVEL), 'No record');
    }

    @IsTest
    static void aTokenIsBoundToTheRuleAndTheValuesItShowed() {
        withKey();
        Purchase_Request__c record = insertRequest();
        AMF_McpSupport.ShownDecision shown = new AMF_McpSupport.ShownDecision();
        shown.processName = TWO_LEVEL;
        shown.ruleName = 'PR_Low';
        shown.ruleVersion = 3;
        shown.valuesJson = '{"Amount__c":10000}';

        String token = AMF_McpSupport.tokenFor(record.Id, shown);
        AMF_McpSupport.TokenCheck check = AMF_McpSupport.checkToken(token, record.Id);

        Assert.isNull(check.problem);
        Assert.isTrue(AMF_McpSupport.sameDecision(check.shown, ' ' + TWO_LEVEL + ' ', 'PR_Low', 3, '{"Amount__c":10000}'), 'The signed decision, spaces aside');
        Assert.isFalse(AMF_McpSupport.sameDecision(check.shown, TWO_LEVEL, 'PR_Low', 3, '{"Amount__c":500000}'), 'The same process over different values is a different decision');
        Assert.isFalse(AMF_McpSupport.sameDecision(check.shown, TWO_LEVEL, 'PR_High', 3, '{"Amount__c":10000}'));
        Assert.isFalse(AMF_McpSupport.sameDecision(check.shown, THREE_LEVEL, 'PR_Low', 3, '{"Amount__c":10000}'));
        Assert.areEqual(AMF_McpSupport.NOT_PREVIEWED, AMF_McpSupport.tokenProblem(token, record.Id, THREE_LEVEL));
    }

    @IsTest
    static void aBlockIsPreviewedAndSubmittedWithNoProcess() {
        withKey();
        Purchase_Request__c record = insertRequest();

        String token = AMF_McpSupport.tokenFor(record.Id, (String) null);

        Assert.isNull(AMF_McpSupport.tokenProblem(token, record.Id, ''));
        Assert.isNull(AMF_McpSupport.tokenProblem(token, record.Id, null));
        Assert.areEqual(AMF_McpSupport.NOT_PREVIEWED, AMF_McpSupport.tokenProblem(token, record.Id, TWO_LEVEL));
    }

    @IsTest
    static void anotherUsersPreviewDoesNotLetThemSubmit() {
        withKey();
        Purchase_Request__c record = insertRequest();
        String mine = AMF_McpSupport.tokenFor(record.Id, TWO_LEVEL);

        String problem;
        System.runAs(anotherUser()) {
            problem = AMF_McpSupport.tokenProblem(mine, record.Id, TWO_LEVEL);
        }

        Assert.areEqual(AMF_McpSupport.NOT_PREVIEWED, problem, 'The signature names the user it was issued to');
    }

    @IsTest
    static void anAlteredOrMalformedTokenIsRefused() {
        withKey();
        Purchase_Request__c record = insertRequest();
        String token = AMF_McpSupport.tokenFor(record.Id, TWO_LEVEL);
        List<String> parts = token.split('\\.');
        String lastHexDigit = parts[1].right(1) == '0' ? '1' : '0';

        List<String> refused = new List<String>{
            null,
            '',
            'not a token',
            parts[1],
            parts[0] + '.',
            parts[0] +
            '.' +
            parts[1].left(parts[1].length() - 1) +
            lastHexDigit,
            EncodingUtil.base64Encode(Blob.valueOf('["1","","","",""]')).replace('\r', '').replace('\n', '') +
            '.' +
            parts[1],
            '1234567890123456789012.' + parts[1],
            parts[0] + '.' + parts[1] + '.extra'
        };
        for (String attempt : refused) {
            Assert.areEqual(
                AMF_McpSupport.NOT_PREVIEWED,
                AMF_McpSupport.tokenProblem(attempt, record.Id, TWO_LEVEL),
                'Refused: ' + attempt
            );
        }
    }

    @IsTest
    static void aTokenLastsFifteenMinutes() {
        withKey();
        Purchase_Request__c record = insertRequest();
        Datetime issued = Datetime.newInstanceGmt(2026, 10, 24, 9, 0, 0);

        AMF_McpSupport.nowOverride = issued;
        String token = AMF_McpSupport.tokenFor(record.Id, TWO_LEVEL);

        AMF_McpSupport.nowOverride = issued.addMinutes(AMF_McpSupport.TOKEN_MINUTES).addSeconds(-1);
        Assert.isNull(AMF_McpSupport.tokenProblem(token, record.Id, TWO_LEVEL), 'Still within the window');

        AMF_McpSupport.nowOverride = issued.addMinutes(AMF_McpSupport.TOKEN_MINUTES).addSeconds(1);
        Assert.areEqual(AMF_McpSupport.EXPIRED, AMF_McpSupport.tokenProblem(token, record.Id, TWO_LEVEL));

        AMF_McpSupport.nowOverride = issued.addSeconds(-30);
        Assert.isNull(AMF_McpSupport.tokenProblem(token, record.Id, TWO_LEVEL), 'A clock a little behind is not a forgery');

        AMF_McpSupport.nowOverride = issued.addMinutes(-5);
        Assert.areEqual(AMF_McpSupport.EXPIRED, AMF_McpSupport.tokenProblem(token, record.Id, TWO_LEVEL), 'Issued in the future');
    }

    @IsTest
    static void anOrgWithNoKeyPreviewsWithoutATokenAndSaysHowToFinishSettingUp() {
        Purchase_Request__c record = insertRequest();

        Assert.isNull(AMF_McpSupport.tokenFor(record.Id, TWO_LEVEL));
        Assert.areEqual(AMF_McpSupport.NOT_SET_UP, AMF_McpSupport.tokenProblem('1.ab', record.Id, TWO_LEVEL));

        insert new AMF_Mcp_Settings__c(SetupOwnerId = UserInfo.getOrganizationId(), Preview_Key__c = '   ');
        Assert.isNull(AMF_McpSupport.tokenFor(record.Id, TWO_LEVEL), 'A blank key is no key');
    }

    @IsTest
    static void aKeyChangeInvalidatesEveryPreviewNotYetSubmitted() {
        withKey();
        Purchase_Request__c record = insertRequest();
        String token = AMF_McpSupport.tokenFor(record.Id, TWO_LEVEL);

        AMF_Mcp_Settings__c settings = AMF_Mcp_Settings__c.getOrgDefaults();
        settings.Preview_Key__c = EncodingUtil.base64Encode(Crypto.generateAesKey(256));
        update settings;

        Assert.areEqual(AMF_McpSupport.NOT_PREVIEWED, AMF_McpSupport.tokenProblem(token, record.Id, TWO_LEVEL));
    }

    @IsTest
    static void resolvesARecordByItsNumberOrIdAndSaysWhenNoneMatches() {
        governing(new List<String>{ 'Purchase_Request__c' });
        Purchase_Request__c record = insertRequest();
        String prNumber = [SELECT Name FROM Purchase_Request__c WHERE Id = :record.Id].Name;

        AMF_McpSupport.Resolution byNumber = AMF_McpSupport.resolve(prNumber);
        AMF_McpSupport.Resolution byId = AMF_McpSupport.resolve(String.valueOf(record.Id).left(15));
        AMF_McpSupport.Resolution nothing = AMF_McpSupport.resolve('PR-99999999');
        AMF_McpSupport.Resolution blank = AMF_McpSupport.resolve('  ');

        Assert.areEqual(AMF_McpSupport.FOUND, byNumber.outcome);
        Assert.areEqual(record.Id, byNumber.recordId);
        Assert.areEqual(AMF_McpSupport.FOUND, byId.outcome);
        Assert.areEqual(record.Id, byId.recordId);
        Assert.areEqual(AMF_McpSupport.NOT_FOUND, nothing.outcome);
        Assert.isNull(nothing.recordId);
        Assert.isTrue(nothing.message.contains('PR-99999999'), '' + nothing.message);
        Assert.areEqual(AMF_McpSupport.NOT_FOUND, blank.outcome);
        Assert.isNotNull(blank.message);
    }

    @IsTest
    static void severalMatchesAreListedForTheUserNeverGuessedBetween() {
        governing(new List<String>{ 'Purchase_Request__c', 'Opportunity' });
        insert new List<Opportunity>{
            new Opportunity(Name = 'Acme Laptop Refresh', StageName = 'Prospecting', CloseDate = Date.today().addDays(30)),
            new Opportunity(Name = 'Acme Server Upgrade', StageName = 'Prospecting', CloseDate = Date.today().addDays(30))
        };

        AMF_McpSupport.Resolution resolution = AMF_McpSupport.resolve('Acme');

        Assert.areEqual(AMF_McpSupport.AMBIGUOUS, resolution.outcome);
        Assert.isNull(resolution.recordId);
        Assert.isTrue(resolution.matches.contains('Acme Laptop Refresh'), '' + resolution.matches);
        Assert.isTrue(resolution.matches.contains('Acme Server Upgrade'), '' + resolution.matches);
        Assert.isNotNull(resolution.message);
    }

    @IsTest
    static void aRecordsLinkOpensItInThisOrg() {
        Purchase_Request__c record = insertRequest();

        String link = AMF_McpSupport.recordUrlOf(record.Id);

        Assert.areEqual(URL.getOrgDomainUrl().toExternalForm() + '/' + record.Id, link);
        Assert.isNull(AMF_McpSupport.recordUrlOf(null));
    }
}
