<#
Invoke-CursorAgent.ps1
Minimal envelope-aware stream-json parser for Cursor adapter remediation.
This script reads lines from stdin (or from a file via -InputFile) and
implements defensive parsing for "stream-json" mode.

Behavior (conservative):
- For each line: attempt to parse JSON. On parse error, record STREAM_JSON_PARSE_ERROR.
- Inspect envelope shape. Eligible envelopes are those that contain an explicit 'event' property
  either at the top-level or inside a common payload container (e.g., .event, .payload.event).
- Ignore envelopes with type 'user' or 'system' unless they also carry a valid event object.
- Recognize acknowledgment: {"event":"CURSOR_TASK_ACKNOWLEDGED"}
- Recognize completion: {"event":"CURSOR_TASK_COMPLETED","status":"COMPLETE"}
- Fail-closed: on any unrecoverable/malformed condition, write dispatch-result.json with an error code.

Usage:
  pwsh Invoke-CursorAgent.ps1 -InputFile fixtures/stream-json/...
#>
param(
    [string]$InputFile = '-',
    [string]$OutputDir = ".",
    [switch]$VerboseLogging
)

function Write-DispatchResult($obj) {
    $json = ($obj | ConvertTo-Json -Depth 5)
    $outPath = Join-Path $OutputDir 'dispatch-result.json'
    try {
        $json | Out-File -FilePath $outPath -Encoding utf8 -Force
    } catch {
        Write-Error "Failed writing dispatch result: $_"
    }
}

# state
$ackSeen = $false
$completionSeen = $false
$completionStatus = $null
$errors = @()

# helper safe property check
function Has-Property($o, $name) {
    if ($null -eq $o) { return $false }
    return $o.PSObject.Properties.Name -contains $name
}

# read lines
if ($InputFile -ne '-' -and -Not (Test-Path $InputFile)) {
    Write-Error "InputFile not found: $InputFile"
    Write-DispatchResult @{ status = 'ERROR'; reason = 'INPUT_FILE_NOT_FOUND'; input = $InputFile }
    exit 2
}

$reader = if ($InputFile -eq '-') { [Console]::In } else { [System.IO.File]::OpenText($InputFile) }

try {
    while ($null -ne ($line = $reader.ReadLine())) {
        if ($line -eq '') { continue }
        if ($VerboseLogging) { Write-Host "LINE: $line" }
        # attempt JSON parse
        $obj = $null
        try {
            $obj = $line | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $errors += 'STREAM_JSON_PARSE_ERROR'
            if ($VerboseLogging) { Write-Host "JSON parse error: $_" }
            continue
        }

        # Defensive extraction of event
        $eventObj = $null
        if (Has-Property $obj 'event') {
            $eventObj = $obj
        } elseif (Has-Property $obj 'payload' -and Has-Property $obj.payload 'event') {
            $eventObj = $obj.payload
        } elseif (Has-Property $obj 'data' -and Has-Property $obj.data 'event') {
            $eventObj = $obj.data
        } else {
            # inspect common nested envelope shapes
            foreach ($prop in $obj.PSObject.Properties) {
                $val = $prop.Value
                if ($val -is [System.Management.Automation.PSCustomObject] -and Has-Property $val 'event') {
                    $eventObj = $val
                    break
                }
            }
        }

        if ($null -eq $eventObj) {
            # If envelope explicitly marks its type as user/system, ignore; else mark as unsupported
            if (Has-Property $obj 'type') {
                $t = $obj.type.ToString()
                if ($t -in @('user','system')) {
                    if ($VerboseLogging) { Write-Host "Ignoring envelope type: $t" }
                    continue
                }
            }
            $errors += 'UNSUPPORTED_STREAM_ENVELOPE'
            if ($VerboseLogging) { Write-Host "Unsupported envelope, no event found" }
            continue
        }

        # now safe to inspect event property
        if (-not (Has-Property $eventObj 'event')) {
            $errors += 'MALFORMED_PROTOCOL_EVENT'
            continue
        }

        $ev = $eventObj.event.ToString()
        if ($ev -eq 'CURSOR_TASK_ACKNOWLEDGED') {
            $ackSeen = $true
            if ($VerboseLogging) { Write-Host "ACK seen" }
            continue
        }
        if ($ev -eq 'CURSOR_TASK_COMPLETED') {
            # ensure status exists
            if (-not (Has-Property $eventObj 'status')) {
                $errors += 'MALFORMED_PROTOCOL_EVENT'
                continue
            }
            $completionSeen = $true
            $completionStatus = $eventObj.status.ToString()
            if ($VerboseLogging) { Write-Host "COMPLETION seen: $completionStatus" }
            continue
        }

        # ignore other events
        if ($VerboseLogging) { Write-Host "Ignoring non-protocol event: $ev" }
    }
} finally {
    if ($reader -ne [Console]::In) { $reader.Close() }
}

# Determine final outcome
$result = @{ }
if ($completionSeen -and $completionStatus -eq 'COMPLETE' -and $ackSeen) {
    $result.status = 'COMPLETE'
    $result.detail = 'Task acknowledged and completed'
} elseif ($completionSeen -and $completionStatus -eq 'COMPLETE' -and -not $ackSeen) {
    $result.status = 'COMPLETE_WITHOUT_ACK'
    $result.detail = 'Completion seen without prior explicit ack'
    $errors += 'MISSING_ACK'
} elseif ($completionSeen -and $completionStatus -ne 'COMPLETE') {
    $result.status = 'COMPLETE_WITH_NONCOMPLETE_STATUS'
    $result.detail = "Completion seen with status $completionStatus"
    $errors += 'COMPLETION_NONCOMPLETE'
} else {
    $result.status = 'FAIL'
    $result.detail = 'No valid completion event observed'
    $errors += 'NO_COMPLETION'
}

if ($errors.Count -gt 0) { $result.errors = $errors }

# write dispatch result
$result.timestamp = (Get-Date).ToString('o')
Write-DispatchResult $result

if ($result.status -eq 'COMPLETE') { exit 0 } else { exit 3 }