[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][ValidateSet('beta', 'release')][string]$Channel,
    [switch]$SkipBuild    # vorhandenen Bau nehmen; er muss dann mit Tests entstanden sein (Baubeleg builds/MauMauFlip-<version>.build.json)
)
# Veröffentlicht die gebaute APK als GitHub-Release (docs/BETA1_PLAN.md 9, AGENTS.md 3):
#   beta     → ShakieVan/Mau-Mau-Flip-Beta, Tag vX.Y.Z, Titel „Mau-Mau Flip X.Y.Z (Beta)“, als Vorabversion (--prerelease)
#   release  → ShakieVan/Mau-Mau-Flip,      Tag vX.Y.Z, Titel „Mau-Mau Flip X.Y.Z“
# Notizen aus docs/release_notes/X.Y.Z.md, einziges Asset MauMauFlip-X.Y.Z.apk (diesen Namen erwartet der Updater).
# Vorher: Bau mit Tests (tools/build.ps1 -Target Android), Versionsschema (Beta: Z ≠ 0, Release: Z = 0), Signatur (Projektschlüssel),
# Paket/Version der APK, Notizen vorhanden, Tag noch frei. Im leeren Beta-Repo werden zuerst README.md und LICENSE angelegt.
# Danach: GitHub-Angaben des Assets (Name, Größe, SHA-256-Digest, URL) so, wie der Updater sie verlangt.
# Trockenlauf:  tools/release.ps1 -Channel beta -WhatIf   (prüft alles, ändert nichts, baut nicht)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$gamePath = Join-Path $projectRoot 'game'
$buildsDir = Join-Path $projectRoot 'builds'
$projectCertSha256 = '85d6f9d94693e675a71ef5348c3e212b5962f793dd1ab1cdf1c86a0dfc8d15cd'   # wie tools/build.ps1
$packageName = 'de.maumauflip.game'
$repo = if ($Channel -eq 'beta') { 'ShakieVan/Mau-Mau-Flip-Beta' } else { 'ShakieVan/Mau-Mau-Flip' }
$dryRun = [bool]$WhatIfPreference
$problems = New-Object System.Collections.Generic.List[string]

function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    # Externes Werkzeug; Ausgabe als Zeilen, stderr bricht nicht ab. Exitcode in $script:NativeExit.
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = @(& $Exe @Arguments 2>&1 | ForEach-Object { "$_" }) }
    finally { $ErrorActionPreference = $previousPreference }
    $script:NativeExit = $LASTEXITCODE
    return $out
}

