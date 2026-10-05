/* Mau-Mau Flip – Browser-Client „Lite“: Ablauf (Startseite, Lobby, Tisch), Verbindung, Aktionen, Einstellungen.
 * Reines HTML/CSS/JS ohne Build-Schritt und ohne Secure-Context-APIs (läuft über http:// vom Gastgeber-Handy).
 * Testmodus: index.html?mock=1 (eingebauter Schein-Gastgeber), &autotest=1 (spielt selbst), &szene=… (Kontrollbilder).
 */
(function (M) {
  'use strict';

  const VERSION = '0.1.1';
  const PROTO = 1;
  // wach.mp4 (32×32, 2 s, H.264 Baseline, ohne Ton; erzeugt mit ffmpeg) als data:-URI
  const WACH_VIDEO = 'data:video/mp4;base64,AAAAIGZ0eXBpc29tAAACAGlzb21pc28yYXZjMW1wNDEAAAMzbW9vdgAAAGxtdmhkAAAAAAAAAAAAAAAAAAAD6AAAB9AAAQAAAQAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAgAAAl50cmFrAAAAXHRraGQAAAADAAAAAAAAAAAAAAABAAAAAAAAB9AAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAABAAAAAAAAAAAAAAAAAABAAAAAACAAAAAgAAAAAAAkZWR0cwAAABxlbHN0AAAAAAAAAAEAAAfQAAAAAAABAAAAAAHWbWRpYQAAACBtZGhkAAAAAAAAAAAAAAAAAABAAAAAgABVxAAAAAAALWhkbHIAAAAAAAAAAHZpZGUAAAAAAAAAAAAAAABWaWRlb0hhbmRsZXIAAAABgW1pbmYAAAAUdm1oZAAAAAEAAAAAAAAAAAAAACRkaW5mAAAAHGRyZWYAAAAAAAAAAQAAAAx1cmwgAAAAAQAAAUFzdGJsAAAAuXN0c2QAAAAAAAAAAQAAAKlhdmMxAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAACAAIABIAAAASAAAAAAAAAABFExhdmM2My4xLjEwMSBsaWJ4MjY0AAAAAAAAAAAAAAAAGP//AAAAL2F2Y0MBQsAe/+EAFmdCwB7ZCWwEQAAAAwBAAAADAQPFi5IBAAZoy4DkTIAAAAAQcGFzcAAAAAEAAAABAAAAFGJ0cnQAAAAAAAAKpAAAAAAAAAAYc3R0cwAAAAAAAAABAAAABAAAIAAAAAAUc3RzcwAAAAAAAAABAAAAAQAAABxzdHNjAAAAAAAAAAEAAAABAAAABAAAAAEAAAAkc3RzegAAAAAAAAAAAAAABAAAAogAAAALAAAACwAAAAsAAAAUc3RjbwAAAAAAAAABAAADYwAAAGF1ZHRhAAAAWW1ldGEAAAAAAAAAIWhkbHIAAAAAAAAAAG1kaXJhcHBsAAAAAAAAAAAAAAAALGlsc3QAAAAkqXRvbwAAABxkYXRhAAAAAQAAAABMYXZmNjMuMS4xMDEAAAAIZnJlZQAAArFtZGF0AAACcgYF//9u3EXpvebZSLeWLNgg2SPu73gyNjQgLSBjb3JlIDE2NSByMzIyMyAwNDgwY2IwIC0gSC4yNjQvTVBFRy00IEFWQyBjb2RlYyAtIENvcHlsZWZ0IDIwMDMtMjAyNSAtIGh0dHA6Ly93d3cudmlkZW9sYW4ub3JnL3gyNjQuaHRtbCAtIG9wdGlvbnM6IGNhYmFjPTAgcmVmPTMgZGVibG9jaz0xOi0zOi0zIGFuYWx5c2U9MHgxOjB4MTExIG1lPWhleCBzdWJtZT03IHBzeT0xIHBzeV9yZD0yLjAwOjAuNzAgbWl4ZWRfcmVmPTEgbWVfcmFuZ2U9MTYgY2hyb21hX21lPTEgdHJlbGxpcz0xIDh4OGRjdD0wIGNxbT0wIGRlYWR6b25lPTIxLDExIGZhc3RfcHNraXA9MSBjaHJvbWFfcXBfb2Zmc2V0PS00IHRocmVhZHM9MSBsb29rYWhlYWRfdGhyZWFkcz0xIHNsaWNlZF90aHJlYWRzPTAgbnI9MCBkZWNpbWF0ZT0xIGludGVybGFjZWQ9MCBibHVyYXlfY29tcGF0PTAgY29uc3RyYWluZWRfaW50cmE9MCBiZnJhbWVzPTAgd2VpZ2h0cD0wIGtleWludD0yNTAga2V5aW50X21pbj0yIHNjZW5lY3V0PTQwIGludHJhX3JlZnJlc2g9MCByY19sb29rYWhlYWQ9NDAgcmM9Y3JmIG1idHJlZT0xIGNyZj00MC4wIHFjb21wPTAuNjAgcXBtaW49MCBxcG1heD02OSBxcHN0ZXA9NCBpcF9yYXRpbz0xLjQwIGFxPTE6MS4yMACAAAAADmWIhAXznJigACX3J114AAAAB0GaOAvnOWAAAAAHQZpUAvnOWAAAAAdBmmAVznLA';
  const params = new URLSearchParams(location.search);
  M.param = n => params.get(n);
  const $ = s => document.querySelector(s);
  const esc = s => String(s == null ? '' : s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

  // localStorage kann fehlen oder werfen (privater Modus, gesperrt) → immer abgesichert
  const Speicher = {
    get(k, d) { try { const v = window.localStorage.getItem('mmf.' + k); return v === null ? d : JSON.parse(v); } catch (e) { return d; } },
    set(k, v) { try { if (v === null || v === undefined) window.localStorage.removeItem('mmf.' + k); else window.localStorage.setItem('mmf.' + k, JSON.stringify(v)); } catch (e) { /* egal */ } },
  };

  const ua = navigator.userAgent || '';
  const IST_IOS = /iPhone|iPad|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
  const IST_SAFARI = IST_IOS && !/CriOS|FxiOS|EdgiOS|OPiOS|GSA\//.test(ua);
  const IST_ANDROID = /Android/i.test(ua);
  const ART = { app: 'App', web: 'Browser', bot: 'Computer', host: 'App' };

  function ladeSkript(src) {
    return new Promise((ok, fehler) => { const s = document.createElement('script'); s.src = src; s.onload = ok; s.onerror = () => fehler(new Error('Laden fehlgeschlagen: ' + src)); document.head.appendChild(s); });
  }

  const App = {
    version: VERSION,
    screen: 'start',
    name: '',
    meineId: null,
    hostName: '',
    lobby: null,
    view: null,
    seq: 0,
    offen: null,           // offene Aktion {seq, zeit, a}
    schwebend: null,       // optimistisch gespielte Karte
    verbindung: null,
    beigetreten: false,
    tisch: null,
    fehler: [],
    logPuffer: [],
    einstellungen: { ton: 'normal', effekte: 'voll', sort: 'farbe', vibration: true, vollbild: true },

    /* ---------------- Start ---------------- */
    init() {
      const e = this.einstellungen;
      e.ton = Speicher.get('ton', 'normal');
      const reduziert = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      e.effekte = Speicher.get('effekte', reduziert ? 'reduziert' : 'voll');
      e.sort = Speicher.get('sort', 'farbe');
      e.vibration = Speicher.get('vibration', true);
      e.vollbild = Speicher.get('vollbild', true);
      M.Ton.setzeStufe(e.ton);
      document.body.classList.toggle('reduziert', e.effekte === 'reduziert');
      if (params.get('ruhig')) document.body.classList.add('ruhig');
      this._fehlerFangen();
      this._startseite();
      this._ereignisse();
      M.Karten.pruefeBilder(() => { if (this.tisch && this.view) this.tisch.zeige(this.view, true); });
      this.groesse();
      const szene = params.get('szene');
      if (szene && szene !== 'start' && params.get('mock')) setTimeout(() => this.beitreten(params.get('name') || 'Kim'), 30);
      if (params.get('autotest') && M.Autotest) M.Autotest.start(this);
    },
    _startseite() {
      const n = $('#name');
      n.value = Speicher.get('name', '') || '';
      $('#beitreten').addEventListener('click', ev => { ev.preventDefault(); this.beitreten(); });
      $('#start-form').addEventListener('submit', ev => { ev.preventDefault(); this.beitreten(); });
      $('#apk').hidden = !IST_ANDROID;
      $('#tipp-safari').hidden = !IST_IOS;
      $('#tipp-ios-browser').hidden = !(IST_IOS && !IST_SAFARI);
      if (Speicher.get('token', null) && n.value) $('#beitreten').textContent = 'Weiterspielen';
      if (location.protocol === 'file:' && !params.get('mock')) this._startFehler('Diese Seite kommt vom Gastgeber-Handy. Zum Ausprobieren ohne Gastgeber: index.html?mock=1');
      // Name und Version des Gastgebers
      if (!params.get('mock') && /^https?:/.test(location.protocol) && window.fetch) {
        const ctl = window.AbortController ? new AbortController() : null;
        const t = setTimeout(() => ctl && ctl.abort(), 3000);
        fetch('/info', ctl ? { signal: ctl.signal, cache: 'no-store' } : { cache: 'no-store' }).then(r => (r.ok ? r.json() : null)).then(info => {
          clearTimeout(t);
          if (!info) return;
          if (info.version) this.version = String(info.version);
          if (info.name) {
            const n = Array.isArray(info.players) ? info.players.length : (info.players | 0);
            this.hostName = info.name;
            $('#start-host').textContent = 'Spiel von ' + info.name + (n ? ' · ' + n + ' Spieler' : '');
          }
        }).catch(() => clearTimeout(t));
      } else if (params.get('mock')) $('#start-host').textContent = 'Spiel von Lena · Testmodus';
    },
    _ereignisse() {
      const neu = () => { cancelAnimationFrame(this._raf); this._raf = requestAnimationFrame(() => this.groesse()); };
      window.addEventListener('resize', neu);
      window.addEventListener('orientationchange', () => setTimeout(neu, 120));
      if (window.visualViewport) window.visualViewport.addEventListener('resize', neu);
      document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') this.wecken(); });
      window.addEventListener('pageshow', () => this.wecken());
      window.addEventListener('online', () => this.wecken());
      // keine Zoom- und Kontextmenü-Gesten im Spiel
      document.addEventListener('gesturestart', e => e.preventDefault());
      document.addEventListener('dblclick', e => { if (!e.target.closest('input')) e.preventDefault(); });
      document.addEventListener('contextmenu', e => { if (!e.target.closest('input')) e.preventDefault(); });
      document.addEventListener('pointerup', () => M.Ton.wecken(), { passive: true });
      // Escape (PC): Farbwahl bzw. Fenster schließen
      document.addEventListener('keydown', e => {
        if (e.key !== 'Escape') return;
        if (this.tisch && this.tisch.farbwahlOffen) { this.tisch.schliesseFarbwahl(); this.tisch.hand.waehle(null); return; }
        ['hilfe', 'ansicht', 'menue', 'runde'].forEach(id => this.schliesse(id));
      });
      // Lobby
      $('#bereit').addEventListener('click', ev => { ev.preventDefault(); this.bereit(); });
      $('#ende-zurueck').addEventListener('click', ev => { ev.preventDefault(); location.reload(); });
      $('#verbinde-laden').addEventListener('click', ev => { ev.preventDefault(); location.reload(); });
      // Fenster schließen
      document.querySelectorAll('.modal').forEach(m => m.addEventListener('click', ev => {
        if (ev.target === m || ev.target.closest('.schliessen')) { ev.preventDefault(); this.schliesse(m.id); }
      }));
      $('#menue').addEventListener('click', ev => {
        const b = ev.target.closest('button[data-set]');
        if (b) { ev.preventDefault(); this.einstellen(b.dataset.set, b.dataset.wert); return; }
        if (ev.target.closest('#menue-neu')) { ev.preventDefault(); this.schliesse('menue'); if (this.verbindung) this.verbindung.neuVerbinden(); }
      });
    },
    groesse() {
      const vv = window.visualViewport;
      const vw = Math.round(vv ? vv.width : window.innerWidth), vh = Math.round(vv ? vv.height : window.innerHeight);
      document.documentElement.style.setProperty('--vh', vh + 'px');
      document.documentElement.style.setProperty('--vw', vw + 'px');
      document.body.classList.toggle('hoch', vw < vh);
      if (this.tisch) {
        const cs = getComputedStyle($('#sicher'));
        const links = parseFloat(cs.paddingLeft) || 0, rechts = parseFloat(cs.paddingRight) || 0;
        this.tisch.groesse(vw, vh, links, rechts);
      }
    },
    zeigeScreen(name) {
      this.screen = name;
      document.body.dataset.screen = name;
      if (name === 'tisch') this._querSperren();
      if (name === 'tisch' && !this.tisch) {
        this.tisch = new M.Tisch.Tisch($('#tisch'), this);
        this.groesse();
      }
      if (name !== 'tisch') ['hilfe', 'ansicht', 'runde'].forEach(id => this.schliesse(id));
    },

    /* ---------------- Verbindung ---------------- */
    beitreten(vorgabe) {
      const feld = $('#name');
      if (vorgabe) feld.value = vorgabe;
      const name = feld.value.replace(/\s+/g, ' ').trim().slice(0, 16);
      if (!name) { this._startFehler('Bitte gib deinen Namen ein.'); feld.focus(); return; }
      this.name = name;
      Speicher.set('name', name);
      this._startFehler('');
      M.Ton.freischalten();
      if (IST_ANDROID && this.einstellungen.vollbild) this.vollbild(true);
      this.wachStart();
      const knopf = $('#beitreten');
      knopf.disabled = true; knopf.textContent = 'Verbinde …';
      if (this.verbindung) this.verbindung.beenden();
      const Klasse = params.get('mock') && M.Mock ? M.Mock.Verbindung : M.Netz.Verbindung;
      const url = (location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws';
      this.verbindung = new Klasse({
        url,
        hallo: () => {
          const h = { t: 'hello', proto: PROTO, game: this.version, name: this.name, kind: 'web' };
          const tok = Speicher.get('token', null);
          if (tok) h.token = tok;
          this._tokenGesendet = !!tok;
          return h;
        },
        beiNachricht: m => this.nachricht(m),
        beiStatus: s => this.status(s),
      });
      this.verbindung.start();
    },
    status(s) {
      const v = $('#verbinde');
      const zeigen = (s === 'getrennt') && this.beigetreten;
      v.hidden = !zeigen;
      if (zeigen) {
        clearTimeout(this._ladeTimer);
        $('#verbinde-laden').hidden = true;
        this._ladeTimer = setTimeout(() => { $('#verbinde-laden').hidden = false; }, 15000);
      } else clearTimeout(this._ladeTimer);
      if (s === 'getrennt' && !this.beigetreten && this.screen === 'start') {
        this._startFehler('Keine Verbindung zum Gastgeber. Seid ihr im selben WLAN? Ich versuche es weiter …');
      }
      if (s === 'offen') { this._logLeeren(); if (this.screen === 'start') this._startFehler(''); }
    },
    wecken() {
      if (this.verbindung) this.verbindung.wecken();
      M.Ton.wecken();
      if (this._wachAn) { const w = $('#wach'); if (w && w.paused) { const p = w.play(); if (p && p.catch) p.catch(() => {}); } }
    },
    // Vollbild (Android-Browser; iPhone kennt es für Seiten nicht): mehr Höhe im Querformat, nur aus einem Tipp heraus
    vollbild(an) {
      const d = document, el = d.documentElement;
      try {
        if (an) {
          const f = el.requestFullscreen || el.webkitRequestFullscreen;
          if (f && !(d.fullscreenElement || d.webkitFullscreenElement)) { const p = f.call(el, { navigationUI: 'hide' }); if (p && p.catch) p.catch(() => {}); }
        } else {
          const f = d.exitFullscreen || d.webkitExitFullscreen;
          if (f && (d.fullscreenElement || d.webkitFullscreenElement)) { const p = f.call(d); if (p && p.catch) p.catch(() => {}); }
        }
      } catch (e) { /* nicht unterstützt */ }
    },
    // Im Vollbild lässt sich das Querformat sperren (Android); sonst bleibt der Hinweis „Bitte quer halten“
    _querSperren() {
      try {
        const o = screen.orientation;
        if (o && o.lock && (document.fullscreenElement || document.webkitFullscreenElement)) { const p = o.lock('landscape'); if (p && p.catch) p.catch(() => {}); }
      } catch (e) { /* egal */ }
    },
    // Wachhalte-Ersatz ohne Wake Lock: stummes Kleinstvideo in Schleife (startet nur aus einem Tipp heraus)
    wachStart() {
      const w = $('#wach');
      if (!w) return;
      try {
        w.muted = true; w.loop = true; w.playsInline = true;
        w.setAttribute('muted', ''); w.setAttribute('playsinline', ''); w.setAttribute('webkit-playsinline', '');
        // als data:-URI, weil iOS-Safari Videos nur mit Range-Anfragen lädt (der Gastgeber-Server muss das so nicht können);
        // Rückfall auf die Datei wach.mp4
        if (!w.src) { w.addEventListener('error', () => { if (w.src.indexOf('data:') === 0) { w.src = 'wach.mp4'; const q = w.play(); if (q && q.catch) q.catch(() => {}); } }); w.src = WACH_VIDEO; }
        const p = w.play();
        if (p && p.catch) p.catch(() => {});
        this._wachAn = true;
      } catch (e) { /* nur Beiwerk */ }
    },
    nachricht(m) {
      switch (m.t) {
        case 'welcome':
          this.meineId = m.id;
          if (m.token) Speicher.set('token', m.token);
          if (m.host_name) this.hostName = m.host_name;
          this.beigetreten = true;
          $('#beitreten').disabled = false; $('#beitreten').textContent = 'Beitreten';
          if (this.screen === 'start') { this.zeigeScreen('lobby'); this._lobbyLeer(); }
          break;
        case 'reject': {
          const texte = { version: 'Die Version passt nicht zum Gastgeber. Bitte die Seite neu laden.', full: 'Das Spiel ist voll.', running: 'Die Partie läuft schon. Warte, bis die nächste beginnt.', proto: 'Der Gastgeber spricht ein anderes Protokoll. Bitte die Seite neu laden.' };
          if (this._tokenGesendet && (m.code === 'running' || m.code === 'token')) Speicher.set('token', null);
          this.verbindung.beenden();
          this.beigetreten = false;
          $('#verbinde').hidden = true;
          this.zeigeScreen('start');
          $('#beitreten').disabled = false; $('#beitreten').textContent = 'Beitreten';
          this._startFehler(m.text || texte[m.code] || 'Der Gastgeber hat abgelehnt.');
          break;
        }
        case 'lobby': {
          this.lobby = m;
          // Während einer laufenden Partie sind Lobby-Stände nur Spielerlisten; nach Partieende zurück in die Lobby
          const amTisch = this.screen === 'tisch' && (!this.view || this.view.phase !== 'game_over');
          if (!amTisch && this.screen !== 'lobby') this.zeigeScreen('lobby');
          this.zeigeLobby(m);
          break;
        }
        case 'start':
          if (typeof m.seat === 'number') this.seat = m.seat;
          this.view = null;
          if (this.tisch) { this.tisch.ablageVerlauf = []; this.tisch.v = null; }
          this.zeigeScreen('tisch');
          break;
        case 'state':
          if (!m.view) break;
          this.view = m.view;
          if (this.screen !== 'tisch') this.zeigeScreen('tisch');
          if (this.offen && (m.seq_ack === undefined || m.seq_ack >= this.offen.seq)) this.offen = null;
          this.tisch.regie.neu(m.events || [], m.view);
          if (M.Autotest && M.Autotest.zustand) M.Autotest.zustand(m);
          break;
        case 'err':
          this.offen = null;
          this.toast(m.text || 'Das geht gerade nicht.', 'fehler');
          M.Ton.spiele('fehler');
          this.vibrieren([20, 50, 20]);
          if (this.schwebend !== null && this.tisch) { this.tisch.hand.schwebe(this.schwebend, false); this.tisch.hand.wackeln(this.schwebend); this.schwebend = null; }
          if (M.Autotest && M.Autotest.fehlerNachricht) M.Autotest.fehlerNachricht(m);
          break;
        case 'pong':
          if (m.ts) this.latenz = Date.now() - m.ts;
          break;
        case 'bye':
          this.verbindung.beenden();
          this.beigetreten = false;
          Speicher.set('token', null);
          $('#verbinde').hidden = true;
          $('#ende-text').textContent = m.text || 'Der Gastgeber hat das Spiel beendet.';
          this.zeigeScreen('ende');
          break;
        default: break;
      }
    },
    sende(obj) { return this.verbindung ? this.verbindung.sende(obj) : false; },

    /* ---------------- Lobby ---------------- */
    _lobbyLeer() {
      $('#lobby-host').textContent = this.hostName ? 'Spiel von ' + this.hostName : 'Verbunden';
      $('#lobby-liste').innerHTML = '<li class="lz leer">Warte auf die Spielerliste …</li>';
    },
    zeigeLobby(l) {
      $('#lobby-host').textContent = this.hostName ? 'Spiel von ' + this.hostName : 'Lobby';
      const spieler = (l.players || []).slice().sort((a, b) => ((a.seat < 0 || a.seat == null) ? 99 : a.seat) - ((b.seat < 0 || b.seat == null) ? 99 : b.seat) || a.id - b.id);
      let ich = null;
      $('#lobby-liste').innerHTML = spieler.map((p, i) => {
        const istIch = p.id === this.meineId;
        if (istIch) ich = p;
        const host = p.id === l.host_id;
        const bereit = p.ready || host || p.kind === 'bot';
        return '<li class="lz' + (istIch ? ' ich' : '') + (p.connected === false ? ' weg' : '') + '">' +
          '<span class="platz">' + ((p.seat != null && p.seat >= 0) ? p.seat + 1 : '–') + '</span>' +
          '<span class="ava" style="background:' + ['#FF9ECF', '#43B05C', '#FFDD33', '#4C7DFF', '#FF8A1F', '#19C6D4', '#8B6BFF', '#FF4D57', '#B0E06A', '#F4EADA'][((p.seat != null && p.seat >= 0) ? p.seat : i) % 10] + '">' + esc((p.name || '?').charAt(0).toUpperCase()) + '</span>' +
          '<span class="nm">' + esc(p.name) + (istIch ? ' <em>(du)</em>' : '') + '</span>' +
          '<span class="art">' + esc(ART[p.kind] || p.kind || '') + '</span>' +
          (host ? '<span class="marke gast">Gastgeber</span>' : '') +
          (p.connected === false ? '<span class="marke weg">getrennt</span>' : '<span class="status ' + (bereit ? 'ja' : '') + '">' + (bereit ? 'bereit' : 'wartet') + '</span>') +
          '</li>';
      }).join('') || '<li class="lz leer">Noch niemand da.</li>';
      const k = $('#bereit');
      const bereit = !!(ich && ich.ready);
      k.textContent = bereit ? 'Bereit ✓' : 'Bereit';
      k.classList.toggle('an', bereit);
      $('#lobby-status').textContent = bereit ? 'Warte auf den Start durch den Gastgeber …' : 'Tippe auf „Bereit“, wenn du startklar bist.';
      $('#lobby-regeln').innerHTML = M.Karten.regelnText(l.rules).map(t => '<li>' + esc(t) + '</li>').join('');
      $('#lobby-zahl').textContent = spieler.length + (spieler.length === 1 ? ' Spieler' : ' Spieler');
    },
    bereit() {
      const ich = this.lobby && (this.lobby.players || []).find(p => p.id === this.meineId);
      this.sende({ t: 'lobby_ready', ready: !(ich && ich.ready) });
    },

    /* ---------------- Aktionen am Tisch ---------------- */
    aktion(a) {
      const v = this.view;
      if (!v || !this.verbindung) return;
      if (a.a === 'wunsch') { this._farbwunsch(); return; }
      if (a.a === 'draw') { this.ziehen(); return; }
      this._sendeAkt(a);
    },
    _sendeAkt(a) {
      this.seq++;
      const ok = this.sende({ t: 'act', seq: this.seq, a });
      if (!ok) { this.toast('Keine Verbindung – ich verbinde neu …', 'fehler'); this.verbindung.wecken(); return false; }
      this.offen = { seq: this.seq, zeit: Date.now(), a };
      clearTimeout(this._antwortTimer);
      const seq = this.seq;
      this._antwortTimer = setTimeout(() => {
        if (this.offen && this.offen.seq === seq) {
          this.offen = null;
          if (this.schwebend !== null && this.tisch) { this.tisch.hand.schwebe(this.schwebend, false); this.schwebend = null; }
          this.toast('Keine Antwort vom Gastgeber – ich verbinde neu …', 'fehler');
          this.verbindung.wecken();
        }
      }, 6000);
      return true;
    },
    antippen(id) {
      const t = this.tisch;
      if (!t) return;
      if (t.hand.rueck) { this.rueckseiten(); return; }
      if (id === null) { if (t.hand.gewaehlt !== null) t.hand.waehle(null); return; }
      if (t.hand.gewaehlt === id) { this.spielen(id); return; }
      t.hand.waehle(id);
    },
    spielen(id) {
      const v = this.view, t = this.tisch;
      if (!v || !t) return;
      if (t.hand.rueck) { this.rueckseiten(); return; }
      const c = (v.hand || []).find(h => h.id === id);
      if (!c) return;
      const h = v.hints || {};
      if (v.turn !== v.seat || (v.phase !== 'turn' && v.phase !== 'drawn')) {
        t.hand.wackeln(id);
        this.toast(v.phase === 'challenge' && h.can_challenge ? 'Erst anzweifeln oder annehmen.' : (h.need_color ? 'Erst die Farbe wählen.' : 'Warte, bis du dran bist.'));
        return;
      }
      if ((h.playable || []).indexOf(id) < 0) {
        t.hand.wackeln(id);
        M.Ton.spiele('fehler');
        this.vibrieren([20, 50, 20]);
        this.toast(this.passtNicht(v, c));
        return;
      }
      if (this.offen && this.offen.a.a === 'play') return;
      if (M.Karten.istJoker(c.face)) {
        t.hand.waehle(id);
        t.oeffneFarbwahl(v.side, this.zaehleFarben(v, id), farbe => {
          if (farbe) this._spieleKarte(id, farbe);
          else if (this.tisch) this.tisch.hand.waehle(null);
        });
        return;
      }
      this._spieleKarte(id);
    },
    _spieleKarte(id, farbe) {
      const a = { a: 'play', card: id };
      if (farbe) a.color = farbe;
      if (!this._sendeAkt(a)) return;
      const hand = this.tisch.hand;
      hand.gewaehlt = null;
      hand.schwebe(id, true);
      this.schwebend = id;
    },
    passtNicht(v, c) {
      const K = M.Karten;
      if (v.phase === 'drawn') return 'Jetzt geht nur die gezogene Karte – oder „Behalten“.';
      if (K.istJoker(c.face)) return 'Diesen Joker darfst du gerade nicht legen – du hast noch ' + K.farbName(v.color) + '.';
      const top = v.top ? K.zerlege(v.top.face) : null;
      let was = K.farbName(v.color);
      if (top && top.art === 'zahl') was += ' oder eine ' + top.wert;
      else if (top && !K.istJoker(top.key)) was += ' oder ' + K.kartenName(top.key).replace(K.farbName(top.farbe) + ' ', '');
      return 'Passt nicht – gefragt ist ' + was + '.';
    },
    zaehleFarben(v, ohne) {
      const z = {};
      (v.hand || []).forEach(c => { if (c.id === ohne) return; const k = M.Karten.zerlege(c.face); if (k.farbe) z[k.farbe] = (z[k.farbe] || 0) + 1; });
      return z;
    },
    _farbwunsch() {
      const v = this.view;
      if (!v || !this.tisch || this.tisch.farbwahlOffen) return;
      this.tisch.oeffneFarbwahl(v.side, this.zaehleFarben(v, null), farbe => { if (farbe) this._sendeAkt({ a: 'color', color: farbe }); });
    },
    ziehen() {
      const v = this.view;
      if (!v) return;
      const h = v.hints || {};
      if (h.can_draw) { if (!this.offen) this._sendeAkt({ a: 'draw' }); return; }
      if (v.turn === v.seat && v.phase === 'drawn') this.toast('Leg die gezogene Karte oder tippe auf „Behalten“.');
      else if (v.turn === v.seat && h.can_challenge) this.toast('Erst anzweifeln oder annehmen.');
      else if (v.turn !== v.seat) this.toast('Warte, bis du dran bist.');
    },
    mau() {
      const v = this.view;
      if (!v || !this.tisch) return;
      const k = this.tisch.knMau;
      k.classList.remove('drueck'); void k.offsetWidth; k.classList.add('drueck');
      if ((v.hints || {}).can_mau) {
        M.Ton.spiele('mau');            // nur auf diesem Gerät
        this.vibrieren(40);
        this._sendeAkt({ a: 'mau' });
      } else this.toast('„Mau!“ rufst du, wenn du nur noch zwei Karten hast und dran bist.');
    },
    sortieren() {
      const reihe = ['farbe', 'wert', 'punkte'];
      const e = this.einstellungen;
      e.sort = reihe[(reihe.indexOf(e.sort) + 1) % reihe.length];
      Speicher.set('sort', e.sort);
      if (this.tisch && this.view) this.tisch.zeige(this.view, true);
      this.toast('Sortiert nach ' + { farbe: 'Farbe', wert: 'Wert', punkte: 'Punkten' }[e.sort], 'leise', 1200);
    },
    sortModus() { return this.einstellungen.sort; },
    rueckseiten() {
      const t = this.tisch;
      if (!t) return;
      const an = !t.hand.rueck;
      t.hand.zeigeRueck(an);
      t.knRueck.classList.toggle('aktiv', an);
      clearTimeout(this._rueckTimer);
      if (an) {
        t.hand.waehle(null);
        this.toast('So sehen die anderen deine Karten', 'leise', 1800);
        this._rueckTimer = setTimeout(() => { if (t.hand.rueck) { t.hand.zeigeRueck(false); t.knRueck.classList.remove('aktiv'); } }, 6000);
      }
    },
    vibrieren(muster) {
      if (!this.einstellungen.vibration || !navigator.vibrate) return;
      try { navigator.vibrate(muster); } catch (e) { /* egal */ }
    },
    effekteReduziert() { return this.einstellungen.effekte === 'reduziert'; },
    // nach jedem Abgleich durch die Regie
    nachZeigen(v) {
      const h = v.hints || {};
      if (this.schwebend !== null && !(v.hand || []).some(c => c.id === this.schwebend)) this.schwebend = null;
      if (h.need_color && v.turn === v.seat && !this.tisch.farbwahlOffen && this._farbAuto !== v.round + ':' + (v.top && v.top.id)) {
        this._farbAuto = v.round + ':' + (v.top && v.top.id);
        this._farbwunsch();
      }
      if (!h.need_color && this.tisch.farbwahlOffen && this.tisch.hand.gewaehlt === null) this.tisch.schliesseFarbwahl();
      if (v.phase === 'round_over' || v.phase === 'game_over') this.zeigeRunde(v); else this.schliesse('runde');
      this._szene(v);
    },
    // Kontrollbilder: Zustände per URL herstellen (nur im Testmodus)
    _szene(v) {
      const s = params.get('szene');
      if (!s || this._szeneErledigt || !params.get('mock')) return;
      this._szeneErledigt = true;
      const K = M.Karten;
      setTimeout(() => {
        const hand = v.hand || [];
        if (s === 'farbwahl') { const j = hand.find(c => K.istJoker(c.face)); if (j) this.spielen(j.id); }
        else if (s === 'hilfe') { const c = hand.find(c => K.zerlege(c.face).art !== 'zahl') || hand[0]; if (c) this.hilfe(c.face); }
        else if (s === 'rueckseiten') this.rueckseiten();
        else if (s === 'menue') this.menue();
        else if (s === 'gegner') { const p = (v.players || []).find(x => x.seat !== v.seat); if (p) this.gegnerAnsicht(p.seat); }
        else if (s === 'gewaehlt' || s === 'tisch') { const id = (v.hints.playable || [])[0]; if (id !== undefined && s === 'gewaehlt') this.tisch.hand.waehle(id); }
      }, 60);
    },

    /* ---------------- Fenster ---------------- */
    oeffne(id) { const m = $('#' + id); m.hidden = false; m.classList.remove('auf'); void m.offsetWidth; m.classList.add('auf'); },
    schliesse(id) { const m = $('#' + id); if (m) m.hidden = true; },
    hilfe(face) {
      const h = M.Karten.hilfe(face, this.view && this.view.rules);
      $('#hilfe-karte').innerHTML = M.Karten.gesichtHTML(face);
      $('#hilfe-titel').textContent = h.titel;
      $('#hilfe-text').innerHTML = h.zeilen.map(z => '<p>' + esc(z) + '</p>').join('');
      this.oeffne('hilfe');
      this.vibrieren(15);
    },
    gegnerAnsicht(seat) {
      const v = this.view;
      const p = v && (v.players || []).find(x => x.seat === seat);
      if (!p) return;
      if (!p.backs || !p.backs.length) { this.toast(p.name + ': ' + p.count + (p.count === 1 ? ' Karte' : ' Karten') + (v.rules && v.rules.backs_visible === false ? ' (Rückseiten verdeckt)' : '')); return; }
      $('#ansicht-titel').textContent = p.name + ' · ' + p.count + (p.count === 1 ? ' Karte' : ' Karten');
      $('#ansicht-karten').innerHTML = p.backs.map(f => '<div class="karte">' + M.Karten.gesichtHTML(f) + '</div>').join('');
      this.oeffne('ansicht');
    },
    zeigeRunde(v) {
      const spieler = v.players || [];
      const name = s => { const p = spieler.find(x => x.seat === s); return p ? p.name : 'Platz ' + (s + 1); };
      let r = Array.isArray(v.ranking) && v.ranking.length ? v.ranking : spieler.slice().sort((a, b) => a.count - b.count).map(p => p.seat);
      r = r.map((x, i) => (typeof x === 'object' && x) ? x : { seat: x, place: i + 1 });
      const punkte = r.some(x => x.points !== undefined || x.punkte !== undefined);
      const wertung = v.rules && v.rules.scoring === 'points500';
      $('#runde-titel').textContent = v.phase === 'game_over' ? 'Partie vorbei' : 'Runde ' + (v.round || 1) + ' vorbei';
      const erster = r[0] ? name(r[0].seat) : '';
      $('#runde-sieger').textContent = r[0] && r[0].seat === v.seat ? 'Mau-Mau! Du hast gewonnen.' : (erster ? erster + ' gewinnt.' : '');
      $('#runde-liste').innerHTML = r.map((x, i) => {
        const p = spieler.find(q => q.seat === x.seat) || {};
        const pts = x.points !== undefined ? x.points : x.punkte;
        return '<li class="' + (x.seat === v.seat ? 'ich' : '') + '"><span class="pl">' + (x.place || i + 1) + '.</span><span class="nm">' + esc(name(x.seat)) + '</span>' +
          (punkte ? '<span class="pk">' + ((x.place || i + 1) === 1 && i === 0 ? '+' : '') + (pts || 0) + ' Pkt.</span>' : '') + (wertung ? '<span class="ges">' + (p.score || 0) + '</span>' : '') + '</li>';
      }).join('');
      $('#runde-fuss').textContent = v.phase === 'game_over' ? 'Der Gastgeber kann eine neue Partie starten.' : 'Der Gastgeber startet die nächste Runde.';
      if ($('#runde').hidden) this.oeffne('runde');
    },
    menue() {
      const e = this.einstellungen;
      document.querySelectorAll('#menue button[data-set]').forEach(b => b.classList.toggle('an', e[b.dataset.set] === b.dataset.wert || String(e[b.dataset.set]) === b.dataset.wert));
      const el = document.documentElement;
      $('#zeile-vollbild').hidden = IST_IOS || !(el.requestFullscreen || el.webkitRequestFullscreen);
      $('#zeile-vibration').hidden = !navigator.vibrate;
      $('#menue-regeln').innerHTML = M.Karten.regelnText(this.view && this.view.rules).map(t => '<li>' + esc(t) + '</li>').join('');
      $('#menue-info').textContent = 'Mau-Mau Flip ' + this.version + ' · Browser · ' + this.name + (this.view ? ' · Platz ' + (this.view.seat + 1) : '');
      this.oeffne('menue');
    },
    einstellen(k, wert) {
      const e = this.einstellungen;
      if (k === 'vibration' || k === 'vollbild') wert = wert === 'true';
      if (k === 'vollbild') { this.vollbild(wert); if (wert) setTimeout(() => this._querSperren(), 300); }
      e[k] = wert;
      Speicher.set(k, wert);
      if (k === 'ton') { M.Ton.setzeStufe(wert); M.Ton.spiele('karte'); }
      if (k === 'effekte') document.body.classList.toggle('reduziert', wert === 'reduziert');
      this.menue();
    },
    toast(text, art, dauer) {
      const box = $('#toasts');
      const t = document.createElement('div');
      t.className = 'toast ' + (art || '');
      t.textContent = text;
      box.appendChild(t);
      while (box.children.length > 3) box.firstChild.remove();
      setTimeout(() => { t.classList.add('weg'); setTimeout(() => t.remove(), 400); }, dauer || 2600);
    },
    _startFehler(text) { const f = $('#start-fehler'); f.textContent = text; f.hidden = !text; },

    /* ---------------- Fehler an den Gastgeber ---------------- */
    _fehlerFangen() {
      let zahl = 0;
      M.meldeFehler = text => {
        const t = String(text).slice(0, 900);
        this.fehler.push(t);
        if (++zahl > 30) return;
        const msg = { t: 'log', text: '[web ' + VERSION + '] ' + t + ' | ' + ua.slice(0, 120) };
        if (!this.verbindung || !this.verbindung.offen || !this.sende(msg)) { this.logPuffer.push(msg); if (this.logPuffer.length > 10) this.logPuffer.shift(); }
      };
      window.addEventListener('error', e => M.meldeFehler((e.message || 'Fehler') + ' @' + String(e.filename || '').split('/').pop() + ':' + (e.lineno || 0) + ':' + (e.colno || 0)));
      window.addEventListener('unhandledrejection', e => { const r = e.reason; M.meldeFehler('Promise: ' + (r && (r.stack || r.message) || r)); });
    },
    _logLeeren() { while (this.logPuffer.length && this.sende(this.logPuffer[0])) this.logPuffer.shift(); },
  };

  M.App = App;
  M.Speicher = Speicher;
  function los() {
    const extra = [];
    if (params.get('mock')) extra.push(ladeSkript('mock.js'));
    if (params.get('autotest')) extra.push(ladeSkript('autotest.js'));
    Promise.all(extra).catch(e => App.toast(String(e), 'fehler')).then(() => App.init());
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', los); else los();
})(window.MMF = window.MMF || {});
