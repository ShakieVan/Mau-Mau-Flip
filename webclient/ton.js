/* Mau-Mau Flip – Browser-Client „Lite“: Töne über Web Audio (ohne AudioWorklet, also auch ohne Secure Context).
 * Zwei Gruppen mit eigener Lautstärke (wie in der App, game/scripts/app/sound.gd):
 *  - Mau-Töne „mau“ und „mau_mau“: die Aufnahmen des Nutzers (sfx/mau.m4a bzw. .ogg, sfx/mau_mau.*). Sie spielen auf JEDEM
 *    Gerät, sobald das Ereignis vom Gastgeber kommt (AGENTS.md Nr. 21), Stufe aus/leise/normal (Standard normal).
 *  - Spieltöne (karte, ziehen, mischen, flip, sieg, fehler, dran): dieselben Dateien wie in der App (sfx/<name>.m4a bzw. .ogg),
 *    eigener Schalter „Spieltöne“, Standard AUS (Nutzerwunsch 05.10.2026). Fehlt eine Datei, klingt ein synthetischer Ersatz.
 *    Pegel wie in der App: dort Mau normal −2 dB, Spieltöne normal −4,5 dB und leise −12,5 dB, also 2,5 bzw. 10,5 dB unter dem Mau-Ton.
 * Darüber ein Stummschalter (Ton-Knopf in der Ecke). sfx/index.json ({"mau":"mau.m4a", …}) nennt die Dateien; je Browser wird
 * m4a (AAC, iPhone-Safari) oder ogg bevorzugt und bei Bedarf auf die andere Endung ausgewichen.
 * Freischalten nur aus einem Tipp heraus (Beitreten-Knopf).
 */
