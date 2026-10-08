/**
 * Recursive descent over the token stream, producing the AST (4.2).
 *
 * Architecture section: 4.1 (grammar and precedence), 4.2 (pipeline).
 *
 * The grammar, one method per production:
 *
 *   expression := or_expr
 *   or_expr    := and_expr ( ('||' | OR) and_expr )*
 *   and_expr   := unary ( ('&&' | AND) unary )*
 *   unary      := ('!' | NOT) unary | primary
 *   primary    := '(' expression ')' | comparison | bool_atom
 *   comparison := operand comp_op operand
 *               | operand [NOT] IN list
 *               | operand (CONTAINS | STARTS_WITH) operand
 *   comp_op    := '==' | '!=' | '>' | '>=' | '<' | '<='
 *   list       := '(' literal ( ',' literal )* ')'
 *   operand    := literal | field_path
 *   literal    := ['-'] NUMBER | 'STRING' | DATE | TRUE | FALSE | NULL | today
 *   today      := TODAY [ '(' [ ['+' | '-'] NUMBER ] ')' ]
 *   field_path := IDENT ( '.' IDENT )*
 *
 * Precedence falls out of the nesting, exactly as 4.1 requires: comparisons bind
 * tighter than '&&', which binds tighter than '||', so a || b && c parses as
 * a || (b && c). NOT binds tightest of the logical operators, and its operand is
 * a whole unary -- which includes a whole comparison -- so NOT a == b && c is
 * (NOT (a == b)) && c. That is the reading 4.1's productions give; its prose
 * ("NOT binds tightest, then comparisons") cannot mean (NOT a) == b, because NOT
 * applies only to a Boolean (docs/decisions.md, 2026-10-08).
 *
 * The parser is a pure syntax machine and asks the schema nothing. It will
 * happily build a six-segment field path or a bare Amount__c used as a boolean;
 * rejecting those is AMF_ExprCompiler's job, because both need describe
 * information. Operators are emitted in one canonical spelling (AMF_Ast's
 * header), so the compiler and evaluator never see how the admin typed them.
 */
public class AMF_Parser {
    private static final Set<AMF_Lexer.TokenType> COMPARISON_OPERATORS = new Set<AMF_Lexer.TokenType>{
        AMF_Lexer.TokenType.EQ,
        AMF_Lexer.TokenType.NEQ,
        AMF_Lexer.TokenType.GT,
        AMF_Lexer.TokenType.GTE,
        AMF_Lexer.TokenType.LT,
        AMF_Lexer.TokenType.LTE
    };

    /**
     * TODAY(n) is a date offset in days. Beyond a century either way it is a
     * typo, not a rule -- and Apex dates end in the year 4000 -- so a larger
     * offset is a compile error rather than an evaluation-time failure.
     */
    @TestVisible
    private static final Integer MAX_TODAY_OFFSET_DAYS = 36500;

    private final List<AMF_Lexer.Token> tokens;
    private Integer index = 0;

    private AMF_Parser(List<AMF_Lexer.Token> tokens) {
        this.tokens = tokens;
    }

    /**
     * Lexes and parses in one step.
     *
     * @param expression Raw Expression__c text.
     * @return The root of the AST. Never null.
     * @throws AMF_ExpressionException On an empty expression, an unexpected
     *         token, an unbalanced parenthesis, a malformed list or TODAY, or
     *         trailing input -- each carrying its character position.
     */
    public static AMF_Ast.Node parse(String expression) {
        if (String.isBlank(expression)) {
            throw AMF_ExpressionException.at('Expression is empty', 0);
        }

        AMF_Parser parser = new AMF_Parser(AMF_Lexer.tokenize(expression));
        AMF_Ast.Node root = parser.parseOr();

        // Anything left over is the classic 4.2 example: a stray closing bracket
        // that parses fine right up to the point where it cannot.
        if (parser.peek().type != AMF_Lexer.TokenType.END_OF_INPUT) {
            throw unexpected(parser.peek());
        }
        return root;
    }

    private AMF_Ast.Node parseOr() {
        AMF_Ast.Node left = parseAnd();

        while (peek().type == AMF_Lexer.TokenType.LOGICAL_OR) {
            AMF_Lexer.Token operator = advance();
            left = new AMF_Ast.BinaryNode('||', left, parseAnd(), operator.position);
        }
        return left;
    }

    private AMF_Ast.Node parseAnd() {
        AMF_Ast.Node left = parseUnary();

        while (peek().type == AMF_Lexer.TokenType.LOGICAL_AND) {
            AMF_Lexer.Token operator = advance();
            left = new AMF_Ast.BinaryNode('&&', left, parseUnary(), operator.position);
        }
        return left;
    }

