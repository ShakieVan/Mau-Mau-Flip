/* Mau-Mau Flip – Entwurf A: Logo (Querformat) und App-Symbol */
'use strict';

const LOGO_CARDS = {
  hell: { file: 'logo_hell', side: 'hell', color: 'rot', type: 'motiv' },
  dunkel: { file: 'logo_dunkel', side: 'dunkel', color: 'pink', type: 'motiv' },
};

function starField(seed, n, area, avoid = () => false, col = MOON) {
  const R = rng(seed);
  let s = '';
  for (let i = 0; i < n; i++) {
    const x = area.x + R() * area.w, y = area.y + R() * area.h;
    if (avoid(x, y)) continue;
    s += `<circle cx="${f1(x)}" cy="${f1(y)}" r="${f1(0.7 + R() * 1.9)}" fill="${col}" opacity="${(0.3 + R() * 0.6).toFixed(2)}"/>`;
  }
  return s;
}

/* Eingebettete Karte, gedreht um ihren Mittelpunkt */
function placedCard(c, cx, cy, w, rot, prefix, shadowId) {
  const h = w * CH / CW;
  const inner = cardSVG(c, { prefix, width: w }).replace('<svg ', `<svg x="${f1(-w / 2)}" y="${f1(-h / 2)}" `);
  return `<g transform="translate(${cx} ${cy}) rotate(${rot})">` +
    `<rect x="${f1(-w / 2 + 6)}" y="${f1(-h / 2 + 14)}" width="${w}" height="${f1(h)}" rx="${f1(w * CR / CW)}" fill="#000" opacity=".22" filter="url(#${shadowId})"/>` +
    inner + `</g>`;
}

