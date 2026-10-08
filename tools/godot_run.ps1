param(
    [Parameter(Mandatory = $true)][string]$Script,
    [int]$Timeout = 90,
    [string]$Resolution = '1600x900',
    [string[]]$EnvPairs = @(),
    [string[]]$Extra = @(),
    [switch]$Headless,
    [int]$LockWaitMinutes = 60
)
# Startet ein Godot-Testskript aus game/tests mit Zeitgrenze und gibt die Ausgabe zurück. Bei einem Skriptfehler innerhalb einer
# Coroutine bleibt Godot sonst offen. Umgebungsvariablen der Skripte (z. B. SZENARIO=…) als "NAME=Wert" in -EnvPairs.
# Beispiel:  tools/godot_run.ps1 -Script res://tests/test_rules.gd
# (aus der PowerShell heraus aufrufen, nicht über "powershell -File": dort kommt -EnvPairs als eine Zeichenkette an)
# Weitere Godot-Argumente in -Extra, z. B. -Extra '--audio-driver','Dummy' (Tonaufnahme ohne Lautsprecher).
# Godot-Läufe des Projekts laufen nie gleichzeitig: Alle Skripte (godot_run, build) halten dazu den benannten
# Systemmutex Global\MauMauFlipGodot (mehrere Agenten teilen game/.godot und die Importe). Innerhalb desselben Prozesses
# ist die Sperre wiederholt nehmbar. Kindprozesse eines laufenden Baus (MMF_GODOT_LOCK_OWNER) sperren nicht erneut.
$root = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $root '.tools\Godot_v4.6.1-stable_win64_console.exe'
$lock = New-Object System.Threading.Mutex($false, 'Global\MauMauFlipGodot')
$held = $false
try {
    # Aus einem laufenden Bau (tools/build.ps1 haelt die Sperre, MMF_GODOT_LOCK_OWNER = seine Prozessnummer) heraus nicht erneut sperren.
    $owner = $env:MMF_GODOT_LOCK_OWNER
    $insideBuild = $owner -match '^[0-9]+$' -and $null -ne (Get-Process -Id ([int]$owner) -ErrorAction SilentlyContinue)
    if ($insideBuild) { $held = $false }
    else {
        try { $held = $lock.WaitOne([TimeSpan]::FromMinutes($LockWaitMinutes)) }
        catch [System.Threading.AbandonedMutexException] { $held = $true }    # Vorbesitzer abgestürzt: die Sperre gilt als erworben
    }
    if (-not $held -and -not $insideBuild) { throw "Godot-Sperre (Global\MauMauFlipGodot) nach $LockWaitMinutes min nicht frei" }
    foreach ($p in $EnvPairs) { $k, $v = $p.Split('=', 2); Set-Item -Path "Env:$k" -Value $v }
    $out = Join-Path $env:TEMP ("godot_run_" + [guid]::NewGuid().ToString('N') + '.txt')
    $err = $out + '.err'
    # Anführungszeichen: Der Projektpfad enthält Leerzeichen, und Start-Process setzt bei -ArgumentList keine.
    $arguments = @('--path', ('"' + (Join-Path $root 'game') + '"'))
    if ($Headless) { $arguments += '--headless' } else { $arguments += @('--resolution', $Resolution) }
    $arguments += $Extra
    $arguments += @('--script', $Script)
    $proc = Start-Process -FilePath $exe -ArgumentList $arguments -PassThru -NoNewWindow -RedirectStandardOutput $out -RedirectStandardError $err
    if (-not $proc.WaitForExit($Timeout * 1000)) {
        Write-Output "ZEITGRENZE nach $Timeout s - Prozess beendet"
        # nur den eigenen Prozess samt Kindern beenden (nicht jedes Godot: Editor und Läufe anderer bleiben unberührt)
        Get-CimInstance Win32_Process -Filter "ParentProcessId=$($proc.Id)" -ErrorAction SilentlyContinue |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    Get-Content $out -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch '^(Godot Engine|Vulkan)' -and $_.Trim() -ne '' }
    Get-Content $err -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -ne '' } | Select-Object -First 20
    Remove-Item $out, $err -ErrorAction SilentlyContinue
}
finally {
    foreach ($p in $EnvPairs) { $k = $p.Split('=', 2)[0]; Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
    if ($held) { $lock.ReleaseMutex() }
    $lock.Dispose()
}
