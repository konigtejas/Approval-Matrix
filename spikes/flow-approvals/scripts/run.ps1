<#
    Flow approvals spike (M6): run an anonymous Apex script with placeholders filled in,
    printing only its ERROR-level debug lines and any failure.

      powershell -NoProfile -File spikes/flow-approvals/scripts/run.ps1 -Script inspect.apex -Vars RECORD_ID=a02...
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Script,
    [string[]] $Vars = @(),
    [string] $TargetOrg = 'amf-dev'
)

$ErrorActionPreference = 'Stop'
$Vars = @($Vars | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
$path = if (Test-Path $Script) { $Script } else { Join-Path $PSScriptRoot $Script }
$body = [IO.File]::ReadAllText((Resolve-Path $path))
foreach ($pair in $Vars) {
    $key, $value = $pair -split '=', 2
    $body = $body.Replace($key, $value)
}
$temp = Join-Path ([IO.Path]::GetTempPath()) ('amf-spike-' + [Guid]::NewGuid().ToString('N') + '.apex')
[IO.File]::WriteAllText($temp, $body, (New-Object Text.UTF8Encoding($false)))

$json = & { $ErrorActionPreference = 'Continue'; sf apex run --file $temp -o $TargetOrg --json 2>$null } | Out-String
Remove-Item -Force $temp
$result = $json | ConvertFrom-Json
$data = if ($result.result) { $result.result } else { $result.data }
if ($data -and -not $data.compiled) {
    Write-Output ('!! COMPILE line {0} col {1}: {2}' -f $data.line, $data.column, $data.compileProblem)
}
if ($data -and $data.compiled -and -not $data.success) {
    Write-Output ('!! RUNTIME line {0}: {1}' -f $data.line, $data.exceptionMessage)
    Write-Output ('!! STACK {0}' -f $data.exceptionStackTrace)
}
foreach ($line in (([string]$data.logs) -split "`r?`n")) {
    if ($line -match '\|USER_DEBUG\|.*\|ERROR\|(.*)$') {
        Write-Output (($Matches[1]) -replace '&#124;', '|' -replace '&quot;', '"' -replace '&#39;', "'")
    } elseif ($line -match '\|(FATAL_ERROR|EXCEPTION_THROWN|FLOW_ELEMENT_ERROR)\|(.*)$') {
        Write-Output ('!! ' + $Matches[1] + ' ' + $Matches[2])
    }
}
if (-not $data) { Write-Output ('!! ' + $result.message) }
