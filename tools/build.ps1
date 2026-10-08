param(
    [ValidateSet('Test', 'Windows', 'Android', 'Web', 'All')][string]$Target = 'All',
    [switch]$SkipTests,                 # nur für schnelle Probebauten; tools/release.ps1 nutzt es nie
    [switch]$NoTestCache,               # Tests auch dann laufen lassen, wenn genau dieser Stand schon grün war
    [int]$Parallel = 0,                 # parallele Godot-Prozesse für reine Tests (0 = automatisch: Kerne − 4, höchstens 10)
    [int]$TestTimeout = 900,            # Sekunden je Testlauf
    [int]$LockWaitMinutes = 120
)
# Bau von Mau-Mau Flip (Muster Draw2Race tools/build.ps1, docs/BETA1_PLAN.md 9):
#   Web      webclient/ → game/assets/web.zip (läuft auch vor Test, Windows und Android, damit die APK den aktuellen Browser-Client trägt)
#   Test     Import, dann alle game/tests/test_*.gd (außer *_lang*/*_shot*), reine Tests parallel, Netz-/Bildschirmtests in einer
#            eigenen Spur nacheinander; Zusammenfassung, Abbruch bei Fehler. Testergebnis-Cache: War genau dieser Stand (Prüfsumme
#            über game/, webclient/ und dieses Skript, siehe Get-TestStateHash) schon vollständig grün, entfallen die Tests
#            (.tools/test_cache.json; -NoTestCache erzwingt sie).
#   Windows  builds/MauMauFlip.exe (pck eingebettet)
#   Android  RELEASE-Export, signiert mit dem Projektschlüssel .tools/maumauflip-release.keystore; Signatur, Paket und Version der APK
#            werden nachgeprüft; dann builds/MauMauFlip-<version>.apk (diesen Namen erwartet der Updater)
#   All      alles zusammen
# Godot-Läufe des Projekts laufen nie gleichzeitig mit fremden: Der Bau hält den Systemmutex Global\MauMauFlipGodot (wie
# tools/godot_run.ps1) vom Import bis zum letzten Export, einmal. Seine eigenen Godot-Kindprozesse (parallele Tests) startet er ohne
# erneutes Sperren; MMF_GODOT_LOCK_OWNER (seine Prozessnummer) lässt auch godot_run.ps1/godot_import.ps1, wenn sie aus diesem Bau
# heraus gestartet werden, ohne Sperre laufen. Andere Godot-Läufe warten weiter.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$projectRoot = Split-Path $PSScriptRoot -Parent
$engine = Join-Path $projectRoot '.tools/Godot_v4.6.1-stable_win64_console.exe'
$gamePath = Join-Path $projectRoot 'game'
$buildsDir = Join-Path $projectRoot 'builds'

# Android-Signatur: Jede Mau-Mau-Flip-APK trägt den eigenen Release-Schlüssel (AGENTS.md 10). Nur dann passt ein Update zur installierten
# App; mit jedem anderen Schlüssel lehnen Android und der Updater (Updater.java) es ab. SHA-256 seines Zertifikats (öffentlich, steht in
# jeder APK; ermittelt mit keytool -list -v am 04.10.2026):
$projectCertSha256 = '85d6f9d94693e675a71ef5348c3e212b5962f793dd1ab1cdf1c86a0dfc8d15cd'
$packageName = 'de.maumauflip.game'

function Get-VersionCode([string]$Version) {
    # version/code aus der Version: X.Y.Z → X·1 000 000 + Y·1 000 + Z (0.1.1 → 1001, 1.0.0 → 1000000). Er steigt mit jeder höheren
    # Version, also auch von jeder Beta zum nächsten Release. Android erlaubt höchstens 2 100 000 000. (Gleiche Formel: Updater.version_code.)
    if ($Version -notmatch '^(\d{1,4})\.(\d{1,3})\.(\d{1,3})$') { throw "Version '$Version' passt nicht zum Schema X.Y.Z (nur Ziffern, Y und Z höchstens 999)." }
    $code = [long]$Matches[1] * 1000000 + [long]$Matches[2] * 1000 + [long]$Matches[3]
    if ($code -gt 2100000000) { throw "Version '$Version' ergibt version/code $code – mehr als Android erlaubt." }
    return $code
}

function Invoke-Godot([string[]]$Arguments) {
    # Godot schreibt auch auf stderr. Unter Windows PowerShell 5.1 macht "2>&1" daraus Fehlerobjekte, die bei 'Stop' sofort abbrechen –
    # Godot liefe dann verwaist weiter (Draw2Race, 04.10.2026: beschädigte .import-Dateien). Darum läuft Godot immer zu Ende, entschieden
    # wird danach.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $output = @(& $engine @Arguments 2>&1 | ForEach-Object { "$_" }) }
    finally { $ErrorActionPreference = $previousPreference }
    $output | Write-Output
    if ($LASTEXITCODE -ne 0 -or ($output -match 'SCRIPT ERROR|^ERROR:|FAIL:')) { throw "Godot fehlgeschlagen: $Arguments" }
}