    private AMF_Ast.Node parseUnary() {
        if (peek().type == AMF_Lexer.TokenType.LOGICAL_NOT) {
            AMF_Lexer.Token operator = advance();
            return new AMF_Ast.UnaryNode('!', parseUnary(), operator.position);
        }
        return parsePrimary();
    }

    private AMF_Ast.Node parsePrimary() {
        if (peek().type == AMF_Lexer.TokenType.LPAREN) {
            advance();
            AMF_Ast.Node grouped = parseOr();
            expect(AMF_Lexer.TokenType.RPAREN, ')');
            return grouped;
        }

        AMF_Ast.Node left = parseOperand();
        AMF_Lexer.Token next = peek();

        if (COMPARISON_OPERATORS.contains(next.type)) {
            advance();
            return new AMF_Ast.ComparisonNode(next.text, left, parseOperand(), next.position);
        }

        switch on next.type {
            when IN_KEYWORD {
                advance();
                return new AMF_Ast.ComparisonNode('IN', left, parseList(next), next.position);
            }
            when LOGICAL_NOT {
                // After an operand, NOT can only begin NOT IN.
                advance();
                if (peek().type != AMF_Lexer.TokenType.IN_KEYWORD) {
                    throw AMF_ExpressionException.at(
                        'Expected ' + AMF_Lexer.quote('IN') + ' after ' + next.describe() + ' but found ' +
                        peek().describe(),
                        peek().position
                    );
                }
                AMF_Lexer.Token inToken = advance();
                return new AMF_Ast.ComparisonNode('NOT IN', left, parseList(inToken), next.position);
            }
            when CONTAINS_KEYWORD {
                advance();
                return new AMF_Ast.ComparisonNode('CONTAINS', left, parseOperand(), next.position);
            }
            when STARTS_WITH_KEYWORD {
                advance();
                return new AMF_Ast.ComparisonNode('STARTS_WITH', left, parseOperand(), next.position);
            }
            when else {
                // No operator means the operand stands alone as the whole
                // condition -- TRUE, FALSE or a Checkbox path (4.1's bool_atom).
                // Whether it is actually boolean is a schema question, so the
                // compiler answers it.
                return left;
            }
        }
    }

    /**
     * '(' literal ( ',' literal )* ')'. A list holds literals only (4.1): a field
     * path in it is refused here, by name, rather than parsed and rejected later.
     *
     * @param operator The IN token, for the message when no '(' follows it.
     */
    private AMF_Ast.ListNode parseList(AMF_Lexer.Token operator) {
        if (peek().type != AMF_Lexer.TokenType.LPAREN) {
            throw AMF_ExpressionException.at(
                'Expected ' + AMF_Lexer.quote('(') + ' after ' + operator.describe() + ' but found ' +
                peek().describe(),
                peek().position
            );
        }
        AMF_Lexer.Token open = advance();

        if (peek().type == AMF_Lexer.TokenType.RPAREN) {
            throw AMF_ExpressionException.at('An IN list must name at least one value', peek().position);
        }

        List<AMF_Ast.Node> items = new List<AMF_Ast.Node>();
        while (true) {
            AMF_Ast.Node item = parseOperand();
            if (item instanceof AMF_Ast.FieldNode) {
                throw AMF_ExpressionException.at(
                    'An IN list may only hold literals, not field ' +
                    AMF_Lexer.quote(((AMF_Ast.FieldNode) item).path),
                    item.position
                );
            }
            items.add(item);

            if (peek().type != AMF_Lexer.TokenType.COMMA) {
                break;
            }
            advance();
        }

        if (peek().type != AMF_Lexer.TokenType.RPAREN) {
            throw AMF_ExpressionException.at(
                'Expected ' + AMF_Lexer.quote(',') + ' or ' + AMF_Lexer.quote(')') + ' but found ' +
                peek().describe(),
                peek().position
            );
        }
        advance();
        return new AMF_Ast.ListNode(items, open.position);
    }

