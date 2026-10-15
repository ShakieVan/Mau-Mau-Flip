/* Mau-Mau Flip – Browser-Client „Lite“: Verbindung zum Gastgeber (WebSocket ws://<host>/ws, JSON-Textrahmen).
 * Protokoll: docs/BETA1_PLAN.md Abschnitt 5. Verbindet nach Abbruch selbst neu (1, 2, 4, höchstens 5 s),
 * sofort bei visibilitychange/pageshow (Weckruf). Ein Wächter erkennt stille Verbindungen (iOS nach Sperre).
 * Online-Modus (opt.online, docs/online/ENTWURF.md): Verbindung über den Vermittler (…/ws?role=guest&room=CODE), das Spielprotokoll bleibt
 * unverändert. Herzschlag ist der Text „ping“ alle 10 s (Antwort „pong“), 25 s Stille = getrennt (Beta 1.3.3; vorher 25/70 s).
 * 4012: Der Gastgeber war kurz weg und ist wieder da → sofort neu anmelden (Token, danach voller Stand). Schließcodes des Vermittlers:
 * 4503 Gastgeber kurz weg (10 s warten, Status host_weg), 4404 Raum unbekannt (kein_raum), 4409 voll (voll), 1001 beendet (raum_ende);
 * die letzten drei sind endgültig. Status: verbinde | offen | getrennt | host_weg | kein_raum | voll | raum_ende | ersetzt | beendet.
 * App-Wechsel (Beta 1.3.3): weg() schickt bei verdeckter Seite sofort {t:"away"}, zurueck() bei sichtbarer {t:"back"} (der Gastgeber
 * schickt darauf den vollen Stand) und prüft wie wecken(): binnen 3 s keine Antwort → sofort neu verbinden. Ältere Gastgeber ignorieren beides.
 * Gastgeber-Wechsel im WLAN (Beta 1.6.2): umziehen(url), Umzug (hosts/move/Anker #t=&n=) und Reihum (Suche über /info), siehe unten.
 */
