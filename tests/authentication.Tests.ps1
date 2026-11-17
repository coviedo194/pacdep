param(
    [string]$ScriptPath = (Join-Path $PSScriptRoot "../pacdep.ps1"),
    [string]$Case,
    [string]$Fixture
)

$ErrorActionPreference = "Stop"

if ($Case) {
    $global:testCase = $Case
    $global:testFixture = $Fixture
    $global:mockProfile = ""

    function global:Read-Host { return "S" }
    function global:osascript {}
    function global:pac {
        $global:LASTEXITCODE = 0
        Add-Content (Join-Path $global:testFixture "calls.txt") ($args -join " ")
        if ($args.Count -eq 0) { return "Version: test" }
        switch ("$($args[0]) $($args[1])") {
            "auth list" { return "test_dev test_pro" }
            "auth select" { $global:mockProfile = $args[3]; return }
            "env who" {
                if ($global:testCase -eq "mfa-preflight" -and $global:mockProfile -eq "test_pro") {
                    Write-Error "AADSTS50078: Presented multi-factor authentication has expired. timeout" -ErrorAction Continue
                    $global:LASTEXITCODE = 1
                }
                return
            }
            "solution list" {
                if ($global:testCase -eq "mfa-list") {
                    Write-Error "AADSTS50078: Presented multi-factor authentication has expired" -ErrorAction Continue
                    $global:LASTEXITCODE = 1
                    return
                }
                if ($global:testCase -eq "import-direct") {
                    return '[{"SolutionUniqueName":"Default"},{"SolutionUniqueName":"OtherSolution"}]'
                }
                return '[{"SolutionUniqueName":"TestSolution","VersionNumber":"1.0.0.1"},{"SolutionUniqueName":"Default"}]'
            }
            "solution create-settings" {
                '{"EnvironmentVariables":[],"ConnectionReferences":[]}' |
                    Set-Content (Join-Path $global:testFixture "settings_generated.json")
                return
            }
            "solution import" {
                if ($global:testCase -eq "mfa-import") {
                    Write-Error "AADSTS50078: Presented multi-factor authentication has expired. timeout" -ErrorAction Continue
                    $global:LASTEXITCODE = 1
                }
                return
            }
            default { throw "Unexpected PAC command: $args" }
        }
    }

    if ($Case -eq "mfa-preflight") {
        & (Join-Path $Fixture "pacdep.ps1") -TargetEnv pro
    }
    else {
        & (Join-Path $Fixture "pacdep.ps1") -ImportOnly -TargetEnv pro
    }
    exit $LASTEXITCODE
}

$ScriptPath = (Resolve-Path $ScriptPath).Path
$pwshPath = (Get-Process -Id $PID).Path
foreach ($scenario in @("mfa-preflight", "mfa-list", "mfa-import", "import-direct", "import-upgrade")) {
    $fixturePath = Join-Path ([System.IO.Path]::GetTempPath()) ("pacdep-auth-test-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $fixturePath | Out-Null
    try {
        Copy-Item $ScriptPath (Join-Path $fixturePath "pacdep.ps1")
        @{
            solutionName = "TestSolution"
            dev = @{ authProfile = "test_dev"; env = "https://dev.example.invalid" }
            pro = @{ authProfile = "test_pro"; env = "https://pro.example.invalid" }
        } | ConvertTo-Json | Set-Content (Join-Path $fixturePath "config.json")
        "original-zip" | Set-Content (Join-Path $fixturePath "solution.zip")
        "original-zip" | Set-Content (Join-Path $fixturePath "solution_managed.zip")
        '{"EnvironmentVariables":[],"ConnectionReferences":[]}' |
            Set-Content (Join-Path $fixturePath "settings_pro.json")

        $output = & $pwshPath -NoProfile -File $PSCommandPath -Case $scenario -Fixture $fixturePath 2>&1 | Out-String
        $exitCode = $LASTEXITCODE
        $calls = Get-Content (Join-Path $fixturePath "calls.txt") -Raw
        $log = Get-ChildItem (Join-Path $fixturePath "logs") -Filter "*.txt" | Get-Content -Raw
        if ($scenario -like "mfa-*") {
            if ($exitCode -ne 1 -or $output -notmatch "La sesion de Microsoft" -or
                $output -notmatch 'pac auth create --name "test_pro" --environment "https://pro.example.invalid"' -or
                $log -notmatch "AADSTS50078") {
                throw "Missing actionable MFA error, technical log or exit code 1.`n$output"
            }
            $importCount = @($calls -split "`n" | Where-Object { $_ -match "^solution import " }).Count
            $expectedImports = if ($scenario -eq "mfa-import") { 1 } else { 0 }
            if ($importCount -ne $expectedImports -or $calls -match "solution (online-version|export)") {
                throw "Authentication failure must not change DEV or retry an import.`n$calls"
            }
            foreach ($zip in @("solution.zip", "solution_managed.zip")) {
                if ((Get-Content (Join-Path $fixturePath $zip) -Raw).Trim() -ne "original-zip") {
                    throw "Authentication failure modified $zip"
                }
            }
        }
        else {
            if ($exitCode -ne 0 -or $output -notmatch "PROCESO FINALIZADO CORRECTAMENTE") {
                throw "Successful import failed.`n$output"
            }
            $hasUpgrade = $calls -match "solution import .*--stage-and-upgrade"
            if ($hasUpgrade -ne ($scenario -eq "import-upgrade")) {
                throw "Incorrect direct import / upgrade mode.`n$calls"
            }
        }
        Write-Host "PASS: $scenario"
    }
    finally {
        Remove-Item -LiteralPath $fixturePath -Recurse -Force
    }
}
