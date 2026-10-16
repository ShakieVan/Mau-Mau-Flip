/* Mau-Mau Flip (Beta 1.6.3, Easter Eggs Teil 2): „Necken“ im Browser-Client „Lite“ (docs/module/eastereggs2.md).
 * Mitspieler können einander eine Papierkugel zuwerfen, den Spieler am Zug nach 10 s mit Schnarchen oder einem Wecker (3 s Ticken,
 * dann Klingeln) necken und schnelle Reaktionen (😂 👏 👍 😱, ab 1.6.5 als Fluent-Emoji-Bilder) an den ganzen Tisch schicken. Es ändert nie den Spielstand.
 *  - Regeln: Spiegel von game/scripts/game/tease_rules.gd (TeaseRules; gleiche Konstanten und Gründe, test_web_contract prüft den
 *    Gleichlauf). Der Gastgeber prüft maßgeblich; hier graut die Oberfläche aus, was er ablehnen würde (Abschnitt 2 „Lokal vorgeprüft“).
 *  - Netz (Abschnitt 4): Wunsch {t:"fx", k, to?|r?}; nach jedem welcome und bei Änderung {t:"fx_pref", off}. Vom Gastgeber kommen
 *    fx {k, from, to?, r?} (an alle Sitzenden, auch an den Absender – erst dann erscheint der Effekt), fx_no {why} (nur an den
 *    Absender: late | busy | rate) und fx_offs {seats} (Plätze mit Necken aus). app.js wertet sie nur am Tisch aus.
 *  - Bedienung (Abschnitt 2): Tipp auf den Kopf eines Mitspielers öffnet das Necken-Menü (Fächer ohne sichtbare Rückseiten auch;
 *    großer Modus: der Avatar). Beta 1.6.5 (Nutzer nach einer Familienrunde, 15.10.2026): Die 4 Reaktionen liegen direkt als eigene
 *    Knöpfe am eigenen Platz (Leiste #nk-leiste, ein Tipp = senden, Reihenfolge Lachen, Klatschen, Daumen hoch, Schreck); der
 *    Lachgesicht-Knopf mit Fächer entfällt. Menü und Leiste liegen in einer eigenen Ebene über dem Viewport (#necken, außerhalb der
 *    skalierten .buehne, Knöpfe mindestens 44 CSS-px, Schrift nach --fs); ein Tipp neben das Menü schließt es und wirkt normal weiter.
 *  - Darstellung und Töne (Abschnitt 3): Effekte auf der Bühne (tisch.flug), Zeilen für den Betroffenen in der Ebene. Ziel hört laut,
 *    Absender leise (Faktor 0,25 ≈ −12 dB), Zuschauer sehen nur (Papierkugel: Plopp leise); Reaktionen hören alle, höchstens 2 Töne
 *    gleichzeitig und je Name 600 ms Sperre. Wecker abstellen: Handelt das Ziel während der 3 s Ticken, fällt er um und klingelt nicht.
 *  - Einstellung „necken“ (je Gerät, ab Werk an, Lite-Menü): aus = nichts sehen, nichts hören, nichts schicken.
 *  - Ältere Gastgeber (≤ 1.6.2) übergehen fx/fx_pref (dann geschieht beim Necken schlicht nichts); ältere Lite-Fassungen übergehen
 *    fx, fx_no und fx_offs (app.js nachricht: default: break).
 *  - Beta 1.6.6 Furzkissen (Abschnitt 12): Menüeintrag mit „Mit Namen“ / „Geheim“ → {t:"fx", k:"kissen", to, reveal}. Der Gastgeber
 *    bestätigt nur dem Leger ({k:"kissen", from, to, reveal} → leise Zeile „Kissen liegt bei …“, kein Bild, kein Ton) bzw. lehnt mit
 *    fx_no {why:"busy"|"rate", k:"kissen"} ab. Beim nächsten Legen/Ziehen des Ziels kommt an alle {k:"kissen_pop", to, reveal, from?}:
 *    Kissen am Platz des Ziels wird plattgedrückt, Wolke, „Pfffrt!“, Ton beim Ziel normal, bei allen anderen leise (auch beim Leger,
 *    sonst verriete sein Handy den geheimen Absender), Vibration nur beim Ziel, danach „Kim war's!“ bzw. „Wer war das?“. Der Spiegel
 *    kennt nur das eigene Kissen und sperrt die Mindestzeit (60 s); die echte Sperre (1–3 min) kennt nur der Gastgeber.
 *    Lite bis 1.6.5 verwirft beide Arten (FX_KINDS ohne „kissen“), ein Gastgeber bis 1.6.5 den Wunsch.
 */
