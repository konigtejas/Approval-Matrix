/**
 * Runs a compiled expression against one record: Boolean out, plus the map of
 * every field value it read (4.2).
 *
 * Architecture section: 4.2 (pipeline), 4.3 (type and null semantics),
 * 4.6 (fail loudly), 3.3 (Evaluated_Values__c).
 *
 * The tree arriving here has already been type-checked by AMF_ExprCompiler, so
 * this class does no describe work and makes no schema decisions -- it reads
 * values and applies 4.3. That is the whole reason compilation is cached and
 * evaluation is not: this is the cheap half.
 *
 * THE NULL RULES (4.3), stated once here because they are the part of the
 * framework most likely to surprise:
 *
 *   null == null                    true
 *   null == value, value == null    false
 *   null != null                    false
 *   null != value                   true
 *   null with > >= < <=             false, and never an exception
 *   null IN (...)                   false, so null NOT IN (...) is true
 *   null CONTAINS / STARTS_WITH     false, either side
 *   a bare Checkbox path that is null   false
 *
 * And one rule that outranks all of the above: IF AN INTERMEDIATE STEP OF A
 * RELATIONSHIP PATH IS NULL, THE COMPARISON IS UNKNOWN -- including
 * Account__r.Name == NULL and Account__r.Name != NULL when the record has no
 * Account. 4.3 states it ("null anywhere in a relationship path makes the
 * comparison false") and docs/decisions.md 2026-08-18 records why: a path the
 * engine could not resolve must route nothing at all, rather than quietly satisfy
 * a presence check.
 *
 * UNKNOWN, NOT FALSE, since M9. Before NOT existed the two were indistinguishable:
 * an unknown comparison could only ever be and-ed or or-ed, and every expression
 * that would match with it unknown also matches with it false. NOT breaks that --
 * NOT (Account__r.Name == NULL) would be true for a record with no Account, the
 * very presence check the rule forbids. So a broken path makes its comparison
 * UNKNOWN (null here), and the logical operators follow Kleene's three-valued
 * logic, as SQL does:
 *
 *   NOT unknown          unknown
 *   unknown && false     false        unknown && true    unknown
 *   unknown || true      true         unknown || false   unknown
 *
 * and the expression matches only when the whole is TRUE. Every expression
 * written before M9 evaluates exactly as it did (docs/decisions.md, 2026-10-08).
 * The unknown is confined to broken paths: a null LEAF value is an ordinary
 * value, and the two-valued rules above still decide it.
 *
 * There is no catch block in this class. A record missing a field the query did
 * not select, or a field deleted from the schema after deploy, throws out of
 * here and blocks the submission (4.6). It never becomes a false.
 */
public class AMF_Evaluator {
    /**
     * The key under which the date TODAY resolved to is recorded in the
     * evaluated values. TODAY is a reserved word, so no field path can collide
     * with it.
     */
    public static final String TODAY_KEY = 'TODAY';

    /**
     * The value separator of a multi-select picklist, in stored values and in the
     * text literals compared with them.
     */
    private static final String VALUE_SEPARATOR = ';';

    /**
     * What TODAY means, fixed once per transaction so every rule and every record
     * in one submission agrees on it, and so the date recorded in the log is the
     * date that was used. Date.today() is the running user's local date -- the
     * submitter's, since the engine runs as them.
     */
    private static Date transactionToday;

    /** Test seam: pins TODAY, so a date rule can be tested on any day. */
    @TestVisible
    private static Date todayOverride;

    /** One record's verdict, and the evidence behind it. */
    public class Result {
        /** Whether the expression matched. Never null. */
        public Boolean matched { get; private set; }

        /**
         * Every field path the expression references, in compile order, mapped to
         * the value read from the record -- plus, under TODAY_KEY, the date TODAY
         * meant, when the expression uses it. This is what Evaluated_Values__c
         * holds (3.3), and it is populated from the compiled path list rather than
         * from the nodes evaluation actually reached -- short-circuiting '&&' must
         * not change what the audit record says the engine looked at.
         */
        public Map<String, Object> evaluatedValues { get; private set; }

        private Result(Boolean matched, Map<String, Object> evaluatedValues) {
            this.matched = matched;
            this.evaluatedValues = evaluatedValues;
        }

