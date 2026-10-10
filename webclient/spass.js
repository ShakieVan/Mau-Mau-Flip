/* Mau-Mau Flip – Browser-Client „Lite“: freche Sprüche in der Hinweisleiste (Beta 1.4.4, Ostereier Teil 1).
 * Gleiche Sprüche und Regeln wie die App (game/scripts/ui/fun_texts.gd, test_web_contract prüft den Gleichlauf); nur auf diesem
 * Gerät, nichts wird an andere geschickt. Übersetzung über M.t (Texte stehen in game/i18n/en_fun.po → i18n_po.js).
 * Einstellung „sprueche“ (aus | nett | frech, ab Werk frech) im Lite-Menü; „sprueche_oft“ (selten | normal | oft | immer, ab Werk oft, Beta 1.4.5):
 * bei „immer“ bekommt jeder eigene Zug einen Spruch, der stehen bleibt (keine Abklingzeit, kein Zurück zum Standardtext).
 * Einhängepunkte: app.js beobachte(events, alteSicht, platz) vor der Regie, tisch.js hinweis(v, h, platz, standard) beim Anzeigen,
 * pointe() nach dem Anzeigen (Meldung „Hehe, verarscht!“), beiNeu = Rückruf, wenn die Hinweisleiste neu muss (Ablauf, Trödeln).
 * Regeln: ersetzt nur harmlose Zugtexte, nie Farbwahl, Strafe, Mau-Pflicht, Erwischen, Auswahl, Glücksspiel; Abklingzeit, nie zwei
 * Sprüche direkt hintereinander; keine Karten verraten; Namen nur von echten Mitspielern.
 */
