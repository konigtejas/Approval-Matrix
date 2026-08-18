/**
 * The table-driven evaluator suite: every operator against every supported type,
 * all null rules, precedence, whitespace, two-segment paths and bare TRUE.
 *
 * Architecture section: 4.3 (type and null semantics), 4.7 (test strategy).
 *
 * Cases are (expression, record, expected) triples run through the real compiler
 * and the real evaluator, and a method reports EVERY mismatch in its table rather
 * than dying on the first -- when a change to the null rules breaks nine cases,
 * seeing all nine at once is what tells you which rule moved.
 *
 * Zero dependence on org CMDT rows: nothing here reads Approval_Matrix_Rule__mdt,
 * and every record is built in memory. Per arch doc 10, types the pilot object
 * does not carry are exercised against standard objects -- Date on
 * Opportunity.CloseDate, Integer and Double on Account -- rather than by adding
 * fields to Purchase_Request__c that only a test would use.
 */
@IsTest
private class AMF_EvaluatorTest {
    private static final String PURCHASE_REQUEST = 'Purchase_Request__c';

    /** One row of a decision table. */
    private class ExprCase {
        private String expression;
        private SObject record;
        private Boolean expected;

        private ExprCase(String expression, SObject record, Boolean expected) {
            this.expression = expression;
            this.record = record;
            this.expected = expected;
        }
    }

    // ---------------------------------------------------------------- numeric

