/* Mau-Mau Flip – Entwurf A: Handansicht (Querformat) und Vorschauseite */
'use strict';

const EXTRA_CARDS = [
  { file: 'hell_gelb_3', side: 'hell', color: 'gelb', type: 'num', v: '3' },
  { file: 'hell_gruen_6', side: 'hell', color: 'gruen', type: 'num', v: '6' },
  { file: 'dunkel_orange_9', side: 'dunkel', color: 'orange', type: 'num', v: '9' },
  { file: 'dunkel_tuerkis_aussetzen', side: 'dunkel', color: 'tuerkis', type: 'aussetzen' },
];
const ALL_CARDS = CARD_LIST.concat(EXTRA_CARDS);
const byFile = f => ALL_CARDS.find(c => c.file === f);

let __uid = 0;
const uid = p => `${p}${++__uid}-`;
function cardAt(file, w, extraStyle = '', cls = '') {
  return `<div class="karte ${cls}" style="width:${w}px;height:${f1(w * CH / CW)}px;${extraStyle}">${cardSVG(byFile(file), { prefix: uid('k'), width: w })}</div>`;
}

const FONT_LINK = `<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin><link href="${FONT_CSS}" rel="stylesheet">`;

/* ------------------------------------------------------------------ */
/* Handansicht 1600×720 (Handy quer, ~800×360 dp bei 2-facher Dichte)   */
/* ------------------------------------------------------------------ */
const HAND_CSS = `
.tisch{position:relative;width:1600px;height:720px;overflow:hidden;border-radius:44px;
  background:radial-gradient(ellipse 70% 62% at 50% 46%,#26305A 0%,#171C38 55%,#0C0F22 100%);font-family:${F_CARD};color:#F4EADA}
.tisch .karte{position:absolute;filter:drop-shadow(0 6px 10px rgba(0,0,0,.45))}
.tisch .karte svg{display:block;width:100%;height:100%}
.tisch .ring{position:absolute;border-radius:50%}
.gegner{position:absolute;display:flex;flex-direction:column;align-items:center;gap:8px;width:220px}
.gegner .kopf{display:flex;align-items:center;gap:12px}
.gegner .ava{width:54px;height:54px;border-radius:50%;display:grid;place-items:center;font:800 24px ${F_CARD};color:#211B2C;border:3px solid #F4EADA}
.gegner .name{font-weight:700;font-size:21px;letter-spacing:.01em}
.gegner .zahl{font:800 15px ${F_CARD};background:#F4EADA;color:#211B2C;border-radius:20px;padding:2px 9px;margin-left:4px}
.gegner .faecher{position:relative;height:100px;width:200px}
.gegner .faecher .karte{filter:drop-shadow(0 3px 4px rgba(0,0,0,.5))}
.pill{position:absolute;display:flex;align-items:center;gap:10px;padding:12px 20px;border-radius:40px;font:700 20px ${F_CARD};
  background:rgba(244,234,218,.1);border:2px solid rgba(244,234,218,.35);color:#F4EADA;backdrop-filter:blur(4px)}
.pill svg{width:26px;height:26px}
.maubtn{position:absolute;right:46px;bottom:40px;width:150px;height:150px;border-radius:50%;background:#FFF7E8;border:5px solid #211B2C;
  box-shadow:0 0 0 6px rgba(255,127,207,.35),0 10px 30px rgba(0,0,0,.5);display:grid;place-items:center;
  font:italic 900 46px ${F_BRAND};font-variation-settings:'SOFT' 100;color:#211B2C}
.dran{position:absolute;left:50%;top:494px;transform:translateX(-50%);font:700 19px ${F_CARD};padding:8px 18px;border-radius:30px;
  background:#FFF7E8;color:#211B2C;box-shadow:0 4px 14px rgba(0,0,0,.35)}
.farbe{position:absolute;display:flex;align-items:center;gap:10px;font:800 22px ${F_CARD}}
.stapelzahl{position:absolute;font:700 17px ${F_CARD};color:#C9C3E8;text-align:center;width:150px}
`;

function miniFan(files, w = 60, step = 22, spread = 7) {
  let h = '';
  const n = files.length;
  files.forEach((f, i) => {
    const a = (i - (n - 1) / 2) * spread;
    const x = 100 - w / 2 + (i - (n - 1) / 2) * step;
    h += cardAt(f, w, `left:${f1(x)}px;top:4px;transform:rotate(${a}deg);transform-origin:50% 160%`);
  });
  return h;
}