        /**
         * @return evaluatedValues as JSON, ready for Evaluated_Values__c.
         */
        public String toJson() {
            return JSON.serialize(evaluatedValues);
        }
    }

    /** A resolved operand: its value, and whether its path resolved at all. */
    private class PathValue {
        private Object value;
        private Boolean broken;

        private PathValue(Object value, Boolean broken) {
            this.value = value;
            this.broken = broken;
        }
    }

    /**
     * @param compiled A compiled expression from AMF_ExprCache.
     * @param record   The record to test. Must carry every path in
     *                 compiled.fieldPaths -- AMF_FieldPathResolver is what
     *                 guarantees that (4.4).
     * @return The verdict and the values behind it.
     * @throws AMF_ExpressionException On a null argument.
     * @throws System.SObjectException If the record was queried without a field
     *         the expression needs. Deliberately not caught (4.6).
     */
    public static Result evaluate(AMF_ExprCompiler.CompiledExpression compiled, SObject record) {
        if (compiled == null) {
            throw AMF_ExpressionException.of('Cannot evaluate a null compiled expression');
        }
        if (record == null) {
            throw AMF_ExpressionException.of(
                'Cannot evaluate ' + AMF_Lexer.quote(compiled.expression) + ' against a null record'
            );
        }

        Map<String, Object> evaluatedValues = new Map<String, Object>();
        for (String path : compiled.fieldPaths) {
            evaluatedValues.put(path, resolve(record, path).value);
        }
        if (compiled.usesToday == true) {
            evaluatedValues.put(TODAY_KEY, today());
        }

        // Only a definite TRUE matches; FALSE and UNKNOWN do not.
        return new Result(evaluateNode(compiled.root, record) == true, evaluatedValues);
    }

    /**
     * A multi-select picklist value, or a text literal compared with one, as a
     * set: split on ';', trimmed, blank entries dropped, lower-cased because 4.3
     * compares text case-insensitively. Also used by AMF_ExprCompiler to refuse a
     * literal that names no values.
     *
     * @param raw The stored value or literal, possibly null.
     * @return The values it names. Empty for null or blank.
     */
    public static Set<String> valueSet(String raw) {
        Set<String> values = new Set<String>();
        if (String.isBlank(raw)) {
            return values;
        }
        for (String part : raw.split(VALUE_SEPARATOR)) {
            if (String.isNotBlank(part)) {
                values.add(part.trim().toLowerCase());
            }
        }
        return values;
    }

    /**
     * @return TRUE, FALSE, or null for UNKNOWN (see the class header).
     */
    private static Boolean evaluateNode(AMF_Ast.Node node, SObject record) {
        if (node instanceof AMF_Ast.BinaryNode) {
            AMF_Ast.BinaryNode binary = (AMF_Ast.BinaryNode) node;

            // Short-circuits on the value that decides the result whatever the
            // other side is. Safe because the null rules make evaluation total --
            // no branch can throw where the other would not have -- and the
            // evaluated-values map is built independently of what runs.
            Boolean left = evaluateNode(binary.left, record);
            if (binary.operator == '&&') {
                if (left == false) {
                    return false;
                }
                Boolean right = evaluateNode(binary.right, record);
                if (right == false) {
                    return false;
                }
                return left == true && right == true ? true : null;
            }

            if (left == true) {
                return true;
            }
            Boolean right = evaluateNode(binary.right, record);
            if (right == true) {
                return true;
            }
            return left == false && right == false ? false : null;
        }

        if (node instanceof AMF_Ast.UnaryNode) {
            return negate(evaluateNode(((AMF_Ast.UnaryNode) node).operand, record));
        }

        if (node instanceof AMF_Ast.ComparisonNode) {
            return evaluateComparison((AMF_Ast.ComparisonNode) node, record);
        }

        // A bare TRUE, FALSE or Checkbox path standing as the whole condition
        // (4.1's bool_atom). The compiler has already proven it is Boolean.
        PathValue atom = operandValue(node, record);
        if (atom.broken) {
            return null;
        }
        if (atom.value == null) {
            return false;
        }
        return (Boolean) atom.value;
    }

    private static Boolean negate(Boolean value) {
        return value == null ? null : !value;
    }

