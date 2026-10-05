/* Mau-Mau Flip – Bediensymbole, Kartenfarb-Symbole, App-Symbole (Android, Touch-Icon) und Startbild.
 * Baut auf mmf.js (Farben, Symbole) und logo.js (logoSVG, iconSVG) auf.
 */
'use strict';

/* Pfad der Katzen-Illustration relativ zu render.html (Original in art/entwurf/a-papier-neon/) */
const KATZE_PFAD = '../../art/entwurf/a-papier-neon/katze_mau.png';
function mitKatze(svg) { return svg.split('href="katze_mau.png"').join(`href="${KATZE_PFAD}"`); }

/* ------------------------------------------------------------------ */
/* Bediensymbole 96×96: Papierfarbe auf transparent, kräftige Linien   */
/* ------------------------------------------------------------------ */
const UI_W = 8; // Linienstärke
const UI_LINE = `fill="none" stroke="${PAPER}" stroke-width="${UI_W}" stroke-linecap="round" stroke-linejoin="round"`;
const UI_FILL = `fill="${PAPER}"`;

function gearPath(cx, cy, n, ro, ri, tooth) {
  // Zahnrad mit n Zähnen; tooth = Anteil der Teilung, den ein Zahn außen einnimmt
  let d = '';
  const step = 360 / n;
  for (let i = 0; i < n; i++) {
    const a = i * step;
    const pts = [
      polar(cx, cy, ri, a - step / 2 + step * 0.06),
      polar(cx, cy, ri, a - step * tooth / 2 - step * 0.08),
      polar(cx, cy, ro, a - step * tooth / 2),
      polar(cx, cy, ro, a + step * tooth / 2),
      polar(cx, cy, ri, a + step * tooth / 2 + step * 0.08),
      polar(cx, cy, ri, a + step / 2 - step * 0.06),
    ];
    pts.forEach(([x, y], k) => { d += (i === 0 && k === 0 ? 'M' : 'L') + f1(x) + ' ' + f1(y); });
  }
  return d + 'Z';
}

function arcD(cx, cy, r, a0, a1) {
  const [x0, y0] = polar(cx, cy, r, a0), [x1, y1] = polar(cx, cy, r, a1);
  const large = ((a1 - a0 + 360) % 360) > 180 ? 1 : 0;
  return `M${f1(x0)} ${f1(y0)}A${r} ${r} 0 ${large} 1 ${f1(x1)} ${f1(y1)}`;
}

