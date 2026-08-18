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
        run(
            new List<ErrorCase>{
                new ErrorCase(
                    'Account__r.Owner.Alias == \'x\'',
                    0,
                    'has 3 segments; the maximum is 2'
                ),
                new ErrorCase('Account__r.Owner.Profile.Name == \'x\'', 0, 'has 4 segments'),
                new ErrorCase('Amount__c > 1 && Account__r.Owner.Alias == \'x\'', 17, 'has 3 segments')
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

    @IsTest
    static void deferredGrammarFailsLoudlyRatherThanSilently() {
        // 13.3 defers IN, CONTAINS, STARTS_WITH, NOT and TODAY(n). None of them
        // is special-cased anywhere -- they simply are not in the keyword table,
        // so they arrive here as ordinary identifiers and fail as such. What
        // matters for 4.6 is that each one is a positioned error and not a
        // silent false, and each will start working the day it is added.
        run(
            new List<ErrorCase>{
                new ErrorCase('Region__c IN (\'APAC\', \'EMEA\')', 10, 'Unexpected token \'IN\''),
                new ErrorCase('Region__c CONTAINS \'AP\'', 10, 'Unexpected token \'CONTAINS\''),
                // NOT is not a keyword yet, so it arrives as an ordinary
                // identifier and the failure lands on the token after it.
                new ErrorCase('NOT Matrix_Submission__c', 4, 'Unexpected token \'Matrix_Submission__c\''),
                new ErrorCase('!Matrix_Submission__c', 0, 'Unexpected character \'!\''),
                new ErrorCase('TRUE AND FALSE', 5, 'Unexpected token \'AND\''),
                new ErrorCase('TRUE OR FALSE', 5, 'Unexpected token \'OR\'')
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
            String objectApiName = testCase.expression.contains('CloseDate')
                ? 'Opportunity'
                : PURCHASE_REQUEST;

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
