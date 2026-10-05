/* Mau-Mau Flip – Produktionssatz der Karten (docs/BETA1_PLAN.md Abschnitt 3)
 * Alle 108 Gesichter mit den exakten Schlüsseln plus die neutrale Rückseite "rueckseite".
 * Die Gesichter zeichnet unverändert cardSVG() aus mmf.js (Entwurf A, Nutzerwunsch: Karten nicht ändern).
 * Neu ist nur die Rückseite: diagonal geteilt Tag/Nacht, Sonne und Mond, kleine Wortmarke. Ohne Spielinformation.
 */
'use strict';

const HELL_FARBEN = ['rot', 'gelb', 'gruen', 'blau'];
const DUNKEL_FARBEN = ['pink', 'tuerkis', 'orange', 'lila'];
const RUECKSEITE = 'rueckseite';

/* Alle 108 Gesichter, Reihenfolge: hell je Farbe 1–9, +1, Aussetzen, Richtungswechsel, Flip, dann Joker; dunkel ebenso */
function deckFaces() {
  const out = [];
  for (const f of HELL_FARBEN) {
    for (let n = 1; n <= 9; n++) out.push({ file: `hell_${f}_${n}`, side: 'hell', color: f, type: 'num', v: String(n) });
    out.push({ file: `hell_${f}_plus1`, side: 'hell', color: f, type: 'zieh', v: '+1' });
    out.push({ file: `hell_${f}_aussetzen`, side: 'hell', color: f, type: 'aussetzen' });
    out.push({ file: `hell_${f}_richtungswechsel`, side: 'hell', color: f, type: 'wende' });
    out.push({ file: `hell_${f}_flip`, side: 'hell', color: f, type: 'flip' });
  }
  out.push({ file: 'hell_wuenscher', side: 'hell', type: 'wunsch' });
  out.push({ file: 'hell_wuenscher_plus2', side: 'hell', type: 'wunsch2', v: '+2' });
  for (const f of DUNKEL_FARBEN) {
    for (let n = 1; n <= 9; n++) out.push({ file: `dunkel_${f}_${n}`, side: 'dunkel', color: f, type: 'num', v: String(n) });
    out.push({ file: `dunkel_${f}_plus5`, side: 'dunkel', color: f, type: 'zieh', v: '+5' });
    out.push({ file: `dunkel_${f}_alle_aussetzen`, side: 'dunkel', color: f, type: 'alle' });
    out.push({ file: `dunkel_${f}_richtungswechsel`, side: 'dunkel', color: f, type: 'wende' });
    out.push({ file: `dunkel_${f}_flip`, side: 'dunkel', color: f, type: 'flip' });
  }
  out.push({ file: 'dunkel_wuenscher', side: 'dunkel', type: 'wunsch' });
  out.push({ file: 'dunkel_farbjagd', side: 'dunkel', type: 'jagd', v: '?' });
  return out;
}

/* Alle 109 Schlüssel (108 Gesichter + Rückseite) */
function allKeys() { return deckFaces().map(c => c.file).concat([RUECKSEITE]); }

/* ------------------------------------------------------------------ */
/* Neutrale Rückseite                                                  */
/* ------------------------------------------------------------------ */
// Naht von rechts oben nach links unten durch die Kartenmitte: links oben Tag (Papier), rechts unten Nacht.
const NAHT = { x0: CW, y0: 150, x1: 0, y1: 720 };