const UI_ICONS = {
  // zwei Pfeile: ab und auf
  sortieren: () => `<path d="M30 14V80M16 66L30 80L44 66M66 82V16M52 30L66 16L80 30" ${UI_LINE}/>`,
  // zwei Karten, die vordere zeigt eine Mondsichel (die andere Seite)
  rueckseiten: P => `<defs><mask id="${P}m" maskUnits="userSpaceOnUse" x="0" y="0" width="96" height="96">` +
    `<rect width="96" height="96" fill="#fff"/><rect x="36" y="22" width="48" height="66" rx="9" fill="#000" stroke="#000" stroke-width="${UI_W + 8}"/></mask>` +
    `<mask id="${P}k" maskUnits="userSpaceOnUse" x="0" y="0" width="96" height="96"><rect width="96" height="96" fill="#fff"/>` +
    `<path d="M62 37A18 18 0 1 0 75 66A14 14 0 1 1 62 37Z" fill="#000"/></mask></defs>` +
    `<g mask="url(#${P}m)"><rect x="12" y="8" width="48" height="66" rx="9" ${UI_LINE}/></g>` +
    `<rect x="36" y="22" width="48" height="66" rx="9" ${UI_FILL} stroke="${PAPER}" stroke-width="${UI_W}" stroke-linejoin="round" mask="url(#${P}k)"/>`,
  // Fragezeichen im Kreis
  hilfe: () => `<circle cx="48" cy="48" r="39" ${UI_LINE}/>` +
    `<path d="M35 37C35 28 41 23 48.5 23C56 23 62 28 62 35.5C62 43 55.5 45.5 51.5 49C49.5 51 48.5 53 48.5 57" ${UI_LINE}/>` +
    `<circle cx="48.5" cy="71" r="5.5" ${UI_FILL}/>`,
  // Zahnrad
  einstellungen: () => `<path d="${gearPath(48, 48, 8, 43, 33, 0.46)}M48 34a14 14 0 1 0 0.01 0Z" ${UI_FILL} fill-rule="evenodd" stroke="${PAPER}" stroke-width="3" stroke-linejoin="round"/>`,
  // Teilen: drei Knoten
  teilen: () => `<path d="M26 48L70 22M26 48L70 74" ${UI_LINE}/>` +
    `<circle cx="70" cy="21" r="12" ${UI_FILL}/><circle cx="25" cy="48" r="12" ${UI_FILL}/><circle cx="70" cy="75" r="12" ${UI_FILL}/>`,
  // Update: Kreispfeil um einen Pfeil nach unten
  update: () => {
    // Bogen im Uhrzeigersinn von 50° bis 318°, Pfeilspitze in Laufrichtung (Tangente) am Ende
    const a = 318, r = 37, [ex, ey] = polar(48, 48, r, a);
    const rad = a * Math.PI / 180, tx = Math.cos(rad), ty = Math.sin(rad); // Tangente im Uhrzeigersinn
    const nx = -ty, ny = tx, L = 13;
    const w1 = [ex - tx * L + nx * L, ey - ty * L + ny * L], w2 = [ex - tx * L - nx * L, ey - ty * L - ny * L];
    return `<path d="${arcD(48, 48, r, 50, a)}" ${UI_LINE}/>` +
      `<path d="M${f1(w1[0])} ${f1(w1[1])}L${f1(ex)} ${f1(ey)}L${f1(w2[0])} ${f1(w2[1])}" ${UI_LINE}/>` +
      `<path d="M48 30V62M36 51L48 63L60 51" ${UI_LINE}/>`;
  },
  // Pfeil zurück
  zurueck: () => `<path d="M82 48H18M44 20L16 48L44 76" ${UI_LINE}/>`,
  // WLAN
  wlan: () => `<path d="${arcD(48, 80, 58, -44, 44)}M${arcD(48, 80, 38, -44, 44).slice(1)}M${arcD(48, 80, 18, -44, 44).slice(1)}" ${UI_LINE}/>` +
    `<circle cx="48" cy="80" r="6.5" ${UI_FILL}/>`,
  // QR-Code (stilisiert, kein lesbarer Code)
  qr: () => {
    const finder = (x, y) => `<rect x="${x + 3.5}" y="${y + 3.5}" width="27" height="27" rx="5" fill="none" stroke="${PAPER}" stroke-width="7"/><rect x="${x + 11}" y="${y + 11}" width="12" height="12" rx="2" ${UI_FILL}/>`;
    const dots = [[44, 8], [44, 26], [8, 44], [26, 44], [44, 44], [57, 57], [79, 57], [68, 68], [57, 79], [79, 79]];
    return finder(6, 6) + finder(56, 6) + finder(6, 56) + dots.map(([x, y]) => `<rect x="${x}" y="${y}" width="10" height="10" rx="2" ${UI_FILL}/>`).join('');
  },
  // Regeln: offenes Buch mit Zeilen
  regeln: () => `<path d="M48 26C40 19 26 16 10 18V76C26 74 40 77 48 84C56 77 70 74 86 76V18C70 16 56 19 48 26ZM48 26V84" ${UI_LINE}/>` +
    `<path d="M20 34C26 33.5 32 34.5 38 37M20 48C26 47.5 32 48.5 38 51M58 37C64 34.5 70 33.5 76 34M58 51C64 48.5 70 47.5 76 48" fill="none" stroke="${PAPER}" stroke-width="5" stroke-linecap="round"/>`,
  // Spieler: Kopf und Schultern
  spieler: () => `<circle cx="48" cy="31" r="17" ${UI_LINE}/><path d="M15 86C15 66 30 56 48 56C66 56 81 66 81 86" ${UI_LINE}/>`,
  // Computergegner: Roboterkopf mit Antenne
  roboter: () => `<rect x="16" y="30" width="64" height="52" rx="14" ${UI_LINE}/>` +
    `<path d="M48 30V17" ${UI_LINE}/><circle cx="48" cy="12" r="7" ${UI_FILL}/>` +
    `<circle cx="36" cy="53" r="7" ${UI_FILL}/><circle cx="60" cy="53" r="7" ${UI_FILL}/>` +
    `<path d="M38 69H58" fill="none" stroke="${PAPER}" stroke-width="6" stroke-linecap="round"/>` +
    `<path d="M8 48V64M88 48V64" ${UI_LINE}/>`,
  // Start: Dreieck
  start: () => `<path d="M30 15L80 48L30 81Z" ${UI_FILL} stroke="${PAPER}" stroke-width="${UI_W}" stroke-linejoin="round"/>`,
  // Mau: Sprechblase mit Katzenohren und Ausrufezeichen
  mau: () => `<path d="M38 24L26 8L21 33C14 39 10 46 10 54C10 70 27 82 48 82C53 82 57 81.5 61 80.5L80 89L75 73C82 68 86 61 86 54C86 46 82 39 75 33L70 8L58 24C55 23.4 51.5 23 48 23C44.5 23 41 23.4 38 24Z" ${UI_LINE}/>` +
    `<path d="M48 40V57" ${UI_LINE}/><circle cx="48" cy="69" r="5.5" ${UI_FILL}/>`,
  // Ziehen: Karte und Pfeil nach unten
  ziehen: () => `<rect x="12" y="8" width="46" height="64" rx="9" ${UI_LINE}/>` +
    `<path d="M74 32V84M60 70L74 84L88 70" ${UI_LINE}/>`,
};
const UI_ICON_NAMES = ['sortieren', 'rueckseiten', 'hilfe', 'einstellungen', 'teilen', 'update', 'zurueck', 'wlan', 'qr', 'regeln', 'spieler', 'roboter', 'start', 'mau', 'ziehen'];