    @IsTest
    static void everyOperatorAgainstCurrency() {
        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                new ExprCase('Amount__c == 100', pr(100), true),
                new ExprCase('Amount__c == 100', pr(200), false),
                new ExprCase('Amount__c != 100', pr(200), true),
                new ExprCase('Amount__c != 100', pr(100), false),
                new ExprCase('Amount__c > 100', pr(101), true),
                new ExprCase('Amount__c > 100', pr(100), false),
                new ExprCase('Amount__c >= 100', pr(100), true),
                new ExprCase('Amount__c >= 100', pr(99), false),
                new ExprCase('Amount__c < 100', pr(99), true),
                new ExprCase('Amount__c < 100', pr(100), false),
                new ExprCase('Amount__c <= 100', pr(100), true),
                new ExprCase('Amount__c <= 100', pr(101), false),
                new ExprCase('Amount__c == 100.50', pr(100.50), true),
                new ExprCase('Amount__c > 100.49', pr(100.50), true),
                new ExprCase('Amount__c < -5', pr(-10), true),
                new ExprCase('Amount__c < -5', pr(-1), false),
                new ExprCase('Amount__c == -10', pr(-10), true),
                // Literal on the left is the same comparison, mirrored.
                new ExprCase('100 < Amount__c', pr(200), true),
                new ExprCase('100 < Amount__c', pr(50), false)
            }
        );
    }

    @IsTest
    static void integerAndDoubleFieldsCompareAsNumbers() {
        run(
            'Account',
            new List<ExprCase>{
                new ExprCase('NumberOfEmployees > 50', new Account(NumberOfEmployees = 100), true),
                new ExprCase('NumberOfEmployees > 50', new Account(NumberOfEmployees = 10), false),
                new ExprCase('NumberOfEmployees == 100', new Account(NumberOfEmployees = 100), true),
                new ExprCase('AnnualRevenue >= 1000000', new Account(AnnualRevenue = 1000000), true),
                new ExprCase('BillingLatitude > 40.5', new Account(BillingLatitude = 41.0), true),
                new ExprCase('BillingLatitude > 40.5', new Account(BillingLatitude = 40.4), false)
            }
        );
    }

    // ------------------------------------------------------------------- text

    @IsTest
    static void picklistAndStringCompareCaseInsensitively() {
        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                new ExprCase('Region__c == \'APAC\'', pr(1, 'APAC', 'Low'), true),
                // 4.3: text equality is case-insensitive, both ways round.
                new ExprCase('Region__c == \'apac\'', pr(1, 'APAC', 'Low'), true),
                new ExprCase('Region__c == \'ApAc\'', pr(1, 'APAC', 'Low'), true),
                new ExprCase('Region__c == \'EMEA\'', pr(1, 'APAC', 'Low'), false),
                new ExprCase('Region__c != \'EMEA\'', pr(1, 'APAC', 'Low'), true),
                new ExprCase('Region__c != \'APAC\'', pr(1, 'APAC', 'Low'), false),
                new ExprCase('Risk_Level__c == \'High\'', pr(1, 'APAC', 'High'), true)
            }
        );
        run(
            'Account',
            new List<ExprCase>{
                new ExprCase('Name == \'Globex\'', new Account(Name = 'Globex'), true),
                new ExprCase('Name == \'globex\'', new Account(Name = 'Globex'), true),
                new ExprCase('Name != \'Initech\'', new Account(Name = 'Globex'), true)
            }
        );
    }

    @IsTest
    static void referenceFieldsCompareAsText() {
        Id accountId = fakeId(Account.SObjectType, 1);
        Id otherId = fakeId(Account.SObjectType, 2);

        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                new ExprCase('Account__c != NULL', new Purchase_Request__c(Account__c = accountId), true),
                new ExprCase('Account__c == NULL', new Purchase_Request__c(Account__c = accountId), false),
                new ExprCase('Account__c == NULL', new Purchase_Request__c(), true),
                new ExprCase(
                    'Account__c == \'' + accountId + '\'',
                    new Purchase_Request__c(Account__c = accountId),
                    true
                ),
                new ExprCase(
                    'Account__c == \'' + otherId + '\'',
                    new Purchase_Request__c(Account__c = accountId),
                    false
                )
            }
        );
    }

    // ---------------------------------------------------------------- boolean

    @IsTest
    static void checkboxIsIdentityAndStandsAloneAsACondition() {
        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                new ExprCase('Matrix_Submission__c == TRUE', guard(true), true),
                new ExprCase('Matrix_Submission__c == TRUE', guard(false), false),
                new ExprCase('Matrix_Submission__c == FALSE', guard(false), true),
                new ExprCase('Matrix_Submission__c != TRUE', guard(false), true),
                new ExprCase('Matrix_Submission__c != FALSE', guard(true), true),
                // 4.1's bool_atom: a bare Checkbox path is a complete expression.
                new ExprCase('Matrix_Submission__c', guard(true), true),
                new ExprCase('Matrix_Submission__c', guard(false), false),
                // An unset Checkbox reads null in memory, and a null atom is false.
                new ExprCase('Matrix_Submission__c', new Purchase_Request__c(), false),
                new ExprCase('Matrix_Submission__c == TRUE', new Purchase_Request__c(), false),
                new ExprCase('Matrix_Submission__c == NULL', new Purchase_Request__c(), true)
            }
        );
    }

    @IsTest
    static void bareTrueIsTheCatchAllAndKeywordsAreCaseInsensitive() {
        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                // The whole reason PR_Catch_All can exist (3.2).
                new ExprCase('TRUE', pr(1), true),
                new ExprCase('true', pr(1), true),
                new ExprCase('True', pr(1), true),
                new ExprCase('FALSE', pr(1), false),
                new ExprCase('false', pr(1), false)
            }
        );

        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(PURCHASE_REQUEST, 'TRUE');
        Assert.areEqual(
            0,
            compiled.fieldPaths.size(),
            'A catch-all reads no fields, so it must contribute nothing to the 4.4 query'
        );
    }

    // ------------------------------------------------------------------- date

    @IsTest
    static void everyOperatorAgainstDate() {
        Date target = Date.newInstance(2026, 1, 31);

        run(
            'Opportunity',
            new List<ExprCase>{
                new ExprCase('CloseDate == 2026-01-31', opp(target), true),
                new ExprCase('CloseDate == 2026-02-01', opp(target), false),
                new ExprCase('CloseDate != 2026-02-01', opp(target), true),
                new ExprCase('CloseDate > 2026-01-01', opp(target), true),
                new ExprCase('CloseDate > 2026-01-31', opp(target), false),
                new ExprCase('CloseDate >= 2026-01-31', opp(target), true),
                new ExprCase('CloseDate < 2026-02-01', opp(target), true),
                new ExprCase('CloseDate < 2026-01-31', opp(target), false),
                new ExprCase('CloseDate <= 2026-01-31', opp(target), true),
                new ExprCase('CloseDate == NULL', opp(target), false),
                new ExprCase('CloseDate != NULL', opp(target), true)
            }
        );
    }

    // ------------------------------------------------------------- null rules

    @IsTest
    static void nullRulesExhaustively() {
        Purchase_Request__c empty = new Purchase_Request__c();
        Purchase_Request__c filled = pr(100, 'APAC', 'Low');

        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                // null == null is true; null != null is false.
                new ExprCase('Amount__c == NULL', empty, true),
                new ExprCase('Amount__c != NULL', empty, false),
                new ExprCase('NULL == NULL', empty, true),
                new ExprCase('NULL != NULL', empty, false),
                // null against a value, both ways round.
                new ExprCase('Amount__c == 100', empty, false),
                new ExprCase('Amount__c != 100', empty, true),
                new ExprCase('100 == Amount__c', empty, false),
                new ExprCase('Amount__c == NULL', filled, false),
                new ExprCase('Amount__c != NULL', filled, true),
                // null against every ordering operator is false, never an error.
                new ExprCase('Amount__c > 100', empty, false),
                new ExprCase('Amount__c >= 100', empty, false),
                new ExprCase('Amount__c < 100', empty, false),
                new ExprCase('Amount__c <= 100', empty, false),
                new ExprCase('Amount__c > NULL', empty, false),
                // Same rules for text and picklist.
                new ExprCase('Region__c == NULL', empty, true),
                new ExprCase('Region__c != NULL', empty, false),
                new ExprCase('Region__c == \'APAC\'', empty, false),
                new ExprCase('Region__c != \'APAC\'', empty, true),
                // A null operand does not stop the other side of an && or ||.
                new ExprCase('Amount__c == NULL && Region__c == NULL', empty, true),
                new ExprCase('Amount__c > 100 || Region__c == NULL', empty, true)
            }
        );
    }

    // ------------------------------------------------------- two-segment path

    @IsTest
    static void relationshipPathsResolveAndBreakSafely() {
        Purchase_Request__c withAccount = prWithAccount(100, 'Globex');
        Purchase_Request__c withNamelessAccount = prWithAccount(100, null);
        Purchase_Request__c withoutAccount = pr(100);

        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                new ExprCase('Account__r.Name == \'Globex\'', withAccount, true),
                new ExprCase('Account__r.Name == \'globex\'', withAccount, true),
                new ExprCase('Account__r.Name == \'Initech\'', withAccount, false),
                new ExprCase('Account__r.Name != NULL', withAccount, true),
                // Account present, its Name null: the ordinary null rules apply.
                new ExprCase('Account__r.Name == NULL', withNamelessAccount, true),
                new ExprCase('Account__r.Name != NULL', withNamelessAccount, false),
                // No Account at all: the path cannot resolve, so the comparison is
                // false whatever the operator -- INCLUDING == NULL and != NULL.
                // 4.3, and docs/decisions.md 2026-08-18.
                new ExprCase('Account__r.Name == \'Globex\'', withoutAccount, false),
                new ExprCase('Account__r.Name == NULL', withoutAccount, false),
                new ExprCase('Account__r.Name != NULL', withoutAccount, false),
                new ExprCase('Account__r.Name != \'Globex\'', withoutAccount, false),
                // A broken path does not poison the rest of the expression.
                new ExprCase('Account__r.Name == \'Globex\' || Amount__c == 100', withoutAccount, true),
                new ExprCase('Account__r.Name == \'Globex\' && Amount__c == 100', withoutAccount, false)
            }
        );
    }

    // --------------------------------------------------------- precedence etc

    @IsTest
    static void precedenceFollowsSection41() {
        Purchase_Request__c record = pr(50, 'EMEA', 'High');

        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                // a || b && c parses as a || (b && c). Grouped the other way this
                // would be false, which is what makes it a precedence test.
                new ExprCase('TRUE || FALSE && FALSE', record, true),
                new ExprCase('FALSE && FALSE || TRUE', record, true),
                new ExprCase('FALSE || TRUE && FALSE', record, false),
                // Parentheses override, and are the only thing that does.
                new ExprCase('(TRUE || FALSE) && FALSE', record, false),
                new ExprCase('(FALSE || TRUE) && TRUE', record, true),
                // Comparisons bind tighter than both.
                new ExprCase('Amount__c > 100 && Region__c == \'APAC\' || Risk_Level__c == \'High\'', record, true),
                new ExprCase('Amount__c > 100 && (Region__c == \'APAC\' || Risk_Level__c == \'High\')', record, false),
                new ExprCase('Amount__c < 100 && (Region__c == \'APAC\' || Risk_Level__c == \'High\')', record, true),
                // Nesting.
                new ExprCase('((Amount__c < 100))', record, true),
                new ExprCase('(Amount__c < 100 && (Risk_Level__c == \'High\' || FALSE))', record, true)
            }
        );
    }

    @IsTest
    static void whitespaceAndFieldNameCasingDoNotChangeMeaning() {
        Purchase_Request__c record = pr(150000, 'APAC', 'Low');

        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                new ExprCase('Amount__c>100000', record, true),
                new ExprCase('   Amount__c   >   100000   ', record, true),
                new ExprCase('Amount__c > 100000\n&& Region__c == \'APAC\'', record, true),
                new ExprCase('Amount__c > 100000\t&&\tRegion__c == \'APAC\'', record, true),
                new ExprCase('Amount__c>100000&&Region__c==\'APAC\'', record, true),
                // API names are case-insensitive, exactly as they are in SOQL.
                new ExprCase('amount__c > 100000', record, true),
                new ExprCase('AMOUNT__C > 100000', record, true),
                new ExprCase('account__r.name == NULL', record, false)
            }
        );
    }

    // ------------------------------------------------------- evaluated values

    @IsTest
    static void evaluatedValuesRecordEveryPathTheExpressionNames() {
        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(
            PURCHASE_REQUEST,
            'Amount__c > 100000 && Region__c == \'APAC\''
        );
        AMF_Evaluator.Result result = AMF_Evaluator.evaluate(compiled, pr(150000, 'APAC', 'Low'));

        Assert.isTrue(result.matched, 'High-value APAC must match its own rule');
        Assert.areEqual(
            new Set<String>{ 'Amount__c', 'Region__c' },
            result.evaluatedValues.keySet(),
            'Evaluated_Values__c must name every path the expression read (3.3)'
        );
        Assert.areEqual(150000, result.evaluatedValues.get('Amount__c'), 'Values are the record values');
        Assert.areEqual('APAC', result.evaluatedValues.get('Region__c'), 'Values are the record values');
    }

    @IsTest
    static void evaluatedValuesSurviveShortCircuiting() {
        // FALSE && ... never evaluates the right-hand side, but the audit record
        // must still say which fields the rule is written against.
        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(
            PURCHASE_REQUEST,
            'FALSE && Amount__c > 100'
        );
        AMF_Evaluator.Result result = AMF_Evaluator.evaluate(compiled, pr(150000));

        Assert.isFalse(result.matched, 'FALSE && anything is false');
        Assert.isTrue(
            result.evaluatedValues.containsKey('Amount__c'),
            'Short-circuiting must not change what the decision log says was read'
        );
        Assert.areEqual(150000, result.evaluatedValues.get('Amount__c'), 'And it must be the real value');
    }

    @IsTest
    static void evaluatedValueKeysAreCanonicalApiNames() {
        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(
            PURCHASE_REQUEST,
            'amount__c > 1 && account__r.name != NULL'
        );
        AMF_Evaluator.Result result = AMF_Evaluator.evaluate(compiled, prWithAccount(100, 'Globex'));

        Assert.areEqual(
            new Set<String>{ 'Amount__c', 'Account__r.Name' },
            result.evaluatedValues.keySet(),
            'The audit JSON must read in API-name spelling however the rule was typed'
        );
        Assert.areEqual('Globex', result.evaluatedValues.get('Account__r.Name'), 'Two hops resolve');
    }

    @IsTest
    static void brokenPathRecordsANullValueRatherThanFailing() {
        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(
            PURCHASE_REQUEST,
            'Account__r.Name == \'Globex\''
        );
        AMF_Evaluator.Result result = AMF_Evaluator.evaluate(compiled, pr(100));

        Assert.isFalse(result.matched, 'An unresolvable path matches nothing');
        Assert.isTrue(
            result.evaluatedValues.containsKey('Account__r.Name'),
            'The log still has to show which path could not be resolved'
        );
        Assert.areEqual(null, result.evaluatedValues.get('Account__r.Name'), 'And that it read as null');
    }

    @IsTest
    static void evaluatedValuesSerialiseToJson() {
        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(
            'Opportunity',
            'CloseDate > 2026-01-01 && Amount > 5'
        );
        AMF_Evaluator.Result result = AMF_Evaluator.evaluate(
            compiled,
            new Opportunity(CloseDate = Date.newInstance(2026, 1, 31), Amount = 10)
        );

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result.toJson());
        Assert.areEqual(
            2,
            parsed.size(),
            'Evaluated_Values__c is JSON, and a Date value must not break the serialisation'
        );
        Assert.areEqual('2026-01-31', parsed.get('CloseDate'), 'Dates serialise as ISO days');
    }

    // ------------------------------------------------------- defensive guards

    @IsTest
    static void orderingOperatorOnTextThrowsRatherThanReturningFalse() {
        // The compiler rejects Region__c > 'APAC', so this tree cannot come from
        // it. Handing it to the evaluator directly proves the runtime guard
        // throws instead of falling through to false, which is 4.6's whole point.
        AMF_ExprCompiler.CompiledExpression compiled = handBuilt(
            comparison('>', AMF_Ast.ValueType.TEXT, 'APAC', 'EMEA')
        );

        try {
            AMF_Evaluator.evaluate(compiled, pr(1));
            Assert.fail('An ordering operator on text must throw, never return false');
        } catch (AMF_ExpressionException e) {
            Assert.isTrue(
                e.getMessage().contains('cannot be applied to text values'),
                'The guard must name the operator and the type. Got: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void unknownOperandTypeThrowsRatherThanReturningFalse() {
        AMF_ExprCompiler.CompiledExpression compiled = handBuilt(comparison('==', null, 'a', 'b'));

        try {
            AMF_Evaluator.evaluate(compiled, pr(1));
            Assert.fail('A comparison with no resolved type must throw');
        } catch (AMF_ExpressionException e) {
            Assert.isTrue(
                e.getMessage().contains('unknown type'),
                'The guard must say the type could not be determined. Got: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void anOrderingOperatorTheGrammarCannotProduceThrows() {
        // The parser emits only the six comparison operators, so this tree is
        // again one the pipeline could not have built. The guard exists so that a
        // future operator added to the parser and forgotten here fails loudly
        // instead of quietly evaluating to false.
        AMF_Ast.ComparisonNode node = numericComparison('LIKE', 1, 2);

        try {
            AMF_Evaluator.evaluate(handBuilt(node), pr(1));
            Assert.fail('An operator the evaluator does not implement must throw');
        } catch (AMF_ExpressionException e) {
            Assert.isTrue(
                e.getMessage().contains('\'LIKE\'') && e.getMessage().contains('numeric values'),
                'The guard must name the operator and the type. Got: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void numbersCompareWhicheverApexTypeTheyArriveAs() {
        // A Currency field reads as Decimal, an Integer field as Integer, a Long
        // one as Long and a geolocation as Double. All four have to compare
        // against a Decimal literal without an equality surprise -- which they do
        // through a single cast, because Apex reports every boxed numeric as
        // `instanceof Decimal` (see AMF_Evaluator.toDecimal). This test is what
        // would notice if that platform behaviour ever changed.
        Map<String, Object> sameValue = new Map<String, Object>{
            'Decimal' => (Decimal) 42,
            'Integer' => (Integer) 42,
            'Long' => (Long) 42,
            'Double' => (Double) 42,
            'String' => '42'
        };

        for (String apexType : sameValue.keySet()) {
            AMF_Evaluator.Result equal = AMF_Evaluator.evaluate(
                handBuilt(numericComparison('==', sameValue.get(apexType), 42)),
                pr(1)
            );
            AMF_Evaluator.Result greater = AMF_Evaluator.evaluate(
                handBuilt(numericComparison('>', sameValue.get(apexType), 41)),
                pr(1)
            );

            Assert.isTrue(equal.matched, apexType + ' must equal the Decimal literal 42');
            Assert.isTrue(greater.matched, apexType + ' must order against the Decimal literal 41');
        }

        Assert.isTrue(
            AMF_Evaluator.evaluate(handBuilt(numericComparison('>', (Long) 5000000000L, 42)), pr(1)).matched,
            'A Long beyond Integer range must not overflow on its way to Decimal'
        );
    }

    @IsTest
    static void nullArgumentsThrow() {
        try {
            AMF_Evaluator.evaluate(null, pr(1));
            Assert.fail('A null compiled expression must throw');
        } catch (AMF_ExpressionException e) {
            Assert.isTrue(e.getMessage().contains('null compiled expression'), e.getMessage());
        }

        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(PURCHASE_REQUEST, 'TRUE');
        try {
            AMF_Evaluator.evaluate(compiled, null);
            Assert.fail('A null record must throw');
        } catch (AMF_ExpressionException e) {
            Assert.isTrue(e.getMessage().contains('null record'), e.getMessage());
        }
    }

    @IsTest
    static void aFieldTheQueryDidNotSelectThrowsRatherThanEvaluatingFalse() {
        // 4.6: a record queried without a field the expression needs is a real
        // fault. It must surface as an exception and block, not read as null.
        insert new Purchase_Request__c(Amount__c = 100, Region__c = 'APAC');
        Purchase_Request__c thin = [SELECT Id FROM Purchase_Request__c LIMIT 1];

        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(
            PURCHASE_REQUEST,
            'Amount__c > 50'
        );

        try {
            AMF_Evaluator.evaluate(compiled, thin);
            Assert.fail('Evaluating an unqueried field must throw, not return false');
        } catch (System.SObjectException e) {
            Assert.isTrue(
                e.getMessage().contains('Amount__c'),
                'The platform error must name the missing field. Got: ' + e.getMessage()
            );
        }
    }

    // ------------------------------------------------------------- test plumbing

    /**
     * Runs a decision table, reporting every mismatch rather than the first.
     *
     * @param objectApiName Object the expressions are compiled against.
     * @param cases         The table.
     */
    private static void run(String objectApiName, List<ExprCase> cases) {
        List<String> failures = new List<String>();

        for (ExprCase testCase : cases) {
            AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(
                objectApiName,
                testCase.expression
            );
            AMF_Evaluator.Result result = AMF_Evaluator.evaluate(compiled, testCase.record);

            if (result.matched != testCase.expected) {
                failures.add(
                    '  ' +
                    testCase.expression +
                    '  ->  expected ' +
                    testCase.expected +
                    ', got ' +
                    result.matched
                );
            }
        }

        Assert.areEqual(
            0,
            failures.size(),
            failures.size() + ' of ' + cases.size() + ' cases failed:\n' + String.join(failures, '\n')
        );
    }

    private static Purchase_Request__c pr(Decimal amount) {
        return new Purchase_Request__c(Amount__c = amount);
    }

    private static Purchase_Request__c pr(Decimal amount, String region, String riskLevel) {
        return new Purchase_Request__c(Amount__c = amount, Region__c = region, Risk_Level__c = riskLevel);
    }

    private static Purchase_Request__c guard(Boolean submitted) {
        return new Purchase_Request__c(Matrix_Submission__c = submitted);
    }

    private static Opportunity opp(Date closeDate) {
        return new Opportunity(CloseDate = closeDate);
    }

    /**
     * An in-memory record carrying a populated parent relationship. Assigning
     * Account__r directly is not possible on a record that was never queried, so
     * the JSON round trip is the only way to build a two-hop fixture without DML.
     *
     * @param amount      Amount__c.
     * @param accountName Account__r.Name, which may be null.
     * @return The record, with Account__r populated.
     */
    private static Purchase_Request__c prWithAccount(Decimal amount, String accountName) {
        Map<String, Object> shape = new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Purchase_Request__c' },
            'Amount__c' => amount,
            'Account__r' => new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'type' => 'Account' },
                'Name' => accountName
            }
        };
        return (Purchase_Request__c) JSON.deserialize(JSON.serialize(shape), Purchase_Request__c.class);
    }

    private static Id fakeId(Schema.SObjectType objectType, Integer index) {
        String suffix = String.valueOf(index);
        return Id.valueOf(objectType.getDescribe().getKeyPrefix() + '0'.repeat(12 - suffix.length()) + suffix);
    }

    private static AMF_Ast.ComparisonNode comparison(
        String operator,
        AMF_Ast.ValueType operandType,
        String left,
        String right
    ) {
        AMF_Ast.ComparisonNode node = new AMF_Ast.ComparisonNode(
            operator,
            new AMF_Ast.LiteralNode(left, AMF_Ast.ValueType.TEXT, 0),
            new AMF_Ast.LiteralNode(right, AMF_Ast.ValueType.TEXT, 0),
            0
        );
        node.operandType = operandType;
        return node;
    }

    private static AMF_Ast.ComparisonNode numericComparison(String operator, Object left, Object right) {
        AMF_Ast.ComparisonNode node = new AMF_Ast.ComparisonNode(
            operator,
            new AMF_Ast.LiteralNode(left, AMF_Ast.ValueType.NUMERIC, 0),
            new AMF_Ast.LiteralNode(right, AMF_Ast.ValueType.NUMERIC, 0),
            0
        );
        node.operandType = AMF_Ast.ValueType.NUMERIC;
        return node;
    }

    private static AMF_ExprCompiler.CompiledExpression handBuilt(AMF_Ast.Node root) {
        return new AMF_ExprCompiler.CompiledExpression(
            PURCHASE_REQUEST,
            'hand-built AST, never produced by the compiler',
            root,
            new List<String>(),
            new Map<String, Schema.DescribeFieldResult>()
        );
    }
}
