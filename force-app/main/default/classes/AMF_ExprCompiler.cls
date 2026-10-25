/**
 * Parse plus static analysis against the schema. Produces the CompiledExpression
 * the evaluator runs and the field-path list AMF_FieldPathResolver queries with.
 *
 * Architecture section: 4.2 (compiler responsibilities), 4.3 (type semantics),
 * 4.4 (path depth), 4.6 (fail loudly).
 *
 * This class is where 4.6 is actually won. Every path is resolved through
 * describe and every operator is checked against the type it is applied to
 * HERE, at compile time -- so CONTAINS on a Currency field, or a misspelled
 * field name, is a positioned error rather than a runtime false that routes
 * every record to the next rule and tells nobody. The evaluator that follows can
 * therefore be simple: by the time it runs, the tree is known to be well typed.
 *
 * The operator table (4.3, M9):
 *
 *   == !=                 every type; a multi-select picklist only against a
 *                         text literal of ';'-separated values, compared as sets
 *   > >= < <=             numeric and date only
 *   IN, NOT IN            every single-valued type; never with NULL, which is
 *                         what keeps 4.3's "IN with a null operand is false" exact
 *   CONTAINS              text in text, case-insensitively; or a multi-select
 *                         picklist holding every value a text literal names
 *   STARTS_WITH           text only
 *   NOT / !               a Boolean only
 *
 * What is deliberately NOT checked here: whether 'APAC' is a member of
 * Region__c's value set. A restricted picklist typo would simply never match,
 * which is a configuration mistake rather than a malformed expression.
 *
 * NOTE, inherited from technical log 1.4d: describe does not return fields the
 * running user has no FLS on, so compilation of a rule over Purchase_Request__c
 * fails with "Unknown field" for a user holding neither permission set. The
 * permission sets are a runtime prerequisite for the whole framework, not
 * packaging.
 */
public class AMF_ExprCompiler {
    /**
     * At most four segments: a field reached through three relationship hops,
     * such as Account__r.Owner.Profile.Name. That is 4.1's "max 4", read in the
     * unit 13.3 used when it called Account__r.Region__c two hops. SOQL itself
     * allows five hops (six segments; measured in amf-dev, technical log M9.3),
     * so raising this constant is all a deeper path would need.
     * AMF_FieldPathResolver enforces the same constant on the query it builds.
     */
    public static final Integer MAX_PATH_SEGMENTS = 4;

    /**
     * The supported field types (4.3). A field type absent from this map is a
     * compile error naming the type, which is how a rule over a DateTime --
     * still unsupported -- reports itself instead of misbehaving.
     */
    private static final Map<Schema.DisplayType, AMF_Ast.ValueType> SUPPORTED_TYPES = new Map<Schema.DisplayType, AMF_Ast.ValueType>{
        Schema.DisplayType.CURRENCY => AMF_Ast.ValueType.NUMERIC,
        Schema.DisplayType.DOUBLE => AMF_Ast.ValueType.NUMERIC,
        Schema.DisplayType.INTEGER => AMF_Ast.ValueType.NUMERIC,
        Schema.DisplayType.LONG => AMF_Ast.ValueType.NUMERIC,
        Schema.DisplayType.PERCENT => AMF_Ast.ValueType.NUMERIC,
        Schema.DisplayType.STRING => AMF_Ast.ValueType.TEXT,
        Schema.DisplayType.PICKLIST => AMF_Ast.ValueType.TEXT,
        Schema.DisplayType.ID => AMF_Ast.ValueType.TEXT,
        Schema.DisplayType.REFERENCE => AMF_Ast.ValueType.TEXT,
        Schema.DisplayType.BOOLEAN => AMF_Ast.ValueType.BOOLEAN_VALUE,
        Schema.DisplayType.DATE => AMF_Ast.ValueType.DATE_VALUE,
        Schema.DisplayType.MULTIPICKLIST => AMF_Ast.ValueType.MULTI_SELECT
    };

    /**
     * 4.3: Boolean is identity-only, text and multi-select picklists carry
     * equality plus CONTAINS/STARTS_WITH/IN -- never ordering. Amount__c > 100000
     * is meaningful; Region__c > 'APAC' is not, and saying so at compile time is
     * the difference between a typo and a silent mis-route.
     */
    private static final Set<AMF_Ast.ValueType> EQUALITY_ONLY_TYPES = new Set<AMF_Ast.ValueType>{
        AMF_Ast.ValueType.BOOLEAN_VALUE,
        AMF_Ast.ValueType.TEXT,
        AMF_Ast.ValueType.MULTI_SELECT
    };

