/**
 * Unit test for AMF_ExprCompiler: path resolution against the schema, the type
 * and operator compatibility table, and the field-path list 4.4 queries with.
 *
 * Architecture section: 4.2, 4.3, 4.4, 4.6.
 *
 * The malformed-input cases that assert character positions live in
 * AMF_ExpressionErrorTest, which is the phase's stated error suite. What is
 * tested here is what the compiler PRODUCES on the happy path, and the
 * boundaries of the supported type surface.
 *
 * The multi-select picklist cases compile against QuickText.Channel, a standard
 * field, by name only: no test class references QuickText as a type, so the
 * suite still deploys to an org without it (technical log M9.2).
 */
@IsTest
private class AMF_ExprCompilerTest {
    private static final String PURCHASE_REQUEST = 'Purchase_Request__c';

    @IsTest
    static void resolvesLocalPathsAndKeepsTheSourceVerbatim() {
        String expression = 'Amount__c > 100000 && Region__c == \'APAC\'';
        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(PURCHASE_REQUEST, expression);

        Assert.areEqual(PURCHASE_REQUEST, compiled.objectApiName, 'The object is carried through');
        Assert.areEqual(
            expression,
            compiled.expression,
            'Expression_Snapshot__c is the source text, so it must survive compilation unaltered (3.3)'
        );
        Assert.areEqual(
            new List<String>{ 'Amount__c', 'Region__c' },
            compiled.fieldPaths,
            'Paths come out in first-seen order, which is what makes the query deterministic'
        );
        Assert.areEqual(
            Schema.DisplayType.CURRENCY,
            compiled.describeByPath.get('Amount__c').getType(),
            'The describe map is what lets a caller reason about types without describing again'
        );
    }

    @IsTest
    static void canonicalisesCasingAndDeduplicatesPaths() {
        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(
            PURCHASE_REQUEST,
            'amount__c > 1 && AMOUNT__C < 100 && account__r.NAME != NULL'
        );

        Assert.areEqual(
            new List<String>{ 'Amount__c', 'Account__r.Name' },
            compiled.fieldPaths,
            'A path named three times is queried once, in API-name spelling'
        );
    }

    @IsTest
    static void resolvesATwoSegmentRelationshipPath() {
        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(
            PURCHASE_REQUEST,
            'Account__r.Name == \'Globex\''
        );

        Assert.areEqual(
            new List<String>{ 'Account__r.Name' },
            compiled.fieldPaths,
            '13.3 allows one relationship hop'
        );
        Assert.areEqual(
            'Name',
            compiled.describeByPath.get('Account__r.Name').getName(),
            'The describe recorded is the leaf field on the parent, not the lookup'
        );
    }

    @IsTest
    static void acceptsEverySupportedFieldType() {
        Map<String, String> expressionByType = new Map<String, String>{
            'Currency' => 'Amount__c > 1',
            'Picklist' => 'Region__c == \'APAC\'',
            'Boolean' => 'Matrix_Submission__c == TRUE',
            'Reference' => 'Account__c != NULL',
            'Id' => 'Id != NULL',
            'String (2 hops)' => 'Account__r.Name == \'Globex\''
        };

        for (String label : expressionByType.keySet()) {
            AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(
                PURCHASE_REQUEST,
                expressionByType.get(label)
            );
            Assert.areEqual(
                1,
                compiled.fieldPaths.size(),
                label + ' must compile under the 13.3 type surface'
            );
        }

        // Date and Integer are not on Purchase_Request__c, so arch doc 10 says
        // to reach for a standard object rather than invent a field.
        Assert.areEqual(
            1,
            AMF_ExprCompiler.compile('Opportunity', 'CloseDate > 2026-01-01').fieldPaths.size(),
            'Date must compile'
        );
        Assert.areEqual(
            1,
            AMF_ExprCompiler.compile('Account', 'NumberOfEmployees >= 10').fieldPaths.size(),
            'Integer must compile'
        );
        // Multi-select picklist (M9): QuickText.Channel is a standard one.
        Assert.areEqual(
            1,
            AMF_ExprCompiler.compile('QuickText', 'Channel CONTAINS \'Email\'').fieldPaths.size(),
            'Multi-select picklist must compile'
        );
    }

