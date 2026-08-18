/**
 * Unit test for AMF_Lexer: token types, decoded literal values, and the
 * character positions every later error message depends on.
 *
 * Architecture section: 4.1 (grammar), 4.2 (position-annotated messages).
 *
 * Positions are zero-based indexes into the source string, so a position
 * assertion here is also an assertion that expression.substring(position) lands
 * on the token the message is talking about.
 */
@IsTest
private class AMF_LexerTest {
    @IsTest
    static void tokenisesAWholeRuleWithPositions() {
        String expression = 'Amount__c > 100000 && Region__c == \'APAC\'';
        List<AMF_Lexer.Token> tokens = AMF_Lexer.tokenize(expression);

        Assert.areEqual(8, tokens.size(), 'Seven tokens plus END_OF_INPUT');
        assertToken(tokens[0], AMF_Lexer.TokenType.IDENT, 'Amount__c', 0);
        assertToken(tokens[1], AMF_Lexer.TokenType.GT, '>', 10);
        assertToken(tokens[2], AMF_Lexer.TokenType.NUMBER_LITERAL, '100000', 12);
        assertToken(tokens[3], AMF_Lexer.TokenType.LOGICAL_AND, '&&', 19);
        assertToken(tokens[4], AMF_Lexer.TokenType.IDENT, 'Region__c', 22);
        assertToken(tokens[5], AMF_Lexer.TokenType.EQ, '==', 32);
        assertToken(tokens[6], AMF_Lexer.TokenType.STRING_LITERAL, '\'APAC\'', 35);
        Assert.areEqual(
            expression.length(),
            tokens[7].position,
            'END_OF_INPUT sits one past the last character, which is where "unexpected end" points'
        );
        Assert.areEqual('APAC', tokens[6].value, 'A string token carries its decoded value');
    }

    @IsTest
    static void everyOperatorLexesAsOneToken() {
        Map<String, AMF_Lexer.TokenType> expected = new Map<String, AMF_Lexer.TokenType>{
            '==' => AMF_Lexer.TokenType.EQ,
            '!=' => AMF_Lexer.TokenType.NEQ,
            '>' => AMF_Lexer.TokenType.GT,
            '>=' => AMF_Lexer.TokenType.GTE,
            '<' => AMF_Lexer.TokenType.LT,
            '<=' => AMF_Lexer.TokenType.LTE,
            '&&' => AMF_Lexer.TokenType.LOGICAL_AND,
            '||' => AMF_Lexer.TokenType.LOGICAL_OR,
            '(' => AMF_Lexer.TokenType.LPAREN,
            ')' => AMF_Lexer.TokenType.RPAREN,
            ',' => AMF_Lexer.TokenType.COMMA,
            '-' => AMF_Lexer.TokenType.MINUS
        };

        for (String symbol : expected.keySet()) {
            List<AMF_Lexer.Token> tokens = AMF_Lexer.tokenize(symbol);
            Assert.areEqual(2, tokens.size(), symbol + ' is one token plus END_OF_INPUT');
            assertToken(tokens[0], expected.get(symbol), symbol, 0);
        }
    }

    @IsTest
    static void keywordsAreCaseInsensitiveAndCarryTheirValue() {
        Map<String, Object> expected = new Map<String, Object>{
            'TRUE' => true,
            'true' => true,
            'True' => true,
            'FALSE' => false,
            'false' => false,
            'NULL' => null,
            'null' => null
        };

        for (String word : expected.keySet()) {
            AMF_Lexer.Token token = AMF_Lexer.tokenize(word)[0];
            Assert.areEqual(expected.get(word), token.value, word + ' decodes to its literal value');
            Assert.areEqual(word, token.text, 'The raw spelling is kept for error messages');
        }
    }

    @IsTest
    static void identifiersCoverApiNameSpelling() {
        List<AMF_Lexer.Token> tokens = AMF_Lexer.tokenize('Account__r.Name');

        assertToken(tokens[0], AMF_Lexer.TokenType.IDENT, 'Account__r', 0);
        assertToken(tokens[1], AMF_Lexer.TokenType.DOT, '.', 10);
        assertToken(tokens[2], AMF_Lexer.TokenType.IDENT, 'Name', 11);
        Assert.areEqual(
            AMF_Lexer.TokenType.END_OF_INPUT,
            tokens[3].type,
            'A dot between identifiers must not be swallowed into a number'
        );
    }

    @IsTest
    static void numbersLexWithAndWithoutAFraction() {
        Assert.areEqual(100, AMF_Lexer.tokenize('100')[0].value, 'Whole numbers');
        Assert.areEqual(100.50, AMF_Lexer.tokenize('100.50')[0].value, 'Decimals');
        Assert.areEqual(0.5, AMF_Lexer.tokenize('0.5')[0].value, 'Leading zero');

        // A minus is its own token; the parser folds it into the literal. That is
        // what leaves room for arithmetic to be added without re-lexing.
        List<AMF_Lexer.Token> negative = AMF_Lexer.tokenize('-5');
        assertToken(negative[0], AMF_Lexer.TokenType.MINUS, '-', 0);
        assertToken(negative[1], AMF_Lexer.TokenType.NUMBER_LITERAL, '5', 1);
    }

    @IsTest
    static void datesLexAheadOfNumbers() {
        AMF_Lexer.Token token = AMF_Lexer.tokenize('2026-01-31')[0];

        Assert.areEqual(AMF_Lexer.TokenType.DATE_LITERAL, token.type, 'YYYY-MM-DD is one date, not 2026 minus 1 minus 31');
        Assert.areEqual(Date.newInstance(2026, 1, 31), token.value, 'And it decodes to a real Date');
        Assert.areEqual(
            Date.newInstance(2024, 2, 29),
            AMF_Lexer.tokenize('2024-02-29')[0].value,
            'A leap day is a valid date'
        );
    }

