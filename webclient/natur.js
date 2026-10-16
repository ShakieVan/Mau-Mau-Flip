/* Mau-Mau Flip (Beta 1.6.11): „Natur-Überraschungen“ im Browser-Client „Lite“ – Kern (docs/module/natur.md, Aufgabe T2).
 * Seltene, lautlose Bild-Ereignisse am Tisch (Marienkäfer, Glühwürmchen, Eule …), wie in der App (game/scripts/ui/nature_fx.gd).
 * Jedes Gerät würfelt selbst: nichts geht übers Netz, nichts in Sicht, Speicher oder Protokoll; kein Ton, keine Vibration, kein Text.
 *
 * Dieser Kern enthält:
 *  - die gemeinsame Tabelle (JSON zwischen den Markern unten, gleich NatureTable.DATA; test_web_contract vergleicht beide),
 *  - den Planer (Abschnitt 4.2: ein Ereignis zur Zeit, Takt, Anlässe Flip und Trödeln, Ruhe, Abgang und Abbruch, Vorführung),
 *  - die drei Ebenen (2.1), Orte (2.2), Schutzflächen (2.3), Tippen und Scheu (4.6).
 * Die Tiere selbst stehen in natur_tag.js / natur_nacht.js (Aufgaben T5/T6) und melden sich mit M.Natur.art(id, def) an.
 * Fehlt eine Art (noch nicht geladen), kommt ihr Ereignis einfach nicht vor.
 *
 * Ebenen (Kinder der .buehne, von natur.js selbst angelegt, pointer-events none, aria-hidden; tisch.js und style.css bleiben unberührt):
 *   #natur-hinten  erstes Kind der .buehne, z-index auto: über Himmel, Sonne und Mond, unter allem anderen
 *   #natur-mitte   direkt nach .richtung, z-index auto (nicht positiv, sonst läge es über .farbanzeige/.stapelzahl): unter Plätzen,
 *                  Stapel, Ablage, Farbring und Hand
 *   #natur-vorn    z-index 33: über Hand (30/31), Stapel und Ablage, unter Plätzen (35), Leiste (50), Knöpfen (60) und .flug (300)
 *
 * Vertrag für eine Art (natur_tag.js / natur_nacht.js):
 *   M.Natur.art('<id>', { baue(ctx, zufall) { …; return inst; } })      id aus der Tabelle; zufall() ∈ [0, 1) aus dem Samen des Ereignisses
 *   M.Natur.stil('<name>', css)   CSS der Art einmal in <style id="natur-stil"> (Klassen mit Präfix nt-, Necken nutzt nk-)
 *   inst = {
 *     el,            Wurzel-Element (SVG/HTML-Zeichenkette als Element). Der Kern hängt es in die Ebene, gibt ihm die Klasse
 *                    nt-wesen (absolut, links oben 0/0) und data-natur=<id> und entfernt es am Ende wieder.
 *     ebene?,        'hinten' | 'mitte' | 'vorn' (fehlt: aus der Tabelle)
 *     dauer,         Sekunden (aus zufall innerhalb der Tabellen-Dauer); darf sich ändern (z. B. nach tipp), der Kern liest sie jedes Bild
 *     stelle(t),     Pose zur Zeit t (s ab Start) setzen. Rein in t: gleiche Samen + gleiches t = gleiches Bild (seek für Tests und
 *                    Kontrollbilder). Nur transform und opacity setzen. Reaktionen auf tipp/abgang laufen als eigene Zeitlinie ab
 *                    der gemerkten Zeit (die Art merkt sie sich selbst).
 *     hulle(t),      {x, y, w, h} in Bühnen-px (Höhe 720) oder null, wenn nichts zu sehen ist (Tests: Sichtbarkeit, deckt, Scheu, Treffer)
 *     treffer?(p),   Tipp p {x, y} trifft das Tier (fehlt: Abstand zur Mitte der Hülle ≤ max(treffer_min_r, halbe Hüllengröße))
 *     tipp?(p),      Reaktion auf einen Tipp ins Leere (nur Arten mit „tipp“ in der Tabelle, höchstens einmal je Ereignis)
 *     scheu?(p),     wird vor dem schnellen Abgang einer scheuen Art gerufen (Berührung in scheu_r)
 *     ereignis?(e),  Spielereignis {e, …} gesehen; true = schnell abgehen (Ereignisse am Ort ergänzt der Kern selbst, siehe ORT_WEG)
 *     abgang(),      schnell abgehen (wegfliegen bzw. ausblenden); Rückgabe Sekunden bis zum Ende (Standard abgang_s, höchstens 1,5)
 *   }
 *   ctx (beim Start berechnet, Bühnen-px): {id, eintrag, W, H, s, cx, cy, seite ('tag'|'nacht'), nacht, ruhig (ruhige Variante bei
 *     „Effekte reduziert“), reduziert, zeiten, form (Sternbild), ort (Anker dieses Eintrags), orte {…alle Anker…},
 *     band(grad, quer?) → {x, y} auf der Richtungs-Plattform (0° rechts, 90° vorn; quer 0 innen … 1 außen, Standard 0,5 = Bandmitte),
 *     ring {cx, cy, rx, ry} (Ellipse als Näherung des Bands), plaetze [{seat, x, y, w, h, ich}] (Köpfe), schutz [{name, x, y, w, h}],
 *     frei(rect) → Überdeckung mit Schutzflächen (px²), hand() → mittlere sichtbare Handkarte {id, x, y, w, h, top, rot} (y = Mitte,
 *     meist unter dem Bildrand) oder null, troedler (Platz der Schnecke), meinPlatz, demo}
 *   Anker in orte: himmel/himmel_oben/himmel_fern/tisch_quer {x0, x1, y0, y1}, himmel_frei {x, y, w, h}, himmel_bogen {cx, cy, r},
 *     sonne {x, y, r}, mond {x, y, w, h, rot}, band_hinten/band_schulter/band_vorn_seite/band_zum_platz {grad (, seat)},
 *     tisch_rund {cx, cy, rx, ry, f0, f1, ymax}, handkarte, stapel_oben {x, y, stapel}, ablage_ring {x, y, R}, aufsteigend {x, y, ziel_y}
 *   Hilfen: M.Natur.h = {el, klemme, lerp, glatt, setze(el, x, y, rot, sk, op)}.
 *   Regeln: keine Bilddateien, keine fremden Grafiken, kein Ton (M.Ton), kein navigator.vibrate, kein Netz; kein filter/backdrop-filter,
 *   kein animierter box-shadow; innere Schleifen als CSS-Keyframes mit der Klasse nt-schleife (steht unter body.reduziert still);
 *   höchstens etwa 30 Knoten; keine Klasse „karte“ (tisch.js sucht danach); kein z-index > 0 in der Ebene „mitte“.
 *   mix-blend-mode: screen wirkt nur gegen die Inhalte der Bühne (sie ist eine eigene Ebene); vor dem Himmel wirkt es wie Deckkraft.
 *
 * Schnittstelle (app.js): init(app) nach M.Necken.init, sicht(events, view) im Fall 'state' nach M.Necken.sicht.
 * Tests (webclient/test/lite_natur.html) und Kontrollbilder (tools/webtest/natur_bilder.ps1):
 *   test({seed, manuell, probe})  manuelle Uhr (kein setInterval/rAF), fester Samen, probe = Art für alle ids
 *   tick(dt)                      Uhr um dt Sekunden weiter (Planer und laufendes Ereignis)
 *   zeige(id, {seed, t, anteil, stehen})  Ereignis ohne Bedingungen starten; t bzw. anteil × dauer = Zeitpunkt; stehen = eingefroren
 *   zustand(), arten(), schutz(), orte(), huelle(t)
 *   Adresse: ?natur=reihe (Vorführung: alle 12 s das nächste Ereignis der Seite), ?natur=test (manuelle Uhr), ?seed=Zahl
 */
