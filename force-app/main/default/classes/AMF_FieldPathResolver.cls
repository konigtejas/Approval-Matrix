/**
 * Turns the union of every field path across an object's rules into ONE dynamic
 * SOQL query, run once per object per transaction.
 *
 * Architecture section: 4.4 (field path resolution), 6.1 step 4.
 *
 * The alternative -- querying per rule, or per record -- is how a matrix with a
 * dozen rules turns a 200-record submission into a governor-limit failure. The
 * union is taken across compiled expressions, so a path shared by five rules is
 * selected once, and a catch-all rule with no paths at all costs nothing.
 *
 * Paths arrive canonicalised from AMF_ExprCompiler, which has already resolved
 * every one of them through describe. Re-validating their SHAPE here is
 * deliberate defence in depth: this class concatenates its input into a query
 * string, so it refuses anything that is not a plain dotted identifier rather
 * than trusting its caller to have come through the compiler.
 *
 * Sharing is inherited rather than declared. 11 makes the service the place that
 * decides -- it runs without sharing and authorises the submitter explicitly --
 * and a library class that quietly forces its own answer would take that
 * decision away from the caller that is supposed to be making it.
 */
public inherited sharing class AMF_FieldPathResolver {
    /** Mirrors AMF_ExprCompiler's MVP limit (13.3); one relationship hop. */
    private static final Integer MAX_PATH_SEGMENTS = 2;

    private static final Pattern IDENTIFIER_PATH = Pattern.compile(
        '(?i)^[a-z][a-z0-9_]*(\\.[a-z][a-z0-9_]*)*$'
    );

    /**
     * @param compiledExpressions Every compiled rule for one object.
     * @return The union of their field paths, canonical spelling, deduped.
     *         Empty when every rule is a catch-all.
     */
    public static Set<String> unionPaths(List<AMF_ExprCompiler.CompiledExpression> compiledExpressions) {
        Set<String> paths = new Set<String>();

        if (compiledExpressions == null) {
            return paths;
        }
        for (AMF_ExprCompiler.CompiledExpression compiled : compiledExpressions) {
            if (compiled != null) {
                paths.addAll(compiled.fieldPaths);
            }
        }
        return paths;
    }

    /**
     * Builds the query. Separated from running it so the string itself is
     * assertable -- the shape of this query is the whole of 4.4.
     *
     * @param objectApiName API name of the object being queried.
     * @param fieldPaths    Paths to select, in any order.
     * @return A SOQL string binding a recordIds variable.
     * @throws AMF_ExpressionException On a malformed object name or path.
     */
    public static String buildQuery(String objectApiName, Set<String> fieldPaths) {
        validateIdentifier(objectApiName, 'Object API name');

        // Id first, then alphabetical: the query text is then a pure function of
        // its inputs, which is what lets a test assert it rather than parse it.
        List<String> selected = new List<String>{ 'Id' };
        Set<String> seen = new Set<String>{ 'id' };

        List<String> ordered = fieldPaths == null
            ? new List<String>()
            : new List<String>(fieldPaths);
        ordered.sort();

        for (String path : ordered) {
            validateIdentifier(path, 'Field path');

            if (path.split('\\.').size() > MAX_PATH_SEGMENTS) {
                throw AMF_ExpressionException.of(
                    'Field path ' +
                    AMF_Lexer.quote(path) +
                    ' exceeds the maximum of ' +
                    MAX_PATH_SEGMENTS +
                    ' segments'
                );
            }
            if (seen.add(path.toLowerCase())) {
                selected.add(path);
            }
        }

        return 'SELECT ' +
            String.join(selected, ', ') +
            ' FROM ' +
            objectApiName +
            ' WHERE Id IN :recordIds';
    }

    /**
     * Runs the query built by buildQuery.
     *
     * @param objectApiName API name of the object being queried.
     * @param fieldPaths    The union of paths every rule for that object needs.
     * @param recordIds     The records being submitted.
     * @return Those records, keyed by Id, each carrying every requested path.
     *         Empty when recordIds is empty -- no query is run.
     */
    public static Map<Id, SObject> load(
        String objectApiName,
        Set<String> fieldPaths,
        Set<Id> recordIds
    ) {
        if (recordIds == null || recordIds.isEmpty()) {
            return new Map<Id, SObject>();
        }

        String soql = buildQuery(objectApiName, fieldPaths);
        return new Map<Id, SObject>(Database.query(soql));
    }

    private static void validateIdentifier(String value, String label) {
        if (String.isBlank(value) || !IDENTIFIER_PATH.matcher(value).matches()) {
            throw AMF_ExpressionException.of(
                label + ' ' + AMF_Lexer.quote(String.valueOf(value)) + ' is not a valid identifier'
            );
        }
    }
}
