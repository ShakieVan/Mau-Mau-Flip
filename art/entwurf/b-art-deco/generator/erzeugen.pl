#!/usr/bin/perl
# Baut alle Dateien von Entwurf B: cards/*.svg, logo.svg, icon.svg, preview.html, logo.html, hand.html, icon.html
# Aufruf im Ordner b-art-deco:  perl generator/erzeugen.pl
use strict;
use warnings;
use utf8;
use FindBin;
require "$FindBin::Bin/karten.pl";
require "$FindBin::Bin/katze.pl";
require "$FindBin::Bin/logo.pl";

our (@CARDS, $IVORY, $INK, $NIGHT, $GOLD, $GOLDL, $FONT_DISPLAY, $FONT_LABEL);

my $FONTS = '<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
  . '<link href="https://fonts.googleapis.com/css2?family=Limelight&family=Josefin+Sans:wght@400;600;700&display=block" rel="stylesheet">';

my %SPEC = map { $_->[0] => $_ } @CARDS;
my $uid = 0;
sub card_inline { my ($name, $P) = @_; $P //= 'u' . (++$uid); card_svg($SPEC{$name} // die("Karte $name"), $P, 0) }

my $CSS = <<'CSS';
:root{--gold:#D9B860;--gold2:#F1DA97;--ivory:#F6EFDD;--night:#0B0F28;--ink:#1B1A33}
*{box-sizing:border-box}
body{margin:0;background:#0C1030;color:var(--ivory);font-family:'Josefin Sans','Century Gothic',sans-serif}
.screen{position:relative;width:1600px;height:720px;overflow:hidden;border-radius:46px;background:#0B0F28;flex:none}
.frame{border-radius:56px;padding:10px;background:#04050d;box-shadow:0 0 0 2px #444a78, 0 30px 60px rgba(0,0,0,.5);display:inline-block}
.card{position:absolute}
.card svg{display:block;width:100%;height:100%}
.playable{filter:drop-shadow(0 0 9px rgba(255,214,130,.85))}
.plaque{position:absolute;display:flex;align-items:center;gap:12px;height:54px;padding:0 16px 0 7px;border:2px solid var(--gold);border-radius:30px;background:rgba(9,12,34,.9);white-space:nowrap}
.plaque .av{width:40px;height:40px;border-radius:50%;display:grid;place-items:center;font-weight:700;font-size:19px;color:var(--night);border:2px solid var(--gold2)}
.plaque .nm{font-weight:600;font-size:21px;letter-spacing:.04em}
.plaque .ct{min-width:32px;height:32px;padding:0 8px;border-radius:16px;background:var(--gold);color:var(--night);font-weight:700;font-size:19px;display:grid;place-items:center}
.plaque.turn{box-shadow:0 0 18px rgba(255,214,130,.6)}
.lbl{position:absolute;font-weight:700;letter-spacing:.32em;font-size:15px;color:var(--gold2);text-transform:uppercase}
.chip{display:flex;align-items:center;gap:10px;height:42px;padding:0 16px;border:1.5px solid rgba(217,184,96,.7);border-radius:21px;font-weight:600;font-size:18px;color:var(--ivory);background:rgba(9,12,34,.75)}
.chip.on{background:linear-gradient(180deg,#F3DD9C,#C99B45);color:var(--night);border-color:#F3DD9C}
.mau{position:absolute;width:132px;height:132px;border-radius:50%;display:grid;place-items:center;background:radial-gradient(circle at 50% 40%,#2A3170,#0B0F28 70%);border:3px solid var(--gold);box-shadow:0 0 0 6px rgba(9,12,34,.9),0 0 0 8px rgba(217,184,96,.6),0 0 30px rgba(255,214,130,.35);font-family:Limelight,serif;font-size:42px;color:var(--gold2)}
.btn{position:absolute;display:flex;align-items:center;gap:12px;height:56px;padding:0 22px 0 12px;border:2px solid var(--gold);border-radius:28px;background:rgba(9,12,34,.85);font-weight:600;font-size:19px}
CSS

# ------------------------------------------------------------------ Tisch
sub table_svg {
  my ($side, $P) = @_;
  my $glow = $side eq 'hell' ? '#E8A64B' : '#7A5CFF';
  my $s = qq(<svg class="card" style="left:0;top:0" width="1600" height="720" viewBox="0 0 1600 720"><defs>)
    . qq(<radialGradient id="$P-tbg" cx="860" cy="300" r="900" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#232A63"/><stop offset="0.5" stop-color="#141945"/><stop offset="1" stop-color="#070A1E"/></radialGradient>)
    . qq(<radialGradient id="$P-tglow" cx="860" cy="300" r="380" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="$glow" stop-opacity="0.22"/><stop offset="1" stop-color="$glow" stop-opacity="0"/></radialGradient>)
    . qq(<linearGradient id="$P-tg" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="1600" y2="720"><stop offset="0" stop-color="#A47A2C"/><stop offset="0.35" stop-color="#F1DA97"/><stop offset="0.6" stop-color="#BC9240"/><stop offset="1" stop-color="#F3DD9C"/></linearGradient>)
    . qq(<filter id="$P-tbl" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="8"/></filter>)
    . qq(</defs>);
  $s .= qq(<rect width="1600" height="720" fill="url(#$P-tbg)"/><rect width="1600" height="720" fill="url(#$P-tglow)"/>);
  $s .= sunburst_lines(860, 300, 230, 1100, 64, 0, 360, "url(#$P-tg)", 0.07, 1);
  $s .= qq(<ellipse cx="860" cy="300" rx="400" ry="215" fill="none" stroke="url(#$P-tg)" stroke-width="1.6" opacity="0.55"/>);
  $s .= qq(<ellipse cx="860" cy="300" rx="414" ry="228" fill="none" stroke="url(#$P-tg)" stroke-width="0.8" opacity="0.4"/>);
  # Spielrichtung (im Uhrzeigersinn): Pfeilspitzen auf dem Ring
  for my $a (-30, 150) {
    my ($x, $y) = (860 + 400 * cos(rad($a)), 300 + 215 * sin(rad($a)));
    my $tang = atan2(215 * cos(rad($a)), -400 * sin(rad($a))) * 180 / atan2(0, -1);
    $s .= sprintf('<path d="M-12,-9 L10,0 L-12,9 Z" fill="url(#%s-tg)" transform="translate(%s %s) rotate(%s)"/>', $P, f($x), f($y), f($tang));
  }
  $s . '</svg>';
}

sub mini_fan {
  my ($names, $cx, $top, $w) = @_;
  $w //= 46;
  my $h = $w * 870 / 560;
  my $n = @$names;
  my $step = 19;
  my $o = '';
  for my $i (0 .. $n - 1) {
    my $ang = ($i - ($n - 1) / 2) * 5;
    my $left = $cx - $w / 2 + ($i - ($n - 1) / 2) * $step;
    $o .= sprintf('<div class="card" style="left:%spx;top:%spx;width:%spx;height:%spx;transform:rotate(%sdeg);transform-origin:50%% 120%%">%s</div>',
      f($left), $top, $w, f($h), f($ang), card_inline($names->[$i]));
  }
  $o;
}

sub sym_svg {
  my ($sym, $px, $fill, $stroke, $sw, $cut) = @_;
  my @pr = $sym eq 'joker4' || $sym eq 'flip' ? icon_prims($sym) : sym_prims($sym);
  my $inner = render_prims(\@pr, main => $fill, stroke => $stroke, sw => $sw, col => { cut => ($cut // '#0B0F28'), c0 => '#B3202A', c1 => '#FFDD33', c2 => '#43B05C', c3 => '#2A5BD7' });
  return qq(<svg width="$px" height="$px" viewBox="-55 -55 110 110" style="display:block">$inner</svg>);
}

sub hand_screen {
  my ($side, $P) = @_;
  my $o = qq(<div class="screen">);
  $o .= table_svg($side, $P);
  my (@hand, %play, $discard, @under, $drawtop, $ring, $ringglow, $sym, $word, @opp);
  if ($side eq 'hell') {
    @hand = qw(hell_rot_7 hell_rot_flip hell_gelb_4 hell_gelb_plus1 hell_gruen_aussetzen hell_blau_9 hell_blau_richtungswechsel hell_wuenscher hell_wuenscher_plus2);
    %play = map { $_ => 1 } qw(hell_rot_7 hell_rot_flip hell_wuenscher hell_wuenscher_plus2);
    ($discard, @under) = qw(hell_rot_5 hell_gruen_2 hell_gelb_4);
    $drawtop = 'dunkel_orange_3';
    ($ring, $ringglow, $sym, $word) = ('#B3202A', '#FF6A5A', 'flamme', 'Rot');
    @opp = (['Lena', 'L', '#E79AAE', [qw(dunkel_pink_8 dunkel_lila_1 dunkel_orange_3 dunkel_tuerkis_7 dunkel_wuenscher)]],
            ['Tom', 'T', '#7FD3DA', [qw(dunkel_lila_6 dunkel_pink_plus5 dunkel_orange_alle_aussetzen)]],
            ['Oma Gerda', 'G', '#F3C98A', [qw(dunkel_farbjagd dunkel_tuerkis_alle_aussetzen dunkel_pink_flip dunkel_lila_richtungswechsel dunkel_orange_3 dunkel_pink_8)]]);
  } else {
    @hand = qw(dunkel_pink_8 dunkel_pink_plus5 dunkel_tuerkis_7 dunkel_orange_3 dunkel_orange_alle_aussetzen dunkel_lila_6 dunkel_lila_richtungswechsel dunkel_wuenscher dunkel_farbjagd);
    %play = map { $_ => 1 } qw(dunkel_tuerkis_7 dunkel_orange_alle_aussetzen dunkel_wuenscher dunkel_farbjagd);
    ($discard, @under) = qw(dunkel_tuerkis_alle_aussetzen dunkel_lila_1 dunkel_pink_flip);
    $drawtop = 'hell_gelb_4';
    ($ring, $ringglow, $sym, $word) = ('#00838F', '#3FD9E4', 'welle', 'Türkis');
    @opp = (['Lena', 'L', '#E79AAE', [qw(hell_gelb_plus1 hell_blau_9 hell_rot_5 hell_gruen_2 hell_wuenscher)]],
            ['Tom', 'T', '#7FD3DA', [qw(hell_rot_7 hell_gruen_aussetzen hell_blau_richtungswechsel)]],
            ['Oma Gerda', 'G', '#F3C98A', [qw(hell_wuenscher_plus2 hell_gelb_4 hell_rot_flip hell_blau_9 hell_gruen_2 hell_rot_5)]]);
  }
  # Mitspieler oben (Option "Rückseiten sichtbar")
  my @ox = (300, 800, 1300);
  for my $k (0 .. 2) {
    my ($nm, $ini, $avc, $cards) = @{ $opp[$k] };
    my $n = @$cards;
    $o .= sprintf('<div class="plaque" style="left:%spx;top:18px;transform:translateX(-50%%)"><div class="av" style="background:%s">%s</div><div class="nm">%s</div><div class="ct">%d</div></div>', $ox[$k], $avc, $ini, $nm, $n);
    $o .= mini_fan($cards, $ox[$k], 84, 46);
  }
  # Nachziehstapel (zeigt die andere Seite)
  my ($dw, $dh) = (150, 233);
  for my $i (reverse 0 .. 3) {
    $o .= sprintf('<div class="card" style="left:%spx;top:%spx;width:%spx;height:%spx;%s">%s</div>', 560 + $i * 3, 184 - $i * 3, $dw, $dh,
      $i ? 'filter:brightness(.55)' : '', $i ? card_inline($drawtop) : card_inline($drawtop));
  }
  $o .= qq(<div class="lbl" style="left:574px;top:432px">Ziehen</div>);
  # Ablage mit Farbring
  my ($ax, $ay) = (880, 300);
  $o .= qq(<svg class="card" style="left:@{[$ax-175]}px;top:@{[$ay-175]}px" width="350" height="350" viewBox="-175 -175 350 350"><defs><filter id="$P-rg" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="7"/></filter></defs>)
     . qq(<circle r="152" fill="none" stroke="$ringglow" stroke-width="12" filter="url(#$P-rg)" opacity="0.8"/><circle r="152" fill="none" stroke="$ring" stroke-width="7"/><circle r="152" fill="none" stroke="$ringglow" stroke-width="1.5"/>)
     . qq(<circle r="164" fill="none" stroke="#D9B860" stroke-width="1.2" opacity="0.8"/></svg>);
  my @rot = (-9, 7);
  for my $i (0 .. $#under) {
    $o .= sprintf('<div class="card" style="left:%spx;top:%spx;width:%spx;height:%spx;transform:rotate(%sdeg);filter:brightness(.8)">%s</div>', $ax - $dw / 2, $ay - $dh / 2, $dw, $dh, $rot[$i], card_inline($under[$i]));
  }
  $o .= sprintf('<div class="card" style="left:%spx;top:%spx;width:%spx;height:%spx;transform:rotate(-2deg)">%s</div>', $ax - $dw / 2, $ay - $dh / 2, $dw, $dh, card_inline($discard));
  # Farbanzeige
  my $symcol = $side eq 'hell' ? $IVORY : $IVORY;
  $o .= sprintf('<div class="plaque" style="left:1052px;top:273px;border-color:%s"><div class="av" style="background:%s;border-color:%s">%s</div><div class="nm">%s</div></div>',
    $ringglow, $ring, $ringglow, sym_svg($sym, 26, $symcol, undef, 0, $ring), $word);
  # Hand: 9 Karten, nur der obere Teil sichtbar
  my ($cw, $ch) = (176, 273);
  my $n = @hand;
  for my $i (0 .. $n - 1) {
    my $ang = ($i - ($n - 1) / 2) * 2.5;
    my $raise = $play{ $hand[$i] } ? -20 : 0;
    $o .= sprintf('<div class="card%s" style="left:%spx;top:%spx;width:%spx;height:%spx;transform-origin:%spx 1100px;transform:rotate(%sdeg) translateY(%spx)">%s</div>',
      $play{ $hand[$i] } ? ' playable' : '', 800 - $cw / 2, 720 - 186, $cw, $ch, $cw / 2, f($ang), $raise, card_inline($hand[$i]));
  }
  # Bedienelemente
  $o .= qq(<div class="lbl" style="left:46px;top:574px">Du bist dran</div>);
  $o .= qq(<div class="btn" style="left:40px;top:610px">) . sym_svg('flip', 34, $GOLDL, undef, 0, '#0B0F28') . qq(Rückseiten ansehen</div>);
  $o .= qq(<div class="mau" style="left:1418px;top:330px">Mau!</div>);
  $o .= qq(<div class="lbl" style="left:1386px;top:500px">Sortieren</div>);
  my @chips = (['Farbe', 1], ['Wert', 0], ['Punkte', 0], ['Manuell', 0]);
  for my $k (0 .. $#chips) {
    my ($t, $on) = @{ $chips[$k] };
    my $x = 1380 + ($k % 2) * 104;
    my $y = 536 + int($k / 2) * 54;
    $o .= sprintf('<div class="chip%s" style="position:absolute;left:%spx;top:%spx;width:%spx;justify-content:center">%s</div>', $on ? ' on' : '', $x, $y, $k == 3 ? 104 : 96, $t);
  }
  $o .= '</div>';
  $o;
}

sub page {
  my ($title, $body, $bodycss) = @_;
  return qq(<!doctype html>\n<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>$title</title>$FONTS<style>$CSS body{$bodycss}</style></head><body>$body</body></html>\n);
}

# ------------------------------------------------------------------ Vorschau
my @PAIRS = (
  ['hell_rot_7', 'dunkel_tuerkis_7', 'Zahl 7'],
  ['hell_gelb_plus1', 'dunkel_pink_plus5', '+1 / +5'],
  ['hell_gruen_aussetzen', 'dunkel_orange_alle_aussetzen', 'Aussetzen / Alle aussetzen'],
  ['hell_blau_richtungswechsel', 'dunkel_lila_richtungswechsel', 'Richtungswechsel'],
  ['hell_rot_flip', 'dunkel_pink_flip', 'Flip'],
  ['hell_wuenscher', 'dunkel_wuenscher', 'Wünscher'],
  ['hell_wuenscher_plus2', 'dunkel_farbjagd', 'Wünscher +2 / Farbjagd'],
  ['hell_blau_9', 'dunkel_lila_6', '9 und 6 (unterstrichen)'],
);

my @PALROWS = (
  ['hell', 'Rot', '#B3202A', 'flamme', 'Flamme', $IVORY], ['hell', 'Gelb', '#FFDD33', 'sonne', 'Sonne', $INK],
  ['hell', 'Grün', '#43B05C', 'klee', 'Kleeblatt', $INK], ['hell', 'Blau', '#2A5BD7', 'kristall', 'Kristall', $IVORY],
  ['dunkel', 'Pink', '#FF99CC', 'herz', 'Herz', $INK], ['dunkel', 'Türkis', '#00838F', 'welle', 'Welle', $IVORY],
  ['dunkel', 'Orange', '#FF6F00', 'laterne', 'Laterne', $INK], ['dunkel', 'Lila', '#4527A0', 'stern', 'Stern', $IVORY],
);

sub preview {
  my $b = '';
  my $css = <<'CSS';
.wrap{width:1500px;margin:0 auto;padding:34px 0 40px}
h1{font-family:Limelight,serif;font-weight:400;font-size:44px;margin:0;color:var(--gold2)}
h2{font-family:Limelight,serif;font-weight:400;font-size:26px;margin:0 0 14px;color:var(--gold2)}
.sub{font-size:17px;letter-spacing:.06em;opacity:.85;margin-top:6px}
.rule{height:1px;background:linear-gradient(90deg,transparent,#D9B860,transparent);margin:22px 0}
.row{display:flex;gap:30px;align-items:flex-start}
.pairs{display:grid;grid-template-columns:repeat(4,1fr);gap:22px 25px}
.pair{display:flex;flex-direction:column;align-items:center;gap:8px}
.pair .two{display:flex;gap:10px}
.pair .two>div{width:172px;height:267px;position:relative}
.pair .cap{font-size:15px;letter-spacing:.08em;color:var(--gold2)}
.hint{font-size:15px;opacity:.8;margin:8px 0 0}
.pal{display:grid;grid-template-columns:repeat(4,minmax(0,1fr));gap:10px}
.sw{display:flex;align-items:center;gap:9px;padding:8px 9px;border:1px solid rgba(217,184,96,.35);border-radius:14px}
.sw .c{width:50px;height:50px;border-radius:10px;display:grid;place-items:center;flex:none}
.sw .t{font-size:13.5px;line-height:1.3}
.sw .t b{font-size:16px}
.gray{filter:grayscale(1)}
.txt{columns:3;column-gap:34px;font-size:15.5px;line-height:1.5}
.txt p{margin:0 0 10px;break-inside:avoid}
.txt b{color:var(--gold2)}
.iconcol{display:flex;flex-direction:column;gap:14px}
.iconsm{display:flex;gap:26px;align-items:flex-end;font-size:14px;color:var(--gold2)}
.iconsm div{display:flex;flex-direction:column;align-items:center;gap:6px}
CSS
  $b .= qq(<style>$css</style><div class="wrap">);
  $b .= qq(<h1>Mau-Mau Flip · Entwurf B „Art déco / Tarot“</h1><div class="sub">Elfenbein und Gold für den Tag, Mitternacht und Neon für die Nacht – Karten, Logo, App-Symbol und Handansicht im Querformat.</div><div class="rule"></div>);
  # Logo + Symbol
  $b .= qq(<div class="row"><div><h2>Logo</h2><div style="width:956px;height:538px;border-radius:18px;overflow:hidden;box-shadow:0 20px 50px rgba(0,0,0,.45)">) . logo_svg('pl', 0) . qq(</div></div>);
  $b .= qq(<div class="iconcol"><h2>App-Symbol</h2>) . icon_svg('pi1', 0, 512)
     . qq(<div class="iconsm"><div>) . icon_svg('pi2', 0, 96) . qq(96 px</div><div>) . icon_svg('pi3', 0, 48) . qq(48 px</div><div style="font-size:14px;color:var(--ivory);opacity:.8;align-items:flex-start;max-width:300px">512 px oben. Die Katze sitzt hinter einer Brüstung vor der Tag-Nacht-Scheibe; Ohren und Scheibe tragen auch bei 48 px.</div></div></div></div>);
  $b .= qq(<div class="rule"></div>);
  # Karten
  $b .= qq(<h2>Karten · helle und dunkle Seite nebeneinander</h2><div class="pairs">);
  for my $p (@PAIRS) {
    my ($h, $d, $cap) = @$p;
    $b .= qq(<div class="pair"><div class="two"><div>) . card_inline($h, "pv-$h") . qq(</div><div>) . card_inline($d, "pv-$d") . qq(</div></div><div class="cap">$cap</div></div>);
  }
  $b .= qq(</div><div class="rule"></div>);
  # Hand
  $b .= qq(<h2>Handansicht im Querformat (1600 × 720, helle Phase)</h2><div style="zoom:0.925"><div class="frame">) . hand_screen('hell', 'hs1') . qq(</div></div>);
  $b .= qq(<p class="hint">Neun Karten im Fächer, je Karte bleibt oben links ein Streifen von etwa 22 dp. Spielbare Karten sind angehoben und leuchten. Oben die Mitspieler mit der Option „Rückseiten sichtbar“, in der Mitte Nachziehstapel (zeigt die andere Seite) und Ablage mit Farbring.</p><div class="rule"></div>);
  # Dunkle Hand + Palette
  $b .= qq(<div class="row"><div><h2>Dunkle Phase</h2><div style="zoom:0.44"><div class="frame">) . hand_screen('dunkel', 'hs2') . qq(</div></div></div>);
  $b .= qq(<div style="flex:1"><h2>Palette und Formsymbole</h2><div class="pal">);
  for my $r (@PALROWS) {
    my ($side, $nm, $hex, $sym, $symname, $txt) = @$r;
    my $bg = $side eq 'hell' ? '#F6EFDD' : '#0B0F28';
    $b .= qq(<div class="sw" style="background:$bg;color:) . ($side eq 'hell' ? $INK : $IVORY) . qq("><div class="c" style="background:$hex">) . sym_svg($sym, 32, $txt, undef, 0, $hex)
       . qq(</div><div class="t"><b>$nm</b><br>$hex<br>$symname</div><div style="margin-left:auto;display:flex;gap:6px;align-items:center">)
       . sym_svg($sym, 20, $hex, ($side eq 'hell' ? $INK : '#F6EFDD'), 6, $bg) . qq(</div></div>);
  }
  $b .= qq(</div><div class="row" style="margin-top:14px;gap:16px;align-items:center"><div class="gray" style="display:flex;gap:8px">)
     . qq(<div style="width:84px;height:130px">) . card_inline('hell_rot_7', 'g1') . qq(</div><div style="width:84px;height:130px">) . card_inline('dunkel_tuerkis_7', 'g2') . qq(</div>)
     . qq(<div style="width:84px;height:130px">) . card_inline('hell_gelb_4', 'g3') . qq(</div><div style="width:84px;height:130px">) . card_inline('dunkel_lila_6', 'g4') . qq(</div></div>)
     . qq(<div class="pal gray" style="grid-template-columns:repeat(8,minmax(0,1fr));gap:6px;flex:1">);
  for my $r (@PALROWS) { $b .= qq(<div style="height:58px;border-radius:8px;background:$r->[2];display:grid;place-items:center">) . sym_svg($r->[3], 30, $r->[5], undef, 0, $r->[2]) . qq(</div>) }
  $b .= qq(</div></div><p class="hint">Graustufenprobe: Papier gegen Nacht trennt die Seiten auch ohne Farbsehen; die Helligkeitsstaffel und die Formsymbole trennen die Farben. Kleine Symbole rechts in jeder Kachel ≈ 10 dp.</p></div></div>);
  $b .= qq(<div class="rule"></div><h2>Gestaltungsbegründung</h2><div class="txt">);
  $b .= qq(<p><b>Leitidee.</b> „Tag und Nacht der Mau-Katze“ als Art-déco-Tarot. Die helle Seite ist Elfenbeinpapier mit Goldlinien, einem Sonnenaufgang im Bogenfenster und Strahlenkranz; die dunkle Seite ist Mitternacht mit Neonkontur, Mondsichel, Sternen und Mondphasen. Beide nutzen dieselbe Bauordnung, damit der Flip als Verwandlung lesbar wird.</p>);
  $b .= qq(<p><b>Funktion zuerst.</b> Der Eckindex ist ein hängendes Banner in voller Kartenfarbe mit Wert und Formsymbol. Es liegt ganz im linken 22-dp-Streifen und bleibt im Fächer sichtbar. Schlussstein mit Farbsymbol und Oberteil des großen Werts machen auch den oberen Kartenrand eindeutig.</p>);
  $b .= qq(<p><b>Erwachsen statt kindlich.</b> Feine Goldlinien, Eckfächer, Bogenfenster, eine Display-Schrift der 1920er (Limelight) und eine geometrische Grotesk (Josefin Sans). Werte stehen aufrecht mit doppelter Kontur (Tinte, Papierfuge, Goldlinie), auf der Nachtseite als Neonröhre.</p>);
  $b .= qq(<p><b>Barrierefreiheit.</b> Jede Farbe hat ein eigenes Symbol (Flamme, Sonne, Kleeblatt, Kristall, Herz, Welle, Laterne, Stern). Papier gegen Nacht trennt die Seiten ohne Farbsehen. 6 und 9 sind unterstrichen, das Farbwort steht im Titelband.</p>);
  $b .= qq(<p><b>Eigene Bildsprache.</b> Kein Oval, nichts Schräges in der Kartenmitte, keine Schlagschatten. Eigene Aktionssymbole: Sanduhr (Aussetzen), Sanduhr im Ring (Alle aussetzen), Kreispfeile, Sonne-Mond-Scheibe (Flip), Katzenpfote (Wünscher), Katzenauge (Farbjagd).</p>);
  $b .= qq(<p><b>Bereit für Effekte.</b> Jede Karten-SVG hat die Ebenen grund, motiv, rahmen, wert, symbol und index. Strahlen können aus der Banner- und Bogenkontur wachsen, der Flip kann Sonne und Mond tauschen.</p>);
  $b .= qq(<p><b>Schriften.</b> Limelight (Sorkin Type) und Josefin Sans (Santiago Orozco), beide SIL Open Font License 1.1, über Google Fonts.</p>);
  $b .= qq(</div></div>);
  page('Mau-Mau Flip – Entwurf B Art déco', $b, 'margin:0');
}

# ------------------------------------------------------------------ Schreiben
for my $c (@CARDS) { write_file("cards/$c->[0].svg", card_svg($c, $c->[0], 1) . "\n") }
write_file('logo.svg', logo_svg('logo', 1) . "\n");
write_file('icon.svg', icon_svg('icon', 1) . "\n");
write_file('logo.html', page('Mau-Mau Flip – Logo', logo_svg('l', 0), 'margin:0;width:1600px;height:900px;overflow:hidden'));
write_file('icon.html', page('Mau-Mau Flip – App-Symbol', icon_svg('i', 0, 512), 'margin:0;width:512px;height:512px;overflow:hidden;background:transparent'));
write_file('hand.html', page('Mau-Mau Flip – Handansicht', hand_screen('hell', 'h'), 'margin:0;width:1600px;height:720px;overflow:hidden'));
write_file('preview.html', preview());
print "fertig: " . scalar(@CARDS) . " Karten\n";