/* ------------------------------------------------------------------ */
/* Logo 1600×900                                                       */
/* ------------------------------------------------------------------ */
function logoSVG(opt = {}) {
  const P = opt.prefix || 'lg-';
  const id = n => P + n;
  const W = 1600, H = 900;
  // Trennlinie Tag/Nacht (leicht schräg, läuft hinter der Katze und zwischen "Mau-Mau" und "Flip")
  const sx0 = 822, sx1 = 992;
  const DAY = `M0 0H${sx0}L${sx1} ${H}H0Z`, NIGHTP = `M${sx0} 0H${W}V${H}H${sx1}Z`;
  const imp = opt.standalone ? `<style><![CDATA[@import url('${FONT_CSS}');]]></style>` : '';
  let s = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${W} ${H}" width="${opt.width || W}" height="${f1((opt.width || W) * H / W)}">` +
    `<title>Mau-Mau Flip – Logo</title>${imp}`;
  s += `<defs>` +
    `<clipPath id="${id('tag')}"><path d="${DAY}"/></clipPath><clipPath id="${id('nacht')}"><path d="${NIGHTP}"/></clipPath>` +
    `<linearGradient id="${id('himmel')}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#1A1F48"/><stop offset=".7" stop-color="${NIGHT}"/></linearGradient>` +
    `<radialGradient id="${id('papierlicht')}" cx=".42" cy=".42" r=".7"><stop offset="0" stop-color="#FFF6E2"/><stop offset="1" stop-color="#EBDDC3"/></radialGradient>` +
    `<radialGradient id="${id('nachtlicht')}" cx=".75" cy=".42" r=".55"><stop offset="0" stop-color="#3A2A78" stop-opacity=".75"/><stop offset="1" stop-color="#3A2A78" stop-opacity="0"/></radialGradient>` +
    `<filter id="${id('schatten')}" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="10"/></filter>` +
    `<filter id="${id('glut')}" x="-20%" y="-40%" width="140%" height="180%"><feGaussianBlur stdDeviation="9" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>` +
    `<filter id="${id('glutweit')}" x="-20%" y="-60%" width="140%" height="220%"><feGaussianBlur stdDeviation="22"/></filter>` +
    `<filter id="${id('korn')}" x="0" y="0" width="100%" height="100%"><feTurbulence type="fractalNoise" baseFrequency=".85" numOctaves="2" seed="4" result="n"/><feColorMatrix in="n" type="matrix" values="0 0 0 0 .13  0 0 0 0 .1  0 0 0 0 .16  0 0 0 -1.6 1.05"/><feComposite in2="SourceGraphic" operator="in"/></filter>` +
    `</defs>`;

  /* Hintergrund Tag: Papier mit Sonnenstrahlen */
  let rays = '';
  const C = [560, 420];
  for (let i = 0; i < 36; i += 2) {
    const [x1, y1] = polar(C[0], C[1], 1800, i * 10), [x2, y2] = polar(C[0], C[1], 1800, i * 10 + 10);
    rays += `M${C[0]} ${C[1]}L${f1(x1)} ${f1(y1)}L${f1(x2)} ${f1(y2)}Z`;
  }
  s += `<g clip-path="url(#${id('tag')})"><rect width="${W}" height="${H}" fill="url(#${id('papierlicht')})"/>` +
    `<path d="${rays}" fill="#E2CFA9" opacity=".28"/>` +
    `<rect width="${W}" height="${H}" filter="url(#${id('korn')})" opacity=".12"/></g>`;
  /* Hintergrund Nacht: Sterne */
  s += `<g clip-path="url(#${id('nacht')})"><rect width="${W}" height="${H}" fill="url(#${id('himmel')})"/><rect width="${W}" height="${H}" fill="url(#${id('nachtlicht')})"/>` +
    starField(77, 170, { x: 800, y: 0, w: 800, h: 760 }, (x, y) => (x > 880 && x < 1160 && y < 210)) +
    [[1500, 90, 16], [1390, 250, 10], [1520, 520, 13], [1240, 70, 9], [1460, 700, 9]].map(([x, y, r]) => `<path d="${sparkle(x, y, r)}" fill="${MOON}" filter="url(#${id('glut')})"/>`).join('') +
    `</g>`;
  // Neonkante der Wendelinie
  s += `<path d="M${sx0} 0L${sx1} ${H}" stroke="#FF7FCF" stroke-width="3" filter="url(#${id('glut')})" opacity=".9"/>`;

  /* Karten hinter der Katze */
  s += placedCard(LOGO_CARDS.hell, 520, 405, 318, -12, P + "kh-", id("schatten"));
  s += placedCard(LOGO_CARDS.dunkel, 1118, 405, 318, 12, P + "kd-", id("schatten"));

  /* Katze: Illustration des Nutzers (katze_mau.png, 1209×1301 mit Alphakanal), Lage nach seiner Montage vom 04.10.2026 */
  const kw = 617, kh = 664;
  s += `<image id="${id('katze')}" href="katze_mau.png" x="516" y="68" width="${kw}" height="${kh}" preserveAspectRatio="xMidYMid meet"/>`;

  /* Sprechblase "Mau!" */
  const bx = 1090, by = 118;
  s += `<g>` +
    `<path d="M${bx - 112} ${by}C${bx - 112} ${by - 50} ${bx - 60} ${by - 66} ${bx} ${by - 66}C${bx + 70} ${by - 66} ${bx + 118} ${by - 46} ${bx + 118} ${by}C${bx + 118} ${by + 46} ${bx + 70} ${by + 62} ${bx} ${by + 62}C${bx - 22} ${by + 62} ${bx - 40} ${by + 60} ${bx - 56} ${by + 54}L${bx - 160} ${by + 122}L${bx - 92} ${by + 36}C${bx - 106} ${by + 26} ${bx - 112} ${by + 14} ${bx - 112} ${by}Z" fill="${CREAM}" stroke="${INK}" stroke-width="6" stroke-linejoin="round"/>` +
    `<text x="${bx + 4}" y="${by + 24}" text-anchor="middle" font-family="${F_BRAND}" font-weight="900" font-style="italic" font-size="70" style="font-variation-settings:'SOFT' 100,'WONK' 1" fill="${INK}">Mau!</text>` +
    `</g>`;

  /* Schriftzug: "Mau-Mau" auf Papier (Druckfarbe), "Flip" in der Nacht (Neon) */
  const ty = 842, fs = 138;
  const fv = `style="font-variation-settings:'SOFT' 100,'WONK' 0,'opsz' 144"`;
  s += `<text x="958" y="${ty}" text-anchor="end" font-family="${F_BRAND}" font-weight="900" font-size="${fs}" ${fv} fill="${INK}" letter-spacing="-2">Mau-Mau</text>`;
  s += `<g><text x="1012" y="${ty}" font-family="${F_BRAND}" font-weight="900" font-style="italic" font-size="${fs}" ${fv} fill="#FF5FC4" filter="url(#${id('glutweit')})" opacity=".9">Flip</text>` +
    `<text x="1012" y="${ty}" font-family="${F_BRAND}" font-weight="900" font-style="italic" font-size="${fs}" ${fv} fill="#FFF0FA" filter="url(#${id('glut')})">Flip</text></g>`;
  s += `</svg>`;
  return s;
}

