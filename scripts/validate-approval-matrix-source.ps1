<#
    Static companion to AMF_ConfigValidator.

    Salesforce does not expose approval-process entry criteria or actions
    through the ProcessDefinition SOQL surface. This script checks the source
    metadata before deployment; validate-config.apex then checks the resulting
    live org. It reads every package directory sfdx-project.json lists.

    For every approval process an active rule names, and for every active one
    in source, it requires (arch doc 5.2, 6.3, M8, M12):
      - the process to be active;
      - Matrix_Submission__c = TRUE as its only entry criterion;
      - a field update that sets Matrix_Submission__c to false in its final
        approval actions, its final rejection actions and, when recall is
        allowed, its recall actions: every way a request leaves the process
        must re-arm the guard.

    For every approval process in source, the lifecycle of arch doc 5.1 (M12):
      - it is released: listed in config/template-releases.json with a
        fingerprint, and its source still has that fingerprint. Only its
        active flag may change, so a released template is never edited in
        place. A change is cloned to <name>_v2, the rules are repointed, and
        the previous version is deactivated;
      - a superseded version (X, once X_v2 exists) is inactive, and no active
        rule names it;
      - every user it names is <alias>@{{AMF_USERNAME_DOMAIN}}, which a
        sfdx-project.json replacement fills from the environment variable of
        that name at deploy. A literal username ties the template to one org.
    Every released template must still be in source: a released template is
    deactivated, never deleted, so that its in-flight approvals and history
    survive.

    For every object an active rule governs (arch doc 6.3, M11):
      - at least one of its layouts in source;
      - an explicit platformActionList on each, without the standard Submit for
        Approval button (Submit / StandardButton). A layout with no list shows
        the platform's default actions, which include that button once an
        approval process exists (technical log M3.9).

    The default package directory is the framework, and must deploy to any org
    (M12). It holds no layout and no object settings of a standard object:
    those are the org's own configuration, kept in an org package directory
    such as org-config/amf-dev.

    Run from the repository root:

      powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-approval-matrix-source.ps1

    -ProjectRoot points it at another copy of the project, such as a scratch
    copy that a gate check breaks on purpose.
#>
[CmdletBinding()]
param(
    [string]$ProjectRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$metadataNamespace = 'http://soap.sforce.com/2006/04/metadata'
$guardField = 'Matrix_Submission__c'
$usernameToken = '{{AMF_USERNAME_DOMAIN}}'
$usernameVariable = 'AMF_USERNAME_DOMAIN'
$releaseManifestName = 'config/template-releases.json'

if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) '..'
}

$resolvedProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$projectFile = Join-Path $resolvedProjectRoot 'sfdx-project.json'
$releaseManifestPath = Join-Path $resolvedProjectRoot $releaseManifestName
$errors = New-Object System.Collections.Generic.List[string]
$activeRuleCount = 0
$checkedLayoutCount = 0

if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) {
    throw "Approval Matrix source validation: sfdx-project.json not found in $resolvedProjectRoot"
}

<# A property of a parsed JSON object, or $null; StrictMode throws on a missing one. #>
function Get-JsonProperty {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

$project = [System.IO.File]::ReadAllText($projectFile) | ConvertFrom-Json

# Every package directory, the default one first. The default is the framework.
$packages = New-Object System.Collections.Generic.List[object]
foreach ($directory in @(Get-JsonProperty -Object $project -Name 'packageDirectories')) {
    $path = [string](Get-JsonProperty -Object $directory -Name 'path')
    $fullPath = Join-Path $resolvedProjectRoot $path
    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        throw "Approval Matrix source validation: package directory not found: $fullPath"
    }
    $package = [pscustomobject]@{
        Path      = $path
        FullPath  = (Resolve-Path -LiteralPath $fullPath).Path
        IsDefault = ((Get-JsonProperty -Object $directory -Name 'default') -eq $true)
    }
    if ($package.IsDefault) {
        $packages.Insert(0, $package)
    } else {
        $packages.Add($package)
    }
}
if ($packages.Count -eq 0 -or -not $packages[0].IsDefault) {
    throw 'Approval Matrix source validation: sfdx-project.json names no default package directory.'
}
$frameworkPackage = $packages[0]

<#
    The files of one metadata folder, across every package directory, each with
    the package it came from. Matching on the folder's name finds it at any
    depth, so main/default is a convention here, not a requirement.
