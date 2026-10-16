# Mau-Mau Flip (Beta 1.6.11, „Natur-Überraschungen“, docs/module/natur.md 8.4): Kontrollbilder des Browser-Clients „Lite“ mit dem
# Schein-Gastgeber (mock.js), Chrome headless über tools/webtest/cdp.ps1 → docs/module/optik_<Stand>_lite_natur_<id>[_<zusatz>].png.
# Jedes Ereignis wird ohne Bedingungen über MMF.Natur.zeige(id, {seed, anteil, stehen: true}) gestartet und eingefroren (Zeitpunkt =
# anteil × Dauer; Standard 0,45 = Hauptphase). Nachttiere auf der Nachtseite (&seite=dunkel). Regenbogen, Polarlicht und UFO zusätzlich
# im Desktop-Fenster 1280×800 (_desktop). Die Ereignisse stehen in webclient/natur.js (Tabelle), die Arten in natur_tag.js /
# natur_nacht.js; fehlt eine Art, meldet die Zeile „gezeigt: “ leer (das Bild zeigt dann nur den Tisch).
# Aufruf: powershell -NoProfile -File tools\webtest\natur_bilder.ps1 [-Nur marienkaefer,eule] [-Stand 1611] [-Anteil 0.45]
#         [-Zeiten 0.1,0.45,0.95] (mehrere Zeitpunkte: Zusatz _t10, _t45, …) [-Ruhig] (Effekte reduziert, nur ruhige; Zusatz _ruhig)
#         [-Gegner 3] [-Seed 7] [-Breite 844 -Hoehe 390] [-OhneDesktop] [-Ziel Ordner] (Standard docs\module)
param([string]$Nur = '', [string]$Stand = '1611', [double]$Anteil = 0.45, [string]$Zeiten = '', [switch]$Ruhig, [int]$Gegner = 3,
    [int]$Seed = 7, [int]$Breite = 844, [int]$Hoehe = 390, [switch]$OhneDesktop, [string]$Ziel = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$cdp = Join-Path $PSScriptRoot 'cdp.ps1'
$out = if ($Ziel) { $Ziel } else { Join-Path $root 'docs\module' }
$seite = ([Uri](Join-Path $root 'webclient\index.html')).AbsoluteUri
# Tabelle aus natur.js (reines JSON zwischen den Markern)
$js = [IO.File]::ReadAllText((Join-Path $root 'webclient\natur.js'))
$a = $js.IndexOf('/*NATUR-DATEN*/'); $b = $js.IndexOf('/*ENDE*/')
if ($a -lt 0 -or $b -lt $a) { throw 'natur.js: Tabelle zwischen /*NATUR-DATEN*/ und /*ENDE*/ fehlt' }
$daten = $js.Substring($a + 15, $b - $a - 15) | ConvertFrom-Json
$auswahl = @($Nur.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$anteile = @(if ($Zeiten) { $Zeiten.Split(',') | ForEach-Object { [double]::Parse($_.Trim(), [Globalization.CultureInfo]::InvariantCulture) } } else { $Anteil })
$desktopIds = @('regenbogen', 'polarlicht', 'ufo')
$warte = "!!(window.MMF && MMF.Natur && MMF.App && MMF.App.tisch && MMF.App.tisch.v && document.querySelector('#natur-mitte'))"
$inv = [Globalization.CultureInfo]::InvariantCulture
foreach ($e in $daten.ereignisse) {
    $id = $e.id
    if ($auswahl.Count -and $auswahl -notcontains $id) { continue }
    if ($Ruhig -and -not $e.ruhig) { continue }
    $q = "?mock=1&szene=tisch&halt=1&gegner=$Gegner&name=Kim&dran=1"
    if ($e.seite -eq 'nacht') { $q += '&seite=dunkel' }
    $formate = @(@{ w = $Breite; h = $Hoehe; zusatz = '' })
    if (-not $OhneDesktop -and $desktopIds -contains $id) { $formate += @{ w = 1280; h = 800; zusatz = '_desktop' } }
    foreach ($f in $formate) {
        foreach ($an in $anteile) {
            $zusatz = $f.zusatz
            if ($anteile.Count -gt 1) { $zusatz += '_t' + [Math]::Round($an * 100) }
            if ($Ruhig) { $zusatz += '_ruhig' }
            $reduziert = if ($Ruhig) { "MMF.App.einstellungen.effekte='reduziert';document.body.classList.add('reduziert');" } else { '' }
            $pre = "setTimeout(()=>{try{${reduziert}MMF.Natur.zeige('$id',{seed:$Seed,anteil:$($an.ToString($inv)),stehen:true})}catch(e){console.error(e)}},700);"
            $datei = Join-Path $out "optik_$($Stand)_lite_natur_$id$zusatz.png"
            & $cdp -Url ($seite + $q) -Out $datei -Width $f.w -Height $f.h -Scale 2 -Mobile -WaitExpr $warte -Pre $pre -WaitMs 1200 -TimeoutMs 30000 `
                -Eval "JSON.stringify({gezeigt: MMF.Natur.current ? MMF.Natur.current.id : '', t: MMF.Natur.current ? +MMF.Natur.current.t.toFixed(2) : 0, fehler: MMF.App.fehler})"
        }
    }
}
