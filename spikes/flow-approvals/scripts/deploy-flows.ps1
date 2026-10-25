<#
    Flow approvals spike (M6): deploy named spike flows to amf-dev in MDAPI format.

    The spike lives outside force-app on purpose, so `sf project deploy start` can never
    ship it. This packages only the named flows from spikes/flow-approvals/mdapi/flows
    into a temporary MDAPI directory and deploys them at API 67.0 (the org's version;
    the product package stays at 62.0).

      powershell -NoProfile -File spikes/flow-approvals/scripts/deploy-flows.ps1 -Names AMF_Spike_User
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string[]] $Names,
    [string] $TargetOrg = 'amf-dev',
    [string] $ApiVersion = '67.0'
)

$ErrorActionPreference = 'Stop'
# -File passes "A,B" as one string; accept either form.
$Names = @($Names | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$source = Join-Path $PSScriptRoot '..\mdapi\flows'
$work = Join-Path ([IO.Path]::GetTempPath()) ('amf-flow-spike-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force (Join-Path $work 'flows') | Out-Null

$members = foreach ($name in $Names) {
    Copy-Item -LiteralPath (Join-Path $source "$name.flow") -Destination (Join-Path $work 'flows')
    "        <members>$name</members>"
}
@"
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
$($members -join "`n")
        <name>Flow</name>
    </types>
    <version>$ApiVersion</version>
</Package>
"@ | Set-Content -Encoding UTF8 (Join-Path $work 'package.xml')

$raw = sf project deploy start -o $TargetOrg --metadata-dir $work --api-version $ApiVersion -w 15 --json 2>$null | Out-String
Remove-Item -Recurse -Force $work
$result = $raw | ConvertFrom-Json

Write-Output ("deploy {0}: {1}" -f ($Names -join ','), $result.result.status)
foreach ($failure in @($result.result.details.componentFailures)) {
    if ($failure) {
        Write-Output ("  FAIL {0} [{1}:{2}] {3}" -f $failure.fullName, $failure.lineNumber, $failure.columnNumber, $failure.problem)
    }
}
if (-not $result.result -and $result.message) {
    Write-Output ("  ERROR {0}" -f $result.message)
}
