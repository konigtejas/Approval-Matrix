/**
 * Connectivity smoke test placeholder.
 *
 * Architecture section: none — this class implements no framework behaviour.
 * It exists only to prove the deploy + test pipeline for Phase 0 of
 * docs/build-playbook.md, and is removed once the engine classes (§4) land.
 */
public with sharing class AMF_Ping {
    /**
     * @return A fixed token proving the class deployed and executes in the org.
     */
    public static String ping() {
        return 'pong';
    }
}
