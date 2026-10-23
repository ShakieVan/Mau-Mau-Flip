/* Mau-Mau Flip (Beta 1.6.12): „Natur-Überraschungen“ im Browser-Client „Lite“ – die Tagseite (docs/module/natur.md, Aufgabe T5).
 * Elf Tagereignisse und der Schmetterling aus dem Bestand: Marienkäfer, Biene, Libelle, Pusteblume, Papierflieger, Seifenblasen, Spatz,
 * Wolke vor der Sonne, Regenbogen nach Flip, Heißluftballon, Schnecke bei Trödlern, Schmetterling; ab 1.6.15 dazu Hoppelhase und Strand
 * mit Palme (Ecke unten rechts, hinter Hand und Mau-Knopf).
 * Jede Art meldet sich mit M.Natur.art(id, {baue(ctx, zufall)}) beim Kern (natur.js) an; Vertrag und ctx stehen im Dateikopf von natur.js.
 *
 * Stil „Papier & Neon“ (Tag): ausgeschnittenes Papier mit Druckfarben-Kontur (INK), kräftige Flächen, kleiner Glanz, ein weicher
 * Papierschatten unter Tieren auf dem Tisch. Alles ist hier selbst gezeichnet (Inline-SVG und CSS), keine Bilddateien, kein Ton.
 *
 * Regeln für alle Arten:
 *  - Die Pose hängt nur von t ab (stelle(t) ist rein): Zufall nur in baue(), Reaktionen (Antippen, Abgang) laufen als eigene Zeitlinie
 *    ab der gemerkten Zeit. So zeigen Tests und Kontrollbilder bei gleichem Samen und gleichem t dasselbe Bild.
 *  - Gesetzt werden transform und opacity, dazu einzelne Klassen bei Zustandswechseln (Flügelschlag an/aus); Ausnahme laut Entwurf: der
 *    Regenbogen wächst über stroke-dashoffset. Innere Schleifen (Flügelschlag, Flimmern) sind CSS-Keyframes mit der Klasse nt-schleife,
 *    die unter body.reduziert stillstehen.
 *  - Größen in Bühnen-px (Höhe 720). Kleine Tiere sind etwa 1,5-mal so groß wie im Entwurf, damit sie am Handy erkennbar bleiben.
 *  - Ein schneller Abgang dauert höchstens 0,45 s.
 *  - Die Reaktionsleiste (#nk-leiste, 5 Knöpfe) ist keine Schutzfläche des Kerns; Tiere auf dem Band meiden sie hier selbst.
 */