(function (M) {
  'use strict';

  /* ---------- Regeln: Spiegel von TeaseRules (tease_rules.gd) ---------- */
  const FX_KINDS = ['snore', 'alarm', 'ball', 'react', 'kissen'];
  // Beta 1.6.6 Furzkissen (TeaseRules.CUSHION …): kissen_pop schickt nur der Gastgeber (nie ein Wunsch); Auslöser prüft nur er
  const CUSHION = 'kissen', CUSHION_POP = 'kissen_pop';
  const CUSHION_BLOCK_MIN_MS = 60000, CUSHION_BLOCK_MAX_MS = 180000;
  const CUSHION_TRIGGERS = ['play', 'draw', 'accept', 'stake'];
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
    // Beta 1.6.6: cushions = Ziel → {from, reveal, at} (nur das eigene Kissen, aus der Bestätigung), cushionUntil = Leger → ms
    constructor() { this.turn = -1; this.turnNo = 0; this.since = 0; this.sent = {}; this.busyUntil = {}; this.lastBall = {}; this.buckets = {}; this.cushions = {}; this.cushionUntil = {}; }
    // host/client: alles; solo: Papierkugel und Furzkissen auf Computergegner; pass und sonst: nichts
    static caps(mode) {
      if (mode === 'host' || mode === 'client') return { kinds: FX_KINDS.slice(), bots_only: false };
      if (mode === 'solo') return { kinds: ['ball', CUSHION], bots_only: true };
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
      if (TURN_PHASES.indexOf(phase) < 0) { cur = -1; this.cushions = {}; }   // 1.6.6: Runde vorbei – offene Kissen verfallen still
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
    reset() { this.turn = -1; this.turnNo++; this.since = 0; this.sent = {}; this.busyUntil = {}; this.lastBall = {}; this.buckets = {}; this.cushions = {}; this.cushionUntil = {}; }
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
      if (k === CUSHION) {
        // 1.6.6: jeder andere Platz (Übung: nur Bots), nur während der Runde; erst die eigene Sperre, dann das (eigene) Kissen am Ziel
        if (TURN_PHASES.indexOf(phase) < 0) return 'phase';
        if (this.cushionUntil[sender] !== undefined && now < this.cushionUntil[sender]) return 'rate';
        if (this.cushions[to] !== undefined) return 'busy';
        return '';
      }
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
      // 1.6.6: Kissen gehen in keinen Eimer (das Legen ist geheim). Bestätigung = eigenes Kissen, Sperre nur die Mindestzeit
      if (k === CUSHION) { if (from >= 0 && to >= 0) this.legeKissen(from, to, msg.reveal === true, now, CUSHION_BLOCK_MIN_MS); return; }
      if (k === CUSHION_POP) { delete this.cushions[to]; return; }
      this._take('table', TABLE_BUCKET, TABLE_REFILL_MS, now);
      if (k === 'react') this._take(from + ':react', REACT_BUCKET, REACT_REFILL_MS, now);
      else if (k === 'ball') { this._take(from + ':ball', BALL_BUCKET, BALL_REFILL_MS, now); if (to >= 0) this.lastBall[to] = now; }
      else if (WAKE_KINDS.indexOf(k) >= 0) {
        (this.sent[from] = this.sent[from] || {})[k] = this.turnNo;
        if (to >= 0) this.busyUntil[to] = now + WAKE_BUSY_MS[k];
      }
    }
    // 1.6.6 (wie TeaseRules.place_cushion): Kissen auf den Platz to, Sperre des Legers bis now + blockMs
    legeKissen(from, to, reveal, now, blockMs) { this.cushions[to] = { from, reveal: !!reveal, at: now }; this.cushionUntil[from] = now + blockMs; }
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
    if (k === CUSHION_POP) return cleanKissenPop(m);
    const from = platz(m && m.from);
    if (FX_KINDS.indexOf(k) < 0 || from < 0) return null;
    if (k === 'react') return typeof m.r === 'string' && FX_REACTS.indexOf(m.r) >= 0 ? { t: 'fx', k, from, r: m.r } : null;
    const to = platz(m.to);
    if (to < 0 || to === from) return null;
    if (k === CUSHION) return typeof m.reveal === 'boolean' ? { t: 'fx', k, from, to, reveal: m.reveal } : null;   // Bestätigung an den Leger
    return { t: 'fx', k, from, to };
  }
  // 1.6.6 (wie NetProtocol._clean_cushion_pop): to und reveal Pflicht; from nur, wenn vorhanden (≠ to); „mit Namen“ ohne from verwerfen
  function cleanKissenPop(m) {
    const to = platz(m.to);
    if (to < 0 || typeof m.reveal !== 'boolean') return null;
    let from = -1;
    if (Object.prototype.hasOwnProperty.call(m, 'from')) {
      from = platz(m.from);
      if (from < 0 || from === to) return null;
    }
    if (m.reveal && from < 0) return null;
    const f = { t: 'fx', k: CUSHION_POP, to, reveal: m.reveal };
    if (from >= 0) f.from = from;
    return f;
  }
  function cleanFxNo(m) { return m && typeof m.why === 'string' && REFUSALS.indexOf(m.why) >= 0 ? m.why : ''; }
  // 1.6.6 (wie NetProtocol.clean_fx_no_kind): Art einer Ablehnung, 'kissen' oder '' (Arten aus 1.6.3)
  function cleanFxNoKind(m) { return m && m.k === CUSHION ? CUSHION : ''; }
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
  // Beta 1.6.6: Furzkissen (rosa Gummikissen mit Mundstück rechts; Farben in style.css, gleich bei Tag und Nacht, nachts mit Schein)
  const SVG_KISSEN = '<svg viewBox="-32 -24 64 48" aria-hidden="true"><path class="nk-kd nk-s" d="M20,-5 L28,-8 C31,-8 32,-6 31,-3 L30,4 C30,7 28,8 26,7 L20,4 Z"/>'
    + '<path class="nk-kf nk-s" d="M-27,2 C-29,-14 -12,-20 2,-19 C16,-18 24,-10 23,1 C22,13 9,18 -4,18 C-18,18 -26,13 -27,2 Z"/>'
    + '<path class="nk-kn" d="M-19,7 C-9,11 6,11 15,6"/><path class="nk-glanz" d="M-17,-9 C-11,-14 -3,-15 4,-14"/></svg>';
  const REAKT = { lachen:['😂', 'Lachen'], schreck: ['😱', 'Schreck'], klatschen: ['👏', 'Klatschen'], daumen: ['👍', 'Daumen hoch'] };
  // Beta 1.6.5 (Nutzer 15.10.2026): Reihenfolge der Reaktionsknöpfe überall Lachen, Klatschen, Daumen hoch, Schreck
  // (FX_REACTS bleibt die Liste des Protokolls, Spiegel von TeaseRules)
  const REAKT_REIHE = ['lachen', 'klatschen', 'daumen', 'schreck'];
  const LEISTE_ABST = 6;   // Abstand zwischen den Reaktionsknöpfen (CSS-px)
  // Beta 1.6.5 (Nutzer 15.10.2026: „Die sind doch viel schöner.“): Reaktionen als Bilder aus Microsoft Fluent Emoji (MIT,
  // bilder/reaktionen/LIZENZ.md; dieselben Dateien wie game/assets/ui/reaktionen/ der App), damit sie auf jedem Gerät gleich aussehen.
  // Lädt ein Bild nicht, bleibt das Emoji der Geräteschrift (span) sichtbar.
  const REAKT_BILD = r => 'bilder/reaktionen/' + r + '.svg';
  function reaktSymbol(r) {
    const f = document.createDocumentFragment();
    const img = el('img', 'nk-ri');
    img.alt = ''; img.draggable = false; img.decoding = 'async';
    img.addEventListener('error', () => img.remove());
    img.src = REAKT_BILD(r);
    f.appendChild(img);
    f.appendChild(el('span', 'nk-re', REAKT[r][0]));
    return f;
  }
  const REAKT_MS = { lachen: 1920, schreck: 610, klatschen: 1920, daumen: 620 };   // Dauer der Töne (Deckel: höchstens 2 gleichzeitig)
  const KNOEPFE = [['ball', SVG_KUGEL, 'Papierkugel'], ['snore', SVG_ZZZ, 'Schnarchen'], ['alarm', SVG_WECKER, 'Wecker'], ['ansehen', SVG_KARTEN, 'Karten ansehen']];
  const LEISE = 0.25;            // −12 dB (Absender, Zuschauer beim Plopp)
  const FLUG_MS = 700, LIEGT_MS = 3000, LIEGT_SK = 0.78, SCHNARCH_MS = 4200, TICK_MS = 3000, KLINGEL_MS = 1800, REAKT_AUF_MS = 1600, MENUE_ZU_MS = 15000;   // Beta 1.6.7: Menü schließt nach 15 s ohne Tipp (vorher 5 s)
  // Beta 1.6.6 Furzkissen: Plattdrücken nach PLATT_MS (Ton und Vibration dazu), Kissen 1,5 s sichtbar, danach 2,6 s „Kim war's!“
  // Nach fx_no rate bleibt der Kissen-Knopf noch KISSEN_GRAU_MS grau (die echte Restzeit kennt nur der Gastgeber, sie bleibt geheim)
  const PLATT_MS = 120, KISSEN_MS = 1500, WER_MS = 2600, KISSEN_VIB = 150, KISSEN_GRAU_MS = 10000;

  const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  function el(tag, cls, html) { const e = document.createElement(tag); if (cls) e.className = cls; if (html !== undefined) e.innerHTML = html; return e; }
  const ueber = (a, b, rand) => a && b && a.width > 0 && b.width > 0 && a.left < b.right + rand && a.right + rand > b.left && a.top < b.bottom + rand && a.bottom + rand > b.top;

  const N = {
    Regeln, cleanFx, cleanFxNo, cleanFxNoKind, cleanFxOffs, REAKT_BILD,
    FX_KINDS, FX_REACTS, FX_SLOW_MS, WAKE_BUSY_MS, REFUSALS,
    CUSHION, CUSHION_POP, CUSHION_BLOCK_MIN_MS, CUSHION_BLOCK_MAX_MS, CUSHION_TRIGGERS,
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
    _rt: [], _rtName: {}, _grauBis: 0, _letzter: null, _zu: null,
    _kissenT: [],         // 1.6.6: Zeitgeber des Furzkissens (Ton, Wer-Zeile)

    init(app) {
      this.app = app;
      this.aus = app.einstellungen.necken === false;
      const e = this.ebene = el('div', 'necken-ebene');
      e.id = 'necken';
      // Beta 1.6.5: Reaktionsleiste mit 4 direkten Knöpfen (vorher Lachgesicht-Knopf, der einen Fächer öffnete)
      this.leiste = el('div', 'nk-leiste');
      this.leiste.id = 'nk-leiste'; this.leiste.hidden = true; this.leiste.setAttribute('role', 'group');
      this.leiste.setAttribute('aria-label', 'Reaktion'); this.leiste.setAttribute('data-t-aria', 'Reaktion');
      REAKT_REIHE.forEach(r => {
        const b = el('button', 'nk-rb');
        b.appendChild(reaktSymbol(r));
        b.type = 'button'; b.dataset.r = r; b.setAttribute('aria-label', REAKT[r][1]); b.setAttribute('data-t-aria', REAKT[r][1]);
        this.leiste.appendChild(b);
      });
      this.menue = el('div', 'nk-menue', '<b class="nk-titel"></b><div class="nk-knoepfe">' + KNOEPFE.map(k => '<button type="button" class="nk-mk" data-k="' + k[0] + '"><i>' + k[1]
        + '</i><span></span></button>').join('') + '</div>'
        // Beta 1.6.6: Furzkissen – eine Zeile mit zwei Knöpfen; der Leger entscheidet, ob sein Name verraten wird
        + '<div class="nk-kissen"><span class="nk-kt"><i>' + SVG_KISSEN + '</i><span data-t>Furzkissen</span></span>'
        + '<button type="button" class="nk-kb" data-kissen="name" data-t>Mit Namen</button><button type="button" class="nk-kb" data-kissen="geheim" data-t>Geheim</button></div>'
        + '<p class="nk-info"></p>');
      KNOEPFE.forEach(k => this.menue.querySelector('button[data-k="' + k[0] + '"] span').setAttribute('data-t', k[2]));
      this.menue.id = 'nk-menue'; this.menue.hidden = true; this.menue.setAttribute('role', 'dialog');
      e.appendChild(this.leiste); e.appendChild(this.menue);   // Menü liegt über der Reaktionsleiste
      document.body.appendChild(e);
      M.I18n.anwenden(e);
      M.I18n.beiWechsel(() => { M.I18n.anwenden(e); if (this.offen) this._menueStand(); });
      this.leiste.addEventListener('click', ev => {
        const b = ev.target.closest('button[data-r]');
        if (!b) return;
        ev.preventDefault();
        if (this._ueberdeckt()) return;
        if (b.classList.contains('grau')) { this._wackel(b); return; }
        this._drueck(b);
        if (this.sende({ k: 'react', r: b.dataset.r })) this._leisteStand();
      });
      this.menue.addEventListener('click', ev => {
        const b = ev.target.closest('button[data-k]');
        if (!this.offen) return;
        this.offen.bis = this.uhr() + MENUE_ZU_MS;
        const kb = ev.target.closest('button[data-kissen]');
        if (kb) {   // Beta 1.6.6: Furzkissen legen (mit Namen bzw. geheim)
          ev.preventDefault();
          if (kb.classList.contains('grau')) { this._wackel(kb); return; }
          this._drueck(kb);
          if (this.sende({ k: CUSHION, to: this.offen.seat, reveal: kb.dataset.kissen === 'name' })) this.zu();
          return;
        }
        if (ev.target.closest('.nk-kt')) { this.menue.querySelectorAll('button[data-kissen]').forEach(x => this._wackel(x)); return; }   // Symbol: Knöpfe zeigen
        if (!b) return;
        ev.preventDefault();
        const seat = this.offen.seat, k = b.dataset.k;
        if (k === 'ansehen') { this.zu(); this.app.gegnerAnsicht(seat); return; }
        if (b.classList.contains('grau')) { this._wackel(b); return; }
        this._drueck(b);
        if (this.sende({ k, to: seat })) this.zu();
      });
      // Tipp daneben schließt das Menü, der Tipp selbst wirkt normal weiter
      document.addEventListener('pointerdown', ev => {
        if (this.offen && !this.menue.contains(ev.target)) { this._zu = { seat: this.offen.seat, zeit: this.uhr() }; this.zu(); }
      }, true);
      window.addEventListener('resize', () => { if (this.offen) this.offen.seite = ''; this.layout(); });   // neue Fenstergröße: Lage neu wählen
      setInterval(() => this._takt(), 400);
    },

    /* ---------- Netz ---------- */
    // Partie bzw. Lobby neu: Regeln, Liste und Effekte vergessen
    // (Beta 1.6.3: auch die Liste fx_offs – der Gastgeber schickt eine leere Liste nie, sonst gälte die der vorigen Partie weiter)
    reset() { this.regeln.reset(); this.offs = []; this.abraeumen(); this.zu(); },
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
      if (aus) { this.abraeumen(); this.zu(); }
      this.layout();
    },
    // jede Sicht mit ihren Ereignissen (vor der Regie): Spiegel der Regeln, Menü schließen, Wecker abstellen
    sicht(events, view) {
      const now = this.uhr();
      events = Array.isArray(events) ? events : [];
      this.regeln.notiereEreignisse(events, now);
      this.regeln.notiereSicht(view, now);
      if (events.some(e => e && e.e === 'seats')) { this.abraeumen(); this.zu(); return; }
      this._wach.slice().forEach(w => {
        const gehandelt = events.some(e => e && e.seat === w.seat) || view.turn !== w.seat || TURN_PHASES.indexOf(view.phase) < 0;
        if (gehandelt) w.abstellen();
      });
      // Beta 1.6.7 (Nutzer 16.10.2026: „ärgerlich, wenn es plötzlich unterm Finger weggeklaut wird“): Zugwechsel und erwischbare
      // Mitspieler schließen das Menü nicht mehr. Es frischt auf (Schnarchen/Wecker grau bzw. aktiv) und bleibt stehen; ein neuer
      // „Erwischt!“-Buzzer weicht ihm aus (tisch.js _buzzerPlatz). Nur das Rundenende schließt es.
      const imZug = TURN_PHASES.indexOf(view.phase) >= 0, warImZug = this._imZug;
      this._imZug = imZug;
      if (this.offen) { if (!imZug && warImZug) this.zu(); else this._menueStand(); }
    },
    fx(m) {
      const v = this.app && this.app.view;
      const f = cleanFx(m);
      if (!f || !v || !(v.seat >= 0)) return false;
      if (f.k === CUSHION && f.from !== v.seat) return false;   // 1.6.6: Bestätigung gilt nur für den eigenen Platz (wie ClientTable)
      this.regeln.verbuche(f, this.uhr());
      if (this.aus || !this.app.tisch || !this.app.tisch.v) return false;
      try { this.zeige(f); } catch (e) { if (M.meldeFehler) M.meldeFehler('Necken ' + f.k + ': ' + (e && e.stack || e)); }
      return true;
    },
    fxNo(m) {
      const why = cleanFxNo(m);
      if (!why || this.aus) return;
      const l = this._letzter, name = l && typeof l.to === 'number' ? this._name(l.to) : '';
      if (cleanFxNoKind(m) === CUSHION) {
        // 1.6.6: Furzkissen abgelehnt – ohne Restzeit und ohne Hinweis, von wem das liegende Kissen ist. Der Spiegel merkt sich beides,
        // damit der Knopf grau bleibt (fremdes Kissen bis zum Pups bzw. Rundenende, eigene Sperre noch KISSEN_GRAU_MS)
        const now = this.uhr(), v = this.app.view, R = this.regeln;
        if (why === 'busy') {
          if (l && l.k === CUSHION && typeof l.to === 'number' && R.cushions[l.to] === undefined) R.cushions[l.to] = { from: -1, reveal: false, at: now };
          this.app.toast(M.t('Da liegt schon ein Kissen.'), 'leise', 2400);
        } else if (why === 'rate') {
          if (v && v.seat >= 0) R.cushionUntil[v.seat] = Math.max(R.cushionUntil[v.seat] || 0, now + KISSEN_GRAU_MS);
          this.app.toast(M.t('Das Kissen muss sich erst wieder aufpusten.'), 'leise', 2400);
        }
        if (this.offen) this._menueStand();
        return;
      }
      if (why === 'late') this.app.toast(M.t('Zu spät – %s hat schon gespielt.', name), 'leise', 2400);
      else if (why === 'busy') this.app.toast(M.t('%s wird gerade schon geweckt.', name), 'leise', 2400);
      else {
        this._grauBis = this.uhr() + 1500; this._menueStand(); this._leisteStand();
        // Beta 1.6.5: Die Reaktionsleiste ist kurz blass, der zuletzt gedrückte Reaktionsknopf wackelt
        const b = l && l.k === 'react' && this.leiste && !this.leiste.hidden ? this.leiste.querySelector('button[data-r="' + l.r + '"]') : null;
        if (b) this._wackel(b);
      }
    },
    fxOffs(m) { this.offs = cleanFxOffs(m); if (this.offen) this._menueStand(); },
    // Wunsch schicken (nach lokaler Vorprüfung); der Effekt kommt mit dem fx des Gastgebers
    sende(req) {
      if (this.aus || this.pruefe(req)) return false;
      const m = req.k === 'react' ? { t: 'fx', k: 'react', r: req.r } : { t: 'fx', k: req.k, to: req.to };
      if (req.k === CUSHION) m.reveal = req.reveal === true;   // 1.6.6: nur true verrät den Namen
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
      this.offen = { seat, bis: this.uhr() + MENUE_ZU_MS, seite: '' };
      this.menue.hidden = false;
      this.menue.classList.remove('auf', 'folgt'); void this.menue.offsetWidth; this.menue.classList.add('auf');
      this._menueStand();
      // erst nach dem Aufgehen gleitet das Menü mit (großer Modus: die Zeile rollt beim Zugwechsel)
      clearTimeout(this._folgtT);
      this._folgtT = setTimeout(() => { if (this.offen) this.menue.classList.add('folgt'); }, 60);
    },
    zu() { this.offen = null; if (this.menue) { this.menue.hidden = true; this.menue.classList.remove('folgt'); } },
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
        // Beta 1.6.7 (wie die App): Schnarchen/Wecker bei Menschen immer im Menü (es bleibt beim Zugwechsel offen und soll nicht
        // springen), nicht am Zug ausgegraut mit Hinweis
        let weg = ziel.aus;
        if (k !== 'ball') weg = weg || ziel.bot || why === 'target';
        b.hidden = weg;
        b.classList.toggle('grau', !!why || grau);
        if (!weg && k !== 'ball' && why === 'late') {
          info = M.t('Erst, wenn %s dran ist.', p.name);
          b.style.removeProperty('--rest');
        } else if (!weg && k !== 'ball' && why === 'early') {
          info = M.t('Erst, wenn %s eine Weile überlegt.', p.name);
          b.style.setProperty('--rest', String(Math.max(0, Math.min(1, 1 - this.regeln.restMs(o.seat, this.uhr()) / FX_SLOW_MS))));
        } else b.style.removeProperty('--rest');
        if (!weg && k !== 'ball' && why === 'busy' && !info) info = M.t('%s wird gerade schon geweckt.', p.name);
      });
      // Beta 1.6.6: Furzkissen (auch auf Computergegner und den Spieler am Zug; Abwesende/Vertretene: Zeile weg)
      {
        const why = this.pruefe({ k: CUSHION, to: o.seat });
        const reihe = this.menue.querySelector('.nk-kissen');
        reihe.hidden = ziel.aus || ['target', 'mode', 'kind', 'self', 'sender'].indexOf(why) >= 0;
        reihe.querySelectorAll('button[data-kissen]').forEach(b => b.classList.toggle('grau', !!why || grau));
        reihe.classList.toggle('grau', !!why || grau);
        const ki = !reihe.hidden && why === 'rate' ? M.t('Das Kissen muss sich erst wieder aufpusten.') : (!reihe.hidden && why === 'busy' ? M.t('Da liegt schon ein Kissen.') : '');
        if (ki) info = info ? info + '\n' + ki : ki;
      }
      if (ziel.aus) info = M.t('%s möchte gerade nicht geneckt werden.', p.name);
      const z = this.menue.querySelector('.nk-info');
      z.textContent = info; z.hidden = !info;
      this._menuePlatz();
    },
    // Blase am Kopf des Ziels (großer Modus: links neben der Zeile), nie über einem „Erwischt!“-Knopf, im Viewport geklemmt
    // Beta 1.6.7: Die Lage wird nur beim Öffnen (und nach einer Größenänderung des Fensters) gewählt; danach bleibt die Seite fest und
    // das Menü folgt nur noch dem Kopf (großer Modus: der rollenden Zeile, an ihr Ziel), damit es nicht unter dem Finger springt.
    // Ist die Zeile gerade außer Sicht, bleibt es stehen.
    _menuePlatz() {
      const o = this.offen, t = this.app.tisch;
      const g = o && t.gegnerEls.get(o.seat);
      if (!g) { this.zu(); return; }
      if (o.seite && g.e.classList.contains('aus')) return;
      let ank = (t.gross ? g.e.querySelector('.ava') : g.e.querySelector('.kopf')).getBoundingClientRect();
      if (t.gross) {
        const dy = this._rollRest(g.e, t);   // Ziel der Rollbewegung statt der Zwischenlage
        if (dy) ank = { left: ank.left, right: ank.right, width: ank.width, height: ank.height, top: ank.top + dy, bottom: ank.bottom + dy };
      }
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
      // Beta 1.6.7 (Bildprüfung, wie die App): den künftigen Buzzer-Platz des Ziels freihalten, auch wenn es noch nicht erwischbar ist –
      // häufiger Fall: Menü am Spieler am Zug, der danach ohne „Mau!“ auf 1 Karte kommt. Sonst läge sein Buzzer mitten im Menü.
      // Bevorzugt wird eine Lage, die ihn frei lässt und weder Hartes noch den Kopf des Ziels überdeckt; gibt es keine, gilt die Wahl
      // wie bisher (der Buzzer weicht dann über/unter das Menü aus, tisch.js _buzzerPlatz).
      let vor = null;
      if (!g.e.classList.contains('fangbar') && t.bzVorschau) {
        const bv = t.bzVorschau(o.seat), x = 12 * (t.s || 1);   // Rand: der Buzzer hält 10 Bühnen-px Abstand zum Menü
        if (bv) vor = { left: bv.left - x, top: bv.top - x, right: bv.right + x, bottom: bv.bottom + x, width: bv.width + 2 * x, height: bv.height + 2 * x };
      }
      const weich = ['#stapel', '#ablage', '#nk-leiste'].map(feld).filter(Boolean);   // 1.6.5: Reaktionsleiste weich
      const flaeche = (a, b, x) => ueber(a, b, x) ? Math.max(0, Math.min(a.right, b.right + x) - Math.max(a.left, b.left - x)) * Math.max(0, Math.min(a.bottom, b.bottom + x) - Math.max(a.top, b.top - x)) : 0;
      let wahl = null, beste = Infinity, frei = null, besteFrei = Infinity;
      const fest = o.seite && kand.find(c => c.seite === o.seite);
      if (fest) wahl = { c: fest, left: kl(fest.left, rand, vw - mw - rand), top: kl(fest.top, rand, vh - mh - rand) };
      else {
        kand.forEach((c, i) => {
          const left = kl(c.left, rand, vw - mw - rand), top = kl(c.top, rand, vh - mh - rand);
          const r = { left, top, right: left + mw, bottom: top + mh, width: mw, height: mh };
          let kosten = i * 400;
          hart.forEach(f => { const a = flaeche(r, f, 6); if (a > 0) kosten += 1e7 + a * 40; });
          weich.forEach(f => { kosten += flaeche(r, f, 0) * 4; });
          const kopf = ueber(r, ank, 0);
          if (i !== kand.length - 1 && kopf) kosten += 1e5;   // Kopf des Ziels: nur die letzte Lage darf ihn überdecken (wie bisher)
          if (kosten < beste) { beste = kosten; wahl = { c, left, top }; }
          if (vor && !kopf && kosten < 1e5 && !flaeche(r, vor, 0) && kosten < besteFrei) { besteFrei = kosten; frei = { c, left, top }; }
        });
        if (frei) wahl = frei;
      }
      m.style.left = Math.round(wahl.left) + 'px'; m.style.top = Math.round(wahl.top) + 'px';
      m.dataset.seite = o.seite = wahl.c.seite;
      const zx = wahl.c.seite === 'unten' || wahl.c.seite === 'oben' ? kl(cx - wahl.left, 18, mw - 18) : kl(cy - wahl.top, 18, mh - 18);
      m.style.setProperty('--zz', Math.round(zx) + 'px');
      this._loch(Math.round(wahl.left), Math.round(wahl.top), mw, mh);
    },
    // Großer Modus: restlicher Weg einer rollenden Zeile (Viewport-px) bis zu ihrem Ziel (translateY aus tisch.js minus laufende Lage)
    _rollRest(e, t) {
      try {
        const ziel = parseFloat((e.style.transform.match(/translateY\(([-\d.]+)px\)/) || [])[1]);
        const jetzt = new DOMMatrixReadOnly(getComputedStyle(e).transform).m42;
        return isFinite(ziel) && isFinite(jetzt) ? (ziel - jetzt) * t.s : 0;
      } catch (err) { return 0; }
    },
    // Beta 1.6.7: Ein „Erwischt!“-Buzzer meidet das offene Menü (tisch.js _buzzerPlatz). Findet er keinen freien Platz und liegt doch
    // darunter, bekommt das Menü dort ein rundes Loch (clip-path wirkt auch auf Tipps): Der Buzzer bleibt sichtbar und drückbar, das
    // Menü bleibt stehen. Der Tipp auf den Buzzer schließt das Menü wie jeder Tipp daneben.
    _loch(left, top, mw, mh) {
      const t = this.app.tisch, R = 40, f = x => x.toFixed(1);
      let d = '';
      document.querySelectorAll('#tisch .gg.fangbar .erwischen').forEach(b => {
        const q = b.getBoundingClientRect();
        if (!q.width) return;
        const g = b.closest('.gg'), dy = t.gross && g ? this._rollRest(g, t) : 0;
        const cx = (q.left + q.right) / 2 - left, cy = (q.top + q.bottom) / 2 + dy - top, r = b.offsetWidth / 2 * (t.s || 1) * 1.1 + 6;
        if (cx + r <= 0 || cx - r >= mw || cy + r <= 0 || cy - r >= mh) return;
        d += ' M' + f(cx - r) + ' ' + f(cy) + ' a' + f(r) + ' ' + f(r) + ' 0 1 0 ' + f(2 * r) + ' 0 a' + f(r) + ' ' + f(r) + ' 0 1 0 ' + f(-2 * r) + ' 0 Z';
      });
      this.menue.style.clipPath = d ? 'path(evenodd, "M' + -R + ' ' + -R + ' H' + (mw + R) + ' V' + (mh + R) + ' H' + -R + ' Z' + d + '")' : '';
      this.menue.classList.toggle('loch', !!d);
    },
    // Beta 1.6.5: Den Reaktionsfächer gibt es nicht mehr (die Reaktionen liegen direkt in der Leiste); app.js (Zurück-Taste) ruft
    // reaktionen(false) noch auf – absichtlich ohne Wirkung
    reaktionen() {},
    // Reaktionsknöpfe ausgrauen: während der Sperrzeit (lokaler Spiegel der Regeln) und kurz nach fx_no rate
    _leisteStand() {
      if (!this.leiste || this.leiste.hidden) return;
      const grau = this.uhr() < this._grauBis;
      this.leiste.querySelectorAll('button[data-r]').forEach(b => b.classList.toggle('grau', grau || !!this.pruefe({ k: 'react', r: b.dataset.r })));
    },
    // Tipp auf das eigene Namensschild (großer Modus: eigene Zeile): Die Reaktionsknöpfe hüpfen kurz, damit man sie findet
    tippEigen() {
      if (!this.verfuegbar() || this.leiste.hidden) return false;
      const l = this.leiste;
      if (!this.reduziert()) { l.classList.remove('huepf'); void l.offsetWidth; l.classList.add('huepf'); }
      return true;
    },
    // Großer Modus: eigene Zeile „Du“ in CSS-px, und zwar dort, wo sie nach dem Gleiten steht (translateY aus tisch.js; die Zeilen
    // gleiten 0,45 s, getBoundingClientRect liefert den Anfang). dy = Weg, der noch vor ihr liegt; nameEnde = Ende des Worts „Du“.
    _eigeneZeile(t) {
      const g = t.v && t.gegnerEls.get(t.v.seat);
      if (!g || g.e.classList.contains('aus')) return null;
      const e = g.e, r = e.getBoundingClientRect();
      if (!r.width) return null;
      const m = /translateY\((-?[\d.]+)px\)/.exec(e.style.transform || '');
      let jetzt = null;
      try { jetzt = new DOMMatrixReadOnly(getComputedStyle(e).transform).m42; } catch (x) { jetzt = null; }
      const dy = m && jetzt !== null ? (parseFloat(m[1]) - jetzt) * (t.s || 1) : 0;
      const ab = x => ({ left: x.left, right: x.right, top: x.top + dy, bottom: x.bottom + dy, width: x.width, height: x.height });
      const name = e.querySelector('.name'), zahl = e.querySelector('.zahl');
      if (!name || !zahl) return null;
      const rg = document.createRange();
      rg.selectNodeContents(name);
      const nw = rg.getBoundingClientRect().width, nr = name.getBoundingClientRect();
      const spalte = nr.right + (parseFloat(getComputedStyle(name).marginRight) || 0) * (t.s || 1);   // rechter Rand der Namensspalte (ohne Platzhalter)
      return { e, rect: ab(r), nameEnde: nr.left + nw, spalte, zahl: ab(zahl.getBoundingClientRect()), dy };
    },
    // Reaktionsleiste platzieren (nach jedem tisch.zeige und bei Größenänderung). Formen: Reihe (4 × 1), Quadrat (2 × 2), Spalte
    // (1 × 4). Lagen nach Vorrang: hochkant bzw. fast quadratisch (Rahmen) unter dem Tisch links (der Hinweis „Quer halten“ rückt
    // nach unten), sonst darüber; großer Modus als Reihe in der Zeile „Du“ vor der Kartenzahl, sonst 2 × 2 links bündig daran; sonst rechts neben
    // „Du“, darüber oder als Quadrat. Hart gemieden (nie verdecken): Hand, Stapel, Ablage, Mau, „Erwischt!“, Sortieren, Rückseiten,
    // Hinweisleiste mit Aktionen, Menü-/Ton-Knopf, Spielerliste (großer Modus), Glücksspiel; weich die Mitspieler und die Farbe.
    layout() {
      if (!this.leiste) return;
      const a = this.app, t = a && a.tisch, v = t && t.v;
      const phaseOk = v && REACT_PHASES.indexOf(v.phase) >= 0;
      const zeigen = this.verfuegbar() && !!v && phaseOk;
      const L = this.leiste;
      if (!zeigen) {
        L.hidden = true; document.body.classList.remove('nk-unten');
        document.querySelectorAll('#tisch .gg').forEach(e => {
          e.style.removeProperty('--nk-res');
          const zg = e.querySelector('.zug');
          if (zg && v && +e.dataset.seat === v.seat && zg.textContent === M.t('dran')) zg.textContent = M.t('Du bist dran');
        });
        return;
      }
      const rahmen = document.body.classList.contains('rahmen');
      const d = Math.max(rahmen ? 52 : 44, Math.round(58 * t.s)), gap = LEISTE_ABST;   // Rahmen: Platz genug für etwas größere Knöpfe
      const FORM = { reihe: [4, 1], quadrat: [2, 2], spalte: [1, 4] };
      const mass = f => ({ w: FORM[f][0] * d + (FORM[f][0] - 1) * gap, h: FORM[f][1] * d + (FORM[f][1] - 1) * gap });
      const rect = sel => { const e = typeof sel === 'string' ? document.querySelector(sel) : sel; if (!e || e.hidden) return null; const r = e.getBoundingClientRect(); return r.width > 0 ? r : null; };
      // Stapel und Ablage sind Ankerpunkte ohne eigene Größe (Karten absolut darin): deren Fläche ist die Hülle der Kinder
      const huelle = e => {
        if (!e || e.hidden) return null;
        const r0 = e.getBoundingClientRect();
        if (r0.width > 0) return r0;
        let l = 1e9, o = 1e9, r = -1e9, u = -1e9;
        e.querySelectorAll('*').forEach(k => { const b = k.getBoundingClientRect(); if (b.width > 0) { l = Math.min(l, b.left); o = Math.min(o, b.top); r = Math.max(r, b.right); u = Math.max(u, b.bottom); } });
        return r > l ? { left: l, top: o, right: r, bottom: u, width: r - l, height: u - o } : null;
      };
      const alle = (sel, arr) => document.querySelectorAll(sel).forEach(e => { const r = rect(e); if (r) arr.push(r); });
      const hart = [t.knSort, t.knRueck, t.knMau, t.knMenue, t.knTon, t.stapelZahl, t.hinweis, t.aktionen,
        '#automat', '#einsatz', '#liste-kopf'].map(rect).concat([t.stapel, t.ablage, document.getElementById('seitenstapel')].map(huelle)).filter(Boolean);
      alle('#tisch .gg.fangbar .erwischen', hart);
      alle('#tisch .hk', hart);
      const weich = [t.farbe].map(rect).filter(Boolean);
      if (!t.gross) { const du = rect(t.ichZahl); if (du) hart.push(du); }   // „Du“ mit Kartenzahl nicht zudecken
      // großer Modus: Zeilen der Spielerliste hart; die eigene zählt erst unten (Lage nach dem Gleiten, für die Reihe darin nicht)
      // (Die Reihe in der eigenen Zeile prüft die anderen Zeilen nicht: sie gleiten gerade, ihre Lage jetzt ist nicht die nach dem Gleiten.)
      const zeilen = [];
      alle(t.gross ? '#tisch .gg:not(.aus):not(.ich)' : '#tisch .gg', t.gross ? zeilen : weich);
      const root = t.root.getBoundingClientRect();
      // Was auf dem Tisch liegt, zählt nur innerhalb von #tisch (Hand und Fächer ragen im Rahmen über den Rand, sind dort aber abgeschnitten)
      const schnitt = r => { const left = Math.max(r.left, root.left), top = Math.max(r.top, root.top), right = Math.min(r.right, root.right), bottom = Math.min(r.bottom, root.bottom);
        return right > left && bottom > top ? { left, top, right, bottom, width: right - left, height: bottom - top } : null; };
      [hart, weich, zeilen].forEach(arr => { const neu = arr.map(schnitt).filter(Boolean); arr.length = 0; neu.forEach(r => arr.push(r)); });
      const runde = rect('#runde:not([hidden]) .runde-karte');   // Rundenende-Tafel (liegt unter der Ebene): nicht zudecken
      if (runde) hart.push(runde);
      const kand = [];
      const dazu = (form, left, top, unten) => kand.push(Object.assign({ form, left, top, unten: !!unten }, mass(form)));
      if (rahmen) {
        const m = mass('reihe');
        const rest = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--rahmen-rest')) || 0;
        if (!document.body.classList.contains('rahmen-hinweis') || rest >= m.h + 10 + 64) dazu('reihe', root.left + 12, root.bottom + 10, true);
        dazu('reihe', root.left + 12, root.top - m.h - 10);
      }
      // Großer Modus (Bildprüfung 1.6.5): wie in der App als Reihe IN der Zeile „Du“ rechtsbündig vor der Kartenzahl (dem Wort „Du“
      // bleibt sein Platz); Ausweichlage 2 × 2 links bündig an der eigenen Zeile, kleinere Knöpfe (unter 36 px, sehr schmale Handys) erst
      // danach, aber noch vor den Notlagen am Rand. Nie mehr als Spalte über alle Zeilen
      // (las sich wie „Reaktion an diesen Spieler“). Trefferfläche: unsichtbarer Rand bis 44 px (--nk-tx/--nk-ty).
      const zeile = t.gross ? this._eigeneZeile(t) : null;
      if (zeile) {
        const x1 = zeile.zahl.left - 5, x0 = zeile.nameEnde + 6;
        const passt = gi => Math.min(d, Math.floor((x1 - x0 - 3 * gi) / 4), Math.max(36, Math.floor(zeile.rect.height - 2)));
        // Abstand 6, 5 oder 4 px: am liebsten Trefferfläche (Knopf + Abstand, je halb links und rechts) ≥ 44 px, dann der größere Knopf
        let gi = LEISTE_ABST, di = passt(gi);
        [5, 4].forEach(g => { const x = passt(g); if (Math.min(44, x + g) * 100 + x > Math.min(44, di + gi) * 100 + di) { gi = g; di = x; } });
        if (di >= 30) {   // unter 36 px (sehr schmale Handys): notfall, siehe Kosten
          const w = 4 * di + 3 * gi;
          kand.push({ form: 'reihe', left: x1 - w, top: zeile.rect.top + zeile.rect.height / 2 - di / 2, unten: false, w, h: di, d: di, gap: gi, inZeile: true, notfall: di < 36 });
        }
      }
      if (t.gross) {
        const liste = Array.from(t.gegnerEls.values()).map(x => x.e.classList.contains('aus') ? null : rect(x.e)).filter(Boolean);
        const links = liste.length ? Math.min.apply(null, liste.map(r => r.left)) : (zeile ? zeile.rect.left : root.right - 12);
        const ziel = zeile ? zeile.rect : (liste.length ? liste[liste.length - 1] : null);
        if (ziel) {
          const m = mass('quadrat');
          dazu('quadrat', links - m.w - 10, ziel.bottom - m.h);
          dazu('quadrat', links - m.w - 10, ziel.top + ziel.height / 2 - m.h / 2);
          dazu('quadrat', links - m.w - 10, ziel.top);
        }
        const s = rect(t.knSort);
        if (s) { dazu('reihe', s.left, s.top - mass('reihe').h - 10); dazu('quadrat', s.left, s.top - mass('quadrat').h - 10); }
      } else {
        const ank = rect(t.ichZahl);
        if (ank) {
          const r = mass('reihe'), q = mass('quadrat');
          dazu('reihe', ank.right + 10, Math.min(ank.top + ank.height / 2 - r.h / 2, ank.bottom + 6 - r.h));   // etwas höher: Sortieren liegt knapp darunter
          dazu('reihe', ank.left, ank.top - r.h - 8);
          dazu('reihe', ank.right + 10, ank.top - r.h - 8);
          dazu('quadrat', ank.right + 10, ank.bottom - q.h);
          dazu('quadrat', ank.left, ank.top - q.h - 8);
        }
      }
      // Notlagen (z. B. Rundenende-Tafel über der Mitte): Spalte am linken bzw. rechten Rand zwischen den Eckknöpfen
      { const m = mass('spalte'), oben = (rect(t.knMenue) || { bottom: root.top }).bottom + 10;
        const unten = Math.min((rect(t.knSort) || { top: root.bottom }).top - 10, t.gross ? 1e9 : (rect(t.ichZahl) || { top: 1e9 }).top - 8);
        dazu('spalte', root.left + 6, Math.max(oben, unten - m.h));
        dazu('spalte', root.right - m.w - 6, (rect(t.knTon) || { bottom: root.top }).bottom + 10); }
      const vw = window.innerWidth, vh = window.innerHeight;
      const flaeche = (a, b, x) => ueber(a, b, x) ? Math.max(0, Math.min(a.right, b.right + x) - Math.max(a.left, b.left - x)) * Math.max(0, Math.min(a.bottom, b.bottom + x) - Math.max(a.top, b.top - x)) : 0;
      let wahl = null, beste = Infinity;
      const eigen = zeile ? [zeile.rect] : [];   // eigene Zeile: hart für alle Lagen außer der Reihe darin
      kand.forEach((c, i) => {
        const left = Math.max(4, Math.min(vw - c.w - 4, c.left)), top = Math.max(4, Math.min(vh - c.h - 4, c.top));
        const r = { left, top, right: left + c.w, bottom: top + c.h, width: c.w, height: c.h };
        let kosten = i * 300 + (Math.abs(left - c.left) + Math.abs(top - c.top)) * 50;
        (c.inZeile ? hart : hart.concat(zeilen, eigen)).forEach(h => { const f = flaeche(r, h, 4); if (f > 0) kosten += 1e6 + f * 40; });
        if (c.notfall) kosten += 1200;   // kleine Knöpfe in der Zeile: schlechter als 2 × 2 daneben, besser als die Notlagen am Rand
        weich.forEach(h => { kosten += flaeche(r, h, 0) * 2; });
        c.kosten = kosten;
        if (kosten < beste) { beste = kosten; wahl = Object.assign({}, c, { left, top }); }
      });
      this._lagen = kand; this._hart = hart;   // Selbsttest/Kontrollbilder: geprüfte Lagen mit Kosten, harte Hindernisse
      const sp = FORM[wahl.form][0], dd = wahl.d || d, gg = wahl.gap || gap;
      L.hidden = false;
      L.dataset.form = wahl.form;
      L.dataset.lage = wahl.inZeile ? 'zeile' : '';
      L.style.left = Math.round(wahl.left) + 'px';
      // In der Zeile „Du“ gleitet die Leiste mit der Zeile (0,45 s wie #tisch.gross .gg): erst an die Lage der Zeile jetzt, dann ans Ziel
      if (wahl.inZeile && Math.abs(zeile.dy) > 0.5) {
        L.style.transition = 'none';
        L.style.top = Math.round(wahl.top - zeile.dy) + 'px';
        void L.offsetWidth;
        L.style.transition = 'top .45s cubic-bezier(.3,.8,.3,1)';
      } else L.style.transition = 'none';
      L.style.top = Math.round(wahl.top) + 'px';
      L.style.gridTemplateColumns = 'repeat(' + sp + ', ' + dd + 'px)';
      L.style.gap = gg + 'px';
      const rand = Math.max(0, (44 - dd) / 2);   // Trefferfläche: unsichtbarer Rand bis 44 px, seitlich höchstens bis zur Mitte des Abstands
      L.style.setProperty('--nk-tx', Math.min(gg / 2, rand) + 'px'); L.style.setProperty('--nk-ty', rand + 'px');
      Array.from(L.children).forEach((b, i) => {
        b.style.width = b.style.height = dd + 'px';
        b.style.fontSize = Math.round(dd * 0.56) + 'px';
        b.style.setProperty('--i', String(i));
      });
      // Zeile „Du“: Name und „dran“ machen der Reihe Platz (wie OpponentSeat.row_reserve der App); „Du bist dran“ wird dort „dran“
      if (zeile) {
        const zg = zeile.e.querySelector('.zug');
        if (wahl.inZeile) {
          zeile.e.style.setProperty('--nk-res', (Math.max(0, zeile.spalte - wahl.left + 3) / (t.s || 1)).toFixed(1) + 'px');
          if (zg && zg.textContent === M.t('Du bist dran')) zg.textContent = M.t('dran');
        } else {
          zeile.e.style.removeProperty('--nk-res');
          if (zg && zg.textContent === M.t('dran')) zg.textContent = M.t('Du bist dran');
        }
      }
      document.querySelectorAll('#tisch .gg').forEach(e => { if (!zeile || e !== zeile.e) e.style.removeProperty('--nk-res'); });
      document.body.classList.toggle('nk-unten', wahl.unten);
      document.documentElement.style.setProperty('--nk-leiste-h', Math.round(wahl.h) + 'px');
      this._leisteStand();
      if (this.offen) this._menuePlatz();
    },
    // alle 400 ms: Menü nach der Uhr auffrischen bzw. nach 15 s ohne Tipp schließen; Ebene unter anderen Fenstern (Menü, Regeln …) verstecken
    // Gerätetest 1.6.3: Fenster (Menü, Regeln …) verdecken die ganze Ebene; das Farbrad nur die Reaktionsleiste (Effektzeilen bleiben)
    _modal() { return !!document.querySelector('.modal:not([hidden]):not(#runde)'); },
    _farbwahl() { const t = this.app && this.app.tisch; return !!(t && t.farbwahl && t.farbwahlOffen); },
    _ueberdeckt() { return this._modal() || this._farbwahl(); },
    _takt() {
      if (!this.ebene) return;
      const modal = this._modal(), fw = this._farbwahl();
      this.ebene.classList.toggle('verdeckt', modal);
      this.ebene.classList.toggle('farbwahl', fw);
      if (modal && this.offen) this.zu();
      if (this.offen) { if (this.uhr() > this.offen.bis) this.zu(); else this._menueStand(); }
      if (!this.leiste.hidden) this._leisteStand();   // Sperrzeit läuft ab bzw. nach fx_no rate wieder frei
      const runde = !!document.querySelector('#runde:not([hidden])');
      if (runde !== this._runde) { this._runde = runde; this.layout(); }   // Rundenende-Tafel auf/zu: Leiste neu legen
      if (this.app && this.app.screen !== 'tisch' && !this.leiste.hidden) this.layout();
    },
    _drueck(b) { b.classList.remove('drueck'); void b.offsetWidth; b.classList.add('drueck'); },
    _wackel(b) { b.classList.remove('wackel'); void b.offsetWidth; b.classList.add('wackel'); },

    /* ---------- Effekte ---------- */
    // angenommenes Necken zeigen; rolle = ziel | absender | zuschauer
    zeige(m) {
      const t = this.app.tisch, ich = t.v.seat;
      const rolle = m.to === ich ? 'ziel' : (m.from === ich ? 'absender' : 'zuschauer');
      this.gezeigt.push({ k: m.k, from: m.from, to: m.to, r: m.r, reveal: m.reveal, rolle });
      if (this.gezeigt.length > 40) this.gezeigt.shift();
      // Beta 1.6.6: Bestätigung nur beim Leger – leise Zeile, kein Bild am Ziel, kein Ton (sonst hörte es der Tisch)
      if (m.k === CUSHION) this.app.toast(M.t('Kissen liegt bei %s.', this._name(m.to)), 'leise', 2400);
      else if (m.k === CUSHION_POP) this._kissen(m, rolle);
      else if (m.k === 'react') this._reaktion(m.from, m.r);
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
      [t.knMenue, t.knTon, t.knSort, t.knRueck, this.leiste].forEach(e => dazu(hart, e));   // Knöpfe (auch die Reaktionsleiste): nicht zudecken
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
      this._kissenT.forEach(clearTimeout);   // 1.6.6: ausstehender Pups-Ton, „Kim war's!“
      this._kissenT = [];
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
      let top = a.width ? a.top - h - 12 : window.innerHeight * 0.6;
      const left = Math.max(6, Math.min(vw - w - 6, a.width ? (t.gross ? a.left + a.width / 2 - w / 2 : a.left - 6) : (vw - w) / 2));
      // Beta 1.6.5: nicht über den Reaktionsknöpfen – dann darüber
      const l = this.leiste && !this.leiste.hidden ? this.leiste.getBoundingClientRect() : null;
      if (l && l.width && ueber({ left, top, right: left + w, bottom: top + h, width: w, height: h }, l, 6) && l.top - h - 8 >= 6) top = l.top - h - 8;
      z.style.left = Math.round(left) + 'px';
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
      // (Zeile „Du“ mit den Reaktionsknöpfen davor: am linken Rand der Zeile, die Knöpfe lägen sonst darüber)
      const inZeile = t.gross && to === ich && this.leiste && !this.leiste.hidden && this.leiste.dataset.lage === 'zeile';
      const liegt = inZeile ? { x: this._kopf(to).rect.l - 6 - Math.random() * 10, y: z.y + 6 }
        : t.gross ? { x: this._kopf(to).zahlX - 36 - Math.random() * 60, y: z.y + 6 }
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

    // Beta 1.6.6 Furzkissen: Kissen am Platz des Ziels (beim Ziel groß über dem eigenen Namensschild), wird plattgedrückt, Wolke und
    // „Pfffrt!“; Ton beim Ziel normal, bei allen anderen leise (auch beim Leger), Vibration nur beim Ziel; danach „Kim war's!“ bzw.
    // „Wer war das?“ (geheim auch beim Leger, obwohl seine Kopie from enthält). Effekte reduziert: Kissen und Wolke blenden nur.
    _kissen(m, rolle) {
      const t = this.app.tisch, to = m.to, z = this.anker(to), kp = this._kopf(to), red = this.reduziert();
      const ziel = rolle === 'ziel';
      const W = ziel ? 170 : (t.gross ? 140 : 130), H = Math.round(W * 0.75);
      const rel = { l: -W * 0.6, r: W * 0.6 + 40, t: -H * 0.5 - 48, b: H * 0.5 };   // plattgedrückt breiter, „Pfffrt!“ oben rechts
      const kand = [];
      if (t.gross) kand.push({ x: kp.zahlX - W * 0.6 - 44, y: z.y, rel });
      if (ziel && !t.gross) kand.push({ x: z.x + 30, y: z.y - z.r - H * 0.5 - 14, rel });
      kand.push({ x: z.x - W * 0.08, y: z.y + z.r * 1.15, rel });                    // auf dem Platz: unter dem Avatar (er sitzt darauf)
      kand.push({ x: z.x - z.r - W * 0.6 - 6, y: z.y + z.r * 0.3, rel });
      kand.push({ x: kp.rect.r + W * 0.6 + 6, y: z.y, rel });
      kand.push({ x: z.x, y: z.y - z.r - H * 0.5 - 4, rel });
      const hind = this._hindernisse(to);
      const p = this._waehle(kand, { hart: hind.hart, weich: hind.weich.slice(0, -1) });   // der eigene Kopf darf darauf sitzen
      const e = el('div', 'nk-furz' + (ziel ? ' ziel' : '') + (red ? ' still' : ''),
        '<div class="nk-kk">' + SVG_KISSEN + '</div><div class="nk-wolke"><b></b><b></b><b></b><b></b></div><div class="nk-pf">' + esc(M.t('Pfffrt!')) + '</div>');
      e.style.width = W + 'px'; e.style.height = H + 'px';
      this._aufBuehne(e, p.x, p.y, KISSEN_MS, to);
      const spaeter = (ms, f) => { const id = setTimeout(() => { this._kissenT = this._kissenT.filter(x => x !== id); f(); }, ms); this._kissenT.push(id); };
      spaeter(PLATT_MS, () => {
        if (!e.isConnected) return;
        this._ton('furzkissen', ziel ? 1 : LEISE);
        if (ziel) this.app.vibrieren(KISSEN_VIB);
        this._stauchen(to);
      });
      const text = m.reveal === true && typeof m.from === 'number' && m.from >= 0 ? M.t("%s war's!", this._name(m.from)) : M.t('Wer war das?');
      spaeter(KISSEN_MS - 250, () => {
        if (!e.isConnected) return;
        if (ziel) { this.zeile(text, WER_MS); return; }
        const w = Math.min(340, 28 + text.length * 13), h = 42, rt = { l: -w / 2, r: w / 2, t: -h, b: 0 };
        const q = this._waehle([{ x: p.x, y: p.y - H * 0.1, rel: rt }, { x: p.x, y: p.y + H * 0.5 + h, rel: rt }, { x: p.x, y: p.y - H * 0.5 - 6, rel: rt }], hind);
        this._aufBuehne(el('div', 'nk-mpf nk-wer', esc(text)), q.x, q.y, WER_MS, to);
      });
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
      const em = el('div', 'nk-emoji' + (this.reduziert() ? ' still' : ''));
      em.appendChild(reaktSymbol(r));
      this._aufBuehne(em, p.x, p.y, REAKT_AUF_MS, from);
      const now = this.uhr();
      this._rt = this._rt.filter(e => e > now);
      if (this._rt.length >= 2 || now - (this._rtName[r] === undefined ? -1e9 : this._rtName[r]) < 600) return;   // höchstens 2 gleichzeitig, je Name 600 ms
      if (this._ton(r)) { this._rt.push(now + REAKT_MS[r]); this._rtName[r] = now; }
    },
  };

  M.Necken = N;
})(window.MMF = window.MMF || {});
