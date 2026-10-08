/* Mau-Mau Flip – Browser-Client „Lite“: Sprache (Beta 1.2.2, englische Fassung).
 * Deutsch ist Quelle und Standard. Wörterbücher (deutscher Text → Englisch):
 *   i18n_po.js  aus game/i18n/*.po erzeugt (tools/build.ps1 -Target Web): Texte der App, die auch hier erscheinen
 *               (Hinweise und Gründe des Gastgebers, Regeltexte, Kartennamen, Netz-Meldungen) – nie von Hand ändern
 *   i18n_en.js  nur Texte des Browser-Clients (Bereich C)
 * Aufruf: M.t('Deutscher Text') bzw. M.t('%s ist dran.', name) – Platzhalter %s, %d, %.1f wie in der App, %% = Prozent.
 * Bausteine vom Gastgeber (Feld lt, siehe game/scripts/app/i18n.gd): M.I18n.render(lt), Nachrichten: M.I18n.msgText(m, ersatz).
 * Statische Texte in index.html: Attribut data-t (Textinhalt), data-t-title, data-t-aria (aria-label), data-t-ph (placeholder);
 * der deutsche Text bleibt im Element und wird beim ersten Anwenden gemerkt.
 * Sprache: Einstellung „sprache“ (auto | de | en, gespeichert wie die anderen Lite-Einstellungen), auto = navigator.language;
 * ?lang=en bzw. ?lang=de für Tests und Kontrollbilder; im Testmodus (?mock=1, ?autotest=1) ohne ?lang immer Deutsch.
 */
(function (M) {
  'use strict';

  const WAHL = ['auto', 'de', 'en'];

  function systemSprache() {
    let l = '';
    try { l = (navigator.languages && navigator.languages[0]) || navigator.language || ''; } catch (e) { l = ''; }
    return /^de/i.test(l) ? 'de' : 'en';
  }

  function format(text, args) {
    let i = 0;
    return String(text).replace(/%(%|[-+ 0-9]*(?:\.(\d+))?([sdf]))/g, (all, p, prec, typ) => {
      if (p === '%') return '%';
      const a = args[i++];
      if (a === undefined) return all;
      if (typ === 'd') return String(Math.trunc(Number(a)));
      if (typ === 'f') return Number(a).toFixed(prec !== undefined ? Number(prec) : 6);
      return String(a);
    });
  }

  const I18n = {
    wahl: 'auto',
    sprache: 'de',
    hoerer: [],

    woerter() {
      if (this.sprache !== 'en') return null;
      return Object.assign({}, window.MMF_I18N_PO || {}, window.MMF_I18N_EN || {});
    },

    // Übersetzen ohne Format (msgid → Text der aktuellen Sprache)
    tr(text) {
      if (text === null || text === undefined) return '';
      const s = String(text);
      if (this.sprache !== 'en' || s === '') return s;
      const w = (window.MMF_I18N_EN && window.MMF_I18N_EN[s]) || (window.MMF_I18N_PO && window.MMF_I18N_PO[s]);
      return w || s;
    },

    // t(text, …args) bzw. t(text, [args])
    t(text, ...rest) {
      const args = rest.length === 1 && Array.isArray(rest[0]) ? rest[0] : rest;
      const s = this.tr(text);
      return args.length ? format(s, args) : s;
    },

    format,

    // Bausteine (lt) → Text: Teil = String | [vorlage, arg…], arg = Zahl | String (wörtlich) | {t: Teil}
    render(lt) {
      if (typeof lt === 'string') return this.tr(lt);
      if (!Array.isArray(lt)) return '';
      return lt.map(p => this.teil(p)).filter(s => s !== '').join(' ');
    },
    teil(p) {
      if (typeof p === 'string') return this.tr(p);
      if (Array.isArray(p) && p.length) {
        const args = p.slice(1).map(a => (a && typeof a === 'object' && !Array.isArray(a)) ? this.teil(a.t) : a);
        return format(this.tr(p[0]), args);
      }
      return '';
    },
    // Text einer Nachricht {text, lt?} in der eigenen Sprache
    msgText(m, ersatz) {
      if (m && Array.isArray(m.lt) && m.lt.length) return this.render(m.lt);
      const text = m && m.text ? String(m.text) : (ersatz || '');
      return this.tr(text);
    },

    aufloesen(wahl) {
      return wahl === 'de' || wahl === 'en' ? wahl : systemSprache();
    },

    // Sprache setzen (Einstellung) und alles Statische neu beschriften; Hörer bauen Dynamisches neu
    setze(wahl) {
      this.wahl = WAHL.indexOf(wahl) >= 0 ? wahl : 'auto';
      const p = M.param ? M.param('lang') : null;
      // Testmodus (?mock=1, ?autotest=1) bleibt deutsch wie die Godot-Tests, außer ?lang=en
      const test = M.param && (M.param('mock') || M.param('autotest'));
      this.sprache = p === 'de' || p === 'en' ? p : (test ? 'de' : this.aufloesen(this.wahl));
      try { document.documentElement.lang = this.sprache; } catch (e) { /* egal */ }
      this.anwenden(document);
      this.hoerer.forEach(f => { try { f(this.sprache); } catch (e) { /* weiter */ } });
    },

    beiWechsel(f) { this.hoerer.push(f); },

    anwenden(wurzel) {
      if (!wurzel || !wurzel.querySelectorAll) return;
      const paare = [['data-t', null], ['data-t-title', 'title'], ['data-t-aria', 'aria-label'], ['data-t-ph', 'placeholder']];
      paare.forEach(([attr, ziel]) => {
        wurzel.querySelectorAll('[' + attr + ']').forEach(el => {
          let de = el.getAttribute(attr);
          if (!de) {
            de = ziel ? (el.getAttribute(ziel) || '') : el.textContent;
            el.setAttribute(attr, de);
          }
          const text = this.tr(de);
          if (ziel) el.setAttribute(ziel, text); else el.textContent = text;
        });
      });
    },
  };

  M.I18n = I18n;
  M.t = (text, ...rest) => I18n.t(text, ...rest);
})(window.MMF = window.MMF || {});
