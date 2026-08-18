/**
 * The abstract syntax tree the parser produces and the evaluator walks.
 *
 * Architecture section: 4.1 (grammar), 4.2 (node types).
 *
 * Every node carries the character position of the token that produced it, so a
 * failure found during static analysis -- long after lexing -- can still point at
 * the offending character (4.2).
 *
 * Nodes are decorated in two passes. The parser sets everything it can know from
 * syntax alone: shape, operator, position, and the valueType of a literal. The
 * compiler sets what needs the schema: the valueType of a field path, and the
 * operandType of a comparison. By the time AMF_Evaluator sees a tree it needs no
 * describe call of its own, which is what makes evaluation the cheap half of the
 * pipeline (4.5).
 *
 * ADDING A DEFERRED CONSTRUCT (13.3: IN, CONTAINS, STARTS_WITH, NOT, TODAY(n),
 * multipicklist) means adding a node class here and one branch in each of the
 * parser, compiler and evaluator. Nothing existing changes shape, and nothing
 * here is written around their absence -- there is simply no UnaryNode or
 * ListNode yet, because nothing yet produces one.
 */
public class AMF_Ast {

    /**
     * The type vocabulary the compiler resolves field paths and literals into.
     * Deliberately coarser than Schema.DisplayType: the grammar cares that a
     * value is numeric, not whether it is Currency or Percent (4.3).
     *
     * BOOLEAN and DATE carry a _VALUE suffix because both are reserved
     * identifiers in Apex and will not compile as enum constants. labelFor is
     * what keeps that platform detail out of the error messages an admin reads.
     */
    public enum ValueType {
        NUMERIC,
        TEXT,
        BOOLEAN_VALUE,
        DATE_VALUE
    }

    private static final Map<ValueType, String> TYPE_LABELS = new Map<ValueType, String>{
        ValueType.NUMERIC => 'numeric',
        ValueType.TEXT => 'text',
        ValueType.BOOLEAN_VALUE => 'boolean',
        ValueType.DATE_VALUE => 'date'
    };

    /**
     * @param valueType The type, or null for the typeless NULL literal.
     * @return How that type is named in an error message.
     */
    public static String labelFor(ValueType valueType) {
        return valueType == null ? 'unknown' : TYPE_LABELS.get(valueType);
    }

    /**
     * Base of every node. valueType is null until something can determine it,
     * and stays null for the NULL literal, which by design has no type and is
     * comparable with every other type (4.3).
     */
    public abstract class Node {
        public Integer position;
        public ValueType valueType;
    }

    /** A logical combination: '&&' or '||' (4.1). */
    public class BinaryNode extends Node {
        public String operator;
        public Node left;
        public Node right;

        public BinaryNode(String operator, Node left, Node right, Integer position) {
            this.operator = operator;
            this.left = left;
            this.right = right;
            this.position = position;
            this.valueType = AMF_Ast.ValueType.BOOLEAN_VALUE;
        }
    }

    /**
     * operand comp_op operand. operandType is the resolved common type of the two
     * sides, set by the compiler; it is null only when both sides are NULL
     * literals, which the evaluator's null rules answer without needing a type.
     */
    public class ComparisonNode extends Node {
        public String operator;
        public Node left;
        public Node right;
        public ValueType operandType;

        public ComparisonNode(String operator, Node left, Node right, Integer position) {
            this.operator = operator;
            this.left = left;
            this.right = right;
            this.position = position;
            this.valueType = AMF_Ast.ValueType.BOOLEAN_VALUE;
        }
    }

    /**
     * A field path: one segment for a local field, two for a relationship hop.
     *
     * segments holds the identifiers exactly as the admin typed them. path holds
     * the canonical API-name spelling the compiler resolves them to, and is what
     * the evaluator reads and what keys the decision log's evaluated-values JSON
     * (3.3) -- so the audit record reads the same whether the rule said
     * Account__r.Name or account__r.name.
     */
    public class FieldNode extends Node {
        public List<String> segments;
        public String path;

        public FieldNode(List<String> segments, Integer position) {
            this.segments = segments;
            this.path = String.join(segments, '.');
            this.position = position;
        }
    }

    /**
     * NUMBER, 'STRING', DATE, TRUE, FALSE or NULL (13.3).
     *
     * isNullLiteral distinguishes the NULL keyword from a typed literal that
     * happens to hold null. The two are not the same thing: NULL is the only
     * literal that compares against every type.
     */
    public class LiteralNode extends Node {
        public Object value;
        public Boolean isNullLiteral;

        public LiteralNode(Object value, ValueType valueType, Integer position) {
            this.value = value;
            this.valueType = valueType;
            this.position = position;
            this.isNullLiteral = false;
        }

        public LiteralNode(Integer position) {
            this.value = null;
            this.valueType = null;
            this.position = position;
            this.isNullLiteral = true;
        }
    }
}