(function (M) {
  'use strict';
  const N = M.Natur;
  if (!N || !N.art) return;
  const { el, klemme, lerp, glatt } = N.h;

  const INK = '#211B2C', PAPER_D = '#E6D7BC', CREAM = '#FFF7E8';
  // Maßstab der Tiere (Zeichnungen in Entwurfsgröße; am Handy sonst zu klein)
  const MK_GR = 1.3, BI_GR = 1.45, SP_GR = 1.2, PF_GR = 1.15, LI_GR = 1.25, SN_GR = 1.3, HB_GR = 1.3, PB_GR = 1.15;
  const RAD = Math.PI / 180;
  const ein = u => { u = klemme(u, 0, 1); return u * u; };
  const aus = u => { u = klemme(u, 0, 1); return 1 - (1 - u) * (1 - u); };
  const rnd = (z, a, b) => a + z() * (b - a);
  const kasten = (x, y, w, h) => ({ x: x - w / 2, y: y - h / 2, w, h });
  const grad = (dx, dy) => Math.atan2(dy, dx) / RAD;
  const flaeche = (a, b) => Math.max(0, Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)) * Math.max(0, Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y));
  function bez2(a, c, b, u) { const v = 1 - u; return { x: v * v * a.x + 2 * v * u * c.x + u * u * b.x, y: v * v * a.y + 2 * v * u * c.y + u * u * b.y }; }

  // transform/opacity nur schreiben, wenn sich etwas ändert
  function tf(e, s) { if (e._tf !== s) { e.style.transform = s; e._tf = s; } }
  function deck(e, v) { v = Math.round(klemme(v, 0, 1) * 1000) / 1000; if (e._op !== v) { e.style.opacity = String(v); e._op = v; } }
  function klasse(e, k, an) { an = !!an; const m = '_k_' + k; if (e[m] !== an) { e.classList.toggle(k, an); e[m] = an; } }
  // Element an Bühnenposition (x, y) = sein Ursprung; Drehung in Grad, Maßstab sx/sy, Deckkraft
  function setz(e, x, y, rot, sx, sy, o) {
    let s = 'translate(' + (+x || 0).toFixed(1) + 'px,' + (+y || 0).toFixed(1) + 'px)';
    if (rot) s += ' rotate(' + rot.toFixed(2) + 'deg)';
    if (sx === undefined) sx = 1;
    if (sy === undefined) sy = sx;
    if (sx !== 1 || sy !== 1) s += ' scale(' + sx.toFixed(3) + ',' + sy.toFixed(3) + ')';
    tf(e, s);
    if (o !== undefined) deck(e, o);
  }
  // Teil im SVG (Ursprung über transform-origin in SVG-Koordinaten, siehe CSS)
  function dreh(e, a, dx, dy, sx, sy) {
    let s = '';
    if (dx || dy) s += 'translate(' + (dx || 0).toFixed(2) + 'px,' + (dy || 0).toFixed(2) + 'px) ';
    s += 'rotate(' + (a || 0).toFixed(2) + 'deg)';
    if (sx !== undefined && (sx !== 1 || (sy !== undefined && sy !== 1))) s += ' scale(' + sx.toFixed(3) + ',' + (sy === undefined ? sx : sy).toFixed(3) + ')';
    tf(e, s);
  }
  // SVG mit lokalem Ursprung (0, 0) am Elementursprung: Kasten x0, y0, w, h in lokalen Koordinaten
  function svg(cls, x0, y0, w, h, inner) {
    return '<svg class="nt-svg ' + cls + '" xmlns="http://www.w3.org/2000/svg" width="' + w + '" height="' + h + '" viewBox="' + x0 + ' ' + y0 + ' ' + w + ' ' + h
      + '" style="left:' + x0 + 'px;top:' + y0 + 'px;transform-origin:' + (-x0) + 'px ' + (-y0) + 'px">' + inner + '</svg>';
  }
  const q = (root, s) => root.querySelector(s);
  const qa = (root, s) => Array.from(root.querySelectorAll(s));

  // Reaktionsleiste (#nk-leiste) in Bühnen-px oder null
  function leiste() {
    const e = document.getElementById('nk-leiste'), t = M.App && M.App.tisch;
    if (!e || e.hidden || !t || !t.zuBuehne) return null;
    const r = e.getBoundingClientRect();
    if (!(r.width > 0 && r.height > 0)) return null;
    const a = t.zuBuehne(r.left, r.top), b = t.zuBuehne(r.right, r.bottom);
    return { x: a.x, y: a.y, w: b.x - a.x, h: b.y - a.y };
  }
  const schutz = (ctx, name) => (ctx.schutz || []).filter(r => r.name === name);
  const randAbstand = (p, r) => Math.hypot(Math.max(r.x - p.x, 0, p.x - (r.x + r.w)), Math.max(r.y - p.y, 0, p.y - (r.y + r.h)));
  // Stelle auf dem Band: Spiegeln (180° − g), wenn sie zu nah an der Reaktionsleiste oder unter einer Schutzfläche liegt
  function freiesBand(ctx, g, quer) {
    const lr = leiste();
    const schlecht = w => {
      const p = ctx.band(w, quer);
      let k = lr ? Math.max(0, 70 - randAbstand(p, lr)) : 0;
      (ctx.schutz || []).forEach(r => { if (r.name !== 'hand') k += Math.max(0, 30 - randAbstand(p, r)); });
      return k;
    };
    const g2 = (540 - g) % 360;
    return schlecht(g2) + 1 < schlecht(g) ? g2 : g;
  }
  // Weg auf dem Band von g0 nach g1 (Grad) mit Bogenlängen-Tabelle: an(s) → {x, y, dir (Laufrichtung in Grad)}
  function bandWeg(ctx, g0, g1, quer) {
    const n = Math.max(2, Math.ceil(Math.abs(g1 - g0) / 0.5)), P = [];
    let L = 0;
    for (let i = 0; i <= n; i++) {
      const p = ctx.band(g0 + (g1 - g0) * i / n, quer);
      if (i) L += Math.hypot(p.x - P[i - 1].x, p.y - P[i - 1].y);
      P.push({ x: p.x, y: p.y, s: L });
    }
    return {
      L,
      an(s) {
        s = klemme(s, 0, L);
        let i = 1;
        while (i < n && P[i].s < s) i++;
        const a = P[i - 1], b = P[i], u = b.s > a.s ? (s - a.s) / (b.s - a.s) : 0;
        return { x: lerp(a.x, b.x, u), y: lerp(a.y, b.y, u), dir: grad(b.x - a.x, b.y - a.y) };
      },
    };
  }
  const winkelMisch = (a, b, u) => { let d = ((b - a + 540) % 360) - 180; return a + d * u; };

  /* ---------- Stile ---------- */
  N.stil('tag', [
    '.nt-svg{position:absolute;overflow:visible;display:block}',
    '.nt-wesen i{position:absolute;display:block;left:0;top:0}',
    // Marienkäfer
    '.nt-mk-flap{transform-origin:0px -6px;animation:nt-flap .055s linear infinite alternate}',
    '.nt-mk-bl,.nt-mk-br{transform-origin:0px 2px}',
    '.nt-mk.geht .nt-mk-bl{animation:nt-trippel .14s linear infinite alternate}',
    '.nt-mk.geht .nt-mk-br{animation:nt-trippel .14s linear -.07s infinite alternate}',
    '.nt-mk-l{transform-origin:-1px -8px}.nt-mk-r{transform-origin:1px -8px}',
    '@keyframes nt-flap{from{transform:scaleY(1)}to{transform:scaleY(.3)}}',
    '@keyframes nt-trippel{from{transform:rotate(-9deg)}to{transform:rotate(9deg)}}',
    // Biene
    '.nt-bi-flap{transform-origin:0px -4px;animation:nt-flap .045s linear infinite alternate}',
    '.nt-bi.sitzt .nt-bi-flap{animation:nt-zitter .09s linear infinite alternate}',
    '.nt-bi-hl{transform-origin:-2px 0px}',
    '@keyframes nt-zitter{from{transform:rotate(-5deg) scaleY(1)}to{transform:rotate(4deg) scaleY(.88)}}',
    // Libelle
    '.nt-li-sch{animation:nt-schimmer .16s linear infinite alternate}',
    '.nt-li-fl{animation:nt-flimmer .04s linear infinite alternate}',
    '@keyframes nt-schimmer{from{opacity:.15}to{opacity:.95}}',
    '@keyframes nt-flimmer{from{opacity:1}to{opacity:.55}}',
    // Spatz
    '.nt-sp-flap{transform-origin:2px -18px}',
    '.nt-sp.fliegt .nt-sp-flap{animation:nt-spflap .083s linear infinite alternate}',
    '.nt-sp-kopf{transform-origin:7px -19px}',
    '@keyframes nt-spflap{from{transform:rotate(18deg)}to{transform:rotate(-62deg)}}',
    // Seifenblasen
    '.nt-bl{border-radius:50%;background:radial-gradient(circle at 50% 50%,rgba(255,255,255,0) 52%,rgba(120,232,255,.16) 66%,rgba(255,150,225,.26) 80%,rgba(255,255,255,.55) 92%,rgba(33,27,44,.4) 98.5%,rgba(33,27,44,0) 100%);'
      + 'box-shadow:inset 3px -3px 5px rgba(255,79,200,.42),inset -3px 3px 6px rgba(25,198,212,.5),inset 0 -4px 6px rgba(255,214,90,.35)}',
    '.nt-bl::after{content:"";position:absolute;left:20%;top:15%;width:28%;height:17%;border-radius:50%;background:rgba(255,255,255,.95);transform:rotate(-38deg)}',
    '.nt-bl::before{content:"";position:absolute;right:22%;bottom:18%;width:10%;height:10%;border-radius:50%;background:rgba(255,255,255,.8)}',
    '.nt-blr{border-radius:50%;border:2px solid rgba(25,198,212,.85);box-shadow:0 0 0 1.5px rgba(255,79,200,.55)}',
    '.nt-bltr{width:6px;height:6px;margin:-3px 0 0 -3px;border-radius:50%;background:#7FE8F2;border:1px solid rgba(33,27,44,.35)}',
    '.nt-bltr:nth-child(even){background:#FF9AD8}',
    // Wolke
    '.nt-wo-sch{left:0;top:0;width:100%;height:100%;background:#211B2C}',
    // Pusteblume (Samen sind <use>)
    '.nt-pb-defs{position:absolute;width:0;height:0;overflow:hidden}',
  ].join('\n'));

  /* ======================================================================== 1 Marienkäfer */
  // Draufsicht, Kopf zeigt nach oben (−y). Deckflügel klappen um ihre Vorderecke auf, darunter die Hautflügel.
  const MK_BEINE = s => '<g class="nt-mk-b' + (s < 0 ? 'l' : 'r') + '"><path d="M' + 9 * s + ' -4 L' + 15 * s + ' -7 L' + 17 * s + ' -11 M' + 10 * s + ' 2 L' + 16 * s + ' 2 L' + 18.5 * s + ' 0 M' + 9 * s + ' 8 L' + 14 * s + ' 12 L' + 15 * s + ' 16" fill="none" stroke="' + INK + '" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></g>';
  const MK_DECK = s => '<g class="nt-mk-' + (s < 0 ? 'l' : 'r') + '">'
    + '<path d="M0 -9 C' + 9 * s + ' -9.5 ' + 15 * s + ' -4 ' + 15 * s + ' 3 C' + 15 * s + ' 10 ' + 8 * s + ' 15 0 15 Z" fill="#E8352E" stroke="' + INK + '" stroke-width="1.7" stroke-linejoin="round"/>'
    + '<circle cx="' + 7.5 * s + '" cy="-2.5" r="2.7" fill="' + INK + '"/><circle cx="' + 10.5 * s + '" cy="6" r="2.4" fill="' + INK + '"/><circle cx="' + 4.2 * s + '" cy="9.6" r="2.3" fill="' + INK + '"/>'
    + '<ellipse cx="' + 8 * s + '" cy="-5.4" rx="3.6" ry="1.5" transform="rotate(' + (32 * s) + ' ' + 8 * s + ' -5.4)" fill="#fff" fill-opacity=".6"/></g>';
  const MK_KOERPER = '<path d="M-2.5 -16 Q-4.5 -20 -7 -21.5 M2.5 -16 Q4.5 -20 7 -21.5" fill="none" stroke="' + INK + '" stroke-width="1.3" stroke-linecap="round"/>'
    + '<circle cx="-7" cy="-21.5" r="1.3" fill="' + INK + '"/><circle cx="7" cy="-21.5" r="1.3" fill="' + INK + '"/>'
    + MK_BEINE(-1) + MK_BEINE(1)
    + '<ellipse cx="0" cy="-14" rx="5.6" ry="4" fill="' + INK + '"/><circle cx="-2.4" cy="-15" r="1.1" fill="#fff"/><circle cx="2.4" cy="-15" r="1.1" fill="#fff"/>'
    + '<g class="nt-mk-haut"><g class="nt-mk-flap nt-schleife">'
    + '<ellipse cx="-11" cy="6" rx="7" ry="15.5" transform="rotate(28 -11 6)" fill="#EAF6FF" fill-opacity=".8" stroke="' + INK + '" stroke-opacity=".65" stroke-width="1.1"/>'
    + '<ellipse cx="11" cy="6" rx="7" ry="15.5" transform="rotate(-28 11 6)" fill="#EAF6FF" fill-opacity=".8" stroke="' + INK + '" stroke-opacity=".65" stroke-width="1.1"/></g></g>'
    + '<ellipse cx="0" cy="-9" rx="8.6" ry="4.8" fill="' + INK + '"/><ellipse cx="-4.4" cy="-9.6" rx="2.1" ry="1.6" fill="#fff"/><ellipse cx="4.4" cy="-9.6" rx="2.1" ry="1.6" fill="#fff"/>'
    + MK_DECK(1) + MK_DECK(-1);

  N.art('marienkaefer', {
    baue(ctx, z) {
      const e = ctx.eintrag;
      const D = rnd(z, e.dauer[0], e.dauer[1]);
      let g = ctx.ort && typeof ctx.ort.grad === 'number' ? ctx.ort.grad : 140;
      g = freiesBand(ctx, g, 0.5);
      // krabbelt zur vorderen Bandmitte, bleibt aber außerhalb 66–114° (unter der Hinweisleiste)
      const ziel = g > 90 && g < 270 ? Math.max(118, g - 30) : Math.min(62, g + 30);
      const weg = bandWeg(ctx, g, ziel, 0.5);
      const P = weg.an(0);
      const sgn = P.x < ctx.cx ? -1 : 1;
      const S = { x: P.x + sgn * 140, y: -50 }, C = { x: P.x + sgn * 170, y: P.y - 170 };
      const T_AN = 1.2, T_SETZ = 0.25, T_AB = 1.0;
      // Krabbeln: laufen (1,5–2,5 s) und anhalten (0,4–0,8 s, leicht drehen)
      const abschn = [];
      let t = T_AN + T_SETZ, s = 0;
      const V = 13;
      while (t < D - T_AB - 1e-6) {
        const lauf = Math.min(rnd(z, 1.5, 2.5), D - T_AB - t);
        abschn.push({ t0: t, t1: t + lauf, s0: s, v: V, dreh: 0 });
        s += lauf * V; t += lauf;
        if (t >= D - T_AB - 1e-6) break;
        const halt = Math.min(rnd(z, 0.4, 0.8), D - T_AB - t);
        abschn.push({ t0: t, t1: t + halt, s0: s, v: 0, dreh: rnd(z, -15, 15) });
        t += halt;
      }
      const root = el('div', 'nt-mk', svg('nt-mk-sch', -22, -14, 44, 28, '<ellipse cx="0" cy="0" rx="16" ry="10" fill="' + INK + '" fill-opacity=".2"/>')
        + svg('nt-mk-k', -30, -30, 60, 60, MK_KOERPER));
      const sch = q(root, '.nt-mk-sch'), k = q(root, '.nt-mk-k'), haut = q(root, '.nt-mk-haut'), dl = q(root, '.nt-mk-l'), dr = q(root, '.nt-mk-r');
      const krabbel = tt => {
        let s = 0, dreh = 0, geht = false;
        for (const a of abschn) {
          if (tt < a.t0) break;
          const u = klemme((tt - a.t0) / (a.t1 - a.t0), 0, 1);
          s = a.s0 + a.v * (Math.min(tt, a.t1) - a.t0);
          if (tt <= a.t1) { geht = a.v > 0; dreh = a.dreh * Math.sin(Math.PI * u); }
        }
        const p = weg.an(s);
        return { x: p.x, y: p.y, rot: p.dir + 90 + dreh, geht, s };
      };
      // Grundpose ohne Reaktionen
      const grund = tt => {
        if (tt < T_AN) {
          const u = aus(tt / T_AN), p = bez2(S, C, P, u), p2 = bez2(S, C, P, Math.min(1, u + 0.02));
          return { x: p.x, y: p.y, rot: grad(p2.x - p.x, p2.y - p.y) + 90, auf: 1, flug: 1, hoch: 1 - u, op: 1, geht: false };
        }
        const kb = krabbel(Math.min(tt, D - T_AB));
        if (tt < T_AN + T_SETZ) {
          const u = (tt - T_AN) / T_SETZ, p2 = bez2(S, C, P, 0.98);
          return { x: P.x, y: P.y, rot: winkelMisch(grad(P.x - p2.x, P.y - p2.y) + 90, kb.rot, glatt(u)), auf: 1 - glatt(u), flug: 1 - u, hoch: 0, op: 1, geht: false };
        }
        if (tt < D - T_AB) return { x: kb.x, y: kb.y, rot: kb.rot, auf: 0, flug: 0, hoch: 0, op: 1, geht: kb.geht };
        const u = (tt - (D - T_AB)) / T_AB;
        return abflug(kb, u, 1, 1);
      };
      // Abflug ab Pose b, Anteil u; weit = Weglänge, steil: wie steil
      const abflug = (b, u, weit, schnell) => {
        const A = { x: b.x, y: b.y }, Cc = { x: b.x + sgn * 25 * weit, y: b.y - 90 * weit }, E = { x: b.x + sgn * 150 * weit, y: b.y - 400 * weit };
        const v = ein(Math.max(0, u - 0.12 / schnell) / (1 - 0.12 / schnell));
        const p = bez2(A, Cc, E, v), p2 = bez2(A, Cc, E, Math.min(1, v + 0.03));
        const auf = klemme(u * schnell / 0.12, 0, 1);
        return { x: p.x, y: p.y, rot: winkelMisch(b.rot, grad(p2.x - p.x, p2.y - p.y) + 90, glatt(u * 3)), auf, flug: auf, hoch: v, op: 1 - klemme((u - 0.7) / 0.3, 0, 1), geht: false };
      };
      const inst = {
        el: root, dauer: D, t: 0, weg: null,
        pose(tt) {
          const w = this.weg;
          if (w && tt >= w.at) {
            const b = grund(w.at);
            return w.art === 'tipp' ? abflug(b, (tt - w.at) / 0.8, 1, 1) : abflug(b, (tt - w.at) / 0.4, 0.5, 2);
          }
          return grund(tt);
        },
        stelle(tt) {
          this.t = tt;
          const p = this.pose(tt), sc = MK_GR * (1 + 0.3 * p.hoch);
          setz(k, p.x, p.y, p.rot, sc, sc, p.op);
          setz(sch, p.x + 2 + 26 * p.hoch, p.y + 4 + 60 * p.hoch, 0, 1 - 0.4 * p.hoch, 1 - 0.4 * p.hoch, p.op * (1 - 0.8 * p.hoch));
          deck(haut, p.flug);
          dreh(dl, 55 * p.auf, -3 * p.auf, 0);
          dreh(dr, -55 * p.auf, 3 * p.auf, 0);
          klasse(root, 'geht', p.geht);
        },
        hulle(tt) {
          const p = this.pose(tt);
          if (p.op < 0.03) return null;
          const g2 = 40 * MK_GR * (1 + 0.3 * p.hoch);
          return kasten(p.x, p.y, g2, g2);
        },
        tipp() { if (!this.weg) { this.weg = { at: this.t, art: 'tipp' }; this.dauer = this.t + 0.82; } },
        abgang() { if (!this.weg) this.weg = { at: this.t, art: 'abgang' }; return 0.4; },
      };
      return inst;
    },
  });

  /* ======================================================================== 2 Biene */
  // Seitenansicht, Blick nach rechts (+x). Flügel schlagen per CSS; sitzend zittern sie.
  const BI_SVG = '<g class="nt-bi-hl"><path d="M-11 -1.6 L-17 0 L-11 1.6 Z" fill="' + INK + '"/>'
    + '<ellipse cx="-1" cy="0" rx="11" ry="7.6" fill="#FFC934" stroke="' + INK + '" stroke-width="1.7"/>'
    + '<path d="M-7.6 -5.4 Q-9 0 -7.6 5.4 L-5 6.8 Q-6.6 0 -5 -6.8 Z M-2.2 -7.4 Q-3.8 0 -2.2 7.4 L0.8 7.5 Q-0.8 0 0.8 -7.5 Z M3.8 -6.9 Q2.4 0 3.8 6.9 L6.4 5.6 Q5 0 6.4 -5.6 Z" fill="' + INK + '"/>'
    + '<ellipse cx="-4" cy="-3.6" rx="3.4" ry="1.3" fill="#fff" fill-opacity=".55" transform="rotate(-12 -4 -3.6)"/></g>'
    + '<circle cx="12" cy="-1" r="5.2" fill="' + INK + '"/><circle cx="13.9" cy="-2.4" r="1.25" fill="#fff"/>'
    + '<path d="M12.5 -5.6 Q13.6 -10.5 17.5 -11.5 M10.5 -5.6 Q9.8 -10.5 12.4 -12.6" fill="none" stroke="' + INK + '" stroke-width="1.2" stroke-linecap="round"/>'
    + '<path d="M-3 6 L-4 10 M2 6.5 L2 10.5 M6 5.5 L7 9.5" stroke="' + INK + '" stroke-width="1.2" stroke-linecap="round"/>'
    + '<g class="nt-bi-flap nt-schleife">'
    + '<ellipse cx="-4" cy="-11" rx="6.2" ry="10" transform="rotate(-24 -4 -11)" fill="#fff" fill-opacity=".72" stroke="' + INK + '" stroke-opacity=".55" stroke-width="1.1"/>'
    + '<ellipse cx="3" cy="-10" rx="5" ry="8.4" transform="rotate(16 3 -10)" fill="#fff" fill-opacity=".72" stroke="' + INK + '" stroke-opacity=".55" stroke-width="1.1"/></g>';

  N.art('biene', {
    baue(ctx, z) {
      const W = ctx.W, H = ctx.H;
      const r1 = rs => rs.reduce((m, r) => Math.max(m, r.y + r.h), -1e9);
      const handR = schutz(ctx, 'hand')[0] || null;
      const lr = (schutz(ctx, 'leiste')[0]) || null, mau = schutz(ctx, 'mau')[0] || null;
      // Acht im freien Streifen zwischen Stapel/Ablage und Hand, rechts der Hinweisleiste und links von „Mau!“
      const oben = Math.max(r1(schutz(ctx, 'stapel').concat(schutz(ctx, 'ablage'), schutz(ctx, 'automat'), schutz(ctx, 'einsatz'))), H * 0.5) + 16;
      const unten = (handR ? handR.y : H - 150) - 16;
      const x0 = (lr ? lr.x + lr.w : ctx.cx) + 30, x1 = (mau ? mau.x : W) - 30;
      const A = Math.min(200, (x1 - x0) / 2 - 18), hh = Math.min(30, (unten - oben) / 2 - 15);
      const acht = A >= 60 && hh >= 8 ? { cx: (x0 + x1) / 2, cy: (oben + unten) / 2, A, hh } : null;
      const runden = acht ? (z() < 0.5 ? 1 : 2) : 0;
      // Landeplatz: rechte obere Ecke der rechten sichtbaren Handkarte (die linke obere Ecke jeder Karte trägt den Eckindex, AGENTS 8)
      let L = null;
      const t = M.App && M.App.tisch;
      if (t && t.hand && t.hand.reihe && t.hand.reihe.length) {
        const KH = 870 / 560;
        let best = null;
        t.hand.reihe.forEach(kk => {
          const p = t.hand.position(kk.id);
          if (!p || !(p.x > 0 && p.x < W)) return;
          const kh = p.w * KH, a = (p.rot || 0) * RAD, lx = p.w / 2 - 30, ly = -kh / 2 + 26;
          const pt = { x: p.x + lx * Math.cos(a) - ly * Math.sin(a), y: p.y + lx * Math.sin(a) + ly * Math.cos(a), rot: p.rot || 0, kx: p.x };
          if (pt.y > H - 24 || pt.x > W - 24) return;
          if (!best || p.x > best.kx) best = pt;
        });
        if (best && !(mau && randAbstand(best, mau) < 24)) L = best;
      }
      const E0 = { x: W + 50, y: acht ? acht.cy - 50 : (L ? L.y - 200 : H * 0.6) };
      const M0 = acht ? { x: acht.cx, y: acht.cy } : (L ? { x: L.x + 40, y: L.y - 110 } : { x: W * 0.6, y: H * 0.62 });
      const T_EIN = 1.2, T_RUNDE = 2.2, T_AB = L ? 0.7 : 0, T_SITZ = 1.3, T_AUF = 1.0;
      const tA = T_EIN, tB = tA + runden * T_RUNDE, tC = tB + T_AB, tD = tC + (L ? T_SITZ : 0), D = tD + T_AUF;
      const root = el('div', 'nt-bi', svg('nt-bi-strich', -44, -3, 40, 6, '<path d="M-42 0 L-14 0" stroke="' + INK + '" stroke-opacity=".3" stroke-width="1.2" stroke-linecap="round" stroke-dasharray="5 4"/>')
        + svg('nt-bi-k', -22, -26, 46, 42, BI_SVG));
      const k = q(root, '.nt-bi-k'), hl = q(root, '.nt-bi-hl'), strich = q(root, '.nt-bi-strich');
      const achtPunkt = ph => ({ x: acht.cx - acht.A * Math.sin(ph), y: acht.cy + acht.hh * Math.sin(2 * ph) });
      const ort = tt => {
        if (tt < tA) return bez2(E0, { x: M0.x + (acht ? acht.A + 80 : 120), y: M0.y - 70 }, M0, aus(tt / T_EIN));
        if (tt < tB) return achtPunkt((tt - tA) / T_RUNDE * Math.PI * 2);
        if (L && tt < tC) return bez2(M0, { x: L.x, y: M0.y }, L, glatt((tt - tB) / T_AB));
        if (L && tt < tD) return { x: L.x, y: L.y + 0.6 * Math.sin((tt - tC) * 11), sitzt: true };
        const A0 = L || M0;
        return bez2(A0, { x: A0.x + 20, y: A0.y - 150 }, { x: A0.x + 180, y: -50 }, aus((tt - tD) / T_AUF));
      };
      const grund = tt => {
        const p = ort(tt), p2 = ort(tt + 0.03), sitzt = !!p.sitzt;
        const vx = (p2.x - p.x) / 0.03, vy = (p2.y - p.y) / 0.03, tempo = Math.hypot(vx, vy);
        // Blickrichtung folgt der Bewegung, bei fast senkrechtem Flug bleibt die letzte (rein in t: aus der Nachbarzeit)
        let face = vx < -20 ? -1 : (vx > 20 ? 1 : 0);
        if (!face) { const p0 = ort(Math.max(0, tt - 0.12)); face = p.x - p0.x < 0 ? -1 : 1; }
        if (sitzt) face = 1;
        return { x: p.x, y: p.y, face, kipp: sitzt ? 0 : klemme(grad(Math.abs(vx), vy), -25, 25), op: 1, sitzt, tempo, v: grad(vx, vy), rot: sitzt ? L.rot : 0 };
      };
      const inst = {
        el: root, ebene: 'vorn', dauer: D, t: 0, weg: null,
        pose(tt) {
          const w = this.weg;
          if (w && tt >= w.at) {
            // scheu: 0,4 s Zickzack nach oben
            const b = grund(w.at), u = klemme((tt - w.at) / 0.4, 0, 1);
            const x = b.x + 34 * Math.sin(u * Math.PI * 3) * (1 - u * 0.3), y = b.y - 300 * ein(u) - 60 * u;
            return { x, y, face: Math.cos(u * Math.PI * 3) >= 0 ? 1 : -1, kipp: -20, op: 1 - klemme((u - 0.55) / 0.45, 0, 1), sitzt: false, tempo: 400, v: -90, rot: 0 };
          }
          return grund(tt);
        },
        stelle(tt) {
          this.t = tt;
          const p = this.pose(tt);
          setz(k, p.x, p.y, (p.rot || 0) + p.kipp * p.face, p.face * BI_GR, BI_GR, p.op);
          klasse(root, 'sitzt', p.sitzt);
          dreh(hl, p.sitzt ? 6 * Math.sin(tt * 9) : 0);
          const fl = klemme((p.tempo - 120) / 200, 0, 1);
          setz(strich, p.x, p.y, p.v, 1, 1, p.op * fl);
        },
        hulle(tt) {
          const p = this.pose(tt);
          return p.op < 0.03 ? null : kasten(p.x, p.y + 1, 34 * BI_GR, 30 * BI_GR);
        },
        scheu() { if (!this.weg) this.weg = { at: this.t }; },
        abgang() { if (!this.weg) this.weg = { at: this.t }; return 0.4; },
      };
      return inst;
    },
  });

  /* ======================================================================== 3 Libelle */
  // Draufsicht, Kopf nach rechts (+x); Sprint – Schweben – Sprint quer über den Streifen hinter dem Band.
  function libelleSvg() {
    let s = '';
    const fl = (cx, cy, rot, f, rx, ry) => '<ellipse cx="' + cx + '" cy="' + cy + '" rx="' + rx + '" ry="' + ry + '" transform="rotate(' + rot + ' ' + cx + ' ' + cy + ')" fill="' + f + '"';
    // Vorderflügel leicht nach vorn, Hinterflügel leicht nach hinten gestellt
    const fluegel = [[16, -17, 13], [16, 17, -13], [3, -16, -17], [3, 16, 17]];
    s += '<g class="nt-li-fl nt-schleife">';
    fluegel.forEach(([x, y, r]) => { s += fl(x, y, r, '#fff', 4.2, 17) + ' fill-opacity=".68" stroke="' + INK + '" stroke-opacity=".5" stroke-width=".9"/>'; });
    s += '</g><g class="nt-li-sch nt-schleife">';
    fluegel.forEach(([x, y, r], i) => { s += fl(x, y + (y < 0 ? 4 : -4), r, i % 2 ? '#8B6BFF' : '#19C6D4', 2.8, 11) + ' fill-opacity=".35"/>'; });
    s += '</g>';
    // Hinterleib: 8 Glieder, 4 → 2 px, dunkle Ringe
    let x = 6;
    for (let i = 0; i < 8; i++) {
      const w = 4.6 - i * 0.35, l = 5.4;
      s += '<line x1="' + x + '" y1="0" x2="' + (x - l) + '" y2="0" stroke="' + INK + '" stroke-width="' + (w + 2) + '" stroke-linecap="round"/>';
      s += '<line x1="' + x + '" y1="0" x2="' + (x - l) + '" y2="0" stroke="' + (i % 2 ? '#14B3C2' : '#2FD8E6') + '" stroke-width="' + w + '" stroke-linecap="round"/>';
      x -= l;
    }
    s += '<path d="M-37 -2 L-41 -3.4 M-37 2 L-41 3.4" stroke="' + INK + '" stroke-width="1.2" stroke-linecap="round"/>';
    s += '<ellipse cx="11" cy="0" rx="7.4" ry="4.8" fill="#0FA3B1" stroke="' + INK + '" stroke-width="1.4"/>';
    s += '<path d="M7 -1.5 L15 -1.5" stroke="#9AF3F8" stroke-width="1.2" stroke-linecap="round"/>';
    s += '<circle cx="21" cy="-3.3" r="3.6" fill="#1FD1E0" stroke="' + INK + '" stroke-width="1.3"/><circle cx="21" cy="3.3" r="3.6" fill="#1FD1E0" stroke="' + INK + '" stroke-width="1.3"/>';
    s += '<circle cx="22" cy="-4.4" r="1.1" fill="#fff"/><circle cx="22" cy="2.2" r="1.1" fill="#fff"/>';
    return s;
  }
  N.art('libelle', {
    baue(ctx, z) {
      const e = ctx.eintrag, W = ctx.W;
      const D = rnd(z, e.dauer[0], e.dauer[1]);
      const o = ctx.ort && typeof ctx.ort.y0 === 'number' ? ctx.ort : { y0: ctx.H * 0.14, y1: ctx.H * 0.25 };
      const dir = z() < 0.5 ? 1 : -1;
      const n = 5 + Math.floor(z() * 3);   // 5–7 Sprints
      const hindernis = (ctx.schutz || []).filter(r => r.name !== 'hand');
      const frei = p => !hindernis.some(r => randAbstand(p, r) < 22);
      const pkt = [{ x: dir > 0 ? -70 : W + 70, y: rnd(z, o.y0 + 10, o.y1 - 10) }];
      for (let i = 1; i < n; i++) {
        const basis = dir > 0 ? -70 + (W + 140) * i / n : W + 70 - (W + 140) * i / n;
        let p = null;
        for (let k = 0; k < 8 && !p; k++) {
          const c = { x: basis + rnd(z, -60, 60) + (k > 3 ? (k % 2 ? 1 : -1) * 90 * (k - 3) : 0), y: rnd(z, o.y0 + 8, o.y1 - 6) };
          if (frei(c)) p = c;
        }
        pkt.push(p || { x: basis, y: (o.y0 + o.y1) / 2 });
      }
      pkt.push({ x: dir > 0 ? W + 70 : -70, y: rnd(z, o.y0, o.y1) });
      // Zeiten: Sprint 0,32 s, Schweben gestreckt auf die Dauer
      const T_SPRINT = 0.32;
      const schweb = pkt.slice(1, -1).map(() => rnd(z, 0.5, 1));
      const sum = schweb.reduce((a, b) => a + b, 0), f = Math.max(0.6, (D - T_SPRINT * n) / sum);
      const plan = [];
      let t = 0;
      for (let i = 0; i < n; i++) {
        plan.push({ typ: 's', t0: t, t1: t + T_SPRINT, a: pkt[i], b: pkt[i + 1] });
        t += T_SPRINT;
        if (i < n - 1) { const h = schweb[i] * f; plan.push({ typ: 'h', t0: t, t1: t + h, a: pkt[i + 1], ph: z() * 6 }); t += h; }
      }
      const Dt = t;
      const root = el('div', 'nt-li', svg('nt-li-k', -44, -36, 74, 72, libelleSvg()));
      const k = q(root, '.nt-li-k');
      const grund = tt => {
        let a = plan[plan.length - 1];
        for (const x of plan) { if (tt < x.t1) { a = x; break; } }
        if (a.typ === 's') {
          const u = aus((tt - a.t0) / (a.t1 - a.t0));
          return { x: lerp(a.a.x, a.b.x, u), y: lerp(a.a.y, a.b.y, u), rot: grad(a.b.x - a.a.x, a.b.y - a.a.y), op: 1 };
        }
        const s = tt - a.t0, vor = plan[plan.indexOf(a) - 1];
        const rot = grad(vor.b.x - vor.a.x, vor.b.y - vor.a.y) + 5 * Math.sin(s * 2.3 + a.ph);
        return { x: a.a.x + 1.5 * Math.sin(s * 23 + a.ph), y: a.a.y + 1.5 * Math.sin(s * 17 + 2 * a.ph), rot, op: 1 };
      };
      const inst = {
        el: root, dauer: Dt, t: 0, weg: null,
        pose(tt) {
          const w = this.weg;
          if (w && tt >= w.at) {
            const b = grund(w.at), s = tt - w.at;
            if (w.art === 'tipp') {
              // drei Zickzack-Sprints (je 0,12 s) hinaus, schräg nach oben
              const raus = b.x < W / 2 ? -1 : 1;
              let p = { x: b.x, y: b.y }, rot = b.rot;
              for (let i = 0; i < 3; i++) {
                const u = klemme((s - i * 0.12) / 0.12, 0, 1);
                if (u <= 0) break;
                const ang = (raus > 0 ? 0 : 180) + (raus > 0 ? -1 : 1) * (35 + (i % 2 ? -40 : 30));
                const d = 190 * aus(u);
                p = { x: p.x + Math.cos(ang * RAD) * d, y: p.y + Math.sin(ang * RAD) * d };
                rot = ang;
              }
              return { x: p.x, y: p.y, rot, op: 1 - klemme((s - 0.3) / 0.12, 0, 1) };
            }
            const u = klemme(s / 0.4, 0, 1), ang = b.rot - 25;
            return { x: b.x + Math.cos(ang * RAD) * 320 * ein(u), y: b.y + Math.sin(ang * RAD) * 320 * ein(u) - 60 * u, rot: ang, op: 1 - klemme((u - 0.5) / 0.5, 0, 1) };
          }
          return grund(tt);
        },
        stelle(tt) { this.t = tt; const p = this.pose(tt); setz(k, p.x, p.y, p.rot, LI_GR, LI_GR, p.op); },
        hulle(tt) { const p = this.pose(tt); return p.op < 0.03 ? null : kasten(p.x, p.y, 58 * LI_GR, 58 * LI_GR); },
        tipp() { if (!this.weg) { this.weg = { at: this.t, art: 'tipp' }; this.dauer = this.t + 0.44; } },
        abgang() { if (!this.weg) this.weg = { at: this.t, art: 'abgang' }; return 0.4; },
      };
      return inst;
    },
  });

  /* ======================================================================== 4 Pusteblumen-Samen */
  function samenSvg() {
    let s = '<g id="nt-tag-samen">';
    const n = 13;
    for (let i = 0; i < n; i++) {
      const a = (-168 + 156 * i / (n - 1)) * RAD, l = 12 + (i % 3 === 1 ? 1.5 : 0);
      const x = Math.cos(a) * l, y = -7 + Math.sin(a) * l, mx = Math.cos(a) * l * 0.55 + Math.cos(a + Math.PI / 2) * 0.8, my = -7 + Math.sin(a) * l * 0.55;
      s += '<path d="M0 -7 Q' + mx.toFixed(1) + ' ' + my.toFixed(1) + ' ' + x.toFixed(1) + ' ' + y.toFixed(1) + '" fill="none" stroke="' + INK + '" stroke-opacity=".5" stroke-width=".9"/>';
    }
    for (let i = 0; i < n; i++) {
      const a = (-168 + 156 * i / (n - 1)) * RAD, l = 12 + (i % 3 === 1 ? 1.5 : 0);
      s += '<circle cx="' + (Math.cos(a) * l).toFixed(1) + '" cy="' + (-7 + Math.sin(a) * l).toFixed(1) + '" r="1.5" fill="' + CREAM + '" stroke="' + INK + '" stroke-opacity=".35" stroke-width=".6"/>';
    }
    s += '<path d="M0 -7 L0 9" stroke="' + INK + '" stroke-opacity=".65" stroke-width="1.1"/>';
    s += '<ellipse cx="0" cy="12.5" rx="1.8" ry="3.8" fill="#8A5A2B" stroke="' + INK + '" stroke-opacity=".6" stroke-width=".8"/>';
    return s + '</g>';
  }
  N.art('pusteblume', {
    baue(ctx, z) {
      const e = ctx.eintrag, W = ctx.W;
      const D = rnd(z, e.dauer[0], e.dauer[1]);
      const o = ctx.ort && typeof ctx.ort.y0 === 'number' ? ctx.ort : { y0: ctx.H * 0.04, y1: ctx.H * 0.3 };
      const dir = z() < 0.5 ? 1 : -1;
      const n = 7 + Math.floor(z() * 4);
      const samen = [];
      for (let i = 0; i < n; i++) {
        samen.push({
          t0: rnd(z, 0, 3), y: rnd(z, o.y0 + 18, o.y1 - 10), v: rnd(z, 60, 95), amp: rnd(z, 12, 25), per: rnd(z, 3, 5), ph: z() * 6.28,
          pend: rnd(z, 1.6, 2.6), pph: z() * 6.28, dreh: rnd(z, 0.6, 1.2), sk: rnd(z, 0.95, 1.25) * PB_GR, x0: dir > 0 ? rnd(z, -60, -20) : W + rnd(z, 20, 60),
        });
      }
      let html = '<svg class="nt-pb-defs" xmlns="http://www.w3.org/2000/svg" width="0" height="0"><defs>' + samenSvg() + '</defs></svg>';
      samen.forEach(() => { html += svg('nt-pb-s', -22, -26, 44, 48, '<use href="#nt-tag-samen" xlink:href="#nt-tag-samen" xmlns:xlink="http://www.w3.org/1999/xlink"/>'); });
      const root = el('div', 'nt-pb', html);
      const els = qa(root, '.nt-pb-s');
      const grund = (sd, tt) => {
        const s = tt - sd.t0;
        if (s < 0) return null;
        return { x: sd.x0 + dir * sd.v * s, y: sd.y + sd.amp * Math.sin(s / sd.per * 6.28 + sd.ph) - s * 2, rot: 12 * Math.sin(s / sd.pend * 6.28 + sd.pph), sx: 0.8 + 0.2 * Math.cos(s * sd.dreh + sd.ph) };
      };
      const ausblenden = tt => 1 - klemme((tt - (inst.dauer - 1.6)) / 1.6, 0, 1);
      const inst = {
        el: root, dauer: D, t: 0, wind: null, weg: null,
        posen(tt) {
          return samen.map((sd, i) => {
            const p = grund(sd, tt);
            if (!p) return null;
            let op = klemme((tt - sd.t0) / 0.5, 0, 1) * ausblenden(tt);
            const w = this.wind;
            if (w && tt >= w.at && w.dir[i]) {
              // Windstoß: Tempo ×4 für 1 s, dann klingt es ab; dazu eine Drehung
              const s = tt - w.at, d = w.dir[i];
              const weg = 3 * sd.v * (Math.min(s, 1) + (s > 1 ? 0.5 * (1 - Math.exp(-(s - 1) * 2)) : 0));
              p.x += d.x * weg; p.y += d.y * weg; p.rot += 200 * (1 - Math.exp(-s * 2)) * d.s;
            }
            if (this.weg && tt >= this.weg.at) op *= 1 - klemme((tt - this.weg.at) / 0.4, 0, 1);
            return op > 0.01 ? Object.assign(p, { op, sk: sd.sk }) : null;
          });
        },
        stelle(tt) {
          this.t = tt;
          this.posen(tt).forEach((p, i) => { if (p) setz(els[i], p.x, p.y, p.rot, p.sx * p.sk, p.sk, p.op); else deck(els[i], 0); });
        },
        hulle(tt) {
          let l = 1e9, o2 = 1e9, r = -1e9, u = -1e9;
          this.posen(tt).forEach(p => { if (p && p.x > -20 && p.x < W + 20) { l = Math.min(l, p.x - 14); r = Math.max(r, p.x + 14); o2 = Math.min(o2, p.y - 20); u = Math.max(u, p.y + 18); } });
          return r > l ? { x: l, y: o2, w: r - l, h: u - o2 } : null;
        },
        treffer(p) { return this.posen(this.t).some(s => s && Math.hypot(s.x - p.x, s.y - p.y) <= 60); },
        tipp(p) {
          if (this.wind) return;
          const dir2 = this.posen(this.t).map(s => {
            if (!s) return null;
            const dx = s.x - p.x, dy = s.y - p.y, d = Math.hypot(dx, dy);
            if (d > 160) return null;
            return d < 1 ? { x: 0, y: -1, s: 1 } : { x: dx / d, y: dy / d, s: dx >= 0 ? 1 : -1 };
          });
          this.wind = { at: this.t, dir: dir2 };
        },
        abgang() { if (!this.weg) this.weg = { at: this.t }; return 0.4; },
      };
      return inst;
    },
  });

  /* ======================================================================== 5 Papierflieger */
  // klassischer Pfeilflieger von schräg unten: großer heller Flügel, dahinter der zweite Flügel, darunter der Kiel; Neon-Streifen hinten
  const PF_SVG = '<path d="M38 2 L-26 4 L-30 13 Z" fill="' + PAPER_D + '" stroke="' + INK + '" stroke-width="1.8" stroke-linejoin="round"/>'
    + '<path d="M38 2 L-22 3 L-14 15 Z" fill="#D9C6A0" stroke="' + INK + '" stroke-width="1.8" stroke-linejoin="round"/>'
    + '<path d="M38 2 L-36 -19 L-22 3 Z" fill="#FFFFFF" stroke="' + INK + '" stroke-width="1.8" stroke-linejoin="round"/>'
    + '<path d="M-30.5 -13.5 L-21.4 0.6" stroke="#FF4FA8" stroke-width="2.6" stroke-linecap="round"/>'
    + '<path d="M36 1.6 L-20 1.4" stroke="' + INK + '" stroke-opacity=".35" stroke-width="1"/>'
    + '<path d="M30 -1 L-14 -12" stroke="' + INK + '" stroke-opacity=".18" stroke-width="1"/>';
  N.art('papierflieger', {
    baue(ctx, z) {
      const e = ctx.eintrag, W = ctx.W;
      const D = rnd(z, e.dauer[0], e.dauer[1]);
      const o = ctx.ort && typeof ctx.ort.y0 === 'number' ? ctx.ort : { y0: ctx.H * 0.04, y1: ctx.H * 0.3 };
      const dir = z() < 0.5 ? 1 : -1;
      const y0 = rnd(z, o.y0 + 15, o.y1 - 60), ph = z() * 6.28;
      const xa = dir > 0 ? -50 : W + 50, xe = dir > 0 ? W + 50 : -50;
      const root = el('div', 'nt-pf', svg('nt-pf-s', -40, -24, 82, 44, PF_SVG));
      const k = q(root, '.nt-pf-s');
      const bahn = s => {   // s: Fahrzeit 0 … D
        const u = s / D;
        return { x: lerp(xa, xe, u), y: y0 + 30 * Math.sin(u * 6.28 + ph) + 40 * u };
      };
      const inst = {
        el: root, dauer: D, t: 0, loop: null, weg: null,
        pose(tt) {
          const lp = this.loop;
          let s = tt, extra = null;
          if (lp && tt >= lp.at) {
            if (tt < lp.at + 1) {
              const th = 6.283 * glatt(tt - lp.at), R = 45;
              extra = { x: dir * R * Math.sin(th), y: R * Math.cos(th) - R, rot: grad(dir * Math.cos(th), -Math.sin(th)) };
              s = lp.at;
            } else s = tt - 1;
          }
          const p = bahn(s), p2 = bahn(s + 0.05);
          let rot = grad(p2.x - p.x, p2.y - p.y);
          let x = p.x, y = p.y;
          if (extra) { x += extra.x; y += extra.y; rot = extra.rot; }
          let op = 1;
          if (this.weg && tt >= this.weg.at) { const u = (tt - this.weg.at) / 0.4; op = 1 - klemme(u, 0, 1); y -= 50 * u; }
          return { x, y, rot, roll: 0.85 + 0.15 * Math.sin(tt * 2.2 + ph), op };
        },
        stelle(tt) {
          this.t = tt;
          const p = this.pose(tt);
          // Blick nach links: gespiegelt (die Nase zeigt in Flugrichtung)
          const links = Math.cos(p.rot * RAD) < 0;
          setz(k, p.x, p.y, links ? p.rot - 180 : p.rot, (links ? -1 : 1) * PF_GR, p.roll * PF_GR, p.op);
        },
        hulle(tt) { const p = this.pose(tt); return p.op < 0.03 ? null : kasten(p.x, p.y, 76 * PF_GR, 36 * PF_GR); },
        tipp() { if (!this.loop) { this.loop = { at: this.t }; this.dauer = D + 1; } },
        abgang() { if (!this.weg) this.weg = { at: this.t }; return 0.4; },
      };
      return inst;
    },
  });

  /* ======================================================================== 6 Seifenblasen */
  N.art('seifenblasen', {
    baue(ctx, z) {
      const e = ctx.eintrag, W = ctx.W;
      const o = ctx.ort && typeof ctx.ort.y0 === 'number' ? ctx.ort : { y0: ctx.H * 0.14, y1: ctx.H * 0.25 };
      const seite = z() < 0.5 ? -1 : 1;
      const n = 5 + Math.floor(z() * 4);
      const bl = [];
      let ende = 0;
      for (let i = 0; i < n; i++) {
        const d = rnd(z, 28, 60), r = d / 2;
        const b = {
          t0: rnd(z, 0, 4), d, r, x0: seite < 0 ? rnd(z, 0.03, 0.2) * W : W - rnd(z, 0.03, 0.2) * W, y0: rnd(z, o.y0 + 10, o.y1),
          vx: -seite * rnd(z, 30, 50), vy: rnd(z, 10, 20), leben: rnd(z, 3, 7), wph: z() * 6.28, wf: rnd(z, 1.2, 2.2), rph: z() * 360,
        };
        b.platz = Math.min(b.leben, Math.max(0.5, (b.y0 - r - 6) / b.vy));
        ende = Math.max(ende, b.t0 + b.platz + 0.3);
        bl.push(b);
      }
      const D = klemme(ende, e.dauer[0], e.dauer[1]);
      bl.forEach(b => { b.platz = Math.min(b.platz, D - 0.3 - b.t0); });
      let html = '';
      bl.forEach(b => { html += '<i class="nt-bl" style="width:' + b.d.toFixed(1) + 'px;height:' + b.d.toFixed(1) + 'px;left:' + (-b.r).toFixed(1) + 'px;top:' + (-b.r).toFixed(1) + 'px"></i>'; });
      bl.forEach(b => { html += '<i class="nt-blr" style="width:' + b.d.toFixed(1) + 'px;height:' + b.d.toFixed(1) + 'px;left:' + (-b.r - 2).toFixed(1) + 'px;top:' + (-b.r - 2).toFixed(1) + 'px;opacity:0"></i>'; });
      for (let i = 0; i < 6; i++) html += '<i class="nt-bltr" style="opacity:0"></i>';
      const root = el('div', 'nt-sb', html);
      const be = qa(root, '.nt-bl'), re = qa(root, '.nt-blr'), te = qa(root, '.nt-bltr');
      const inst = {
        el: root, dauer: D, t: 0, tipp_: null, weg: null,
        platzZeit(i) { const b = bl[i], tp = this.tipp_; return tp && tp.i === i ? Math.min(b.platz, tp.at - b.t0) : b.platz; },
        lage(i, tt) {
          const b = bl[i], s = tt - b.t0;
          if (s < 0) return null;
          const sp = Math.min(s, this.platzZeit(i));
          return { x: b.x0 + b.vx * sp + 7 * Math.sin(sp * b.wf + b.wph), y: b.y0 - b.vy * sp + 3 * Math.sin(sp * 2.7 + b.wph), s, platzt: s >= this.platzZeit(i) };
        },
        stelle(tt) {
          this.t = tt;
          const wegOp = this.weg && tt >= this.weg.at ? 1 - klemme((tt - this.weg.at) / 0.4, 0, 1) : 1;
          bl.forEach((b, i) => {
            const p = this.lage(i, tt);
            if (!p) { deck(be[i], 0); deck(re[i], 0); return; }
            if (!p.platzt) {
              const w = 0.04 * Math.sin(p.s * 5.3 + b.wph);
              setz(be[i], p.x, p.y, b.rph + p.s * 40, 1 + w, 1 - w, klemme(p.s / 0.35, 0, 1) * wegOp);
              deck(re[i], 0);
            } else {
              const u = (p.s - this.platzZeit(i)) / 0.22;
              deck(be[i], 0);
              if (u < 1) setz(re[i], p.x, p.y, 0, 1 + 0.6 * u, 1 + 0.6 * u, (1 - u) * wegOp); else deck(re[i], 0);
            }
          });
          // Tröpfchen der angetippten Blase
          const tp = this.tipp_;
          te.forEach((d, j) => {
            if (!tp || tt < tp.at) { deck(d, 0); return; }
            const u = (tt - tp.at) / 0.35;
            if (u >= 1) { deck(d, 0); return; }
            const a = (j / 6) * 6.283 + 0.4, R = bl[tp.i].r * (0.8 + 1.3 * aus(u));
            setz(d, tp.x + Math.cos(a) * R, tp.y + Math.sin(a) * R + 18 * u * u, 0, 1, 1, (1 - u) * wegOp);
          });
        },
        hulle(tt) {
          let l = 1e9, o2 = 1e9, r = -1e9, u = -1e9;
          bl.forEach((b, i) => { const p = this.lage(i, tt); if (p && !p.platzt) { l = Math.min(l, p.x - b.r); r = Math.max(r, p.x + b.r); o2 = Math.min(o2, p.y - b.r); u = Math.max(u, p.y + b.r); } });
          if (this.weg && tt >= this.weg.at + 0.4) return null;
          return r > l ? { x: l, y: o2, w: r - l, h: u - o2 } : null;
        },
        _ziel(p) {
          let best = -1, bd = 1e9;
          bl.forEach((b, i) => { const s = this.lage(i, this.t); if (s && !s.platzt) { const d = Math.hypot(s.x - p.x, s.y - p.y) - b.r; if (d < 16 && d < bd) { bd = d; best = i; } } });
          return best;
        },
        treffer(p) { return this._ziel(p) >= 0; },
        tipp(p) {
          const i = this._ziel(p);
          if (i < 0 || this.tipp_) return;
          const s = this.lage(i, this.t);
          this.tipp_ = { i, at: this.t, x: s.x, y: s.y };
        },
        abgang() { if (!this.weg) this.weg = { at: this.t }; return 0.4; },
      };
      return inst;
    },
  });

  /* ======================================================================== 7 Spatz */
  // Seitenansicht, Blick nach rechts (+x), Ursprung an den Füßen.
  const SP_SVG = '<g class="nt-sp-k">'
    + '<path d="M-12 -14 L-31 -9 L-30 -3.5 L-11 -8.5 Z" fill="#6E4A26" stroke="' + INK + '" stroke-width="1.5" stroke-linejoin="round"/>'
    + '<path d="M-23 -10.5 L-12 -12" stroke="#A0703C" stroke-width="1.2"/>'
    + '<path d="M-1 -5 L-2 0 M-5 0 L1 0 M4 -5 L4 0 M1.5 0 L7.5 0" fill="none" stroke="' + INK + '" stroke-width="1.5" stroke-linecap="round"/>'
    + '<path d="M-14 -12 C-14 -23 -2 -28 8 -25 C16 -22 16.5 -10 9 -5.5 C3 -2 -8 -3 -14 -12 Z" fill="#A0703C" stroke="' + INK + '" stroke-width="1.7" stroke-linejoin="round"/>'
    + '<path d="M-7 -6.4 C-1 -3.4 7 -3.6 10.4 -8.4 C12.4 -12 11.8 -17 9 -18.5 C5 -12.5 -1 -9 -7 -6.4 Z" fill="#E8D2B0"/>'
    + '<g class="nt-sp-flap nt-schleife"><path d="M-14 -14 C-11 -23 2 -25 6.5 -19.5 C3.5 -13 -5 -10.5 -14 -14 Z" fill="#6E4A26" stroke="' + INK + '" stroke-width="1.4" stroke-linejoin="round"/>'
    + '<path d="M-8 -18 L-4.5 -14.5 M-2.5 -20 L1 -16.5" stroke="#E8D2B0" stroke-width="1.4" stroke-linecap="round"/></g>'
    + '<g class="nt-sp-kopf"><circle cx="11" cy="-24" r="7.6" fill="#A0703C" stroke="' + INK + '" stroke-width="1.7"/>'
    + '<path d="M4.2 -27 C5.6 -32.4 15 -33.6 18.4 -27.4 C14 -28.6 8.6 -28.4 4.2 -27 Z" fill="#8A7F74" stroke="' + INK + '" stroke-width="1" stroke-linejoin="round"/>'
    + '<ellipse cx="11.6" cy="-20.6" rx="3.8" ry="2.6" fill="#E8D2B0"/>'
    + '<path d="M15.5 -21.5 C17.5 -20 17.5 -17.6 15 -16.4 C13.2 -17.4 13.4 -20 15.5 -21.5 Z" fill="' + INK + '"/>'
    + '<path d="M17.6 -25.6 L24 -23 L17.6 -20.8 Z" fill="' + INK + '" stroke="' + INK + '" stroke-width=".8" stroke-linejoin="round"/>'
    + '<circle cx="14" cy="-25.4" r="1.8" fill="' + INK + '"/><circle cx="14.6" cy="-26" r=".65" fill="#fff"/></g></g>';
  // Federchen: geschwungene Fahne mit Kiel, oben heller
  const FEDER = '<path d="M0.5 -10 C5 -7 5.5 1 1.5 8 L0.6 10 C-0.6 7 -3.6 3 -4 -1 C-4.4 -6 -2.4 -9 0.5 -10 Z" fill="#C9955A" stroke="' + INK + '" stroke-width=".9" stroke-linejoin="round"/>'
    + '<path d="M0.5 -9 C-2 -7 -3 -4 -3 -1" fill="none" stroke="#F1DDBE" stroke-width="1.6" stroke-linecap="round"/>'
    + '<path d="M0.6 11 C0.4 4 0.8 -3 0.5 -9 M0.5 -4 L3.4 -6 M0.5 0 L3.6 -2 M0.5 -2 L-2.6 -4.6 M0.6 3 L-2.4 0.6" fill="none" stroke="#6E4A26" stroke-width=".8" stroke-linecap="round"/>';
  N.art('spatz', {
    baue(ctx, z) {
      const e = ctx.eintrag;
      const D = rnd(z, e.dauer[0], e.dauer[1]);
      // Platz auf dem hinteren Band: der Vogel ragt nach oben (Richtung Fächer), daher seine ganze Fläche samt Hüpfweg prüfen
      const g0 = ctx.ort && typeof ctx.ort.grad === 'number' ? ctx.ort.grad : 260;
      const hindernis = (ctx.schutz || []).filter(r => r.name !== 'hand');
      let g = g0, gk = 1e18;
      for (let w = 226; w <= 314; w += 2) {
        const p = ctx.band(w, 0.55), r = { x: p.x - 60, y: p.y - 58, w: 120, h: 62 };
        const k = hindernis.reduce((s, h) => s + flaeche(r, h), 0) * 10 + Math.abs(w - g0);
        if (k < gk) { gk = k; g = w; }
      }
      const weg = bandWeg(ctx, g - 14, g + 14, 0.55);
      const s0 = weg.L / 2;
      let f = z() < 0.5 ? 1 : -1;   // Blickrichtung (+1 rechts)
      const P = weg.an(s0);
      const T_AN = 1.0, T_AB = 0.8;
      const S = { x: P.x - f * 170, y: -60 }, C = { x: P.x - f * 50, y: P.y - 170 };
      // Ablauf am Boden: hüpfen, picken, umdrehen …
      const akt = [];
      let t = T_AN, s = s0, ff = f;
      const ende = D - T_AB;
      const dazu = (typ, d, x) => { const a = Object.assign({ typ, t0: t, t1: Math.min(t + d, ende), s0: s, f: ff }, x || {}); akt.push(a); t = a.t1; return a; };
      dazu('stehen', 0.3);
      let runde = 0;
      while (t < ende - 0.05) {
        const hops = runde === 0 ? 2 + Math.floor(z() * 2) : 1 + Math.floor(z() * 2);
        for (let i = 0; i < hops && t < ende - 0.05; i++) {
          let w = rnd(z, 12, 18) * ff;
          if (s + w < 4 || s + w > weg.L - 4) w = -w;
          const a = dazu('hupf', 0.25, { s1: s + w });
          s = a.s1; dazu('stehen', rnd(z, 0.2, 0.45));
        }
        if (t < ende - 0.05) dazu('picken', 0.9);
        if (t < ende - 0.05) dazu('stehen', rnd(z, 0.2, 0.5));
        if (t < ende - 0.05) { const a = dazu('drehen', 0.22, { f1: -ff }); ff = a.f1; }
        runde++;
      }
      const root = el('div', 'nt-sp', svg('nt-sp-sch', -20, -6, 40, 12, '<ellipse cx="0" cy="0" rx="16" ry="4.5" fill="' + INK + '" fill-opacity=".2"/>')
        + svg('nt-sp-v', -36, -38, 66, 44, SP_SVG)
        + svg('nt-sp-f1', -7, -12, 14, 24, FEDER) + svg('nt-sp-f2', -7, -12, 14, 24, FEDER));
      const vogel = q(root, '.nt-sp-v'), kopf = q(root, '.nt-sp-kopf'), sch = q(root, '.nt-sp-sch'), fe = [q(root, '.nt-sp-f1'), q(root, '.nt-sp-f2')];
      const boden = tt => {
        let a = akt[akt.length - 1];
        for (const x of akt) { if (tt < x.t1) { a = x; break; } }
        const u = klemme((tt - a.t0) / Math.max(0.001, a.t1 - a.t0), 0, 1);
        let ss = a.s0, hoch = 0, nick = 0, sx = a.f;
        if (a.typ === 'hupf') { ss = lerp(a.s0, a.s1, u); hoch = 8 * Math.sin(Math.PI * u); }
        if (a.typ === 'picken') nick = 34 * Math.max(0, Math.sin(Math.PI * ((u * 3) % 1)));
        if (a.typ === 'drehen') sx = a.f * Math.cos(Math.PI * u);
        if (tt >= a.t1 && a.typ === 'drehen') sx = a.f1;
        if (tt >= a.t1 && a.typ === 'hupf') ss = a.s1;
        const p = weg.an(ss);
        return { x: p.x, y: p.y, hoch, nick, sx, kipp: 0, fliegt: false, op: 1, boden: p };
      };
      const flug = (A, B, Cc, u, faceX) => {
        const p = bez2(A, Cc, B, u), p2 = bez2(A, Cc, B, Math.min(1, u + 0.02));
        const fx = Math.abs(p2.x - p.x) > 0.01 ? Math.sign(p2.x - p.x) : faceX;
        return { x: p.x, y: p.y, hoch: 0, nick: 0, sx: fx, kipp: klemme(grad(Math.abs(p2.x - p.x), p2.y - p.y), -30, 30), fliegt: true, op: 1 };
      };
      const grund = tt => {
        if (tt < T_AN) {
          const r = flug(S, P, C, aus(tt / T_AN), f);
          r.boden = P; r.sh = aus(tt / T_AN);
          return r;
        }
        const b = boden(Math.min(tt, ende));
        if (tt < ende) { b.sh = 1; return b; }
        const u = ein((tt - ende) / T_AB), A = { x: b.x, y: b.y };
        const r = flug(A, { x: b.x + b.sx * 200, y: -70 }, { x: b.x + b.sx * 40, y: b.y - 120 }, u, b.sx);
        r.boden = b.boden; r.sh = 1 - u; r.op = 1 - klemme((u - 0.8) / 0.2, 0, 1);
        return r;
      };
      const inst = {
        el: root, dauer: D, t: 0, weg: null,
        pose(tt) {
          const w = this.weg;
          if (w && tt >= w.at) {
            const b = grund(w.at), L2 = w.art === 'tipp' ? 0.6 : 0.4, u = aus(klemme((tt - w.at) / L2, 0, 1)), fx = b.sx >= 0 ? 1 : -1;
            const r = flug({ x: b.x, y: b.y - b.hoch }, { x: b.x + fx * 110, y: -80 }, { x: b.x + fx * 10, y: b.y - 170 }, u, fx);
            r.boden = b.boden; r.sh = 1 - u; r.op = 1 - klemme((tt - w.at - L2 * 0.7) / (L2 * 0.3), 0, 1);
            return r;
          }
          return grund(tt);
        },
        stelle(tt) {
          this.t = tt;
          const p = this.pose(tt);
          setz(vogel, p.x, p.y - p.hoch, p.kipp * (p.sx >= 0 ? 1 : -1), (p.sx === 0 ? 0.001 : p.sx) * SP_GR, SP_GR, p.op);
          dreh(kopf, p.nick);
          klasse(root, 'fliegt', p.fliegt);
          const bd = p.boden || p;
          setz(sch, bd.x, bd.y, 0, 1 - 0.25 * (p.hoch / 8), 1, 0.9 * (p.sh === undefined ? 1 : p.sh) * (p.op));
          // Federchen nach dem Antippen
          const w = this.weg;
          fe.forEach((d, i) => {
            if (!w || w.art !== 'tipp' || tt < w.at) { deck(d, 0); return; }
            const s = tt - w.at, u = klemme(s / 1.0, 0, 1), b = w.p;
            setz(d, b.x + (i ? 14 : -10) + (i ? 8 : -8) * Math.sin(s * 6 + i), b.y - 22 + 46 * u, (i ? 40 : -30) + 35 * Math.sin(s * 7 + i * 2), 1, 1, 1 - klemme((u - 0.6) / 0.4, 0, 1));
          });
        },
        hulle(tt) {
          const p = this.pose(tt);
          return p.op < 0.03 ? null : kasten(p.x, p.y - p.hoch - 17 * SP_GR, 54 * SP_GR, 40 * SP_GR);
        },
        tipp() { if (!this.weg) { const b = this.pose(this.t); this.weg = { at: this.t, art: 'tipp', p: { x: b.x, y: b.y } }; this.dauer = this.t + 1.0; } },
        abgang() { if (!this.weg) this.weg = { at: this.t, art: 'abgang' }; return 0.4; },
      };
      return inst;
    },
  });

  /* ======================================================================== 8 Wolke vor der Sonne */
  function wolkeSvg() {
    const kr = [[-62, 10, 30], [-28, -6, 38], [16, -16, 42], [56, 2, 33], [2, 14, 36], [86, 18, 20], [-88, 22, 18]];
    let s = '';
    const kreis = (c, dy, att) => '<circle cx="' + c[0] + '" cy="' + (c[1] + dy) + '" r="' + c[2] + '" ' + att + '/>';
    kr.forEach(c => { s += kreis(c, 7, 'fill="none" stroke="' + INK + '" stroke-opacity=".7" stroke-width="5"'); });
    kr.forEach(c => { s += kreis(c, 0, 'fill="none" stroke="' + INK + '" stroke-opacity=".7" stroke-width="5"'); });
    kr.forEach(c => { s += kreis(c, 7, 'fill="' + PAPER_D + '"'); });
    kr.forEach(c => { s += kreis(c, 0, 'fill="#FFFDF8"'); });
    s += '<path d="M-44 -22 Q-30 -40 -10 -36 M10 -46 Q30 -54 46 -40" fill="none" stroke="#fff" stroke-width="4" stroke-linecap="round"/>';
    return s;
  }
  N.art('wolke', {
    baue(ctx, z) {
      const e = ctx.eintrag;
      const D = rnd(z, e.dauer[0], e.dauer[1]);
      // Sonne aus dem Kern; steht sie nicht an ihrem Tagesplatz (z. B. mitten in der Tag/Nacht-Überblendung), gilt die Lage aus dem
      // CSS (.himmel .sonne: Mitte bei 7 % / 3 %)
      let so = ctx.ort && typeof ctx.ort.x === 'number' ? ctx.ort : null;
      if (!so || !(so.y > -80 && so.y < 0.25 * ctx.H) || !(so.x > -80 && so.x < ctx.W * 0.5)) so = { x: ctx.W * 0.07, y: ctx.H * 0.03, r: 66 };
      const y = so.y + rnd(z, 10, 25) + 18;
      const xa = so.x - 220, xe = so.x + 330;
      const ruhig = !!ctx.ruhig;
      const root = el('div', 'nt-wo', '<i class="nt-wo-sch" style="width:' + ctx.W + 'px;height:' + ctx.H + 'px;opacity:0"></i>' + svg('nt-wo-k', -115, -62, 230, 124, wolkeSvg()));
      const k = q(root, '.nt-wo-k'), sch = q(root, '.nt-wo-sch');
      const inst = {
        el: root, dauer: ruhig ? 10 : D, t: 0, weg: null,
        pose(tt) {
          let x, op;
          if (ruhig) { x = so.x + 20; op = klemme(tt / 2, 0, 1) * (1 - klemme((tt - 8) / 2, 0, 1)); }
          else { x = lerp(xa, xe, tt / D); op = klemme(tt / 1.2, 0, 1) * (1 - klemme((tt - (D - 1.5)) / 1.5, 0, 1)); }
          if (this.weg && tt >= this.weg.at) op *= 1 - klemme((tt - this.weg.at) / 0.4, 0, 1);
          const bob = ruhig ? 0 : 3 * Math.sin(tt * 0.9);
          const deckt = klemme(1 - Math.abs(x - so.x) / 130, 0, 1);
          return { x, y: y + bob, op, schatten: op * glatt(deckt) * (ruhig ? 0.03 : 0.05) };
        },
        stelle(tt) { this.t = tt; const p = this.pose(tt); setz(k, p.x, p.y, 0, 1, 1, p.op); deck(sch, p.schatten); },
        hulle(tt) { const p = this.pose(tt); return p.op < 0.03 ? null : kasten(p.x, p.y, 220, 96); },
        abgang() { if (!this.weg) this.weg = { at: this.t }; return 0.4; },
      };
      return inst;
    },
  });

  /* ======================================================================== 9 Regenbogen */
  const RB_FARBEN = ['#FF4D57', '#FF8A1F', '#FFDD33', '#4FD36E', '#4C7DFF', '#8B6BFF'];
  N.art('regenbogen', {
    baue(ctx) {
      const W = ctx.W, H = ctx.H;
      const o = ctx.ort && typeof ctx.ort.cx === 'number' ? ctx.ort : { cx: ctx.cx, cy: ctx.cy + 40, r: 0.46 * W };
      const B = 10;   // Bandbreite
      // Ellipse statt Kreis: Der Scheitel liegt im oberen Himmel (bei 0,46 W käme er weit über dem Bildrand zu liegen)
      const ry0 = Math.max(120, Math.min(o.r, o.cy - 0.07 * H - 6 * B));
      const ruhig = !!ctx.ruhig;
      let s = '', laengen = [];
      const bogen = (rx, ry) => 'M' + (o.cx - rx).toFixed(1) + ' ' + o.cy.toFixed(1) + ' A' + rx.toFixed(1) + ' ' + ry.toFixed(1) + ' 0 0 1 ' + (o.cx + rx).toFixed(1) + ' ' + o.cy.toFixed(1);
      const lang = (rx, ry) => Math.PI * (3 * (rx + ry) - Math.sqrt((3 * rx + ry) * (rx + 3 * ry))) / 2;
      // weicher Saum außen und innen
      s += '<path class="nt-rb-b" d="' + bogen(o.r + 6 * B + 5, ry0 + 6 * B + 5) + '" fill="none" stroke="#FF4D57" stroke-opacity=".1" stroke-width="12"/>';
      laengen.push(lang(o.r + 6 * B + 5, ry0 + 6 * B + 5));
      RB_FARBEN.forEach((c, i) => {
        const d = (5 - i) * B + B / 2;
        s += '<path class="nt-rb-b" d="' + bogen(o.r + d, ry0 + d) + '" fill="none" stroke="' + c + '" stroke-opacity=".44" stroke-width="' + (B + 0.6) + '"/>';
        laengen.push(lang(o.r + d, ry0 + d));
      });
      s += '<path class="nt-rb-b" d="' + bogen(o.r - 5, ry0 - 5) + '" fill="none" stroke="#8B6BFF" stroke-opacity=".1" stroke-width="12"/>';
      laengen.push(lang(o.r - 5, ry0 - 5));
      const root = el('div', 'nt-rb', '<svg class="nt-svg nt-rb-s" xmlns="http://www.w3.org/2000/svg" width="' + W.toFixed(0) + '" height="' + H.toFixed(0) + '" viewBox="0 0 ' + W.toFixed(0) + ' ' + H.toFixed(0) + '" style="left:0;top:0">' + s + '</svg>');
      const sv = q(root, '.nt-rb-s'), pf = qa(root, '.nt-rb-b');
      pf.forEach((p, i) => { p.style.strokeDasharray = laengen[i].toFixed(1) + ' ' + laengen[i].toFixed(1); });
      const rOut = o.r + 6 * B + 10, ryOut = ry0 + 6 * B + 10;
      const inst = {
        el: root, dauer: 7, t: 0, weg: null, _u: -1,
        pose(tt) {
          let op, wachs;
          if (ruhig) { op = klemme(tt / 1.5, 0, 1) * (1 - klemme((tt - 5) / 2, 0, 1)); wachs = 1; }
          else { op = 1 - klemme((tt - 5) / 2, 0, 1); wachs = glatt(tt / 1.5); }
          if (this.weg && tt >= this.weg.at) op *= 1 - klemme((tt - this.weg.at) / 0.4, 0, 1);
          return { op, wachs };
        },
        stelle(tt) {
          this.t = tt;
          const p = this.pose(tt);
          deck(sv, p.op);
          const u = Math.round(p.wachs * 1000) / 1000;
          if (u !== this._u) { this._u = u; pf.forEach((e, i) => { e.style.strokeDashoffset = (laengen[i] * (1 - u)).toFixed(1); }); }
        },
        hulle(tt) {
          const p = this.pose(tt);
          if (p.op < 0.03) return null;
          const x0 = Math.max(0, o.cx - rOut), x1 = Math.min(W, o.cx - rOut + 2 * rOut * Math.max(0.05, p.wachs));
          const y0 = Math.max(0, o.cy - ryOut);
          return { x: x0, y: y0, w: Math.max(1, x1 - x0), h: Math.max(1, o.cy - y0) };
        },
        abgang() { if (!this.weg) this.weg = { at: this.t }; return 0.4; },
      };
      return inst;
    },
  });

  /* ======================================================================== 10 Heißluftballon */
  function ballonSvg() {
    const huelle = (a, b) => 'M0 -48 C' + 27 * a + ' -48 ' + 31 * a + ' -16 ' + 21 * a + ' 3 C' + 15 * a + ' 13 ' + 8 * a + ' 19 ' + 6 * a + ' 23 L' + 6 * b + ' 23 C' + 8 * b + ' 19 ' + 15 * b + ' 13 ' + 21 * b + ' 3 C' + 31 * b + ' -16 ' + 27 * b + ' -48 0 -48 Z';
    const bahnen = [[-1, -0.6, '#FF4D57'], [-0.6, -0.2, '#FFD65A'], [-0.2, 0.2, '#4FD36E'], [0.2, 0.6, '#4C7DFF'], [0.6, 1, CREAM]];
    let s = '<g class="nt-hb-fl"><circle cx="0" cy="26" r="12" fill="#FFD65A" fill-opacity=".5"/><circle cx="0" cy="26" r="6" fill="#FFF3A8" fill-opacity=".7"/>'
      + '<path d="M0 18 C4 22 4.5 27 0 31 C-4.5 27 -4 22 0 18 Z" fill="#FF8A1F" stroke="' + INK + '" stroke-width=".8"/><path d="M0 22 C2 24.5 2 27 0 29 C-2 27 -2 24.5 0 22 Z" fill="#FFF3A8"/></g>';
    s += '<path d="M-6 23 L-6.5 34 M6 23 L6.5 34 M-2 23 L-2.5 34 M2 23 L2.5 34" stroke="' + INK + '" stroke-width="1.1"/>';
    s += '<rect x="-8" y="33" width="16" height="11" rx="2" fill="#A0703C" stroke="' + INK + '" stroke-width="1.5"/><path d="M-8 37.5 L8 37.5 M-3 33 L-3 44 M3 33 L3 44" stroke="#6E4A26" stroke-width="1"/>';
    bahnen.forEach(([a, b, c]) => { s += '<path d="' + huelle(a, b) + '" fill="' + c + '"/>'; });
    s += '<path d="' + huelle(-1, 1) + '" fill="none" stroke="' + INK + '" stroke-width="1.8" stroke-linejoin="round"/>';
    [-0.6, -0.2, 0.2, 0.6].forEach(a => { s += '<path d="M0 -48 C' + 27 * a + ' -48 ' + 31 * a + ' -16 ' + 21 * a + ' 3 C' + 15 * a + ' 13 ' + 8 * a + ' 19 ' + 6 * a + ' 23" fill="none" stroke="' + INK + '" stroke-opacity=".55" stroke-width="1"/>'; });
    s += '<path d="M-21 3 C-14 7 14 7 21 3" fill="none" stroke="' + INK + '" stroke-opacity=".55" stroke-width="1"/>';
    s += '<path d="M-17 -30 C-20 -20 -19 -8 -14 2" fill="none" stroke="#fff" stroke-opacity=".55" stroke-width="3" stroke-linecap="round"/>';
    return s;
  }
  N.art('heissluftballon', {
    baue(ctx, z) {
      const e = ctx.eintrag, W = ctx.W;
      const D = rnd(z, e.dauer[0], e.dauer[1]);
      const o = ctx.ort && typeof ctx.ort.y0 === 'number' ? ctx.ort : { y0: ctx.H * 0.06, y1: ctx.H * 0.18 };
      const dir = z() < 0.5 ? 1 : -1, ph = z() * 6.28;
      const y0 = rnd(z, o.y0 + 34, o.y1 + 12);
      const xa = dir > 0 ? -45 : W + 45, xe = dir > 0 ? W + 45 : -45;
      const root = el('div', 'nt-hb', svg('nt-hb-s', -36, -52, 72, 100, ballonSvg()));
      const k = q(root, '.nt-hb-s'), fl = q(root, '.nt-hb-fl');
      const inst = {
        el: root, dauer: D, t: 0, steig: null, weg: null,
        pose(tt) {
          let x = lerp(xa, xe, tt / D), y = y0 + 4 * Math.sin(tt / 4 * 6.28 + ph), rot = 2 * Math.sin(tt / 4 * 6.28 + ph + 1);
          let flamme = 0.35 + 0.1 * Math.sin(tt * 9), op = 1;
          const s = this.steig;
          if (s && tt >= s.at) {
            const a = tt - s.at;
            flamme = a < 0.4 ? 1 : 0.6;
            const st = Math.max(0, a - 0.15);
            y -= 30 * st + 55 * st * st;
            x += dir * 25 * st;
            rot += dir * 4 * klemme(st, 0, 1);
          }
          if (this.weg && tt >= this.weg.at) { const u = klemme((tt - this.weg.at) / 0.4, 0, 1); op = 1 - u; y -= 40 * u; }
          return { x, y, rot, flamme, op: op * klemme(y / 20 + 3, 0, 1) };
        },
        stelle(tt) {
          this.t = tt;
          const p = this.pose(tt);
          setz(k, p.x, p.y, p.rot, HB_GR, HB_GR, p.op);
          tf(fl, 'translate(0px,27px) scale(' + (0.75 + 1.7 * p.flamme).toFixed(3) + ') translate(0px,-27px)');
        },
        hulle(tt) { const p = this.pose(tt); return p.op < 0.03 || p.y < -60 ? null : kasten(p.x, p.y - 2 * HB_GR, 64 * HB_GR, 96 * HB_GR); },
        tipp() { if (!this.steig) { this.steig = { at: this.t }; this.dauer = Math.min(this.dauer, this.t + 3.2); } },
        abgang() { if (!this.weg) this.weg = { at: this.t }; return 0.4; },
      };
      return inst;
    },
  });

  /* ======================================================================== 11 Schnecke */
  // Seitenansicht, Blick nach rechts (+x), Ursprung unter dem Fuß. Einziehen: Körper schrumpft ins Haus, Fühler fahren ein.
  function schneckeSvg() {
    let spirale = '';
    for (let i = 0; i <= 60; i++) {
      const a = i / 60 * 3 * 6.283, r = 12.5 * (1 - i / 64);
      spirale += (i ? 'L' : 'M') + (-6 + Math.cos(-a + 1.2) * r).toFixed(1) + ' ' + (-16 + Math.sin(-a + 1.2) * r).toFixed(1);
    }
    return '<g class="nt-sn-koerper">'
      + '<g class="nt-sn-fuehler"><path d="M17 -11 Q18 -20 15 -27 M20 -11 Q23 -19 24 -25" fill="none" stroke="' + INK + '" stroke-width="3.4" stroke-linecap="round"/>'
      + '<path d="M17 -11 Q18 -20 15 -27 M20 -11 Q23 -19 24 -25" fill="none" stroke="#B9C7A0" stroke-width="1.8" stroke-linecap="round"/>'
      + '<circle cx="15" cy="-27.5" r="2.6" fill="#B9C7A0" stroke="' + INK + '" stroke-width="1.2"/><circle cx="24" cy="-25.5" r="2.6" fill="#B9C7A0" stroke="' + INK + '" stroke-width="1.2"/>'
      + '<circle cx="15.4" cy="-27.8" r="1.1" fill="' + INK + '"/><circle cx="24.4" cy="-25.8" r="1.1" fill="' + INK + '"/></g>'
      + '<path d="M-24 0 C-24 -4 -14 -6 -2 -6 L12 -6 C16 -14 24 -13 25 -6 C26 -2 27 -1 30 0 Z" fill="#B9C7A0" stroke="' + INK + '" stroke-width="1.6" stroke-linejoin="round"/>'
      + '<path d="M-20 0 Q-17 -3 -14 0 Q-11 -3 -8 0 Q-5 -3 -2 0 Q1 -3 4 0 Q7 -3 10 0 Q13 -3 16 0 Q19 -3 22 0" fill="none" stroke="#7E8F63" stroke-width="1.1"/>'
      + '<path d="M20 -9 Q21.5 -7 21 -5.4" fill="none" stroke="' + INK + '" stroke-width="1" stroke-linecap="round"/></g>'
      + '<g class="nt-sn-haus"><circle cx="-6" cy="-16" r="14" fill="#C9803E" stroke="' + INK + '" stroke-width="1.7"/>'
      + '<path d="' + spirale + '" fill="none" stroke="#7A4718" stroke-width="1.6" stroke-linecap="round"/>'
      + '<path d="M-15 -25 Q-9 -31 -1 -29" fill="none" stroke="#FFE2B8" stroke-width="2.2" stroke-linecap="round"/></g>';
  }
  N.art('schnecke', {
    baue(ctx) {
      const e = ctx.eintrag;
      const D = e.dauer[1];
      let g = ctx.ort && typeof ctx.ort.grad === 'number' ? ctx.ort.grad : 115;
      const V = 8, LANG = 230;
      // Start: so weit vor dem Zielwinkel, dass die Schnecke in etwa 30 s ankommt; nicht durch 66–114° (Hinweisleiste)
      const gradProPx = w => { const a = ctx.band(w - 0.5, 0.5), b = ctx.band(w + 0.5, 0.5); return 1 / Math.max(0.5, Math.hypot(a.x - b.x, a.y - b.y)); };
      const dg = LANG * gradProPx(g);
      // Weg wählen: Richtung, Bandlage und ein Ziel kurz vor dem Platz so, dass Plätze, Leisten und Knöpfe die Schnecke möglichst
      // wenig verdecken (am Ziel wartet sie am längsten, daher zählt es mehrfach)
      const lr = leiste();
      const hindernis = (ctx.schutz || []).filter(r => r.name !== 'hand').concat(lr ? [Object.assign({ name: 'reaktion' }, lr)] : []);
      const huelleAuf = (w, quer) => { const p = ctx.band(w, quer); return kasten(p.x, p.y - 15 * SN_GR, 60 * SN_GR, 36 * SN_GR); };
      const deckung = r => Math.min(1, hindernis.reduce((s, h) => s + flaeche(r, h), 0) / (r.w * r.h));
      // Bewertet wird wie beim Zuschauen: Anteil der Zeit (6–34 s), in der die Schnecke mehr als zur Hälfte verdeckt ist
      // Beim eigenen Trödeln darf sie auch auf die andere vordere Seite (65° statt 115°), wenn dort deutlich mehr frei ist
      const ziele = [[g, 0]];
      if (ctx.ort && ctx.ort.seat === ctx.meinPlatz) ziele.push([(540 - g) % 360, 0.08]);
      let wahl = null;
      ziele.forEach(([gz, malus]) => [0.55, 0.3].forEach(quer => [1, -1].forEach(sg => [1, 0.75, 0.5, 0.3].forEach(lf => {
        for (let zur = 0; zur <= 30; zur += 3) {
          const e2 = gz + sg * zur, s2 = e2 + sg * dg * lf;
          if (Math.min(s2, e2) < 114 && Math.max(s2, e2) > 66) continue;
          const L2 = LANG * lf;
          let schlecht = 0, summe = 0, n = 0;
          for (let tt = 6; tt <= 34; tt += 2) {
            const u = Math.min(1, (tt - 1) * V / L2), d = deckung(huelleAuf(s2 + (e2 - s2) * u, quer));
            if (d > 0.45) schlecht++;
            summe += d; n++;
          }
          const k = schlecht / n + 0.2 * summe / n + (1 - lf) * 0.12 + zur * 0.004 + (quer !== 0.55 ? 0.05 : 0) + malus
            + Math.max(0, ctx.band(s2, quer).y - (ctx.H - 250)) * 0.01;
          if (!wahl || k < wahl.k) wahl = { k, s: s2, e: e2, quer };
        }
      }))));
      if (!wahl) wahl = { s: g + dg, e: g, quer: 0.55 };
      const weg = bandWeg(ctx, wahl.s, wahl.e, wahl.quer);
      const rechts = weg.an(1).dir;
      const root = el('div', 'nt-sn', svg('nt-sn-sch', -28, -5, 56, 10, '<ellipse cx="0" cy="0" rx="24" ry="3.6" fill="' + INK + '" fill-opacity=".16"/>')
        + Array.from({ length: 9 }, () => '<i class="nt-sn-spur" style="width:9px;height:4px;margin:-2px 0 0 -4.5px;border-radius:3px;background:#fff;opacity:0"></i>').join('')
        + svg('nt-sn-k', -34, -36, 70, 42, schneckeSvg()));
      const k = q(root, '.nt-sn-k'), kp = q(root, '.nt-sn-koerper'), fu = q(root, '.nt-sn-fuehler'), sch = q(root, '.nt-sn-sch'), spur = qa(root, '.nt-sn-spur');
      const inst = {
        el: root, dauer: D, t: 0, rein: null, weg: null,
        // Kriechzeit bis tt (Pausen durch Antippen abgezogen)
        kriech(tt) {
          let s = Math.max(0, tt - 1);
          const r = this.rein;
          if (r && tt > r.at) s -= Math.min(tt - r.at, 2.9);
          return Math.max(0, s);
        },
        pose(tt) {
          const s = Math.min(weg.L, this.kriech(tt) * V), p = weg.an(s);
          let einzug = 0, op = klemme(tt / 1, 0, 1);
          const hervor = 1 - aus(klemme(tt / 1, 0, 1));
          const r = this.rein;
          if (r && tt >= r.at) { const a = tt - r.at; einzug = a < 0.3 ? a / 0.3 : (a < 2.3 ? 1 : 1 - klemme((a - 2.3) / 0.5, 0, 1)); }
          if (tt > D - 0.9) { einzug = Math.max(einzug, klemme((tt - (D - 0.9)) / 0.4, 0, 1)); op *= 1 - klemme((tt - (D - 0.5)) / 0.5, 0, 1); }
          const w = this.weg;
          if (w && tt >= w.at) { const a = tt - w.at; einzug = Math.max(einzug, klemme(a / 0.2, 0, 1)); op *= 1 - klemme((a - 0.15) / 0.25, 0, 1); }
          const f = Math.cos(rechts * RAD) >= 0 ? 1 : -1;
          // Seitenansicht: der Band-Perspektive nur gedämpft folgen
          const rot = klemme(((f > 0 ? p.dir : p.dir - 180) + 540) % 360 - 180, -25, 25);
          return { x: p.x, y: p.y + 10 * hervor, rot, f, einzug, op, s, kriecht: s < weg.L && einzug === 0 && tt > 1 };
        },
        stelle(tt) {
          this.t = tt;
          const p = this.pose(tt);
          setz(k, p.x, p.y, p.rot, p.f * SN_GR, SN_GR, p.op);
          const puls = p.kriecht ? 0.025 * Math.sin(tt * 5) : 0;
          tf(kp, 'translate(-6px,-6px) scale(' + (1 - 0.72 * p.einzug + puls).toFixed(3) + ',' + (1 - 0.35 * p.einzug).toFixed(3) + ') translate(6px,6px)');
          tf(fu, 'translate(18px,-10px) scale(1,' + Math.max(0.02, 1 - p.einzug * 1.15).toFixed(3) + ') rotate(' + (p.kriecht ? 6 * Math.sin(tt * 3.1) : 0).toFixed(1) + 'deg) translate(-18px,10px)');
          setz(sch, p.x, p.y + 1, p.rot, SN_GR, SN_GR, p.op);
          // glänzende Spur: verblasst in etwa 5 s
          spur.forEach((d, i) => {
            const ss = p.s - 14 - i * 6;
            if (ss < 0) { deck(d, 0); return; }
            const q2 = weg.an(ss), alter = (p.s - ss) / V;
            setz(d, q2.x, q2.y - 1, q2.dir, 1, 1, p.op * 0.55 * klemme(1 - alter / 5, 0, 1));
          });
        },
        hulle(tt) { const p = this.pose(tt); return p.op < 0.03 ? null : kasten(p.x, p.y - 15 * SN_GR, 60 * SN_GR, 36 * SN_GR); },
        tipp() { if (!this.rein) this.rein = { at: this.t }; },
        abgang() { if (!this.weg) this.weg = { at: this.t }; return 0.4; },
      };
      return inst;
    },
  });

  /* ======================================================================== B1 Schmetterling (Bestand) */
  // Gleiche Bahn wie FunFx.SkyNode.launch (App): Höhe 0,10–0,24 H, quer über das Bild, Wellen, 9 s, Maßstab 1,8, drei Farbpaare.
  const SM_PAAR = [['#FF9A3C', '#FFD76A'], ['#5FA8FF', '#BFE0FF'], ['#F08AD0', '#FFD0EE']];
  N.art('schmetterling', {
    baue(ctx, z) {
      const W = ctx.W, H = ctx.H, D = 9;
      const y = rnd(z, 0.1, 0.24) * H, links = z() < 0.5;
      const p0 = { x: links ? -30 : W + 30, y }, p1 = { x: links ? W + 30 : -30, y: y + rnd(z, -0.05, 0.08) * H };
      const bob = rnd(z, 0, 6.283);
      const pal = SM_PAAR[Math.floor(z() * SM_PAAR.length) % SM_PAAR.length];
      const fl = (s, cls, cx, cy, rx, ry, c) => '<g class="' + cls + '" style="transform-origin:' + cx * s + 'px ' + cy + 'px"><ellipse cx="' + cx * s + '" cy="' + cy + '" rx="' + rx + '" ry="' + ry + '" fill="' + c + '" stroke="' + INK + '" stroke-width="1.2"/>'
        + '<circle cx="' + (cx + rx * 0.35) * s + '" cy="' + (cy - ry * 0.15) + '" r="' + (ry * 0.28).toFixed(1) + '" fill="#fff" fill-opacity=".55"/></g>';
      let inner = '';
      [-1, 1].forEach(s => { inner += fl(s, 'nt-sm-u' + (s < 0 ? 'l' : 'r'), 5, 6, 6, 5.5, pal[1]); });
      [-1, 1].forEach(s => { inner += fl(s, 'nt-sm-o' + (s < 0 ? 'l' : 'r'), 7, -5, 9, 8, pal[0]); });
      inner += '<path d="M0 -8 L0 9" stroke="' + INK + '" stroke-width="2.6" stroke-linecap="round"/>'
        + '<path class="nt-sm-fh" d="M0 -8 L5 -15 M0 -8 L-1 -15" fill="none" stroke="' + INK + '" stroke-width="1" stroke-linecap="round"/>';
      const root = el('div', 'nt-sm', svg('nt-sm-s', -18, -18, 36, 34, inner));
      const k = q(root, '.nt-sm-s'), fh = q(root, '.nt-sm-fh');
      const wings = ['.nt-sm-ul', '.nt-sm-ur', '.nt-sm-ol', '.nt-sm-or'].map(s => q(root, s));
      const bahn = u => ({ x: lerp(p0.x, p1.x, u), y: lerp(p0.y, p1.y, u) + Math.sin(u * 6.283 * 3 + bob) * 22 + Math.sin(u * 6.283 * 7) * 5 });
      const inst = {
        el: root, dauer: D, t: 0, weg: null,
        pose(tt) {
          const u = klemme(tt / D, 0, 1), p = bahn(u), v = bahn(Math.min(u + 0.01, 1));
          let op = Math.min(1, u * 12, (1 - u) * 12);
          if (this.weg && tt >= this.weg.at) op *= 1 - klemme((tt - this.weg.at) / 0.4, 0, 1);
          return { x: p.x, y: p.y, face: v.x - p.x >= 0 ? 1 : -1, flap: Math.max(0.06, Math.abs(Math.cos(tt * 14))), op };
        },
        stelle(tt) {
          this.t = tt;
          const p = this.pose(tt);
          setz(k, p.x, p.y, 0, 1.8, 1.8, p.op);
          wings.forEach(w => tf(w, 'scaleX(' + p.flap.toFixed(3) + ')'));
          tf(fh, 'scaleX(' + p.face + ')');
        },
        hulle(tt) { const p = this.pose(tt); return p.op < 0.03 ? null : kasten(p.x, p.y, 58, 50); },
        abgang() { if (!this.weg) this.weg = { at: this.t }; return 0.4; },
      };
      return inst;
    },
  });

  /* ---------- Hilfen für Hoppelhase und Strand (1.6.15) ---------- */
  const TAU = Math.PI * 2;
  const n1 = v => String(Math.round(v * 10) / 10);

  /* ======================================================================== 12 Hoppelhase (1.6.15) */
  // Nutzerwunsch 23.10.2026: „Ein Hoppelhase hüpft durch das Bild“. Wie die App (nature_day.gd Hoppelhase): hüpft von einer Seite auf den
  // Plattformrand, vorn herum zur anderen Seite (Ducken, Strecken, Landen), zwei Pausen (Männchen, Ohrenzucken), hüpft hinaus.
  // Antippen: Schreck-Sprung mit aufgestellten Ohren, danach schnell davon. Seitenansicht, Blick nach rechts (+x), Ursprung an den Füßen.
  const HH_GR = 1.6;
  const HH = { fell: '#D3AE87', fellD: '#B38B64', bauch: '#F8EDDC', ohr: '#F5A9BC', nase: '#EE7499' };
  // Ohr als Ellipse ab dem Ansatz b in Richtung w (Grad), Länge l, Breite d
  const hhOhr = (b, w, l, d, fill, rand) => {
    const cx = b[0] + Math.cos(w * RAD) * l / 2, cy = b[1] + Math.sin(w * RAD) * l / 2;
    return '<ellipse cx="' + cx.toFixed(1) + '" cy="' + cy.toFixed(1) + '" rx="' + (l / 2).toFixed(1) + '" ry="' + (d / 2).toFixed(1) + '" transform="rotate(' + w.toFixed(1) + ' ' + cx.toFixed(1) + ' ' + cy.toFixed(1) + ')" fill="' + fill + '"'
      + (rand ? ' stroke="' + INK + '" stroke-width="1.3"' : '') + '/>';
  };
  const HH_SVG = '<g class="nt-hh-oh">' + hhOhr([6.5, -28], -112, 16, 7, HH.fellD, true) + '</g>'
    + '<circle cx="-15" cy="-12" r="5.4" fill="' + HH.bauch + '" stroke="' + INK + '" stroke-width="1.2"/><circle cx="-17" cy="-14" r="2.6" fill="#fff"/>'
    + '<ellipse cx="-7" cy="-8" rx="8.6" ry="7.4" transform="rotate(-11 -7 -8)" fill="' + HH.fellD + '" stroke="' + INK + '" stroke-width="1.3"/>'
    + '<ellipse class="nt-hh-fuss" cx="-4" cy="-1.8" rx="9.2" ry="3" fill="' + HH.fell + '" stroke="' + INK + '" stroke-width="1.2"/>'
    + '<ellipse cx="-1" cy="-12.5" rx="13.5" ry="10.5" transform="rotate(-11 -1 -12.5)" fill="' + HH.fell + '" stroke="' + INK + '" stroke-width="1.4"/>'
    + '<ellipse cx="5" cy="-9" rx="6.4" ry="5.2" transform="rotate(-17 5 -9)" fill="' + HH.bauch + '"/>'
    + '<path d="M-12.4,-12.6 A7.6,6.4 0 0 1 -2.6,-15.4" fill="none" stroke="' + INK + '" stroke-opacity=".55" stroke-width="1.1"/>'
    + '<ellipse class="nt-hh-pf" cx="8" cy="-1.8" rx="3.3" ry="2.3" fill="' + HH.fell + '" stroke="' + INK + '" stroke-width="1.1"/>'
    + '<ellipse cx="10.5" cy="-21" rx="9.8" ry="9.2" fill="' + HH.fell + '" stroke="' + INK + '" stroke-width="1.4"/>'
    + '<ellipse cx="16.4" cy="-17.8" rx="4.8" ry="3.6" fill="' + HH.bauch + '"/>'
    + '<circle cx="13.6" cy="-16.8" r="2.7" fill="#FF8CAD" fill-opacity=".38"/>'
    + '<g class="nt-hh-au"><ellipse cx="13.4" cy="-22.8" rx="2.2" ry="2.8" fill="' + INK + '"/><circle cx="14.2" cy="-23.9" r="1" fill="#fff"/><circle cx="12.9" cy="-21.7" r=".45" fill="#fff" fill-opacity=".8"/></g>'
    + '<circle class="nt-hh-na" cx="20.6" cy="-19.2" r="1.6" fill="' + HH.nase + '"/>'
    + '<path d="M18,-18.4 L24.5,-19.8 M18,-17.3 L24.5,-17.6" stroke="' + INK + '" stroke-opacity=".45" stroke-width=".7" stroke-linecap="round"/>'
    + '<g class="nt-hh-ov">' + hhOhr([9, -28.6], -92.8, 17, 7.6, HH.fell, true) + hhOhr([9.3, -30.2], -92.8, 12.5, 3.6, HH.ohr, false) + '</g>';
  N.stil('hoppelhase', [
    '.nt-hh-ov{transform-origin:9px -28.6px}',
    '.nt-hh-oh{transform-origin:6.5px -28px}',
    '.nt-hh-au{transform-origin:13.4px -22.8px}',
  ].join('\n'));
  N.art('hoppelhase', {
    baue(ctx, z) {
      const e = ctx.eintrag, D0 = rnd(z, e.dauer[0], e.dauer[1]);
      const Q = 0.62, HOP = 0.42, REST = 0.1, SCHRECK = 0.55, FLUCHT = 0.3;
      const lr = leiste();
      const hind = (ctx.schutz || []).filter(r => r.name !== 'hand').concat(lr ? [lr] : []);
      const bedeckt = r => Math.min(1, hind.reduce((s, h) => s + flaeche(r, h), 0) / (r.w * r.h));
      const g0 = ctx.ort && typeof ctx.ort.grad === 'number' ? ctx.ort.grad : 140;
      // Weg: von einer Seite vorn herum zur anderen; die Seite des Ankers zuerst, sonst die freiere
      let a0 = 168, a1 = 12, bk = Infinity;
      [170, 164, 158, 10, 16, 22].forEach(st => [10, 16, 22, 28].forEach(en => {
        const ee = st > 90 ? en : 180 - en;
        let k = 0;
        for (let m = 0; m < 16; m++) { const p = ctx.band(lerp(st, ee, (m + 0.5) / 16), Q); k += bedeckt(kasten(p.x, p.y - 26, 60, 58)); }
        k = k / 16 + ((st > 90) === (g0 > 90) ? 0 : 0.04) + Math.abs(Math.abs(ee - st) - 160) * 0.0004 + z() * 0.01;
        if (k < bk) { bk = k; a0 = st; a1 = ee; }
      }));
      const weg = bandWeg(ctx, a0, a1, Q), L = weg.L;
      const pA = weg.an(0), pE = weg.an(L);
      const norm = (p) => { const dx = p.x - ctx.cx, dy = p.y - ctx.cy, l = Math.hypot(dx, dy) || 1; return { x: dx / l, y: dy / l }; };
      const vA = norm(pA), vE = norm(pE);
      const pause = [rnd(z, 1.1, 1.5), rnd(z, 1.0, 1.4)];
      let n = Math.max(6, Math.floor((D0 - 3 * HOP - pause[0] - pause[1]) / (HOP + REST)));
      let hl = klemme(L / n, 40, 84);
      n = Math.max(3, Math.ceil(L / hl)); hl = L / n;
      const pausenBei = [0.33, 0.68].map(f => {
        let bi = klemme(Math.round(n * f), 1, n - 1);
        for (const dj of [0, 1, -1, 2, -2]) { const j = klemme(bi + dj, 1, n - 1), p = weg.an(hl * j); if (bedeckt(kasten(p.x, p.y - 26, 60, 58)) < 0.2) { bi = j; break; } }
        return bi;
      });
      const pt = p => ({ x: p.x, y: p.y });
      const akt = [];
      let t = 0;
      const dazu = (art, d, p0, p1, x) => { akt.push({ t0: t, t1: t + d, art, p0, p1, x: x || '' }); t += d; };
      const pIn = { x: pA.x + vA.x * 60, y: pA.y + vA.y * 60 };
      dazu('hop', HOP, pIn, pt(pA));
      let s = 0;
      for (let i = 0; i < n; i++) {
        dazu('rest', REST, pt(weg.an(s)), pt(weg.an(s)));
        dazu('hop', HOP, pt(weg.an(s)), pt(weg.an(s + hl)));
        s += hl;
        const pz = pausenBei.indexOf(i + 1);
        if (pz >= 0) dazu('pause', pause[pz], pt(weg.an(s)), pt(weg.an(s)), pz === 0 ? 'maennchen' : 'ohren');
      }
      const pOut = { x: pE.x + vE.x * 62, y: pE.y + vE.y * 62 };
      dazu('rest', REST, pt(pE), pt(pE));
      dazu('hop', HOP, pt(pE), pOut);
      const tFade = t;
      dazu('hop', HOP, pOut, { x: pOut.x + vE.x * 62, y: pOut.y + vE.y * 62 });
      const D = t;
      const root = el('div', 'nt-hh', svg('nt-hh-sch', -22, -6, 44, 12, '<ellipse cx="0" cy="0" rx="18" ry="4.5" fill="' + INK + '" fill-opacity=".18"/>')
        + svg('nt-hh-s', -26, -50, 56, 54, HH_SVG));
      const sch = q(root, '.nt-hh-sch'), hase = q(root, '.nt-hh-s'), ov = q(root, '.nt-hh-ov'), oh = q(root, '.nt-hh-oh'), au = q(root, '.nt-hh-au'), na = q(root, '.nt-hh-na');
      const hupf = (p0, p1, u, h) => {
        const dx = p1.x - p0.x, dy = p1.y - p0.y, face = dx >= 0 ? 1 : -1;
        const neig = klemme(Math.atan2(dy * face, Math.abs(dx) + 0.001), -0.45, 0.45);
        if (u < 0.18) { const w = u / 0.18; return { x: p0.x, y: p0.y, hoch: 0, sy: 1 - 0.2 * Math.sin(Math.PI / 2 * w), sx: 1 + 0.12 * Math.sin(Math.PI / 2 * w), kipp: neig + 0.06 * w, ohr: 0.15 * w, face }; }
        if (u < 0.82) {
          const v = (u - 0.18) / 0.64, e2 = glatt(v), sy = 1 + 0.16 * Math.pow(1 - v, 2) + 0.06 * Math.pow(v, 3);
          return { x: lerp(p0.x, p1.x, e2), y: lerp(p0.y, p1.y, e2), hoch: h * Math.sin(Math.PI * v), sy, sx: 1 / Math.sqrt(sy), kipp: neig - 0.3 * Math.cos(Math.PI * v), ohr: 0.15 + 0.45 * Math.sin(Math.PI * v), face };
        }
        const w = (u - 0.82) / 0.18;
        return { x: p1.x, y: p1.y, hoch: 0, sy: 1 - 0.16 * Math.sin(Math.PI * w), sx: 1 + 0.1 * Math.sin(Math.PI * w), kipp: neig * (1 - 0.3 * w), ohr: 0.3 * (1 - w), face };
      };
      const grund = tt => {
        let i = akt.findIndex(a => tt < a.t1);
        if (i < 0) i = akt.length - 1;
        const a = akt[i], u = klemme((tt - a.t0) / Math.max(1e-4, a.t1 - a.t0), 0, 1);
        let r;
        if (a.art === 'hop') r = hupf(a.p0, a.p1, u, 0.42 * hl + 6);
        else {
          const nx = i + 1 < akt.length ? akt[i + 1].p1 : { x: a.p0.x + vE.x, y: a.p0.y + vE.y };
          const dx = nx.x - a.p0.x, dy = nx.y - a.p0.y, face = dx >= 0 ? 1 : -1;
          r = { x: a.p0.x, y: a.p0.y, hoch: 0, sx: 1, sy: 1, kipp: klemme(Math.atan2(dy * face, Math.abs(dx) + 0.001), -0.45, 0.45), ohr: 0, face };
        }
        r.zuck = 0; r.sitz = 0; r.schnupp = 0; r.schreck = 0;
        if (a.art === 'pause') {
          const lt = tt - a.t0, len = a.t1 - a.t0;
          r.schnupp = 1;
          const b = x => Math.sin(Math.PI * klemme(x, 0, 1));
          if (a.x === 'maennchen') { r.sitz = glatt(lt / 0.25) * (1 - glatt((lt - len + 0.25) / 0.25)); r.zuck = 0.35 * Math.sin(lt * 22) * b((lt - 0.4) / 0.35); }
          else r.zuck = 0.4 * Math.sin(lt * 24) * (b((lt - 0.15) / 0.3) + b((lt - 0.7) / 0.3));
        }
        r.a = a;
        return r;
      };
      const inst = { el: root, dauer: D, t: 0, tap: null, weg: null };
      inst.pose = tt => {
        const tp = inst.tap;
        let r;
        if (tp && tt >= tp.at) {
          const k = tt - tp.at;
          if (k < SCHRECK) {
            const u = k / SCHRECK, sy = u < 0.5 ? 1.18 - 0.18 * u : 1 + 0.1 * Math.sin(Math.PI * (u - 0.5) * 2);
            r = { x: tp.p.x, y: tp.p.y, hoch: 66 * Math.sin(Math.PI * u), sy, sx: 1 / Math.sqrt(sy), kipp: -0.35 * Math.sin(Math.PI * u) + 0.12 * Math.sin(u * 40) * (1 - u),
              ohr: -0.55 * Math.sin(Math.PI * klemme(u * 1.4, 0, 1)), face: tp.dir.x >= 0 ? 1 : -1, zuck: 0, sitz: 0, schnupp: 0, schreck: Math.sin(Math.PI * klemme(u * 1.2, 0, 1)) };
          } else {
            const k2 = k - SCHRECK, i = Math.floor(k2 / FLUCHT), u = (k2 % FLUCHT) / FLUCHT;
            const st = { x: tp.dir.x * hl * 1.5, y: tp.dir.y * hl * 1.5 }, p0 = { x: tp.p.x + st.x * i, y: tp.p.y + st.y * i };
            r = hupf(p0, { x: p0.x + st.x, y: p0.y + st.y }, u, 0.5 * hl + 8);
            r.ohr = 0.6; r.zuck = 0; r.sitz = 0; r.schnupp = 0; r.schreck = 0;
          }
          r.op = 1 - klemme((k - SCHRECK - FLUCHT * 1.2) / (FLUCHT * 1.8), 0, 1);
        } else {
          r = grund(tt);
          r.op = Math.min(klemme(tt / (HOP * 0.7), 0, 1), 1 - klemme((tt - tFade) / HOP, 0, 1));
        }
        if (inst.weg && tt >= inst.weg.at) r.op *= 1 - klemme((tt - inst.weg.at) / 0.4, 0, 1);
        return r;
      };
      inst.stelle = tt => {
        inst.t = tt;
        const r = inst.pose(tt);
        setz(hase, r.x, r.y - r.hoch, (r.kipp - 0.5 * r.sitz) / RAD, r.face * r.sx * HH_GR, r.sy * HH_GR, r.op);
        dreh(ov, (r.ohr + r.zuck - 0.2 * r.sitz) / RAD);
        dreh(oh, (r.ohr - 0.25 * r.sitz) / RAD);
        dreh(au, 0, 0, 0, 1 + 0.35 * r.schreck);
        tf(na, 'translate(0px,' + (r.schnupp ? 0.5 * Math.sin(tt * 30) : 0).toFixed(2) + 'px)');
        setz(sch, r.x, r.y + 2, 0, 1 - 0.4 * klemme(r.hoch / 70, 0, 1), 1, r.op * (1 - 0.6 * klemme(r.hoch / 60, 0, 1)));
      };
      inst.hulle = tt => { const r = inst.pose(tt); return r.op < 0.03 ? null : kasten(r.x, r.y - r.hoch - 19 * HH_GR, 42 * HH_GR, 42 * HH_GR); };
      inst.tipp = () => {
        if (inst.tap) return;
        const r = grund(inst.t), a = r.a;
        let dx = a.p1.x - a.p0.x, dy = a.p1.y - a.p0.y, l = Math.hypot(dx, dy);
        if (l < 1) { dx = r.face; dy = 0; l = 1; }
        inst.tap = { at: inst.t, p: { x: r.x, y: r.y }, dir: { x: dx / l, y: dy / l } };
        inst.dauer = inst.t + SCHRECK + FLUCHT * 3 + 0.05;
      };
      inst.abgang = () => { if (!inst.weg) inst.weg = { at: inst.t }; return 0.4; };
      return inst;
    },
  });

  /* ======================================================================== 13 Strand mit Palme (1.6.15) */
  // Nutzerwunsch 23.10.2026: „In der unteren rechten Ecke kommt mit einer Welle für ein paar Sekunden ein Strand ins Bild und eine Palme
  // wächst“. Wie die App (nature_day.gd Strand): Welle aus der Ecke, Sand bleibt zurück, Meer in der Ecke, Palme wächst Stück für Stück,
  // Wedel entfalten sich, sie wiegt sich; eine große Welle spült alles weg. Ebene hinten: Hand (#hand-zone) und Mau-Knopf liegen darüber.
  // Die Palme steht zwischen Hand und Mau-Knopf (rechts 46, unten 40, 150 × 150), die Krone darüber. Antippen der Palme: sie schüttelt
  // sich, eine Kokosnuss fällt. SVG mit Ursprung in der Ecke; Sand und Meer wachsen per scale um die Ecke.
  const ST = { meer: '#2FBFD2', meerHell: '#86E6EF', sand: '#F3CC86', sandD: '#D9A85E', nass: '#D2A061', stamm: '#B47D46', stammD: '#7E5329',
    blatt: '#3DBB6A', blattHell: '#5FD486', nuss: '#7A4A22', stern: '#FF8A5B', muschel: '#FFC9D6' };
  const ST_WEDEL = [[-178, 86, 42], [-152, 82, 24], [-124, 66, 10], [-95, 56, 2], [-64, 64, 8], [-36, 80, 22], [-10, 86, 38], [16, 72, 44]];
  N.art('strand', {
    baue(ctx, z) {
      const W = ctx.W, H = ctx.H, e = ctx.eintrag, D = rnd(z, e.dauer[0], e.dauer[1]);
      const o = ctx.ort && typeof ctx.ort.x === 'number' ? ctx.ort : { x: W, y: H, mau: null };
      const P = { x: o.x, y: o.y }, RX = 410, RY = 245, SEA = 0.5, T_IN = 1.0, T_BACK = 1.8, T_WASH = D - 1.7, SEGS = 8;
      let bx = P.x - 233;
      if (o.mau) bx = Math.min(bx, o.mau.x - 34);
      const B = { x: bx - P.x, y: -52 }, TH = 250;   // Fuß der Palme (relativ zur Ecke)
      const TOP = { x: B.x + 16, y: B.y - TH }, CT = { x: B.x - 38, y: B.y - 0.55 * TH };
      const ph = z() * TAU;
      // Strand-Form (Viertel-Ellipse um die Ecke mit leichtem Wellenrand), Radius r als Anteil
      const rand = (r, wob, ph2) => { const pts = []; for (let i = 0; i <= 24; i++) { const th = Math.PI + Math.PI / 2 * i / 24, w = 1 + wob * Math.sin(5 * th + ph + (ph2 || 0)); pts.push([Math.cos(th) * RX * r * w, Math.sin(th) * RY * r * w]); } return pts; };
      const P2 = a => a.map(p => n1(p[0]) + ',' + n1(p[1])).join(' L');
      const form = (r, wob, ph2) => 'M' + n1(-RX * r * 1.2 - 20) + ',4 L' + P2(rand(r, wob, ph2)) + ' L4,' + n1(-RY * r * 1.2 - 20) + ' L4,4 Z';
      const linie = (r, wob, ph2) => 'M' + P2(rand(r, wob, ph2));
      // Sandkörnchen und Schaumbläschen als runde Punkte (Linien der Länge 0)
      let koerner = '';
      for (let i = 0; i < 16; i++) { const th = rnd(z, Math.PI * 1.03, Math.PI * 1.47), r = rnd(z, SEA + 0.08, 0.95); koerner += 'M' + n1(Math.cos(th) * RX * r) + ',' + n1(Math.sin(th) * RY * r) + ' l0,0 '; }
      let blasen = '';
      for (let i = 0; i < 9; i++) { const th = Math.PI + Math.PI / 2 * (i + 0.5) / 9; blasen += 'M' + n1(Math.cos(th) * (RX + 3)) + ',' + n1(Math.sin(th) * (RY + 3)) + ' l0,0 '; }
      // Stamm: Stücke entlang der Bezierkurve (lokal: Fuß der Palme = 0,0)
      const kurve = f => bez2({ x: 0, y: 0 }, { x: CT.x - B.x, y: CT.y - B.y }, { x: TOP.x - B.x, y: TOP.y - B.y }, f);
      let stamm = '';
      for (let j = 0; j < SEGS; j++) {
        const p0 = kurve(j / SEGS), p1 = kurve((j + 1) / SEGS), w0 = lerp(9, 6, j / SEGS), w1 = lerp(9, 6, (j + 1) / SEGS) * 1.12;
        const l = Math.hypot(p1.x - p0.x, p1.y - p0.y), wn = Math.atan2(p1.y - p0.y, p1.x - p0.x) / RAD + 90;
        stamm += '<path class="nt-st-sg" data-tr="translate(' + n1(p0.x) + ' ' + n1(p0.y) + ') rotate(' + n1(wn) + ')" transform="translate(' + n1(p0.x) + ' ' + n1(p0.y) + ') rotate(' + n1(wn) + ') scale(1 0)" d="M' + (-w0) + ',0 L' + n1(-w1) + ',' + n1(-l) + ' L' + n1(w1) + ',' + n1(-l) + ' L' + w0 + ',0 Z" fill="' + ST.stamm + '" stroke="' + INK + '" stroke-opacity=".85" stroke-width="1.3" stroke-linejoin="round"/>';
      }
      // Wedel: Blatt mit gezackter Unterkante, in Endlage gezeichnet; die Gruppe dreht und wächst beim Entfalten
      const wedel = ST_WEDEL.map((wd, i) => {
        const a = wd[0] * RAD, ln = wd[1], dr = wd[2], d = { x: Math.cos(a), y: Math.sin(a) };
        const tip = { x: d.x * ln, y: d.y * ln + dr }, cp = { x: d.x * ln * 0.55, y: d.y * ln * 0.55 - ln * 0.22 };
        const mid = []; for (let j = 0; j <= 8; j++) mid.push(bez2({ x: 0, y: 0 }, cp, tip, j / 8));
        const up = [], dn = [];
        mid.forEach((m, j) => {
          const f = j / 8, a2 = mid[Math.min(j + 1, 8)], b2 = mid[Math.max(j - 1, 0)], tl = Math.hypot(a2.x - b2.x, a2.y - b2.y) || 1;
          const nx = -(a2.y - b2.y) / tl, ny = (a2.x - b2.x) / tl, w = 13 * Math.sin(Math.PI * Math.min(f * 1.12, 1)) * (0.55 + 0.45 * (1 - f));
          up.push([m.x + nx * w * 0.6, m.y + ny * w * 0.6]); dn.push([m.x - nx * w * (j % 2 ? 0.5 : 1), m.y - ny * w * (j % 2 ? 0.5 : 1)]);
        });
        return '<g class="nt-st-wd" data-w="' + wd[0] + '"><path d="M' + P2(up) + ' L' + P2(dn.reverse()) + ' Z" fill="' + (i % 2 ? ST.blatt : ST.blattHell) + '" stroke="' + INK + '" stroke-opacity=".85" stroke-width="1.2" stroke-linejoin="round"/>'
          + '<path d="M' + mid.map(m => n1(m.x) + ',' + n1(m.y)).join(' L') + '" fill="none" stroke="#227F44" stroke-width="1.5"/></g>';
      });
      const nuss = (x, y, cls) => '<g class="' + cls + '" transform="translate(' + x + ' ' + y + ')"><circle r="5.6" fill="' + ST.nuss + '" stroke="' + INK + '" stroke-opacity=".8" stroke-width="1.1"/><circle cx="-1.8" cy="-1.8" r="1.4" fill="#fff" fill-opacity=".35"/></g>';
      const stern = (() => { let s = ''; for (let i = 0; i < 10; i++) { const a = -Math.PI / 2 + TAU * i / 10 + 0.2, r = i % 2 ? 4.3 : 9.5; s += (i ? ' L' : 'M') + n1(Math.cos(a) * r) + ',' + n1(Math.sin(a) * r); } return s + ' Z'; })();
      const STERN = { x: B.x - 52, y: -26 }, MUSCHEL = { x: -128, y: -212 };
      const html = svg('nt-st-s', -RX * 1.3 - 30, -TH - 140, RX * 1.3 + 40, TH + 150,
        '<g class="nt-st-sa" transform="scale(0)"><path d="' + form(1, 0.025) + '" transform="translate(-3 -3)" fill="' + INK + '" fill-opacity=".07"/>'
        + '<path d="' + form(1, 0.025) + '" fill="' + ST.sand + '"/>'
        + '<path class="nt-st-na" d="' + form(1, 0.025) + '" fill="' + ST.nass + '" fill-opacity=".5"/>'
        + '<path d="' + linie(1, 0.025) + '" fill="none" stroke="' + INK + '" stroke-opacity=".5" stroke-width="1.6" vector-effect="non-scaling-stroke"/>'
        + '<path d="' + koerner + '" stroke="' + ST.sandD + '" stroke-opacity=".75" stroke-width="2.8" stroke-linecap="round" vector-effect="non-scaling-stroke"/></g>'
        + '<g class="nt-st-deko" style="opacity:0"><path d="' + stern + '" transform="translate(' + n1(STERN.x) + ' ' + STERN.y + ')" fill="' + ST.stern + '" stroke="' + INK + '" stroke-opacity=".8" stroke-width="1.1" stroke-linejoin="round"/>'
        + '<path d="M0,3.9 L-7,0 A7,5.6 0 0 1 7,0 Z" transform="translate(' + MUSCHEL.x + ' ' + MUSCHEL.y + ')" fill="' + ST.muschel + '" stroke="' + INK + '" stroke-opacity=".75" stroke-width="1"/></g>'
        + '<g class="nt-st-me" transform="scale(0)"><path d="' + form(1, 0.03) + '" fill="' + ST.meerHell + '" fill-opacity=".95"/>'
        + '<path d="' + form(0.86, 0.03, 0.6) + '" fill="' + ST.meer + '" fill-opacity=".95"/>'
        + '<path d="' + linie(0.66, 0.04, 1.7) + '" fill="none" stroke="#fff" stroke-opacity=".35" stroke-width="2" vector-effect="non-scaling-stroke"/>'
        + '<path d="' + linie(1, 0.03) + '" fill="none" stroke="#fff" stroke-opacity=".95" stroke-width="4" stroke-linecap="round" vector-effect="non-scaling-stroke"/>'
        + '<path d="' + blasen + '" stroke="#fff" stroke-opacity=".9" stroke-width="5.5" stroke-linecap="round" vector-effect="non-scaling-stroke"/></g>'
        + '<g class="nt-st-pa" style="opacity:0" transform="translate(' + n1(B.x) + ' ' + B.y + ')">' + stamm
        + '<g class="nt-st-kr" transform="translate(' + n1(TOP.x - B.x) + ' ' + n1(TOP.y - B.y) + ')"><g class="nt-st-nu" style="opacity:0">' + nuss(-6, 8, '') + nuss(5, 9, 'nt-st-n1') + nuss(-1, 14, '') + '</g>' + wedel.join('') + '</g></g>'
        + '<g class="nt-st-fa" style="opacity:0">' + nuss(0, 0, '') + '</g>');
      const root = el('div', 'nt-st', html);
      const sv = q(root, '.nt-st-s'), sa = q(root, '.nt-st-sa'), na = q(root, '.nt-st-na'), me = q(root, '.nt-st-me'), deko = q(root, '.nt-st-deko');
      const pa = q(root, '.nt-st-pa'), kr = q(root, '.nt-st-kr'), nu = q(root, '.nt-st-nu'), n1el = q(root, '.nt-st-n1'), fa = q(root, '.nt-st-fa');
      const sg = qa(root, '.nt-st-sg'), wd = qa(root, '.nt-st-wd');
      const T2 = (e2, s) => { if (e2._ntT !== s) { e2._ntT = s; e2.setAttribute('transform', s); } };
      const inst = { el: root, dauer: D, t: 0, tapT: null, weg: null };
      inst.pose = tt => {
        let meer, wasser = 1;
        if (tt < T_IN) meer = 1.08 * aus(tt / T_IN);
        else if (tt < T_BACK) meer = lerp(1.08, SEA, glatt((tt - T_IN) / (T_BACK - T_IN)));
        else if (tt < T_WASH) meer = SEA + 0.035 * Math.sin(6.283 * (tt - T_BACK) / 1.7) * klemme((tt - T_BACK) / 0.4, 0, 1);
        else if (tt < T_WASH + 0.7) meer = lerp(SEA + 0.035 * Math.sin(6.283 * (T_WASH - T_BACK) / 1.7), 1.18, aus((tt - T_WASH) / 0.7));
        else { meer = lerp(1.18, 0, glatt((tt - T_WASH - 0.7) / Math.max(0.1, D - T_WASH - 0.75))); wasser = 1 - klemme((tt - (D - 0.45)) / 0.45, 0, 1); }
        let sand = tt < T_IN ? Math.min(1, meer * 0.96) : 1;
        if (tt > T_WASH + 0.55) sand = 0;
        const nass = tt >= T_IN ? 1 - klemme((tt - T_BACK) / 1.6, 0, 1) : 0;
        const wachs = klemme((tt - 1.7) / 1.0, 0, 1), blaetter = klemme((tt - 2.5) / 0.8, 0, 1);
        let wieg = 0.05 * Math.sin(6.283 * tt / 2.6 + ph) * blaetter, nussT = -1;
        if (inst.tapT !== null && tt >= inst.tapT) { const s = tt - inst.tapT; wieg += 0.24 * Math.exp(-1.7 * s) * Math.sin(6.283 * 1.5 * s); nussT = s; }
        let palme = wachs > 0 ? 1 : 0, kipp = 0;
        const hitT = T_WASH + 0.32;
        if (tt > hitT) { const u = klemme((tt - hitT) / 0.45, 0, 1); kipp = glatt(u); palme = 1 - u; }
        let op = 1;
        if (inst.weg && tt >= inst.weg.at) op = 1 - klemme((tt - inst.weg.at) / 0.4, 0, 1);
        return { meer, wasser, sand, nass, wachs, blaetter, wieg, nussT, palme, kipp, op };
      };
      // Hülle der Palme (Bühnen-px), sonst Strand/Meer
      const palmHulle = p => {
        const x0 = P.x + B.x - 100, x1 = P.x + B.x + 105, y0 = P.y + TOP.y - 55;
        return p.blaetter > 0 ? { x: x0, y: y0, w: x1 - x0, h: P.y + B.y + 6 - y0 } : { x: P.x + B.x - 14, y: P.y + B.y - TH * p.wachs - 10, w: 40, h: TH * p.wachs + 16 };
      };
      inst.stelle = tt => {
        inst.t = tt;
        const p = inst.pose(tt);
        setz(sv, P.x, P.y, 0, 1, 1, p.op);
        T2(sa, 'scale(' + Math.max(0.001, p.sand).toFixed(3) + ')');
        deck(sa, p.sand > 0.02 ? 1 : 0);
        deck(na, p.nass);
        deck(deko, p.sand >= 0.99 ? 1 : 0);
        T2(me, 'scale(' + Math.max(0.001, p.meer).toFixed(3) + ')');
        deck(me, p.meer > 0.02 ? 0.98 * p.wasser : 0);
        deck(pa, p.palme);
        T2(pa, 'translate(' + n1(B.x) + ' ' + B.y + ') rotate(' + n1(-43 * p.kipp) + ')');
        const nv = p.wachs * SEGS;
        sg.forEach((e2, j) => { const pop = klemme(nv - j, 0, 1); T2(e2, e2.dataset.tr + ' scale(' + (0.75 + 0.25 * pop).toFixed(3) + ' ' + pop.toFixed(3) + ')'); });
        T2(kr, 'translate(' + n1(TOP.x - B.x + TH * 0.06 * Math.sin(p.wieg)) + ' ' + n1(TOP.y - B.y) + ') rotate(' + n1(p.wieg / RAD * 1.4) + ')');
        deck(kr, p.blaetter > 0 ? 1 : 0);
        deck(nu, klemme((p.blaetter - 0.5) / 0.4, 0, 1));
        deck(n1el, p.nussT >= 0 ? 0 : 1);
        wd.forEach((e2, i) => {
          const ee = aus(klemme((p.blaetter - i * 0.04) / 0.72, 0, 1)), w0 = +e2.dataset.w;
          T2(e2, 'rotate(' + n1((-90 - w0) * (1 - ee)) + ') scale(' + lerp(0.25, 1, ee).toFixed(3) + ')');
        });
        if (p.nussT >= 0) {
          // Kokosnuss fällt vom Kronenansatz auf den Sand, hüpft einmal, rollt ein Stück
          const sx = P.x + TOP.x + 5 + TH * 0.06 * Math.sin(p.wieg), sy = P.y + TOP.y + 9, gy = P.y + B.y - 4, fh = Math.max(1, gy - sy), tf2 = Math.sqrt(2 * fh / 900);
          let x = sx, y = sy, rot = 0;
          if (p.nussT < tf2) y = sy + 450 * p.nussT * p.nussT;
          else { const b = p.nussT - tf2, bh = fh * 0.12; y = gy - (b < 0.3 ? 4 * bh * (b / 0.3) * (1 - b / 0.3) : 0); const r = aus((b - 0.05) / 0.7); x += 34 * r; rot = 350 * r; }
          setz(fa, x - P.x, y - P.y, rot, 1, 1, p.palme);
        } else deck(fa, 0);
      };
      inst.hulle = tt => {
        const p = inst.pose(tt);
        if (p.op < 0.03) return null;
        if (p.wachs > 0.25 && p.palme > 0.1) return palmHulle(p);
        const r = Math.max(p.meer, p.sand);
        if (r <= 0.02 || p.wasser <= 0.02) return null;
        const x0 = P.x - RX * r, y0 = P.y - RY * r;
        return { x: Math.max(0, x0), y: Math.max(0, y0), w: Math.min(W, P.x) - Math.max(0, x0), h: Math.min(H, P.y) - Math.max(0, y0) };
      };
      inst.treffer = pt2 => {
        const p = inst.pose(inst.t);
        if (p.wachs <= 0.25 || p.palme <= 0.1) return false;
        const h = palmHulle(p);
        return pt2.x >= h.x - 14 && pt2.x <= h.x + h.w + 14 && pt2.y >= h.y - 14 && pt2.y <= h.y + h.h + 14;
      };
      inst.tipp = () => { if (inst.tapT === null) inst.tapT = inst.t; };
      inst.abgang = () => { if (!inst.weg) inst.weg = { at: inst.t }; return 0.4; };
      return inst;
    },
  });
})(window.MMF = window.MMF || {});
