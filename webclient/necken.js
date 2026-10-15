/* Mau-Mau Flip (Beta 1.6.3, Easter Eggs Teil 2): „Necken“ im Browser-Client „Lite“ (docs/module/eastereggs2.md).
 * Mitspieler können einander eine Papierkugel zuwerfen, den Spieler am Zug nach 10 s mit Schnarchen oder einem Wecker (3 s Ticken,
 * dann Klingeln) necken und schnelle Reaktionen (😂 😱 👏 👍) an den ganzen Tisch schicken. Es ändert nie den Spielstand.
 *  - Regeln: Spiegel von game/scripts/game/tease_rules.gd (TeaseRules; gleiche Konstanten und Gründe, test_web_contract prüft den
 *    Gleichlauf). Der Gastgeber prüft maßgeblich; hier graut die Oberfläche aus, was er ablehnen würde (Abschnitt 2 „Lokal vorgeprüft“).
 *  - Netz (Abschnitt 4): Wunsch {t:"fx", k, to?|r?}; nach jedem welcome und bei Änderung {t:"fx_pref", off}. Vom Gastgeber kommen
 *    fx {k, from, to?, r?} (an alle Sitzenden, auch an den Absender – erst dann erscheint der Effekt), fx_no {why} (nur an den
 *    Absender: late | busy | rate) und fx_offs {seats} (Plätze mit Necken aus). app.js wertet sie nur am Tisch aus.
 *  - Bedienung (Abschnitt 2): Tipp auf den Kopf eines Mitspielers öffnet das Necken-Menü (Fächer ohne sichtbare Rückseiten auch;
 *    großer Modus: der Avatar), der Knopf am eigenen Platz fächert 4 Reaktionen auf. Menü, Knopf und Fächer liegen in einer eigenen
 *    Ebene über dem Viewport (#necken, außerhalb der skalierten .buehne, Knöpfe mindestens 44 CSS-px, Schrift nach --fs); ein Tipp
 *    daneben schließt das Menü und wirkt normal weiter.
 *  - Darstellung und Töne (Abschnitt 3): Effekte auf der Bühne (tisch.flug), Zeilen für den Betroffenen in der Ebene. Ziel hört laut,
 *    Absender leise (Faktor 0,25 ≈ −12 dB), Zuschauer sehen nur (Papierkugel: Plopp leise); Reaktionen hören alle, höchstens 2 Töne
 *    gleichzeitig und je Name 600 ms Sperre. Wecker abstellen: Handelt das Ziel während der 3 s Ticken, fällt er um und klingelt nicht.
 *  - Einstellung „necken“ (je Gerät, ab Werk an, Lite-Menü): aus = nichts sehen, nichts hören, nichts schicken.
 *  - Ältere Gastgeber (≤ 1.6.2) übergehen fx/fx_pref (dann geschieht beim Necken schlicht nichts); ältere Lite-Fassungen übergehen
 *    fx, fx_no und fx_offs (app.js nachricht: default: break).
 */