    @IsTest
    static void resolvesThreeRelationshipHops() {
        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(
            PURCHASE_REQUEST,
            'account__r.owner.profile.NAME == \'System Administrator\''
        );

        Assert.areEqual(
            new List<String>{ 'Account__r.Owner.Profile.Name' },
            compiled.fieldPaths,
            'Four segments resolve, each canonicalised to its API-name spelling'
        );
        Assert.areEqual(
            Profile.Name.getDescribe().getName(),
            compiled.describeByPath.get('Account__r.Owner.Profile.Name').getName(),
            'The describe recorded is the leaf, on the object three hops away'
        );
        Assert.areEqual(4, AMF_ExprCompiler.MAX_PATH_SEGMENTS, 'Three hops is the limit (technical log M9.2)');
    }

    @IsTest
    static void typesTheNewComparisons() {
        Map<String, AMF_Ast.ValueType> expected = new Map<String, AMF_Ast.ValueType>{
            'Region__c IN (\'APAC\', \'EMEA\')' => AMF_Ast.ValueType.TEXT,
            'Amount__c NOT IN (1, 2)' => AMF_Ast.ValueType.NUMERIC,
            'Region__c CONTAINS \'PA\'' => AMF_Ast.ValueType.TEXT,
            'Account__r.Name STARTS_WITH Region__c' => AMF_Ast.ValueType.TEXT
        };

        for (String expression : expected.keySet()) {
            AMF_Ast.ComparisonNode root = (AMF_Ast.ComparisonNode) AMF_ExprCompiler.compile(PURCHASE_REQUEST, expression)
                .root;
            Assert.areEqual(expected.get(expression), root.operandType, 'Wrong operand type for ' + expression);
        }

        for (String expression : new List<String>{ 'Channel == \'Email;Phone\'', 'Channel CONTAINS \'Email\'' }) {
            AMF_Ast.ComparisonNode root = (AMF_Ast.ComparisonNode) AMF_ExprCompiler.compile('QuickText', expression)
                .root;
            Assert.areEqual(
                AMF_Ast.ValueType.MULTI_SELECT,
                root.operandType,
                'A multi-select comparison is a set comparison: ' + expression
            );
        }
    }

    @IsTest
    static void listsAndNegationsContributeTheirOperandsPathsOnly() {
        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(
            PURCHASE_REQUEST,
            'NOT (Amount__c > 1) && Region__c IN (\'APAC\') OR Account__r.Name CONTAINS \'x\''
        );

        Assert.areEqual(
            new List<String>{ 'Amount__c', 'Region__c', 'Account__r.Name' },
            compiled.fieldPaths,
            'A list of literals reads no field; its operand does'
        );
    }

    @IsTest
    static void flagsAnExpressionThatReadsToday() {
        Assert.isTrue(
            AMF_ExprCompiler.compile('Opportunity', 'CloseDate > TODAY(-7)').usesToday,
            'TODAY on the right of a comparison'
        );
        Assert.isTrue(
            AMF_ExprCompiler.compile('Opportunity', 'Amount > 1 || CloseDate IN (2026-01-01, TODAY)').usesToday,
            'TODAY inside an IN list'
        );
        Assert.isFalse(
            AMF_ExprCompiler.compile('Opportunity', 'CloseDate > 2026-01-01').usesToday,
            'A fixed date is not TODAY'
        );

        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile('Opportunity', 'CloseDate > TODAY');
        Assert.areEqual(
            new List<String>{ 'CloseDate' },
            compiled.fieldPaths,
            'TODAY is not a field, so it adds nothing to the 4.4 query'
        );
    }

    @IsTest
    static void nullComparesAgainstEveryType() {
        List<String> expressions = new List<String>{
            'Amount__c == NULL',
            'Amount__c != NULL',
            'Region__c == NULL',
            'Matrix_Submission__c == NULL',
            'Account__c != NULL',
            'Account__r.Name == NULL',
            'NULL == NULL'
        };

        for (String expression : expressions) {
            AMF_ExprCompiler.compile(PURCHASE_REQUEST, expression);
        }

        Assert.areEqual(
            7,
            expressions.size(),
            'NULL is the typeless literal, so 4.3 presence checks compile against every type'
        );
    }

