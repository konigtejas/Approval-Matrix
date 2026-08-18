/**
 * Unit test for AMF_FieldPathResolver: the union of paths across an object's
 * rules, and the single dynamic query 4.4 builds from it.
 *
 * Architecture section: 4.4 (field path resolution), 6.1 step 4.
 *
 * The query STRING is asserted directly rather than inferred from results,
 * because "one query per object per transaction" is a claim about the query and
 * not about what comes back from it. The load path is then exercised once
 * against real records to prove the string is valid SOQL and that a two-hop path
 * arrives populated.
 */
@IsTest
private class AMF_FieldPathResolverTest {
    private static final String PURCHASE_REQUEST = 'Purchase_Request__c';

    @IsTest
    static void unionCollectsPathsAcrossRulesAndDeduplicates() {
        List<AMF_ExprCompiler.CompiledExpression> compiled = new List<AMF_ExprCompiler.CompiledExpression>{
            AMF_ExprCompiler.compile(PURCHASE_REQUEST, 'Amount__c > 100000 && Region__c == \'APAC\''),
            AMF_ExprCompiler.compile(PURCHASE_REQUEST, 'Risk_Level__c == \'High\''),
            // Shares Amount__c with the first rule, and adds one hop.
            AMF_ExprCompiler.compile(PURCHASE_REQUEST, 'Amount__c > 1 && Account__r.Name != NULL'),
            // The catch-all reads nothing at all.
            AMF_ExprCompiler.compile(PURCHASE_REQUEST, 'TRUE')
        };

        Assert.areEqual(
            new Set<String>{ 'Amount__c', 'Region__c', 'Risk_Level__c', 'Account__r.Name' },
            AMF_FieldPathResolver.unionPaths(compiled),
            'A path shared by two rules is queried once (4.4)'
        );
    }

    @IsTest
    static void unionHandlesNothingToUnion() {
        Assert.areEqual(
            0,
            AMF_FieldPathResolver.unionPaths(null).size(),
            'A null list is no paths, not an error'
        );
        Assert.areEqual(
            0,
            AMF_FieldPathResolver.unionPaths(new List<AMF_ExprCompiler.CompiledExpression>()).size(),
            'And neither is an empty one'
        );
    }

    @IsTest
    static void queryIsOneSelectWithIdFirstAndPathsSorted() {
        String soql = AMF_FieldPathResolver.buildQuery(
            PURCHASE_REQUEST,
            new Set<String>{ 'Region__c', 'Amount__c', 'Account__r.Name' }
        );

        Assert.areEqual(
            'SELECT Id, Account__r.Name, Amount__c, Region__c FROM Purchase_Request__c WHERE Id IN :recordIds',
            soql,
            'Id first then alphabetical makes the query a pure function of its inputs'
        );
    }

    @IsTest
    static void aCatchAllOnlyMatrixStillQueriesIds() {
        Assert.areEqual(
            'SELECT Id FROM Purchase_Request__c WHERE Id IN :recordIds',
            AMF_FieldPathResolver.buildQuery(PURCHASE_REQUEST, new Set<String>()),
            'A matrix of catch-alls reads no fields but still has to load the records'
        );
        Assert.areEqual(
            'SELECT Id FROM Purchase_Request__c WHERE Id IN :recordIds',
            AMF_FieldPathResolver.buildQuery(PURCHASE_REQUEST, null),
            'And a null path set is the same thing'
        );
    }

    @IsTest
    static void idIsNotSelectedTwice() {
        Assert.areEqual(
            'SELECT Id, Amount__c FROM Purchase_Request__c WHERE Id IN :recordIds',
            AMF_FieldPathResolver.buildQuery(PURCHASE_REQUEST, new Set<String>{ 'Id', 'Amount__c', 'id' }),
            'An expression naming Id must not produce a duplicate column'
        );
    }

