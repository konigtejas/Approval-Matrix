/**
 * Compiles each rule's expression once per transaction and hands out the result.
 *
 * Architecture section: 4.5 (caching), 4.2 (pipeline), 6.1 step 3.
 *
 * Compilation is the expensive half of the pipeline -- describe calls, schema
 * walks -- and evaluation is cheap. A submission of 200 records against 12 rules
 * must not compile 2,400 times, so the engine calls this and never
 * AMF_ExprCompiler directly.
 *
 * THE KEY IS DeveloperName + Version__c, per 4.5, and that is a design statement
 * rather than an implementation detail: an admin who edits an expression bumps
 * Version__c, which changes the key, which invalidates the entry naturally. There
 * is no flush mechanism and there is nothing to remember to call. The corollary
 * is that editing an expression WITHOUT bumping the version is invisible to a
 * transaction that has already compiled the old one -- which is exactly why
 * Rule_Version__c is stamped onto every decision log row (3.3).
 *
 * Failures are deliberately not cached. A compile error throws every time it is
 * asked for, rather than being remembered and replayed, because a negative cache
 * is a second thing that can go stale and 4.6 wants failures loud and repeatable.
 */
public class AMF_ExprCache {
    private static final Map<String, AMF_ExprCompiler.CompiledExpression> CACHE = new Map<String, AMF_ExprCompiler.CompiledExpression>();

    /** Counts real compilations, so a test can prove the cache is being hit. */
    private static Integer compilations = 0;

    /**
     * @param rule The rule whose expression is needed.
     * @return Its compiled expression, from cache when already compiled in this
     *         transaction.
     * @throws AMF_ExpressionException On any compile fault, every time it is
     *         asked for.
     */
    public static AMF_ExprCompiler.CompiledExpression get(AMF_RuleDefinition rule) {
        if (rule == null) {
            throw AMF_ExpressionException.of('Cannot compile a null rule');
        }

        String key = keyFor(rule);
        AMF_ExprCompiler.CompiledExpression cached = CACHE.get(key);

        if (cached != null) {
            return cached;
        }

        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(
            rule.objectApiName,
            rule.expression
        );
        CACHE.put(key, compiled);
        compilations++;
        return compiled;
    }

    /**
     * The cache key. DeveloperName is unique across the Custom Metadata type, so
     * the object API name is not part of it -- one rule governs one object.
     *
     * @param rule The rule.
     * @return Its cache key.
     */
    @TestVisible
    private static String keyFor(AMF_RuleDefinition rule) {
        return rule.developerName + '|' + rule.version;
    }

    /**
     * Test seam only. A static map survives between test methods in the same
     * class, which would let one test's compilation satisfy another's assertion
     * about how many compilations happened.
     */
    @TestVisible
    private static void reset() {
        CACHE.clear();
        compilations = 0;
    }

    /**
     * @return How many expressions have actually been compiled since the last
     *         reset, as opposed to served from cache.
     */
    @TestVisible
    private static Integer getCompilations() {
        return compilations;
    }
}