    private static final Set<String> EQUALITY_OPERATORS = new Set<String>{ '==', '!=' };
    private static final Set<String> LIST_OPERATORS = new Set<String>{ 'IN', 'NOT IN' };
    private static final Set<String> TEXT_MATCH_OPERATORS = new Set<String>{ 'CONTAINS', 'STARTS_WITH' };

    private static Map<String, Schema.SObjectType> globalDescribe;
    private static final Map<String, Map<String, Schema.DescribeFieldResult>> RELATIONSHIPS_BY_TYPE = new Map<String, Map<String, Schema.DescribeFieldResult>>();

    /**
     * A compiled, schema-checked expression: the AST the evaluator walks, plus
     * everything a caller needs to query for it (4.4) and to audit it (3.3).
     */
    public class CompiledExpression {
        /** The object the paths were resolved against. */
        public String objectApiName { get; private set; }

        /** The source text, kept verbatim for Expression_Snapshot__c (3.3). */
        public String expression { get; private set; }

        /** Root of the type-annotated tree. */
        public AMF_Ast.Node root { get; private set; }

        /** Canonical API-name paths, deduped, in the order first encountered. */
        public List<String> fieldPaths { get; private set; }

        /** Describe of the leaf field of each path, keyed by canonical path. */
        public Map<String, Schema.DescribeFieldResult> describeByPath { get; private set; }

        /**
         * Whether the expression reads TODAY anywhere. When it does, the
         * evaluator records the date TODAY resolved to beside the field values,
         * because the decision depended on it (3.3, 8).
         */
        public Boolean usesToday { get; private set; }

        /**
         * Test-visible so AMF_EvaluatorTest can hand the evaluator a tree the
         * compiler would never have produced, and prove that the evaluator's
         * type guards throw rather than falling through to false (4.6). Nothing
         * in production constructs one of these outside compile().
         */
        @TestVisible
        private CompiledExpression(
            String objectApiName,
            String expression,
            AMF_Ast.Node root,
            List<String> fieldPaths,
            Map<String, Schema.DescribeFieldResult> describeByPath
        ) {
            this(objectApiName, expression, root, fieldPaths, describeByPath, false);
        }

        private CompiledExpression(
            String objectApiName,
            String expression,
            AMF_Ast.Node root,
            List<String> fieldPaths,
            Map<String, Schema.DescribeFieldResult> describeByPath,
            Boolean usesToday
        ) {
            this.objectApiName = objectApiName;
            this.expression = expression;
            this.root = root;
            this.fieldPaths = fieldPaths;
            this.describeByPath = describeByPath;
            this.usesToday = usesToday;
        }
    }

    private final String objectApiName;
    private final String expression;
    private final Schema.SObjectType rootType;
    private final List<String> fieldPaths = new List<String>();
    private final Map<String, Schema.DescribeFieldResult> describeByPath = new Map<String, Schema.DescribeFieldResult>();
    private Boolean usesToday = false;

    private AMF_ExprCompiler(String objectApiName, String expression) {
        this.objectApiName = objectApiName;
        this.expression = expression;
        this.rootType = describeGlobal().get(objectApiName);

        if (this.rootType == null) {
            throw AMF_ExpressionException.of(
                'Object ' + AMF_Lexer.quote(objectApiName) + ' does not exist or is not visible'
            ).withExpression(expression);
        }
    }

    /**
     * Compiles one expression against one object.
     *
     * @param objectApiName API name of the object the rule governs.
     * @param expression    Raw Expression__c text.
     * @return The compiled expression, ready for AMF_Evaluator.
     * @throws AMF_ExpressionException On any lexical, syntactic or semantic
     *         fault, carrying the character position and the source expression.
     */
    public static CompiledExpression compile(String objectApiName, String expression) {
        AMF_ExprCompiler compiler = new AMF_ExprCompiler(objectApiName, expression);
        AMF_Ast.Node root;

        try {
            root = AMF_Parser.parse(expression);
            compiler.analyse(root, true);
        } catch (AMF_ExpressionException e) {
            // Rethrow of the same instance, enriched with the source text so a
            // caller knows which rule to open. Nothing is caught into a boolean
            // here and nothing is suppressed -- that is 4.6's whole point.
            throw e.withExpression(expression);
        }

        return new CompiledExpression(
            objectApiName,
            expression,
            root,
            compiler.fieldPaths,
            compiler.describeByPath,
            compiler.usesToday
        );
    }