function uiIconSVG(name, P = 'ui-') {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96" width="96" height="96">${UI_ICONS[name](P + name + '-')}</svg>`;
}

/* ------------------------------------------------------------------ */
/* Kartenfarb-Symbole 96×96 in der Kartenfarbe                         */
/* hell: Flächenfarbe mit Druckfarben-Kontur, Details in Papier (wie im Eckindex der hellen Seite)
 * dunkel: Neonfarbe, Details in Nacht, Kontur in Nacht (wie im Eckindex der dunklen Seite)
 * Dazu ein heller Außenrand (hell: Papier wie ein Aufkleber, dunkel: aufgehellte Neonfarbe), damit das Symbol auch auf
 * dunklem Tisch genug Kontrast hat (Lila-Neon #5E3BD8 auf #0A0D20 nur etwa 2,8:1, der Rand über 9:1). Die Karten selbst bleiben unverändert. */
/* ------------------------------------------------------------------ */
const FARB_NAMES = ['rot', 'gelb', 'gruen', 'blau', 'pink', 'tuerkis', 'orange', 'lila'];
/* Außenrand der dunklen Farbsymbole: Neonfarbe zu 62 % aufgehellt (wie die Werte auf der dunklen Seite) */
function farbRand(farbe) { return mix(DARK[farbe].neon, '#FFFFFF', 0.62); }
function colorSymbolSVG(farbe) {
  const hell = !!LIGHT[farbe];
  const c = hell ? LIGHT[farbe] : DARK[farbe];
  const prims = symbolPrims(c.sym);
  const rand = hell ? PAPER : farbRand(farbe);
  const inner = renderPrims(prims, { sil: rand }, 'sil', 6.2) + (hell
    ? renderPrims(prims, { sil: INK }, 'sil', 3.2) + renderPrims(prims, { main: c.hex, cut: PAPER })
    : renderPrims(prims, { sil: NIGHT }, 'sil', 3.2) + renderPrims(prims, { main: c.neon, cut: NIGHT }));
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 96 96" width="96" height="96">${place(inner, 48, 48, 80)}</svg>`;
}

