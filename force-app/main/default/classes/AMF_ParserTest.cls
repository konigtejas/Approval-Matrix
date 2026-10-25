/**
 * Unit test for AMF_Parser: the shape of the tree, and the precedence 4.1
 * requires.
 *
 * Architecture section: 4.1 (grammar and precedence), 4.2 (node types).
 *
 * Asserted on the AST rather than on an evaluation result, because precedence is
 * a structural property: TRUE || FALSE && FALSE and (TRUE || FALSE) && FALSE
 * both evaluate to something, and only the tree says which one the parser built.
 * No schema is involved -- the parser never asks describe anything.
 */
@IsTest
private class AMF_ParserTest {
    @IsTest
    static void comparisonBecomesAComparisonNode() {
        AMF_Ast.ComparisonNode node = (AMF_Ast.ComparisonNode) AMF_Parser.parse('Amount__c > 100000');

        Assert.areEqual('>', node.operator, 'The operator is kept as written');
        Assert.areEqual(10, node.position, 'A comparison is positioned at its operator');
        Assert.areEqual(
            new List<String>{ 'Amount__c' },
            ((AMF_Ast.FieldNode) node.left).segments,
            'The left operand is the field path'
        );
        Assert.areEqual(100000, ((AMF_Ast.LiteralNode) node.right).value, 'The right operand is the literal');
    }

    @IsTest
    static void orBindsLoosestSoAndGroupsFirst() {
        // a || b && c  must parse as  a || (b && c).
        AMF_Ast.BinaryNode root = (AMF_Ast.BinaryNode) AMF_Parser.parse('TRUE || FALSE && FALSE');

        Assert.areEqual('||', root.operator, 'The root is the loosest-binding operator');
        Assert.areEqual(true, ((AMF_Ast.LiteralNode) root.left).value, 'Its left is the bare TRUE');
        Assert.areEqual(
            '&&',
            ((AMF_Ast.BinaryNode) root.right).operator,
            'And its right is the whole && group'
        );
    }

    @IsTest
    static void andBindsTighterOnBothSidesOfAnOr() {
        AMF_Ast.BinaryNode root = (AMF_Ast.BinaryNode) AMF_Parser.parse('TRUE && FALSE || FALSE && TRUE');

        Assert.areEqual('||', root.operator, 'Still the root');
        Assert.areEqual('&&', ((AMF_Ast.BinaryNode) root.left).operator, 'Left group');
        Assert.areEqual('&&', ((AMF_Ast.BinaryNode) root.right).operator, 'Right group');
    }

    @IsTest
    static void parenthesesOverridePrecedence() {
        AMF_Ast.BinaryNode root = (AMF_Ast.BinaryNode) AMF_Parser.parse('(TRUE || FALSE) && FALSE');

        Assert.areEqual('&&', root.operator, 'Parentheses make && the root instead of ||');
        Assert.areEqual('||', ((AMF_Ast.BinaryNode) root.left).operator, 'The grouped expression is its left');
    }

    @IsTest
    static void redundantParenthesesCollapse() {
        AMF_Ast.Node root = AMF_Parser.parse('(((TRUE)))');

        Assert.isTrue(root instanceof AMF_Ast.LiteralNode, 'Grouping adds no node of its own');
        Assert.areEqual(true, ((AMF_Ast.LiteralNode) root).value, 'It is still the bare TRUE');
    }

    @IsTest
    static void comparisonsBindTighterThanBothLogicalOperators() {
        AMF_Ast.BinaryNode root = (AMF_Ast.BinaryNode) AMF_Parser.parse(
            'Amount__c > 1 && Region__c == \'APAC\''
        );

        Assert.areEqual('&&', root.operator, 'Comparisons are complete before && is considered');
        Assert.isTrue(root.left instanceof AMF_Ast.ComparisonNode, 'Left is a whole comparison');
        Assert.isTrue(root.right instanceof AMF_Ast.ComparisonNode, 'Right is a whole comparison');
    }

    @IsTest
    static void bareAtomsAreCompleteExpressions() {
        Assert.areEqual(
            true,
            ((AMF_Ast.LiteralNode) AMF_Parser.parse('TRUE')).value,
            'Bare TRUE is what makes the catch-all rule expressible (3.2)'
        );
        Assert.areEqual(
            false,
            ((AMF_Ast.LiteralNode) AMF_Parser.parse('FALSE')).value,
            'And bare FALSE parses the same way'
        );
        Assert.areEqual(
            new List<String>{ 'Matrix_Submission__c' },
            ((AMF_Ast.FieldNode) AMF_Parser.parse('Matrix_Submission__c')).segments,
            'A bare field path is 4.1 bool_atom; whether it is Boolean is the compiler question'
        );
    }

