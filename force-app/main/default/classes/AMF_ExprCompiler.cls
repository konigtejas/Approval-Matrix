/**
 * Parse plus static analysis against the schema. Produces the CompiledExpression
 * the evaluator runs and the field-path list AMF_FieldPathResolver queries with.
 *
 * Architecture section: 4.2 (compiler responsibilities), 4.3 (type semantics),
 * 4.4 (path depth), 4.6 (fail loudly), 13.3 (reduced MVP grammar).
 *
 * This class is where 4.6 is actually won. Every path is resolved through
 * describe and every operator is checked against the type it is applied to
 * HERE, at compile time -- so CONTAINS on a Currency field, or a misspelled
 * field name, is a positioned error rather than a runtime false that routes
 * every record to the next rule and tells nobody. The evaluator that follows can
 * therefore be simple: by the time it runs, the tree is known to be well typed.
 *
 * What is deliberately NOT checked here: whether 'APAC' is a member of
 * Region__c's value set. A restricted picklist typo would simply never match,
 * which is a configuration mistake rather than a malformed expression, and 9's
 * config validator is the thing that owns it. It is out of MVP scope (13.2).
 *
 * NOTE, inherited from technical log 1.4d: describe does not return fields the
 * running user has no FLS on, so compilation of a rule over Purchase_Request__c
 * fails with "Unknown field" for a user holding neither permission set. The
 * permission sets are a runtime prerequisite for the whole framework, not
 * packaging.
 */
public class AMF_ExprCompiler {
    /**
     * 13.3 caps MVP paths at two segments -- one relationship hop. 4.4's limit is
     * the platform's four. Raising it is this constant and nothing else, which is
     * what "structure them so they are additive" asks for.
     */
    @TestVisible
    private static final Integer MAX_PATH_SEGMENTS = 2;

    /**
     * The MVP type surface (13.3). A field type absent from this map is a compile
     * error naming the type, which is how a rule over a DateTime or a
     * Multipicklist -- both deferred -- reports itself instead of misbehaving.
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
        Schema.DisplayType.DATE => AMF_Ast.ValueType.DATE_VALUE
    };

    /**
     * 4.3: Boolean is identity-only, and text types carry equality plus the
     * deferred CONTAINS/STARTS_WITH/IN -- never ordering. Amount__c > 100000 is
     * meaningful; Region__c > 'APAC' is not, and saying so at compile time is
     * the difference between a typo and a silent mis-route.
     */
    private static final Set<AMF_Ast.ValueType> EQUALITY_ONLY_TYPES = new Set<AMF_Ast.ValueType>{
        AMF_Ast.ValueType.BOOLEAN_VALUE,
        AMF_Ast.ValueType.TEXT
    };

    private static final Set<String> EQUALITY_OPERATORS = new Set<String>{ '==', '!=' };

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
            this.objectApiName = objectApiName;
            this.expression = expression;
            this.root = root;
            this.fieldPaths = fieldPaths;
            this.describeByPath = describeByPath;
        }
    }

    private final String objectApiName;
    private final String expression;
    private final Schema.SObjectType rootType;
    private final List<String> fieldPaths = new List<String>();
    private final Map<String, Schema.DescribeFieldResult> describeByPath = new Map<String, Schema.DescribeFieldResult>();

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
            compiler.describeByPath
        );
    }

    /**
     * @param node        The node to check.
     * @param asCondition True where the grammar requires a Boolean -- the root,
     *                    and both sides of '&&' / '||'.
     */
    private void analyse(AMF_Ast.Node node, Boolean asCondition) {
        if (node instanceof AMF_Ast.BinaryNode) {
            AMF_Ast.BinaryNode binary = (AMF_Ast.BinaryNode) node;
            analyse(binary.left, true);
            analyse(binary.right, true);
            return;
        }

        if (node instanceof AMF_Ast.ComparisonNode) {
            AMF_Ast.ComparisonNode comparison = (AMF_Ast.ComparisonNode) node;
            analyse(comparison.left, false);
            analyse(comparison.right, false);
            checkComparison(comparison);
            return;
        }

        if (node instanceof AMF_Ast.FieldNode) {
            resolveField((AMF_Ast.FieldNode) node);
        }

        if (asCondition && node.valueType != AMF_Ast.ValueType.BOOLEAN_VALUE) {
            throw AMF_ExpressionException.at(
                describeOperand(node) + ' is not a Boolean and cannot stand alone as a condition',
                node.position
            );
        }
    }

    /**
     * 4.3's compatibility table, enforced in two parts: the operator has to make
     * sense for the type, and the two sides have to be the same type. A NULL
     * literal is typeless and passes both -- Field__c == NULL is the sanctioned
     * presence check.
     */
    private void checkComparison(AMF_Ast.ComparisonNode node) {
        AMF_Ast.ValueType leftType = node.left.valueType;
        AMF_Ast.ValueType rightType = node.right.valueType;

        if (leftType != null && rightType != null && leftType != rightType) {
            throw AMF_ExpressionException.at(
                'Cannot compare ' + describeOperand(node.left) + ' with ' + describeOperand(node.right),
                node.position
            );
        }

        node.operandType = leftType != null ? leftType : rightType;

        if (
            node.operandType != null &&
            EQUALITY_ONLY_TYPES.contains(node.operandType) &&
            !EQUALITY_OPERATORS.contains(node.operator)
        ) {
            throw AMF_ExpressionException.at(
                'Operator ' +
                AMF_Lexer.quote(node.operator) +
                ' is not supported for ' +
                AMF_Ast.labelFor(node.operandType) +
                ' values',
                node.position
            );
        }
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

        AMF_Ast.LiteralNode literal = (AMF_Ast.LiteralNode) node;
        if (literal.isNullLiteral) {
            return 'a NULL literal';
        }
        return 'a ' + AMF_Ast.labelFor(literal.valueType) + ' literal';
    }
}