function handScene() {
  let h = `<div class="tisch">`;
  // Richtungspfeile um die Tischmitte (im Uhrzeigersinn)
  h += `<svg width="1600" height="720" style="position:absolute;left:0;top:0" viewBox="0 0 1600 720"><defs><filter id="hs-glut" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="4" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter></defs>` +
    `<g fill="none" stroke="#9A86FF" stroke-width="4" stroke-linecap="round" opacity=".55" filter="url(#hs-glut)">` +
    `<path d="M560 205A330 170 0 0 1 1040 205"/><path d="M1040 205l-8 -22M1040 205l-24 4"/>` +
    `<path d="M1090 420A330 150 0 0 1 510 420"/><path d="M510 420l6 22M510 420l24 -6"/></g></svg>`;
  // Gegner (Rückseiten = dunkle Seite sichtbar, Option "Rückseiten der Mitspieler: sichtbar")
  const seats = [
    { name: 'Lena', ini: 'L', col: '#FF99CC', x: 30, y: 190, n: 6, cards: ['dunkel_pink_flip', 'dunkel_tuerkis_7', 'dunkel_orange_9', 'dunkel_lila_6', 'dunkel_pink_plus5', 'dunkel_wuenscher'] },
    { name: 'Tom', ini: 'T', col: '#43B05C', x: 690, y: 18, n: 5, cards: ['dunkel_lila_richtungswechsel', 'dunkel_orange_alle_aussetzen', 'dunkel_tuerkis_aussetzen', 'dunkel_farbjagd', 'dunkel_pink_flip'] },
    { name: 'Mia', ini: 'M', col: '#FFDD33', x: 1350, y: 190, n: 2, cards: ['dunkel_orange_9', 'dunkel_tuerkis_7'] },
  ];
  for (const s of seats) {
    h += `<div class="gegner" style="left:${s.x}px;top:${s.y}px"><div class="kopf"><div class="ava" style="background:${s.col}">${s.ini}</div><div class="name">${s.name}</div><div class="zahl">${s.n}</div></div>` +
      `<div class="faecher">${miniFan(s.cards)}</div></div>`;
  }
  // Nachziehstapel (zeigt die dunkle Seite der obersten Karte)
  h += cardAt('dunkel_lila_6', 118, 'left:572px;top:236px;transform:rotate(-3deg)');
  h += cardAt('dunkel_tuerkis_7', 118, 'left:568px;top:230px;transform:rotate(-1deg)');
  h += cardAt('dunkel_orange_9', 118, 'left:564px;top:224px;transform:rotate(1.5deg)');
  h += `<div class="stapelzahl" style="left:548px;top:412px">Stapel · 47</div>`;
  // Ablage: auf Höhe des Nachziehstapels, spiegelbildlich zur Tischmitte (x = 800).
  // Nachziehstapel-Mitte ≈ (623 | 321), also Ablage-Mitte (977 | 321).
  const AX = 977, AY = 321, AW = 124, AH = AW * CH / CW;
  h += `<div class="ring" style="left:${AX - 116}px;top:${AY - 116}px;width:232px;height:232px;border:5px solid #2A5BD7;box-shadow:0 0 26px rgba(42,91,215,.65),inset 0 0 20px rgba(42,91,215,.4)"></div>`;
  const ablage = (f, dx, dy, rot) => cardAt(f, AW, `left:${f1(AX - AW / 2 + dx)}px;top:${f1(AY - AH / 2 + dy)}px;transform:rotate(${rot}deg)`);
  h += ablage('hell_gelb_plus1', -14, 2, 16);
  h += ablage('hell_blau_richtungswechsel', -4, -1, -11);
  h += ablage('hell_blau_9', 4, 0, 4);
  // Aktuelle Farbe zwischen den Stapeln
  const kr = renderPrims(symbolPrims('kristall'), { main: LIGHT.blau.hex, cut: PAPER, sil: '#F4EADA' }, 'sil', 5) + renderPrims(symbolPrims('kristall'), { main: LIGHT.blau.hex, cut: PAPER });
  h += `<div class="farbe" style="left:800px;top:${AY}px;transform:translate(-50%,-50%);flex-direction:column;gap:6px"><svg width="40" height="40" viewBox="0 0 100 100">${kr}</svg>Blau</div>`;
  h += `<div class="dran">Du bist dran</div>`;
  // Hand: 9 Karten, nach Farbe sortiert, nur der obere Teil sichtbar
  const hand = ['hell_rot_7', 'hell_rot_flip', 'hell_gelb_3', 'hell_gelb_plus1', 'hell_gruen_aussetzen', 'hell_blau_9', 'hell_blau_richtungswechsel', 'hell_wuenscher', 'hell_wuenscher_plus2'];
  const playable = new Set(['hell_blau_9', 'hell_blau_richtungswechsel', 'hell_wuenscher', 'hell_wuenscher_plus2']);
  const W = 190, step = 72, n = hand.length;
  const x0 = 800 - (W + step * (n - 1)) / 2;
  hand.forEach((f, i) => {
    const t = i - (n - 1) / 2;
    const rot = t * 2.6;
    let top = 574 + Math.abs(t) * Math.abs(t) * 0.9;
    let style = `left:${f1(x0 + i * step)}px;top:${f1(top)}px;transform:rotate(${rot.toFixed(1)}deg);transform-origin:50% 100%`;
    let cls = '';
    if (playable.has(f)) { style = style.replace(`top:${f1(top)}px`, `top:${f1(top - 16)}px`); cls = 'spielbar'; }
    if (f === 'hell_blau_9') { style = style.replace(/top:[\d.]+px/, `top:${f1(top - 46)}px`); cls = 'gewaehlt'; }
    h += cardAt(f, W, style, cls);
  });
  // Knöpfe
  const sortIcon = `<svg viewBox="0 0 26 26"><path d="M7 4v17M7 21l-4-4M7 21l4-4M19 22V5M19 5l-4 4M19 5l4 4" stroke="#F4EADA" stroke-width="2.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
  const flipIcon = `<svg viewBox="0 0 26 26"><rect x="4" y="3" width="13" height="19" rx="3" fill="none" stroke="#F4EADA" stroke-width="2.4"/><rect x="10" y="6" width="13" height="18" rx="3" fill="#0A0D20" stroke="#FF7FCF" stroke-width="2.4"/></svg>`;
  h += `<div class="pill" style="left:46px;top:560px">${sortIcon}Farbe</div>`;
  h += `<div class="pill" style="left:46px;top:632px">${flipIcon}Rückseiten</div>`;
  h += `<div class="maubtn">Mau!</div>`;
  h += `</div>`;
  return h;
}
const HAND_EXTRA_CSS = `
.tisch .karte.spielbar{filter:drop-shadow(0 0 8px rgba(255,247,232,.55)) drop-shadow(0 6px 10px rgba(0,0,0,.45))}
.tisch .karte.gewaehlt{filter:drop-shadow(0 0 14px rgba(255,214,90,.95)) drop-shadow(0 8px 14px rgba(0,0,0,.5))}
`;

function handHTML() {
  return `<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=1600">` +
    `<title>Mau-Mau Flip – Hand (Querformat)</title>${FONT_LINK}` +
    `<style>html,body{margin:0;background:#0C0F22}${HAND_CSS}${HAND_EXTRA_CSS}.tisch{border-radius:0}</style></head><body>` +
    handScene() + `</body></html>`;
}

