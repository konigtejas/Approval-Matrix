<#
    Static companion to AMF_ConfigValidator.

    Salesforce does not expose approval-process entry criteria through the
    ProcessDefinition SOQL surface. This script checks the source metadata
    before deployment; validate-config.apex then checks the resulting live org.

    Run from the repository root:

      powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-approval-matrix-source.ps1
#>
[CmdletBinding()]
param(
    [string]$SourceRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    $SourceRoot = Join-Path $scriptDirectory '..\force-app\main\default'
}

$resolvedSourceRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
$rulesDirectory = Join-Path $resolvedSourceRoot 'customMetadata'
$approvalProcessesDirectory = Join-Path $resolvedSourceRoot 'approvalProcesses'
$errors = New-Object System.Collections.Generic.List[string]
$activeRuleCount = 0

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
}

if ($errors.Count -gt 0) {
    throw "Approval Matrix source validation failed:`n - $($errors -join "`n - ")"
}

Write-Host "Approval Matrix source guard validation passed for $activeRuleCount active rule(s)."
