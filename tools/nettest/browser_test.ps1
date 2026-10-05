param(
    [int]$Port = 24800,
    [int]$Seconds = 60,
    [int]$Budget = 0,                  # >0: zusätzlich --virtual-time-budget (im Versuch untauglich, siehe page/index.html)
    [string]$Chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe',
    [int]$WaitMinutes = 30,
    [string]$Adb = '',                 # Seriennummer (adb devices): statt Chrome am PC den Chrome des Handys nehmen (adb reverse)
    [string]$AdbExe = (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe')
)
# Browser-Test für Modul D (Netz): Ein echter Chrome spricht mit dem GDScript-Server.
#  1. Startet game/tests/net_browser_host.gd über tools/godot_run.ps1 im Hintergrund (das Skript hält die Godot-Sperre; Chrome braucht
#     sie nicht). Der Server liefert die Testseite tools/nettest/page/ aus einer Test-Zip aus (Port 24800).
#  2. Wartet, bis http://127.0.0.1:<Port>/info antwortet (auch, während die Sperre noch von einem anderen Lauf gehalten wird).
#  3. Chrome headless lädt die Seite (--dump-dom, Sicherheitsnetz --timeout). Die Seite holt Skript (gzip), Stil und /info, probiert
#     https auf demselben Port (muss sofort scheitern: TLS-Byte), verbindet per ws://127.0.0.1:<Port>/ws, schickt hello, bekommt
#     welcome und lobby, Ping/Pong, lobby_ready, trennt und kommt mit Token zurück, prüft ein state mit Umlauten und 70 KB und schreibt
#     RESULT-OK/RESULT-FAIL ins DOM; dasselbe meldet sie dem Server per log. --dump-dom schreibt beim load-Ereignis; ein verstecktes
#     iframe zum „Halter“ (Port + 1, antwortet nie) hält load auf, bis der Test fertig ist. --virtual-time-budget taugt dafür nicht:
#     Die virtuelle Zeit wartet nicht auf WebSocket-Verkehr (Zeitgrenzen der Seite liefen sofort ab), und ein offener Abruf, der sie
#     anhält, hielt im Versuch auch die WebSocket-Ereignisse an. -Budget n schaltet sie trotzdem zu.
#  4. Bestanden, wenn das DOM RESULT-OK enthält und der Godot-Lauf „RESULT: n ok“ ohne FAIL meldet.
# Mit -Adb <Seriennummer>: Gerätetest mit dem Chrome des Handys. adb reverse leitet 127.0.0.1:<Port> (und Port + 1) des Handys zum PC
# (keine Firewall-Freigabe nötig), am Handy öffnet sich die Seite im Chrome. Bestanden, wenn der Godot-Lauf ohne FAIL endet (das DOM
# des Handys liest niemand aus; die Seite meldet ihr Ergebnis per WebSocket). Danach werden die Weiterleitungen wieder entfernt.
# Aufruf:  powershell -NoProfile -Command "& 'E:\Documents\Programmierung\Mau-Mau Flip\tools\nettest\browser_test.ps1'"
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$page = Join-Path $PSScriptRoot 'page'
$run = Join-Path $root 'tools\godot_run.ps1'
if (-not (Test-Path -LiteralPath $Chrome)) { throw "Chrome nicht gefunden: $Chrome" }

$job = Start-Job -ScriptBlock {
    param($run, $page, $seconds, $port)
    & $run -Script 'res://tests/net_browser_host.gd' -Headless -Timeout ($seconds + 30) -EnvPairs @("NETTEST_PAGE=$page", "NETTEST_SECONDS=$seconds", "NETTEST_PORT=$port")
} -ArgumentList $run, $page, $Seconds, $Port

$ready = $false
$deadline = (Get-Date).AddMinutes($WaitMinutes)
while ((Get-Date) -lt $deadline -and $job.State -eq 'Running') {
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/info" -TimeoutSec 2
        if ($r.StatusCode -eq 200) { $ready = $true; break }
    } catch { }
    Start-Sleep -Milliseconds 300
}
$dom = ''
if ($ready -and $Adb -ne '') {
    Write-Output "Server bereit auf Port $Port - öffne die Seite im Chrome von $Adb"
    & $AdbExe -s $Adb reverse "tcp:$Port" "tcp:$Port" | Out-Null
    & $AdbExe -s $Adb reverse "tcp:$($Port + 1)" "tcp:$($Port + 1)" | Out-Null
    & $AdbExe -s $Adb shell am start -a android.intent.action.VIEW -d "http://127.0.0.1:$Port/?autotest=1" com.android.chrome | Out-Null
} elseif ($ready) {
    Write-Output "Server bereit auf Port $Port – starte Chrome headless"
    $profileDir = Join-Path $env:TEMP ('mmf_chrome_' + [guid]::NewGuid().ToString('N'))
    $chromeArgs = @('--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check', '--disable-extensions',
        "--user-data-dir=$profileDir", "--timeout=$(($Seconds - 5) * 1000)", '--dump-dom', "http://127.0.0.1:$Port/?autotest=1")
    if ($Budget -gt 0) { $chromeArgs = @("--virtual-time-budget=$Budget") + $chromeArgs }
    # Chrome mit Zeitgrenze (hängt, falls der Halter-Abruf nie endet)
    $domFile = Join-Path $env:TEMP ('mmf_dom_' + [guid]::NewGuid().ToString('N') + '.html')
    $proc = Start-Process -FilePath $Chrome -ArgumentList $chromeArgs -PassThru -NoNewWindow -RedirectStandardOutput $domFile -RedirectStandardError ($domFile + '.err')
    if (-not $proc.WaitForExit(($Seconds + 20) * 1000)) {
        Write-Output 'Chrome: Zeitgrenze - beendet'
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    $dom = Get-Content -LiteralPath $domFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($null -eq $dom) { $dom = '' }
    Remove-Item -LiteralPath $domFile, ($domFile + '.err') -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $profileDir -Recurse -Force -ErrorAction SilentlyContinue
} else {
    Write-Output "Server nicht erreichbar (Godot-Lauf: $($job.State))"
}
$out = Receive-Job $job -Wait -AutoRemoveJob | Out-String
if ($Adb -ne '') {
    & $AdbExe -s $Adb reverse --remove "tcp:$Port" 2>$null | Out-Null
    & $AdbExe -s $Adb reverse --remove "tcp:$($Port + 1)" 2>$null | Out-Null
}
Write-Output '--- Godot ---'
Write-Output $out.Trim()
$m = [regex]::Match($dom, '<pre id="result">([^<]*)</pre>')
Write-Output '--- Chrome (#result) ---'
Write-Output ($(if ($m.Success) { [System.Net.WebUtility]::HtmlDecode($m.Groups[1].Value) } else { '(kein Ergebnis im DOM)' }))
$domOk = ($m.Success -and $m.Groups[1].Value.StartsWith('RESULT-OK')) -or ($Adb -ne '')
$godotOk = ($out -match 'RESULT: \d+ ok\s*$' -or $out -match 'RESULT: \d+ ok\r?\n') -and ($out -notmatch 'FAIL:')
if ($domOk -and $godotOk) {
    Write-Output 'BROWSERTEST: bestanden'
    exit 0
}
Write-Output "BROWSERTEST: FEHLGESCHLAGEN (DOM ok: $domOk, Godot ok: $godotOk)"
exit 1