function Find-SdkTool([string]$Name) {
    # Werkzeug aus den build-tools des Android-SDK, das auch Godot benutzt (Editor-Einstellung export/android/android_sdk_path), sonst
    # den üblichen Orten; die neueste Fassung gewinnt.
    $roots = @()
    $settings = Get-ChildItem -LiteralPath (Join-Path $env:APPDATA 'Godot') -Filter 'editor_settings-4*.tres' -ErrorAction SilentlyContinue | Sort-Object Name -Descending
    foreach ($file in $settings) {
        $line = Select-String -LiteralPath $file.FullName -Pattern '^export/android/android_sdk_path = "(.+)"' | Select-Object -First 1
        if ($line) { $roots += $line.Matches[0].Groups[1].Value -replace '\\\\', '\' }
    }
    $roots += @($env:ANDROID_HOME, $env:ANDROID_SDK_ROOT, (Join-Path $env:LOCALAPPDATA 'Android\Sdk')) | Where-Object { $_ }
    foreach ($root in $roots) {
        $tools = Join-Path $root 'build-tools'
        if (-not (Test-Path -LiteralPath $tools)) { continue }
        $found = Get-ChildItem -LiteralPath $tools -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName $Name) } |
            Sort-Object { try { [version]$_.Name } catch { [version]'0.0' } } -Descending | Select-Object -First 1
        if ($found) { return Join-Path $found.FullName $Name }
    }
    return $null
}

function Find-Keytool {
    # keytool aus dem JDK, das Godot benutzt (export/android/java_sdk_path), sonst JAVA_HOME bzw. PATH.
    $candidates = @()
    $settings = Get-ChildItem -LiteralPath (Join-Path $env:APPDATA 'Godot') -Filter 'editor_settings-4*.tres' -ErrorAction SilentlyContinue | Sort-Object Name -Descending
    foreach ($file in $settings) {
        $line = Select-String -LiteralPath $file.FullName -Pattern '^export/android/java_sdk_path = "(.+)"' | Select-Object -First 1
        if ($line) { $candidates += Join-Path ($line.Matches[0].Groups[1].Value -replace '\\\\', '\') 'bin\keytool.exe' }
    }
    if ($env:JAVA_HOME) { $candidates += Join-Path $env:JAVA_HOME 'bin\keytool.exe' }
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }
    $cmd = Get-Command keytool -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    # Externes Werkzeug ausführen; Ausgabe als Zeilen, Warnungen auf stderr brechen nicht ab. Exitcode in $script:NativeExit.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = @(& $Exe @Arguments 2>&1 | ForEach-Object { "$_" }) }
    finally { $ErrorActionPreference = $previousPreference }
    $script:NativeExit = $LASTEXITCODE
    return $out
}

function Read-KeyProperties([string]$Path) {
    # .tools/maumauflip-release.properties: keystore=…, alias=…, password=… (Zeilen key=value; # Kommentare)
    $props = @{}
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -match '^\s*#' -or $line -notmatch '=') { continue }
        $key, $value = $line.Split('=', 2)
        $props[$key.Trim()] = $value.Trim()
    }
    return $props
}

