/* Mau-Mau Flip – Browser-Client „Lite“: Schein-Gastgeber für die Entwicklung ohne Godot (index.html?mock=1).
 * Simuliert Lobby und einen vereinfachten, aber plausiblen Spielablauf nach docs/BETA1_PLAN.md (Abschnitte 4 und 5):
 * gleiche Nachrichten (welcome, lobby, start, state mit events+view, err, pong), Sicht mit hints, sortierte Rückseiten.
 * Nicht regelvollständig (kein Stapeln, keine Platzierungen „bis zum Letzten“). Parameter:
 *   gegner=1..9 (Standard 3), karten=N (eigene Startkarten), seite=dunkel, seed=Zahl, tempo=Faktor,
 *   szene=lobby|tisch|farbwahl|anzweifeln|gezogen|mau|rundenende|getrennt|viele|hilfe|rueckseiten|menue|gegner
 */
(function (M) {
  'use strict';

  const ICH = 0;
  const P = n => M.param(n);
  const NAMEN = ['Lena', 'Tom', 'Mia', 'Ben', 'Ida', 'Noah', 'Lea', 'Finn', 'Ella'];
  const FARBEN = { hell: ['rot', 'gelb', 'gruen', 'blau'], dunkel: ['pink', 'tuerkis', 'orange', 'lila'] };
  const JOKER = { wuenscher: 1, wuenscher_plus2: 1, farbjagd: 1 };
  const REGELN = {
    round_end: 'first', scoring: 'none', target: 500, hand_size: 7, draw_rule: 'one', drawn_card: 'may', stacking: 'off',
    wild_restriction: 'bluff', wild_counts_for_bluff: true, jagd_wild_stops: false, mau_call: 'catch', mau_penalty: 2,
    backs_visible: true, peek_own_backs: true, two_player_reverse_skips: true, flip_last_card: 'execute',
  };
  const z = key => M.Karten.zerlege(key);

  function zufall(seed) { let s = (seed >>> 0) || 1; return () => { s = (s * 1664525 + 1013904223) >>> 0; return s / 4294967296; }; }
  function gesichter(seite) {
    const akt = seite === 'hell' ? ['plus1', 'aussetzen', 'richtungswechsel', 'flip'] : ['plus5', 'alle_aussetzen', 'richtungswechsel', 'flip'];
    const jok = seite === 'hell' ? ['wuenscher', 'wuenscher_plus2'] : ['wuenscher', 'farbjagd'];
    const out = [];
    FARBEN[seite].forEach(f => {
      for (let n = 1; n <= 9; n++) out.push(seite + '_' + f + '_' + n, seite + '_' + f + '_' + n);
      akt.forEach(a => out.push(seite + '_' + f + '_' + a, seite + '_' + f + '_' + a));
    });
    jok.forEach(j => { for (let i = 0; i < 4; i++) out.push(seite + '_' + j); });
    return out;
  }
  // Sortierung der sichtbaren Rückseiten (nie Handreihenfolge)
  function sortiereFaces(faces) {
    return M.Karten.sortiere(faces.map((f, i) => ({ id: i, face: f })), 'farbe').map(c => c.face);
  }

  /* ---------------- vereinfachte Spiellogik ---------------- */
  class Spiel {
    constructor(spieler, opt) {
      this.sp = spieler; this.n = spieler.length; this.opt = opt;
      this.rng = zufall(opt.seed);
      this.runde = 0;
      this.punkte = new Array(this.n).fill(0);
    }
    mische(a) { for (let i = a.length - 1; i > 0; i--) { const j = Math.floor(this.rng() * (i + 1)); const t = a[i]; a[i] = a[j]; a[j] = t; } return a; }
    f(id) { return this.karten[id][this.seite]; }
    b(id) { return this.karten[id][this.seite === 'hell' ? 'dunkel' : 'hell']; }
    top() { return this.ablage[this.ablage.length - 1]; }
    naechster(s, k) { return (((s + this.dir * (k || 1)) % this.n) + this.n) % this.n; }
    neueRunde() {
      this.runde++;
      const hell = this.mische(gesichter('hell')), dunkel = this.mische(gesichter('dunkel'));
      this.karten = hell.map((h, i) => ({ hell: h, dunkel: dunkel[i] }));
      this.seite = this.opt.seite === 'dunkel' && this.runde === 1 ? 'dunkel' : 'hell';
      this.stapel = this.mische(Array.from({ length: 112 }, (x, i) => i));
      this.ablage = [];
      this.haende = this.sp.map(() => []);
      this.dir = 1; this.phase = 'turn'; this.gezogen = null; this.mau = new Set(); this.mauOffen = null; this.fordern = null; this.ranking = []; this.scores = null;
      const n = REGELN.hand_size;
      for (let r = 0; r < n; r++) for (let s = 0; s < this.n; s++) this.haende[s].push(this.stapel.pop());
      const meine = this.opt.karten | 0;
      if (meine > 0) { while (this.haende[ICH].length < meine) this.haende[ICH].push(this.stapel.pop()); while (this.haende[ICH].length > meine) this.stapel.unshift(this.haende[ICH].pop()); }
      let t;
      do { t = this.stapel.pop(); this.ablage.push(t); } while (z(this.f(t)).art !== 'zahl');
      this.farbe = z(this.f(t)).farbe;
      this.dran = ICH;
      return [{ e: 'shuffle' }, { e: 'deal' }];
    }
    passt(id) {
      const k = z(this.f(id)), t = z(this.f(this.top()));
      if (this.phase === 'drawn' && id !== this.gezogen) return false;
      if (JOKER[k.art]) return true;
      if (k.farbe === this.farbe) return true;
      return k.art === 'zahl' ? (t.art === 'zahl' && t.wert === k.wert) : (k.art === t.art);
    }
    spielbar(s) {
      if (this.dran !== s || (this.phase !== 'turn' && this.phase !== 'drawn')) return [];
      return this.haende[s].filter(id => this.passt(id));
    }
    zieheEine(s, ev) {
      if (!this.stapel.length) {
        const t = this.ablage.pop();
        this.stapel = this.mische(this.ablage);
        this.ablage = [t];
        ev.push({ e: 'shuffle' });
        if (!this.stapel.length) return null;
      }
      const id = this.stapel.pop();
      this.haende[s].push(id);
      if (this.haende[s].length > 1) this.mau.delete(s);
      return id;
    }
    ziehe(s, n, ev) {
      const faces = [];
      for (let i = 0; i < n; i++) { const id = this.zieheEine(s, ev); if (id === null) break; faces.push(this.f(id)); }
      if (faces.length) ev.push(s === ICH ? { e: 'draw', seat: s, count: faces.length, faces } : { e: 'draw', seat: s, count: faces.length });
    }
    ziehBisFarbe(s, farbe, ev) {
      const faces = [];
      for (let i = 0; i < 40; i++) {
        const id = this.zieheEine(s, ev);
        if (id === null) break;
        faces.push(this.f(id));
        if (z(this.f(id)).farbe === farbe) break;
      }
      if (faces.length) ev.push(s === ICH ? { e: 'draw', seat: s, count: faces.length, faces } : { e: 'draw', seat: s, count: faces.length });
    }
    beginneZug(s) { if (this.mauOffen && this.mauOffen.seat !== s) this.mauOffen = null; }
    botFarbe(s, ohne) {
      const z2 = {};
      this.haende[s].forEach(id => { if (id === ohne) return; const k = z(this.f(id)); if (k.farbe) z2[k.farbe] = (z2[k.farbe] || 0) + 1; });
      const fs = FARBEN[this.seite];
      return fs.slice().sort((a, b) => (z2[b] || 0) - (z2[a] || 0))[0] || fs[0];
    }
    apply(s, a) {
      const ev = [];
      const nein = text => ({ ok: false, reason: text, events: [] });
      const hand = this.haende[s];
      if (this.phase === 'round_over' || this.phase === 'game_over') { if (a.a === 'next_round') return { ok: true, events: this.neueRunde() }; return nein('Die Runde ist vorbei.'); }
      switch (a.a) {
        case 'play': {
          if (this.dran !== s || (this.phase !== 'turn' && this.phase !== 'drawn')) return nein('Du bist nicht dran.');
          const i = hand.indexOf(a.card);
          if (i < 0) return nein('Diese Karte hast du nicht.');
          if (!this.passt(a.card)) return nein('Die Karte passt nicht.');
          const face = this.f(a.card), k = z(face);
          if (JOKER[k.art] && FARBEN[this.seite].indexOf(a.color) < 0) return nein('Bitte eine Farbe wählen.');
          this.beginneZug(s);
          hand.splice(i, 1); this.ablage.push(a.card); this.gezogen = null; this.phase = 'turn';
          ev.push({ e: 'play', seat: s, card: a.card, face });
          const farbeVorher = this.farbe;
          if (JOKER[k.art]) { this.farbe = a.color; ev.push({ e: 'color', color: a.color }); } else this.farbe = k.farbe;
          if (hand.length === 1 && !this.mau.has(s)) this.mauOffen = { seat: s };
          if (hand.length !== 1) this.mau.delete(s);
          const nx = this.naechster(s);
          switch (k.art) {
            case 'plus1': case 'plus5': this.ziehe(nx, k.art === 'plus1' ? 1 : 5, ev); ev.push({ e: 'skip', seat: nx }); this.dran = this.naechster(nx); break;
            case 'aussetzen': ev.push({ e: 'skip', seat: nx }); this.dran = this.naechster(nx); break;
            case 'alle_aussetzen': ev.push({ e: 'skip_all', seat: s }); this.dran = s; break;
            case 'richtungswechsel':
              this.dir *= -1; ev.push({ e: 'reverse', dir: this.dir });
              if (this.n === 2) { ev.push({ e: 'skip', seat: nx }); this.dran = s; } else this.dran = this.naechster(s);
              break;
            case 'flip': this.wende(s, ev); break;
            case 'wuenscher_plus2': case 'farbjagd': {
              const bluff = hand.some(id => { const kk = z(this.f(id)); return kk.farbe === farbeVorher || (REGELN.wild_counts_for_bluff && JOKER[kk.art]); });
              this.fordern = { von: s, opfer: nx, art: k.art, bluff, farbe: a.color };
              this.dran = nx; this.phase = 'challenge';
              break;
            }
            default: this.dran = nx;
          }
          if (hand.length === 0) {
            if (this.fordern) this.loese(false, ev);
            this.rundeEnde(s, ev);
          }
          return { ok: true, events: ev };
        }
        case 'color':
          if (this.phase !== 'color' || this.dran !== s) return nein('Gerade ist keine Farbe zu wählen.');
          if (FARBEN[this.seite].indexOf(a.color) < 0) return nein('Diese Farbe gibt es auf dieser Seite nicht.');
          this.farbe = a.color; this.phase = 'turn'; ev.push({ e: 'color', color: a.color }); this.dran = this.naechster(s);
          return { ok: true, events: ev };
        case 'draw': {
          if (this.dran !== s || this.phase !== 'turn') return nein('Du kannst gerade nicht ziehen.');
          this.beginneZug(s);
          const id = this.zieheEine(s, ev);
          if (id === null) { this.dran = this.naechster(s); return { ok: true, events: ev }; }
          ev.push(s === ICH ? { e: 'draw', seat: s, count: 1, faces: [this.f(id)] } : { e: 'draw', seat: s, count: 1 });
          if (this.passt(id)) { this.phase = 'drawn'; this.gezogen = id; } else this.dran = this.naechster(s);
          return { ok: true, events: ev };
        }
        case 'keep':
          if (this.dran !== s || this.phase !== 'drawn') return nein('Behalten geht nur nach dem Ziehen.');
          this.phase = 'turn'; this.gezogen = null; this.dran = this.naechster(s);
          return { ok: true, events: ev };
        case 'challenge': case 'accept':
          if (this.phase !== 'challenge' || !this.fordern || this.fordern.opfer !== s) return nein('Hier gibt es nichts anzuzweifeln.');
          this.beginneZug(s);
          this.loese(a.a === 'challenge', ev);
          return { ok: true, events: ev };
        case 'mau': {
          const ok = (this.dran === s && (this.phase === 'turn' || this.phase === 'drawn') && hand.length === 2) || (this.mauOffen && this.mauOffen.seat === s);
          if (!ok || this.mau.has(s)) return nein('„Mau!“ geht erst bei zwei Karten, wenn du dran bist.');
          this.mau.add(s);
          if (this.mauOffen && this.mauOffen.seat === s) this.mauOffen = null;
          ev.push({ e: 'mau', seat: s });
          return { ok: true, events: ev };
        }
        case 'catch':
          if (!this.mauOffen || this.mauOffen.seat !== a.target || a.target === s) return nein('Zu spät – da gibt es nichts zu erwischen.');
          ev.push({ e: 'catch', seat: s, target: a.target }, { e: 'penalty', seat: a.target, count: REGELN.mau_penalty });
          this.ziehe(a.target, REGELN.mau_penalty, ev);
          this.mauOffen = null;
          return { ok: true, events: ev };
        default: return nein('Unbekannte Aktion.');
      }
    }
    wende(s, ev) {
      this.ablage.reverse(); this.stapel.reverse();
      this.seite = this.seite === 'hell' ? 'dunkel' : 'hell';
      ev.push({ e: 'flip', side: this.seite });
      const t = z(this.f(this.top()));
      if (JOKER[t.art]) {
        if (s === ICH && this.haende[s].length) { this.phase = 'color'; this.dran = s; return; }
        this.farbe = this.botFarbe(s); ev.push({ e: 'color', color: this.farbe });
      } else this.farbe = t.farbe;
      this.dran = this.naechster(s);
    }
    loese(anzweifeln, ev) {
      const f = this.fordern;
      this.fordern = null; this.phase = 'turn';
      const zieh = (seat, n) => (f.art === 'wuenscher_plus2' ? this.ziehe(seat, n, ev) : (this.ziehBisFarbe(seat, f.farbe, ev), n > 2 ? this.ziehe(seat, 2, ev) : null));
      if (!anzweifeln) { zieh(f.opfer, 2); ev.push({ e: 'skip', seat: f.opfer }); this.dran = this.naechster(f.opfer); return; }
      ev.push({ e: 'challenge', seat: f.opfer, success: f.bluff });
      if (f.bluff) { zieh(f.von, 2); this.dran = f.opfer; } else { zieh(f.opfer, 4); ev.push({ e: 'skip', seat: f.opfer }); this.dran = this.naechster(f.opfer); }
    }
    rundeEnde(sieger, ev) {
      const pkt = s => this.haende[s].reduce((sum, id) => sum + M.Karten.punkte(this.f(id)), 0);
      const andere = this.sp.map((p, s) => s).filter(s => s !== sieger).sort((a, b) => pkt(a) - pkt(b));
      const gewinn = andere.reduce((sum, s) => sum + pkt(s), 0);
      this.punkte[sieger] += gewinn;
      this.ranking = [{ seat: sieger, place: 1, points: gewinn }].concat(andere.map((s, i) => ({ seat: s, place: i + 2, points: pkt(s) })));
      this.scores = this.punkte.slice();
      this.phase = 'round_over';
      this.mauOffen = null; this.fordern = null;
      ev.push({ e: 'round_over', ranking: this.ranking, scores: this.scores });
    }
    sicht(seat) {
      const ich = seat;
      const hand = this.haende[ich];
      const meinZug = this.dran === ich;
      const spielbar = this.spielbar(ich);
      const h = {
        playable: spielbar,
        can_draw: meinZug && this.phase === 'turn',
        can_keep: meinZug && this.phase === 'drawn',
        can_challenge: this.phase === 'challenge' && this.fordern && this.fordern.opfer === ich,
        can_mau: !this.mau.has(ich) && ((meinZug && (this.phase === 'turn' || this.phase === 'drawn') && hand.length === 2) || !!(this.mauOffen && this.mauOffen.seat === ich)),
        catch: this.mauOffen && this.mauOffen.seat !== ich ? [this.mauOffen.seat] : [],
        need_color: this.phase === 'color' && meinZug,
        text: '',
      };
      const name = s => this.sp[s].name;
      if (this.phase === 'round_over') h.text = this.ranking[0].seat === ich ? 'Mau-Mau! Du hast gewonnen.' : name(this.ranking[0].seat) + ' gewinnt die Runde.';
      else if (h.need_color) h.text = 'Oben liegt ein Joker – wähle die Farbe.';
      else if (h.can_challenge) h.text = name(this.fordern.von) + ' legt ' + M.Karten.kartenName(this.f(this.top())) + '. Anzweifeln oder annehmen?';
      else if (meinZug && this.phase === 'drawn') h.text = 'Gezogene Karte legen oder behalten.';
      else if (meinZug) h.text = spielbar.length ? 'Du bist dran.' : 'Du bist dran – nichts passt, zieh eine Karte.';
      else h.text = name(this.dran) + ' ist dran.';
      return {
        v: 1, seat: ich, side: this.seite, phase: this.phase === 'color' ? 'turn' : this.phase, turn: this.dran, dir: this.dir, color: this.farbe,
        players: this.sp.map((p, s) => ({
          seat: s, name: p.name, kind: p.kind, count: this.haende[s].length,
          backs: s === ich || !REGELN.backs_visible ? [] : sortiereFaces(this.haende[s].map(id => this.b(id))),
          place: this.phase === 'round_over' ? (this.ranking.find(r => r.seat === s) || {}).place || 0 : 0,
          mau: this.mau.has(s), connected: p.connected !== false, score: this.punkte[s],
        })),
        hand: hand.map(id => ({ id, face: this.f(id), back: REGELN.peek_own_backs ? this.b(id) : undefined })),
        top: { id: this.top(), face: this.f(this.top()) },
        draw_back: this.stapel.length ? this.b(this.stapel[this.stapel.length - 1]) : '',
        draw_count: this.stapel.length,
        pending: null,
        hints: h,
        round: this.runde,
        ranking: this.phase === 'round_over' ? this.ranking : [],
        rules: REGELN,
      };
    }
    // Computergegner: einfache Wahl, schummelt nicht über die Sicht hinaus (hier vereinfacht)
    botAktion(s) {
      if (this.phase === 'challenge' && this.fordern && this.fordern.opfer === s) return { a: this.rng() < 0.3 ? 'challenge' : 'accept' };
      if (this.dran !== s) return null;
      const hand = this.haende[s];
      if (hand.length === 2 && !this.mau.has(s) && this.phase === 'turn' && this.rng() < 0.75) return { a: 'mau' };
      const sp = this.spielbar(s);
      if (sp.length) {
        const normal = sp.filter(id => !JOKER[z(this.f(id)).art]);
        const wahl = normal.length ? normal : sp;
        const id = wahl[Math.floor(this.rng() * wahl.length)];
        const a = { a: 'play', card: id };
        if (JOKER[z(this.f(id)).art]) a.color = this.botFarbe(s, id);
        return a;
      }
      if (this.phase === 'drawn') return { a: 'keep' };
      return { a: 'draw' };
    }
    // Szenen für Kontrollbilder
    szene(name) {
      const nimm = pred => { const i = this.stapel.findIndex(id => pred(z(this.f(id)))); return i < 0 ? null : this.stapel.splice(i, 1)[0]; };
      const hand = this.haende[ICH];
      if (name === 'farbwahl') {
        const j = nimm(k => k.art === 'wuenscher');
        if (j !== null) { this.stapel.push(hand.pop()); hand.push(j); }
      } else if (name === 'anzweifeln') {
        const v = this.n - 1;
        const j = nimm(k => k.art === (this.seite === 'hell' ? 'wuenscher_plus2' : 'farbjagd'));
        if (j !== null) {
          this.ablage.push(j);
          this.farbe = FARBEN[this.seite][3];
          this.fordern = { von: v, opfer: ICH, art: z(this.f(j)).art, bluff: true, farbe: this.farbe };
          this.phase = 'challenge'; this.dran = ICH;
        }
      } else if (name === 'gezogen') {
        const id = nimm(k => k.farbe === this.farbe && k.art === 'zahl');
        if (id !== null) { hand.push(id); this.gezogen = id; this.phase = 'drawn'; }
      } else if (name === 'mau') {
        while (hand.length > 2) this.stapel.unshift(hand.pop());
        const t = z(this.f(this.top()));
        const id = nimm(k => k.farbe === t.farbe && k.art === 'zahl');
        if (id !== null) { this.stapel.unshift(hand.pop()); hand.push(id); }
        const g = Math.min(2, this.n - 1);
        while (this.haende[g].length > 1) this.stapel.unshift(this.haende[g].pop());
        this.mauOffen = { seat: g };
      } else if (name === 'rundenende') {
        const g = Math.min(2, this.n - 1);
        const ev = [];
        while (this.haende[g].length) this.ablage.splice(this.ablage.length - 1, 0, this.haende[g].pop());
        this.rundeEnde(g, ev);
      }
    }
  }

  /* ---------------- Schein-Gastgeber ---------------- */
  class MockHost {
    constructor() {
      const gegner = Math.max(1, Math.min(9, +(P('gegner') || 3)));
      this.tempo = Math.max(0.2, +(P('tempo') || 1));
      this.szene = P('szene') || '';
      this.seed = +(P('seed') || 20261004);
      this.rev = 0;
      this.ich = { id: 7, name: '', kind: 'web', connected: false, ready: false, seat: ICH, token: '' };
      this.andere = NAMEN.slice(0, gegner).map((name, i) => ({ id: i + 1, name, kind: i === 0 ? 'app' : (i % 3 === 1 ? 'bot' : (i % 3 === 2 ? 'web' : 'app')), connected: true, ready: i !== 2, seat: i + 1 }));
      this.hostId = 1;
      this.spiel = null;
      this.client = null;
      this.timer = 0;
      this.logs = [];
      this.kaputt = this.szene === 'getrennt';
    }
    spieler() { return [this.ich].concat(this.andere).sort((a, b) => a.seat - b.seat); }
    an(msg) { if (this.client) this.client.liefere(msg); }
    lobby() {
      this.rev++;
      this.an({ t: 'lobby', rev: this.rev, host_id: this.hostId, rules: REGELN, players: this.spieler().map(p => ({ id: p.id, name: p.name, kind: p.kind, connected: p.connected, ready: p.ready, seat: p.seat })) });
    }
    verbinde(c) { this.client = c; }
    getrennt() { this.ich.connected = false; if (this.spiel) this.spiel.sp[ICH].connected = false; }
    empfange(m) {
      switch (m.t) {
        case 'hello':
          if (m.proto !== 1) { this.an({ t: 'reject', code: 'proto', text: 'Protokoll passt nicht.' }); return; }
          if (m.token && m.token === this.ich.token) { this.ich.connected = true; }
          else if (this.spiel) { this.an({ t: 'reject', code: 'running', text: 'Die Partie läuft schon.' }); return; }
          else { this.ich.token = M.Netz.zufallsText(24); this.ich.name = String(m.name || 'Gast').slice(0, 16); this.ich.connected = true; }
          if (this.spiel) this.spiel.sp[ICH].connected = true;
          this.an({ t: 'welcome', id: this.ich.id, token: this.ich.token, host_name: 'Lena' });
          if (this.spiel) { this.an({ t: 'start', seat: ICH }); this.sendeState([]); this.plane(); }
          else {
            this.lobby();
            if (!this._miaTimer) this._miaTimer = setTimeout(() => { const mia = this.andere.find(p => !p.ready); if (mia) { mia.ready = true; this.lobby(); this._pruefeStart(); } }, 1500 / this.tempo);
            if (this.szene && this.szene !== 'lobby') setTimeout(() => this.empfange({ t: 'lobby_ready', ready: true }), 200);
          }
          break;
        case 'lobby_ready':
          if (this.spiel) return;
          this.ich.ready = !!m.ready;
          this.lobby();
          this._pruefeStart();
          break;
        case 'act': this.aktion(ICH, m.a || {}, m.seq); break;
        case 'ping': this.an({ t: 'pong', ts: m.ts }); break;
        case 'log': this.logs.push(m.text); if (window.console) console.log('[mock-log]', m.text); break;
        default: break;
      }
    }
    _pruefeStart() {
      if (this.spiel || !this.spieler().every(p => p.ready || p.kind === 'bot')) return;
      clearTimeout(this._startTimer);
      this._startTimer = setTimeout(() => this.starte(), (this.szene ? 300 : 900) / this.tempo);
    }
    starte() {
      if (this.spiel) return;
      const opt = { seed: this.seed, karten: +(P('karten') || (this.szene === 'viele' ? 24 : 0)), seite: P('seite') || '' };
      this.spiel = new Spiel(this.spieler().map(p => ({ name: p.name, kind: p.kind, connected: p.connected })), opt);
      const ev = this.spiel.neueRunde();
      if (this.szene) this.spiel.szene(this.szene);
      this.an({ t: 'start', seat: ICH });
      this.sendeState(this.szene === 'rundenende' ? [] : ev);
      if (this.kaputt) setTimeout(() => this.client && this.client.trennen(), 2500);
      this.plane();
    }
    sendeState(events, seqAck) {
      const m = { t: 'state', events, view: this.spiel.sicht(ICH) };
      if (seqAck !== undefined) m.seq_ack = seqAck;
      this.an(m);
    }
    aktion(seat, a, seq) {
      if (!this.spiel) { if (seat === ICH) this.an({ t: 'err', text: 'Die Partie hat noch nicht begonnen.' }); return; }
      const r = this.spiel.apply(seat, a);
      if (!r.ok) { if (seat === ICH) this.an({ t: 'err', text: r.reason }); return; }
      this.sendeState(r.events, seat === ICH ? seq : undefined);
      this.plane();
    }
    plane() {
      clearTimeout(this.timer);
      const sp = this.spiel;
      if (!sp || this.szene === 'rundenende') return;
      if (sp.phase === 'round_over') { this.timer = setTimeout(() => { if (this.spiel.phase === 'round_over') { const ev = this.spiel.neueRunde(); this.sendeState(ev); this.plane(); } }, 6000 / this.tempo); return; }
      // Ein Computergegner erwischt mich manchmal, wenn ich „Mau!“ vergesse
      if (sp.mauOffen && sp.mauOffen.seat === ICH && sp.dran !== ICH && !this._fangPlan) {
        this._fangPlan = setTimeout(() => {
          this._fangPlan = 0;
          if (sp.mauOffen && sp.mauOffen.seat === ICH && sp.rng() < 0.6) this.aktion(sp.naechster(ICH), { a: 'catch', target: ICH });
        }, 700 / this.tempo);
      }
      const amZug = sp.phase === 'challenge' ? sp.fordern.opfer : sp.dran;
      if (amZug === ICH) return;
      const warte = (900 + sp.rng() * 500) / this.tempo;
      this.timer = setTimeout(() => {
        const a = sp.botAktion(amZug);
        if (a) this.aktion(amZug, a); else this.plane();
      }, warte);
    }
  }

  // gleiche Schnittstelle wie M.Netz.Verbindung
  class Verbindung {
    constructor(opt) {
      this.opt = opt; this.status = 'neu'; this._offen = false; this.endgueltig = false;
      this.host = Verbindung.host || (Verbindung.host = new MockHost());
      this.latenz = 25;
    }
    _setze(s) { if (this.status !== s) { this.status = s; if (this.opt.beiStatus) this.opt.beiStatus(s); } }
    start() {
      if (this.endgueltig) return;
      this._setze(this._warGetrennt ? 'getrennt' : 'verbinde');
      clearTimeout(this._t);
      this._t = setTimeout(() => {
        if (this.endgueltig) return;
        this._offen = true;
        this.host.verbinde(this);
        this._setze('offen');
        this._an(this.opt.hallo());
      }, 80);
    }
    _an(msg) { const s = JSON.stringify(msg); setTimeout(() => this.host.empfange(JSON.parse(s)), this.latenz); }
    liefere(msg) {
      if (!this._offen) return;
      const s = JSON.stringify(msg);
      setTimeout(() => { if (this._offen && this.opt.beiNachricht) this.opt.beiNachricht(JSON.parse(s)); }, this.latenz);
    }
    sende(obj) { if (!this._offen) return false; this._an(obj); return true; }
    get offen() { return this._offen; }
    wecken() { if (!this._offen && !this.endgueltig && !this.host.kaputt) this.start(); }
    neuVerbinden() { if (this._offen) this.trennen(300); else this.wecken(); }
    beenden() { this.endgueltig = true; this._offen = false; clearTimeout(this._t); this._setze('beendet'); }
    // Verbindungsabbruch simulieren (Autotest, Szene „getrennt“)
    trennen(dauer) {
      if (!this._offen) return;
      this._offen = false; this._warGetrennt = true;
      this.host.getrennt();
      this._setze('getrennt');
      if (!this.host.kaputt) { clearTimeout(this._t); this._t = setTimeout(() => this.start(), dauer || 1500); }
    }
  }

  M.Mock = { Verbindung, MockHost, Spiel, REGELN, gesichter };
})(window.MMF = window.MMF || {});
