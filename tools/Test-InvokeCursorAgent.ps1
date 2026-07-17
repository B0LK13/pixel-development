<#
Test-InvokeCursorAgent.ps1
Simple test harness to run Invoke-CursorAgent.ps1 against fixture files and
emit the produced dispatch-result.json content for review. Does not launch any
real Cursor process.
#>
param(
    [string]$Fixture = "tests/fixtures/stream-json/example-ok.txt",
    [string]$OutputDir = "tests/fixtures/stream-json/out",
    [switch]$Verbose
)

if (-not (Test-Path $Fixture)) { Write-Error "Fixture not found: $Fixture"; exit 2 }
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir | Out-Null }

$parser = Join-Path (Get-Location) 'adapters/Invoke-CursorAgent.ps1'
if (-not (Test-Path $parser)) { Write-Error "Parser not found: $parser"; exit 3 }

# run parser
pwsh -File $parser -InputFile $Fixture -OutputDir $OutputDir -VerboseLogging:$Verbose

# show result
$dr = Join-Path $OutputDir 'dispatch-result.json'
if (Test-Path $dr) { Get-Content $dr -Raw; exit 0 } else { Write-Error "dispatch-result.json missing"; exit 4 }