#>
function Get-SourceFiles {
    param(
        [string]$Folder,
        [string]$Filter
    )

    foreach ($package in $packages) {
        foreach ($file in Get-ChildItem -LiteralPath $package.FullPath -Recurse -File -Filter $Filter) {
            if ($file.Directory.Name -eq $Folder) {
                [pscustomobject]@{ File = $file; Package = $package }
            }
        }
    }
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

<# Read as UTF-8 whatever the PowerShell edition; 5.1's Get-Content assumes the ANSI code page. #>
function Read-MetadataXml {
    param([string]$Path)

    $document = New-Object System.Xml.XmlDocument
    $document.PreserveWhitespace = $false
    $document.LoadXml(([System.IO.File]::ReadAllText($Path) -replace "`r`n", "`n"))
    return , $document
}

<#
    Arch doc 5.1, M12. A template's fingerprint is the SHA-256 of its XML with
    the <active> element removed, insignificant whitespace dropped and line
    endings normalised. Activation is the one change a released template may
    undergo, because superseding it means deactivating it. Everything else,
    including a description, is the released content: a change to it is a
    change to what auditors and in-flight approvals were told.
#>
function Get-TemplateFingerprint {
    param([string]$Path)

    $document = Read-MetadataXml -Path $Path
    $namespace = New-MetadataNamespaceManager -Document $document
    $active = $document.SelectSingleNode('/m:ApprovalProcess/m:active', $namespace)
    if ($null -ne $active) {
        [void]$document.DocumentElement.RemoveChild($active)
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($document.DocumentElement.OuterXml)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return (($sha256.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '')
    } finally {
        $sha256.Dispose()
    }
}

<#
    A template's place in its version chain (arch doc 5.1): X is version 1,
    X_v2 version 2, and so on. The first version has no suffix, so _v0 and _v1
    are refused.
#>
function Get-TemplateVersion {
    param([string]$ProcessApiName)

    if ($ProcessApiName -match '^(?<base>.+)_v(?<number>\d+)$') {
        return [pscustomobject]@{ Base = $Matches['base']; Number = [int]$Matches['number'] }
    }
    return [pscustomobject]@{ Base = $ProcessApiName; Number = 1 }
}

# ── Templates, guard-clearing updates and layouts in source ─────────────────

$templates = @{}
foreach ($entry in Get-SourceFiles -Folder 'approvalProcesses' -Filter '*.approvalProcess-meta.xml') {
    $key = $entry.File.Name -replace '\.approvalProcess-meta\.xml$', ''
    if ($templates.ContainsKey($key)) {
        $errors.Add("$key is in two package directories, $($templates[$key].Package.Path) and $($entry.Package.Path).")
        continue
    }
    $separator = $key.IndexOf('.')
    $document = Read-MetadataXml -Path $entry.File.FullName
    $templates[$key] = [pscustomobject]@{
        Key           = $key
        FileName      = $entry.File.Name
        Path          = $entry.File.FullName
        Package       = $entry.Package
        ObjectApiName = $key.Substring(0, $separator)
        ProcessName   = $key.Substring($separator + 1)
        Document      = $document
        IsActive      = ([string]$document.ApprovalProcess.active).Trim().Equals('true', [System.StringComparison]::OrdinalIgnoreCase)
        NamedBy       = New-Object System.Collections.Generic.List[string]
    }
}

$guardClearingUpdatesByObject = @{}

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
    foreach ($entry in Get-SourceFiles -Folder 'workflows' -Filter "$ObjectApiName.workflow-meta.xml") {
        $workflowDocument = Read-MetadataXml -Path $entry.File.FullName
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
    Arch doc 6.3: the guard is the only entry criterion, and every way a request
    leaves the process clears it. Otherwise the record is left unlocked with
    Matrix_Submission__c still true, and a submission that bypasses the engine
    passes entry criteria unlogged (technical log M7.8).
#>
function Test-Guard {
    param([object]$Template)

    $document = $Template.Document
    $namespace = New-MetadataNamespaceManager -Document $document

    $formula = ([string]$document.ApprovalProcess.entryCriteria.formula).Trim()
    $normalisedFormula = $formula -replace '\s', ''
    if ($normalisedFormula -notmatch '^\(*Matrix_Submission__c=TRUE\)*$') {
        $errors.Add("$($Template.FileName) must use Matrix_Submission__c = TRUE as its only entry criterion; found '$formula'.")
    }

    $clearingUpdates = Get-GuardClearingUpdates -ObjectApiName $Template.ObjectApiName
    $allowsRecall = (Get-ChildText -Node $document.DocumentElement -Name 'allowRecall' -Namespace $namespace) -eq 'true'

    $exits = [ordered]@{
        finalApprovalActions  = 'final approval'
        finalRejectionActions = 'final rejection'
    }
    if ($allowsRecall) {
        $exits['recallActions'] = 'recall'
    }

    foreach ($element in $exits.Keys) {
        $clearsGuard = $false

        foreach ($action in $document.SelectNodes("/m:ApprovalProcess/m:$element/m:action", $namespace)) {
            $type = Get-ChildText -Node $action -Name 'type' -Namespace $namespace
            $name = Get-ChildText -Node $action -Name 'name' -Namespace $namespace
            if ($type -eq 'FieldUpdate' -and $clearingUpdates.Contains($name)) {
                $clearsGuard = $true
            }
        }

        if (-not $clearsGuard) {
            $errors.Add("$($Template.FileName) does not clear $guardField in its $($exits[$element]) actions; add a field update that sets it to false, such as AMF_Clear_Matrix_Submission.")
        }
    }
}

<#
    M12: a username is unique across every Salesforce org, so a literal one ties
    the template to the org it came from. Approvers and allowed submitters of
    type user are written <alias>@{{AMF_USERNAME_DOMAIN}}. Queues, groups and
    roles are named by DeveloperName, which travels. Returns whether the
    template uses the placeholder.
#>
function Test-PortableUsernames {
    param([object]$Template)

    $document = $Template.Document
    $namespace = New-MetadataNamespaceManager -Document $document
    $usesToken = $false
    $named = @()

    foreach ($approver in $document.SelectNodes('/m:ApprovalProcess/m:approvalStep/m:assignedApprover/m:approver', $namespace)) {
        if ((Get-ChildText -Node $approver -Name 'type' -Namespace $namespace) -eq 'user') {
            $named += Get-ChildText -Node $approver -Name 'name' -Namespace $namespace
        }
    }
    foreach ($submitter in $document.SelectNodes('/m:ApprovalProcess/m:allowedSubmitters', $namespace)) {
        if ((Get-ChildText -Node $submitter -Name 'type' -Namespace $namespace) -eq 'user') {
            $named += Get-ChildText -Node $submitter -Name 'submitter' -Namespace $namespace
        }
    }

    foreach ($username in $named) {
        if ($username -match ('^[^@\s]+@' + [regex]::Escape($usernameToken) + '$')) {
            $usesToken = $true
        } else {
            $errors.Add("$($Template.FileName) names the user '$username' literally, which only one org has. Write it <alias>@$usernameToken, which sfdx-project.json fills from $usernameVariable at deploy (M12).")
        }
    }
    return $usesToken
}

<#
    Arch doc 6.3: the standard Submit for Approval button is removed from every
    governed object's layouts, so that every submission goes through the engine.
    In Lightning it is the platformActionList entry Submit / StandardButton, and
    a layout with no list shows the platform's default set, which includes it
    once an approval process exists (technical log M3.9). Opportunity's layouts
    listed it explicitly until M11. A layout that exists only in the org cannot
    be checked here, which is why a governed object with none in source fails.

    Returns how many layouts were checked.
#>
function Test-StandardSubmitRemoved {
    param([string]$ObjectApiName)

    $layouts = @(Get-SourceFiles -Folder 'layouts' -Filter "$ObjectApiName-*.layout-meta.xml")

    if ($layouts.Count -eq 0) {
        $errors.Add("No layout of $ObjectApiName is in source, so this gate cannot show that the standard Submit for Approval button is removed from it (arch doc 6.3). Retrieve its layouts into source.")
        return 0
    }

    foreach ($entry in $layouts) {
        $layout = $entry.File
        $layoutDocument = Read-MetadataXml -Path $layout.FullName
        $namespace = New-MetadataNamespaceManager -Document $layoutDocument
        $actionList = $layoutDocument.SelectSingleNode('/m:Layout/m:platformActionList', $namespace)

        if ($null -eq $actionList) {
            $errors.Add("$($layout.Name) has no platformActionList, so its record page shows the platform's default actions, which include the standard Submit for Approval button (arch doc 6.3). Give it an explicit list without Submit.")
            continue
        }

        foreach ($item in $actionList.SelectNodes('m:platformActionListItems', $namespace)) {
            $name = Get-ChildText -Node $item -Name 'actionName' -Namespace $namespace
            $type = Get-ChildText -Node $item -Name 'actionType' -Namespace $namespace
            if ($name -eq 'Submit' -and $type -eq 'StandardButton') {
                $errors.Add("$($layout.Name) keeps the standard Submit for Approval button (Submit / StandardButton) in its platformActionList; remove it, so that every submission goes through the engine (arch doc 6.3).")
            }
        }
    }

    return $layouts.Count
}

# ── Rules ───────────────────────────────────────────────────────────────────

$governedObjects = New-Object 'System.Collections.Generic.SortedSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
$ruleFiles = @(Get-SourceFiles -Folder 'customMetadata' -Filter 'Approval_Matrix_Rule.*.md-meta.xml')
if ($ruleFiles.Count -eq 0) {
    throw 'Approval Matrix source validation: no Approval_Matrix_Rule records found in any package directory.'
}

foreach ($entry in $ruleFiles) {
    $rulePath = $entry.File
    $ruleDocument = Read-MetadataXml -Path $rulePath.FullName
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
    $ruleName = $rulePath.Name -replace '^Approval_Matrix_Rule\.', '' -replace '\.md-meta\.xml$', ''

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

    [void]$governedObjects.Add($objectApiName)

    $key = "$objectApiName.$processApiName"
    if (-not $templates.ContainsKey($key)) {
        $errors.Add("$ruleName names $processApiName, but source does not contain $key.approvalProcess-meta.xml.")
        continue
    }
    $templates[$key].NamedBy.Add($ruleName)
}

# ── Templates: the guard, usernames, and the lifecycle ──────────────────────

$releases = @{}
if (-not (Test-Path -LiteralPath $releaseManifestPath -PathType Leaf)) {
    $errors.Add("$releaseManifestName is missing, so no template can be shown to be released and unchanged (arch doc 5.1).")
} else {
    $manifest = [System.IO.File]::ReadAllText($releaseManifestPath) | ConvertFrom-Json
    foreach ($release in @(Get-JsonProperty -Object $manifest -Name 'templates')) {
        $key = [string](Get-JsonProperty -Object $release -Name 'template')
        $fingerprint = [string](Get-JsonProperty -Object $release -Name 'sha256')
        if ([string]::IsNullOrWhiteSpace($key) -or $fingerprint -notmatch '^[0-9a-f]{64}$') {
            $errors.Add("$releaseManifestName has an entry without a template name or a 64-character lowercase sha256: '$key'.")
            continue
        }
        if ($releases.ContainsKey($key)) {
            $errors.Add("$releaseManifestName lists $key twice.")
            continue
        }
        $releases[$key] = $fingerprint
    }
}

$guardCheckedCount = 0
$releasedCount = 0
$templatesUseToken = $false
$chains = @{}

foreach ($template in @($templates.Values | Sort-Object -Property Key)) {
    if ($template.IsActive -or $template.NamedBy.Count -gt 0) {
        if (-not $template.IsActive) {
            $errors.Add("$($template.FileName) is not active, but $($template.NamedBy -join ', ') names it.")
        }
        Test-Guard -Template $template
        $guardCheckedCount++
    }

    if (Test-PortableUsernames -Template $template) {
        $templatesUseToken = $true
    }

    $fingerprint = Get-TemplateFingerprint -Path $template.Path
    if (-not $releases.ContainsKey($template.Key)) {
        $errors.Add("$($template.Key) is not released. To release it, add { `"template`": `"$($template.Key)`", `"sha256`": `"$fingerprint`" } to $releaseManifestName (arch doc 5.1). From then on it may not change, except to be deactivated.")
    } elseif ($releases[$template.Key] -ne $fingerprint) {
        $errors.Add("$($template.Key) has changed since it was released. A released template is never edited in place (arch doc 5.1): restore it, and make the change in a new version, $(( Get-TemplateVersion -ProcessApiName $template.ProcessName ).Base)_v<n>, then repoint its rules and deactivate this one.")
    } else {
        $releasedCount++
    }

    $version = Get-TemplateVersion -ProcessApiName $template.ProcessName
    if ($version.Number -lt 2 -and $template.ProcessName -match '_v\d+$') {
        $errors.Add("$($template.Key) spells out a version below 2. The first version of a template has no suffix; the second is _v2 (arch doc 5.1).")
        continue
    }
    $chainKey = "$($template.ObjectApiName).$($version.Base)"
    if (-not $chains.ContainsKey($chainKey)) {
        $chains[$chainKey] = New-Object System.Collections.Generic.List[object]
    }
    $chains[$chainKey].Add([pscustomobject]@{ Template = $template; Number = $version.Number })
}

foreach ($key in @($releases.Keys | Sort-Object)) {
    if (-not $templates.ContainsKey($key)) {
        $errors.Add("$key is released but not in source. A released template is deactivated, never deleted, so that its in-flight approvals and history survive (arch doc 5.1). Restore it.")
    }
}

# Arch doc 5.1: when X_v<n> exists, every earlier version is superseded.
foreach ($chain in $chains.Values) {
    $latest = ($chain | Measure-Object -Property Number -Maximum).Maximum
    foreach ($member in $chain) {
        if ($member.Number -ge $latest) {
            continue
        }
        $template = $member.Template
        $successor = @($chain | Where-Object { $_.Number -eq $latest })[0].Template.ProcessName
        if ($template.IsActive) {
            $errors.Add("$($template.Key) is superseded by $successor and must be deactivated (arch doc 5.1).")
        }
        foreach ($ruleName in $template.NamedBy) {
            $errors.Add("$ruleName names $($template.ProcessName), which $successor supersedes; repoint it to $successor (arch doc 5.1).")
        }
    }
}

# The placeholder is only safe while the replacement that fills it is configured.
if ($templatesUseToken) {
    $covered = $false
    foreach ($replacement in @(Get-JsonProperty -Object $project -Name 'replacements')) {
        $target = [string](Get-JsonProperty -Object $replacement -Name 'glob') + [string](Get-JsonProperty -Object $replacement -Name 'filename')
        if ((Get-JsonProperty -Object $replacement -Name 'stringToReplace') -eq $usernameToken -and
            (Get-JsonProperty -Object $replacement -Name 'replaceWithEnv') -eq $usernameVariable -and
            $target -match 'approvalProcesses') {
            $covered = $true
        }
    }
    if (-not $covered) {
        $errors.Add("Templates name users as <alias>@$usernameToken, but sfdx-project.json has no replacement of $usernameToken from $usernameVariable covering approvalProcesses, so the placeholder would deploy as written (M12).")
    }
}

# ── Layouts ─────────────────────────────────────────────────────────────────

foreach ($governedObject in $governedObjects) {
    $checkedLayoutCount += Test-StandardSubmitRemoved -ObjectApiName $governedObject
}

# M12: a standard object's layouts and object settings belong to the org.
$customSuffix = '__(c|mdt|e|b|x)$'
foreach ($entry in @(Get-SourceFiles -Folder 'layouts' -Filter '*.layout-meta.xml')) {
    $objectApiName = $entry.File.Name.Substring(0, $entry.File.Name.IndexOf('-'))
    if ($entry.Package.IsDefault -and $objectApiName -notmatch $customSuffix) {
        $errors.Add("$($entry.File.Name) is a standard object's layout in $($frameworkPackage.Path), which must deploy to any org. It is org configuration: move it to an org package directory, such as org-config/amf-dev (M12).")
    }
}
# objects/<Object>/<Object>.object-meta.xml: one level below objects/, so not Get-SourceFiles.
foreach ($file in Get-ChildItem -LiteralPath $frameworkPackage.FullPath -Recurse -File -Filter '*.object-meta.xml') {
    $objectApiName = $file.Name -replace '\.object-meta\.xml$', ''
    if ($file.Directory.Parent.Name -eq 'objects' -and $objectApiName -notmatch $customSuffix) {
        $errors.Add("$($file.Name) holds a standard object's settings in $($frameworkPackage.Path), which must deploy to any org. They are org configuration: move the file to an org package directory, such as org-config/amf-dev (M12).")
    }
}

if ($errors.Count -gt 0) {
    throw "Approval Matrix source validation failed:`n - $($errors -join "`n - ")"
}

Write-Host ("Approval Matrix source validation passed for $activeRuleCount active rule(s), " +
    "$guardCheckedCount approval process(es) guard-checked, $releasedCount of $($templates.Count) template(s) released and unchanged, " +
    "and $checkedLayoutCount layout(s) of $($governedObjects.Count) governed object(s): entry criteria, the guard cleared on every way out, " +
    "no superseded version active or named, no literal username, no standard Submit for Approval button, " +
    "and no standard object's configuration in $($frameworkPackage.Path).")