/* ------------------------------------------------------------------ */
/* App-Symbole                                                         */
/* ------------------------------------------------------------------ */
/* Abgerundetes App-Symbol (wie Entwurf icon.svg) */
function appIconSVG(w = 512, P = 'ai-') { return mitKatze(iconSVG({ prefix: P, width: w })); }

/* Quadratisch ohne Eckenrundung (iOS-Touch-Icon: iOS rundet selbst, transparente Ecken würden schwarz) */
function appIconSquareSVG(w = 512, P = 'aq-') {
  return appIconSVG(w, P).replace(`<rect width="512" height="512" rx="112"/>`, `<rect width="512" height="512"/>`)
    .replace(/<rect x="1\.5" y="1\.5"[^>]*\/>/, '');
}

/* Android adaptiv: 432×432 (108 dp), sichtbar ist die Mitte 288×288 (72 dp), sicher der Kreis mit 264 px (66 dp).
 * Die 512er-Fläche des App-Symbols wird auf die sichtbaren 288 px abgebildet. */
const AD = { S: 432, off: 72, k: 288 / 512 };
const AD_TF = `translate(${AD.off} ${AD.off}) scale(${AD.k})`;

function adaptiveBackgroundSVG(P = 'ab-') {
  const id = n => P + n;
  const S = AD.S;
  // Wendelinie wie im App-Symbol (300|0 → 212|512), auf die volle Fläche verlängert (−128 … 640 in Symbol-Koordinaten)
  const xAt = y => 300 - 88 * y / 512;
  const DAY = `M-140 -140H${f1(xAt(-140))}L${f1(xAt(660))} 660H-140Z`, NIGHTP = `M${f1(xAt(-140))} -140H660V660H${f1(xAt(660))}Z`;
  let rays = '';
  for (let i = 0; i < 36; i += 2) {
    const [x1, y1] = polar(84, 84, 1200, i * 10), [x2, y2] = polar(84, 84, 1200, i * 10 + 10);
    rays += `M84 84L${f1(x1)} ${f1(y1)}L${f1(x2)} ${f1(y2)}Z`;
  }
  const sun = { x: 100, y: 108 }, moon = { x: 418, y: 92 };   // etwas nach innen gerückt, damit runde Masken sie zeigen
  let s = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${S} ${S}" width="${S}" height="${S}">` +
    `<defs><clipPath id="${id('tag')}"><path d="${DAY}"/></clipPath><clipPath id="${id('nacht')}"><path d="${NIGHTP}"/></clipPath>` +
    `<linearGradient id="${id('himmel')}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#26205A"/><stop offset="1" stop-color="${NIGHT}"/></linearGradient>` +
    `<radialGradient id="${id('papier')}" cx=".3" cy=".3" r=".8"><stop offset="0" stop-color="#FFF6E2"/><stop offset="1" stop-color="#EAD9BA"/></radialGradient>` +
    `<radialGradient id="${id('sonne')}" cx=".4" cy=".38" r=".7"><stop offset="0" stop-color="#FFF3B0"/><stop offset=".55" stop-color="#FFC93C"/><stop offset="1" stop-color="#F29A1F"/></radialGradient>` +
    `<radialGradient id="${id('sonnenhof')}"><stop offset=".45" stop-color="#FFC93C" stop-opacity=".55"/><stop offset="1" stop-color="#FFC93C" stop-opacity="0"/></radialGradient>` +
    `<filter id="${id('glut')}" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="5" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>` +
    `</defs><g transform="${AD_TF}">`;
  s += `<g clip-path="url(#${id('tag')})"><rect x="-140" y="-140" width="800" height="800" fill="url(#${id('papier')})"/><path d="${rays}" fill="#E0CBA2" opacity=".35"/>` +
    `<circle cx="${sun.x}" cy="${sun.y}" r="58" fill="url(#${id('sonnenhof')})"/><circle cx="${sun.x}" cy="${sun.y}" r="34" fill="url(#${id('sonne')})"/></g>`;
  const mr = 40;
  s += `<g clip-path="url(#${id('nacht')})"><rect x="-140" y="-140" width="800" height="800" fill="url(#${id('himmel')})"/>` +
    starField(9, 50, { x: 200, y: 0, w: 312, h: 330 }) + starField(91, 60, { x: 200, y: -140, w: 460, h: 800 }, (x, y) => x > 0 && x < 512 && y > 0 && y < 330) +
    `<path d="M${moon.x} ${moon.y - mr}A${mr} ${mr} 0 1 0 ${moon.x + 36} ${moon.y + 20}A33 33 0 1 1 ${moon.x} ${moon.y - mr}Z" fill="#FFE3F4" filter="url(#${id('glut')})"/>` +
    `<path d="${sparkle(352, 50, 10)}" fill="${MOON}" filter="url(#${id('glut')})"/></g>`;
  s += `<path d="M${f1(xAt(-140))} -140L${f1(xAt(660))} 660" stroke="#FF7FCF" stroke-width="2.5" opacity=".8" filter="url(#${id('glut')})"/>`;
  s += `</g></svg>`;
  return s;
}