    /**
     * @param node        The node to check.
     * @param asCondition True where the grammar requires a Boolean -- the root,
     *                    both sides of '&&' / '||', and the operand of NOT.
     */
    private void analyse(AMF_Ast.Node node, Boolean asCondition) {
        if (node instanceof AMF_Ast.BinaryNode) {
            AMF_Ast.BinaryNode binary = (AMF_Ast.BinaryNode) node;
            analyse(binary.left, true);
            analyse(binary.right, true);
            return;
        }

        if (node instanceof AMF_Ast.UnaryNode) {
            analyse(((AMF_Ast.UnaryNode) node).operand, true);
            return;
        }

        if (node instanceof AMF_Ast.ComparisonNode) {
            AMF_Ast.ComparisonNode comparison = (AMF_Ast.ComparisonNode) node;
            analyse(comparison.left, false);
            analyse(comparison.right, false);
            checkComparison(comparison);
            return;
        }

        if (node instanceof AMF_Ast.ListNode) {
            for (AMF_Ast.Node item : ((AMF_Ast.ListNode) node).items) {
                analyse(item, false);
            }
            return;
        }

        if (node instanceof AMF_Ast.FieldNode) {
            resolveField((AMF_Ast.FieldNode) node);
        }

        if (node instanceof AMF_Ast.TodayNode) {
            usesToday = true;
        }

        if (asCondition && node.valueType != AMF_Ast.ValueType.BOOLEAN_VALUE) {
            throw AMF_ExpressionException.at(
                describeOperand(node) + ' is not a Boolean and cannot stand alone as a condition',
                node.position
            );
        }
    }

    private void checkComparison(AMF_Ast.ComparisonNode node) {
        if (LIST_OPERATORS.contains(node.operator)) {
            checkListComparison(node);
        } else if (TEXT_MATCH_OPERATORS.contains(node.operator)) {
            checkTextMatch(node);
        } else if (isMultiSelect(node.left) || isMultiSelect(node.right)) {
            checkMultiSelectEquality(node);
        } else {
            checkScalarComparison(node);
        }
    }

    /**
     * 4.3's compatibility table for the six comparison operators, enforced in two
     * parts: the operator has to make sense for the type, and the two sides have
     * to be the same type. A NULL literal is typeless and passes both --
     * Field__c == NULL is the sanctioned presence check.
     */
    private void checkScalarComparison(AMF_Ast.ComparisonNode node) {
        requireSameType(node.left, node.right, node.position);
        node.operandType = node.left.valueType != null ? node.left.valueType : node.right.valueType;
        requireOperatorSupports(node);
    }

    /**
     * A multi-select picklist is a set, so == and != compare it with a set: a text
     * literal naming values separated by ';', in any order and any case. Comparing
     * one with another field, or ordering one, has no meaning 4.3 defines, so
     * both are refused. NULL remains the presence check.
     */
    private void checkMultiSelectEquality(AMF_Ast.ComparisonNode node) {
        node.operandType = AMF_Ast.ValueType.MULTI_SELECT;
        requireOperatorSupports(node);

        AMF_Ast.Node other = isMultiSelect(node.left) ? node.right : node.left;
        if (isNullLiteral(other)) {
            return;
        }
        requireValueListLiteral(node, other);
    }

    /**
     * IN and NOT IN mean the operand equals one of the values (4.1), so every
     * value has to be the operand's type. NULL is refused on either side: 4.3
     * makes IN with a null operand false, and allowing NULL in the list would make
     * Field__c IN ('A', NULL) true for a blank field and contradict it. A blank
     * field is tested with == NULL.
     */
    private void checkListComparison(AMF_Ast.ComparisonNode node) {
        if (isNullLiteral(node.left)) {
            throw nullNotAllowed(node, node.left);
        }
        if (node.left.valueType == AMF_Ast.ValueType.MULTI_SELECT) {
            throw unsupportedOperator(node, AMF_Ast.ValueType.MULTI_SELECT);
        }

        for (AMF_Ast.Node item : ((AMF_Ast.ListNode) node.right).items) {
            if (isNullLiteral(item)) {
                throw nullNotAllowed(node, item);
            }
            requireSameType(node.left, item, item.position);
        }
        node.operandType = node.left.valueType;
    }

