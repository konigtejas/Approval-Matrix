/**
 * Expression text to token stream, tracking the character position of every
 * token so later stages can point at the character that broke (4.2).
 *
 * Architecture section: 4.1 (grammar), 4.2 (pipeline), 13.3 (reduced MVP set).
 *
 * The lexer knows nothing about grammar -- it does not know that '&&' joins two
 * comparisons, only that '&&' is one token. That separation is what keeps the
 * deferred 13.3 constructs additive: IN, CONTAINS, STARTS_WITH and NOT become
 * entries in KEYWORDS, and TODAY(n) reuses the identifier and paren tokens that
 * already exist. Nothing here is written around their absence -- a word that is
 * not in KEYWORDS is simply an identifier, which is what makes the table the
 * only thing a later phase touches.
 *
 * Word forms of the logical operators are deliberately NOT accepted in the MVP.
 * Arch doc 4.1 allows an admin to write AND for '&&', but 13.3 and CLAUDE.md
 * both list only the symbols, and CLAUDE.md is the override document
 * (docs/decisions.md, 2026-08-18). 'A AND B' therefore fails at the parser with a
 * positioned error rather than routing on a half-read expression, and enabling
 * the word forms later is two entries in KEYWORDS.
 */
public class AMF_Lexer {
    /**
     * DATE_LITERAL is matched ahead of NUMBER_LITERAL because 2026-01-31 starts
     * with digits and would otherwise lex as 2026 followed by two negations.
     */
    public enum TokenType {
        NUMBER_LITERAL,
        STRING_LITERAL,
        DATE_LITERAL,
        TRUE_LITERAL,
        FALSE_LITERAL,
        NULL_LITERAL,
        IDENT,
        LOGICAL_AND,
        LOGICAL_OR,
        EQ,
        NEQ,
        GT,
        GTE,
        LT,
        LTE,
        LPAREN,
        RPAREN,
        DOT,
        COMMA,
        MINUS,
        END_OF_INPUT
    }

    /**
     * One lexeme. text is always the raw source spelling, which is what error
     * messages quote; value carries the decoded literal for the parser, so the
     * parser never re-parses a number or unescapes a string.
     */
    public class Token {
        public TokenType type;
        public String text;
        public Object value;
        public Integer position;

        private Token(TokenType type, String text, Object value, Integer position) {
            this.type = type;
            this.text = text;
            this.value = value;
            this.position = position;
        }

        /**
         * How this token is named in an error message.
         *
         * @return A human-readable rendering, quoted for real tokens.
         */
        public String describe() {
            return this.type == TokenType.END_OF_INPUT ? 'end of expression' : quote(this.text);
        }
    }

    /**
     * Case-insensitive reserved words. Everything else that looks like a word is
     * an identifier -- see the class header on why this table is the extension
     * point for the deferred grammar.
     */
    private static final Map<String, TokenType> KEYWORDS = new Map<String, TokenType>{
        'TRUE' => TokenType.TRUE_LITERAL,
        'FALSE' => TokenType.FALSE_LITERAL,
        'NULL' => TokenType.NULL_LITERAL
    };

    private static final String DIGITS = '0123456789';
    private static final String LETTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
    private static final String QUOTE = '\'';
    private static final String BACKSLASH = '\\';

    private final String source;
    private final Integer length;
    private Integer pos = 0;

    private AMF_Lexer(String source) {
        this.source = source;
        this.length = source.length();
    }

    /**
     * Wraps a lexeme in single quotes for an error message.
     *
     * @param text The raw lexeme.
     * @return The lexeme, quoted.
     */
    public static String quote(String text) {
        return QUOTE + text + QUOTE;
    }

    /**
     * @param expression Raw Expression__c text.
     * @return Every token in order, always ending in END_OF_INPUT. Never empty.
     * @throws AMF_ExpressionException On any character the grammar cannot start a
     *         token with, on an unterminated string, and on a date literal that is
     *         not a real calendar date -- each carrying its character position.
     */
    public static List<Token> tokenize(String expression) {
        return new AMF_Lexer(expression == null ? '' : expression).scan();
    }

    private List<Token> scan() {
        List<Token> tokens = new List<Token>();

        while (pos < length) {
            String c = charAt(pos);

            if (isWhitespace(c)) {
                pos++;
                continue;
            }
            if (isDigit(c)) {
                tokens.add(readNumberOrDate());
                continue;
            }
            if (isIdentStart(c)) {
                tokens.add(readWord());
                continue;
            }
            if (c == QUOTE) {
                tokens.add(readString());
                continue;
            }
            tokens.add(readOperator());
        }

        tokens.add(new Token(TokenType.END_OF_INPUT, '', null, length));
        return tokens;
    }

