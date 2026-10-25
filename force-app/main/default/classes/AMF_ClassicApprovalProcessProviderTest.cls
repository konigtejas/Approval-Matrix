/**
 * Unit test for AMF_ClassicApprovalProcessProvider.
 *
 * Architecture section: 9, 10.
 *
 * Like the SOQL pin in AMF_CmdtRuleProviderTest, this reads deployed metadata
 * deliberately: the provider's whole job is a ProcessDefinition query, and a
 * ProcessDefinition cannot be created in a test. It reads the two Classic
 * templates that ship in force-app/main/default/approvalProcesses. Every other
 * validator test uses the in-memory catalog in AMF_ConfigValidatorTest.
 */
@IsTest
private class AMF_ClassicApprovalProcessProviderTest {

    private static final String GOVERNED_OBJECT = 'Purchase_Request__c';
    private static final String TWO_LEVEL = 'PR_Two_Level_Mgmt';
    private static final String THREE_LEVEL = 'PR_Three_Level_Finance';

    @IsTest
    static void theShippedTemplatesAreFoundActiveAndAnUnknownNameIsNot() {
        Set<String> active = new AMF_ClassicApprovalProcessProvider().getActiveApprovalProcessNames(
            GOVERNED_OBJECT,
            new Set<String>{ TWO_LEVEL, THREE_LEVEL, 'No_Such_Process' }
        );

        Assert.areEqual(
            new Set<String>{ TWO_LEVEL, THREE_LEVEL },
            active,
            'Both shipped templates must be active for ' + GOVERNED_OBJECT + ', and only they may match'
        );
    }

    @IsTest
    static void aProcessOnAnotherObjectDoesNotCount() {
        Set<String> active = new AMF_ClassicApprovalProcessProvider().getActiveApprovalProcessNames(
            'Account',
            new Set<String>{ TWO_LEVEL, THREE_LEVEL }
        );

        Assert.isTrue(
            active.isEmpty(),
            'A rule on Account naming a Purchase Request template must not validate; got ' + active
        );
    }

    @IsTest
    static void blankInputReturnsEmptyWithoutQuerying() {
        AMF_ClassicApprovalProcessProvider provider = new AMF_ClassicApprovalProcessProvider();

        Assert.isTrue(provider.getActiveApprovalProcessNames(null, new Set<String>{ TWO_LEVEL }).isEmpty());
        Assert.isTrue(provider.getActiveApprovalProcessNames(GOVERNED_OBJECT, null).isEmpty());
        Assert.isTrue(provider.getActiveApprovalProcessNames(GOVERNED_OBJECT, new Set<String>()).isEmpty());
        Assert.areEqual(0, Limits.getQueries(), 'Nothing to look up must cost no query');
    }
}
