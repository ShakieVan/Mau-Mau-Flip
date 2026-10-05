/* Mau-Mau Flip – Browser-Client „Lite“: Töne über Web Audio (ohne AudioWorklet, also auch ohne Secure Context).
 * Klänge werden synthetisch erzeugt. Liegt sfx/index.json vor ({"mau":"mau.mp3", …}), werden diese Dateien bevorzugt.
 * Freischalten nur aus einem Tipp heraus (Beitreten-Knopf). Der Mau-Ton spielt nur auf dem Gerät, das „Mau!“ drückt.
 */
(function (M) {
  'use strict';

  const STUFEN = { aus: 0, leise: 0.35, normal: 0.85 };
  let ctx = null, master = null, rausch = null;
  let stufe = 'normal';
  const dateien = {};      // Name → AudioBuffer aus sfx/

  function freischalten() {
    try {
      if (!ctx) {
        const AC = window.AudioContext || window.webkitAudioContext;
        if (!AC) return false;
        ctx = new AC();
        master = ctx.createGain();
        master.gain.value = STUFEN[stufe];
        master.connect(ctx.destination);
        // stummer Puffer schaltet iOS frei
        const b = ctx.createBuffer(1, 1, 22050);
        const q = ctx.createBufferSource();
        q.buffer = b; q.connect(ctx.destination); q.start(0);
        rausch = rauschPuffer();
        ladeDateien();
      }
      if (ctx.state !== 'running' && ctx.resume) ctx.resume().catch(() => {});
      return true;
    } catch (e) { return false; }
  }
  // nach Sperre oder App-Wechsel wieder aufwecken (klappt auf iOS teils erst beim nächsten Tipp)
  function wecken() { if (ctx && ctx.state !== 'running' && ctx.resume) ctx.resume().catch(() => {}); }

  function setzeStufe(s) {
    stufe = STUFEN[s] !== undefined ? s : 'normal';
    if (master) master.gain.value = STUFEN[stufe];
  }

  // Klangdateien aus sfx/: sfx/index.json ({"mau":"mau.m4a", …}) legt fest, welche Synth-Klänge ersetzt werden.
  // Ohne Liste wird nur der Mau-Ton gesucht (mau.m4a, sonst mau.ogg), damit keine Reihe von 404-Anfragen entsteht.
  function ladeDateien() {
    if (!window.fetch || location.protocol === 'file:') return;
    const lade = (name, datei) => fetch('sfx/' + datei).then(r => (r.ok ? r.arrayBuffer() : null)).then(ab => {
      if (!ab) return false;
      return new Promise(ok => ctx.decodeAudioData(ab, buf => { dateien[name] = buf; ok(true); }, () => ok(false)));
    }).catch(() => false);
    fetch('sfx/index.json').then(r => (r.ok ? r.json() : null)).catch(() => null).then(liste => {
      if (liste && typeof liste === 'object') { Object.keys(liste).forEach(name => lade(name, String(liste[name]))); return; }
      const a = document.createElement('audio');
      const aac = a.canPlayType && a.canPlayType('audio/mp4; codecs="mp4a.40.2"');
      const reihe = aac ? ['mau.m4a', 'mau.ogg'] : ['mau.ogg', 'mau.m4a'];
      lade('mau', reihe[0]).then(ok => { if (!ok) lade('mau', reihe[1]); });
    });
  }

  function rauschPuffer() {
    const n = ctx.sampleRate | 0;
    const b = ctx.createBuffer(1, n, ctx.sampleRate);
    const d = b.getChannelData(0);
    let s = 1234567;
    for (let i = 0; i < n; i++) { s = (s * 1103515245 + 12345) & 0x7fffffff; d[i] = (s / 0x3fffffff) - 1; }
    return b;
  }
  // Hüllkurve: Anstieg a, Halten h, Abklingen r (Sekunden)
  function huelle(g, t, spitze, a, h, r) {
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(spitze, t + a);
    g.gain.setValueAtTime(spitze, t + a + h);
    g.gain.exponentialRampToValueAtTime(0.0001, t + a + h + r);
  }
  function osz(typ, f, t, dauer, ziel) {
    const o = ctx.createOscillator();
    o.type = typ; o.frequency.setValueAtTime(f, t);
    o.connect(ziel); o.start(t); o.stop(t + dauer + 0.05);
    return o;
  }
  function rauschen(t, dauer, filterTyp, f, q, ziel) {
    const s = ctx.createBufferSource();
    s.buffer = rausch;
    const fl = ctx.createBiquadFilter();
    fl.type = filterTyp; fl.frequency.setValueAtTime(f, t); fl.Q.value = q || 1;
    s.connect(fl); fl.connect(ziel);
    s.start(t, Math.random() * 0.5); s.stop(t + dauer + 0.05);
    return fl;
  }
  function gain(ziel) { const g = ctx.createGain(); g.connect(ziel || master); return g; }

  const SYNTH = {
    karte(t) {   // Karte legen: kurzes Klatschen
      const g = gain(); huelle(g, t, 0.55, 0.003, 0.01, 0.09);
      rauschen(t, 0.12, 'bandpass', 2600, 0.9, g);
      const g2 = gain(); huelle(g2, t, 0.35, 0.002, 0.0, 0.07);
      const o = osz('sine', 170, t, 0.1, g2); o.frequency.exponentialRampToValueAtTime(90, t + 0.08);
    },
    ziehen(t) {  // Ziehen: Wischen
      const g = gain(); huelle(g, t, 0.35, 0.03, 0.05, 0.12);
      const fl = rauschen(t, 0.25, 'bandpass', 900, 1.4, g);
      fl.frequency.exponentialRampToValueAtTime(3800, t + 0.2);
    },
    mischen(t) { // Mischen: mehrere kurze Ticks
      for (let i = 0; i < 9; i++) {
        const ti = t + i * 0.045 + Math.random() * 0.015;
        const g = gain(); huelle(g, ti, 0.22 + Math.random() * 0.1, 0.002, 0.0, 0.04);
        rauschen(ti, 0.06, 'bandpass', 2000 + Math.random() * 1800, 1.2, g);
      }
    },
    flip(t) {    // Flip: aufsteigender Schwung mit Glockenton
      const g = gain(); huelle(g, t, 0.3, 0.08, 0.1, 0.25);
      const fl = rauschen(t, 0.5, 'bandpass', 400, 2, g);
      fl.frequency.exponentialRampToValueAtTime(5000, t + 0.4);
      const g2 = gain(); huelle(g2, t + 0.12, 0.22, 0.01, 0.05, 0.6);
      const o = osz('triangle', 440, t + 0.12, 0.7, g2); o.frequency.exponentialRampToValueAtTime(880, t + 0.32);
      const g3 = gain(); huelle(g3, t + 0.3, 0.12, 0.01, 0.0, 0.7);
      osz('sine', 1318.5, t + 0.3, 0.75, g3);
    },
    sieg(t) {    // Sieg: Dreiklang aufwärts
      [523.25, 659.25, 783.99, 1046.5].forEach((f, i) => {
        const ti = t + i * 0.11;
        const g = gain(); huelle(g, ti, 0.25, 0.01, 0.06, i === 3 ? 0.9 : 0.3);
        osz('triangle', f, ti, i === 3 ? 1.0 : 0.4, g);
      });
      const g = gain(); huelle(g, t + 0.44, 0.12, 0.02, 0.2, 0.9);
      [523.25, 659.25, 783.99].forEach(f => osz('sine', f, t + 0.44, 1.2, g));
    },
    fehler(t) {  // Fehler: tiefes Doppelbrummen
      [0, 0.13].forEach(d => {
        const g = gain(); huelle(g, t + d, 0.2, 0.005, 0.05, 0.05);
        const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.frequency.value = 900; lp.connect(g);
        osz('square', 170, t + d, 0.12, lp);
      });
    },
    dran(t) {    // Du bist dran: zweitönige Glocke
      [[1318.5, 0], [987.77, 0.12]].forEach(([f, d]) => {
        const g = gain(); huelle(g, t + d, 0.22, 0.005, 0.02, 0.45);
        osz('sine', f, t + d, 0.5, g);
        const g2 = gain(); huelle(g2, t + d, 0.05, 0.005, 0.0, 0.25);
        osz('sine', f * 2.01, t + d, 0.3, g2);
      });
    },
    mau(t) {     // „Mau!“: kurzer, heller Katzenlaut (m → a → u über Formanten)
      const ausgang = gain(); huelle(ausgang, t, 0.5, 0.04, 0.26, 0.2);
      const lp = ctx.createBiquadFilter(); lp.type = 'lowpass'; lp.Q.value = 0.7;
      lp.frequency.setValueAtTime(700, t); lp.frequency.exponentialRampToValueAtTime(4200, t + 0.09);
      lp.frequency.setValueAtTime(4200, t + 0.22); lp.frequency.exponentialRampToValueAtTime(900, t + 0.48);
      lp.connect(ausgang);
      const f1 = ctx.createBiquadFilter(); f1.type = 'bandpass'; f1.Q.value = 4;
      f1.frequency.setValueAtTime(500, t); f1.frequency.linearRampToValueAtTime(1100, t + 0.12); f1.frequency.linearRampToValueAtTime(600, t + 0.45);
      const f2 = ctx.createBiquadFilter(); f2.type = 'bandpass'; f2.Q.value = 5;
      f2.frequency.setValueAtTime(1500, t); f2.frequency.linearRampToValueAtTime(2000, t + 0.12); f2.frequency.linearRampToValueAtTime(900, t + 0.45);
      const mixG = ctx.createGain(); mixG.gain.value = 0.9; mixG.connect(lp);
      f1.connect(mixG); f2.connect(mixG);
      const o = ctx.createOscillator(); o.type = 'sawtooth';
      o.frequency.setValueAtTime(560, t); o.frequency.exponentialRampToValueAtTime(820, t + 0.11);
      o.frequency.exponentialRampToValueAtTime(700, t + 0.28); o.frequency.exponentialRampToValueAtTime(470, t + 0.5);
      const vib = ctx.createOscillator(); vib.frequency.value = 7; const vg = ctx.createGain(); vg.gain.value = 9; vib.connect(vg); vg.connect(o.frequency);
      const roh = ctx.createGain(); roh.gain.value = 0.18; o.connect(roh); roh.connect(lp);
      o.connect(f1); o.connect(f2);
      o.start(t); o.stop(t + 0.6); vib.start(t); vib.stop(t + 0.6);
    },
  };

  function spiele(name) {
    if (!ctx || stufe === 'aus') return;
    try {
      if (ctx.state !== 'running') wecken();
      const t = ctx.currentTime + 0.01;
      if (dateien[name]) {
        const s = ctx.createBufferSource(); s.buffer = dateien[name]; s.connect(master); s.start(t);
        return;
      }
      if (SYNTH[name]) SYNTH[name](t);
    } catch (e) { /* Ton ist Beiwerk */ }
  }

  // Selbstprüfung (Autotest): jeden Klang offline rendern und den Spitzenpegel messen → {name: Pegel | 'Fehler: …'}
  function pruefe() {
    const OAC = window.OfflineAudioContext || window.webkitOfflineAudioContext;
    if (!OAC) return Promise.resolve(null);
    return Object.keys(SYNTH).reduce((kette, name) => kette.then(erg => {
      const off = new OAC(1, 44100 * 1.8, 44100);
      const alt = [ctx, master, rausch];
      ctx = off; master = off.createGain(); master.gain.value = STUFEN.normal; master.connect(off.destination); rausch = rauschPuffer();
      let fehler = null;
      try { SYNTH[name](0.01); } catch (e) { fehler = e; }
      [ctx, master, rausch] = alt;
      if (fehler) { erg[name] = 'Fehler: ' + fehler.message; return erg; }
      return off.startRendering().then(buf => {
        const d = buf.getChannelData(0);
        let spitze = 0;
        for (let i = 0; i < d.length; i++) { const a = Math.abs(d[i]); if (a > spitze) spitze = a; }
        erg[name] = Math.round(spitze * 1000) / 1000;
        return erg;
      });
    }), Promise.resolve({}));
  }

  M.Ton = { freischalten, wecken, spiele, setzeStufe, pruefe, get stufe() { return stufe; }, get bereit() { return !!ctx; }, get dateien() { return Object.keys(dateien); } };
})(window.MMF = window.MMF || {});