    /**
     * A run of digits is a date literal when it is spelled YYYY-MM-DD and is not
     * glued to a further identifier character; otherwise it is a number, with an
     * optional fractional part.
     */
    private Token readNumberOrDate() {
        Integer start = pos;

        if (looksLikeDate(start)) {
            return readDate(start);
        }

        while (pos < length && isDigit(charAt(pos))) {
            pos++;
        }
        // A '.' only continues the number when a digit follows it, so that
        // Account__r.Name keeps its dot and 5. does not silently become 5.0.
        if (pos + 1 < length && charAt(pos) == '.' && isDigit(charAt(pos + 1))) {
            pos++;
            while (pos < length && isDigit(charAt(pos))) {
                pos++;
            }
        }

        String text = source.substring(start, pos);
        return new Token(TokenType.NUMBER_LITERAL, text, Decimal.valueOf(text), start);
    }

    private Boolean looksLikeDate(Integer start) {
        if (start + 10 > length) {
            return false;
        }
        if (!Pattern.matches('[0-9]{4}-[0-9]{2}-[0-9]{2}', source.substring(start, start + 10))) {
            return false;
        }
        // 2026-01-311 is a malformed literal, not a date followed by a 1.
        return start + 10 >= length || !isIdentPart(charAt(start + 10));
    }

    private Token readDate(Integer start) {
        String text = source.substring(start, start + 10);
        Integer year = Integer.valueOf(text.substring(0, 4));
        Integer month = Integer.valueOf(text.substring(5, 7));
        Integer day = Integer.valueOf(text.substring(8, 10));

        if (year < 1 || month < 1 || month > 12 || day < 1 || day > Date.daysInMonth(year, month)) {
            throw AMF_ExpressionException.at('Invalid date literal ' + quote(text), start);
        }

        pos = start + 10;
        return new Token(TokenType.DATE_LITERAL, text, Date.newInstance(year, month, day), start);
    }

    private Token readWord() {
        Integer start = pos;
        while (pos < length && isIdentPart(charAt(pos))) {
            pos++;
        }

        String text = source.substring(start, pos);
        TokenType keyword = KEYWORDS.get(text.toUpperCase());

        if (keyword == TokenType.TRUE_LITERAL) {
            return new Token(keyword, text, true, start);
        }
        if (keyword == TokenType.FALSE_LITERAL) {
            return new Token(keyword, text, false, start);
        }
        if (keyword == TokenType.NULL_LITERAL) {
            return new Token(keyword, text, null, start);
        }
        return new Token(TokenType.IDENT, text, null, start);
    }

    /**
     * Single-quoted, with escaped quote and escaped backslash. Any other
     * backslash is a literal backslash, so an admin need not double one.
     */
    private Token readString() {
        Integer start = pos;
        pos++;

        String value = '';
        while (pos < length) {
            String c = charAt(pos);

            if (c == BACKSLASH && pos + 1 < length) {
                String next = charAt(pos + 1);
                if (next == QUOTE || next == BACKSLASH) {
                    value += next;
                    pos += 2;
                    continue;
                }
            }
            if (c == QUOTE) {
                pos++;
                return new Token(TokenType.STRING_LITERAL, source.substring(start, pos), value, start);
            }
            value += c;
            pos++;
        }

        throw AMF_ExpressionException.at('Unterminated string literal', start);
    }

    private Token readOperator() {
        Integer start = pos;
        String c = charAt(pos);
        String pair = pos + 1 < length ? source.substring(pos, pos + 2) : null;

        if (pair == '&&') {
            pos += 2;
            return new Token(TokenType.LOGICAL_AND, pair, null, start);
        }
        if (pair == '||') {
            pos += 2;
            return new Token(TokenType.LOGICAL_OR, pair, null, start);
        }
        if (pair == '==') {
            pos += 2;
            return new Token(TokenType.EQ, pair, null, start);
        }
        if (pair == '!=') {
            pos += 2;
            return new Token(TokenType.NEQ, pair, null, start);
        }
        if (pair == '>=') {
            pos += 2;
            return new Token(TokenType.GTE, pair, null, start);
        }
        if (pair == '<=') {
            pos += 2;
            return new Token(TokenType.LTE, pair, null, start);
        }

        pos++;
        if (c == '>') {
            return new Token(TokenType.GT, c, null, start);
        }
        if (c == '<') {
            return new Token(TokenType.LT, c, null, start);
        }
        if (c == '(') {
            return new Token(TokenType.LPAREN, c, null, start);
        }
        if (c == ')') {
            return new Token(TokenType.RPAREN, c, null, start);
        }
        if (c == '.') {
            return new Token(TokenType.DOT, c, null, start);
        }
        if (c == ',') {
            return new Token(TokenType.COMMA, c, null, start);
        }
        if (c == '-') {
            return new Token(TokenType.MINUS, c, null, start);
        }

        throw AMF_ExpressionException.at('Unexpected character ' + quote(c), start);
    }

    private String charAt(Integer index) {
        return source.substring(index, index + 1);
    }

    private Boolean isWhitespace(String c) {
        return c == ' ' || c == '\t' || c == '\n' || c == '\r';
    }

    private Boolean isDigit(String c) {
        return DIGITS.contains(c);
    }

    private Boolean isIdentStart(String c) {
        return LETTERS.contains(c);
    }

    private Boolean isIdentPart(String c) {
        return LETTERS.contains(c) || DIGITS.contains(c) || c == '_';
    }
}
