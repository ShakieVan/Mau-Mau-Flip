param(
    [string]$TemplatesArchive = '',   # vorhandenes Exportvorlagen-Archiv (.tpz/.zip) statt Download, z. B. aus einem Nachbarprojekt
    [switch]$ReinstallAndroidTemplate # Gradle-Vorlage neu entpacken (nach einem Godot-Update); eigene Dateien bleiben erhalten
)
# Richtet die Werkzeuge ein (Muster Draw2Race tools/setup.ps1):
#   1. Godot 4.6.1 nach .tools/
#   2. Exportvorlagen: benötigte Dateien nach .tools/export/templates/ (android_source.zip bleibt dort) und, falls dort noch nicht
#      vorhanden, nach %APPDATA%\Godot\export_templates\4.6.1.stable (Godot sucht die Vorlagen dort)
#   3. Android-Gradle-Vorlage in game/android/ wie Godots „Android-Build-Vorlage installieren“: android/.build_version,
#      android/build/.gdignore und der Inhalt von android_source.zip. Die eigenen Dateien (Java-Helfer, Manifest, gradle.properties)
#      liegen in git; vorhandene Dateien überschreibt nur -ReinstallAndroidTemplate, und auch dann nicht die eigenen.
#   4. Fehlende Godot-Bibliotheken (libs/*.aar, je ~100 MB, nicht in git) aus android_source.zip nachziehen.
# Android braucht außerdem JDK 17 und ein Android-SDK (Godot-Editoreinstellungen export/android/java_sdk_path, android_sdk_path).
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$projectRoot = Split-Path $PSScriptRoot -Parent
$toolDir = Join-Path $projectRoot '.tools'
$version = '4.6.1'
$base = "https://github.com/godotengine/godot-builds/releases/download/$version-stable"
New-Item -ItemType Directory -Force $toolDir | Out-Null

# 1. Godot
if (-not (Test-Path -LiteralPath (Join-Path $toolDir "Godot_v$version-stable_win64_console.exe"))) {
    $archive = Join-Path $toolDir 'godot.zip'
    Invoke-WebRequest "$base/Godot_v$version-stable_win64.exe.zip" -OutFile $archive
    Expand-Archive -LiteralPath $archive -DestinationPath $toolDir -Force
    Remove-Item -LiteralPath $archive -Force
}

# 2. Exportvorlagen (nur die gebrauchten Dateien; das ganze Archiv hat 1,2 GB)
$needed = @('version.txt', 'android_source.zip', 'android_debug.apk', 'android_release.apk',
    'windows_release_x86_64.exe', 'windows_release_x86_64_console.exe', 'windows_debug_x86_64.exe', 'windows_debug_x86_64_console.exe',
    'web_nothreads_release.zip', 'web_nothreads_debug.zip')
$localTemplates = Join-Path $toolDir 'export/templates'
$appTemplates = Join-Path $env:APPDATA "Godot/export_templates/$version.stable"
$missing = @($needed | Where-Object { -not (Test-Path -LiteralPath (Join-Path $localTemplates $_)) })
if ($missing.Count -gt 0) {
    $archive = $TemplatesArchive
    if ($archive -eq '') {
        $archive = Join-Path $toolDir 'templates.zip'
        if (-not (Test-Path -LiteralPath $archive)) {
            Write-Output 'Lade die Exportvorlagen (rund 1,2 GB) …'
            Invoke-WebRequest "$base/Godot_v$version-stable_export_templates.tpz" -OutFile $archive
        }
    }
    if (-not (Test-Path -LiteralPath $archive)) { throw "Vorlagenarchiv fehlt: $archive" }
    New-Item -ItemType Directory -Force $localTemplates | Out-Null
    $zip = [IO.Compression.ZipFile]::OpenRead($archive)
    try {
        foreach ($name in $missing) {
            $entry = $zip.GetEntry("templates/$name")
            if ($null -eq $entry) { throw "Vorlagenarchiv ohne templates/$name – falsche Godot-Version?" }
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, (Join-Path $localTemplates $name), $true)
        }
    }
    finally { $zip.Dispose() }
    $found = (Get-Content -LiteralPath (Join-Path $localTemplates 'version.txt') -Raw).Trim()
    if ($found -ne "$version.stable") { throw "Vorlagen passen nicht: $found statt $version.stable" }
}
New-Item -ItemType Directory -Force $appTemplates | Out-Null
foreach ($name in $needed) {
    # Godots Vorlagenordner wird mit anderen Projekten geteilt: nur Fehlendes ergänzen, nie überschreiben.
    $target = Join-Path $appTemplates $name
    if ($name -ne 'android_source.zip' -and -not (Test-Path -LiteralPath $target)) {
        Copy-Item -LiteralPath (Join-Path $localTemplates $name) -Destination $target
    }
}