(function (M) {
  'use strict';

  const SHOW_TIME = 7, GAP = 4, QUEUE_LIFE = 6;
  const MANY_CHANCE = 0.5, FEW_CHANCE = 0.4, REVERSE_CHANCE = 0.6, NAME_CHANCE = 0.35;
  // Häufigkeit (Beta 1.4.5) – wie FunTexts.FREQ_*: Chance auf einen Spruch zum eigenen Zugbeginn, Abklingzeit, Faktor für seltene Anlässe
  const FREQS = ['selten', 'normal', 'oft', 'immer'], FREQ_DEFAULT = 'oft';
  const FREQ_TURN = { selten: 0.15, normal: 0.35, oft: 0.65, immer: 1 };
  const FREQ_COOLDOWN = { selten: 40, normal: 15, oft: 5, immer: 0 };
  const FREQ_RARE = { selten: 0.6, normal: 1, oft: 1.8, immer: 1 };
  const RARE_CAP = 0.95, IMMER_MIN_SHOW = 1.5;
  const SLOW_SELF = [15, 30], SLOW_OTHER = 25, MANY = 12, FEW_MIN = 2, FEW_MAX = 3, STREAK = 3, JAGD_MANY = 8, AUTSCH_AMOUNT = 5;
  const TIP_CHANCE = 0.1, GLUECK_STAKE = 3, GLUECK_DISCARD = 4, GLUECK_FINISH_CHANCE = 0.5;

  // Anlässe, die die Zeilen eines anderen mitbenutzen – wie FunTexts.ALIAS
  const ALIAS = { farbjagd_du: 'pech_du', autsch_du: 'pech_du' };

  // Anlass → [[deutscher Text, Stufe]] – wie FunTexts.LINES (Quelle: docs/module/sprueche.md)
  const LINES = {
    zug: [
      ["Die anderen warten schon auf dich.", "nett"],
      ["Was ist eigentlich deine Lieblingsfarbe?", "nett"],
      ["Die Karten welcher Farbe stören dich am meisten?", "nett"],
      ["Tu einfach so, als würdest du einen fiesen Plan schmieden.", "nett"],
      ["Bühne frei für dich!", "nett"],
      ["Alle Augen auf dich.", "nett"],
      ["Jetzt kommt dein großer Auftritt.", "nett"],
      ["Na, schon eine Idee?", "nett"],
      ["Zeig mal, was du draufhast.", "nett"],
      ["Deine Karten, deine Entscheidung.", "nett"],
      ["Ganz ruhig – du schaffst das.", "nett"],
      ["Die Katze schaut gespannt zu.", "nett"],
      ["Heute ist dein Glückstag. Vielleicht.", "nett"],
      ["Mach was Schlaues. Oder was Lustiges.", "nett"],
      ["Jetzt nur nicht die falsche Farbe erwischen.", "nett"],
      ["Spannung! Was legst du?", "nett"],
      ["Dein Moment ist gekommen.", "nett"],
      ["Erst denken, dann legen. Oder umgekehrt.", "nett"],
      ["Die Ablage hat Hunger.", "nett"],
      ["Leg los – im wahrsten Sinne.", "nett"]
    ],
    zug_name: [
      ["%s hat gesagt, du wärst doof! Zahl's heim!", "frech"],
      ["%s hat dir gerade in die Karten geguckt. Ich hab's genau gesehen.", "frech"],
      ["%s lacht schon über deine Karten.", "frech"],
      ["%s meint, du verlierst sowieso.", "frech"],
      ["Zeig %s mal, wo der Hammer hängt.", "frech"],
      ["%s hat heimlich Karten gezählt. Pass auf!", "frech"],
      ["Gerüchten zufolge blufft %s.", "frech"],
      ["%s hat eben die Augen verdreht. Rache?", "frech"],
      ["Du weißt, was zu tun ist: %s ärgern.", "frech"],
      ["%s hat behauptet, du kannst nicht mischen.", "frech"],
      ["Ich würde ja %s eine reinwürgen. Nur so ein Gedanke.", "frech"],
      ["%s grinst verdächtig. Sei auf der Hut.", "frech"],
      ["%s hat gerade gegähnt. Weck %s mal auf!", "frech"],
      ["Für %s wäre jetzt ein „+5“ genau richtig.", "frech"],
      ["%s hält dich für harmlos. Beweis das Gegenteil.", "frech"],
      ["Psst: %s hat nur noch schlechte Karten. Glaube ich.", "frech"],
      ["%s hat gesagt, Katzen sind doof. Unverzeihlich!", "frech"],
      ["%s hat dich „Anfänger“ genannt. Tu was!", "frech"],
      ["Wenn du %s jetzt aussetzen lässt, sag ich nichts.", "frech"],
      ["%s wettet gegen dich. Mit Keksen.", "frech"]
    ],
    nichts_passt: [
      ["Nichts passt. Ab zum Stapel!", "nett"],
      ["Leider nix dabei. Zieh eine!", "nett"],
      ["Deine Karten streiken. Zieh eine neue.", "nett"],
      ["Keine passt? Dann ab zum Ziehstapel.", "nett"],
      ["Tja, nichts dabei. Der Stapel wartet schon.", "nett"],
      ["Nix zu machen – zieh eine Karte.", "nett"],
      ["Die Ablage mag gerade keine deiner Karten. Zieh!", "nett"],
      ["Kein Treffer auf der Hand. Zieh eine.", "nett"],
      ["Passt nicht, gibt's nicht? Doch. Zieh eine.", "nett"],
      ["Deine Hand hat heute frei. Zieh eine Karte.", "nett"],
      ["Leere Versprechen auf der Hand. Zieh!", "nett"],
      ["Nichts passt – Zeit für Nachschub vom Stapel.", "nett"],
      ["Ab zum Buffet: eine Karte vom Stapel, bitte.", "nett"],
      ["Keine Chance. Der Stapel ruft.", "nett"],
      ["Fehlanzeige! Zieh eine Karte.", "nett"],
      ["Da passt nix. Ziehen, bitte.", "nett"],
      ["Pech gehabt – nimm eine vom Stapel.", "nett"],
      ["Zieh eine. Vielleicht ist ja die richtige dabei.", "nett"],
      ["Deine Karten sind sich einig: Ziehen!", "nett"],
      ["Nichts passt zusammen. Wie bei Socken. Zieh eine.", "nett"],
      ["Der Stapel hat Sehnsucht nach dir. Zieh!", "nett"],
      ["Keine passende Karte? Dann gibt's Nachschub.", "nett"],
      ["Kartenflaute. Zieh eine.", "nett"],
      ["Mit dieser Hand wird das nix. Zieh eine.", "nett"],
      ["Die Farbe stimmt nicht, die Zahl auch nicht. Zieh!", "nett"],
      ["Gut gemischt, schlecht getroffen. Zieh eine.", "nett"],
      ["Shopping-Zeit: eine Karte vom Stapel.", "nett"],
      ["Nix passt? Willkommen im Club. Zieh eine.", "nett"],
      ["Deine Karten sind heute einfach nutzlos. Zieh eine.", "frech"],
      ["Nichts passt. Ab zum Stapel, aber flott!", "frech"],
      ["Nichts passt. War ja klar. Zieh eine.", "frech"],
      ["Die Katze empfiehlt: eine vom Stapel ziehen.", "nett"],
      ["Ziehen ist auch eine Strategie.", "nett"],
      ["Kein Match. Nach links wischen – und eine ziehen.", "nett"],
      ["Leider kein Volltreffer. Zieh eine Karte.", "nett"],
      ["Der Stapel hat bestimmt was Passendes. Zieh!", "nett"],
      ["Nichts zu legen, aber was zu ziehen!", "nett"],
      ["Zieh eine – das Glück wartet vielleicht oben.", "nett"],
      ["Nichts passt. Die anderen freuen sich schon. Zieh!", "frech"],
      ["Deine Hand: viel Auswahl, null Treffer. Zieh eine.", "frech"]
    ],
    tipp: [
      ["Im Ziehstapel liegt vielleicht genau die Karte, die du brauchst. Schau mal nach.", "frech"],
      ["Oben auf dem Stapel liegt ein Joker. Ganz sicher.", "frech"],
      ["Die nächste Karte ist bestimmt in deiner Lieblingsfarbe.", "frech"],
      ["Psst: Ziehen lohnt sich gerade besonders.", "frech"],
      ["Ich hab gehört, der Stapel verteilt heute Geschenke.", "frech"],
      ["Der Ziehstapel hat dir gerade zugezwinkert.", "frech"],
      ["Da wartet eine Überraschung im Stapel auf dich.", "frech"],
      ["Zieh doch mal – nur so zum Spaß.", "frech"],
      ["Die Katze sagt, im Stapel liegt was Gutes.", "frech"],
      ["Heute gibt's im Stapel zwei zum Preis von einer.", "frech"],
      ["Ich würde jetzt ziehen. Vertrau mir.", "frech"],
      ["Der Stapel ist heute in Spendierlaune.", "frech"],
      ["Gerüchten zufolge liegt da ein Joker ganz oben.", "frech"],
      ["Die oberste Karte glänzt so verheißungsvoll.", "frech"],
      ["Ein Blick in den Stapel kann nicht schaden. Oder?", "frech"],
      ["Dein Glück liegt nur eine Karte entfernt.", "frech"],
      ["Zieh! Der Stapel hat dich lieb.", "frech"],
      ["Mein sechster Sinn sagt: ziehen!", "frech"],
      ["Ich hab da so ein Gefühl beim Stapel …", "frech"],
      ["Die beste Karte des Spiels wartet auf dich. Im Stapel.", "frech"]
    ],
    verarscht: [
      ["Hehe, verarscht!", "frech"],
      ["War gelogen.", "nett"],
      ["Reingefallen!", "nett"],
      ["Ups, falscher Stapel.", "nett"],
      ["Hab ich das gesagt? Muss jemand anderes gewesen sein.", "nett"],
      ["Na, wenigstens hast du jetzt eine Karte mehr.", "nett"],
      ["Kleiner Scherz unter Freunden.", "nett"],
      ["Die Katze hat gelogen, nicht ich.", "nett"],
      ["Haha! Der älteste Trick der Welt.", "nett"],
      ["Tja. Glaub nicht alles, was auf dem Bildschirm steht.", "nett"],
      ["Mein sechster Sinn hat heute frei.", "nett"],
      ["Ich nehm alles zurück.", "nett"],
      ["Das war ein Test. Du hast bestanden. Nicht.", "frech"],
      ["Erwischt – diesmal du!", "nett"],
      ["Gerüchte sind halt Gerüchte.", "nett"],
      ["Oh. Das war wohl doch nichts.", "nett"],
      ["Sorry, ich konnte nicht widerstehen.", "nett"],
      ["Wenigstens ehrlich gezogen.", "nett"],
      ["Der Stapel war heute doch geizig.", "nett"],
      ["Nächstes Mal glaubst du mir bestimmt wieder.", "nett"]
    ],
    langsam: [
      ["Worauf wartest du, Weihnachten?", "nett"],
      ["Wenn du noch länger brauchst, schlafen alle ein.", "nett"],
      ["Trink ruhig aus, wir haben Zeit. *hust hust*", "frech"],
      ["Lass die anderen ruhig schmoren.", "nett"],
      ["Die Katze ist schon eingeschlafen.", "nett"],
      ["Soll ich dir einen Kaffee bringen?", "nett"],
      ["Schach ist ein anderes Spiel.", "nett"],
      ["Die Karten werden vom Anschauen nicht besser.", "nett"],
      ["Hallo? Jemand zu Hause?", "nett"],
      ["Ich hab inzwischen die Steuererklärung gemacht.", "nett"],
      ["Kleiner Tipp: Irgendeine Karte geht immer. Fast.", "nett"],
      ["Die anderen altern gerade sichtbar.", "frech"],
      ["Das ist kein Schönheitswettbewerb. Leg einfach was.", "nett"],
      ["Tick, tack, tick, tack …", "nett"],
      ["Mein Akku ist gleich leer. Deiner auch?", "nett"],
      ["Noch eine Runde Nachdenken, und es ist Frühling.", "nett"],
      ["Die Ablage fragt, ob du sie vergessen hast.", "nett"],
      ["Du denkst so laut, man hört es bis hier.", "nett"],
      ["Grübel, grübel und studier …", "nett"],
      ["Nimm dir Zeit. Aber nicht ALLE Zeit.", "nett"]
    ],
    langsam_andere: [
      ["%s schmiedet offenbar einen Masterplan.", "nett"],
      ["%s denkt nach. Das kann dauern.", "nett"],
      ["Wetten, %s hat die Regeln vergessen?", "frech"],
      ["%s zählt heimlich Schäfchen.", "nett"],
      ["Ob %s eingeschlafen ist?", "nett"],
      ["%s sucht noch die passende Farbe. Seit Stunden.", "nett"],
      ["%s braucht wohl einen Taschenrechner.", "frech"],
      ["Zeit für einen Snack – %s braucht noch.", "nett"],
      ["%s meditiert gerade.", "nett"],
      ["Achtung, %s denkt! Bitte nicht stören.", "nett"],
      ["Hat jemand %s gesehen?", "nett"],
      ["%s schreibt vermutlich gerade ein Buch.", "nett"],
      ["Bis %s legt, kannst du in Ruhe Tee kochen.", "nett"],
      ["%s plant was Fieses. Ganz sicher.", "nett"],
      ["%s hat den Faden verloren. Und die Karten.", "frech"],
      ["Man hört förmlich, wie es bei %s rattert.", "nett"],
      ["%s wartet auf eine Eingebung.", "nett"],
      ["Das Universum dehnt sich aus. %s denkt noch.", "nett"],
      ["Vielleicht braucht %s einen Wecker.", "nett"],
      ["%s macht es heute spannend.", "nett"]
    ],
    viele: [
      ["Komm schon, zieh noch eine. Das macht das Kraut auch nicht mehr fett.", "nett"],
      ["Lass den anderen auch noch ein paar Karten.", "nett"],
      ["Du könntest auch einfach aufgeben.", "frech"],
      ["Sammelst du die etwa?", "nett"],
      ["Deine Hand braucht bald einen Anbau.", "nett"],
      ["Beeindruckende Sammlung!", "nett"],
      ["Planst du einen eigenen Kartenladen?", "nett"],
      ["Ein Fächer? Das ist schon ein Sonnenschirm.", "nett"],
      ["Wenigstens wird dir beim Sortieren nicht langweilig.", "nett"],
      ["Das sind ja mehr Karten als Freunde.", "frech"],
      ["Wer viel hat, kann viel legen. Theoretisch.", "nett"],
      ["Der Ziehstapel vermisst dich schon.", "nett"],
      ["Hast du den halben Stapel abonniert?", "nett"],
      ["Kopf hoch, Rekorde sind auch was wert.", "nett"],
      ["Halte durch, es kann nur besser werden. Glaube ich.", "nett"],
      ["Deine Karten haben Karten bekommen.", "nett"],
      ["Noch zehn mehr und du bekommst einen Pokal.", "nett"],
      ["Wenigstens hast du jetzt Auswahl.", "nett"],
      ["Du siehst aus wie ein Fächer-Model.", "nett"],
      ["Das wird ein langer Abend für dich.", "nett"]
    ],
    wenige: [
      ["Du bist bald fertig – oder hast du einfach keine Lust mehr?", "nett"],
      ["Komm schon, willst du jetzt schon fertig machen?", "nett"],
      ["Wenn du jetzt fertig machst, kannst du nur noch zuschauen.", "nett"],
      ["Willst du die anderen nicht noch etwas länger leiden sehen?", "frech"],
      ["Die anderen werden langsam nervös.", "nett"],
      ["Ganz schön eilig heute, was?", "nett"],
      ["Vergiss das „Mau!“ nicht!", "nett"],
      ["Gleich ist es geschafft. Oder doch nicht?", "nett"],
      ["Die Ziellinie ist in Sicht!", "nett"],
      ["Psst – nicht zu früh freuen.", "nett"],
      ["Die anderen schmieden schon Rachepläne.", "nett"],
      ["Fast leer – fast genial.", "nett"],
      ["Nur nicht übermütig werden.", "nett"],
      ["Wer zuletzt lacht …", "nett"],
      ["Die Karten verlassen dich. Verständlich.", "frech"],
      ["Noch ein paar Züge bis zum Ruhm.", "nett"],
      ["Jetzt bloß kein „+5“ kassieren.", "nett"],
      ["Ich spüre einen Sieg … oder ist das Hunger?", "nett"],
      ["Halt dich fest, gleich wird's spannend.", "nett"],
      ["Sieht gut aus. Zu gut.", "nett"]
    ],
    richtung: [
      ["Und jetzt rückwärts. Alle kotzen schon.", "frech"],
      ["Rückwärtsgang eingelegt!", "nett"],
      ["Kommando zurück!", "nett"],
      ["Alles andersrum – wie im Spiegel.", "nett"],
      ["Uff, mir wird schwindelig.", "nett"],
      ["Einmal im Kreis und zurück.", "nett"],
      ["Wer hat am Lenkrad gedreht?", "nett"],
      ["Rolle rückwärts!", "nett"],
      ["Umleitung! Bitte der Beschilderung folgen.", "nett"],
      ["Moonwalk-Modus aktiviert.", "nett"],
      ["Die Erde dreht sich jetzt andersrum. Fast.", "nett"],
      ["Rückwärts ist das neue Vorwärts.", "nett"],
      ["Halt, falsche Richtung! Ach nee, Absicht.", "nett"],
      ["Kehrtwende!", "nett"],
      ["Und alle drehen sich um. Schwindelfrei?", "nett"],
      ["Der Zug fährt jetzt in die Gegenrichtung.", "nett"],
      ["Zurück auf Los. Aber nur die Richtung.", "nett"],
      ["Wer eben noch zuletzt kam, kommt jetzt zuerst.", "nett"],
      ["Uhrzeigersinn ist sowieso überbewertet.", "nett"],
      ["Bitte anschnallen, es geht rückwärts.", "nett"]
    ],
    pech_du: [
      ["Autsch!", "nett"],
      ["Das tat weh.", "nett"],
      ["Farbenblind?", "frech"],
      ["Heute ist nicht dein Tag, oder?", "nett"],
      ["Mitgefangen, mitgehangen.", "nett"],
      ["Die Karten mögen dich. Sehr.", "nett"],
      ["Na, Hauptsache, die anderen freuen sich.", "nett"],
      ["Das gibt einen blauen Fleck.", "nett"],
      ["Kopf hoch, schlimmer geht immer.", "nett"],
      ["Wer zuletzt lacht … bist wohl nicht du.", "frech"],
      ["Das war gemein. Herrlich gemein.", "nett"],
      ["Gesammelte Werke, Band 2.", "nett"],
      ["Und plötzlich: Kartenflut.", "nett"],
      ["Mein Beileid.", "nett"],
      ["Das Universum hat entschieden.", "nett"],
      ["Ziehen, ziehen, ziehen …", "nett"],
      ["Pech im Spiel, Glück in der Liebe.", "nett"],
      ["Rache ist süß – merk dir das.", "nett"],
      ["Huch, wo kommen die alle her?", "nett"],
      ["Kleiner Rückschlag. Ganz kleiner. Okay, großer.", "nett"]
    ],
    pech: [
      ["%s hat heute echt kein Glück.", "nett"],
      ["Der Automat mag %s. Leider.", "nett"],
      ["%s zockt heute mit dem Feuer.", "nett"],
      ["%s und das Glücksspiel – eine tragische Liebesgeschichte.", "frech"],
      ["Jemand sollte %s das Zocken verbieten.", "frech"],
      ["Die Glückssträhne von %s ist eher eine Pechsträhne.", "frech"]
    ],
    farbjagd: [
      ["Farbenblind, %s?", "frech"],
      ["%s hat die halbe Ablage gefunden.", "nett"],
      ["%s hat lange gesucht.", "nett"],
      ["%s sammelt Karten wie andere Briefmarken.", "nett"],
      ["Bei %s wird die Hand gerade sehr voll.", "nett"]
    ],
    autsch: [
      ["Autsch!", "nett"],
      ["Das tat weh.", "nett"],
      ["So knapp vor dem Ziel. Autsch!", "nett"],
      ["So kurz vor Schluss – das tut weh.", "nett"],
      ["Fast fertig und dann das. Gemein!", "nett"],
      ["Hehe. Ich meine: Oh nein!", "frech"]
    ],
    glueck: [
      ["Läuft bei dir!", "nett"],
      ["Glückspilz!", "nett"],
      ["Das Glück ist mit dir.", "nett"],
      ["Schon wieder? Unglaublich.", "nett"],
      ["Hast du einen Glücksbringer dabei?", "nett"],
      ["Die Karten lieben dich heute.", "nett"],
      ["Volltreffer!", "nett"],
      ["Dir droht bald Spielbank-Verbot!", "nett"],
      ["Dir gelingt heute alles.", "nett"],
      ["Respekt!", "nett"],
      ["Wie machst du das nur?", "nett"],
      ["Die anderen staunen.", "nett"],
      ["Ein Hoch auf dich!", "nett"],
      ["Sieht nach Talent aus. Oder nach Glück.", "nett"],
      ["Bitte etwas von dem Glück abgeben.", "nett"],
      ["Die Katze ist beeindruckt.", "nett"],
      ["Zufall? Ich glaube nicht.", "nett"],
      ["Jetzt nur nicht abheben.", "nett"],
      ["So sehen Gewinner aus.", "nett"],
      ["Bravo, weiter so!", "nett"]
    ]
  };

  function linesFor(occ, stufe) {
    if (stufe === 'aus') return [];
    return (LINES[ALIAS[occ] || occ] || []).filter(e => stufe === 'frech' || e[1] === 'nett').map(e => e[0]);
  }

  function spieler(v, seat) { return (v && v.players || []).find(p => p.seat === seat) || {}; }

  // wie FunTexts.replaceable
  function ersetzbar(v, h, ich) {
    if (!v || v.phase !== 'turn') return false;
    if (v.pending && Object.keys(v.pending).length) return false;
    if (v.discard_pick && Object.keys(v.discard_pick).length) return false;
    if (h.need_color || h.can_challenge) return false;
    if (Array.isArray(h.catch) && h.catch.length) return false;
    const t = h.text || '';
    if (t.indexOf('Mau') >= 0 || t.indexOf('nichts passt') >= 0) return false;
    if (ich >= 0 && v.turn === ich) return t === '' || t.indexOf('Du bist dran') === 0;
    return t === '' || /ist dran\.$/.test(t) || t.indexOf('Du bist fertig') === 0;
  }

  // Der reine „nichts passt, zieh eine Karte“-Fall (Beta 1.4.6) – wie FunTexts.nothing_fits: Anlass nichts_passt darf ihn ersetzen
  const NICHTS_PASST = "Du bist dran – nichts passt, zieh eine Karte.";
  function nichtsPasst(v, h, ich) {
    if (!v || ich < 0 || v.phase !== 'turn' || v.turn !== ich) return false;
    if (v.pending && Object.keys(v.pending).length) return false;
    if (v.discard_pick && Object.keys(v.discard_pick).length) return false;
    if (h.need_color || h.can_challenge) return false;
    if (Array.isArray(h.catch) && h.catch.length) return false;
    return (h.text || '') === NICHTS_PASST;
  }

  const S = {
    stufe: 'frech',
    nichtsOk: true, _nichts: false,      // nichtsOk = false: „Spielbare Karten hervorheben“ aus, ein „nichts passt“-Spruch würde es verraten
    haeufigkeit: FREQ_DEFAULT,
    _tuete: {}, _gezeigtUm: 0,
    LINES, ALIAS, linesFor, ersetzbar, nichtsPasst,
    beiNeu: null,
    text: '', zeile: '', anlass: '',
    _bis: -1, _ende: -1000, _zugGezeigt: -2, _warte: null, _notiz: '', _platz: -99, _meinZug: false, _zugStart: 0,
    _startFaellig: false, _langsamN: 0, _ersetzbar: false, _anderer: -1, _andererStart: 0, _andererFertig: false, _andererName: '',
    _tipp: false, _serie: {}, _jagdOpfer: -1, _zuletzt: {}, _gefragt: -1000, _uhr: null,

    jetzt() { return performance.now() / 1000; },
    setzeHaeufigkeit(h) {
      const neu = FREQS.indexOf(h) >= 0 ? h : FREQ_DEFAULT;
      if (neu === this.haeufigkeit) return;
      this.haeufigkeit = neu;
      this._beende();                    // ein stehender Spruch endet, die Hinweisleiste wird neu aufgebaut
    },
    _selten(basis) {                     // Chance eines seltenen Anlasses (basis = Wert für „normal“)
      if (this.haeufigkeit === 'immer') return 1;
      const f = FREQ_RARE[this.haeufigkeit];
      return f > 1 ? Math.min(RARE_CAP, basis * f) : basis * f;
    },
    _abkling() { return FREQ_COOLDOWN[this.haeufigkeit]; },
    _luecke() { return this.haeufigkeit === 'immer' ? 0 : GAP; },
    setzeStufe(s) {
      const alt = this.stufe;
      this.stufe = ['aus', 'nett', 'frech'].indexOf(s) >= 0 ? s : 'frech';
      if (this.stufe !== alt) this._tuete = {};
      if (this.stufe === 'aus') { this._beende(); this._warte = null; this._tipp = false; this._notiz = ''; }
      this._uhrAn();
    },
    _uhrAn() {
      if (this._uhr) return;
      this._uhr = setInterval(() => { if (this.tick() && this.beiNeu) this.beiNeu(); }, 250);
    },

    // Ereignisse des Gastgebers vor der neuen Sicht (alt = bisherige Sicht)
    beobachte(events, alt, ich) {
      if (this.stufe === 'aus') return;
      for (const d of events || []) {
        if (!d) continue;
        const seat = typeof d.seat === 'number' ? d.seat : -1;
        switch (d.e) {
          case 'reverse': if (Math.random() < this._selten(REVERSE_CHANCE)) this._reihe('richtung', ''); break;
          case 'pending':
            if (d.kind === 'farbjagd') this._jagdOpfer = seat;
            else if ((d.amount | 0) >= AUTSCH_AMOUNT && spieler(alt, seat).count === 1) this._reihe(seat === ich ? 'autsch_du' : 'autsch', '');
            break;
          case 'draw':
            if (d.reason === 'strafe' && seat === this._jagdOpfer) {
              if ((d.count | 0) >= JAGD_MANY) {
                if (seat === ich) this._reihe('farbjagd_du', ''); else this._reihe('farbjagd', spieler(alt, seat).name || '');
              }
              this._jagdOpfer = -1;
            }
            if (d.reason === 'zug' && seat === ich && this._tipp) { this._tipp = false; this._notiz = this._waehle('verarscht', '').text; }
            break;
          case 'gamble_roll':
            if ((d.value | 0) > 0) {
              this._serie[seat] = (this._serie[seat] || 0) + 1;
              if (this._serie[seat] === STREAK) { if (seat === ich) this._reihe('pech_du', ''); else this._reihe('pech', spieler(alt, seat).name || ''); }
            } else this._serie[seat] = 0;
            break;
          case 'stake_discard': if (seat === ich && (d.count | 0) >= GLUECK_STAKE) this._reihe('glueck', ''); break;
          case 'discard_color': if (seat === ich && (d.count | 0) >= GLUECK_DISCARD) this._reihe('glueck', ''); break;
          case 'finish': if (seat === ich && Math.random() < this._selten(GLUECK_FINISH_CHANCE)) this._reihe('glueck', ''); break;
          case 'round_start': case 'start': case 'seats': this._serie = {}; this._jagdOpfer = -1; break;
        }
      }
    },

    pointe() { const n = this._notiz; this._notiz = ''; return n; },

    // Text für die Hinweisleiste: standard (schon übersetzt) oder ein Spruch
    hinweis(v, h, ich, standard, gesperrt) {
      this._uhrAn();
      const now = this.jetzt();
      if (ich !== this._platz) { this._platz = ich; this._meinZug = false; this._startFaellig = false; this._tipp = false; this._notiz = ''; this._beende(); }
      const phase = v.phase || '';
      const laeuft = phase !== 'round_over' && phase !== 'game_over' && phase !== 'idle' && phase !== '';
      const mein = ich >= 0 && v.turn === ich && laeuft;
      this._gesperrt = !!gesperrt;
      this._nichts = this.nichtsOk && this.stufe !== 'aus' && !gesperrt && nichtsPasst(v, h || {}, ich);
      this._ersetzbar = this.stufe !== 'aus' && !gesperrt && (this._nichts || ersetzbar(v, h || {}, ich));
      if (mein && !this._meinZug) { this._zugStart = now; this._langsamN = 0; this._startFaellig = true; }
      else if (!mein && this._meinZug) { this._tipp = false; this._startFaellig = false; }
      this._meinZug = mein;
      if (gesperrt) this._zugStart = now;
      if (!mein && laeuft && v.turn >= 0 && phase === 'turn') {
        if (v.turn !== this._anderer) { this._anderer = v.turn; this._andererStart = now; this._andererFertig = false; }
        const p = spieler(v, v.turn);
        this._andererName = p.kind !== 'bot' && v.turn !== ich ? (p.name || '') : '';
      } else { this._anderer = -1; this._andererName = ''; }
      if (this.text && (!this._ersetzbar || v.turn !== this._zugGezeigt || (this.anlass === 'nichts_passt') !== this._nichts)) this._beende();
      if (this.stufe === 'aus' || !this._ersetzbar) {
        if (!gesperrt && mein && this._startFaellig) this._startFaellig = false;
        return standard;
      }
      if (this.text && this.haeufigkeit === 'immer' && this._wartetPassend(mein, now) && now - this._gezeigtUm >= IMMER_MIN_SHOW) this._beende();   // neuer Anlass löst den stehenden Spruch ab
      if (!this.text) this._versuche(v, ich, mein, now);
      return this.text || standard;
    },
    // Wartet ein Anlass, der zu diesem Zug passt? (Trödel-Sprüche gehören zum eigenen Zug, Kommentare über andere nicht dorthin)
    _wartetPassend(mein, now) {
      const q = this._warte;
      if (!q || now - q.t > QUEUE_LIFE) return false;
      if (this._nichts && q.occ !== 'nichts_passt') return false;   // bei „nichts passt“ nur Sprüche, die das Ziehen nennen
      return !((q.occ === 'langsam' && !mein) || (q.occ === 'langsam_andere' && mein));
    },

    tick() {
      const now = this.jetzt();
      let neu = false;
      if (this.text && now >= this._bis) { this._beende(); neu = true; }
      if (this.stufe === 'aus' || this._gesperrt) return neu;
      if (this._meinZug && this._langsamN < SLOW_SELF.length && now - this._zugStart >= SLOW_SELF[this._langsamN]) {
        this._langsamN++;
        this._reihe('langsam', '');
        neu = true;
      }
      if (!this._meinZug && this._anderer >= 0 && this._andererName && !this._andererFertig && now - this._andererStart >= SLOW_OTHER) {
        this._andererFertig = true;
        if (now - this._ende >= this._abkling()) { this._reihe('langsam_andere', this._andererName); neu = true; }
      }
      if (this._warte && this._ersetzbar && now - this._gefragt >= 0.5) {
        if (!this.text && now - this._ende >= this._luecke()) { this._gefragt = now; neu = true; }
        else if (this.text && this.haeufigkeit === 'immer' && now - this._gezeigtUm >= IMMER_MIN_SHOW) { this._gefragt = now; neu = true; }   // „immer“: neuer Anlass löst den stehenden Spruch ab
      }
      return neu;
    },

    _versuche(v, ich, mein, now) {
      if (this._warte) {
        const q = this._warte;
        if (now - q.t > QUEUE_LIFE) this._warte = null;
        else if (now - this._ende >= this._luecke()) {
          this._warte = null;
          if (!this._nichts && !((q.occ === 'langsam' && !mein) || (q.occ === 'langsam_andere' && mein))) {
            this._zeige(this._waehle(q.occ, q.name), q.occ, v.turn, now);
            if (this.text) { this._startFaellig = false; return; }
          }
        }
      }
      if (!(mein && this._startFaellig)) return;
      this._startFaellig = false;
      if (now - this._ende < this._abkling()) return;
      if (this._nichts) {                // „nichts passt“: wie der Zug-Anlass, aber nur Sprüche, die das Ziehen nennen
        if (Math.random() < FREQ_TURN[this.haeufigkeit]) this._zeige(this._waehle('nichts_passt', ''), 'nichts_passt', v.turn, now);
        return;
      }
      const n = (v.hand || []).length;
      let occ = '';
      if (n >= MANY && Math.random() < this._selten(MANY_CHANCE)) occ = 'viele';
      else if (n >= FEW_MIN && n <= FEW_MAX && Math.random() < this._selten(FEW_CHANCE)) occ = 'wenige';
      else if (Math.random() < FREQ_TURN[this.haeufigkeit]) occ = 'zug';
      if (!occ) return;
      let name = '';
      if (occ === 'zug' && this.stufe === 'frech') {
        if (Math.random() < TIP_CHANCE) occ = 'tipp';
        else if (Math.random() < NAME_CHANCE) {
          const namen = (v.players || []).filter(p => p.seat !== ich && p.kind !== 'bot' && p.name && p.connected !== false).map(p => p.name);
          if (namen.length) { name = namen[Math.floor(Math.random() * namen.length)]; occ = 'zug_name'; }
        }
      }
      const w = this._waehle(occ, name);
      this._zeige(w, occ, v.turn, now);
      if (this.anlass === 'tipp') this._tipp = true;
    },
    _zeige(w, occ, turn, now) {
      if (!w.text) return;
      this.text = w.text; this.zeile = w.de; this.anlass = occ; this._bis = this.haeufigkeit === 'immer' ? Infinity : now + SHOW_TIME; this._gezeigtUm = now; this._zugGezeigt = turn;
    },
    _beende() {
      if (this.text) this._ende = this.jetzt();
      this.text = ''; this.zeile = ''; this.anlass = ''; this._bis = -1;
    },
    _reihe(occ, name) {
      if (!linesFor(occ, this.stufe).length) return;
      if ((occ === 'pech' || occ === 'farbjagd' || occ === 'langsam_andere') && !name) return;
      const now = this.jetzt();
      if (this._warte && now - this._warte.t <= QUEUE_LIFE) return;
      this._warte = { occ, name, t: now };
    },
    // Nächste Zeile eines Anlasses (wie FunTexts._pick): gemischt der Reihe nach, erst dann neu mischen; die erste einer neuen Runde ist
    // nie die zuletzt gezeigte; Aliase teilen sich die Tüte. Übersetzt, Name eingesetzt.
    _waehle(occ, name) {
      const pool = linesFor(occ, this.stufe);
      if (!pool.length) return { text: '', de: '' };
      const key = ALIAS[occ] || occ;
      let tuete = (this._tuete[key] || []).filter(s => pool.indexOf(s) >= 0);
      if (!tuete.length) {
        tuete = pool.slice();
        for (let i = tuete.length - 1; i > 0; i--) {
          const j = Math.floor(Math.random() * (i + 1));
          const t = tuete[i]; tuete[i] = tuete[j]; tuete[j] = t;
        }
        if (tuete.length > 1 && tuete[tuete.length - 1] === this._zuletzt[key]) {
          const t = tuete[tuete.length - 1]; tuete[tuete.length - 1] = tuete[0]; tuete[0] = t;
        }
      }
      const de = tuete.pop();
      this._tuete[key] = tuete;
      this._zuletzt[key] = de;
      return { de, text: de.indexOf('%s') >= 0 ? M.t(de).split('%s').join(name || '?') : M.t(de) };
    }
  };

  M.Spass = S;
})(window.MMF = window.MMF || {});
