/*
 * M13's live check of the plain-English explanation: Einstein explains a real
 * recorded decision through the same entry point as the timeline's Explain
 * button. It writes nothing.
 *
 * Run as a user holding Approval_Matrix_Admin and the Prompt Template User
 * permission set, after the agentforce package directory is deployed:
 *
 *   sf apex run --file scripts/explain-decision.apex --target-org amf-dev
 *
 * It explains the newest decision log row on the Purchase Request named below,
 * among the rows the running user can read. PR-00000042 has two (technical log
 * M12.7); change the name to explain another.
 *
 * It calls the explainer itself, not explainDecision: that @AuraEnabled wrapper
 * throws an AuraHandledException, which anonymous Apex cannot throw (technical
 * log M13.7).
 */
String recordName = 'PR-00000042';

Purchase_Request__c record = [SELECT Id, Name FROM Purchase_Request__c WHERE Name = :recordName LIMIT 1];
String recordKey = String.valueOf(record.Id);
Approval_Decision_Log__c row = [
    SELECT Id, Name, Outcome__c, Matched_Rule__c, Selected_Process__c
    FROM Approval_Decision_Log__c
    WHERE Record_Id__c = :recordKey
    WITH USER_MODE
    ORDER BY Submitted_At__c DESC NULLS LAST, CreatedDate DESC
    LIMIT 1
];

AMF_DecisionExplainer.Explanation explanation = new AMF_DecisionExplainer().explain(row.Id);

System.debug(
    LoggingLevel.ERROR,
    'Recorded: ' + row.Name + ', ' + row.Outcome__c + ', ' + row.Matched_Rule__c + ' -> ' + row.Selected_Process__c
);
System.debug(LoggingLevel.ERROR, 'Explained (' + explanation.logName + '): ' + explanation.text);
