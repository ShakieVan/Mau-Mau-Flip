/* Mau-Mau Flip – Entwurf A "Papier & Neon"
 * Generator für Karten-SVGs, Logo, App-Symbol und Vorschauseiten.
 * Läuft im Browser (quelle/build.html), Ausgabe wird von quelle/build.sh in Dateien zerlegt.
 * Alles hier ist selbst gezeichnet (Vektor), keine fremden Bilder.
 */
'use strict';

/* ------------------------------------------------------------------ */
/* Schriften (Google Fonts, SIL Open Font License 1.1)                  */
/* ------------------------------------------------------------------ */
const FONT_CSS = 'https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wdth,wght@12..96,75..100,200..800&family=Fraunces:ital,opsz,wght,SOFT,WONK@0,9..144,100..900,0..100,0..1;1,9..144,100..900,0..100,0..1&display=block';
const F_CARD = "'Bricolage Grotesque', 'Archivo', 'Arial Narrow', sans-serif";
const F_BRAND = "'Fraunces', 'Georgia', serif";

/* ------------------------------------------------------------------ */
/* Palette                                                             */
/* ------------------------------------------------------------------ */
const INK = '#211B2C';        // Druckfarbe (warmes Aubergine-Schwarz)
const PAPER = '#F4EADA';      // Papier
const PAPER_D = '#E6D7BC';    // Papierkante
const CREAM = '#FFF7E8';      // Wert-Füllung hell
const NIGHT = '#0A0D20';      // Nachtgrund
const NIGHT_HI = '#161C3F';   // Nachtgrund oben
const MOON = '#F4F0FF';       // Mondlicht

const LIGHT = {
  rot:   { key: 'rot',   name: 'Rot',   hex: '#B3202A', deep: '#86161F', sym: 'flamme' },
  gelb:  { key: 'gelb',  name: 'Gelb',  hex: '#FFDD33', deep: '#E2A90E', sym: 'sonne' },
  gruen: { key: 'gruen', name: 'Grün',  hex: '#43B05C', deep: '#2C8543', sym: 'klee' },
  blau:  { key: 'blau',  name: 'Blau',  hex: '#2A5BD7', deep: '#1D3FA3', sym: 'kristall' },
};
const DARK = {
  pink:    { key: 'pink',    name: 'Pink',   hex: '#FF9ECF', neon: '#FFB3DC', sym: 'herz' },
  tuerkis: { key: 'tuerkis', name: 'Türkis', hex: '#00838F', neon: '#0B97A3', sym: 'welle' },
  orange:  { key: 'orange',  name: 'Orange', hex: '#FF6F00', neon: '#FF7F14', sym: 'laterne' },
  lila:    { key: 'lila',    name: 'Lila',   hex: '#4527A0', neon: '#5E3BD8', sym: 'stern' },
};
const SYM_NAMES = { flamme: 'Flamme', sonne: 'Sonne', klee: 'Kleeblatt', kristall: 'Kristall', herz: 'Herz', welle: 'Welle', laterne: 'Laterne', stern: 'Stern' };

