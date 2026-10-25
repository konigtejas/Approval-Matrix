/**
 * The table-driven evaluator suite: every operator against every supported type,
 * all null rules, precedence, both keyword forms, whitespace, relationship paths
 * to three hops, bare TRUE, and -- since M9 -- NOT, IN, CONTAINS, STARTS_WITH,
 * multi-select picklists, TODAY, and the three-valued logic of a broken path.
 *
 * Architecture section: 4.3 (type and null semantics), 4.7 (test strategy).
 *
 * Cases are (expression, record, expected) triples run through the real compiler
 * and the real evaluator, and a method reports EVERY mismatch in its table rather
 * than dying on the first -- when a change to the null rules breaks nine cases,
 * seeing all nine at once is what tells you which rule moved.
 *
 * Zero dependence on org CMDT rows: nothing here reads Approval_Matrix_Rule__mdt,
 * and every record is built in memory. Per arch doc 10, types the pilot object
 * does not carry are exercised against standard objects -- Date on
 * Opportunity.CloseDate, Integer and Double on Account, the multi-select picklist
 * on QuickText.Channel -- rather than by adding fields to Purchase_Request__c that
 * only a test would use. QuickText is built by name, never as a type, so this
 * class still compiles in an org without it.
 */
@IsTest
private class AMF_EvaluatorTest {
    private static final String PURCHASE_REQUEST = 'Purchase_Request__c';

    /** One row of a decision table. */
    private class ExprCase {
        private String expression;
        private SObject record;
        private Boolean expected;

        private ExprCase(String expression, SObject record, Boolean expected) {
            this.expression = expression;
            this.record = record;
            this.expected = expected;
        }
    }

    // ---------------------------------------------------------------- numeric

