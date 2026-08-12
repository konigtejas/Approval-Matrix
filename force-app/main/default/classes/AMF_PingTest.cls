/**
 * Unit test for AMF_Ping.
 *
 * Architecture section: none — Phase 0 pipeline smoke test only
 * (docs/build-playbook.md, Phase 0). Removed with AMF_Ping.
 */
@IsTest
private class AMF_PingTest {
    @IsTest
    static void pingReturnsPong() {
        System.assertEquals('pong', AMF_Ping.ping(), 'AMF_Ping.ping() must return the smoke-test token');
    }
}