function backSVG(opt = {}) {
  const P = opt.prefix || '';
  const id = n => P + n;
  const N = NAHT;
  const TAGP = `M-10 -10H${CW + 10}V${N.y0}L${N.x1} ${N.y1}H-10Z`;
  const NACHTP = `M${CW + 10} ${N.y0}V${CH + 10}H-10V${N.y1}L${N.x0} ${N.y0}Z`;
  const ang = Math.atan2(N.y0 - N.y1, N.x0 - N.x1) * 180 / Math.PI;   // ≈ −45,5°: Schrift läuft entlang der Naht
  const mx = (N.x0 + N.x1) / 2, my = (N.y0 + N.y1) / 2;
  const SO = { x: 150, y: 236, r: 58 }, MO = { x: 410, y: 634, r: 60 }; // Sonne links oben, Mond rechts unten (punktsymmetrisch)
  let s = svgOpen(P, 'Rückseite (neutral)', opt);
  s += `<defs>` +
    `<clipPath id="${id('tag')}"><path d="${TAGP}"/></clipPath><clipPath id="${id('nacht')}"><path d="${NACHTP}"/></clipPath>` +
    `<radialGradient id="${id('papierlicht')}" cx=".3" cy=".25" r=".9"><stop offset="0" stop-color="#FFF6E2"/><stop offset="1" stop-color="#E9D9BC"/></radialGradient>` +
    `<linearGradient id="${id('himmel')}" x1="0" y1="0" x2=".4" y2="1"><stop offset="0" stop-color="#202656"/><stop offset=".55" stop-color="${NIGHT_HI}"/><stop offset="1" stop-color="${NIGHT}"/></linearGradient>` +
    `<radialGradient id="${id('sonne')}" cx=".4" cy=".38" r=".7"><stop offset="0" stop-color="#FFF3B0"/><stop offset=".55" stop-color="#FFC93C"/><stop offset="1" stop-color="#F29A1F"/></radialGradient>` +
    `<radialGradient id="${id('sonnenhof')}"><stop offset=".45" stop-color="#FFC93C" stop-opacity=".45"/><stop offset="1" stop-color="#FFC93C" stop-opacity="0"/></radialGradient>` +
    `<radialGradient id="${id('mondhof')}"><stop offset=".5" stop-color="#FF7FCF" stop-opacity=".16"/><stop offset="1" stop-color="#FF7FCF" stop-opacity="0"/></radialGradient>` +
    `<filter id="${id('glut')}" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="6" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>` +
    `<filter id="${id('glutklein')}" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="3.5" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>` +
    `<filter id="${id('glutweit')}" x="-60%" y="-60%" width="220%" height="220%"><feGaussianBlur stdDeviation="14"/></filter>` +
    `<filter id="${id('korn')}" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="17" result="n"/><feColorMatrix in="n" type="matrix" values="0 0 0 0 0.13  0 0 0 0 0.10  0 0 0 0 0.16  0 0 0 -1.6 1.05" result="a"/><feComposite in="a" in2="SourceGraphic" operator="in"/></filter>` +
    `<clipPath id="${id('karte')}"><rect width="${CW}" height="${CH}" rx="${CR}"/></clipPath>` +
    `</defs>`;

  s += `<g clip-path="url(#${id('karte')})">`;
  /* Tag: Papier mit leisen Sonnenstrahlen */
  let rays = '';
  for (let i = 0; i < 32; i += 2) {
    const [x1, y1] = polar(SO.x, SO.y, 1400, i * 360 / 32), [x2, y2] = polar(SO.x, SO.y, 1400, (i + 1) * 360 / 32);
    rays += `M${SO.x} ${SO.y}L${f1(x1)} ${f1(y1)}L${f1(x2)} ${f1(y2)}Z`;
  }
  s += `<g id="${id('tagseite')}" clip-path="url(#${id('tag')})">` +
    `<rect x="-10" y="-10" width="${CW + 20}" height="${CH + 20}" fill="url(#${id('papierlicht')})"/>` +
    `<path d="${rays}" fill="#E2CFA9" opacity=".30"/>` +
    `<circle cx="${SO.x}" cy="${SO.y}" r="${SO.r * 1.75}" fill="url(#${id('sonnenhof')})"/>` +
    `<circle cx="${SO.x}" cy="${SO.y}" r="${SO.r}" fill="url(#${id('sonne')})"/>` +
    `<rect width="${CW}" height="${CH}" filter="url(#${id('korn')})" opacity=".16" style="mix-blend-mode:multiply"/>` +
    `</g>`;
  /* Nacht: Sterne und Mondsichel */
  s += `<g id="${id('nachtseite')}" clip-path="url(#${id('nacht')})">` +
    `<rect x="-10" y="-10" width="${CW + 20}" height="${CH + 20}" fill="url(#${id('himmel')})"/>`;
  const R = rng(4711);
  for (let i = 0; i < 70; i++) {
    const x = R() * CW, y = 120 + R() * (CH - 120);
    const r0 = 0.8 + R() * 1.9, op = 0.3 + R() * 0.55;
    if (Math.hypot(x - MO.x, y - MO.y) < MO.r + 26) continue;
    s += `<circle cx="${f1(x)}" cy="${f1(y)}" r="${f1(r0)}" fill="${MOON}" opacity="${op.toFixed(2)}"/>`;
  }
  for (const [x, y, r] of [[488, 452, 13], [250, 760, 10], [512, 812, 8], [318, 560, 7]]) s += `<path d="${sparkle(x, y, r)}" fill="${MOON}" filter="url(#${id('glutklein')})"/>`;
  const mr = MO.r;
  s += `<circle cx="${MO.x}" cy="${MO.y}" r="${f1(mr * 1.8)}" fill="url(#${id('mondhof')})"/>` +
    `<path d="M${MO.x} ${MO.y - mr}A${mr} ${mr} 0 1 0 ${f1(MO.x + mr * 0.98)} ${f1(MO.y + mr * 0.2)}A${f1(mr * 0.82)} ${f1(mr * 0.82)} 0 1 1 ${MO.x} ${MO.y - mr}Z" fill="#FFE3F4" filter="url(#${id('glut')})"/>` +
    `</g>`;
  /* Naht: Neonkante wie im Logo */
  s += `<path d="M${N.x0 + 20} ${f1(N.y0 - 20 * (N.y1 - N.y0) / (N.x1 - N.x0))}L${N.x1 - 20} ${f1(N.y1 + 20 * (N.y1 - N.y0) / (N.x1 - N.x0))}" stroke="#FF7FCF" stroke-width="4" filter="url(#${id('glut')})" opacity=".9"/>`;
  /* Wortmarke entlang der Naht: "Mau-Mau" in Druckfarbe auf dem Tag, "Flip" als Neon in der Nacht */
  const fv = `style="font-variation-settings:'SOFT' 100,'WONK' 0,'opsz' 72"`;
  s += `<g transform="translate(${mx} ${my}) rotate(${ang.toFixed(2)})">` +
    `<text x="0" y="-16" text-anchor="middle" font-family="${F_BRAND}" font-weight="900" font-size="62" ${fv} fill="${INK}" letter-spacing="-1">Mau-Mau</text>` +
    `<text x="0" y="56" text-anchor="middle" font-family="${F_BRAND}" font-weight="900" font-style="italic" font-size="62" ${fv} fill="#FF5FC4" filter="url(#${id('glutweit')})" opacity=".85">Flip</text>` +
    `<text x="0" y="56" text-anchor="middle" font-family="${F_BRAND}" font-weight="900" font-style="italic" font-size="62" ${fv} fill="#FFF0FA" filter="url(#${id('glutklein')})">Flip</text>` +
    `</g>`;
  s += `</g>`;
  /* Rahmen: feine Innenkante, auf dem Tag in Druckfarbe, in der Nacht als Neonlinie */
  const inner = `<rect x="22" y="22" width="${CW - 44}" height="${CH - 44}" rx="${CR - 16}" fill="none"`;
  s += `<g id="${id('rahmen')}">` +
    `<g clip-path="url(#${id('tag')})">${inner} stroke="${INK}" stroke-width="3" opacity=".55"/></g>` +
    `<g clip-path="url(#${id('nacht')})">${inner} stroke="#FF7FCF" stroke-width="3" opacity=".75" filter="url(#${id('glutklein')})"/></g>` +
    `<rect x="1.5" y="1.5" width="${CW - 3}" height="${CH - 3}" rx="${CR - 1.5}" fill="none" stroke="#000" stroke-opacity=".18" stroke-width="3"/>` +
    `</g>`;
  s += `</svg>`;
  return s;
}

/* Gesicht oder Rückseite als SVG */
function faceSVG(key, opt = {}) {
  if (key === RUECKSEITE) return backSVG(opt);
  const c = deckFaces().find(f => f.file === key);
  if (!c) throw new Error('Unbekannter Kartenschlüssel ' + key);
  return cardSVG(c, opt);
}

if (typeof window !== 'undefined') { window.deckFaces = deckFaces; window.allKeys = allKeys; window.backSVG = backSVG; window.faceSVG = faceSVG; }