function Build-I18nPo {
    # game/i18n/*.po → webclient/i18n_po.js (Beta 1.2.2): die englischen Texte der App auch für den Browser-Client (Hinweise und
    # Gründe des Gastgebers als Bausteine, Regeltexte, Kartennamen, Netz-Meldungen). Nur Einträge mit msgstr; sortiert, damit die
    # Datei bei gleichem Inhalt gleich bleibt (Testcache). Format: window.MMF_I18N_PO = {JSON}; (test_web_contract liest es).
    $dir = Join-Path $gamePath 'i18n'
    $target = Join-Path $projectRoot 'webclient/i18n_po.js'
    $map = New-Object 'System.Collections.Generic.SortedDictionary[string,string]' ([StringComparer]::Ordinal)
    $unq = {
        param([string]$q)
        $t = $q.Trim()
        if ($t.Length -ge 2 -and $t.StartsWith('"') -and $t.EndsWith('"')) { $t = $t.Substring(1, $t.Length - 2) }
        return $t.Replace('\n', "`n").Replace('\"', '"').Replace('\\', '\')
    }
    foreach ($po in @(Get-ChildItem -LiteralPath $dir -Filter '*.po' -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $id = $null; $str = $null; $field = ''
        $flush = { if ($null -ne $id -and $id -ne '' -and $str -ne '') { $map[$id] = $str } }
        foreach ($raw in [IO.File]::ReadAllLines($po.FullName, [Text.Encoding]::UTF8)) {
            $line = $raw.Trim()
            if ($line -eq '' -or $line.StartsWith('#')) { continue }
            if ($line.StartsWith('msgid ')) { . $flush; $id = & $unq $line.Substring(6); $str = ''; $field = 'id' }
            elseif ($line.StartsWith('msgstr ')) { $str = & $unq $line.Substring(7); $field = 'str' }
            elseif ($line.StartsWith('"')) { if ($field -eq 'id') { $id += & $unq $line } elseif ($field -eq 'str') { $str += & $unq $line } }
        }
        . $flush
    }
    $esc = { param([string]$s) '"' + $s.Replace('\', '\\').Replace('"', '\"').Replace("`n", '\n').Replace("`r", '').Replace("`t", '\t') + '"' }
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($k in $map.Keys) { $lines.Add('  ' + (& $esc $k) + ': ' + (& $esc $map[$k])) }
    $body = "/* Erzeugt von tools/build.ps1 (Build-I18nPo) aus game/i18n/*.po – nicht von Hand ändern. */`nwindow.MMF_I18N_PO = {`n" + ($lines -join ",`n") + "`n};`n"
    $old = if (Test-Path -LiteralPath $target) { [IO.File]::ReadAllText($target) } else { '' }
    if ($old -cne $body) { [IO.File]::WriteAllText($target, $body, (New-Object Text.UTF8Encoding($false))) }
    Write-Output ("i18n_po.js: {0} Texte" -f $map.Count)
}

function Build-WebZip {
    # webclient/ → game/assets/web.zip: Einträge mit Pfaden relativ zu webclient/ und „/“ als Trenner (Compress-Archive aus Windows
    # PowerShell 5.1 schriebe „\“), ohne Ordnereinträge und ohne versteckte Dateien. Der Netz-Server (Modul D) liefert daraus aus.
    $source = Join-Path $projectRoot 'webclient'
    $zipPath = Join-Path $gamePath 'assets/web.zip'
    if (-not (Test-Path -LiteralPath (Join-Path $source 'index.html'))) {
        if ($Target -eq 'Web') { throw 'webclient/index.html fehlt – nichts zu packen.' }
        Write-Output 'Hinweis: webclient/index.html fehlt noch – game/assets/web.zip bleibt, wie es ist.'
        return
    }
    Build-I18nPo
    $base = (Resolve-Path -LiteralPath $source).Path.TrimEnd('\') + '\'
    $files = @(Get-ChildItem -LiteralPath $source -Recurse -File | Where-Object {
            $rel = $_.FullName.Substring($base.Length)
            -not ($rel -split '\\' | Where-Object { $_.StartsWith('.') }) } | Sort-Object FullName)
    New-Item -ItemType Directory -Force (Split-Path $zipPath -Parent) | Out-Null
    $tmp = $zipPath + '.tmp'
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
    $stream = [IO.File]::Open($tmp, [IO.FileMode]::CreateNew)
    $zip = New-Object IO.Compression.ZipArchive($stream, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($file in $files) {
            $name = $file.FullName.Substring($base.Length).Replace('\', '/')
            # Bereits komprimierte Formate nicht noch einmal packen (schneller beim Ausliefern, kaum größer).
            $level = if ($file.Extension -in @('.webp', '.png', '.jpg', '.mp4', '.woff2', '.ogg', '.mp3', '.zip', '.gz')) { [IO.Compression.CompressionLevel]::NoCompression } else { [IO.Compression.CompressionLevel]::Optimal }
            [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $file.FullName, $name, $level)
        }
    }
    finally { $zip.Dispose(); $stream.Dispose() }
    Move-Item -LiteralPath $tmp -Destination $zipPath -Force
    Write-Output ("web.zip: {0} Dateien, {1:N0} KB" -f $files.Count, ((Get-Item -LiteralPath $zipPath).Length / 1KB))
}

function Get-TestStateHash {
    # Prüfsumme über alles, was ein Testergebnis beeinflusst: game/ und webclient/ (Dateien, die git verfolgt oder verfolgen würde –
    # .gitignore schließt Erzeugtes wie game/.godot/, game/android/build/build/, libs/ und web.zip aus), dazu dieses Bauskript und
    # die Godot-Fassung. export_presets.cfg geht ein, nachdem der Bau die Versionszeilen gesetzt hat. Ohne git: $null (kein Cache).
    $git = Get-Command git -ErrorAction SilentlyContinue
    if (-not $git) { return $null }
    $list = Invoke-Native $git.Source @('-C', $projectRoot, '-c', 'core.quotepath=off', 'ls-files', '--cached', '--others', '--exclude-standard', '--', 'game', 'webclient', 'tools/build.ps1')
    if ($script:NativeExit -ne 0) { return $null }
    $sha = [Security.Cryptography.SHA256]::Create()
    $sb = New-Object Text.StringBuilder
    [void]$sb.AppendLine("engine $((Get-Item -LiteralPath $engine).Length)")
    foreach ($rel in (@($list | Where-Object { $_ }) | Sort-Object -Unique)) {
        $full = Join-Path $projectRoot $rel
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { [void]$sb.AppendLine("$rel -"); continue }
        $bytes = [IO.File]::ReadAllBytes($full)
        [void]$sb.AppendLine("$rel " + [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', ''))
    }
    $all = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($sb.ToString()))).Replace('-', '').ToLower()
    $sha.Dispose()
    return $all
}

function Read-JsonFile([string]$Path) {
    try { if (Test-Path -LiteralPath $Path) { return [IO.File]::ReadAllText($Path) | ConvertFrom-Json } } catch { }
    return $null
}

function Test-Kind([string]$Name) {
    # Reine Tests (Regeln, Darstellung ohne Netz: keine festen Ports, keine Server) laufen parallel, je Prozess mit eigenem
    # user:// (APPDATA in einem Wegwerfordner – Einstellungs- und Spielstanddateien stören sich so nicht). Alles andere (Netz, Lobby,
    # Bildschirmabläufe, App-Dienste, Updater, Regelsätze) läuft nacheinander in einer eigenen Spur mit dem echten user://. Neue
    # Testskripte landen ohne Eintrag hier in der sicheren, seriellen Spur.
    if ($Name -match '^test_(rules_|ui_|card_view$|smoke$|game_local$|b_assets$)') { return 'parallel' }
    return 'serial'
}

# Lange Dauerläufe in Teile (Umgebungsvariable TEIL=k/n, tests/teil.gd): zusammen dieselben Startwerte wie ungeteilt.
$testSplits = @{ 'test_rules_bots_long' = 8; 'test_rules_swap' = 4; 'test_rules_views_long' = 4; 'test_rules_gamble' = 3; 'test_rules_discard' = 2 }

function Start-TestUnit($Unit) {
    $Unit.Out = Join-Path $env:TEMP ('mmf_test_' + [guid]::NewGuid().ToString('N') + '.txt')
    $Unit.Err = $Unit.Out + '.err'
    $arguments = @('--headless', '--path', ('"' + $gamePath + '"'), '--script', "res://tests/$($Unit.Test).gd")
    $savedAppData = $env:APPDATA
    try {
        if ($Unit.Part) { $env:TEIL = $Unit.Part } else { Remove-Item Env:TEIL -ErrorAction SilentlyContinue }
        if ($Unit.Lane -eq 'parallel') {
            $Unit.UserDir = Join-Path $env:TEMP ('mmf_ud_' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Force $Unit.UserDir | Out-Null
            $env:APPDATA = $Unit.UserDir
        }
        $Unit.Watch = [Diagnostics.Stopwatch]::StartNew()
        $Unit.Proc = Start-Process -FilePath $engine -ArgumentList $arguments -PassThru -NoNewWindow -RedirectStandardOutput $Unit.Out -RedirectStandardError $Unit.Err
        $null = $Unit.Proc.Handle    # sonst liefert Windows PowerShell nach WaitForExit keinen Exitcode
    }
    finally {
        $env:APPDATA = $savedAppData
        Remove-Item Env:TEIL -ErrorAction SilentlyContinue
    }
}

function Complete-TestUnit($Unit, [bool]$TimedOut) {
    if ($TimedOut) {
        Get-CimInstance Win32_Process -Filter "ParentProcessId=$($Unit.Proc.Id)" -ErrorAction SilentlyContinue |
            ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
        Stop-Process -Id $Unit.Proc.Id -Force -ErrorAction SilentlyContinue
    }
    $Unit.Proc.WaitForExit()
    $Unit.Seconds = $Unit.Watch.Elapsed.TotalSeconds
    $exitCode = $Unit.Proc.ExitCode
    $result = @(Get-Content -LiteralPath $Unit.Out, $Unit.Err -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_.Trim() -ne '' })
    Remove-Item -LiteralPath $Unit.Out, $Unit.Err -ErrorAction SilentlyContinue
    if ($Unit.UserDir) { Remove-Item -LiteralPath $Unit.UserDir -Recurse -Force -ErrorAction SilentlyContinue }
    # Ausgabe am Stück je Lauf (nicht durcheinander), wie bisher ohne Kopfzeilen der Engine.
    Write-Output ("--- {0}{1} ({2:N0} s)" -f $Unit.Test, $(if ($Unit.Part) { " [Teil $($Unit.Part)]" } else { '' }), $Unit.Seconds)
    $result | Where-Object { $_ -notmatch '^(Godot Engine|Vulkan|OpenGL)' } | Write-Output
    $Unit.Failures = @($result | Where-Object { $_ -match 'SCRIPT ERROR|^ERROR:|FAIL:' })
    $Unit.Result = "$(@($result | Where-Object { $_ -match 'RESULT: ' }) | Select-Object -Last 1)".Trim()
    $Unit.Problem = ''
    if ($TimedOut) { $Unit.Problem = "Zeitgrenze $TestTimeout s" }
    elseif ($exitCode -ne 0) { $Unit.Problem = "Exitcode $exitCode" }
    elseif (-not $Unit.Result) { $Unit.Problem = 'keine RESULT-Zeile (abgebrochen?)' }
    elseif ($Unit.Failures.Count -gt 0) { $Unit.Problem = "$($Unit.Failures.Count) Fehlerzeile(n)" }
}

function Invoke-Tests {
    # Alle Testskripte laufen immer durch (auch wenn einer scheitert); danach eine Zusammenfassung und ein Abbruch, falls einer
    # fehlgeschlagen ist. Bestanden = Exitcode 0, RESULT-Zeile, keine Fehlermuster (SCRIPT ERROR, ERROR:, FAIL:). Jeder Lauf hat eine
    # Zeitgrenze (hängende Coroutine nach einem Skriptfehler).
    # Zwei Spuren gleichzeitig: reine Tests (Test-Kind) in bis zu $Parallel Godot-Prozessen, die längsten zuerst (Dauer des letzten
    # Laufs aus .tools/test_times.json); die übrigen nacheinander in einer eigenen Spur. Alle Prozesse sind Kinder dieses Baus, der die
    # Godot-Sperre hält; der Import ist vorher gelaufen, kein Testprozess importiert.
    $tests = @(Get-ChildItem -LiteralPath (Join-Path $gamePath 'tests') -Filter 'test_*.gd' | Where-Object { $_.BaseName -notmatch '_lang|_shot' } | Sort-Object Name)
    if ($tests.Count -eq 0) { throw 'Keine Testskripte gefunden (game/tests/test_*.gd).' }
    $timesPath = Join-Path $projectRoot '.tools/test_times.json'
    $known = @{}
    $saved = Read-JsonFile $timesPath
    if ($saved) { foreach ($p in $saved.PSObject.Properties) { $known[$p.Name] = [double]$p.Value } }
    $units = New-Object Collections.ArrayList
    foreach ($test in $tests) {
        $name = $test.BaseName
        $lane = Test-Kind $name
        $n = if ($lane -eq 'parallel' -and $testSplits.ContainsKey($name)) { $testSplits[$name] } else { 1 }
        for ($k = 1; $k -le $n; $k++) {
            $part = if ($n -gt 1) { "$k/$n" } else { '' }
            $key = if ($part) { "$name#$part" } else { $name }
            $estimate = if ($known.ContainsKey($key)) { $known[$key] } else { 30 }
            [void]$units.Add([pscustomobject]@{ Test = $name; Part = $part; Key = $key; Lane = $lane; Estimate = $estimate; Proc = $null; Watch = $null
                    Out = ''; Err = ''; UserDir = ''; Seconds = 0.0; Result = ''; Problem = ''; Failures = @() })
        }
    }
    $parallelQueue = New-Object Collections.Queue
    foreach ($u in @($units | Where-Object { $_.Lane -eq 'parallel' } | Sort-Object Estimate -Descending)) { $parallelQueue.Enqueue($u) }
    $serialQueue = New-Object Collections.Queue
    foreach ($u in @($units | Where-Object { $_.Lane -eq 'serial' })) { $serialQueue.Enqueue($u) }
    $slots = if ($Parallel -gt 0) { $Parallel } else { [Math]::Max(1, [Math]::Min(10, [Environment]::ProcessorCount - 4)) }
    Write-Output ("Tests: {0} Skripte, {1} parallel in bis zu {2} Prozessen ({3} Läufe), {4} nacheinander" -f $tests.Count,
        @($units | Where-Object { $_.Lane -eq 'parallel' } | Select-Object -ExpandProperty Test -Unique).Count, $slots, $parallelQueue.Count, $serialQueue.Count)
    $total = [Diagnostics.Stopwatch]::StartNew()
    $running = New-Object Collections.ArrayList
    $serialBusy = $false
    while ($parallelQueue.Count -gt 0 -or $serialQueue.Count -gt 0 -or $running.Count -gt 0) {
        if (-not $serialBusy -and $serialQueue.Count -gt 0) { $u = $serialQueue.Dequeue(); Start-TestUnit $u; [void]$running.Add($u); $serialBusy = $true }
        while ($parallelQueue.Count -gt 0 -and @($running | Where-Object { $_.Lane -eq 'parallel' }).Count -lt $slots) {
            $u = $parallelQueue.Dequeue(); Start-TestUnit $u; [void]$running.Add($u)
        }
        Start-Sleep -Milliseconds 200
        foreach ($u in @($running)) {
            $done = $u.Proc.HasExited
            $late = (-not $done) -and $u.Watch.Elapsed.TotalSeconds -gt $TestTimeout
            if ($done -or $late) {
                Complete-TestUnit $u $late
                $running.Remove($u)
                if ($u.Lane -eq 'serial') { $serialBusy = $false }
            }
        }
    }
    # Dauer je Lauf merken (Reihenfolge des nächsten Laufs).
    foreach ($u in $units) { if (-not $u.Problem) { $known[$u.Key] = [Math]::Round($u.Seconds, 1) } }
    try { [IO.File]::WriteAllText($timesPath, ($known | ConvertTo-Json)) } catch { }
    # Zusammenfassung je Testskript (Teile zusammengefasst: Dauer = längster Teil, dazu die Summe).
    $suites = @()
    foreach ($group in ($units | Group-Object Test | Sort-Object Name)) {
        $parts = @($group.Group)
        $problems = @($parts | Where-Object { $_.Problem } | ForEach-Object { if ($_.Part) { "Teil $($_.Part): $($_.Problem)" } else { $_.Problem } })
        $resultText = if ($parts.Count -eq 1) { $parts[0].Result } else {
            $ok = 0; foreach ($p in $parts) { if ($p.Result -match 'RESULT: (\d+) ok') { $ok += [int]$Matches[1] } }
            "RESULT: $ok ok ($($parts.Count) Teile, zusammen $([int]($parts | Measure-Object Seconds -Sum).Sum) s)" }
        $suites += [pscustomobject]@{ Name = $group.Name; Lane = $parts[0].Lane; Ok = ($problems.Count -eq 0); Problem = ($problems -join '; '); Result = $resultText
            Failures = @($parts | ForEach-Object { $_.Failures }); Seconds = [int]($parts | Measure-Object Seconds -Maximum).Maximum }
    }
    Write-Output ''
    Write-Output 'Zusammenfassung der Testläufe (P = parallel, S = nacheinander):'
    foreach ($suite in $suites) {
        $status = if ($suite.Ok) { 'OK     ' } else { 'FEHLER ' }
        $laneMark = if ($suite.Lane -eq 'parallel') { 'P' } else { 'S' }
        Write-Output ("  {0} {1} {2,-30} {3,5} s  {4}{5}" -f $status, $laneMark, $suite.Name, $suite.Seconds, $suite.Result, $(if ($suite.Problem) { "  [$($suite.Problem)]" } else { '' }))
        foreach ($line in ($suite.Failures | Select-Object -First 5)) { Write-Output ("            {0}" -f $line) }
    }
    Write-Output ("Testdauer: {0:N1} min (Summe aller Läufe {1:N1} min)" -f $total.Elapsed.TotalMinutes, ((($units | Measure-Object Seconds -Sum).Sum) / 60))
    $failedSuites = @($suites | Where-Object { -not $_.Ok })
    if ($failedSuites.Count -gt 0) { throw ("{0} von {1} Testläufen fehlgeschlagen: {2}" -f $failedSuites.Count, $suites.Count, (($failedSuites | ForEach-Object { $_.Name }) -join ', ')) }
    Write-Output ("Alle {0} Testläufe bestanden." -f $suites.Count)
}

if ($Target -ne 'Web' -and -not (Test-Path -LiteralPath $engine)) { throw 'Godot 4.6.1 fehlt. Zuerst tools/setup.ps1 ausführen.' }

# Version: project.godot ist maßgeblich; version/name und version/code im Android-Exportprofil werden daraus gesetzt.
$version = (Select-String -LiteralPath (Join-Path $gamePath 'project.godot') -Pattern '^config/version="(.+)"').Matches[0].Groups[1].Value
$versionCode = Get-VersionCode $version
$presetsPath = Join-Path $gamePath 'export_presets.cfg'
$presetText = [IO.File]::ReadAllText($presetsPath)
$codeLines = [regex]::Matches($presetText, '(?m)^version/code=(\d+)(\r?)$')
$nameLines = [regex]::Matches($presetText, '(?m)^version/name="([^"]*)"(\r?)$')
if ($codeLines.Count -ne 1 -or $nameLines.Count -ne 1) { throw "Exportprofil: genau eine Zeile version/code und version/name erwartet." }
$presetCode = [long]$codeLines[0].Groups[1].Value
if ($presetCode -gt $versionCode) {
    throw "version/code im Exportprofil ($presetCode) ist höher als der aus Version $version berechnete ($versionCode). Ein Update muss immer höher nummeriert sein – die Version anheben statt den Code zu senken."
}
if ($presetCode -ne $versionCode -or $nameLines[0].Groups[1].Value -ne $version) {
    # Von hinten ersetzen, damit die Fundstellen gültig bleiben.
    $edits = @(
        @{ Index = $codeLines[0].Index; Length = $codeLines[0].Length; Text = "version/code=$versionCode$($codeLines[0].Groups[2].Value)" },
        @{ Index = $nameLines[0].Index; Length = $nameLines[0].Length; Text = "version/name=`"$version`"$($nameLines[0].Groups[2].Value)" }
    ) | Sort-Object { $_.Index } -Descending
    foreach ($e in $edits) { $presetText = $presetText.Remove($e.Index, $e.Length).Insert($e.Index, $e.Text) }
    [IO.File]::WriteAllText($presetsPath, $presetText)
    Write-Output "Exportprofil: version/name $version, version/code $versionCode (vorher $presetCode)"
}

# Vorabprüfung für Android, bevor Import und Tests Minuten kosten.
if ($Target -in @('All', 'Android')) {
    $propsPath = Join-Path $projectRoot '.tools/maumauflip-release.properties'
    $keystore = Join-Path $projectRoot '.tools/maumauflip-release.keystore'
    if (-not (Test-Path -LiteralPath $keystore) -or -not (Test-Path -LiteralPath $propsPath)) {
        throw ("Release-Schlüssel fehlt: $keystore bzw. $propsPath`n" +
            "Ohne ihn wäre die APK mit einem anderen Schlüssel signiert, und Updates scheiterten auf jedem Handy mit 'Signatur passt nicht'.`n" +
            "Die Dateien aus der Sicherung zurückkopieren. Nicht neu erzeugen: Mit einem neuen Schlüssel müsste Mau-Mau Flip auf jedem Handy " +
            "deinstalliert und neu installiert werden.")
    }
    $keyProps = Read-KeyProperties $propsPath
    $keyAlias = $keyProps['alias']
    $keyPassword = $keyProps['password']
    if (-not $keyAlias -or -not $keyPassword) { throw "${propsPath}: alias und password erwartet." }
    $apksigner = Find-SdkTool 'apksigner.bat'
    $aapt = Find-SdkTool 'aapt.exe'
    $keytool = Find-Keytool
    if (-not $apksigner) { throw 'apksigner (Android-SDK, build-tools) nicht gefunden – ohne ihn lässt sich die Signatur der APK nicht prüfen.' }
    if (-not $keytool) { throw 'keytool (JDK 17) nicht gefunden.' }
    # Passt der Schlüssel zum festgeschriebenen Zertifikat? (Passwort nur über eine Umgebungsvariable, nie auf der Befehlszeile.)
    $env:MMF_STOREPASS = $keyPassword
    try { $listing = Invoke-Native $keytool @('-list', '-v', '-keystore', $keystore, '-alias', $keyAlias, '-storepass:env', 'MMF_STOREPASS') }
    finally { Remove-Item Env:MMF_STOREPASS -ErrorAction SilentlyContinue }
    $keyLine = $listing | Where-Object { $_ -match 'SHA256:\s*([0-9A-Fa-f:]{95})' } | Select-Object -First 1
    if ($script:NativeExit -ne 0 -or -not $keyLine) { throw "keytool konnte den Schlüssel nicht lesen (Alias/Passwort in $propsPath prüfen)." }
    $keySha = ([regex]::Match($keyLine, 'SHA256:\s*([0-9A-Fa-f:]{95})').Groups[1].Value -replace ':', '').ToLower()
    if ($keySha -ne $projectCertSha256) { throw "Der Schlüssel in $keystore ist nicht der Projektschlüssel (SHA-256 $keySha statt $projectCertSha256)." }
    Write-Output "Release-Schlüssel geprüft (Alias $keyAlias, SHA-256 $($projectCertSha256.Substring(0, 16))...)"
}

if ($Target -ne 'Windows' -or (Test-Path -LiteralPath (Join-Path $projectRoot 'webclient/index.html'))) { Build-WebZip }
if ($Target -eq 'Web') { return }

# Testergebnis-Cache (.tools/test_cache.json): Prüfsummen der zuletzt vollständig grün getesteten Stände.
$cachePath = Join-Path $projectRoot '.tools/test_cache.json'
$testsCached = $false
$stateHash = $null
if (-not $SkipTests) {
    $cacheWatch = [Diagnostics.Stopwatch]::StartNew()
    $stateHash = Get-TestStateHash
    $cache = Read-JsonFile $cachePath
    $greens = @(if ($cache -and $cache.green) { $cache.green })
    if (-not $stateHash) { Write-Output 'Testergebnis-Cache: git nicht gefunden – Tests laufen immer.' }
    elseif ($NoTestCache) { Write-Output "Testergebnis-Cache abgeschaltet (-NoTestCache), Stand $($stateHash.Substring(0, 12))." }
    elseif ($greens -contains $stateHash) {
        $testsCached = $true
        Write-Output ("Tests für diesen Stand schon grün, übersprungen (Prüfsumme {0}, {1:N1} s; -NoTestCache erzwingt sie)." -f $stateHash.Substring(0, 12), $cacheWatch.Elapsed.TotalSeconds)
    }
    else { Write-Output "Testergebnis-Cache: Stand $($stateHash.Substring(0, 12)) noch nicht grün getestet – Tests laufen." }
}
if ($Target -eq 'Test' -and $testsCached) { return }

$lock = New-Object System.Threading.Mutex($false, 'Global\MauMauFlipGodot')
$held = $false
try {
    try { $held = $lock.WaitOne([TimeSpan]::FromMinutes($LockWaitMinutes)) }
    catch [System.Threading.AbandonedMutexException] { $held = $true }    # Vorbesitzer abgestürzt: die Sperre gilt als erworben
    if (-not $held) { throw "Godot-Sperre (Global\MauMauFlipGodot) nach $LockWaitMinutes min nicht frei" }
    $env:MMF_GODOT_LOCK_OWNER = "$PID"    # eigene Kindprozesse (godot_run/godot_import) sperren nicht erneut
    Invoke-Godot -Arguments @('--headless', '--path', $gamePath, '--editor', '--import', '--quit')
    if ($SkipTests) { Write-Output 'Tests übersprungen (-SkipTests).' }
    elseif ($testsCached) { Write-Output 'Tests für diesen Stand schon grün, übersprungen (Baubeleg: tests true, tests_cached true).' }
    else {
        # Getesteter Stand: nach dem Import (der legt z. B. .uid-Dateien neuer Skripte an).
        if ($stateHash) { $stateHash = Get-TestStateHash }
        Invoke-Tests
        # Nur merken, wenn sich während der Tests nichts geändert hat (sonst wäre ein Mischstand getestet).
        if ($stateHash) {
            $after = Get-TestStateHash
            if ($after -eq $stateHash) {
                $cache = Read-JsonFile $cachePath
                $older = @(if ($cache -and $cache.green) { $cache.green })
                $greens = @(@($stateHash) + @($older | Where-Object { $_ -ne $stateHash }) | Select-Object -First 20)
                [IO.File]::WriteAllText($cachePath, ([ordered]@{ green = $greens; last = $stateHash; version = $version; time = (Get-Date).ToString('s') } | ConvertTo-Json))
                Write-Output "Testergebnis-Cache: Stand $($stateHash.Substring(0, 12)) als grün gemerkt."
            }
            else { Write-Output 'Testergebnis-Cache: Dateien haben sich während der Tests geändert – Stand nicht gemerkt.' }
        }
    }
    if ($Target -eq 'Test') { return }
    New-Item -ItemType Directory -Force $buildsDir | Out-Null
    if ($Target -in @('All', 'Windows')) {
        Invoke-Godot -Arguments @('--headless', '--path', $gamePath, '--export-release', 'Windows', (Join-Path $buildsDir 'MauMauFlip.exe'))
        Write-Output "Windows: builds/MauMauFlip.exe"
    }
    if ($Target -in @('All', 'Android')) {
        # Godot-Bibliotheken (je ~100 MB) nicht im Repo: bei Bedarf aus der Exportvorlage nachziehen (tools/setup.ps1 legt sie ab).
        $buildDir = Join-Path $gamePath 'android/build'
        if (-not (Test-Path -LiteralPath (Join-Path $buildDir 'libs/release/godot-lib.template_release.aar'))) {
            $sourceZip = Join-Path $projectRoot '.tools/export/templates/android_source.zip'
            if (-not (Test-Path -LiteralPath $sourceZip)) { throw 'android_source.zip fehlt – zuerst tools/setup.ps1 ausführen.' }
            $zip = [IO.Compression.ZipFile]::OpenRead($sourceZip)
            try {
                foreach ($entry in ($zip.Entries | Where-Object { $_.FullName.StartsWith('libs/') -and -not $_.FullName.EndsWith('/') })) {
                    $dest = Join-Path $buildDir $entry.FullName
                    New-Item -ItemType Directory -Force (Split-Path $dest -Parent) | Out-Null
                    [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $dest, $true)
                }
            }
            finally { $zip.Dispose() }
        }
        $apk = Join-Path $buildsDir 'MauMauFlip.apk'
        if (Test-Path -LiteralPath $apk) { Remove-Item -LiteralPath $apk -Force }
        # Release-Export mit dem Projektschlüssel (Vorabprüfung oben); Godot liest Pfad, Alias und Passwort aus diesen Variablen.
        $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH = $keystore
        $env:GODOT_ANDROID_KEYSTORE_RELEASE_USER = $keyAlias
        $env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD = $keyPassword
        try { Invoke-Godot -Arguments @('--headless', '--path', $gamePath, '--export-release', 'Android', $apk) }
        finally {
            Remove-Item Env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH, Env:GODOT_ANDROID_KEYSTORE_RELEASE_USER, Env:GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD -ErrorAction SilentlyContinue
        }
        if (-not (Test-Path -LiteralPath $apk)) { throw 'Android-Export lieferte keine APK.' }
        # Signatur nachprüfen: genau ein Unterzeichner, und zwar der Projektschlüssel. Erst dann entsteht die Release-Datei.
        $certs = Invoke-Native $apksigner @('verify', '--print-certs', $apk)
        if ($script:NativeExit -ne 0) { throw ("apksigner: Signatur der APK ungültig.`n" + ($certs -join "`n")) }
        $signers = @($certs | Where-Object { $_ -match 'certificate SHA-256 digest: ([0-9a-f]{64})' } | ForEach-Object { ($_ -split ': ')[-1].Trim() })
        if ($signers.Count -ne 1 -or $signers[0] -ne $projectCertSha256) {
            throw ("APK ist nicht mit dem Projektschlüssel signiert (gefunden: $($signers -join ', ')). Updates würden auf den Handys " +
                "mit 'Signatur passt nicht' scheitern. builds/MauMauFlip-$version.apk wurde nicht angelegt.")
        }
        # Paket und Version in der APK (aapt dump badging): package: name='…' versionCode='…' versionName='…'
        if ($aapt) {
            $badging = Invoke-Native $aapt @('dump', 'badging', $apk)
            $pkgLine = $badging | Where-Object { $_ -match "^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'" } | Select-Object -First 1
            if (-not $pkgLine) { throw 'aapt: Paketangaben der APK nicht lesbar.' }
            $m = [regex]::Match($pkgLine, "^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'")
            if ($m.Groups[1].Value -ne $packageName -or [long]$m.Groups[2].Value -ne $versionCode -or $m.Groups[3].Value -ne $version) {
                throw "APK-Angaben passen nicht: $pkgLine (erwartet $packageName, $versionCode, $version)"
            }
            $debuggable = @($badging | Where-Object { $_ -match "application-debuggable" }).Count -gt 0
            if ($debuggable) { throw 'APK ist als debuggable markiert – erwartet war ein Release-Export.' }
        }
        else { Write-Output 'Hinweis: aapt nicht gefunden – Paket und Version der APK ungeprüft.' }
        Write-Output "APK-Signatur: Projektschlüssel (SHA-256 $($projectCertSha256.Substring(0, 16))...), $packageName $version, version/code $versionCode"
        # Release-Datei für GitHub: Die Update-Funktion erwartet genau "MauMauFlip-<version>.apk" (version = config/version).
        $versioned = Join-Path $buildsDir "MauMauFlip-$version.apk"
        Copy-Item -LiteralPath $apk -Destination $versioned -Force
        $hash = (Get-FileHash -LiteralPath $versioned -Algorithm SHA256).Hash.ToLower()
        Write-Output ("Android: builds/MauMauFlip-{0}.apk ({1:N1} MB, SHA-256 {2})" -f $version, ((Get-Item -LiteralPath $versioned).Length / 1MB), $hash)
        # Baubeleg für tools/release.ps1: zu genau dieser APK, mit oder ohne Tests entstanden.
        $stamp = [ordered]@{ version = $version; code = $versionCode; sha256 = $hash; size = (Get-Item -LiteralPath $versioned).Length; tests = (-not $SkipTests); tests_cached = $testsCached; time =(Get-Date).ToString('s') }
        [IO.File]::WriteAllText((Join-Path $buildsDir "MauMauFlip-$version.build.json"), ($stamp | ConvertTo-Json))
    }
}
finally {
    Remove-Item Env:MMF_GODOT_LOCK_OWNER -ErrorAction SilentlyContinue
    if ($held) { $lock.ReleaseMutex() }
    $lock.Dispose()
}