    @IsTest
    static void fieldPathsSplitIntoSegments() {
        AMF_Ast.ComparisonNode comparison = (AMF_Ast.ComparisonNode) AMF_Parser.parse(
            'Account__r.Name == \'x\''
        );
        AMF_Ast.FieldNode node = (AMF_Ast.FieldNode) comparison.left;

        Assert.areEqual(
            new List<String>{ 'Account__r', 'Name' },
            node.segments,
            'Segments are kept as written; the compiler canonicalises them'
        );
        Assert.areEqual('Account__r.Name', node.path, 'And the as-written path is available before compilation');
        Assert.areEqual(0, node.position, 'A path is positioned at its first segment');
    }

    @IsTest
    static void deepPathsParseAndAreLeftForTheCompilerToReject() {
        // The parser is a pure syntax machine: a path of any depth is
        // grammatical, and the segment cap is a schema rule.
        AMF_Ast.FieldNode node = (AMF_Ast.FieldNode) ((AMF_Ast.ComparisonNode) AMF_Parser.parse(
                'Account__r.Owner.Alias == \'x\''
            ))
            .left;

        Assert.areEqual(3, node.segments.size(), 'Parsed, not rejected -- rejection belongs to 4.4');
    }

    @IsTest
    static void negativeNumbersFoldIntoTheLiteral() {
        AMF_Ast.ComparisonNode node = (AMF_Ast.ComparisonNode) AMF_Parser.parse('Amount__c < -100.50');
        AMF_Ast.LiteralNode literal = (AMF_Ast.LiteralNode) node.right;

        Assert.areEqual(-100.50, literal.value, 'A minus before a number is part of the literal');
        Assert.areEqual(AMF_Ast.ValueType.NUMERIC, literal.valueType, 'And it is still numeric');
    }

    @IsTest
    static void literalsCarryTheirParsedType() {
        Map<String, AMF_Ast.ValueType> expected = new Map<String, AMF_Ast.ValueType>{
            'Amount__c == 1' => AMF_Ast.ValueType.NUMERIC,
            'Region__c == \'APAC\'' => AMF_Ast.ValueType.TEXT,
            'CloseDate == 2026-01-31' => AMF_Ast.ValueType.DATE_VALUE,
            'Matrix_Submission__c == TRUE' => AMF_Ast.ValueType.BOOLEAN_VALUE
        };

        for (String expression : expected.keySet()) {
            AMF_Ast.LiteralNode literal = (AMF_Ast.LiteralNode) ((AMF_Ast.ComparisonNode) AMF_Parser.parse(
                    expression
                ))
                .right;
            Assert.areEqual(expected.get(expression), literal.valueType, 'Wrong type for ' + expression);
        }

        AMF_Ast.LiteralNode nullLiteral = (AMF_Ast.LiteralNode) ((AMF_Ast.ComparisonNode) AMF_Parser.parse(
                'Amount__c == NULL'
            ))
            .right;
        Assert.isTrue(nullLiteral.isNullLiteral, 'NULL is flagged rather than typed');
        Assert.areEqual(null, nullLiteral.valueType, 'Because it compares against every type (4.3)');
    }

    @IsTest
    static void literalsMayAppearOnEitherSide() {
        AMF_Ast.ComparisonNode node = (AMF_Ast.ComparisonNode) AMF_Parser.parse('100 < Amount__c');

        Assert.isTrue(node.left instanceof AMF_Ast.LiteralNode, 'Literal on the left is grammatical');
        Assert.isTrue(node.right instanceof AMF_Ast.FieldNode, 'Field on the right is grammatical');
    }

    // ------------------------------------------------------------ M9 grammar

    @IsTest
    static void wordFormsBuildTheSameTreeAsTheSymbols() {
        // 4.1: admins may write AND, developers &&. Same precedence, same tree,
        // and the canonical operator whichever was typed.
        AMF_Ast.BinaryNode root = (AMF_Ast.BinaryNode) AMF_Parser.parse('TRUE OR FALSE AND FALSE');

        Assert.areEqual('||', root.operator, 'OR is the loosest-binding operator, as || is');
        Assert.areEqual('&&', ((AMF_Ast.BinaryNode) root.right).operator, 'AND groups first, as && does');
        Assert.areEqual(5, root.position, 'Positioned at the word');

        AMF_Ast.BinaryNode mixed = (AMF_Ast.BinaryNode) AMF_Parser.parse('TRUE and FALSE || TRUE');
        Assert.areEqual('||', mixed.operator, 'The two spellings mix freely');
        Assert.areEqual('&&', ((AMF_Ast.BinaryNode) mixed.left).operator, 'Lower-case words are keywords too');
    }