    /**
     * CONTAINS and STARTS_WITH match text within text. CONTAINS on a multi-select
     * picklist is set membership instead: the field holds every value the literal
     * names (4.3). Neither has a meaning for NULL, numbers, dates or Booleans.
     */
    private void checkTextMatch(AMF_Ast.ComparisonNode node) {
        if (isNullLiteral(node.left)) {
            throw nullNotAllowed(node, node.left);
        }
        if (isNullLiteral(node.right)) {
            throw nullNotAllowed(node, node.right);
        }

        AMF_Ast.ValueType leftType = node.left.valueType;
        if (leftType == AMF_Ast.ValueType.MULTI_SELECT && node.operator == 'CONTAINS') {
            node.operandType = AMF_Ast.ValueType.MULTI_SELECT;
            requireValueListLiteral(node, node.right);
            return;
        }
        if (leftType != AMF_Ast.ValueType.TEXT) {
            throw unsupportedOperator(node, leftType);
        }

        requireSameType(node.left, node.right, node.position);
        node.operandType = AMF_Ast.ValueType.TEXT;
    }

    /**
     * @param position Where to point: a comparison's operator, as it always has
     *                 been, or the offending item of an IN list.
     */
    private void requireSameType(AMF_Ast.Node left, AMF_Ast.Node right, Integer position) {
        AMF_Ast.ValueType leftType = left.valueType;
        AMF_Ast.ValueType rightType = right.valueType;

        if (leftType != null && rightType != null && leftType != rightType) {
            throw AMF_ExpressionException.at(
                'Cannot compare ' + describeOperand(left) + ' with ' + describeOperand(right),
                position
            );
        }
    }

    private void requireOperatorSupports(AMF_Ast.ComparisonNode node) {
        if (
            node.operandType != null &&
            EQUALITY_ONLY_TYPES.contains(node.operandType) &&
            !EQUALITY_OPERATORS.contains(node.operator)
        ) {
            throw unsupportedOperator(node, node.operandType);
        }
    }

    /**
     * The other side of a multi-select comparison must be a text literal naming
     * at least one value. An empty one would be the empty set, which no stored
     * value ever is -- a blank multi-select picklist reads null -- so it is a
     * mistake to report, not a condition to evaluate.
     */
    private void requireValueListLiteral(AMF_Ast.ComparisonNode node, AMF_Ast.Node other) {
        if (!(other instanceof AMF_Ast.LiteralNode) || other.valueType != AMF_Ast.ValueType.TEXT) {
            throw AMF_ExpressionException.at(
                'A multi-select picklist can only be compared with a text literal of values separated by ' +
                AMF_Lexer.quote(';') +
                ', not ' +
                describeOperand(other),
                other.position
            );
        }
        if (AMF_Evaluator.valueSet((String) ((AMF_Ast.LiteralNode) other).value).isEmpty()) {
            throw AMF_ExpressionException.at(
                'The value list for a multi-select picklist names no values; test for a blank field with ' +
                AMF_Lexer.quote('== NULL'),
                other.position
            );
        }
    }

    private AMF_ExpressionException unsupportedOperator(AMF_Ast.ComparisonNode node, AMF_Ast.ValueType type) {
        return AMF_ExpressionException.at(
            'Operator ' + AMF_Lexer.quote(node.operator) + ' is not supported for ' + AMF_Ast.labelFor(type) + ' values',
            node.position
        );
    }

    private AMF_ExpressionException nullNotAllowed(AMF_Ast.ComparisonNode node, AMF_Ast.Node nullNode) {
        return AMF_ExpressionException.at(
            'Operator ' +
            AMF_Lexer.quote(node.operator) +
            ' cannot be used with NULL; test for a blank field with ' +
            AMF_Lexer.quote('== NULL'),
            nullNode.position
        );
    }

    private static Boolean isNullLiteral(AMF_Ast.Node node) {
        return node instanceof AMF_Ast.LiteralNode && ((AMF_Ast.LiteralNode) node).isNullLiteral;
    }

    private static Boolean isMultiSelect(AMF_Ast.Node node) {
        return node.valueType == AMF_Ast.ValueType.MULTI_SELECT;
    }

