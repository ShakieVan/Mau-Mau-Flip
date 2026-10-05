/* Mau-Mau Flip – Browser-Client „Lite“: Selbsttest (index.html?mock=1&autotest=1, später auch gegen einen echten Gastgeber).
 * Spielt über die echte Oberfläche (synthetische Zeigerereignisse auf der Hand, Klicks auf Knöpfe), prüft nach jedem
 * Abgleich DOM gegen Sicht und schreibt das Ergebnis nach #autotest-result (data-ok="1"/"0"), auswertbar mit --dump-dom.
 * Parameter: zuege=N (eigene Züge, Standard 14), runden=N (Abbruch nach N Rundenenden, Standard 2).
 */
(function (M) {
  'use strict';
  const $ = s => document.querySelector(s);
  const schlaf = ms => new Promise(r => setTimeout(r, ms));
  const P = new URLSearchParams(location.search);

  // Chrome --dump-dom schreibt das DOM beim load-Ereignis. Mit &halter=<Port> hält ein verstecktes iframe zu einem Port, der nie
  // antwortet (Testgastgeber game/tests/web_host.gd), das load-Ereignis auf, bis der Test fertig ist und es entfernt.
  // (Dieses Skript wird vor dem load-Ereignis eingefügt und ausgeführt, also zählt das iframe noch mit.)
  let halter = null;
  if (P.get('halter') && document.body) {
    halter = document.createElement('iframe');
    halter.style.display = 'none';
    halter.src = 'http://' + location.hostname + ':' + (+P.get('halter')) + '/halten';
    document.body.appendChild(halter);
  }

  // Erwartete Form der Sicht (game/scripts/rules/mau_game.gd view_for/_hints) – Prüfung Feld für Feld gegen den echten Gastgeber
  const PHASEN = ['idle', 'turn', 'drawn', 'challenge', 'color', 'round_over', 'game_over'];
  const HINT_FELDER = { playable: 'array', wild: 'array', can_draw: 'boolean', can_keep: 'boolean', can_challenge: 'boolean', can_accept: 'boolean',
    can_mau: 'boolean', catch: 'array', need_color: 'boolean', can_next_round: 'boolean', text: 'string' };
  const SICHT_FELDER = { seat: 'number', side: 'string', phase: 'string', turn: 'number', dir: 'number', color: 'string', players: 'array', hand: 'array',
    top: 'object', draw_back: 'string', draw_count: 'number', pending: 'object', hints: 'object', round: 'number', ranking: 'array', rules: 'object', result: 'object' };
  const SPIELER_FELDER = { seat: 'number', name: 'string', kind: 'string', count: 'number', backs: 'array', place: 'number', mau: 'boolean', connected: 'boolean', score: 'number' };
  const art = x => Array.isArray(x) ? 'array' : (x === null ? 'null' : typeof x);
  // Ereignisse, die der Client kennt (Effekt in tisch.js oder bewusst ohne Effekt)
  const EREIGNISSE = ['deal', 'play', 'draw', 'skip', 'skip_all', 'reverse', 'color', 'flip', 'pending', 'challenge', 'mau', 'catch', 'penalty', 'shuffle',
    'round_over', 'game_over', 'finish', 'pass', 'choose_color', 'round_start', 'start', 'turn', 'keep', 'accept'];

  const T = {
    start(app) {
      this.app = app;
      this.t0 = Date.now();
      this.zuege = 0; this.runden = 0; this.states = 0; this.errs = 0; this.ereignisse = {};
      this.fehler = []; this.notizen = [];
      this.mock = !!M.param('mock');
      // gegen den echten Gastgeber: bis zum ersten Rundenende spielen
      this.ziel = +(M.param('zuege') || (this.mock ? 14 : 400));
      this.rundenZiel = +(M.param('runden') || (this.mock ? 2 : 1));
      this._fertig = false;
      setTimeout(() => this.lauf(), 30);
    },
    // Sicht Feld für Feld prüfen (nur gegen den echten Gastgeber; das Mock liefert eine vereinfachte Form)
    vertrag(v) {
      if (this.mock || !v) return;
      Object.keys(SICHT_FELDER).forEach(k => { if (art(v[k]) !== SICHT_FELDER[k]) this.fail('Sicht.' + k + ': ' + art(v[k]) + ' statt ' + SICHT_FELDER[k]); });
      if (PHASEN.indexOf(v.phase) < 0) this.fail('unbekannte Phase ' + v.phase);
      const h = v.hints || {};
      Object.keys(HINT_FELDER).forEach(k => { if (art(h[k]) !== HINT_FELDER[k]) this.fail('hints.' + k + ': ' + art(h[k]) + ' statt ' + HINT_FELDER[k]); });
      (v.players || []).forEach(p => Object.keys(SPIELER_FELDER).forEach(k => { if (art(p[k]) !== SPIELER_FELDER[k]) this.fail('players[].' + k + ': ' + art(p[k])); }));
      (v.hand || []).forEach(c => { if (typeof c.id !== 'number' || typeof c.face !== 'string') this.fail('hand[] ohne id/face'); });
      if (v.pending && v.pending.kind && ['plus1', 'plus5', 'wuenscher_plus2', 'farbjagd'].indexOf(v.pending.kind) < 0) this.fail('pending.kind ' + v.pending.kind);
      if (h.need_color && v.phase !== 'color') this.fail('need_color außerhalb der Phase color');
      if (v.phase === 'color') this.ereignisse.phaseColor = (this.ereignisse.phaseColor || 0) + 1;
      if ((h.wild || []).some(id => (h.playable || []).indexOf(id) < 0)) this.fail('hints.wild nicht in playable');
      if ((v.phase === 'round_over' || v.phase === 'game_over') && !(v.result && Array.isArray(v.result.ranking) && v.result.ranking.length === (v.players || []).length)) this.fail('result.ranking fehlt');
    },
    zustand(m) {
      this.states++;
      (m.events || []).forEach(e => {
        this.ereignisse[e.e] = (this.ereignisse[e.e] || 0) + 1;
        if (!this.mock && EREIGNISSE.indexOf(e.e) < 0) this.fail('unbekanntes Ereignis ' + e.e);
      });
      try { this.vertrag(m.view); } catch (e) { this.fail('Vertrag: ' + e); }
    },
    fehlerNachricht(m) { this.errs++; this.notiz('err vom Gastgeber: ' + m.text); },
    notiz(t) { this.notizen.push(t); },
    fail(t) { if (this.fehler.indexOf(t) < 0) this.fehler.push(t); },
    async warte(bed, ms, was) {
      const ende = Date.now() + ms;
      while (Date.now() < ende) { try { if (bed()) return true; } catch (e) { /* weiter */ } await schlaf(40); }
      throw new Error('Zeitüberschreitung: ' + was);
    },
    get v() { return this.app.view; },
    ruhig() { const t = this.app.tisch; return !!(t && t.regie.leer); },
    binDran() {
      const v = this.v;
      if (!v || !this.ruhig()) return false;
      const h = v.hints || {};
      return (v.turn === v.seat && (v.phase === 'turn' || v.phase === 'drawn' || v.phase === 'challenge')) || !!h.need_color || !!h.can_challenge;
    },
    rundeVorbei() { const v = this.v; return !!v && (v.phase === 'round_over' || v.phase === 'game_over') && this.ruhig(); },

    /* ---------- Eingaben ---------- */
    zeiger(typ, x, y) {
      const z = this.app.tisch.hand.zone;
      const opt = { clientX: x, clientY: y, pointerId: 7, pointerType: 'touch', isPrimary: true, bubbles: true, cancelable: true, buttons: typ === 'pointerup' ? 0 : 1 };
      z.dispatchEvent(window.PointerEvent ? new PointerEvent(typ, opt) : Object.assign(new MouseEvent(typ, opt), { pointerId: 7 }));
    },
    // Bildschirmpunkt, an dem Karte id zuoberst liegt
    punkt(id) {
      const t = this.app.tisch, h = t.hand;
      const lay = h.letztesLayout, i = h.index(id);
      if (!lay || i < 0) return null;
      const k = lay.karten[i];
      const r = t.root.getBoundingClientRect();
      for (const dy of [30, 60, 15, 90]) for (const fx of [0.15, 0.3, 0.05, 0.5, 0.7]) {
        const x = k.x - M.Hand.KW / 2 + M.Hand.KW * fx, y = k.y + dy;
        if (h.trefferId(x, y) === id) return { x: r.left + t.ox + x * t.s, y: r.top + t.oy + y * t.s };
      }
      return null;
    },
    // Im Band liegt die Karte evtl. außerhalb: per Wischgeste hinrollen (am Ende kurz still halten → kein Schwung)
    async sichtbar(id) {
      if (this.punkt(id)) return;
      const t = this.app.tisch, h = t.hand, lay = h.letztesLayout;
      if (!lay || !lay.band) return;
      const i = h.index(id);
      const r = t.root.getBoundingClientRect();
      const x0 = r.left + t.ox + t.W / 2 * t.s, y0 = r.top + (t.H - 60) * t.s;
      const dx = (h.scroll - i) * lay.step * t.s;
      this.zeiger('pointerdown', x0, y0);
      for (let k = 1; k <= 8; k++) { await schlaf(20); this.zeiger('pointermove', x0 + dx * k / 8, y0); }
      await schlaf(160);
      this.zeiger('pointermove', x0 + dx, y0);
      this.zeiger('pointerup', x0 + dx, y0);
      await schlaf(80);
      this.wischte = (this.wischte || 0) + 1;
    },
    async tippe(id) {
      await this.sichtbar(id);
      const p = this.punkt(id);
      if (!p) throw new Error('Karte ' + id + ' nicht antippbar');
      this.zeiger('pointerdown', p.x, p.y); await schlaf(60); this.zeiger('pointerup', p.x, p.y);
      await schlaf(80);
    },
    async wischHoch(id) {
      await this.sichtbar(id);
      const p = this.punkt(id);
      if (!p) throw new Error('Karte ' + id + ' nicht greifbar');
      this.zeiger('pointerdown', p.x, p.y);
      for (let i = 1; i <= 6; i++) { await schlaf(16); this.zeiger('pointermove', p.x + i, p.y - i * 30); }
      this.zeiger('pointerup', p.x + 6, p.y - 180);
      await schlaf(80);
    },
    async halten(id) {
      await this.sichtbar(id);
      const p = this.punkt(id);
      if (!p) throw new Error('Karte ' + id + ' nicht greifbar');
      this.zeiger('pointerdown', p.x, p.y); await schlaf(650); this.zeiger('pointerup', p.x, p.y);
      await schlaf(80);
    },
    klick(sel) { const e = typeof sel === 'string' ? $(sel) : sel; if (!e) throw new Error('fehlt: ' + sel); e.click(); },
    async farbeWaehlen() {
      await this.warte(() => this.app.tisch.farbwahlOffen, 3000, 'Farbwahl');
      const felder = this.app.tisch.farbwahl.querySelectorAll('.feld');
      this.klick(felder[this.zuege % felder.length]);
    },

    /* ---------- Prüfungen DOM gegen Sicht ---------- */
    pruefe() {
      const v = this.v, t = this.app.tisch;
      if (!v || !t) return;
      const els = t.hand.el.querySelectorAll('.hk');
      if (els.length !== (v.hand || []).length) this.fail('Hand: ' + els.length + ' Elemente, Sicht ' + v.hand.length);
      const faces = new Set((v.hand || []).map(c => c.face));
      els.forEach(e => { if (!faces.has(e.dataset.face)) this.fail('Handkarte ' + e.dataset.face + ' nicht in der Sicht'); });
      const ich = (v.players || []).find(p => p.seat === v.seat);
      if (ich && ich.count !== v.hand.length) this.fail('count ' + ich.count + ' ≠ Hand ' + v.hand.length);
      (v.players || []).forEach(p => {
        if (p.seat === v.seat) return;
        const g = t.gegnerBox.querySelector('.gg[data-seat="' + p.seat + '"] .zahl');
        if (!g) this.fail('Gegner ' + p.seat + ' fehlt');
        else if (g.textContent !== String(p.count)) this.fail('Gegner ' + p.seat + ': ' + g.textContent + ' statt ' + p.count);
      });
      const oben = t.ablageKarten.lastElementChild;
      if (v.top && (!oben || oben.dataset.face !== v.top.face)) this.fail('Ablage zeigt ' + (oben && oben.dataset.face) + ' statt ' + v.top.face);
      if (t.stapelZahl.textContent.indexOf(String(v.draw_count)) < 0) this.fail('Stapelzahl falsch');
      if (v.hints && v.hints.text && t.hinweis.textContent !== v.hints.text) this.fail('Hinweistext weicht ab');
      if (t.root.dataset.seite !== v.side) this.fail('Seite ' + t.root.dataset.seite + ' statt ' + v.side);
      if (this.app.fehler.length) this.app.fehler.forEach(f => this.fail('JS-Fehler: ' + f));
    },

    /* ---------- Ablauf ---------- */
    async lauf() {
      try {
        const app = this.app;
        await this.warte(() => document.body.dataset.screen === 'start', 3000, 'Startseite');
        $('#name').value = 'Autotest';
        this.klick('#beitreten');
        await this.warte(() => document.body.dataset.screen === 'lobby' && app.lobby, 8000, 'Lobby');
        if (!$('#lobby-liste .lz.ich')) this.fail('Lobby: eigener Eintrag fehlt');
        this.klick('#bereit');
        await this.warte(() => document.body.dataset.screen === 'tisch' && this.v && this.ruhig(), 15000, 'Tisch');
        this.pruefe();
        await this.toene();
        this.layoutTest();
        await this.bedienung();
        // Zählstand für die Mau-Prüfung am Ende (Ereignisse, Töne)
        this.mau0 = { mau: this.ereignisse.mau || 0, finish: this.ereignisse.finish || 0, toene: this.app.mauEreignisse || 0,
          blasen: this.app.tisch.blasenZahl || 0, mauTon: M.Ton.zaehler.mau || 0, mauMauTon: M.Ton.zaehler.mau_mau || 0 };
        let getrenntGetestet = !(this.mock || M.param('trennen'));
        while (this.zuege < this.ziel) {
          await this.warte(() => this.binDran() || this.rundeVorbei(), 60000, 'eigener Zug');
          this.pruefe();
          if (this.rundeVorbei()) {
            this.runden++;
            if (!$('#runde') || $('#runde').hidden) this.fail('Rundenende-Fenster fehlt');
            else {
              const zeilen = document.querySelectorAll('#runde-liste li').length;
              if (zeilen !== (this.v.players || []).length) this.fail('Rundenende: ' + zeilen + ' Zeilen für ' + (this.v.players || []).length + ' Spieler');
              if (!$('#runde-sieger').textContent) this.fail('Rundenende ohne Sieger');
              this.notiz('Rundenende: ' + $('#runde-sieger').textContent + ' [' + Array.from(document.querySelectorAll('#runde-liste li')).map(li => li.textContent.replace(/\s+/g, ' ')).join(' / ') + ']');
            }
            if (this.runden >= this.rundenZiel) break;
            const r = this.v.round;
            await this.warte(() => this.v.round !== r && this.ruhig(), 20000, 'nächste Runde');
            if (!$('#runde').hidden) this.fail('Rundenende-Fenster bleibt offen');
            continue;
          }
          if (!getrenntGetestet && this.zuege >= 3) { getrenntGetestet = true; await this.wiederverbinden(); continue; }
          await this.zug();
        }
        await this.warte(() => this.ruhig(), 10000, "Regie am Ende");
        this.pruefe();
        this.mauPruefung();
      } catch (e) {
        this.fail(String(e && e.message || e));
      }
      this.ende();
    },
    // reine Layoutfunktion der Hand: endliche Werte, Fächer bleibt im Bild, jede Fächerkarte hat einen eigenen Tippstreifen
    layoutTest() {
      const L = M.Hand;
      for (const [W, H] of [[1558, 720], [1600, 720], [1180, 860], [2100, 720]]) {
        for (let n = 1; n <= 40; n++) {
          const lay = L.layout(n, W, H, { scroll: Math.floor(n / 2) });
          if (lay.karten.some(k => !isFinite(k.x) || !isFinite(k.y) || !isFinite(k.rot))) { this.fail('Layout n=' + n + ': ungültige Werte'); continue; }
          if (!lay.band) {
            if (lay.karten[0].x - L.KW / 2 < 0 || lay.karten[n - 1].x + L.KW / 2 > W) this.fail('Fächer n=' + n + ' W=' + W + ' ragt hinaus');
            const order = lay.karten.map((q, j) => j).sort((a, b) => lay.karten[b].z - lay.karten[a].z);
            const hit = new Set(lay.karten.map((k, i) => {
              // Mitte des sichtbaren Streifens, 40 px unter der Oberkante, in Bühnenkoordinaten (Drehpunkt unten Mitte)
              const lx = -L.KW / 2 + Math.min(lay.step || L.KW, L.KW) / 2, ly = -L.KH + 40, a = k.rot * Math.PI / 180;
              const x = k.x + (lx * Math.cos(a) - ly * Math.sin(a)) * k.sc, y = k.y + L.KH + (lx * Math.sin(a) + ly * Math.cos(a)) * k.sc;
              return order.find(j => L.trifft(lay.karten[j], x, y)) === i;
            }));
            if (hit.has(false)) this.fail('Fächer n=' + n + ': Karte ohne eigenen Tippstreifen');
          } else if (n < 9 || (W >= 1550 && n < 14)) this.fail('Band schon bei n=' + n + ' W=' + W);
        }
      }
    },
    // alle synthetischen Klänge offline rendern: hörbar, aber ohne Übersteuerung
    // Spieltöne synthetisch (hörbar, ohne Übersteuerung); Mau-Aufnahmen: Spitze nahe −1 dBFS, Dauer plausibel
    async toene() {
      await Promise.race([M.Ton.geladen(), schlaf(8000)]);
      const erg = await M.Ton.pruefe();
      if (!erg) { this.notiz('Tonprüfung übersprungen'); return; }
      if (erg.mau !== undefined) this.fail('synthetischer Mau-Ton ist noch da');
      const teile = [];
      Object.keys(erg).forEach(n => {
        const p = erg[n];
        if (n.indexOf('datei:') === 0) {
          teile.push(n + '=' + p.spitze + '/' + p.dauer + 's');
          if (!(p.spitze >= 0.5 && p.spitze <= 1.0)) this.fail('Aufnahme ' + n + ': Spitze ' + p.spitze);
          if (!(p.dauer >= 0.25 && p.dauer <= 2.0)) this.fail('Aufnahme ' + n + ': Dauer ' + p.dauer + ' s');
          return;
        }
        teile.push(n + '=' + p);
        if (typeof p !== 'number') this.fail('Ton ' + n + ': ' + p);
        else if (p < 0.02 || p > 1) this.fail('Ton ' + n + ': Pegel ' + p);
      });
      this.notiz('Töne ' + teile.join(' '));
    },
    // Mau für alle (AGENTS.md Nr. 21): jedes Ereignis „mau“/„finish“ (auch fremder Plätze) ergibt genau einen Ton-Anstoß und eine Blase;
    // mit geladenen Aufnahmen und Ton an wurde die Datei wirklich abgespielt.
    mauPruefung() {
      const a = this.app, t = a.tisch, z = this.mau0;
      if (!z) return;
      const mau = (this.ereignisse.mau || 0) - z.mau, fertig = (this.ereignisse.finish || 0) - z.finish;
      const toene = (a.mauEreignisse || 0) - z.toene, blasen = (t.blasenZahl || 0) - z.blasen;
      if (toene !== mau + fertig) this.fail('Mau-Töne: ' + toene + ' Anstöße für ' + mau + ' Mau und ' + fertig + ' Fertig');
      if (blasen !== mau + fertig) this.fail('Mau-Blasen: ' + blasen + ' für ' + mau + ' Mau und ' + fertig + ' Fertig');
      if (this.dateienGeladen && !M.Ton.stumm && M.Ton.stufe !== 'aus') {
        const gm = (M.Ton.zaehler.mau || 0) - z.mauTon, gmm = (M.Ton.zaehler.mau_mau || 0) - z.mauMauTon;
        if (gm !== mau || gmm !== fertig) this.fail('Aufnahmen abgespielt: mau ' + gm + '/' + mau + ', mau_mau ' + gmm + '/' + fertig);
      }
      const varianten = Object.keys(t.blasenVarianten || {}).sort().map(k => k + '=' + t.blasenVarianten[k]).join(' ');
      this.notiz('Mau-Ereignisse ' + mau + ', Fertig ' + fertig + ', Blasen ' + blasen + (varianten ? ' [' + varianten + ']' : ''));
    },
    // Sortieren, Rückseiten, Kartenhilfe, Menü, Gegneransicht einmal bedienen
    async bedienung() {
      const t = this.app.tisch;
      // Mau-Ton zum Ereignis: Entprellung 1 s je Platz und Art (Platz 99 gibt es nicht → stört die Zählung der Partie nicht)
      const app = this.app;
      const n0 = app.mauEreignisse || 0;
      app.mauTon(99, 'mau'); app.mauTon(99, 'mau'); app.mauTon(99, 'mau_mau');
      if ((app.mauEreignisse || 0) !== n0 + 2) this.fail('Mau-Ton-Entprellung: ' + ((app.mauEreignisse || 0) - n0) + ' statt 2 Töne');
      app.mauEreignisse = n0;
      // Standard: Spieltöne aus, Mau-Ton normal (frisches Profil), nicht stumm
      if (M.Speicher.get('toene', null) === null && (app.einstellungen.toene !== 'aus' || M.Ton.toene !== 'aus')) this.fail('Spieltöne sind nicht standardmäßig aus');
      if (M.Speicher.get('ton', null) === null && M.Ton.stufe !== 'normal') this.fail('Mau-Ton ist nicht standardmäßig normal');
      if (M.Ton.stumm) this.fail('Ton ist von Anfang an stumm');
      // Ton-Knopf in der Ecke: stumm und wieder an
      this.klick('#ton-knopf'); await schlaf(40);
      if (!M.Ton.stumm || !app.einstellungen.stumm || !t.knTon.classList.contains('stumm')) this.fail('Ton-Knopf schaltet nicht stumm');
      if (M.Ton.spiele('mau')) this.fail('Mau-Ton spielt trotz stumm');
      this.klick('#ton-knopf'); await schlaf(40);
      if (M.Ton.stumm || t.knTon.classList.contains('stumm')) this.fail('Ton-Knopf schaltet nicht wieder an');
      if (M.Ton.spiele('karte')) this.fail('Spieltöne spielen, obwohl sie aus sind');
      // Aufnahmen (sfx/mau.* und sfx/mau_mau.*) über http geladen und dekodiert
      if (/^https?:/.test(location.protocol)) {
        const ende = Date.now() + 8000;
        while (Date.now() < ende && !(M.Ton.dateien.indexOf('mau') >= 0 && M.Ton.dateien.indexOf('mau_mau') >= 0)) await schlaf(100);
        const fehlt = M.Ton.MAU_TOENE.filter(n => M.Ton.dateien.indexOf(n) < 0);
        if (fehlt.length) this.fail('Mau-Aufnahmen nicht geladen: ' + fehlt.join(', ') + (M.Ton.bereit ? '' : ' (Web Audio nicht freigeschaltet)'));
        else { this.dateienGeladen = true; this.notiz('Mau-Aufnahmen geladen'); }
      }
      const vorher = this.app.einstellungen.sort;
      for (let i = 0; i < 3; i++) { this.klick('#sortieren'); await schlaf(60); }
      if (this.app.einstellungen.sort !== vorher) this.fail('Sortieren kehrt nicht zum Anfang zurück');
      if (!t.knRueck.hidden) {
        this.klick('#rueckseiten'); await schlaf(100);
        if (!t.hand.rueck) this.fail('Rückseiten lassen sich nicht zeigen');
        this.klick('#rueckseiten'); await schlaf(100);
        if (t.hand.rueck) this.fail('Rückseiten bleiben sichtbar');
      }
      const c = this.v.hand[0];
      await this.halten(c.id);
      if ($('#hilfe').hidden) this.fail('Kartenhilfe öffnet nicht (langes Drücken)');
      else if (!$('#hilfe-text').textContent) this.fail('Kartenhilfe ohne Text');
      this.klick('#hilfe .schliessen'); await schlaf(50);
      if (t.hand.gewaehlt !== null) t.hand.waehle(null);
      this.klick(t.knMenue); await schlaf(50);
      if ($('#menue').hidden) this.fail('Menü öffnet nicht');
      this.klick('#menue .knopf.haupt.schliessen'); await schlaf(50);
      const g = t.gegnerBox.querySelector('.gg');
      if (g) {
        const p = (this.v.players || []).find(x => x.seat === +g.dataset.seat);
        const toasts = document.querySelectorAll('.toast').length;
        this.klick(g.querySelector('.ava')); await schlaf(50);
        if (p && (!p.backs || !p.backs.length)) {
          // Rückseiten verdeckt (backs_visible=false): nur ein Hinweis mit der Kartenzahl, keine Ansicht
          if (!$('#ansicht').hidden) this.fail('Gegneransicht trotz verdeckter Rückseiten');
          else if (document.querySelectorAll('.toast').length <= toasts && toasts < 3) this.fail('Kein Hinweis bei verdeckten Rückseiten');
        } else if ($('#ansicht').hidden) this.fail('Gegneransicht öffnet nicht');
        else this.klick('#ansicht .schliessen');
      }
      await schlaf(50);
    },
    async wiederverbinden() {
      const app = this.app;
      const id = app.meineId, n = this.v.hand.length;
      app.verbindung.trennen(1200);
      await this.warte(() => !$('#verbinde').hidden, 3000, 'Anzeige „Verbinde neu“');
      await this.warte(() => $('#verbinde').hidden && app.verbindung.offen, 8000, 'Wiederverbindung');
      await this.warte(() => this.ruhig(), 5000, 'Regie nach Wiederverbindung');
      if (app.meineId !== id) this.fail('Nach Wiederverbindung andere Spieler-Kennung');
      if (this.v.hand.length !== n) this.fail('Nach Wiederverbindung andere Hand');
      if (document.body.dataset.screen !== 'tisch') this.fail('Nach Wiederverbindung nicht am Tisch');
      this.notiz('Wiederverbindung ok');
    },
    async zug() {
      const app = this.app, v = this.v, h = v.hints || {};
      const s0 = this.states, e0 = this.errs;
      const antwort = () => this.warte(() => this.states > s0 || this.errs > e0, 8000, 'Antwort auf Zug');
      if (h.need_color) { app.aktion({ a: 'wunsch' }); await this.farbeWaehlen(); await antwort(); this.zuege++; return; }
      if (h.can_challenge) {
        const knopf = this.app.tisch.aktionen.querySelector('button[data-a="' + (this.zuege % 2 ? 'challenge' : 'accept') + '"]');
        this.klick(knopf); await antwort(); this.zuege++; return;
      }
      const mauSchluessel = v.round + ':' + v.hand.length + ':' + (v.top && v.top.id);
      if (h.can_mau && this._mauVersucht !== mauSchluessel) {
        this._mauVersucht = mauSchluessel;
        const n0 = app.mauEreignisse || 0, b0 = app.tisch.blasenZahl || 0;
        const anzahl = () => (this.ereignisse.mau || 0) + (this.ereignisse.finish || 0);
        const ev0 = anzahl();
        this.klick('#mau');
        // kein Ton beim Drücken selbst – er kommt mit dem Ereignis „mau“ (sonst hörte man ihn hier doppelt)
        if ((app.mauEreignisse || 0) !== n0) this.fail('Mau-Ton schon beim Drücken (doppelt)');
        await antwort();
        if (this.errs > e0) { this.fail('Mau! abgelehnt'); return; }
        await this.warte(() => this.ruhig(), 8000, 'Regie nach Mau');
        const eigene = app.tisch.flug.querySelector('.mau-blase[data-seat="' + v.seat + '"]') || (app.tisch.blasenZahl || 0) > b0;
        const dEv = anzahl() - ev0;
        if (dEv < 1) this.fail('Kein Ereignis „mau“ nach eigenem Ruf');
        if ((app.mauEreignisse || 0) - n0 !== dEv) this.fail('Mau-Ton nach eigenem Ruf: ' + ((app.mauEreignisse || 0) - n0) + ' Anstöße für ' + dEv + ' Ereignisse');
        if (!eigene) this.fail('Keine Mau-Blase nach eigenem Ruf');
        this.notiz('Mau! gerufen');
        return;
      }
      if (h.catch && h.catch.length) {
        const k = this.app.tisch.gegnerBox.querySelector('.gg.fangbar .erwischen');
        if (!k) this.fail('Erwischen-Knopf fehlt');
        else { this.klick(k); await antwort(); return; }
      }
      const spielbar = h.playable || [];
      if (spielbar.length) {
        const id = spielbar[this.zuege % spielbar.length];
        const c = v.hand.find(x => x.id === id);
        if (this.zuege % 3 === 1) await this.wischHoch(id);
        else { await this.tippe(id); if (app.tisch.hand.gewaehlt !== id) this.fail('Antippen hebt die Karte nicht an'); await this.tippe(id); }
        if (Array.isArray(h.wild) ? h.wild.indexOf(id) >= 0 : M.Karten.istJoker(c.face)) await this.farbeWaehlen();
        await antwort();
        if (this.errs > e0) this.fail('Zug abgelehnt: ' + c.face);
        else this.ereignisse.eigeneKarte = (this.ereignisse.eigeneKarte || 0) + 1;
        this.zuege++;
        return;
      }
      if (h.can_keep) { this.klick(app.tisch.aktionen.querySelector('button[data-a="keep"]')); await antwort(); this.zuege++; return; }
      if (h.can_draw) { this.klick('#stapel'); await antwort(); this.zuege++; return; }
      this.fail('Am Zug, aber keine Möglichkeit: ' + JSON.stringify(h));
      throw new Error('festgefahren');
    },
    ende() {
      if (this._fertig) return;
      this._fertig = true;
      const ok = !this.fehler.length;
      if (this.wischte) this.notiz('Band gewischt: ' + this.wischte);
      const ev = Object.keys(this.ereignisse).sort().map(k => k + '=' + this.ereignisse[k]).join(' ');
      const text = (ok ? 'OK' : 'FAIL') + ': ' + this.zuege + ' Züge, ' + this.runden + ' Rundenenden, ' + this.states + ' Zustände, ' + this.errs + ' Ablehnungen, ' +
        Math.round((Date.now() - this.t0) / 1000) + ' s | Ereignisse: ' + ev + (this.notizen.length ? ' | ' + this.notizen.join('; ') : '') + (ok ? '' : ' | FEHLER: ' + this.fehler.join(' || '));
      let r = $('#autotest-result');
      if (!r) { r = document.createElement('pre'); r.id = 'autotest-result'; document.body.appendChild(r); }
      r.dataset.ok = ok ? '1' : '0';
      r.textContent = text;
      document.title = ok ? 'AUTOTEST-OK' : 'AUTOTEST-FAIL';
      // Ergebnis auch an den Gastgeber (Testgastgeber wertet es aus; im Spiel landet es nur im Netzprotokoll)
      if (!this.mock && this.app.verbindung && this.app.verbindung.offen) this.app.sende({ t: 'log', text: 'AUTOTEST ' + text.slice(0, 1500) });
      if (halter) setTimeout(() => { if (halter) { halter.remove(); halter = null; } }, 300);
      r.style.cssText = 'position:fixed;left:8px;bottom:8px;z-index:9999;max-width:90vw;white-space:pre-wrap;font:12px monospace;background:' + (ok ? '#CFF1D7' : '#FFE1E3') + ';color:#211B2C;padding:6px 8px;border-radius:8px;pointer-events:none;';
      if (window.console) console.log('AUTOTEST ' + text);
    },
  };
  M.Autotest = T;
})(window.MMF = window.MMF || {});
