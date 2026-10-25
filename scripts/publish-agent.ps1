<#
    Publishes, then activates, the Approval Matrix Assistant (M13).

    sf agent publish authoring-bundle looks for the bundle only in the project's
    default package directory, force-app, and the bundle lives in agentforce/, so
    that force-app still deploys to an org without Agentforce (technical log
    M13.7). So this script publishes from a throwaway project whose one, default,
    package directory holds a copy of the bundle. The repository is not touched.

    Run from anywhere, after the bundle is deployed:

      powershell -NoProfile -ExecutionPolicy Bypass -File scripts/publish-agent.ps1

    -TargetOrg defaults to amf-dev. -SkipActivate publishes without activating,
    which leaves the previously active version in use.

    --skip-retrieve keeps the Bot, BotVersion and GenAiPlannerBundle that publish
    generates out of source: they are the agent's runtime form, rebuilt from the
    bundle on every publish.
#>
[CmdletBinding()]
param(
    [string]$TargetOrg = 'amf-dev',
    [string]$AgentName = 'AMF_Approval_Assistant',
    [switch]$SkipActivate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$bundle = Join-Path $root "agentforce\main\default\aiAuthoringBundles\$AgentName"

if (-not (Test-Path -LiteralPath $bundle -PathType Container)) {
    throw "No authoring bundle at $bundle"
}

$sourceApiVersion = (Get-Content -LiteralPath (Join-Path $root 'sfdx-project.json') -Raw | ConvertFrom-Json).sourceApiVersion
$project = Join-Path ([IO.Path]::GetTempPath()) ('amf-publish-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))

try {
    $copy = Join-Path $project "agentforce\main\default\aiAuthoringBundles\$AgentName"
    New-Item -ItemType Directory -Force -Path $copy | Out-Null
    Copy-Item -Path (Join-Path $bundle '*') -Destination $copy

    # Without a byte-order mark: the CLI's JSON parser refuses one.
    $projectJson = @{
        packageDirectories = @(@{ path = 'agentforce'; default = $true })
        sourceApiVersion = $sourceApiVersion
    } | ConvertTo-Json -Depth 4
    [IO.File]::WriteAllText((Join-Path $project 'sfdx-project.json'), $projectJson, (New-Object System.Text.UTF8Encoding $false))

    Push-Location -LiteralPath $project
    try {
        sf agent publish authoring-bundle --api-name $AgentName --skip-retrieve -o $TargetOrg
        if ($LASTEXITCODE -ne 0) {
            throw "Publishing $AgentName failed (exit $LASTEXITCODE)."
        }

        if (-not $SkipActivate) {
            sf agent activate --api-name $AgentName -o $TargetOrg
            if ($LASTEXITCODE -ne 0) {
                throw "Activating $AgentName failed (exit $LASTEXITCODE)."
            }
        }
    } finally {
        Pop-Location
    }
} finally {
    Remove-Item -LiteralPath $project -Recurse -Force -ErrorAction SilentlyContinue
}