    /**
     * Walks a path through describe, canonicalising each segment to its API-name
     * spelling and recording the leaf for the evaluator and the query builder.
     */
    private void resolveField(AMF_Ast.FieldNode node) {
        if (node.segments.size() > MAX_PATH_SEGMENTS) {
            throw AMF_ExpressionException.at(
                'Field path ' +
                AMF_Lexer.quote(node.path) +
                ' has ' +
                node.segments.size() +
                ' segments; the maximum is ' +
                MAX_PATH_SEGMENTS,
                node.position
            );
        }

        Schema.SObjectType currentType = rootType;
        List<String> canonical = new List<String>();

        for (Integer i = 0; i < node.segments.size() - 1; i++) {
            Schema.DescribeFieldResult relationship = resolveRelationship(
                currentType,
                node.segments[i],
                node.position
            );
            canonical.add(relationship.getRelationshipName());
            currentType = relationship.getReferenceTo()[0];
        }

        String leafName = node.segments[node.segments.size() - 1];
        Schema.SObjectField leafToken = currentType.getDescribe().fields.getMap().get(leafName.toLowerCase());

        if (leafToken == null) {
            throw AMF_ExpressionException.at(
                'Unknown field ' + AMF_Lexer.quote(leafName) + ' on ' + String.valueOf(currentType),
                node.position
            );
        }

        Schema.DescribeFieldResult leaf = leafToken.getDescribe();
        AMF_Ast.ValueType valueType = SUPPORTED_TYPES.get(leaf.getType());

        if (valueType == null) {
            throw AMF_ExpressionException.at(
                'Field ' +
                AMF_Lexer.quote(leaf.getName()) +
                ' on ' +
                String.valueOf(currentType) +
                ' is of type ' +
                String.valueOf(leaf.getType()) +
                ', which the expression grammar does not support',
                node.position
            );
        }

        canonical.add(leaf.getName());
        node.path = String.join(canonical, '.');
        node.valueType = valueType;

        if (!describeByPath.containsKey(node.path)) {
            fieldPaths.add(node.path);
            describeByPath.put(node.path, leaf);
        }
    }

    private Schema.DescribeFieldResult resolveRelationship(
        Schema.SObjectType type,
        String segment,
        Integer position
    ) {
        Schema.DescribeFieldResult relationship = relationshipsFor(type).get(segment.toLowerCase());

        if (relationship == null) {
            throw AMF_ExpressionException.at(
                'Unknown relationship ' + AMF_Lexer.quote(segment) + ' on ' + String.valueOf(type),
                position
            );
        }
        if (relationship.getReferenceTo().size() != 1) {
            // A polymorphic lookup has no single target to describe the next
            // segment against. Naming it beats guessing at referenceTo[0].
            throw AMF_ExpressionException.at(
                'Relationship ' +
                AMF_Lexer.quote(segment) +
                ' on ' +
                String.valueOf(type) +
                ' is polymorphic and cannot be traversed',
                position
            );
        }
        return relationship;
    }

    /**
     * Relationship name to field describe, built once per SObjectType per
     * transaction. Finding a relationship means describing every field on the
     * object, which on a standard object is hundreds of calls -- worth doing once
     * and not once per path.
     */
    private static Map<String, Schema.DescribeFieldResult> relationshipsFor(Schema.SObjectType type) {
        String key = String.valueOf(type);
        Map<String, Schema.DescribeFieldResult> cached = RELATIONSHIPS_BY_TYPE.get(key);

        if (cached != null) {
            return cached;
        }

        cached = new Map<String, Schema.DescribeFieldResult>();
        for (Schema.SObjectField field : type.getDescribe().fields.getMap().values()) {
            Schema.DescribeFieldResult describe = field.getDescribe();
            String relationshipName = describe.getRelationshipName();

            if (String.isNotBlank(relationshipName)) {
                cached.put(relationshipName.toLowerCase(), describe);
            }
        }

        RELATIONSHIPS_BY_TYPE.put(key, cached);
        return cached;
    }

    private static Map<String, Schema.SObjectType> describeGlobal() {
        if (globalDescribe == null) {
            globalDescribe = Schema.getGlobalDescribe();
        }
        return globalDescribe;
    }

    /**
     * How an operand is named in an error message -- a field by its path and
     * platform type, a literal by what kind of literal it is.
     *
     * @param node The operand.
     * @return A phrase that fits mid-sentence.
     */
    private String describeOperand(AMF_Ast.Node node) {
        if (node instanceof AMF_Ast.FieldNode) {
            AMF_Ast.FieldNode field = (AMF_Ast.FieldNode) node;
            Schema.DescribeFieldResult describe = describeByPath.get(field.path);
            return 'field ' +
                AMF_Lexer.quote(field.path) +
                (describe == null ? '' : ' (' + String.valueOf(describe.getType()) + ')');
        }
        if (node instanceof AMF_Ast.TodayNode) {
            return 'TODAY';
        }

        // Only operands are ever described, and the parser builds operands from
        // fields, TODAY and literals alone.
        AMF_Ast.LiteralNode literal = (AMF_Ast.LiteralNode) node;
        if (literal.isNullLiteral) {
            return 'a NULL literal';
        }
        return 'a ' + AMF_Ast.labelFor(literal.valueType) + ' literal';
    }
}
