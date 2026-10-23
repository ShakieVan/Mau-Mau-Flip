/* Mau-Mau Flip (Beta 1.6.12): „Natur-Überraschungen“ im Browser-Client „Lite“ – die Nachttiere (docs/module/natur.md 3.3, Aufgabe T6).
 * Glühwürmchen, Eule, Fledermaus, Mond mit Schlafmütze, Polarlicht, Katzen-Sternbild, UFO, Satellit, Motte, Igel, Komet, Lampion und
 * die Sternschnuppe (Bestand, im leuchtenden Stil der App: game/scripts/ui/shooting_star_fx.gd); ab 1.6.15 Feuerwerk und Astronaut am
 * Mond, das UFO ist nicht mehr scheu (weicht zweimal aus, der dritte Tipp verscheucht es).
 * Vertrag und Hilfen: Dateikopf von webclient/natur.js (M.Natur.art(id, {baue(ctx, zufall)}), M.Natur.stil, M.Natur.h).
 * Alles selbst gezeichnet (Inline-SVG und CSS-Verläufe), kein Ton, kein Text, kein Netz, kein filter/backdrop-filter.
 * stelle(t) ist rein in t (gleicher Samen + gleiches t = gleiches Bild); Reaktionen auf Tipp und Abgang laufen ab der gemerkten Zeit.
 * Per Bild gesetzt werden nur transform (Stil oder SVG-Attribut) und opacity; Flügelschlag und Lichterkette sind CSS-Schleifen
 * (Klasse nt-schleife, unter body.reduziert still). Ruhige Varianten (Effekte reduziert): Mond mit Mütze, Polarlicht, Sternbild.
 * Zusätzlich zu den Schutzflächen des Kerns meiden Igel und Glühwürmchen die Reaktionsknöpfe (.nk-leiste, ab 1.6.13 sieben Knöpfe als Block 4 + 3).
 */
