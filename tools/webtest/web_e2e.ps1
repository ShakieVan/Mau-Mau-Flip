param(
    [int]$Port = 24870,
    [int]$Seconds = 300,                 # Zeitgrenze des Godot-Gastgebers
    [switch]$Bilder,                     # zusätzlich Kontrollbilder einer echten Partie nach docs/module/E2_*.png
    [string]$Regeln = '',                # JSON für RuleConfig.apply_dict, z. B. '{"stacking":"same"}'
    [int]$Bots = 2,
    [string]$Szene = '',                 # gebaute Lage im Gastgeber, z. B. "farbwahl" (Phase color, dazu -Bots 1)
    [string]$Adb = '',                   # Seriennummer: Gerätetest im Chrome des Handys statt Chrome headless
    [switch]$Lan,                        # mit -Adb: über die WLAN-Adresse des PCs statt adb reverse (Windows-Firewall!)
    [string]$Chrome = 'C:\Program Files\Google\Chrome\Application\chrome.exe',
    [string]$AdbExe = (Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe')
)
# Modul E2 – Ende-zu-Ende-Test des Browser-Clients „Lite“ am echten Gastgeber.
#  1. Startet game/tests/web_host.gd über tools/godot_run.ps1 im Hintergrund: der ECHTE Gastgeber HostTable (Modul G) mit
#     Computergegnern, der Gastgeber-Platz spielt per MauBot; der Gastgeber packt webclient/ selbst zu einer Zip, game/assets/web.zip
#     bleibt unberührt.
#  2. Wartet, bis http://127.0.0.1:<Port>/info antwortet.
#  3. Chrome headless (--dump-dom) öffnet http://127.0.0.1:<Port>/?autotest=1&halter=<Port+1>&tempo=3&trennen=1: Der Selbsttest
#     (webclient/autotest.js) tritt bei, meldet Bereit, spielt über die echte Oberfläche bis zum Rundenende (einfache Strategie aus
#     hints), trennt einmal hart und kommt mit Token zurück, prüft jede Sicht Feld für Feld und schreibt #autotest-result.
#     Das iframe zum „Halter“ (Port + 1, antwortet nie) hält das load-Ereignis auf, bis der Test fertig ist.
#  4. Mit -Bilder weitere Sitzungen über tools/webtest/cdp.ps1 (exakte Geräteansicht): E2_tisch_844x390, E2_tisch_1600x720,
#     E2_rundenende_844x390, E2_mau_844x390 und E2_mau_1600x720 (erste Mau-Blase der Partie; der Selbsttest läuft danach zu Ende).
#  5. Bestanden, wenn das DOM data-ok="1" zeigt und der Gastgeber „RESULT: n ok“ ohne FAIL meldet.
# Mit -Adb <Seriennummer>: Gerätetest. Der Chrome des Handys öffnet die Seite (adb reverse auf 127.0.0.1, mit -Lan über die
# WLAN-Adresse des PCs), Bildschirmfotos nach docs/module/E2_s10_*.png. Am Gerät wird nichts eingestellt.
# Aufruf:  powershell -NoProfile -Command "& 'E:\Documents\Programmierung\Mau-Mau Flip\tools\webtest\web_e2e.ps1' -Bilder"
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$run = Join-Path $root 'tools\godot_run.ps1'
$cdp = Join-Path $PSScriptRoot 'cdp.ps1'
$out = Join-Path $root 'docs\module'
if (-not (Test-Path -LiteralPath $Chrome)) { throw "Chrome nicht gefunden: $Chrome" }

$sitzungen = 1
if ($Bilder -and $Adb -eq '') { $sitzungen = 6 }
$envPairs = @("WEB_PORT=$Port", "WEB_SEKUNDEN=$Seconds", "WEB_SITZUNGEN=$sitzungen", "WEB_BOTS=$Bots")
if ($Regeln -ne '') { $envPairs += "WEB_REGELN=$Regeln" }
if ($Szene -ne '') { $envPairs += "WEB_SZENE=$Szene" }
if ($Adb -ne '') { $envPairs += @('WEB_NACH_BERICHT=8000', 'WEB_HALTER=0') }

$job = Start-Job -ScriptBlock {
    param($run, $seconds, $envPairs)
    & $run -Script 'res://tests/web_host.gd' -Headless -Timeout ($seconds + 20) -EnvPairs $envPairs
} -ArgumentList $run, $Seconds, $envPairs

function Warte-Server {
    $deadline = (Get-Date).AddMinutes(30)       # die Godot-Sperre kann noch von anderen Läufen gehalten sein
    while ((Get-Date) -lt $deadline -and $job.State -eq 'Running') {
        try {
            $r = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/info" -TimeoutSec 2
            if ($r.StatusCode -eq 200) { return $true }
        } catch { }
        Start-Sleep -Milliseconds 300
    }
    return $false
}
function Warte-Lobby {
    # nächste Sitzung erst, wenn der Gastgeber die vorige abgeschlossen hat (sonst Ablehnung „running“)
    $deadline = (Get-Date).AddSeconds(40)
    while ((Get-Date) -lt $deadline -and $job.State -eq 'Running') {
        try { $i = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/info" -TimeoutSec 2; if (-not $i.running) { return $true } } catch { }
        Start-Sleep -Milliseconds 400
    }
    return $false
}
function Ergebnis([string]$text) {
    $m = [regex]::Match($text, '<pre id="autotest-result" data-ok="(\d)"[^>]*>([^<]*)</pre>')
    if (-not $m.Success) { return @{ ok = $false; text = '(kein Ergebnis im DOM)' } }
    return @{ ok = ($m.Groups[1].Value -eq '1'); text = [System.Net.WebUtility]::HtmlDecode($m.Groups[2].Value) }
}

$ok = $true
$basis = "http://127.0.0.1:$Port/"
if (-not (Warte-Server)) {
    Write-Output "Server nicht erreichbar (Godot-Lauf: $($job.State))"
    $ok = $false
} elseif ($Adb -ne '') {
    # ---------- Gerätetest am Handy ----------
    $adbT = { param($a) $p = Start-Process -FilePath $AdbExe -ArgumentList $a -PassThru -NoNewWindow -RedirectStandardOutput "$env:TEMP\mmf_adb.txt" -RedirectStandardError "$env:TEMP\mmf_adb.err"; if (-not $p.WaitForExit(20000)) { Stop-Process -Id $p.Id -Force; 'ADB-ZEITGRENZE' } else { Get-Content "$env:TEMP\mmf_adb.txt" -Raw } }
    if ($Lan) {
        $ip = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '192.168.*' -and $_.PrefixOrigin -ne 'WellKnown' } | Select-Object -First 1).IPAddress
        $basis = "http://${ip}:$Port/"
    } else {
        & $adbT @('-s', $Adb, 'reverse', "tcp:$Port", "tcp:$Port") | Out-Null
    }
    $url = $basis + '?autotest=1&tempo=2'
    Write-Output "Handy $Adb öffnet $url"
    & $adbT @('-s', $Adb, 'shell', 'am', 'start', '-a', 'android.intent.action.VIEW', '-d', "'$url'", 'com.android.chrome') | Out-Null
    foreach ($i in 1..8) {
        Start-Sleep -Seconds 12
        if ($job.State -ne 'Running') { break }
        $png = Join-Path $out ("E2_s10_{0}.png" -f $i)
        $p = Start-Process -FilePath $AdbExe -ArgumentList @('-s', $Adb, 'exec-out', 'screencap', '-p') -PassThru -NoNewWindow -RedirectStandardOutput $png
        if (-not $p.WaitForExit(15000)) { Stop-Process -Id $p.Id -Force }
        Write-Output "Bild: $png ($((Get-Item $png).Length) Byte)"
    }
} else {
    # ---------- 1. Selbsttest mit --dump-dom ----------
    $profileDir = Join-Path $env:TEMP ('mmf_e2e_' + [guid]::NewGuid().ToString('N'))
    $domFile = Join-Path $env:TEMP ('mmf_e2e_dom_' + [guid]::NewGuid().ToString('N') + '.html')
    $url = $basis + "?autotest=1&halter=$($Port + 1)&tempo=3&trennen=1"
    $chromeArgs = @('--headless=new', '--disable-gpu', '--no-first-run', '--no-default-browser-check', '--disable-extensions', '--mute-audio',
        '--autoplay-policy=no-user-gesture-required', "--user-data-dir=`"$profileDir`"", '--window-size=870,490', "--timeout=$(($Seconds - 40) * 1000)", '--dump-dom', $url)
    Write-Output "Chrome headless: $url"
    $t0 = Get-Date
    $proc = Start-Process -FilePath $Chrome -ArgumentList $chromeArgs -PassThru -NoNewWindow -RedirectStandardOutput $domFile -RedirectStandardError ($domFile + '.err')
    if (-not $proc.WaitForExit(($Seconds - 20) * 1000)) { Write-Output 'Chrome: Zeitgrenze - beendet'; Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
    $dom = Get-Content -LiteralPath $domFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if ($null -eq $dom) { $dom = '' }
    $e = Ergebnis $dom
    Write-Output ("Selbsttest ({0:N0} s): {1}" -f ((Get-Date) - $t0).TotalSeconds, $e.text)
    if (-not $e.ok) { $ok = $false; Copy-Item -LiteralPath $domFile -Destination (Join-Path $env:TEMP 'mmf_e2e_letzter_dom.html') -Force }
    Remove-Item -LiteralPath $domFile, ($domFile + '.err') -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $profileDir -Recurse -Force -ErrorAction SilentlyContinue

    # ---------- 2. Kontrollbilder einer echten Partie ----------
    if ($Bilder) {
        $fertig = "!!document.getElementById('autotest-result')&&MMF.App.tisch&&MMF.App.tisch.regie.leer&&document.fonts.status==='loaded'"
        $versteck = "var r=document.getElementById('autotest-result');if(r)r.style.display='none';document.querySelectorAll('.toast').forEach(t=>t.remove());true"
        # Mau-Blase mitten in der Partie: Bild, sobald eine Blase steht (blase=8000 hält sie 8 s), danach läuft der Selbsttest zu Ende
        $blase = "!!document.querySelector('.mau-blase:not(.aus)')&&document.fonts.status==='loaded'"
        $liste = @(
            @{ name = 'tisch_844x390'; q = '?autotest=1&zuege=5&tempo=3'; w = 844; h = 390; s = 2 },
            @{ name = 'tisch_1600x720'; q = '?autotest=1&zuege=7&tempo=3'; w = 1600; h = 720; s = 1 },
            @{ name = 'rundenende_844x390'; q = '?autotest=1&tempo=3'; w = 844; h = 390; s = 2 },
            @{ name = 'mau_844x390'; q = '?autotest=1&tempo=3&blase=8000'; w = 844; h = 390; s = 2; warte = $blase; ms = 1000 },
            @{ name = 'mau_1600x720'; q = '?autotest=1&tempo=3&blase=8000'; w = 1600; h = 720; s = 1; warte = $blase; ms = 1000 }
        )
        foreach ($b in $liste) {
            $ziel = Join-Path $out ("E2_{0}.png" -f $b.name)
            $warte = if ($b.warte) { $b.warte } else { $fertig }
            $ms = if ($b.ms) { $b.ms } else { 700 }
            $cargs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $cdp, '-Url', ($basis + $b.q), '-Out', $ziel, '-Width', $b.w, '-Height', $b.h,
                '-Scale', $b.s, '-WaitExpr', $warte, '-Pre', $versteck, '-WaitMs', $ms, '-TimeoutMs', 200000,
                '-Eval', "document.getElementById('autotest-result').dataset.ok+' '+document.getElementById('autotest-result').textContent")
            if ($b.warte) { $cargs += @('-EndExpr', "!!document.getElementById('autotest-result')", '-EndTimeoutMs', 200000) }
            if ($b.w -lt 1200) { $cargs += '-Mobile' }
            if (-not (Warte-Lobby)) { Write-Output 'Gastgeber kehrt nicht in die Lobby zurück'; $ok = $false; break }
            $r = & powershell @cargs 2>&1 | Out-String
            Write-Output ("Bild {0}: {1}" -f $b.name, ($r.Trim() -replace '\s+', ' ').Substring(0, [Math]::Min(700, ($r.Trim() -replace '\s+', ' ').Length)))
            if ($r -notmatch 'EVAL: 1 ') { $ok = $false }
        }
    }
}
$godot = Receive-Job $job -Wait -AutoRemoveJob | Out-String
if ($Adb -ne '' -and -not $Lan) {
    $p = Start-Process -FilePath $AdbExe -ArgumentList @('-s', $Adb, 'reverse', '--remove', "tcp:$Port") -PassThru -NoNewWindow
    $null = $p.WaitForExit(10000)
}
Write-Output '--- Godot-Gastgeber (Auszug) ---'
$zeilen = $godot -split "`r?`n" | Where-Object { $_ -match 'SERVER-BEREIT|PARTIE|Sitzung|STATS|RESULT|FAIL|ABGELEHNT|abgelehnt|LOG: Gast|SCRIPT ERROR|ERROR' }
Write-Output ($zeilen -join "`n")
$godotOk = ($godot -match 'RESULT: \d+ ok') -and ($godot -notmatch 'FAIL:') -and ($godot -notmatch 'SCRIPT ERROR')
if ($ok -and $godotOk) { Write-Output 'WEB-E2E: bestanden'; exit 0 }
Write-Output "WEB-E2E: FEHLGESCHLAGEN (Browser ok: $ok, Gastgeber ok: $godotOk)"
exit 1
