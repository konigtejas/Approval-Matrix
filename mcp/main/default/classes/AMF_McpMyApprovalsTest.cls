/**
 * The Claude connector's list_my_approvals tool (M16): the assistant's My
 * Pending Approvals, unchanged.
 *
 * Architecture section: 8 (its M14 note), 7 (its M14 and M16 notes), 10.
 *
 * Who an approval is waiting on is AMF_ApproverScopeTest's subject, and the
 * listing AMF_AgentMyApprovalsTest's. Pinned here is that the facade passes the
 * object through and the answer back, over in-memory rules and work items.
 */
@IsTest
private class AMF_McpMyApprovalsTest {

    @IsTest
    static void saysPlainlyWhenNothingIsWaitingOnTheUser() {
        AMF_AgentMyApprovals.ruleProviderOverride = new AMF_RuleBuilder.Stub(
            new List<AMF_RuleDefinition>{ new AMF_RuleBuilder().named('PR_Catch_All').withPriority(9999).build() }
        );
        AMF_AgentMyApprovals.workOverride = new List<ProcessInstanceWorkitem>();

        AMF_McpMyApprovals.Request request = new AMF_McpMyApprovals.Request();
        request.objectName = 'Purchase Request';
        AMF_McpMyApprovals.Result result = AMF_McpMyApprovals.listApprovals(new List<AMF_McpMyApprovals.Request>{ request })[0];

        Assert.areEqual(0, result.count);
        Assert.isTrue(String.isBlank(result.approvals), '' + result.approvals);
        Assert.isNotNull(result.message);
        Assert.areEqual(0, AMF_McpMyApprovals.listApprovals(null).size());
    }
}
