/**
 * The malformed-input suite: every category of bad expression, driven through
 * the whole pipeline, each asserting the CHARACTER POSITION in the error.
 *
 * Architecture section: 4.2 (position-annotated messages), 4.6 (fail loudly),
 * 4.7 (test strategy).
 *
 * The categories the M2 gate names -- unbalanced parentheses, unknown field,
 * over-deep path, bad literal, type mismatch -- plus the ones that would
 * otherwise only be caught by a lexer or parser test in isolation. Everything
 * goes through AMF_ExprCompiler.compile, because that is the entry point the
 * engine will use and therefore the only error surface an admin ever sees.
 *
 * Positions are zero-based, so expression.substring(position) starts at the
 * character the message blames. Each case asserts BOTH the structured
 * position field and the rendered message, because 4.2 promises the position in
 * the message text and a caller may only ever read one of the two.
 */
@IsTest
private class AMF_ExpressionErrorTest {
    private static final String PURCHASE_REQUEST = 'Purchase_Request__c';

    /** One malformed expression, where it breaks, and what it must say. */
    private class ErrorCase {
        private String expression;
        private Integer position;
        private String fragment;

        private ErrorCase(String expression, Integer position, String fragment) {
            this.expression = expression;
            this.position = position;
            this.fragment = fragment;
        }
    }

    @IsTest
    static void unbalancedParentheses() {
        run(
            new List<ErrorCase>{
                new ErrorCase('(Amount__c > 1', 14, 'Expected \')\''),
                new ErrorCase('Amount__c > 1)', 13, 'Unexpected token \')\''),
                new ErrorCase('((Amount__c > 1)', 16, 'Expected \')\''),
                new ErrorCase('(Amount__c > 1 && (Region__c == \'APAC\')', 39, 'Expected \')\''),
                new ErrorCase('()', 1, 'Unexpected token \')\'')
            }
        );
    }

    @IsTest
    static void unknownFieldsAndRelationships() {
        run(
            new List<ErrorCase>{
                new ErrorCase('Bogus__c > 1', 0, 'Unknown field \'Bogus__c\' on Purchase_Request__c'),
                new ErrorCase('Amount__c > 1 && Bogus__c == 2', 17, 'Unknown field \'Bogus__c\''),
                new ErrorCase('Account__r.Bogus__c == \'x\'', 0, 'Unknown field \'Bogus__c\' on Account'),
                new ErrorCase('Bogus__r.Name == \'x\'', 0, 'Unknown relationship \'Bogus__r\''),
                // The lookup field, not its relationship name, cannot be hopped.
                new ErrorCase('Account__c.Name == \'x\'', 0, 'Unknown relationship \'Account__c\'')
            }
        );
    }

    @IsTest
    static void overDeepPaths() {
        // Four segments -- three relationship hops -- is the limit (M9).
        run(
            new List<ErrorCase>{
                new ErrorCase(
                    'Account__r.Owner.Manager.Profile.Name == \'x\'',
                    0,
                    'has 5 segments; the maximum is 4'
                ),
                new ErrorCase('Account__r.Owner.Manager.Manager.Profile.Name == \'x\'', 0, 'has 6 segments'),
                new ErrorCase(
                    'Amount__c > 1 && Account__r.Owner.Manager.Profile.Name == \'x\'',
                    17,
                    'has 5 segments'
                )
            }
        );
    }

    @IsTest
    static void badLiterals() {
        run(
            new List<ErrorCase>{
                new ErrorCase('Region__c == \'APAC', 13, 'Unterminated string literal'),
                new ErrorCase('CloseDate == 2026-13-01', 13, 'Invalid date literal \'2026-13-01\''),
                new ErrorCase('CloseDate == 2026-02-30', 13, 'Invalid date literal'),
                new ErrorCase('Amount__c > 1 ] 2', 14, 'Unexpected character \']\''),
                new ErrorCase('Amount__c = 1', 10, 'Unexpected character \'=\''),
                new ErrorCase('Amount__c > ', 12, 'Unexpected token end of expression')
            }
        );
    }

    @IsTest
    static void typeMismatches() {
        run(
            new List<ErrorCase>{
                new ErrorCase('Amount__c == \'APAC\'', 10, 'Cannot compare field \'Amount__c\' (CURRENCY)'),
                new ErrorCase('Region__c == 100', 10, 'Cannot compare field \'Region__c\' (PICKLIST)'),
                new ErrorCase('Matrix_Submission__c == \'yes\'', 21, 'Cannot compare'),
                new ErrorCase('Amount__c == 2026-01-31', 10, 'with a date literal'),
                new ErrorCase(
                    'Amount__c > 1 && Region__c == TRUE',
                    27,
                    'with a boolean literal'
                )
            }
        );
    }