(function (M) {
  'use strict';

  const DATEN = /*NATUR-DATEN*/{
 "zeiten": {"erst_s": [45, 150], "abstand_s": [100, 260], "reduziert_faktor": 2, "neuversuch_s": 5, "ruhe_s": 2,
  "anlass_abstand_s": 25, "keine_wiederholung": 4, "abgang_s": 0.4, "flip_chance": 0.4, "flip_nach_s": 1.5, "flip_bis_s": 6,
  "flip_je_runde": 1, "troedel_s": 35, "troedel_chance": 0.35, "troedel_max_s": 40, "scheu_r": 130, "treffer_min_r": 40,
  "komet_sperre_s": 20, "vorfuehr_tipps": 7, "vorfuehr_fenster_s": 4, "vorfuehr_abstand_s": 12},
 "ereignisse": [
  {"id": "marienkaefer", "seite": "tag", "zufall": 3, "nach_flip": 0, "troedeln": false, "ebene": "mitte", "ort": "band_vorn_seite", "dauer": [9, 12], "ruhig": false, "tipp": "wegfliegen", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "biene", "seite": "tag", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "vorn", "ort": "handkarte", "dauer": [7, 9], "ruhig": false, "tipp": "", "scheu": true, "fremder_zug": true, "je_partie": 0, "je_runde": 0, "deckt": ["hand"], "deckt_max_s": 2, "bestand": false},
  {"id": "libelle", "seite": "tag", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "mitte", "ort": "tisch_quer", "dauer": [6, 8], "ruhig": false, "tipp": "wegflitzen", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "pusteblume", "seite": "tag", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel", "dauer": [12, 15], "ruhig": false, "tipp": "wind", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "papierflieger", "seite": "tag", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel", "dauer": [6, 7], "ruhig": false, "tipp": "looping", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "seifenblasen", "seite": "tag", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "mitte", "ort": "tisch_quer", "dauer": [8, 11], "ruhig": false, "tipp": "platzen", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "spatz", "seite": "tag", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "mitte", "ort": "band_hinten", "dauer": [7, 10], "ruhig": false, "tipp": "wegfliegen", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "wolke", "seite": "tag", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "sonne", "dauer": [12, 16], "ruhig": true, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "regenbogen", "seite": "tag", "zufall": 0, "nach_flip": 1, "troedeln": false, "ebene": "hinten", "ort": "himmel_bogen", "dauer": [7, 7], "ruhig": true, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 1, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "heissluftballon", "seite": "tag", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel_fern", "dauer": [18, 22], "ruhig": false, "tipp": "aufsteigen", "scheu": false, "fremder_zug": false, "je_partie": 1, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "schnecke", "seite": "tag", "zufall": 0, "nach_flip": 0, "troedeln": true, "ebene": "mitte", "ort": "band_zum_platz", "dauer": [40, 40], "ruhig": false, "tipp": "einziehen", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "schmetterling", "seite": "tag", "zufall": 3, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel", "dauer": [9, 9], "ruhig": false, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": true},
  {"id": "gluehwuermchen", "seite": "nacht", "zufall": 3, "nach_flip": 3, "troedeln": false, "ebene": "mitte", "ort": "tisch_rund", "dauer": [12, 15], "ruhig": false, "tipp": "auseinander", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "eule", "seite": "nacht", "zufall": 3, "nach_flip": 1, "troedeln": false, "ebene": "mitte", "ort": "band_schulter", "dauer": [12, 16], "ruhig": false, "tipp": "kopf_blinzeln", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "fledermaus", "seite": "nacht", "zufall": 2, "nach_flip": 2, "troedeln": false, "ebene": "hinten", "ort": "himmel", "dauer": [4, 6], "ruhig": false, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "mond_muetze", "seite": "nacht", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "mond", "dauer": [10, 12], "ruhig": true, "tipp": "aufwachen", "scheu": false, "fremder_zug": false, "je_partie": 1, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "polarlicht", "seite": "nacht", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel_oben", "dauer": [12, 14], "ruhig": true, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 1, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "sternbild", "seite": "nacht", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel_frei", "dauer": [9, 10], "ruhig": true, "tipp": "funkeln", "scheu": false, "fremder_zug": false, "je_partie": 1, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false,
   "form": {"punkte": [[0.12, 0.06], [0.22, 0.20], [0.32, 0.04], [0.08, 0.38], [0.38, 0.34], [0.18, 0.64], [0.22, 0.96], [0.62, 0.48], [0.78, 0.92], [0.97, 0.72], [0.90, 0.38]],
            "linien": [[0, 1], [1, 2], [0, 3], [2, 4], [3, 5], [4, 7], [5, 6], [6, 8], [7, 8], [8, 9], [9, 10]]}},
  {"id": "ufo", "seite": "nacht", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "vorn", "ort": "stapel_oben", "dauer": [6, 7], "ruhig": false, "tipp": "davon", "scheu": true, "fremder_zug": true, "je_partie": 1, "je_runde": 0, "deckt": ["stapel"], "deckt_max_s": 3, "bestand": false},
  {"id": "satellit", "seite": "nacht", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel_oben", "dauer": [9, 11], "ruhig": false, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "motte", "seite": "nacht", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "mitte", "ort": "ablage_ring", "dauer": [6, 8], "ruhig": false, "tipp": "", "scheu": true, "fremder_zug": true, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "igel", "seite": "nacht", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "mitte", "ort": "band_vorn_seite", "dauer": [10, 14], "ruhig": false, "tipp": "einrollen", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "komet", "seite": "nacht", "zufall": 1, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel_oben", "dauer": [14, 16], "ruhig": false, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "lampion", "seite": "nacht", "zufall": 2, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "aufsteigend", "dauer": [11, 13], "ruhig": false, "tipp": "leuchten", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": false},
  {"id": "sternschnuppe", "seite": "nacht", "zufall": 3, "nach_flip": 0, "troedeln": false, "ebene": "hinten", "ort": "himmel", "dauer": [1.2, 1.2], "ruhig": false, "tipp": "", "scheu": false, "fremder_zug": false, "je_partie": 0, "je_runde": 0, "deckt": [], "deckt_max_s": 0, "bestand": true}
 ]
}/*ENDE*/;

  const Z = DATEN.zeiten;
  const EINTRAG = {};
  DATEN.ereignisse.forEach(e => { EINTRAG[e.id] = e; });
  const EBENEN = ['hinten', 'mitte', 'vorn'];
  const SEITE = s => (s === 'dunkel' || s === 'nacht' ? 'nacht' : 'tag');
  const ZUG_PHASEN = ['turn', 'drawn'];
  const ALLE_WEG = ['round_over', 'game_over', 'round_start', 'deal', 'seats', 'start'];
  const VORN_WEG = ['mau', 'finish', 'catch', 'gamble_start'];
  // Ereignisse am Ort (Abschnitt 4.5): UFO am Stapel, Motte am Ablage-Ring, Biene auf der Hand
  const ORT_WEG = { stapel_oben: ['draw', 'shuffle'], ablage_ring: ['play', 'flip', 'discard_color', 'stake_discard', 'shuffle'], handkarte: ['swap_hands'] };
  const HAND_WEG = ['play', 'draw', 'stake', 'stake_back', 'discard_color', 'unplay'];   // eigene Hand ändert sich
  const PROTOKOLL_MAX = 60;
  const KW = 190, KH = Math.round(KW * 870 / 560);   // Handkarte (hand.js)

  const params = new URLSearchParams(location.search);
  const klemme = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
  const lerp = (a, b, u) => a + (b - a) * u;
  const glatt = u => { u = klemme(u, 0, 1); return u * u * (3 - 2 * u); };
  function el(tag, cls, html) { const e = document.createElement(tag); if (cls) e.className = cls; if (html !== undefined) e.innerHTML = html; return e; }
  function setze(e, x, y, rot, sk, op) {
    e.style.transform = 'translate(' + (+x || 0).toFixed(1) + 'px,' + (+y || 0).toFixed(1) + 'px)' + (rot ? ' rotate(' + (+rot).toFixed(2) + 'deg)' : '') + (sk !== undefined && sk !== 1 ? ' scale(' + (+sk).toFixed(3) + ')' : '');
    if (op !== undefined) e.style.opacity = String(Math.round(klemme(op, 0, 1) * 1000) / 1000);
  }
  // mulberry32: kleiner, fester Zufall aus einem Samen (gleicher Samen = gleiche Bahn)
  function mulberry32(a) {
    a = a >>> 0;
    return function () {
      a = (a + 0x6D2B79F5) >>> 0;
      let t = a;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  // Punkt auf der Richtungs-Plattform relativ zur Tischmitte, wie plattform() in tisch.js (Superellipse, Kippung, Perspektive; gleiche
  // Konstanten PL): grad 0 = rechts, 90 = vorn (im Uhrzeigersinn); quer 0 = Innenkante, 0,5 = Bandmitte, 1 = Außenkante.
  // Die Ellipse aus dem Entwurf (rx, ry = 159) wich in den Ecken sichtbar ab (Kontrollbild), daher die genaue Rechnung.
  const PL = { lochX: 372, lochY: 136, minX: 326, band: 66, kipp: 0.70, persp: 0.11, eck: 2.5, dy: 6 };
  function bandPunkt(W, grad, quer) {
    const fx = Math.min(330, W * 0.21) / 330;
    const ai = Math.max(PL.lochX * fx, PL.minX), bi = PL.lochY / PL.kipp, bd = PL.band * Math.min(fx, 1), zref = bi + bd;
    const proj = (x, z) => { const s = 1 / (1 - PL.persp * z / zref); return [x * s, PL.kipp * z * s]; };
    const yoff = PL.dy - (proj(0, bi)[1] + proj(0, -bi)[1]) / 2;
    const t = grad * Math.PI / 180, c = Math.cos(t), s = Math.sin(t), e = PL.eck;
    const q = [ai * Math.sign(c) * Math.pow(Math.abs(c), 2 / e), bi * Math.sign(s) * Math.pow(Math.abs(s), 2 / e)];
    const g = [Math.sign(q[0]) * Math.pow(Math.abs(q[0]) / ai, e - 1) / ai, Math.sign(q[1]) * Math.pow(Math.abs(q[1]) / bi, e - 1) / bi];
    const l = Math.hypot(g[0], g[1]) || 1, off = bd * (typeof quer === 'number' ? quer : 0.5);
    const r = proj(q[0] + g[0] / l * off, q[1] + g[1] / l * off);
    return [r[0], r[1] + yoff];
  }
  const flaeche = (a, b) => Math.max(0, Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)) * Math.max(0, Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y));
  const innen = (p, r) => p.x >= r.x && p.x <= r.x + r.w && p.y >= r.y && p.y <= r.y + r.h;
  const abstandRect = (p, r) => Math.hypot(Math.max(r.x - p.x, 0, p.x - (r.x + r.w)), Math.max(r.y - p.y, 0, p.y - (r.y + r.h)));

  const CSS_KERN = '.natur-ebene{position:absolute;left:0;top:0;width:100%;height:100%;overflow:hidden;pointer-events:none}'
    + '.natur-ebene,.natur-ebene *{pointer-events:none!important}'
    + '#natur-vorn{z-index:33}'
    + '.nt-wesen{position:absolute;left:0;top:0;transform-origin:0 0}'
    + 'body.reduziert .natur-ebene .nt-schleife{animation:none!important}';

  const N = {
    DATEN, ZEITEN: Z, EINTRAG, mulberry32,
    h: { el, klemme, lerp, glatt, setze },
    app: null,
    ebenen: null,          // {hinten, mitte, vorn}
    _arten: {},            // id → def
    _stile: {},            // Name → true
    rng: mulberry32((Math.random() * 4294967296) >>> 0),
    manuell: false,        // Tests: Uhr nur über tick(dt)
    probe: null,           // Tests: eine Art für alle ids
    lageTest: null,        // Tests: Lage überschreiben (z. B. {regieLeer: false, seite: 'nacht'})
    now: 0,                // Planer-Uhr (s)
    faellig: Infinity,     // nächster Zufallsstart
    current: null,         // laufendes Ereignis
    verlauf: { tag: [], nacht: [] },
    zaehler: { partie: {}, runde: {} },
    flipRunde: {},
    letztesEnde: -1e9,
    flip: null,            // Anlass {seite, at}
    tr: { sig: '', seit: 0, gewuerfelt: false, seat: -1, spieler: {} },   // Trödel-Uhr
    trWartet: null,        // Schnecke wartet {seat, sig, verdraengt}
    kometSperreBis: -1e9,
    demo: { an: false, naechste: 0, pos: { tag: -1, nacht: -1 } },
    protokoll: [],         // [{was: 'start'|'ende', id, now, anlass, grund, seite, meinZug}]
    _unruhe: -1e9, _plan: -1e9, _warAktiv: false, _warTisch: false, _alt: null, _letzt: 0, _raf: 0, _verstecktAb: 0,
    _handGedrueckt: false, _tipps: [],

    uhr: () => (window.performance && performance.now ? performance.now() : Date.now()) / 1000,

    init(app) {
      this.app = app;
      const nt = params.get('natur') || '';
      const s = parseInt(params.get('seed'), 10);
      if (isFinite(s)) this.rng = mulberry32(s);
      if (nt === 'test') this.manuell = true;
      if (nt === 'reihe') this.demo.an = true;
      this.stil('kern', CSS_KERN);
      const root = document.getElementById('tisch');
      if (root) root.addEventListener('pointerdown', ev => this._druck(ev), true);
      const los = () => { this._handGedrueckt = false; };
      window.addEventListener('pointerup', los, true);
      window.addEventListener('pointercancel', los, true);
      document.addEventListener('visibilitychange', () => {
        const j = this.uhr();
        if (document.hidden) { this._verstecktAb = j; return; }
        this._letzt = j;
        if (this._verstecktAb && j - this._verstecktAb > 2) this.faellig = Math.max(this.faellig, this.now + this._gleich(Z.erst_s));
      });
      setInterval(() => this._uhr(), 500);
    },

    /* ---------- Arten ---------- */
    art(id, def) {
      if (!EINTRAG[id] || !def || typeof def.baue !== 'function') { if (M.meldeFehler) M.meldeFehler('Natur: unbekannte Art ' + id); return false; }
      this._arten[id] = def;
      return true;
    },
    stil(name, css) {
      if (this._stile[name]) return;
      this._stile[name] = true;
      let s = document.getElementById('natur-stil');
      if (!s) { s = document.createElement('style'); s.id = 'natur-stil'; document.head.appendChild(s); }
      s.appendChild(document.createTextNode('\n' + css));
    },
    arten() { return Object.keys(this._arten).filter(id => EINTRAG[id]); },
    _def(id) { return this.probe || this._arten[id] || null; },

    /* ---------- Tests ---------- */
    test(o) {
      o = o || {};
      if (o.seed !== undefined) this.rng = mulberry32(o.seed);
      if (o.manuell !== undefined) this.manuell = !!o.manuell;
      if (o.probe !== undefined) this.probe = o.probe || null;
      if (o.lage !== undefined) this.lageTest = o.lage || null;
      if (o.neu) {
        if (this.current) this._weg(this.current, 'test');
        this.now = 0; this.faellig = Infinity; this.verlauf = { tag: [], nacht: [] }; this.zaehler = { partie: {}, runde: {} };
        this.flipRunde = {}; this.letztesEnde = -1e9; this.flip = null; this.trWartet = null; this.kometSperreBis = -1e9;
        this.tr = { sig: '', seit: 0, gewuerfelt: false, seat: -1, spieler: {} };
        this.demo = { an: false, naechste: 0, pos: { tag: -1, nacht: -1 } };
        this.protokoll = []; this._unruhe = -1e9; this._plan = -1e9; this._warAktiv = false; this._alt = null; this._tipps = [];
      }
      if (o.faellig !== undefined) this.faellig = this.now + o.faellig;
      return this.zustand();
    },
    zustand() {
      const c = this.current, L = this.app && this.app.tisch ? this._lage() : null;
      return {
        now: this.now, faellig: this.faellig, letztesEnde: this.letztesEnde, aktiv: !!L && this._aktiv(L), ruhe: !!L && this._ruhe(L),
        current: c ? { id: c.id, t: c.t, dauer: this._dauer(c), ebene: c.ebene, ende: c.ende, getippt: c.getippt, seed: c.seed, anlass: c.anlass, stehen: c.stehen } : null,
        verlauf: { tag: this.verlauf.tag.slice(), nacht: this.verlauf.nacht.slice() }, zaehler: JSON.parse(JSON.stringify(this.zaehler)),
        flip: this.flip, wartet: this.trWartet, demo: this.demo.an, protokoll: this.protokoll.slice(),
      };
    },
    // Ereignis ohne Bedingungen (Tests, Kontrollbilder, Vorführung); t bzw. anteil: gleich dorthin springen; stehen: eingefroren
    zeige(id, o) {
      o = o || {};
      if (!this.app || !this.app.tisch || !this._ebenenDa()) return false;
      if (this.current) this._weg(this.current, 'zeige');
      if (!this._starte(id, { seed: o.seed, anlass: 'zeige', troedler: o.troedler })) return false;
      const c = this.current;
      c.stehen = !!o.stehen;
      let t = typeof o.t === 'number' ? o.t : (typeof o.anteil === 'number' ? o.anteil * this._dauer(c) : null);
      if (t !== null) this._seek(c, t);
      return true;
    },
    huelle(t) {
      const c = this.current;
      if (!c) return null;
      if (typeof t === 'number') this._seek(c, t);
      try { return c.inst.hulle ? c.inst.hulle(c.t) : null; } catch (e) { return null; }
    },
    schutz() { return this.app && this.app.tisch ? this._schutz() : []; },
    orte() { return this.app && this.app.tisch && this.app.tisch.g ? this._orte(mulberry32(1), this._schutz(), this._plaetze()) : null; },

    /* ---------- Uhr ---------- */
    _uhr() {
      if (this.manuell) return;
      const j = this.uhr();
      const dt = this._letzt ? j - this._letzt : 0;
      this._letzt = j;
      if (document.hidden || !this.app) return;
      this.tick(Math.min(Math.max(dt, 0), 2));
    },
    _rafLos() {
      if (this.manuell || this._raf || !window.requestAnimationFrame) return;
      const f = () => {
        this._raf = 0;
        if (this.manuell || !this.current) return;
        this._uhr();
        if (this.current) this._raf = requestAnimationFrame(f);
      };
      this._raf = requestAnimationFrame(f);
    },
    tick(dt) {
      dt = Math.max(0, Math.min(+dt || 0, 5));
      this.now += dt;
      if (!this.app) return;
      const c = this.current;
      if (c) this._schritt(c, dt);
      if (!this.manuell && this.now - this._plan < 0.25) return;
      this._plan = this.now;
      try { this._planen(); } catch (e) { if (M.meldeFehler) M.meldeFehler('Natur: ' + (e && e.stack || e)); }
    },

    /* ---------- Lage ---------- */
    _reduziert() { return !!((this.app && this.app.effekteReduziert && this.app.effekteReduziert()) || document.body.classList.contains('reduziert')); },
    _dialog(t) {
      if (document.querySelector('.modal:not([hidden])')) return true;
      if (M.Necken && M.Necken.offen) return true;
      for (const id of ['verbinde', 'umzug']) { const e = document.getElementById(id); if (e && !e.hidden) return true; }
      if (t && (t.farbwahlOffen || (t.farbwahl && !t.farbwahl.hidden) || t.durch)) return true;
      return false;
    },
    _neckenZahl(t) {
      if (!t || !t.flug) return 0;
      let n = 0;   // Necken-Effekte sind Kinder von .flug mit Klasse nk-… (necken.js _aufBuehne)
      for (const e of t.flug.children) if (/(^|\s)nk-/.test(String(e.className || ''))) n++;
      return n;
    },
    _lage() {
      const a = this.app, t = a && a.tisch, tv = t && t.v, v = (a && a.view) || tv;
      const L = {
        tisch: !!(a && a.screen === 'tisch' && t && tv && v),
        seite: t && t.root.dataset.seite === 'dunkel' ? 'nacht' : 'tag',
        W: t ? t.W : 0, H: t ? t.H : 0, s: t ? t.s : 1,
        gross: !!(t && t.gross), eng: !!(t && t.s < 0.5),
        reduziert: this._reduziert(),
        phase: v ? String(v.phase || '') : '',
        meinZug: !!(v && typeof v.seat === 'number' && v.seat >= 0 && v.turn === v.seat),
        regieLeer: !t || t.regie.leer,
        wechsel: !!(t && t.wechselRest && t.wechselRest() > 0),
        dialog: this._dialog(t),
        fang: !!(v && v.hints && Array.isArray(v.hints.catch) && v.hints.catch.length),
        necken: this._neckenZahl(t),
        strafe: !!(t && t.offenEl && !t.offenEl.hidden),
        handSig: t && t.hand ? t.hand.reihe.map(k => k.id).join(',') : '',
        gewaehlt: !!(t && t.hand && t.hand.gewaehlt !== null && t.hand.gewaehlt !== undefined),
      };
      if (this.lageTest) Object.assign(L, this.lageTest);
      return L;
    },
    _aktiv(L) { return L.tisch && !L.gross && !L.eng; },
    _ruhe(L) {
      return this._aktiv(L) && ZUG_PHASEN.indexOf(L.phase) >= 0 && L.regieLeer && !L.wechsel && this.now - this._unruhe >= Z.ruhe_s
        && !L.dialog && !L.fang && !L.necken;
    },

    /* ---------- Planer (Abschnitt 4.2) ---------- */
    _planen() {
      const L = this._lage();
      if (!L.regieLeer || L.wechsel) this._unruhe = this.now;
      this._beobachte(L);
      const aktiv = this._aktiv(L);
      const warTisch = this._warTisch;
      this._warTisch = L.tisch;
      if (!aktiv) {
        this._warAktiv = false;
        if (!L.tisch && warTisch) this.demo.an = false;   // Tisch verlassen: Vorführung aus (?natur=reihe gilt ab dem ersten Tisch)
        return;
      }
      if (!this._warAktiv) {   // Tischstart (auch nach Lobby, großem Modus, engem Fenster): erstes Ereignis nach erst_s
        this._warAktiv = true;
        this.faellig = this.now + this._gleich(Z.erst_s);
      }
      this._ebenenDa();
      if (this.demo.an) { this._vorfuehrung(L); return; }
      if (this._troedeln(L)) return;
      if (this.current || L.necken) return;
      const ruhe = this._ruhe(L);
      const f = this.flip;
      if (f) {
        // verfällt nach flip_bis_s, oder wenn der Tisch die Seite gar nicht gewechselt hat
        if (this.now > f.at + Z.flip_bis_s || (f.seite !== L.seite && L.regieLeer && !L.wechsel && this.now > f.at + Z.flip_nach_s + 1)) this.flip = null;
        else if (ruhe && f.seite === L.seite && this.now >= f.at + Z.flip_nach_s && this.now >= this.letztesEnde + Z.anlass_abstand_s) {
          this.flip = null;   // einmal würfeln
          if ((this.flipRunde[f.seite] || 0) < Z.flip_je_runde && this.rng() < Z.flip_chance) {
            const id = this._waehle(this._pool(f.seite, L, 'nach_flip'));
            if (id && this._starte(id, { anlass: 'flip' })) this.flipRunde[f.seite] = (this.flipRunde[f.seite] || 0) + 1;
          }
          return;
        }
      }
      if (this.now >= this.faellig) {
        if (!ruhe) { this.faellig = this.now + Z.neuversuch_s; return; }
        const id = this._ziehe(L);
        if (!id) { this.faellig = this.now + 6 * Z.neuversuch_s; return; }
        if (!this._starte(id, { anlass: 'zufall' })) this.faellig = this.now + Z.neuversuch_s;
      }
    },
    _gleich(b) { return b[0] + this.rng() * (b[1] - b[0]); },
    _waehle(paare) {
      let sum = 0;
      paare.forEach(p => { sum += p[1]; });
      if (sum <= 0) return '';
      let r = this.rng() * sum;
      for (const p of paare) { r -= p[1]; if (r < 0) return p[0]; }
      return paare[paare.length - 1][0];
    },
    // Kandidaten der Seite mit Gewicht aus feld (zufall | nach_flip), ohne Wiederholungssperre
    _pool(seite, L, feld) {
      const zp = this.zaehler.partie, zr = this.zaehler.runde;
      return DATEN.ereignisse.filter(e => e.seite === seite && e[feld] > 0 && !!this._def(e.id)
        && !(L.reduziert && !e.ruhig)
        && !(e.fremder_zug && (L.meinZug || this._handGedrueckt))
        && !(e.je_partie > 0 && (zp[e.id] || 0) >= e.je_partie)
        && !(e.je_runde > 0 && (zr[e.id] || 0) >= e.je_runde)
        && !(e.id === 'komet' && this.now < this.kometSperreBis)
        && !(e.ort === 'ablage_ring' && L.strafe)).map(e => [e.id, e[feld]]);
    },
    _ziehe(L) {
      const pool = this._pool(L.seite, L, 'zufall');
      if (!pool.length) return '';
      const v = this.verlauf[L.seite] || [];
      for (let k = Math.min(Z.keine_wiederholung, v.length); k >= 0; k--) {   // bleibt nichts übrig, fällt die älteste Sperre weg
        const sperre = v.slice(v.length - k);
        const rest = pool.filter(p => sperre.indexOf(p[0]) < 0);
        if (rest.length) return this._waehle(rest);
      }
      return '';
    },
    // Trödeln (4.3): true = der Planer ist für diesen Takt fertig
    _troedeln(L) {
      const tr = this.tr;
      if (tr.sig && !tr.gewuerfelt && ZUG_PHASEN.indexOf(L.phase) >= 0 && this.now - tr.seit >= Z.troedel_s) {
        tr.gewuerfelt = true;
        const e = EINTRAG.schnecke;
        if (tr.seat >= 0 && !tr.spieler[tr.seat] && e && e.seite === L.seite && this._def('schnecke') && !L.reduziert && this.rng() < Z.troedel_chance) {
          this.trWartet = { seat: tr.seat, sig: tr.sig, verdraengt: false };
        }
      }
      const w = this.trWartet;
      if (!w) return false;
      if (w.sig !== tr.sig || L.reduziert || EINTRAG.schnecke.seite !== L.seite) { this.trWartet = null; return false; }
      const c = this.current;
      if (c) {
        if (c.id !== 'schnecke' && c.ende === null && !c.stehen) { this._abgang(c, 'schnecke'); w.verdraengt = true; }
        return true;
      }
      if (L.necken || !this._ruhe(L)) return true;   // jede Sekunde neu versuchen, solange der Zug dauert
      if (!w.verdraengt && this.now < this.letztesEnde + Z.anlass_abstand_s) return true;
      this.trWartet = null;
      if (this._starte('schnecke', { anlass: 'troedeln', troedler: w.seat })) tr.spieler[w.seat] = true;
      return true;
    },
    // Vorführung (4.7): alle vorfuehr_abstand_s das nächste Ereignis der Seite in Tabellenreihenfolge (ohne je_partie, Sperre, fremder_zug)
    _vorfuehrung(L) {
      if (this.current || L.dialog || this.now < this.demo.naechste) return;
      const ids = DATEN.ereignisse.filter(e => e.seite === L.seite && !!this._def(e.id) && (!L.reduziert || e.ruhig)).map(e => e.id);
      if (!ids.length) return;
      const pos = (this.demo.pos[L.seite] + 1) % ids.length;
      this.demo.pos[L.seite] = pos;
      this.demo.naechste = this.now + Z.vorfuehr_abstand_s;
      const v = this.app.view || {};
      this._starte(ids[pos], { anlass: 'demo', troedler: typeof v.turn === 'number' ? v.turn : -1 });
    },
    _demoSchalten() {
      this.demo.an = !this.demo.an;
      this.demo.naechste = this.now;
      if (!this.demo.an) {
        if (this.current && !this.current.stehen) this._abgang(this.current, 'demo');
        this.faellig = Math.max(this.faellig, this.now + this._gleich(Z.abstand_s));
      }
    },

    /* ---------- Spielereignisse (app.js, vor der Regie) ---------- */
    sicht(events, view) {
      if (!this.app) return;
      events = Array.isArray(events) ? events : [];
      if (events.length) this._unruhe = this.now;
      const ich = view && typeof view.seat === 'number' ? view.seat : -1;
      for (const e of events) {
        if (!e || typeof e !== 'object') continue;
        const k = String(e.e || '');
        const c = this.current && !this.current.stehen ? this.current : null;
        if (k === 'flip') {
          const s = SEITE(e.side || (view && view.side));
          if (c && c.e.seite !== s) this._abgang(c, 'flip');
          this.flip = { seite: s, at: this.now };
        } else if (ALLE_WEG.indexOf(k) >= 0) {
          if (c) this._abgang(c, k);
          this.flip = null; this.trWartet = null;
          if (k === 'round_start') {
            this.zaehler.runde = {}; this.flipRunde = {};
            if ((e.round | 0) === 1) { this.zaehler.partie = {}; this.tr.spieler = {}; }
          }
        } else if (VORN_WEG.indexOf(k) >= 0) {
          if (c && (c.ebene === 'vorn' || c.e.fremder_zug)) this._abgang(c, k);
        } else if (k === 'skip_all') this.kometSperreBis = this.now + Z.komet_sperre_s;
        const cc = this.current && !this.current.stehen ? this.current : null;
        if (!cc || cc.ende !== null) continue;
        const ort = ORT_WEG[cc.e.ort];
        if (ort && ort.indexOf(k) >= 0) { this._abgang(cc, k); continue; }
        if (cc.e.ort === 'handkarte' && e.seat === ich && HAND_WEG.indexOf(k) >= 0) { this._abgang(cc, k); continue; }
        if (cc.inst.ereignis) {
          let weg = false;
          try { weg = cc.inst.ereignis(e) === true; } catch (err) { weg = true; }
          if (weg) this._abgang(cc, k);
        }
      }
      if (view) this._troedelSicht(view);
    },
    // Trödel-Uhr wie FunFx (Signatur aus turn | top.id | draw_count): beginnt neu, wenn sich Zug, Ablage oder Stapelzahl ändern
    _troedelSicht(v) {
      const sig = [v.turn, v.top && v.top.id, v.draw_count].join('|');
      if (sig === this.tr.sig) return;
      this.tr.sig = sig; this.tr.seit = this.now; this.tr.gewuerfelt = false; this.tr.seat = typeof v.turn === 'number' ? v.turn : -1;
      if (this.trWartet && this.trWartet.sig !== sig) this.trWartet = null;
      const c = this.current;
      if (c && c.id === 'schnecke' && !c.stehen && c.anlass !== 'zeige') this._abgang(c, 'zugende');
    },

    /* ---------- Abgang und Abbruch (4.5) ---------- */
    _beobachte(L) {
      const alt = this._alt;
      this._alt = { W: L.W, H: L.H, necken: L.necken, handSig: L.handSig, seite: L.seite };
      const c = this.current;
      if (!c || c.stehen) return;
      if (!this._aktiv(L)) { this._weg(c, L.gross ? 'gross' : (L.eng ? 'eng' : 'tisch')); return; }
      if (alt && (alt.W !== L.W || alt.H !== L.H)) { this._weg(c, 'groesse'); return; }
      if (L.reduziert && !c.e.ruhig) { this._weg(c, 'reduziert'); return; }
      if (c.ende !== null) return;
      if (c.e.seite !== L.seite && c.anlass !== 'zeige') { this._abgang(c, 'seite'); return; }   // zeige: auch auf der anderen Seite (Tests)
      const vorn = c.ebene === 'vorn', fz = vorn || c.e.fremder_zug;
      if (fz && (L.meinZug || L.fang)) { this._abgang(c, L.meinZug ? 'mein_zug' : 'erwischt'); return; }
      if (vorn && ZUG_PHASEN.indexOf(L.phase) < 0) { this._abgang(c, 'phase'); return; }   // Glücksspiel, Ablege-/Farbauswahl: Mitte frei
      if (vorn && L.dialog) { this._abgang(c, 'dialog'); return; }
      if (vorn && alt && L.necken > alt.necken) { this._abgang(c, 'necken'); return; }
      if (c.e.deckt.indexOf('hand') >= 0 && (L.gewaehlt || (alt && alt.handSig !== L.handSig) || this._handGedrueckt)) this._abgang(c, 'hand');
    },
    _abgang(c, grund) {
      if (!c || c.ende !== null) return;
      let d = Z.abgang_s;
      try { const r = c.inst.abgang ? c.inst.abgang() : undefined; if (typeof r === 'number' && r >= 0) d = Math.min(r, 1.5); } catch (e) { d = 0; }
      c.ende = c.t + d;
      c.grund = grund || '';
    },
    // sofort entfernen (Größe, großer Modus, reduziert, Tisch weg)
    _weg(c, grund) { c.grund = grund || c.grund || ''; this._beende(c); },
    _beende(c) {
      if (this.current !== c) return;
      try { if (c.el && c.el.parentNode) c.el.parentNode.removeChild(c.el); } catch (e) { /* egal */ }
      this.current = null;
      if (c.anlass === 'zeige') return;   // Tests und Kontrollbilder zählen nicht
      const red = this._reduziert();
      if (c.anlass !== 'demo') {
        this.faellig = this.now + this._gleich(Z.abstand_s) * (red ? Z.reduziert_faktor : 1);
        const v = this.verlauf[c.e.seite];
        v.push(c.id);
        if (v.length > 8) v.shift();
      } else this.demo.naechste = Math.max(this.demo.naechste, this.now + 0.5);
      this.letztesEnde = this.now;
      this._prot({ was: 'ende', id: c.id, now: this.now, anlass: c.anlass, grund: c.grund || '', dauer: c.t });
    },
    _prot(z) {
      this.protokoll.push(z);
      if (!this.manuell && this.protokoll.length > PROTOKOLL_MAX) this.protokoll.shift();
    },

    /* ---------- Start und Lauf ---------- */
    _ebenenDa() {
      const t = this.app && this.app.tisch;
      if (!t || !t.buehne) return false;
      if (this.ebenen && this.ebenen.hinten.parentNode === t.buehne) return true;
      const b = t.buehne, E = {};
      EBENEN.forEach(n => {
        const e = el('div', 'natur-ebene');
        e.id = 'natur-' + n;
        e.setAttribute('aria-hidden', 'true');
        E[n] = e;
      });
      b.insertBefore(E.hinten, b.firstChild);
      if (t.ring && t.ring.parentNode === b) b.insertBefore(E.mitte, t.ring.nextSibling); else b.insertBefore(E.mitte, E.hinten.nextSibling);
      b.appendChild(E.vorn);
      this.ebenen = E;
      return true;
    },
    _starte(id, o) {
      o = o || {};
      const e = EINTRAG[id], def = this._def(id);
      if (!e || !def || !this._ebenenDa()) return false;
      const seed = typeof o.seed === 'number' ? o.seed >>> 0 : Math.floor(this.rng() * 4294967296) >>> 0;
      const L = this._lage();
      let ctx, inst;
      try {
        ctx = this._ctx(e, seed, L, o);
        inst = def.baue(ctx, mulberry32(seed));
      } catch (err) { if (M.meldeFehler) M.meldeFehler('Natur ' + id + ': ' + (err && err.stack || err)); return false; }
      if (!inst || !inst.el || typeof inst.stelle !== 'function') return false;
      const ebene = EBENEN.indexOf(inst.ebene) >= 0 ? inst.ebene : e.ebene;
      inst.el.classList.add('nt-wesen');
      inst.el.dataset.natur = id;
      inst.el.setAttribute('aria-hidden', 'true');
      this.ebenen[ebene].appendChild(inst.el);
      const c = { id, e, inst, el: inst.el, ebene, seed, t: 0, ende: null, getippt: false, stehen: false, anlass: o.anlass || '', grund: '', ctx };
      this.current = c;
      try { inst.stelle(0); } catch (err) { this._weg(c, 'fehler'); if (M.meldeFehler) M.meldeFehler('Natur ' + id + ': ' + (err && err.stack || err)); return false; }
      if (c.anlass !== 'zeige' && c.anlass !== 'demo') {
        this.zaehler.partie[id] = (this.zaehler.partie[id] || 0) + 1;
        this.zaehler.runde[id] = (this.zaehler.runde[id] || 0) + 1;
      }
      this._prot({ was: 'start', id, now: this.now, anlass: c.anlass, seite: e.seite, tischSeite: L.seite, meinZug: L.meinZug, seed });
      this._rafLos();
      return true;
    },
    _dauer(c) { const d = +c.inst.dauer; return isFinite(d) && d > 0 ? Math.min(d, 60) : c.e.dauer[1]; },
    _seek(c, t) {
      c.t = Math.max(0, t);
      try { c.inst.stelle(c.t); } catch (e) { /* egal */ }
    },
    _schritt(c, dt) {
      if (c.stehen) return;
      c.t += dt;
      try { c.inst.stelle(c.t); } catch (e) { this._weg(c, 'fehler'); if (M.meldeFehler) M.meldeFehler('Natur ' + c.id + ': ' + (e && e.stack || e)); return; }
      if (c.ende !== null ? c.t >= c.ende : c.t >= this._dauer(c)) this._beende(c);
    },

    /* ---------- Tippen und Scheu (4.6) ---------- */
    _druck(ev) {
      const a = this.app, t = a && a.tisch;
      if (!t || !t.v || a.screen !== 'tisch') return;
      const ziel = ev.target;
      if (ziel && ziel.closest && ziel.closest('#hand-zone, #hand')) this._handGedrueckt = true;
      const L = this._lage();
      if (!this._aktiv(L)) return;
      const p = t.zuBuehne(ev.clientX, ev.clientY);
      const c = this.current && !this.current.stehen ? this.current : null;
      const h = c ? this._hulle(c) : null;
      // Scheu: geht ab, der Tipp wirkt normal weiter (nie preventDefault/stopPropagation)
      if (c && c.ende === null && c.e.scheu) {
        const amOrt = (c.e.deckt.indexOf('hand') >= 0 && ziel && ziel.closest && ziel.closest('#hand-zone, #hand'))
          || (c.e.deckt.indexOf('stapel') >= 0 && ziel && ziel.closest && ziel.closest('#stapel'));
        if (amOrt || (h && abstandRect(p, h) <= Z.scheu_r)) {
          try { if (c.inst.scheu) c.inst.scheu(p); } catch (e) { /* egal */ }
          this._abgang(c, 'scheu');
          return;
        }
      }
      if (!this._leer(ziel)) return;
      if (this._schutz().some(r => innen(p, r))) return;
      if (c && c.ende === null && c.e.tipp && !c.getippt && h && this._trifft(c, h, p)) {
        c.getippt = true;
        try { if (c.inst.tipp) c.inst.tipp(p); } catch (e) { /* egal */ }
        return;
      }
      if (c && h && this._trifft(c, h, p)) return;   // auf ein Tier ohne Reaktion: keine Vorführungs-Zählung
      this._vorfuehrTipp(p);
    },
    _leer(z) {
      if (!z || !z.closest) return false;
      if (z.closest('.natur-ebene')) return true;
      return z.id === 'tisch' || z.id === 'buehne' || z.classList.contains('buehne') || !!z.closest('.himmel') || !!z.closest('.richtung');
    },
    _hulle(c) { try { return c.inst.hulle ? c.inst.hulle(c.t) : null; } catch (e) { return null; } },
    _trifft(c, h, p) {
      if (c.inst.treffer) { try { return !!c.inst.treffer(p); } catch (e) { return false; } }
      const r = Math.max(Z.treffer_min_r, Math.max(h.w, h.h) / 2);
      return Math.hypot(p.x - (h.x + h.w / 2), p.y - (h.y + h.h / 2)) <= r;
    },
    // 7 Tipps in 4 s auf eine freie Stelle (höchstens 80 px auseinander) schalten die Vorführung ein bzw. aus
    _vorfuehrTipp(p) {
      const j = this.uhr();
      this._tipps = this._tipps.filter(x => j - x.at <= Z.vorfuehr_fenster_s && Math.hypot(x.x - p.x, x.y - p.y) <= 80);
      this._tipps.push({ x: p.x, y: p.y, at: j });
      if (this._tipps.length >= Z.vorfuehr_tipps) { this._tipps = []; this._demoSchalten(); }
    },

    /* ---------- Orte und Schutzflächen (2.2 / 2.3) ---------- */
    _rb(r) {
      const t = this.app.tisch, a = t.zuBuehne(r.left, r.top), b = t.zuBuehne(r.right, r.bottom);
      return { x: a.x, y: a.y, w: b.x - a.x, h: b.y - a.y };
    },
    _rect(e) {
      if (!e || e.hidden) return null;
      const r = e.getBoundingClientRect();
      return r.width > 0 && r.height > 0 ? this._rb(r) : null;
    },
    // Hülle eines Elements und seiner Kinder (gedrehte Fächerkarten ragen über das Element hinaus)
    _huelle(e) {
      if (!e || e.hidden) return null;
      let l = 1e9, o = 1e9, r = -1e9, u = -1e9;
      [e].concat(Array.from(e.children)).forEach(k => { const q = k.getBoundingClientRect(); if (q.width > 0 && q.height > 0) { l = Math.min(l, q.left); o = Math.min(o, q.top); r = Math.max(r, q.right); u = Math.max(u, q.bottom); } });
      return r > l ? this._rb({ left: l, top: o, right: r, bottom: u }) : null;
    },
    _handRect() {
      const t = this.app.tisch;
      let l = 1e9, o = 1e9, r = -1e9, u = -1e9;
      t.root.querySelectorAll('.hk').forEach(k => {
        if (k.style.visibility === 'hidden') return;
        const q = this._rect(k);
        if (!q) return;
        l = Math.min(l, q.x); o = Math.min(o, q.y); r = Math.max(r, q.x + q.w); u = Math.max(u, q.y + q.h);
      });
      if (r <= l) return null;
      o = Math.max(o, 0); u = Math.min(u, t.H); l = Math.max(l, 0); r = Math.min(r, t.W);
      return u > o && r > l ? { x: l, y: o, w: r - l, h: u - o } : null;
    },
    _schutz() {
      const t = this.app.tisch, out = [];
      const add = (name, r, rand) => { if (r) out.push({ name, x: r.x - (rand || 0), y: r.y - (rand || 0), w: r.w + 2 * (rand || 0), h: r.h + 2 * (rand || 0) }); };
      const hand = this._handRect();
      add('hand', hand);
      add('stapel', this._rect(t.stapel), 12);
      if (t.g && t.g.ablage) {
        const fr = this._rect(t.farbring);
        const R = (fr ? fr.w / 2 : 118) + 8;
        add('ablage', { x: t.g.ablage.x - R, y: t.g.ablage.y - R, w: 2 * R, h: 2 * R });
      }
      t.root.querySelectorAll('.gg:not(.aus)').forEach(g => {
        add('platz', this._rect(g.querySelector('.kopf')));
        add('platz', this._huelle(g.querySelector('.faecher')));   // Fächer: Hülle der gedrehten Karten (breiter als das Element)
        const bz = g.classList.contains('fangbar') ? this._rect(g.querySelector('.erwischen')) : null;
        add('erwischt', bz);
      });
      add('name', this._rect(t.ichZahl));
      add('leiste', this._rect(t.leiste));
      add('sortieren', this._rect(t.knSort));
      add('rueckseiten', this._rect(t.knRueck));
      add('mau', this._rect(t.knMau));
      add('menue', this._rect(t.knMenue));
      add('ton', this._rect(t.knTon));
      add('automat', this._rect(t.automat));
      add('einsatz', this._rect(t.einsatz));
      add('farbe', this._rect(t.farbe), 8);              // Wunschfarbe in der Tischmitte
      add('stapelzahl', this._rect(t.stapelZahl), 4);
      return out;
    },
    _plaetze() {
      const t = this.app.tisch, v = t.v || {}, out = [];
      t.root.querySelectorAll('.gg:not(.aus)').forEach(g => {
        const r = this._rect(g.querySelector('.kopf')) || this._rect(g);
        if (r) out.push({ seat: +g.dataset.seat, x: r.x + r.w / 2, y: r.y + r.h / 2, w: r.w, h: r.h, ich: +g.dataset.seat === v.seat });
      });
      const ich = this._rect(t.ichZahl);
      if (ich && !out.some(p => p.ich)) out.push({ seat: v.seat, x: ich.x + ich.w / 2, y: ich.y + ich.h / 2, w: ich.w, h: ich.h, ich: true });
      return out;
    },
    _ctx(e, seed, L, o) {
      const t = this.app.tisch, v = t.v || {};
      const schutz = this._schutz(), plaetze = this._plaetze();
      const orte = this._orte(mulberry32((seed ^ 0x9E3779B9) >>> 0), schutz, plaetze, o.troedler);
      const ich = typeof v.seat === 'number' ? v.seat : -1;
      return {
        id: e.id, eintrag: e, W: t.W, H: t.H, s: t.s, cx: t.g.cx, cy: t.g.cy,
        seite: e.seite, nacht: L.seite === 'nacht', reduziert: L.reduziert, ruhig: L.reduziert && e.ruhig, zeiten: Z, form: e.form || null,
        ort: orte[e.ort], orte, band: orte._band, ring: orte._ring, plaetze, schutz,
        frei: r => schutz.reduce((s, q) => s + flaeche(r, q), 0),
        hand: () => this._handkarte(),
        troedler: typeof o.troedler === 'number' && o.troedler >= 0 ? o.troedler : (typeof v.turn === 'number' ? v.turn : ich),
        meinPlatz: ich, demo: o.anlass === 'demo',
      };
    },
    // mittlere sichtbare Handkarte (Bühnen-px, y = Mitte), null ohne Hand
    _handkarte() {
      const t = this.app && this.app.tisch;
      if (!t || !t.hand || !t.hand.reihe.length) return null;
      // Mitte liegt meist unter dem Bildrand (nur der obere Teil der Karten ist zu sehen, AGENTS 8): sichtbar = Oberkante im Bild
      const sicht = t.hand.reihe.filter(k => { const p = t.hand.position(k.id); return p && p.x > 0 && p.x < t.W && p.y - p.w * KH / KW / 2 < t.H - 20; });
      if (!sicht.length) return null;
      const k = sicht[Math.floor((sicht.length - 1) / 2)];
      const p = t.hand.position(k.id), h = p.w * KH / KW;
      return { id: k.id, x: p.x, y: p.y, w: p.w, h, top: p.y - h / 2, rot: p.rot || 0 };
    },
    _orte(z, schutz, plaetze, troedler) {
      const t = this.app.tisch, W = t.W, H = t.H, g = t.g, cx = g.cx, cy = g.cy, v = t.v || {};
      const fx = Math.min(330, W * 0.21) / 330;
      const ring = { cx, cy: cy + 6, rx: Math.max(372 * fx, 326) + 33 * Math.min(fx, 1), ry: 159 };
      const band = (grad, quer) => { const p = bandPunkt(W, grad, quer); return { x: cx + p[0], y: cy + p[1] }; };
      const winkel = p => ((Math.atan2((p.y - ring.cy) / ring.ry, (p.x - ring.cx) / ring.rx) * 180 / Math.PI) + 360) % 360;
      const fremd = plaetze.filter(p => !p.ich);
      const freiheit = p => {
        let d = 1e9;
        plaetze.forEach(q => { d = Math.min(d, Math.hypot(p.x - q.x, p.y - q.y) - Math.max(q.w, q.h) / 2); });
        schutz.forEach(q => { if (q.name !== 'hand') d = Math.min(d, abstandRect(p, q) + 40); });
        return d;
      };
      // freiester Winkel in den Bereichen (5°-Schritte, kleiner Zufall gegen immer denselben Platz)
      const besterWinkel = bereiche => {
        let best = bereiche[0][0], bw = -1e9;
        bereiche.forEach(([a, b]) => { for (let w = a; w <= b + 1e-6; w += 5) { const s = freiheit(band(w)) + z() * 12; if (s > bw) { bw = s; best = w; } } });
        return best;
      };
      const flaecheMit = (r, liste) => liste.reduce((s, q) => s + flaeche(r, q), 0);
      const R = x => ({ x: x.x, y: x.y, w: x.w, h: x.h });
      // Himmel
      const himmel = { x0: 0, x1: W, y0: 0.04 * H, y1: 0.30 * H };
      const himmelOben = { x0: 0, x1: W, y0: 0.02 * H, y1: 0.20 * H };
      const himmelFern = { x0: 0, x1: W, y0: 0.06 * H, y1: 0.18 * H };
      const himmelEl = t.himmel || t.root.querySelector('.himmel');
      const sonneEl = himmelEl && himmelEl.querySelector('.sonne'), mondEl = himmelEl && himmelEl.querySelector('.mond');
      let sonne = { x: 0.07 * W + 66, y: 0.03 * H + 66, r: 64 };
      const sr = sonneEl ? this._rect(sonneEl) : null;
      if (sr) sonne = { x: sr.x + sr.w / 2, y: sr.y + sr.h / 2, r: sonneEl.offsetWidth / t.s / 2 || 64 };
      let mond = { x: W * 0.93 - 52, y: 0.04 * H + 52, w: 104, h: 104, rot: -24 };
      const mr = mondEl ? this._rect(mondEl) : null;
      if (mr) { const mw = (mondEl.offsetWidth || 104 * t.s) / t.s, mh = (mondEl.offsetHeight || 104 * t.s) / t.s; mond = { x: mr.x + mr.w / 2, y: mr.y + mr.h / 2, w: mw, h: mh, rot: -24 }; }
      const knoepfe = schutz.filter(q => q.name === 'menue' || q.name === 'ton');
      const koepfe = plaetze.map(p => ({ x: p.x - p.w / 2, y: p.y - p.h / 2, w: p.w, h: p.h }));
      let frei = null, fk = Infinity;
      [0.18, 0.32, 0.50, 0.66].forEach(f => {
        const r = { x: f * W - 120, y: 0.02 * H + 4, w: 240, h: 160 };
        const m = { x: r.x + 120, y: r.y + 80 };
        const k = flaecheMit(r, koepfe) + (Math.hypot(m.x - mond.x, m.y - mond.y) < 200 ? 1e7 : 0) + (flaecheMit(r, knoepfe) > 0 ? 1e6 : 0);
        if (k < fk) { fk = k; frei = r; }
      });
      // Band
      const zielPlatz = typeof troedler === 'number' ? troedler : v.turn;
      const pz = plaetze.find(p => p.seat === zielPlatz);
      let zumPlatz = 115;
      if (pz && !pz.ich) { zumPlatz = winkel(pz); if (zumPlatz >= 66 && zumPlatz <= 114) zumPlatz = zumPlatz < 90 ? 65 : 115; }
      // Aufsteigend: der Spalt mit mehr Abstand zu den Plätzen
      const spalt = [[0.25, 0.40], [0.60, 0.75]].map(([a, b]) => ({ a, b, d: Math.min(1e9, ...fremd.map(p => Math.abs(p.x - (a + b) / 2 * W) + Math.abs(p.y - cy) * 0.5)) }));
      const sp = spalt[0].d >= spalt[1].d ? spalt[0] : spalt[1];
      const stapelR = this._rect(t.stapel);
      const stapelTop = stapelR ? stapelR.y : g.stapel.y - 92;
      const ringR = (() => { const fr = this._rect(t.farbring); return fr ? fr.w / 2 : 118; })();
      const hinweisY = H - 212;
      return {
        _band: band, _ring: ring,
        himmel, himmel_oben: himmelOben, himmel_fern: himmelFern, himmel_frei: R(frei),
        himmel_bogen: { cx, cy: cy + 40, r: 0.46 * W },
        sonne, mond,
        band_hinten: { grad: besterWinkel([[240, 300]]) },
        band_schulter: { grad: besterWinkel([[200, 215], [325, 340]]) },
        band_vorn_seite: { grad: besterWinkel([[115, 160], [20, 65]]) },
        band_zum_platz: { grad: zumPlatz, seat: zielPlatz },
        tisch_quer: { x0: 0, x1: W, y0: cy - ring.ry - 60, y1: cy - ring.ry + 20 },
        tisch_rund: { cx: ring.cx, cy: ring.cy, rx: ring.rx, ry: ring.ry, f0: 1.05, f1: 1.45, ymax: hinweisY - 40 },
        handkarte: this._handkarte(),
        stapel_oben: { x: g.stapel.x, y: stapelTop - 62, stapel: stapelR },
        ablage_ring: { x: g.ablage.x, y: g.ablage.y, R: ringR },
        aufsteigend: { x: (sp.a + z() * (sp.b - sp.a)) * W, y: cy, ziel_y: -80 },
      };
    },
  };

  M.Natur = N;
})(window.MMF = window.MMF || {});