(function (M) {
  'use strict';

  const PING_ABSTAND = 5000;     // ms zwischen Lebenszeichen
  const STILL_GRENZE = 15000;    // ohne Nachricht → neu verbinden
  const WECK_PRUEFUNG = 3000;    // nach Weckruf: so lange auf Antwort warten
  const ONLINE_PING = 10000;     // Online: Text „ping“ alle 10 s (der Vermittler antwortet „pong“, ohne sein Objekt zu wecken)
  const ONLINE_STILL = 25000;    // Online: so lange Stille bis „getrennt“
  const ONLINE_HOST_WEG = 10000; // Online: Gastgeber kurz weg (4503) → so lange warten
  const ONLINE_ENDE = { 4404: 'kein_raum', 4409: 'voll', 1001: 'raum_ende' };   // endgültige Schließcodes des Vermittlers

  class Verbindung {
    // opt: {url, hallo: () => Object, beiNachricht(msg), beiStatus(status), online: bool, zeiten: {ping, still, hostWeg} (nur Tests)}
    constructor(opt) {
      this.opt = opt;
      this.online = !!opt.online;
      const z = opt.zeiten || {};
      this.pingAbstand = z.ping || (this.online ? ONLINE_PING : PING_ABSTAND);
      this.stillGrenze = z.still || (this.online ? ONLINE_STILL : STILL_GRENZE);
      this.hostWegWarte = z.hostWeg || ONLINE_HOST_WEG;
      this.ws = null;
      this.status = 'neu';
      this.versuche = 0;
      this.timer = 0;
      this.endgueltig = false;
      this.letzteRx = 0;
      this.letzterPing = 0;
      this.imHintergrund = false;
      this.wache = setInterval(() => this._wachen(), 1000);
    }
    start() { this.endgueltig = false; this._verbinde(); }
    _setze(s) { if (this.status !== s) { this.status = s; if (this.opt.beiStatus) this.opt.beiStatus(s); } }
    _verbinde() {
      clearTimeout(this.timer);
      this._schliesseSocket();
      this._setze(this.versuche ? 'getrennt' : 'verbinde');
      let ws;
      try { ws = new WebSocket(this.opt.url); } catch (e) { this._spaeter(); return; }
      this.ws = ws;
      ws.onopen = () => {
        if (ws !== this.ws) return;
        this.versuche = 0;
        this.letzteRx = Date.now();
        this._roh(this.opt.hallo());
        if (this.imHintergrund) this._roh({ t: 'away' });   // neu angemeldet, aber noch in einer anderen App
        this._setze('offen');
      };
      ws.onmessage = ev => {
        if (ws !== this.ws) return;
        this.letzteRx = Date.now();
        let msg = null;
        try { msg = JSON.parse(ev.data); } catch (e) { return; }
        if (msg && typeof msg === 'object' && this.opt.beiNachricht) this.opt.beiNachricht(msg);
      };
      ws.onclose = ev => {
        if (ws !== this.ws) return;
        this.ws = null;
        // 4000: Der Gastgeber hat diese Verbindung durch eine neuere desselben Spielers ersetzt (z. B. zweiter Tab) → nicht neu verbinden,
        // sonst verdrängen sich zwei Tabs gegenseitig.
        if (ev && ev.code === 4000) { this.endgueltig = true; clearTimeout(this.timer); this._setze('ersetzt'); return; }
        if (this.online && ev) {
          const ende = ONLINE_ENDE[ev.code];
          if (ende) { this.endgueltig = true; clearTimeout(this.timer); this._setze(ende); return; }
          if (ev.code === 4503) { this._hostWeg(); return; }
          if (ev.code === 4012) { this._setze('getrennt'); clearTimeout(this.timer); this.timer = setTimeout(() => this._verbinde(), 100); return; }
        }
        this._spaeter();
      };
      ws.onerror = () => { /* onclose folgt */ };
    }
    _schliesseSocket() {
      const ws = this.ws;
      this.ws = null;
      if (ws) { ws.onopen = ws.onmessage = ws.onclose = ws.onerror = null; try { ws.close(); } catch (e) { /* egal */ } }
    }
    _spaeter() {
      if (this.endgueltig) return;
      this._setze('getrennt');
      const warte = [1000, 2000, 4000, 5000][Math.min(this.versuche, 3)];
      this.versuche++;
      clearTimeout(this.timer);
      this.timer = setTimeout(() => this._verbinde(), warte);
    }
    // Online, Gastgeber getrennt (4503): nicht im Sekundentakt anklopfen, sondern 10 s warten
    _hostWeg() {
      this.versuche = Math.max(this.versuche, 1);
      this._setze('host_weg');
      clearTimeout(this.timer);
      this.timer = setTimeout(() => this._verbinde(), this.hostWegWarte);
    }
    // Lebenszeichen: im WLAN {t:'ping'} (der Gastgeber antwortet mit pong), online der Text „ping“ (Antwort „pong“ vom Vermittler)
    _ping() {
      this.letzterPing = Date.now();
      return this.online ? this._text('ping') : this._roh({ t: 'ping', ts: this.letzterPing });
    }
    _text(s) {
      if (!this.ws || this.ws.readyState !== 1) return false;
      try { this.ws.send(s); return true; } catch (e) { return false; }
    }
    _wachen() {
      if (this.endgueltig || !this.ws || this.ws.readyState !== 1) return;
      const jetzt = Date.now();
      if (jetzt - this.letzteRx > this.stillGrenze) { this.versuche = Math.max(this.versuche, 1); this._verbinde(); return; }
      if (jetzt - this.letzterPing > this.pingAbstand) this._ping();
    }
    // Seite wieder sichtbar: tote Verbindung sofort ersetzen, offene prüfen
    wecken() {
      if (this.endgueltig) return;
      if (!this.ws || this.ws.readyState > 1) { this.versuche = Math.max(this.versuche, 1); this._verbinde(); return; }
      if (this.ws.readyState === 1) {
        const vorher = this.letzteRx;
        this._ping();
        setTimeout(() => { if (!this.endgueltig && this.letzteRx === vorher && this.ws && this.ws.readyState === 1) { this.versuche = 1; this._verbinde(); } }, WECK_PRUEFUNG);
      }
    }
    // Seite verdeckt (andere App): „away“ sofort an den Gastgeber (Best effort)
    weg() { this.imHintergrund = true; this._roh({ t: 'away' }); }
    // Seite wieder sichtbar: „back“ (der Gastgeber schickt den vollen Stand), dann prüfen wie wecken()
    zurueck() {
      const war = this.imHintergrund;
      this.imHintergrund = false;
      if (war) this._roh({ t: 'back' });
      this.wecken();
    }
    // Nutzerwunsch „Neu verbinden“: Verbindung sofort ersetzen
    neuVerbinden() { if (this.endgueltig) return; this.versuche = Math.max(this.versuche, 1); this._verbinde(); }
    // Mau-Mau Flip (Beta 1.6.2, Gastgeber-Wechsel im WLAN, docs/module/uebergabe.md 10.9): ab jetzt diese Adresse, sofort verbinden.
    // Die Seite bleibt beim alten Ursprung (Token im Speicher, hello wie bisher); der neue Gastgeber erlaubt diesen Ursprung (wlan.past).
    umziehen(url) {
      if (this.endgueltig || !url) return false;
      this.opt.url = url;
      this.versuche = 0;
      this._verbinde();
      return true;
    }
    // Selbsttest: Verbindung hart kappen (wie Funkloch) und nach ms neu verbinden
    trennen(ms) {
      if (this.endgueltig) return;
      this._schliesseSocket();
      this._setze('getrennt');
      clearTimeout(this.timer);
      this.versuche = Math.max(this.versuche, 1);
      this.timer = setTimeout(() => this._verbinde(), ms || 1000);
    }
    _roh(obj) {
      if (!this.ws || this.ws.readyState !== 1) return false;
      try { this.ws.send(JSON.stringify(obj)); return true; } catch (e) { return false; }
    }
    sende(obj) { return this._roh(obj); }
    get offen() { return !!this.ws && this.ws.readyState === 1; }
    beenden() {
      this.endgueltig = true;
      clearTimeout(this.timer);
      clearInterval(this.wache);
      this._schliesseSocket();
      this._setze('beendet');
    }
  }

  // Zufalls-Kennung ohne Secure Context (crypto.getRandomValues ist überall verfügbar)
  function zufallsText(n) {
    const a = new Uint8Array(n);
    (window.crypto || window.msCrypto).getRandomValues(a);
    const z = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return Array.from(a, b => z[b % z.length]).join('');
  }

  /* ---- Online-Adressen und Raumcodes (reine Funktionen, getestet in webclient/test/netz_online.html) ---- */
  const Online = {
    GITHUB_RELEASES: 'https://github.com/ShakieVan/Mau-Mau-Flip/releases/latest',
    // Eingabe → „WORT-ZZ“ (Großbuchstaben, Ä/Ö/Ü/ß → AE/OE/UE/SS, Leerzeichen/Unterstrich/fehlender Strich); ungültig → ''
    code(roh) {
      let t = String(roh == null ? '' : roh).trim().toUpperCase().replace(/Ä/g, 'AE').replace(/Ö/g, 'OE').replace(/Ü/g, 'UE').replace(/ß/g, 'SS');
      t = t.replace(/[\s_–—]+/g, '-');
      const m = /^([A-Z]{2,10})-?(\d{2})$/.exec(t);
      return m ? m[1] + '-' + m[2] : '';
    },
    // loc = window.location (oder gleich geformtes Objekt: protocol, host, pathname)
    wsUrl(loc, code) { return (loc.protocol === 'https:' ? 'wss://' : 'ws://') + loc.host + '/ws?role=guest&room=' + encodeURIComponent(code); },
    infoUrl(code) { return '/info?room=' + encodeURIComponent(code); },
    // Android-Intent „In der App spielen“: maumauflip://join?r=CODE&v=<Vermittler>; fehlt die App, kehrt Chrome mit app=1 auf diese Seite zurück
    appIntent(loc, code) {
      const zurueck = loc.protocol + '//' + loc.host + (loc.pathname || '/') + '?r=' + encodeURIComponent(code) + '&app=1';
      return 'intent://join?r=' + encodeURIComponent(code) + '&v=' + encodeURIComponent(loc.host)
        + '#Intent;scheme=maumauflip;package=de.maumauflip.game;S.browser_fallback_url=' + encodeURIComponent(zurueck) + ';end';
    },
  };

  /* ---- Mau-Mau Flip (Beta 1.6.2): Gastgeber-Wechsel im WLAN (docs/module/uebergabe.md 10.9) ----
   * hosts {gid, gen, list:[{name, url}], online, ap, ap_name}: mögliche Nachfolger des Gastgebers (url = http://<IPv4>:<Port>/).
   * move {gid, gen, name, how: lan|online|qr, addr, port, url}: geplanter Wechsel. Reine Funktionen, getestet in webclient/test/netz_online.html. */
  const LITE_SUCHE_AB = 20000;    // so lange „getrennt“, bevor Lite den neuen Gastgeber sucht (und bei Spiel-WLAN den Kasten zeigt)
  const LITE_ONLINE_AB = 60000;   // so lange erfolglose Suche, bevor „Über das Internet weiterspielen“ erscheint
  const PROBE_ABSTAND = 5000;     // Reihum-Probe: alle 5 s jeder Eintrag
  const PROBE_FRIST = 2000;       // je Abfrage /info höchstens 2 s
  const LISTE_MAX = 16;
  const NAME_MAX = 14;            // NetProtocol.MAX_NAME
  const GID = /^[0-9a-fA-F]{1,32}$/;
  const name = roh => String(roh == null ? '' : roh).replace(/\s+/g, ' ').trim().slice(0, NAME_MAX);

  const Umzug = {
    // „http://<IPv4>:<Port>/“ (auch ohne Schrägstrich) → einheitlich mit Schrägstrich; alles andere → ''
    basis(roh) {
      const m = /^http:\/\/((?:\d{1,3}\.){3}\d{1,3}):(\d{1,5})\/?$/.exec(String(roh == null ? '' : roh).trim());
      if (!m || m[1].split('.').some(o => +o > 255)) return '';
      const p = +m[2];
      return p >= 1 && p <= 65535 ? 'http://' + m[1] + ':' + p + '/' : '';
    },
    vonAdresse(addr, port) { return Umzug.basis('http://' + addr + ':' + port + '/'); },
    wsUrl(basis) { return 'ws://' + basis.slice(7) + 'ws'; },
    infoUrl(basis) { return basis + 'info'; },
    // Raum-Link des Vermittlers (http/https, ohne Leerzeichen und Anker)
    netzLink(roh) {
      const s = String(roh == null ? '' : roh).trim();
      return s.length <= 400 && /^https?:\/\/[^\s#"'<>]+$/.test(s) ? s : '';
    },
    hosts(m) {
      if (!m || typeof m.gid !== 'string' || !GID.test(m.gid)) return null;
      const gen = Number(m.gen);
      if (!Number.isInteger(gen) || gen < 0) return null;
      const list = [];
      (Array.isArray(m.list) ? m.list : []).forEach(e => {
        const b = e && Umzug.basis(e.url);
        if (b && list.length < LISTE_MAX && !list.some(x => x.url === b)) list.push({ name: name(e.name), url: b });
      });
      return { gid: m.gid, gen, list, online: Umzug.netzLink(m.online), ap: m.ap === true, ap_name: name(m.ap_name) };
    },
    move(m) {
      if (!m || ['lan', 'online', 'qr'].indexOf(m.how) < 0) return null;
      const out = { how: m.how, gid: typeof m.gid === 'string' && GID.test(m.gid) ? m.gid : '', name: name(m.name) };
      if (m.how === 'lan') { out.basis = Umzug.basis(m.url) || Umzug.vonAdresse(m.addr, m.port); if (!out.basis) return null; }
      if (m.how === 'online') { out.url = Umzug.netzLink(m.url); if (!out.url) return null; }
      return out;
    },
    // Navigation zum neuen Ursprung mit Token und Name im Anker (#t=…&n=…; der Anker geht nie an einen Server)
    ziel(basis, token, n) {
      const b = String(basis == null ? '' : basis).split('#')[0];
      const teile = [];
      if (token) teile.push('t=' + encodeURIComponent(token));
      if (n) teile.push('n=' + encodeURIComponent(n));
      return teile.length ? b + '#' + teile.join('&') : b;
    },
    // location.hash → {t, n} oder null (nur Token aus Buchstaben/Ziffern, Name gekürzt wie beim Beitreten)
    leseHash(hash) {
      let t = '', n = '';
      String(hash == null ? '' : hash).replace(/^#/, '').split('&').forEach(p => {
        const i = p.indexOf('=');
        if (i < 0) return;
        let v = '';
        try { v = decodeURIComponent(p.slice(i + 1).replace(/\+/g, ' ')); } catch (e) { return; }
        if (p.slice(0, i) === 't') t = v;
        else if (p.slice(0, i) === 'n') n = v;
      });
      if (!/^[A-Za-z0-9_-]{1,64}$/.test(t)) t = '';
      n = name(n);
      return t || n ? { t, n } : null;
    },
  };

  // Reihum-Probe: fragt alle `abstand` ms jeden Eintrag der Liste nach /info (Abbruch nach `frist`). Treffer = gleiche gid und
  // höhere gen als bekannt; der erste Treffer in Rangfolge gewinnt. opt: {fetch, abstand, frist, beiTreffer(basis, info)} (fetch für Tests).
  class Reihum {
    constructor(opt) {
      this.opt = opt || {};
      this.abstand = this.opt.abstand || PROBE_ABSTAND;
      this.frist = this.opt.frist || PROBE_FRIST;
      this.gid = '';
      this.gen = 0;
      this.liste = [];
      this.laeuft = false;
      this.runden = 0;
      this.timer = 0;
      this._lauf = 0;
    }
    setze(hosts) {
      if (!hosts) return;
      this.gid = hosts.gid;
      this.gen = hosts.gen;
      this.liste = (hosts.list || []).map(e => e.url);
    }
    start() {
      if (this.laeuft) return;
      this.laeuft = true;
      this._runde(++this._lauf);
    }
    stop() { this.laeuft = false; this._lauf++; clearTimeout(this.timer); }
    _runde(lauf) {
      this.pruefe().then(t => {
        if (lauf !== this._lauf) return;
        this.runden++;
        if (t) { this.stop(); if (this.opt.beiTreffer) this.opt.beiTreffer(t.basis, t.info); return; }
        this.timer = setTimeout(() => this._runde(lauf), this.abstand);
      });
    }
    // eine Runde: alle Einträge gleichzeitig; Ergebnis {basis, info} oder null
    pruefe() {
      const f = this.opt.fetch || (window.fetch ? window.fetch.bind(window) : null);
      const gid = this.gid, gen = this.gen;
      if (!f || !gid || !this.liste.length) return Promise.resolve(null);
      const eins = basis => new Promise(fertig => {
        const ctl = window.AbortController ? new AbortController() : null;
        const t = setTimeout(() => { if (ctl) ctl.abort(); fertig(null); }, this.frist);
        let p;
        try { p = f(Umzug.infoUrl(basis), ctl ? { cache: 'no-store', signal: ctl.signal } : { cache: 'no-store' }); } catch (e) { p = Promise.reject(e); }
        Promise.resolve(p).then(r => (r && r.ok ? r.json() : null)).then(info => {
          clearTimeout(t);
          fertig(info && info.gid === gid && Number.isInteger(info.gen) && info.gen > gen ? { basis, info } : null);
        }).catch(() => { clearTimeout(t); fertig(null); });
      });
      return Promise.all(this.liste.map(eins)).then(alle => alle.find(x => x) || null);
    }
  }

  M.Netz = { Verbindung, zufallsText, Online, Umzug, Reihum, LITE_SUCHE_AB, LITE_ONLINE_AB };
})(window.MMF = window.MMF || {});