/* ------------------------------------------------------------------ */
/* Farb-Hilfen                                                         */
/* ------------------------------------------------------------------ */
function hexToRgb(h) { h = h.replace('#', ''); return [0, 2, 4].map(i => parseInt(h.substr(i, 2), 16)); }
function rgbToHex(c) { return '#' + c.map(v => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0')).join('').toUpperCase(); }
function mix(a, b, t) { const A = hexToRgb(a), B = hexToRgb(b); return rgbToHex(A.map((v, i) => v + (B[i] - v) * t)); }
function lin(c) { c /= 255; return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); }
function oklabLin([r, g, b]) {
  const l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b;
  const m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b;
  const s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b;
  const l_ = Math.cbrt(l), m_ = Math.cbrt(m), s_ = Math.cbrt(s);
  return [0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
          1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
          0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_];
}
// Machado et al. 2009, Schweregrad 1.0 (lineares RGB)
const CVD = {
  normal: null,
  protan: [[0.152286, 1.052583, -0.204868], [0.114503, 0.786281, 0.099216], [-0.003882, -0.048116, 1.051998]],
  deutan: [[0.367322, 0.860646, -0.227968], [0.280085, 0.672501, 0.047413], [-0.011820, 0.042940, 0.968881]],
  tritan: [[1.255528, -0.076749, -0.178779], [-0.078411, 0.930809, 0.147602], [0.004733, 0.691367, 0.303900]],
};
function labOf(hex, kind) {
  let c = hexToRgb(hex).map(lin);
  const M = CVD[kind];
  if (M) c = M.map(row => Math.min(1, Math.max(0, row[0] * c[0] + row[1] * c[1] + row[2] * c[2])));
  return oklabLin(c);
}
function dist(a, b, kind) { const A = labOf(a, kind), B = labOf(b, kind); return Math.hypot(A[0] - B[0], A[1] - B[1], A[2] - B[2]); }
function minPair(hexes, names) {
  const res = {};
  for (const kind of Object.keys(CVD)) {
    let best = { d: 9 };
    for (let i = 0; i < hexes.length; i++) for (let j = i + 1; j < hexes.length; j++) {
      const d = dist(hexes[i], hexes[j], kind);
      if (d < best.d) best = { d, pair: names[i] + '–' + names[j] };
    }
    res[kind] = best;
  }
  return res;
}
function Lof(hex) { return oklabLin(hexToRgb(hex).map(lin))[0]; }

/* ------------------------------------------------------------------ */
/* Allgemeine Hilfen                                                   */
/* ------------------------------------------------------------------ */
const f1 = v => (Math.round(v * 10) / 10).toString();
function esc(s) { return String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;'); }
// Nicht-ASCII als numerische Zeichenreferenz (robust gegen Kodierungsprobleme)
function asciiSafe(s) { return s.replace(/[^\x00-\x7F]/g, ch => '&#x' + ch.codePointAt(0).toString(16).toUpperCase() + ';'); }
function polar(cx, cy, r, deg) { const a = (deg - 90) * Math.PI / 180; return [cx + r * Math.cos(a), cy + r * Math.sin(a)]; }
function starPath(cx, cy, n, ro, ri, rot = 0) {
  let d = '';
  for (let i = 0; i < n * 2; i++) {
    const [x, y] = polar(cx, cy, i % 2 ? ri : ro, rot + i * 180 / n);
    d += (i ? 'L' : 'M') + f1(x) + ' ' + f1(y);
  }
  return d + 'Z';
}
function sparkle(cx, cy, r, k = 0.22) { // vierzackiger Funkel
  const q = r * k;
  return `M${f1(cx)} ${f1(cy - r)} C${f1(cx + q * 0.3)} ${f1(cy - q)} ${f1(cx + q)} ${f1(cy - q * 0.3)} ${f1(cx + r)} ${f1(cy)} C${f1(cx + q)} ${f1(cy + q * 0.3)} ${f1(cx + q * 0.3)} ${f1(cy + q)} ${f1(cx)} ${f1(cy + r)} C${f1(cx - q * 0.3)} ${f1(cy + q)} ${f1(cx - q)} ${f1(cy + q * 0.3)} ${f1(cx - r)} ${f1(cy)} C${f1(cx - q)} ${f1(cy - q * 0.3)} ${f1(cx - q * 0.3)} ${f1(cy - q)} ${f1(cx)} ${f1(cy - r)}Z`;
}
// deterministischer Zufall
function rng(seed) { let s = seed >>> 0; return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; }; }

/* ------------------------------------------------------------------ */
/* Farbsymbole (Box 100×100)                                            */
/* Rückgabe: Liste von Primitiven {d, kind:'fill'|'line', w, role}      */
/* role: main (Farbe), cut (Aussparung/Detail)                          */
/* ------------------------------------------------------------------ */
function symbolPrims(name) {
  switch (name) {
    case 'flamme': return [
      { d: 'M50 3C59 19 81 33 81 61C81 83 66 97 50 97C34 97 19 83 19 61C19 46 27 36 36 28C36 40 40 48 47 51C43 37 43 19 50 3Z', role: 'main' },
      { d: 'M51 55C57 63 63 69 63 78C63 87 57 92 50 92C43 92 38 87 38 79C38 71 44 64 51 55Z', role: 'cut' },
    ];
    case 'sonne': {
      const p = [{ d: 'M50 29a21 21 0 1 0 0.01 0Z', role: 'main' }];
      let d = '';
      for (let i = 0; i < 8; i++) {
        const a = i * 45;
        const [x1, y1] = polar(50, 50, 30, a - 9), [x2, y2] = polar(50, 50, 30, a + 9), [x3, y3] = polar(50, 50, 48, a);
        d += `M${f1(x1)} ${f1(y1)}L${f1(x3)} ${f1(y3)}L${f1(x2)} ${f1(y2)}Z`;
      }
      p.push({ d, role: 'main' });
      return p;
    }
    case 'klee': {
      const heart = 'M0 0C-7 -6 -25 -14 -25 -29C-25 -39 -17 -45 -9 -45C-4 -45 0 -41 0 -36C0 -41 4 -45 9 -45C17 -45 25 -39 25 -29C25 -14 7 -6 0 0Z';
      return [
        { d: 'M50 54C52 70 58 82 70 95', kind: 'line', w: 8, role: 'main' },
        ...[0, 120, 240].map(a => ({ d: heart, tf: `translate(50 52) rotate(${a})`, role: 'main' })),
      ];
    }
    case 'kristall': return [
      { d: 'M28 13H72L93 38L50 95L7 38Z', role: 'main' },
      { d: 'M7 38H93M28 13L39 38L50 95M72 13L61 38L50 95M39 38L50 13L61 38', kind: 'line', w: 3.2, role: 'cut' },
    ];
    case 'herz': return [
      { d: 'M50 91C43 85 7 63 7 36C7 20 19 9 32 9C40 9 46 13 50 21C54 13 60 9 68 9C81 9 93 20 93 36C93 63 57 85 50 91Z', role: 'main' },
    ];
    case 'welle': return [
      { d: 'M8 36C19 20 30 20 39 34C48 48 59 48 70 34C79 22 88 22 94 30', kind: 'line', w: 13, role: 'main' },
      { d: 'M8 68C19 52 30 52 39 66C48 80 59 80 70 66C79 54 88 54 94 62', kind: 'line', w: 13, role: 'main' },
    ];
    case 'laterne': return [
      { d: 'M50 4a9 9 0 1 1 -0.01 0Z', kind: 'line', w: 6, role: 'main' },
      { d: 'M33 20H67V31H33Z', role: 'main' },
      { d: 'M31 31H69L84 55L69 82H31L16 55Z', role: 'main' },
      { d: 'M36 82H64V93H36Z', role: 'main' },
      { d: 'M50 42C55 50 59 55 59 61C59 67 55 71 50 71C45 71 41 67 41 61C41 55 45 50 50 42Z', role: 'cut' },
    ];
    case 'stern': return [
      { d: starPath(50, 54, 5, 46, 20), role: 'main', join: 6 },
    ];
  }
  return [];
}

/* ------------------------------------------------------------------ */
/* Aktions-Piktogramme (Box 100×100)                                    */
/* ------------------------------------------------------------------ */
const CAT_HEAD = 'M13 62C13 49 16 41 21 35L23 9C23 6 26 5 28 7L44 25C48 24 52 24 56 25L72 7C74 5 77 6 77 9L79 35C84 41 87 49 87 62C87 82 71 94 50 94C29 94 13 82 13 62Z';
function catHeadPrims(tf = '', sleeping = true) {
  const p = [{ d: CAT_HEAD, role: 'main', tf }];
  if (sleeping) {
    p.push({ d: 'M26 60Q33 67 41 60M59 60Q67 67 74 60', kind: 'line', w: 5.5, role: 'cut', tf });
  } else {
    p.push({ d: 'M27 56a7 8 0 1 0 14 0a7 8 0 1 0 -14 0ZM59 56a7 8 0 1 0 14 0a7 8 0 1 0 -14 0Z', role: 'cut', tf });
  }
  p.push({ d: 'M45 69H55L50 75Z', role: 'cut', tf });
  return p;
}
function arcArrow(cx, cy, r, a0, a1, w, head) {
  // Bogen von a0 nach a1 (Grad, im Uhrzeigersinn) mit Pfeilspitze am Ende
  const back = (head * 0.9) / (r) * 180 / Math.PI;
  const aEnd = a1 - back;
  const [x0, y0] = polar(cx, cy, r, a0), [x1, y1] = polar(cx, cy, r, aEnd);
  const large = (aEnd - a0) > 180 ? 1 : 0;
  const arcD = `M${f1(x0)} ${f1(y0)}A${r} ${r} 0 ${large} 1 ${f1(x1)} ${f1(y1)}`;
  const shaft = { d: arcD, kind: 'line', w, role: 'main', cap: 'butt' };
  const stripe = { d: arcD, kind: 'line', w: w - 1, role: 'stripe', cap: 'butt', dash: '6 9', dashOff: 2 };
  const [hx, hy] = polar(cx, cy, r, a1 + 2);           // Spitze
  const [ox, oy] = polar(cx, cy, r + head * 0.85, aEnd); // außen
  const [ix, iy] = polar(cx, cy, r - head * 0.85, aEnd); // innen
  const tip = { d: `M${f1(ox)} ${f1(oy)}L${f1(hx)} ${f1(hy)}L${f1(ix)} ${f1(iy)}Z`, role: 'main', join: 3 };
  return [shaft, stripe, tip];
}
function iconPrims(name, opt = {}) {
  switch (name) {
    case 'schlaf': return catHeadPrims('', true);
    case 'schlaf3': return [
      ...catHeadPrims('translate(-2 2) scale(.56)', true),
      ...catHeadPrims('translate(46 2) scale(.56)', true),
      ...catHeadPrims('translate(22 42) scale(.58)', true).map(q => ({ ...q, front: true })),
    ];
    case 'wende': return [
      ...arcArrow(50, 50, 33, 236, 30, 12, 17),
      ...arcArrow(50, 50, 33, 56, 210, 12, 17),
    ];
    case 'flip': return [
      { d: 'M50 6a44 44 0 1 0 0.01 0Z', role: 'main' },
      { d: 'M81.1 18.9A44 44 0 0 1 18.9 81.1Z', role: 'dark' },
      { d: 'M50 6a44 44 0 1 0 0.01 0Z', kind: 'line', w: 6, role: 'ring' },
      // Mond in der Nachthälfte, Sonne in der Taghälfte
      { d: 'M74 50a15 15 0 1 1 -16 22a12 12 0 1 0 16 -22Z', role: 'cut' },
      { d: 'M36 39a9 9 0 1 0 0.01 0Z', role: 'sun' },
    ];
    case 'pfote': return [
      { d: 'M50 50C64 50 80 64 80 78C80 89 72 94 64 94C57 94 54 90 50 90C46 90 43 94 36 94C28 94 20 89 20 78C20 64 36 50 50 50Z', role: 'main' },
      { d: 'M12 40a10 13 -20 1 0 20 -6a10 13 -20 1 0 -20 6Z', role: 'toe1' },
      { d: 'M30 20a11 14 -6 1 0 22 0a11 14 -6 1 0 -22 0Z', role: 'toe2' },
      { d: 'M48 20a11 14 6 1 0 22 0a11 14 6 1 0 -22 0Z', role: 'toe3' },
      { d: 'M68 34a10 13 20 1 0 20 6a10 13 20 1 0 -20 -6Z', role: 'toe4' },
    ];
    case 'tausch': return tauschPrims();
    case 'gluecks': return gluecksPrims(opt);
    case 'ablegen': return ablegenPrims(opt);
    case 'frage': return [];
  }
  return [];
}

/* Kartentausch (Hausregel swap_cards, nicht im Entwurf): drei aufrechte Karten im Dreieck wie drei Plätze am Tisch,
 * dazwischen drei kräftige Bogenpfeile im Uhrzeigersinn – jeder gibt seine Hand an den nächsten Platz weiter.
 * Unterscheidbar vom Richtungswechsel (zwei gestreifte Bogenpfeile ohne Inhalt) und vom Flip (geteilte Scheibe).
 * Die Karten tragen einen Trennrand (front, ringW 6) in Grund- bzw. Konturfarbe, damit sie sich klein von den Pfeilen lösen.
 * Rolle panel: Innenfeld der kleinen Karten (groß: tiefe Kartenfarbe; im Eckindex nicht gesetzt, also voll in der Wertfarbe). */
function rrPath(x, y, w, h, r) {
  return `M${f1(x + r)} ${f1(y)}H${f1(x + w - r)}A${f1(r)} ${f1(r)} 0 0 1 ${f1(x + w)} ${f1(y + r)}V${f1(y + h - r)}A${f1(r)} ${f1(r)} 0 0 1 ${f1(x + w - r)} ${f1(y + h)}` +
    `H${f1(x + r)}A${f1(r)} ${f1(r)} 0 0 1 ${f1(x)} ${f1(y + h - r)}V${f1(y + r)}A${f1(r)} ${f1(r)} 0 0 1 ${f1(x + r)} ${f1(y)}Z`;
}
function tauschPrims() {
  const C = { x: 50, y: 53 }, RK = 30, RP = 36, KW = 23, KH = 32;
  const kipp = { 0: 0, 120: 14, 240: -14 };                 // obere Karte gerade, untere leicht nach außen gekippt
  const p = [];
  for (const a of [0, 120, 240]) p.push(...arcArrow(C.x, C.y, RP, a + 26, a + 96, 12, 19).filter(q => q.role !== 'stripe'));
  for (const a of [0, 120, 240]) {
    const [x, y] = polar(C.x, C.y, RK, a);
    const tf = `rotate(${kipp[a]} ${f1(x)} ${f1(y)})`, i = KW * 0.17;
    p.push({ d: rrPath(x - KW / 2, y - KH / 2, KW, KH, KW * 0.18), tf, role: 'main', front: true, ringW: 6 });
    p.push({ d: rrPath(x - KW / 2 + i, y - KH / 2 + i, KW - 2 * i, KH - 2 * i, KW * 0.09), tf, role: 'panel' });
  }
  return p;
}

/* Glücksspiel (Hausregel gamble_cards, nicht im Entwurf): ein großer runder Glücksspielknopf (Buzzer) mit Fragezeichen auf einem
 * flachen Sockel, vorn ein kleines Zahlenwerk „0–10“ zwischen vier Lampen in den Farben der Seite, daneben zwei Glücksfunkel.
 * Rollen: main Sockel und Funkel, dome Knopf, shine Glanz, qmark Fragezeichen (kind text), edge Vorderkante der Sockelplatte,
 * display Zahlenfenster, digits Ziffern (kind text), toe1–4 Lampen. Im Eckindex (opt.index) ohne Zahlenwerk und Lampen. */
function gluecksPrims(opt = {}) {
  const ix = !!opt.index;
  // Geometrie im 100er-Feld: Sockel (PX0, PT oben, PB unten, PRY Ellipsenhöhe), Kuppel (DX0, DT oben, DRY), Fragezeichen Q, Funkel F [x, y, r]
  const G = ix ? { PX0: 6, PT: 64, PB: 84, PRY: 10, DX0: 17, DT: 27, DRY: 8, Q: 36, F: [[13, 20, 12], [88, 15, 9]] }
    : { PX0: 6, PT: 62, PB: 85, PRY: 11, DX0: 19, DT: 30, DRY: 8, Q: 31, F: [[14, 24, 10], [86, 16, 7.5], [91, 36, 4.5]] };
  const p = [];
  const PX1 = 100 - G.PX0, PRX = 50 - G.PX0, PT = G.PT, PB = G.PB;
  for (const [x, y, r] of G.F) p.push({ d: sparkle(x, y, r, 0.26), role: 'main', join: 2 });   // Glücksfunkel
  // Sockel: flacher Zylinder mit Deckplatte (Ellipse) und Seitenband
  p.push({ d: `M${G.PX0} ${PT}A${PRX} ${G.PRY} 0 0 1 ${PX1} ${PT}V${PB}A${PRX} ${G.PRY} 0 0 1 ${G.PX0} ${PB}Z`, role: 'main' });
  p.push({ d: `M${G.PX0} ${PT}A${PRX} ${G.PRY} 0 0 0 ${PX1} ${PT}`, kind: 'line', w: ix ? 4 : 3, role: 'edge' });
  // Knopf: flache Kuppel auf der Deckplatte
  const DX0 = G.DX0, DX1 = 100 - DX0, DY = PT - 2, DT = G.DT, DRX = (DX1 - DX0) / 2;
  p.push({ d: `M${DX0} ${DY}C${DX0} ${DT + 8} ${DX0 + 12} ${DT} 50 ${DT}C${DX1 - 12} ${DT} ${DX1} ${DT + 8} ${DX1} ${DY}A${DRX} ${G.DRY} 0 0 1 ${DX0} ${DY}Z`, role: 'dome' });
  // Glanz oben links auf dem Knopf, Fragezeichen in der Mitte (Ausgang ungewiss)
  p.push({ d: `M${DX0 + 7} ${DY - 6}C${DX0 + 7} ${DT + 11} ${DX0 + 15} ${DT + 5} ${DX0 + 24} ${DT + 4}C${DX0 + 17} ${DT + 8} ${DX0 + 12} ${DT + 14} ${DX0 + 12} ${DY - 6}Z`, role: 'shine' });
  p.push({ kind: 'text', txt: '?', x: 52, y: DY - 3, size: G.Q, role: 'qmark' });
  if (!ix) {
    // Zahlenwerk vorn auf dem Sockel, links und rechts je zwei Lampen
    const DT2 = PT + 9;
    p.push({ d: rrPath(32, DT2, 36, 13.5, 3.5), role: 'display' });
    p.push({ kind: 'text', txt: '0–10', x: 50, y: DT2 + 10.6, size: 12, role: 'digits' });
    const lamp = (x, y) => `M${f1(x - 3.8)} ${f1(y)}a3.8 3.8 0 1 0 7.6 0a3.8 3.8 0 1 0 -7.6 0Z`;
    [[13.5, PT + 12.5], [23.5, PT + 15.5], [76.5, PT + 15.5], [86.5, PT + 12.5]].forEach(([x, y], i) => p.push({ d: lamp(x, y), role: 'toe' + (i + 1) }));
  }
  return p;
}

/* Farbe mit ablegen (Hausregel discard_color, nicht im Entwurf): oben ein flacher Handfächer, aus dem die Karten der einen Farbe
 * nach unten herausrutschen (Lücke im Fächer mit Bewegungsstrichen), darunter ein kräftiger Pfeil nach unten auf den Ablagestapel.
 * Unterscheidbar von +1/+5 (drei große Karten hinter der Zahl), Kartentausch (drei Karten im Kreis mit Bogenpfeilen),
 * Richtungswechsel (zwei gestreifte Bogenpfeile) und Flip (geteilte Scheibe).
 * Rollen: main abrutschende Karten und Pfeil, ncard/npanel die übrigen Handkarten (neutral), panel Innenfeld der abrutschenden Karten,
 * cardsym deren Farbsymbol (opt.sym), speed Bewegungsstriche. Beim Joker (opt.joker) statt Innenfeld und Symbol vier Farbstreifen
 * toe1–4. Alle Karten tragen einen Trennrand (front). Im Eckindex (opt.index) drei Karten, die mittlere rutscht, ohne Farbsymbole. */
function ablegenCard(p, opt, x, y, KW, KH, tf, colored) {
  const i = KW * 0.16;
  p.push({ d: rrPath(x, y, KW, KH, KW * 0.17), tf, role: colored ? 'main' : 'ncard', front: true, ringW: 6 });
  if (!colored) { p.push({ d: rrPath(x + i, y + i, KW - 2 * i, KH - 2 * i, KW * 0.08), tf, role: 'npanel' }); return; }
  if (opt.joker) {
    const hx = x + i, hy = y + i, hw = KW - 2 * i, hh = (KH - 2 * i) / 4;
    for (let k = 0; k < 4; k++) p.push({ d: rrPath(hx, hy + k * hh, hw, hh + (k < 3 ? 0.4 : 0), k === 0 || k === 3 ? KW * 0.06 : 0.01), tf, role: 'toe' + (k + 1) });
    return;
  }
  p.push({ d: rrPath(x + i, y + i, KW - 2 * i, KH - 2 * i, KW * 0.08), tf, role: 'panel' });
  if (opt.sym && !opt.index) {
    const s = KW * 0.62, cx = x + KW / 2, cy = y + KH / 2;
    for (const q of symbolPrims(opt.sym)) p.push({ ...q, tf: `${tf} translate(${f1(cx - s / 2)} ${f1(cy - s / 2)}) scale(${(s / 100).toFixed(4)})${q.tf ? ' ' + q.tf : ''}`, role: q.role === 'cut' ? 'panel' : 'cardsym' });
  }
}
function ablegenPrims(opt = {}) {
  const ix = !!opt.index, p = [];
  // Fächer aus n Karten (KW × KH, Winkelschritt step) um den Drehpunkt (50, PVY), Oberkante TOP; die Karten drop rutschen um DROP
  // nach unten. Pfeil: Schaft AT–AM (halbe Breite AW), Spitze bis AB (halbe Breite HW).
  const G = ix ? { n: 3, step: 22, KW: 25, KH: 33, PVY: 112, TOP: 2, DROP: 22, drop: [1], AT: 60, AM: 74, AB: 96, AW: 7, HW: 17 }
    : { n: 5, step: 13, KW: 21, KH: 30, PVY: 116, TOP: 3, DROP: 26, drop: [1, 3], AT: 69, AM: 81, AB: 97, AW: 6, HW: 14 };
  const tfOf = a => `rotate(${a} 50 ${G.PVY})`;
  const angs = [...Array(G.n)].map((_, k) => (k - (G.n - 1) / 2) * G.step);
  angs.forEach((a, k) => { if (!G.drop.includes(k)) ablegenCard(p, opt, 50 - G.KW / 2, G.TOP, G.KW, G.KH, tfOf(a), false); });
  if (!ix) for (const k of G.drop) p.push({ d: `M${f1(50 - G.KW * 0.2)} ${G.TOP + 5}V${G.TOP + G.DROP - 3}M${f1(50 + G.KW * 0.2)} ${G.TOP + 10}V${G.TOP + G.DROP - 3}`, tf: tfOf(angs[k]), kind: 'line', w: 3.5, role: 'speed', nosil: true });
  for (const k of G.drop) ablegenCard(p, opt, 50 - G.KW / 2, G.TOP + G.DROP, G.KW, G.KH, tfOf(angs[k]), true);
  p.push({ d: `M${50 - G.AW} ${G.AT}H${50 + G.AW}V${G.AM}H${50 + G.HW}L50 ${G.AB}L${50 - G.HW} ${G.AM}H${50 - G.AW}Z`, role: 'main', join: 3 });
  return p;
}

/* Rendert Primitive. colors: {main, cut, dark, sun, toe1..4}; mode 'sil' = Kontur-Silhouette */
function renderPrims(prims, colors, mode = 'fill', outline = 0) {
  let out = '';
  for (const p of prims) {
    if (p.role === 'none') continue;
    if (p.kind === 'text') {   // Schrift im Symbol (Glücksspiel-Zahlenwerk), nicht in der Silhouette
      if (mode !== 'sil') out += valueText({ x: p.x, y: p.y, size: p.size, txt: p.txt, fill: colors[p.role] || colors.main, stretch: 75, extra: p.tf ? ` transform="${p.tf}"` : '' });
      continue;
    }
    if (p.nosil && mode === 'sil') continue;   // ohne Kontur (Bewegungsstriche)
    if (p.role === 'stripe' && (mode === 'sil' || !colors.stripe)) continue;
    if (p.role === 'ring' && (mode === 'sil' || !colors.ring)) continue;
    const tf = p.tf ? ` transform="${p.tf}"` : '';
    if (mode === 'sil') {
      if (p.role === 'cut' || p.role === 'sun') continue;
      const col = colors.sil;
      if (p.kind === 'line') out += `<path d="${p.d}"${tf} fill="none" stroke="${col}" stroke-width="${p.w + outline * 2}" stroke-linecap="${p.cap || 'round'}" stroke-linejoin="round"/>`;
      else out += `<path d="${p.d}"${tf} fill="${col}" stroke="${col}" stroke-width="${outline * 2 + (p.join || 0)}" stroke-linejoin="round"/>`;
      continue;
    }
    let col = colors[p.role] || colors.main;
    if (p.front && colors.frontRing) {
      // vordere Figur mit Trennrand
      out += `<path d="${p.d}"${tf} fill="none" stroke="${colors.frontRing}" stroke-width="${p.kind === 'line' ? 0 : (p.ringW || 9)}" stroke-linejoin="round"/>`;
    }
    if (p.kind === 'line') out += `<path d="${p.d}"${tf} fill="none" stroke="${col}" stroke-width="${p.w}" stroke-linecap="${p.cap || 'round'}" stroke-linejoin="round"${p.dash ? ` stroke-dasharray="${p.dash}" stroke-dashoffset="${p.dashOff || 0}"` : ''}/>`;
    else if (p.join) out += `<path d="${p.d}"${tf} fill="${col}" stroke="${col}" stroke-width="${p.join}" stroke-linejoin="round"/>`;
    else out += `<path d="${p.d}"${tf} fill="${col}"/>`;
  }
  return out;
}
/* Box 100×100 an Position (cx, cy) mit Größe s */
function place(inner, cx, cy, s) {
  const k = s / 100;
  return `<g transform="translate(${f1(cx - s / 2)} ${f1(cy - s / 2)}) scale(${k.toFixed(4)})">${inner}</g>`;
}

/* ------------------------------------------------------------------ */
/* Kartengeometrie                                                     */
/* ------------------------------------------------------------------ */
const CW = 560, CH = 870, CR = 40;
const PX0 = 26, PY0 = 26, PX1 = 534, PY1 = 844;   // Farbfeld
const XA = 158, YA = 300;                           // Ecklasche oben links (Papier)
const XB = CW - XA, YB = CH - YA;                   // Ecklasche unten rechts
const PR = 26, PRC = 34;
const SUN = { x: 280, y: 452, r: 150 }, HORIZON = 604;

function panelPath(d = 0) {
  const x0 = PX0 + d, y0 = PY0 + d, x1 = PX1 - d, y1 = PY1 - d;
  const xa = XA + d, ya = YA + d, xb = XB - d, yb = YB - d;
  const r = Math.max(4, PR - d), rc = PRC + d;
  return `M${xa + r} ${y0}H${x1 - r}A${r} ${r} 0 0 1 ${x1} ${y0 + r}V${yb - r}A${r} ${r} 0 0 1 ${x1 - r} ${yb}H${xb + rc}A${rc} ${rc} 0 0 0 ${xb} ${yb + rc}V${y1 - r}A${r} ${r} 0 0 1 ${xb - r} ${y1}H${x0 + r}A${r} ${r} 0 0 1 ${x0} ${y1 - r}V${ya + r}A${r} ${r} 0 0 1 ${x0 + r} ${ya}H${xa - rc}A${rc} ${rc} 0 0 0 ${xa} ${ya - rc}V${y0 + r}A${r} ${r} 0 0 1 ${xa + r} ${y0}Z`;
}
const ROT180 = `rotate(180 ${CW / 2} ${CH / 2})`;

/* Kartenliste: type: num|zieh|aussetzen|alle|wende|flip|wunsch|wunsch2|jagd (nur Produktion, Hausregeln: tausch Kartentausch, gluecks Glücksspiel,
 * ablegen Farbe mit ablegen, ablegenj dessen Joker) */
const CARD_LIST = [
  { file: 'hell_rot_7', side: 'hell', color: 'rot', type: 'num', v: '7' },
  { file: 'hell_gelb_plus1', side: 'hell', color: 'gelb', type: 'zieh', v: '+1' },
  { file: 'hell_gruen_aussetzen', side: 'hell', color: 'gruen', type: 'aussetzen' },
  { file: 'hell_blau_richtungswechsel', side: 'hell', color: 'blau', type: 'wende' },
  { file: 'hell_rot_flip', side: 'hell', color: 'rot', type: 'flip' },
  { file: 'hell_wuenscher', side: 'hell', type: 'wunsch' },
  { file: 'hell_wuenscher_plus2', side: 'hell', type: 'wunsch2', v: '+2' },
  { file: 'hell_blau_9', side: 'hell', color: 'blau', type: 'num', v: '9' },
  { file: 'dunkel_tuerkis_7', side: 'dunkel', color: 'tuerkis', type: 'num', v: '7' },
  { file: 'dunkel_pink_plus5', side: 'dunkel', color: 'pink', type: 'zieh', v: '+5' },
  { file: 'dunkel_orange_alle_aussetzen', side: 'dunkel', color: 'orange', type: 'alle' },
  { file: 'dunkel_lila_richtungswechsel', side: 'dunkel', color: 'lila', type: 'wende' },
  { file: 'dunkel_pink_flip', side: 'dunkel', color: 'pink', type: 'flip' },
  { file: 'dunkel_wuenscher', side: 'dunkel', type: 'wunsch' },
  { file: 'dunkel_farbjagd', side: 'dunkel', type: 'jagd', v: '?' },
  { file: 'dunkel_lila_6', side: 'dunkel', color: 'lila', type: 'num', v: '6' },
];
const TYPE_NAMES = { num: '', zieh: 'Zieh', aussetzen: 'Aussetzen', alle: 'Alle aussetzen', wende: 'Richtungswechsel', flip: 'Flip', wunsch: 'Wünscher', wunsch2: 'Wünscher +2', jagd: 'Farbjagd', tausch: 'Kartentausch',
  gluecks: 'Glücksspiel', ablegen: 'Farbe ablegen', ablegenj: 'Farbe ablegen (Joker)' };
/* Piktogramm je Kartentyp (Index und Mitte); gluecks, ablegen und ablegenj nur in der Produktion (Hausregeln, nicht im Entwurf) */
const ICON_OF = { aussetzen: 'schlaf', alle: 'schlaf3', wende: 'wende', flip: 'flip', wunsch: 'pfote', tausch: 'tausch', gluecks: 'gluecks', ablegen: 'ablegen', ablegenj: 'ablegen' };
// Zusatzangaben für die Piktogramme der Hausregel-Karten: Joker-Fassung und Farbsymbol der Karte (für die Karten im Ablegen-Fächer)
function iconOpt(c, index) {
  const sym = c.color ? (c.side === 'hell' ? LIGHT : DARK)[c.color].sym : null;
  return { index, joker: c.type === 'ablegenj', sym };
}
function cardTitle(c) {
  const side = c.side === 'hell' ? 'Helle Seite' : 'Dunkle Seite';
  const col = c.color ? (c.side === 'hell' ? LIGHT : DARK)[c.color].name + ' ' : '';
  const what = c.type === 'num' ? c.v : c.type === 'zieh' ? 'Zieh ' + c.v.replace('+', '') : TYPE_NAMES[c.type];
  return `${side}: ${col}${what}`;
}

/* ------------------------------------------------------------------ */
/* Bausteine Text                                                       */
/* ------------------------------------------------------------------ */
// Optische Größe fest auf 12: Bei automatischer Wahl (opsz 96 bei großen Werten) verjüngen sich 6 und 9 in der Mitte zu stark.
function valueText({ x, y, size, txt, fill, stroke, sw, stretch = 100, weight = 800, extra = '' }) {
  return `<text x="${x}" y="${y}" text-anchor="middle" font-family="${F_CARD}" font-weight="${weight}" font-size="${size}" style="font-stretch:${stretch}%;font-variation-settings:'opsz' 12" fill="${fill}"` +
    (stroke ? ` stroke="${stroke}" stroke-width="${sw}" stroke-linejoin="round" paint-order="stroke"` : '') + `${extra}>${esc(txt)}</text>`;
}

/* ------------------------------------------------------------------ */
/* Kartenseiten                                                        */
/* ------------------------------------------------------------------ */
function cardSVG(c, opt = {}) {
  const P = opt.prefix || '';
  const id = n => P + n;
  return c.side === 'hell' ? lightCard(c, P, id, opt) : darkCard(c, P, id, opt);
}

function svgOpen(P, title, opt) {
  const sz = opt.width ? ` width="${opt.width}" height="${f1(opt.width * CH / CW)}"` : ` width="${CW}" height="${CH}"`;
  const imp = opt.standalone ? `<style><![CDATA[@import url('${FONT_CSS}');]]></style>` : '';
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${CW} ${CH}"${sz}${opt.cls ? ` class="${opt.cls}"` : ''}>` +
    `<title>${esc(title)}</title>${imp}`;
}

/* ---- Index (Wert + Farbsymbol) ---- */
function indexContent(c, look) {
  // look: {valFill, valStroke, valSw, symColors, glow}
  const X = 86;
  if (c.type === 'motiv') {
    const prims = c.side === 'hell' ? symbolPrims('sonne') : [{ d: 'M60 8A44 44 0 1 0 92 70A36 36 0 1 1 60 8Z', role: 'main' }];
    return `<g${look.valGlow ? ` filter="url(#${look.valGlow})"` : ''}>` + place(renderPrims(prims, { main: look.valFill }), X, 136, 112) + '</g>';
  }
  let val = '';
  const glowAttr = look.valGlow ? ` filter="url(#${look.valGlow})"` : '';
  if (c.type === 'num' || c.type === 'zieh' || c.type === 'wunsch2' || c.type === 'jagd') {
    const txt = c.v;
    const two = txt.length > 1;
    const size = two ? 168 : 196;
    const base = two ? 178 : 190;
    val += `<g${glowAttr}>` + valueText({ x: X, y: base, size, txt, fill: look.valFill, stroke: look.valStroke, sw: look.valSw, stretch: 75 });
    if (txt === '6' || txt === '9') val += `<rect x="${X - 40}" y="${base + 12}" width="80" height="15" rx="7.5" fill="${look.valFill}"/>`;
    val += `</g>`;
  } else {
    const ic = ICON_OF[c.type];
    const prims = iconPrims(ic, iconOpt(c, true));
    val += `<g${glowAttr}>` + place(renderPrims(prims, look.iconColors(c)), X, 120, 118) + `</g>`;
  }
  // Farbsymbol bzw. Joker-Pfote
  let sym = '';
  const SY = c.type === 'num' && (c.v === '6' || c.v === '9') ? 258 : 252;
  if (c.color) {
    const prims = symbolPrims(look.symName(c));
    const sc = look.symColors(c);
    const inner = (sc.outline ? renderPrims(prims, { sil: sc.outline }, 'sil', sc.outlineW) : '') + renderPrims(prims, sc);
    sym = `<g${look.symGlow ? ` filter="url(#${look.symGlow})"` : ''}>` + place(inner, X, SY, 74) + '</g>';
  } else if (c.type !== 'wunsch') {
    const prims = iconPrims('pfote');
    sym = `<g${look.symGlow ? ` filter="url(#${look.symGlow})"` : ''}>` + place(renderPrims(prims, look.jokerPaw()), X, SY, 70) + '</g>';
  } else {
    // Joker: vier Farbpunkte unter der Pfote
    const cols = look.jokerDots();
    sym = cols.map((col, i) => `<circle cx="${X - 33 + i * 22}" cy="${SY - 4}" r="8.5" fill="${col}"${look.dotStroke ? ` stroke="${look.dotStroke}" stroke-width="2.5"` : ''}/>`).join('');
  }
  return val + sym;
}

/* ================== HELLE SEITE ================== */
function lightCard(c, P, id, opt) {
  const joker = !c.color;
  const col = joker ? null : LIGHT[c.color];
  const motif = c.type === 'motiv';
  const base = joker ? '#E9DCC4' : motif ? `url(#${id('abend')})` : col.hex;
  const deep = joker ? '#D9C8A8' : motif ? '#6E1424' : col.deep;
  const sunCol = joker ? CREAM : motif ? '#FFD447' : mix(col.hex, '#FFF4D6', c.color === 'gelb' ? 0.55 : 0.32);
  const SR = motif ? 178 : SUN.r;
  const rayCol = c.color === 'gelb' ? '#FFFFFF' : CREAM;
  let s = svgOpen(P, cardTitle(c), opt);
  s += `<defs>` +
    `<clipPath id="${id('karte')}"><rect width="${CW}" height="${CH}" rx="${CR}"/></clipPath>` +
    `<clipPath id="${id('feld')}"><path d="${panelPath()}"/></clipPath>` +
    `<filter id="${id('korn')}" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="${(c.file.length * 7) % 50}" result="n"/><feColorMatrix in="n" type="matrix" values="0 0 0 0 0.13  0 0 0 0 0.10  0 0 0 0 0.16  0 0 0 -1.6 1.05" result="a"/><feComposite in="a" in2="SourceGraphic" operator="in"/></filter>` +
    `<radialGradient id="${id('sonnenglanz')}" cx="0.4" cy="0.35" r="0.75"><stop offset="0" stop-color="#FFFFFF" stop-opacity=".35"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>` +
    `<linearGradient id="${id('abend')}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#8E1626"/><stop offset=".5" stop-color="#C8322A"/><stop offset=".7" stop-color="#EE7A2A"/></linearGradient>` +
    `</defs>`;

  /* Rahmen: Papierkarte */
  s += `<g id="${id('rahmen')}"><rect width="${CW}" height="${CH}" rx="${CR}" fill="${PAPER}"/>` +
    `<rect x="5" y="5" width="${CW - 10}" height="${CH - 10}" rx="${CR - 5}" fill="none" stroke="${PAPER_D}" stroke-width="3"/></g>`;

  /* Grund: Farbfeld + Sonnenstrahlen */
  s += `<g id="${id('grund')}">`;
  s += `<path d="${panelPath()}" fill="${base}"/>`;
  s += `<g clip-path="url(#${id('feld')})">`;
  if (joker) {
    // Joker: Sonnenkranz aus den vier Farben
    const cols = [LIGHT.rot.hex, LIGHT.gelb.hex, LIGHT.gruen.hex, LIGHT.blau.hex];
    const n = 16;
    for (let i = 0; i < n; i++) {
      const a0 = i * 360 / n, a1 = a0 + 360 / n * 0.62;
      const [x1, y1] = polar(SUN.x, SUN.y, 1100, a0), [x2, y2] = polar(SUN.x, SUN.y, 1100, a1);
      s += `<path d="M${SUN.x} ${SUN.y}L${f1(x1)} ${f1(y1)}L${f1(x2)} ${f1(y2)}Z" fill="${cols[i % 4]}"/>`;
    }
  } else {
    const n = 28;
    let d = '';
    for (let i = 0; i < n; i += 2) {
      const a0 = i * 360 / n, a1 = (i + 1) * 360 / n;
      const [x1, y1] = polar(SUN.x, SUN.y, 1100, a0), [x2, y2] = polar(SUN.x, SUN.y, 1100, a1);
      d += `M${SUN.x} ${SUN.y}L${f1(x1)} ${f1(y1)}L${f1(x2)} ${f1(y2)}Z`;
    }
    s += `<path d="${d}" fill="${rayCol}" opacity="${c.color === 'gelb' ? 0.22 : motif ? 0.12 : 0.09}"/>`;
  }
  s += `</g></g>`;

  /* Motiv: Sonne über dem Meer */
  s += `<g id="${id('motiv')}" clip-path="url(#${id('feld')})">`;
  s += `<circle cx="${SUN.x}" cy="${SUN.y}" r="${SR + 22}" fill="${joker ? '#FFF7E8' : sunCol}" opacity="${joker ? 0.55 : 0.35}"/>`;
  s += `<circle cx="${SUN.x}" cy="${SUN.y}" r="${SR}" fill="${sunCol}"/>`;
  s += `<circle cx="${SUN.x}" cy="${SUN.y}" r="${SR}" fill="url(#${id('sonnenglanz')})"/>`;
  // Meer
  const seaTop = HORIZON;
  s += `<rect x="0" y="${seaTop}" width="${CW}" height="${CH - seaTop}" fill="${deep}"/>`;
  // Wellenstreifen (Abstand wächst nach unten)
  let y = seaTop + 10, h = 4, k = 0;
  const stripeCol = joker ? '#C7B38F' : mix(deep, CREAM, c.color === 'gelb' ? 0.22 : 0.16);
  while (y < CH) {
    s += `<rect x="0" y="${f1(y)}" width="${CW}" height="${f1(h)}" fill="${stripeCol}"/>`;
    y += h + 8 + k * 5; h += 3; k++;
  }
  // Spiegelung der Sonne
  y = seaTop + 8; k = 0;
  const refl = joker ? '#FFF7E8' : sunCol;
  while (y < CH - 20 && k < 7) {
    const w = 230 - k * 32;
    s += `<rect x="${f1(SUN.x - w / 2)}" y="${f1(y)}" width="${f1(w)}" height="${f1(7 + k * 2.2)}" rx="${f1(3.5 + k)}" fill="${refl}" opacity="${(0.9 - k * 0.09).toFixed(2)}"/>`;
    y += 18 + k * 7; k++;
  }
  s += `<rect x="0" y="${seaTop - 2}" width="${CW}" height="4" fill="${INK}" opacity=".85"/>`;
  s += `</g>`;

  /* Symbol: Farbsymbole in den freien Feldecken */
  s += `<g id="${id('symbol')}">`;
  if (col && !motif) {
    const prims = symbolPrims(col.sym);
    const onCol = c.color === 'gelb' ? INK : CREAM;
    const one = place(renderPrims(prims, { main: onCol, cut: base }), 478, 84, 62);
    s += `<g opacity=".9">${one}<g transform="${ROT180}">${one}</g></g>`;
  }
  s += `</g>`;

  /* Wert */
  s += `<g id="${id('wert')}">${lightValue(c, id)}</g>`;

  /* Index */
  const look = {
    valFill: INK,
    iconColors: c => ({ main: c.type === 'flip' ? PAPER : INK, ring: INK, cut: PAPER, dark: INK, sun: INK, toe1: LIGHT.rot.hex, toe2: LIGHT.gelb.hex, toe3: LIGHT.gruen.hex, toe4: LIGHT.blau.hex, frontRing: PAPER,
      shine: PAPER, edge: PAPER, npanel: PAPER, qmark: PAPER }),
    symName: c => LIGHT[c.color].sym,
    symColors: c => ({ main: LIGHT[c.color].hex, cut: PAPER, outline: INK, outlineW: 3.2 }),
    jokerPaw: () => ({ main: INK, toe1: LIGHT.rot.hex, toe2: LIGHT.gelb.hex, toe3: LIGHT.gruen.hex, toe4: LIGHT.blau.hex }),
    jokerDots: () => [LIGHT.rot.hex, LIGHT.gelb.hex, LIGHT.gruen.hex, LIGHT.blau.hex],
    dotStroke: INK,
  };
  const idx = indexContent(c, look);
  s += `<g id="${id('index')}"><g id="${id('index_oben')}">${idx}</g><g id="${id('index_unten')}" transform="${ROT180}">${idx}</g></g>`;

  /* Papierkorn über allem */
  s += `<rect width="${CW}" height="${CH}" rx="${CR}" filter="url(#${id('korn')})" opacity=".16" style="mix-blend-mode:multiply"/>`;
  s += `</svg>`;
  return s;
}

function lightValue(c, id) {
  const X = 280;
  if (c.type === 'motiv') return '';
  const fill = CREAM, stroke = INK;
  const ol = 9; // halbe Konturbreite
  if (c.type === 'num') {
    let s = valueText({ x: X, y: 572, size: 420, txt: c.v, fill, stroke, sw: ol * 2 });
    if (c.v === '6' || c.v === '9') s += `<rect x="${X - 92}" y="${596}" width="184" height="30" rx="15" fill="${fill}" stroke="${stroke}" stroke-width="${ol * 1.6}" paint-order="stroke"/>`;
    return s;
  }
  if (c.type === 'zieh' || c.type === 'wunsch2') {
    // Kartenstapel als ruhiges Emblem hinter "+1" bzw. "+2"
    let st = '';
    const deep = c.color ? LIGHT[c.color].deep : INK;
    const fanCols = c.type === 'wunsch2' ? [LIGHT.blau.hex, LIGHT.gruen.hex, LIGHT.rot.hex] : [deep, deep, deep];
    const geo = [[-18, -70, 26], [18, 70, 26], [0, 0, 0]];
    st += geo.map(([r, dx, dy], i) => `<g transform="rotate(${r} ${X + dx} ${300 + dy})"><rect x="${X - 92 + dx}" y="${168 + dy}" width="184" height="264" rx="22" fill="${fanCols[i]}" stroke="${CREAM}" stroke-width="7"/><rect x="${X - 74 + dx}" y="${186 + dy}" width="148" height="228" rx="14" fill="none" stroke="${CREAM}" stroke-width="3" opacity=".45"/></g>`).join('');
    st += valueText({ x: X, y: 600, size: 330, txt: c.v, fill, stroke, sw: ol * 2 });
    return st;
  }
  const prims = iconPrims(ICON_OF[c.type], iconOpt(c, false));
  const cols = { main: CREAM, cut: INK, dark: INK, sun: INK, sil: INK, toe1: LIGHT.rot.hex, toe2: LIGHT.gelb.hex, toe3: LIGHT.gruen.hex, toe4: LIGHT.blau.hex, frontRing: INK };
  if (c.type === 'flip') { cols.cut = CREAM; cols.sun = LIGHT.gelb.hex; }
  if (c.type === 'wunsch') { cols.main = INK; }
  if (c.type === 'wende') cols.stripe = LIGHT[c.color].deep;
  if (c.type === 'tausch') cols.panel = LIGHT[c.color].deep;
  if (c.type === 'gluecks') Object.assign(cols, { dome: INK, shine: CREAM, edge: INK, display: INK, digits: LIGHT.gelb.hex, qmark: CREAM });
  if (c.type === 'ablegen' || c.type === 'ablegenj') Object.assign(cols, { panel: c.color ? LIGHT[c.color].deep : INK, cardsym: CREAM, ncard: CREAM, npanel: mix(CREAM, INK, 0.14), speed: c.color ? LIGHT[c.color].deep : mix(INK, CREAM, 0.3) });
  const size = c.type === 'wunsch' ? 300 : 330;
  let s = place(renderPrims(prims, cols, 'sil', 3.2) + renderPrims(prims, cols), X, 452, size);
  if (c.type === 'aussetzen') s += zzz(X + 118, 300, INK, CREAM);
  return s;
}
function zzz(x, y, stroke, fill, glow = '') {
  return `<g${glow}>` + valueText({ x, y, size: 78, txt: 'z', fill, stroke, sw: 12, weight: 800 }) +
    valueText({ x: x + 40, y: y - 52, size: 56, txt: 'z', fill, stroke, sw: 10, weight: 800 }) + '</g>';
}

/* ================== DUNKLE SEITE ================== */
function darkCard(c, P, id, opt) {
  const joker = !c.color;
  const col = joker ? null : DARK[c.color];
  const motif = c.type === 'motiv';
  const neon = motif ? '#FF8AD8' : joker ? '#E8E0FF' : col.neon;
  const base = motif ? '#C9B8FF' : joker ? '#2A2350' : col.hex;
  const panel = motif ? '#17143F' : joker ? '#12153A' : mix(NIGHT, col.hex, c.color === 'lila' ? 0.30 : 0.20);
  const tint = joker ? MOON : mix(neon, '#FFFFFF', 0.62);
  let s = svgOpen(P, cardTitle(c), opt);
  const jokerGrad = `<linearGradient id="${id('regenbogen')}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="${DARK.pink.neon}"/><stop offset=".36" stop-color="${DARK.orange.neon}"/><stop offset=".66" stop-color="${DARK.tuerkis.neon}"/><stop offset="1" stop-color="${DARK.lila.neon}"/></linearGradient>`;
  s += `<defs>` +
    `<linearGradient id="${id('nacht')}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${NIGHT_HI}"/><stop offset="1" stop-color="${NIGHT}"/></linearGradient>` +
    `<radialGradient id="${id('feldlicht')}" cx="0.5" cy="0.5" r="0.62"><stop offset="0" stop-color="${joker ? '#3B3170' : mix(panel, base, 0.45)}"/><stop offset="1" stop-color="${panel}"/></radialGradient>` +
    `<radialGradient id="${id('mondlicht')}" cx="0.35" cy="0.7" r="0.8"><stop offset="0" stop-color="${joker ? '#FFFFFF' : mix(base, '#FFFFFF', 0.35)}"/><stop offset="1" stop-color="${joker ? '#CFC6F5' : base}"/></radialGradient>` +
    `<clipPath id="${id('feld')}"><path d="${panelPath()}"/></clipPath>` +
    `<filter id="${id('glut')}" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="7" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>` +
    `<filter id="${id('glutweit')}" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="16" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>` +
    `<filter id="${id('glutklein')}" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="4" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>` +
    (joker ? jokerGrad : '') +
    (motif ? `<linearGradient id="${id('neonlogo')}" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FF7FCF"/><stop offset=".5" stop-color="#9A6BFF"/><stop offset="1" stop-color="#3FD3E6"/></linearGradient>` : '') +
    `</defs>`;

  /* Rahmen: Nachtkarte */
  s += `<g id="${id('rahmen')}"><rect width="${CW}" height="${CH}" rx="${CR}" fill="url(#${id('nacht')})"/>` +
    `<rect x="4" y="4" width="${CW - 8}" height="${CH - 8}" rx="${CR - 4}" fill="none" stroke="#2C3366" stroke-width="3"/></g>`;

  /* Grund: Feld + Neonkontur */
  const stroke = joker ? `url(#${id('regenbogen')})` : motif ? `url(#${id('neonlogo')})` : neon;
  s += `<g id="${id('grund')}"><path d="${panelPath()}" fill="url(#${id('feldlicht')})"/>` +
    `<path d="${panelPath(9)}" fill="none" stroke="${stroke}" stroke-width="6" filter="url(#${id('glut')})"/>` +
    `<path d="${panelPath(9)}" fill="none" stroke="#FFFFFF" stroke-width="1.6" opacity=".55"/></g>`;

  /* Motiv: Mond, Sterne, Horizont */
  s += `<g id="${id('motiv')}" clip-path="url(#${id('feld')})">`;
  const R = rng(c.file.length * 31 + (c.color || 'j').length * 7);
  for (let i = 0; i < 46; i++) {
    const x = PX0 + R() * (PX1 - PX0), y = PY0 + R() * (HORIZON - 40 - PY0);
    if (x < XA + 10 && y < YA + 10) continue;
    if (Math.hypot(x - SUN.x, y - SUN.y) < SUN.r + 24) continue;
    s += `<circle cx="${f1(x)}" cy="${f1(y)}" r="${f1(0.8 + R() * 2)}" fill="${MOON}" opacity="${(0.35 + R() * 0.5).toFixed(2)}"/>`;
  }
  const sp = [[452, 92, 20], [204, 104, 12], [492, 210, 11], [110, 352, 13], [470, 540, 15], [92, 520, 9]];
  for (const [x, y, r] of sp) s += `<path d="${sparkle(x, y, r)}" fill="${MOON}" filter="url(#${id('glutklein')})"/>`;
  // Mondsichel
  const mx = SUN.x, my = SUN.y, mr = motif ? 182 : SUN.r + 6;
  s += `<circle cx="${mx}" cy="${my}" r="${mr + 30}" fill="${joker ? '#8F7BFF' : neon}" opacity=".10"/>`;
  s += `<path d="M${mx} ${my - mr}A${mr} ${mr} 0 1 0 ${f1(mx + mr * 0.98)} ${f1(my + mr * 0.2)}A${mr * 0.82} ${mr * 0.82} 0 1 1 ${mx} ${my - mr}Z" fill="url(#${id('mondlicht')})" filter="url(#${id('glutweit')})"/>`;
  // Horizont und Spiegelung
  s += `<rect x="0" y="${HORIZON}" width="${CW}" height="${CH - HORIZON}" fill="${NIGHT}" opacity=".55"/>`;
  s += `<rect x="0" y="${HORIZON - 1.5}" width="${CW}" height="3" fill="${stroke}" filter="url(#${id('glutklein')})"/>`;
  let y = HORIZON + 16, g = 14, k = 0;
  while (y < CH) {
    s += `<rect x="0" y="${f1(y)}" width="${CW}" height="${f1(1.6 + k * 0.5)}" fill="${stroke}" opacity="${(0.55 - k * 0.04).toFixed(2)}"/>`;
    y += g; g += 7; k++;
  }
  y = HORIZON + 9; k = 0;
  while (k < 7) {
    const w = 170 - k * 22;
    s += `<rect x="${f1(SUN.x - w / 2)}" y="${f1(y)}" width="${f1(w)}" height="${f1(5 + k * 1.6)}" rx="${f1(2.5 + k)}" fill="${joker ? MOON : mix(base, '#FFFFFF', 0.3)}" opacity="${(0.75 - k * 0.08).toFixed(2)}"/>`;
    y += 17 + k * 7; k++;
  }
  s += `</g>`;

  /* Symbol */
  s += `<g id="${id('symbol')}">`;
  if (col && !motif) {
    const prims = symbolPrims(col.sym);
    const one = place(renderPrims(prims, { main: neon, cut: panel }), 478, 84, 58);
    s += `<g filter="url(#${id('glutklein')})">${one}<g transform="${ROT180}">${one}</g></g>`;
  }
  s += `</g>`;

  /* Wert */
  s += `<g id="${id('wert')}">${darkValue(c, id, { neon, tint, base, panel })}</g>`;

  /* Index */
  const jokerCols = [DARK.pink.neon, DARK.tuerkis.neon, DARK.orange.neon, DARK.lila.neon];
  const look = {
    valFill: tint, valGlow: id('glutklein'),
    iconColors: () => ({ main: tint, cut: NIGHT, dark: NIGHT, sun: tint, toe1: DARK.pink.neon, toe2: DARK.orange.neon, toe3: DARK.tuerkis.neon, toe4: DARK.lila.neon, frontRing: NIGHT,
      shine: NIGHT, edge: NIGHT, npanel: NIGHT, qmark: NIGHT }),
    symName: c => DARK[c.color].sym,
    symColors: c => ({ main: DARK[c.color].neon, cut: NIGHT }),
    symGlow: id('glutklein'),
    jokerPaw: () => ({ main: MOON, toe1: DARK.pink.neon, toe2: DARK.orange.neon, toe3: DARK.tuerkis.neon, toe4: DARK.lila.neon }),
    jokerDots: () => jokerCols,
  };
  const idx = indexContent(c, look);
  s += `<g id="${id('index')}"><g id="${id('index_oben')}">${idx}</g><g id="${id('index_unten')}" transform="${ROT180}">${idx}</g></g>`;
  s += `</svg>`;
  return s;
}

function darkValue(c, id, k) {
  const X = 280;
  if (c.type === 'motiv') return '';
  const glow = ` filter="url(#${id('glut')})"`;
  if (c.type === 'num') {
    let s = `<g${glow}>` + valueText({ x: X, y: 572, size: 420, txt: c.v, fill: k.tint, stroke: NIGHT, sw: 16 });
    if (c.v === '6' || c.v === '9') s += `<rect x="${X - 92}" y="${596}" width="184" height="30" rx="15" fill="${k.tint}" stroke="${NIGHT}" stroke-width="12" paint-order="stroke"/>`;
    return s + '</g>';
  }
  if (c.type === 'zieh' || c.type === 'jagd') {
    let st = '';
    const rects = [[-16, -54, 22], [16, 54, 22], [0, 0, 0]];
    const jc = [DARK.pink.neon, DARK.tuerkis.neon, DARK.orange.neon];
    st += rects.map(([r, dx, dy], i) => `<rect x="${X - 62 + dx}" y="${262 + dy}" width="124" height="180" rx="16" transform="rotate(${r} ${X + dx} ${352 + dy})" fill="${NIGHT}" stroke="${c.type === 'jagd' ? jc[i] : k.neon}" stroke-width="6"${glow}/>`).join('');
    st += `<g${glow}>` + valueText({ x: X, y: 590, size: 300, txt: c.v, fill: k.tint, stroke: NIGHT, sw: 16 }) + '</g>';
    return st;
  }
  const prims = iconPrims(ICON_OF[c.type], iconOpt(c, false));
  const cols = { main: k.tint, cut: NIGHT, dark: NIGHT, sun: k.neon, sil: NIGHT, toe1: DARK.pink.neon, toe2: DARK.orange.neon, toe3: DARK.tuerkis.neon, toe4: DARK.lila.neon, frontRing: NIGHT };
  if (c.type === 'flip') { cols.dark = mix(NIGHT, k.neon, 0.25); cols.cut = k.tint; cols.sun = k.neon; }
  if (c.type === 'wunsch') cols.main = MOON;
  if (c.type === 'wende') cols.stripe = mix(k.panel, k.neon, 0.55);
  if (c.type === 'tausch') cols.panel = mix(k.panel, k.neon, 0.55);
  if (c.type === 'gluecks') Object.assign(cols, { dome: `url(#${id('regenbogen')})`, shine: MOON, edge: NIGHT, display: NIGHT, digits: DARK.tuerkis.neon, qmark: NIGHT });
  if (c.type === 'ablegen' || c.type === 'ablegenj') Object.assign(cols, { panel: mix(k.panel, k.neon, 0.55), cardsym: k.tint, ncard: k.tint, npanel: mix(k.panel, k.tint, 0.3), speed: k.neon });
  const size = c.type === 'wunsch' ? 300 : 330;
  let s = `<g${glow}>` + place(renderPrims(prims, cols, 'sil', 3.2) + renderPrims(prims, cols), X, 452, size) + '</g>';
  if (c.type === 'alle') s += zzz(X + 150, 290, NIGHT, k.tint, glow);
  return s;
}

/* ------------------------------------------------------------------ */
/* Export für build.html / Entwicklerseiten                             */
/* ------------------------------------------------------------------ */
if (typeof window !== 'undefined') window.MMF = { cardSVG, CARD_LIST, LIGHT, DARK, symbolPrims, iconPrims, renderPrims, place, minPair, Lof, mix, FONT_CSS, F_CARD, F_BRAND, INK, PAPER, CREAM, NIGHT, MOON, asciiSafe, esc, f1, polar, sparkle, starPath, rng, SYM_NAMES, cardTitle, PAPER_D, NIGHT_HI };