    private AMF_Ast.Node parseOperand() {
        AMF_Lexer.Token token = peek();

        switch on token.type {
            when MINUS {
                advance();
                if (peek().type != AMF_Lexer.TokenType.NUMBER_LITERAL) {
                    throw AMF_ExpressionException.at(
                        'Expected a number after ' + AMF_Lexer.quote('-') + ' but found ' + peek().describe(),
                        peek().position
                    );
                }
                AMF_Lexer.Token numberToken = advance();
                return new AMF_Ast.LiteralNode(
                    -((Decimal) numberToken.value),
                    AMF_Ast.ValueType.NUMERIC,
                    token.position
                );
            }
            when NUMBER_LITERAL {
                advance();
                return new AMF_Ast.LiteralNode(token.value, AMF_Ast.ValueType.NUMERIC, token.position);
            }
            when STRING_LITERAL {
                advance();
                return new AMF_Ast.LiteralNode(token.value, AMF_Ast.ValueType.TEXT, token.position);
            }
            when DATE_LITERAL {
                advance();
                return new AMF_Ast.LiteralNode(token.value, AMF_Ast.ValueType.DATE_VALUE, token.position);
            }
            when TRUE_LITERAL, FALSE_LITERAL {
                advance();
                return new AMF_Ast.LiteralNode(token.value, AMF_Ast.ValueType.BOOLEAN_VALUE, token.position);
            }
            when NULL_LITERAL {
                advance();
                return new AMF_Ast.LiteralNode(token.position);
            }
            when TODAY_KEYWORD {
                return parseToday();
            }
            when IDENT {
                return parseFieldPath();
            }
            when else {
                throw unexpected(token);
            }
        }
    }

    /**
     * TODAY, TODAY(), TODAY(n), TODAY(+n) or TODAY(-n): n whole days from today.
     * TODAY() is accepted because a formula author types it by reflex and it is
     * unambiguous; it means TODAY.
     */
    private AMF_Ast.TodayNode parseToday() {
        AMF_Lexer.Token today = advance();

        if (peek().type != AMF_Lexer.TokenType.LPAREN) {
            return new AMF_Ast.TodayNode(0, today.position);
        }
        advance();

        if (peek().type == AMF_Lexer.TokenType.RPAREN) {
            advance();
            return new AMF_Ast.TodayNode(0, today.position);
        }

        Integer sign = 1;
        if (peek().type == AMF_Lexer.TokenType.PLUS) {
            advance();
        } else if (peek().type == AMF_Lexer.TokenType.MINUS) {
            advance();
            sign = -1;
        }

        if (peek().type != AMF_Lexer.TokenType.NUMBER_LITERAL) {
            throw AMF_ExpressionException.at(
                'Expected a number of days in ' + today.describe() + ' but found ' + peek().describe(),
                peek().position
            );
        }
        AMF_Lexer.Token days = advance();

        if (days.text.contains('.')) {
            throw AMF_ExpressionException.at(
                'The offset in ' + today.describe() + ' must be a whole number of days, not ' + days.describe(),
                days.position
            );
        }
        Decimal magnitude = (Decimal) days.value;
        if (magnitude > MAX_TODAY_OFFSET_DAYS) {
            throw AMF_ExpressionException.at(
                'The offset in ' + today.describe() + ' must be at most ' + MAX_TODAY_OFFSET_DAYS + ' days',
                days.position
            );
        }

        expect(AMF_Lexer.TokenType.RPAREN, ')');
        return new AMF_Ast.TodayNode(sign * magnitude.intValue(), today.position);
    }

    /**
     * IDENT ( '.' IDENT )*, to any depth. The depth limit is a schema concern and
     * belongs to the compiler (4.4), so an over-deep path is reported there with
     * the limit it broke.
     */
    private AMF_Ast.Node parseFieldPath() {
        AMF_Lexer.Token first = advance();
        List<String> segments = new List<String>{ first.text };

        while (peek().type == AMF_Lexer.TokenType.DOT) {
            advance();
            if (peek().type != AMF_Lexer.TokenType.IDENT) {
                throw AMF_ExpressionException.at(
                    'Expected a field name after ' + AMF_Lexer.quote('.') + ' but found ' + peek().describe(),
                    peek().position
                );
            }
            segments.add(advance().text);
        }

        return new AMF_Ast.FieldNode(segments, first.position);
    }

    private void expect(AMF_Lexer.TokenType type, String spelling) {
        if (peek().type != type) {
            throw AMF_ExpressionException.at(
                'Expected ' + AMF_Lexer.quote(spelling) + ' but found ' + peek().describe(),
                peek().position
            );
        }
        advance();
    }

    private static AMF_ExpressionException unexpected(AMF_Lexer.Token token) {
        return AMF_ExpressionException.at('Unexpected token ' + token.describe(), token.position);
    }

    private AMF_Lexer.Token peek() {
        return tokens[index];
    }

    private AMF_Lexer.Token advance() {
        return tokens[index++];
    }
}