# 3./4. Android-Gradle-Vorlage
$androidDir = Join-Path $projectRoot 'game/android'
$buildDir = Join-Path $androidDir 'build'
$sourceZip = Join-Path $localTemplates 'android_source.zip'
# Eigene, versionierte Dateien: nie mit der Vorlage überschreiben.
$own = @('src/main/AndroidManifest.xml', 'gradle.properties') + @(Get-ChildItem -LiteralPath (Join-Path $buildDir 'src/main/java/com/godot/game') -Filter '*.java' -ErrorAction SilentlyContinue |
    ForEach-Object { "src/main/java/com/godot/game/$($_.Name)" })
$fresh = -not (Test-Path -LiteralPath (Join-Path $buildDir 'build.gradle'))
New-Item -ItemType Directory -Force $buildDir | Out-Null
$zip = [IO.Compression.ZipFile]::OpenRead($sourceZip)
try {
    foreach ($entry in $zip.Entries) {
        if ($entry.FullName.EndsWith('/')) { continue }
        $target = Join-Path $buildDir $entry.FullName
        $isLib = $entry.FullName.StartsWith('libs/')
        $exists = Test-Path -LiteralPath $target
        if ($exists -and (-not $ReinstallAndroidTemplate -or ($own -contains $entry.FullName))) { continue }
        if (-not $fresh -and -not $isLib -and -not $ReinstallAndroidTemplate -and -not $exists) {
            # Vorlage schon installiert (aus git): nur die Bibliotheken fehlen typischerweise; andere Lücken melden statt still füllen.
            Write-Output "Hinweis: Vorlagendatei fehlt im Projekt und wird ergänzt: $($entry.FullName)"
        }
        New-Item -ItemType Directory -Force (Split-Path $target -Parent) | Out-Null
        [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $true)
    }
}
finally { $zip.Dispose() }
# Wie Godot: Versionsmarke (der Export bricht ab, wenn sie nicht zur Engine passt) und .gdignore (Godot durchsucht den Ordner nicht).
[IO.File]::WriteAllText((Join-Path $androidDir '.build_version'), "$version.stable`n")
if (-not (Test-Path -LiteralPath (Join-Path $buildDir '.gdignore'))) { [IO.File]::WriteAllText((Join-Path $buildDir '.gdignore'), "`n") }
# Kein Gradle-Hintergrunddienst: Er hielt in Draw2Race die Ausgabe offen, der Godot-Export kehrte nie zurück.
$props = Join-Path $buildDir 'gradle.properties'
if (-not (Select-String -LiteralPath $props -Pattern '^org\.gradle\.daemon=false' -Quiet)) {
    Add-Content -LiteralPath $props -Value "`n# Mau-Mau Flip: kein Gradle-Hintergrunddienst – er hielt die Ausgabe offen, der Godot-Export kehrte nie zurück.`norg.gradle.daemon=false" -Encoding UTF8
}
Write-Output 'Godot ist bereit (Godot 4.6.1, Exportvorlagen, Android-Gradle-Vorlage).'
Write-Output 'Android benötigt JDK 17 und ein Android-SDK; Pfade bei Bedarf in den Godot-Editoreinstellungen setzen.'
