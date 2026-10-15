# Mau-Mau Flip (Beta 1.6.3, Easter Eggs Teil 2 „Necken“): Kontrollbilder des Browser-Clients „Lite“ mit dem Schein-Gastgeber (mock.js),
# Chrome headless über tools/webtest/cdp.ps1 → docs/module/optik_163_lite_*.png. Die Effekte werden direkt über MMF.Necken.zeige
# ausgelöst (wie ein fx des Gastgebers; Wecker auch an Computergegnern nur hier), das Menü über MMF.Necken.oeffne.
# Aufruf: powershell -NoProfile -File tools\webtest\necken_bilder.ps1 [-Nur tag,nacht,…]
param([string]$Nur = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$cdp = Join-Path $PSScriptRoot 'cdp.ps1'
$out = Join-Path $root 'docs\module'
$seite = ([Uri](Join-Path $root 'webclient\index.html')).AbsoluteUri
$warte = "!!(window.MMF && MMF.App && MMF.App.tisch && MMF.App.tisch.v && document.querySelector('#tisch .gg[data-seat=`"3`"]'))"
# Bausteine: Effekte nach ms auslösen
function Z([int]$ms, [string]$js) { return "setTimeout(()=>{try{$js}catch(e){console.error(e)}},$ms);" }
$N = 'MMF.Necken'
$bilder = [ordered]@{
    # Tag: Menü an Lena (am Zug, vor 10 s: Schnarchen/Wecker ausgegraut), Mia schnarcht, Kugel liegt bei Tom (Computer, „Mpf!“), Reaktionen
    tag = @{ q = '&dran=1'; w = 844; h = 390; ms = 3000; pre = (Z 0 "$N.zeige({k:'snore',from:1,to:3});$N.zeige({k:'ball',from:3,to:2})") + (Z 2300 "$N.zeige({k:'react',from:0,r:'klatschen'})") + (Z 2450 "$N.zeige({k:'react',from:1,r:'lachen'})") + (Z 2600 "$N.oeffne(1)") }
    # Nacht: Wecker klingelt bei Mia, Kugel fliegt zu Lena, Reaktionsfächer offen
    nacht = @{ q = '&dran=3&seite=dunkel'; w = 844; h = 390; ms = 3350; pre = (Z 0 "$N.zeige({k:'alarm',from:1,to:3})") + (Z 2950 "$N.zeige({k:'ball',from:0,to:1})") + (Z 2500 "$N.zeige({k:'snore',from:0,to:3})") + (Z 3100 "$N.reaktionen(true)") }
    # Wecker an mich (groß, klingelt) und die Zeile über dem eigenen Namensschild
    wecker_ziel = @{ q = '&dran=0'; w = 844; h = 390; ms = 2000; pre = (Z 0 "$N.zeige({k:'alarm',from:1,to:0})") }
    wecker_klingelt = @{ q = '&dran=0&seite=dunkel'; w = 844; h = 390; ms = 3350; pre = (Z 0 "$N.zeige({k:'alarm',from:1,to:0})") + (Z 2600 "$N.zeige({k:'ball',from:3,to:0})") }
    # Menü nach 10 s (Schnarchen und Wecker frei) und Ziel mit Necken aus
    menue_frei = @{ q = '&dran=1'; w = 844; h = 390; ms = 10800; pre = (Z 10500 "$N.oeffne(1)") }
    menue_aus = @{ q = '&dran=1&seite=dunkel'; w = 844; h = 390; ms = 900; pre = (Z 0 "$N.fxOffs({seats:[3]})") + (Z 500 "$N.oeffne(3)") }
    # Großer Modus: Reaktionsknopf links an der eigenen Zeile, Fächer offen, Kugel auf Tom
    gross = @{ q = '&dran=1&gross=1'; w = 844; h = 390; ms = 1500; pre = (Z 0 "$N.zeige({k:'ball',from:0,to:2})") + (Z 900 "$N.zeige({k:'react',from:1,r:'daumen'})") + (Z 1100 "$N.reaktionen(true)") }
    gross_menue = @{ q = '&dran=1&gross=1&seite=dunkel'; w = 844; h = 390; ms = 1200; pre = (Z 0 "$N.zeige({k:'snore',from:0,to:1})") + (Z 800 "$N.oeffne(3)") }
    # Hochkant (Rahmen), Schrift „Sehr groß“, Englisch, Rundenende
    hochkant = @{ q = '&dran=1'; w = 390; h = 844; ms = 1200; pre = (Z 0 "$N.zeige({k:'snore',from:0,to:1})") + (Z 800 "$N.oeffne(1)") }
    hochkant_faecher = @{ q = '&dran=1&seite=dunkel'; w = 390; h = 844; ms = 1200; pre = (Z 600 "$N.zeige({k:'react',from:0,r:'schreck'})") + (Z 800 "$N.reaktionen(true)") }
    sehr_gross = @{ q = '&dran=1&schrift=sehr_gross'; w = 844; h = 390; ms = 900; pre = (Z 500 "$N.oeffne(1)") }
    en = @{ q = '&dran=1&lang=en'; w = 844; h = 390; ms = 1000; pre = (Z 0 "$N.zeige({k:'ball',from:1,to:0})") + (Z 600 "$N.oeffne(1)") }
    rundenende = @{ q = '&szene=rundenende'; w = 844; h = 390; ms = 1800; pre = (Z 900 "$N.zeige({k:'react',from:0,r:'klatschen'});$N.zeige({k:'react',from:2,r:'lachen'})") + (Z 1200 "$N.reaktionen(true)") }
    # Beta 1.6.3: größere Effekte bei Mitspielern (Wecker, Z und Mütze etwa doppelt, Reaktionen und fliegende Kugel 1,6-fach)
    schnarchen_oben_tag = @{ q = '&dran=2'; w = 844; h = 390; ms = 2300; pre = (Z 0 "$N.zeige({k:'snore',from:1,to:2})") + (Z 1700 "$N.zeige({k:'react',from:3,r:'lachen'})") }
    wecker_rechts_nacht = @{ q = '&dran=3&seite=dunkel'; w = 844; h = 390; ms = 3400; pre = (Z 0 "$N.zeige({k:'alarm',from:1,to:3})") + (Z 2900 "$N.zeige({k:'react',from:2,r:'schreck'})") }
    wecker_links_tag = @{ q = '&dran=1'; w = 844; h = 390; ms = 3400; pre = (Z 0 "$N.zeige({k:'alarm',from:0,to:1})") + (Z 3050 "$N.zeige({k:'ball',from:3,to:2})") }
    reaktionen_nacht = @{ q = '&dran=1&seite=dunkel'; w = 844; h = 390; ms = 700; pre = (Z 0 "$N.zeige({k:'react',from:0,r:'lachen'});$N.zeige({k:'react',from:1,r:'schreck'});$N.zeige({k:'react',from:2,r:'klatschen'});$N.zeige({k:'react',from:3,r:'daumen'})") }
    reaktionen_tag = @{ q = '&dran=1'; w = 844; h = 390; ms = 700; pre = (Z 0 "$N.zeige({k:'react',from:0,r:'daumen'});$N.zeige({k:'react',from:1,r:'klatschen'});$N.zeige({k:'react',from:2,r:'schreck'});$N.zeige({k:'react',from:3,r:'lachen'})") }
    gross_effekte = @{ q = '&dran=1&gross=1'; w = 844; h = 390; ms = 3400; pre = (Z 0 "$N.zeige({k:'snore',from:0,to:1});$N.zeige({k:'alarm',from:0,to:3});$N.zeige({k:'ball',from:0,to:2})") + (Z 2800 "$N.zeige({k:'react',from:2,r:'lachen'});$N.zeige({k:'react',from:0,r:'daumen'})") }
    gross_effekte_nacht = @{ q = '&dran=1&gross=1&seite=dunkel'; w = 844; h = 390; ms = 3400; pre = (Z 0 "$N.zeige({k:'alarm',from:0,to:1})") + (Z 1600 "$N.zeige({k:'snore',from:0,to:3})") + (Z 3050 "$N.zeige({k:'ball',from:3,to:2})") }
    hochkant_effekte = @{ q = '&dran=1'; w = 390; h = 844; ms = 3400; pre = (Z 0 "$N.zeige({k:'snore',from:0,to:1});$N.zeige({k:'alarm',from:0,to:3})") + (Z 2700 "$N.zeige({k:'react',from:2,r:'lachen'});$N.zeige({k:'react',from:0,r:'klatschen'})") + (Z 3050 "$N.zeige({k:'ball',from:3,to:2})") }
    reduziert = @{ q = '&dran=1'; w = 844; h = 390; ms = 3400; pre = (Z 0 "MMF.App.einstellungen.effekte='reduziert';document.body.classList.add('reduziert');$N.zeige({k:'snore',from:0,to:1});$N.zeige({k:'alarm',from:0,to:3})") + (Z 2800 "$N.zeige({k:'react',from:2,r:'lachen'});$N.zeige({k:'ball',from:3,to:2})") }
    desktop = @{ q = '&dran=1'; w = 1600; h = 900; ms = 3000; pre = (Z 0 "$N.zeige({k:'snore',from:1,to:3});$N.zeige({k:'ball',from:3,to:2})") + (Z 2300 "$N.zeige({k:'react',from:0,r:'daumen'})") + (Z 2600 "$N.oeffne(1)") }
}
$auswahl = @($Nur.Split(',') | Where-Object { $_ })
foreach ($name in $bilder.Keys) {
    if ($auswahl.Count -and $auswahl -notcontains $name) { continue }
    $b = $bilder[$name]
    $szene = if ($b.q -match 'szene=') { '' } else { '&szene=tisch' }
    $url = "$seite`?mock=1$szene&halt=1&gegner=3&name=Kim$($b.q)"
    $datei = Join-Path $out "optik_163_lite_$name.png"
    & $cdp -Url $url -Out $datei -Width $b.w -Height $b.h -Scale 2 -Mobile -WaitExpr $warte -Pre $b.pre -WaitMs $b.ms -TimeoutMs 30000 -Eval "JSON.stringify({fehler: MMF.App.fehler, gezeigt: MMF.Necken.gezeigt.length})"
}
