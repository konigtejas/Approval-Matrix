<#
    Static companion to AMF_ConfigValidator.

    Salesforce does not expose approval-process entry criteria or actions
    through the ProcessDefinition SOQL surface. This script checks the source
    metadata before deployment; validate-config.apex then checks the resulting
    live org.

    For every approval process an active rule names, it requires:
      - the process to be active;
      - Matrix_Submission__c = TRUE as its only entry criterion (arch doc 6.3);
      - a field update that sets Matrix_Submission__c to false in its final
        approval actions, its final rejection actions and, when recall is
        allowed, its recall actions: every way a request leaves the process
        must re-arm the guard (arch doc 5.2, M8).

    Run from the repository root:

      powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-approval-matrix-source.ps1
#>
[CmdletBinding()]
param(
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$metadataNamespace = 'http://soap.sforce.com/2006/04/metadata'
$guardField = 'Matrix_Submission__c'

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $SourceRoot = Join-Path $scriptDirectory '..\force-app\main\default'
}

$resolvedSourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$rulesDirectory = Join-Path $resolvedSourceRoot 'customMetadata'
$approvalProcessesDirectory = Join-Path $resolvedSourceRoot 'approvalProcesses'
$workflowsDirectory = Join-Path $resolvedSourceRoot 'workflows'
$errors = New-Object System.Collections.Generic.List[string]
$activeRuleCount = 0

# Several rules may route to one template; each template is checked once.
$checkedProcesses = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$guardClearingUpdatesByObject = @{}

if (-not (Test-Path -LiteralPath $rulesDirectory -PathType Container)) {
    throw "Approval Matrix source validation: custom-metadata directory not found: $rulesDirectory"
}
if (-not (Test-Path -LiteralPath $approvalProcessesDirectory -PathType Container)) {
    throw "Approval Matrix source validation: approval-process directory not found: $approvalProcessesDirectory"
}

function Get-CmdtValue {
    param(
        [System.Xml.XmlDocument]$Document,
        [string]$FieldApiName
    )

    foreach ($entry in $Document.CustomMetadata.values) {
        if ([string]$entry.field -eq $FieldApiName) {
            return [string]$entry.value.InnerText
        }
    }
    return $null
}

function New-MetadataNamespaceManager {
    param([System.Xml.XmlDocument]$Document)

    $manager = New-Object System.Xml.XmlNamespaceManager($Document.NameTable)
    $manager.AddNamespace('m', $metadataNamespace)
    # The comma stops PowerShell unrolling the manager, which is enumerable.
    return , $manager
}

function Get-ChildText {
    param(
        [System.Xml.XmlNode]$Node,
        [string]$Name,
        [System.Xml.XmlNamespaceManager]$Namespace
    )

    $child = $Node.SelectSingleNode("m:$Name", $Namespace)
    if ($null -eq $child) {
        return ''
    }
    return $child.InnerText.Trim()
}

<#
    The names of the field updates on an object that set the guard to false,
    read from its workflow file. An action is judged by what its field update
    does, not by what it is called.
#>
function Get-GuardClearingUpdates {
    param([string]$ObjectApiName)

    if ($guardClearingUpdatesByObject.ContainsKey($ObjectApiName)) {
        return , $guardClearingUpdatesByObject[$ObjectApiName]
    }

    $names = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $workflowPath = Join-Path $workflowsDirectory "$ObjectApiName.workflow-meta.xml"

    if (Test-Path -LiteralPath $workflowPath -PathType Leaf) {
        [xml]$workflowDocument = Get-Content -LiteralPath $workflowPath -Raw
        $namespace = New-MetadataNamespaceManager -Document $workflowDocument

        foreach ($update in $workflowDocument.SelectNodes('/m:Workflow/m:fieldUpdates', $namespace)) {
            $field = Get-ChildText -Node $update -Name 'field' -Namespace $namespace
            $operation = Get-ChildText -Node $update -Name 'operation' -Namespace $namespace
            $literal = Get-ChildText -Node $update -Name 'literalValue' -Namespace $namespace

            if ($field -eq $guardField -and $operation -eq 'Literal' -and ($literal -eq '0' -or $literal -eq 'false')) {
                [void]$names.Add((Get-ChildText -Node $update -Name 'fullName' -Namespace $namespace))
            }
        }
    }

    $guardClearingUpdatesByObject[$ObjectApiName] = $names
    return , $names
}

<#
    Every way a request leaves the process must clear the guard. Otherwise the
    record is left unlocked with Matrix_Submission__c still true, and a
    submission that bypasses the engine passes entry criteria unlogged
    (technical log M7.8).
