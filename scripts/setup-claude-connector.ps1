<#
.SYNOPSIS
    Sets up the Claude connector (M16) in an org, and prints how to connect Claude to it.

.DESCRIPTION
    1. Deploys the mcp package directory: the AMF_Mcp* tool classes, AMF_Mcp_Settings__c and the two
       connector permission sets. (Its MCP server definitions are .forceignore'd: see step 3.)
    2. Deploys the org's External Client App from org-config/<OrgConfig>, unless -OrgConfig is ''.
    3. Deploys the two MCP server definitions from a throwaway project at Metadata API 67.0. Their
       tool annotations (readOnly, destructive, idempotent, openWorld) exist only from 67.0, and a
       deploy at the project's sourceApiVersion (66.0) resets them to false (technical log M16.1).
    4. Activates both servers. Activation is a runtime record (McpServerAccess), not metadata, so
       every org needs this step.
    5. Seeds the preview key (scripts/setup-mcp.apex). An existing key is kept.
    6. Assigns AMF_Claude_Connector_User, or with -Admin AMF_Claude_Connector_Admin, to -AssignTo
       (default: the CLI user). The connector's OAuth policy admits only holders of these sets.
    7. Prints both server URLs, the OAuth client ID, and the steps for claude.ai and Claude Code.

    Run it from anywhere; it works from the project root. With AMF_USERNAME_DOMAIN unset it still
    runs, because it deploys no approval process.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/setup-claude-connector.ps1 -Admin

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File scripts/setup-claude-connector.ps1 -SkipDeploy -AssignTo amfu1@amf.00daj000012gj9b.dev
#>
param(
    [string]$TargetOrg = 'amf-dev',
    [string]$OrgConfig = 'amf-dev',
    [string]$EcaName = 'AMFClaudeConnector',
    [string[]]$AssignTo = @(),
    [switch]$Admin,
    [switch]$SkipDeploy
)

$root = Split-Path -Parent $PSScriptRoot
$servers = @('AMFApprovalMatrix', 'AMFApprovalMatrixAdmin')

# Native commands report on stderr even when they succeed (beta warnings, spinners), so stderr is
# discarded and the exit code decides; $ErrorActionPreference = 'Stop' would turn it into a failure.
function Invoke-SfJson([string[]]$Arguments) {
    $out = & sf @Arguments --json 2>$null
    $code = $LASTEXITCODE
    $parsed = $null
    try { $parsed = ($out -join "`n") | ConvertFrom-Json } catch { }
    if ($code -ne 0 -or ($parsed -and $parsed.status -ne 0)) {
        $why = if ($parsed -and $parsed.message) { $parsed.message } else { ($out -join ' ') }
        throw "sf $($Arguments -join ' ') failed: $why"
    }
    return $parsed
}

function Invoke-SfRest([string]$Path, [string]$Method = 'GET', [string]$Body = $null) {
    $arguments = @('api', 'request', 'rest', $Path, '--method', $Method, '-o', $TargetOrg)
    $bodyFile = $null
    if ($Body) {
        $bodyFile = [IO.Path]::GetTempFileName()
        [IO.File]::WriteAllText($bodyFile, $Body)
        $arguments += @('--body', "@$bodyFile")
    }
    $out = & sf @arguments 2>$null
    $code = $LASTEXITCODE
    if ($bodyFile) { Remove-Item $bodyFile -ErrorAction SilentlyContinue }
    if ($code -ne 0) { throw "$Method $Path failed: $($out -join ' ')" }
    $text = ($out -join "`n")
    if ([string]::IsNullOrWhiteSpace($text)) { return $null }
    return $text | ConvertFrom-Json
}

function Deploy-Dirs([string[]]$Dirs, [string]$What) {
    $arguments = @('project', 'deploy', 'start', '-o', $TargetOrg, '--wait', '20')
    foreach ($dir in $Dirs) { $arguments += @('--source-dir', $dir) }
    $result = Invoke-SfJson $arguments
    Write-Host "  $What deployed: $($result.result.numberComponentsDeployed) component(s)."
}

Push-Location $root
try {
    Write-Host "Claude connector setup for $TargetOrg"

    if (-not $SkipDeploy) {
        Write-Host '1. The mcp package directory'
        Deploy-Dirs @('mcp') 'Tool classes, settings and permission sets'

        if ($OrgConfig) {
            Write-Host "2. The External Client App, from org-config/$OrgConfig"
            $base = "org-config/$OrgConfig/main/default"
            $ecaDirs = @('externalClientApps', 'extlClntAppGlobalOauthSets', 'extlClntAppOauthSettings', 'extlClntAppOauthPolicies') |
                ForEach-Object { "$base/$_" } | Where-Object { Test-Path $_ }
            Deploy-Dirs $ecaDirs 'External Client App'
        } else {
            Write-Host '2. External Client App: skipped (-OrgConfig empty)'
        }

        Write-Host '3. The MCP servers, at Metadata API 67.0'
        $scratch = Join-Path ([IO.Path]::GetTempPath()) ("amf-mcp-servers-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
        New-Item -ItemType Directory -Force "$scratch/mcp/main/default/mcpServerDefinitions" | Out-Null
        Copy-Item 'mcp/main/default/mcpServerDefinitions/*.mcpServerDefinition-meta.xml' "$scratch/mcp/main/default/mcpServerDefinitions/"
        [IO.File]::WriteAllText("$scratch/sfdx-project.json",
            '{"packageDirectories":[{"path":"mcp","default":true}],"name":"amf-mcp-servers","namespace":"","sfdcLoginUrl":"https://login.salesforce.com","sourceApiVersion":"67.0"}')
        Push-Location $scratch
        try { Deploy-Dirs @('mcp') 'MCP servers' } finally { Pop-Location; Remove-Item -Recurse -Force $scratch -ErrorAction SilentlyContinue }
    }

    Write-Host '4. Activating the servers'
    $definitions = (Invoke-SfJson @('data', 'query', '--use-tooling-api', '-o', $TargetOrg, '--query',
        "SELECT Id, DeveloperName, MasterLabel FROM McpServerDefinition WHERE DeveloperName IN ('$($servers -join "','")')")).result.records
    $access = (Invoke-SfJson @('data', 'query', '--use-tooling-api', '-o', $TargetOrg, '--query',
        'SELECT Id, McpServerId, Active FROM McpServerAccess WHERE McpServerId != null')).result.records
    foreach ($definition in $definitions) {
        $row = $access | Where-Object { $_.McpServerId -eq $definition.Id } | Select-Object -First 1
        if ($row -and $row.Active) {
            Write-Host "  $($definition.MasterLabel): already active."
        } elseif ($row) {
            Invoke-SfRest "/services/data/v67.0/tooling/sobjects/McpServerAccess/$($row.Id)" 'PATCH' '{"Active":true}' | Out-Null
            Write-Host "  $($definition.MasterLabel): activated."
        } else {
            $body = @{ DeveloperName = $definition.DeveloperName; MasterLabel = $definition.MasterLabel; Active = $true; McpServerId = $definition.Id } | ConvertTo-Json -Compress
            Invoke-SfRest '/services/data/v67.0/tooling/sobjects/McpServerAccess' 'POST' $body | Out-Null
            Write-Host "  $($definition.MasterLabel): activated."
        }
    }

    $tools = Invoke-SfRest ('/services/data/v67.0/tooling/query?q=' + [uri]::EscapeDataString(
        'SELECT McpServer.DeveloperName, ToolName, ReadOnly, Destructive FROM McpServerToolDefinition ORDER BY McpServer.DeveloperName, ToolName'))
    foreach ($tool in $tools.records) {
        $kind = if ($tool.ReadOnly) { 'read-only' } elseif ($tool.Destructive) { 'asks first (destructive)' } else { 'not annotated' }
        Write-Host ("    {0,-24} {1,-22} {2}" -f $tool.McpServer.DeveloperName, $tool.ToolName, $kind)
    }

    Write-Host '5. The preview key'
    $run = Invoke-SfJson @('apex', 'run', '--file', 'scripts/setup-mcp.apex', '-o', $TargetOrg)
    $said = ($run.result.logs -split "`n" | Where-Object { $_ -match 'Claude connector: ' } | Select-Object -Last 1) -replace '^.*Claude connector: ', ''
    Write-Host "  $said"

    $permissionSet = if ($Admin) { 'AMF_Claude_Connector_Admin' } else { 'AMF_Claude_Connector_User' }
    Write-Host "6. Assigning $permissionSet"
    $assign = @('org', 'assign', 'permset', '--name', $permissionSet, '-o', $TargetOrg)
    foreach ($username in $AssignTo) { $assign += @('--on-behalf-of', $username) }
    & sf @assign 2>$null | Out-Null
    Write-Host ('  ' + $(if ($LASTEXITCODE -eq 0) { 'Assigned (or already held).' } else { 'Not assigned: it may already be held. Check the user''s permission sets.' }))

    $org = (Invoke-SfJson @('data', 'query', '-o', $TargetOrg, '--query', 'SELECT IsSandbox FROM Organization')).result.records[0]
    $base = 'https://api.salesforce.com/platform/mcp/v1/' + $(if ($org.IsSandbox) { 'sandbox/' } else { '' }) + 'custom/'
    $userUrl = $base + $servers[0]
    $adminUrl = $base + $servers[1]

    $keyDir = Join-Path ([IO.Path]::GetTempPath()) ("amf-eca-" + [Guid]::NewGuid().ToString('N').Substring(0, 8))
    Invoke-SfJson @('project', 'retrieve', 'start', '--metadata', "ExtlClntAppGlobalOauthSettings:$EcaName",
        '--target-metadata-dir', $keyDir, '--unzip', '-o', $TargetOrg) | Out-Null
    $keyFile = Get-ChildItem -Recurse $keyDir -Filter "$EcaName.ecaGlblOauth" | Select-Object -First 1
    $clientId = if ($keyFile) { ([xml](Get-Content $keyFile.FullName -Raw)).ExtlClntAppGlobalOauthSettings.consumerKey } else { '(not found: is the External Client App deployed?)' }
    Remove-Item -Recurse -Force $keyDir -ErrorAction SilentlyContinue

    Write-Host ''
    Write-Host 'Ready. A new External Client App can take up to 30 minutes before its first login works.'
    Write-Host ''
    Write-Host "  Approval Matrix (everyone)    $userUrl"
    Write-Host "  Approval Matrix Admin         $adminUrl"
    Write-Host "  OAuth Client ID               $clientId"
    Write-Host ''
    Write-Host 'claude.ai, Claude Desktop and mobile:'
    Write-Host '  Customize > Connectors > + > Add custom connector. Name: Approval Matrix. URL: the first one above.'
    Write-Host '  Advanced settings > OAuth Client ID: the client ID above; leave the secret empty. Add, then Connect,'
    Write-Host '  log in to Salesforce and Allow. Administrators add Approval Matrix Admin the same way.'
    Write-Host '  In the connector''s tool permissions, keep submit_for_approval on "Needs approval".'
    Write-Host ''
    Write-Host 'Claude Code:'
    Write-Host "  claude mcp add --transport http --scope user approval-matrix $userUrl --client-id $clientId --callback-port 38000"
    Write-Host "  claude mcp add --transport http --scope user approval-matrix-admin $adminUrl --client-id $clientId --callback-port 38000"
    Write-Host '  then, in Claude Code, /mcp > approval-matrix > Authenticate.'
    Write-Host ''
    Write-Host 'Guide: docs/claude-connector.md'
} catch {
    Write-Host "Setup stopped: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    Pop-Location
}