    @IsTest
    static void notIsAUnaryNodeInEitherSpelling() {
        for (String expression : new List<String>{ 'NOT TRUE', 'not TRUE', '!TRUE' }) {
            AMF_Ast.UnaryNode node = (AMF_Ast.UnaryNode) AMF_Parser.parse(expression);
            Assert.areEqual('!', node.operator, 'One canonical operator for ' + expression);
            Assert.areEqual(0, node.position, 'Positioned at the NOT');
            Assert.areEqual(true, ((AMF_Ast.LiteralNode) node.operand).value, 'Its operand is the TRUE');
        }
    }

    @IsTest
    static void notTakesAWholeComparisonAndBindsTighterThanAnd() {
        // 4.1's unary_expr: NOT's operand is a unary, which can be a whole
        // comparison. So NOT a == b && c is (NOT (a == b)) && c.
        AMF_Ast.BinaryNode root = (AMF_Ast.BinaryNode) AMF_Parser.parse(
            'NOT Region__c == \'APAC\' && Amount__c > 1'
        );

        Assert.areEqual('&&', root.operator, 'NOT binds tighter than &&');
        AMF_Ast.UnaryNode negation = (AMF_Ast.UnaryNode) root.left;
        Assert.isTrue(negation.operand instanceof AMF_Ast.ComparisonNode, 'NOT negates the whole comparison');
        Assert.areEqual('==', ((AMF_Ast.ComparisonNode) negation.operand).operator, 'The comparison is intact');
        Assert.isTrue(root.right instanceof AMF_Ast.ComparisonNode, 'And the && keeps its right operand');
    }

    @IsTest
    static void negationsNestAndApplyToGroups() {
        AMF_Ast.UnaryNode twice = (AMF_Ast.UnaryNode) AMF_Parser.parse('!!TRUE');
        Assert.isTrue(twice.operand instanceof AMF_Ast.UnaryNode, 'A double negation is two nodes');

        AMF_Ast.UnaryNode grouped = (AMF_Ast.UnaryNode) AMF_Parser.parse('NOT (TRUE || FALSE)');
        Assert.areEqual('||', ((AMF_Ast.BinaryNode) grouped.operand).operator, 'NOT applies to the whole group');

        AMF_Ast.ComparisonNode notEquals = (AMF_Ast.ComparisonNode) AMF_Parser.parse('Region__c != \'x\'');
        Assert.areEqual('!=', notEquals.operator, 'The ! of != is still part of the comparison');
    }

    @IsTest
    static void inBuildsAComparisonOverAList() {
        AMF_Ast.ComparisonNode node = (AMF_Ast.ComparisonNode) AMF_Parser.parse(
            'Region__c IN (\'APAC\', \'EMEA\', -5, TODAY)'
        );

        Assert.areEqual('IN', node.operator, 'Canonical operator');
        Assert.areEqual(10, node.position, 'Positioned at IN');
        AMF_Ast.ListNode values = (AMF_Ast.ListNode) node.right;
        Assert.areEqual(13, values.position, 'The list is positioned at its opening parenthesis');
        Assert.areEqual(4, values.items.size(), 'Every value is an item');
        Assert.areEqual('EMEA', ((AMF_Ast.LiteralNode) values.items[1]).value, 'Items are literals, in order');
        Assert.areEqual(-5, ((AMF_Ast.LiteralNode) values.items[2]).value, 'A negative number folds as elsewhere');
        Assert.isTrue(values.items[3] instanceof AMF_Ast.TodayNode, 'TODAY is a literal too');
    }

    @IsTest
    static void operatorWordsAreCanonicalisedWhateverTheirCase() {
        // Apex switch on a String is case-sensitive (technical log M9.3), so the
        // evaluator must never see 'in' or 'Contains'.
        Map<String, String> expected = new Map<String, String>{
            'Region__c in (\'x\')' => 'IN',
            'Region__c NOT IN (\'x\')' => 'NOT IN',
            'Region__c not in (\'x\')' => 'NOT IN',
            'Name CONTAINS \'x\'' => 'CONTAINS',
            'Name contains \'x\'' => 'CONTAINS',
            'Name Starts_With \'x\'' => 'STARTS_WITH'
        };

        for (String expression : expected.keySet()) {
            AMF_Ast.ComparisonNode node = (AMF_Ast.ComparisonNode) AMF_Parser.parse(expression);
            Assert.areEqual(expected.get(expression), node.operator, 'Wrong operator for ' + expression);
        }

        AMF_Ast.ComparisonNode notIn = (AMF_Ast.ComparisonNode) AMF_Parser.parse('Region__c NOT IN (\'x\')');
        Assert.areEqual(10, notIn.position, 'NOT IN is positioned at its NOT');
        Assert.isTrue(notIn.right instanceof AMF_Ast.ListNode, 'And takes a list, as IN does');
    }