    @IsTest
    static void aDigitRunThatIsNotADateStaysANumber() {
        // 20260131 has no dashes; 2026-1-31 is not the fixed-width form.
        Assert.areEqual(
            AMF_Lexer.TokenType.NUMBER_LITERAL,
            AMF_Lexer.tokenize('20260131')[0].type,
            'No dashes, no date'
        );
        Assert.areEqual(
            AMF_Lexer.TokenType.NUMBER_LITERAL,
            AMF_Lexer.tokenize('2026-1-31')[0].type,
            'Only the fixed-width YYYY-MM-DD form is a date literal'
        );
    }

    @IsTest
    static void stringsHandleEscapes() {
        Assert.areEqual('APAC', AMF_Lexer.tokenize('\'APAC\'')[0].value, 'Plain');
        Assert.areEqual('', AMF_Lexer.tokenize('\'\'')[0].value, 'Empty');
        Assert.areEqual('a b', AMF_Lexer.tokenize('\'a b\'')[0].value, 'Spaces are content inside quotes');
        Assert.areEqual(
            'O\'Brien',
            AMF_Lexer.tokenize('\'O\\\'Brien\'')[0].value,
            'An escaped quote is content, not a terminator'
        );
        Assert.areEqual(
            'a\\b',
            AMF_Lexer.tokenize('\'a\\\\b\'')[0].value,
            'An escaped backslash is one backslash'
        );
    }

    @IsTest
    static void whitespaceIsSkippedButPositionsStayAbsolute() {
        List<AMF_Lexer.Token> tokens = AMF_Lexer.tokenize('  \t\n Amount__c \t > \n 100 ');

        assertToken(tokens[0], AMF_Lexer.TokenType.IDENT, 'Amount__c', 5);
        assertToken(tokens[1], AMF_Lexer.TokenType.GT, '>', 17);
        assertToken(tokens[2], AMF_Lexer.TokenType.NUMBER_LITERAL, '100', 21);
    }

    @IsTest
    static void emptyAndNullInputYieldOnlyEndOfInput() {
        for (String source : new List<String>{ '', null }) {
            List<AMF_Lexer.Token> tokens = AMF_Lexer.tokenize(source);
            Assert.areEqual(1, tokens.size(), 'Nothing to lex');
            Assert.areEqual(AMF_Lexer.TokenType.END_OF_INPUT, tokens[0].type, 'But always an END_OF_INPUT');
        }
    }

    @IsTest
    static void tokensDescribeThemselvesForErrorMessages() {
        List<AMF_Lexer.Token> tokens = AMF_Lexer.tokenize(')');

        Assert.areEqual('\')\'', tokens[0].describe(), 'A real token is quoted, as 4.2 spells it');
        Assert.areEqual('end of expression', tokens[1].describe(), 'END_OF_INPUT reads as prose');
    }

    // ------------------------------------------------------- lexical failures

    @IsTest
    static void unexpectedCharactersReportTheirPosition() {
        Map<String, Integer> expected = new Map<String, Integer>{
            'Amount__c ] 5' => 10,
            'Amount__c # 5' => 10,
            // A lone & or | is not half of an operator, it is a bad character.
            'Amount__c & 5' => 10,
            'Amount__c | 5' => 10,
            // = is the classic slip for ==, and ! for the deferred NOT.
            'Amount__c = 5' => 10,
            '!Amount__c' => 0
        };

        for (String expression : expected.keySet()) {
            try {
                AMF_Lexer.tokenize(expression);
                Assert.fail(expression + ' must not lex');
            } catch (AMF_ExpressionException e) {
                Assert.areEqual(expected.get(expression), e.position, 'Wrong position for ' + expression);
                Assert.isTrue(
                    e.getMessage().contains('Unexpected character') &&
                    e.getMessage().contains('at position ' + expected.get(expression)),
                    'The message must carry the position too. Got: ' + e.getMessage()
                );
            }
        }
    }

    @IsTest
    static void unterminatedStringReportsTheOpeningQuote() {
        try {
            AMF_Lexer.tokenize('Region__c == \'APAC');
            Assert.fail('An unterminated string must not lex');
        } catch (AMF_ExpressionException e) {
            Assert.areEqual(13, e.position, 'The useful position is where the string started');
            Assert.isTrue(e.getMessage().contains('Unterminated string literal'), e.getMessage());
        }
    }

    @IsTest
    static void impossibleDatesAreRejectedAtTheirPosition() {
        Map<String, Integer> expected = new Map<String, Integer>{
            'CloseDate == 2026-13-01' => 13,
            'CloseDate == 2026-02-30' => 13,
            'CloseDate == 2026-00-10' => 13,
            'CloseDate == 2026-01-00' => 13,
            'CloseDate == 2025-02-29' => 13
        };

        for (String expression : expected.keySet()) {
            try {
                AMF_Lexer.tokenize(expression);
                Assert.fail(expression + ' is not a real date and must not lex');
            } catch (AMF_ExpressionException e) {
                Assert.areEqual(expected.get(expression), e.position, 'Wrong position for ' + expression);
                Assert.isTrue(e.getMessage().contains('Invalid date literal'), e.getMessage());
            }
        }
    }

    private static void assertToken(
        AMF_Lexer.Token token,
        AMF_Lexer.TokenType type,
        String text,
        Integer position
    ) {
        Assert.areEqual(type, token.type, 'Wrong type for ' + text);
        Assert.areEqual(text, token.text, 'Wrong text at position ' + position);
        Assert.areEqual(position, token.position, 'Wrong position for ' + text);
    }
}
