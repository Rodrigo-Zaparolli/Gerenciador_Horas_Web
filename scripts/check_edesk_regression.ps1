param(
    [string]$Flutter = 'C:\src\flutter\bin\flutter.bat'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Push-Location $root
try {
    $python = Join-Path $root 'python/python.exe'
    $env:PLAYWRIGHT_BROWSERS_PATH = Join-Path $root 'python/ms-playwright'
    $checks = @(
        @{Name='python'; Command=$python; Arguments=@('-m','unittest','discover','-s','test','-p','test_*.py')},
        @{Name='flutter'; Command=$Flutter; Arguments=@('test',
            'test/hours_send_selection_test.dart','test/edesk_retry_policy_test.dart',
            'test/edesk_web_client_test.dart','test/edesk_send_progress_test.dart',
            'test/edesk_preparation_error_test.dart','test/comment_percentage_receipt_test.dart',
            'test/comment_percentage_test.dart','test/comment_percentage_work_test.dart',
            'test/comment_save_gate_test.dart','test/comment_template_test.dart',
            'test/comment_document_snapshot_test.dart','test/comment_recovery_test.dart',
            'test/standalone_percentage_dialog_test.dart')},
        @{Name='work-selection'; Command=$python; Arguments=@('scripts/check_hours_work_flow.py')},
        @{Name='cold-start'; Command=$python; Arguments=@('scripts/check_hours_cold_start.py')},
        @{Name='hours-batch'; Command=$python; Arguments=@('scripts/check_hours_batch_flow.py')},
        @{Name='percentage-browser'; Command=$python; Arguments=@('scripts/check_comment_percentage_flow.py','edesk_bot')}
    )
    New-Item -ItemType Directory -Path 'build' -Force | Out-Null
    foreach ($check in $checks) {
        $log = Join-Path $root "build/edesk-regression-$($check.Name).txt"
        Write-Host "Checking $($check.Name)..."
        $command = $check.Command
        $arguments = $check.Arguments
        # Windows PowerShell treats native stderr as ErrorRecord even when the
        # program succeeds (unittest writes its normal progress to stderr).
        $ErrorActionPreference = 'Continue'
        & $command @arguments *> $log
        $checkExit = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($checkExit -ne 0) {
            throw "Regression failed: $($check.Name). See $log"
        }
        Write-Host "PASS $($check.Name)"
    }
    Write-Host 'EDESK_REGRESSION_OK - isolated tests only; live E-Desk acceptance still required.'
} finally {
    Pop-Location
}