/* ------------------------------------------------------------------ */
/* Vorschauseite                                                       */
/* ------------------------------------------------------------------ */
function previewHTML() {
  const pairs = [
    ['hell_rot_7', 'dunkel_tuerkis_7', 'Zahl 7'],
    ['hell_gelb_plus1', 'dunkel_pink_plus5', 'Zieh 1 · Zieh 5'],
    ['hell_gruen_aussetzen', 'dunkel_orange_alle_aussetzen', 'Aussetzen · Alle aussetzen'],
    ['hell_blau_richtungswechsel', 'dunkel_lila_richtungswechsel', 'Richtungswechsel'],
    ['hell_rot_flip', 'dunkel_pink_flip', 'Flip'],
    ['hell_wuenscher', 'dunkel_wuenscher', 'Wünscher'],
    ['hell_wuenscher_plus2', 'dunkel_farbjagd', 'Wünscher +2 · Farbjagd'],
    ['hell_blau_9', 'dunkel_lila_6', '9 · 6 (unterstrichen)'],
  ];
  const cw = 166;
  let cards = '';
  for (const [a, b, label] of pairs) {
    cards += `<figure class="paar">${cardAt(a, cw)}${cardAt(b, cw)}<figcaption>${esc(label)}</figcaption></figure>`;
  }

  // Palette
  const swatch = (c, side) => {
    const prims = symbolPrims(c.sym);
    const symSvg = side === 'hell'
      ? renderPrims(prims, { sil: INK }, 'sil', 3.2) + renderPrims(prims, { main: c.hex, cut: PAPER })
      : renderPrims(prims, { main: c.neon, cut: NIGHT });
    const bg = side === 'hell' ? PAPER : NIGHT;
    const small = (s) => `<svg width="${s}" height="${s}" viewBox="0 0 100 100">${symSvg}</svg>`;
    return `<div class="farbfeld"><div class="fl" style="background:${c.hex}"></div>` +
      `<div class="sym" style="background:${bg}">${small(54)}${small(20)}</div>` +
      `<div class="ft"><b>${esc(c.name)}</b> · ${esc(SYM_NAMES[c.sym])}<br><code>${c.hex}</code>${c.neon ? ` · Neon <code>${c.neon}</code>` : ''}<br><span>L ${Lof(c.hex).toFixed(2)}</span></div></div>`;
  };
  const L = Object.values(LIGHT), D = Object.values(DARK);
  const rows = [['Hell (Flächen)', L.map(c => c.hex), L.map(c => c.name)], ['Dunkel (Flächen)', D.map(c => c.hex), D.map(c => c.name)], ['Dunkel (Neon)', D.map(c => c.neon), D.map(c => c.name)]];
  const kinds = { normal: 'normal', protan: 'Rot-Schwäche', deutan: 'Grün-Schwäche', tritan: 'Blau-Gelb-Schwäche' };
  let table = `<table><tr><th>Satz</th>${Object.values(kinds).map(k => `<th>${k}</th>`).join('')}</tr>`;
  for (const [name, hex, names] of rows) {
    const r = minPair(hex, names);
    table += `<tr><td>${esc(name)}</td>${Object.keys(kinds).map(k => `<td class="${r[k].d >= 0.15 ? 'ok' : 'knapp'}">${r[k].d.toFixed(3).replace('.', ',')}<small>${esc(r[k].pair)}</small></td>`).join('')}</tr>`;
  }
  table += `</table>`;

  const css = `
:root{--ink:#211B2C;--paper:#F4EADA;--night:#0A0D20;--bg:#17141F;--panel:#211D2B;--line:#3A3346;--text:#EDE5D6;--muted:#A69CB4;--neon:#FF7FCF}
*{box-sizing:border-box}
html,body{margin:0;background:var(--bg);color:var(--text);font-family:${F_CARD};font-size:17px;line-height:1.5}
.wrap{width:1520px;margin:0 auto;padding:30px 0 36px}
header{display:flex;align-items:flex-end;justify-content:space-between;margin-bottom:20px}
header h1{font:900 54px/1 ${F_BRAND};font-variation-settings:'SOFT' 100;margin:0;color:var(--paper)}
header h1 em{font-style:italic;color:#FFE6F6;text-shadow:0 0 18px rgba(255,95,196,.8)}
header p{margin:6px 0 0;color:var(--muted);font-size:18px}
.tag{font:700 14px ${F_CARD};letter-spacing:.14em;text-transform:uppercase;color:var(--neon)}
section{margin-top:34px}
h2{font:800 28px ${F_CARD};margin:0 0 6px;color:var(--paper)}
h2 + p{margin:0 0 20px;color:var(--muted);max-width:1100px}
.oben{display:grid;grid-template-columns:968px 512px;gap:40px;align-items:start}
.logo svg{display:block;width:968px;height:auto;border-radius:28px;box-shadow:0 18px 50px rgba(0,0,0,.45)}
.gross{margin:0;color:var(--muted);font-size:14px;text-align:center}.gross svg{display:block;filter:drop-shadow(0 14px 30px rgba(0,0,0,.45))}.gross figcaption{margin-top:10px}
.karten{display:grid;grid-template-columns:repeat(8,1fr);gap:16px}
.paar{margin:0;display:flex;flex-direction:column;gap:12px;align-items:center}
.paar .karte svg{display:block;width:${cw}px;height:auto;filter:drop-shadow(0 6px 12px rgba(0,0,0,.4))}
.paar figcaption{font-size:14px;color:var(--muted);text-align:center;min-height:2.6em}
.handbox{width:1520px;height:684px;border-radius:44px;overflow:hidden;box-shadow:0 18px 50px rgba(0,0,0,.5);outline:10px solid #050508}
.handbox .tisch{transform:scale(.95);transform-origin:0 0}
.symbole{display:flex;gap:28px;align-items:flex-end;margin-top:12px}
.symbole figure{margin:0;display:flex;flex-direction:column;align-items:center;gap:10px;color:var(--muted);font-size:14px}
.symbole .auf{display:flex;gap:24px;align-items:center;padding:22px;border-radius:24px}
.zwei{display:grid;grid-template-columns:1fr 1fr;gap:40px}
.farben{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin-bottom:14px}
.farbfeld{background:var(--panel);border:1px solid var(--line);border-radius:18px;overflow:hidden}
.farbfeld .fl{height:44px}
.farbfeld .sym{display:flex;gap:14px;align-items:center;justify-content:center;padding:10px}
.farbfeld .ft{padding:10px 14px 12px;font-size:14px;color:var(--muted)}
.farbfeld b{color:var(--text)} code{font:13px ui-monospace,Consolas,monospace;color:var(--text)}
table{border-collapse:collapse;width:100%;font-size:15px;margin-top:6px}
th,td{border-bottom:1px solid var(--line);padding:8px 10px;text-align:left}
th{color:var(--muted);font-weight:600}
td small{display:block;color:var(--muted);font-size:12px}
td.ok{color:#9BE3A5} td.knapp{color:#FFB37A}
.text{font-size:15.5px;line-height:1.48}
.text p{margin:0 0 12px}
.text b{color:var(--paper)}
`;

  const icons = `<div class="symbole">` +
    `<figure><div class="auf" style="background:#F4EADA">${iconSVG({ prefix: 'pi96a-', width: 96 })}${iconSVG({ prefix: 'pi48a-', width: 48 })}</div><figcaption>96 / 48 px auf hell</figcaption></figure>` +
    `<figure><div class="auf" style="background:#0A0D20">${iconSVG({ prefix: 'pi96b-', width: 96 })}${iconSVG({ prefix: 'pi48b-', width: 48 })}</div><figcaption>96 / 48 px auf dunkel</figcaption></figure>` +
    `</div>`;

  const text = `
<p><b>Tag und Nacht der Mau-Katze.</b> Die helle Seite ist ein Siebdruck auf warmem Papier: flache Farbflächen, eine Sonne, die über einem gestreiften Meer aufgeht, der Wert als ausgespartes Papier mit Druckfarben-Kontur. Die dunkle Seite ist dieselbe Landschaft bei Nacht: tiefblauer Grund, leuchtende Neonkontur, Mondsichel und Sterne, der Wert glüht.</p>
<p><b>Die Papierlasche.</b> Oben links und unten rechts spart das Farbfeld eine Lasche aus. Dort steht der Eckindex groß in Druckfarbe (bzw. Mondlicht), darunter das Farbsymbol. Die Lasche ist so breit, dass Wert und Symbol im Fächer auf rund 22 dp lesbar bleiben, und sie gibt der Karte eine eigene, unverwechselbare Silhouette.</p>
<p><b>Barrierefreiheit.</b> Jede der acht Farben hat ein eigenes Formsymbol (Flamme, Sonne, Kleeblatt, Kristall; Herz, Welle, Laterne, Stern). Die Farben folgen einer Helligkeitsstaffel; die Tabelle zeigt den kleinsten OKLab-Abstand unter simulierter Farbsehschwäche. Hell und dunkel unterscheiden sich schon über die Helligkeit: Papierfläche gegen Nachtgrund. 6 und 9 sind unterstrichen.</p>
<p><b>Abstand zum Vorbild.</b> Kein Oval, nichts schräg gestellt, keine Zahl mit Schlagschatten, keine rote Rückseite. Werte stehen aufrecht auf Sonne bzw. Mond, die Aktionen sind eigene Katzenmotive: schlafende Katze (Aussetzen), getigerte Pfeile wie Katzenschwänze (Richtungswechsel), Tag/Nacht-Scheibe (Flip), Pfote mit Farbzehen (Wünscher).</p>
<p><b>Für die Effekte gebaut.</b> Jede Karten-SVG hat benannte Ebenen: <code>rahmen</code>, <code>grund</code>, <code>motiv</code>, <code>symbol</code>, <code>wert</code>, <code>index</code>. Die Kontur für Joker-Strahlen ist der Rahmen, der Flip-Übergang kann Sonne in Mond und Papier in Nacht überblenden.</p>
<p><b>Schriften.</b> Bricolage Grotesque (Karten und Oberfläche, schmale Breite für den Index) und Fraunces (Schriftzug und „Mau!“), beide unter SIL Open Font License 1.1.</p>`;

  return `<!doctype html><html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=1600">` +
    `<title>Mau-Mau Flip – Entwurf A: Papier &amp; Neon</title>${FONT_LINK}` +
    `<style>${css}${HAND_CSS}${HAND_EXTRA_CSS}</style></head><body><div class="wrap">` +
    `<header><div><div class="tag">Entwurf A</div><h1>Papier &amp; <em>Neon</em></h1><p>Kartendesign, Logo und App-Symbol für Mau-Mau Flip</p></div>` +
    `<p style="text-align:right">Kartenformat 56 : 87 · viewBox 560 × 870<br>Schriften: Bricolage Grotesque, Fraunces (OFL)</p></header>` +
    `<section class="oben"><div class="logo">${logoSVG({ prefix: 'plg-' })}</div><figure class="gross">${iconSVG({ prefix: 'pi512-', width: 512 })}<figcaption>App-Symbol 512 px: die Katze als Büste vor Tag und Nacht</figcaption></figure></section>` +
    `<section><h2>Karten</h2><p>Oben die helle Seite, darunter die dunkle Seite. Gleiche Bauweise auf beiden Seiten, Unterschied über Papier gegen Nacht und Fläche gegen Leuchtkontur.</p><div class="karten">${cards}</div></section>` +
    `<section><h2>Hand im Querformat</h2><p>Handy quer (1600 × 720 px, etwa 800 × 360 dp). Neun Karten im Fächer, nach Farbe sortiert, nur der obere Teil sichtbar; jede Karte zeigt einen Streifen von 72 px (36 dp, Minimum 22 dp). Spielbare Karten heben sich leicht, die gewählte leuchtet. Mitspieler mit sichtbaren Rückseiten (globale Option).</p><div class="handbox">${handScene()}</div></section>` +
    `<section class="zwei"><div><h2>Palette und Symbole</h2><p>Flächenfarben aus der Farbsehschwäche-Rechnung, dazu Neon-Varianten für Konturen der dunklen Seite. Symbole in 54 und 20 px.</p>` +
    `<div class="farben">${L.map(c => swatch(c, 'hell')).join('')}</div><div class="farben">${D.map(c => swatch(c, 'dunkel')).join('')}</div>` +
    `<p style="color:var(--muted);margin:14px 0 4px">Kleinster OKLab-Abstand je Satz (Simulation nach Machado 2009, Schweregrad 1; Ziel ≥ 0,15):</p>${table}</div>` +
    `<div><h2>App-Symbol klein</h2>${icons}<h2 style="margin-top:28px">Gestaltungsbegründung</h2><div class="text">${text}</div></div></section>` +
    `</div></body></html>`;
}

/* Alle Ausgabedateien */
function buildAll() {
  const files = {};
  for (const c of ALL_CARDS) files[`cards/${c.file}.svg`] = cardSVG(c, { standalone: true });
  files['logo.svg'] = logoSVG({ standalone: true, prefix: '' });
  files['icon.svg'] = iconSVG({ standalone: true, prefix: '' });
  files['hand.html'] = handHTML();
  files['preview.html'] = previewHTML();
  for (const k of Object.keys(files)) {
    let v = files[k];
    if (k.endsWith('.svg')) v = '<?xml version="1.0" encoding="UTF-8"?>\n' + v;
    files[k] = asciiSafe(v);
  }
  return files;
}

if (typeof window !== 'undefined') { window.buildAll = buildAll; window.handHTML = handHTML; window.previewHTML = previewHTML; }