    @IsTest
    static void containsTakesAnyOperandOnItsRight() {
        AMF_Ast.ComparisonNode node = (AMF_Ast.ComparisonNode) AMF_Parser.parse('Name CONTAINS Account__r.Name');
        Assert.isTrue(node.right instanceof AMF_Ast.FieldNode, 'A field may be the text searched for');
    }

    @IsTest
    static void todayTakesAnOptionalSignedWholeOffset() {
        Map<String, Integer> expected = new Map<String, Integer>{
            'CloseDate > TODAY' => 0,
            'CloseDate > TODAY()' => 0,
            'CloseDate > TODAY(7)' => 7,
            'CloseDate > TODAY(+7)' => 7,
            'CloseDate > TODAY(-7)' => -7,
            'CloseDate > today( - 30 )' => -30,
            'CloseDate > TODAY(36500)' => 36500,
            'CloseDate > TODAY(-36500)' => -36500
        };

        for (String expression : expected.keySet()) {
            AMF_Ast.TodayNode today = (AMF_Ast.TodayNode) ((AMF_Ast.ComparisonNode) AMF_Parser.parse(expression))
                .right;
            Assert.areEqual(expected.get(expression), today.offsetDays, 'Wrong offset for ' + expression);
            Assert.areEqual(12, today.position, 'Positioned at TODAY in ' + expression);
            Assert.areEqual(AMF_Ast.ValueType.DATE_VALUE, today.valueType, 'TODAY is a date');
        }
    }

    // -------------------------------------------------------- syntax failures

    @IsTest
    static void emptyExpressionsAreRejectedAtPositionZero() {
        for (String expression : new List<String>{ '', '   ', '\t\n', null }) {
            try {
                AMF_Parser.parse(expression);
                Assert.fail('A blank expression is not a catch-all and must not parse');
            } catch (AMF_ExpressionException e) {
                Assert.areEqual(0, e.position, 'There is nowhere else to point');
                Assert.isTrue(e.getMessage().contains('Expression is empty'), e.getMessage());
            }
        }
    }

    @IsTest
    static void structuralFaultsReportTheirPosition() {
        Map<String, Integer> expected = new Map<String, Integer>{
            // Unbalanced parentheses, both directions.
            '(Amount__c > 1' => 14,
            'Amount__c > 1)' => 13,
            '((Amount__c > 1)' => 16,
            // A dangling operator runs off the end.
            'Amount__c >' => 11,
            'Amount__c > 1 &&' => 16,
            // A dot with no field name after it.
            'Account__r. == 1' => 12,
            // A minus that is not part of a number.
            'Amount__c > -TRUE' => 13,
            // Two operands with nothing joining them.
            'Amount__c 100' => 10,
            // A comparison operator where an operand belongs.
            '> 100' => 0,
            // IN lists: missing, empty, unclosed, unseparated, trailing comma,
            // and a field where only literals belong.
            'Region__c IN' => 12,
            'Region__c IN ()' => 14,
            'Region__c IN (\'A\'' => 17,
            'Region__c IN (\'A\' \'B\')' => 18,
            'Region__c IN (\'A\',)' => 18,
            'Region__c IN (Amount__c)' => 14,
            // NOT after an operand can only begin NOT IN.
            'Region__c NOT' => 13,
            'Region__c NOT == \'A\'' => 14,
            // A dangling NOT or logical word.
            'NOT' => 3,
            '!' => 1,
            'TRUE AND' => 8,
            'Name CONTAINS' => 13,
            // TODAY: no number, a fraction, too far, unclosed, a bare sign.
            'TODAY(' => 6,
            'TODAY(1.5)' => 6,
            'TODAY(36501)' => 6,
            'TODAY(36500' => 11,
            'TODAY(+)' => 7
        };

        for (String expression : expected.keySet()) {
            try {
                AMF_Parser.parse(expression);
                Assert.fail(expression + ' must not parse');
            } catch (AMF_ExpressionException e) {
                Assert.areEqual(expected.get(expression), e.position, 'Wrong position for ' + expression);
                Assert.isTrue(
                    e.getMessage().contains('at position ' + expected.get(expression)),
                    'The message must carry the position. Got: ' + e.getMessage()
                );
            }
        }
    }
}
