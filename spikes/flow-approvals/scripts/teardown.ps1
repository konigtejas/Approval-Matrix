<#
    Flow approvals spike (M6): remove spike artefacts from amf-dev. Each part is opt-in.

      -RecallPending    recall every InProgress Flow approval submission (all are spike ones)
      -DeleteTestClass  delete AMF_FlowApprovalSpikeTest (must never join RunLocalTests)
      -DeleteProbe      delete the Tooling-created draft flow AMF_Spike_Probe
      -DeleteFlows      deactivate and delete every AMF_Spike_* flow, all versions
      -DeleteGroups     delete the AMF_Spike_Any / AMF_Spike_All / AMF_Spike_Queue groups
      -DeleteRecords    delete the spike Purchase Requests (every record with a Flow approval
                        submission, plus today's Amount 1001-1017 records)

      powershell -NoProfile -File spikes/flow-approvals/scripts/teardown.ps1 -RecallPending -DeleteTestClass
#>
[CmdletBinding()]
param(
    [switch] $RecallPending,
    [switch] $DeleteTestClass,
    [switch] $DeleteProbe,
    [switch] $DeleteFlows,
    [switch] $DeleteGroups,
    [switch] $DeleteRecords,
    [string] $TargetOrg = 'amf-dev'
)

$ErrorActionPreference = 'Stop'
$org = (sf org display -o $TargetOrg --json 2>$null | Out-String | ConvertFrom-Json).result
$headers = @{ Authorization = "Bearer $($org.accessToken)" }
$tooling = "$($org.instanceUrl)/services/data/v67.0/tooling"
$runner = Join-Path $PSScriptRoot 'run.ps1'

function Invoke-Apex([string] $body) {
    $file = Join-Path ([IO.Path]::GetTempPath()) ('amf-teardown-' + [Guid]::NewGuid().ToString('N') + '.apex')
    [IO.File]::WriteAllText($file, $body, (New-Object Text.UTF8Encoding($false)))
    & powershell -NoProfile -ExecutionPolicy Bypass -File $runner -Script $file
    Remove-Item -Force $file
}

if ($RecallPending) {
    Invoke-Apex @'
for (ApprovalSubmission s : [SELECT Id FROM ApprovalSubmission WHERE Status = 'InProgress']) {
    Invocable.Action a = Invocable.Action.createStandardAction('recallApprovalSubmission');
    a.setInvocationParameter('approvalSubmissionId', String.valueOf(s.Id));
    a.setInvocationParameter('comments', 'Flow approvals spike teardown');
    System.debug(LoggingLevel.ERROR, 'recall ' + s.Id + ' success=' + a.invoke()[0].isSuccess());
}
'@
}

if ($DeleteTestClass) {
    $work = Join-Path ([IO.Path]::GetTempPath()) ('amf-teardown-' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force $work | Out-Null
    '<?xml version="1.0" encoding="UTF-8"?><Package xmlns="http://soap.sforce.com/2006/04/metadata"><version>67.0</version></Package>' |
        Set-Content -Encoding UTF8 (Join-Path $work 'package.xml')
    '<?xml version="1.0" encoding="UTF-8"?><Package xmlns="http://soap.sforce.com/2006/04/metadata"><types><members>AMF_FlowApprovalSpikeTest</members><name>ApexClass</name></types><version>67.0</version></Package>' |
        Set-Content -Encoding UTF8 (Join-Path $work 'destructiveChanges.xml')
    $r = sf project deploy start -o $TargetOrg --metadata-dir $work --api-version 67.0 -w 15 --json 2>$null | Out-String | ConvertFrom-Json
    Remove-Item -Recurse -Force $work
    Write-Output "delete test class: $($r.result.status)"
}

function Remove-FlowVersions([string] $soqlFilter) {
    $q = [Uri]::EscapeDataString("SELECT Id, VersionNumber, Status, Definition.DeveloperName, DefinitionId FROM Flow WHERE $soqlFilter ORDER BY Definition.DeveloperName, VersionNumber")
    $versions = (Invoke-RestMethod -Headers $headers -Uri "$tooling/query/?q=$q").records
    foreach ($definitionId in ($versions | Select-Object -ExpandProperty DefinitionId -Unique)) {
        $body = @{ Metadata = @{ activeVersionNumber = 0 } } | ConvertTo-Json -Compress
        Invoke-RestMethod -Method Patch -Headers $headers -ContentType 'application/json' -Uri "$tooling/sobjects/FlowDefinition/$definitionId" -Body $body | Out-Null
    }
    foreach ($v in $versions) {
        Invoke-RestMethod -Method Delete -Headers $headers -Uri "$tooling/sobjects/Flow/$($v.Id)" | Out-Null
        Write-Output ("deleted flow {0} v{1}" -f $v.Definition.DeveloperName, $v.VersionNumber)
    }
}

if ($DeleteProbe) {
    Remove-FlowVersions "Definition.DeveloperName = 'AMF_Spike_Probe'"
}

if ($DeleteFlows) {
    # Orchestrations first: they reference the screen and background flows.
    Remove-FlowVersions "Definition.DeveloperName LIKE 'AMF_Spike%' AND ProcessType = 'ApprovalWorkflow'"
    Remove-FlowVersions "Definition.DeveloperName LIKE 'AMF_Spike%'"
}

if ($DeleteGroups) {
    Invoke-Apex @'
List<Group> groups = [SELECT Id FROM Group WHERE DeveloperName IN ('AMF_Spike_Any', 'AMF_Spike_All', 'AMF_Spike_Queue')];
delete [SELECT Id FROM GroupMember WHERE GroupId IN :groups];
delete [SELECT Id FROM QueueSobject WHERE QueueId IN :groups];
delete groups;
System.debug(LoggingLevel.ERROR, 'deleted spike groups: ' + groups.size());
'@
}

if ($DeleteRecords) {
    Invoke-Apex @'
Set<Id> ids = new Set<Id>();
for (ApprovalSubmission s : [SELECT RelatedRecordId FROM ApprovalSubmission]) {
    ids.add(s.RelatedRecordId);
}
for (Purchase_Request__c pr : [SELECT Id FROM Purchase_Request__c WHERE CreatedDate = TODAY AND Amount__c >= 1001 AND Amount__c <= 1017]) {
    ids.add(pr.Id);
}
List<Purchase_Request__c> spike = [SELECT Id, Name FROM Purchase_Request__c WHERE Id IN :ids];
delete spike;
System.debug(LoggingLevel.ERROR, 'deleted spike Purchase Requests: ' + spike.size());
'@
}