    private static Boolean evaluateComparison(AMF_Ast.ComparisonNode node, SObject record) {
        PathValue left = operandValue(node.left, record);

        switch on node.operator {
            when 'IN' {
                return left.broken ? null : isInList(node, left.value, record);
            }
            when 'NOT IN' {
                return left.broken ? null : !isInList(node, left.value, record);
            }
        }

        PathValue right = operandValue(node.right, record);

        // The relationship-path rule, ahead of everything else.
        if (left.broken || right.broken) {
            return null;
        }

        Boolean leftIsNull = left.value == null;
        Boolean rightIsNull = right.value == null;

        switch on node.operator {
            when 'CONTAINS' {
                return !leftIsNull && !rightIsNull && contains(node, left.value, right.value);
            }
            when 'STARTS_WITH' {
                return !leftIsNull &&
                    !rightIsNull &&
                    String.valueOf(left.value).startsWithIgnoreCase(String.valueOf(right.value));
            }
        }

        if (leftIsNull || rightIsNull) {
            if (node.operator == '==') {
                return leftIsNull && rightIsNull;
            }
            if (node.operator == '!=') {
                return !(leftIsNull && rightIsNull);
            }
            return false;
        }

        return compareValues(node, left.value, right.value);
    }

    /**
     * IN is equality with any one of the values (4.1). A null operand is in no
     * list (4.3); the compiler refuses NULL in the list itself.
     */
    private static Boolean isInList(AMF_Ast.ComparisonNode node, Object value, SObject record) {
        if (value == null) {
            return false;
        }
        for (AMF_Ast.Node item : ((AMF_Ast.ListNode) node.right).items) {
            if (areEqual(node, value, operandValue(item, record).value)) {
                return true;
            }
        }
        return false;
    }

    /**
     * Text within text, case-insensitively; or, for a multi-select picklist,
     * every value the literal names among the values selected (4.3).
     */
    private static Boolean contains(AMF_Ast.ComparisonNode node, Object left, Object right) {
        if (node.operandType == AMF_Ast.ValueType.MULTI_SELECT) {
            return valueSet(String.valueOf(left)).containsAll(valueSet(String.valueOf(right)));
        }
        if (node.operandType == AMF_Ast.ValueType.TEXT) {
            return String.valueOf(left).containsIgnoreCase(String.valueOf(right));
        }
        throw unsupportedOperator(node);
    }

    private static Boolean compareValues(AMF_Ast.ComparisonNode node, Object left, Object right) {
        if (node.operandType == AMF_Ast.ValueType.NUMERIC) {
            Decimal leftNumber = toDecimal(left);
            Decimal rightNumber = toDecimal(right);
            return applyOrdering(
                node,
                leftNumber == rightNumber ? 0 : (leftNumber > rightNumber ? 1 : -1)
            );
        }

        if (node.operandType == AMF_Ast.ValueType.DATE_VALUE) {
            Date leftDate = (Date) left;
            Date rightDate = (Date) right;
            return applyOrdering(node, leftDate == rightDate ? 0 : (leftDate > rightDate ? 1 : -1));
        }

        if (
            node.operandType == AMF_Ast.ValueType.TEXT ||
            node.operandType == AMF_Ast.ValueType.BOOLEAN_VALUE ||
            node.operandType == AMF_Ast.ValueType.MULTI_SELECT
        ) {
            return applyEquality(node, areEqual(node, left, right));
        }

        // Unreachable through AMF_ExprCompiler, which never leaves operandType
        // unset on a comparison of two non-null operands. Kept as a guard because
        // 4.6 says an unexpected state throws; it must not fall through to false.
        throw AMF_ExpressionException.at(
            'Cannot compare values of unknown type',
            node.position
        );
    }

    /**
     * Equality of two non-null values of the comparison's type: what == means
     * and what IN means for each value in its list.
     */
    private static Boolean areEqual(AMF_Ast.ComparisonNode node, Object left, Object right) {
        if (right == null) {
            return false;
        }
        switch on node.operandType {
            when NUMERIC {
                return toDecimal(left) == toDecimal(right);
            }
            when DATE_VALUE {
                return (Date) left == (Date) right;
            }
            when TEXT {
                // 4.3: text comparison is case-insensitive, so a rule written
                // Region__c == 'apac' matches a record whose Region__c is APAC.
                return String.valueOf(left).equalsIgnoreCase(String.valueOf(right));
            }
            when BOOLEAN_VALUE {
                return (Boolean) left == (Boolean) right;
            }
            when MULTI_SELECT {
                // An exact set match, in any order (4.3).
                return valueSet(String.valueOf(left)).equals(valueSet(String.valueOf(right)));
            }
            when else {
                throw AMF_ExpressionException.at('Cannot compare values of unknown type', node.position);
            }
        }
    }

