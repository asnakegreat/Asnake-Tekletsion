# remove_bom.ps1
# Removes UTF-8 BOM from specified files and re-saves as BOM-less UTF-8.

$files = @(
    "app/engines/smc_ict.py",
    "app/alerting.py",
    "app/main.py",
    "app/celery_app.py",
    "app/celery_tasks.py",
    "app/position_sizing.py",
    "app/__init__.py",
    "app/engines/__init__.py",
    "tests/test_position_sizing.py"
)

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

foreach ($f in $files) {
    if (Test-Path $f) {
        $content = Get-Content -Raw -Path $f
        # Strip a leading BOM character if present in the string itself
        if ($content.Length -gt 0 -and $content[0] -eq [char]0xFEFF) {
            $content = $content.Substring(1)
        }
        [System.IO.File]::WriteAllText((Resolve-Path $f), $content, $utf8NoBom)
        Write-Host "Cleaned: $f"
    } else {
        Write-Host "Skipped (not found): $f"
    }
}

Write-Host "Done. Review changes with 'git diff', then commit."