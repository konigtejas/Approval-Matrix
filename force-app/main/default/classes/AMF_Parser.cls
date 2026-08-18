/**
 * Recursive descent over the token stream, producing the AST (4.2).
 *
 * Architecture section: 4.1 (grammar and precedence), 4.2 (pipeline).
 *
 * The MVP grammar (13.3), one method per production:
 *
 *   expression := or_expr
 *   or_expr    := and_expr ( '||' and_expr )*
 *   and_expr   := primary ( '&&' primary )*
 *   primary    := '(' expression ')' | comparison | bool_atom
 *   comparison := operand comp_op operand
 *   comp_op    := '==' | '!=' | '>' | '>=' | '<' | '<='
 *   operand    := ['-'] NUMBER | 'STRING' | DATE | TRUE | FALSE | NULL | field_path
 *   field_path := IDENT ( '.' IDENT )*
 *
 * Precedence falls out of the nesting, exactly as 4.1 requires: comparisons bind
 * tighter than '&&', which binds tighter than '||', so a || b && c parses as
 * a || (b && c).
 *
 * The parser is a pure syntax machine and asks the schema nothing. It will
 * happily build a four-segment field path or a bare Amount__c used as a boolean;
 * rejecting those is AMF_ExprCompiler's job, because both need describe
 * information. Keeping the split at exactly that line is what makes the deferred
 * 13.3 constructs additive -- adding NOT is one production and one node type, and
 * raising the path depth limit is a constant in the compiler, not a change here.
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
     *         token, an unbalanced parenthesis or trailing input -- each carrying
     *         its character position.
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
        AMF_Ast.Node left = parsePrimary();

        while (peek().type == AMF_Lexer.TokenType.LOGICAL_AND) {
            AMF_Lexer.Token operator = advance();
            left = new AMF_Ast.BinaryNode('&&', left, parsePrimary(), operator.position);
        }
        return left;
    }

    private AMF_Ast.Node parsePrimary() {
        if (peek().type == AMF_Lexer.TokenType.LPAREN) {
            advance();
            AMF_Ast.Node grouped = parseOr();

            if (peek().type != AMF_Lexer.TokenType.RPAREN) {
                throw AMF_ExpressionException.at(
                    'Expected ' + AMF_Lexer.quote(')') + ' but found ' + peek().describe(),
                    peek().position
                );
            }
            advance();
            return grouped;
        }

        AMF_Ast.Node left = parseOperand();

        // No comparison operator means the operand stands alone as the whole
        // condition -- TRUE, FALSE or a Checkbox path (4.1's bool_atom). Whether
        // it is actually boolean is a schema question, so the compiler answers it.
        if (!COMPARISON_OPERATORS.contains(peek().type)) {
            return left;
        }

        AMF_Lexer.Token operator = advance();
        return new AMF_Ast.ComparisonNode(operator.text, left, parseOperand(), operator.position);
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
            when IDENT {
                return parseFieldPath();
            }
            when else {
                throw unexpected(token);
            }
        }
    }

    /**
     * IDENT ( '.' IDENT )*, to any depth. The depth limit is a schema concern and
     * belongs to the compiler (4.4), so an over-deep path is reported there with
     * the object it was too deep for.
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
