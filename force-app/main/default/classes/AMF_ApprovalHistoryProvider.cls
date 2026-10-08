/**
 * Read seam for a governed record's native approval history.
 *
 * Architecture section: 8 (who and when are native), 10 (testability).
 *
 * The timeline needs every approval a record has entered, with its steps, and a
 * ProcessInstance can only come into existence through a real
 * Approval.process(). This interface keeps that platform read behind a
 * replaceable boundary, as AMF_ApprovalProcessProvider does for 9, so the
 * timeline's own tests run against in-memory history.
 */
public interface AMF_ApprovalHistoryProvider {

    /**
     * @param recordId     The governed record.
     * @param maxInstances The most instances to return; the newest are kept.
     * @return The approvals the record has entered, newest first, each with its
     *         steps in the order AMF_ApprovalHistory.sortChronologically gives
     *         them. Never null.
     */
    List<AMF_ApprovalHistory.Instance> getHistory(Id recordId, Integer maxInstances);
}