function Find-SdkTool([string]$Name) {
    $roots = @()
    foreach ($file in (Get-ChildItem -LiteralPath (Join-Path $env:APPDATA 'Godot') -Filter 'editor_settings-4*.tres' -ErrorAction SilentlyContinue)) {
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

function Step([string]$Text) { Write-Output "== $Text" }

# 1. Werkzeuge und Version
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'GitHub CLI (gh) fehlt.' }
$auth = Invoke-Native 'gh' @('auth', 'status')
if ($script:NativeExit -ne 0) { throw "gh ist nicht angemeldet:`n$($auth -join "`n")" }
$version = (Select-String -LiteralPath (Join-Path $gamePath 'project.godot') -Pattern '^config/version="(.+)"').Matches[0].Groups[1].Value
if ($version -notmatch '^(\d{1,4})\.(\d{1,3})\.(\d{1,3})$') { throw "Version '$version' passt nicht zum Schema X.Y.Z." }
$versionCode = [long]$Matches[1] * 1000000 + [long]$Matches[2] * 1000 + [long]$Matches[3]
$patch = [int]$Matches[3]
$tag = "v$version"
$assetName = "MauMauFlip-$version.apk"
$apk = Join-Path $buildsDir $assetName
$title = if ($Channel -eq 'beta') { "Mau-Mau Flip $version (Beta)" } else { "Mau-Mau Flip $version" }
Step "Mau-Mau Flip $version ($Channel) → $repo, Tag $tag$(if ($dryRun) { ' – TROCKENLAUF' })"
# Nummernschema (wie Draw2Race): Releases X.Y.0, Betas X.Y.Z mit Z ≠ 0 – danach richtet sich auch der Beta-Kanal der App.
if ($Channel -eq 'beta' -and $patch -eq 0) { $problems.Add("Beta-Versionen enden nicht auf .0 ($version) – sonst schaltet die App den Beta-Kanal ab.") }
if ($Channel -eq 'release' -and $patch -ne 0) { $problems.Add("Reguläre Releases enden auf .0 ($version).") }

# 2. Notizen
$notes = Join-Path $projectRoot "docs/release_notes/$version.md"
if (-not (Test-Path -LiteralPath $notes) -or (Get-Content -LiteralPath $notes -Raw -ErrorAction SilentlyContinue).Trim() -eq '') {
    $problems.Add("Release-Notizen fehlen oder sind leer: docs/release_notes/$version.md")
}

# 3. Ziel-Repo: vorhanden, Tag noch frei
$repoInfo = Invoke-Native 'gh' @('api', "repos/$repo", '--jq', '.full_name')
if ($script:NativeExit -ne 0) { throw "Repo $repo nicht erreichbar: $($repoInfo -join ' ')" }
$existing = Invoke-Native 'gh' @('api', "repos/$repo/releases/tags/$tag", '--jq', '.html_url')
if ($script:NativeExit -eq 0) { $problems.Add("Release $tag gibt es in $repo schon: $($existing -join ' ')") }
$contents = Invoke-Native 'gh' @('api', "repos/$repo/contents", '--jq', '.[].name')
$repoEmpty = $script:NativeExit -ne 0 -and ($contents -join ' ') -match 'empty'
if ($Channel -eq 'release' -and $repoEmpty) { $problems.Add("$repo ist leer – zuerst den Quellcode hochladen (git push), dann das Release anlegen.") }
Step ("Ziel-Repo: {0}" -f $(if ($repoEmpty -and $Channel -eq 'beta') { 'leer (README.md und LICENSE werden angelegt)' } elseif ($repoEmpty) { 'leer' } else { 'Inhalt: ' + ($contents -join ', ') }))

# 4. Bau mit Tests
if ($problems.Count -eq 0 -and -not $SkipBuild) {
    if ($PSCmdlet.ShouldProcess('tools/build.ps1 -Target Android', 'Bau samt Tests')) {
        & (Join-Path $PSScriptRoot 'build.ps1') -Target Android
    }
}
elseif ($problems.Count -gt 0 -and -not $SkipBuild) { Step 'Bau übersprungen (erst die Probleme unten beheben)' }

# 5. Baubeleg, Signatur, Paket und Version der APK
if (-not (Test-Path -LiteralPath $apk)) { $problems.Add("APK fehlt: builds/$assetName (tools/build.ps1 -Target Android)") }
else {
    # Get-FileHash liefert unter Windows PowerShell 5.1 im Trockenlauf (-WhatIf) nichts, deshalb hier ohne WhatIf
    $previousWhatIf = $WhatIfPreference
    $WhatIfPreference = $false
    try { $sha = (Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash.ToLower() }
    finally { $WhatIfPreference = $previousWhatIf }
    $size = (Get-Item -LiteralPath $apk).Length
    $stampPath = Join-Path $buildsDir "MauMauFlip-$version.build.json"
    $stamp = if (Test-Path -LiteralPath $stampPath) { Get-Content -LiteralPath $stampPath -Raw | ConvertFrom-Json } else { $null }
    if ($null -eq $stamp -or $stamp.sha256 -ne $sha) { $problems.Add("Kein Baubeleg zu dieser APK ($stampPath) – mit tools/build.ps1 -Target Android neu bauen.") }
    elseif (-not $stamp.tests) { $problems.Add('Die APK entstand ohne Tests (-SkipTests) – mit Tests neu bauen.') }
    $apksigner = Find-SdkTool 'apksigner.bat'
    if (-not $apksigner) { $problems.Add('apksigner nicht gefunden.') }
    else {
        $certs = Invoke-Native $apksigner @('verify', '--print-certs', $apk)
        $signers = @($certs | Where-Object { $_ -match 'certificate SHA-256 digest: ([0-9a-f]{64})' } | ForEach-Object { ($_ -split ': ')[-1].Trim() })
        if ($script:NativeExit -ne 0 -or $signers.Count -ne 1 -or $signers[0] -ne $projectCertSha256) { $problems.Add("Signatur: nicht der Projektschlüssel (gefunden: $($signers -join ', '))") }
        else { Step "Signatur: Projektschlüssel ($($projectCertSha256.Substring(0, 16))...)" }
    }
    $aapt = Find-SdkTool 'aapt.exe'
    if ($aapt) {
        $badging = Invoke-Native $aapt @('dump', 'badging', $apk)
        $m = [regex]::Match((($badging | Where-Object { $_ -like 'package:*' }) | Select-Object -First 1), "^package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'")
        if (-not $m.Success -or $m.Groups[1].Value -ne $packageName -or [long]$m.Groups[2].Value -ne $versionCode -or $m.Groups[3].Value -ne $version) {
            $problems.Add("APK-Angaben passen nicht (erwartet $packageName $versionCode $version): $($m.Value)")
        }
        else { Step "APK: $packageName $version (Code $versionCode), $([math]::Round($size / 1MB, 1)) MB, SHA-256 $sha" }
    }
}

if ($problems.Count -gt 0) {
    Write-Output ''
    Write-Output 'Nicht veröffentlicht – Probleme:'
    $problems | ForEach-Object { Write-Output "  - $_" }
    throw "$($problems.Count) Problem(e), siehe oben."
}

# 6. Leeres Beta-Repo: README.md und LICENSE wie bei Draw2Race-Beta (erste Commits, nötig für den Tag).
if ($repoEmpty -and $Channel -eq 'beta') {
    $readme = @"
# Mau-Mau Flip – Testversionen (Beta)

Hier liegen **Vorabversionen zum Testen**. Sie können unfertig sein und Fehler enthalten.

**Die regulären Versionen gibt es hier:** https://github.com/ShakieVan/Mau-Mau-Flip/releases

Installation auf Android: die Datei ``MauMauFlip-X.Y.Z.apk`` aus dem neuesten Release auf dem Handy öffnen und die Installation erlauben.
Danach kommen Updates über die App (Menü *Update*). Testversionen erhält man mit dem Schalter *Beta-Kanal* in den Einstellungen;
eine installierte Testversion hat ihn schon eingeschaltet.

Lizenz wie Mau-Mau Flip: CC BY-NC 4.0 (siehe ``LICENSE``).
"@
    $files = [ordered]@{ 'README.md' = $readme; 'LICENSE' = [IO.File]::ReadAllText((Join-Path $projectRoot 'LICENSE')) }
    foreach ($name in $files.Keys) {
        if ($PSCmdlet.ShouldProcess("$repo/$name", 'Datei anlegen')) {
            $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($files[$name] -replace "`r`n", "`n")))
            $out = Invoke-Native 'gh' @('api', '-X', 'PUT', "repos/$repo/contents/$name", '-f', "message=$name", '-f', "content=$b64", '--jq', '.commit.sha')
            if ($script:NativeExit -ne 0) { throw "Anlegen von $name in $repo fehlgeschlagen: $($out -join ' ')" }
            Step "$name angelegt (Commit $($out -join ''))"
        }
    }
}