    @IsTest
    static void operatorsAppliedToTypesThatDoNotSupportThem() {
        run(
            new List<ErrorCase>{
                new ErrorCase('Region__c > \'APAC\'', 10, 'not supported for text values'),
                new ErrorCase('Region__c <= \'APAC\'', 10, 'not supported for text values'),
                new ErrorCase('Matrix_Submission__c < TRUE', 21, 'not supported for boolean values'),
                new ErrorCase('Account__r.Name >= \'Globex\'', 16, 'not supported for text values')
            }
        );
    }

    @IsTest
    static void nonBooleanExpressions() {
        run(
            new List<ErrorCase>{
                new ErrorCase('Amount__c', 0, 'cannot stand alone as a condition'),
                new ErrorCase('\'APAC\'', 0, 'a text literal is not a Boolean'),
                new ErrorCase('NULL', 0, 'a NULL literal is not a Boolean'),
                new ErrorCase('Amount__c > 1 && Region__c', 17, 'cannot stand alone as a condition'),
                new ErrorCase('Amount__c > 1 || 5', 17, 'a numeric literal is not a Boolean')
            }
        );
    }

    @IsTest
    static void emptyExpressions() {
        run(
            new List<ErrorCase>{
                new ErrorCase('', 0, 'Expression is empty'),
                new ErrorCase('    ', 0, 'Expression is empty')
            }
        );
    }

    // -------------------------------------------------- M9's grammar, misused

    @IsTest
    static void malformedInLists() {
        run(
            new List<ErrorCase>{
                new ErrorCase('Region__c IN ()', 14, 'An IN list must name at least one value'),
                new ErrorCase('Region__c IN \'APAC\'', 13, 'Expected \'(\' after \'IN\''),
                new ErrorCase('Region__c IN (\'APAC\',)', 21, 'Unexpected token \')\''),
                new ErrorCase('Region__c IN (\'APAC\' \'EMEA\')', 21, 'Expected \',\' or \')\''),
                new ErrorCase('Region__c NOT \'APAC\'', 14, 'Expected \'IN\' after \'NOT\''),
                new ErrorCase('Region__c NOT IN (\'APAC\'', 24, 'Expected \',\' or \')\' but found end of expression'),
                new ErrorCase(
                    'Region__c IN (\'APAC\', Risk_Level__c)',
                    22,
                    'may only hold literals, not field \'Risk_Level__c\''
                )
            }
        );
    }

    @IsTest
    static void inListsAreTypedAndNeverHoldNull() {
        run(
            new List<ErrorCase>{
                // Every value must be the operand's type, and the error points at
                // the value that is not.
                new ErrorCase('Region__c IN (\'APAC\', 5)', 22, 'Cannot compare field \'Region__c\' (PICKLIST) with a numeric literal'),
                new ErrorCase('Amount__c IN (100, \'x\')', 19, 'with a text literal'),
                new ErrorCase('CloseDate IN (TODAY, \'x\')', 21, 'Cannot compare field \'CloseDate\' (DATE) with a text literal'),
                // 4.3: IN with a null operand is false. NULL in the list would
                // contradict that, so it is refused on either side.
                new ErrorCase('Region__c IN (\'APAC\', NULL)', 22, 'cannot be used with NULL'),
                new ErrorCase('NULL IN (\'APAC\')', 0, 'cannot be used with NULL'),
                new ErrorCase('Region__c NOT IN (NULL)', 18, 'test for a blank field with \'== NULL\''),
                // A set has no single value to look up.
                new ErrorCase('Channel IN (\'Email\')', 8, 'Operator \'IN\' is not supported for multi-select picklist values')
            }
        );
    }

    @IsTest
    static void containsAndStartsWithAreForText() {
        run(
            new List<ErrorCase>{
                new ErrorCase('Amount__c CONTAINS \'1\'', 10, 'Operator \'CONTAINS\' is not supported for numeric values'),
                new ErrorCase('Matrix_Submission__c STARTS_WITH \'T\'', 21, 'not supported for boolean values'),
                new ErrorCase('CloseDate CONTAINS \'2026\'', 10, 'not supported for date values'),
                new ErrorCase('Region__c CONTAINS 5', 10, 'Cannot compare field \'Region__c\' (PICKLIST) with a numeric literal'),
                new ErrorCase('Region__c CONTAINS NULL', 19, 'cannot be used with NULL'),
                new ErrorCase('NULL STARTS_WITH \'A\'', 0, 'Operator \'STARTS_WITH\' cannot be used with NULL'),
                new ErrorCase('Region__c CONTAINS', 18, 'Unexpected token end of expression'),
                new ErrorCase('Channel STARTS_WITH \'E\'', 8, 'Operator \'STARTS_WITH\' is not supported for multi-select picklist values')
            }
        );
    }

