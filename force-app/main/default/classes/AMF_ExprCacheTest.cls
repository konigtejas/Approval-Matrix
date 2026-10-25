/**
 * Unit test for AMF_ExprCache: compile once per transaction, and invalidate on
 * Version__c rather than on a flush call.
 *
 * Architecture section: 4.5 (caching), 6.1 step 3, 10 (in-memory fixtures).
 *
 * Every rule here is an AMF_RuleBuilder fixture -- no org CMDT row is read, per
 * CLAUDE.md. reset() runs first in each method because a static map outlives a
 * test method, and a count assertion that depended on execution order would be
 * worthless.
 */
@IsTest
private class AMF_ExprCacheTest {
    @IsTest
    static void compilesOnceAndServesTheRestFromCache() {
        AMF_ExprCache.reset();
        AMF_RuleDefinition rule = new AMF_RuleBuilder()
            .named('High_Value')
            .withExpression('Amount__c > 100000')
            .build();

        AMF_ExprCompiler.CompiledExpression first = AMF_ExprCache.get(rule);
        AMF_ExprCompiler.CompiledExpression second = AMF_ExprCache.get(rule);
        AMF_ExprCache.get(rule);

        Assert.areEqual(
            1,
            AMF_ExprCache.getCompilations(),
            'Compilation is the expensive half (4.5); three lookups must cost one compile'
        );
        Assert.isTrue(first == second, 'And must hand back the same instance, not an equal copy');
    }

    @IsTest
    static void aVersionBumpInvalidatesNaturally() {
        AMF_ExprCache.reset();
        AMF_RuleDefinition version1 = new AMF_RuleBuilder()
            .named('High_Value')
            .withExpression('Amount__c > 100000')
            .atVersion(1)
            .build();
        AMF_RuleDefinition version2 = new AMF_RuleBuilder()
            .named('High_Value')
            .withExpression('Amount__c > 250000')
            .atVersion(2)
            .build();

        AMF_ExprCache.get(version1);
        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCache.get(version2);

        Assert.areEqual(
            2,
            AMF_ExprCache.getCompilations(),
            'The key carries Version__c, so an edited rule recompiles with no flush call (4.5)'
        );
        Assert.areEqual(
            'Amount__c > 250000',
            compiled.expression,
            'And the caller gets the new expression, not the cached old one'
        );
    }

    @IsTest
    static void anEditWithoutAVersionBumpIsInvisibleToThisTransaction() {
        // Stated as a test because it is the sharp edge of the 4.5 design, and
        // the reason 3.3 stamps Rule_Version__c onto every decision log row: the
        // log records which version actually routed the record.
        AMF_ExprCache.reset();
        AMF_RuleDefinition before = new AMF_RuleBuilder()
            .named('High_Value')
            .withExpression('Amount__c > 100000')
            .atVersion(1)
            .build();
        AMF_RuleDefinition edited = new AMF_RuleBuilder()
            .named('High_Value')
            .withExpression('Amount__c > 999')
            .atVersion(1)
            .build();

        AMF_ExprCache.get(before);
        AMF_ExprCompiler.CompiledExpression served = AMF_ExprCache.get(edited);

        Assert.areEqual(1, AMF_ExprCache.getCompilations(), 'Same key, so no second compile');
        Assert.areEqual(
            'Amount__c > 100000',
            served.expression,
            'The transaction keeps the version it started with; bumping Version__c is what changes it'
        );
    }

    @IsTest
    static void differentRulesGetDifferentEntries() {
        AMF_ExprCache.reset();

        AMF_ExprCache.get(new AMF_RuleBuilder().named('A').withExpression('Amount__c > 1').build());
        AMF_ExprCache.get(new AMF_RuleBuilder().named('B').withExpression('Amount__c > 2').build());
        AMF_ExprCache.get(new AMF_RuleBuilder().named('A').withExpression('Amount__c > 1').build());

        Assert.areEqual(2, AMF_ExprCache.getCompilations(), 'Two rules, two compiles, then a cache hit');
    }

    @IsTest
    static void keyIsDeveloperNameAndVersion() {
        AMF_RuleDefinition rule = new AMF_RuleBuilder().named('High_Value').atVersion(3).build();

        Assert.areEqual(
            'High_Value|3',
            AMF_ExprCache.keyFor(rule),
            'The 4.5 key, spelled out, so a change to it is a deliberate act'
        );
    }

    @IsTest
    static void failuresAreNotCached() {
        AMF_ExprCache.reset();
        AMF_RuleDefinition broken = new AMF_RuleBuilder()
            .named('Broken')
            .withExpression('Amount__c > ')
            .build();

        for (Integer attempt = 1; attempt <= 2; attempt++) {
            try {
                AMF_ExprCache.get(broken);
                Assert.fail('A malformed expression must throw on attempt ' + attempt);
            } catch (AMF_ExpressionException e) {
                Assert.isNotNull(e.position, 'Every failure carries a position');
            }
        }

        Assert.areEqual(
            0,
            AMF_ExprCache.getCompilations(),
            'A failed compile is never counted or remembered -- 4.6 wants it loud every time'
        );
    }

    @IsTest
    static void aNullRuleThrows() {
        try {
            AMF_ExprCache.get(null);
            Assert.fail('A null rule must throw rather than returning null');
        } catch (AMF_ExpressionException e) {
            Assert.isTrue(e.getMessage().contains('null rule'), e.getMessage());
        }
    }
}