#>
function Test-GuardClearing {
    param(
        [System.Xml.XmlDocument]$ProcessDocument,
        [string]$ProcessFileName,
        [string]$ObjectApiName
    )

    $namespace = New-MetadataNamespaceManager -Document $ProcessDocument
    $clearingUpdates = Get-GuardClearingUpdates -ObjectApiName $ObjectApiName
    $allowsRecall = (Get-ChildText -Node $ProcessDocument.DocumentElement -Name 'allowRecall' -Namespace $namespace) -eq 'true'

    $exits = [ordered]@{
        finalApprovalActions  = 'final approval'
        finalRejectionActions = 'final rejection'
    }
    if ($allowsRecall) {
        $exits['recallActions'] = 'recall'
    }

    foreach ($element in $exits.Keys) {
        $clearsGuard = $false

        foreach ($action in $ProcessDocument.SelectNodes("/m:ApprovalProcess/m:$element/m:action", $namespace)) {
            $type = Get-ChildText -Node $action -Name 'type' -Namespace $namespace
            $name = Get-ChildText -Node $action -Name 'name' -Namespace $namespace
            if ($type -eq 'FieldUpdate' -and $clearingUpdates.Contains($name)) {
                $clearsGuard = $true
            }
        }

        if (-not $clearsGuard) {
            $errors.Add("$ProcessFileName does not clear $guardField in its $($exits[$element]) actions; add a field update that sets it to false, such as AMF_Clear_Matrix_Submission.")
        }
    }
}

foreach ($rulePath in Get-ChildItem -LiteralPath $rulesDirectory -Filter 'Approval_Matrix_Rule.*.md-meta.xml' -File) {
    [xml]$ruleDocument = Get-Content -LiteralPath $rulePath.FullName -Raw
    $activeValue = Get-CmdtValue -Document $ruleDocument -FieldApiName 'Active__c'
    if ([string]::IsNullOrWhiteSpace($activeValue)) {
        $errors.Add("$($rulePath.Name) has no Active__c value.")
        continue
    }
    $isActive = $activeValue.Trim()
    if (-not $isActive.Equals('true', [System.StringComparison]::OrdinalIgnoreCase)) {
        continue
    }

    $activeRuleCount++
    $objectValue = Get-CmdtValue -Document $ruleDocument -FieldApiName 'Object_API_Name__c'
    $processValue = Get-CmdtValue -Document $ruleDocument -FieldApiName 'Process_API_Name__c'
    $objectApiName = if ($null -eq $objectValue) { '' } else { $objectValue.Trim() }
    $processApiName = if ($null -eq $processValue) { '' } else { $processValue.Trim() }
    $ruleName = [System.IO.Path]::GetFileNameWithoutExtension($rulePath.Name)

    if ([string]::IsNullOrWhiteSpace($objectApiName)) {
        $errors.Add("$ruleName has no Object_API_Name__c.")
        continue
    }
    if ([string]::IsNullOrWhiteSpace($processApiName)) {
        $errors.Add("$ruleName has no Process_API_Name__c.")
        continue
    }
    if ($objectValue -ne $objectApiName) {
        $errors.Add("$ruleName has leading or trailing whitespace in Object_API_Name__c.")
        continue
    }
    if ($processValue -ne $processApiName) {
        $errors.Add("$ruleName has leading or trailing whitespace in Process_API_Name__c.")
        continue
    }

    $processFileName = "$objectApiName.$processApiName.approvalProcess-meta.xml"
    $processPath = Join-Path $approvalProcessesDirectory $processFileName
    if (-not (Test-Path -LiteralPath $processPath -PathType Leaf)) {
        $errors.Add("$ruleName names $processApiName, but source does not contain $processFileName.")
        continue
    }
    if (-not $checkedProcesses.Add($processFileName)) {
        continue
    }

    [xml]$processDocument = Get-Content -LiteralPath $processPath -Raw
    $isProcessActive = ([string]$processDocument.ApprovalProcess.active).Trim()
    if (-not $isProcessActive.Equals('true', [System.StringComparison]::OrdinalIgnoreCase)) {
        $errors.Add("$processFileName is not active.")
    }

    $formula = ([string]$processDocument.ApprovalProcess.entryCriteria.formula).Trim()
    $normalisedFormula = $formula -replace '\s', ''
    if ($normalisedFormula -notmatch '^\(*Matrix_Submission__c=TRUE\)*$') {
        $errors.Add("$processFileName must use Matrix_Submission__c = TRUE as its only entry criterion; found '$formula'.")
    }

    Test-GuardClearing -ProcessDocument $processDocument -ProcessFileName $processFileName -ObjectApiName $objectApiName
}

if ($errors.Count -gt 0) {
    throw "Approval Matrix source validation failed:`n - $($errors -join "`n - ")"
}

Write-Host "Approval Matrix source guard validation passed for $activeRuleCount active rule(s) and $($checkedProcesses.Count) approval process(es): entry criteria, and the guard cleared on every way out."