    @IsTest
    static void multiSelectPicklistsCompareOnlyWithAValueList() {
        run(
            new List<ErrorCase>{
                new ErrorCase('Channel > \'Email\'', 8, 'Operator \'>\' is not supported for multi-select picklist values'),
                new ErrorCase('Channel == 5', 11, 'can only be compared with a text literal of values separated by \';\''),
                new ErrorCase('Channel CONTAINS Name', 17, 'not field \'Name\''),
                // The empty set: a blank multi-select picklist reads NULL instead.
                new ErrorCase('Channel == \'\'', 11, 'names no values'),
                new ErrorCase('Channel CONTAINS \' ; \'', 17, 'names no values'),
                new ErrorCase('\'abc\' CONTAINS Channel', 6, 'Cannot compare a text literal with field \'Channel\' (MULTIPICKLIST)')
            }
        );
    }

    @IsTest
    static void malformedToday() {
        run(
            new List<ErrorCase>{
                new ErrorCase('CloseDate > TODAY(1.5)', 18, 'must be a whole number of days, not \'1.5\''),
                new ErrorCase('CloseDate > TODAY(36501)', 18, 'must be at most 36500 days'),
                new ErrorCase('CloseDate > TODAY(+)', 19, 'Expected a number of days in \'TODAY\''),
                new ErrorCase('CloseDate > TODAY(7', 19, 'Expected \')\' but found end of expression'),
                // TODAY is a date, and only a date.
                new ErrorCase('Amount__c > TODAY', 10, 'Cannot compare field \'Amount__c\' (CURRENCY) with TODAY'),
                new ErrorCase('TODAY', 0, 'TODAY is not a Boolean')
            }
        );
    }

    @IsTest
    static void malformedNegationsAndLogicalWords() {
        run(
            new List<ErrorCase>{
                new ErrorCase('NOT Amount__c', 4, 'field \'Amount__c\' (CURRENCY) is not a Boolean'),
                new ErrorCase('!\'APAC\'', 1, 'a text literal is not a Boolean'),
                new ErrorCase('NOT', 3, 'Unexpected token end of expression'),
                new ErrorCase('Amount__c > 1 NOT', 14, 'Unexpected token \'NOT\''),
                new ErrorCase('TRUE AND', 8, 'Unexpected token end of expression'),
                new ErrorCase('TRUE OR OR FALSE', 8, 'Unexpected token \'OR\''),
                // A word glued to another is an identifier, not an operator.
                new ErrorCase('TRUE ANDFALSE', 5, 'Unexpected token \'ANDFALSE\'')
            }
        );
    }

    @IsTest
    static void everyFailureCarriesTheSourceExpression() {
        String expression = 'Amount__c == \'APAC\'';

        try {
            AMF_ExprCompiler.compile(PURCHASE_REQUEST, expression);
            Assert.fail('This suite only holds expressions that must not compile');
        } catch (AMF_ExpressionException e) {
            Assert.areEqual(expression, e.expressionText, 'The rule text travels with the error');
            Assert.isTrue(
                e.getMessage().endsWith('at position ' + e.position),
                '4.2 fixes the message shape as "<detail> at position <n>". Got: ' + e.getMessage()
            );
        }
    }

    /**
     * Compiles each case, asserting it throws with the right position and says
     * something recognisable. Reports every failure in the table, not the first.
     *
     * @param cases The malformed expressions.
     */
    private static void run(List<ErrorCase> cases) {
        List<String> failures = new List<String>();

        for (ErrorCase testCase : cases) {
            // Dates live on Opportunity and the multi-select picklist on
            // QuickText, standard objects, rather than on fields added to the
            // pilot object only for tests (arch doc 10).
            String objectApiName = testCase.expression.contains('CloseDate')
                ? 'Opportunity'
                : testCase.expression.contains('Channel') ? 'QuickText' : PURCHASE_REQUEST;

            try {
                AMF_ExprCompiler.compile(objectApiName, testCase.expression);
                failures.add('  ' + testCase.expression + '  ->  compiled, but must not have');
            } catch (AMF_ExpressionException e) {
                if (testCase.position != e.position) {
                    failures.add(
                        '  ' +
                        testCase.expression +
                        '  ->  expected position ' +
                        testCase.position +
                        ', got ' +
                        e.position +
                        ' (' +
                        e.getMessage() +
                        ')'
                    );
                } else if (!e.getMessage().contains(testCase.fragment)) {
                    failures.add(
                        '  ' +
                        testCase.expression +
                        '  ->  message must contain "' +
                        testCase.fragment +
                        '", got: ' +
                        e.getMessage()
                    );
                } else if (!e.getMessage().contains('at position ' + testCase.position)) {
                    failures.add(
                        '  ' +
                        testCase.expression +
                        '  ->  message must render the position, got: ' +
                        e.getMessage()
                    );
                }
            }
        }

        Assert.areEqual(
            0,
            failures.size(),
            failures.size() + ' of ' + cases.size() + ' malformed cases were wrong:\n' +
            String.join(failures, '\n')
        );
    }
}