    @IsTest
    static void everyOperatorAgainstCurrency() {
        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                new ExprCase('Amount__c == 100', pr(100), true),
                new ExprCase('Amount__c == 100', pr(200), false),
                new ExprCase('Amount__c != 100', pr(200), true),
                new ExprCase('Amount__c != 100', pr(100), false),
                new ExprCase('Amount__c > 100', pr(101), true),
                new ExprCase('Amount__c > 100', pr(100), false),
                new ExprCase('Amount__c >= 100', pr(100), true),
                new ExprCase('Amount__c >= 100', pr(99), false),
                new ExprCase('Amount__c < 100', pr(99), true),
                new ExprCase('Amount__c < 100', pr(100), false),
                new ExprCase('Amount__c <= 100', pr(100), true),
                new ExprCase('Amount__c <= 100', pr(101), false),
                new ExprCase('Amount__c == 100.50', pr(100.50), true),
                new ExprCase('Amount__c > 100.49', pr(100.50), true),
                new ExprCase('Amount__c < -5', pr(-10), true),
                new ExprCase('Amount__c < -5', pr(-1), false),
                new ExprCase('Amount__c == -10', pr(-10), true),
                // Literal on the left is the same comparison, mirrored.
                new ExprCase('100 < Amount__c', pr(200), true),
                new ExprCase('100 < Amount__c', pr(50), false)
            }
        );
    }

    @IsTest
    static void integerAndDoubleFieldsCompareAsNumbers() {
        run(
            'Account',
            new List<ExprCase>{
                new ExprCase('NumberOfEmployees > 50', new Account(NumberOfEmployees = 100), true),
                new ExprCase('NumberOfEmployees > 50', new Account(NumberOfEmployees = 10), false),
                new ExprCase('NumberOfEmployees == 100', new Account(NumberOfEmployees = 100), true),
                new ExprCase('AnnualRevenue >= 1000000', new Account(AnnualRevenue = 1000000), true),
                new ExprCase('BillingLatitude > 40.5', new Account(BillingLatitude = 41.0), true),
                new ExprCase('BillingLatitude > 40.5', new Account(BillingLatitude = 40.4), false)
            }
        );
    }

    // ------------------------------------------------------------------- text

    @IsTest
    static void picklistAndStringCompareCaseInsensitively() {
        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                new ExprCase('Region__c == \'APAC\'', pr(1, 'APAC', 'Low'), true),
                // 4.3: text equality is case-insensitive, both ways round.
                new ExprCase('Region__c == \'apac\'', pr(1, 'APAC', 'Low'), true),
                new ExprCase('Region__c == \'ApAc\'', pr(1, 'APAC', 'Low'), true),
                new ExprCase('Region__c == \'EMEA\'', pr(1, 'APAC', 'Low'), false),
                new ExprCase('Region__c != \'EMEA\'', pr(1, 'APAC', 'Low'), true),
                new ExprCase('Region__c != \'APAC\'', pr(1, 'APAC', 'Low'), false),
                new ExprCase('Risk_Level__c == \'High\'', pr(1, 'APAC', 'High'), true)
            }
        );
        run(
            'Account',
            new List<ExprCase>{
                new ExprCase('Name == \'Globex\'', new Account(Name = 'Globex'), true),
                new ExprCase('Name == \'globex\'', new Account(Name = 'Globex'), true),
                new ExprCase('Name != \'Initech\'', new Account(Name = 'Globex'), true)
            }
        );
    }

    @IsTest
    static void referenceFieldsCompareAsText() {
        Id accountId = fakeId(Account.SObjectType, 1);
        Id otherId = fakeId(Account.SObjectType, 2);

        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                new ExprCase('Account__c != NULL', new Purchase_Request__c(Account__c = accountId), true),
                new ExprCase('Account__c == NULL', new Purchase_Request__c(Account__c = accountId), false),
                new ExprCase('Account__c == NULL', new Purchase_Request__c(), true),
                new ExprCase(
                    'Account__c == \'' + accountId + '\'',
                    new Purchase_Request__c(Account__c = accountId),
                    true
                ),
                new ExprCase(
                    'Account__c == \'' + otherId + '\'',
                    new Purchase_Request__c(Account__c = accountId),
                    false
                )
            }
        );
    }

    // ---------------------------------------------------------------- boolean

    @IsTest
    static void checkboxIsIdentityAndStandsAloneAsACondition() {
        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                new ExprCase('Matrix_Submission__c == TRUE', guard(true), true),
                new ExprCase('Matrix_Submission__c == TRUE', guard(false), false),
                new ExprCase('Matrix_Submission__c == FALSE', guard(false), true),
                new ExprCase('Matrix_Submission__c != TRUE', guard(false), true),
                new ExprCase('Matrix_Submission__c != FALSE', guard(true), true),
                // 4.1's bool_atom: a bare Checkbox path is a complete expression.
                new ExprCase('Matrix_Submission__c', guard(true), true),
                new ExprCase('Matrix_Submission__c', guard(false), false),
                // An unset Checkbox reads null in memory, and a null atom is false.
                new ExprCase('Matrix_Submission__c', new Purchase_Request__c(), false),
                new ExprCase('Matrix_Submission__c == TRUE', new Purchase_Request__c(), false),
                new ExprCase('Matrix_Submission__c == NULL', new Purchase_Request__c(), true)
            }
        );
    }

    @IsTest
    static void bareTrueIsTheCatchAllAndKeywordsAreCaseInsensitive() {
        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                // The whole reason PR_Catch_All can exist (3.2).
                new ExprCase('TRUE', pr(1), true),
                new ExprCase('true', pr(1), true),
                new ExprCase('True', pr(1), true),
                new ExprCase('FALSE', pr(1), false),
                new ExprCase('false', pr(1), false)
            }
        );

        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(PURCHASE_REQUEST, 'TRUE');
        Assert.areEqual(
            0,
            compiled.fieldPaths.size(),
            'A catch-all reads no fields, so it must contribute nothing to the 4.4 query'
        );
    }

    // ------------------------------------------------------------------- date

    @IsTest
    static void everyOperatorAgainstDate() {
        Date target = Date.newInstance(2026, 1, 31);

        run(
            'Opportunity',
            new List<ExprCase>{
                new ExprCase('CloseDate == 2026-01-31', opp(target), true),
                new ExprCase('CloseDate == 2026-02-01', opp(target), false),
                new ExprCase('CloseDate != 2026-02-01', opp(target), true),
                new ExprCase('CloseDate > 2026-01-01', opp(target), true),
                new ExprCase('CloseDate > 2026-01-31', opp(target), false),
                new ExprCase('CloseDate >= 2026-01-31', opp(target), true),
                new ExprCase('CloseDate < 2026-02-01', opp(target), true),
                new ExprCase('CloseDate < 2026-01-31', opp(target), false),
                new ExprCase('CloseDate <= 2026-01-31', opp(target), true),
                new ExprCase('CloseDate == NULL', opp(target), false),
                new ExprCase('CloseDate != NULL', opp(target), true)
            }
        );
    }

    // ------------------------------------------------------------- null rules

    @IsTest
    static void nullRulesExhaustively() {
        Purchase_Request__c empty = new Purchase_Request__c();
        Purchase_Request__c filled = pr(100, 'APAC', 'Low');

        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                // null == null is true; null != null is false.
                new ExprCase('Amount__c == NULL', empty, true),
                new ExprCase('Amount__c != NULL', empty, false),
                new ExprCase('NULL == NULL', empty, true),
                new ExprCase('NULL != NULL', empty, false),
                // null against a value, both ways round.
                new ExprCase('Amount__c == 100', empty, false),
                new ExprCase('Amount__c != 100', empty, true),
                new ExprCase('100 == Amount__c', empty, false),
                new ExprCase('Amount__c == NULL', filled, false),
                new ExprCase('Amount__c != NULL', filled, true),
                // null against every ordering operator is false, never an error.
                new ExprCase('Amount__c > 100', empty, false),
                new ExprCase('Amount__c >= 100', empty, false),
                new ExprCase('Amount__c < 100', empty, false),
                new ExprCase('Amount__c <= 100', empty, false),
                new ExprCase('Amount__c > NULL', empty, false),
                // Same rules for text and picklist.
                new ExprCase('Region__c == NULL', empty, true),
                new ExprCase('Region__c != NULL', empty, false),
                new ExprCase('Region__c == \'APAC\'', empty, false),
                new ExprCase('Region__c != \'APAC\'', empty, true),
                // A null operand does not stop the other side of an && or ||.
                new ExprCase('Amount__c == NULL && Region__c == NULL', empty, true),
                new ExprCase('Amount__c > 100 || Region__c == NULL', empty, true)
            }
        );
    }

    // ------------------------------------------------------- two-segment path

    @IsTest
    static void relationshipPathsResolveAndBreakSafely() {
        Purchase_Request__c withAccount = prWithAccount(100, 'Globex');
        Purchase_Request__c withNamelessAccount = prWithAccount(100, null);
        Purchase_Request__c withoutAccount = pr(100);

        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                new ExprCase('Account__r.Name == \'Globex\'', withAccount, true),
                new ExprCase('Account__r.Name == \'globex\'', withAccount, true),
                new ExprCase('Account__r.Name == \'Initech\'', withAccount, false),
                new ExprCase('Account__r.Name != NULL', withAccount, true),
                // Account present, its Name null: the ordinary null rules apply.
                new ExprCase('Account__r.Name == NULL', withNamelessAccount, true),
                new ExprCase('Account__r.Name != NULL', withNamelessAccount, false),
                // No Account at all: the path cannot resolve, so the comparison is
                // false whatever the operator -- INCLUDING == NULL and != NULL.
                // 4.3, and docs/decisions.md 2026-08-18.
                new ExprCase('Account__r.Name == \'Globex\'', withoutAccount, false),
                new ExprCase('Account__r.Name == NULL', withoutAccount, false),
                new ExprCase('Account__r.Name != NULL', withoutAccount, false),
                new ExprCase('Account__r.Name != \'Globex\'', withoutAccount, false),
                // A broken path does not poison the rest of the expression.
                new ExprCase('Account__r.Name == \'Globex\' || Amount__c == 100', withoutAccount, true),
                new ExprCase('Account__r.Name == \'Globex\' && Amount__c == 100', withoutAccount, false)
            }
        );
    }

    // --------------------------------------------------------- precedence etc

    @IsTest
    static void precedenceFollowsSection41() {
        Purchase_Request__c record = pr(50, 'EMEA', 'High');

        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                // a || b && c parses as a || (b && c). Grouped the other way this
                // would be false, which is what makes it a precedence test.
                new ExprCase('TRUE || FALSE && FALSE', record, true),
                new ExprCase('FALSE && FALSE || TRUE', record, true),
                new ExprCase('FALSE || TRUE && FALSE', record, false),
                // Parentheses override, and are the only thing that does.
                new ExprCase('(TRUE || FALSE) && FALSE', record, false),
                new ExprCase('(FALSE || TRUE) && TRUE', record, true),
                // Comparisons bind tighter than both.
                new ExprCase('Amount__c > 100 && Region__c == \'APAC\' || Risk_Level__c == \'High\'', record, true),
                new ExprCase('Amount__c > 100 && (Region__c == \'APAC\' || Risk_Level__c == \'High\')', record, false),
                new ExprCase('Amount__c < 100 && (Region__c == \'APAC\' || Risk_Level__c == \'High\')', record, true),
                // Nesting.
                new ExprCase('((Amount__c < 100))', record, true),
                new ExprCase('(Amount__c < 100 && (Risk_Level__c == \'High\' || FALSE))', record, true)
            }
        );
    }

    @IsTest
    static void whitespaceAndFieldNameCasingDoNotChangeMeaning() {
        Purchase_Request__c record = pr(150000, 'APAC', 'Low');

        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                new ExprCase('Amount__c>100000', record, true),
                new ExprCase('   Amount__c   >   100000   ', record, true),
                new ExprCase('Amount__c > 100000\n&& Region__c == \'APAC\'', record, true),
                new ExprCase('Amount__c > 100000\t&&\tRegion__c == \'APAC\'', record, true),
                new ExprCase('Amount__c>100000&&Region__c==\'APAC\'', record, true),
                // API names are case-insensitive, exactly as they are in SOQL.
                new ExprCase('amount__c > 100000', record, true),
                new ExprCase('AMOUNT__C > 100000', record, true),
                new ExprCase('account__r.name == NULL', record, false)
            }
        );
    }

    // ------------------------------------------------------ NOT and word forms

    @IsTest
    static void negationAndTheWordFormsOfTheLogicalOperators() {
        Purchase_Request__c record = pr(50, 'EMEA', 'High');

        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                new ExprCase('NOT TRUE', record, false),
                new ExprCase('!TRUE', record, false),
                new ExprCase('!FALSE', record, true),
                new ExprCase('NOT NOT TRUE', record, true),
                new ExprCase('!!FALSE', record, false),
                // NOT negates a whole comparison...
                new ExprCase('NOT Region__c == \'APAC\'', record, true),
                new ExprCase('NOT (Region__c == \'EMEA\')', record, false),
                new ExprCase('!(Amount__c > 100)', record, true),
                // ...and binds tighter than AND and OR.
                new ExprCase('NOT Amount__c > 100 && Risk_Level__c == \'High\'', record, true),
                new ExprCase('NOT (Amount__c > 10 && Risk_Level__c == \'High\')', record, false),
                new ExprCase('NOT TRUE OR TRUE', record, true),
                new ExprCase('NOT (TRUE OR TRUE)', record, false),
                new ExprCase('TRUE && NOT FALSE || FALSE', record, true),
                // AND and OR mean && and ||, in any case, at the same precedence.
                new ExprCase('Amount__c > 100 OR Region__c == \'EMEA\'', record, true),
                new ExprCase('Amount__c > 10 AND Region__c == \'APAC\'', record, false),
                new ExprCase('amount__c > 10 and region__c == \'emea\'', record, true),
                new ExprCase('TRUE OR FALSE AND FALSE', record, true),
                new ExprCase('FALSE OR TRUE AND FALSE', record, false),
                new ExprCase('(FALSE OR TRUE) AND TRUE', record, true)
            }
        );
        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                new ExprCase('!Matrix_Submission__c', guard(true), false),
                new ExprCase('NOT Matrix_Submission__c', guard(false), true)
            }
        );
    }

    @IsTest
    static void aNullLeafIsAnOrdinaryValueUnderNegation() {
        // Only a broken PATH is unknown. A null field value follows the
        // two-valued null rules, so negating a false-because-null comparison
        // gives true -- exactly as != already does.
        Purchase_Request__c empty = new Purchase_Request__c();

        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                new ExprCase('NOT (Amount__c > 100)', empty, true),
                new ExprCase('NOT (Amount__c == NULL)', empty, false),
                new ExprCase('NOT (Region__c == \'APAC\')', empty, true),
                new ExprCase('NOT (Account__r.Name == NULL)', prWithAccount(100, null), false),
                new ExprCase('NOT (Account__r.Name != NULL)', prWithAccount(100, null), true)
            }
        );
    }

    @IsTest
    static void aBrokenPathStaysUnknownUnderNegation() {
        // docs/decisions.md 2026-08-18 and 2026-10-08: a path that cannot be
        // resolved must route nothing. Before NOT, "false" was enough; with NOT,
        // the comparison has to be UNKNOWN, or NOT (Account__r.Name == NULL)
        // would be satisfied by a record with no Account at all.
        Purchase_Request__c withoutAccount = pr(100);
        Purchase_Request__c withAccount = prWithAccount(100, 'Globex');
        String unknown = 'Account__r.Name == \'x\'';

        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                new ExprCase('NOT (Account__r.Name == NULL)', withoutAccount, false),
                new ExprCase('NOT (Account__r.Name != NULL)', withoutAccount, false),
                new ExprCase('NOT (Account__r.Name == NULL)', withAccount, true),
                new ExprCase('!(Account__r.Name == \'Initech\')', withoutAccount, false),
                new ExprCase('!(Account__r.Name == \'Initech\')', withAccount, true),
                // Kleene's tables: unknown decides nothing that the other side
                // does not already decide.
                new ExprCase(unknown + ' && TRUE', withoutAccount, false),
                new ExprCase(unknown + ' || TRUE', withoutAccount, true),
                new ExprCase(unknown + ' || FALSE', withoutAccount, false),
                new ExprCase('NOT (' + unknown + ')', withoutAccount, false),
                new ExprCase('NOT NOT (' + unknown + ')', withoutAccount, false),
                new ExprCase('NOT (' + unknown + ' && FALSE)', withoutAccount, true),
                new ExprCase('NOT (' + unknown + ' && TRUE)', withoutAccount, false),
                new ExprCase('NOT (' + unknown + ' || TRUE)', withoutAccount, false),
                new ExprCase('NOT (' + unknown + ' || FALSE)', withoutAccount, false),
                new ExprCase('NOT (Account__r.Name == NULL) || Amount__c == 100', withoutAccount, true),
                new ExprCase('NOT (Account__r.Name == NULL) && Amount__c == 100', withoutAccount, false),
                // Every new operator on a broken path is unknown too.
                new ExprCase('Account__r.Name IN (\'Globex\')', withoutAccount, false),
                new ExprCase('Account__r.Name NOT IN (\'Globex\')', withoutAccount, false),
                new ExprCase('NOT Account__r.Name CONTAINS \'G\'', withoutAccount, false),
                new ExprCase('NOT Account__r.Name STARTS_WITH \'G\'', withoutAccount, false),
                // And so is a bare Checkbox reached through one.
                new ExprCase('Account__r.IsDeleted', withoutAccount, false),
                new ExprCase('NOT Account__r.IsDeleted', withoutAccount, false),
                new ExprCase('NOT Account__r.IsDeleted', prWithAccount(1, 'Globex'), true)
            }
        );
    }

    // ------------------------------------------------------------ IN, NOT IN

    @IsTest
    static void inAndNotInAgainstText() {
        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                new ExprCase('Region__c IN (\'APAC\', \'EMEA\')', pr(1, 'APAC', 'Low'), true),
                new ExprCase('Region__c IN (\'APAC\', \'EMEA\')', pr(1, 'LATAM', 'Low'), false),
                new ExprCase('Region__c IN (\'apac\')', pr(1, 'APAC', 'Low'), true),
                new ExprCase('Region__c NOT IN (\'APAC\', \'EMEA\')', pr(1, 'LATAM', 'Low'), true),
                new ExprCase('Region__c NOT IN (\'APAC\', \'EMEA\')', pr(1, 'APAC', 'Low'), false),
                new ExprCase('Region__c not in (\'emea\')', pr(1, 'APAC', 'Low'), true),
                new ExprCase('Risk_Level__c IN (\'High\')', pr(1, 'APAC', 'High'), true),
                new ExprCase('Region__c IN (\'APAC\') && Amount__c IN (1, 2)', pr(2, 'APAC', 'Low'), true),
                new ExprCase('Account__r.Name IN (\'Initech\', \'Globex\')', prWithAccount(1, 'Globex'), true),
                // 4.3: IN with a null operand is false, so NOT IN is true.
                new ExprCase('Region__c IN (\'APAC\')', new Purchase_Request__c(), false),
                new ExprCase('Region__c NOT IN (\'APAC\')', new Purchase_Request__c(), true)
            }
        );
    }

    @IsTest
    static void inAndNotInAgainstNumbersDatesAndBooleans() {
        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                new ExprCase('Amount__c IN (100, 200.50, -5)', pr(200.50), true),
                new ExprCase('Amount__c IN (100, 200.50, -5)', pr(-5), true),
                new ExprCase('Amount__c IN (100, 200.50, -5)', pr(201), false),
                new ExprCase('Amount__c IN (100)', new Purchase_Request__c(), false),
                new ExprCase('Amount__c NOT IN (100)', pr(100), false),
                new ExprCase('Amount__c NOT IN (100)', pr(100.01), true),
                new ExprCase('Matrix_Submission__c IN (TRUE)', guard(true), true),
                new ExprCase('Matrix_Submission__c IN (TRUE)', guard(false), false)
            }
        );
        run(
            'Account',
            new List<ExprCase>{
                // An Integer field against Decimal literals: one numeric currency.
                new ExprCase('NumberOfEmployees IN (10, 100)', new Account(NumberOfEmployees = 100), true),
                new ExprCase('NumberOfEmployees NOT IN (10, 100)', new Account(NumberOfEmployees = 99), true)
            }
        );
        Date target = Date.newInstance(2026, 1, 31);
        run(
            'Opportunity',
            new List<ExprCase>{
                new ExprCase('CloseDate IN (2026-01-31, 2026-02-28)', opp(target), true),
                new ExprCase('CloseDate NOT IN (2026-02-28)', opp(target), true),
                new ExprCase('CloseDate IN (2026-02-28)', opp(target), false)
            }
        );
    }

    // ------------------------------------------------- CONTAINS, STARTS_WITH

    @IsTest
    static void containsAndStartsWithMatchTextCaseInsensitively() {
        run(
            'Account',
            new List<ExprCase>{
                new ExprCase('Name CONTAINS \'lob\'', new Account(Name = 'Globex'), true),
                new ExprCase('Name CONTAINS \'LOB\'', new Account(Name = 'Globex'), true),
                new ExprCase('Name CONTAINS \'xyz\'', new Account(Name = 'Globex'), false),
                new ExprCase('Name STARTS_WITH \'glo\'', new Account(Name = 'Globex'), true),
                new ExprCase('Name STARTS_WITH \'lob\'', new Account(Name = 'Globex'), false),
                new ExprCase('Name contains \'G\' and Name starts_with \'g\'', new Account(Name = 'Globex'), true),
                // The empty string is in every string.
                new ExprCase('Name CONTAINS \'\'', new Account(Name = 'Globex'), true),
                // A field may be the text searched for.
                new ExprCase('Name CONTAINS Site', new Account(Name = 'Globex Corp', Site = 'corp'), true),
                new ExprCase('Name STARTS_WITH Site', new Account(Name = 'Globex Corp', Site = 'corp'), false),
                // Null on either side is false; NOT of it is true (4.3).
                new ExprCase('Name CONTAINS \'a\'', new Account(), false),
                new ExprCase('Name CONTAINS Site', new Account(Name = 'Globex'), false),
                new ExprCase('NOT Name CONTAINS \'a\'', new Account(), true),
                new ExprCase('Name STARTS_WITH \'a\'', new Account(), false)
            }
        );
        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                new ExprCase('Region__c STARTS_WITH \'AP\'', pr(1, 'APAC', 'Low'), true),
                new ExprCase('Region__c CONTAINS \'pa\'', pr(1, 'APAC', 'Low'), true),
                new ExprCase('Account__r.Name CONTAINS \'obe\'', prWithAccount(1, 'Globex'), true)
            }
        );
    }

    // ------------------------------------------------- multi-select picklists

    @IsTest
    static void multiSelectPicklistsCompareAsSets() {
        SObject emailAndPhone = quickText('Email;Phone');
        SObject blank = quickText(null);

        run(
            'QuickText',
            new List<ExprCase>{
                // == is an exact set match: any order, any case, spaces trimmed.
                new ExprCase('Channel == \'Email;Phone\'', emailAndPhone, true),
                new ExprCase('Channel == \'phone;EMAIL\'', emailAndPhone, true),
                new ExprCase('Channel == \' Email ; Phone \'', emailAndPhone, true),
                new ExprCase('Channel == \'Email\'', emailAndPhone, false),
                new ExprCase('Channel == \'Email;Phone;Portal\'', emailAndPhone, false),
                new ExprCase('Channel != \'Email\'', emailAndPhone, true),
                new ExprCase('\'Email;Phone\' == Channel', emailAndPhone, true),
                // CONTAINS is membership: every value named is selected.
                new ExprCase('Channel CONTAINS \'Email\'', emailAndPhone, true),
                new ExprCase('Channel CONTAINS \'email\'', emailAndPhone, true),
                new ExprCase('Channel CONTAINS \'Phone;Email\'', emailAndPhone, true),
                new ExprCase('Channel CONTAINS \'Email;Portal\'', emailAndPhone, false),
                new ExprCase('Channel CONTAINS \'Portal\'', emailAndPhone, false),
                new ExprCase('NOT Channel CONTAINS \'Portal\'', emailAndPhone, true),
                // Membership, not substring: 'Mail' is not a value that is selected.
                new ExprCase('Channel CONTAINS \'Mail\'', emailAndPhone, false),
                // A blank multi-select picklist is null, and the null rules apply.
                new ExprCase('Channel == NULL', blank, true),
                new ExprCase('Channel != NULL', blank, false),
                new ExprCase('Channel != NULL', emailAndPhone, true),
                new ExprCase('Channel == \'Email\'', blank, false),
                new ExprCase('Channel != \'Email\'', blank, true),
                new ExprCase('Channel CONTAINS \'Email\'', blank, false)
            }
        );
    }

    // ------------------------------------------------------------------ TODAY

    @IsTest
    static void todayAndItsOffsetsCompareAsDates() {
        AMF_Evaluator.todayOverride = Date.newInstance(2026, 3, 15);

        run(
            'Opportunity',
            new List<ExprCase>{
                new ExprCase('CloseDate == TODAY', opp(Date.newInstance(2026, 3, 15)), true),
                new ExprCase('CloseDate == TODAY()', opp(Date.newInstance(2026, 3, 15)), true),
                new ExprCase('CloseDate == TODAY(+0)', opp(Date.newInstance(2026, 3, 15)), true),
                new ExprCase('CloseDate < TODAY(1)', opp(Date.newInstance(2026, 3, 15)), true),
                new ExprCase('CloseDate > TODAY(-1)', opp(Date.newInstance(2026, 3, 15)), true),
                new ExprCase('CloseDate == TODAY(7)', opp(Date.newInstance(2026, 3, 22)), true),
                new ExprCase('CloseDate <= TODAY(+7)', opp(Date.newInstance(2026, 3, 22)), true),
                new ExprCase('CloseDate > TODAY(6)', opp(Date.newInstance(2026, 3, 22)), true),
                new ExprCase('CloseDate >= TODAY(-14)', opp(Date.newInstance(2026, 3, 1)), true),
                new ExprCase('CloseDate >= TODAY(-13)', opp(Date.newInstance(2026, 3, 1)), false),
                // Across a month end.
                new ExprCase('CloseDate == TODAY(30)', opp(Date.newInstance(2026, 4, 14)), true),
                new ExprCase('CloseDate IN (TODAY, TODAY(1))', opp(Date.newInstance(2026, 3, 16)), true),
                new ExprCase('CloseDate NOT IN (TODAY, TODAY(1))', opp(Date.newInstance(2026, 3, 17)), true),
                new ExprCase('TODAY > 2026-01-01', new Opportunity(), true),
                new ExprCase('today == TODAY', new Opportunity(), true),
                new ExprCase('CloseDate < TODAY', new Opportunity(), false)
            }
        );
    }

    @IsTest
    static void todayIsTheRunningUsersDateUnlessPinned() {
        AMF_Evaluator.Result result = AMF_Evaluator.evaluate(
            AMF_ExprCompiler.compile('Opportunity', 'CloseDate == TODAY'),
            opp(Date.today())
        );

        Assert.isTrue(result.matched, 'Unpinned, TODAY is Date.today(): the running user\'s local date');
        Assert.areEqual(Date.today(), result.evaluatedValues.get(AMF_Evaluator.TODAY_KEY), 'And that is what is recorded');
    }

    // ------------------------------------------------------ three-hop paths

    @IsTest
    static void threeHopPathsResolveAndBreakSafelyAtEveryHop() {
        Purchase_Request__c full = prWithOwnerProfile('System Administrator');
        Purchase_Request__c ownerWithoutProfile = prWithOwner();
        Purchase_Request__c accountWithoutOwner = prWithAccount(1, 'Globex');
        Purchase_Request__c noAccount = pr(1);
        String path = 'Account__r.Owner.Profile.Name';

        run(
            PURCHASE_REQUEST,
            new List<ExprCase>{
                new ExprCase(path + ' == \'System Administrator\'', full, true),
                new ExprCase(path + ' STARTS_WITH \'system\'', full, true),
                new ExprCase('account__r.owner.profile.name IN (\'Standard User\', \'System Administrator\')', full, true),
                new ExprCase(path + ' != NULL', full, true),
                // A null at any hop is a broken path: unknown, even under NOT.
                new ExprCase(path + ' == NULL', ownerWithoutProfile, false),
                new ExprCase('NOT (' + path + ' == NULL)', ownerWithoutProfile, false),
                new ExprCase(path + ' == NULL', accountWithoutOwner, false),
                new ExprCase(path + ' != NULL', accountWithoutOwner, false),
                new ExprCase(path + ' == NULL', noAccount, false),
                new ExprCase(path + ' == NULL || Amount__c == 1', noAccount, true)
            }
        );
    }

    // ------------------------------------------------------- evaluated values

    @IsTest
    static void evaluatedValuesRecordWhatTodayMeant() {
        AMF_Evaluator.todayOverride = Date.newInstance(2026, 3, 15);

        AMF_Evaluator.Result withToday = AMF_Evaluator.evaluate(
            AMF_ExprCompiler.compile('Opportunity', 'CloseDate < TODAY(30) && Amount > 5'),
            new Opportunity(CloseDate = Date.newInstance(2026, 4, 1), Amount = 10)
        );

        Assert.isTrue(withToday.matched, 'Apr 1 is within 30 days of Mar 15');
        Assert.areEqual(
            new Set<String>{ 'CloseDate', 'Amount', AMF_Evaluator.TODAY_KEY },
            withToday.evaluatedValues.keySet(),
            'A decision that depended on the date must record the date (3.3, 8)'
        );
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(withToday.toJson());
        Assert.areEqual('2026-03-15', parsed.get('TODAY'), 'Recorded as an ISO day, the base date before any offset');

        AMF_Evaluator.Result withoutToday = AMF_Evaluator.evaluate(
            AMF_ExprCompiler.compile('Opportunity', 'CloseDate < 2026-04-30'),
            new Opportunity(CloseDate = Date.newInstance(2026, 4, 1))
        );
        Assert.isFalse(
            withoutToday.evaluatedValues.containsKey(AMF_Evaluator.TODAY_KEY),
            'A rule that does not use TODAY records no date'
        );
    }

    @IsTest
    static void evaluatedValuesRecordEveryPathTheExpressionNames() {
        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(
            PURCHASE_REQUEST,
            'Amount__c > 100000 && Region__c == \'APAC\''
        );
        AMF_Evaluator.Result result = AMF_Evaluator.evaluate(compiled, pr(150000, 'APAC', 'Low'));

        Assert.isTrue(result.matched, 'High-value APAC must match its own rule');
        Assert.areEqual(
            new Set<String>{ 'Amount__c', 'Region__c' },
            result.evaluatedValues.keySet(),
            'Evaluated_Values__c must name every path the expression read (3.3)'
        );
        Assert.areEqual(150000, result.evaluatedValues.get('Amount__c'), 'Values are the record values');
        Assert.areEqual('APAC', result.evaluatedValues.get('Region__c'), 'Values are the record values');
    }

    @IsTest
    static void evaluatedValuesSurviveShortCircuiting() {
        // FALSE && ... never evaluates the right-hand side, but the audit record
        // must still say which fields the rule is written against.
        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(
            PURCHASE_REQUEST,
            'FALSE && Amount__c > 100'
        );
        AMF_Evaluator.Result result = AMF_Evaluator.evaluate(compiled, pr(150000));

        Assert.isFalse(result.matched, 'FALSE && anything is false');
        Assert.isTrue(
            result.evaluatedValues.containsKey('Amount__c'),
            'Short-circuiting must not change what the decision log says was read'
        );
        Assert.areEqual(150000, result.evaluatedValues.get('Amount__c'), 'And it must be the real value');
    }

    @IsTest
    static void evaluatedValueKeysAreCanonicalApiNames() {
        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(
            PURCHASE_REQUEST,
            'amount__c > 1 && account__r.name != NULL'
        );
        AMF_Evaluator.Result result = AMF_Evaluator.evaluate(compiled, prWithAccount(100, 'Globex'));

        Assert.areEqual(
            new Set<String>{ 'Amount__c', 'Account__r.Name' },
            result.evaluatedValues.keySet(),
            'The audit JSON must read in API-name spelling however the rule was typed'
        );
        Assert.areEqual('Globex', result.evaluatedValues.get('Account__r.Name'), 'Two hops resolve');
    }

    @IsTest
    static void brokenPathRecordsANullValueRatherThanFailing() {
        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(
            PURCHASE_REQUEST,
            'Account__r.Name == \'Globex\''
        );
        AMF_Evaluator.Result result = AMF_Evaluator.evaluate(compiled, pr(100));

        Assert.isFalse(result.matched, 'An unresolvable path matches nothing');
        Assert.isTrue(
            result.evaluatedValues.containsKey('Account__r.Name'),
            'The log still has to show which path could not be resolved'
        );
        Assert.areEqual(null, result.evaluatedValues.get('Account__r.Name'), 'And that it read as null');
    }

    @IsTest
    static void evaluatedValuesSerialiseToJson() {
        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(
            'Opportunity',
            'CloseDate > 2026-01-01 && Amount > 5'
        );
        AMF_Evaluator.Result result = AMF_Evaluator.evaluate(
            compiled,
            new Opportunity(CloseDate = Date.newInstance(2026, 1, 31), Amount = 10)
        );

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(result.toJson());
        Assert.areEqual(
            2,
            parsed.size(),
            'Evaluated_Values__c is JSON, and a Date value must not break the serialisation'
        );
        Assert.areEqual('2026-01-31', parsed.get('CloseDate'), 'Dates serialise as ISO days');
    }

    // ------------------------------------------------------- defensive guards

    @IsTest
    static void orderingOperatorOnTextThrowsRatherThanReturningFalse() {
        // The compiler rejects Region__c > 'APAC', so this tree cannot come from
        // it. Handing it to the evaluator directly proves the runtime guard
        // throws instead of falling through to false, which is 4.6's whole point.
        AMF_ExprCompiler.CompiledExpression compiled = handBuilt(
            comparison('>', AMF_Ast.ValueType.TEXT, 'APAC', 'EMEA')
        );

        try {
            AMF_Evaluator.evaluate(compiled, pr(1));
            Assert.fail('An ordering operator on text must throw, never return false');
        } catch (AMF_ExpressionException e) {
            Assert.isTrue(
                e.getMessage().contains('cannot be applied to text values'),
                'The guard must name the operator and the type. Got: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void unknownOperandTypeThrowsRatherThanReturningFalse() {
        AMF_ExprCompiler.CompiledExpression compiled = handBuilt(comparison('==', null, 'a', 'b'));

        try {
            AMF_Evaluator.evaluate(compiled, pr(1));
            Assert.fail('A comparison with no resolved type must throw');
        } catch (AMF_ExpressionException e) {
            Assert.isTrue(
                e.getMessage().contains('unknown type'),
                'The guard must say the type could not be determined. Got: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void anOrderingOperatorTheGrammarCannotProduceThrows() {
        // The parser emits only the six comparison operators, so this tree is
        // again one the pipeline could not have built. The guard exists so that a
        // future operator added to the parser and forgotten here fails loudly
        // instead of quietly evaluating to false.
        AMF_Ast.ComparisonNode node = numericComparison('LIKE', 1, 2);

        try {
            AMF_Evaluator.evaluate(handBuilt(node), pr(1));
            Assert.fail('An operator the evaluator does not implement must throw');
        } catch (AMF_ExpressionException e) {
            Assert.isTrue(
                e.getMessage().contains('\'LIKE\'') && e.getMessage().contains('numeric values'),
                'The guard must name the operator and the type. Got: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void aContainsTheCompilerCouldNotProduceThrows() {
        // CONTAINS on a numeric operand type: the compiler refuses it, so this
        // tree is hand-built to prove the evaluator throws rather than guessing.
        AMF_Ast.ComparisonNode node = numericComparison('CONTAINS', 1, 2);

        try {
            AMF_Evaluator.evaluate(handBuilt(node), pr(1));
            Assert.fail('CONTAINS on numbers must throw, never return false');
        } catch (AMF_ExpressionException e) {
            Assert.isTrue(
                e.getMessage().contains('\'CONTAINS\'') && e.getMessage().contains('numeric values'),
                'The guard must name the operator and the type. Got: ' + e.getMessage()
            );
        }
    }

    @IsTest
    static void anInListWithNoResolvedTypeThrows() {
        AMF_Ast.ComparisonNode node = new AMF_Ast.ComparisonNode(
            'IN',
            new AMF_Ast.LiteralNode('a', AMF_Ast.ValueType.TEXT, 0),
            new AMF_Ast.ListNode(
                new List<AMF_Ast.Node>{ new AMF_Ast.LiteralNode('b', AMF_Ast.ValueType.TEXT, 0) },
                0
            ),
            0
        );

        try {
            AMF_Evaluator.evaluate(handBuilt(node), pr(1));
            Assert.fail('An IN with no operand type must throw');
        } catch (AMF_ExpressionException e) {
            Assert.isTrue(e.getMessage().contains('unknown type'), 'Got: ' + e.getMessage());
        }
    }

    @IsTest
    static void aNullInAHandBuiltListMatchesNothing() {
        // The compiler refuses NULL in a list. Were one to arrive, the ordinary
        // null rule decides it -- a value never equals NULL -- rather than a cast
        // failing on it.
        AMF_Ast.ComparisonNode node = new AMF_Ast.ComparisonNode(
            'IN',
            new AMF_Ast.LiteralNode(5, AMF_Ast.ValueType.NUMERIC, 0),
            new AMF_Ast.ListNode(new List<AMF_Ast.Node>{ new AMF_Ast.LiteralNode(0) }, 0),
            0
        );
        node.operandType = AMF_Ast.ValueType.NUMERIC;

        Assert.isFalse(AMF_Evaluator.evaluate(handBuilt(node), pr(1)).matched, '5 is not in (NULL)');
    }

    @IsTest
    static void valueSetsSplitTrimAndIgnoreCase() {
        Assert.areEqual(
            new Set<String>{ 'email', 'phone' },
            AMF_Evaluator.valueSet(' Email ;;PHONE; '),
            'Split on ;, trimmed, blanks dropped, lower-cased'
        );
        Assert.isTrue(AMF_Evaluator.valueSet(null).isEmpty(), 'Null is the empty set');
        Assert.isTrue(AMF_Evaluator.valueSet(' ; ').isEmpty(), 'And so is a list of nothing');
    }

    @IsTest
    static void numbersCompareWhicheverApexTypeTheyArriveAs() {
        // A Currency field reads as Decimal, an Integer field as Integer, a Long
        // one as Long and a geolocation as Double. All four have to compare
        // against a Decimal literal without an equality surprise -- which they do
        // through a single cast, because Apex reports every boxed numeric as
        // `instanceof Decimal` (see AMF_Evaluator.toDecimal). This test is what
        // would notice if that platform behaviour ever changed.
        Map<String, Object> sameValue = new Map<String, Object>{
            'Decimal' => (Decimal) 42,
            'Integer' => (Integer) 42,
            'Long' => (Long) 42,
            'Double' => (Double) 42,
            'String' => '42'
        };

        for (String apexType : sameValue.keySet()) {
            AMF_Evaluator.Result equal = AMF_Evaluator.evaluate(
                handBuilt(numericComparison('==', sameValue.get(apexType), 42)),
                pr(1)
            );
            AMF_Evaluator.Result greater = AMF_Evaluator.evaluate(
                handBuilt(numericComparison('>', sameValue.get(apexType), 41)),
                pr(1)
            );

            Assert.isTrue(equal.matched, apexType + ' must equal the Decimal literal 42');
            Assert.isTrue(greater.matched, apexType + ' must order against the Decimal literal 41');
        }

        Assert.isTrue(
            AMF_Evaluator.evaluate(handBuilt(numericComparison('>', (Long) 5000000000L, 42)), pr(1)).matched,
            'A Long beyond Integer range must not overflow on its way to Decimal'
        );
    }

    @IsTest
    static void nullArgumentsThrow() {
        try {
            AMF_Evaluator.evaluate(null, pr(1));
            Assert.fail('A null compiled expression must throw');
        } catch (AMF_ExpressionException e) {
            Assert.isTrue(e.getMessage().contains('null compiled expression'), e.getMessage());
        }

        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(PURCHASE_REQUEST, 'TRUE');
        try {
            AMF_Evaluator.evaluate(compiled, null);
            Assert.fail('A null record must throw');
        } catch (AMF_ExpressionException e) {
            Assert.isTrue(e.getMessage().contains('null record'), e.getMessage());
        }
    }

    @IsTest
    static void aFieldTheQueryDidNotSelectThrowsRatherThanEvaluatingFalse() {
        // 4.6: a record queried without a field the expression needs is a real
        // fault. It must surface as an exception and block, not read as null.
        insert new Purchase_Request__c(Amount__c = 100, Region__c = 'APAC');
        Purchase_Request__c thin = [SELECT Id FROM Purchase_Request__c LIMIT 1];

        AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(
            PURCHASE_REQUEST,
            'Amount__c > 50'
        );

        try {
            AMF_Evaluator.evaluate(compiled, thin);
            Assert.fail('Evaluating an unqueried field must throw, not return false');
        } catch (System.SObjectException e) {
            Assert.isTrue(
                e.getMessage().contains('Amount__c'),
                'The platform error must name the missing field. Got: ' + e.getMessage()
            );
        }
    }

    // ------------------------------------------------------------- test plumbing

    /**
     * Runs a decision table, reporting every mismatch rather than the first.
     *
     * @param objectApiName Object the expressions are compiled against.
     * @param cases         The table.
     */
    private static void run(String objectApiName, List<ExprCase> cases) {
        List<String> failures = new List<String>();

        for (ExprCase testCase : cases) {
            AMF_ExprCompiler.CompiledExpression compiled = AMF_ExprCompiler.compile(
                objectApiName,
                testCase.expression
            );
            AMF_Evaluator.Result result = AMF_Evaluator.evaluate(compiled, testCase.record);

            if (result.matched != testCase.expected) {
                failures.add(
                    '  ' +
                    testCase.expression +
                    '  ->  expected ' +
                    testCase.expected +
                    ', got ' +
                    result.matched
                );
            }
        }

        Assert.areEqual(
            0,
            failures.size(),
            failures.size() + ' of ' + cases.size() + ' cases failed:\n' + String.join(failures, '\n')
        );
    }

    private static Purchase_Request__c pr(Decimal amount) {
        return new Purchase_Request__c(Amount__c = amount);
    }

    private static Purchase_Request__c pr(Decimal amount, String region, String riskLevel) {
        return new Purchase_Request__c(Amount__c = amount, Region__c = region, Risk_Level__c = riskLevel);
    }

    private static Purchase_Request__c guard(Boolean submitted) {
        return new Purchase_Request__c(Matrix_Submission__c = submitted);
    }

    private static Opportunity opp(Date closeDate) {
        return new Opportunity(CloseDate = closeDate);
    }

    /**
     * An in-memory record carrying a populated parent relationship. Assigning
     * Account__r directly is not possible on a record that was never queried, so
     * the JSON round trip is the only way to build a two-hop fixture without DML.
     *
     * @param amount      Amount__c.
     * @param accountName Account__r.Name, which may be null.
     * @return The record, with Account__r populated.
     */
    private static Purchase_Request__c prWithAccount(Decimal amount, String accountName) {
        Map<String, Object> shape = new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Purchase_Request__c' },
            'Amount__c' => amount,
            'Account__r' => new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'type' => 'Account' },
                'Name' => accountName
            }
        };
        return (Purchase_Request__c) JSON.deserialize(JSON.serialize(shape), Purchase_Request__c.class);
    }

    /**
     * A Purchase Request whose Account's owner has a profile: the three-hop
     * fixture, built by the same JSON round trip as prWithAccount.
     */
    private static Purchase_Request__c prWithOwnerProfile(String profileName) {
        return prWithOwnerShape(
            new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'type' => 'User' },
                'Profile' => new Map<String, Object>{
                    'attributes' => new Map<String, Object>{ 'type' => 'Profile' },
                    'Name' => profileName
                }
            }
        );
    }

    /** The Account has an owner, the owner no profile: broken at the third hop. */
    private static Purchase_Request__c prWithOwner() {
        return prWithOwnerShape(
            new Map<String, Object>{ 'attributes' => new Map<String, Object>{ 'type' => 'User' } }
        );
    }

    private static Purchase_Request__c prWithOwnerShape(Map<String, Object> owner) {
        Map<String, Object> shape = new Map<String, Object>{
            'attributes' => new Map<String, Object>{ 'type' => 'Purchase_Request__c' },
            'Amount__c' => 1,
            'Account__r' => new Map<String, Object>{
                'attributes' => new Map<String, Object>{ 'type' => 'Account' },
                'Name' => 'Globex',
                'Owner' => owner
            }
        };
        return (Purchase_Request__c) JSON.deserialize(JSON.serialize(shape), Purchase_Request__c.class);
    }

    /**
     * A QuickText, by name rather than by type, so this class compiles in an org
     * without the object. Without it, the multi-select tests fail here, loudly.
     */
    private static SObject quickText(String channel) {
        Schema.SObjectType quickTextType = Schema.getGlobalDescribe().get('QuickText');
        Assert.isNotNull(quickTextType, 'The multi-select picklist tests need the standard QuickText object');

        SObject record = quickTextType.newSObject();
        record.put('Channel', channel);
        return record;
    }

    private static Id fakeId(Schema.SObjectType objectType, Integer index) {
        String suffix = String.valueOf(index);
        return Id.valueOf(objectType.getDescribe().getKeyPrefix() + '0'.repeat(12 - suffix.length()) + suffix);
    }

    private static AMF_Ast.ComparisonNode comparison(
        String operator,
        AMF_Ast.ValueType operandType,
        String left,
        String right
    ) {
        AMF_Ast.ComparisonNode node = new AMF_Ast.ComparisonNode(
            operator,
            new AMF_Ast.LiteralNode(left, AMF_Ast.ValueType.TEXT, 0),
            new AMF_Ast.LiteralNode(right, AMF_Ast.ValueType.TEXT, 0),
            0
        );
        node.operandType = operandType;
        return node;
    }

    private static AMF_Ast.ComparisonNode numericComparison(String operator, Object left, Object right) {
        AMF_Ast.ComparisonNode node = new AMF_Ast.ComparisonNode(
            operator,
            new AMF_Ast.LiteralNode(left, AMF_Ast.ValueType.NUMERIC, 0),
            new AMF_Ast.LiteralNode(right, AMF_Ast.ValueType.NUMERIC, 0),
            0
        );
        node.operandType = AMF_Ast.ValueType.NUMERIC;
        return node;
    }

    private static AMF_ExprCompiler.CompiledExpression handBuilt(AMF_Ast.Node root) {
        return new AMF_ExprCompiler.CompiledExpression(
            PURCHASE_REQUEST,
            'hand-built AST, never produced by the compiler',
            root,
            new List<String>(),
            new Map<String, Schema.DescribeFieldResult>()
        );
    }
}
