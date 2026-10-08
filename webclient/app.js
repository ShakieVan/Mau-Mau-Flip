/* Mau-Mau Flip – Browser-Client „Lite“: Ablauf (Startseite, Lobby, Tisch), Verbindung, Aktionen, Einstellungen.
 * Reines HTML/CSS/JS ohne Build-Schritt und ohne Secure-Context-APIs (läuft über http:// vom Gastgeber-Handy).
 * Testmodus: index.html?mock=1 (eingebauter Schein-Gastgeber), &autotest=1 (spielt selbst), &szene=… (Kontrollbilder).
 */
(function (M) {
  'use strict';

  const VERSION = '1.3.2';
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
    // ton = Mau-Ton (Aufnahmen, Standard normal), toene = übrige Spieltöne (Dateien aus sfx/, sonst synthetisch; Standard aus), stumm = Ton-Knopf in der Ecke
    // hervorheben = spielbare Karten hervorheben (persönliche Einstellung je Gerät, AGENTS.md Nr. 24; Standard an)
    // grosser_modus = großer Modus (Standard aus), zug_vibration = „Bei deinem Zug: Vibration“ (Standard an seit 1.2.1); beide je Gerät, wie App.settings
    einstellungen: { ton: 'normal', toene: 'aus', stumm: false, effekte: 'voll', sort: 'farbe', vibration: true, vollbild: true, hervorheben: true, schrift: 'normal', grosser_modus: false, zug_vibration: true, sprache: 'auto' },
    _mauZuletzt: {},       // „art:Platz“ → Zeitpunkt des letzten Mau-Tons (Entprellung)
    // Online-Spiel (docs/online/ENTWURF.md): ?r=CODE auf einer vom Vermittler ausgelieferten Seite. Vermittler = eigener Ursprung.
    online: false,         // ?r= vorhanden
    raum: '',              // normalisierter Raumcode „WORT-ZZ“ ('' = ungültig)
    _tokKey: 'token',      // Speicherschlüssel des Spieler-Tokens; online je Raumcode

    /* ---------------- Start ---------------- */
    init() {
      const e = this.einstellungen;
      // Sprache (Beta 1.2.2, i18n.js): auto = navigator.language, sonst de/en; zuerst, damit alles Weitere schon übersetzt erscheint
      e.sprache = Speicher.get('sprache', 'auto');
      M.I18n.setze(e.sprache);
      document.title = M.t('Mau-Mau Flip – Mitspielen');
      const roh = params.get('r');
      this.online = !!roh && !params.get('mock');
      this.raum = this.online ? M.Netz.Online.code(roh) : '';
      this._tokKey = this.online ? 'token:' + (this.raum || '-') : 'token';
      e.ton = Speicher.get('ton', 'normal');
      e.toene = Speicher.get('toene', 'aus');
      e.stumm = Speicher.get('stumm', false) === true;
      const reduziert = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
      e.effekte = Speicher.get('effekte', reduziert ? 'reduziert' : 'voll');
      e.sort = Speicher.get('sort', 'farbe');
      e.vibration = Speicher.get('vibration', true);
      e.vollbild = Speicher.get('vollbild', true);
      e.hervorheben = Speicher.get('hervorheben', true) !== false;
      e.schrift = params.get('schrift') || Speicher.get('schrift', 'normal');   // ?schrift=… nur für Kontrollbilder
      this._schrift(e.schrift);
      e.grosser_modus = params.get('gross') ? params.get('gross') === '1' : Speicher.get('grosser_modus', false) === true;   // ?gross=1 für Test und Kontrollbilder
      e.zug_vibration = Speicher.get('zug_vibration', true) !== false;   // ab Werk an (Nutzerentscheidung 1.2.1), wirkt nur mit navigator.vibrate
      this._gross(e.grosser_modus);
      M.Ton.setzeStufe(e.ton);
      M.Ton.setzeToene(e.toene);
      M.Ton.setzeStumm(e.stumm);
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
      this._appLink();
      $('#tipp-safari').hidden = !IST_IOS;
      $('#tipp-ios-browser').hidden = !(IST_IOS && !IST_SAFARI);
      this._startTexte();
      if (location.protocol === 'file:' && !params.get('mock')) this._startFehler(M.t('Diese Seite kommt vom Gastgeber-Handy. Zum Ausprobieren ohne Gastgeber: index.html?mock=1'));
      if (this.online) { this._onlineStart(); return; }
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
            this._hostZeile = { name: info.name, n };
            this._startTexte();
          }
        }).catch(() => clearTimeout(t));
      } else if (params.get('mock')) { this._hostZeile = { name: 'Lena', mock: true }; this._startTexte(); }
    },
    // Online-Start: Raumcode prüfen, beim Vermittler nach Gastgeber und Spielversion fragen (/info?room=CODE).
    // Hier ist /info die Antwort des Vermittlers und nie die eines Gastgeber-Handys (kein name/players am Wurzelobjekt).
    _onlineStart() {
      if (!this.raum) {
        this._startFehler(M.t('Der Raumcode stimmt nicht. Er sieht so aus: KATZE-42.'));
        $('#beitreten').disabled = true;
        return;
      }
      this._hostZeile = { name: '', raum: this.raum };
      this._startTexte();
      if (!window.fetch || !/^https?:/.test(location.protocol)) return;
      const ctl = window.AbortController ? new AbortController() : null;
      const t = setTimeout(() => ctl && ctl.abort(), 5000);
      fetch(M.Netz.Online.infoUrl(this.raum), ctl ? { signal: ctl.signal, cache: 'no-store' } : { cache: 'no-store' }).then(r => (r.ok ? r.json() : null)).then(info => {
        clearTimeout(t);
        const r = info && info.room;
        if (!r) return;
        if (r.open === false) { this._startFehler(M.t('Raum nicht gefunden. Prüfe den Raumcode oder frage den Gastgeber.')); return; }
        if (r.version) this.version = String(r.version);   // der Gastgeber verlangt genau seine Version (check_hello)
        // room.host ist beim Vermittler nur „Gastgeber verbunden ja/nein“ (er kennt keine Namen); einen Namen gibt es erst mit „welcome“
        if (typeof r.host === 'string' && r.host) { this.hostName = r.host; this._hostZeile.name = this.hostName; }
        this._startTexte();
      }).catch(() => clearTimeout(t));
    },
    // Startseite: Texte, die der Code setzt (Knopf, Gastgeber-Zeile); bei Sprachwechsel neu
    _startTexte() {
      const k = $('#beitreten');
      if (k && !k.disabled) k.textContent = (Speicher.get(this._tokKey, null) && $('#name').value) ? M.t('Weiterspielen') : M.t('Beitreten');
      const h = this._hostZeile;
      if (h && h.raum) {
        $('#start-host').textContent = M.t('Raum %s', h.raum) + (h.name ? ' · ' + M.t('Spiel von %s', h.name) : '');
      } else if (h) {
        let s = M.t('Spiel von %s', h.name);
        if (h.mock) s += ' · ' + M.t('Testmodus');
        else if (h.n) s += ' · ' + (h.n === 1 ? M.t('1 Spieler') : M.t('%d Spieler', h.n));
        $('#start-host').textContent = s;
      }
    },
    // „In der App spielen“ (nur Android, AGENTS.md 1.0.2): Intent-Link öffnet die App mit maumauflip://join?h=<IP>&p=<Port>;
    // fehlt sie, schickt Chrome auf diese Seite mit ?app=1 zurück → APK-Bereich aufgeklappt mit Hinweis.
    _appLink() {
      const h = location.hostname, p = location.port || (location.protocol === 'https:' ? '443' : '80');
      const geht = IST_ANDROID && /^https?:/.test(location.protocol) && !!h;
      $('#app-spielen').hidden = !geht;
      if (geht && this.online) {
        // Online: App-Link mit Raumcode und Vermittler (maumauflip://join?r=&v=); die APK gibt es dann bei GitHub (der Vermittler hat keine)
        $('#app-spielen').hidden = !this.raum;
        if (this.raum) $('#app-link').href = M.Netz.Online.appIntent(location, this.raum);
        const apk = $('#apk-knopf');
        apk.href = M.Netz.Online.GITHUB_RELEASES;
        apk.removeAttribute('download');
        apk.target = '_blank';
        apk.rel = 'noopener';
      } else if (geht) {
        const zurueck = 'http://' + h + ':' + p + '/?app=1';
        $('#app-link').href = 'intent://join?h=' + encodeURIComponent(h) + '&p=' + p + '#Intent;scheme=maumauflip;package=de.maumauflip.game;S.browser_fallback_url='
          + encodeURIComponent(zurueck) + ';end';
      }
      const aufklappen = () => {
        if ($('#apk').hidden) return;
        $('#apk-hinweis').hidden = false;
        $('#apk-anleitung').open = true;
        $('#apk').classList.add('auf');
        setTimeout(() => { try { $('#apk').scrollIntoView({ block: 'start' }); } catch (e) { $('#apk').scrollIntoView(); } }, 120);
      };
      $('#app-hier').addEventListener('click', ev => { ev.preventDefault(); aufklappen(); });
      if (params.get('app') === '1') aufklappen();
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
        ['hilfe', 'ansicht', 'menue', 'runde', 'regeln', 'sogehts'].forEach(id => this.schliesse(id));
      });
      // Lobby
      $('#bereit').addEventListener('click', ev => { ev.preventDefault(); this.bereit(); });
      $('#ende-zurueck').addEventListener('click', ev => { ev.preventDefault(); location.reload(); });
      $('#verbinde-laden').addEventListener('click', ev => { ev.preventDefault(); location.reload(); });
      // Fenster schließen
      document.querySelectorAll('.modal').forEach(m => m.addEventListener('click', ev => {
        if (ev.target === m || ev.target.closest('.schliessen')) { ev.preventDefault(); this.schliesse(m.id); }
      }));
      // Schriftgröße auch auf Start und Lobby (dieselbe Einstellung wie im Menü)
      document.querySelectorAll('.schrift-wahl').forEach(w => w.addEventListener('click', ev => {
        const b = ev.target.closest('button[data-schrift]');
        if (!b) return;
        ev.preventDefault();
        this.einstellungen.schrift = b.dataset.schrift; Speicher.set('schrift', b.dataset.schrift); this._schrift(b.dataset.schrift);
      }));
      document.querySelectorAll('.gross-wahl').forEach(w => w.addEventListener('click', ev => {
        const b = ev.target.closest('button[data-gross]');
        if (!b) return;
        ev.preventDefault();
        const an = b.dataset.gross === 'true';
        this.einstellungen.grosser_modus = an; Speicher.set('grosser_modus', an); this._gross(an);
      }));
      $('#menue').addEventListener('click', ev => {
        const b = ev.target.closest('button[data-set]');
        if (b) { ev.preventDefault(); this.einstellen(b.dataset.set, b.dataset.wert); return; }
        if (ev.target.closest('#menue-neu')) { ev.preventDefault(); this.schliesse('menue'); if (this.verbindung) this.verbindung.neuVerbinden(); }
        if (ev.target.closest('#menue-regeln')) { ev.preventDefault(); this.regeln(); }
        if (ev.target.closest('#menue-sogehts')) { ev.preventDefault(); this.schliesse('menue'); this.oeffne('sogehts'); }
      });
    },
    groesse() {
      const vv = window.visualViewport;
      const vw = Math.round(vv ? vv.width : window.innerWidth), vh = Math.round(vv ? vv.height : window.innerHeight);
      document.documentElement.style.setProperty('--vh', vh + 'px');
      document.documentElement.style.setProperty('--vw', vw + 'px');
      document.body.classList.toggle('hoch', vw < vh);
      // Unpassendes Fenster (hoch oder fast quadratisch): Tisch in einem Rahmen mit Bühnenproportion (1180 × 720) nach der
      // Fensterbreite, darunter im Überstand ein dezenter Hinweis. Rahmen und Hinweis zusammen stehen mittig.
      const rahmen = vw / vh < 1.3;
      let th = vh, oben = 0, rest = 0;
      if (rahmen) {
        th = Math.round(vw * 720 / 1180);
        const frei = vh - th, hh = Math.min(frei, 150);
        oben = Math.round((frei - hh) / 2); rest = hh;
      }
      const de = document.documentElement.style;
      de.setProperty('--rahmen-oben', oben + 'px'); de.setProperty('--rahmen-h', th + 'px'); de.setProperty('--rahmen-rest', rest + 'px');
      document.body.classList.toggle('rahmen', rahmen);
      document.body.classList.toggle('rahmen-hinweis', rahmen && rest >= 56);
      document.body.classList.toggle('grob', !!(window.matchMedia && matchMedia('(pointer: coarse)').matches));
      if (this.tisch) {
        const cs = getComputedStyle($('#sicher'));
        const links = rahmen ? 0 : parseFloat(cs.paddingLeft) || 0, rechts = rahmen ? 0 : parseFloat(cs.paddingRight) || 0;
        this.tisch.groesse(vw, th, links, rechts);
      }
    },
    zeigeScreen(name) {
      this.screen = name;
      document.body.dataset.screen = name;
      if (name === 'tisch') this._querSperren();
      if (name === 'tisch' && !this.tisch) {
        this.tisch = new M.Tisch.Tisch($('#tisch'), this);
        this.tisch.setzeGross(this.einstellungen.grosser_modus);
        this.groesse();
      }
      if (name !== 'tisch') ['hilfe', 'ansicht', 'runde', 'regeln', 'sogehts'].forEach(id => this.schliesse(id));
      this.themaFarbe();
    },
    // Browserleiste (theme-color): am Tisch nach Tag/Nacht (Tisch.themaFarbe), sonst Nachtblau wie Start und Lobby
    themaFarbe() {
      const m = document.querySelector('meta[name="theme-color"]');
      const f = this.screen === 'tisch' && this.tisch && this.tisch.root.dataset.seite ? this.tisch.themaFarbe() : '#0C0F22';
      if (m && m.getAttribute('content') !== f) m.setAttribute('content', f);
      document.body.classList.toggle('tag', f === '#E6D7BC');   // leise Hinweise: am Tag dunkel, nachts hell (style.css .toast.leise)
    },

    /* ---------------- Verbindung ---------------- */
    beitreten(vorgabe) {
      const feld = $('#name');
      if (vorgabe) feld.value = vorgabe;
      const name = feld.value.replace(/\s+/g, ' ').trim().slice(0, 14);   // Gastgeber kürzt auf 14 (NetProtocol.MAX_NAME)
      if (!name) { this._startFehler(M.t('Bitte gib deinen Namen ein.')); feld.focus(); return; }
      this.name = name;
      Speicher.set('name', name);
      this._startFehler('');
      M.Ton.freischalten();
      if (IST_ANDROID && this.einstellungen.vollbild) this.vollbild(true);
      this.wachStart();
      const knopf = $('#beitreten');
      knopf.disabled = true; knopf.textContent = M.t('Verbinde …');
      if (this.verbindung) this.verbindung.beenden();
      const Klasse = params.get('mock') && M.Mock ? M.Mock.Verbindung : M.Netz.Verbindung;
      if (this.online && !this.raum) { knopf.disabled = true; return; }
      const online = this.online && !params.get('mock');
      const url = online ? M.Netz.Online.wsUrl(location, this.raum) : (location.protocol === 'https:' ? 'wss://' : 'ws://') + location.host + '/ws';
      this.verbindung = new Klasse({
        url,
        online,
        hallo: () => {
          const h = { t: 'hello', proto: PROTO, game: this.version, name: this.name, kind: 'web' };
          const tok = Speicher.get(this._tokKey, null);
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
      const weg = s === 'host_weg';   // online: Gastgeber kurz weg (Vermittler-Code 4503)
      const zeigen = (s === 'getrennt' || weg) && this.beigetreten;
      v.hidden = !zeigen;
      ['verbinde-titel', 'verbinde-unter'].forEach(id => { $('#' + id).hidden = weg; });
      ['verbinde-weg-titel', 'verbinde-weg'].forEach(id => { $('#' + id).hidden = !weg; });
      if (zeigen) {
        clearTimeout(this._ladeTimer);
        $('#verbinde-laden').hidden = true;
        this._ladeTimer = setTimeout(() => { $('#verbinde-laden').hidden = false; }, 15000);
      } else clearTimeout(this._ladeTimer);
      if (s === 'getrennt' && !this.beigetreten && this.screen === 'start') {
        this._startFehler(this.online ? M.t('Keine Verbindung zum Vermittler. Hast du Internet? Ich versuche es weiter …')
          : M.t('Keine Verbindung zum Gastgeber. Seid ihr im selben WLAN? Ich versuche es weiter …'));
      }
      if (weg && !this.beigetreten && this.screen === 'start') this._startFehler(M.t('Der Gastgeber ist kurz weg. Ich versuche es in 10 Sekunden erneut …'));
      // endgültige Schließcodes des Vermittlers: Raum unbekannt (4404), voll (4409), beendet (1001)
      const ende = { kein_raum: M.t('Raum nicht gefunden. Prüfe den Raumcode oder frage den Gastgeber.'), voll: M.t('Der Raum ist voll.'), raum_ende: M.t('Der Gastgeber hat den Raum geschlossen.') }[s];
      if (ende) this._raumEnde(ende, s !== 'voll');
      if (s === 'offen') { this._logLeeren(); if (this.screen === 'start') this._startFehler(''); }
      if (s === 'ersetzt') {
        this.beigetreten = false;
        v.hidden = true;
        $('#ende-text').textContent = M.t('Du spielst jetzt in einem anderen Fenster oder Tab weiter. Hier ist die Verbindung beendet.');
        this.zeigeScreen('ende');
      }
    },
    // Raum weg/voll/geschlossen: Verbindung beenden, zurück auf die Startseite mit Erklärung; Token nur löschen, wenn der Raum nicht mehr da ist
    _raumEnde(text, tokenLoeschen) {
      if (this.verbindung) this.verbindung.beenden();
      if (tokenLoeschen) Speicher.set(this._tokKey, null);
      this.beigetreten = false;
      $('#verbinde').hidden = true;
      if (this.screen !== 'start') this.zeigeScreen('start');
      $('#beitreten').disabled = false; this._startTexte();
      this._startFehler(text);
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
          if (m.token) Speicher.set(this._tokKey, m.token);
          if (m.host_name) this.hostName = m.host_name;
          this.beigetreten = true;
          $('#beitreten').disabled = false; this._startTexte();
          if (this.screen === 'start') { this.zeigeScreen('lobby'); this._lobbyLeer(); }
          break;
        case 'reject': {
          const texte = { version: M.t('Die Version passt nicht zum Gastgeber. Bitte die Seite neu laden.'), full: M.t('Das Spiel ist voll.'), running: M.t('Die Partie läuft schon. Warte, bis die nächste beginnt.'), proto: M.t('Der Gastgeber spricht ein anderes Protokoll. Bitte die Seite neu laden.') };
          if (this._tokenGesendet && (m.code === 'running' || m.code === 'token')) Speicher.set(this._tokKey, null);
          this.verbindung.beenden();
          this.beigetreten = false;
          $('#verbinde').hidden = true;
          this.zeigeScreen('start');
          $('#beitreten').disabled = false; this._startTexte();
          this._startFehler(M.I18n.msgText(m, texte[m.code] || M.t('Der Gastgeber hat abgelehnt.')));   // eigene Sprache (Bausteine lt bzw. msgid)
          break;
        }
        case 'lobby': {
          this.lobby = m;
          // Der Gastgeber (NetHostSession) verteilt Lobby-Stände nur, solange keine Partie läuft. Kommt einer am Tisch an,
          // ist die Partie vorbei (set_running(false)) → zurück in die Lobby.
          if (this.screen !== 'lobby') {
            this.zeigeScreen('lobby');
            this.view = null;
            if (this.tisch) { this.tisch.ablageVerlauf = []; this.tisch.v = null; }
          }
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
          this.toast(M.I18n.msgText(m, M.t('Das geht gerade nicht.')), 'fehler');
          M.Ton.spiele('fehler');
          this.vibrieren([20, 50, 20]);
          if (this.schwebend !== null && this.tisch) { this.tisch.hand.schwebe(this.schwebend, false); this.tisch.hand.wackeln(this.schwebend); this.schwebend = null; }
          if (this.tisch && this.view && this.view.phase === 'gamble' && this.tisch.regie.leer) this.tisch.zeige(this.view, true);   // Glücksspielknopf wieder frei
          if (M.Autotest && M.Autotest.fehlerNachricht) M.Autotest.fehlerNachricht(m);
          break;
        case 'notice':     // Hinweis des Gastgebers an alle (HostTable), z. B. „Kim ist getrennt – warte …“
          if (m.text || m.lt) this.toast(M.I18n.msgText(m), 'leise', 3200);
          break;
        case 'pong':
          if (m.ts) this.latenz = Date.now() - m.ts;
          break;
        case 'bye':
          this.verbindung.beenden();
          this.beigetreten = false;
          Speicher.set(this._tokKey, null);
          $('#verbinde').hidden = true;
          $('#ende-text').textContent = M.I18n.msgText(m, M.t('Der Gastgeber hat das Spiel beendet.'));
          this.zeigeScreen('ende');
          break;
        default: break;
      }
    },
    sende(obj) { return this.verbindung ? this.verbindung.sende(obj) : false; },

    /* ---------------- Lobby ---------------- */
    _lobbyLeer() {
      $('#lobby-host').textContent = this.hostName ? M.t('Spiel von %s', this.hostName) : M.t('Verbunden');
      $('#lobby-liste').innerHTML = '<li class="lz leer">' + M.t('Warte auf die Spielerliste …') + '</li>';
    },
    zeigeLobby(l) {
      $('#lobby-host').textContent = this.hostName ? M.t('Spiel von %s', this.hostName) : M.t('Lobby');
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
          '<span class="nm">' + esc(p.name) + (istIch ? ' <em>(' + M.t('du') + ')</em>' : '') + '</span>' +
          '<span class="art">' + esc(M.t(ART[p.kind] || p.kind || '')) + '</span>' +
          (host ? '<span class="marke gast">' + M.t('Gastgeber') + '</span>' : '') +
          (p.connected === false ? '<span class="marke weg">' + M.t('getrennt') + '</span>' : '<span class="status ' + (bereit ? 'ja' : '') + '">' + (bereit ? M.t('bereit') : M.t('wartet')) + '</span>') +
          '</li>';
      }).join('') || '<li class="lz leer">' + M.t('Noch niemand da.') + '</li>';
      const k = $('#bereit');
      const bereit = !!(ich && ich.ready);
      k.textContent = bereit ? M.t('Bereit ✓') : M.t('Bereit');
      k.classList.toggle('an', bereit);
      $('#lobby-status').textContent = bereit ? M.t('Warte auf den Start durch den Gastgeber …') : M.t('Tippe auf „Bereit“, wenn du startklar bist.');
      $('#lobby-regeln').innerHTML = M.Karten.regelnText(l.rules).map(t => '<li>' + esc(t) + '</li>').join('');
      $('#lobby-zahl').textContent = spieler.length === 1 ? M.t('1 Spieler') : M.t('%d Spieler', spieler.length);
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
      if (a.a === 'ablegen') { this.ablegenBestaetigen(); return; }
      this._sendeAkt(a);
    },
    _sendeAkt(a) {
      this.seq++;
      const ok = this.sende({ t: 'act', seq: this.seq, a });
      if (!ok) { this.toast(M.t('Keine Verbindung – ich verbinde neu …'), 'fehler'); this.verbindung.wecken(); return false; }
      this.offen = { seq: this.seq, zeit: Date.now(), a };
      clearTimeout(this._antwortTimer);
      const seq = this.seq;
      this._antwortTimer = setTimeout(() => {
        if (this.offen && this.offen.seq === seq) {
          this.offen = null;
          if (this.schwebend !== null && this.tisch) { this.tisch.hand.schwebe(this.schwebend, false); this.schwebend = null; }
          this.toast(M.t('Keine Antwort vom Gastgeber – ich verbinde neu …'), 'fehler');
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
      if (this.imAblegen()) { this.pickTipp(id); return; }
      // Glücksspiel: Im eigenen Glücksspiel setzt ein Tipp die Karte verdeckt (welche, ist fast egal: alle kommen zurück oder unter die Ablage)
      if (this.imGluecksspiel()) { this.setzen(id); return; }
      if (t.hand.gewaehlt === id) { this.spielen(id); return; }
      t.hand.waehle(id);
    },
    spielen(id) {
      const v = this.view, t = this.tisch;
      if (!v || !t) return;
      if (t.hand.rueck) { this.rueckseiten(); return; }
      const c = (v.hand || []).find(h => h.id === id);
      if (!c) return;
      if (this.imGluecksspiel()) { this.setzen(id); return; }
      if (this.imAblegen()) { this.pickTipp(id); return; }
      const h = v.hints || {};
      // Legen geht in „turn“ und „drawn“, mit Stapeln (stacking=same) auch in „challenge“ (dann steht die Karte in hints.playable)
      const legbar = v.turn === v.seat && (v.phase === 'turn' || v.phase === 'drawn' || (v.phase === 'challenge' && (h.playable || []).length > 0));
      if (!legbar) {
        t.hand.wackeln(id);
        this.toast(v.phase === 'challenge' && h.can_challenge ? M.t('Erst anzweifeln oder annehmen.') : (h.need_color ? M.t('Erst die Farbe wählen.') : M.t('Warte, bis du dran bist.')));
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
      // hints.wild: spielbare Karten, die eine Farbe brauchen (Gastgeber); Rückfall: am Gesicht erkennen
      if (Array.isArray(h.wild) ? h.wild.indexOf(id) >= 0 : M.Karten.istJoker(c.face)) {
        t.hand.waehle(id);
        t.oeffneFarbwahl(v.side, this.zaehleFarben(v, id), farbe => {
          if (farbe) this._spieleKarte(id, farbe);
          else if (this.tisch) this.tisch.hand.waehle(null);
        }, M.Karten.zerlege(c.face).art === 'ablegen_joker' ? M.t('Welche Farbe legst du mit ab?') : null);
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
      if (v.phase === 'drawn') return this.beliebigNachZiehen(v) ? M.t('Passt nicht – leg eine passende Karte oder tippe auf „Behalten“.') : M.t('Jetzt geht nur die gezogene Karte – oder „Behalten“.');
      if (v.phase === 'challenge') return M.t('Jetzt geht nur die gleiche Ziehkarte zum Weitergeben – oder anzweifeln bzw. annehmen.');
      if (v.pending && v.pending.kind) return M.t('Erst die Strafe: %s', M.I18n.msgText({ lt: (v.hints || {}).lt, text: (v.hints || {}).text }, M.t('ziehen oder weitergeben.')));
      // Ohne Hervorhebung (persönliche Einstellung) nur der schlichte Hinweis, ohne Tipp, was stattdessen passt
      if (!this.hervorheben()) return M.t('Die Karte passt nicht.');
      if (K.istJoker(c.face)) return M.t('Diesen Joker darfst du gerade nicht legen – du hast noch %s.', K.farbName(v.color));
      const top = v.top ? K.zerlege(v.top.face) : null;
      const passend = top && !K.istJoker(top.key) ? K.passendText(top.key) : '';
      if (passend) return M.t('Passt nicht – gefragt ist %s oder %s.', K.farbName(v.color), passend);
      return M.t('Passt nicht – gefragt ist %s.', K.farbName(v.color));
    },
    hervorheben() { return this.einstellungen.hervorheben !== false; },
    // Hausregel draw_play = "any": nach dem Ziehen darf jede passende Karte gelegt werden (hints.playable listet sie)
    beliebigNachZiehen(v) { return !!(v && v.rules && v.rules.draw_play === 'any'); },
    // Farbe mit ablegen (Phase discard_pick, ich wähle): Auswahl je Ablegen-Karte, alle Kandidaten (hints.can_pick) vorausgewählt
    imAblegen() { const v = this.view; return !!(v && v.phase === 'discard_pick' && v.discard_pick && v.discard_pick.seat === v.seat && v.seat >= 0); },
    pickAuswahl(v) {
      const kand = (v.hints || {}).can_pick || [];
      const key = v.round + ':' + (v.top && v.top.id);
      if (!this._pick || this._pick.key !== key) this._pick = { key, ab: new Set() };
      return kand.filter(id => !this._pick.ab.has(id));
    },
    pickTipp(id) {
      const v = this.view, t = this.tisch;
      if ((v.hints.can_pick || []).indexOf(id) < 0) {
        t.hand.wackeln(id);
        this.toast(M.t('Mit ablegen kannst du nur Karten in %s (keine Joker).', M.Karten.farbName(v.discard_pick.color)));
        return;
      }
      this.pickAuswahl(v);
      const ab = this._pick.ab;
      if (ab.has(id)) ab.delete(id); else ab.add(id);
      M.Ton.spiele('tipp');
      t.zeige(v, true);
    },
    ablegenBestaetigen() {
      const v = this.view, t = this.tisch;
      if (!this.imAblegen() || !t || this.offen) return;
      const karten = this.pickAuswahl(v);
      const h = v.hints || {};
      const joker = h.pick_color !== undefined ? !!h.pick_color : !!(v.top && M.Karten.zerlege(v.top.face).art === 'ablegen_joker');
      if (!joker) { this._sendeAkt({ a: 'discard_pick', cards: karten }); return; }
      // Ablegen-Joker: zum Schluss die Spielfarbe (Zählung ohne die mitabgelegten Karten)
      const z = {};
      (v.hand || []).forEach(c => { if (karten.indexOf(c.id) >= 0) return; const k = M.Karten.zerlege(c.face); if (k.farbe) z[k.farbe] = (z[k.farbe] || 0) + 1; });
      t.oeffneFarbwahl(v.side, z, farbe => { if (farbe && this.imAblegen()) this._sendeAkt({ a: 'discard_pick', cards: karten, color: farbe }); }, M.t('Mit welcher Farbe geht es weiter?'));
    },
    // eigenes Glücksspiel läuft (Phase gamble, ich bin dran)
    imGluecksspiel() { const v = this.view; return !!(v && v.phase === 'gamble' && v.turn === v.seat && v.seat >= 0); },
    // Glücksspiel: Karte verdeckt auf den Einsatz ({a:"stake", card}), nur mit hints.can_stake
    setzen(id) {
      const v = this.view, t = this.tisch;
      if (!v || !t) return;
      const h = v.hints || {};
      if ((Array.isArray(h.can_stake) ? h.can_stake : []).indexOf(id) < 0) {
        t.hand.wackeln(id);
        this.toast(h.can_press ? M.t('Erst den Glücksspielknopf drücken.') : M.t('Warte, bis du dran bist.'));
        return;
      }
      if (this.offen) return;
      if (!this._sendeAkt({ a: 'stake', card: id })) return;
      t.hand.gewaehlt = null;
      t.hand.schwebe(id, true);
      this.schwebend = id;
      this.vibrieren(15);
    },
    // Glücksspielknopf ({a:"press"}), nur mit hints.can_press
    druecken() {
      const v = this.view;
      if (!v || !this.tisch) return;
      const h = v.hints || {};
      if (h.can_press) {
        if (this.offen) return;
        this.tisch.knopfDruck();
        this.vibrieren(35);
        this._sendeAkt({ a: 'press' });
        return;
      }
      if (this.imGluecksspiel()) this.toast(h.can_stop ? M.t('Leg erst eine Karte verdeckt auf deinen Einsatz – oder hör auf.') : M.t('Leg erst eine Karte verdeckt auf deinen Einsatz – tipp sie an.'));
      else this.toast(M.t('Den Knopf drückt, wer gerade Glücksspiel spielt.'));
    },
    // Glücksspiel aufhören ({a:"stop"}), nur mit hints.can_stop (nach mindestens einem Druck ohne Treffer)
    aufhoeren() {
      const v = this.view;
      if (!v || !this.tisch) return;
      if (!(v.hints || {}).can_stop) { this.toast(M.t('Aufhören geht erst nach einem Druck ohne Treffer.')); return; }
      if (this.offen) return;
      if (!this._sendeAkt({ a: 'stop' })) return;
      this.tisch.stopGesendet();
      this.vibrieren(20);
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
      if (this.imAblegen()) this.toast(M.t('Wähl erst die Karten zum Mitablegen und tippe auf „Ablegen“.'));
      else if (this.imGluecksspiel()) this.toast(h.can_press ? M.t('Im Glücksspiel wird nicht gezogen – drück den Knopf.') : M.t('Im Glücksspiel wird nicht gezogen – setz eine Karte.'));
      else if (v.turn === v.seat && v.phase === 'drawn') this.toast(this.beliebigNachZiehen(v) ? M.t('Leg eine passende Karte oder tippe auf „Behalten“.') : M.t('Leg die gezogene Karte oder tippe auf „Behalten“.'));
      else if (v.turn === v.seat && h.can_challenge) this.toast(M.t('Erst anzweifeln oder annehmen.'));
      else if (v.turn !== v.seat) this.toast(M.t('Warte, bis du dran bist.'));
    },
    mau() {
      const v = this.view;
      if (!v || !this.tisch) return;
      const k = this.tisch.knMau;
      k.classList.remove('drueck'); void k.offsetWidth; k.classList.add('drueck');
      if ((v.hints || {}).can_mau) {
        // Kein Ton hier: Er kommt mit dem Ereignis „mau“ vom Gastgeber – auf allen Geräten gleichzeitig und nie doppelt.
        this.vibrieren(40);
        this._sendeAkt({ a: 'mau' });
      } else this.toast(M.t('„Mau!“ rufst du, wenn du dran bist und dir nach dem Legen nur noch eine Karte bleibt.'));
    },
    // Mau-Ton zum Ereignis (AGENTS.md Nr. 21: auf allen Geräten, außer der Ton ist hier aus). art = 'mau' | 'mau_mau'.
    // Entprellung je Platz und Art: höchstens ein Ton pro Sekunde (z. B. wenn ein Stand doppelt ankommt).
    // Rückgabe: true = Ton angestoßen, false = entprellt oder Ton aus.
    mauTon(seat, art) {
      art = art === 'mau_mau' ? 'mau_mau' : 'mau';
      const schluessel = art + ':' + seat, jetzt = Date.now();
      if (this._mauZuletzt[schluessel] && jetzt - this._mauZuletzt[schluessel] < 1000) return false;
      this._mauZuletzt[schluessel] = jetzt;
      this.mauEreignisse = (this.mauEreignisse || 0) + 1;
      return M.Ton.spiele(art);
    },
    // Ton-Knopf in der Ecke: alles stumm bzw. wieder an
    tonSchalter() {
      const e = this.einstellungen;
      M.Ton.freischalten();
      e.stumm = !e.stumm;
      Speicher.set('stumm', e.stumm);
      M.Ton.setzeStumm(e.stumm);
      if (this.tisch) this.tisch.zeigeTon();
      this.toast(e.stumm ? M.t('Ton aus – „Mau!“ siehst du weiter als Sprechblase.') : M.t('Ton an'), 'leise', 1600);
    },
    sortieren() {
      const reihe = ['farbe', 'wert', 'punkte'];
      const e = this.einstellungen;
      e.sort = reihe[(reihe.indexOf(e.sort) + 1) % reihe.length];
      Speicher.set('sort', e.sort);
      if (this.tisch && this.view) this.tisch.zeige(this.view, true);
      this.toast({ farbe: M.t('Sortiert nach Farbe'), wert: M.t('Sortiert nach Wert'), punkte: M.t('Sortiert nach Punkten') }[e.sort], 'leise', 1200);
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
        this.toast(M.t('So sehen die anderen deine Karten'), 'leise', 1800);
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
        else if (s === 'regeln') this.regeln();
        else if (s === 'sogehts') this.oeffne('sogehts');
        else if (s === 'gegner') { const p = (v.players || []).find(x => x.seat !== v.seat); if (p) this.gegnerAnsicht(p.seat); }
        else if (s === 'gewaehlt' || s === 'tisch') { const id = (v.hints.playable || [])[0]; if (id !== undefined && s === 'gewaehlt') this.tisch.hand.waehle(id); }
        else if (s === 'ablegejoker') { const j = hand.find(c => K.zerlege(c.face).art === 'ablegen_joker'); if (j) this.spielen(j.id); }
        else if (s === 'tausch' || s === 'ablegen') {
          const passt = c => K.zerlege(c.face).art === s && (v.hints.playable || []).indexOf(c.id) >= 0;
          const c = hand.find(passt) || hand.find(c => K.zerlege(c.face).art === s);
          if (c) this.spielen(c.id);
        }
        else if (s === 'blasen') {
          // alle Varianten der Mau-Blase auf einmal (eigener Platz zuerst; der letzte Gegner ruft „Mau-Mau!“); &variante= erzwingt eine
          const reihe = ['plopp', 'ohren', 'huepf', 'ballon', 'gummi', 'schlicht'];
          const plaetze = (v.players || []).map(p => p.seat);
          plaetze.forEach((seat, i) => this.tisch.mauBlase(seat, i === plaetze.length - 1 && i > 0 ? 'mau_mau' : 'mau', 60000, params.get('variante') || reihe[i % reihe.length]));
        }
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
    // „1 Karte“ / „5 Karten“ (Mehrzahl je Sprache)
    kartenText(n) { return n === 1 ? M.t('1 Karte') : M.t('%d Karten', n); },
    gegnerAnsicht(seat) {
      const v = this.view;
      const p = v && (v.players || []).find(x => x.seat === seat);
      if (!p) return;
      if (!p.backs || !p.backs.length) { this.toast(p.name + ': ' + this.kartenText(p.count) + (v.rules && v.rules.backs_visible === false ? ' ' + M.t('(Rückseiten verdeckt)') : '')); return; }
      $('#ansicht-titel').textContent = p.name + ' · ' + this.kartenText(p.count);
      $('#ansicht-karten').innerHTML = p.backs.map(f => '<div class="karte">' + M.Karten.gesichtHTML(f) + '</div>').join('');
      this.oeffne('ansicht');
    },
    // Rundenende nach view.result (MauGame): {ranking:[Plätze], points:[Restpunkte je Platz], gains:[Gewinn je Platz],
    // scores:[Stand je Platz], hands:[[Gesichter] je Platz], reason:"fertig"|"blockiert"}. Ältere Form: ranking als Liste.
    zeigeRunde(v) {
      const spieler = v.players || [];
      const res = (v.result && typeof v.result === 'object') ? v.result : {};
      const name = s => { const p = spieler.find(x => x.seat === s); return p ? p.name : M.t('Platz %d', s + 1); };
      let r = Array.isArray(res.ranking) && res.ranking.length ? res.ranking : (Array.isArray(v.ranking) && v.ranking.length ? v.ranking : spieler.slice().sort((a, b) => a.count - b.count).map(p => p.seat));
      r = r.map((x, i) => (typeof x === 'object' && x) ? x : { seat: x, place: i + 1 });
      const feld = (a, s) => (Array.isArray(a) && typeof a[s] === 'number') ? a[s] : undefined;
      const wertung = !!(v.rules && v.rules.scoring === 'points500' && v.rules.round_end !== 'last');
      const ich = v.seat;
      $('#runde-titel').textContent = v.phase === 'game_over' ? M.t('Partie vorbei') : M.t('Runde %d vorbei', res.round || v.round || 1);
      const erster = r[0] ? r[0].seat : -1;
      const vorn = res.reason === 'blockiert' ? M.t('Nichts geht mehr – ') : '';
      $('#runde-sieger').textContent = vorn + (erster === ich ? (v.phase === 'game_over' ? M.t('Du gewinnst die Partie!') : M.t('Mau-Mau! Du hast gewonnen.')) : (erster >= 0 ? (v.phase === 'game_over' ? M.t('%s gewinnt die Partie.', name(erster)) : M.t('%s gewinnt.', name(erster))) : ''));
      $('#runde-liste').innerHTML = r.map((x, i) => {
        const p = spieler.find(q => q.seat === x.seat) || {};
        const rest = feld(res.points, x.seat) !== undefined ? feld(res.points, x.seat) : (x.points !== undefined ? x.points : x.punkte);
        const gewinn = feld(res.gains, x.seat);
        const stand = feld(res.scores, x.seat) !== undefined ? feld(res.scores, x.seat) : (p.score || 0);
        const karten = Array.isArray(res.hands) && Array.isArray(res.hands[x.seat]) ? res.hands[x.seat].length : (p.count | 0);
        let pk = '';
        if (i === 0 && wertung && gewinn) pk = M.t('+%d Pkt.', gewinn);
        else if (karten) pk = this.kartenText(karten) + (rest !== undefined ? ' · ' + M.t('%d Pkt.', rest) : '');
        else if (i > 0) pk = M.t('fertig');     // „bis zum Letzten“: schon ausgeschieden
        const ges = wertung ? stand : (stand ? (stand === 1 ? M.t('1 Sieg') : M.t('%d Siege', stand)) : '');
        return '<li class="' + (x.seat === ich ? 'ich' : '') + '"><span class="pl">' + (x.place || i + 1) + '.</span><span class="nm">' + esc(name(x.seat)) + '</span>' +
          (pk ? '<span class="pk">' + esc(pk) + '</span>' : '') + (ges !== '' ? '<span class="ges">' + esc(ges) + '</span>' : '') + '</li>';
      }).join('');
      const weiter = !!((v.hints || {}).can_next_round) && v.phase === 'round_over';
      const kw = $('#runde-weiter');
      if (kw) {
        kw.hidden = !weiter;
        kw.onclick = ev => { ev.preventDefault(); kw.disabled = true; this._sendeAkt({ a: 'next_round' }); setTimeout(() => { kw.disabled = false; }, 1500); };
      }
      $('#runde-fuss').textContent = v.phase === 'game_over' ? M.t('Der Gastgeber kann eine neue Partie starten.') : (weiter ? M.t('Du startest die nächste Runde.') : (this.hostName ? M.t('%s startet die nächste Runde.', this.hostName) : M.t('Der Gastgeber startet die nächste Runde.')));
      if ($('#runde').hidden) this.oeffne('runde');
    },
    menue() {
      const e = this.einstellungen;
      document.querySelectorAll('#menue button[data-set]').forEach(b => b.classList.toggle('an', e[b.dataset.set] === b.dataset.wert || String(e[b.dataset.set]) === b.dataset.wert));
      const el = document.documentElement;
      $('#zeile-vollbild').hidden = IST_IOS || !(el.requestFullscreen || el.webkitRequestFullscreen);
      $('#zeile-vibration').hidden = !navigator.vibrate;
      $('#zeile-zugvib').hidden = !navigator.vibrate;
      $('#menue-gross-tipp').hidden = !(e.schrift === 'sehr_gross' && !e.grosser_modus);
      $('#menue-stumm').hidden = !e.stumm;
      $('#menue-info').textContent = this._menueInfo();
      this.oeffne('menue');
    },
    _menueInfo() { return 'Mau-Mau Flip ' + this.version + ' · ' + M.t('Browser') + ' · ' + this.name + (this.view ? ' · ' + M.t('Platz %d', this.view.seat + 1) : ''); },
    // „Regeln“ im Spielmenü: aktive Regeln und besondere Karten (nur lesen, Partie läuft weiter)
    regeln() {
      const r = this.view && this.view.rules;
      $('#regeln-liste').innerHTML = M.Karten.regelnText(r).map(t => '<li>' + esc(t) + '</li>').join('');
      $('#regeln-karten').innerHTML = M.Karten.besondereKarten(r).map(g => '<h4>' + esc(g.titel) + '</h4>' + (g.hinweis ? '<p class="klein">' + esc(g.hinweis) + '</p>' : '')
        + '<div class="rk-reihe">' + g.karten.map(k => '<div class="rk"><div class="rk-bild">' + M.Karten.gesichtHTML(k.key) + '</div><div class="rk-text"><b>' + esc(k.name) + '</b>'
          + k.zeilen.map(z => '<span>' + esc(z) + '</span>').join('') + '</div></div>').join('') + '</div>').join('');
      this.schliesse('menue');
      this.oeffne('regeln');
      $('#regeln .modal-karte').scrollTop = 0;
    },
    einstellen(k, wert) {
      const e = this.einstellungen;
      if (k === 'vibration' || k === 'vollbild' || k === 'hervorheben' || k === 'grosser_modus' || k === 'zug_vibration') wert = wert === 'true';
      if (k === 'vollbild') { this.vollbild(wert); if (wert) setTimeout(() => this._querSperren(), 300); }
      e[k] = wert;
      Speicher.set(k, wert);
      if ((k === 'ton' || k === 'toene') && wert !== 'aus' && e.stumm) {   // wer eine Lautstärke wählt, will Ton
        e.stumm = false; Speicher.set('stumm', false); M.Ton.setzeStumm(false);
        if (this.tisch) this.tisch.zeigeTon();
      }
      if (k === 'ton' || k === 'toene') M.Ton.freischalten();
      if (k === 'ton') { M.Ton.setzeStufe(wert); M.Ton.spiele('mau'); }        // Probehören: die Aufnahme
      if (k === 'toene') { M.Ton.setzeToene(wert); M.Ton.spiele('karte'); }
      if (k === 'effekte') document.body.classList.toggle('reduziert', wert === 'reduziert');
      if (k === 'hervorheben' && this.tisch && this.view) this.tisch.zeige(this.view, true);
      if (k === 'schrift') { this._schrift(wert); if (this.tisch && this.view) this.tisch.zeige(this.view, true); }
      if (k === 'grosser_modus') this._gross(wert);
      if (k === 'zug_vibration' && wert) this.zugVibration();   // zum Ausprobieren
      if (k === 'sprache') M.I18n.setze(wert);   // Hörer unten bauen Dynamisches neu
      this.menue();
    },
    // Schriftgröße je Gerät: html[data-schrift] setzt --fs (style.css); Kartenbilder bleiben gleich
    _schrift(w) {
      if (['normal', 'gross', 'sehr_gross'].indexOf(w) < 0) w = 'normal';
      document.documentElement.dataset.schrift = w;
      document.querySelectorAll('.schrift-wahl button[data-schrift]').forEach(b => b.classList.toggle('an', b.dataset.schrift === w));
    },
    // Großer Modus je Gerät: Tisch mit riesigem Stapel und Ablage, Spielerliste rechts (tisch.js setzeGross)
    _gross(an) {
      an = !!an;
      document.documentElement.classList.toggle('gross', an);
      document.querySelectorAll('.gross-wahl button[data-gross]').forEach(b => b.classList.toggle('an', b.dataset.gross === String(an)));
      if (this.tisch) this.tisch.setzeGross(an);
    },
    // „Bei deinem Zug: Vibration“ (eigene Einstellung, unabhängig von „Vibration“; nur wo navigator.vibrate da ist)
    zugVibration() {
      if (!this.einstellungen.zug_vibration || !navigator.vibrate) return;
      try { navigator.vibrate([70, 60, 70]); } catch (e) { /* egal */ }
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

  // Sprachwechsel: alles Dynamische neu beschriften (Titel, Startseite, Lobby, Tisch, offene Fenster)
  M.I18n.beiWechsel(() => {
    document.title = M.t('Mau-Mau Flip – Mitspielen');
    App._startTexte();
    if (App.lobby && App.screen === 'lobby') App.zeigeLobby(App.lobby);
    else if (App.screen === 'lobby') App._lobbyLeer();
    if (App.tisch && App.view) { App.tisch.zeige(App.view, true); if (!$('#runde').hidden) App.zeigeRunde(App.view); }
    if (!$('#regeln').hidden) App.regeln();
    if (!$('#hilfe').hidden || !$('#ansicht').hidden) { App.schliesse('hilfe'); App.schliesse('ansicht'); }
    if (!$('#menue').hidden) $('#menue-info').textContent = App._menueInfo();
  });

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