(function (M) {
  'use strict';

  /* ---------- Regeln: Spiegel von TeaseRules (tease_rules.gd) ---------- */
  const FX_KINDS = ['snore', 'alarm', 'ball', 'react'];
  const FX_REACTS = ['lachen', 'schreck', 'klatschen', 'daumen'];
  const WAKE_KINDS = ['snore', 'alarm'];
  const FX_SLOW_MS = 10000;
  const WAKE_BUSY_MS = { snore: 4500, alarm: 5000 };
  const BALL_BUCKET = 2, BALL_REFILL_MS = 5000, BALL_GAP_MS = 1500;
  const REACT_BUCKET = 3, REACT_REFILL_MS = 3000;
  const TABLE_BUCKET = 8, TABLE_REFILL_MS = 250;
  const TURN_PHASES = ['turn', 'drawn', 'color', 'challenge', 'gamble', 'discard_pick'];
  const REACT_PHASES = ['turn', 'drawn', 'color', 'challenge', 'gamble', 'discard_pick', 'round_over', 'game_over'];
  const REFUSALS = ['late', 'busy', 'rate'];
  const MAX_PLAYERS = 10;   // NetProtocol.MAX_PLAYERS
  const ganz = v => typeof v === 'number' && Number.isInteger(v);

  class Regeln {
    constructor() { this.turn = -1; this.turnNo = 0; this.since = 0; this.sent = {}; this.busyUntil = {}; this.lastBall = {}; this.buckets = {}; }
    // host/client: alles; solo: nur die Papierkugel auf Computergegner; pass und sonst: nichts
    static caps(mode) {
      if (mode === 'host' || mode === 'client') return { kinds: FX_KINDS.slice(), bots_only: false };
      if (mode === 'solo') return { kinds: ['ball'], bots_only: true };
      return { kinds: [], bots_only: false };
    }
    // Tisch-Beschreibung aus einer Sicht: {mode, phase, turn, seats:[{bot, gone, off}]}, offs = Plätze mit Necken aus
    static tischAusSicht(view, offs, mode) {
      const seats = [];
      const sp = view && Array.isArray(view.players) ? view.players : [];
      sp.forEach((p, i) => {
        const d = p && typeof p === 'object' ? p : {};
        const s = ganz(d.seat) && d.seat >= 0 ? d.seat : i;
        seats[s] = { bot: d.kind === 'bot', gone: d.connected === false || d.away === true || d.substituted === true, off: offs.indexOf(s) >= 0 };
      });
      for (let i = 0; i < seats.length; i++) if (!seats[i]) seats[i] = { bot: false, gone: true, off: false };
      return { mode, phase: String((view && view.phase) || ''), turn: view && ganz(view.turn) ? view.turn : -1, seats };
    }
    notiereSicht(view, now) { this.notiereZug(view && ganz(view.turn) ? view.turn : -1, String((view && view.phase) || ''), now); }
    // Platz am Zug: Wechsel = neue Zugnummer, Uhr neu, laufende Weckaktion vorbei
    notiereZug(cur, phase, now) {
      if (TURN_PHASES.indexOf(phase) < 0) cur = -1;
      if (cur !== this.turn) { this.turn = cur; this.turnNo++; this.since = now; this.busyUntil = {}; }
    }
    // Ereignis mit dem Platz am Zug setzt dessen Uhr zurück (wie die Denkblase); „seats“ leert alles (Platznummern verschieben sich)
    notiereEreignisse(events, now) {
      (Array.isArray(events) ? events : []).forEach(e => {
        if (!e || typeof e !== 'object') return;
        if (e.e === 'seats') { this.reset(); return; }
        if (typeof e.seat === 'number' && e.seat >= 0) this.notiereAktion(Math.trunc(e.seat), now);
      });
    }
    notiereAktion(seat, now) { if (seat === this.turn && this.turn >= 0) this.since = now; }
    reset() { this.turn = -1; this.turnNo++; this.since = 0; this.sent = {}; this.busyUntil = {}; this.lastBall = {}; this.buckets = {}; }
    // Restzeit bis Schnarchen/Wecker (ms); −1 = nicht am Zug
    restMs(seat, now) { return seat < 0 || seat !== this.turn ? -1 : Math.max(0, FX_SLOW_MS - (now - this.since)); }
    // "" = erlaubt, sonst der Grund (wie TeaseRules.check)
    pruefe(sender, req, table, now) {
      const k = req && typeof req.k === 'string' ? req.k : '';
      if (FX_KINDS.indexOf(k) < 0) return 'kind';
      const cap = Regeln.caps(table.mode);
      if (cap.kinds.indexOf(k) < 0) return 'mode';
      const seats = Array.isArray(table.seats) ? table.seats : [];
      if (!ganz(sender) || sender < 0 || sender >= seats.length) return 'sender';
      const me = seats[sender];
      if (me.bot || me.gone) return 'sender';
      if (me.off) return 'off';
      const phase = table.phase;
      if (k === 'react') {
        if (typeof req.r !== 'string' || FX_REACTS.indexOf(req.r) < 0) return 'kind';
        if (REACT_PHASES.indexOf(phase) < 0) return 'phase';
        if (this._level(sender + ':react', REACT_BUCKET, REACT_REFILL_MS, now) < 1) return 'rate';
        return this._tischOk(now);
      }
      const to = req.to;
      if (!ganz(to)) return 'target';
      if (to === sender) return 'self';
      if (to < 0 || to >= seats.length) return 'target';
      const tgt = seats[to];
      if (cap.bots_only && !tgt.bot) return 'target';
      if (tgt.gone) return 'target';
      if (tgt.off) return 'off';
      if (k === 'ball') {
        if (TURN_PHASES.indexOf(phase) < 0) return 'phase';
        if (this._level(sender + ':ball', BALL_BUCKET, BALL_REFILL_MS, now) < 1) return 'rate';
        if (this.lastBall[to] !== undefined && now - this.lastBall[to] < BALL_GAP_MS) return 'rate';
        return this._tischOk(now);
      }
      if (tgt.bot) return 'target';
      if (TURN_PHASES.indexOf(phase) < 0 || to !== table.turn || to !== this.turn) return 'late';
      if (now - this.since < FX_SLOW_MS) return 'early';
      if ((this.sent[sender] || {})[k] === this.turnNo) return 'once';
      if (this.busyUntil[to] !== undefined && now < this.busyUntil[to]) return 'busy';
      return this._tischOk(now);
    }
    // angenommenes Ereignis {k, from, to?, r?} verbuchen (beim Empfang), ohne Prüfung
    verbuche(msg, now) {
      const k = String(msg.k || ''), from = ganz(msg.from) ? msg.from : -1, to = ganz(msg.to) ? msg.to : -1;
      this._take('table', TABLE_BUCKET, TABLE_REFILL_MS, now);
      if (k === 'react') this._take(from + ':react', REACT_BUCKET, REACT_REFILL_MS, now);
      else if (k === 'ball') { this._take(from + ':ball', BALL_BUCKET, BALL_REFILL_MS, now); if (to >= 0) this.lastBall[to] = now; }
      else if (WAKE_KINDS.indexOf(k) >= 0) {
        (this.sent[from] = this.sent[from] || {})[k] = this.turnNo;
        if (to >= 0) this.busyUntil[to] = now + WAKE_BUSY_MS[k];
      }
    }
    _tischOk(now) { return this._level('table', TABLE_BUCKET, TABLE_REFILL_MS, now) >= 1 ? '' : 'rate'; }
    _level(key, cap, refill, now) {
      const b = this.buckets[key];
      return b ? Math.min(cap, b.level + Math.max(0, now - b.t) / refill) : cap;
    }
    _take(key, cap, refill, now) { this.buckets[key] = { level: Math.max(0, this._level(key, cap, refill, now) - 1), t: now }; }
  }

  // Nachrichten des Gastgebers prüfen (wie NetProtocol.clean_fx / clean_fx_no / clean_fx_offs); null bzw. '' bzw. [] = verwerfen
  const platz = v => (ganz(v) && v >= 0 && v < MAX_PLAYERS ? v : -1);
  function cleanFx(m) {
    const k = m && typeof m.k === 'string' ? m.k : '';
    const from = platz(m && m.from);
    if (FX_KINDS.indexOf(k) < 0 || from < 0) return null;
    if (k === 'react') return typeof m.r === 'string' && FX_REACTS.indexOf(m.r) >= 0 ? { t: 'fx', k, from, r: m.r } : null;
    const to = platz(m.to);
    return to >= 0 && to !== from ? { t: 'fx', k, from, to } : null;
  }
  function cleanFxNo(m) { return m && typeof m.why === 'string' && REFUSALS.indexOf(m.why) >= 0 ? m.why : ''; }
  function cleanFxOffs(m) {
    const out = [];
    if (!m || !Array.isArray(m.seats) || m.seats.length > MAX_PLAYERS) return out;
    m.seats.forEach(v => { const s = platz(v); if (s >= 0 && out.indexOf(s) < 0) out.push(s); });
    return out.sort((a, b) => a - b);
  }

  /* ---------- Bilder (SVG, Farben über CSS: Tag Tinte auf Papier, nachts Creme mit Neon) ---------- */
  const SVG_KUGEL = '<svg viewBox="-20 -20 40 40" aria-hidden="true"><path class="nk-f nk-s" d="M-15,-5 L-9,-14 L-1,-16 L9,-13 L15,-5 L16,5 L10,13 L1,16 L-9,14 L-15,7 Z"/>'
    + '<path class="nk-l" d="M-9,-14 L-3,-4 L-15,-5 M-3,-4 L6,-6 L9,-13 M6,-6 L15,5 M-3,-4 L-4,7 L-15,7 M-4,7 L7,5 L10,13 M7,5 L1,16"/></svg>';
  const SVG_WECKER = '<svg viewBox="-40 -46 80 92" aria-hidden="true"><g class="nk-glocken"><path class="nk-f nk-s" d="M-34,-20 A16,16 0 0 1 -12,-38 Z"/><path class="nk-f nk-s" d="M34,-20 A16,16 0 0 0 12,-38 Z"/></g>'
    + '<path class="nk-s nk-dick" d="M-18,30 L-24,40 M18,30 L24,40"/><circle class="nk-f nk-s nk-dick" cx="0" cy="2" r="30"/><circle class="nk-gesicht" cx="0" cy="2" r="24"/>'
    + '<g class="nk-ziffern"><path d="M0,-19 L0,-15 M0,19 L0,23 M-21,2 L-17,2 M21,2 L17,2"/></g>'
    + '<g class="nk-zeiger"><path class="nk-s nk-dick" d="M0,2 L0,-15"/></g><path class="nk-s nk-dick" d="M0,2 L9,8"/><circle class="nk-punkt" cx="0" cy="2" r="3.2"/>'
    + '<path class="nk-s nk-dick" d="M-6,-32 L6,-32"/></svg>';
  const SVG_MUETZE = '<svg viewBox="-30 -26 60 34" aria-hidden="true"><path class="nk-mf nk-s" d="M-24,4 C-20,-16 2,-24 22,-14 C14,-12 8,-6 6,0 Z"/><rect class="nk-f nk-s" x="-27" y="0" width="38" height="7" rx="3.5"/><circle class="nk-f nk-s" cx="24" cy="-14" r="5"/></svg>';
  const SVG_KARTEN = '<svg viewBox="-20 -20 40 40" aria-hidden="true"><rect class="nk-f nk-s" x="-15" y="-13" width="17" height="24" rx="3" transform="rotate(-14)"/><rect class="nk-f nk-s" x="-4" y="-13" width="17" height="24" rx="3" transform="rotate(12)"/></svg>';
  const SVG_ZZZ = '<svg viewBox="-20 -20 40 40" aria-hidden="true"><text x="-13" y="12" class="nk-z">Z</text><text x="3" y="0" class="nk-z k">z</text><text x="10" y="-10" class="nk-z kk">z</text></svg>';
  const SVG_LACH = '<svg viewBox="-20 -20 40 40" aria-hidden="true"><circle class="nk-gelb nk-s" r="16"/><path class="nk-s nk-dick" d="M-9,-5 Q-6,-9 -3,-5 M3,-5 Q6,-9 9,-5"/><path class="nk-mund nk-s" d="M-10,2 Q0,15 10,2 Z"/></svg>';
  const REAKT = { lachen: ['😂', 'Lachen'], schreck: ['😱', 'Schreck'], klatschen: ['👏', 'Klatschen'], daumen: ['👍', 'Daumen hoch'] };
  const REAKT_MS = { lachen: 1920, schreck: 610, klatschen: 1920, daumen: 620 };   // Dauer der Töne (Deckel: höchstens 2 gleichzeitig)
  const KNOEPFE = [['ball', SVG_KUGEL, 'Papierkugel'], ['snore', SVG_ZZZ, 'Schnarchen'], ['alarm', SVG_WECKER, 'Wecker'], ['ansehen', SVG_KARTEN, 'Karten ansehen']];
  const LEISE = 0.25;            // −12 dB (Absender, Zuschauer beim Plopp)
  const FLUG_MS = 700, LIEGT_MS = 3000, LIEGT_SK = 0.78, SCHNARCH_MS = 4200, TICK_MS = 3000, KLINGEL_MS = 1800, REAKT_AUF_MS = 1600, MENUE_ZU_MS = 5000;

  const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  function el(tag, cls, html) { const e = document.createElement(tag); if (cls) e.className = cls; if (html !== undefined) e.innerHTML = html; return e; }
  const ueber = (a, b, rand) => a && b && a.width > 0 && b.width > 0 && a.left < b.right + rand && a.right + rand > b.left && a.top < b.bottom + rand && a.bottom + rand > b.top;

  const N = {
    Regeln, cleanFx, cleanFxNo, cleanFxOffs,
    FX_KINDS, FX_REACTS, FX_SLOW_MS, WAKE_BUSY_MS, REFUSALS,
    regeln: new Regeln(),
    offs: [],             // Plätze mit Necken aus (fx_offs des Gastgebers)
    aus: false,           // Einstellung „necken“ dieses Geräts aus
    uhr: () => (window.performance && performance.now ? performance.now() : Date.now()),   // Monotonuhr (Tests: ersetzbar)
    app: null,
    offen: null,          // offenes Menü {seat, turn, bis}
    gesendet: [],         // Selbsttest: geschickte Wünsche
    gezeigt: [],          // Selbsttest: gezeigte Effekte [{k, rolle, …}]
    toene: [],            // Selbsttest: [{name, pegel}]
    _wach: [],            // laufende Weckaktionen {seat, k, abstellen()}
    _liegen: {},          // Platz → liegende Kugeln (Elemente)
    _effekte: new Set(),  // alle Effekt-Elemente (zum Abräumen)
    _rt: [], _rtName: {}, _grauBis: 0, _letzter: null, _zu: null, _zuFaecher: -1e9,

    init(app) {
      this.app = app;
      this.aus = app.einstellungen.necken === false;
      const e = this.ebene = el('div', 'necken-ebene');
      e.id = 'necken';
      this.knopf = el('button', 'nk-rk', SVG_LACH);
      this.knopf.id = 'nk-reaktion'; this.knopf.type = 'button'; this.knopf.hidden = true;
      this.knopf.setAttribute('aria-label', 'Reaktion'); this.knopf.setAttribute('data-t-aria', 'Reaktion');
      this.faecher = el('div', 'nk-faecher');
      this.faecher.id = 'nk-faecher'; this.faecher.hidden = true;
      FX_REACTS.forEach(r => {
        const b = el('button', 'nk-rb', '<span>' + REAKT[r][0] + '</span>');
        b.type = 'button'; b.dataset.r = r; b.setAttribute('aria-label', REAKT[r][1]); b.setAttribute('data-t-aria', REAKT[r][1]);
        this.faecher.appendChild(b);
      });
      this.menue = el('div', 'nk-menue', '<b class="nk-titel"></b><div class="nk-knoepfe">' + KNOEPFE.map(k => '<button type="button" class="nk-mk" data-k="' + k[0] + '"><i>' + k[1]
        + '</i><span></span></button>').join('') + '</div><p class="nk-info"></p>');
      KNOEPFE.forEach(k => this.menue.querySelector('button[data-k="' + k[0] + '"] span').setAttribute('data-t', k[2]));
      this.menue.id = 'nk-menue'; this.menue.hidden = true; this.menue.setAttribute('role', 'dialog');
      e.appendChild(this.knopf); e.appendChild(this.faecher); e.appendChild(this.menue);   // Menü liegt über dem Reaktionsknopf
      document.body.appendChild(e);
      M.I18n.anwenden(e);
      M.I18n.beiWechsel(() => { M.I18n.anwenden(e); if (this.offen) this._menueStand(); });
      this.knopf.addEventListener('click', ev => { ev.preventDefault(); this.reaktionen(this.faecher.hidden); });
      this.faecher.addEventListener('click', ev => {
        const b = ev.target.closest('button[data-r]');
        if (!b) return;
        ev.preventDefault();
        if (b.classList.contains('grau')) { this._wackel(b); return; }
        this._drueck(b);
        if (this.sende({ k: 'react', r: b.dataset.r })) this.reaktionen(false);
      });
      this.menue.addEventListener('click', ev => {
        const b = ev.target.closest('button[data-k]');
        if (!this.offen) return;
        this.offen.bis = this.uhr() + MENUE_ZU_MS;
        if (!b) return;
        ev.preventDefault();
        const seat = this.offen.seat, k = b.dataset.k;
        if (k === 'ansehen') { this.zu(); this.app.gegnerAnsicht(seat); return; }
        if (b.classList.contains('grau')) { this._wackel(b); return; }
        this._drueck(b);
        if (this.sende({ k, to: seat })) this.zu();
      });
      // Tipp daneben schließt Menü bzw. Fächer, der Tipp selbst wirkt normal weiter
      document.addEventListener('pointerdown', ev => {
        if (this.offen && !this.menue.contains(ev.target)) { this._zu = { seat: this.offen.seat, zeit: this.uhr() }; this.zu(); }
        if (!this.faecher.hidden && !this.faecher.contains(ev.target) && !this.knopf.contains(ev.target)) { this._zuFaecher = this.uhr(); this.reaktionen(false); }
      }, true);
      window.addEventListener('resize', () => this.layout());
      setInterval(() => this._takt(), 400);
    },

    /* ---------- Netz ---------- */
    // Partie bzw. Lobby neu: Regeln, Liste und Effekte vergessen
    // (Beta 1.6.3: auch die Liste fx_offs – der Gastgeber schickt eine leere Liste nie, sonst gälte die der vorigen Partie weiter)
    reset() { this.regeln.reset(); this.offs = []; this.abraeumen(); this.zu(); this.reaktionen(false); },
    // nach jedem welcome (auch beim neuen Gastgeber): Der kennt nur, was wir ihm jetzt sagen; seine Liste fx_offs kommt danach neu
    welcome() {
      this.regeln.reset();
      this.offs = [];
      this._prefSenden();
    },
    _prefSenden() { if (this.app && this.app.verbindung && this.app.verbindung.offen) this.app.sende({ t: 'fx_pref', off: !!this.aus }); },
    setzeAus(aus) {
      aus = !!aus;
      if (aus === this.aus) return;
      this.aus = aus;
      this._prefSenden();
      if (aus) { this.abraeumen(); this.zu(); this.reaktionen(false); }
      this.layout();
    },
    // jede Sicht mit ihren Ereignissen (vor der Regie): Spiegel der Regeln, Menü schließen, Wecker abstellen
    sicht(events, view) {
      const now = this.uhr();
      events = Array.isArray(events) ? events : [];
      this.regeln.notiereEreignisse(events, now);
      this.regeln.notiereSicht(view, now);
      if (events.some(e => e && e.e === 'seats')) { this.abraeumen(); this.zu(); this.reaktionen(false); return; }
      this._wach.slice().forEach(w => {
        const gehandelt = events.some(e => e && e.seat === w.seat) || view.turn !== w.seat || TURN_PHASES.indexOf(view.phase) < 0;
        if (gehandelt) w.abstellen();
      });
      if (this.offen) {
        const h = view.hints || {};
        if ((Array.isArray(h.catch) && h.catch.length) || view.turn !== this.offen.turn) this.zu();
      }
    },
    fx(m) {
      const v = this.app && this.app.view;
      const f = cleanFx(m);
      if (!f || !v || !(v.seat >= 0)) return false;
      this.regeln.verbuche(f, this.uhr());
      if (this.aus || !this.app.tisch || !this.app.tisch.v) return false;
      try { this.zeige(f); } catch (e) { if (M.meldeFehler) M.meldeFehler('Necken ' + f.k + ': ' + (e && e.stack || e)); }
      return true;
    },
    fxNo(m) {
      const why = cleanFxNo(m);
      if (!why || this.aus) return;
      const l = this._letzter, name = l && typeof l.to === 'number' ? this._name(l.to) : '';
      if (why === 'late') this.app.toast(M.t('Zu spät – %s hat schon gespielt.', name), 'leise', 2400);
      else if (why === 'busy') this.app.toast(M.t('%s wird gerade schon geweckt.', name), 'leise', 2400);
      else {
        this._grauBis = this.uhr() + 1500; this._menueStand(); this._faecherStand();
        // Beta 1.6.3: Menü bzw. Fächer sind nach dem Senden meist schon zu – der Reaktionsknopf wackelt und ist kurz blass
        if (this.knopf && !this.knopf.hidden) { this.knopf.classList.add('grau'); this._wackel(this.knopf); }
      }
    },
    fxOffs(m) { this.offs = cleanFxOffs(m); if (this.offen) this._menueStand(); },
    // Wunsch schicken (nach lokaler Vorprüfung); der Effekt kommt mit dem fx des Gastgebers
    sende(req) {
      if (this.aus || this.pruefe(req)) return false;
      const m = req.k === 'react' ? { t: 'fx', k: 'react', r: req.r } : { t: 'fx', k: req.k, to: req.to };
      if (!this.app.sende(m)) return false;
      this._letzter = req;
      this.gesendet.push(m);
      return true;
    },
    // lokale Vorprüfung für den eigenen Platz ("" = geht jetzt)
    pruefe(req) {
      const v = this.app && this.app.view;
      if (!v || !(v.seat >= 0)) return 'sender';
      return this.regeln.pruefe(v.seat, req, this._tisch(v), this.uhr());
    },
    _tisch(v) {
      const offs = this.offs.filter(s => s !== v.seat);
      if (this.aus) offs.push(v.seat);
      return Regeln.tischAusSicht(v, offs, 'client');
    },
    verfuegbar() {
      const a = this.app, v = a && a.view;
      return !this.aus && !!a && a.screen === 'tisch' && !!a.tisch && !!v && v.seat >= 0;
    },
    _name(seat) { const p = ((this.app.view || {}).players || []).find(x => x.seat === seat); return p ? p.name : M.t('Platz %d', seat + 1); },
    _spieler(seat) { return ((this.app.view || {}).players || []).find(x => x.seat === seat); },
    reduziert() { return this.app.effekteReduziert() || !!(window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches); },

    /* ---------- Bedienung ---------- */
    // Tipp auf einen Mitspieler (tisch.js): true = erledigt (Menü auf bzw. gerade geschlossen), false = wie bisher
    tippGegner(seat, ziel) {
      if (!this.verfuegbar()) return false;
      const t = this.app.tisch, v = t.v;
      if (!v || seat === v.seat) return false;
      if (this._zu && this._zu.seat === seat && this.uhr() - this._zu.zeit < 500) return true;   // derselbe Tipp hat es eben geschlossen
      const kopf = t.gross ? !!ziel.closest('.ava') : !!ziel.closest('.kopf');
      const p = this._spieler(seat);
      const backs = !!(p && p.backs && p.backs.length);
      if (kopf || (!t.gross && ziel.closest('.faecher') && !backs)) { this.oeffne(seat); return true; }
      return false;
    },
    oeffne(seat) {
      const v = this.app.view;
      if (!v) return;
      this.reaktionen(false);
      this.offen = { seat, turn: v.turn, bis: this.uhr() + MENUE_ZU_MS };
      this.menue.hidden = false;
      this.menue.classList.remove('auf'); void this.menue.offsetWidth; this.menue.classList.add('auf');
      this._menueStand();
    },
    zu() { this.offen = null; if (this.menue) this.menue.hidden = true; },
    // Einträge des Menüs nach der lokalen Uhr (ausgrauen, ausblenden, Hinweiszeile), dann platzieren
    _menueStand() {
      const o = this.offen, v = this.app.view;
      if (!o || !v) return;
      const p = this._spieler(o.seat);
      if (!p) { this.zu(); return; }
      this.menue.querySelector('.nk-titel').textContent = p.name + ' · ' + this.app.kartenText(p.count | 0);
      const grau = this.uhr() < this._grauBis;
      const backs = !!(p.backs && p.backs.length);
      const ziel = { bot: p.kind === 'bot', aus: this.offs.indexOf(o.seat) >= 0 };
      let info = '';
      KNOEPFE.forEach(([k]) => {
        const b = this.menue.querySelector('button[data-k="' + k + '"]');
        if (k === 'ansehen') { b.hidden = !backs; return; }
        const why = this.pruefe({ k, to: o.seat });
        let weg = ziel.aus;
        if (k !== 'ball') weg = weg || ziel.bot || why === 'late' || why === 'target';
        b.hidden = weg;
        b.classList.toggle('grau', !!why || grau);
        if (!weg && k !== 'ball' && why === 'early') {
          info = M.t('Erst, wenn %s eine Weile überlegt.', p.name);
          b.style.setProperty('--rest', String(Math.max(0, Math.min(1, 1 - this.regeln.restMs(o.seat, this.uhr()) / FX_SLOW_MS))));
        } else b.style.removeProperty('--rest');
        if (!weg && k !== 'ball' && why === 'busy' && !info) info = M.t('%s wird gerade schon geweckt.', p.name);
      });
      if (ziel.aus) info = M.t('%s möchte gerade nicht geneckt werden.', p.name);
      const z = this.menue.querySelector('.nk-info');
      z.textContent = info; z.hidden = !info;
      this._menuePlatz();
    },
    // Blase am Kopf des Ziels (großer Modus: links neben der Zeile), nie über einem „Erwischt!“-Knopf, im Viewport geklemmt
    _menuePlatz() {
      const o = this.offen, t = this.app.tisch;
      const g = o && t.gegnerEls.get(o.seat);
      if (!g) { this.zu(); return; }
      const ank = (t.gross ? g.e.querySelector('.ava') : g.e.querySelector('.kopf')).getBoundingClientRect();
      const m = this.menue, mw = m.offsetWidth, mh = m.offsetHeight;
      const vw = window.innerWidth, vh = window.innerHeight, rand = 8, abst = 14;
      const fang = Array.from(document.querySelectorAll('#tisch .gg.fangbar .erwischen')).map(e => e.getBoundingClientRect());
      const kl = (x, lo, hi) => Math.max(lo, Math.min(hi, x));
      const cx = ank.left + ank.width / 2, cy = ank.top + ank.height / 2;
      const kand = [
        { seite: 'unten', left: cx - mw / 2, top: ank.bottom + abst },
        { seite: 'oben', left: cx - mw / 2, top: ank.top - abst - mh },
        { seite: 'links', left: ank.left - abst - mw, top: cy - mh / 2 },
        { seite: 'rechts', left: ank.right + abst, top: cy - mh / 2 },
      ];
      if (t.gross) kand.unshift(kand.splice(2, 1)[0]);
      // Beta 1.6.3 (Gegenprüfung): hart gemieden „Erwischt!“ und der Mau-Knopf (zeitkritisch, ein Tipp auf das Menü schlösse es nicht),
      // weich Ziehstapel, Ablage und der Kopf des Ziels; Reihenfolge der Lagen wie bisher. Passt keine, gewinnt die kleinste Überdeckung.
      const feld = sel => { const e = document.querySelector(sel); if (!e || e.hidden) return null; const r = e.getBoundingClientRect(); return r.width > 0 ? r : null; };
      const hart = fang.concat(['#mau'].map(feld).filter(Boolean));
      const weich = ['#stapel', '#ablage'].map(feld).filter(Boolean);
      const flaeche = (a, b, x) => ueber(a, b, x) ? Math.max(0, Math.min(a.right, b.right + x) - Math.max(a.left, b.left - x)) * Math.max(0, Math.min(a.bottom, b.bottom + x) - Math.max(a.top, b.top - x)) : 0;
      let wahl = null, beste = Infinity;
      kand.forEach((c, i) => {
        const left = kl(c.left, rand, vw - mw - rand), top = kl(c.top, rand, vh - mh - rand);
        const r = { left, top, right: left + mw, bottom: top + mh, width: mw, height: mh };
        let kosten = i * 400;
        hart.forEach(f => { const a = flaeche(r, f, 6); if (a > 0) kosten += 1e7 + a * 40; });
        weich.forEach(f => { kosten += flaeche(r, f, 0) * 4; });
        if (i !== kand.length - 1 && ueber(r, ank, 0)) kosten += 1e5;   // Kopf des Ziels: nur die letzte Lage darf ihn überdecken (wie bisher)
        if (kosten < beste) { beste = kosten; wahl = { c, left, top }; }
      });
      m.style.left = Math.round(wahl.left) + 'px'; m.style.top = Math.round(wahl.top) + 'px';
      m.dataset.seite = wahl.c.seite;
      const zx = wahl.c.seite === 'unten' || wahl.c.seite === 'oben' ? kl(cx - wahl.left, 18, mw - 18) : kl(cy - wahl.top, 18, mh - 18);
      m.style.setProperty('--zz', Math.round(zx) + 'px');
    },
    // Reaktionsfächer auf/zu
    reaktionen(auf) {
      if (!this.faecher) return;
      auf = !!auf && this.verfuegbar() && !this.knopf.hidden && !this._ueberdeckt();
      this.faecher.hidden = !auf;
      this.knopf.classList.toggle('aktiv', auf);
      if (auf) { this.zu(); this._faecherStand(); }
    },
    _faecherStand() {
      if (!this.faecher || this.faecher.hidden) return;
      const grau = this.uhr() < this._grauBis;
      this.faecher.querySelectorAll('button[data-r]').forEach(b => b.classList.toggle('grau', grau || !!this.pruefe({ k: 'react', r: b.dataset.r })));
      // Viertelbogen um den Knopf: nach oben rechts, sonst oben links, unten rechts, unten links (was ganz in den Viewport passt)
      const k = this.knopf.getBoundingClientRect(), d = Math.max(44, Math.round(k.width * 0.95));
      const knoepfe = Array.from(this.faecher.children);
      const bx = k.left + k.width / 2, by = k.top + k.height / 2, R = d * 1.55 + 6, vw = window.innerWidth, vh = window.innerHeight;
      const bogen = (a0, a1) => knoepfe.map((b, i) => {
        const a = (a0 + (a1 - a0) * i / Math.max(1, knoepfe.length - 1)) * Math.PI / 180;
        return { x: bx + R * Math.cos(a) - d / 2, y: by - R * Math.sin(a) - d / 2 };
      });
      const passt = p => p.every(q => q.x >= 4 && q.y >= 4 && q.x + d <= vw - 4 && q.y + d <= vh - 4);
      const lagen = [bogen(95, -5), bogen(85, 185), bogen(-95, 5), bogen(-85, -185)];
      if (this.app.tisch && this.app.tisch.gross) lagen.unshift(lagen.splice(1, 1)[0]);   // großer Modus: nach links, weg von der Liste
      const lage = lagen.find(passt) || lagen[0];
      knoepfe.forEach((b, i) => {
        b.style.width = b.style.height = d + 'px';
        b.style.fontSize = Math.round(d * 0.56) + 'px';
        b.style.left = Math.round(Math.min(vw - d - 4, Math.max(4, lage[i].x))) + 'px';
        b.style.top = Math.round(Math.min(vh - d - 4, Math.max(4, lage[i].y))) + 'px';
        b.style.setProperty('--i', String(i));
      });
    },
    // Tipp auf den Reaktionsknopf bzw. das eigene Namensschild (großer Modus: eigene Zeile)
    tippEigen() {
      if (!this.verfuegbar() || this.knopf.hidden) return false;
      if (this.faecher.hidden && this.uhr() - this._zuFaecher < 500) return true;   // derselbe Tipp hat den Fächer eben geschlossen (1.6.3)
      this.reaktionen(this.faecher.hidden);
      return true;
    },
    // Reaktionsknopf platzieren (nach jedem tisch.zeige und bei Größenänderung): neben „Du“ bzw. im großen Modus links an der eigenen
    // Zeile; ein Platz, der nichts verdeckt (Sortieren, Rückseiten, Hinweisleiste, Aktionen, Mau-Knopf, Erwischt)
    layout() {
      if (!this.knopf) return;
      const a = this.app, t = a && a.tisch, v = t && t.v;
      const phaseOk = v && REACT_PHASES.indexOf(v.phase) >= 0;
      const zeigen = this.verfuegbar() && !!v && phaseOk;
      if (!zeigen) { this.knopf.hidden = true; this.reaktionen(false); return; }
      const d = Math.max(44, Math.round(64 * t.s));
      const rect = sel => { const e = typeof sel === 'string' ? document.querySelector(sel) : sel; if (!e || e.hidden) return null; const r = e.getBoundingClientRect(); return r.width > 0 ? r : null; };
      const hind = ['#sortieren', '#rueckseiten', '#mau', '#tisch .leiste .hinweis', '#tisch .leiste .aktionen'].map(rect).filter(Boolean);
      document.querySelectorAll('#tisch .gg.fangbar .erwischen').forEach(e => { const r = rect(e); if (r) hind.push(r); });
      let ank = null;
      const kand = [];
      if (t.gross) {
        const g = t.gegnerEls.get(v.seat);
        ank = g && !g.e.classList.contains('aus') ? rect(g.e) : null;
        if (ank) kand.push({ left: ank.left - d - 10, top: ank.top + ank.height / 2 - d / 2 });
        const s = rect('#sortieren');
        if (s) kand.push({ left: s.left, top: s.top - d - 10 });
      } else {
        ank = rect(t.ichZahl);
        if (ank) {
          kand.push({ left: ank.right + 10, top: ank.top + ank.height / 2 - d / 2 });
          kand.push({ left: ank.right + 10, top: ank.bottom - d });
          kand.push({ left: ank.left, top: ank.top - d - 8 });
          kand.push({ left: ank.right + 10, top: ank.top - d - 8 });
        }
      }
      if (!kand.length) { const r = t.root.getBoundingClientRect(); kand.push({ left: r.left + 12, top: r.top + r.height * 0.55 }); }
      const vw = window.innerWidth, vh = window.innerHeight;
      let wahl = kand[0];
      for (const c of kand) {
        const r = { left: c.left, top: c.top, right: c.left + d, bottom: c.top + d, width: d, height: d };
        if (c.left < 2 || c.top < 2 || r.right > vw - 2 || r.bottom > vh - 2) continue;
        if (hind.some(h => ueber(r, h, 4))) continue;
        wahl = c; break;
      }
      const k = this.knopf;
      k.hidden = false;
      k.style.width = k.style.height = d + 'px';
      k.style.left = Math.round(Math.max(2, Math.min(vw - d - 2, wahl.left))) + 'px';
      k.style.top = Math.round(Math.max(2, Math.min(vh - d - 2, wahl.top))) + 'px';
      this._faecherStand();
      if (this.offen) this._menuePlatz();
    },
    // alle 400 ms: Menü nach der Uhr auffrischen bzw. nach 5 s schließen; Ebene unter anderen Fenstern (Menü, Regeln …) verstecken
    // Gerätetest 1.6.3: Fenster (Menü, Regeln …) verdecken die ganze Ebene; das Farbrad nur Reaktionsknopf und Fächer (Effektzeilen bleiben)
    _modal() { return !!document.querySelector('.modal:not([hidden]):not(#runde)'); },
    _farbwahl() { const t = this.app && this.app.tisch; return !!(t && t.farbwahl && t.farbwahlOffen); },
    _ueberdeckt() { return this._modal() || this._farbwahl(); },
    _takt() {
      if (!this.ebene) return;
      const modal = this._modal(), fw = this._farbwahl();
      this.ebene.classList.toggle('verdeckt', modal);
      this.ebene.classList.toggle('farbwahl', fw);
      if ((modal || fw) && !this.faecher.hidden) this.reaktionen(false);
      if (modal && this.offen) this.zu();
      if (this.offen) { if (this.uhr() > this.offen.bis) this.zu(); else this._menueStand(); }
      if (this.knopf.classList.contains('grau') && this.uhr() >= this._grauBis) this.knopf.classList.remove('grau');   // 1.6.3: nach fx_no rate
      if (!this.faecher.hidden) this._faecherStand();
      if (this.app && this.app.screen !== 'tisch' && !this.knopf.hidden) this.layout();
    },
    _drueck(b) { b.classList.remove('drueck'); void b.offsetWidth; b.classList.add('drueck'); },
    _wackel(b) { b.classList.remove('wackel'); void b.offsetWidth; b.classList.add('wackel'); },

    /* ---------- Effekte ---------- */
    // angenommenes Necken zeigen; rolle = ziel | absender | zuschauer
    zeige(m) {
      const t = this.app.tisch, ich = t.v.seat;
      const rolle = m.to === ich ? 'ziel' : (m.from === ich ? 'absender' : 'zuschauer');
      this.gezeigt.push({ k: m.k, from: m.from, to: m.to, r: m.r, rolle });
      if (this.gezeigt.length > 40) this.gezeigt.shift();
      if (m.k === 'react') this._reaktion(m.from, m.r);
      else if (m.k === 'ball') this._kugel(m.from, m.to, rolle);
      else if (m.k === 'snore') this._schnarchen(m.from, m.to, rolle);
      else if (m.k === 'alarm') this._wecker(m.from, m.to, rolle);
    },
    _ton(name, pegel) {
      const ok = M.Ton.spiele(name, pegel);
      this.toene.push({ name, pegel: pegel === undefined ? 1 : pegel, ok });
      if (this.toene.length > 60) this.toene.shift();
      return ok;
    },
    // Mitte des Avatars in Bühnenkoordinaten {x, y, r} (eigener Platz: „Du“ bzw. die eigene Zeile im großen Modus)
    anker(seat) {
      const t = this.app.tisch;
      const zu = e => {
        if (!e) return null;
        const r = e.getBoundingClientRect();
        if (!r.width) return null;
        const a = t.zuBuehne(r.left, r.top), b = t.zuBuehne(r.right, r.bottom);
        return { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2, r: Math.max(18, Math.min(b.x - a.x, b.y - a.y) / 2), w: b.x - a.x, h: b.y - a.y };
      };
      if (seat === t.v.seat && !t.gross) { const r = zu(t.ichZahl); if (r) return Object.assign(r, { r: 26, ich: true }); }
      const g = t.gegnerEls.get(seat);
      if (g && !g.e.classList.contains('aus')) { const r = zu(g.e.querySelector('.ava')); if (r) return r; }
      const p = t.platzPos(seat);
      return { x: p.x, y: p.y - 26, r: 27 };
    },
    // Beta 1.6.3 (größere Effekte, wie TeaseFx._choose in der App): Rechteck eines Elements in Bühnenkoordinaten {l, t, r, b}
    _bRect(e) {
      if (!e || e.hidden) return null;
      const r = e.getBoundingClientRect();
      if (!r.width || !r.height) return null;
      const t = this.app.tisch, a = t.zuBuehne(r.left, r.top), b = t.zuBuehne(r.right, r.bottom);
      return { l: a.x, t: a.y, r: b.x, b: b.y };
    },
    // Kopf eines Platzes: rect (Avatar, Name, Zahl bzw. im großen Modus die ganze Zeile), zahlX = linker Rand der Kartenzahl (sonst rechts)
    _kopf(seat) {
      const t = this.app.tisch, z = this.anker(seat);
      let e = null, zahl = null;
      if (seat === t.v.seat && !t.gross) e = t.ichZahl;
      else {
        const g = t.gegnerEls.get(seat);
        if (g && !g.e.classList.contains('aus')) { e = t.gross ? g.e : g.e.querySelector('.kopf'); zahl = t.gross ? g.e.querySelector('.zahl') : null; }
      }
      const rect = this._bRect(e) || { l: z.x - z.r, t: z.y - z.r, r: z.x + z.r, b: z.y + z.r };
      const zr = this._bRect(zahl);
      return { rect, zahlX: zr ? zr.l : rect.r };
    },
    // Was ein Effekt am Platz seat möglichst nicht überdeckt: hart Mau, „Erwischt!“, Ziehstapel, Ablage, Hand und die Knöpfe (Menü, Ton,
    // Sortieren, Rückseiten, Reaktion); weich die Köpfe (der eigene als Listenzeile nur links)
    _hindernisse(seat) {
      const t = this.app.tisch, hart = [], weich = [];
      const dazu = (arr, e) => { const r = this._bRect(e); if (r) arr.push(r); };
      dazu(hart, t.knMau);
      document.querySelectorAll('#tisch .gg.fangbar .erwischen').forEach(e => dazu(hart, e));
      dazu(hart, t.stapel); dazu(hart, t.ablage);
      const hy = t.H - (t.gross ? 250 : 190);
      hart.push({ l: t.g.cx - 540 * t.handF, t: hy, r: t.g.cx + 540 * t.handF, b: t.H });
      const sitze = ((t.v && t.v.players) || []).map(p => p.seat);
      sitze.forEach(s => {
        if (s === seat) return;
        const g = s === t.v.seat && !t.gross ? null : t.gegnerEls.get(s);
        if (s !== t.v.seat && (!g || g.e.classList.contains('aus'))) return;
        weich.push(this._kopf(s).rect);
      });
      const eigen = Object.assign({}, this._kopf(seat).rect);
      if (t.gross) eigen.r = eigen.l + (eigen.r - eigen.l) * 0.35;
      weich.push(eigen);
      [t.knMenue, t.knTon, t.knSort, t.knRueck, this.knopf].forEach(e => dazu(hart, e));   // Knöpfe: nicht zudecken
      return { hart, weich };
    },
    // Beste Lage aus kand [{x, y, rel:{l,t,r,b}}] (rel relativ zu x/y): jede auch auf die Bühne geschoben; Kosten nach Reihenfolge,
    // Verschiebung, Fläche außerhalb und Überdeckung (hart × 12, weich × 2). Gibt die Lage mit endgültigem x/y zurück.
    _waehle(kand, hind) {
      const t = this.app.tisch, B = { l: 6, t: 6, r: t.W - 6, b: t.H - 6 };
      const flaeche = (a, b) => Math.max(0, Math.min(a.r, b.r) - Math.max(a.l, b.l)) * Math.max(0, Math.min(a.b, b.b) - Math.max(a.t, b.t));
      let wahl = null, beste = Infinity;
      kand.forEach((c, i) => {
        const r0 = { l: c.x + c.rel.l, t: c.y + c.rel.t, r: c.x + c.rel.r, b: c.y + c.rel.b };
        const dx = r0.l < B.l ? B.l - r0.l : (r0.r > B.r ? B.r - r0.r : 0);
        const dy = r0.t < B.t ? B.t - r0.t : (r0.b > B.b ? B.b - r0.b : 0);
        [[0, 0], [dx, dy]].forEach(([sx, sy]) => {
          const r = { l: r0.l + sx, t: r0.t + sy, r: r0.r + sx, b: r0.b + sy };
          const ganz = (r.r - r.l) * (r.b - r.t);
          let kosten = i * 2500 + Math.hypot(sx, sy) * 20 + (ganz - flaeche(r, B)) * 30;
          hind.hart.forEach(h => { kosten += flaeche(r, h) * 12; });
          hind.weich.forEach(h => { kosten += flaeche(r, h) * 2; });
          if (kosten < beste) { beste = kosten; wahl = Object.assign({}, c, { x: c.x + sx, y: c.y + sy }); }
        });
      });
      return wahl;
    },
    _aufBuehne(e, x, y, dauer, seat) {
      const t = this.app.tisch;
      e.style.left = x.toFixed(1) + 'px'; e.style.top = y.toFixed(1) + 'px';
      if (t.gross) e.classList.add('gross');
      t.flug.appendChild(e);
      e._seat = seat;
      this._effekte.add(e);
      if (dauer > 0) setTimeout(() => this._weg(e), dauer);
      return e;
    },
    _weg(e, sofort) {
      if (!e || !e.isConnected) { this._effekte.delete(e); return; }
      if (sofort) { e.remove(); this._effekte.delete(e); return; }
      e.classList.add('aus');
      setTimeout(() => { e.remove(); this._effekte.delete(e); }, 380);
    },
    // Effekte je Platz abräumen (seats, neue Partie, Necken aus); laufende Töne aus
    abraeumen() {
      this._effekte.forEach(e => e.remove());
      this._effekte.clear();
      this._wach.forEach(w => clearTimeout(w.timer));
      this._wach = [];
      this._liegen = {};
      if (M.Ton.stoppe) { M.Ton.stoppe('schnarchen', 150); M.Ton.stoppe('wecker', 150); }
    },
    // Zeile für den Betroffenen über dem eigenen Namensschild (in der Ebene, Schrift nach --fs)
    zeile(text, dauer) {
      if (!this.ebene) return null;
      this.ebene.querySelectorAll('.nk-zeile').forEach(z => z.remove());
      const t = this.app.tisch;
      const z = el('div', 'nk-zeile', esc(text));
      this.ebene.appendChild(z);
      const g = t.gross && t.v ? t.gegnerEls.get(t.v.seat) : null;
      const a = (g && !g.e.classList.contains('aus') ? g.e : t.ichZahl).getBoundingClientRect();
      const w = z.offsetWidth, h = z.offsetHeight, vw = window.innerWidth;
      const top = a.width ? a.top - h - 12 : window.innerHeight * 0.6;
      const left = a.width ? (t.gross ? a.left + a.width / 2 - w / 2 : a.left - 6) : (vw - w) / 2;
      z.style.left = Math.round(Math.max(6, Math.min(vw - w - 6, left))) + 'px';
      z.style.top = Math.round(Math.max(6, top)) + 'px';
      setTimeout(() => { z.classList.add('aus'); setTimeout(() => z.remove(), 400); }, dauer || 2800);
      return z;
    },
    _stauchen(seat) {
      if (this.reduziert()) return;
      const t = this.app.tisch;
      const e = seat === t.v.seat && !t.gross ? t.ichZahl : (t.gegnerEls.get(seat) ? t.gegnerEls.get(seat).e.querySelector('.ava') : null);
      if (!e) return;
      e.classList.remove('nk-stauch'); void e.offsetWidth; e.classList.add('nk-stauch');
      setTimeout(() => e.classList.remove('nk-stauch'), 450);
    },

    // Papierkugel: Parabel vom Absender (eigener Platz: über der Hand) zum Ziel, Plopp, Stauchen, zurückspringen, 3 s liegen
    _kugel(from, to, rolle) {
      const t = this.app.tisch, ich = t.v.seat, red = this.reduziert();
      const z = this.anker(to);
      const v = from === ich ? { x: t.g.cx, y: t.H - 236 } : this.anker(from);
      const k = el('div', 'nk-kugel', SVG_KUGEL);
      // Beta 1.6.3: im Flug 1,6-fach (64 px), liegend etwas kleiner (LIEGT_SK); großer Modus: in der Zeile vor der Kartenzahl
      const liegt = t.gross ? { x: this._kopf(to).zahlX - 36 - Math.random() * 60, y: z.y + 6 }
        : { x: z.x + (Math.random() - 0.5) * z.r * 1.4, y: z.y + z.r * 0.75 };
      if (rolle === 'absender') this._ton('papier_wurf');
      const treffer = () => {
        if (!k.isConnected) return;
        if (rolle === 'ziel') { this._ton('papier_plopp'); this.app.vibrieren(40); this.zeile(M.t('Papierkugel von %s!', this._name(from)), 2400); }
        else if (rolle === 'zuschauer') this._ton('papier_plopp', LEISE);
        this._stauchen(to);
        const sp = this._spieler(to);
        if (sp && sp.kind === 'bot') {
          const gross = this.app.tisch.gross;   // großer Modus: links neben der Zeile (darüber läge die Zeile davor)
          this._aufBuehne(el('div', 'nk-mpf' + (gross ? ' links' : ''), esc(M.t('Mpf!'))), gross ? z.x - z.r - 10 : z.x + z.r + 6, gross ? z.y : z.y - z.r - 6, 1300, to);
        }
        const reihe = this._liegen[to] = (this._liegen[to] || []).filter(e => e.isConnected);
        reihe.push(k);
        while (reihe.length > 3) this._weg(reihe.shift());
        setTimeout(() => this._weg(k), LIEGT_MS);
      };
      this._aufBuehne(k, 0, 0, 0, to);
      const tf = (x, y, rot, sk) => 'translate(' + x.toFixed(1) + 'px,' + y.toFixed(1) + 'px) rotate(' + rot.toFixed(0) + 'deg) scale(' + (sk || 1) + ')';
      if (red || !k.animate) {
        k.style.transform = tf(liegt.x, liegt.y, 20, LIEGT_SK);
        k.classList.add('erscheint');
        setTimeout(treffer, red ? 120 : FLUG_MS);
        return;
      }
      const hoch = Math.max(80, Math.min(260, Math.hypot(z.x - v.x, z.y - v.y) * 0.35));
      const bild = [];
      for (let i = 0; i <= 14; i++) {
        const p = i / 14;
        bild.push({ transform: tf(v.x + (z.x - v.x) * p, v.y + (z.y - v.y) * p - hoch * 4 * p * (1 - p), p * 620) });
      }
      k.style.transform = tf(liegt.x, liegt.y, 700, LIEGT_SK);
      k.animate(bild, { duration: FLUG_MS, easing: 'cubic-bezier(.35,.1,.65,1)' });
      setTimeout(() => {
        treffer();
        if (k.isConnected && k.animate) k.animate([{ transform: tf(z.x, z.y, 620) }, { transform: tf((z.x + liegt.x) / 2 - (z.x - v.x) * 0.08, z.y - 34, 660) }, { transform: tf(liegt.x, liegt.y, 700, LIEGT_SK) }], { duration: 380, easing: 'ease-out' });
      }, FLUG_MS);
    },

    // Schnarchen: 4,2 s „Z z z“ in Wellen und eine Schlafmütze auf dem Avatar; beim Ziel Ton und Zeile, Absender leise
    _schnarchen(from, to, rolle) {
      // Beta 1.6.3: doppelt so groß; die „Z“-Wolke steigt schräg links über der Mütze auf, am Rand rechts neben dem Kopf nach rechts,
      // sonst links neben dem Avatar bzw. im großen Modus in der Zeile vor der Kartenzahl (_waehle)
      const z = this.anker(to), t = this.app.tisch, kp = this._kopf(to);
      const zl = { l: -104, t: -170, r: 52, b: 0 }, zr = { l: 0, t: -170, r: 156, b: 0 };
      const kand = [];
      if (t.gross) kand.push({ x: kp.zahlX - 64, y: kp.rect.b - 6, zx: -1, rel: zl });
      kand.push({ x: z.x - z.r * 1.15 - 52, y: z.y - z.r * 0.45, zx: -1, rel: zl });
      kand.push({ x: kp.rect.r + 8, y: z.y + z.r * 0.7, zx: 1, rel: zr });
      kand.push({ x: z.x - z.r - 58, y: z.y + z.r * 1.2, zx: -1, rel: zl });
      const wl = this._waehle(kand, this._hindernisse(to));
      const zzz = this._aufBuehne(el('div', 'nk-zzz' + (this.reduziert() ? ' still' : '') + (wl.zx < 0 ? ' links' : ''), '<b>Z</b><b>z</b><b>z</b><b>Z</b><b>z</b>'), wl.x, wl.y, SCHNARCH_MS, to);
      // Mütze etwa doppelt so groß, oben am Rand kleiner (sie bleibt ganz im Bild)
      const mh = Math.max(36, Math.min(t.gross ? 60 : 68, (z.y - z.r * 0.95 - 4) / 0.85));
      const mu = this._aufBuehne(el('div', 'nk-muetze', SVG_MUETZE), z.x, Math.max(z.y - z.r * 0.95, mh * 0.85 + 4), SCHNARCH_MS, to);
      mu.style.width = Math.round(mh * 120 / 68) + 'px'; mu.style.height = Math.round(mh) + 'px';
      if (rolle === 'ziel') { this._ton('schnarchen'); this.zeile(M.t('%s findet, du schläfst gleich ein.', this._name(from)), 3200); }
      else if (rolle === 'absender') this._ton('schnarchen', LEISE);
      const w = { seat: to, k: 'snore', timer: setTimeout(() => this._wachEnde(w), SCHNARCH_MS) };
      w.abstellen = () => {
        clearTimeout(w.timer); this._wachEnde(w);
        this._weg(zzz); this._weg(mu);
        if (rolle !== 'zuschauer' && M.Ton.stoppe) M.Ton.stoppe('schnarchen', 300);
      };
      this._wach.push(w);
    },
    _wachEnde(w) { this._wach = this._wach.filter(x => x !== w); },

    // Wecker: hüpft über den Avatar, 3 s Zeiger und sichtbares Ticken, dann 1,8 s Klingeln; beim Ziel groß über dem eigenen Platz
    _wecker(from, to, rolle) {
      const z = this.anker(to), gross = rolle === 'ziel';
      const red = this.reduziert();
      let y = z.y - z.r - 70, x = z.x + (z.ich ? 40 : 0);
      if (gross) {   // beim Ziel über der Zeile, damit sie ihn nicht verdeckt
        const zl = this.zeile(M.t('%s hat dir einen Wecker gestellt!', this._name(from)), TICK_MS);
        const r = zl && zl.getBoundingClientRect();
        if (r && r.width) y = Math.max(70, Math.min(y, this.app.tisch.zuBuehne(r.left, r.top).y - 74));
      } else {
        // Beta 1.6.3: bei Mitspielern doppelt so groß (144 × 166, großer Modus 140 × 161), Lage nach _waehle
        const t = this.app.tisch, W = t.gross ? 140 : 144, H = t.gross ? 161 : 166, kp = this._kopf(to);
        const rel = { l: -0.62 * W, r: 0.62 * W, t: -0.56 * H, b: 0.5 * H };
        const kand = [];
        if (t.gross) kand.push({ x: kp.zahlX - W * 0.62 - 8, y: z.y, rel });
        kand.push({ x: z.x - z.r * 0.55, y: z.y - z.r - H * 0.5, rel });
        kand.push({ x: z.x - z.r - W * 0.62 - 4, y: z.y - H * 0.08, rel });
        kand.push({ x: z.x, y: z.y - z.r - H * 0.52, rel });
        kand.push({ x: kp.rect.r + W * 0.62 + 6, y: z.y, rel });
        const p = this._waehle(kand, this._hindernisse(to));
        x = p.x; y = p.y;
      }
      const w = this._aufBuehne(el('div', 'nk-wecker' + (gross ? ' ziel' : '') + (red ? ' still' : ''), SVG_WECKER + '<i class="sw s1"></i><i class="sw s2"></i>'),
        x, y, 0, to);
      const a = { seat: to, k: 'alarm' };
      a.timer = setTimeout(() => {
        if (!w.isConnected) { this._wachEnde(a); return; }
        w.classList.add('klingelt');
        if (rolle === 'ziel') { this._ton('wecker'); this.app.vibrieren([250, 120, 250, 120, 250]); }
        else if (rolle === 'absender') this._ton('wecker', LEISE);
        a.abstellen = () => {};   // klingelt schon
        this._wachEnde(a);
        setTimeout(() => this._weg(w), KLINGEL_MS);
      }, TICK_MS);
      // Ziel handelt während des Tickens: Wecker fällt um, klingelt nicht
      a.abstellen = () => {
        clearTimeout(a.timer); this._wachEnde(a);
        if (!w.isConnected) return;
        w.classList.add('faellt');
        setTimeout(() => this._weg(w, true), red ? 300 : 800);
        if (rolle === 'ziel') this.zeile(M.t('Gerade noch geschafft!'), 2000);
      };
      this._wach.push(a);
    },

    // Reaktion: Symbol steigt am Platz des Absenders auf (nebeneinander, wenn mehrere laufen); Ton für alle, gedeckelt
    _reaktion(from, r) {
      const z = this.anker(from), t = this.app.tisch, kp = this._kopf(from);
      const n = Array.from(this._effekte).filter(e => e._seat === from && e.classList.contains('nk-emoji') && e.isConnected).length;
      // Beta 1.6.3: 1,6-fach (84 px, großer Modus 100); über dem Avatar, links daneben, rechts neben dem Kopf bzw. in der Zeile (_waehle)
      const g = t.gross ? 100 : 84, auf = this.reduziert() ? 0 : g * 1.5;
      const dx = n ? (n % 2 ? 1 : -1) * Math.ceil(n / 2) * g * 1.08 : 0;
      const rel = { l: -g * 0.6, r: g * 0.6, t: -g * 0.55 - auf, b: g * 0.55 };
      const kand = [];
      if (t.gross) kand.push({ x: z.x + z.r + (kp.zahlX - z.x - z.r) * 0.6 + dx, y: z.y, rel });
      kand.push({ x: z.x + dx, y: z.y - z.r - g * 0.45, rel });
      kand.push({ x: z.x - z.r - g * 0.6 - 8 + dx, y: z.y, rel });
      kand.push({ x: kp.rect.r + g * 0.6 + 8 + dx, y: z.y, rel });
      const p = this._waehle(kand, this._hindernisse(from));
      this._aufBuehne(el('div', 'nk-emoji' + (this.reduziert() ? ' still' : ''), REAKT[r][0]), p.x, p.y, REAKT_AUF_MS, from);
      const now = this.uhr();
      this._rt = this._rt.filter(e => e > now);
      if (this._rt.length >= 2 || now - (this._rtName[r] === undefined ? -1e9 : this._rtName[r]) < 600) return;   // höchstens 2 gleichzeitig, je Name 600 ms
      if (this._ton(r)) { this._rt.push(now + REAKT_MS[r]); this._rtName[r] = now; }
    },
  };

  M.Necken = N;
})(window.MMF = window.MMF || {});
