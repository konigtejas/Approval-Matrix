/**
 * One record's instruction to a submission strategy: submit THIS record to THAT
 * process. The engine's output and the strategy's only input.
 *
 * Architecture section: 6.2 (submission strategies).
 *
 * Deliberately free of execution detail. It names a process and nothing about
 * how that process runs, which is what lets AMF_ClassicProcessStrategy read it
 * as a ProcessDefinition DeveloperName and a Flow strategy later read the same
 * field as an orchestration API name with no change here and none upstream
 * (6.2: "nothing upstream of step 10 knows which is in play").
 */
public class AMF_SubmitRequest {

    /** The governed record to submit. */
    public Id recordId { get; private set; }

    /**
     * Process_API_Name__c from the matched rule, verbatim. For Classic this is
     * the ProcessDefinition DeveloperName (3.1).
     */
    public String processApiName { get; private set; }

    /**
     * @param recordId       The governed record.
     * @param processApiName The process the matrix selected for it.
     */
    public AMF_SubmitRequest(Id recordId, String processApiName) {
        this.recordId = recordId;
        this.processApiName = processApiName;
    }
}