# 7. Release anlegen
$create = @('release', 'create', $tag, $apk, '-R', $repo, '--title', $title, '--notes-file', $notes)
if ($Channel -eq 'beta') { $create += '--prerelease' } else { $create += '--latest' }
if ($PSCmdlet.ShouldProcess("$repo $tag", "gh $($create -join ' ')")) {
    $out = Invoke-Native 'gh' $create
    if ($script:NativeExit -ne 0) { throw "gh release create fehlgeschlagen: $($out -join "`n")" }
    Step "Release angelegt: $($out -join ' ')"
    # 8. Nachprüfung wie der Updater: genau ein Asset mit diesem Namen, Größe, SHA-256-Digest, exakte Download-Adresse.
    $json = (Invoke-Native 'gh' @('api', "repos/$repo/releases/tags/$tag")) -join "`n"
    $rel = $json | ConvertFrom-Json
    $asset = @($rel.assets | Where-Object { $_.name -eq $assetName })
    $url = "https://github.com/$repo/releases/download/$tag/$assetName"
    $ok = $asset.Count -eq 1 -and $asset[0].size -eq $size -and $asset[0].digest -eq "sha256:$sha" -and $asset[0].browser_download_url -eq $url `
        -and $rel.draft -eq $false -and $rel.prerelease -eq ($Channel -eq 'beta')
    if (-not $ok) { throw "Release angelegt, aber die Angaben passen nicht zum Updater: $($asset | ConvertTo-Json -Compress)" }
    Step "Nachprüfung: Asset $assetName, $size Bytes, Digest passt, $url"
}
