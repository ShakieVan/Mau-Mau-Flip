/* Mau-Mau Flip – Browser-Client „Lite“: der Tisch im Querformat und die Tischregie.
 * Die Bühne hat Logik-Pixel wie der Entwurf (Höhe 720, Breite je nach Gerät) und wird per CSS skaliert.
 * zeige(view) gleicht alles mit der Sicht des Gastgebers ab; Regie spielt vorher die Ereignisse als kurze
 * CSS-Animationen ab (Karte fliegt, Ziehen, Farbwelle, Flip als Tag→Nacht-Übergang, Mau-Blase, Abzeichen).
 */
(function (M) {
  'use strict';

  const K = () => M.Karten;
  const H0 = 720, W_MIN = 1180;
  const AVA_FARBEN = ['#FF9ECF', '#43B05C', '#FFDD33', '#4C7DFF', '#FF8A1F', '#19C6D4', '#8B6BFF', '#FF4D57', '#B0E06A', '#F4EADA'];
  const schlaf = ms => new Promise(r => setTimeout(r, ms));
  const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  function el(tag, cls, html) { const e = document.createElement(tag); if (cls) e.className = cls; if (html !== undefined) e.innerHTML = html; return e; }
  function kartenRot(id) { return ((Math.abs(id | 0) * 37) % 23) - 11; }
  function offenText(p) {
    if (!p || !p.kind) return p && p.amount ? '+' + p.amount : '';
    if (p.kind === 'farbjagd') return 'Jagd!';
    return p.amount ? '+' + p.amount : '';
  }
  // Testhilfe: ?tempo=N beschleunigt die Tischregie (nur für Prüfläufe)
  const TEMPO = Math.max(0.2, Math.min(8, +((M.param && M.param('tempo')) || new URLSearchParams(location.search).get('tempo') || 1) || 1));
  // Standzeit der Mau-Blase: folgt dem Regie-Tempo, bleibt aber lesbar (mind. 0,9 s); ?blase=ms setzt sie fest (Kontrollbilder)
  function blasenDauer(ms, d) { return BLASE_PARAM > 0 ? BLASE_PARAM : Math.max(900, d(ms)); }

  const ICON_SORT = '<svg viewBox="0 0 26 26" aria-hidden="true"><path d="M7 4v17M7 21l-4-4M7 21l4-4M19 22V5M19 5l-4 4M19 5l4 4" stroke="currentColor" stroke-width="2.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  const ICON_RUECK = '<svg viewBox="0 0 26 26" aria-hidden="true"><rect x="4" y="3" width="13" height="19" rx="3" fill="none" stroke="currentColor" stroke-width="2.4"/><rect x="10" y="6" width="13" height="18" rx="3" fill="#0A0D20" stroke="#FF7FCF" stroke-width="2.4"/></svg>';
  const ICON_MENUE = '<svg viewBox="0 0 26 26" aria-hidden="true"><path d="M5 8h16M5 13h16M5 18h16" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"/></svg>';
  const ICON_TON = '<svg viewBox="0 0 26 26" aria-hidden="true"><path d="M4 10h4l6-5v16l-6-5H4z" fill="currentColor" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path class="an" d="M17.5 9.5a5 5 0 0 1 0 7M20.5 6.5a9.5 9.5 0 0 1 0 13" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/><path class="aus" d="M17 9.5l7 7M24 9.5l-7 7" fill="none" stroke="#FF6B6B" stroke-width="2.6" stroke-linecap="round"/></svg>';
  // Mau-Sprechblase: Animationsvarianten (zufällig je Ruf), „schlicht“ bei reduzierten Effekten bzw. prefers-reduced-motion
  const BLASEN = ['plopp', 'ohren', 'huepf', 'ballon', 'gummi'];
  const BLASE_PARAM = +((M.param && M.param('blase')) || new URLSearchParams(location.search).get('blase') || 0);   // Testhilfe: feste Dauer in ms
  const STERNE = [[-8, 18, -26, -18], [104, 10, 28, -22], [92, 96, 30, 20], [-6, 88, -28, 18], [48, -18, 0, -30], [30, 108, -6, 26]];   // x %, y %, Drift x/y px
  const ICON_GETRENNT ='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 9a13 13 0 0 1 18 0M6.5 12.5a8 8 0 0 1 11 0M10 16a3 3 0 0 1 4 0" stroke="currentColor" stroke-width="2.2" fill="none" stroke-linecap="round"/><path d="M4 4l16 16" stroke="#FF6B6B" stroke-width="2.4" stroke-linecap="round"/></svg>';

  class Tisch {
    // app: Rückrufe {spielen(id), antippen(id), ziehen(), aktion(a), mau(), sortieren(), rueckseiten(), menue(), hilfe(face), gegnerAnsicht(seat), sortModus()}
    constructor(root, app) {
      this.root = root; this.app = app;
      this.s = 1; this.W = 1600; this.H = H0; this.ox = 0; this.oy = 0;
      this.v = null;
      this.ablageVerlauf = [];   // [{id, face}] die letzten Karten der Ablage (für den kleinen Stapel)
      this.gegnerEls = new Map();
      this.regie = new Regie(this);
      this._baue();
    }

    _baue() {
      const r = this.root;
      this.himmel = el('div', 'himmel', '<div class="tag"></div><div class="nacht"><div class="sterne"></div></div>');
      r.appendChild(this.himmel);
      const b = this.buehne = el('div', 'buehne');
      b.id = 'buehne';
      r.appendChild(b);
      this.ring = el('div', 'richtung');
      this.ring.innerHTML = '<svg viewBox="-400 -230 800 460" aria-hidden="true"><g class="pfeile">' +
        '<path class="bahn" d="M-240 -116A330 170 0 0 1 240 -116"/><path class="spitze" d="M240 -116l-8 -22M240 -116l-24 4"/>' +
        '<path class="bahn" d="M290 99A330 150 0 0 1 -290 99"/><path class="spitze" d="M-290 99l6 22M-290 99l24 -6"/></g></svg>';
      b.appendChild(this.ring);
      this.gegnerBox = el('div', 'gegner-box'); b.appendChild(this.gegnerBox);
      this.stapel = el('div', 'stapel'); b.appendChild(this.stapel);
      this.stapel.innerHTML = '<div class="leer"></div>';
      this.stapelUnter = [K().element('rueckseite', 118, 'unter u2'), K().element('rueckseite', 118, 'unter u1')];
      this.stapelOben = K().element('rueckseite', 118, 'oben');
      this.stapelUnter.forEach(e => this.stapel.appendChild(e));
      this.stapel.appendChild(this.stapelOben);
      this.stapelZahl = el('div', 'stapelzahl'); b.appendChild(this.stapelZahl);
      this.farbe = el('div', 'farbanzeige'); b.appendChild(this.farbe);
      this.ablage = el('div', 'ablage', '<div class="farbring"></div><div class="karten"></div><div class="offen"></div>');
      b.appendChild(this.ablage);
      this.farbring = this.ablage.querySelector('.farbring');
      this.ablageKarten = this.ablage.querySelector('.karten');
      this.offenEl = this.ablage.querySelector('.offen');
      this.leiste = el('div', 'leiste', '<div class="hinweis"></div><div class="aktionen"></div>');
      b.appendChild(this.leiste);
      this.hinweis = this.leiste.firstChild; this.aktionen = this.leiste.lastChild;
      this.hand = new M.Hand.Hand(this, {
        antippen: id => this.app.antippen(id), spielen: id => this.app.spielen(id), hilfe: f => this.app.hilfe(f), leer: () => this.app.antippen(null),
      });
      b.appendChild(this.hand.zone); b.appendChild(this.hand.el);
      this.knSort = el('button', 'pill sortieren', ICON_SORT + '<span>Farbe</span>'); b.appendChild(this.knSort);
      this.knRueck = el('button', 'pill rueckseiten', ICON_RUECK + '<span>Rückseiten</span>'); b.appendChild(this.knRueck);
      this.knMau = el('button', 'mau-knopf', '<span>Mau!</span>'); b.appendChild(this.knMau);
      this.knMenue = el('button', 'rund menue-knopf', ICON_MENUE); this.knMenue.setAttribute('aria-label', 'Menü'); b.appendChild(this.knMenue);
      this.knTon = el('button', 'rund ton-knopf', ICON_TON); this.knTon.id = 'ton-knopf'; b.appendChild(this.knTon);
      this.zeigeTon();
      this.flug = el('div', 'flug'); b.appendChild(this.flug);
      this.farbwahl = el('div', 'farbwahl'); this.farbwahl.hidden = true; b.appendChild(this.farbwahl);
      this.knSort.id = 'sortieren'; this.knRueck.id = 'rueckseiten'; this.knMau.id = 'mau'; this.stapel.id = 'stapel'; this.ablage.id = 'ablage';

      const tipp = (e, f) => { e.addEventListener('click', ev => { ev.preventDefault(); f(ev); }); };
      tipp(this.knSort, () => this.app.sortieren());
      tipp(this.knRueck, () => this.app.rueckseiten());
      tipp(this.knMau, () => this.app.mau());
      tipp(this.knMenue, () => this.app.menue());
      tipp(this.knTon, () => this.app.tonSchalter());
      tipp(this.stapel, () => this.app.ziehen());
      this._halten(this.ablage, () => this.v && this.v.top && this.app.hilfe(this.v.top.face));
      this._halten(this.stapel, () => this.v && this.v.draw_back && this.app.hilfe(this.v.draw_back));
      this.aktionen.addEventListener('click', e => {
        const k = e.target.closest('button[data-a]');
        if (k) { e.preventDefault(); this.app.aktion({ a: k.dataset.a }); }
      });
      this.gegnerBox.addEventListener('click', e => {
        const k = e.target.closest('.erwischen');
        const g = e.target.closest('.gg');
        if (!g) return;
        e.preventDefault();
        if (k) this.app.aktion({ a: 'catch', target: +g.dataset.seat });
        else this.app.gegnerAnsicht(+g.dataset.seat);
      });
    }
    // langes Drücken auf Stapel/Ablage → Kartenhilfe
    _halten(e, f) {
      let t = 0;
      e.addEventListener('pointerdown', () => { clearTimeout(t); t = setTimeout(() => { t = -1; f(); }, 500); });
      const ende = () => { if (t > 0) clearTimeout(t); };
      e.addEventListener('pointerup', ende); e.addEventListener('pointercancel', ende); e.addEventListener('pointerleave', ende);
      e.addEventListener('click', ev => { if (t === -1) { ev.stopImmediatePropagation(); ev.preventDefault(); t = 0; } }, true);
    }

    /* ---------- Größe und Koordinaten ---------- */
    groesse(vw, vh, links, rechts) {
      const breite = Math.max(200, vw - links - rechts);
      let s = vh / H0, W = breite / s, H = H0;
      if (W < W_MIN) { s = breite / W_MIN; W = W_MIN; H = vh / s; }
      this.s = s; this.W = W; this.H = H; this.ox = links; this.oy = 0;
      const b = this.buehne;
      b.style.width = W + 'px'; b.style.height = H + 'px';
      b.style.transform = 'translate(' + links + 'px,0) scale(' + s + ')';
      b.classList.toggle('eng', s < 0.5);
      this._geometrie();
      if (this.v) this.zeige(this.v, true);
    }
    zuBuehne(cx, cy) {
      const r = this.root.getBoundingClientRect();
      return { x: (cx - r.left - this.ox) / this.s, y: (cy - r.top - this.oy) / this.s };
    }
    _geometrie() {
      const W = this.W, H = this.H;
      const cx = W / 2, cy = Math.round(H * 0.446);
      this.g = { cx, cy, stapel: { x: cx - 177, y: cy }, ablage: { x: cx + 177, y: cy } };
      const setz = (e, x, y) => { e.style.left = x + 'px'; e.style.top = y + 'px'; };
      setz(this.ring, cx, cy);
      setz(this.stapel, cx - 177, cy);
      setz(this.stapelZahl, cx - 177, cy + 106);
      setz(this.farbe, cx, cy);
      setz(this.ablage, cx + 177, cy);
      setz(this.leiste, cx, H - 212);
      setz(this.farbwahl, cx + 177, cy);
      this.knSort.style.top = (H - 160) + 'px';
      this.knRueck.style.top = (H - 88) + 'px';
    }
    // Position eines Platzes (Bühnenkoordinaten) für Flüge und Abzeichen
    platzPos(seat) {
      if (!this.v || seat === this.v.seat) return { x: this.g.cx, y: this.H - 110, w: 150 };
      const g = this.gegnerEls.get(seat);
      if (g) return { x: g.px, y: g.py + 26, w: g.kompakt ? 46 : 60 };
      return { x: this.g.cx, y: 60, w: 60 };
    }
    _gegnerPos(r, n) {
      const phi0 = 55 * Math.PI / 180, theta = 2 * Math.PI * r / n;
      const phi = phi0 + theta * (2 * Math.PI - 2 * phi0) / (2 * Math.PI);
      const ocx = this.g.cx, ocy = this.g.cy + 84;
      const rx = Math.min(this.W / 2 - 150, 820), ry = ocy - 92;
      return { x: ocx - Math.sin(phi) * rx, y: ocy + Math.cos(phi) * ry };
    }

    /* ---------- Abgleich mit der Sicht ---------- */
    zeige(v, nurLayout) {
      const alt = this.v;
      this.v = v;
      const ich = v.seat;
      this.root.dataset.seite = v.side || 'hell';
      this._zeigeGegner(v);
      this._zeigeStapel(v);
      this._zeigeAblage(v, alt);
      this._zeigeFarbe(v);
      this.ring.classList.toggle('gegen', v.dir === -1);
      const h = v.hints || {};
      const spielbar = h.playable || [];
      // Phasen des Gastgebers (MauGame): turn, drawn, challenge, color, round_over, game_over (idle nur vor dem Austeilen)
      const dran = v.turn === ich && (v.phase === 'turn' || v.phase === 'drawn' || v.phase === 'challenge' || v.phase === 'color');
      this.hinweis.textContent = h.text || this._hinweisErsatz(v);
      this.hinweis.classList.toggle('dran', v.turn === ich && dran);
      const p = v.pending || {};
      const jagd = p.kind === 'farbjagd';
      let ak = '';
      // In „challenge“ ist Ziehen dasselbe wie Annehmen → nur ein Knopf
      if (h.can_draw && !h.can_accept) ak += '<button class="knopf klein" data-a="draw">' + (p.kind && v.turn === ich ? (jagd ? 'Ziehen bis Farbe' : (p.amount | 0) + ' ziehen') : 'Ziehen') + '</button>';
      if (h.can_keep) ak += '<button class="knopf klein" data-a="keep">Behalten</button>';
      if (h.can_challenge) ak += '<button class="knopf klein warn" data-a="challenge">Anzweifeln</button>';
      if (h.can_accept || (h.can_challenge && h.can_accept === undefined)) ak += '<button class="knopf klein" data-a="accept">' + (jagd ? 'Annehmen' : 'Annehmen' + (p.amount ? ' (+' + p.amount + ')' : '')) + '</button>';
      if (h.need_color) ak += '<button class="knopf klein" data-a="wunsch">Farbe wählen</button>';
      if (this.aktionen.innerHTML !== ak) this.aktionen.innerHTML = ak;
      this.stapel.classList.toggle('ziehbar', !!h.can_draw);
      this.knMau.classList.toggle('bereit', !!h.can_mau);
      this.knMau.hidden = !!(v.rules && v.rules.mau_call === 'off');
      const ichSpieler = (v.players || []).find(p => p.seat === ich);
      this.knMau.classList.toggle('gerufen', !!(ichSpieler && ichSpieler.mau));
      const peek = !(v.rules && v.rules.peek_own_backs === false) && (v.hand || []).some(c => c.back);
      this.knRueck.hidden = !peek;
      if (!peek && this.hand.rueck) this.hand.zeigeRueck(false);
      this.knRueck.classList.toggle('aktiv', this.hand.rueck);
      this.knSort.lastChild.textContent = { farbe: 'Farbe', wert: 'Wert', punkte: 'Punkte' }[this.app.sortModus()] || 'Farbe';
      const reihe = K().sortiere(v.hand || [], this.app.sortModus());
      this.hand.setze(reihe, { spielbar, dran: dran && (v.phase === 'turn' || v.phase === 'drawn' || (v.phase === 'challenge' && spielbar.length > 0)) });
      if (!nurLayout && alt && alt.turn !== ich && v.turn === ich && dran) {
        M.Ton.spiele('dran');
        if (this.app.vibrieren) this.app.vibrieren(25);
      }
    }
    _hinweisErsatz(v) {
      const p = (v.players || []).find(x => x.seat === v.turn);
      if (v.phase === 'round_over') return 'Runde vorbei';
      if (v.phase === 'game_over') return 'Partie vorbei';
      if (v.turn === v.seat) return 'Du bist dran';
      return p ? p.name + ' ist dran' : '';
    }
    _zeigeGegner(v) {
      const ich = v.seat;
      const spieler = (v.players || []).slice().sort((a, b) => a.seat - b.seat);
      const n = spieler.length;
      const kompakt = n >= 7;
      const h = v.hints || {};
      const fangbar = new Set(h.catch || []);
      const da = new Set();
      spieler.forEach(p => {
        if (p.seat === ich) return;
        da.add(p.seat);
        let g = this.gegnerEls.get(p.seat);
        if (!g) {
          const e = el('div', 'gg');
          e.dataset.seat = p.seat;
          e.innerHTML = '<div class="kopf"><div class="ava"></div><div class="name"></div><div class="zahl"></div></div><div class="faecher"></div><div class="marken"></div><button class="erwischen">Erwischt!</button>';
          this.gegnerBox.appendChild(e);
          g = { e, sig: '' };
          this.gegnerEls.set(p.seat, g);
        }
        const rel = (p.seat - ich + n) % n;
        const pos = this._gegnerPos(rel, n);
        g.px = pos.x; g.py = pos.y; g.kompakt = kompakt;
        const e = g.e;
        e.classList.toggle('kompakt', kompakt);
        e.style.left = pos.x + 'px'; e.style.top = pos.y + 'px';
        e.classList.toggle('dran', v.turn === p.seat && v.phase !== 'round_over' && v.phase !== 'game_over');
        e.classList.toggle('weg', p.connected === false);
        e.classList.toggle('fangbar', fangbar.has(p.seat));
        const ava = e.querySelector('.ava');
        ava.textContent = (p.name || '?').trim().charAt(0).toUpperCase();
        ava.style.background = AVA_FARBEN[p.seat % AVA_FARBEN.length];
        e.querySelector('.name').textContent = p.name || ('Platz ' + (p.seat + 1));
        e.querySelector('.zahl').textContent = p.count;
        let marken = '';
        if (p.mau) marken += '<span class="marke mau">Mau!</span>';
        if (p.kind === 'bot' && !kompakt) marken += '<span class="marke">Computer</span>';
        if (p.place > 0) marken += '<span class="marke platz">' + p.place + '. Platz</span>';
        if (p.connected === false) marken += '<span class="marke weg">' + ICON_GETRENNT + 'getrennt</span>';
        const mk = e.querySelector('.marken');
        if (mk.innerHTML !== marken) mk.innerHTML = marken;
        // Fächer der sichtbaren Rückseiten (sortiert vom Gastgeber) oder neutrale Rückseiten
        const backs = (p.backs && p.backs.length) ? p.backs : new Array(Math.min(p.count | 0, 14)).fill('rueckseite');
        const sig = backs.join(',') + '|' + kompakt + '|' + p.count;
        if (g.sig !== sig) { g.sig = sig; this._faecher(e.querySelector('.faecher'), backs, kompakt, p.count); }
      });
      for (const [seat, g] of this.gegnerEls) if (!da.has(seat)) { g.e.remove(); this.gegnerEls.delete(seat); }
    }
    _faecher(box, backs, kompakt, count) {
      box.innerHTML = '';
      const n = backs.length;
      const breite = kompakt ? 150 : 200;
      const einzel = n === 1;
      // eine Karte etwas größer, aber so, dass die Marken darunter frei bleiben (Fächerhöhe passt sich an)
      const w = einzel ? (kompakt ? 52 : 66) : (kompakt ? 46 : 60);
      box.style.height = einzel ? Math.ceil(w * K().VERHAELTNIS + 8) + 'px' : '';
      const step = n > 1 ? Math.min(kompakt ? 16 : 22, (breite - w - 10) / (n - 1)) : 0;
      const spread = kompakt ? Math.min(4, 28 / Math.max(1, n)) : Math.min(7, 60 / Math.max(1, n));
      backs.forEach((f, i) => {
        const t = i - (n - 1) / 2;
        const k = K().element(f, w, 'mini');
        k.style.left = (breite / 2 - w / 2 + t * step).toFixed(1) + 'px';
        k.style.transform = 'rotate(' + (t * spread).toFixed(1) + 'deg)';
        box.appendChild(k);
      });
      if (count > n) box.appendChild(el('span', 'mehr', '+' + (count - n)));
    }
    _zeigeStapel(v) {
      const n = v.draw_count | 0;
      this.stapel.classList.toggle('leer', n === 0);
      const back = v.draw_back || 'rueckseite';
      K().setzeGesicht(this.stapelOben, back);
      this.stapelUnter.forEach((e, i) => { K().setzeGesicht(e, back); e.style.display = n > i + 1 ? '' : 'none'; });
      this.stapelOben.style.display = n > 0 ? '' : 'none';
      this.stapelZahl.textContent = 'Stapel · ' + n;
    }
    _zeigeAblage(v, alt) {
      const top = v.top;
      if (!top) { this.ablageKarten.innerHTML = ''; this.ablageVerlauf = []; return; }
      const letzte = this.ablageVerlauf[this.ablageVerlauf.length - 1];
      if (alt && alt.side !== v.side) this.ablageVerlauf = [];
      if (!letzte || letzte.id !== top.id || letzte.face !== top.face) {
        if (this.ablageVerlauf.length && this.ablageVerlauf[this.ablageVerlauf.length - 1].id === top.id) this.ablageVerlauf.pop();
        this.ablageVerlauf.push({ id: top.id, face: top.face });
        while (this.ablageVerlauf.length > 3) this.ablageVerlauf.shift();
      }
      const sig = this.ablageVerlauf.map(c => c.id + c.face).join(',');
      if (this.ablageKarten.dataset.sig !== sig) {
        this.ablageKarten.dataset.sig = sig;
        this.ablageKarten.innerHTML = '';
        this.ablageVerlauf.forEach((c, i) => {
          const k = K().element(c.face, 124, i === this.ablageVerlauf.length - 1 ? 'top' : 'alt');
          k.style.transform = 'translate(-50%,-50%) rotate(' + (i === this.ablageVerlauf.length - 1 ? kartenRot(c.id) * 0.4 : kartenRot(c.id)) + 'deg)';
          this.ablageKarten.appendChild(k);
        });
      }
      // offene Ziehstrafe: pending {kind, amount, by, victim, color}; Farbjagd hat amount 0 (gezogen wird bis zur Farbe)
      const p = v.pending;
      const txt = offenText(p);
      this.offenEl.textContent = txt;
      this.offenEl.hidden = !txt;
    }
    _zeigeFarbe(v) {
      const f = v.color;
      const fi = K().FARB_INFO[f];
      const sig = f + (K().Bilder.symbole ? 'b' : 's');
      if (this.farbe.dataset.sig !== sig) {
        this.farbe.dataset.sig = sig;
        this.farbe.innerHTML = fi ? K().farbSymbolHTML(f, { kontur: '#F4EADA', konturBreite: 4 }) + '<span>' + esc(fi.name) + '</span>' : '';
      }
      this.farbring.style.setProperty('--ring', fi ? fi.ring : 'rgba(244,234,218,.35)');
      this.root.style.setProperty('--farbe', fi ? fi.ring : '#9A86FF');
    }

    /* ---------- Farbwahl (vier Felder um die Ablage) ---------- */
    oeffneFarbwahl(seite, zaehlung, beiWahl) {
      const fw = this.farbwahl;
      const farben = K().FARBEN[seite] || K().FARBEN.hell;
      fw.innerHTML = '<div class="schleier"></div>' + farben.map((f, i) => {
        const fi = K().FARB_INFO[f];
        const grund = seite === 'dunkel' ? fi.ring : fi.hex;
        const hellGrund = f === 'gelb' || f === 'pink';
        return '<button class="feld f' + i + '" data-farbe="' + f + '" style="--f:' + grund + '">' +
          K().symbolSVG(f, { farbe: hellGrund ? K().INK : K().CREAM, grund }) +
          '<b>' + esc(fi.name) + '</b><i>' + (zaehlung[f] ? zaehlung[f] + '× auf der Hand' : 'keine') + '</i></button>';
      }).join('') + '<button class="abbrechen rund" aria-label="Abbrechen">✕</button><div class="frage">Welche Farbe?</div>';
      fw.hidden = false;
      fw.classList.remove('auf'); void fw.offsetWidth; fw.classList.add('auf');
      fw.onclick = e => {
        const b = e.target.closest('button');
        if (!b && !e.target.classList.contains('schleier')) return;
        e.preventDefault();
        const farbe = b && b.dataset.farbe;
        this.schliesseFarbwahl();
        beiWahl(farbe || null);
      };
    }
    schliesseFarbwahl() { this.farbwahl.hidden = true; this.farbwahl.onclick = null; }
    get farbwahlOffen() { return !this.farbwahl.hidden; }

    /* ---------- Effekte ---------- */
    fliege(face, von, nach, dauer, opt) {
      const w = von.w || 124;
      const k = K().element(face, w, 'flug-karte');
      const h = w * K().VERHAELTNIS;
      const tf = (p, sc) => 'translate(' + (p.x - w / 2).toFixed(1) + 'px,' + (p.y - h / 2).toFixed(1) + 'px) rotate(' + (p.rot || 0) + 'deg) scale(' + sc + ')';
      k.style.transform = tf(von, 1);
      this.flug.appendChild(k);
      void k.offsetWidth;
      k.style.transition = 'transform ' + dauer + 'ms cubic-bezier(.2,.75,.25,1)' + (opt && opt.ausblenden ? ', opacity ' + dauer + 'ms ease-in' : '');
      k.style.transform = tf(nach, (nach.w || w) / w);
      if (opt && opt.ausblenden) k.style.opacity = '0.2';
      return schlaf(dauer).then(() => { if (!(opt && opt.bleiben)) k.remove(); return k; });
    }
    abzeichen(seat, html, cls, dauer) {
      const p = this.platzPos(seat);
      const a = el('div', 'abzeichen ' + (cls || ''), html);
      a.style.left = p.x + 'px'; a.style.top = (p.y - (seat === (this.v && this.v.seat) ? 60 : 50)) + 'px';
      a.style.animationDuration = dauer + 'ms';
      this.flug.appendChild(a);
      setTimeout(() => a.remove(), dauer + 50);
    }
    // Ton-Knopf in der Ecke: Zustand aus den Einstellungen
    zeigeTon() {
      const stumm = !!(this.app.einstellungen && this.app.einstellungen.stumm);
      this.knTon.classList.toggle('stumm', stumm);
      this.knTon.setAttribute('aria-label', stumm ? 'Ton einschalten' : 'Ton ausschalten');
      this.knTon.setAttribute('aria-pressed', stumm ? 'true' : 'false');
    }

    /* ---------- „Mau!“-Sprechblase beim rufenden Spieler ---------- */
    // art 'mau' („Mau!“) oder 'mau_mau' („Mau-Mau!“, größer, wer fertig ist). Variante zufällig (nie zweimal dieselbe hintereinander),
    // „schlicht“ bei reduzierten Effekten. Rückgabe: das Element (Selbsttest).
    mauBlase(seat, art, dauer, variante) {
      const gross = art === 'mau_mau';
      const ruhigWunsch = this.app.effekteReduziert() || !!(window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches);
      if (!variante) {
        if (ruhigWunsch) variante = 'schlicht';
        else {
          const wahl = BLASEN.filter(x => x !== this._letzteBlase);
          variante = wahl[Math.floor(Math.random() * wahl.length)];
        }
      }
      this._letzteBlase = variante;
      const text = gross ? 'Mau-Mau!' : 'Mau!';
      const inhalt = variante === 'huepf' ? Array.from(text).map((c, i) => '<b style="--i:' + i + '">' + esc(c) + '</b>').join('') : esc(text);
      let extra = '';
      if (variante === 'ballon') extra += '<i class="ring r1"></i><i class="ring r2"></i><i class="ring r3"></i>';
      if (variante === 'ohren' || (gross && variante !== 'schlicht')) {
        STERNE.forEach((s, i) => { extra += '<i class="stern" style="left:' + s[0] + '%;top:' + s[1] + '%;--sx:' + s[2] + 'px;--sy:' + s[3] + 'px;--i:' + i + '">✦</i>'; });
      }
      const b = el('div', 'mau-blase messen' + (gross ? ' gross' : ''),
        '<div class="koerper">' + (variante === 'ohren' ? '<i class="ohr l"></i><i class="ohr r"></i>' : '') +
        '<span class="txt">' + inhalt + '</span><i class="schwanz"></i></div>' + extra);
      b.dataset.seat = seat; b.dataset.variante = variante; b.dataset.art = gross ? 'mau_mau' : 'mau';
      this.flug.appendChild(b);
      const k = b.firstChild;
      const w = k.offsetWidth, h = k.offsetHeight;
      const a = this._blasenAnker(seat);
      const W = this.W, H = this.H, rand = 8, abstand = 20;
      const klemme = (x, lo, hi) => Math.max(lo, Math.min(hi, x));
      let left, top, tx, ty;
      if (a.seite === 'unten') {
        top = klemme(a.y - abstand - h, rand, H - h - rand);
        left = klemme(a.x - w / 2, rand, W - w - rand);
        tx = klemme(a.x - left, 26, w - 26); ty = h;
      } else {
        top = klemme(a.y - h / 2, rand, H - h - rand);
        left = klemme(a.seite === 'links' ? a.x + abstand : a.x - abstand - w, rand, W - w - rand);
        tx = a.seite === 'links' ? 0 : w; ty = klemme(a.y - top, 22, h - 22);
      }
      b.style.left = left.toFixed(1) + 'px'; b.style.top = top.toFixed(1) + 'px';
      b.style.width = w + 'px'; b.style.height = h + 'px';
      b.style.setProperty('--tx', tx.toFixed(1) + 'px'); b.style.setProperty('--ty', ty.toFixed(1) + 'px');
      // Spitze des Schwanzes (ragt ~18 px über den Rand): Drehpunkt der Animationen und Mitte der Schallringe
      const ox = a.seite === 'links' ? -18 : (a.seite === 'rechts' ? w + 18 : tx), oy = a.seite === 'unten' ? h + 18 : ty;
      b.style.setProperty('--ox', ox.toFixed(1) + 'px'); b.style.setProperty('--oy', oy.toFixed(1) + 'px');
      b.className = 'mau-blase v-' + variante + ' zeigt-' + a.seite + (gross ? ' gross' : '');
      this.blasenZahl = (this.blasenZahl || 0) + 1;
      const z = this.blasenVarianten = this.blasenVarianten || {};
      z[variante + (gross ? '+' : '')] = (z[variante + (gross ? '+' : '')] || 0) + 1;
      setTimeout(() => b.classList.add('aus'), dauer);
      setTimeout(() => b.remove(), dauer + 380);
      return b;
    }
    // Wohin die Blase zeigt (seite = Richtung des Schwanzes): eigener Platz → auf den Mau-Knopf (Blase darüber), Gegner → auf den
    // Kopf (Avatar, Name). Seitlich Sitzende bekommen die Blase zur Tischmitte hin, die obere Reihe nach außen (zwei Rufe oben
    // überdecken sich so nicht), wer oben in der Mitte sitzt, rechts davon.
    _blasenAnker(seat) {
      if (!this.v || seat === this.v.seat) return { x: this.W - 46 - 75 - 18, y: this.H - 40 - 150 + 6, seite: 'unten' };
      const g = this.gegnerEls.get(seat);
      const p = g ? { x: g.px, y: g.py } : this.platzPos(seat);
      const oben = p.y < this.H * 0.32, rechts = p.x > this.g.cx + 60, links = p.x < this.g.cx - 60;
      const blaseLinks = oben ? links : rechts;      // Blase links vom Kopf (Schwanz zeigt nach rechts)
      const kopf = g && g.e.querySelector('.kopf');
      if (kopf && kopf.getBoundingClientRect().width > 0) {
        const r = kopf.getBoundingClientRect();
        const l = this.zuBuehne(r.left, r.top), rb = this.zuBuehne(r.right, r.bottom);
        const y = (l.y + rb.y) / 2;
        return blaseLinks ? { x: l.x - 2, y, seite: 'rechts' } : { x: rb.x + 2, y, seite: 'links' };
      }
      return blaseLinks ? { x: p.x - 40, y: p.y - 60, seite: 'rechts' } : { x: p.x + 40, y: p.y - 60, seite: 'links' };
    }
    banner(titel, unter, cls, dauer) {
      const b = el('div', 'banner ' + (cls || ''), '<b>' + esc(titel) + '</b>' + (unter ? '<span>' + esc(unter) + '</span>' : ''));
      b.style.left = this.g.cx + 'px'; b.style.top = (this.g.cy - 4) + 'px';
      b.style.animationDuration = dauer + 'ms';
      this.flug.appendChild(b);
      setTimeout(() => b.remove(), dauer + 50);
    }
    welle(farbe) {
      const fi = K().FARB_INFO[farbe];
      if (!fi) return;
      const w = el('div', 'welle');
      w.style.left = this.g.ablage.x + 'px'; w.style.top = this.g.ablage.y + 'px';
      w.style.setProperty('--f', fi.ring);
      this.flug.appendChild(w);
      setTimeout(() => w.remove(), 1000);
    }
    konfetti() {
      const farben = ['#FF4D57', '#FFDD33', '#4FD36E', '#4C7DFF', '#FF9ECF', '#19C6D4', '#FF8A1F', '#8B6BFF'];
      for (let i = 0; i < 46; i++) {
        const c = el('div', 'konfetti');
        c.style.left = (this.g.cx + (Math.random() - 0.5) * 200) + 'px';
        c.style.top = (this.g.cy - 40) + 'px';
        c.style.background = farben[i % farben.length];
        c.style.setProperty('--dx', ((Math.random() - 0.5) * 1400).toFixed(0) + 'px');
        c.style.setProperty('--dy', (-200 - Math.random() * 300).toFixed(0) + 'px');
        c.style.setProperty('--r', ((Math.random() - 0.5) * 1080).toFixed(0) + 'deg');
        c.style.animationDelay = (Math.random() * 120).toFixed(0) + 'ms';
        this.flug.appendChild(c);
        setTimeout(() => c.remove(), 1900);
      }
    }
    // Flip-Welle: alle Karten drehen sich (links → rechts versetzt)
    wende(richtung) {
      const karten = this.buehne.querySelectorAll('.karte:not(.flug-karte)');
      const rb = this.root.getBoundingClientRect();
      karten.forEach(k => {
        const r = k.getBoundingClientRect();
        const d = Math.max(0, Math.min(1, (r.left + r.width / 2 - rb.left) / Math.max(1, rb.width))) * 320;
        k.style.setProperty('--d', d.toFixed(0) + 'ms');
        k.classList.remove('wende-aus', 'wende-ein');
        k.classList.add(richtung === 'aus' ? 'wende-aus' : 'wende-ein');
      });
    }
    wendeEnde() { this.buehne.querySelectorAll('.wende-aus,.wende-ein').forEach(k => k.classList.remove('wende-aus', 'wende-ein')); }
    name(seat) { const p = this.v && (this.v.players || []).find(x => x.seat === seat); return p ? p.name : ('Platz ' + (seat + 1)); }
  }

  /* ---------- Tischregie: Ereignisse nacheinander abspielen, dann mit der Sicht abgleichen ---------- */
  class Regie {
    constructor(t) { this.t = t; this.schlange = []; this.laeuft = false; this.beiLeer = []; }
    neu(events, view) {
      this.schlange.push({ events: events || [], view });
      if (!this.laeuft) this._lauf();
    }
    get leer() { return !this.laeuft && !this.schlange.length; }
    bisLeer() { return this.leer ? Promise.resolve() : new Promise(r => this.beiLeer.push(r)); }
    async _lauf() {
      this.laeuft = true;
      while (this.schlange.length) {
        const { events, view } = this.schlange.shift();
        const tempo = (this.schlange.length ? 0.35 : 1) * (this.t.app.effekteReduziert() ? 0.6 : 1) / TEMPO;
        for (const e of events) {
          if (!this.t.v) break;
          try { await this._spiele(e, view, tempo); } catch (err) { if (M.meldeFehler) M.meldeFehler('Regie ' + (e && e.e) + ': ' + err); }
        }
        try { this.t.zeige(view); } catch (err) { if (M.meldeFehler) M.meldeFehler('zeige: ' + (err && err.stack || err)); }
        if (this.t.app.nachZeigen) this.t.app.nachZeigen(view);
      }
      this.laeuft = false;
      this.beiLeer.splice(0).forEach(r => r());
    }
    async _spiele(e, view, tempo) {
      const t = this.t, ich = t.v.seat;
      const d = ms => Math.round(ms * tempo);
      const reduziert = t.app.effekteReduziert();
      switch (e.e) {
        case 'deal': {
          M.Ton.spiele('mischen');
          const plaetze = (view.players || []).map(p => p.seat);
          const back = t.v.draw_back || 'rueckseite';
          const fluege = [];
          plaetze.forEach((s, i) => {
            fluege.push(schlaf(d(i * 70)).then(() => t.fliege(back, { x: t.g.stapel.x, y: t.g.stapel.y, w: 118 }, Object.assign({ rot: kartenRot(i * 7) }, t.platzPos(s)), d(380), { ausblenden: true })));
          });
          await Promise.all(fluege);
          break;
        }
        case 'play': {
          M.Ton.spiele('karte');
          const face = e.face || 'rueckseite';
          const ziel = { x: t.g.ablage.x, y: t.g.ablage.y, w: 124, rot: kartenRot(e.card) * 0.4 };
          let von;
          if (e.seat === ich) {
            const p = t.hand.position(e.card);
            const he = t.hand.element(e.card);
            von = p ? { x: p.x, y: p.y, w: p.w, rot: p.rot } : { x: t.g.cx, y: t.H - 100, w: 190 };
            if (he) he.style.visibility = 'hidden';
          } else von = Object.assign({ rot: -8 }, t.platzPos(e.seat));
          await t.fliege(face, von, ziel, d(340));
          // Ablage sofort aktualisieren, damit folgende Ereignisse darauf aufbauen
          t._zeigeAblage(Object.assign({}, t.v, { top: { id: e.card, face } }), t.v);
          break;
        }
        case 'draw': {
          M.Ton.spiele('ziehen');
          const n = Math.min(e.count | 0 || 1, 6);
          const back = t.v.draw_back || 'rueckseite';
          const ziel = t.platzPos(e.seat);
          const fluege = [];
          for (let i = 0; i < n; i++) {
            const face = (e.seat === ich && e.faces && e.faces[i]) ? e.faces[i] : back;
            fluege.push(schlaf(d(i * 90)).then(() => t.fliege(face, { x: t.g.stapel.x, y: t.g.stapel.y, w: 118 }, Object.assign({ rot: kartenRot(i * 13) * 0.5 }, ziel), d(360), { ausblenden: e.seat !== ich })));
          }
          if ((e.count | 0) > 1) t.abzeichen(e.seat, '+' + e.count, 'zieh', d(1100));
          await Promise.all(fluege);
          break;
        }
        case 'skip':
          t.abzeichen(e.seat, K().iconSVG('schlaf', { main: '#FFF7E8', cut: '#211B2C' }) + '<span>Aussetzen</span>', 'aussetzen', d(1000));
          await schlaf(d(650));
          break;
        case 'skip_all':
          t.banner('Alle aussetzen!', t.name(e.seat) + ' ist gleich noch mal dran', 'aussetzen', d(1200));
          await schlaf(d(800));
          break;
        case 'reverse':
          t.ring.classList.remove('dreh'); void t.ring.offsetWidth; t.ring.classList.add('dreh');
          setTimeout(() => t.ring.classList.toggle('gegen', e.dir === -1), d(300));
          t.banner('Richtungswechsel', '', 'klein', d(1000));
          await schlaf(d(700));
          break;
        case 'color': {
          const fi = K().FARB_INFO[e.color];
          if (!reduziert) t.welle(e.color);
          t._zeigeFarbe({ color: e.color });
          if (fi) t.banner(fi.name, 'neue Farbe', 'farbe', d(1000));
          await schlaf(d(650));
          break;
        }
        case 'flip':
          M.Ton.spiele('flip');
          if (!reduziert) {
            t.wende('aus');
            t.root.dataset.seite = e.side;
            await schlaf(d(560));
            t.zeige(view, true);
            t.wende('ein');
            await schlaf(d(620));
            t.wendeEnde();
          } else { t.root.dataset.seite = e.side; t.zeige(view, true); }
          t.banner(e.side === 'dunkel' ? 'Nacht!' : 'Tag!', 'Alles gewendet', 'flip', d(1100));
          await schlaf(d(600));
          break;
        case 'pending':
          t.offenEl.hidden = false; t.offenEl.textContent = offenText(e) || ('+' + (e.amount | 0));
          t.offenEl.classList.remove('puls'); void t.offenEl.offsetWidth; t.offenEl.classList.add('puls');
          await schlaf(d(500));
          break;
        case 'challenge':
          t.banner(e.success ? 'Bluff erwischt!' : 'Kein Bluff!', t.name(e.seat) + (e.success ? ' hat richtig gezweifelt' : ' hat sich geirrt'), e.success ? 'gut' : 'warn', d(1500));
          await schlaf(d(1100));
          break;
        case 'mau':      // auf allen Geräten: Aufnahme „Mao“ (außer Ton aus) und Sprechblase beim Rufenden
          if (t.app.mauTon) t.app.mauTon(e.seat, 'mau');
          t.mauBlase(e.seat, 'mau', blasenDauer(1700, d));
          await schlaf(d(450));
          break;
        case 'catch':
          t.banner('Erwischt!', t.name(e.target) + ' hat „Mau!“ vergessen', 'warn', d(1400));
          await schlaf(d(900));
          break;
        case 'penalty':
          t.abzeichen(e.seat, '+' + e.count + ' Strafe', 'strafe', d(1200));
          await schlaf(d(500));
          break;
        case 'shuffle':
          M.Ton.spiele('mischen');
          t.stapel.classList.remove('mischen'); void t.stapel.offsetWidth; t.stapel.classList.add('mischen');
          t.banner('Neu gemischt', '', 'klein', d(900));
          await schlaf(d(700));
          break;
        case 'round_over': {
          const r = Array.isArray(e.ranking) ? e.ranking : [];
          const erster = r.length ? (typeof r[0] === 'object' ? r[0].seat : r[0]) : -1;
          if (erster === ich) { M.Ton.spiele('sieg'); if (!reduziert) t.konfetti(); }
          t.banner(erster === ich ? 'Mau-Mau!' : 'Runde vorbei', erster >= 0 ? t.name(erster) + ' ist fertig' : '', 'gross', d(1500));
          await schlaf(d(1300));
          break;
        }
        case 'game_over':
          t.banner('Partie vorbei', typeof e.winner === 'number' && e.winner >= 0 ? (e.winner === ich ? 'Du gewinnst!' : t.name(e.winner) + ' gewinnt') : '', 'gross', d(1500));
          await schlaf(d(1000));
          break;
        // zusätzliche Ereignisse des Regelwerks (docs/module/A.md)
        case 'finish':   // {seat, place}: fertig → „Mau-Mau!“ (Aufnahme „Mao-Mao“ und große Blase); bei „bis zum Letzten“ mit Platz
          if (t.app.mauTon) t.app.mauTon(e.seat, 'mau_mau');
          t.mauBlase(e.seat, 'mau_mau', blasenDauer(2300, d));
          if (t.v.rules && t.v.rules.round_end === 'last') t.abzeichen(e.seat, (e.place | 0) + '. Platz', 'platz', d(1500));
          await schlaf(d(700));
          break;
        case 'pass':     // {seat}: beide Stapel leer, Ziehen entfällt
          t.abzeichen(e.seat, 'Nichts zu ziehen', 'aussetzen', d(1100));
          await schlaf(d(500));
          break;
        case 'choose_color':   // {seat}: nach einem Flip liegt ein Joker oben, dieser Platz wählt die Farbe
          if (e.seat !== ich) t.banner('Farbwahl', t.name(e.seat) + ' wählt die Farbe', 'klein', d(1000));
          await schlaf(d(300));
          break;
        // round_start, start (Startkarte), turn, keep, accept: nur Zustand, kein eigener Effekt
        default: break;
      }
    }
  }

  M.Tisch = { Tisch, Regie };
})(window.MMF = window.MMF || {});