    /**
     * @param node The comparison, for its operator and position.
     * @param sign -1, 0 or 1 for left less than, equal to, or greater than right.
     * @return The operator applied to that ordering.
     */
    private static Boolean applyOrdering(AMF_Ast.ComparisonNode node, Integer sign) {
        switch on node.operator {
            when '==' {
                return sign == 0;
            }
            when '!=' {
                return sign != 0;
            }
            when '>' {
                return sign > 0;
            }
            when '>=' {
                return sign >= 0;
            }
            when '<' {
                return sign < 0;
            }
            when '<=' {
                return sign <= 0;
            }
            when else {
                throw unsupportedOperator(node);
            }
        }
    }

    /**
     * Types that carry no ordering (4.3: Boolean is identity, text and
     * multi-select picklists are case-insensitive equality). The compiler rejects
     * an ordering operator on all three, so reaching the throw means an AST that
     * did not come from it.
     *
     * @param node    The comparison.
     * @param isEqual Whether the two operands are equal.
     * @return The operator applied to that equality.
     */
    private static Boolean applyEquality(AMF_Ast.ComparisonNode node, Boolean isEqual) {
        if (node.operator == '==') {
            return isEqual;
        }
        if (node.operator == '!=') {
            return !isEqual;
        }
        throw unsupportedOperator(node);
    }

    private static AMF_ExpressionException unsupportedOperator(AMF_Ast.ComparisonNode node) {
        return AMF_ExpressionException.at(
            'Operator ' +
            AMF_Lexer.quote(node.operator) +
            ' cannot be applied to ' +
            AMF_Ast.labelFor(node.operandType) +
            ' values',
            node.position
        );
    }

    private static PathValue operandValue(AMF_Ast.Node node, SObject record) {
        if (node instanceof AMF_Ast.FieldNode) {
            return resolve(record, ((AMF_Ast.FieldNode) node).path);
        }
        if (node instanceof AMF_Ast.TodayNode) {
            return new PathValue(today().addDays(((AMF_Ast.TodayNode) node).offsetDays), false);
        }
        return new PathValue(((AMF_Ast.LiteralNode) node).value, false);
    }

    private static Date today() {
        if (todayOverride != null) {
            return todayOverride;
        }
        if (transactionToday == null) {
            transactionToday = Date.today();
        }
        return transactionToday;
    }

    /**
     * Walks a canonical path across the record, stopping at the first null
     * relationship rather than dereferencing it.
     *
     * @param record The record.
     * @param path   A canonical path from the compiler, e.g. Account__r.Name.
     * @return The leaf value, or a broken PathValue if a hop was null.
     */
    private static PathValue resolve(SObject record, String path) {
        List<String> segments = path.split('\\.');
        SObject current = record;

        for (Integer i = 0; i < segments.size() - 1; i++) {
            current = current.getSObject(segments[i]);
            if (current == null) {
                return new PathValue(null, true);
            }
        }

        return new PathValue(current.get(segments[segments.size() - 1]), false);
    }

    /**
     * SObject numeric fields arrive as Decimal, Double, Integer or Long
     * depending on the field type; literals arrive as Decimal. Comparing them in
     * one currency is what avoids an Integer/Decimal equality surprise.
     *
     * MEASURED, not assumed (amf-dev, API 62; technical log M2.4): Apex reports
     * EVERY boxed numeric as `instanceof Decimal` -- an Integer field, a Long and
     * a Double all answer true -- and the cast succeeds for all of them. Per-type
     * branches under this one would therefore be unreachable, so there are none.
     * The fallback covers only a value that reads as a number without being
     * boxed as one, which the compiler's type check should already prevent.
     *
     * @param value A numeric value.
     * @return It, as a Decimal.
     */
    private static Decimal toDecimal(Object value) {
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        return Decimal.valueOf(String.valueOf(value));
    }
}
