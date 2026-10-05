param([int]$Timeout = 300, [int]$LockWaitMinutes = 60)
# Importiert das Projekt ohne Fenster (neue Dateien, Klassen-Cache für class_name). Nötig, nachdem Skripte mit class_name oder neue
# Assets hinzugekommen sind, sonst kennt ein Testlauf die Klassen nicht. Hält denselben Mutex wie godot_run.ps1.
# Aufruf aus Git Bash:  powershell -NoProfile -Command "& 'E:\Documents\Programmierung\Mau-Mau Flip\tools\godot_import.ps1'"
$root = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $root '.tools\Godot_v4.6.1-stable_win64_console.exe'
$lock = New-Object System.Threading.Mutex($false, 'Global\MauMauFlipGodot')
$held = $false
try {
    try { $held = $lock.WaitOne([TimeSpan]::FromMinutes($LockWaitMinutes)) }
    catch [System.Threading.AbandonedMutexException] { $held = $true }
    if (-not $held) { throw "Godot-Sperre (Global\MauMauFlipGodot) nach $LockWaitMinutes min nicht frei" }
    $out = Join-Path $env:TEMP ("godot_import_" + [guid]::NewGuid().ToString('N') + '.txt')
    $err = $out + '.err'
    $arguments = @('--headless', '--path', ('"' + (Join-Path $root 'game') + '"'), '--editor', '--import', '--quit')
    $proc = Start-Process -FilePath $exe -ArgumentList $arguments -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError $err
    if (-not $proc.WaitForExit($Timeout * 1000)) {
        Write-Output "ZEITGRENZE nach $Timeout s - Import beendet"
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    Get-Content $out, $err -ErrorAction SilentlyContinue | Where-Object { $_ -match 'ERROR|SCRIPT ERROR|Parse Error|WARNING' } | Select-Object -First 40
    Write-Output "Import beendet (Exitcode $($proc.ExitCode))"
    Remove-Item $out, $err -ErrorAction SilentlyContinue
}
finally {
    if ($held) { $lock.ReleaseMutex() }
    $lock.Dispose()
}