    @IsTest
    static void rejectsAnUnsupportedFieldType() {
        // DateTime is in 4.3's full table but has not been built (M9 left it
        // out), so it must name itself rather than misbehave.
        try {
            AMF_ExprCompiler.compile(PURCHASE_REQUEST, 'CreatedDate > 2026-01-01');
            Assert.fail('A DateTime field is outside the MVP grammar and must not compile');
        } catch (AMF_ExpressionException e) {
            Assert.isTrue(
                e.getMessage().contains('DATETIME') && e.getMessage().contains('does not support'),
                'The error must name the unsupported type. Got: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void rejectsANonBooleanUsedAsAWholeCondition() {
        Map<String, String> expected = new Map<String, String>{
            'Amount__c' => 'field \'Amount__c\'',
            'Region__c' => 'field \'Region__c\'',
            '\'APAC\'' => 'a text literal',
            '100' => 'a numeric literal',
            'NULL' => 'a NULL literal',
            'Amount__c > 1 && Region__c' => 'field \'Region__c\''
        };

        for (String expression : expected.keySet()) {
            try {
                AMF_ExprCompiler.compile(PURCHASE_REQUEST, expression);
                Assert.fail(expression + ' is not a Boolean and must not stand alone as a condition');
            } catch (AMF_ExpressionException e) {
                Assert.isTrue(
                    e.getMessage().contains(expected.get(expression)) &&
                    e.getMessage().contains('cannot stand alone as a condition'),
                    'For ' + expression + ' the error must name the operand. Got: ' + e.getMessage()
                );
            }
        }
    }

    @IsTest
    static void rejectsOrderingOperatorsOnTypesThatHaveNoOrder() {
        Map<String, String> expected = new Map<String, String>{
            'Region__c > \'APAC\'' => 'text',
            'Region__c <= \'APAC\'' => 'text',
            'Account__r.Name < \'Globex\'' => 'text',
            'Matrix_Submission__c > TRUE' => 'boolean',
            'Matrix_Submission__c >= FALSE' => 'boolean'
        };

        for (String expression : expected.keySet()) {
            try {
                AMF_ExprCompiler.compile(PURCHASE_REQUEST, expression);
                Assert.fail(expression + ' must be a compile error, not a runtime false (4.6)');
            } catch (AMF_ExpressionException e) {
                Assert.isTrue(
                    e.getMessage().contains('is not supported for ' + expected.get(expression) + ' values'),
                    'For ' + expression + ' the error must name the type. Got: ' + e.getMessage()
                );
            }
        }
    }

    @IsTest
    static void rejectsMismatchedOperandTypes() {
        List<String> expressions = new List<String>{
            'Amount__c == \'APAC\'',
            'Region__c == 100',
            'Matrix_Submission__c == \'yes\'',
            'Matrix_Submission__c == 1',
            'Amount__c == TRUE',
            'Amount__c == 2026-01-31',
            'Region__c == TRUE',
            '100 == \'100\''
        };

        for (String expression : expressions) {
            try {
                AMF_ExprCompiler.compile(PURCHASE_REQUEST, expression);
                Assert.fail(expression + ' compares two different types and must not compile');
            } catch (AMF_ExpressionException e) {
                Assert.isTrue(
                    e.getMessage().contains('Cannot compare'),
                    'For ' + expression + ' the error must say what could not be compared. Got: ' +
                    e.getMessage()
                );
            }
        }
    }

    @IsTest
    static void rejectsAnObjectThatDoesNotExist() {
        try {
            AMF_ExprCompiler.compile('Not_An_Object__c', 'TRUE');
            Assert.fail('An unknown object must not compile');
        } catch (AMF_ExpressionException e) {
            Assert.isTrue(
                e.getMessage().contains('Not_An_Object__c') && e.getMessage().contains('does not exist'),
                'The error must name the object. Got: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void rejectsTraversingAPolymorphicRelationship() {
        // Task.Who points at Contact or Lead, so there is no single type to
        // resolve the next segment against. Guessing would be worse than failing.
        try {
            AMF_ExprCompiler.compile('Task', 'Who.Name == \'Globex\'');
            Assert.fail('A polymorphic relationship must not be traversed');
        } catch (AMF_ExpressionException e) {
            Assert.isTrue(
                e.getMessage().contains('polymorphic'),
                'The error must say why the hop is impossible. Got: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void attachesTheSourceExpressionToEveryFailure() {
        String expression = 'Amount__c > ';

        try {
            AMF_ExprCompiler.compile(PURCHASE_REQUEST, expression);
            Assert.fail('A truncated expression must not compile');
        } catch (AMF_ExpressionException e) {
            Assert.areEqual(
                expression,
                e.expressionText,
                'A caller catching this needs to know which rule to open'
            );
        }
    }
}
