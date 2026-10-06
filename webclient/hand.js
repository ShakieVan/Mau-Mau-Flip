/* Mau-Mau Flip – Browser-Client „Lite“: die eigene Hand.
 * Bis ~14 Karten ein Fächer (jede Karte direkt antippbar), darüber ein waagerecht wischbares Band mit Schwung,
 * Gummiband und Einrasten. Antippen hebt an, zweites Tippen oder Wischen nach oben spielt aus, langes Drücken öffnet
 * die Kartenhilfe. Koordinaten in Logik-Pixeln der Bühne (Basis 1600×720 wie der Entwurf).
 */
(function (M) {
  'use strict';

  const KW = 190;                         // Kartenbreite in der Hand
  const KH = Math.round(KW * 870 / 560);  // 295
  const SICHTBAR = 146;                   // sichtbarer oberer Teil der Karte
  const BEWEGUNG = 9;                     // px bis zur Gestenentscheidung (Bildschirm-px)
  const HALTEN = 450;                     // ms bis zur Kartenhilfe
  const AUSSPIELEN = 105;                 // Logik-px nach oben zum Ausspielen
  const clamp = (v, a, b) => Math.max(a, Math.min(b, v));

  // Reine Layoutfunktion: n Karten auf einer Bühne der Größe W×H.
  // o: {scroll, gewaehlt, fokus, spielbar:Set<Index>, zug:{index, dy}, schwebend:Set<Index>}
  function layout(n, W, H, o) {
    o = o || {};
    const top = H - SICHTBAR, cx = W / 2;
    const breite = Math.max(640, W - 600);
    let step = n > 1 ? Math.min(106, (breite - KW) / (n - 1)) : 0;
    const band = n > 1 && step < 58;
    if (band) step = 66;
    const karten = [];
    for (let i = 0; i < n; i++) {
      let x, y, rot, sc = 1, op = 1, z = i;
      if (!band) {
        const t = i - (n - 1) / 2, tn = t * step / 72;
        x = cx + t * step;
        rot = clamp(tn * 2.6, -16, 16);
        y = top + Math.min(40, 0.9 * tn * tn);
      } else {
        const d = i - (o.scroll || 0);
        x = cx + d * step;
        const u = (x - cx) / (breite / 2);
        rot = clamp(u * 9, -14, 14);
        y = top + Math.min(60, 26 * u * u);
        sc = 1 - 0.06 * Math.min(1, u * u);
        const aus = Math.abs(x - cx) - breite / 2;
        op = aus <= -30 ? 1 : (aus >= 70 ? 0 : 1 - (aus + 30) / 100);
        z = i;
      }
      let heben = 0;
      if (o.spielbar && o.spielbar.has(i)) heben = 16;
      if (band && Math.abs(i - (o.scroll || 0)) < 0.5) heben = Math.max(heben, 10);
      if (o.fokus === i) { heben = Math.max(heben, 32); sc *= 1.08; z += 2000; }
      if (o.gewaehlt === i) { heben = 46; z += band ? 2000 : 0; }
      if (o.schwebend && o.schwebend.has(i)) { heben = 120; z += 3000; }
      y -= heben;
      if (o.zug && o.zug.index === i) { y += o.zug.dy; z += 4000; sc *= 1.04; }
      karten.push({ x, y, rot, sc, op, z });
    }
    return { karten, band, step, breite };
  }

  // Liegt Punkt (px, py) auf Karte k? (Drehpunkt unten Mitte)
  function trifft(k, px, py) {
    const ox = k.x, oy = k.y + KH;
    const a = -k.rot * Math.PI / 180;
    const dx = px - ox, dy = py - oy;
    const lx = (dx * Math.cos(a) - dy * Math.sin(a)) / k.sc, ly = (dx * Math.sin(a) + dy * Math.cos(a)) / k.sc;
    return lx >= -KW / 2 && lx <= KW / 2 && ly >= -KH && ly <= 0;
  }

  class Hand {
    // tisch: {buehne, W, H, s, zuBuehne(cx, cy)}, cb: {antippen(id), spielen(id), hilfe(face), leer()}
    constructor(tisch, cb) {
      this.t = tisch; this.cb = cb;
      this.el = document.createElement('div');
      this.el.id = 'hand';
      this.zone = document.createElement('div');
      this.zone.id = 'hand-zone';
      this.reihe = [];             // [{id, face, back}] in Anzeigereihenfolge
      this.els = new Map();        // id → Element
      this.scroll = 0;
      this.gewaehlt = null;
      this.fokus = null;
      this.spielbar = new Set();   // ids
      this.schwebend = new Set();  // ids, die gerade gespielt werden (optimistisch)
      this.zug = null;             // {id, dy}
      this.rueck = false;
      this.geste = null;
      this.letztesLayout = null;
      this._zeiger();
    }

    /* ---------- Daten ---------- */
    setze(reihe, opt) {
      const alt = new Set(this.reihe.map(c => c.id));
      this.reihe = reihe.slice();
      this.spielbar = new Set(opt.spielbar || []);
      this.kandidaten = new Set(opt.kandidaten || []);   // Farbe mit ablegen: wählbare Karten (gewählte stehen in spielbar)
      const jetzt = new Set(reihe.map(c => c.id));
      for (const [id, el] of this.els) if (!jetzt.has(id)) { el.remove(); this.els.delete(id); }
      for (const id of Array.from(this.schwebend)) if (!jetzt.has(id)) this.schwebend.delete(id);
      if (this.gewaehlt !== null && !jetzt.has(this.gewaehlt)) this.gewaehlt = null;
      const neu = [];
      reihe.forEach(c => {
        let el = this.els.get(c.id);
        if (!el) {
          el = document.createElement('div');
          el.className = 'karte hk';
          el.style.width = KW + 'px'; el.style.height = KH + 'px';
          el.dataset.id = c.id;
          el.innerHTML = '<div class="innen"><div class="seite vorn"></div><div class="seite hinten"></div></div>';
          this.el.appendChild(el);
          this.els.set(c.id, el);
          if (alt.size || opt.neuMarkieren) neu.push(c.id);
        }
        const vorn = el.firstChild.firstChild, hinten = el.firstChild.lastChild;
        if (vorn.dataset.face !== c.face) { vorn.dataset.face = c.face; vorn.innerHTML = M.Karten.gesichtHTML(c.face); }
        const back = c.back || 'rueckseite';
        if (hinten.dataset.face !== back) { hinten.dataset.face = back; hinten.innerHTML = M.Karten.gesichtHTML(back); }
        el.dataset.face = c.face;
        el.classList.toggle('spielbar', this.spielbar.has(c.id));
        el.classList.toggle('kandidat', this.kandidaten.has(c.id));
        el.classList.toggle('matt', !!opt.dran && !this.spielbar.has(c.id) && !this.kandidaten.has(c.id));
      });
      this.el.classList.toggle('dran', !!opt.dran);
      // neue Karten kurz markieren; im Band zur einzelnen neuen Karte rollen
      neu.forEach(id => { const el = this.els.get(id); el.classList.add('neu'); setTimeout(() => el.classList.remove('neu'), 2600); });
      const lay = layout(this.reihe.length, this.t.W, this.t.H, {});
      const warBand = !!(this.letztesLayout && this.letztesLayout.band);
      const g = this.grenzen(lay);
      if (lay.band && !warBand) this.scroll = g.lo;
      else if (lay.band && neu.length === 1) this.scroll = this.index(neu[0]);
      this.scroll = Math.round(clamp(this.scroll, g.lo, g.hi));
      this.ordne();
    }
    index(id) { return this.reihe.findIndex(c => c.id === id); }
    element(id) { return this.els.get(id) || null; }

    /* ---------- Layout ---------- */
    ordne(ohneUebergang) {
      const n = this.reihe.length;
      const sp = new Set(), sw = new Set();
      this.reihe.forEach((c, i) => { if (this.spielbar.has(c.id)) sp.add(i); if (this.schwebend.has(c.id)) sw.add(i); });
      const o = {
        scroll: this._scrollAnzeige(), spielbar: sp, schwebend: sw,
        gewaehlt: this.gewaehlt === null ? null : this.index(this.gewaehlt),
        fokus: this.fokus === null ? null : this.index(this.fokus),
        zug: this.zug ? { index: this.index(this.zug.id), dy: this.zug.dy } : null,
      };
      const lay = layout(n, this.t.W, this.t.H, o);
      this.letztesLayout = lay;
      this.el.classList.toggle('band', lay.band);
      this.el.classList.toggle('ohne-tr', !!ohneUebergang);
      this.reihe.forEach((c, i) => {
        const k = lay.karten[i], el = this.els.get(c.id);
        el.style.transform = 'translate(' + (k.x - KW / 2).toFixed(1) + 'px,' + k.y.toFixed(1) + 'px) rotate(' + k.rot.toFixed(2) + 'deg) scale(' + k.sc.toFixed(3) + ')';
        el.style.opacity = k.op < 1 ? k.op.toFixed(2) : '';
        el.style.zIndex = k.z;
        el.style.visibility = k.op <= 0.01 ? 'hidden' : '';
        el.classList.toggle('gewaehlt', this.gewaehlt === c.id);
        el.style.setProperty('--i', i);
      });
    }
    // Rollgrenzen im Band: das Band bleibt gefüllt (erste Karte am linken, letzte am rechten Rand)
    grenzen(lay) {
      const n = this.reihe.length;
      lay = lay || this.letztesLayout || layout(n, this.t.W, this.t.H, {});
      if (!lay.band) return { lo: 0, hi: Math.max(0, n - 1) };
      const m = Math.floor((lay.breite - KW) / 2 / lay.step);
      const mitte = (n - 1) / 2;
      return { lo: Math.min(m, mitte), hi: Math.max(n - 1 - m, mitte) };
    }
    _scrollAnzeige() {
      const g = this.grenzen(), s = this.scroll;
      if (s < g.lo) return g.lo + (s - g.lo) * 0.35;
      if (s > g.hi) return g.hi + (s - g.hi) * 0.35;
      return s;
    }
    // Position (Mitte oben) einer Handkarte in Bühnenkoordinaten, z. B. als Startpunkt eines Flugs
    position(id) {
      const i = this.index(id);
      if (i < 0 || !this.letztesLayout) return null;
      const k = this.letztesLayout.karten[i];
      return { x: k.x, y: k.y + KH / 2, rot: k.rot, w: KW * k.sc };
    }
    trefferId(px, py) {
      if (!this.letztesLayout) return null;
      const ks = this.letztesLayout.karten;
      const order = ks.map((k, i) => i).sort((a, b) => ks[b].z - ks[a].z);
      for (const i of order) if (ks[i].op > 0.3 && trifft(ks[i], px, py)) return this.reihe[i].id;
      return null;
    }

    /* ---------- Zustände ---------- */
    waehle(id) {
      this.gewaehlt = id;
      this.ordne();
    }
    schwebe(id, an) { if (an) this.schwebend.add(id); else this.schwebend.delete(id); this.ordne(); }
    wackeln(id) {
      const el = this.els.get(id);
      if (!el) return;
      const innen = el.firstChild;
      innen.classList.remove('wackeln'); void innen.offsetWidth; innen.classList.add('wackeln');
      setTimeout(() => innen.classList.remove('wackeln'), 420);
    }
    zeigeRueck(an) {
      this.rueck = !!an;
      this.el.classList.toggle('rueck', this.rueck);
    }

    /* ---------- Gesten ---------- */
    _zeiger() {
      const z = this.zone;
      z.addEventListener('pointerdown', e => this._runter(e));
      z.addEventListener('pointermove', e => this._bewegen(e));
      z.addEventListener('pointerup', e => this._hoch(e, false));
      z.addEventListener('pointercancel', e => this._hoch(e, true));
      z.addEventListener('lostpointercapture', e => { if (this.geste && this.geste.pid === e.pointerId) this._hoch(e, true); });
      // Mausrad (PC-Browser): im Band kartenweise rollen
      z.addEventListener('wheel', e => {
        const lay = this.letztesLayout;
        if (!lay || !lay.band) return;
        e.preventDefault();
        const jetzt = performance.now();
        if (jetzt - (this._radZeit || 0) < 70) return;
        this._radZeit = jetzt;
        const d = Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY;
        const g = this.grenzen();
        this.scroll = clamp(Math.round(this.scroll) + (d > 0 ? 1 : -1), g.lo, g.hi);
        this.ordne();
      }, { passive: false });
    }
    _runter(e) {
      if (this.geste) return;
      e.preventDefault();
      try { this.zone.setPointerCapture(e.pointerId); } catch (err) { /* synthetische Ereignisse */ }
      const p = this.t.zuBuehne(e.clientX, e.clientY);
      const id = this.trefferId(p.x, p.y);
      const lay = this.letztesLayout || { band: false, step: 66 };
      this.geste = {
        pid: e.pointerId, x0: e.clientX, y0: e.clientY, t0: performance.now(), id, art: 'offen',
        scroll0: this.scroll, band: lay.band, step: lay.step, proben: [{ t: performance.now(), x: e.clientX, y: e.clientY }],
      };
      clearTimeout(this._halteTimer);
      if (id !== null) this._halteTimer = setTimeout(() => {
        const g = this.geste;
        if (g && g.art === 'offen' && g.id === id) {
          g.art = 'hilfe';
          const c = this.reihe[this.index(id)];
          if (c && this.cb.hilfe) this.cb.hilfe(this.rueck ? (c.back || 'rueckseite') : c.face);
        }
      }, HALTEN);
    }
    _bewegen(e) {
      const g = this.geste;
      if (!g || g.pid !== e.pointerId) return;
      e.preventDefault();
      const dx = e.clientX - g.x0, dy = e.clientY - g.y0;
      const jetzt = performance.now();
      g.proben.push({ t: jetzt, x: e.clientX, y: e.clientY });
      while (g.proben.length > 2 && jetzt - g.proben[0].t > 120) g.proben.shift();
      if (g.art === 'offen') {
        if (Math.hypot(dx, dy) < BEWEGUNG) return;
        clearTimeout(this._halteTimer);
        if (g.id !== null && dy < 0 && Math.abs(dy) > 1.2 * Math.abs(dx) && !this.rueck) g.art = 'hoch';
        else if (g.band) g.art = 'wisch';
        else g.art = 'gleiten';
      }
      const s = this.t.s;
      if (g.art === 'hoch') {
        this.zug = { id: g.id, dy: Math.min(0, dy / s) };
        this.ordne(true);
      } else if (g.art === 'wisch') {
        this.scroll = g.scroll0 - (dx / s) / g.step;
        this.ordne(true);
      } else if (g.art === 'gleiten') {
        const p = this.t.zuBuehne(e.clientX, e.clientY);
        const id = this.trefferId(p.x, p.y);
        if (id !== this.fokus) { this.fokus = id; this.ordne(); }
      }
    }
    _hoch(e, abbruch) {
      const g = this.geste;
      if (!g || (e.pointerId !== undefined && g.pid !== e.pointerId)) return;
      this.geste = null;
      clearTimeout(this._halteTimer);
      try { this.zone.releasePointerCapture(g.pid); } catch (err) { /* egal */ }
      if (g.art === 'hoch') {
        const dy = (e.clientY - g.y0) / this.t.s;
        const v = this._tempo(g, 'y');  // px/ms (Bildschirm)
        this.zug = null;
        if (!abbruch && (dy < -AUSSPIELEN || (v < -0.9 && dy < -30))) { this.ordne(); this.cb.spielen(g.id); }
        else this.ordne();
      } else if (g.art === 'wisch') {
        const v = this._tempo(g, 'x') / this.t.s / g.step;   // Karten pro ms
        const ziel = this.scroll - v * 260;
        const gr = this.grenzen();
        this.scroll = Math.round(clamp(ziel, gr.lo, gr.hi));
        this.el.classList.add('schwung');
        this.ordne();
        clearTimeout(this._schwungTimer);
        this._schwungTimer = setTimeout(() => this.el.classList.remove('schwung'), 520);
      } else if (g.art === 'gleiten') {
        const id = this.fokus;
        this.fokus = null;
        if (!abbruch && id !== null) this.cb.antippen(id); else this.ordne();
      } else if (g.art === 'offen' && !abbruch) {
        if (g.id !== null) this.cb.antippen(g.id);
        else if (this.cb.leer) this.cb.leer();
      }
    }
    _tempo(g, achse) {
      const p = g.proben;
      if (p.length < 2) return 0;
      const a = p[0], b = p[p.length - 1];
      const dt = Math.max(1, b.t - a.t);
      return (b[achse] - a[achse]) / dt;
    }
  }

  M.Hand = { Hand, layout, trifft, KW, KH };
})(window.MMF = window.MMF || {});