(function (M) {
  'use strict';
  const N = M.Natur;
  if (!N || !N.art) return;
  const { el, klemme, lerp, glatt } = N.h;
  const TAU = Math.PI * 2, RAD = Math.PI / 180;
  const INK = '#211B2C', RING = '#9A86FF', NACHT = '#0A0D20', CREME = '#FFF7E8';

  /* ---------- Hilfen ---------- */
  let lfd = 0;
  const uid = s => 'ntn' + (++lfd) + s;
  const zz = (z, a, b) => a + z() * (b - a);
  const n1 = v => String(Math.round(v * 10) / 10);
  const ein = (t, a, d) => (d <= 0 ? (t >= a ? 1 : 0) : klemme((t - a) / d, 0, 1));
  const ausAb = (t, a, d) => 1 - ein(t, a, d);
  const raus = u => 1 - (1 - u) * (1 - u);          // bremst ab
  const rein = u => u * u;                          // beschleunigt
  const kasten = (x, y, w, h) => ({ x: x - w / 2, y: y - h / 2, w, h });
  const abstandRect = (p, r) => Math.hypot(Math.max(r.x - p.x, 0, p.x - (r.x + r.w)), Math.max(r.y - p.y, 0, p.y - (r.y + r.h)));
  const flaeche = (a, b) => Math.max(0, Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)) * Math.max(0, Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y));
  const bez2 = (a, c, b, u) => ({ x: (1 - u) * (1 - u) * a.x + 2 * (1 - u) * u * c.x + u * u * b.x, y: (1 - u) * (1 - u) * a.y + 2 * (1 - u) * u * c.y + u * u * b.y });
  const bez3 = (a, b, c, d, u) => { const v = 1 - u; return { x: v * v * v * a.x + 3 * v * v * u * b.x + 3 * v * u * u * c.x + u * u * u * d.x, y: v * v * v * a.y + 3 * v * v * u * b.y + 3 * v * u * u * c.y + u * u * u * d.y }; };
  // SVG mit eigenem Ursprung: Nutzerkoordinaten (0, 0) liegen auf dem Ursprung des Wurzel-Elements
  function svg(x0, y0, w, h, inner, cls) {
    return '<svg class="nt-svg' + (cls ? ' ' + cls : '') + '" width="' + w + '" height="' + h + '" viewBox="' + x0 + ' ' + y0 + ' ' + w + ' ' + h
      + '" style="left:' + x0 + 'px;top:' + y0 + 'px" xmlns="http://www.w3.org/2000/svg">' + inner + '</svg>';
  }
  const wesen = (html, cls) => el('div', cls || '', html);
  // transform (SVG-Attribut) bzw. opacity nur bei Änderung setzen
  function T(e, s) { if (e && e._ntT !== s) { e._ntT = s; e.setAttribute('transform', s); } }
  function O(e, a) { if (!e) return; const v = String(Math.round(klemme(a, 0, 1) * 1000) / 1000); if (e._ntO !== v) { e._ntO = v; e.style.opacity = v; } }
  function S(e, x, y, rot, sk, op) { N.h.setze(e, x, y, rot, sk, op); }
  const tr = (x, y, rot, sx, sy) => 'translate(' + n1(x) + ' ' + n1(y) + ')' + (rot ? ' rotate(' + n1(rot) + ')' : '')
    + (sx !== undefined && (sx !== 1 || (sy !== undefined && sy !== 1)) ? ' scale(' + (Math.round(sx * 1000) / 1000) + ' ' + (Math.round((sy === undefined ? sx : sy) * 1000) / 1000) + ')' : '');
  // Reaktionsknöpfe (.nk-leiste) als zusätzliche Schutzfläche (der Kern kennt sie nicht)
  function extraSchutz() {
    const t = N.app && N.app.tisch, out = [];
    if (!t || !t.zuBuehne) return out;
    document.querySelectorAll('.nk-leiste').forEach(e => {
      if (e.hidden) return;
      const r = e.getBoundingClientRect();
      if (r.width <= 0 || r.height <= 0) return;
      const a = t.zuBuehne(r.left, r.top), b = t.zuBuehne(r.right, r.bottom);
      out.push({ name: 'reaktion', x: a.x - 6, y: a.y - 6, w: b.x - a.x + 12, h: b.y - a.y + 12 });
    });
    return out;
  }
  const ueberdeckt = (r, liste) => liste.reduce((s, q) => s + flaeche(r, q), 0);
  // freiester Winkel auf dem Band (eigene Wahl, damit auch die Reaktionsknöpfe zählen)
  function bandWahl(ctx, z, bereiche, quer, hoehe) {
    const schutz = ctx.schutz.concat(extraSchutz());
    let best = bereiche[0][0], bw = -1e9;
    bereiche.forEach(([a, b]) => {
      for (let g = a; g <= b + 1e-6; g += 5) {
        const p = ctx.band(g, quer), c = { x: p.x, y: p.y - hoehe / 2 };
        let d = 1e9;
        schutz.forEach(q => { d = Math.min(d, abstandRect(c, q)); });
        ctx.plaetze.forEach(q => { d = Math.min(d, Math.hypot(c.x - q.x, c.y - q.y) - Math.max(q.w, q.h) / 2); });
        if (c.x < 60 || c.x > ctx.W - 60) d -= 300;
        const s = Math.min(d, 150) + z() * 10;
        if (s > bw) { bw = s; best = g; }
      }
    });
    return best;
  }
  // Bogenlängen-Tabelle entlang des Bands (für Igel): Punkte von g0 bis g1 in kleinen Schritten
  function bandBahn(ctx, g0, g1, quer) {
    const pts = [], n = Math.max(8, Math.ceil(Math.abs(g1 - g0) / 0.5));
    let s = 0, alt = null;
    for (let i = 0; i <= n; i++) {
      const g = lerp(g0, g1, i / n), p = ctx.band(g, quer);
      if (alt) s += Math.hypot(p.x - alt.x, p.y - alt.y);
      pts.push({ g, x: p.x, y: p.y, s });
      alt = p;
    }
    return { pts, laenge: s };
  }
  function bahnPunkt(b, s) {
    const p = b.pts;
    s = klemme(s, 0, b.laenge);
    let lo = 0, hi = p.length - 1;
    while (hi - lo > 1) { const m = (lo + hi) >> 1; if (p[m].s <= s) lo = m; else hi = m; }
    const a = p[lo], c = p[hi], u = c.s > a.s ? (s - a.s) / (c.s - a.s) : 0;
    return { x: lerp(a.x, c.x, u), y: lerp(a.y, c.y, u), dx: c.x - a.x, dy: c.y - a.y };
  }

  N.stil('nacht', [
    '.nt-svg{position:absolute;overflow:visible;display:block}',
    '.nt-glanz{mix-blend-mode:screen}',
    '.nt-wesen i.nt-gw{position:absolute;left:-32px;top:-32px;width:64px;height:64px;border-radius:50%;mix-blend-mode:screen;will-change:transform,opacity;'
      + 'background:radial-gradient(circle,#FFFFF4 0,#F2FFB4 3px,#E2FF7A 4.6px,rgba(216,255,106,.6) 9px,rgba(216,255,106,.26) 17px,rgba(216,255,106,.08) 26px,rgba(216,255,106,0) 32px)}',
    '@keyframes nt-fmflap{0%{opacity:1}50%{opacity:0}}',
    '.nt-fm .fa{animation:nt-fmflap .125s steps(1,end) infinite}',
    '.nt-fm .fb{opacity:0;animation:nt-fmflap .125s steps(1,end) -.0625s infinite}',
    '@keyframes nt-mflap{0%,100%{transform:scaleX(1)}50%{transform:scaleX(.28)}}',
    '.nt-motte .fl{animation:nt-mflap .072s linear infinite}',
    '@keyframes nt-li{0%,16%{opacity:1}34%,100%{opacity:.28}}',
    '.nt-ufo .li{animation:nt-li .8s linear infinite}',
    '.nt-pl{position:absolute;left:0;top:0;transform-origin:50% 100%;will-change:transform,opacity;mix-blend-mode:screen}',
    '.nt-halo{position:absolute;border-radius:50%;mix-blend-mode:screen;will-change:transform,opacity}',
  ].join('\n'));

  /* ================================================================ 12 Glühwürmchen (Idee des Nutzers) */
  N.art('gluehwuermchen', {
    baue(ctx, z) {
      const o = ctx.ort, W = ctx.W;
      const dauer = zz(z, 12, 15);
      const schutz = ctx.schutz.concat(extraSchutz());
      // ein loser Schwarm an einer freien Stelle des Rings um den Tisch
      let mitte = null, ms = Infinity;
      for (let i = 0; i < 60; i++) {
        const a = z() * TAU, f = lerp(o.f0, o.f1, z());
        const x = o.cx + Math.cos(a) * o.rx * f, y = o.cy + Math.sin(a) * o.ry * f;
        if (y > o.ymax - 50 || y < 100 || x < 150 || x > W - 150) continue;
        const s = ueberdeckt({ x: x - 130, y: y - 85, w: 260, h: 170 }, schutz) + z() * 1500;
        if (s < ms) { ms = s; mitte = { x, y }; }
      }
      if (!mitte) mitte = { x: W * 0.3, y: Math.max(140, o.cy - o.ry * 1.2) };
      const n = 6 + Math.floor(z() * 4), tiere = [];
      for (let i = 0; i < n; i++) {
        let best = null, bd = -1e9;
        for (let k = 0; k < 14; k++) {
          const a = z() * TAU, r = Math.sqrt(z());
          const p = { x: mitte.x + Math.cos(a) * r * 125, y: mitte.y + Math.sin(a) * r * 78 };
          let d = 1e9;
          schutz.forEach(q => { d = Math.min(d, abstandRect(p, q) * 1.5); });
          tiere.forEach(q => { d = Math.min(d, Math.hypot(q.bx - p.x, q.by - p.y)); });
          if (d > bd) { bd = d; best = p; }
        }
        tiere.push({
          bx: best.x, by: best.y, ax: zz(z, 14, 24), wx: zz(z, 0.45, 0.8), px: z() * TAU, ay: zz(z, 8, 15), wy: zz(z, 0.5, 0.9), py: z() * TAU,
          bx2: zz(z, 4, 8), wx2: zz(z, 1.2, 1.9), px2: z() * TAU, by2: zz(z, 3, 6), wy2: zz(z, 1.3, 2.1), py2: z() * TAU,
          per: zz(z, 1.4, 3), ph: z(), ein: zz(z, 0, 2), wink: z() * TAU,
        });
      }
      const root = wesen(tiere.map(() => '<i class="nt-gw"></i>').join(''));
      const els = Array.from(root.children);
      const inst = { el: root, dauer, cur: 0, tapT: null, tapP: null, leaveT: null };
      const lage = t => tiere.map(f => {
        let x = f.bx + f.ax * Math.sin(f.wx * t + f.px) + f.bx2 * Math.sin(f.wx2 * t + f.px2);
        let y = f.by + f.ay * Math.sin(f.wy * t + f.py) + f.by2 * Math.sin(f.wy2 * t + f.py2);
        const s = 0.5 + 0.5 * Math.sin(TAU * (t / f.per + f.ph));
        let b = 0.3 + 0.7 * s * s * s;
        let a = ein(t, f.ein, 0.8) * klemme((inst.dauer - t) / 2, 0, 1);
        let sk = 0.72 + 0.42 * b;
        if (inst.tapT !== null && t >= inst.tapT) {   // stieben auseinander und verlöschen
          const u = klemme((t - inst.tapT) / 0.8, 0, 1);
          let dx = x - inst.tapP.x, dy = y - inst.tapP.y;
          const l = Math.hypot(dx, dy);
          if (l < 1) { dx = Math.cos(f.wink); dy = Math.sin(f.wink); } else { dx /= l; dy /= l; }
          const weg = 165 * raus(u);
          x += dx * weg - dy * 18 * Math.sin(u * 5 + f.wink);
          y += dy * weg + dx * 18 * Math.sin(u * 5 + f.wink);
          b = Math.min(1, b + 0.8 * (1 - u));
          a = Math.min(a, ein(inst.tapT, f.ein, 0.8)) * Math.pow(1 - u, 1.2);
          sk = 0.8 + 0.5 * (1 - u);
        }
        if (inst.leaveT !== null) a *= klemme(1 - (t - inst.leaveT) / 0.38, 0, 1);
        return { x, y, op: a * b, sk };
      });
      inst.stelle = t => {
        inst.cur = t;
        lage(t).forEach((p, i) => S(els[i], p.x, p.y, 0, p.sk, p.op));
      };
      inst.hulle = t => {
        const sicht = lage(t).filter(p => p.op > 0.04);
        if (!sicht.length) return null;
        let l = 1e9, o2 = 1e9, r = -1e9, u = -1e9;
        sicht.forEach(p => { l = Math.min(l, p.x); r = Math.max(r, p.x); o2 = Math.min(o2, p.y); u = Math.max(u, p.y); });
        return { x: l - 13, y: o2 - 13, w: r - l + 26, h: u - o2 + 26 };
      };
      inst.treffer = p => lage(inst.cur).some(q => q.op > 0.03 && Math.hypot(q.x - p.x, q.y - p.y) <= 60);
      inst.tipp = p => { inst.tapT = inst.cur; inst.tapP = { x: p.x, y: p.y }; inst.dauer = Math.min(inst.dauer, inst.cur + 0.85); };
      inst.abgang = () => { inst.leaveT = inst.cur; return 0.4; };
      return inst;
    },
  });

  /* ================================================================ 13 Eule (Idee des Nutzers) */
  const EU = { koerper: '#4A3B63', brust: '#7A6A92', gesicht: '#8C7BA6', fluegel: '#2C2145', iris: '#FFB627', schnabel: '#E8C46A' };
  function euleSvg(id) {
    const fl = 'M9,-37 C22,-51 40,-57 58,-51 C53,-47 52,-44 47,-42 C49,-38 45,-35 40,-35 C41,-31 36,-29 32,-30 C30,-26 24,-26 20,-29 C16,-31 12,-32 9,-31 Z';
    const flF = 'M21,-43 C31,-48 41,-50 51,-49 M19,-37 C28,-40 35,-41 42,-41 M16,-32 C21,-34 26,-35 31,-35';
    const flugel = '<path d="' + fl + '" fill="' + EU.fluegel + '" stroke="' + RING + '" stroke-width="1.5" stroke-linejoin="round"/>'
      + '<path d="' + flF + '" fill="none" stroke="#6E5C92" stroke-width="1.2" stroke-linecap="round"/>';
    const fw = 'M-18,-35 C-25,-22 -22,-8 -12,-2 C-15,-12 -15,-24 -11,-36 Z';
    const fwF = 'M-18,-26 C-17,-20 -15,-14 -13,-9';
    const falte = '<path d="' + fw + '" fill="' + EU.fluegel + '" stroke="' + RING + '" stroke-width="1.3" stroke-linejoin="round"/>'
      + '<path d="' + fwF + '" fill="none" stroke="#8371B0" stroke-width="1.1" stroke-linecap="round"/>';
    const kralle = x => '<path d="M' + (x - 3) + ',-1 l-.6,3.4 M' + x + ',-1 l0,3.8 M' + (x + 3) + ',-1 l.6,3.4" stroke="' + EU.schnabel + '" stroke-width="1.8" stroke-linecap="round" fill="none"/>';
    const v = (x, y) => '<path d="M' + (x - 2.6) + ',' + y + ' l2.6,2.4 l2.6,-2.4" fill="none" stroke="#5A4A76" stroke-width="1.2" stroke-linecap="round" stroke-linejoin="round"/>';
    const auge = (x, s) => '<circle cx="' + x + '" cy="-50" r="6.6" fill="' + EU.iris + '" stroke="' + INK + '" stroke-width=".8"/>'
      + '<g class="p' + s + '"><circle cx="' + x + '" cy="-50" r="3.4" fill="' + INK + '"/><circle cx="' + (x + 1.5) + '" cy="-51.6" r="1.3" fill="#fff"/></g>'
      + '<g transform="translate(' + x + ' -56.8)"><g class="l' + s + '" transform="scale(1 0)"><circle cx="0" cy="6.8" r="7" fill="' + EU.gesicht + '" stroke="#5A4A76" stroke-width=".8"/></g></g>';
    return svg(-70, -90, 140, 100,
      '<defs><radialGradient id="' + id + 'b" cx=".5" cy=".35" r=".7"><stop offset="0" stop-color="#5C4B7A"/><stop offset="1" stop-color="' + EU.koerper + '"/></radialGradient></defs>'
      + '<g class="fl"><g class="fr">' + flugel + '</g><g transform="scale(-1 1)"><g class="fr2">' + flugel + '</g></g></g>'
      + '<g class="fu">' + kralle(-7) + kralle(7) + '</g>'
      + '<path d="M0,-45 C14,-45 21,-31 21,-19 C21,-7 12,0 0,0 C-12,0 -21,-7 -21,-19 C-21,-31 -14,-45 0,-45 Z" fill="url(#' + id + 'b)" stroke="' + RING + '" stroke-width="1.6"/>'
      + '<ellipse cx="0" cy="-17" rx="12.5" ry="13.5" fill="' + EU.brust + '"/>'
      + v(-5, -26) + v(5, -26) + v(0, -20) + v(-7, -16) + v(7, -16) + v(-3, -10) + v(3, -10)
      + '<g class="wf">' + falte + '<g transform="scale(-1 1)">' + falte + '</g></g>'
      + '<g class="kopf">'
      + '<path class="oh" d="M-17,-61 L-23,-75 L-9,-64 Z M17,-61 L23,-75 L9,-64 Z" fill="' + EU.koerper + '" stroke="' + RING + '" stroke-width="1.4" stroke-linejoin="round"/>'
      + '<path d="M0,-68 C15,-68 24,-60 24,-49 C24,-38 13,-34 0,-34 C-13,-34 -24,-38 -24,-49 C-24,-60 -15,-68 0,-68 Z" fill="url(#' + id + 'b)" stroke="' + RING + '" stroke-width="1.6"/>'
      + '<g class="gs"><path d="M0,-41 C-6,-37 -19,-39 -20,-50 C-20,-58 -12,-61 -6,-59 C-3,-58 -1,-56 0,-55 C1,-56 3,-58 6,-59 C12,-61 20,-58 20,-50 C19,-39 6,-37 0,-41 Z" fill="' + EU.gesicht + '"/>'
      + auge(-9, 'a') + auge(9, 'b')
      + '<path d="M0,-47 L-3,-43.5 L0,-38.5 L3,-43.5 Z" fill="' + EU.schnabel + '" stroke="' + INK + '" stroke-width=".7" stroke-linejoin="round"/></g>'
      + '</g>');
  }
  N.art('eule', {
    baue(ctx, z) {
      const dauer = zz(z, 12, 16), SK = 1.25;
      const land = ctx.band(ctx.ort.grad, 0.42);
      const seite = land.x < ctx.cx ? -1 : 1;
      const p0 = { x: land.x + seite * 210, y: -80 }, c0 = { x: land.x + seite * 40, y: land.y - 190 };
      const pAus = { x: land.x + seite * 260, y: -110 }, cAus = { x: land.x + seite * 70, y: land.y - 70 };
      const ziel = ctx.plaetze.find(p => p.seat === ctx.troedler) || null;
      const blinks = [];
      for (let tb = 2.3 + z(); tb < dauer - 1.3; tb += zz(z, 3, 4)) blinks.push(tb);
      const tPuff = zz(z, 3.6, Math.max(3.7, dauer - 3)), dreh = z() < 0.5 ? -1 : 1;
      const id = uid('e');
      const root = wesen(euleSvg(id));
      const q = s => root.querySelector(s);
      const E = { fl: q('.fl'), fr: q('.fr'), fr2: q('.fr2'), fu: q('.fu'), wf: q('.wf'), oh: q('.oh'), gs: q('.gs'), pa: q('.pa'), pb: q('.pb'), la: q('.la'), lb: q('.lb') };
      const inst = { el: root, dauer, cur: 0, tapT: null, leaveT: null };
      let blick = { x: 0, y: 0 };
      if (ziel) blick = { x: klemme((ziel.x - land.x) / 160, -1, 1), y: klemme((ziel.y - (land.y - 50)) / 160, -1, 1) };
      // Grundpose ohne schnellen Abgang
      const grund = t => {
        const tL = inst.dauer - 1.2;
        let x, y, rot = 0, spread, sk = SK;
        if (t < 1.6) {
          const u = raus(t / 1.6), p = bez2(p0, c0, land, u);
          x = p.x; y = p.y; rot = seite * -10 * (1 - u); spread = 1;
        } else if (t < tL) {
          x = land.x; y = land.y; spread = 1 - glatt((t - 1.6) / 0.3);
          sk = SK * (1 + 0.06 * Math.sin(Math.PI * ein(t, tPuff, 0.9)));
        } else {
          const u = ein(t, tL + 0.2, 1.0), p = bez2(land, cAus, pAus, rein(u));
          x = p.x; y = p.y; rot = seite * 9 * u; spread = glatt((t - tL) / 0.2);
        }
        return { x, y, rot, spread, sk };
      };
      const lage = t => {
        let g = grund(t), op = 1;
        if (inst.leaveT !== null && t >= inst.leaveT) {
          const g0 = grund(inst.leaveT), u = klemme((t - inst.leaveT) / 0.4, 0, 1);
          g = { x: g0.x + seite * 130 * rein(u), y: g0.y - 170 * rein(u), rot: seite * 12 * u, spread: Math.max(g0.spread, glatt(u / 0.3)), sk: g0.sk };
          op = 1 - ein(u, 0.6, 0.4);
        }
        return { g, op };
      };
      inst.stelle = t => {
        inst.cur = t;
        const { g, op } = lage(t);
        S(root, g.x, g.y, g.rot, g.sk, op);
        const flap = g.spread > 0.02 ? 9 * Math.sin(t * 7.5) * (t < 1.6 || t > inst.dauer - 1.0 ? 1 : 0.3) : 0;
        T(E.fl, 'scale(' + (Math.round((0.15 + 0.85 * g.spread) * 1000) / 1000) + ' 1)');
        O(E.fl, klemme(g.spread * 1.6, 0, 1));
        T(E.fr, 'rotate(' + n1(flap) + ' 9 -34)');
        T(E.fr2, 'rotate(' + n1(flap) + ' 9 -34)');
        O(E.wf, 1 - g.spread);
        O(E.fu, 1 - g.spread);
        // Blick zum Spieler am Zug (nach der Landung), Kopf-Drehen beim Antippen
        const sitzt = t >= 1.6 && t < inst.dauer - 1.2;
        const k = sitzt ? glatt(ein(t, 2.4, 0.6)) : 0;
        let f = 0;
        if (inst.tapT !== null) {
          const s = t - inst.tapT;
          if (s >= 0 && s < 0.3) f = glatt(s / 0.3);
          else if (s >= 0.3 && s < 0.42) f = 1;
          else if (s >= 0.42 && s < 0.76) f = 1 - 1.28 * glatt((s - 0.42) / 0.34);
          else if (s >= 0.76 && s < 0.92) f = -0.28 + 0.28 * glatt((s - 0.76) / 0.16);
        }
        const fx = dreh * f;
        const sx = 3 * blick.x * k + 17 * fx, kx = 1 - 0.72 * Math.abs(fx);
        T(E.gs, 'translate(' + n1(sx) + ' 0) scale(' + (Math.round(kx * 1000) / 1000) + ' 1)');
        O(E.gs, 1 - 0.9 * Math.min(1, fx * fx));
        T(E.oh, 'translate(' + n1(3 * fx + 0.8 * blick.x * k) + ' 0)');
        const px = 2.4 * blick.x * k, py = 1.4 * blick.y * k;
        T(E.pa, 'translate(' + n1(px) + ' ' + n1(py) + ')');
        T(E.pb, 'translate(' + n1(px) + ' ' + n1(py) + ')');
        let lid = 0;
        const zu = tb => { const d = Math.abs(t - tb - 0.08); if (d < 0.08) lid = Math.max(lid, 1 - d / 0.08); };
        if (sitzt) blinks.forEach(zu);
        if (inst.tapT !== null) { zu(inst.tapT + 0.98); zu(inst.tapT + 1.28); }
        if (t >= 1.6 && t < 1.9) lid = Math.max(lid, 0.35 * Math.sin(Math.PI * (t - 1.6) / 0.3));   // Landung: kurz zukneifen
        T(E.la, 'scale(1 ' + (Math.round(lid * 1000) / 1000) + ')');
        T(E.lb, 'scale(1 ' + (Math.round(lid * 1000) / 1000) + ')');
      };
      inst.hulle = t => {
        const { g, op } = lage(t);
        if (op < 0.03) return null;
        const s = g.sk;
        return g.spread > 0.35 ? kasten(g.x, g.y - 44 * s, 118 * s, 56 * s) : { x: g.x - 26 * s, y: g.y - 78 * s, w: 52 * s, h: 82 * s };
      };
      inst.tipp = () => { inst.tapT = inst.cur; };
      inst.abgang = () => { inst.leaveT = inst.cur; return 0.4; };
      return inst;
    },
  });

  /* ================================================================ 14 Fledermaus */
  N.art('fledermaus', {
    baue(ctx, z) {
      const W = ctx.W, H = ctx.H, dauer = zz(z, 4, 6);
      // Zickzack über den freien Himmel einer Seite (zwischen Knöpfen oben und den Köpfen; die Mitte gehört dem oberen Platz):
      // vom Rand herein bis gut ein Drittel der Breite, eine Kehre, dann im Zickzack zurück und oben hinaus.
      // (Die Ebene „hinten“ liegt unter der Richtungs-Plattform, deshalb oberhalb von ihr.)
      const n = 6 + Math.floor(z() * 4), links = z() < 0.5, nHin = Math.ceil(n / 2), nZur = n - nHin;
      const xr = x => (links ? x : W - x);
      const y0 = Math.max(ctx.ort.y0 + 10, 96), y1 = Math.max(y0 + 40, Math.min(ctx.ort.y1, H * 0.25, ctx.cy - 160));
      const xMax = zz(z, 0.33, 0.37) * W;
      const d = [];
      for (let i = 0; i < n; i++) d.push(zz(z, 0.35, 0.6));
      const sum = d.reduce((a, b) => a + b, 0);
      for (let i = 0; i < n; i++) d[i] *= dauer / sum;
      const pkt = [{ x: xr(-50), y: zz(z, y0, y1), t: 0 }];
      let t0 = 0;
      for (let i = 0; i < nHin; i++) {
        t0 += d[i];
        const oben = (i % 2 === 0) === (pkt[0].y > (y0 + y1) / 2);
        pkt.push({ x: xr(lerp(-50, xMax, (i + 1) / nHin) + (i < nHin - 1 ? zz(z, -25, 25) : 0)), y: lerp(y0, y1, oben ? zz(z, 0, 0.35) : zz(z, 0.65, 1)), t: t0 });
      }
      const yK = pkt[pkt.length - 1].y;
      for (let j = 0; j < nZur; j++) {
        t0 += d[nHin + j];
        const u = (j + 1) / nZur;
        pkt.push({ x: xr(lerp(xMax, -60, Math.pow(u, 0.8)) + (j < nZur - 1 ? zz(z, -30, 30) : 0)), y: lerp(yK, -50, Math.pow(u, 1.6)) + (j % 2 ? 1 : -1) * zz(z, 8, 22) * (1 - u), t: t0 });
      }
      // Silhouette (Nacht mit violetter Kontur), zwei Flügelstellungen im Wechsel (CSS steps)
      const kz = 'stroke="#8B6BFF" stroke-width="1.5" stroke-linejoin="round" fill="' + NACHT + '"';
      const hoch = 'M2.5,-2 L9,-12 L17,-15 L25,-14 C23,-11 22.5,-8.5 22.5,-6.5 C20,-7.5 18,-6.5 17,-4 C15,-5.5 12,-4.5 11,-2 C9,-3 6,-1 5,1.5 Z';
      const tief = 'M2.5,-1 L10,2 L18,7 L24,13 C21,12.5 19,13 18,15 C16.5,12.5 14,12 12.5,13 C11.5,10 9,9 7,9.5 C6.5,6.5 5,4 3,3.5 Z';
      const fl = p => '<path d="' + p + '" ' + kz + '/><path d="' + p + '" ' + kz + ' transform="scale(-1 1)"/>';
      const koerper = '<path d="M-3,-9 L-4.6,-14.5 L-1.4,-10.2 Z M3,-9 L4.6,-14.5 L1.4,-10.2 Z" ' + kz + '/>'
        + '<ellipse cx="0" cy="1.5" rx="4.4" ry="7" ' + kz + '/><circle cx="0" cy="-6" r="4.4" ' + kz + '/>'
        + '<circle cx="-1.7" cy="-6.6" r="1" fill="#FF5FC8"/><circle cx="1.7" cy="-6.6" r="1" fill="#FF5FC8"/>';
      const root = wesen(svg(-30, -20, 60, 40, '<g class="fa nt-schleife">' + fl(hoch) + '</g><g class="fb nt-schleife">' + fl(tief) + '</g>' + koerper, 'nt-fm'));
      const inst = { el: root, dauer, cur: 0, leaveT: null };
      const lage = t => {
        t = klemme(t, 0, dauer);
        let i = 1;
        while (i < pkt.length - 1 && pkt[i].t < t) i++;
        const a = pkt[i - 1], b = pkt[i], u = b.t > a.t ? klemme((t - a.t) / (b.t - a.t), 0, 1) : 1;
        const e = 1 - Math.pow(1 - u, 3);
        const vx = b.x - a.x, vy = b.y - a.y;
        const rot = klemme(Math.atan2(vy, Math.abs(vx)) / RAD * 0.45, -22, 22) * Math.sign(vx || 1);
        return { x: lerp(a.x, b.x, e), y: lerp(a.y, b.y, e), rot };
      };
      inst.stelle = t => {
        inst.cur = t;
        const p = lage(t);
        let op = ein(t, 0, 0.2) * klemme((dauer - t) / 0.2, 0, 1);
        if (inst.leaveT !== null) op *= klemme(1 - (t - inst.leaveT) / 0.35, 0, 1);
        S(root, p.x, p.y - (inst.leaveT !== null ? 220 * rein(klemme((t - inst.leaveT) / 0.4, 0, 1)) : 0), p.rot, 1.4, op);
      };
      inst.hulle = t => { const p = lage(t); return kasten(p.x, p.y, 62, 32); };
      inst.abgang = () => { inst.leaveT = inst.cur; return 0.4; };
      return inst;
    },
  });

  /* ================================================================ 15 Mond mit Schlafmütze */
  // Lite-Mond (style.css .himmel .mond): Kreis Ø104, ausgeschnitten mit einem Kreis r 41,6 bei (31,2 | 41,6) der Box, gedreht um −24°.
  // Die obere Sichelspitze liegt im Lite immer über dem Bildrand, der Ton-Knopf deckt die dicke rechte Seite. Deshalb sitzt die Mütze
  // oben auf dem Mond, ihr Zipfel fällt nach links in die freie Höhlung der Sichel, die „z“ steigen nach links auf.
  const MOND_SCHNITT = (() => { const a = -24 * RAD, x = -20.8, y = -10.4; return { x: x * Math.cos(a) - y * Math.sin(a), y: x * Math.sin(a) + y * Math.cos(a), r: 41.6 }; })();
  function muetzeForm() {
    // Mittellinie des Zipfels (Bezier) und Breite → Umriss, Streifen und Bommel in Mond-Koordinaten (Mitte 0|0, Radius 52)
    const B = { x: 21, y: -20 }, C1 = { x: 16, y: -52 }, C2 = { x: -24, y: -44 }, Tp = { x: -31, y: 3 };
    const pt = u => bez3(B, C1, C2, Tp, u);
    const breite = u => 28 * Math.pow(1 - u, 1.2) + 2.4;
    const rand = (u0, u1) => {
      const l = [], r = [], n = Math.max(3, Math.round((u1 - u0) * 26));
      for (let i = 0; i <= n; i++) {
        const u = lerp(u0, u1, i / n), p = pt(u), q = pt(Math.min(1, u + 0.01)), q0 = pt(Math.max(0, u - 0.01));
        let dx = q.x - q0.x, dy = q.y - q0.y; const ll = Math.hypot(dx, dy) || 1; dx /= ll; dy /= ll;
        const w = breite(u);
        l.push([p.x - dy * w, p.y + dx * w]); r.push([p.x + dy * w, p.y - dx * w]);
      }
      return 'M' + l.concat(r.reverse()).map(p => n1(p[0]) + ',' + n1(p[1])).join(' L') + ' Z';
    };
    return { pt, rand };
  }
  N.art('mond_muetze', {
    baue(ctx, z) {
      const m = ctx.ort, k = (m.w || 104) / 104, ruhig = !!ctx.ruhig;
      const dauer = zz(z, 10, 12);
      const F = muetzeForm(), J1 = F.pt(0.42), J2 = F.pt(0.7), TIP = F.pt(1);
      const id = uid('m');
      // Auge: Stelle auf der hellen Sichel unter der Krempe, die der (runde) Ton-Knopf nicht verdeckt; sonst die untere Spitze
      const knoepfe = ctx.schutz.filter(q => q.name === 'ton' || q.name === 'menue').map(q => ({ x: q.x + q.w / 2, y: q.y + q.h / 2, r: Math.min(q.w, q.h) / 2 }));
      let auge = null, ab = -1e9;
      for (let y = -12; y <= 44; y += 2) {
        for (let x = -44; x <= 50; x += 2) {
          const p = { x, y };
          if (Math.hypot(x, y) > 47 || Math.hypot(x - MOND_SCHNITT.x, y - MOND_SCHNITT.y) < MOND_SCHNITT.r + 4.5) continue;
          if (y < -6 - 0.09 * (x + 7) + 6) continue;   // nicht unter der Krempe
          const st = { x: m.x + x * k, y: m.y + y * k };
          if (st.y < 8) continue;
          let d = 1e9;
          knoepfe.forEach(q => { d = Math.min(d, Math.hypot(st.x - q.x, st.y - q.y) - q.r); });
          if (d < 5) continue;
          const sc = Math.min(d, 12) - Math.abs(y + 4) * 0.5;
          if (sc > ab) { ab = sc; auge = p; }
        }
      }
      if (!auge) auge = { x: -24, y: 30 };
      const zipfel = F.rand(0.40, 0.73), spitze = F.rand(0.68, 1.0), basis = F.rand(0, 0.45);
      const streifen = (u) => F.rand(u - 0.035, u + 0.035);
      let augeWinkel = Math.atan2(auge.y, auge.x) / RAD + 90;   // entlang der Sichel, „◡“ zeigt nach unten
      augeWinkel = ((augeWinkel % 180) + 270) % 180 - 90;
      const zPfad = '<path d="M-4,-4.5 h8 l-8,9 h8" fill="none" stroke="' + CREME + '" stroke-width="2.3" stroke-linecap="round" stroke-linejoin="round"/>';
      const html = svg(-80, -80, 160, 140,
        '<defs><linearGradient id="' + id + 'g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#FF5CC0"/><stop offset="1" stop-color="#E0168C"/></linearGradient></defs>'
        + '<g class="au" transform="translate(' + n1(auge.x) + ' ' + n1(auge.y) + ') rotate(' + n1(augeWinkel) + ')">'
        + '<g class="zu"><path d="M-6,-1.5 Q0,4.5 6,-1.5" fill="none" stroke="' + INK + '" stroke-opacity=".7" stroke-width="2" stroke-linecap="round"/>'
        + '<path d="M-3.4,1.4 l-1,2 M0,2.4 l0,2.2 M3.4,1.4 l1,2" stroke="' + INK + '" stroke-opacity=".5" stroke-width="1" stroke-linecap="round"/></g>'
        + '<g class="of" style="opacity:0"><ellipse cx="0" cy="0" rx="3.3" ry="3.8" fill="' + INK + '" fill-opacity=".8"/><circle cx="1" cy="-1.2" r="1.1" fill="#fff"/></g></g>'
        + '<g class="kap">'
        + '<path d="' + basis + '" fill="url(#' + id + 'g)" stroke="#8E0E5C" stroke-width="1.1" stroke-linejoin="round"/>'
        + '<path d="' + streifen(0.2) + '" fill="' + CREME + '" opacity=".9"/>'
        + '<g class="z1"><path d="' + zipfel + '" fill="url(#' + id + 'g)" stroke="#8E0E5C" stroke-width="1.1" stroke-linejoin="round"/>'
        + '<path d="' + streifen(0.55) + '" fill="' + CREME + '" opacity=".9"/>'
        + '<g class="z2"><path d="' + spitze + '" fill="url(#' + id + 'g)" stroke="#8E0E5C" stroke-width="1.1" stroke-linejoin="round"/>'
        + '<path d="' + streifen(0.84) + '" fill="' + CREME + '" opacity=".9"/>'
        + '<g class="bo"><circle cx="' + n1(TIP.x - 1) + '" cy="' + n1(TIP.y + 5) + '" r="7.4" fill="' + CREME + '" stroke="#C9BBA4" stroke-width="1"/>'
        + '<path d="M' + n1(TIP.x - 4) + ',' + n1(TIP.y + 3) + ' l1.5,1 M' + n1(TIP.x + 1) + ',' + n1(TIP.y + 1) + ' l1,1.4 M' + n1(TIP.x - 2) + ',' + n1(TIP.y + 8) + ' l1.6,.4 M' + n1(TIP.x + 2) + ',' + n1(TIP.y + 6.5) + ' l.6,1.5" stroke="#D9CBB2" stroke-width="1" stroke-linecap="round"/></g>'
        + '</g></g>'
        + '<path d="M-8,-15 C7,-23 30,-26 50,-20 L51,-11 C31,-17 7,-14 -7,-6 Z" fill="' + CREME + '" stroke="#C9BBA4" stroke-width="1.1" stroke-linejoin="round"/>'
        + '</g>'
        + '<g class="zz" style="opacity:0">' + zPfad + '</g>');
      const root = wesen(html);
      const q = s => root.querySelector(s);
      const E = { kap: q('.kap'), z1: q('.z1'), z2: q('.z2'), bo: q('.bo'), zu: q('.zu'), of: q('.of'), zz: q('.zz') };
      const inst = { el: root, dauer, cur: 0, tapT: null, leaveT: null };
      const tW = () => inst.dauer - 1.0;   // Wind pustet die Mütze weg
      inst.stelle = t => {
        inst.cur = t;
        const D = inst.dauer;
        let opAll = 1, kapY = 0, kapRot = 0, kapX = 0, kapOp = 1, swing = 0, bounce = 0, offen = 0, zOp = 0;
        if (ruhig) {
          opAll = ein(t, 0, 1) * klemme((D - t) / 1, 0, 1);
        } else {
          if (t < 0.6) { const u = t / 0.6; kapY = u < 0.75 ? -46 * (1 - Math.pow(u / 0.75, 2)) : -4.5 * Math.sin(Math.PI * (u - 0.75) / 0.25); }
          kapOp = ein(t, 0, 0.12);
          swing = 12 * Math.sin(TAU * (t - 0.6) / 2.4) * ein(t, 0.5, 0.6);
          if (t >= tW()) {
            const u = klemme((t - tW()) / 0.8, 0, 1);
            kapRot = 38 * raus(u); kapX = 55 * rein(u); kapY -= 50 * rein(u); kapOp *= 1 - ein(u, 0.55, 0.45);
            offen = Math.max(offen, Math.sin(Math.PI * klemme((t - tW() - 0.05) / 0.6, 0, 1)));
          }
          // „z“ alle 2 s, wächst und verblasst in 1,6 s
          const zt = t - 1.0;
          if (zt >= 0 && t < tW()) {
            const a = zt % 2;
            if (a < 1.6) {
              const u = a / 1.6;
              const zx = -50 - 42 * u + 6 * Math.sin(u * 5), zy = 16 - 20 * u;
              T(E.zz, tr(zx, zy, -12 + 10 * u, 0.8 + 1.0 * u));
              zOp = 0.95 * ein(u, 0, 0.15) * (1 - ein(u, 0.55, 0.45));
            }
          }
          opAll = klemme((D - t) / 0.3, 0, 1);
        }
        if (inst.tapT !== null && t >= inst.tapT) {   // Mond öffnet das Auge, der Bommel hüpft
          const s = t - inst.tapT;
          offen = Math.max(offen, s < 0.15 ? s / 0.15 : (s < 0.75 ? 1 : 1 - (s - 0.75) / 0.2));
          bounce = -7 * Math.abs(Math.sin(Math.PI * klemme(s / 0.45, 0, 2)) * Math.exp(-s * 2.5));
          if (s > 1.1) offen = 0;
        }
        if (inst.leaveT !== null) opAll *= klemme(1 - (t - inst.leaveT) / 0.38, 0, 1);
        S(root, m.x, m.y, 0, k, opAll);
        T(E.kap, 'translate(' + n1(kapX) + ' ' + n1(kapY) + ') rotate(' + n1(kapRot) + ' 20 -14)');
        O(E.kap, kapOp);
        T(E.z1, 'rotate(' + n1(swing * 0.5) + ' ' + n1(J1.x) + ' ' + n1(J1.y) + ')');
        T(E.z2, 'rotate(' + n1(swing * 0.5) + ' ' + n1(J2.x) + ' ' + n1(J2.y) + ')');
        T(E.bo, 'translate(0 ' + n1(bounce) + ')');
        O(E.of, offen); O(E.zu, 1 - offen);
        O(E.zz, zOp);
      };
      inst.hulle = t => {
        if (t >= inst.dauer || (inst.leaveT !== null && t - inst.leaveT >= 0.38)) return null;
        const x0 = m.x - 44 * k, x1 = m.x + 53 * k, y0 = Math.max(0, m.y - 52 * k), y1 = m.y + 6 * k;
        return y1 > y0 ? { x: x0, y: y0, w: x1 - x0, h: y1 - y0 } : null;
      };
      inst.treffer = p => Math.hypot(p.x - m.x, p.y - m.y) <= 62 * k;
      inst.tipp = () => { inst.tapT = inst.cur; };
      inst.abgang = () => { inst.leaveT = inst.cur; return 0.4; };
      return inst;
    },
  });

  /* ================================================================ 16 Polarlicht */
  N.art('polarlicht', {
    baue(ctx, z) {
      const W = ctx.W, H = ctx.H, ruhig = !!ctx.ruhig;
      const dauer = zz(z, 12, 14);
      const FARBEN = ['#B36BFF', '#19E0D4', '#4FFFB0'];   // hinten oben Violett, vorn unten Grün
      const breite = Math.round(W * 1.4);
      // Je Vorhang ein statisches SVG-Band (Wellenkante unten, zerfranste Oberkante, Strahlen, heller Saum) in einem eigenen <div>;
      // bewegt werden nur die <div> (Verschieben, Neigen, Strecken von unten, Deckkraft), das SVG bleibt unverändert.
      const vorh = FARBEN.map((c, i) => {
        const h = zz(z, 120, 180), unten = zz(z, 0.19, 0.225) * H + (i - 1) * 14;
        const l1 = zz(z, 0.32, 0.5) * W, l2 = zz(z, 0.11, 0.18) * W, l3 = zz(z, 0.05, 0.08) * W, p1 = z() * TAU, p2 = z() * TAU, p3 = z() * TAU;
        const A1 = zz(z, 18, 28), A2 = zz(z, 5, 9), n = 64, unt = [], obn = [];
        for (let j = 0; j <= n; j++) {
          const x = breite * j / n;
          const yb = h + A1 * Math.sin(TAU * x / l1 + p1) + A2 * Math.sin(TAU * x / l2 + p2);
          const hh = h * (0.55 + 0.3 * Math.abs(Math.sin(TAU * x / (l1 * 0.6) + p2)) + 0.15 * Math.sin(TAU * x / l3 + p3));
          unt.push([x, yb]); obn.push([x, yb - hh]);
        }
        const P = a => a.map(p => n1(p[0]) + ',' + n1(p[1]));
        const form = 'M' + P(obn).join(' L') + ' L' + P(unt.slice().reverse()).join(' L') + ' Z';
        const saum = 'M' + P(unt).join(' L');
        const id = uid('p'), y0 = -40, hg = Math.round(h + 80);
        const verlauf = (gid, a0) => '<linearGradient id="' + gid + '" gradientUnits="userSpaceOnUse" x1="0" y1="' + n1(h + A1 + A2 + 6) + '" x2="0" y2="' + n1(-10) + '">'
          + '<stop offset="0" stop-color="' + c + '" stop-opacity="0"/><stop offset=".07" stop-color="' + c + '" stop-opacity="' + a0 + '"/>'
          + '<stop offset=".3" stop-color="' + c + '" stop-opacity="' + (a0 * 0.6).toFixed(2) + '"/><stop offset=".65" stop-color="' + c + '" stop-opacity="' + (a0 * 0.22).toFixed(2) + '"/>'
          + '<stop offset="1" stop-color="' + c + '" stop-opacity="0"/></linearGradient>';
        const strahl = Math.round(zz(z, 8, 13));
        const inner = '<defs>' + verlauf(id + 'v', 1) + verlauf(id + 'r', 1)
          + '<pattern id="' + id + 's" patternUnits="userSpaceOnUse" x="0" y="' + y0 + '" width="' + strahl + '" height="' + hg + '">'
          + '<rect x="0" y="' + y0 + '" width="2.4" height="' + hg + '" fill="url(#' + id + 'r)"/><rect x="' + (strahl / 2).toFixed(1) + '" y="' + y0 + '" width="1.2" height="' + hg + '" fill="url(#' + id + 'r)" opacity=".6"/></pattern></defs>'
          + '<path d="' + form + '" fill="url(#' + id + 'v)"/>'
          + '<path d="' + form + '" fill="url(#' + id + 's)"/>'
          + '<path d="' + saum + '" fill="none" stroke="' + c + '" stroke-opacity=".2" stroke-width="8" stroke-linejoin="round"/>'
          + '<path d="' + saum + '" fill="none" stroke="#EFFFF8" stroke-opacity=".5" stroke-width="2" stroke-linejoin="round"/>';
        const maske = 'linear-gradient(90deg,transparent 0,#000 14%,#000 86%,transparent 100%)';
        const css = 'width:' + breite + 'px;height:' + hg + 'px;transform-origin:50% ' + Math.round(h - y0) + 'px;-webkit-mask-image:' + maske + ';mask-image:' + maske;
        return { html: '<div class="nt-pl" style="' + css + '">' + svg(0, y0, breite, hg, inner) + '</div>', h, unten, y0,
          x0: -W * 0.2 + zz(z, -40, 40), drift: zz(z, 5, 10) * (z() < 0.5 ? -1 : 1), ph: z() * TAU, sk: zz(z, 4, 8), a: zz(z, 0.3, 0.35) };
      });
      const root = wesen(vorh.map(v => v.html).join(''));
      const els = Array.from(root.children);
      const inst = { el: root, dauer, cur: 0, leaveT: null };
      inst.stelle = t => {
        inst.cur = t;
        let fade = ein(t, 0, 3) * klemme((inst.dauer - t) / 3, 0, 1);
        if (inst.leaveT !== null) fade *= klemme(1 - (t - inst.leaveT) / 0.38, 0, 1);
        vorh.forEach((v, i) => {
          const w = ruhig ? 0 : 1;
          const x = v.x0 + w * v.drift * t + w * 14 * Math.sin(TAU * 0.12 * t + v.ph);
          const skew = w * v.sk * Math.sin(TAU * 0.12 * t + v.ph * 1.3);
          const sy = 1 + w * 0.08 * Math.sin(TAU * 0.09 * t + v.ph * 0.7);
          const puls = ruhig ? 1 : 0.8 + 0.2 * Math.sin(TAU * 0.17 * t + v.ph);
          els[i].style.transform = 'translate(' + n1(x) + 'px,' + n1(v.unten - v.h + v.y0) + 'px) skewX(' + n1(skew) + 'deg) scaleY(' + (Math.round(sy * 1000) / 1000) + ')';
          O(els[i], v.a * puls * fade);
        });
      };
      inst.hulle = t => {
        let fade = ein(t, 0, 3) * klemme((inst.dauer - t) / 3, 0, 1);
        if (inst.leaveT !== null) fade *= klemme(1 - (t - inst.leaveT) / 0.38, 0, 1);
        if (fade < 0.05) return null;
        const top = Math.min(...vorh.map(v => v.unten - v.h * 0.8)), bot = Math.max(...vorh.map(v => v.unten));
        return { x: W * 0.05, y: Math.max(0, top), w: W * 0.9, h: bot - Math.max(0, top) };
      };
      inst.abgang = () => { inst.leaveT = inst.cur; return 0.4; };
      return inst;
    },
  });

  /* ================================================================ 17 Katzen-Sternbild */
  N.art('sternbild', {
    baue(ctx, z) {
      const o = ctx.ort, form = ctx.form || N.EINTRAG.sternbild.form, ruhig = !!ctx.ruhig;
      const dauer = zz(z, 9, 10), pad = 16;
      const P = form.punkte.map(p => ({ x: o.x + pad + p[0] * (o.w - 2 * pad), y: o.y + pad + p[1] * (o.h - 2 * pad) }));
      const id = uid('s');
      const stern = (p, i) => '<g class="st" transform="translate(' + n1(p.x - o.x) + ' ' + n1(p.y - o.y) + ')"><g class="sk">'
        + '<circle r="13" fill="url(#' + id + 'g)"/>'
        + '<path d="M0,-' + (i % 3 === 0 ? 8 : 6) + ' L1,-1 L' + (i % 3 === 0 ? 8 : 6) + ',0 L1,1 L0,' + (i % 3 === 0 ? 8 : 6) + ' L-1,1 L-' + (i % 3 === 0 ? 8 : 6) + ',0 L-1,-1 Z" fill="#EEF2FF"/>'
        + '<circle r="1.9" fill="#fff"/></g></g>';
      const linie = (a, b) => {
        const l = Math.hypot(b.x - a.x, b.y - a.y), w = Math.atan2(b.y - a.y, b.x - a.x) / RAD;
        return '<g transform="translate(' + n1(a.x - o.x) + ' ' + n1(a.y - o.y) + ') rotate(' + n1(w) + ')"><g class="ln" transform="scale(0 1)">'
          + '<line x1="0" y1="0" x2="' + n1(l) + '" y2="0" stroke="#DDE6FF" stroke-opacity=".14" stroke-width="5" stroke-linecap="round"/>'
          + '<line x1="0" y1="0" x2="' + n1(l) + '" y2="0" stroke="#DDE6FF" stroke-opacity=".5" stroke-width="1.5" stroke-linecap="round"/></g></g>';
      };
      const html = svg(0, 0, Math.round(o.w), Math.round(o.h),
        '<defs><radialGradient id="' + id + 'g"><stop offset="0" stop-color="#EEF2FF" stop-opacity=".9"/><stop offset=".3" stop-color="#B9C8FF" stop-opacity=".32"/><stop offset="1" stop-color="#B9C8FF" stop-opacity="0"/></radialGradient></defs>'
        + form.linien.map(l => linie(P[l[0]], P[l[1]])).join('') + P.map(stern).join(''));
      const root = wesen(html);
      const st = Array.from(root.querySelectorAll('.sk')), ln = Array.from(root.querySelectorAll('.ln'));
      const schwanz = form.linien.map((l, i) => (l[0] >= 8 || l[1] >= 9) ? i : -1).filter(i => i >= 0);
      const lnRot = Array.from(root.querySelectorAll('.ln')).map(e => e.parentNode);
      const lnBasis = lnRot.map(e => e.getAttribute('transform'));
      const funk = P.map(() => ({ ph: z() * TAU, w: zz(z, 3, 6) }));
      const inst = { el: root, dauer, cur: 0, tapT: null, leaveT: null };
      inst.stelle = t => {
        inst.cur = t;
        const D = inst.dauer;
        let fade = ruhig ? ein(t, 0, 1.5) * klemme((D - t) / 2, 0, 1) : klemme((D - t) / 2, 0, 1);
        if (inst.leaveT !== null) fade *= klemme(1 - (t - inst.leaveT) / 0.38, 0, 1);
        S(root, o.x, o.y, 0, 1, fade);
        const blitz = inst.tapT !== null && t >= inst.tapT ? Math.max(0, 1 - (t - inst.tapT) / 0.4) : 0;
        st.forEach((e, i) => {
          let a, s;
          if (ruhig) { a = 1; s = 1; } else {
            const u = ein(t, 0.3 + i * 0.22, 0.3);
            a = u; s = u < 1 ? 0.3 + 1.1 * Math.sin(u * Math.PI * 0.75) : 1;
            if (u >= 1) { const f = 0.85 + 0.15 * Math.sin(t * funk[i].w + funk[i].ph); a = f; s = 0.92 + 0.12 * f; }
          }
          s *= 1 + 0.7 * blitz; a = Math.min(1, a + blitz);
          T(e, 'scale(' + (Math.round(s * 1000) / 1000) + ')');
          O(e, a);
        });
        const tl = 0.3 + P.length * 0.22 + 0.2, schritt = 1.6 / ln.length;
        ln.forEach((e, i) => {
          const u = ruhig ? 1 : glatt(ein(t, tl + i * schritt * 0.6, 0.55));
          T(e, 'scale(' + (Math.round(u * 1000) / 1000) + ' 1)');
        });
        const wack = inst.tapT !== null && t >= inst.tapT ? 7 * Math.sin((t - inst.tapT) * 22) * Math.max(0, 1 - (t - inst.tapT) / 0.8) : 0;
        schwanz.forEach(i => T(lnRot[i], lnBasis[i] + (wack ? ' rotate(' + n1(wack) + ')' : '')));
      };
      inst.hulle = t => {
        let fade = klemme((inst.dauer - t) / 2, 0, 1);
        if (inst.leaveT !== null) fade *= klemme(1 - (t - inst.leaveT) / 0.38, 0, 1);
        if (fade < 0.05 || (!ruhig && t < 0.35)) return null;
        return { x: o.x, y: o.y, w: o.w, h: o.h };
      };
      inst.treffer = p => p.x >= o.x - 10 && p.x <= o.x + o.w + 10 && p.y >= o.y - 10 && p.y <= o.y + o.h + 10;
      inst.tipp = () => { inst.tapT = inst.cur; };
      inst.abgang = () => { inst.leaveT = inst.cur; return 0.4; };
      return inst;
    },
  });

  /* ================================================================ 18 UFO leuchtet den Stapel an
   * 1.6.15 (Nutzer: „nicht so einfach verscheuchen“): nicht mehr scheu, Ziehen stört es nicht; der 1. und 2. Tipp lassen es zur Seite
   * ausweichen (Kegel flackert), erst der 3. verscheucht es. */
  N.art('ufo', {
    baue(ctx, z) {
      const o = ctx.ort, st = o.stapel || { x: o.x - 60, y: o.y + 62, w: 120, h: 180 };
      const dauer = zz(z, 6, 7), SK = 1.3;
      const H0 = { x: o.x, y: o.y };
      const seite = H0.x < ctx.W / 2 ? -1 : 1;
      const P0 = { x: H0.x + seite * 230, y: -70 }, C0 = { x: H0.x + seite * 215, y: H0.y + 8 };
      const kegelUnten = (st.y + st.h * 0.82 - H0.y) / SK, kegelB = (st.w / 2 + 10) / SK;   // im Maßstab des UFOs
      const id = uid('u');
      const lichter = [-24, -12, 0, 12, 24].map((x, i) => '<circle class="li nt-schleife" cx="' + x + '" cy="5" r="2.5" fill="' + ['#FF2FA8', '#FFD65A', '#19E0D4'][i % 3] + '" style="animation-delay:' + (-0.16 * (4 - i)).toFixed(2) + 's"/>').join('');
      const funken = [0, 1, 2, 3, 4].map(() => '<circle class="fk" r="1.7" fill="#D8FFFA"/>').join('');
      const kegel = '<g class="kg"><polygon points="-15,9 15,9 ' + n1(kegelB) + ',' + n1(kegelUnten) + ' ' + n1(-kegelB) + ',' + n1(kegelUnten) + '" fill="url(#' + id + 'k)"/>'
        + '<ellipse cx="0" cy="' + n1(kegelUnten) + '" rx="' + n1(kegelB) + '" ry="9" fill="#A8FFF6" fill-opacity=".1"/>' + funken + '</g>';
      const html = svg(-60, -40, 120, Math.round(kegelUnten + 60),
        '<defs><linearGradient id="' + id + 'k" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#A8FFF6" stop-opacity=".22"/><stop offset="1" stop-color="#A8FFF6" stop-opacity=".06"/></linearGradient>'
        + '<radialGradient id="' + id + 'd" cx=".4" cy=".35" r=".8"><stop offset="0" stop-color="#C8FBFF" stop-opacity=".75"/><stop offset="1" stop-color="#19C6D4" stop-opacity=".4"/></radialGradient>'
        + '<linearGradient id="' + id + 'h" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#D6DCEE"/><stop offset="1" stop-color="#9AA3C2"/></linearGradient></defs>'
        + kegel
        + '<g class="kp">'
        + '<ellipse cx="0" cy="12" rx="13" ry="3" fill="#A8FFF6" class="bl" style="opacity:0"/>'
        + '<ellipse cx="0" cy="5" rx="36" ry="10" fill="#6B7394" stroke="#19C6D4" stroke-width="1.7"/>'
        + '<ellipse cx="0" cy="0.5" rx="33" ry="7.5" fill="url(#' + id + 'h)"/>'
        + lichter
        + '<path d="M-17,0 C-16,-17 16,-17 17,0 Z" fill="url(#' + id + 'd)" stroke="#9EF3FF" stroke-width="1.2"/>'
        + '<path d="M-9,-8 C-7.5,-12 -3,-13.5 1,-13.5" fill="none" stroke="#fff" stroke-opacity=".85" stroke-width="1.7" stroke-linecap="round"/>'
        + '</g>', 'nt-ufo');
      const root = wesen(html);
      const q = s => root.querySelector(s);
      const E = { kg: q('.kg'), kp: q('.kp'), bl: q('.bl'), fk: Array.from(root.querySelectorAll('.fk')) };
      const fz = E.fk.map(() => ({ ph: z(), x: zz(z, -0.6, 0.6), v: zz(z, 0.5, 0.8) }));
      const tAn = 1.9, tAus = 4.4;
      // 1.6.15: nicht mehr scheu; 1. und 2. Tipp → Satz zur Seite (DS), zitternd dort (DH), zurück über den Stapel (DB); 3. Tipp → davon
      const DS = 0.22, DH = 0.9, DB = 0.8, DX = 64;
      const ausweich = [];   // [{at, x, y}] je Ausweich-Tipp (rein in t: stelle liest nur diese Liste)
      const blockiert = x => ctx.schutz.some(q => q.name !== 'stapel' && flaeche(kasten(H0.x + x, H0.y - 2 * SK, 76 * SK, 36 * SK), q) > 0);
      const freieSeite = blockiert(DX) && !blockiert(-DX) ? -1 : 1;
      const segment = (i, t) => {
        const d = ausweich[i], von = i > 0 ? segment(i - 1, d.at) : { x: 0, y: 0 }, x = t - d.at;
        if (x < DS) { const u = raus(x / DS); return { x: lerp(von.x, d.x, u), y: lerp(von.y, d.y, u) }; }
        if (x < DS + DH) return { x: d.x, y: d.y };
        const u = glatt((x - DS - DH) / DB);
        return { x: d.x * (1 - u), y: d.y * (1 - u) };
      };
      const versatz = t => { let i = -1; ausweich.forEach((d, j) => { if (d.at <= t) i = j; }); return i < 0 ? null : { off: segment(i, t), seit: t - ausweich[i].at }; };
      const inst = { el: root, dauer, cur: 0, leaveT: null, tippMax: 3, tipps: 0 };
      const grund = t => {
        const tL = inst.dauer - 0.8;
        if (t < 1.5) {
          const u = raus(t / 1.5), p = bez2(P0, C0, H0, u);
          return { x: p.x, y: p.y, rot: seite * -8 * Math.sin(u * Math.PI * 1.5) * (1 - u * 0.6) };
        }
        if (t < tL) return { x: H0.x, y: H0.y + 3 * Math.sin(TAU * (t - 1.5) / 1.6), rot: 2 * Math.sin(TAU * (t - 1.5) / 2.3) };
        const u = rein(klemme((t - tL) / 0.8, 0, 1));
        return { x: H0.x + seite * 330 * u, y: H0.y - (H0.y + 130) * u, rot: seite * 12 * u };
      };
      // Grundbahn samt Ausweichen: Versatz, Schaukeln; der Lichtkegel flackert und bleibt aus, solange das UFO neben dem Stapel ist
      const mitAusweichen = (t, g, kegel) => {
        const v = versatz(t);
        if (!v) return { g, kegel };
        const lean = Math.abs(v.off.x) > 0.5 ? Math.sign(v.off.x) : 0;
        const rot = g.rot - lean * 13 * Math.sin(Math.PI * klemme(v.seit / (DS * 1.6), 0, 1)) + 9 * Math.sin(v.seit * 26) * Math.exp(-3.2 * v.seit);
        let k = kegel * klemme(1 - Math.abs(v.off.x) / DX * 1.3, 0, 1);
        if (v.seit < 0.55) k *= Math.sin(v.seit * 58) > 0 ? 1 : 0.25;
        return { g: { x: g.x + v.off.x, y: g.y + v.off.y, rot }, kegel: k };
      };
      const lage = t => {
        let g = grund(t), kegel = ein(t, tAn, 0.25) * klemme((tAus - t) / 0.2, 0, 1), op = 1;
        if (inst.leaveT !== null && t >= inst.leaveT) {
          const g0 = mitAusweichen(inst.leaveT, grund(inst.leaveT), 0).g, u = rein(klemme((t - inst.leaveT) / 0.4, 0, 1));
          g = { x: g0.x + seite * 260 * u, y: g0.y - 280 * u, rot: seite * 16 * u };
          kegel = 0; op = 1 - ein(t - inst.leaveT, 0.25, 0.15);
        } else {
          const a = mitAusweichen(t, g, kegel);
          g = a.g; kegel = a.kegel;
        }
        return { g, kegel, op };
      };
      inst.stelle = t => {
        inst.cur = t;
        const { g, kegel, op } = lage(t);
        S(root, g.x, g.y, 0, SK, op);
        T(E.kp, 'rotate(' + n1(g.rot) + ')');
        T(E.kg, 'translate(' + n1((H0.x - g.x) / SK) + ' ' + n1((H0.y - g.y) / SK) + ') scale(1 ' + (Math.round(Math.max(0.001, glatt(kegel)) * 1000) / 1000) + ')');
        O(E.kg, kegel);
        O(E.bl, kegel * 0.8);
        E.fk.forEach((e, i) => {
          const f = fz[i], u = ((t * f.v * 0.6 + f.ph) % 1);
          const y = kegelUnten - (kegelUnten - 12) * u, b = lerp(kegelB, 15, u);
          T(e, 'translate(' + n1(f.x * b * 0.8) + ' ' + n1(y) + ')');
          O(e, Math.sin(Math.PI * u) * 0.9);
        });
      };
      inst.hulle = t => {
        const { g, kegel, op } = lage(t);
        if (op < 0.03) return null;
        const k = kasten(g.x, g.y - 2 * SK, 76 * SK, 36 * SK);
        if (kegel > 0.02) { const b = (kegelB + 2) * SK, u = H0.y + kegelUnten * SK; const x0 = Math.min(k.x, H0.x - b), x1 = Math.max(k.x + k.w, H0.x + b); return { x: x0, y: k.y, w: x1 - x0, h: u - k.y }; }
        return k;
      };
      inst.treffer = p => { const { g } = lage(inst.cur); return Math.hypot(p.x - g.x, (p.y - g.y) * 1.6) <= 60; };
      inst.tipp = p => {
        inst.tipps++;
        if (inst.tipps >= 3) { inst.leaveT = inst.cur; inst.dauer = Math.min(inst.dauer, inst.cur + 0.42); return; }
        // weg vom Finger, sonst zur freieren Seite; liegt dort ein Platz oder Knopf, zur anderen
        const { g } = lage(inst.cur);
        let s = p && Math.abs(g.x - p.x) >= 5 ? Math.sign(g.x - p.x) : (ausweich.length ? -Math.sign(ausweich[ausweich.length - 1].x) : freieSeite);
        if (!s) s = freieSeite;
        if (blockiert(s * DX) && !blockiert(-s * DX)) s = -s;
        ausweich.push({ at: inst.cur, x: s * DX, y: ausweich.length ? 6 : -10 });
      };
      inst.ausweichen = () => ausweich.length;
      inst.abgang = () => { if (inst.leaveT === null) inst.leaveT = inst.cur; return Math.max(0.05, inst.leaveT + 0.42 - inst.cur); };
      return inst;
    },
  });

  /* ================================================================ 19 Satellit */
  N.art('satellit', {
    baue(ctx, z) {
      const W = ctx.W, o = ctx.ort, dauer = zz(z, 9, 11);
      const dir = z() < 0.5 ? 1 : -1;
      const y0 = zz(z, o.y0 + 20, o.y1 - 30), y1 = klemme(y0 + zz(z, -50, 50), o.y0 + 12, o.y1 - 12);
      const A = { x: dir > 0 ? -20 : W + 20, y: y0 }, B = { x: dir > 0 ? W + 20 : -20, y: y1 };
      const tBlitz = dauer * zz(z, 0.3, 0.65), rotW = Math.atan2(B.y - A.y, B.x - A.x) / RAD;
      const html = '<div class="nt-halo" style="left:-15px;top:-15px;width:30px;height:30px;background:radial-gradient(circle,rgba(255,255,255,.95) 0,rgba(220,232,255,.55) 25%,rgba(200,215,255,.15) 55%,rgba(200,215,255,0) 72%)"></div>'
        + svg(-14, -8, 28, 16, '<g transform="rotate(' + n1(rotW) + ')"><rect x="-11" y="-1.6" width="6.5" height="3.2" fill="#6F7BD8" fill-opacity=".75" stroke="#B9C2FF" stroke-opacity=".6" stroke-width=".5"/>'
          + '<rect x="4.5" y="-1.6" width="6.5" height="3.2" fill="#6F7BD8" fill-opacity=".75" stroke="#B9C2FF" stroke-opacity=".6" stroke-width=".5"/>'
          + '<line x1="-4.5" y1="0" x2="4.5" y2="0" stroke="#B9C2FF" stroke-opacity=".7" stroke-width=".7"/></g>'
          + '<circle r="4.2" fill="#fff" fill-opacity=".22"/><circle r="2.5" fill="#fff"/><circle class="rot" cx="2.8" cy="2.4" r="1.4" fill="#FF4D57"/>');
      const root = wesen(html);
      const halo = root.querySelector('.nt-halo'), rot = root.querySelector('.rot');
      const inst = { el: root, dauer, cur: 0, leaveT: null };
      const lage = t => { const u = klemme(t / dauer, 0, 1); return { x: lerp(A.x, B.x, u), y: lerp(A.y, B.y, u) }; };
      inst.stelle = t => {
        inst.cur = t;
        const p = lage(t);
        let op = ein(t, 0, 0.6) * klemme((dauer - t) / 0.6, 0, 1);
        if (inst.leaveT !== null) op *= klemme(1 - (t - inst.leaveT) / 0.38, 0, 1);
        S(root, p.x, p.y, 0, 1, op);
        const bl = t - tBlitz;
        const b = bl >= 0 && bl < 0.4 ? Math.sin(Math.PI * bl / 0.4) : 0;
        S(halo, 0, 0, 0, 0.6 + 1.6 * b, 0.25 + 0.75 * b);
        O(rot, (t % 1) < 0.1 ? 1 : 0.12);
      };
      inst.hulle = t => { const p = lage(t); return kasten(p.x, p.y, 18, 18); };
      inst.abgang = () => { inst.leaveT = inst.cur; return 0.4; };
      return inst;
    },
  });

  /* ================================================================ 20 Motte am Ablage-Ring */
  N.art('motte', {
    baue(ctx, z) {
      const o = ctx.ort, R = o.R || 118, dauer = zz(z, 6, 8);
      const a = R + 40, b = R + 36, dir = z() < 0.5 ? 1 : -1;
      const quadrat = th => { const c = Math.cos(th), s = Math.sin(th); return { x: o.x + a * Math.sign(c) * Math.sqrt(Math.abs(c)), y: o.y + b * Math.sign(s) * Math.sqrt(Math.abs(s)) }; };
      const th0 = -Math.PI / 2 + zz(z, -0.6, 0.6);
      const vonA = { x: o.x + zz(z, -1, 1) * 160, y: o.y - R - 230 };
      const om = dir * TAU / 2.2;
      const tO0 = 1.2, tO1 = dauer - 1.0;
      const stups = [zz(z, tO0 + 0.6, tO1 - 0.6), zz(z, tO0 + 0.6, tO1 - 0.6)];
      const zit = { ph1: z() * TAU, ph2: z() * TAU };
      const fluegel = (s) => '<g transform="scale(' + s + ' 1)"><g class="fl nt-schleife">'
        + '<path d="M0,-2.5 C-5,-9.5 -14,-10.5 -16,-5 C-17,0 -9,2.5 0,1 Z" fill="#8E8170" stroke="#C9BBA4" stroke-width="1" stroke-linejoin="round"/>'
        + '<path d="M-6,-5.5 C-9,-6.5 -12,-6 -13.5,-4" fill="none" stroke="#C9BBA4" stroke-opacity=".7" stroke-width=".8"/>'
        + '<circle cx="-9" cy="-3.5" r="1.4" fill="#5F5446"/>'
        + '<path d="M0,1 C-5,2 -11,6 -9,9.5 C-6,12 -1.5,7.5 0,4 Z" fill="#7E7262" stroke="#C9BBA4" stroke-width=".9" stroke-linejoin="round"/></g></g>';
      const fuehler = s => '<path d="M' + (s * 1.2) + ',-8 C' + (s * 3) + ',-12 ' + (s * 6) + ',-14.5 ' + (s * 8.5) + ',-14.5" fill="none" stroke="#C9BBA4" stroke-width=".9" stroke-linecap="round"/>'
        + '<path d="M' + (s * 3) + ',-11.2 l' + (s * 1.6) + ',-1.8 M' + (s * 4.8) + ',-12.8 l' + (s * 1.4) + ',-1.9 M' + (s * 6.6) + ',-14 l' + (s * 1) + ',-1.8 M' + (s * 3.4) + ',-10.6 l' + (s * 2) + ',.2 M' + (s * 5.4) + ',-12.3 l' + (s * 1.8) + ',.4" stroke="#C9BBA4" stroke-opacity=".8" stroke-width=".6"/>';
      const html = svg(-22, -20, 44, 36,
        '<ellipse cx="0" cy="0" rx="9" ry="7" fill="#FFF3D6" fill-opacity=".12"/>' + fluegel(1) + fluegel(-1) + fuehler(1) + fuehler(-1)
        + '<ellipse cx="0" cy="1" rx="2.8" ry="8" fill="#6E6253" stroke="#C9BBA4" stroke-width=".8"/><circle cx="0" cy="-7" r="2.4" fill="#7C6F5E" stroke="#C9BBA4" stroke-width=".7"/>'
        + '<circle cx="-1.1" cy="-7.6" r=".7" fill="#211B2C"/><circle cx="1.1" cy="-7.6" r=".7" fill="#211B2C"/>', 'nt-motte');
      const root = wesen(html);
      const inst = { el: root, dauer, cur: 0, leaveT: null };
      const roh = t => {
        const thE = th0 + om * (tO1 - tO0);
        if (t < tO0) {
          const u = raus(t / tO0), p1 = quadrat(th0);
          return { x: lerp(vonA.x, p1.x, u) + 9 * Math.sin(t * 13 + zit.ph1) * (1 - u), y: lerp(vonA.y, p1.y, u) + 7 * Math.sin(t * 17 + zit.ph2) * (1 - u) };
        }
        if (t < tO1) {
          const th = th0 + om * (t - tO0), p = quadrat(th);
          const c = { x: p.x - o.x, y: p.y - o.y }, l = Math.hypot(c.x, c.y) || 1;
          let d = 6 * Math.sin(t * 5.3 + zit.ph1) + 3 * Math.sin(t * 11 + zit.ph2);
          stups.forEach(ts => { const s = t - ts; if (s >= 0 && s < 0.35) d -= 10 * Math.sin(Math.PI * s / 0.35); });
          return { x: p.x + c.x / l * d, y: p.y + c.y / l * d };
        }
        const pE = quadrat(thE), u = rein(klemme((t - tO1) / 1.0, 0, 1));
        const aus = { x: pE.x - o.x, y: pE.y - o.y }, l = Math.hypot(aus.x, aus.y) || 1;
        return { x: pE.x + aus.x / l * 260 * u + 12 * Math.sin(t * 12), y: pE.y + aus.y / l * 260 * u - 120 * u + 8 * Math.sin(t * 15) };
      };
      const lage = t => {
        let p = roh(t), op = ein(t, 0, 0.3) * klemme((inst.dauer - t) / 0.3, 0, 1);
        if (inst.leaveT !== null && t >= inst.leaveT) {
          const p0 = roh(inst.leaveT), u = rein(klemme((t - inst.leaveT) / 0.4, 0, 1));
          const c = { x: p0.x - o.x, y: p0.y - o.y }, l = Math.hypot(c.x, c.y) || 1;
          p = { x: p0.x + c.x / l * 180 * u + 10 * Math.sin(t * 30), y: p0.y + c.y / l * 180 * u - 80 * u };
          op *= 1 - ein(t - inst.leaveT, 0.22, 0.16);
        }
        return { p, op };
      };
      inst.stelle = t => {
        inst.cur = t;
        const { p, op } = lage(t), q = lage(t + 0.04).p;
        const kurs = Math.atan2(q.y - p.y, q.x - p.x) / RAD + 90;
        S(root, p.x, p.y, kurs, 1.5, op);
      };
      inst.hulle = t => { const { p, op } = lage(t); return op < 0.03 ? null : kasten(p.x, p.y, 32, 26); };
      inst.abgang = () => { inst.leaveT = inst.cur; return 0.4; };
      return inst;
    },
  });

  /* ================================================================ 21 Igel am Tischrand */
  function igelSvg() {
    const st = [];
    for (let i = 0; i <= 28; i++) {   // Stachelkleid: 14 Zacken auf einem Bogen über dem Rücken
      const a = (178 - i * (150 / 28)) * RAD, r = i % 2 ? 1.27 + 0.07 * (((i - 1) / 2) % 2) : 1;
      st.push(n1(-3 + Math.cos(a) * 18 * r) + ',' + n1(-6 - Math.sin(a) * 12.5 * r));
    }
    const stacheln = 'M12,-4 L' + st.slice().reverse().join(' L') + ' L-21,-1 C-15,1 6,1 12,-4 Z';
    const linien = [-14, -9, -3, 3, 8].map((x, i) => '<path d="M' + x + ',' + (-6 - (i % 2)) + ' l' + (x < 0 ? -2.5 : 2) + ',-' + (6 + (i % 2) * 2) + '" stroke="#7E6246" stroke-width=".9" stroke-linecap="round"/>').join('');
    const kst = [];
    for (let i = 0; i < 44; i++) { const a = i * TAU / 44, r = i % 2 ? 15.5 : 11.5; kst.push(n1(Math.cos(a) * r) + ',' + n1(-12 + Math.sin(a) * r)); }
    const bein = (x, c) => '<g class="' + c + '"><rect x="' + (x - 1.6) + '" y="-3" width="3.4" height="5" rx="1.5" fill="#3E2F22"/></g>';
    return svg(-30, -34, 60, 40,
      '<g class="ig">'
      + bein(-11, 'ba') + bein(7, 'ba') + bein(-7, 'bb') + bein(11, 'bb')
      + '<ellipse cx="-2" cy="-3" rx="15" ry="4" fill="#C9AE88"/>'
      + '<path d="' + stacheln + '" fill="#5B4632" stroke="#8A6C4C" stroke-width=".75" stroke-linejoin="round"/>' + linien
      + '<path d="M-17,-15 C-11,-20 -2,-21 6,-18" fill="none" stroke="' + CREME + '" stroke-opacity=".5" stroke-width="1.6" stroke-linecap="round"/>'
      + '<g class="na"><path d="M5,-12 C11,-14 17,-10 22,-6 C21,-3.5 16,-1 6,-1 Z" fill="#D9BE98" stroke="#A88A62" stroke-width=".9" stroke-linejoin="round"/>'
      + '<circle cx="22.4" cy="-5.6" r="2.1" fill="' + INK + '"/><circle cx="23" cy="-6.3" r=".7" fill="#fff"/></g>'
      + '<circle cx="8.6" cy="-12.2" r="2.1" fill="#C9A77E" stroke="#A88A62" stroke-width=".6"/>'
      + '<circle cx="13.6" cy="-8.6" r="1.7" fill="' + INK + '"/><circle cx="14.1" cy="-9.2" r=".6" fill="#fff"/>'
      + '</g>'
      + '<g class="ku" style="opacity:0"><polygon points="' + kst.join(' ') + '" fill="#5B4632" stroke="#8A6C4C" stroke-width=".75" stroke-linejoin="round"/>'
      + '<circle cx="0" cy="-12" r="9" fill="#6A5239"/><path d="M-8,-20 C-4,-24 3,-24 7,-21" fill="none" stroke="' + CREME + '" stroke-opacity=".5" stroke-width="1.6" stroke-linecap="round"/>'
      + '<circle cx="5" cy="-6" r="1.5" fill="' + INK + '"/></g>');
  }
  N.art('igel', {
    baue(ctx, z) {
      const dauer = zz(z, 10, 14), SK = 1.6, Q = 0.93;
      const g = bandWahl(ctx, z, [[115, 160], [20, 65]], Q, 44);
      const D = Math.max(50, (dauer - 3.0) * 10);
      // Bahn: Bogen um den gewählten Winkel, die Länge reicht für D in beide Richtungen
      const bahn = bandBahn(ctx, g - 30, g + 30, Q);
      const sMitte = bahn.laenge / 2;
      const s0 = klemme(sMitte - D / 2, 0, bahn.laenge - D), s1 = s0 + D;
      // Von der äußeren Seite her kommen (die Seite, die weiter vom vorderen Bandteil weg ist)
      const pA = bahnPunkt(bahn, s0), pB = bahnPunkt(bahn, s1);
      const vonA = Math.abs(pA.x - ctx.cx) >= Math.abs(pB.x - ctx.cx);
      const sStart = vonA ? s0 : s1, sZiel = vonA ? s1 : s0, richt = vonA ? 1 : -1;
      const tA = 0.5, schnueff = [0.35, 0.7], tWeg = D / 20;
      const tWende = tA + tWeg + 1.6, tZur = tWende + 0.4, tEnde = tZur + tWeg;
      const stopps = [schnueff[0] * tWeg, schnueff[1] * tWeg + 0.8];
      const root = wesen(igelSvg());
      const q = s => root.querySelector(s);
      const E = { ig: q('.ig'), ku: q('.ku'), na: q('.na'), ba: Array.from(root.querySelectorAll('.ba')), bb: Array.from(root.querySelectorAll('.bb')) };
      const inst = { el: root, dauer, cur: 0, tapT: null, leaveT: null };
      // Weg (s) und Blickrichtung zur Zeit t ohne Tipp
      const weg = t => {
        if (t < tA) return { s: sStart, r: richt, geht: false, schn: 0 };
        if (t < tWende) {   // Gehzeit ohne die zwei Schnüffelpausen (je 0,8 s)
          const tt = t - tA;
          let geh = tt, schn = 0;
          stopps.forEach(a => { geh -= klemme(tt - a, 0, 0.8); if (tt > a && tt < a + 0.8) schn = (tt - a) / 0.8; });
          return { s: sStart + richt * klemme(20 * geh, 0, D), r: richt, geht: schn === 0 && geh < tWeg, schn };
        }
        if (t < tZur) return { s: sZiel, r: richt, geht: false, schn: 0, wende: (t - tWende) / 0.4 };
        return { s: sZiel - richt * Math.min(D, 20 * (t - tZur)), r: -richt, geht: t < tEnde, schn: 0 };
      };
      const lage = t => {
        let w = weg(t), kugel = 0, op = ein(t, 0, tA) * klemme((inst.dauer - t) / 0.5, 0, 1), auf = (1 - ein(t, 0, tA)) * 7;
        if (inst.tapT !== null && t >= inst.tapT) {
          const w0 = weg(inst.tapT), s = t - inst.tapT;
          kugel = s < 0.3 ? s / 0.3 : (s < 2.1 ? 1 : Math.max(0, 1 - (s - 2.1) / 0.3));
          if (s < 2.4) w = { s: w0.s, r: w0.r, geht: false, schn: 0 };
          else w = { s: w0.s + w0.r * 40 * (s - 2.4), r: w0.r, geht: true, schn: 0, schnell: true };
          op = Math.min(op, ein(inst.tapT, 0, tA));
        }
        if (inst.leaveT !== null) op *= klemme(1 - (t - inst.leaveT) / 0.38, 0, 1);
        const p = bahnPunkt(bahn, w.s);
        let rot = Math.atan2(p.dy, p.dx) / RAD;
        if (rot > 90) rot -= 180; if (rot < -90) rot += 180;
        let face = w.r * (p.dx >= 0 ? 1 : -1);
        if (w.wende !== undefined) face *= Math.cos(Math.PI * klemme(w.wende, 0, 1)) >= 0 ? 1 : -1;
        const wendeK = w.wende !== undefined ? Math.max(0.15, Math.abs(Math.cos(Math.PI * klemme(w.wende, 0, 1)))) : 1;
        return { x: p.x, y: p.y + auf, rot: klemme(rot, -28, 28), face, wendeK, w, kugel, op };
      };
      inst.stelle = t => {
        inst.cur = t;
        const L = lage(t);
        S(root, L.x, L.y, L.rot, SK, L.op);
        const kx = L.face * L.wendeK * (1 - 0.35 * L.kugel);
        T(E.ig, 'scale(' + (Math.round(kx * 1000) / 1000) + ' ' + (Math.round((1 - 0.35 * L.kugel) * 1000) / 1000) + ')');
        O(E.ig, 1 - L.kugel);
        T(E.ku, 'rotate(' + n1(L.kugel * (L.face > 0 ? 40 : -40) + (L.kugel >= 1 ? 4 * Math.sin(t * 9) : 0)) + ' 0 -12) scale(' + (Math.round((0.6 + 0.4 * L.kugel) * 1000) / 1000) + ')');
        O(E.ku, L.kugel);
        const tritt = L.w.geht ? Math.sin((L.w.s / 4.2) * Math.PI) : 0;
        E.ba.forEach(e => T(e, 'translate(0 ' + n1(-1.6 * Math.max(0, tritt)) + ')'));
        E.bb.forEach(e => T(e, 'translate(0 ' + n1(-1.6 * Math.max(0, -tritt)) + ')'));
        T(E.na, L.w.schn > 0 ? 'rotate(' + n1(4 * Math.sin(L.w.schn * Math.PI * 9)) + ' 8 -6)' : 'rotate(0)');
      };
      inst.hulle = t => { const L = lage(t); return L.op < 0.03 ? null : kasten(L.x, L.y - 14 * SK, 52 * SK, 32 * SK); };
      inst.tipp = () => { inst.tapT = inst.cur; inst.dauer = Math.min(inst.dauer, inst.cur + 2.4 + 1.6); };
      inst.abgang = () => { inst.leaveT = inst.cur; return 0.4; };
      return inst;
    },
  });

  /* ================================================================ 22 Komet (blass, langsam, oben; nie kreisend) */
  N.art('komet', {
    baue(ctx, z) {
      const W = ctx.W, dauer = zz(z, 14, 16), KS = 1.3;
      // freier Himmel links oder rechts der Mitte (in der Mitte sitzt der obere Platz); vom Rand zur Mitte hin, Schweif nach außen
      const links = z() < 0.5, sehne = 0.37 * W;
      const A = links ? { x: 0.03 * W, y: zz(z, 62, 105) } : { x: 0.97 * W, y: zz(z, 108, 138) };
      const B = { x: A.x + (links ? 1 : -1) * sehne, y: klemme(A.y + zz(z, -22, 18), links ? 48 : 98, links ? 118 : 148) };
      const C = { x: (A.x + B.x) / 2, y: (A.y + B.y) / 2 + 60 };
      const L1 = zz(z, 150, 180), L2 = zz(z, 140, 175);
      const id = uid('k');
      // Staubschweif breit und leicht gebogen (warm), Ionenschweif gerade und schmal (blau), Koma und Kern; alles blass und weich
      const verl = (gid, c0, c1, a) => '<linearGradient id="' + id + gid + '" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="' + c1 + '" stop-opacity="0"/>'
        + '<stop offset=".55" stop-color="' + c1 + '" stop-opacity="' + (a * 0.35).toFixed(2) + '"/><stop offset="1" stop-color="' + c0 + '" stop-opacity="' + a + '"/></linearGradient>';
      const staub = (b, k) => '<path d="M2,' + (-5 * k) + ' Q' + n1(-L1 * 0.5) + ',' + n1(-12 * k) + ' ' + n1(-L1) + ',' + n1(-34 * k - 6) + ' Q' + n1(-L1 * 0.88) + ',-6 ' + n1(-L1 - 4) + ',' + n1(16 * k + 4)
        + ' Q' + n1(-L1 * 0.5) + ',' + n1(8 * k) + ' 2,' + (5 * k) + ' Z" fill="url(#' + id + b + ')"/>';
      const html = svg(-240, -70, 270, 140,
        '<defs>' + verl('a', '#FFF6D8', '#FFE3A0', 0.55) + verl('b', '#FFFBEA', '#FFEBB5', 0.7) + verl('c', '#C8DEFF', '#8FB8FF', 0.35) + verl('d', '#EAF2FF', '#9CC4FF', 0.8)
        + '<radialGradient id="' + id + 'h"><stop offset="0" stop-color="#FFFDF0" stop-opacity=".95"/><stop offset=".22" stop-color="#FFF3C8" stop-opacity=".5"/><stop offset=".55" stop-color="#FFE9A8" stop-opacity=".14"/><stop offset="1" stop-color="#FFE9A8" stop-opacity="0"/></radialGradient></defs>'
        + staub('a', 1.25) + staub('b', 0.6)
        + '<g transform="rotate(-6)"><path d="M2,-5 L' + n1(-L2 - 20) + ',-2.4 L' + n1(-L2 - 20) + ',2.4 L2,5 Z" fill="url(#' + id + 'c)"/>'
        + '<path d="M2,-1.6 L' + n1(-L2 - 20) + ',-.5 L' + n1(-L2 - 20) + ',.5 L2,1.6 Z" fill="url(#' + id + 'd)"/></g>'
        + '<ellipse cx="-7" cy="0" rx="24" ry="12" fill="url(#' + id + 'h)"/><circle r="30" fill="url(#' + id + 'h)"/><circle r="4" fill="#FFFDF2"/>');
      const root = wesen(html);
      const inst = { el: root, dauer, cur: 0, leaveT: null };
      const lage = t => {
        const u = klemme(t / dauer, 0, 1), p = bez2(A, C, B, u), q = bez2(A, C, B, Math.min(1, u + 0.01)), q0 = bez2(A, C, B, Math.max(0, u - 0.01));
        return { x: p.x, y: p.y, rot: Math.atan2(q.y - q0.y, q.x - q0.x) / RAD };
      };
      const deck = t => { let a = ein(t, 0, 2) * klemme((inst.dauer - t) / 3, 0, 1); if (inst.leaveT !== null) a *= klemme(1 - (t - inst.leaveT) / 0.38, 0, 1); return a; };
      inst.stelle = t => { inst.cur = t; const p = lage(t); S(root, p.x, p.y, p.rot, KS, deck(t)); };
      inst.hulle = t => {
        if (deck(t) < 0.05) return null;
        const p = lage(t), r = p.rot * RAD, e = { x: p.x - Math.cos(r) * L1 * 0.8 * KS, y: p.y - Math.sin(r) * L1 * 0.8 * KS };
        const x0 = Math.min(p.x, e.x) - 14, y0 = Math.min(p.y, e.y) - 18;
        return { x: x0, y: y0, w: Math.max(p.x, e.x) + 14 - x0, h: Math.max(p.y, e.y) + 18 - y0 };
      };
      inst.abgang = () => { inst.leaveT = inst.cur; return 0.4; };
      return inst;
    },
  });

  /* ================================================================ 23 Lampion */
  N.art('lampion', {
    baue(ctx, z) {
      const o = ctx.ort, dauer = zz(z, 11, 13), SK = 1.15;
      const v = klemme((o.y - (o.ziel_y || -80)) / (dauer - 0.6), 34, 50);
      const ph = z() * TAU, fl = [zz(z, 7, 11), zz(z, 13, 19), z() * TAU];
      const id = uid('l');
      const rippe = (c) => '<path d="M0,-20 C' + c + ',-12 ' + c + ',12 0,20" fill="none" stroke="#C45A10" stroke-opacity=".75" stroke-width="1.2"/>';
      const html = '<div class="nt-halo" style="left:-60px;top:-60px;width:120px;height:120px;background:radial-gradient(circle,rgba(255,210,122,.42) 0,rgba(255,170,70,.18) 35%,rgba(255,150,60,0) 70%)"></div>'
        + svg(-24, -32, 48, 64,
          '<defs><radialGradient id="' + id + 'g" cx=".5" cy=".58" r=".62"><stop offset="0" stop-color="#FFE7A0"/><stop offset=".45" stop-color="#FFB04A"/><stop offset="1" stop-color="#E86A14"/></radialGradient></defs>'
          + '<ellipse cx="0" cy="0" rx="17" ry="21" fill="url(#' + id + 'g)" stroke="#C45A10" stroke-width="1.1"/>'
          + '<ellipse class="in" cx="0" cy="3" rx="8.5" ry="11" fill="#FFF1B8" fill-opacity=".55"/>'
          + rippe(-11) + rippe(-5) + rippe(5) + rippe(11)
          + '<rect x="-9" y="-24" width="18" height="4.5" rx="1.6" fill="' + INK + '" stroke="#FFB15A" stroke-opacity=".7" stroke-width=".8"/>'
          + '<rect x="-7" y="19.5" width="14" height="4" rx="1.5" fill="' + INK + '" stroke="#FFB15A" stroke-opacity=".7" stroke-width=".8"/>'
          + '<path class="fl" d="M0,27 C-2.6,24.5 -1.8,22 0,20.5 C1.8,22 2.6,24.5 0,27 Z" fill="#FFE7A0"/>');
      const root = wesen(html);
      const halo = root.querySelector('.nt-halo'), innen = root.querySelector('.in');
      const inst = { el: root, dauer, cur: 0, tapT: null, leaveT: null };
      const lage = t => {
        let amp = 10, rotA = 4, glow = 0;
        if (inst.tapT !== null && t >= inst.tapT) {
          const s = t - inst.tapT;
          glow = s < 0.15 ? s / 0.15 : Math.max(0, 1 - (s - 0.15) / 0.45);
          const st = Math.exp(-s * 0.9);
          amp = 10 + 16 * st; rotA = 4 + 9 * st;
        }
        const x = o.x + amp * Math.sin(TAU * t / 3 + ph), y = o.y + 6 - v * t, rot = rotA * Math.sin(TAU * t / 3 + ph + 0.7);
        let op = ein(t, 0, 0.8) * klemme((inst.dauer - t) / 0.6, 0, 1);
        if (inst.leaveT !== null) op *= klemme(1 - (t - inst.leaveT) / 0.38, 0, 1);
        return { x, y, rot, glow, op };
      };
      inst.stelle = t => {
        inst.cur = t;
        const L = lage(t);
        S(root, L.x, L.y, L.rot, SK, L.op);
        const fk = 0.8 + 0.1 * Math.sin(t * fl[0]) + 0.1 * Math.sin(t * fl[1] + fl[2]);
        O(innen, Math.min(1, fk + L.glow * 0.6));
        S(halo, 0, 0, 0, 1 + 0.6 * L.glow, Math.min(1, 0.75 * fk + 0.25 + 0.4 * L.glow));
      };
      inst.hulle = t => { const L = lage(t); return L.op < 0.03 ? null : kasten(L.x, L.y, 40 * SK, 52 * SK); };
      inst.tipp = () => { inst.tapT = inst.cur; };
      inst.abgang = () => { inst.leaveT = inst.cur; return 0.4; };
      return inst;
    },
  });

  /* ================================================================ B2 Sternschnuppe (Bestand, leuchtend wie in der App) */
  // Kopf mit Lichthof und funkelnden Strahlen, langer Schweif weiß → gold → eisblau → violett, Funken, die abfallen und verglimmen;
  // am Ende verglüht der Kopf mit einem kurzen Aufblitzen und einem Funkenkranz. Bahn wie FunFx.SkyNode.launch (hoch und flach).
  N.art('sternschnuppe', {
    baue(ctx, z) {
      const W = ctx.W, H = ctx.H, nacht = ctx.nacht !== false;
      const MOVE = 1.2, AFTER = 0.6, TAIL = 0.6;
      const p0 = { x: zz(z, 0.5, 0.95) * W, y: zz(z, 0.03, 0.13) * H }, p1 = { x: p0.x - 0.34 * W, y: p0.y + 0.11 * H };
      const pl = Math.hypot(p1.x - p0.x, p1.y - p0.y), dirW = Math.atan2(p1.y - p0.y, p1.x - p0.x) / RAD;
      const dx = (p1.x - p0.x) / pl, dy = (p1.y - p0.y) / pl, px = -dy, py = dx;
      const ease = t => { const u = klemme(t / MOVE, 0, 1); return u * (2 - u); };
      const kopf = t => ({ x: p0.x + (p1.x - p0.x) * ease(t), y: p0.y + (p1.y - p0.y) * ease(t) });
      const FA = nacht ? ['#FFFFFF', '#FFF1C2', '#FFCF5A', '#7FD4FF', '#A77BFF'] : ['#FFC23A', '#FFA51E', '#FF8A3D', '#F86F6F', '#E26AA8'];
      const SP = nacht ? ['#FFFFFF', '#FFE9A0', '#FFD66B', '#FFC400', '#BFE8FF', '#FFB3E6'] : ['#FFB21E', '#FF9A2E', '#FFC94A', '#FF7A59'];
      // Funken: Startzeit, Ort, Tempo (Luftwiderstand 0,25^Alter, sanft nach unten), Lebensdauer
      const fk = [], k4 = Math.log(4);
      for (let i = 0; i < 15; i++) {
        const ts = MOVE * Math.pow(z(), 1.3) * 0.95, h = kopf(ts), sp = (1 - ts / MOVE);
        const vb = zz(z, 20, 90) * (0.6 + 0.4 * sp), vq = zz(z, -38, 38);
        fk.push({ ts, x: h.x + px * zz(z, -3, 3), y: h.y + py * zz(z, -3, 3), vx: -dx * vb + px * vq, vy: -dy * vb + py * vq + zz(z, 0, 30), life: zz(z, 0.35, 0.95), r: zz(z, 2.6, 5), c: SP[Math.floor(z() * SP.length)], fl: zz(z, 22, 40), ph: z() * TAU });
      }
      for (let i = 0; i < 7; i++) {
        const a = TAU * (i + z()) / 7, sp = zz(z, 35, 85);
        fk.push({ ts: MOVE, x: p1.x, y: p1.y, vx: Math.cos(a) * sp + dx * 25, vy: Math.sin(a) * sp + dy * 25, life: zz(z, 0.35, 0.6), r: zz(z, 2.4, 4.2), c: SP[Math.floor(z() * SP.length)], fl: zz(z, 22, 40), ph: z() * TAU });
      }
      const fkPos = (f, a) => { const e = (1 - Math.exp(-k4 * a)) / k4, g = 70; return { x: f.x + f.vx * e, y: f.y + f.vy * e + g / k4 * (a - e) }; };
      const id = uid('ss'), L = 400;
      const stops = (aMul) => FA.map((c, i) => '<stop offset="' + (i / (FA.length - 1)).toFixed(2) + '" stop-color="' + c + '" stop-opacity="' + (Math.pow(1 - i / (FA.length - 1), 1.15) * aMul).toFixed(3) + '"/>').join('');
      const glut = SP.map((c, i) => '<radialGradient id="' + id + 'f' + i + '"><stop offset="0" stop-color="#fff" stop-opacity="1"/><stop offset=".22" stop-color="' + c + '" stop-opacity=".95"/>'
        + '<stop offset=".5" stop-color="' + c + '" stop-opacity=".3"/><stop offset="1" stop-color="' + c + '" stop-opacity="0"/></radialGradient>').join('');
      const html = svg(0, 0, 10, 10,
        '<defs><linearGradient id="' + id + 'a" x1="0" y1="0" x2="1" y2="0">' + stops(nacht ? 0.95 : 0.9) + '</linearGradient>'
        + '<linearGradient id="' + id + 'b" x1="0" y1="0" x2="1" y2="0">' + stops(nacht ? 0.3 : 0.24) + '</linearGradient>'
        + '<linearGradient id="' + id + 'w" x1="0" y1="0" x2="1" y2="0">' + stops(nacht ? 0.13 : 0.1) + '</linearGradient>'
        + '<linearGradient id="' + id + 'k" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#fff" stop-opacity=".95"/><stop offset=".35" stop-color="#fff" stop-opacity=".35"/><stop offset=".7" stop-color="#fff" stop-opacity="0"/></linearGradient>' + glut
        + '<radialGradient id="' + id + 'h"><stop offset="0" stop-color="' + (nacht ? '#FFE7A8' : '#FFC53D') + '" stop-opacity=".55"/><stop offset=".45" stop-color="' + (nacht ? '#FFE7A8' : '#FFC53D') + '" stop-opacity=".18"/><stop offset="1" stop-color="' + (nacht ? '#FFE7A8' : '#FFC53D') + '" stop-opacity="0"/></radialGradient>'
        + '<radialGradient id="' + id + 'i"><stop offset="0" stop-color="#fff" stop-opacity="1"/><stop offset=".5" stop-color="' + (nacht ? '#fff' : '#FFB21E') + '" stop-opacity=".45"/><stop offset="1" stop-color="#fff" stop-opacity="0"/></radialGradient>'
        + '<linearGradient id="' + id + 'r" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="' + (nacht ? '#FFF6DC' : '#FF9A2E') + '" stop-opacity="0"/><stop offset=".5" stop-color="' + (nacht ? '#FFF6DC' : '#FF9A2E') + '" stop-opacity="1"/><stop offset="1" stop-color="' + (nacht ? '#FFF6DC' : '#FF9A2E') + '" stop-opacity="0"/></linearGradient></defs>'
        + '<g class="sw" transform="scale(0)"><polygon points="0,-19 ' + L + ',-3 ' + L + ',3 0,19" fill="url(#' + id + 'w)"/>'
        + '<polygon points="0,-10 ' + L + ',-1.8 ' + L + ',1.8 0,10" fill="url(#' + id + 'b)"/>'
        + '<polygon points="0,-4.2 ' + L + ',-.6 ' + L + ',.6 0,4.2" fill="url(#' + id + 'a)"/>'
        + '<polygon points="0,-1.6 ' + L + ',-.2 ' + L + ',.2 0,1.6" fill="url(#' + id + 'k)"/></g>'
        + fk.map(f => '<g class="fk" style="opacity:0"><circle r="' + n1(f.r * 2.4) + '" fill="url(#' + id + 'f' + SP.indexOf(f.c) + ')"/></g>').join('')
        + '<g class="kf"><circle r="40" fill="url(#' + id + 'h)"/><circle r="15" fill="url(#' + id + 'i)"/>'
        + '<g class="ra"><rect x="-37" y="-1.1" width="74" height="2.2" rx="1.1" fill="url(#' + id + 'r)"/></g>'
        + '<g class="rb"><rect x="-37" y="-1.1" width="74" height="2.2" rx="1.1" fill="url(#' + id + 'r)"/></g>'
        + '<g class="rc"><rect x="-18" y="-.9" width="36" height="1.8" rx=".9" fill="url(#' + id + 'r)"/></g>'
        + '<g class="rd"><rect x="-18" y="-.9" width="36" height="1.8" rx=".9" fill="url(#' + id + 'r)"/></g>'
        + '<circle r="5.5" fill="#fff"/></g>');
      const root = wesen(html);
      const q = s => root.querySelector(s);
      const E = { sw: q('.sw'), kf: q('.kf'), ra: q('.ra'), rb: q('.rb'), rc: q('.rc'), rd: q('.rd'), fk: Array.from(root.querySelectorAll('.fk')) };
      const dauer = MOVE + AFTER;
      const inst = { el: root, dauer, cur: 0, leaveT: null };
      const hell = t => (t >= MOVE ? klemme(1 - (t - MOVE) / 0.2, 0, 1) * 1.35 : klemme(t / 0.1, 0, 1) * (1 + 0.35 * glatt((t / MOVE - 0.75) / 0.25)));
      inst.stelle = t => {
        inst.cur = t;
        const h = kopf(t), e = ease(t);
        let fade = 1;
        if (inst.leaveT !== null) fade = klemme(1 - (t - inst.leaveT) / 0.35, 0, 1);
        S(root, 0, 0, 0, 1, fade);
        // Schweif: Länge wächst mit der Bahn, nach dem Ende des Fluges glüht er von hinten nach vorn aus
        const len = Math.min(TAIL, e) * pl * (t > MOVE ? Math.max(0, 1 - (t - MOVE) / AFTER) : 1);
        const glimm = t > MOVE ? Math.max(0, 1 - (t - MOVE) / AFTER) : 1;
        T(E.sw, 'translate(' + n1(h.x) + ' ' + n1(h.y) + ') rotate(' + n1(dirW + 180) + ') scale(' + (Math.round(Math.max(0.001, len / L) * 10000) / 10000) + ' ' + (nacht ? 1 : 0.85) + ')');
        O(E.sw, glimm);
        const hb = hell(t), tw = 0.82 + 0.18 * Math.sin(t * 31) * Math.sin(t * 13 + 1);
        T(E.kf, 'translate(' + n1(h.x) + ' ' + n1(h.y) + ') scale(' + (Math.round((0.75 + 0.25 * Math.min(1, hb)) * (nacht ? 1 : 0.85) * 1000) / 1000) + ')');
        O(E.kf, Math.min(1, hb));
        const lng = tw * (0.8 + 0.2 * Math.min(1, hb));
        T(E.ra, 'rotate(7) scale(' + (Math.round(lng * 1000) / 1000) + ' 1)');
        T(E.rb, 'rotate(97) scale(' + (Math.round(lng * 1000) / 1000) + ' 1)');
        const sht = (2 - tw) * 0.9;
        T(E.rc, 'rotate(52) scale(' + (Math.round(sht * 1000) / 1000) + ' 1)');
        T(E.rd, 'rotate(142) scale(' + (Math.round(sht * 1000) / 1000) + ' 1)');
        fk.forEach((f, i) => {
          const a = t - f.ts;
          if (a < 0 || a >= f.life) { O(E.fk[i], 0); return; }
          const u = a / f.life, p = fkPos(f, a), fl = 0.6 + 0.4 * Math.sin(a * f.fl + f.ph);
          T(E.fk[i], 'translate(' + n1(p.x) + ' ' + n1(p.y) + ') scale(' + (Math.round((1 - 0.45 * u) * 1000) / 1000) + ')');
          O(E.fk[i], Math.pow(1 - u, 1.3) * fl * (nacht ? 1 : 0.85));
        });
      };
      inst.hulle = t => {
        const h = kopf(t), e = ease(t), len = Math.min(TAIL, e) * pl * (t > MOVE ? Math.max(0, 1 - (t - MOVE) / AFTER) : 1);
        if (t > MOVE + 0.2 && len < 4) return null;
        const ex = h.x - dx * len, ey = h.y - dy * len;
        const x0 = Math.min(h.x, ex) - 16, y0 = Math.min(h.y, ey) - 16;
        return { x: x0, y: y0, w: Math.max(h.x, ex) + 16 - x0, h: Math.max(h.y, ey) + 16 - y0 };
      };
      inst.abgang = () => { inst.leaveT = inst.cur; return 0.35; };
      return inst;
    },
  });

  /* ================================================================ 24 Feuerwerk (1.6.15)
   * Nutzerwunsch 23.10.2026: „Ein Feuerwerk als zufällige Aktion bei Nacht“. 2–4 Raketen steigen mit Leuchtspur in freien Himmel und
   * zerplatzen in bunte Funkensterne, die sinken und verglimmen (wie game/scripts/ui/nature_night.gd Fireworks). Je Knall eine Gruppe
   * mit zwei Strich-Pfaden (äußerer Stern, innerer Kranz) und einem Blitz; die Gruppe wächst per scale und sinkt per translate.
   * Antippen: an der Stelle noch ein Knall (höchstens zweimal, tippMax 2). Hülle = was gerade leuchtet (ohne Teile unter Plätzen). */
  N.stil('feuerwerk', [
    '.nt-fw{mix-blend-mode:screen}',
  ].join('\n'));
  N.art('feuerwerk', {
    baue(ctx, z) {
      const W = ctx.W, H = ctx.H, dauer0 = zz(z, 5, 6), DRAG = 3.2, GRAV = 40;
      const FARBEN = ['#FF4FD8', '#FFD65A', '#3FF2E6', '#A77BFF', '#7CFFB2', '#FF9A3C'];
      const schutz = ctx.schutz.concat(extraSchutz());
      const deckung = r => { const a = r.w * r.h; return a > 0 ? Math.min(1, ueberdeckt(r, schutz) / a) : 0; };
      const draussen = r => { const a = r.w * r.h, x0 = Math.max(0, r.x), y0 = Math.max(0, r.y), x1 = Math.min(W, r.x + r.w), y1 = Math.min(H, r.y + r.h); return a > 0 ? 1 - Math.max(0, x1 - x0) * Math.max(0, y1 - y0) / a : 1; };
      const mond = ctx.orte && ctx.orte.mond ? ctx.orte.mond : { x: W * 0.93, y: H * 0.1 };
      let n = 2 + Math.floor(z() * 3);
      const b0 = zz(z, 1.05, 1.25), b1 = dauer0 - 1.85;
      while (n > 2 && (b1 - b0) / (n - 1) < 0.55) n--;
      const knalle = [], stellen = [];
      const neuerKnall = (tb, c, R, von, steig) => {
        const stil = Math.floor(z() * 3);   // 0 Pfingstrose, 1 Ring, 2 Trauerweide (gold, sinkt stärker)
        let c0 = FARBEN[Math.floor(z() * FARBEN.length)], c1 = FARBEN[Math.floor(z() * FARBEN.length)];
        if (stil === 2) { c0 = '#FFD65A'; c1 = '#FF9A3C'; }
        const m = 28 + Math.floor(z() * 7), aussen = [], innen = [], spitzen = [];
        for (let i = 0; i < m; i++) {
          const a = TAU * (i + zz(z, -0.25, 0.25)) / m, v = stil === 1 ? 1 : zz(z, 0.78, 1);
          aussen.push('M' + n1(Math.cos(a) * R * v * 0.66) + ',' + n1(Math.sin(a) * R * v * 0.66) + ' L' + n1(Math.cos(a) * R * v) + ',' + n1(Math.sin(a) * R * v));
          spitzen.push('M' + n1(Math.cos(a) * R * v) + ',' + n1(Math.sin(a) * R * v) + ' l0,0');
        }
        const k = 10 + Math.floor(z() * 5);
        for (let i = 0; i < k; i++) {
          const a = TAU * (i + 0.5) / k, v = zz(z, 0.4, 0.5);
          innen.push('M' + n1(Math.cos(a) * R * v * 0.62) + ',' + n1(Math.sin(a) * R * v * 0.62) + ' L' + n1(Math.cos(a) * R * v) + ',' + n1(Math.sin(a) * R * v));
        }
        return { t: tb, c, R, von, steig, c0, c1, grav: stil === 2 ? 1.9 : 1, life: 1.8, ph: z() * TAU, aussen: aussen.join(' '), innen: innen.join(' '), spitzen: spitzen.join(' ') };
      };
      for (let i = 0; i < n; i++) {
        const tb = lerp(b0, b1, i / Math.max(1, n - 1)) + zz(z, -0.12, 0.12), R = zz(z, 84, 104);
        let best = { x: W / 2, y: H * 0.16 }, bk = Infinity;
        for (let j = 0; j < 40; j++) {
          const p = { x: zz(z, 0.1, 0.9) * W, y: zz(z, 0.1, 0.27) * H }, r = kasten(p.x, p.y, R * 1.7, R * 1.7);
          let k = (deckung(r) + draussen(r)) * 3;
          if (Math.hypot(p.x - mond.x, p.y - mond.y) < R + 80) k += 2;
          stellen.forEach(q => { const d = Math.hypot(p.x - q.x, p.y - q.y); if (d < R * 1.9) k += 1.5 * (1 - d / (R * 1.9)); });
          k += z() * 0.08;
          if (k < bk) { bk = k; best = p; }
        }
        stellen.push(best);
        let von = { x: best.x, y: best.y + 200 }, vk = Infinity;
        [-50, -25, 0, 25, 50].forEach(dx => [160, 200, 240].forEach(dy => {
          const f = { x: best.x + dx, y: best.y + dy };
          let k = 0;
          for (let m = 0; m < 6; m++) { const u = (m + 0.5) / 6; k += deckung(kasten(lerp(f.x, best.x, u), lerp(f.y, best.y, u), 20, 28)); }
          k += Math.abs(dx) * 0.002 + z() * 0.05;
          if (k < vk) { vk = k; von = f; }
        }));
        knalle.push(neuerKnall(tb, best, R, von, zz(z, 0.85, 1.05)));
      }
      const extra = [neuerKnall(0, null, zz(z, 76, 90), null, 0), neuerKnall(0, null, zz(z, 76, 90), null, 0)];
      const id = uid('fw');
      const hoefe = Array.from(new Set(knalle.concat(extra).map(k => k.c0))).map(c => '<radialGradient id="' + id + 'h' + c.slice(1) + '"><stop offset="0" stop-color="' + c + '" stop-opacity=".32"/><stop offset=".55" stop-color="' + c + '" stop-opacity=".1"/><stop offset="1" stop-color="' + c + '" stop-opacity="0"/></radialGradient>').join('');
      let inner = '<defs>' + hoefe + '<radialGradient id="' + id + 'b"><stop offset="0" stop-color="#fff" stop-opacity="1"/><stop offset=".25" stop-color="#FFF3C8" stop-opacity=".7"/><stop offset="1" stop-color="#FFF3C8" stop-opacity="0"/></radialGradient>'
        + '<linearGradient id="' + id + 's" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#FFE2A8" stop-opacity="0"/><stop offset="1" stop-color="#FFE2A8" stop-opacity=".95"/></linearGradient></defs>';
      knalle.concat(extra).forEach(k => {
        inner += '<g class="kn" style="opacity:0"><circle r="' + n1(k.R * 1.15) + '" fill="url(#' + id + 'h' + k.c0.slice(1) + ')"/><circle class="bl" r="' + n1(k.R * 0.55) + '" fill="url(#' + id + 'b)"/>'
          + '<path d="' + k.aussen + '" stroke="' + k.c0 + '" stroke-width="4.6" stroke-linecap="round" fill="none"/>'
          + '<path d="' + k.spitzen + '" stroke="#FFFBEA" stroke-width="7" stroke-linecap="round" fill="none"/>'
          + '<path d="' + k.innen + '" stroke="' + k.c1 + '" stroke-width="3.4" stroke-linecap="round" fill="none"/></g>';
      });
      knalle.forEach(() => { inner += '<g class="ra" style="opacity:0"><rect x="-40" y="-1.4" width="40" height="2.8" rx="1.4" fill="url(#' + id + 's)"/><circle r="3.2" fill="#fff"/><circle r="8" fill="#FFE2A8" fill-opacity=".35"/></g>'; });
      const root = wesen(svg(0, 0, Math.round(W), Math.round(H), inner, 'nt-fw'));
      const gk = Array.from(root.querySelectorAll('.kn')), gr = Array.from(root.querySelectorAll('.ra')), bl = gk.map(g => g.querySelector('.bl'));
      const inst = { el: root, dauer: dauer0, cur: 0, leaveT: null, tippMax: 2, tipps: [] };
      const alle = () => knalle.concat(inst.tipps.map((tp, i) => Object.assign({}, extra[i], { t: tp.at, c: { x: klemme(tp.x, 40, W - 40), y: klemme(tp.y - 12, 40, H * 0.6) } })));
      const weite = a => (1 - Math.exp(-DRAG * a)) / (1 - Math.exp(-DRAG * 1.1));
      const rakete = (k, t) => {
        const u = klemme((t - (k.t - k.steig)) / k.steig, 0, 1), e = raus(u);
        return { x: lerp(k.von.x, k.c.x, e) + Math.sin(u * Math.PI) * 6, y: lerp(k.von.y, k.c.y, e), u };
      };
      const fade = t => { let a = 1 - ein(t, inst.dauer - 0.2, 0.2); if (inst.leaveT !== null) a *= klemme(1 - (t - inst.leaveT) / 0.38, 0, 1); return a; };
      inst.stelle = t => {
        inst.cur = t;
        O(root, fade(t));
        const ks = alle();
        ks.forEach((k, i) => {
          const g = gk[i], age = t - k.t;
          if (age < 0 || age > k.life) { O(g, 0); return; }
          const d = Math.max(0.12, weite(age)), sag = GRAV * k.grav * age * age;
          let a = ausAb(age, k.life * 0.55, k.life * 0.45);
          if (age > k.life * 0.45) a *= 0.6 + 0.4 * Math.sin(age * 34 + k.ph);
          T(g, tr(k.c.x, k.c.y + sag, 0, d));
          O(g, a);
          O(bl[i], age < 0.35 ? 1 - age / 0.35 : 0);
        });
        knalle.forEach((k, i) => {
          const g = gr[i];
          if (t < k.t - k.steig || t >= k.t) { O(g, 0); return; }
          const p = rakete(k, t), q = rakete(k, Math.max(k.t - k.steig, t - 0.05));
          T(g, tr(p.x, p.y, Math.atan2(p.y - q.y, p.x - q.x) / RAD));
          O(g, ein(t, k.t - k.steig, 0.15));
        });
      };
      inst.hulle = t => {
        if (fade(t) < 0.05) return null;
        let u = null, best = null, bc = 2;
        const add = r => {
          if (r.x + r.w < 0 || r.x > W || r.y + r.h < 0 || r.y > H) return;
          const cv = deckung(r);
          if (cv >= 0.5) return;
          if (cv < bc) { bc = cv; best = r; }
          u = u ? { x: Math.min(u.x, r.x), y: Math.min(u.y, r.y), w: Math.max(u.x + u.w, r.x + r.w) - Math.min(u.x, r.x), h: Math.max(u.y + u.h, r.y + r.h) - Math.min(u.y, r.y) } : r;
        };
        alle().forEach(k => {
          if (k.steig > 0 && t >= k.t - k.steig && t < k.t) { const p = rakete(k, t); add(kasten(p.x, p.y, 20, 28)); }
          else if (t >= k.t && t < k.t + k.life) { const age = t - k.t, rr = k.R * Math.max(0.15, weite(age)) + 8; add(kasten(k.c.x, k.c.y + GRAV * k.grav * age * age * 0.6, rr * 2, rr * 2)); }
        });
        return u && deckung(u) > 0.5 ? best : u;
      };
      inst.treffer = p => { const h = inst.hulle(inst.cur); return !!h && p.x >= h.x - 20 && p.x <= h.x + h.w + 20 && p.y >= h.y - 20 && p.y <= h.y + h.h + 20; };
      inst.tipp = p => { if (inst.tipps.length < 2 && p) { inst.tipps.push({ at: inst.cur, x: p.x, y: p.y }); inst.dauer = Math.max(inst.dauer, inst.cur + 2.0); } };
      inst.knalle = t => alle().filter(k => t - k.t >= 0 && t - k.t < k.life).map(k => k.c);
      inst.abgang = () => { inst.leaveT = inst.cur; return 0.4; };
      return inst;
    },
  });

  /* ================================================================ 25 Astronaut am Mond (1.6.15)
   * Nutzerwunsch 23.10.2026: „Ein Astronaut schwebt neben dem Mond“. Kleiner, runder Astronaut (weißer Anzug, Visier mit Spiegelung) wie
   * in der App (nature_night.gd Astronaut): schwebt schräg von oben neben den Mond, taumelt langsam, winkt einmal, treibt nach links oben
   * davon. Antippen: langsamer Salto mit Winken. Meidet Menü- und Ton-Knopf, Plätze und den Mond selbst. */
  function astronautSvg() {
    const L = '#8A80C8', ANZ = '#F6F4FF', ANZ_D = '#D2CCEE', id = uid('as');
    const glied = (a, b, r, cls) => {
      const w = Math.atan2(b[1] - a[1], b[0] - a[0]) / RAD, l = Math.hypot(b[0] - a[0], b[1] - a[1]);
      return '<g class="' + (cls || '') + '" transform="translate(' + a[0] + ' ' + a[1] + ')"><g transform="rotate(' + n1(w) + ')">'
        + '<rect x="' + (-r) + '" y="' + (-r) + '" width="' + n1(l + 2 * r) + '" height="' + 2 * r + '" rx="' + r + '" fill="' + ANZ + '" stroke="' + L + '" stroke-width="1.3"/>'
        + '<circle cx="' + n1(l) + '" cy="0" r="' + n1(r * 1.05) + '" fill="' + ANZ_D + '" stroke="' + L + '" stroke-width="1.1"/></g></g>';
    };
    return svg(-40, -46, 80, 86,
      '<defs><radialGradient id="' + id + 'g"><stop offset="0" stop-color="#9A86FF" stop-opacity=".22"/><stop offset="1" stop-color="#9A86FF" stop-opacity="0"/></radialGradient></defs>'
      + '<circle cx="0" cy="-4" r="38" fill="url(#' + id + 'g)"/>'
      + '<path d="M-15,-8 L-4,-11 L-3,11 L-14,12 Z" fill="#B9B2DC" stroke="' + L + '" stroke-width="1.2" stroke-linejoin="round"/>'
      + '<g class="bl">' + glied([-4.5, 10], [-6.5, 20.5], 4.4) + '</g><g class="br">' + glied([4.5, 10], [6.5, 19.5], 4.4) + '</g>'
      + '<ellipse cx="0" cy="4" rx="11" ry="11.5" fill="' + ANZ + '" stroke="' + L + '" stroke-width="1.3"/>'
      + '<path d="M-5.5,0.5 L5.5,0.5 L5,8 L-5,8 Z" fill="' + ANZ_D + '" stroke="' + L + '" stroke-opacity=".8" stroke-width=".9"/>'
      + '<circle cx="-2.6" cy="3" r="1.4" fill="#FF4FD8"/><circle cx="0.6" cy="3" r="1.4" fill="#FFD65A"/><circle cx="3.4" cy="3" r="1.4" fill="#3FF2E6"/>'
      + glied([-9, -1], [-17, 6], 3.8)
      + '<ellipse cx="0" cy="-14" rx="13" ry="12.5" fill="' + ANZ + '" stroke="' + L + '" stroke-width="1.4"/>'
      + '<ellipse cx="1.2" cy="-14" rx="9.6" ry="7.6" fill="#1B2147" stroke="' + L + '" stroke-width="1.1"/>'
      + '<ellipse cx="2.4" cy="-12.4" rx="7" ry="4.4" fill="#2E3A78" fill-opacity=".9"/>'
      + '<path d="M8.5,-12.7 A7.4,7.4 0 0 1 3.7,-7.0" fill="none" stroke="#5FE3F0" stroke-opacity=".85" stroke-width="1.6" stroke-linecap="round"/>'
      + '<path d="M-4.9,-17.8 A7,7 0 0 1 -0.3,-20.8" fill="none" stroke="#fff" stroke-opacity=".9" stroke-width="1.8" stroke-linecap="round"/>'
      + '<circle cx="5.4" cy="-17" r="2.1" fill="#fff" fill-opacity=".85"/><circle cx="6.3" cy="-17.6" r="1.8" fill="#1B2147"/><circle cx="-3.2" cy="-17.6" r=".9" fill="#fff"/>'
      + '<path d="M-4,-25.5 L-5,-29" stroke="' + L + '" stroke-width="1.2"/><circle class="la" cx="-5" cy="-29.5" r="2" fill="#FF4FD8"/>'
      + '<g class="ar" transform="translate(9 -1)">' + glied([0, 0], [10.5, 0], 3.8) + '</g>');
  }
  N.art('astronaut', {
    baue(ctx, z) {
      const W = ctx.W, H = ctx.H, SK = 1.5;
      let dauer = zz(z, 9, 12);
      const IN = 2.2, OUT = 2.0, SALTO = 1.9;
      const m = ctx.ort && typeof ctx.ort.x === 'number' ? ctx.ort : { x: W * 0.93 - 52, y: 0.04 * H + 52, w: 104 };
      const mr = (m.w || 104) / 2, he = { w: 52 * SK, h: 64 * SK };
      const schutz = ctx.schutz.concat(extraSchutz());
      const kosten = r => { const a = r.w * r.h, x0 = Math.max(0, r.x), y0 = Math.max(0, r.y), x1 = Math.min(W, r.x + r.w), y1 = Math.min(H, r.y + r.h);
        const drin = Math.max(0, x1 - x0) * Math.max(0, y1 - y0); return Math.min(1, ueberdeckt(r, schutz) / a) + (1 - drin / a); };
      let heim = { x: m.x - 150, y: m.y + 50 }, bk = Infinity;
      [165, 150, 180, 135, 195, 120].forEach(w => [mr + 70, mr + 100, mr + 135, mr + 175].forEach(d => {
        const p = { x: klemme(m.x + Math.cos(w * RAD) * d, he.w / 2 + 8, W - he.w / 2 - 8), y: Math.max(m.y + Math.sin(w * RAD) * d, he.h / 2 + 8) };
        let k = kosten(kasten(p.x, p.y, he.w, he.h)) * 4 + d / 500 + Math.abs(w - 160) / 400 + z() * 0.02;
        if (Math.hypot(p.x - m.x, p.y - m.y) < mr + 40) k += 3;
        if (k < bk) { bk = k; heim = p; }
      }));
      const von = { x: Math.min(W + 50, heim.x + 260), y: -70 }, ctrl = { x: heim.x + 130, y: heim.y - 10 }, nach = { x: heim.x - 280, y: heim.y - 260 };
      const ph = [z() * TAU, z() * TAU, z() * TAU, z() * TAU], tWink = zz(z, IN + 1.0, Math.max(IN + 1.1, dauer - OUT - 2.0)), dreh0 = zz(z, -11, 11);
      const root = wesen(astronautSvg());
      const q = s => root.querySelector(s);
      const E = { bl: q('.bl'), br: q('.br'), ar: q('.ar'), la: q('.la') };
      const inst = { el: root, dauer, cur: 0, tapT: null, leaveT: null };
      const lage = t => {
        const D = inst.dauer, tOut = D - OUT;
        const drift = { x: 14 * Math.sin(TAU * t / 5.3 + ph[0]), y: 9 * Math.sin(TAU * t / 3.9 + ph[1]) };
        const basis = dreh0 + 17 * Math.sin(TAU * t / 6.5 + ph[2]);
        let x, y, rot;
        if (t < IN) { const u = raus(t / IN), p = bez2(von, ctrl, heim, u); x = p.x + drift.x * u; y = p.y + drift.y * u; rot = basis + (1 - u) * 63; }
        else if (t < tOut) { x = heim.x + drift.x; y = heim.y + drift.y; rot = basis; }
        else { const u = rein(klemme((t - tOut) / OUT, 0, 1)); x = lerp(heim.x, nach.x, u) + drift.x; y = lerp(heim.y, nach.y, u) + drift.y; rot = basis - 52 * u; }
        let wink = ein(t, tWink, 0.3) * ausAb(t, tWink + 1.5, 0.3), op = ein(t, 0, 0.4) * klemme((D - t) / 0.5, 0, 1);
        if (inst.tapT !== null && t >= inst.tapT) {
          const u = klemme((t - inst.tapT) / SALTO, 0, 1);
          rot -= 360 * glatt(u); y -= 12 * Math.sin(Math.PI * u);
          wink = Math.max(wink, Math.sin(Math.PI * klemme((t - inst.tapT) / (SALTO + 0.5), 0, 1)));
        }
        if (inst.leaveT !== null) op *= klemme(1 - (t - inst.leaveT) / 0.38, 0, 1);
        return { x, y, rot, wink, op };
      };
      inst.stelle = t => {
        inst.cur = t;
        const L = lage(t);
        S(root, L.x, L.y, L.rot, SK, L.op);
        const kick = Math.sin(t * 1.7 + ph[3]);
        T(E.bl, 'rotate(' + n1(-10 * kick) + ' -4.5 10)');
        T(E.br, 'rotate(' + n1(10 * kick) + ' 4.5 10)');
        T(E.ar, 'translate(9 -1) rotate(' + n1(lerp(55, -48 + 24 * Math.sin(t * TAU * 2.2), L.wink)) + ')');
        O(E.la, 0.35 + 0.65 * Math.max(0, Math.sin(t * TAU * 0.7)));
      };
      inst.hulle = t => { const L = lage(t); return L.op < 0.03 ? null : kasten(L.x, L.y - 2 * SK, he.w, he.h); };
      inst.tipp = () => {
        inst.tapT = inst.cur;
        const tOut = inst.dauer - OUT;
        if (inst.cur < tOut && inst.cur + SALTO + 0.3 > tOut) inst.dauer = inst.cur + SALTO + 0.3 + OUT;
      };
      inst.abgang = () => { inst.leaveT = inst.cur; return 0.4; };
      return inst;
    },
  });
})(window.MMF = window.MMF || {});
