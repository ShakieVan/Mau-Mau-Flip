/* Mau-Mau Flip – Browser-Client „Lite“: Karten (Schlüssel, Farben, Sortierung, Punkte, Hilfe, Darstellung).
 * Kartenbilder kommen aus cards/<schlüssel>.webp (Modul B). Fehlen sie, zeichnet karteSVG() eine eigene
 * Karte im Stil von Entwurf A (Papier & Neon); die Symbole sind aus art/entwurf/a-papier-neon/quelle/mmf.js übernommen.
 */
(function (M) {
  'use strict';

  // Palette aus Entwurf A
  const INK = '#211B2C', PAPER = '#F4EADA', PAPER_D = '#E6D7BC', CREAM = '#FFF7E8', NIGHT = '#0A0D20', MOON = '#F4F0FF';
  const FARBEN = { hell: ['rot', 'gelb', 'gruen', 'blau'], dunkel: ['pink', 'tuerkis', 'orange', 'lila'] };
  // hex = Fläche, tief = dunklerer Ton, neon = Kontur (dunkel), ring = gut sichtbare Leuchtfarbe auf Nachtgrund
  const FARB_INFO = {
    rot: { name: 'Rot', hex: '#B3202A', tief: '#86161F', ring: '#FF4D57', sym: 'flamme' },
    gelb: { name: 'Gelb', hex: '#FFDD33', tief: '#E2A90E', ring: '#FFDD33', sym: 'sonne' },
    gruen: { name: 'Grün', hex: '#43B05C', tief: '#2C8543', ring: '#4FD36E', sym: 'klee' },
    blau: { name: 'Blau', hex: '#2A5BD7', tief: '#1D3FA3', ring: '#4C7DFF', sym: 'kristall' },
    pink: { name: 'Pink', hex: '#FF9ECF', tief: '#C2649A', neon: '#FFB3DC', ring: '#FF9ECF', sym: 'herz' },
    tuerkis: { name: 'Türkis', hex: '#00838F', tief: '#005A62', neon: '#0B97A3', ring: '#19C6D4', sym: 'welle' },
    orange: { name: 'Orange', hex: '#FF6F00', tief: '#B84F00', neon: '#FF7F14', ring: '#FF8A1F', sym: 'laterne' },
    lila: { name: 'Lila', hex: '#4527A0', tief: '#2E1A6B', neon: '#5E3BD8', ring: '#8B6BFF', sym: 'stern' },
  };
  // Hausregel-Karten (docs/module/A.md): Kartentausch „tausch“ (farbig), Glücksspiel „gluecksspiel“ (Joker), Farbe ablegen
  // „ablegen“ (farbig) und „ablegen_joker“ (Joker). Namen wie RulesText.face_title: „Rot Kartentausch“, „Rot ablegen“.
  const ART_NAME = {
    plus1: '+1', plus5: '+5', aussetzen: 'Aussetzen', alle_aussetzen: 'Alle aussetzen', richtungswechsel: 'Richtungswechsel',
    flip: 'Flip', wuenscher: 'Wünscher', wuenscher_plus2: 'Wünscher +2', farbjagd: 'Farbjagd', rueckseite: 'Rückseite',
    tausch: 'Kartentausch', gluecksspiel: 'Glücksspiel', ablegen: 'ablegen', ablegen_joker: 'Ablegen-Joker',
  };
  // Wie man auf eine Karte antwortet („… oder eine +1“), wie RulesText.KIND_WITH_ARTICLE
  const ART_PASSEND = {
    plus1: 'eine +1', plus5: 'eine +5', aussetzen: 'ein Aussetzen', alle_aussetzen: 'ein Alle aussetzen', richtungswechsel: 'einen Richtungswechsel',
    flip: 'einen Flip', tausch: 'einen Kartentausch', ablegen: 'eine Ablegen-Karte',
  };
  const PUNKTE = { plus1: 10, plus5: 20, aussetzen: 20, alle_aussetzen: 30, richtungswechsel: 20, flip: 20, wuenscher: 40, wuenscher_plus2: 50, farbjagd: 60,
    tausch: 20, gluecksspiel: 50, ablegen: 30, ablegen_joker: 50 };
  // Rang wie CardDB.rank_table: in der Farbe Zahlen, Aktionen, Kartentausch, Ablegen-Karte; Joker: Wünscher, +2/Farbjagd, Glücksspiel, Ablegen-Joker
  const ART_REIHE = ['plus1', 'plus5', 'aussetzen', 'alle_aussetzen', 'richtungswechsel', 'flip', 'tausch', 'ablegen', 'wuenscher', 'wuenscher_plus2', 'farbjagd', 'gluecksspiel', 'ablegen_joker'];
  const JOKER = { wuenscher: 1, wuenscher_plus2: 1, farbjagd: 1, gluecksspiel: 1, ablegen_joker: 1 };
  const HAUS_KARTEN = { tausch: 4, gluecksspiel: 2, ablegen: 6 };   // zusätzliche Karten je Hausregel (Grunddeck 112)

  /* ---------------- Schlüssel ---------------- */
  const _zerlegt = new Map();
  // "hell_blau_9" → {seite:'hell', farbe:'blau', art:'zahl', wert:9}; Joker ohne Farbe
  function zerlege(key) {
    key = String(key || 'rueckseite');
    let k = _zerlegt.get(key);
    if (k) return k;
    if (key === 'rueckseite') k = { key, seite: '', farbe: '', art: 'rueckseite', wert: null };
    else {
      const t = key.split('_');
      const seite = t[0] === 'dunkel' ? 'dunkel' : 'hell';
      let farbe = '', rest;
      if (FARB_INFO[t[1]]) { farbe = t[1]; rest = t.slice(2).join('_'); } else rest = t.slice(1).join('_');
      const n = parseInt(rest, 10);
      k = String(n) === rest ? { key, seite, farbe, art: 'zahl', wert: n } : { key, seite, farbe, art: rest, wert: null };
    }
    _zerlegt.set(key, k);
    return k;
  }
  const istJoker = key => !!JOKER[zerlege(key).art];
  const punkte = key => { const k = zerlege(key); return k.art === 'zahl' ? k.wert : (PUNKTE[k.art] || 0); };
  const farbName = f => (FARB_INFO[f] ? FARB_INFO[f].name : '');
  function kartenName(key) {
    const k = zerlege(key);
    if (k.art === 'zahl') return farbName(k.farbe) + ' ' + k.wert;
    if (!k.farbe) return ART_NAME[k.art] || k.art;
    return farbName(k.farbe) + ' ' + (ART_NAME[k.art] || k.art);
  }
  // „eine 7“, „ein Aussetzen“, „eine Ablegen-Karte“ (für „Passt nicht – gefragt ist Rot oder …“)
  function passendText(key) {
    const k = zerlege(key);
    if (k.art === 'zahl') return 'eine ' + k.wert;
    return ART_PASSEND[k.art] || '';
  }
  // Zahl der Karten einer Partie nach den Hausregeln (112 bis 124)
  function kartenZahl(r) {
    r = r || {};
    return 112 + (r.swap_cards === 'on' ? HAUS_KARTEN.tausch : 0) + (r.gamble_cards === 'on' ? HAUS_KARTEN.gluecksspiel : 0) + (r.discard_color === 'on' ? HAUS_KARTEN.ablegen : 0);
  }
  // kurzer Wert für Index und Ersatzdarstellung
  function kurzWert(k) {
    if (k.art === 'zahl') return String(k.wert);
    return { plus1: '+1', plus5: '+5', wuenscher_plus2: '+2', farbjagd: '?' }[k.art] || '';
  }

  /* ---------------- Sortierung ---------------- */
  function farbIndex(k) { const s = FARBEN[k.seite] || FARBEN.hell; const i = s.indexOf(k.farbe); return i < 0 ? 9 : i; }
  function artIndex(k) { return k.art === 'zahl' ? k.wert : 10 + ART_REIHE.indexOf(k.art); }
  // hand: [{id, face}], modus: farbe | wert | punkte; sortiert nach der aktiven Seite (face)
  function sortiere(hand, modus) {
    const a = hand.slice();
    const cmp = {
      farbe: (x, y) => farbIndex(x.k) - farbIndex(y.k) || artIndex(x.k) - artIndex(y.k),
      wert: (x, y) => (istJoker(x.k.key) - istJoker(y.k.key)) || artIndex(x.k) - artIndex(y.k) || farbIndex(x.k) - farbIndex(y.k),
      punkte: (x, y) => punkte(y.k.key) - punkte(x.k.key) || farbIndex(x.k) - farbIndex(y.k) || artIndex(x.k) - artIndex(y.k),
    }[modus] || null;
    if (!cmp) return a;
    return a.map(c => ({ c, k: zerlege(c.face) })).sort((x, y) => cmp(x, y) || (x.c.id - y.c.id)).map(o => o.c);
  }

  /* ---------------- Hilfe und Regeltexte ---------------- */
  // Kein Anzweifeln mehr (0.1.3): „bluff“ eines alten Gastgebers gilt wie „free“ (die Knöpfe in tisch.js bleiben nur dafür)
  function bluffText(r) {
    if (r.wild_restriction === 'enforce') return 'Nur erlaubt, wenn du keine Karte der aktuellen Farbe hast. Die App prüft das.';
    return 'Darf immer gelegt werden.';
  }
  // Kartenhilfe passend zu den aktiven Regeln: {titel, zeilen}
  function hilfe(key, regeln) {
    const r = regeln || {};
    const k = zerlege(key);
    const f = farbName(k.farbe);
    const z = [];
    const stapeln = r.stacking === 'same';
    // Hausregel penalty_turn: nach dem Strafziehen aussetzen (offiziell) oder gleich weiterspielen
    const ende = r.penalty_turn === 'play' ? ' und ist danach trotzdem dran.' : ' und setzt aus.';
    switch (k.art) {
      case 'zahl': z.push('Passt auf ' + f + ' oder auf jede ' + k.wert + '.'); break;
      case 'plus1': case 'plus5': {
        const n = k.art === 'plus1' ? 1 : 5;
        z.push('Der Nächste zieht ' + n + (n === 1 ? ' Karte' : ' Karten') + ende);
        z.push('Passt auf ' + f + ' oder auf jede +' + n + '.');
        if (stapeln) z.push('Stapeln ist an: Wer selbst eine +' + n + ' hat, gibt weiter, und die Summe wächst.');
        break;
      }
      case 'aussetzen': z.push('Der Nächste setzt aus.', 'Passt auf ' + f + ' oder auf jedes Aussetzen.'); break;
      case 'alle_aussetzen': z.push('Alle anderen setzen aus – du bist sofort noch einmal dran.', 'Passt auf ' + f + ' oder auf jedes Alle aussetzen.'); break;
      case 'richtungswechsel':
        z.push('Die Spielrichtung dreht sich um.' + (r.two_player_reverse_skips !== false ? ' Zu zweit wirkt sie wie Aussetzen.' : ''));
        z.push('Passt auf ' + f + ' oder auf jeden Richtungswechsel.');
        break;
      case 'flip':
        z.push(r.flip_mode === 'card'
          ? 'Nachziehstapel und alle Hände werden gewendet, von der Ablage nur dieser Flip: Oben liegt seine andere Seite, die übrige Ablage bleibt zur Seite gelegt. Ab jetzt gilt die andere Seite.'
          : 'Alles wird gewendet: Ablage, Nachziehstapel und alle Hände. Oben liegt dann die bisher unterste Ablagekarte mit ihrer anderen Seite. Ab jetzt gilt die andere Seite.');
        z.push('Passt auf ' + f + ' oder auf jeden Flip.');
        if ((r.flip_last_card || 'execute') === 'execute') z.push('Als letzte Karte wird der Flip noch ausgeführt; gewertet wird die neue Seite.');
        z.push(r.flip_surprise === 'on'
          ? 'Flip-Überraschung ist an: Liegt danach eine Aktionskarte oben (+1/+5, Aussetzen, Alle aussetzen, Richtungswechsel, Wünscher +2, Farbjagd), wirkt sie auf den Nächsten – als hättest du sie gelegt. Bei Wünscher +2 und Farbjagd wählst du zuerst die Farbe.'
          : 'Die Aktionskarte, die danach oben liegt, wirkt nicht.');
        break;
      case 'wuenscher': z.push('Passt immer. Du wünschst dir eine Farbe – auch die bisherige.'); break;
      case 'wuenscher_plus2':
        z.push('Du wünschst dir eine Farbe. Der Nächste zieht 2 Karten' + ende, bluffText(r));
        if (stapeln) z.push('Stapeln ist an: Ein Wünscher +2 darf mit einem Wünscher +2 beantwortet werden.');
        break;
      case 'farbjagd':
        z.push('Du wünschst dir eine Farbe. Der Nächste zieht so lange, bis er eine Karte dieser Farbe hat, behält alle' + ende);
        z.push(r.jagd_wild_stops ? 'Ein gezogener Joker beendet das Ziehen.' : 'Ein gezogener Joker beendet das Ziehen nicht.');
        z.push(bluffText(r));
        break;
      // Hausregel-Karten (Texte wie RulesText._swap_lines/_gamble_lines/_discard_lines)
      case 'tausch':
        z.push('Alle geben gleichzeitig ihre ganze Hand an den Nächsten weiter, ' + tauschRichtung(r) + '. Danach ist ganz normal der Nächste in Spielrichtung dran.');
        if (r.swap_direction === 'play' || r.swap_direction === 'against') z.push('Nach einem Richtungswechsel wandern die Hände also andersherum.');
        z.push('Passt auf ' + f + ' und auf jeden Kartentausch.', 'Zu zweit tauscht ihr einfach eure Hände.');
        z.push(r.round_end === 'last' ? 'Auch als letzte Karte: Du bist fertig, die anderen tauschen trotzdem untereinander.'
          : 'Auch als letzte Karte: Du bist fertig und gewinnst die Runde; getauscht wird dann nicht mehr.');
        if (r.mau_call !== 'off') z.push('Wer durch den Tausch nur noch 1 Karte hat, muss nicht „Mau!“ rufen.');
        if (r.swap_cards !== 'on') z.push('Gehört zur Hausregel Kartentausch (gerade nicht im Spiel).');
        break;
      case 'gluecksspiel':
        z.push('Joker: passt immer. Du wünschst eine Farbe; sie gilt nach dem Glücksspiel.');
        z.push('Dann spielst du um dein Glück: Leg eine beliebige Karte verdeckt auf deinen Einsatz und drück den Glücksspielknopf. Zeigt er 0, setzt du die nächste Karte.');
        z.push('Aufhören darfst du immer nach einem Druck ohne Treffer: Dein Einsatz kommt unter den Ablagestapel, dein Zug ist vorbei.');
        z.push('Für jedes Glücksspiel wird geheim eine Trefferquote zwischen 1:1 und 1:10 ausgelost.');
        z.push('Treffer: Der Knopf zeigt 1 bis 10. So viele Karten ziehst du, nimmst deinen ganzen Einsatz zurück, und dein Zug ist vorbei.');
        z.push('Zeigt er 0 und deine Hand ist leer, kommt der Einsatz unter den Ablagestapel und du bist fertig' + (r.round_end === 'last' ? '.' : ' – du gewinnst die Runde.'));
        z.push('Die Einsatzkarten liegen verdeckt und wirken nicht, auch kein Flip.');
        if (r.mau_call !== 'off') z.push('Bleibt dir nach dem Setzen nur noch 1 Karte, ruf „Mau!“ – wie beim Legen, auch wenn du danach aufhörst.');
        if (stapeln) z.push('Liegt eine Ziehstrafe auf dir, passt das Glücksspiel nicht (wie jeder andere Joker).');
        z.push('Als letzte Karte bist du einfach fertig; dann gibt es kein Glücksspiel.');
        if (r.gamble_cards !== 'on') z.push('Gehört zur Hausregel Glücksspiel (gerade nicht im Spiel).');
        break;
      case 'ablegen': case 'ablegen_joker': {
        if (k.art === 'ablegen') z.push('Du wählst, welche deiner anderen Karten in ' + f + ' mit abgelegt werden (alle sind vorausgewählt). Sie kommen unter diese Karte, die oben bleibt.', 'Passt auf ' + f + ' und auf jede andere Ablegen-Karte.');
        else z.push('Joker: passt immer. Erst wählst du die Farbe zum Mitablegen, dann die Karten, zum Schluss die Farbe, mit der es weitergeht (auch eine andere).');
        z.push('Joker auf deiner Hand bleiben dort. Mitabgelegte Aktionskarten wirken nicht.');
        const ende = r.round_end === 'last' ? 'bist du fertig' : 'gewinnst du die Runde';
        z.push(r.mau_call !== 'off' ? 'Bleibt dir danach 1 Karte, ruf „Mau!“ (auch schon vorher erlaubt); bleibt keine, ' + ende + '.' : 'Bleibt dir danach keine Karte, ' + ende + '.');
        if (r.discard_color !== 'on') z.push('Gehört zur Hausregel Farbe ablegen (gerade nicht im Spiel).');
        break;
      }
      default: z.push('Die Gegenseite einer Karte. Welche Seite gilt, entscheidet der letzte Flip.');
    }
    if (k.art !== 'rueckseite') z.push('Wert bei der Abrechnung: ' + punkte(key) + ' Punkte.');
    return { titel: kartenName(key), zeilen: z };
  }
  const tauschRichtung = r => ({ counter: 'immer gegen den Uhrzeigersinn', play: 'in der aktuellen Spielrichtung', against: 'gegen die aktuelle Spielrichtung' }[r && r.swap_direction] || 'immer im Uhrzeigersinn');
  // Regelübersicht (Lobby, Menü)
  function regelnText(regeln) {
    const r = regeln || {};
    const z = [];
    z.push(r.round_end === 'last' ? 'Gespielt wird bis zum Letzten (Platzierungen).' : 'Wer zuerst alle Karten los ist, gewinnt die Runde.');
    if (r.scoring === 'points500') z.push('Punktewertung: Der Sieger bekommt die Restpunkte, Partie bis ' + (r.target || 500) + '.');
    z.push((r.hand_size || 7) + ' Karten zu Beginn.');
    z.push(r.draw_rule === 'until_playable' ? 'Ziehen: so lange, bis eine Karte passt.' : 'Ziehen: eine Karte.');
    z.push({ must: 'Eine passende gezogene Karte muss gelegt werden.', may_not: 'Eine gezogene Karte darf nicht sofort gelegt werden.' }[r.drawn_card] || 'Eine passende gezogene Karte darf sofort gelegt werden.');
    if (r.stacking === 'same') z.push('Gleiche Ziehkarten dürfen gestapelt werden.');
    if (r.penalty_turn === 'play') z.push('Nach dem Strafziehen bist du trotzdem dran und darfst legen.');
    z.push(r.wild_restriction === 'enforce' ? 'Wünscher +2 und Farbjagd nur ohne Karte der aktuellen Farbe (App prüft).' : 'Wünscher +2 und Farbjagd sind immer erlaubt.');
    const pen = r.mau_penalty || 2;
    z.push({ auto: 'Vergessenes „Mau!“ kostet sofort ' + (pen === 1 ? 'eine Karte' : pen + ' Karten') + '.', reminder: '„Mau!“ wird nur angezeigt, ohne Strafe.', off: 'Ohne „Mau!“-Ansage.' }[r.mau_call] || 'Wer „Mau!“ vergisst, kann erwischt werden (' + (pen === 1 ? 'eine Strafkarte' : pen + ' Strafkarten') + ').');
    if (r.backs_visible === false) z.push('Rückseiten der Mitspieler sind verdeckt.');
    // Hausregeln mit Zusatzkarten (wie RuleConfig.describe)
    if (r.swap_cards === 'on') z.push('Kartentausch: Wer einen legt, lässt alle ihre ganze Hand an den Nächsten weitergeben, ' + tauschRichtung(r) + '.');
    if (r.gamble_cards === 'on') z.push('Glücksspiel (2 Joker): verdeckt setzen und drücken – weiter riskieren oder aufhören. Treffer: 1 bis 10 Karten ziehen, Einsatz zurück; Aufhören: Einsatz unter die Ablage.');
    if (r.discard_color === 'on') z.push('Farbe ablegen: Wer eine Ablegen-Karte legt, wählt eigene Karten dieser Farbe zum Mitablegen; Joker bleiben auf der Hand. Beim Ablegen-Joker wählst du Ablegefarbe und Spielfarbe getrennt.');
    if (r.flip_mode === 'card') z.push('Flip dreht nur die gelegte Karte: Oben liegt ihre andere Seite, die übrige Ablage bleibt zur Seite gelegt.');
    if (r.flip_surprise === 'on') z.push('Flip-Überraschung: Die Aktionskarte, die nach dem Flip oben liegt, wirkt auf den Nächsten.');
    if (kartenZahl(r) > 112) z.push('Gespielt wird mit ' + kartenZahl(r) + ' Karten.');
    return z;
  }

  // Besondere Karten für „Regeln“ im Spielmenü: je Art eine Beispielkarte mit Name und Wirkung (die ersten Zeilen aus hilfe()).
  // Zusatzkarten nur, wenn ihre Hausregel an ist.
  function besondereKarten(regeln) {
    const r = regeln || {};
    const karte = key => {
      const art = zerlege(key).art;
      const zeilen = hilfe(key, r).zeilen.filter(z => !/^(Passt auf|Wert bei|Gehört zur)/.test(z)).slice(0, 2);
      return { key, name: art === 'ablegen' ? 'Ablegen-Karte' : (ART_NAME[art] || art), zeilen };
    };
    const g = [
      { titel: 'Helle Seite', karten: ['hell_rot_plus1', 'hell_rot_aussetzen', 'hell_rot_richtungswechsel', 'hell_rot_flip', 'hell_wuenscher', 'hell_wuenscher_plus2'].map(karte) },
      { titel: 'Dunkle Seite (nach einem Flip)', hinweis: 'Richtungswechsel, Flip und Wünscher gibt es hier auch.', karten: ['dunkel_pink_plus5', 'dunkel_pink_alle_aussetzen', 'dunkel_farbjagd'].map(karte) },
    ];
    const haus = [];
    if (r.swap_cards === 'on') haus.push('hell_rot_tausch');
    if (r.gamble_cards === 'on') haus.push('hell_gluecksspiel');
    if (r.discard_color === 'on') haus.push('hell_rot_ablegen', 'hell_ablegen_joker');
    if (haus.length) g.push({ titel: 'Zusatzkarten (Hausregeln)', hinweis: 'Gibt es auf beiden Seiten.', karten: haus.map(karte) });
    return g;
  }

  /* ---------------- Symbole (aus Entwurf A, Box 100×100) ---------------- */
  const f1 = v => (Math.round(v * 10) / 10).toString();
  function polar(cx, cy, r, deg) { const a = (deg - 90) * Math.PI / 180; return [cx + r * Math.cos(a), cy + r * Math.sin(a)]; }
  function starPath(cx, cy, n, ro, ri, rot) {
    let d = '';
    for (let i = 0; i < n * 2; i++) {
      const [x, y] = polar(cx, cy, i % 2 ? ri : ro, (rot || 0) + i * 180 / n);
      d += (i ? 'L' : 'M') + f1(x) + ' ' + f1(y);
    }
    return d + 'Z';
  }
  function symbolPrims(name) {
    switch (name) {
      case 'flamme': return [
        { d: 'M50 3C59 19 81 33 81 61C81 83 66 97 50 97C34 97 19 83 19 61C19 46 27 36 36 28C36 40 40 48 47 51C43 37 43 19 50 3Z', role: 'main' },
        { d: 'M51 55C57 63 63 69 63 78C63 87 57 92 50 92C43 92 38 87 38 79C38 71 44 64 51 55Z', role: 'cut' }];
      case 'sonne': {
        const p = [{ d: 'M50 29a21 21 0 1 0 0.01 0Z', role: 'main' }];
        let d = '';
        for (let i = 0; i < 8; i++) {
          const a = i * 45;
          const [x1, y1] = polar(50, 50, 30, a - 9), [x2, y2] = polar(50, 50, 30, a + 9), [x3, y3] = polar(50, 50, 48, a);
          d += 'M' + f1(x1) + ' ' + f1(y1) + 'L' + f1(x3) + ' ' + f1(y3) + 'L' + f1(x2) + ' ' + f1(y2) + 'Z';
        }
        p.push({ d, role: 'main' });
        return p;
      }
      case 'klee': {
        const heart = 'M0 0C-7 -6 -25 -14 -25 -29C-25 -39 -17 -45 -9 -45C-4 -45 0 -41 0 -36C0 -41 4 -45 9 -45C17 -45 25 -39 25 -29C25 -14 7 -6 0 0Z';
        return [{ d: 'M50 54C52 70 58 82 70 95', kind: 'line', w: 8, role: 'main' }].concat([0, 120, 240].map(a => ({ d: heart, tf: 'translate(50 52) rotate(' + a + ')', role: 'main' })));
      }
      case 'kristall': return [
        { d: 'M28 13H72L93 38L50 95L7 38Z', role: 'main' },
        { d: 'M7 38H93M28 13L39 38L50 95M72 13L61 38L50 95M39 38L50 13L61 38', kind: 'line', w: 3.2, role: 'cut' }];
      case 'herz': return [{ d: 'M50 91C43 85 7 63 7 36C7 20 19 9 32 9C40 9 46 13 50 21C54 13 60 9 68 9C81 9 93 20 93 36C93 63 57 85 50 91Z', role: 'main' }];
      case 'welle': return [
        { d: 'M8 36C19 20 30 20 39 34C48 48 59 48 70 34C79 22 88 22 94 30', kind: 'line', w: 13, role: 'main' },
        { d: 'M8 68C19 52 30 52 39 66C48 80 59 80 70 66C79 54 88 54 94 62', kind: 'line', w: 13, role: 'main' }];
      case 'laterne': return [
        { d: 'M50 4a9 9 0 1 1 -0.01 0Z', kind: 'line', w: 6, role: 'main' },
        { d: 'M33 20H67V31H33Z', role: 'main' },
        { d: 'M31 31H69L84 55L69 82H31L16 55Z', role: 'main' },
        { d: 'M36 82H64V93H36Z', role: 'main' },
        { d: 'M50 42C55 50 59 55 59 61C59 67 55 71 50 71C45 71 41 67 41 61C41 55 45 50 50 42Z', role: 'cut' }];
      case 'stern': return [{ d: starPath(50, 54, 5, 46, 20), role: 'main', join: 6 }];
    }
    return [];
  }
  const CAT_HEAD = 'M13 62C13 49 16 41 21 35L23 9C23 6 26 5 28 7L44 25C48 24 52 24 56 25L72 7C74 5 77 6 77 9L79 35C84 41 87 49 87 62C87 82 71 94 50 94C29 94 13 82 13 62Z';
  function catHeadPrims(tf, front) {
    const p = [{ d: CAT_HEAD, role: 'main', tf, front }];
    p.push({ d: 'M26 60Q33 67 41 60M59 60Q67 67 74 60', kind: 'line', w: 5.5, role: 'cut', tf });
    p.push({ d: 'M45 69H55L50 75Z', role: 'cut', tf });
    return p;
  }
  function arcArrow(cx, cy, r, a0, a1, w, head) {
    const back = (head * 0.9) / r * 180 / Math.PI;
    const aEnd = a1 - back;
    const [x0, y0] = polar(cx, cy, r, a0), [x1, y1] = polar(cx, cy, r, aEnd);
    const large = (aEnd - a0) > 180 ? 1 : 0;
    const arcD = 'M' + f1(x0) + ' ' + f1(y0) + 'A' + r + ' ' + r + ' 0 ' + large + ' 1 ' + f1(x1) + ' ' + f1(y1);
    const [hx, hy] = polar(cx, cy, r, a1 + 2), [ox, oy] = polar(cx, cy, r + head * 0.85, aEnd), [ix, iy] = polar(cx, cy, r - head * 0.85, aEnd);
    return [{ d: arcD, kind: 'line', w, role: 'main', cap: 'butt' },
      { d: 'M' + f1(ox) + ' ' + f1(oy) + 'L' + f1(hx) + ' ' + f1(hy) + 'L' + f1(ix) + ' ' + f1(iy) + 'Z', role: 'main', join: 3 }];
  }
  function iconPrims(name) {
    switch (name) {
      case 'schlaf': return catHeadPrims('');
      case 'schlaf3': return catHeadPrims('translate(-2 2) scale(.56)').concat(catHeadPrims('translate(46 2) scale(.56)'), catHeadPrims('translate(22 42) scale(.58)', true));
      case 'wende': return arcArrow(50, 50, 33, 236, 30, 12, 17).concat(arcArrow(50, 50, 33, 56, 210, 12, 17));
      case 'flip': return [
        { d: 'M50 6a44 44 0 1 0 0.01 0Z', role: 'main' },
        { d: 'M81.1 18.9A44 44 0 0 1 18.9 81.1Z', role: 'dark' },
        { d: 'M74 50a15 15 0 1 1 -16 22a12 12 0 1 0 16 -22Z', role: 'cut' },
        { d: 'M36 39a9 9 0 1 0 0.01 0Z', role: 'sun' }];
      // Ersatzsymbole der Hausregel-Karten (nur ohne Kartenbilder): Karte im Pfeilkreis, Kartenfächer mit Pfeil, Knopf mit Anzeige
      case 'tausch': return arcArrow(50, 50, 38, 236, 30, 9, 14).concat(arcArrow(50, 50, 38, 56, 210, 9, 14),
        [{ d: 'M38 30h24v40h-24Z', role: 'main', join: 6 }, { d: 'M43 36h14v28h-14Z', role: 'cut' }]);
      case 'ablegen': return [
        { d: 'M14 16h20v30h-20Z', role: 'main', join: 5 }, { d: 'M40 10h20v30h-20Z', role: 'main', join: 5 }, { d: 'M66 16h20v30h-20Z', role: 'main', join: 5 },
        { d: 'M50 50V74', kind: 'line', w: 11, role: 'main' }, { d: 'M32 68L50 92L68 68Z', role: 'main', join: 4 }];
      case 'gluecksspiel': return [
        { d: 'M20 60a30 30 0 0 1 60 0Z', role: 'main' }, { d: 'M8 60h84v26h-84Z', role: 'main', join: 6 },
        { d: 'M30 66h40v14h-40Z', role: 'cut' }, { d: 'M43 40a7 7 0 1 1 10 6v4', kind: 'line', w: 4.5, role: 'cut' }];
      case 'pfote': return [
        { d: 'M50 50C64 50 80 64 80 78C80 89 72 94 64 94C57 94 54 90 50 90C46 90 43 94 36 94C28 94 20 89 20 78C20 64 36 50 50 50Z', role: 'main' },
        { d: 'M12 40a10 13 -20 1 0 20 -6a10 13 -20 1 0 -20 6Z', role: 'toe1' },
        { d: 'M30 20a11 14 -6 1 0 22 0a11 14 -6 1 0 -22 0Z', role: 'toe2' },
        { d: 'M48 20a11 14 6 1 0 22 0a11 14 6 1 0 -22 0Z', role: 'toe3' },
        { d: 'M68 34a10 13 20 1 0 20 6a10 13 20 1 0 -20 -6Z', role: 'toe4' }];
    }
    return [];
  }
  // Primitive zeichnen; mode 'sil' = Umriss (Silhouette) für Konturen
  function renderPrims(prims, colors, mode, outline) {
    let out = '';
    outline = outline || 0;
    for (const p of prims) {
      const tf = p.tf ? ' transform="' + p.tf + '"' : '';
      if (mode === 'sil') {
        if (p.role === 'cut' || p.role === 'sun') continue;
        const col = colors.sil;
        if (p.kind === 'line') out += '<path d="' + p.d + '"' + tf + ' fill="none" stroke="' + col + '" stroke-width="' + (p.w + outline * 2) + '" stroke-linecap="' + (p.cap || 'round') + '" stroke-linejoin="round"/>';
        else out += '<path d="' + p.d + '"' + tf + ' fill="' + col + '" stroke="' + col + '" stroke-width="' + (outline * 2 + (p.join || 0)) + '" stroke-linejoin="round"/>';
        continue;
      }
      const col = colors[p.role] || colors.main;
      if (p.front && colors.frontRing) out += '<path d="' + p.d + '"' + tf + ' fill="none" stroke="' + colors.frontRing + '" stroke-width="9" stroke-linejoin="round"/>';
      if (p.kind === 'line') out += '<path d="' + p.d + '"' + tf + ' fill="none" stroke="' + col + '" stroke-width="' + p.w + '" stroke-linecap="' + (p.cap || 'round') + '" stroke-linejoin="round"/>';
      else if (p.join) out += '<path d="' + p.d + '"' + tf + ' fill="' + col + '" stroke="' + col + '" stroke-width="' + p.join + '" stroke-linejoin="round"/>';
      else out += '<path d="' + p.d + '"' + tf + ' fill="' + col + '"/>';
    }
    return out;
  }
  // Farbsymbol als SVG-Text (für Farbanzeige, Farbwahl, Ersatzkarten)
  function symbolSVG(farbe, opt) {
    const fi = FARB_INFO[farbe];
    if (!fi) return '';
    const o = opt || {};
    const dunkel = FARBEN.dunkel.indexOf(farbe) >= 0;
    const main = o.farbe || (dunkel ? fi.ring : fi.hex);
    const cut = o.grund || (dunkel ? NIGHT : PAPER);
    const kontur = o.kontur ? renderPrims(symbolPrims(fi.sym), { sil: o.kontur }, 'sil', o.konturBreite || 5) : '';
    return '<svg class="sym" viewBox="-6 -6 112 112" aria-hidden="true">' + kontur + renderPrims(symbolPrims(fi.sym), { main, cut }) + '</svg>';
  }
  function iconSVG(name, colors, kontur) {
    const prims = iconPrims(name);
    return '<svg class="ico" viewBox="-6 -6 112 112" aria-hidden="true">' + (kontur ? renderPrims(prims, { sil: kontur }, 'sil', 5) : '') + renderPrims(prims, colors) + '</svg>';
  }

  /* ---------------- Ersatzkarte als SVG (Format 56:87, viewBox 560×870) ---------------- */
  const CW = 560, CH = 870, M0 = 30, TW = 158, TH = 262;
  const ICON_ART = { aussetzen: 'schlaf', alle_aussetzen: 'schlaf3', richtungswechsel: 'wende', flip: 'flip', wuenscher: 'pfote',
    tausch: 'tausch', ablegen: 'ablegen', ablegen_joker: 'ablegen', gluecksspiel: 'gluecksspiel' };
  function hexRgb(h) { h = h.replace('#', ''); return [0, 2, 4].map(i => parseInt(h.substr(i, 2), 16)); }
  function mix(a, b, t) { const A = hexRgb(a), B = hexRgb(b); return '#' + A.map((v, i) => Math.round(v + (B[i] - v) * t).toString(16).padStart(2, '0')).join(''); }
  // Farbfeld mit Laschen oben links und unten rechts (eingerückt, runde Ecken über Kontur)
  const FELD_PUNKTE = [[TW + 10, M0 + 10], [CW - M0 - 10, M0 + 10], [CW - M0 - 10, CH - TH - 10], [CW - TW - 10, CH - TH - 10], [CW - TW - 10, CH - M0 - 10], [M0 + 10, CH - M0 - 10], [M0 + 10, TH + 10], [TW + 10, TH + 10]];
  const FELD = FELD_PUNKTE.map(p => p.join(',')).join(' ');
  const FELD_UMFANG = (function () { let u = 0; for (let i = 0; i < FELD_PUNKTE.length; i++) { const a = FELD_PUNKTE[i], b = FELD_PUNKTE[(i + 1) % FELD_PUNKTE.length]; u += Math.hypot(b[0] - a[0], b[1] - a[1]); } return u; })();
  const FONT = "font-family=\"'Bricolage Grotesque','Arial Narrow',Arial,sans-serif\"";
  function text(x, y, size, inhalt, fill, extra) {
    return '<text x="' + x + '" y="' + y + '" text-anchor="middle" ' + FONT + ' font-weight="800" font-size="' + size + '" fill="' + fill + '" style="font-variation-settings:\'opsz\' 12' + (extra && extra.wdth ? ",'wdth' " + extra.wdth : '') + '"' + (extra && extra.stroke ? ' stroke="' + extra.stroke + '" stroke-width="' + extra.sw + '" paint-order="stroke" stroke-linejoin="round"' : '') + '>' + inhalt + '</text>';
  }
  function gruppe(inhalt, x, y, s, rot) { return '<g transform="translate(' + x + ' ' + y + ')' + (rot ? ' rotate(180 ' + (50 * s) + ' ' + (50 * s) + ')' : '') + ' scale(' + s + ')">' + inhalt + '</g>'; }
  const TOES_HELL = { toe1: FARB_INFO.rot.hex, toe2: FARB_INFO.gelb.hex, toe3: FARB_INFO.gruen.hex, toe4: FARB_INFO.blau.hex };
  const TOES_DUNKEL = { toe1: FARB_INFO.pink.ring, toe2: FARB_INFO.tuerkis.ring, toe3: FARB_INFO.orange.ring, toe4: FARB_INFO.lila.ring };

  // Index (Wert + Symbol) in der Lasche oben links; unten rechts gedreht
  function index(k, hell, farbHex) {
    const tint = hell ? INK : farbHex;
    let g = '';
    const kw = kurzWert(k);
    if (kw) g += text(94, 150, kw.length > 1 ? 104 : 128, kw, tint, { wdth: 75 });
    else if (ICON_ART[k.art]) g += gruppe(renderPrims(iconPrims(ICON_ART[k.art]), hell ? { main: INK, cut: PAPER, dark: INK, sun: PAPER } : { main: farbHex, cut: NIGHT, dark: NIGHT, sun: farbHex }), 44, 52, 1.0);
    if (k.wert === 6 || k.wert === 9) g += '<rect x="70" y="160" width="48" height="10" rx="5" fill="' + tint + '"/>';
    if (k.farbe) g += gruppe(renderPrims(symbolPrims(FARB_INFO[k.farbe].sym), { main: hell ? FARB_INFO[k.farbe].hex : farbHex, cut: hell ? PAPER : NIGHT }), 64, 180, 0.6);
    else g += gruppe(renderPrims(iconPrims('pfote'), Object.assign({ main: hell ? INK : MOON }, hell ? TOES_HELL : TOES_DUNKEL)), 64, 180, 0.6);
    return g + '<g transform="rotate(180 ' + CW / 2 + ' ' + CH / 2 + ')">' + g + '</g>';
  }
  function mitte(k, hell, farbHex) {
    const fill = hell ? CREAM : MOON, stroke = hell ? INK : farbHex;
    const kw = kurzWert(k);
    if (k.art === 'zahl') {
      let s = text(280, 545, 330, kw, fill, { stroke, sw: hell ? 14 : 10 });
      if (k.wert === 6 || k.wert === 9) s += '<rect x="215" y="572" width="130" height="22" rx="11" fill="' + fill + '" stroke="' + stroke + '" stroke-width="' + (hell ? 8 : 6) + '"/>';
      return s;
    }
    if (k.art === 'wuenscher' || k.art === 'wuenscher_plus2' || k.art === 'farbjagd') {
      const toes = hell ? TOES_HELL : TOES_DUNKEL;
      let s = gruppe(renderPrims(iconPrims('pfote'), { sil: hell ? INK : MOON }, 'sil', 5) + renderPrims(iconPrims('pfote'), Object.assign({ main: hell ? CREAM : NIGHT }, toes)), 160, k.art === 'wuenscher' ? 310 : 400, 2.4);
      if (k.art !== 'wuenscher') s += text(280, 390, 220, kw, fill, { stroke: hell ? INK : '#FFB3DC', sw: hell ? 12 : 8 });
      return s;
    }
    if (ICON_ART[k.art]) {
      const prims = iconPrims(ICON_ART[k.art]);
      return gruppe(renderPrims(prims, { sil: stroke }, 'sil', 5) + renderPrims(prims, { main: fill, cut: hell ? farbHex : NIGHT, dark: hell ? mix(farbHex, INK, .35) : mix(NIGHT, farbHex, .4), sun: hell ? FARB_INFO.gelb.hex : MOON }), 150, 300, 2.6);
    }
    return text(280, 530, 280, kw, fill, { stroke, sw: hell ? 14 : 10 });
  }
  function hellSVG(k) {
    const fi = FARB_INFO[k.farbe];
    let s = '<rect width="560" height="870" rx="40" fill="' + PAPER + '"/><rect x="5" y="5" width="550" height="860" rx="36" fill="none" stroke="' + PAPER_D + '" stroke-width="6"/>';
    if (fi) {
      s += '<polygon points="' + FELD + '" fill="' + fi.hex + '" stroke="' + fi.hex + '" stroke-width="20" stroke-linejoin="round"/>';
      let rays = '';
      for (let i = 0; i < 16; i += 2) {
        const [x1, y1] = polar(280, 430, 225, i * 22.5 - 6), [x2, y2] = polar(280, 430, 225, i * 22.5 + 6);
        rays += 'M280 430L' + f1(x1) + ' ' + f1(y1) + 'L' + f1(x2) + ' ' + f1(y2) + 'Z';
      }
      s += '<path d="' + rays + '" fill="#fff" opacity=".1"/>';
      s += '<circle cx="280" cy="430" r="132" fill="' + mix(fi.hex, CREAM, .28) + '"/>';
      [[580, 280], [612, 220], [644, 160], [676, 110], [708, 64]].forEach(([y, w]) => { s += '<rect x="' + (280 - w / 2) + '" y="' + y + '" width="' + w + '" height="14" rx="7" fill="' + mix(fi.hex, fi.tief, .7) + '"/>'; });
    } else {
      // Joker: vier Farbfelder
      const q = [['rot', M0, M0], ['gelb', CW / 2, M0], ['gruen', M0, CH / 2], ['blau', CW / 2, CH / 2]];
      s += q.map(([f, x, y]) => '<rect x="' + x + '" y="' + y + '" width="' + (CW / 2 - M0) + '" height="' + (CH / 2 - M0) + '" fill="' + FARB_INFO[f].hex + '"/>').join('');
      s += '<rect x="' + (M0 - 2) + '" y="' + (M0 - 2) + '" width="' + (TW - M0 + 2) + '" height="' + (TH - M0 + 2) + '" fill="' + PAPER + '"/><rect x="' + (CW - TW) + '" y="' + (CH - TH) + '" width="' + (TW - M0 + 2) + '" height="' + (TH - M0 + 2) + '" fill="' + PAPER + '"/>';
      s += '<circle cx="280" cy="435" r="150" fill="' + CREAM + '" opacity=".22"/>';
    }
    return s + mitte(k, true, fi ? fi.hex : INK) + index(k, true, fi ? fi.hex : INK);
  }
  function dunkelSVG(k) {
    const fi = FARB_INFO[k.farbe];
    const neon = fi ? fi.ring : MOON;
    let s = '<rect width="560" height="870" rx="40" fill="' + NIGHT + '"/><rect x="6" y="6" width="548" height="858" rx="35" fill="none" stroke="' + (fi ? fi.tief : '#3A3F6B') + '" stroke-width="5"/>';
    if (fi) {
      s += '<polygon points="' + FELD + '" fill="' + mix(NIGHT, fi.hex, .16) + '" stroke="' + neon + '" stroke-opacity=".22" stroke-width="26" stroke-linejoin="round"/>';
      s += '<polygon points="' + FELD + '" fill="none" stroke="' + neon + '" stroke-width="8" stroke-linejoin="round"/>';
    } else {
      // Joker: Regenbogen-Neonkontur
      const farben = ['pink', 'tuerkis', 'orange', 'lila'];
      s += '<polygon points="' + FELD + '" fill="' + mix(NIGHT, '#3A2D7A', .25) + '"/>';
      farben.forEach((f, i) => { s += '<polygon points="' + FELD + '" fill="none" stroke="' + FARB_INFO[f].ring + '" stroke-width="9" stroke-dasharray="' + f1(FELD_UMFANG / 4) + ' ' + f1(FELD_UMFANG * 3 / 4) + '" stroke-dashoffset="' + f1(-i * FELD_UMFANG / 4) + '"/>'; });
    }
    // Mondsichel, Sterne, Spiegellinien
    s += '<circle cx="280" cy="430" r="132" fill="' + mix(NIGHT, MOON, .2) + '"/><circle cx="326" cy="404" r="116" fill="' + (fi ? mix(NIGHT, fi.hex, .16) : mix(NIGHT, '#3A2D7A', .25)) + '"/>';
    [[200, 300, 10], [430, 330, 7], [380, 560, 6], [175, 540, 7], [440, 200, 6]].forEach(([x, y, r]) => { s += '<path d="' + starPath(x, y, 4, r * 1.6, r * .45, 0) + '" fill="' + MOON + '" opacity=".75"/>'; });
    [[600, 200], [628, 150], [656, 100], [684, 60]].forEach(([y, w]) => { s += '<rect x="' + (280 - w / 2) + '" y="' + y + '" width="' + w + '" height="5" rx="2.5" fill="' + neon + '" opacity=".55"/>'; });
    return s + mitte(k, false, neon) + index(k, false, neon);
  }
  function rueckSVG() {
    let s = '<rect width="560" height="870" rx="40" fill="#141A3A"/><rect x="22" y="22" width="516" height="826" rx="26" fill="none" stroke="#3B4280" stroke-width="6"/>';
    let pts = '';
    for (let y = 70; y < 830; y += 56) for (let x = 70 + ((y / 56) % 2) * 28; x < 500; x += 56) pts += 'M' + x + ' ' + (y - 9) + 'L' + (x + 9) + ' ' + y + 'L' + x + ' ' + (y + 9) + 'L' + (x - 9) + ' ' + y + 'Z';
    s += '<path d="' + pts + '" fill="#262D5E"/>';
    s += '<circle cx="280" cy="435" r="120" fill="#141A3A"/>' + gruppe(renderPrims(iconPrims('flip'), { main: '#F4EADA', dark: '#2A3170', cut: '#F4EADA', sun: '#FFDD33' }), 190, 345, 1.8);
    return s;
  }
  const _svg = new Map();
  function karteSVG(key) {
    let s = _svg.get(key);
    if (s) return s;
    const k = zerlege(key);
    const inhalt = k.art === 'rueckseite' ? rueckSVG() : (k.seite === 'dunkel' ? dunkelSVG(k) : hellSVG(k));
    s = '<svg class="kf" viewBox="0 0 560 870" preserveAspectRatio="none" aria-hidden="true">' + inhalt + '</svg>';
    _svg.set(key, s);
    return s;
  }

  /* ---------------- Bilder ---------------- */
  // Prüft einmal, ob Modul B Kartenbilder bzw. Farbsymbole geliefert hat; sonst Ersatz-SVG ohne Fehlanfragen.
  const Bilder = { karten: false, symbole: false, geprueft: false, beiFertig: [] };
  function pruefeBilder(cb) {
    if (cb) Bilder.beiFertig.push(cb);
    if (Bilder._laeuft) return;
    Bilder._laeuft = true;
    let offen = 2;
    const fertig = () => { if (--offen) return; Bilder.geprueft = true; Bilder.beiFertig.splice(0).forEach(f => { try { f(); } catch (e) { setTimeout(() => { throw e; }); } }); };
    const probe = (src, key) => { const i = new Image(); i.onload = () => { Bilder[key] = i.naturalWidth > 0; fertig(); }; i.onerror = () => { Bilder[key] = false; fertig(); }; i.src = src; };
    if (M.param && M.param('bilder') === '0') { offen = 1; fertig(); return; }
    probe('cards/hell_rot_1.webp', 'karten');
    probe('cards/farbe_rot.webp', 'symbole');
  }
  // Inhalt einer Kartenseite (Bild oder Ersatz)
  function gesichtHTML(key) {
    key = key || 'rueckseite';
    if (Bilder.karten) return '<img class="kb" src="cards/' + key + '.webp" alt="" draggable="false" data-face="' + key + '">';
    return karteSVG(key);
  }
  // fehlendes Einzelbild → Ersatz
  document.addEventListener('error', e => {
    const t = e.target;
    if (t && t.tagName === 'IMG' && t.classList.contains('kb') && t.dataset.face) {
      const span = document.createElement('span');
      span.className = 'kfh';
      span.innerHTML = karteSVG(t.dataset.face);
      t.replaceWith(span.firstChild);
    } else if (t && t.tagName === 'IMG' && t.classList.contains('sym') && t.dataset.farbe) {
      const span = document.createElement('span');
      span.innerHTML = symbolSVG(t.dataset.farbe, { kontur: '#F4EADA', konturBreite: 4 });
      t.replaceWith(span.firstChild);
    }
  }, true);
  // Farbsymbol (Bild oder SVG)
  function farbSymbolHTML(farbe, opt) {
    if (Bilder.symbole) return '<img class="sym" src="cards/farbe_' + farbe + '.webp" alt="" draggable="false" data-farbe="' + farbe + '">';
    return symbolSVG(farbe, opt);
  }
  // Kartenelement in Logik-Pixeln (w = Breite), Ursprung oben links
  function element(key, w, cls) {
    const el = document.createElement('div');
    el.className = 'karte' + (cls ? ' ' + cls : '');
    el.style.width = w + 'px';
    el.style.height = Math.round(w * CH / CW) + 'px';
    el.dataset.face = key || 'rueckseite';
    el.innerHTML = gesichtHTML(key);
    return el;
  }
  function setzeGesicht(el, key) {
    key = key || 'rueckseite';
    if (el.dataset.face === key) return;
    el.dataset.face = key;
    el.innerHTML = gesichtHTML(key);
  }

  M.Karten = {
    INK, PAPER, CREAM, NIGHT, MOON, FARBEN, FARB_INFO, VERHAELTNIS: CH / CW,
    zerlege, istJoker, punkte, farbName, kartenName, passendText, kartenZahl, sortiere, hilfe, regelnText, besondereKarten,
    symbolSVG, iconSVG, karteSVG, gesichtHTML, farbSymbolHTML, element, setzeGesicht, pruefeBilder, Bilder, mix,
  };
})(window.MMF = window.MMF || {});