/* Vordergrund: nur die Katze, in derselben Lage wie im App-Symbol (Kopf und Pfote im sicheren Kreis).
 * Der Schwanz (rechts unten, im App-Symbol außerhalb) wird weggeschnitten, damit er bei Parallax-Effekten nicht hereinragt. */
function adaptiveForegroundSVG(P = 'af-') {
  const ks = 0.66;
  return mitKatze(`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${AD.S} ${AD.S}" width="${AD.S}" height="${AD.S}">` +
    `<defs><clipPath id="${P}ohne-schwanz"><path d="M-200 -200H700V480H475V720H-200Z"/></clipPath></defs>` +
    `<g transform="${AD_TF}"><g clip-path="url(#${P}ohne-schwanz)"><image href="katze_mau.png" x="-113" y="57" width="${f1(1209 * ks)}" height="${f1(1301 * ks)}"/></g></g></svg>`);
}

/* Einfarbig (Android 13 „Themensymbole“): wache Katzenkopf-Silhouette, Details ausgespart */
function adaptiveMonochromeSVG(P = 'am-') {
  const prims = catHeadPrims('', false);
  const head = prims.filter(p => p.role === 'main').map(p => `<path d="${p.d}" fill="#fff"/>`).join('');
  const cuts = prims.filter(p => p.role === 'cut').map(p => p.kind === 'line'
    ? `<path d="${p.d}" fill="none" stroke="#000" stroke-width="${p.w}" stroke-linecap="round"/>`
    : `<path d="${p.d}" fill="#000"/>`).join('');
  // Maul offen (Mau!) statt Nase allein
  const mouth = `<path d="M40 79Q50 89 60 79" fill="none" stroke="#000" stroke-width="5" stroke-linecap="round"/>`;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${AD.S} ${AD.S}" width="${AD.S}" height="${AD.S}">` +
    `<defs><mask id="${P}m" maskUnits="userSpaceOnUse" x="0" y="0" width="100" height="100"><rect width="100" height="100" fill="#000"/>${head}${cuts}${mouth}</mask></defs>` +
    place(`<rect width="100" height="100" fill="#fff" mask="url(#${P}m)"/>`, 216, 222, 236) + `</svg>`;
}

/* ------------------------------------------------------------------ */
/* Logo und Startbild                                                  */
/* ------------------------------------------------------------------ */
function logoFullSVG() { return mitKatze(logoSVG({ prefix: 'lg-' })); }

/* Startbild 1600×720: Nachthimmel wie der Tisch, das Logo als abgerundete Tafel in der Mitte.
 * Die Ränder laufen in die Nachtfarbe #0A0D20 aus (= boot_splash/bg_color), die äußersten 4 px sind genau diese Farbe,
 * damit bei anderem Seitenverhältnis keine Kante entsteht. */