    @IsTest
    static void malformedInputIsRefusedRatherThanConcatenated() {
        Map<String, String> expected = new Map<String, String>{
            'Amount__c FROM User WHERE Name != \'\' --' => 'Field path',
            'Amount__c, Id' => 'Field path',
            'Amount__c)' => 'Field path',
            '' => 'Field path',
            '1Amount__c' => 'Field path'
        };

        for (String path : expected.keySet()) {
            try {
                AMF_FieldPathResolver.buildQuery(PURCHASE_REQUEST, new Set<String>{ path });
                Assert.fail('"' + path + '" must not reach a query string');
            } catch (AMF_ExpressionException e) {
                Assert.isTrue(
                    e.getMessage().contains(expected.get(path)),
                    'For "' + path + '" got: ' + e.getMessage()
                );
            }
        }

        try {
            AMF_FieldPathResolver.buildQuery('Purchase_Request__c WHERE Id != NULL', new Set<String>());
            Assert.fail('A malformed object name must not reach a query string');
        } catch (AMF_ExpressionException e) {
            Assert.isTrue(e.getMessage().contains('Object API name'), e.getMessage());
        }
    }

    @IsTest
    static void overDeepPathsAreRefused() {
        try {
            AMF_FieldPathResolver.buildQuery(
                PURCHASE_REQUEST,
                new Set<String>{ 'Account__r.Owner.Alias' }
            );
            Assert.fail('The 13.3 two-segment cap is enforced here as well as in the compiler');
        } catch (AMF_ExpressionException e) {
            Assert.isTrue(e.getMessage().contains('exceeds the maximum of 2 segments'), e.getMessage());
        }
    }

    @IsTest
    static void loadReturnsRecordsCarryingEveryRequestedPath() {
        Account account = new Account(Name = 'Globex');
        insert account;
        List<Purchase_Request__c> requests = new List<Purchase_Request__c>{
            new Purchase_Request__c(Amount__c = 150000, Region__c = 'APAC', Account__c = account.Id),
            new Purchase_Request__c(Amount__c = 500, Region__c = 'EMEA')
        };
        insert requests;

        Test.startTest();
        Map<Id, SObject> loaded = AMF_FieldPathResolver.load(
            PURCHASE_REQUEST,
            new Set<String>{ 'Amount__c', 'Region__c', 'Account__r.Name' },
            new Map<Id, Purchase_Request__c>(requests).keySet()
        );
        // Read inside the block: stopTest restores the outer context's counters.
        Integer queriesUsed = Limits.getQueries();
        Test.stopTest();

        Assert.areEqual(2, loaded.size(), 'Both records come back from one query');
        Assert.areEqual(
            1,
            queriesUsed,
            'One query per object per transaction is the whole point of 4.4'
        );

        Purchase_Request__c withAccount = (Purchase_Request__c) loaded.get(requests[0].Id);
        Assert.areEqual(150000, withAccount.Amount__c, 'Local fields arrive');
        Assert.areEqual(
            'Globex',
            withAccount.getSObject('Account__r').get('Name'),
            'And so does the two-hop path the evaluator will read'
        );

        Purchase_Request__c withoutAccount = (Purchase_Request__c) loaded.get(requests[1].Id);
        Assert.areEqual(
            null,
            withoutAccount.getSObject('Account__r'),
            'A record with no parent yields a null relationship, which the evaluator treats as a broken path'
        );
    }

    @IsTest
    static void loadWithNothingToLoadRunsNoQuery() {
        Test.startTest();
        Assert.areEqual(
            0,
            AMF_FieldPathResolver.load(PURCHASE_REQUEST, new Set<String>{ 'Amount__c' }, new Set<Id>()).size(),
            'No records, no map'
        );
        Assert.areEqual(
            0,
            AMF_FieldPathResolver.load(PURCHASE_REQUEST, new Set<String>{ 'Amount__c' }, null).size(),
            'And a null id set is the same thing'
        );
        Integer queriesUsed = Limits.getQueries();
        Test.stopTest();

        Assert.areEqual(0, queriesUsed, 'An empty submission must not spend a query');
    }
}