(function (M) {
  'use strict';

  const MAU_TOENE = ['mau', 'mau_mau'];
  const SPIEL_TOENE = ['karte', 'ziehen', 'mischen', 'flip', 'dran', 'fehler', 'sieg'];
  // Pegel je Stufe: Die Aufnahmen sind auf −1 dBTP ausgesteuert und verdichtet → „normal“ = volle Lautstärke (Handy-Lautsprecher)
  const STUFEN_MAU = { aus: 0, leise: 0.4, normal: 1.0 };
  const STUFEN_SPIEL = { aus: 0, leise: 0.3, normal: 0.75 };      // −10,5 bzw. −2,5 dB unter dem Mau-Ton (wie in der App, sound.gd TON_DB)
  const SYNTH_PEGEL = 1.0;     // synthetischer Ersatz: bleibt so laut wie bisher (0,3 bzw. 0,75)
  const STANDARD_DATEIEN = {};  // falls sfx/index.json fehlt: alle Töne als m4a (Rückfall ogg)
  MAU_TOENE.concat(SPIEL_TOENE).forEach(n => { STANDARD_DATEIEN[n] = n + '.m4a'; });
  let ctx = null, master = null, busMau = null, busSpiel = null, busSynth = null, rausch = null;
  let stufeMau = 'normal', stufeSpiel = 'aus', stumm = false;
  const dateien = {};      // Name → AudioBuffer aus sfx/
  const zaehler = {};      // Name → wie oft wirklich abgespielt (Selbsttest)
  let ladeVersprechen = null;

  const istMau = name => MAU_TOENE.indexOf(name) >= 0;

  function freischalten() {
    try {
      if (!ctx) {
        const AC = window.AudioContext || window.webkitAudioContext;
        if (!AC) return false;
        ctx = new AC();
        master = ctx.createGain();
        master.gain.value = stumm ? 0 : 1;
        master.connect(ctx.destination);
        busMau = ctx.createGain(); busMau.gain.value = STUFEN_MAU[stufeMau]; busMau.connect(master);
        busSpiel = ctx.createGain(); busSpiel.gain.value = STUFEN_SPIEL[stufeSpiel]; busSpiel.connect(master);
        busSynth = ctx.createGain(); busSynth.gain.value = SYNTH_PEGEL; busSynth.connect(busSpiel);
        // stummer Puffer schaltet iOS frei
        const b = ctx.createBuffer(1, 1, 22050);
        const q = ctx.createBufferSource();
        q.buffer = b; q.connect(ctx.destination); q.start(0);
        rausch = rauschPuffer();
        ladeVersprechen = ladeDateien();
      }
      if (ctx.state !== 'running' && ctx.resume) ctx.resume().catch(() => {});
      return true;
    } catch (e) { return false; }
  }
  // nach Sperre oder App-Wechsel wieder aufwecken (klappt auf iOS teils erst beim nächsten Tipp)
  function wecken() { if (ctx && ctx.state !== 'running' && ctx.resume) ctx.resume().catch(() => {}); }

  function _pegel() {
    if (!ctx) return;
    master.gain.value = stumm ? 0 : 1;
    busMau.gain.value = STUFEN_MAU[stufeMau];
    busSpiel.gain.value = STUFEN_SPIEL[stufeSpiel];
  }
  function setzeStufe(s) { stufeMau = STUFEN_MAU[s] !== undefined ? s : 'normal'; _pegel(); }       // Mau-Ton
  function setzeToene(s) { stufeSpiel = STUFEN_SPIEL[s] !== undefined ? s : 'aus'; _pegel(); }     // Spieltöne
  function setzeStumm(an) { stumm = !!an; _pegel(); }

  // Klangdateien aus sfx/. Je Eintrag erst die Endung, die der Browser sicher kann (m4a/AAC für Safari, sonst ogg), dann die andere.
  function ladeDateien() {
    if (!window.fetch || location.protocol === 'file:') return Promise.resolve([]);
    const a = document.createElement('audio');
    const aac = !!(a.canPlayType && a.canPlayType('audio/mp4; codecs="mp4a.40.2"'));
    const ogg = !!(a.canPlayType && a.canPlayType('audio/ogg; codecs="vorbis"'));
    const dekodiere = ab => new Promise(ok => {
      try {
        const p = ctx.decodeAudioData(ab, buf => ok(buf), () => ok(null));
        if (p && p.catch) p.catch(() => ok(null));
      } catch (e) { ok(null); }
    });
    const lade = datei => fetch('sfx/' + datei).then(r => (r.ok ? r.arrayBuffer() : null)).then(ab => (ab ? dekodiere(ab) : null)).catch(() => null);
    const reihe = datei => {
      const m = /^(.*)\.(m4a|ogg)$/i.exec(datei);
      if (!m) return [datei];
      const m4a = m[1] + '.m4a', vorbis = m[1] + '.ogg';
      return (aac || !ogg) ? [m4a, vorbis] : [vorbis, m4a];
    };
    return fetch('sfx/index.json', { cache: 'no-store' }).then(r => (r.ok ? r.json() : null)).catch(() => null).then(liste => {
      if (!liste || typeof liste !== 'object') liste = STANDARD_DATEIEN;
      return Promise.all(Object.keys(liste).map(name => {
        const versuche = reihe(String(liste[name]));
        const weiter = i => (i >= versuche.length ? Promise.resolve(false) : lade(versuche[i]).then(buf => {
          if (buf) { dateien[name] = buf; return true; }
          return weiter(i + 1);
        }));
        return weiter(0);
      }));
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
  let synthZiel = null;
  function gain(ziel) { const g = ctx.createGain(); g.connect(ziel || synthZiel); return g; }

  // Synthetischer Ersatz der Spieltöne (nur wenn eine Datei in sfx/ fehlt). Keinen synthetischen Mau-Ton: Mau kommt nur aus den Aufnahmen.
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
  };

  // Abspielen; true, wenn der Ton wirklich angestoßen wurde (nicht stumm, Stufe > 0, Klang vorhanden)
  function spiele(name) {
    if (!ctx || stumm) return false;
    const mau = istMau(name);
    if ((mau ? STUFEN_MAU[stufeMau] : STUFEN_SPIEL[stufeSpiel]) <= 0) return false;
    try {
      if (ctx.state !== 'running') wecken();
      const t = ctx.currentTime + 0.01;
      const bus = mau ? busMau : busSpiel;
      if (dateien[name]) {
        const s = ctx.createBufferSource(); s.buffer = dateien[name]; s.connect(bus); s.start(t);
      } else if (!mau && SYNTH[name]) {
        synthZiel = busSynth;
        SYNTH[name](t);
      } else return false;
      zaehler[name] = (zaehler[name] || 0) + 1;
      return true;
    } catch (e) { return false; /* Ton ist Beiwerk */ }
  }

  // Selbstprüfung (Autotest): jeden synthetischen Klang offline rendern und den Spitzenpegel messen, dazu die geladenen
  // Aufnahmen (Spitze und Dauer) → {name: Pegel | 'Fehler: …'}, Aufnahmen als „datei:<name>“ mit {spitze, dauer}
  function pruefe() {
    const OAC = window.OfflineAudioContext || window.webkitOfflineAudioContext;
    if (!OAC) return Promise.resolve(null);
    return Object.keys(SYNTH).reduce((kette, name) => kette.then(erg => {
      const off = new OAC(1, 44100 * 1.8, 44100);
      const alt = [ctx, synthZiel, rausch];
      ctx = off; synthZiel = off.createGain(); synthZiel.gain.value = STUFEN_SPIEL.normal * SYNTH_PEGEL; synthZiel.connect(off.destination); rausch = rauschPuffer();
      let fehler = null;
      try { SYNTH[name](0.01); } catch (e) { fehler = e; }
      [ctx, synthZiel, rausch] = alt;
      if (fehler) { erg[name] = 'Fehler: ' + fehler.message; return erg; }
      return off.startRendering().then(buf => {
        erg[name] = spitze(buf);
        return erg;
      });
    }), Promise.resolve({})).then(erg => {
      Object.keys(dateien).forEach(name => { erg['datei:' + name] = { spitze: spitze(dateien[name]), dauer: Math.round(dateien[name].duration * 100) / 100 }; });
      return erg;
    });
  }
  function spitze(buf) {
    let s = 0;
    for (let k = 0; k < buf.numberOfChannels; k++) {
      const d = buf.getChannelData(k);
      for (let i = 0; i < d.length; i++) { const a = Math.abs(d[i]); if (a > s) s = a; }
    }
    return Math.round(s * 1000) / 1000;
  }

  M.Ton = {
    freischalten, wecken, spiele, setzeStufe, setzeToene, setzeStumm, pruefe, istMau,
    geladen() { return ladeVersprechen || Promise.resolve([]); },
    get stufe() { return stufeMau; }, get toene() { return stufeSpiel; }, get stumm() { return stumm; },
    get bereit() { return !!ctx; }, get dateien() { return Object.keys(dateien); }, get zaehler() { return zaehler; },
    MAU_TOENE, SPIEL_TOENE, STUFEN_SPIEL,
  };
})(window.MMF = window.MMF || {});