function splashSVG(P = 'sp-') {
  const id = n => P + n;
  const W = 1600, H = 720, lw = 1040, lh = lw * 900 / 1600, lx = (W - lw) / 2, ly = (H - lh) / 2;
  let s = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${W}" height="${H}">` +
    `<defs><radialGradient id="${id('tisch')}" cx=".5" cy=".46" r=".75"><stop offset="0" stop-color="#26305A"/><stop offset=".55" stop-color="#171C38"/><stop offset="1" stop-color="${NIGHT}"/></radialGradient>` +
    `<clipPath id="${id('tafel')}"><rect x="${lx}" y="${ly}" width="${lw}" height="${f1(lh)}" rx="34"/></clipPath>` +
    `<filter id="${id('schatten')}" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="18"/></filter>` +
    `<filter id="${id('glut')}" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="4" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>` +
    `</defs>`;
  s += `<rect width="${W}" height="${H}" fill="url(#${id('tisch')})"/>`;
  // Ränder laufen in die Nachtfarbe aus (Balken oben/unten bzw. seitlich bei anderem Seitenverhältnis fallen nicht auf)
  s += `<linearGradient id="${id('rand_v')}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${NIGHT}"/><stop offset=".12" stop-color="${NIGHT}" stop-opacity="0"/><stop offset=".88" stop-color="${NIGHT}" stop-opacity="0"/><stop offset="1" stop-color="${NIGHT}"/></linearGradient>` +
    `<linearGradient id="${id('rand_h')}" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="${NIGHT}"/><stop offset=".06" stop-color="${NIGHT}" stop-opacity="0"/><stop offset=".94" stop-color="${NIGHT}" stop-opacity="0"/><stop offset="1" stop-color="${NIGHT}"/></linearGradient>` +
    `<rect width="${W}" height="${H}" fill="url(#${id('rand_v')})"/><rect width="${W}" height="${H}" fill="url(#${id('rand_h')})"/>`;
  s += starField(23, 140, { x: 0, y: 0, w: W, h: H }, (x, y) => (x > lx - 20 && x < lx + lw + 20 && y > ly - 20 && y < ly + lh + 20) || y < 36 || y > H - 36 || x < 40 || x > W - 40);
  for (const [x, y, r] of [[120, 110, 12], [1490, 140, 14], [200, 600, 9], [1420, 610, 10]]) s += `<path d="${sparkle(x, y, r)}" fill="${MOON}" filter="url(#${id('glut')})"/>`;
  s += `<rect x="${lx}" y="${ly + 16}" width="${lw}" height="${f1(lh)}" rx="34" fill="#000" opacity=".5" filter="url(#${id('schatten')})"/>`;
  s += `<rect x="${lx - 3}" y="${ly - 3}" width="${lw + 6}" height="${f1(lh + 6)}" rx="37" fill="none" stroke="#FF7FCF" stroke-width="3" opacity=".55" filter="url(#${id('glut')})"/>`;
  const inner = logoSVG({ prefix: P + 'lg-', width: lw }).replace('<svg ', `<svg x="${lx}" y="${ly}" `);
  s += `<g clip-path="url(#${id('tafel')})">${inner}</g>`;
  // Rahmen 4 px in reiner Nachtfarbe ohne Verlauf: Chrome rastert Verläufe mit Dithering (±1), der äußerste Rand soll exakt #0A0D20 sein
  s += `<rect width="${W}" height="${H}" fill="none" stroke="${NIGHT}" stroke-width="8"/>`;
  s += `</svg>`;
  return mitKatze(s);
}

if (typeof window !== 'undefined') Object.assign(window, { UI_ICON_NAMES, uiIconSVG, FARB_NAMES, colorSymbolSVG, appIconSVG, appIconSquareSVG, adaptiveBackgroundSVG, adaptiveForegroundSVG, adaptiveMonochromeSVG, logoFullSVG, splashSVG });
