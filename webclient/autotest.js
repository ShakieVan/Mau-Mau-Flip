/* Mau-Mau Flip – Browser-Client „Lite“: Selbsttest (index.html?mock=1&autotest=1, später auch gegen einen echten Gastgeber).
 * Spielt über die echte Oberfläche (synthetische Zeigerereignisse auf der Hand, Klicks auf Knöpfe), prüft nach jedem
 * Abgleich DOM gegen Sicht und schreibt das Ergebnis nach #autotest-result (data-ok="1"/"0"), auswertbar mit --dump-dom.
 * Parameter: zuege=N (eigene Züge, Standard 14), runden=N (Abbruch nach N Rundenenden, Standard 2),
 * pflicht=tausch,ablegen,gluecksspiel,beliebig (diese Hausregel-Karten muss der Test selbst gespielt haben; Glücksspiel samt Setzen und Drücken;
 *   beliebig = nach dem Ziehen eine andere als die gezogene Karte gelegt, Hausregel draw_play "any").
 * Hausregeln: bevorzugt Kartentausch, Ablegen-Karten und Glücksspiel, setzt im Glücksspiel per Antippen und drückt den Knopf; prüft
 * Automat, Einsatzstapel und Zahlenwerk gegen view.gamble sowie die Einstellung „Spielbare Karten hervorheben“ (aus: Hinweis
 * „Die Karte passt nicht.“) und im Mock den gesperrten Speicher.
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
  const PHASEN = ['idle', 'turn', 'drawn', 'challenge', 'color', 'gamble', 'discard_pick', 'round_over', 'game_over'];
  const HINT_FELDER = { playable: 'array', wild: 'array', can_draw: 'boolean', can_keep: 'boolean', can_challenge: 'boolean', can_accept: 'boolean',
    can_mau: 'boolean', catch: 'array', need_color: 'boolean', can_next_round: 'boolean', text: 'string' };
  const SICHT_FELDER = { seat: 'number', side: 'string', phase: 'string', turn: 'number', dir: 'number', color: 'string', players: 'array', hand: 'array',
    top: 'object', draw_back: 'string', draw_count: 'number', pending: 'object', hints: 'object', round: 'number', ranking: 'array', rules: 'object', result: 'object', discard_log: 'array' };
  // Einträge von view.discard_log (Ablage von unten nach oben, öffentlich): Gesicht ("" verdeckt), Leger (-1 Startkarte), Wunschfarbe, verdeckter Einsatz
  const DISCARD_FELDER = { f: 'string', s: 'number', c: 'string', h: 'boolean' };
  const SPIELER_FELDER = { seat: 'number', name: 'string', kind: 'string', count: 'number', backs: 'array', place: 'number', mau: 'boolean', connected: 'boolean', score: 'number' };
  // Nur mit der Hausregel Glücksspiel (rules.gamble_cards = "on"); ohne sie fehlen die Felder (der Client rechnet mit Standardwerten)
  const HINT_GLUECK = { can_stake: 'array', can_press: 'boolean', can_stop: 'boolean' };
  const SICHT_GLUECK = { gamble: 'object' };
  const GLUECK_FELDER = { seat: 'number', stake: 'number', need: 'string', last: 'number' };
  const art = x => Array.isArray(x) ? 'array' : (x === null ? 'null' : typeof x);
  // Ereignisse, die der Client kennt (Effekt in tisch.js oder bewusst ohne Effekt)
  const EREIGNISSE = ['deal', 'play', 'draw', 'skip', 'skip_all', 'reverse', 'color', 'flip', 'pending', 'challenge', 'mau', 'catch', 'penalty', 'shuffle',
    'round_over', 'game_over', 'finish', 'pass', 'choose_color', 'seats', 'leave_cards', 'round_start', 'start', 'turn', 'keep', 'accept',
    'swap_hands', 'gamble_start', 'stake', 'gamble_roll', 'stake_back', 'stake_discard', 'discard_color', 'discard_pick', 'flip_surprise'];
  // Hausregel-Karten, die der Selbsttest bevorzugt legt (damit Kartentausch, Farbe ablegen und Glücksspiel sicher vorkommen)
  const VORRANG = { tausch: 1, ablegen: 2, ablegen_joker: 3, gluecksspiel: 4 };

  const T = {
    start(app) {
      this.app = app;
      this.t0 = Date.now();
      this.zuege = 0; this.runden = 0; this.states = 0; this.errs = 0; this.ereignisse = {};
      this.fehler = []; this.notizen = [];
      this.haus = { tausch: 0, ablegen: 0, ablegen_joker: 0, gluecksspiel: 0, gesetzt: 0, gedrueckt: 0, aufgehoert: 0, ausgewaehlt: 0, abgewaehlt: 0, beliebig: 0, behalten: 0 };
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
    // Glücksspiel-Felder (auch gegen das Mock): da genau mit der Hausregel, Form wie docs/BETA1_PLAN.md Abschnitt 4
    vertragGlueck(v) {
      if (!v) return;
      const h = v.hints || {}, an = !!(v.rules && v.rules.gamble_cards === 'on');
      Object.keys(SICHT_GLUECK).forEach(k => { if (an ? art(v[k]) !== SICHT_GLUECK[k] : v[k] !== undefined) this.fail('Sicht.' + k + (an ? ': ' + art(v[k]) : ' ohne Hausregel')); });
      Object.keys(HINT_GLUECK).forEach(k => { if (an ? art(h[k]) !== HINT_GLUECK[k] : h[k] !== undefined) this.fail('hints.' + k + (an ? ': ' + art(h[k]) : ' ohne Hausregel')); });
      const g = v.gamble;
      if (!an || !g || art(g) !== 'object') return;
      const laeuft = Object.keys(g).length > 0;
      if (laeuft !== (v.phase === 'gamble')) this.fail('gamble ' + JSON.stringify(g) + ' in Phase ' + v.phase);
      if (laeuft) {
        Object.keys(GLUECK_FELDER).forEach(k => { if (art(g[k]) !== GLUECK_FELDER[k]) this.fail('gamble.' + k + ': ' + art(g[k])); });
        if (['stake', 'press'].indexOf(g.need) < 0) this.fail('gamble.need ' + g.need);
        if (g.seat !== v.turn) this.fail('gamble.seat ≠ turn');
        if (g.q !== undefined) this.fail('Trefferquote in der Sicht');
        const ich = g.seat === v.seat;
        const ids = new Set((v.hand || []).map(c => c.id));
        if ((h.can_stake || []).some(id => !ids.has(id))) this.fail('can_stake nicht in der Hand');
        if (ich && g.need === 'stake' && (h.can_stake || []).length !== (v.hand || []).length) this.fail('can_stake ≠ ganze Hand');
        if ((!ich || g.need !== 'stake') && (h.can_stake || []).length) this.fail('can_stake außerhalb des eigenen Setzens');
        if (!!h.can_press !== (ich && g.need === 'press')) this.fail('can_press passt nicht zu gamble.need');
        if (!!h.can_stop !== (ich && g.need === 'stake' && (g.stake | 0) >= 1)) this.fail('can_stop passt nicht zu gamble.need/stake');
        if ((h.playable || []).length || h.can_draw) this.fail('playable/can_draw im Glücksspiel');
      } else if ((h.can_stake || []).length || h.can_press || h.can_stop) this.fail('can_stake/can_press/can_stop ohne Glücksspiel');
    },
    // Farbe mit ablegen (Phase discard_pick): discard_pick {seat, color} für alle, ohne Kandidatenzahl; can_pick nur für den Wählenden
    vertragAblegen(v) {
      if (!v) return;
      const h = v.hints || {}, dp = v.discard_pick;
      if (h.can_pick !== undefined && !Array.isArray(h.can_pick)) this.fail('hints.can_pick: ' + art(h.can_pick));
      if (v.phase !== 'discard_pick') {
        if (dp && Object.keys(dp).length) this.fail('discard_pick außerhalb der Phase');
        if ((h.can_pick || []).length) this.fail('can_pick außerhalb der Phase');
        return;
      }
      if (!dp || typeof dp.seat !== 'number' || typeof dp.color !== 'string') { this.fail('discard_pick ' + JSON.stringify(dp)); return; }
      if (Object.keys(dp).some(k => k !== 'seat' && k !== 'color')) this.fail('discard_pick verrät mehr: ' + Object.keys(dp).join(','));
      const ich = dp.seat === v.seat;
      if (!ich && (h.can_pick || []).length) this.fail('can_pick bei fremder Auswahl');
      (h.can_pick || []).forEach(id => {
        const c = (v.hand || []).find(x => x.id === id);
        if (!c) this.fail('can_pick nicht in der Hand');
        else if (M.Karten.istJoker(c.face) || M.Karten.zerlege(c.face).farbe !== dp.color) this.fail('can_pick mit falscher Karte ' + c.face);
      });
      if ((h.playable || []).length || h.can_draw) this.fail('playable/can_draw in discard_pick');
    },
    // Ablage durchsehen (auch gegen das Mock): Form je Eintrag, letzter Eintrag = oberste Karte, verdeckte Einsätze ohne Gesicht
    vertragAblage(v) {
      if (!v || !v.top) return;
      const log = v.discard_log;
      if (!Array.isArray(log)) { this.fail('Sicht.discard_log fehlt'); return; }
      if (!log.length) { this.fail('discard_log leer trotz Ablage'); return; }
      log.forEach(e => Object.keys(DISCARD_FELDER).forEach(k => { if (art(e[k]) !== DISCARD_FELDER[k]) this.fail('discard_log[].' + k + ': ' + art(e[k])); }));
      if (log.some(e => e.h && e.f !== '')) this.fail('discard_log: verdeckter Einsatz mit Gesicht');
      if (log.some(e => e.s < -1 || e.s >= (v.players || []).length)) this.fail('discard_log: Platz außerhalb');
      if (log[log.length - 1].f !== v.top.face) this.fail('discard_log: letzter Eintrag ' + log[log.length - 1].f + ' ≠ top ' + v.top.face);
      this.ereignisse.ablageLog = Math.max(this.ereignisse.ablageLog || 0, log.length);
    },
    // &protokoll=1: Ablauf (Stände, eigene Entscheidungen) ans Ergebnis hängen, zur Fehlersuche
    prot(t) { if (M.param('protokoll')) { (this._prot = this._prot || []).push(t); if (this._prot.length > 60) this._prot.shift(); } },
    zustand(m) {
      this.states++;
      if (m.view) this.prot('S t' + m.view.turn + ' ' + m.view.phase + ' [' + (m.events || []).map(e => e.e + (e.seat !== undefined ? e.seat : '')).join(',') + '] h' + (m.view.hand || []).length);
      (m.events || []).forEach((e, i) => {
        this.ereignisse[e.e] = (this.ereignisse[e.e] || 0) + 1;
        if (!this.mock && EREIGNISSE.indexOf(e.e) < 0) this.fail('unbekanntes Ereignis ' + e.e);
        // verdeckte Information: fremde Einsatzkarten nie, die eigene neue Hand nach dem Tausch nur selbst
        if (e.e === 'stake' && m.view && e.seat !== m.view.seat && (e.face !== undefined || e.card !== undefined)) this.fail('fremde Einsatzkarte sichtbar');
        if (e.e === 'stake_discard' && ['stop', 'empty'].indexOf(e.reason) < 0) this.fail('stake_discard.reason ' + e.reason);
        if (e.e === 'gamble_roll' && !(e.value >= 0 && e.value <= 10)) this.fail('gamble_roll.value ' + e.value);
        if (e.e === 'swap_hands' && !Array.isArray(e.counts)) this.fail('swap_hands ohne counts');
        if (e.e === 'discard_color' && (!Array.isArray(e.faces) || e.faces.length !== (e.count | 0))) this.fail('discard_color: faces ≠ count');
        // Flip-Überraschung: nur mit der Hausregel, direkt nach einem Flip (bzw. der Farbwahl danach), Gesicht = Aktions- oder Zusatzkarte oben
        if (e.e === 'flip_surprise') {
          const ar = typeof e.face === 'string' ? M.Karten.zerlege(e.face).art : '';
          if (typeof e.seat !== 'number' || ['plus1', 'plus5', 'aussetzen', 'alle_aussetzen', 'richtungswechsel', 'wuenscher_plus2', 'farbjagd', 'tausch', 'gluecksspiel', 'ablegen', 'ablegen_joker'].indexOf(ar) < 0) this.fail('flip_surprise ' + JSON.stringify(e));
          if (m.view && m.view.rules && m.view.rules.flip_surprise !== 'on') this.fail('flip_surprise ohne Hausregel');
          const vor = (m.events || [])[i - 1];
          if (vor && ['flip', 'color', 'choose_color'].indexOf(vor.e) < 0) this.fail('flip_surprise nicht direkt nach flip/color');
        }
      });
      try { this.vertrag(m.view); this.vertragGlueck(m.view); this.vertragAblegen(m.view); this.vertragAblage(m.view); } catch (e) { this.fail('Vertrag: ' + e); }
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
      return (v.turn === v.seat && (v.phase === 'turn' || v.phase === 'drawn' || v.phase === 'challenge' || v.phase === 'gamble' || v.phase === 'discard_pick')) || !!h.need_color || !!h.can_challenge;
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
        const f = h._f ? h._f() : 1;
        if (h.trefferId(x, y) === id) return { x: r.left + t.ox + x * f * t.s, y: r.top + t.oy + y * f * t.s };
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
      const dx = (h.scroll - i) * lay.step * t.s * (h._f ? h._f() : 1);
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
      this.prot('tipp ' + id + (p ? '' : ' (nicht sichtbar)') + ' g' + this.app.tisch.hand.gewaehlt + ' t' + (this.v && this.v.turn));
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
    // Farbe mit den meisten Karten auf der Hand (wichtig für den Ablegen-Joker), bei Gleichstand reihum
    async farbeWaehlen() {
      await this.warte(() => this.app.tisch.farbwahlOffen, 3000, 'Farbwahl');
      const felder = Array.from(this.app.tisch.farbwahl.querySelectorAll('.feld'));
      const anzahl = f => parseInt((f.querySelector('i') || {}).textContent, 10) || 0;
      const max = Math.max.apply(null, felder.map(anzahl));
      const beste = felder.filter(f => anzahl(f) === max);
      this.klick(beste[this.zuege % beste.length]);
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
      if (!this.app._vor && (!M.Spass || M.Spass.stufe === 'aus') && t.hinweis.textContent !== 'Tippe auf eine Karte der Farbe, die du mit ablegen willst.' && v.hints && v.hints.text && t.hinweis.textContent !== t.hinweisText(v.hints.text)) this.fail('Hinweistext weicht ab: ' + t.hinweis.textContent + ' | ' + v.hints.text + ' | ph ' + v.phase);
      if (!this.app.hervorheben() && t.hinweis.textContent.indexOf('nichts passt') >= 0) this.fail('Hinweis verrät „nichts passt“ trotz Hervorheben aus');
      if (t.root.dataset.seite !== v.side) this.fail('Seite ' + t.root.dataset.seite + ' statt ' + v.side);
      if (this.app.fehler.length) this.app.fehler.forEach(f => this.fail('JS-Fehler: ' + f));
      if (t.hand.el.getAttribute('style')) this.fail('Hand bleibt nach dem Kartentausch verschoben');
      // Glücksspiel: Automat, Zahlenwerk und Einsatzstapel folgen der Sicht
      const g = v.phase === 'gamble' && v.gamble && typeof v.gamble.seat === 'number' ? v.gamble : null;
      if (g) {
        if (t.automat.hidden || !t.automatAktiv) this.fail('Glücksspiel-Automat fehlt');
        if ((g.stake | 0) > 0) {
          if (t.einsatz.hidden) this.fail('Einsatzstapel fehlt');
          else if (t.einsatz.querySelector('.zahl').textContent !== String(g.stake)) this.fail('Einsatz zeigt ' + t.einsatz.querySelector('.zahl').textContent + ' statt ' + g.stake);
        } else if (!t.einsatz.hidden) this.fail('Einsatzstapel ohne Einsatz');
        if (g.last >= 0 && t.walze.textContent.trim() !== String(g.last)) this.fail('Zahlenwerk zeigt ' + t.walze.textContent + ' statt ' + g.last);
        if (t.automat.classList.contains('drueckbar') !== !!(v.hints || {}).can_press) this.fail('Glücksspielknopf-Zustand passt nicht zu can_press');
      } else if (t.automatAktiv || !t.einsatz.hidden) this.fail('Automat oder Einsatz bleibt nach dem Glücksspiel');
      // großer Modus (?gross=1): Liste mit allen Plätzen, wer dran ist, steht oben (k = 0), der Nächste in Spielrichtung darunter
      if (t.gross) {
        const n = (v.players || []).length, laeuft = v.phase !== 'round_over' && v.phase !== 'game_over';
        if (t.gegnerBox.querySelectorAll('.gg').length !== n) this.fail('Großer Modus: Liste hat ' + t.gegnerBox.querySelectorAll('.gg').length + ' statt ' + n + ' Zeilen');
        const g0 = t.gegnerEls.get(v.turn);
        const turnP = (v.players || []).find(p => p.seat === v.turn);
        if (laeuft && n > 1 && !(turnP && turnP.place > 0) && (!g0 || g0.k !== 0)) this.fail('Großer Modus: Spieler am Zug steht nicht oben');
        if (!t.gegnerEls.get(v.seat)) this.fail('Großer Modus: eigene Zeile fehlt');
        // fertige Spieler („bis zum Letzten“) verschwinden, solange die Runde läuft
        if (laeuft) (v.players || []).forEach(p => { const g = t.gegnerEls.get(p.seat); if (g && p.place > 0 && !g.e.classList.contains('aus')) this.fail('Großer Modus: fertiger Spieler ' + p.seat + ' bleibt in der Liste'); });
        if (!t.root.classList.contains('gross')) this.fail('Großer Modus: #tisch.gross fehlt');
      }
      // persönliche Einstellung: ohne Hervorhebung weder Leuchten noch Abdunkeln
      if (!this.app.hervorheben() && t.hand.el.querySelector('.hk.spielbar, .hk.matt')) this.fail('Hervorhebung trotz Einstellung „aus“');
    },

    /* ---------- Ablauf ---------- */
    async lauf() {
      try {
        const app = this.app; if (M.Spass && M.Spass.setzeStufe) M.Spass.setzeStufe('aus');   // Sprüche (1.4.4) ersetzen den Hinweis
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
        await this.durchsehenTest();
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
          if (M.Ton.istMau(n.slice(6))) {   // Aufnahmen des Nutzers: laut ausgesteuert
            if (!(p.spitze >= 0.5 && p.spitze <= 1.0)) this.fail('Aufnahme ' + n + ': Spitze ' + p.spitze);
            if (!(p.dauer >= 0.25 && p.dauer <= 2.0)) this.fail('Aufnahme ' + n + ': Dauer ' + p.dauer + ' s');
          } else {                          // Spieltöne aus sfx/: hörbar, ohne Übersteuerung, kurz
            if (!(p.spitze >= 0.05 && p.spitze <= 1.0)) this.fail('Spielton ' + n + ': Spitze ' + p.spitze);
            if (!(p.dauer >= 0.05 && p.dauer <= 3.0)) this.fail('Spielton ' + n + ': Dauer ' + p.dauer + ' s');
          }
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
    // Ablage durchsehen: zwei Karten zur Seite, eine zurück, Tipp daneben schiebt alle zurück (am Ende, dann ist die Ablage länger)
    async durchsehenTest() {
      const t = this.app.tisch, log = (this.v && this.v.discard_log) || [], sig = t._durchSig;
      if (log.length < 2) { this.notiz('Ablage durchsehen: nur ' + log.length + ' Karte(n)'); return; }
      const fehler = [];
      this.klick('#ablage'); this.klick('#ablage'); await schlaf(30);
      const z = ($('#seitenstapel .zaehler') || {}).textContent;
      if (t.durch !== 2 || $('#seitenstapel').hidden || z !== '2 von ' + log.length) fehler.push('Ablage durchsehen: ' + t.durch + ' / ' + z);
      if (!$('#seitenstapel .von').textContent) fehler.push('Ablage durchsehen: Leger fehlt');
      this.klick('#seitenstapel'); await schlaf(30);
      if (t.durch !== 1) fehler.push('Seitenstapel schiebt nicht zurück (' + t.durch + ')');
      t.stapelZahl.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
      await schlaf(30);
      if (t.durch !== 0 || !$('#seitenstapel').hidden) fehler.push('Tipp daneben schiebt nicht alles zurück');
      if (t._durchSig !== sig) { this.notiz('Ablage durchsehen: Ablage hat sich währenddessen geändert'); return; }
      fehler.forEach(f => this.fail(f));
      this.ereignisse.durchgesehen = log.length;
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
      // Aufnahmen (sfx/mau.* und sfx/mau_mau.*) und Spieltöne (alle Einträge aus sfx/index.json) über http geladen und dekodiert
      if (/^https?:/.test(location.protocol)) {
        let liste = null;
        try { liste = await fetch('sfx/index.json', { cache: 'no-store' }).then(r => r.json()); } catch (e) { this.fail('sfx/index.json nicht lesbar'); }
        const namen = Object.keys(liste || {});
        M.Ton.MAU_TOENE.concat(M.Ton.SPIEL_TOENE).forEach(n => { if (namen.indexOf(n) < 0) this.fail('sfx/index.json nennt „' + n + '“ nicht'); });
        const ende = Date.now() + 8000;
        while (Date.now() < ende && namen.some(n => M.Ton.dateien.indexOf(n) < 0)) await schlaf(100);
        const fehlt = M.Ton.MAU_TOENE.filter(n => M.Ton.dateien.indexOf(n) < 0);
        if (fehlt.length) this.fail('Mau-Aufnahmen nicht geladen: ' + fehlt.join(', ') + (M.Ton.bereit ? '' : ' (Web Audio nicht freigeschaltet)'));
        else { this.dateienGeladen = true; this.notiz('Mau-Aufnahmen geladen'); }
        const spiel = namen.filter(n => !M.Ton.istMau(n));
        const fehltSpiel = spiel.filter(n => M.Ton.dateien.indexOf(n) < 0);
        if (fehltSpiel.length) this.fail('Spieltöne nicht geladen: ' + fehltSpiel.join(', '));
        else this.notiz('Spieltöne geladen: ' + spiel.length);
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
      // „Spielbare Karten hervorheben“: persönliche Einstellung (Standard an); hier ausschalten, den Hinweis „Die Karte passt nicht.“
      // prüft der nächste passende eigene Zug (zug), danach wieder an
      const an = $('#menue button[data-set="hervorheben"][data-wert="true"]'), aus = $('#menue button[data-set="hervorheben"][data-wert="false"]');
      if (!an || !aus) this.fail('Einstellung „Spielbare Karten hervorheben“ fehlt im Menü');
      else {
        if (M.Speicher.get('hervorheben', null) === null && (!app.hervorheben() || !an.classList.contains('an'))) this.fail('Hervorheben ist nicht standardmäßig an');
        this.klick(aus); await schlaf(60);
        if (app.hervorheben() || !aus.classList.contains('an')) this.fail('Hervorheben lässt sich nicht ausschalten');
        if (t.hand.el.querySelector('.hk.spielbar, .hk.matt')) this.fail('Hervorhebung bleibt nach „Aus“');
        if (M.Speicher.get('hervorheben', null) !== false) this.notiz('Speicher nicht verfügbar – Einstellung gilt bis zum Neuladen');
        this.ohneHervorheben = true;
      }
      this.klick('#menue .knopf.haupt.schliessen'); await schlaf(50);
      if (this.mock) this.ohneSpeicher();
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
    // Gesperrter Speicher (privater Modus, blockierte Website-Daten): localStorage wirft → Standardwerte, Einstellen klappt trotzdem
    ohneSpeicher() {
      const eigen = Object.getOwnPropertyDescriptor(window, 'localStorage');
      try { Object.defineProperty(window, 'localStorage', { configurable: true, get() { throw new Error('gesperrt'); } }); } catch (e) { this.notiz('localStorage nicht ersetzbar'); return; }
      try {
        if (M.Speicher.get('hervorheben', 'standard') !== 'standard') this.fail('Speicher liefert ohne localStorage nicht den Standardwert');
        M.Speicher.set('hervorheben', true);
        const vorher = this.app.einstellungen.hervorheben;
        this.app.einstellen('hervorheben', String(!vorher));
        if (this.app.einstellungen.hervorheben === vorher) this.fail('Einstellen ohne localStorage wirkt nicht');
        this.app.einstellen('hervorheben', String(vorher));
        this.app.schliesse('menue');
        this.notiz('ohne localStorage ok');
      } catch (e) { this.fail('Ohne localStorage: ' + e.message); } finally {
        if (eigen) Object.defineProperty(window, 'localStorage', eigen); else delete window.localStorage;
      }
      try { window.localStorage.getItem('mmf.x'); } catch (e) { this.fail('localStorage nach dem Test nicht wiederhergestellt'); }
    },
    async wiederverbinden() {
      const app = this.app;
      const id = app.meineId, n = this.v.hand.length;
      app.verbindung.trennen(1200);
      await this.warte(() => !$('#verbinde').hidden, 3000, 'Anzeige „Verbinde neu“');
      const s0 = this.states;
      await this.warte(() => $('#verbinde').hidden && app.verbindung.offen, 8000, 'Wiederverbindung');
      // erst den frischen Stand des Gastgebers abwarten (kommt kurz nach dem Öffnen), sonst hielte der nächste Zug ihn für seine Antwort
      await this.warte(() => this.states > s0 && !!this.v && this.ruhig(), 8000, 'Stand nach Wiederverbindung');
      if (app.meineId !== id) this.fail('Nach Wiederverbindung andere Spieler-Kennung');
      if (this.v.hand.length !== n) this.fail('Nach Wiederverbindung andere Hand');
      if (document.body.dataset.screen !== 'tisch') this.fail('Nach Wiederverbindung nicht am Tisch');
      this.notiz('Wiederverbindung ok');
    },
    async zug() {
      const app = this.app, v = this.v, h = v.hints || {};
      this.prot('ZUG t' + v.turn + ' ' + v.phase + ' sp' + JSON.stringify(h.playable) + ' g' + app.tisch.hand.gewaehlt);
      const s0 = this.states, e0 = this.errs;
      const antwort = () => this.warte(() => this.states > s0 || this.errs > e0, 8000, 'Antwort auf Zug');
      if (h.need_color && app.ablegeWunsch(v)) {   // Flip-Überraschung mit Ablegen-Joker: Ablegefarbe per Tipp (ohne farbige Karten gleich weiter)
        app.aktion({ a: 'wunsch' });
        if (app._vor) { const kv = app.vorKarten(v); await this.tippe(kv[this.zuege % kv.length]); this.haus.vorwahl = (this.haus.vorwahl | 0) + 1; }
        await antwort(); this.zuege++; return;
      }
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
      // Farbe mit ablegen: alle Kandidaten vorausgewählt; jeder zweite Durchgang wählt eine ab; beim Joker danach die Spielfarbe
      if (v.phase === 'discard_pick' && v.discard_pick && v.discard_pick.seat === v.seat) {
        const t = app.tisch, kand = h.can_pick || [];
        const knopf = () => t.aktionen.querySelector('button[data-a="ablegen"]');
        if (!knopf() || knopf().textContent !== 'Ablegen (' + kand.length + ')') this.fail('Knopf „Ablegen (' + kand.length + ')“ fehlt: ' + (knopf() ? knopf().textContent : '-'));
        if (t.hand.el.querySelectorAll('.hk.kandidat.spielbar').length !== kand.length) this.fail('Kandidaten nicht alle vorausgewählt');
        let n = kand.length;
        if (kand.length && this.zuege % 2) {
          await this.tippe(kand[0]); n--;
          if (!knopf() || knopf().textContent !== 'Ablegen (' + n + ')') this.fail('Abwählen ändert den Knopf nicht');
          else this.haus.abgewaehlt++;
        }
        const ev0 = this.ereignisse.discard_color | 0;
        this.klick(knopf());
        const joker = h.pick_color !== undefined ? !!h.pick_color : !!(v.top && M.Karten.zerlege(v.top.face).art === 'ablegen_joker');
        if (joker) {
          await this.warte(() => t.farbwahlOffen, 3000, 'Spielfarbe');
          if (t.farbwahl.querySelector('.frage').textContent !== 'Mit welcher Farbe geht es weiter?') this.fail('Frage der Spielfarbe fehlt');
          await this.farbeWaehlen();
        }
        await antwort();
        if (this.errs > e0) this.fail('Ablegen-Auswahl abgelehnt');
        else {
          this.haus.ausgewaehlt++;
          await this.warte(() => this.ruhig(), 8000, 'Regie nach dem Ablegen');
          if ((this.ereignisse.discard_color | 0) <= ev0) this.fail('Kein discard_color nach der Auswahl');
        }
        this.zuege++; return;
      }
      // Glücksspiel: Karte antippen = verdeckt setzen, dann den Kuppelknopf des Automaten drücken
      if (v.phase === 'gamble' && v.turn === v.seat) {
        const t = app.tisch;
        if (h.can_press) {
          if (t.automat.hidden || !t.automat.classList.contains('drueckbar')) this.fail('Glücksspielknopf nicht bereit');
          this.klick('#gluecksknopf'); await antwort();
          if (this.errs > e0) this.fail('Drücken abgelehnt'); else this.haus.gedrueckt++;
          this.zuege++; return;
        }
        // Knopf „Aufhören“ genau mit can_stop; manchmal aufhören (immer erlaubt nach einem Druck ohne Treffer)
        const stopK = t.automat.querySelector('.aufhoeren');
        if (!stopK || stopK.hidden === !!h.can_stop) this.fail('Aufhören-Knopf passt nicht zu can_stop');
        if (h.can_stop && stopK && (this.zuege % 3 === 1 || ((v.gamble && v.gamble.stake) | 0) >= 3)) {
          this.klick(stopK); await antwort();
          if (this.errs > e0) this.fail('Aufhören abgelehnt'); else this.haus.aufgehoert++;
          this.zuege++; return;
        }
        const setzbar = h.can_stake || [];
        if (setzbar.length) {
          const n0 = (v.gamble && v.gamble.stake) | 0;
          await this.tippe(setzbar[this.zuege % setzbar.length]); await antwort();
          if (this.errs > e0) this.fail('Setzen abgelehnt');
          else {
            this.haus.gesetzt++;
            await this.warte(() => this.ruhig(), 8000, 'Regie nach dem Setzen');
            const z = this.app.tisch.einsatz.querySelector('.zahl').textContent;
            if (this.v.phase === 'gamble' && z !== String(n0 + 1)) this.fail('Einsatzstapel zeigt ' + z + ' statt ' + (n0 + 1));
          }
          this.zuege++; return;
        }
      }
      // ohne Hervorhebung: unpassende Karte zweimal antippen → nur der Hinweis, nichts wird gesendet
      if (this.ohneHervorheben && v.phase === 'turn' && !(v.pending && v.pending.kind)) {
        const unpassend = (v.hand || []).find(c => (h.playable || []).indexOf(c.id) < 0);
        if (unpassend) { await this.passtNichtTest(unpassend.id); return; }
      }
      let spielbar = h.playable || [];
      // Phase drawn: „Behalten“ muss sichtbar sein; draw_play "drawn" erlaubt nur die gezogene Karte, "any" jede passende
      let beliebig = false;
      // draw_play "any": manchmal freiwillig ziehen, obwohl etwas passt (danach darf jede passende Karte gelegt werden)
      if (v.phase === 'turn' && h.can_draw && !(v.pending && v.pending.kind) && spielbar.length && v.rules && v.rules.draw_play === 'any' && this.zuege % 3 === 0) {
        await this.ziehenMerken(antwort); return;
      }
      if (v.phase === 'drawn' && v.turn === v.seat) {
        const any = !!(v.rules && v.rules.draw_play === 'any');
        if (!h.can_keep || !app.tisch.aktionen.querySelector('button[data-a="keep"]')) this.fail('Nach dem Ziehen fehlt „Behalten“');
        if (!spielbar.length) this.fail('Phase drawn, aber keine Karte passt');
        if (this.gezogenId !== undefined && !any && spielbar.some(x => x !== this.gezogenId)) this.fail('Nach dem Ziehen andere Karte als die gezogene legbar (draw_play "drawn")');
        if (this.zuege % 5 === 4) {
          this.klick(app.tisch.aktionen.querySelector('button[data-a="keep"]')); await antwort();
          if (this.errs > e0) this.fail('Behalten abgelehnt'); else this.haus.behalten++;
          this.zuege++; return;
        }
        const andere = any && this.gezogenId !== undefined ? spielbar.filter(x => x !== this.gezogenId) : [];
        if (andere.length) { spielbar = andere; beliebig = true; }
      }
      if (spielbar.length) {
        // Hausregel-Karten zuerst (Kartentausch, Farbe ablegen, Ablegen-Joker, Glücksspiel), sonst reihum
        const artVon = x => M.Karten.zerlege((v.hand.find(c => c.id === x) || {}).face).art;
        const haus = spielbar.filter(x => VORRANG[artVon(x)]).sort((a, b) => VORRANG[artVon(a)] - VORRANG[artVon(b)]);
        const id = haus.length ? haus[0] : spielbar[this.zuege % spielbar.length];
        if (beliebig) this.prot('BELIEBIG ' + id + ' statt ' + this.gezogenId);
        const c = v.hand.find(x => x.id === id);
        if (this.zuege % 3 === 1) await this.wischHoch(id);
        else { await this.tippe(id); if (app.tisch.hand.gewaehlt !== id) this.fail('Antippen hebt die Karte nicht an'); await this.tippe(id); }
        if (Array.isArray(h.wild) ? h.wild.indexOf(id) >= 0 : M.Karten.istJoker(c.face)) {
          if (artVon(id) === 'ablegen_joker') {
            // 1.4.9: kein erstes Farbrad; mit farbigen Handkarten Vorwahl per Tipp, sonst gleich das Farbrad der Spielfarbe
            if (app.tisch.farbwahlOffen && !app._vor) this.fail('Farbrad der Ablegefarbe statt Antippen');
            if (app._vor) {
              const kv = app.vorKarten(this.v);
              if (!kv.length) this.fail('Vorwahl ohne farbige Karten');
              if (app.tisch.farbwahlOffen) this.fail('Farbrad trotz Vorwahl');
              if (app.tisch.hinweis.textContent !== 'Tippe auf eine Karte der Farbe, die du mit ablegen willst.') this.fail('Hinweis der Vorwahl: ' + app.tisch.hinweis.textContent);
              if (app.tisch.hand.el.querySelectorAll('.hk.kandidat').length !== kv.length) this.fail('Vorwahl: farbige Karten nicht alle hervorgehoben');
              if (this.zuege % 4 === 3) {   // Abbruch: Tipp auf den Joker selbst legt nichts
                await this.tippe(id);
                if (app._vor) this.fail('Vorwahl lässt sich nicht abbrechen');
                await this.tippe(id); await this.tippe(id);
                if (!app._vor) this.fail('Vorwahl startet nach Abbruch nicht neu');
              }
              await this.tippe(kv[this.zuege % kv.length]);
              if (app._vor) this.fail('Tipp auf Farbkarte wählt keine Ablegefarbe');
              this.haus.vorwahl = (this.haus.vorwahl | 0) + 1;
            }
          } else await this.farbeWaehlen();
        }
        await antwort();
        if (this.errs > e0) this.fail('Zug abgelehnt: ' + c.face);
        else {
          this.ereignisse.eigeneKarte = (this.ereignisse.eigeneKarte || 0) + 1;
          if (this.haus[artVon(id)] !== undefined) this.haus[artVon(id)]++;
          if (beliebig) this.haus.beliebig++;
        }
        this.zuege++;
        return;
      }
      if (h.can_keep) { this.klick(app.tisch.aktionen.querySelector('button[data-a="keep"]')); await antwort(); this.zuege++; return; }
      if (h.can_draw) { await this.ziehenMerken(antwort); return; }
      this.fail('Am Zug, aber keine Möglichkeit: ' + JSON.stringify(h));
      throw new Error('festgefahren');
    },
    // ohne Hervorhebung: unpassende Karte zweimal antippen → Hinweis „Die Karte passt nicht.“, keine Aktion; danach wieder an
    // Ziehen über den Stapel und die gezogene Karte merken (für die Prüfung der Phase drawn)
    async ziehenMerken(antwort) {
      const vorher = new Set((this.v.hand || []).map(c => c.id));
      this.klick('#stapel'); await antwort();
      const neu = ((this.v && this.v.hand) || []).filter(c => !vorher.has(c.id));
      this.gezogenId = neu.length === 1 ? neu[0].id : undefined;
      this.zuege++;
    },
    async passtNichtTest(id) {
      const app = this.app, t = app.tisch, seq0 = app.seq;
      this.ohneHervorheben = false;
      if (t.hand.el.querySelector('.hk.spielbar, .hk.matt')) this.fail('Hervorhebung trotz Einstellung „aus“');
      await this.tippe(id); await this.tippe(id); await schlaf(120);
      if (app.seq !== seq0) this.fail('Unpassende Karte wurde trotzdem gesendet');
      const texte = Array.from(document.querySelectorAll('.toast')).map(x => x.textContent);
      if (texte.indexOf('Die Karte passt nicht.') < 0) this.fail('Kein Hinweis „Die Karte passt nicht.“ (' + texte.join(' / ') + ')');
      else this.notiz('ohne Hervorhebung: „Die Karte passt nicht.“');
      if (t.hand.gewaehlt !== null) t.hand.waehle(null);
      app.einstellen('hervorheben', 'true'); app.schliesse('menue');
      await schlaf(60);
      if (((this.v.hints || {}).playable || []).length && !t.hand.el.querySelector('.hk.spielbar')) this.fail('Hervorhebung kommt nach „An“ nicht zurück');
    },
    ende() {
      if (this._fertig) return;
      this._fertig = true;
      if (this.ohneHervorheben) { this.ohneHervorheben = false; this.notiz('„Die Karte passt nicht.“ nicht geprüft (kein passender Zug)'); this.app.einstellen('hervorheben', 'true'); this.app.schliesse('menue'); }
      const hs = Object.keys(this.haus).filter(k => this.haus[k]).map(k => k + '=' + this.haus[k]).join(' ');
      if (hs) this.notiz('Hausregeln: ' + hs);
      // &pflicht=tausch,ablegen,gluecksspiel: diese Hausregel-Karten muss der Selbsttest selbst gespielt haben (gebaute Lage)
      String(M.param('pflicht') || '').split(',').filter(Boolean).forEach(p => {
        const n = p === 'gluecksspiel' ? Math.min(this.haus.gluecksspiel, this.haus.gesetzt, this.haus.gedrueckt) : (this.haus[p] | 0);
        if (!n) this.fail('Pflicht „' + p + '“ nicht gespielt');
      });
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
      if (this._prot) r.textContent += ' | PROTOKOLL: ' + this._prot.join(' / ');
      if (window.console) console.log('AUTOTEST ' + text);
    },
  };
  M.Autotest = T;
})(window.MMF = window.MMF || {});
