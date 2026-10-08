/* Mau-Mau Flip – Browser-Client „Lite“: der Tisch im Querformat und die Tischregie.
 * Die Bühne hat Logik-Pixel wie der Entwurf (Höhe 720, Breite je nach Gerät) und wird per CSS skaliert.
 * zeige(view) gleicht alles mit der Sicht des Gastgebers ab; Regie spielt vorher die Ereignisse als kurze
 * CSS-Animationen ab (Karte fliegt, Ziehen, Farbwelle, Flip als Tag→Nacht-Übergang, Mau-Blase, Abzeichen).
 */
(function (M) {
  'use strict';

  const K = () => M.Karten;
  const H0 = 720, W_MIN = 1180;
  const ZEILE = 46;          // Zeilenhöhe im Zahlenwerk des Glücksspiel-Automaten (style.css .walze b)
  const WECHSEL_MS = 1100;   // Tag/Nacht-Wechsel beim Flip, gleich style.css #tisch --wd
  const AVA_FARBEN = ['#FF9ECF', '#43B05C', '#FFDD33', '#4C7DFF', '#FF8A1F', '#19C6D4', '#8B6BFF', '#FF4D57', '#B0E06A', '#F4EADA'];
  const schlaf = ms => new Promise(r => setTimeout(r, ms));
  const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  function el(tag, cls, html) { const e = document.createElement(tag); if (cls) e.className = cls; if (html !== undefined) e.innerHTML = html; return e; }
  function kartenRot(id) { return ((Math.abs(id | 0) * 37) % 23) - 11; }

  // Richtungs-Plattform wie in der App (game/scripts/ui/direction_ring.gd, Variante B „breit“), vereinfacht: dicker Ring
  // schräg von oben (Superellipse als Loch, Perspektive vorn größer), Ober- und Unterkante als zwei versetzte Kurven, weicher
  // Schatten, Laufbahn mit Winkeln. Die Winkel stehen fest (HTML, eigene Ebenen) und zeigen den Fluss als Lauflicht
  // (Deckkraft je Winkel versetzt, wie wandernde Dreiergruppen); .gegen kehrt Lauf und Spitzen um, .dreh glimmt einmal auf.
  // Ursprung = Tischmitte; nur bei neuer Bühnenbreite neu berechnet.
  const PL = { lochX: 372, lochY: 136, minX: 326, band: 66, kante: 16, zelle: 38, kipp: 0.70, persp: 0.11, eck: 2.5, dy: 6, seg: 128, gruppe: 5, fluss: 34 };
  function plattform(W) {
    const fx = Math.min(330, W * 0.21) / 330;
    const ai = Math.max(PL.lochX * fx, PL.minX), bi = PL.lochY / PL.kipp;
    const band = PL.band * Math.min(fx, 1), wall = PL.kante, zref = bi + band, n = PL.seg;
    const proj = (x, z, drop) => { const s = 1 / (1 - PL.persp * z / zref); return [x * s, (PL.kipp * z + drop) * s]; };
    const yoff = PL.dy - (proj(0, bi, 0)[1] + proj(0, -bi, 0)[1]) / 2;
    const innen = [], nrm = [];
    for (let i = 0; i <= n; i++) {
      const t = 2 * Math.PI * i / n, c = Math.cos(t), s = Math.sin(t);
      const q = [ai * Math.sign(c) * Math.pow(Math.abs(c), 2 / PL.eck), bi * Math.sign(s) * Math.pow(Math.abs(s), 2 / PL.eck)];
      const g = [Math.sign(q[0]) * Math.pow(Math.abs(q[0]) / ai, PL.eck - 1) / ai, Math.sign(q[1]) * Math.pow(Math.abs(q[1]) / bi, PL.eck - 1) / bi];
      const l = Math.hypot(g[0], g[1]) || 1;
      innen.push(q); nrm.push([g[0] / l, g[1] / l]);
    }
    const welt = (i, off) => [innen[i][0] + nrm[i][0] * off, innen[i][1] + nrm[i][1] * off];
    const bild = (p, drop) => { const r = proj(p[0], p[1], drop); return [r[0], r[1] + yoff]; };
    const f1 = v => (Math.round(v * 10) / 10).toString();
    const kurve = (off, drop, dx, dy) => {
      let d = '';
      for (let i = 0; i < n; i++) { const p = bild(welt(i, off), drop); d += (i ? 'L' : 'M') + f1(p[0] + (dx || 0)) + ' ' + f1(p[1] + (dy || 0)); }
      return d + 'Z';
    };
    // Der weiche Schatten (feGaussianBlur) liegt in einem eigenen SVG mit fester Farbe: Beim Flip blendet nur dessen Deckkraft
    // als eigene Ebene über (Compositor), der teure Weichzeichner wird nicht jedes Bild neu gerechnet.
    let h = '<svg class="pf pf-sch" viewBox="-480 -290 960 580" aria-hidden="true"><defs>' +
      '<filter id="pf-weich" x="-15%" y="-25%" width="130%" height="150%"><feGaussianBlur stdDeviation="9"/></filter></defs>' +
      '<path class="pf-schatten" fill-rule="evenodd" filter="url(#pf-weich)" d="' + kurve(band + 6, wall, 7, 9) + kurve(-4, wall, 7, 9) + '"/></svg>' +
      '<svg class="pf" viewBox="-480 -290 960 580" aria-hidden="true"><defs>' +
      '<linearGradient id="pf-glas" x1="0" y1="0" x2="0" y2="1"><stop offset="0" class="s1"/><stop offset="1" class="s2"/></linearGradient>' +
      '<linearGradient id="pf-wand" x1="0" y1="0" x2="0" y2="1"><stop offset=".55" class="s3"/><stop offset="1" class="s4"/></linearGradient></defs>' +
      '<path class="pf-kante" fill-rule="evenodd" d="' + kurve(band, wall) + kurve(band, 0) + '"/>' +
      '<path class="pf-fuss" d="' + kurve(band, wall - 1.2) + '"/>' +
      '<path class="pf-kante-innen" fill-rule="evenodd" d="' + kurve(0, 0) + kurve(0, wall) + '"/>' +
      '<path class="pf-oben" fill-rule="evenodd" d="' + kurve(band, 0) + kurve(0, 0) + '"/>' +
      '<path class="pf-bahn" fill-rule="evenodd" d="' + kurve(band * 0.8, 0) + kurve(band * 0.2, 0) + '"/>' +
      '<path class="pf-glanz" d="' + kurve(band - 2, 0) + '"/>' +
      '<path class="pf-rand" d="' + kurve(band - 1.4, 0) + '"/>' +
      '<path class="pf-rand-innen" d="' + kurve(1.2, 0) + '"/></svg>';
    // Winkel auf der Bandmitte: ganze Zahl von Gruppen, je Winkel eine Matrix (längs, quer) mit der örtlichen Verkürzung
    const lauf = [0];
    for (let i = 1; i <= n; i++) {
      const a = welt(i, band / 2), b = welt(i - 1, band / 2);
      lauf.push(lauf[i - 1] + Math.hypot(a[0] - b[0], a[1] - b[1]));
    }
    const gesamt = lauf[n], zahl = Math.max(PL.gruppe, Math.round(gesamt / (PL.zelle * PL.gruppe)) * PL.gruppe), zl = gesamt / zahl;
    const periode = PL.gruppe * zl / PL.fluss, takt = periode / PL.gruppe;
    const VOR = [1, 0, 0, 0.45, 0.72], RUECK = [1, 0.72, 0.45, 0, 0], sek = v => (Math.round(v * 100) / 100) + 's';
    let j = 1;
    for (let k = 0; k < zahl; k++) {
      const ziel = (k + 0.5) * zl;
      while (j < n && lauf[j] < ziel) j++;
      const u = (ziel - lauf[j - 1]) / Math.max(lauf[j] - lauf[j - 1], 1e-6);
      const a = welt(j - 1, band / 2), b = welt(j, band / 2);
      const p = [a[0] + (b[0] - a[0]) * u, a[1] + (b[1] - a[1]) * u];
      const tl = Math.hypot(b[0] - a[0], b[1] - a[1]) || 1, tw = [(b[0] - a[0]) / tl, (b[1] - a[1]) / tl], nw = [tw[1], -tw[0]];
      const s0 = bild(p, 0), st = bild([p[0] + tw[0], p[1] + tw[1]], 0), sn = bild([p[0] + nw[0], p[1] + nw[1]], 0);
      const m = [st[0] - s0[0], st[1] - s0[1], sn[0] - s0[0], sn[1] - s0[1], s0[0], s0[1]].map(v => (Math.round(v * 1000) / 1000));
      const g = k % PL.gruppe;
      h += '<i class="w" style="transform:matrix(' + m.join(',') + ');--d:' + sek((g - PL.gruppe) * takt) + ';--r:' +
        sek((((PL.gruppe - g) % PL.gruppe) - PL.gruppe) * takt) + ';--o:' + VOR[g] + ';--or:' + RUECK[g] + ';--p:' + sek(periode) + '"><b></b></i>';
    }
    return h;
  }
  // „1 Karte“ / „5 Karten“ (Mehrzahl je Sprache)
  const kt = n => (n === 1 ? M.t('1 Karte') : M.t('%d Karten', n));
  function offenText(p) {
    if (!p || !p.kind) return p && p.amount ? '+' + p.amount : '';
    if (p.kind === 'farbjagd') return M.t('Jagd!');
    return p.amount ? '+' + p.amount : '';
  }
  // Testhilfe: ?tempo=N beschleunigt die Tischregie (nur für Prüfläufe)
  const TEMPO = Math.max(0.2, Math.min(8, +((M.param && M.param('tempo')) || new URLSearchParams(location.search).get('tempo') || 1) || 1));
  // Standzeit der Mau-Blase: folgt dem Regie-Tempo, bleibt aber lesbar (mind. 0,9 s); ?blase=ms setzt sie fest (Kontrollbilder)
  function blasenDauer(ms, d) { return BLASE_PARAM > 0 ? BLASE_PARAM : Math.max(900, d(ms)); }

  // Kreispfeil über der großen Liste (wie ListHeader in der App): im Uhrzeigersinn gezeichnet, .gegen spiegelt ihn (style.css)
  const PFEIL_REIHE = '<svg class="dreh" viewBox="-50 -50 100 100" aria-hidden="true"><g class="halo"><path d="M17 -29.44A34 34 0 1 1 -32.3 -10.6"/><polygon points="-8.71,-39.37 -43.86,-29.56 -18.52,-4.22"/></g><g class="pf"><path d="M17 -29.44A34 34 0 1 1 -32.3 -10.6"/><polygon points="-8.71,-39.37 -43.86,-29.56 -18.52,-4.22"/></g></svg>';
  const ICON_SORT = '<svg viewBox="0 0 26 26" aria-hidden="true"><path d="M7 4v17M7 21l-4-4M7 21l4-4M19 22V5M19 5l-4 4M19 5l4 4" stroke="currentColor" stroke-width="2.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  const ICON_RUECK = '<svg viewBox="0 0 26 26" aria-hidden="true"><rect x="4" y="3" width="13" height="19" rx="3" fill="none" stroke="currentColor" stroke-width="2.4"/><rect x="10" y="6" width="13" height="18" rx="3" fill="#0A0D20" stroke="#FF7FCF" stroke-width="2.4"/></svg>';
  const ICON_MENUE = '<svg viewBox="0 0 26 26" aria-hidden="true"><path d="M5 8h16M5 13h16M5 18h16" stroke="currentColor" stroke-width="2.6" stroke-linecap="round"/></svg>';
  const ICON_TON = '<svg viewBox="0 0 26 26" aria-hidden="true"><path d="M4 10h4l6-5v16l-6-5H4z" fill="currentColor" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round"/><path class="an" d="M17.5 9.5a5 5 0 0 1 0 7M20.5 6.5a9.5 9.5 0 0 1 0 13" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"/><path class="aus" d="M17 9.5l7 7M24 9.5l-7 7" fill="none" stroke="#FF6B6B" stroke-width="2.6" stroke-linecap="round"/></svg>';
  // Mau-Sprechblase: Animationsvarianten (zufällig je Ruf), „schlicht“ bei reduzierten Effekten bzw. prefers-reduced-motion
  const BLASEN = ['plopp', 'ohren', 'huepf', 'ballon', 'gummi'];
  const SEITE_DX = 200;   // Seitenstapel beim Durchsehen der Ablage: Abstand rechts neben der Ablage (Bühnenpixel)
  const BLASE_PARAM = +((M.param && M.param('blase')) || new URLSearchParams(location.search).get('blase') || 0);   // Testhilfe: feste Dauer in ms
  const STERNE = [[-8, 18, -26, -18], [104, 10, 28, -22], [92, 96, 30, 20], [-6, 88, -28, 18], [48, -18, 0, -30], [30, 108, -6, 26]];   // x %, y %, Drift x/y px
  const ICON_GETRENNT ='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 9a13 13 0 0 1 18 0M6.5 12.5a8 8 0 0 1 11 0M10 16a3 3 0 0 1 4 0" stroke="currentColor" stroke-width="2.2" fill="none" stroke-linecap="round"/><path d="M4 4l16 16" stroke="#FF6B6B" stroke-width="2.4" stroke-linecap="round"/></svg>';

  class Tisch {
    // app: Rückrufe {spielen(id), antippen(id), ziehen(), aktion(a), mau(), sortieren(), rueckseiten(), menue(), hilfe(face), gegnerAnsicht(seat), sortModus()}
    constructor(root, app) {
      this.root = root; this.app = app;
      this.s = 1; this.W = 1600; this.H = H0; this.ox = 0; this.oy = 0;
      this.gross = false; this.handF = 1;   // großer Modus (persönliche Einstellung grosser_modus): setzeGross()
      this.v = null;
      this.ablageVerlauf = [];   // [{id, face}] die letzten Karten der Ablage (für den kleinen Stapel)
      this.gegnerEls = new Map();
      this.regie = new Regie(this);
      this._baue();
    }

    _baue() {
      const r = this.root;
      // Himmel: Tagebene (Papier, Sonne oben links), Nachtebene (Sterne) und Dämmerung, die nur beim Flip kurz aufscheint
      this.himmel = el('div', 'himmel', '<div class="tag"><i class="strahlen"></i><i class="sonne"></i></div><div class="nacht"><div class="sterne"></div><i class="mond"></i></div><div class="daemmerung"></div>');
      r.appendChild(this.himmel);
      const b = this.buehne = el('div', 'buehne');
      b.id = 'buehne';
      r.appendChild(b);
      this.ring = el('div', 'richtung');   // Richtungs-Plattform, Inhalt aus plattform() in _geometrie (hängt von der Bühnenbreite ab)
      b.appendChild(this.ring);
      this.gegnerBox = el('div', 'gegner-box'); b.appendChild(this.gegnerBox);
      this.listeKopf = el('div', 'liste-kopf', PFEIL_REIHE + '<span>Reihenfolge</span>'); this.listeKopf.id = 'liste-kopf'; b.appendChild(this.listeKopf);
      this.stapel = el('div', 'stapel'); b.appendChild(this.stapel);
      this.stapel.innerHTML = '<div class="leer"></div>';
      this.stapelUnter = [K().element('rueckseite', 118, 'unter u2'), K().element('rueckseite', 118, 'unter u1')];
      this.stapelOben = K().element('rueckseite', 118, 'oben');
      this.stapelUnter.forEach(e => this.stapel.appendChild(e));
      this.stapel.appendChild(this.stapelOben);
      this.stapelZahl = el('div', 'stapelzahl'); b.appendChild(this.stapelZahl);
      this.farbe = el('div', 'farbanzeige'); b.appendChild(this.farbe);
      this.ablage = el('div', 'ablage', '<div class="farbring"></div><div class="karten"></div>');
      b.appendChild(this.ablage);
      this.farbring = this.ablage.querySelector('.farbring');
      this.ablageKarten = this.ablage.querySelector('.karten');
      // Strafplakette (offene Ziehstrafe) als eigene Ebene auf der Bühne: liegt über Ablage, Seitenstapel und Farbe
      this.offenEl = el('div', 'offen'); this.offenEl.hidden = true;
      // Ablage durchsehen (view.discard_log): Tipp auf die Ablage schiebt die oberste Karte auf den Seitenstapel daneben
      this.seiten = el('div', 'seitenstapel', '<div class="zaehler"></div><div class="karten"></div><div class="info"><b class="von"></b><span class="wunsch"></span></div>');
      this.seiten.id = 'seitenstapel'; this.seiten.hidden = true;
      b.appendChild(this.seiten);
      b.appendChild(this.offenEl);
      this.seitenKarten = this.seiten.querySelector('.karten');
      this.durch = 0; this._durchSig = '';
      this.leiste = el('div', 'leiste', '<div class="hinweis"></div><div class="aktionen"></div>');
      b.appendChild(this.leiste);
      this.hinweis = this.leiste.firstChild; this.aktionen = this.leiste.lastChild;
      // Eigener Platz: Strahlen hinter der Hand, wenn ich dran bin, und die eigene Kartenzahl (wie bei den Mitspielern)
      this.ichKranz = el('div', 'ich-kranz'); b.insertBefore(this.ichKranz, this.gegnerBox);
      this.ichZahl = el('div', 'ich-zahl', '<span class="name" data-t>Du</span><span class="zahl"></span>'); this.ichZahl.id = 'ich-zahl';
      b.appendChild(this.ichZahl);
      this.hand = new M.Hand.Hand(this, {
        antippen: id => this.app.antippen(id), spielen: id => this.app.spielen(id), hilfe: f => this.app.hilfe(f), leer: () => this.app.antippen(null),
      });
      b.appendChild(this.hand.zone); b.appendChild(this.hand.el);
      this.knSort = el('button', 'pill sortieren', ICON_SORT + '<span>Farbe</span>'); b.appendChild(this.knSort);
      this.knRueck = el('button', 'pill rueckseiten', ICON_RUECK + '<span data-t>Rückseiten</span>'); b.appendChild(this.knRueck);
      this.knMau = el('button', 'mau-knopf', '<span>Mau!</span>'); b.appendChild(this.knMau);
      this.knMenue = el('button', 'rund menue-knopf', ICON_MENUE); this.knMenue.setAttribute('aria-label', 'Menü'); this.knMenue.setAttribute('data-t-aria', 'Menü'); b.appendChild(this.knMenue);
      this.knTon = el('button', 'rund ton-knopf', ICON_TON); this.knTon.id = 'ton-knopf'; b.appendChild(this.knTon);
      this.zeigeTon();
      // Glücksspiel (Hausregel gamble_cards): Automat in der Tischmitte (Kuppelknopf wie auf der Karte, Zahlenwerk 0–10) und der
      // verdeckte Einsatzstapel mit Zähler am Platz des Glücksspielers. Beides nur während der Phase „gamble“.
      this.automat = el('div', 'automat',
        '<div class="schild" data-t>Glücksspiel</div>' +
        '<button class="kuppel" type="button" aria-label="Glücksspielknopf drücken" data-t-aria="Glücksspielknopf drücken"><span class="frage" data-t>Los!</span></button>' +
        '<div class="sockel"><i class="lampe l1"></i><i class="lampe l2"></i><div class="fenster"><div class="walze"><b>?</b></div></div><i class="lampe l3"></i><i class="lampe l4"></i></div>' +
        '<div class="unter"></div>' +
        '<button class="knopf klein aufhoeren" type="button" hidden data-t>Aufhören</button>');
      this.automat.hidden = true; this.automat.id = 'automat';
      b.appendChild(this.automat);
      this.kuppel = this.automat.querySelector('.kuppel'); this.kuppel.id = 'gluecksknopf';
      this.walze = this.automat.querySelector('.walze');
      this.automatUnter = this.automat.querySelector('.unter');
      this.knStop = this.automat.querySelector('.aufhoeren'); this.knStop.id = 'aufhoeren';
      this.einsatz = el('div', 'einsatz', '<div class="stapelchen"></div><b class="zahl"></b><span class="was" data-t>Einsatz</span>');
      this.einsatz.hidden = true; this.einsatz.id = 'einsatz';
      b.appendChild(this.einsatz);
      this.flug = el('div', 'flug'); b.appendChild(this.flug);
      this.farbwahl = el('div', 'farbwahl'); this.farbwahl.hidden = true; b.appendChild(this.farbwahl);
      this.knSort.id = 'sortieren'; this.knRueck.id = 'rueckseiten'; this.knMau.id = 'mau'; this.stapel.id = 'stapel'; this.ablage.id = 'ablage';
      M.I18n.anwenden(this.root);   // data-t im Tisch (Beta 1.2.2); beim Sprachwechsel neu
      M.I18n.beiWechsel(() => { M.I18n.anwenden(this.root); this.zeigeTon(); });

      const tipp = (e, f) => { e.addEventListener('click', ev => { ev.preventDefault(); f(ev); }); };
      tipp(this.knSort, () => this.app.sortieren());
      tipp(this.knRueck, () => this.app.rueckseiten());
      tipp(this.knMau, () => this.app.mau());
      tipp(this.knMenue, () => this.app.menue());
      tipp(this.knTon, () => this.app.tonSchalter());
      tipp(this.stapel, () => this.app.ziehen());
      tipp(this.kuppel, () => this.app.druecken());
      tipp(this.knStop, () => this.app.aufhoeren());
      tipp(this.ablage, () => this.durchsehen(1));
      tipp(this.seiten, () => this.durchsehen(-1));
      // Tipp irgendwo sonst schiebt alle Karten zurück (der Tipp selbst wirkt normal weiter)
      this.root.addEventListener('pointerdown', ev => { if (this.durch && !ev.target.closest('#ablage, #seitenstapel')) this.durchsehen(0); }, true);
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
        else if (!this.v || +g.dataset.seat !== this.v.seat) this.app.gegnerAnsicht(+g.dataset.seat);   // eigene Zeile (großer Modus): nichts
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
      this.root.style.setProperty('--s', s.toFixed(4));   // Bühnenmaßstab für den Himmel (Sonne in Logik-Pixeln)
      this._geometrie();
      if (this.v) this.zeige(this.v, true);
    }
    zuBuehne(cx, cy) {
      const r = this.root.getBoundingClientRect();
      return { x: (cx - r.left - this.ox) / this.s, y: (cy - r.top - this.oy) / this.s };
    }
    // Großer Modus an/aus (persönliche Einstellung je Gerät): #tisch.gross, Hand um handF vergrößert, eigene Geometrie
    setzeGross(an) {
      an = !!an;
      if (an === this.gross) return;
      this.gross = an; this.handF = an ? 1.3 : 1;
      this.root.classList.toggle('gross', an);
      for (const g of this.gegnerEls.values()) { g.sig = ''; g.k = undefined; g.e.style.transform = ''; }
      this._geometrie();
      if (this.v) this.zeige(this.v, true);
    }
    _geometrie() {
      if (this.gross) return this._geometrieGross();
      const W = this.W, H = this.H;
      const cx = W / 2, cy = Math.round(H * 0.446);
      this.g = { cx, cy, stapel: { x: cx - 177, y: cy }, ablage: { x: cx + 177, y: cy }, sw: 118, aw: 124 };
      const setz = (e, x, y) => { e.style.left = x + 'px'; e.style.top = y + 'px'; };
      this.root.style.removeProperty('--gk');
      this.root.classList.remove('farbe-mitte');
      setz(this.ring, cx, cy);
      const pw = Math.round(Math.min(330, W * 0.21));
      if (this.ring.dataset.w !== String(pw)) { this.ring.innerHTML = plattform(W); this.ring.dataset.w = String(pw); }
      setz(this.stapel, cx - 177, cy);
      setz(this.stapelZahl, cx - 177, cy + 106);
      setz(this.farbe, cx, cy);
      setz(this.ablage, cx + 177, cy);
      setz(this.seiten, cx + 177 + SEITE_DX, cy);
      setz(this.offenEl, cx + 177 + 50, cy - 128);
      setz(this.leiste, cx, H - 212);
      setz(this.farbwahl, cx + 177, cy);
      setz(this.automat, cx - 2, cy + 10);
      this.g.einsatz = { x: cx - 335, y: H - 250 };   // eigener Einsatzstapel: über der Hand links neben dem Hinweis (nicht bei den Mitspielern)
      this.knSort.style.top = (H - 160) + 'px';
      this.knRueck.style.top = (H - 88) + 'px';
      this.ichZahl.style.top = (H - 222) + 'px';
      setz(this.ichKranz, cx, H);
    }
    // Großer Modus: links riesig Stapel und Ablage nebeneinander (Hand darf die untere Hälfte überdecken), daneben die Farbe groß,
    // rechts die Spielerliste (wer dran ist, oben). Stapel und Ablage werden per --gk vergrößert (style.css #tisch.gross).
    // Liste wie in der App (big_layout.gd list_rect, 1.1.2) etwa 36 % der Breite; die Stapel bekommen, was zwischen Menü-Knopf,
    // Farbspalte und Liste bleibt. Der Abstand rechnet die Überstände mit ein: unterste Stapelkarten (8 px versetzt, −3°) und die
    // älteren Ablagekarten (bis 24 px nach links versetzt, bis ±11° gedreht), sonst läge die Ablage auf dem Stapel.
    // 1.2.1: Die Unterkante der Stapel bleibt über der Hinweisleiste (Ecken lesbar, „Du bist dran“ liegt nicht darauf). In
    // schmalen Fenstern (z. B. Desktop 1280×800, 1600×900) rückt die Farbe zwischen Stapel und Ablage (#tisch.farbe-mitte),
    // damit die Stapel die Höhe nutzen, statt klein oben in der Ecke zu liegen.
    _geometrieGross() {
      const W = this.W, H = this.H, rand = 18, links = 130, FARBE_MIN = 200, FARBE_SPALT = 150;
      const LW = Math.round(Math.max(440, Math.min(620, W * 0.365)));
      const lx0 = W - rand - LW;
      const VH = K().VERHAELTNIS;
      const leisteY = H - 258, leisteOben = leisteY - 46;   // Hinweisleiste (auch bei Schrift „Sehr groß“ höchstens etwa 92 hoch)
      const kwHoch = Math.min(360, (leisteOben - 12 - 18) / VH);
      // 2·kw + Spalt(30 + 54·gk) + Ablage-Mehrbreite (6·gk) ≤ frei, gk = kw / 118
      const breit = frei => (frei - 30) / (2 + 60 / 118);
      const kwSpalte = breit(lx0 - 16 - links - FARBE_MIN);
      let kw = Math.min(kwHoch, kwSpalte), mitte = false;
      if (kwSpalte < kwHoch) {
        // Farbe im Spalt: der ist dann mindestens FARBE_SPALT breit, die Farbspalte entfällt
        const frei = lx0 - 16 - links;
        let kwM = Math.min(kwHoch, breit(frei));
        if (30 + 54 * kwM / 118 < FARBE_SPALT) kwM = Math.min(kwHoch, (frei - FARBE_SPALT) / (2 + 6 / 118));
        if (kwM > kw + 8) { kw = kwM; mitte = true; }
      }
      kw = Math.max(130, kw);
      const gk = kw / 118, aw = 124 * gk, kh = kw * VH, spalt = Math.max(mitte ? FARBE_SPALT : 0, 30 + 54 * gk);
      const cy = Math.round(18 + kh / 2), sx = links + kw / 2, ax = sx + kw / 2 + spalt + aw / 2;
      const mx = Math.round((links + lx0) / 2), cx = W / 2;
      this.g = { cx, cy, mx, stapel: { x: sx, y: cy }, ablage: { x: ax, y: cy }, sw: kw, aw };
      const setz = (e, x, y) => { e.style.left = x + 'px'; e.style.top = y + 'px'; };
      this.root.style.setProperty('--gk', gk.toFixed(3));
      this.root.style.setProperty('--lw', LW + 'px');
      this.root.classList.toggle('farbe-mitte', mitte);
      setz(this.stapel, sx, cy);
      setz(this.stapelZahl, sx, Math.round(cy + kh * 0.08));   // als Schild auf dem Stapel (unten liegt die Hand)
      if (mitte) setz(this.farbe, Math.round(sx + kw / 2 + spalt / 2), Math.round(cy - kh * 0.12));   // zwischen Stapel und Ablage
      else setz(this.farbe, Math.round((ax + aw / 2 + lx0) / 2), Math.round(cy - kh * 0.2));   // Mitte der Farbspalte
      setz(this.ablage, ax, cy);
      setz(this.seiten, ax + aw / 2 + 40, cy);
      setz(this.offenEl, Math.round(ax + aw * 0.04), Math.round(cy - kh / 2 + 14));   // oben rechts auf der Ablage (oben ist kein Platz, unten liegt die Hand)
      setz(this.leiste, mx, leisteY);
      setz(this.farbwahl, ax, cy);
      setz(this.automat, mx, cy + 10);
      this.g.einsatz = { x: Math.max(120, mx - 340), y: H - 300 };
      this.knSort.style.top = (H - 178) + 'px';
      this.knRueck.style.top = (H - 96) + 'px';
      setz(this.ichKranz, cx, H);
      // Spielerliste: Kopf „Reihenfolge“ links neben dem Ton-Knopf, Zeilen darunter bis über den Mau-Knopf. Zeilenhöhe und Zahl
      // der sichtbaren Zeilen richten sich nach der Zahl der Einträge (_listeZeilen, wie BigLayout.list_rows).
      const top = 124, unten = H - 244;
      this.g.liste = { x: lx0 + LW / 2, top, hoehe: Math.max(90, unten - top), zeile: 100, cap: 3, w: LW, n: 0 };
      setz(this.listeKopf, Math.round((lx0 + W - 34 - 84 - 10) / 2), 68);
      this._listeZeilen(this.v ? (this.v.players || []).length : 4);
    }
    // Zeilen der großen Liste für n Einträge: Abstand 86–124 Bühnenpixel, so viele, wie hineinpassen; --zh = Zeilenhöhe (style.css)
    _listeZeilen(n) {
      const L = this.g.liste;
      if (!L || L.n === n) return;
      const zeile = Math.max(86, Math.min(124, L.hoehe / Math.max(1, n)));
      L.n = n; L.zeile = zeile; L.cap = Math.max(2, Math.floor(L.hoehe / zeile + 0.01));
      this.root.style.setProperty('--zh', Math.round(zeile - 10) + 'px');
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

    /* ---------- Tag (helle Seite, Papier) und Nacht (dunkle Seite, Neon) ---------- */
    // Setzt #tisch[data-seite]; style.css blendet Himmel und Plattform über WECHSEL_MS weich über, Schrift, Knöpfe und
    // Markierungen wechseln auf halbem Weg (.wechselt), dazu scheint die Dämmerung auf (nicht bei reduzierten Effekten).
    // Ohne Überblenden (.sofort): beim ersten Bild und beim ersten Bild einer neuen Partie (sofort = true, zeige ohne alte Sicht).
    // Ein zweiter Wechsel, solange einer läuft, startet die Dämmerung nicht neu (sonst spränge sie); die Regie wartet vor einem
    // Flip ohnehin, bis der vorige fertig ist (wechselRest).
    setzeSeite(seite, sofort) {
      seite = seite === 'dunkel' ? 'dunkel' : 'hell';
      const r = this.root, h = this.himmel, alt = r.dataset.seite;
      if (!alt || sofort) {
        if (alt === seite && !r.classList.contains('wechselt')) return;
        clearTimeout(this._wechselTimer); clearTimeout(this._themaTimer);
        this._wechselBis = 0;
        r.classList.add('sofort');
        r.classList.remove('wechselt', 'halb'); h.classList.remove('wechsel');
        r.dataset.seite = seite; document.body.dataset.seite = seite;   // Fenster (Menü, Regeln, Hilfe …) folgen Tag/Nacht (style.css)
        void r.offsetWidth;
        requestAnimationFrame(() => requestAnimationFrame(() => r.classList.remove('sofort')));
        if (this.app.themaFarbe) this.app.themaFarbe();
        return;
      }
      if (alt === seite) return;
      const laeuft = this.wechselRest() > 0;
      r.classList.add('wechselt');   // Übergänge nur jetzt (style.css)
      r.classList.remove('halb');
      r.dataset.seite = seite; document.body.dataset.seite = seite;   // Fenster (Menü, Regeln, Hilfe …) folgen Tag/Nacht (style.css)
      if (!laeuft) {
        h.classList.remove('wechsel');
        if (!this.app.effekteReduziert()) { void h.offsetWidth; h.classList.add('wechsel'); }
      }
      this._wechselBis = performance.now() + WECHSEL_MS;
      clearTimeout(this._wechselTimer);
      this._wechselTimer = setTimeout(() => { h.classList.remove('wechsel'); r.classList.remove('wechselt', 'halb'); this._wechselBis = 0; }, WECHSEL_MS + 300);
      // Browserleiste wechselt mit der Schrift auf halbem Weg. Ab dort (.halb) wechseln Schrift und Markierungen ohne Übergang: Was
      // sich erst nach der Mitte ändert (z. B. .gg.dran mit dem Zwischenstand des Flips), steht sofort in der Farbe der neuen Seite,
      // statt mit einem neuen Übergang erst 0,55 s später umzuspringen.
      clearTimeout(this._themaTimer);
      this._themaTimer = setTimeout(() => { r.classList.add('halb'); if (this.app.themaFarbe) this.app.themaFarbe(); }, WECHSEL_MS / 2);
    }
    // Restzeit des laufenden Tag/Nacht-Wechsels in ms (0 = keiner)
    wechselRest() { return Math.max(0, (this._wechselBis || 0) - performance.now()); }
    // Farbe der Browserleiste passend zum Tisch (Papier am Tag, Nachtblau nachts)
    themaFarbe() { return this.root.dataset.seite === 'dunkel' ? '#0C0F22' : '#E6D7BC'; }

    /* ---------- Abgleich mit der Sicht ---------- */
    zeige(v, nurLayout) {
      const alt = this.v;
      this.v = v;
      const ich = v.seat;
      // Erstes Bild (auch einer neuen Partie) und neue Runde ohne Überblenden. Reine Layout-Aufrufe (Größe, Bilder, Einstellungen)
      // ändern die Seite nicht: Beim Flip setzt die Regie sie selbst, die angezeigte Sicht trägt dann noch die alte Seite.
      if (!alt || !nurLayout) this.setzeSeite(v.side, !alt || (typeof v.round === 'number' && typeof alt.round === 'number' && v.round !== alt.round));
      this._zeigeGegner(v);
      this._zeigeStapel(v);
      this._zeigeAblage(v, alt);
      this._zeigeFarbe(v);
      this.ring.classList.toggle('gegen', v.dir === -1);
      const h = v.hints || {};
      const spielbar = h.playable || [];
      // Phasen des Gastgebers (MauGame): turn, drawn, challenge, color, gamble, round_over, game_over (idle nur vor dem Austeilen)
      const dran = v.turn === ich && (v.phase === 'turn' || v.phase === 'drawn' || v.phase === 'challenge' || v.phase === 'color' || v.phase === 'gamble' || v.phase === 'discard_pick');
      this._zeigeAutomat(v);
      if (!this._tauschLaeuft && this.hand.el.getAttribute('style')) this.hand.el.removeAttribute('style');   // Rest einer Tausch-Animation
      this.hinweis.textContent = this.hinweisLokal(h) || this._hinweisErsatz(v);
      this.hinweis.classList.toggle('dran', v.turn === ich && dran);
      this.ichKranz.classList.toggle('an', dran);
      this.ichZahl.classList.toggle('dran', dran);
      this.ichZahl.lastChild.textContent = (v.hand || []).length;
      const p = v.pending || {};
      const jagd = p.kind === 'farbjagd';
      let ak = '';
      // In „challenge“ ist Ziehen dasselbe wie Annehmen → nur ein Knopf
      if (h.can_draw && !h.can_accept) ak += '<button class="knopf klein" data-a="draw">' + (p.kind && v.turn === ich ? (jagd ? M.t('Ziehen bis Farbe') : M.t('%d ziehen', p.amount | 0)) : M.t('Ziehen')) + '</button>';
      if (h.can_keep) ak += '<button class="knopf klein" data-a="keep">' + M.t('Behalten') + '</button>';
      if (h.can_challenge) ak += '<button class="knopf klein warn" data-a="challenge">' + M.t('Anzweifeln') + '</button>';
      if (h.can_accept || (h.can_challenge && h.can_accept === undefined)) ak += '<button class="knopf klein" data-a="accept">' + (jagd || !p.amount ? M.t('Annehmen') : M.t('Annehmen (+%d)', p.amount)) + '</button>';
      if (h.need_color) ak += '<button class="knopf klein" data-a="wunsch">' + M.t('Farbe wählen') + '</button>';
      const pick = this.app.imAblegen && this.app.imAblegen() ? this.app.pickAuswahl(v) : null;
      if (pick) ak += '<button class="knopf klein" data-a="ablegen">' + M.t('Ablegen (%d)', pick.length) + '</button>';
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
      this.knSort.lastChild.textContent = { farbe: M.t('Farbe'), wert: M.t('Wert'), punkte: M.t('Punkte') }[this.app.sortModus()] || M.t('Farbe');
      const reihe = K().sortiere(v.hand || [], this.app.sortModus());
      // Hervorgehoben werden die legbaren Karten, im eigenen Glücksspiel die setzbaren (hints.can_stake). Die persönliche
      // Einstellung „Spielbare Karten hervorheben“ (aus) nimmt Leuchten, Anheben und Abdunkeln ganz weg.
      const setzbar = v.phase === 'gamble' && Array.isArray(h.can_stake) ? h.can_stake : null;
      const markiert = setzbar || spielbar;
      const hervor = !this.app.hervorheben || this.app.hervorheben();
      const aktiv = dran && (v.phase === 'turn' || v.phase === 'drawn' || (v.phase === 'challenge' && spielbar.length > 0) || (setzbar !== null && setzbar.length > 0));
      // Farbe mit ablegen: Auswahl angehoben, abgewählte Kandidaten bleiben hell, alles andere matt (unabhängig von „hervorheben“)
      if (pick) this.hand.setze(reihe, { spielbar: pick, dran: true, kandidaten: h.can_pick || [] });
      else this.hand.setze(reihe, { spielbar: hervor ? markiert : [], dran: hervor && aktiv });
      if (!nurLayout && alt && alt.turn !== ich && v.turn === ich && dran) {
        M.Ton.spiele('dran');
        if (this.app.zugVibration) this.app.zugVibration();   // eigene Einstellung „Bei deinem Zug: Vibration“
      }
    }
    // Hinweis des Gastgebers; ohne „Spielbare Karten hervorheben“ verrät er nicht, dass nichts passt (sonst wäre das die
    // Markierung) – wie in der App (table_view.gd hint_text).
    hinweisText(text) {
      const t = text || '';
      if (this.app.hervorheben && !this.app.hervorheben() && t.indexOf('Du bist dran – nichts passt') === 0)
        return 'Du bist dran.' + (/Denk an „Mau!“$/.test(t) ? ' Denk an „Mau!“' : '');
      return t;
    }
    // Hinweis in der eigenen Sprache (i18n.js): Bausteine hints.lt des Gastgebers bzw. der deutsche Text als msgid; die Kürzung von
    // hinweisText (Hervorheben aus) gilt für beide Wege.
    hinweisLokal(h) {
      const t = h.text || '';
      const kurz = this.hinweisText(t);
      if (kurz === t) return Array.isArray(h.lt) && h.lt.length ? M.I18n.render(h.lt) : M.t(t);
      return M.I18n.render(/Denk an „Mau!“$/.test(kurz) ? ['Du bist dran.', 'Denk an „Mau!“'] : ['Du bist dran.']);
    }
    _hinweisErsatz(v) {
      const p = (v.players || []).find(x => x.seat === v.turn);
      if (v.phase === 'round_over') return M.t('Runde vorbei');
      if (v.phase === 'game_over') return M.t('Partie vorbei');
      if (v.phase === 'gamble') return v.turn === v.seat ? ((v.hints || {}).can_press ? M.t('Drück den Glücksspielknopf!') : ((v.hints || {}).can_stop ? M.t('Noch eine Karte setzen – oder aufhören?') : M.t('Leg eine Karte verdeckt auf deinen Einsatz.'))) : (p ? M.t('%s spielt Glücksspiel', p.name) : '');
      if (v.phase === 'discard_pick' && v.discard_pick) return v.discard_pick.seat === v.seat ? M.t('Wähl die Karten, die du mit ablegst') : M.t('%s wählt Karten in %s zum Mitablegen', ((v.players || []).find(x => x.seat === v.discard_pick.seat) || {}).name, K().farbName(v.discard_pick.color));
      if (v.turn === v.seat) return M.t('Du bist dran');
      return p ? M.t('%s ist dran', p.name) : '';
    }
    _zeigeGegner(v) {
      const ich = v.seat;
      const spieler = (v.players || []).slice().sort((a, b) => a.seat - b.seat);
      const n = spieler.length;
      const gross = this.gross;
      const kompakt = gross || n >= 7;
      const h = v.hints || {};
      const fangbar = new Set(h.catch || []);
      // offenes Erwischen-Fenster: Mitspieler über Ablage, Strafplakette und Farbanzeige legen (Nutzerbefund 08.10.2026)
      this.gegnerBox.classList.toggle('fangbar', fangbar.size > 0);
      const da = new Set();
      const laeuft = v.phase !== 'round_over' && v.phase !== 'game_over';
      // Großer Modus: Liste in Spielrichtung ab dem Spieler, der dran ist (k = 0 oben); eigene Zeile „Du“ gehört dazu
      const dir = v.dir === -1 ? -1 : 1;
      // Fertige Spieler („bis zum Letzten“) verschwinden aus der Liste, solange die Runde läuft (Nutzerentscheidung 08.10.2026)
      const imSpiel = spieler.filter(p => !(p.place > 0));
      const listeSp = laeuft && imSpiel.length ? imSpiel : spieler;
      const nl = listeSp.length;
      const ti = Math.max(0, listeSp.findIndex(p => p.seat === v.turn));
      const richtungNeu = this._listeDir !== undefined && this._listeDir !== dir;
      this._listeDir = dir;
      if (gross) {
        this._listeZeilen(nl);
        this.listeKopf.classList.toggle('gegen', dir === -1);
        if (richtungNeu && !this.app.effekteReduziert()) { this.listeKopf.classList.remove('wendet'); void this.listeKopf.offsetWidth; this.listeKopf.classList.add('wendet'); }
      }
      spieler.forEach((p, i) => {
        if (p.seat === ich && !gross) return;
        da.add(p.seat);
        let g = this.gegnerEls.get(p.seat);
        if (!g) {
          const e = el('div', 'gg');
          e.dataset.seat = p.seat;
          e.innerHTML = '<i class="kranz"></i><div class="denk" aria-hidden="true"><i></i><i></i><b>…</b></div><div class="kopf"><div class="ava"></div><div class="name"></div><div class="zahl"></div><span class="zug"></span></div><div class="faecher"></div><div class="marken"></div><button class="erwischen" data-t>Erwischt!</button>';
          M.I18n.anwenden(e);
          this.gegnerBox.appendChild(e);
          g = { e, sig: '' };
          this.gegnerEls.set(p.seat, g);
        }
        const e = g.e;
        g.kompakt = kompakt;
        e.classList.toggle('kompakt', kompakt && !gross);
        e.classList.toggle('ich', p.seat === ich);
        if (gross) {
          const L = this.g.liste, li = listeSp.indexOf(p), fertig = li < 0;
          let k = fertig ? L.cap : ((li - ti) * dir % nl + nl) % nl;
          // Erwischbar, aber unterhalb der sichtbaren Zeilen (wer gerade gelegt hat, steht ganz unten): Zeile über die letzte
          // sichtbare legen, damit „Erwischt!“ zu sehen ist (Nutzerbefund 08.10.2026)
          const vorn = fangbar.has(p.seat) && k >= L.cap && L.cap > 0;
          if (vorn) k = L.cap - 1;
          e.classList.toggle('vorn', vorn);
          const sprung = g.k !== undefined && k > g.k && !richtungNeu && !fertig;   // oben raus, unten wieder rein (endlose Liste)
          g.k = k;
          const y = L.top + (k + 0.5) * L.zeile;
          g.px = L.x; g.py = L.top + (Math.min(k, L.cap - 1) + 0.5) * L.zeile - 26;   // Unsichtbare docken an der letzten Zeile an
          e.style.left = L.x + 'px'; e.style.top = '0px';
          if (sprung) {
            e.classList.add('sprung');
            e.style.transform = 'translateY(' + (y + L.zeile) + 'px)';
            void e.offsetWidth;
            e.classList.remove('sprung');
          }
          e.style.transform = 'translateY(' + y + 'px)';
          e.classList.toggle('aus', k >= L.cap);
          e.querySelector('.zug').textContent = !laeuft || nl < 2 || fertig ? '' : (k === 0 ? (p.seat === ich ? M.t('Du bist dran') : M.t('ist dran')) : (k === 1 ? M.t('gleich dran') : ''));
        } else {
          const pos = this._gegnerPos((p.seat - ich + n) % n, n);
          g.px = pos.x; g.py = pos.y;
          e.style.left = pos.x + 'px'; e.style.top = pos.y + 'px'; e.classList.remove('aus');
        }
        e.classList.toggle('dran', v.turn === p.seat && laeuft);
        e.classList.toggle('weg', p.connected === false);
        e.classList.toggle('fangbar', fangbar.has(p.seat));
        if (!gross) e.classList.remove('vorn');
        const ava = e.querySelector('.ava');
        ava.textContent = (p.name || '?').trim().charAt(0).toUpperCase();
        ava.style.background = AVA_FARBEN[p.seat % AVA_FARBEN.length];
        e.querySelector('.name').textContent = p.seat === ich ? M.t('Du') : (p.name || M.t('Platz %d', p.seat + 1));
        const zahl = p.seat === ich ? (v.hand || []).length : p.count;
        e.querySelector('.zahl').textContent = zahl;
        let marken = '';
        if (p.mau) marken += '<span class="marke mau">Mau!</span>';
        if (p.kind === 'bot' && !kompakt) marken += '<span class="marke">' + esc(M.t('Computer')) + '</span>';
        if (p.place > 0) marken += '<span class="marke platz">' + esc(M.t('%d. Platz', p.place)) + '</span>';
        if (p.substituted) marken += '<span class="marke">' + esc(M.t('Computer spielt')) + '</span>';
        else if (p.connected === false) marken += '<span class="marke weg">' + ICON_GETRENNT + esc(M.t('getrennt')) + '</span>';
        const mk = e.querySelector('.marken');
        if (mk.innerHTML !== marken) mk.innerHTML = marken;
        // Fächer der sichtbaren Rückseiten (sortiert vom Gastgeber) oder neutrale Rückseiten; im großen Modus keiner (sparsam)
        if (gross) { if (g.sig !== 'gross') { g.sig = 'gross'; e.querySelector('.faecher').innerHTML = ''; } return; }
        const backs = (p.backs && p.backs.length) ? p.backs : new Array(Math.min(p.count | 0, 14)).fill('rueckseite');
        const sig = backs.join(',') + '|' + kompakt + '|' + p.count;
        if (g.sig !== sig) { g.sig = sig; this._faecher(e.querySelector('.faecher'), backs, kompakt, p.count); }
      });
      for (const [seat, g] of this.gegnerEls) if (!da.has(seat)) { g.e.remove(); this.gegnerEls.delete(seat); }
      // vorgezogene erwischbare Zeile verdeckt die letzte sichtbare: diese solange ausblenden (sonst scheint sie durch)
      if (gross) {
        const vorne = [...this.gegnerEls.values()].some(g => g.e.classList.contains('vorn'));
        for (const g of this.gegnerEls.values()) if (vorne && !g.e.classList.contains('vorn') && g.k === this.g.liste.cap - 1) g.e.classList.add('aus');
      }
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
      this.stapelZahl.textContent = M.t('Stapel · %d', n);
    }
    _zeigeAblage(v, alt) {
      const top = v.top;
      // Durchsehen: ändert sich die Ablage (jemand legt, Flip, Mischen), springt alles zurück
      const log = Array.isArray(v.discard_log) ? v.discard_log : [];
      const dsig = log.length + '|' + v.side + '|' + (top ? top.id + top.face : '') + '|' + (log.length ? log[log.length - 1].f : '');
      if (dsig !== this._durchSig) { this._durchSig = dsig; if (this.durch) { this.durch = 0; this._seitenZeichnen(); } }
      this.ablage.classList.toggle('durchsehbar', log.length > 0);
      if (!top) { this.ablageKarten.innerHTML = ''; this.ablageVerlauf = []; return; }
      const letzte = this.ablageVerlauf[this.ablageVerlauf.length - 1];
      if (alt && alt.side !== v.side) this.ablageVerlauf = [];
      if (!letzte || letzte.id !== top.id || letzte.face !== top.face) {
        if (this.ablageVerlauf.length && this.ablageVerlauf[this.ablageVerlauf.length - 1].id === top.id) this.ablageVerlauf.pop();
        this.ablageVerlauf.push({ id: top.id, face: top.face });
        while (this.ablageVerlauf.length > 3) this.ablageVerlauf.shift();
      }
      this._ablageZeichnen();
      // offene Ziehstrafe: pending {kind, amount, by, victim, color}; Farbjagd hat amount 0 (gezogen wird bis zur Farbe)
      const p = v.pending;
      const txt = offenText(p);
      this.offenEl.textContent = txt;
      this.offenEl.hidden = !txt;
    }
    _ablageZeichnen() {
      if (this.durch > 0) return this._durchZeichnen();
      const sig = this.ablageVerlauf.map(c => c.id + c.face).join(',');
      if (this.ablageKarten.dataset.sig === sig) return;
      this.ablageKarten.dataset.sig = sig;
      this.ablageKarten.innerHTML = '';
      const n = this.ablageVerlauf.length;
      this.ablageVerlauf.forEach((c, i) => {
        const k = K().element(c.face, 124, i === n - 1 ? 'top' : 'alt');
        // unter der obersten Karte leicht versetzt, damit mitabgelegte Karten hervorschauen
        const dx = i === n - 1 ? 0 : (i - n + 1) * 12;
        k.style.transform = 'translate(calc(-50% + ' + dx + 'px),-50%) rotate(' + (i === n - 1 ? kartenRot(c.id) * 0.4 : kartenRot(c.id)) + 'deg)';
        this.ablageKarten.appendChild(k);
      });
    }
    /* ---------- Ablage durchsehen (view.discard_log, für alle gleich) ---------- */
    // d = 1: oberste noch liegende Karte auf den Seitenstapel, -1: eine zurück, 0: alle zurück
    durchsehen(d) {
      const log = this.v && Array.isArray(this.v.discard_log) ? this.v.discard_log : [];
      const n = d === 0 ? 0 : Math.max(0, Math.min(log.length, this.durch + d));
      if (n === this.durch) return;
      const vor = this.durch;
      this.durch = n;
      if (n === 0) { this.ablageKarten.dataset.sig = ''; this._ablageZeichnen(); } else this._durchZeichnen();
      this.farbe.style.visibility = this.gross && n ? 'hidden' : '';   // großer Modus: Seitenstapel liegt über der Farbanzeige
      this._seitenZeichnen(n > vor);
    }
    _durchGesicht(e) { return e && e.f && !e.h ? e.f : 'rueckseite'; }
    // Ablage während des Durchsehens: die noch liegenden Karten (die obersten drei)
    _durchZeichnen() {
      const log = (this.v && this.v.discard_log) || [], rest = log.length - this.durch;
      const sig = 'd' + this.durch + '|' + this._durchSig;
      if (this.ablageKarten.dataset.sig === sig) return;
      this.ablageKarten.dataset.sig = sig;
      this.ablageKarten.innerHTML = '';
      for (let i = Math.max(0, rest - 3); i < rest; i++) {
        const k = K().element(this._durchGesicht(log[i]), 124, i === rest - 1 ? 'top' : 'alt');
        k.style.transform = 'translate(calc(-50% + ' + (i - rest + 1) * 12 + 'px),-50%) rotate(' + kartenRot(i * 13 + 5) * 0.6 + 'deg)';
        this.ablageKarten.appendChild(k);
      }
    }
    // Seitenstapel: zuerst verschobene Karte unten, zuletzt verschobene (tiefste) oben, mit Leger, Wunschfarbe und Zähler
    _seitenZeichnen(neu) {
      const log = (this.v && this.v.discard_log) || [], n = this.durch;
      this.seiten.hidden = n === 0;
      this.seitenKarten.innerHTML = '';
      if (!n) return;
      const L = log.length, oben = L - n;
      for (let i = Math.min(L - 1, oben + 2); i >= oben; i--) {
        const k = K().element(this._durchGesicht(log[i]), 124, i === oben ? 'top' + (neu ? ' neu' : '') : 'alt');
        k.style.transform = 'translate(calc(-50% + ' + (i - oben) * 10 + 'px),-50%) rotate(' + kartenRot(i * 13 + 5) * 0.6 + 'deg)';
        this.seitenKarten.appendChild(k);
      }
      const e = log[oben] || {};
      const s = typeof e.s === 'number' ? e.s : -1;
      const wer = s < 0 ? M.t('Startkarte') : (this.v && s === this.v.seat ? M.t('von dir') : M.t('von %s', this.name(s)));
      this.seiten.querySelector('.von').textContent = e.h ? M.t('Einsatz %s', wer) : wer;
      const w = this.seiten.querySelector('.wunsch');
      w.textContent = e.c ? M.t('Wunsch: %s', K().farbName(e.c)) : '';
      w.hidden = !e.c;
      if (e.c) w.dataset.farbe = e.c; else delete w.dataset.farbe;
      this.seiten.querySelector('.zaehler').textContent = M.t('%d von %d', n, L);
    }

    // Farbe mit ablegen / Einsatz unter die Ablage: Karten landen UNTER der obersten (sie bleibt oben)
    unterAblage(karten) {
      const top = this.ablageVerlauf[this.ablageVerlauf.length - 1];
      const unten = this.ablageVerlauf.slice(0, -1).concat(karten).slice(-3);
      this.ablageVerlauf = top ? unten.concat([top]) : unten;
      this._ablageZeichnen();
    }

    /* ---------- Glücksspiel: Automat (Kuppelknopf, Zahlenwerk 0–10) und Einsatzstapel ---------- */
    // view.gamble = {seat, stake, need, last} während eines Glücksspiels, {} sonst; fehlt ohne die Hausregel ganz.
    _gluecksspiel(v) {
      const g = v && v.gamble;
      return (v && v.phase === 'gamble' && g && typeof g.seat === 'number' && g.seat >= 0) ? g : null;
    }
    _zeigeAutomat(v) {
      const g = this._gluecksspiel(v);
      if (!g) { this.automatZu(); this.zeigeEinsatz(-1, 0); return; }
      this.automatAuf();
      this.automatStand(g, v);
      this.zeigeEinsatz(g.seat, g.stake | 0);
    }
    automatAuf() {
      clearTimeout(this._automatTimer);
      this.root.classList.add('mit-automat');
      if (this.automatAktiv) return;
      this.automatAktiv = true;
      const a = this.automat;
      a.hidden = false;
      a.classList.remove('zu', 'treffer', 'niete', 'auf'); void a.offsetWidth; a.classList.add('auf');
    }
    automatZu() {
      if (!this.automatAktiv) return;
      this.automatAktiv = false;
      this.automat.classList.add('zu');
      this.automat.classList.remove('drueckbar');
      this.knStop.hidden = true;
      clearTimeout(this._automatTimer);
      this._automatTimer = setTimeout(() => { if (!this.automatAktiv) { this.automat.hidden = true; this.root.classList.remove('mit-automat'); } }, 700);
    }
    // Zustand aus der Sicht: Knopf bereit (hints.can_press), Text darunter, letzter Wert im Zahlenwerk
    automatStand(g, v) {
      v = v || this.v;
      const ich = v && g.seat === v.seat;
      const h = (v && v.hints) || {};
      const druck = !!(ich && h.can_press), stop = !!(ich && h.can_stop);
      this.automat.classList.toggle('drueckbar', druck);
      this.automat.classList.toggle('meins', !!ich);
      this.kuppel.disabled = !ich;
      this.knStop.hidden = !stop;   // „Aufhören“ nur mit hints.can_stop (nach einem Druck ohne Treffer)
      const n = this.name(g.seat);
      this.automatUnter.textContent = ich ? (druck ? M.t('Drück den Knopf!') : (stop ? '' : M.t('Tipp eine Karte an')))   // mit can_stop steht dort der Knopf, der Hinweis oben fragt
        : (g.need === 'press' ? M.t('%s drückt …', n) : M.t('%s setzt …', n));
      if (!this._walzeLaeuft && typeof g.last === 'number') this.walzeZeige(g.last);   // ohne last: Anzeige bleibt
    }
    walzeZeige(wert) {
      const w = this.walze;
      w.style.transition = 'none'; w.style.transform = '';
      w.innerHTML = '<b>' + (wert >= 0 ? wert : '?') + '</b>';
      this.automat.classList.toggle('treffer', wert > 0);
      this.automat.classList.toggle('niete', wert === 0);
    }
    // Zahlenwerk dreht (Band aus Zufallszahlen) und rastet auf dem Wert ein
    walzeDreh(wert, dauer) {
      const w = this.walze;
      this._walzeLaeuft = true;
      this.automat.classList.remove('treffer', 'niete');
      this.automat.classList.add('dreht');
      const alt = (w.textContent || '?').trim().slice(0, 2);
      const band = [alt];
      for (let i = 0; i < 14; i++) band.push(String(Math.floor(Math.random() * 11)));
      band.push(String(wert));
      w.innerHTML = band.map(z => '<b>' + z + '</b>').join('');
      w.style.transition = 'none'; w.style.transform = 'translateY(0)';
      void w.offsetWidth;
      w.style.transition = 'transform ' + dauer + 'ms cubic-bezier(.12,.62,.2,1)';
      w.style.transform = 'translateY(' + (-(band.length - 1) * ZEILE) + 'px)';
      return schlaf(dauer).then(() => { this._walzeLaeuft = false; this.automat.classList.remove('dreht'); this.walzeZeige(wert); });
    }
    // eigener Druck: Knopf federt, bis die Antwort kommt kein zweiter Druck
    knopfDruck() {
      const k = this.kuppel;
      k.classList.remove('druck'); void k.offsetWidth; k.classList.add('druck');
      this.automat.classList.remove('drueckbar');
      this.automatUnter.textContent = M.t('Viel Glück …');
    }
    // eigenes Aufhören gesendet: Knopf weg, bis die Antwort kommt
    stopGesendet() {
      this.knStop.hidden = true;
      this.automatUnter.textContent = M.t('Du hörst auf …');
    }
    // Lage des Einsatzstapels: eigener Platz links über der Hand, Mitspieler neben ihrem Fächer (zur Tischmitte hin)
    einsatzPos(seat) {
      if (!this.v || seat === this.v.seat) return { x: this.g.einsatz.x, y: this.g.einsatz.y, w: 56 };
      const g = this.gegnerEls.get(seat);
      if (!g) return { x: this.g.cx, y: 80, w: 46 };
      if (this.gross) return { x: g.px - this.g.liste.w / 2 - 60, y: g.py + 26, w: 44 };   // links neben der Listenzeile
      const rechts = g.px <= this.g.cx + 40;
      return { x: g.px + (rechts ? 1 : -1) * (g.kompakt ? 106 : 130), y: g.py + 30, w: g.kompakt ? 40 : 48 };
    }
    zeigeEinsatz(seat, n) {
      this.einsatzSeat = seat; this.einsatzZahl = n;
      const e = this.einsatz;
      if (seat < 0 || !(n > 0)) { e.hidden = true; e.dataset.sig = ''; return; }
      const p = this.einsatzPos(seat);
      e.hidden = false;
      e.style.left = p.x + 'px'; e.style.top = p.y + 'px';
      const meins = !!(this.v && seat === this.v.seat);
      e.classList.toggle('meins', meins);
      e.querySelector('.was').textContent = meins ? M.t('Dein Einsatz') : M.t('Einsatz');
      const sig = seat + ':' + n + ':' + p.w;
      if (e.dataset.sig === sig) return;
      e.dataset.sig = sig;
      const box = e.firstChild;
      box.innerHTML = '';
      const sichtbar = Math.min(n, 4), h = Math.round(p.w * K().VERHAELTNIS);
      box.style.width = (p.w + 3 * 5) + 'px'; box.style.height = (h + 3 * 4) + 'px';
      for (let i = 0; i < sichtbar; i++) {
        const k = K().element('rueckseite', p.w, 'mini');
        k.style.left = (i * 5) + 'px'; k.style.top = ((sichtbar - 1 - i) * 4) + 'px';
        k.style.transform = 'rotate(' + (kartenRot(i * 11 + seat) * 0.35).toFixed(1) + 'deg)';
        box.appendChild(k);
      }
      e.querySelector('.zahl').textContent = n;
      e.classList.remove('neu'); void e.offsetWidth; e.classList.add('neu');
    }

    /* ---------- Kartentausch: eigene Hand wandert zum Nächsten, die neue kommt vom Vorigen ---------- */
    // Transformation der Hand: um (ox, oy) auf sc verkleinert und um (dx, dy) verschoben; handF = Grundmaßstab (großer Modus)
    _handTf(dx, dy, sc) {
      const ox = this.g.cx, oy = this.H - 110;
      return 'translate(' + dx.toFixed(0) + 'px,' + dy.toFixed(0) + 'px) translate(' + ox + 'px,' + oy + 'px) scale(' + sc + ') translate(' + (-ox) + 'px,' + (-oy) + 'px) scale(' + this.handF + ')';
    }
    handWeg(ziel, dauer) {
      const h = this.hand.el, ox = this.g.cx, oy = this.H - 110;
      this._tauschLaeuft = true;
      h.style.transformOrigin = '0 0';
      h.style.transition = 'transform ' + dauer + 'ms cubic-bezier(.5,0,.75,.45), opacity ' + dauer + 'ms ease-in';
      h.style.transform = this._handTf((ziel.x - ox) * 0.8, (ziel.y - oy) * 0.8, 0.3);
      h.style.opacity = '0';
    }
    handRein(reihe, quelle, dauer) {
      const h = this.hand.el, ox = this.g.cx, oy = this.H - 110;
      this.hand.waehle(null);
      this.hand.setze(reihe, { spielbar: [], dran: false });
      h.style.transition = 'none';
      h.style.transformOrigin = '0 0';
      h.style.transform = this._handTf((quelle.x - ox) * 0.8, (quelle.y - oy) * 0.8, 0.3);
      h.style.opacity = '0';
      void h.offsetWidth;
      h.style.transition = 'transform ' + dauer + 'ms cubic-bezier(.2,.75,.3,1), opacity ' + Math.round(dauer * 0.6) + 'ms ease-out';
      h.style.transform = this._handTf(0, 0, 1);
      h.style.opacity = '1';
      return schlaf(dauer + 30).then(() => { this._tauschLaeuft = false; h.removeAttribute('style'); });
    }

    _zeigeFarbe(v) {
      const f = v.color;
      const fi = K().FARB_INFO[f];
      const sig = f + (K().Bilder.symbole ? 'b' : 's') + M.I18n.sprache;
      if (this.farbe.dataset.sig !== sig) {
        this.farbe.dataset.sig = sig;
        this.farbe.innerHTML = fi ? K().farbSymbolHTML(f, { kontur: '#F4EADA', konturBreite: 4 }) + '<span>' + esc(K().farbName(f)) + '</span>' : '';
      }
      this.farbring.style.setProperty('--ring', fi ? fi.ring : 'rgba(244,234,218,.35)');
      this.root.style.setProperty('--farbe', fi ? fi.ring : '#9A86FF');
    }

    /* ---------- Farbwahl (vier Felder um die Ablage) ---------- */
    oeffneFarbwahl(seite, zaehlung, beiWahl, frage) {
      const fw = this.farbwahl;
      const farben = K().FARBEN[seite] || K().FARBEN.hell;
      fw.innerHTML = '<div class="schleier"></div>' + farben.map((f, i) => {
        const fi = K().FARB_INFO[f];
        const grund = seite === 'dunkel' ? fi.ring : fi.hex;
        const hellGrund = f === 'gelb' || f === 'gruen' || f === 'pink';   // Druckfarbe (style.css .farbwahl .feld)
        return '<button class="feld f' + i + '" data-farbe="' + f + '" style="--f:' + grund + '">' +
          K().symbolSVG(f, { farbe: hellGrund ? K().INK : K().CREAM, grund }) +
          '<b>' + esc(K().farbName(f)) + '</b><i>' + (zaehlung[f] ? esc(M.t('%d× auf der Hand', zaehlung[f])) : esc(M.t('keine'))) + '</i></button>';
      }).join('') + '<button class="abbrechen rund" aria-label="' + esc(M.t('Abbrechen')) + '">✕</button><div class="frage">' + esc(frage || M.t('Welche Farbe?')) + '</div>';
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
    // Stempel auf der Ablage (Flip-Überraschung): schräger Schriftzug, der aufgedrückt wird und ausblendet
    stempel(titel, unter, dauer) {
      const a = el('div', 'stempel', '<b>' + esc(titel) + '</b>' + (unter ? '<span>' + esc(unter) + '</span>' : ''));
      a.id = 'stempel';
      a.style.left = this.g.ablage.x + 'px'; a.style.top = this.g.ablage.y + 'px';
      a.style.animationDuration = dauer + 'ms';
      this.flug.appendChild(a);
      setTimeout(() => a.remove(), dauer + 50);
      return a;
    }
    // Ton-Knopf in der Ecke: Zustand aus den Einstellungen
    zeigeTon() {
      const stumm = !!(this.app.einstellungen && this.app.einstellungen.stumm);
      this.knTon.classList.toggle('stumm', stumm);
      this.knTon.setAttribute('aria-label', stumm ? M.t('Ton einschalten') : M.t('Ton ausschalten'));
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
      const blaseLinks = this.gross || (oben ? links : rechts);   // Blase links vom Kopf (Schwanz nach rechts); großer Modus: Liste rechts, Blase immer links
      const kopf = g && g.e.querySelector('.kopf');
      if (kopf && kopf.getBoundingClientRect().width > 0) {
        const r = kopf.getBoundingClientRect();
        const l = this.zuBuehne(r.left, r.top), rb = this.zuBuehne(r.right, r.bottom);
        const y = (l.y + rb.y) / 2;
        return blaseLinks ? { x: l.x - 2, y, seite: 'rechts' } : { x: rb.x + 2, y, seite: 'links' };
      }
      return blaseLinks ? { x: p.x - 40, y: p.y - 60, seite: 'rechts' } : { x: p.x + 40, y: p.y - 60, seite: 'links' };
    }
    // oben = über dem Glücksspiel-Automaten (der die Tischmitte belegt)
    banner(titel, unter, cls, dauer, oben) {
      const b = el('div', 'banner ' + (cls || ''), '<b>' + esc(titel) + '</b>' + (unter ? '<span>' + esc(unter) + '</span>' : ''));
      b.style.left = this.g.cx + 'px'; b.style.top = (this.g.cy - (oben ? 196 : 4)) + 'px';
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
    name(seat) { const p = this.v && (this.v.players || []).find(x => x.seat === seat); return p ? p.name : M.t('Platz %d', seat + 1); }
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
            fluege.push(schlaf(d(i * 70)).then(() => t.fliege(back, { x: t.g.stapel.x, y: t.g.stapel.y, w: t.g.sw }, Object.assign({ rot: kartenRot(i * 7) }, t.platzPos(s)), d(380), { ausblenden: true })));
          });
          await Promise.all(fluege);
          break;
        }
        case 'play': {
          M.Ton.spiele('karte');
          const face = e.face || 'rueckseite';
          const ziel = { x: t.g.ablage.x, y: t.g.ablage.y, w: t.g.aw, rot: kartenRot(e.card) * 0.4 };
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
            fluege.push(schlaf(d(i * 90)).then(() => t.fliege(face, { x: t.g.stapel.x, y: t.g.stapel.y, w: t.g.sw }, Object.assign({ rot: kartenRot(i * 13) * 0.5 }, ziel), d(360), { ausblenden: e.seat !== ich })));
          }
          if ((e.count | 0) > 1) t.abzeichen(e.seat, '+' + e.count, 'zieh', d(1100));
          await Promise.all(fluege);
          break;
        }
        case 'skip':
          t.abzeichen(e.seat, K().iconSVG('schlaf', { main: '#FFF7E8', cut: '#211B2C' }) + '<span>' + esc(M.t('Aussetzen')) + '</span>', 'aussetzen', d(1000));
          await schlaf(d(650));
          break;
        case 'skip_all':
          t.banner(M.t('Alle aussetzen!'), M.t('%s ist gleich noch mal dran', t.name(e.seat)), 'aussetzen', d(1200));
          await schlaf(d(800));
          break;
        case 'reverse':
          t.ring.classList.remove('dreh'); void t.ring.offsetWidth; t.ring.classList.add('dreh');
          setTimeout(() => t.ring.classList.toggle('gegen', e.dir === -1), d(300));
          t.banner(M.t('Richtungswechsel'), '', 'klein', d(1000));
          await schlaf(d(700));
          break;
        case 'color': {
          const fi = K().FARB_INFO[e.color];
          if (!reduziert) t.welle(e.color);
          t._zeigeFarbe({ color: e.color });
          if (fi) t.banner(K().farbName(e.color), M.t('neue Farbe'), 'farbe', d(1000));
          await schlaf(d(650));
          break;
        }
        case 'flip': {
          // Läuft noch ein Wechsel (zwei Flips kurz nacheinander, Rückstau), erst ihn zu Ende blenden lassen
          const rest = t.wechselRest();
          if (rest > 0) await schlaf(rest);
          // Zwischenstand mit der Seite dieses Flips (bei zwei Flips in einem Paket wäre view.side schon die Endseite)
          const zwischen = view.side === e.side ? view : Object.assign({}, view, { side: e.side });
          M.Ton.spiele('flip');
          if (!reduziert) {
            t.wende('aus');
            t.setzeSeite(e.side);   // Himmel, Plattform, Schrift und Knöpfe blenden über (style.css, --wd)
            await schlaf(d(560));
            t.zeige(zwischen, true);
            t.wende('ein');
            await schlaf(d(620));
            t.wendeEnde();
          } else { t.setzeSeite(e.side); t.zeige(zwischen, true); }
          t.banner(e.side === 'dunkel' ? M.t('Nacht!') : M.t('Tag!'), M.t('Alles gewendet'), 'flip', d(1100));
          await schlaf(d(600));
          break;
        }
        case 'flip_surprise': {
          // Hausregel flip_surprise: Die Aktionskarte oben nach dem Flip wirkt, als hätte der Flip-Spieler sie gelegt.
          // Die Wirkungs-Ereignisse (skip, pending, reverse …) folgen direkt danach.
          const name = e.face ? K().kartenName(e.face) : M.t('Aktionskarte');
          t.stempel(M.t('Überraschung!'), e.seat === ich ? M.t('%s – von dir', name) : M.t('%s – von %s', name, t.name(e.seat)), d(1700));
          await schlaf(d(900));
          break;
        }
        case 'pending':
          t.offenEl.hidden = false; t.offenEl.textContent = offenText(e) || ('+' + (e.amount | 0));
          t.offenEl.classList.remove('puls'); void t.offenEl.offsetWidth; t.offenEl.classList.add('puls');
          await schlaf(d(500));
          break;
        case 'challenge':
          t.banner(e.success ? M.t('Bluff erwischt!') : M.t('Kein Bluff!'), e.success ? M.t('%s hat richtig gezweifelt', t.name(e.seat)) : M.t('%s hat sich geirrt', t.name(e.seat)), e.success ? 'gut' : 'warn', d(1500));
          await schlaf(d(1100));
          break;
        case 'mau':      // auf allen Geräten: Aufnahme „Mao“ (außer Ton aus) und Sprechblase beim Rufenden
          if (t.app.mauTon) t.app.mauTon(e.seat, 'mau');
          t.mauBlase(e.seat, 'mau', blasenDauer(1700, d));
          await schlaf(d(450));
          break;
        case 'catch':
          t.banner(M.t('Erwischt!'), M.t('%s hat „Mau!“ vergessen', t.name(e.target)), 'warn', d(1400));
          await schlaf(d(900));
          break;
        case 'penalty':
          t.abzeichen(e.seat, M.t('+%d Strafe', e.count | 0), 'strafe', d(1200));
          await schlaf(d(500));
          break;
        case 'shuffle':
          M.Ton.spiele('mischen');
          t.stapel.classList.remove('mischen'); void t.stapel.offsetWidth; t.stapel.classList.add('mischen');
          t.banner(M.t('Neu gemischt'), '', 'klein', d(900));
          await schlaf(d(700));
          break;
        case 'round_over': {
          const r = Array.isArray(e.ranking) ? e.ranking : [];
          const erster = r.length ? (typeof r[0] === 'object' ? r[0].seat : r[0]) : -1;
          if (erster === ich) { M.Ton.spiele('sieg'); if (!reduziert) t.konfetti(); }
          t.banner(erster === ich ? 'Mau-Mau!' : M.t('Runde vorbei'), erster >= 0 ? M.t('%s ist fertig', t.name(erster)) : '', 'gross', d(1500));
          await schlaf(d(1300));
          break;
        }
        case 'game_over':
          t.banner(M.t('Partie vorbei'), typeof e.winner === 'number' && e.winner >= 0 ? (e.winner === ich ? M.t('Du gewinnst!') : M.t('%s gewinnt', t.name(e.winner))) : '', 'gross', d(1500));
          await schlaf(d(1000));
          break;
        // zusätzliche Ereignisse des Regelwerks (docs/module/A.md)
        case 'finish':   // {seat, place}: fertig → „Mau-Mau!“ (Aufnahme „Mao-Mao“ und große Blase); bei „bis zum Letzten“ mit Platz
          if (t.app.mauTon) t.app.mauTon(e.seat, 'mau_mau');
          t.mauBlase(e.seat, 'mau_mau', blasenDauer(2300, d));
          if (t.v.rules && t.v.rules.round_end === 'last') t.abzeichen(e.seat, M.t('%d. Platz', e.place | 0), 'platz', d(1500));
          await schlaf(d(700));
          break;
        case 'pass':     // {seat}: beide Stapel leer, Ziehen entfällt
          t.abzeichen(e.seat, M.t('Nichts zu ziehen'), 'aussetzen', d(1100));
          await schlaf(d(500));
          break;
        case 'choose_color':   // {seat}: nach einem Flip liegt ein Joker oben, dieser Platz wählt die Farbe
          if (e.seat !== ich) t.banner(M.t('Farbwahl'), M.t('%s wählt die Farbe', t.name(e.seat)), 'klein', d(1000));
          await schlaf(d(300));
          break;

        // ---------- Hausregel Kartentausch ----------
        // {seat, dir, counts, hand (nur die eigene neue Hand), backs?}: Alle aktiven Plätze geben ihre ganze Hand an den nächsten
        // aktiven Platz in Tauschrichtung. Kleine verdeckte Stapel wandern reihum, die eigene Hand fliegt zum Nächsten und die neue
        // kommt vom Vorigen herein; danach zeigt die Sicht die neuen Hände.
        case 'swap_hands': {
          M.Ton.spiele('mischen');
          const schritt = e.dir === -1 ? -1 : 1;
          const aktiv = (view.players || []).filter(p => !(p.place > 0)).map(p => p.seat).sort((a, b) => a - b);
          const nach = s => aktiv[(aktiv.indexOf(s) + schritt + aktiv.length) % aktiv.length];
          const von = s => aktiv[(aktiv.indexOf(s) - schritt + aktiv.length) % aktiv.length];
          t.banner(M.t('Kartentausch!'), M.t('Alle Hände wandern %s weiter', schritt === 1 ? M.t('im Uhrzeigersinn') : M.t('gegen den Uhrzeigersinn')), 'tausch', d(1700));
          if (aktiv.length < 2) { await schlaf(d(900)); break; }
          const vorher = new Map((t.v.players || []).map(p => [p.seat, p.count | 0]));
          const ichDabei = aktiv.indexOf(ich) >= 0;
          aktiv.forEach(s => { const g = t.gegnerEls.get(s); if (g) g.e.classList.add('tauscht'); });
          const flug = d(reduziert ? 420 : 680);
          if (ichDabei) t.handWeg(t.platzPos(nach(ich)), flug);
          const fluege = [];
          aktiv.forEach((s, i) => {
            const stapel = Math.min(3, Math.max(1, vorher.get(s) || 1));
            const a = t.platzPos(s), b = t.platzPos(nach(s));
            for (let j = 0; j < stapel; j++) {
              fluege.push(schlaf(d(i * 35 + j * 80)).then(() => t.fliege('rueckseite', { x: a.x, y: a.y, w: s === ich ? 96 : 54, rot: kartenRot(s * 5 + j) },
                { x: b.x + (j - 1) * 6, y: b.y, w: nach(s) === ich ? 96 : 54, rot: kartenRot(s * 3 + j) * 0.6 }, flug, { ausblenden: nach(s) !== ich })));
            }
          });
          await Promise.all(fluege);
          // neue Fächer der Mitspieler (Kartenzahl, Rückseiten) und die eigene neue Hand
          t._zeigeGegner(view);
          aktiv.forEach(s => { const g = t.gegnerEls.get(s); if (g) g.e.classList.remove('tauscht'); });
          if (ichDabei) {
            const neu = Array.isArray(e.hand) ? e.hand : (view.hand || []);
            await t.handRein(K().sortiere(neu, t.app.sortModus()), t.platzPos(von(ich)), flug);
            t.app.toast(M.t('Deine neuen Karten kommen von %s.', t.name(von(ich))), 'leise', 2600);
          } else await schlaf(d(300));
          break;
        }

        // ---------- Hausregel Glücksspiel ----------
        case 'discard_pick': {  // {seat, color}: Auswahl der mitabgelegten Karten beginnt (Phase discard_pick)
          const fi = K().FARB_INFO[e.color];
          if (e.seat !== ich) t.banner(M.t('Farbe ablegen'), M.t('%s wählt Karten in %s zum Mitablegen', t.name(e.seat), fi ? K().farbName(e.color) : ''), 'farbe', d(1300));
          break;
        }
        case 'gamble_start':    // {seat}: Phase „gamble“ beginnt; der Automat erscheint
          t.automatAuf();
          t.automatStand({ seat: e.seat, stake: 0, need: 'stake', last: -1 }, Object.assign({}, t.v, { hints: {} }));
          t.banner(M.t('Glücksspiel!'), e.seat === ich ? M.t('Setz Karte um Karte und drück den Knopf') : M.t('%s spielt Glücksspiel', t.name(e.seat)), 'gluecks', d(1500), true);
          await schlaf(d(1000));
          break;
        case 'stake': {         // {seat, count, card*, face*}: eine Karte verdeckt auf den Einsatz
          M.Ton.spiele('karte');
          const ziel = t.einsatzPos(e.seat);
          let von;
          if (e.seat === ich && e.card !== undefined) {
            const p = t.hand.position(e.card), he = t.hand.element(e.card);
            von = p ? { x: p.x, y: p.y, w: p.w * 0.8, rot: p.rot } : { x: t.g.cx, y: t.H - 100, w: 150 };
            if (he) he.style.visibility = 'hidden';
          } else von = Object.assign({ rot: -6 }, t.platzPos(e.seat), { w: 54 });
          await t.fliege('rueckseite', von, Object.assign({ rot: kartenRot((e.count | 0) * 7) * 0.35 }, ziel), d(400));
          t.zeigeEinsatz(e.seat, e.count | 0);
          if (t.automatAktiv) t.automatStand({ seat: e.seat, stake: e.count | 0, need: 'press' }, Object.assign({}, t.v, { hints: {} }));
          await schlaf(d(150));
          break;
        }
        case 'gamble_roll': {   // {seat, value}: 0 = kein Treffer (weiter), 1–10 = Treffer (so viele Karten ziehen, Einsatz zurück)
          const wert = e.value | 0;
          t.automatAuf();
          M.Ton.spiele('mischen');
          await t.walzeDreh(wert, d(reduziert ? 500 : 1150));
          const wer = t.name(e.seat);
          if (wert > 0) {
            M.Ton.spiele('fehler');
            const zieht = e.seat === ich ? (wert === 1 ? M.t('Du ziehst 1 Karte – der Einsatz geht zurück') : M.t('Du ziehst %d Karten – der Einsatz geht zurück', wert))
              : (wert === 1 ? M.t('%s zieht 1 Karte – der Einsatz geht zurück', wer) : M.t('%s zieht %d Karten – der Einsatz geht zurück', wer, wert));
            t.banner(M.t('Treffer: %d!', wert), zieht, 'warn klein', d(1600), true);
            await schlaf(d(1100));
          } else {
            t.banner(M.t('0 – Glück gehabt!'), e.seat === ich ? M.t('Kein Treffer, weiter geht’s') : M.t('Kein Treffer für %s', wer), 'gut klein', d(1300), true);
            await schlaf(d(800));
          }
          break;
        }
        case 'stake_back': {    // {seat, count, …}: der ganze Einsatz kommt zurück auf die Hand
          const a = t.einsatzPos(e.seat), b = t.platzPos(e.seat), n = Math.min(4, Math.max(1, e.count | 0));
          t.zeigeEinsatz(e.seat, 0);
          const fluege = [];
          for (let i = 0; i < n; i++) fluege.push(schlaf(d(i * 80)).then(() => t.fliege('rueckseite', { x: a.x, y: a.y, w: a.w, rot: kartenRot(i * 9) * 0.4 }, Object.assign({ rot: kartenRot(i * 5) * 0.5 }, b), d(380), { ausblenden: e.seat !== ich })));
          t.abzeichen(e.seat, M.t('+%d zurück', e.count | 0), 'zieh', d(1200));
          await Promise.all(fluege);
          break;
        }
        // {seat, count, cards*, faces*, reason}: der Einsatz kommt unter die Ablage. reason "empty": Hand leer und 0 gedrückt, der
        // Spieler ist fertig; reason "stop": der Spieler hört auf, sein Zug ist vorbei (danach turn des Nächsten)
        case 'stake_discard': {
          const a = t.einsatzPos(e.seat), n = Math.min(4, Math.max(1, e.count | 0)), stop = e.reason === 'stop';
          t.zeigeEinsatz(e.seat, 0);
          M.Ton.spiele('karte');
          if (stop) {
            const k = e.count | 0;
            t.banner(e.seat === ich ? M.t('Aufgehört!') : M.t('%s hört auf!', t.name(e.seat)), M.t('Der Einsatz (%s) kommt unter die Ablage', kt(k)), 'gluecks klein', d(1500), true);
            if (t.automatAktiv) { t.knStop.hidden = true; t.kuppel.disabled = true; t.automat.classList.remove('drueckbar'); t.automatUnter.textContent = e.seat === ich ? M.t('Du hörst auf') : M.t('%s hört auf', t.name(e.seat)); }
          } else t.banner(M.t('Alles gesetzt!'), M.t('Der Einsatz kommt unter die Ablage'), 'gut klein', d(1500), true);
          const fluege = [];
          for (let i = 0; i < n; i++) fluege.push(schlaf(d(i * 80)).then(() => t.fliege('rueckseite', { x: a.x, y: a.y, w: a.w, rot: kartenRot(i * 9) * 0.4 },
            { x: t.g.ablage.x - 10 + i * 4, y: t.g.ablage.y + 4, w: t.g.aw, rot: kartenRot(i * 7) }, d(420))));
          await Promise.all(fluege);
          if (Array.isArray(e.faces) && e.faces.length) t.unterAblage(e.faces.slice(-2).map((f, i) => ({ id: (e.cards || [])[i] | 0, face: f })));
          await schlaf(d(400));
          break;
        }

        // ---------- Hausregel Farbe mit ablegen ----------
        // {seat, color, cards, faces, count} (öffentlich): alle übrigen Karten der Farbe fliegen auf die Ablage, UNTER die Ablegen-Karte
        case 'discard_color': {
          const n = e.count | 0, fi = K().FARB_INFO[e.color];
          const faces = Array.isArray(e.faces) ? e.faces : [], karten = Array.isArray(e.cards) ? e.cards : [];
          const fname = fi ? K().farbName(e.color) : '';
          t._zeigeFarbe({ color: e.color });
          if (n > 0) {
            M.Ton.spiele('karte');
            const fluege = [];
            faces.forEach((f, i) => {
              let von;
              if (e.seat === ich) {
                const p = t.hand.position(karten[i]), he = t.hand.element(karten[i]);
                von = p ? { x: p.x, y: p.y, w: p.w, rot: p.rot } : { x: t.g.cx, y: t.H - 100, w: 190 };
                if (he) he.style.visibility = 'hidden';
              } else von = Object.assign({ rot: -8 }, t.platzPos(e.seat));
              const ziel = { x: t.g.ablage.x - 16 + (i % 3) * 8, y: t.g.ablage.y + 6, w: t.g.aw, rot: kartenRot(karten[i] | 0) };
              fluege.push(schlaf(d(i * 110)).then(() => t.fliege(f, von, ziel, d(440))));
            });
            t.banner(M.t('Farbe ablegen'), e.seat === ich ? M.t('Du legst %s in %s mit ab', kt(n), fname) : M.t('%s legt %s in %s mit ab', t.name(e.seat), kt(n), fname), 'farbe', d(1600));
            await Promise.all(fluege);
            t.unterAblage(faces.map((f, i) => ({ id: karten[i] | 0, face: f })));
            if (n > 1) t.abzeichen(e.seat, '−' + n, 'zieh', d(1000));
            await schlaf(d(450));
          } else {
            t.abzeichen(e.seat, M.t('Keine weitere %s-Karte', fname), 'aussetzen', d(1200));
            await schlaf(d(500));
          }
          break;
        }
        // round_start, start (Startkarte), turn, keep, accept: nur Zustand, kein eigener Effekt
        default: break;
      }
    }
  }

  M.Tisch = { Tisch, Regie };
})(window.MMF = window.MMF || {});
