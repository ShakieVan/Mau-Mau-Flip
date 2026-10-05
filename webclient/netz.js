/* Mau-Mau Flip – Browser-Client „Lite“: Verbindung zum Gastgeber (WebSocket ws://<host>/ws, JSON-Textrahmen).
 * Protokoll: docs/BETA1_PLAN.md Abschnitt 5. Verbindet nach Abbruch selbst neu (1, 2, 4, höchstens 5 s),
 * sofort bei visibilitychange/pageshow (Weckruf). Ein Wächter erkennt stille Verbindungen (iOS nach Sperre).
 */
(function (M) {
  'use strict';

  const PING_ABSTAND = 5000;     // ms zwischen Lebenszeichen
  const STILL_GRENZE = 15000;    // ohne Nachricht → neu verbinden
  const WECK_PRUEFUNG = 3000;    // nach Weckruf: so lange auf Antwort warten

  class Verbindung {
    // opt: {url, hallo: () => Object, beiNachricht(msg), beiStatus(status)}; status: verbinde | offen | getrennt | beendet
    constructor(opt) {
      this.opt = opt;
      this.ws = null;
      this.status = 'neu';
      this.versuche = 0;
      this.timer = 0;
      this.endgueltig = false;
      this.letzteRx = 0;
      this.letzterPing = 0;
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
    _wachen() {
      if (this.endgueltig || !this.ws || this.ws.readyState !== 1) return;
      const jetzt = Date.now();
      if (jetzt - this.letzteRx > STILL_GRENZE) { this.versuche = Math.max(this.versuche, 1); this._verbinde(); return; }
      if (jetzt - this.letzterPing > PING_ABSTAND) { this.letzterPing = jetzt; this._roh({ t: 'ping', ts: jetzt }); }
    }
    // Seite wieder sichtbar: tote Verbindung sofort ersetzen, offene prüfen
    wecken() {
      if (this.endgueltig) return;
      if (!this.ws || this.ws.readyState > 1) { this.versuche = Math.max(this.versuche, 1); this._verbinde(); return; }
      if (this.ws.readyState === 1) {
        const vorher = this.letzteRx;
        this.letzterPing = Date.now();
        this._roh({ t: 'ping', ts: this.letzterPing });
        setTimeout(() => { if (!this.endgueltig && this.letzteRx === vorher && this.ws && this.ws.readyState === 1) { this.versuche = 1; this._verbinde(); } }, WECK_PRUEFUNG);
      }
    }
    // Nutzerwunsch „Neu verbinden“: Verbindung sofort ersetzen
    neuVerbinden() { if (this.endgueltig) return; this.versuche = Math.max(this.versuche, 1); this._verbinde(); }
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

  M.Netz = { Verbindung, zufallsText };
})(window.MMF = window.MMF || {});
