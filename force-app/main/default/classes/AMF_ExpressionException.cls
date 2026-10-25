/**
 * The one error type the expression package raises, from lexing through to
 * evaluation, always carrying the character position that caused it.
 *
 * Architecture section: 4.2 (position-annotated messages), 4.6 (fail loudly).
 *
 * Section 4.6 is the reason this class exists at all. The prior implementation
 * wrapped evaluation in try/catch and returned false, so a malformed expression
 * never matched, forever, silently. Every failure in this package is therefore an
 * exception, never a boolean, and every one of them can say where it happened.
 *
 * POSITION IS A ZERO-BASED CHARACTER INDEX into the expression string. That is
 * the index a reader can hand straight to expression.substring(position), which
 * is what makes an error message actionable rather than decorative. A caller
 * rendering it for an admin is free to add one.
 */
public class AMF_ExpressionException extends Exception {

    /** Zero-based index into expressionText. Null only for errors with no position. */
    public Integer position;

    /** The full expression under compilation, attached by whichever stage caught it. */
    public String expressionText;

    /**
     * The standard form: a positioned failure, rendered exactly as arch doc 4.2
     * specifies -- "Unexpected token ']' at position 34".
     *
     * @param detail   What went wrong, with no trailing punctuation.
     * @param position Zero-based character index.
     * @return The exception, ready to throw.
     */
    public static AMF_ExpressionException at(String detail, Integer position) {
        AMF_ExpressionException e = new AMF_ExpressionException(
            detail + ' at position ' + position
        );
        e.position = position;
        return e;
    }

    /**
     * For the handful of failures with no meaningful character position -- a null
     * record handed to the evaluator, an object API name that does not exist.
     *
     * @param detail What went wrong.
     * @return The exception, ready to throw.
     */
    public static AMF_ExpressionException of(String detail) {
        return new AMF_ExpressionException(detail);
    }

    /**
     * Attaches the source expression, so a caller catching this out of
     * AMF_ExprCache knows which rule to go and look at.
     *
     * @param expressionText The expression being compiled or evaluated.
     * @return This exception, for chaining into a throw.
     */
    public AMF_ExpressionException withExpression(String expressionText) {
        this.expressionText = expressionText;
        return this;
    }
}