/* ------------------------------------------------------------------ */
/* App-Symbol 512×512                                                  */
/* ------------------------------------------------------------------ */
function iconSVG(opt = {}) {
  const P = opt.prefix || 'ic-';
  const id = n => P + n;
  const S = 512;
  const w = opt.width || S;
  const imp = opt.standalone ? `<style><![CDATA[@import url('${FONT_CSS}');]]></style>` : '';
  const DAY = `M0 0H300L212 ${S}H0Z`, NIGHTP = `M300 0H${S}V${S}H212Z`;
  let s = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${S} ${S}" width="${w}" height="${w}">` +
    `<title>Mau-Mau Flip – App-Symbol</title>${imp}`;
  s += `<defs><clipPath id="${id('form')}"><rect width="${S}" height="${S}" rx="112"/></clipPath>` +
    `<clipPath id="${id('tag')}"><path d="${DAY}"/></clipPath><clipPath id="${id('nacht')}"><path d="${NIGHTP}"/></clipPath>` +
    `<linearGradient id="${id('himmel')}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#26205A"/><stop offset="1" stop-color="${NIGHT}"/></linearGradient>` +
    `<radialGradient id="${id('papier')}" cx=".3" cy=".3" r=".8"><stop offset="0" stop-color="#FFF6E2"/><stop offset="1" stop-color="#EAD9BA"/></radialGradient>` +
    `<radialGradient id="${id('sonne')}" cx=".4" cy=".38" r=".7"><stop offset="0" stop-color="#FFF3B0"/><stop offset=".55" stop-color="#FFC93C"/><stop offset="1" stop-color="#F29A1F"/></radialGradient>` +
    `<radialGradient id="${id('sonnenhof')}"><stop offset=".45" stop-color="#FFC93C" stop-opacity=".55"/><stop offset="1" stop-color="#FFC93C" stop-opacity="0"/></radialGradient>` +
    `<filter id="${id('glut')}" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="5" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>` +
    `</defs>`;
  s += `<g clip-path="url(#${id('form')})">`;
  // Tag
  let rays = '';
  for (let i = 0; i < 36; i += 2) {
    const [x1, y1] = polar(84, 84, 900, i * 10), [x2, y2] = polar(84, 84, 900, i * 10 + 10);
    rays += `M84 84L${f1(x1)} ${f1(y1)}L${f1(x2)} ${f1(y2)}Z`;
  }
  s += `<g clip-path="url(#${id('tag')})"><rect width="${S}" height="${S}" fill="url(#${id('papier')})"/><path d="${rays}" fill="#E0CBA2" opacity=".35"/>` +
    `<circle cx="80" cy="88" r="58" fill="url(#${id('sonnenhof')})"/><circle cx="80" cy="88" r="34" fill="url(#${id('sonne')})"/></g>`;
  // Nacht
  s += `<g clip-path="url(#${id('nacht')})"><rect width="${S}" height="${S}" fill="url(#${id('himmel')})"/>` +
    starField(9, 50, { x: 200, y: 0, w: 312, h: 330 }) +
    `<path d="M438 40A40 40 0 1 0 474 100A33 33 0 1 1 438 40Z" fill="#FFE3F4" filter="url(#${id('glut')})"/>` +
    `<path d="${sparkle(352, 50, 10)}" fill="${MOON}" filter="url(#${id('glut')})"/></g>`;
  s += `<path d="M300 0L212 ${S}" stroke="#FF7FCF" stroke-width="2.5" opacity=".8" filter="url(#${id('glut')})"/>`;
  // Katze als Büste: Ausschnitt (Kopf und Pfote) aus der Illustration des Nutzers, unten angeschnitten
  const ks = opt.catScale || 0.66, kx = opt.catX ?? -113, ky = opt.catY ?? 57;
  s += `<image id="${id('katze')}" href="katze_mau.png" x="${kx}" y="${ky}" width="${f1(1209 * ks)}" height="${f1(1301 * ks)}"/>`;
  s += `</g>`;
  s += `<rect x="1.5" y="1.5" width="${S - 3}" height="${S - 3}" rx="111" fill="none" stroke="#000" stroke-opacity=".12" stroke-width="3"/>`;
  s += `</svg>`;
  return s;
}

if (typeof window !== 'undefined') { window.logoSVG = logoSVG; window.iconSVG = iconSVG; }
