#!/usr/bin/perl
# Mau-Mau Flip – Entwurf B "Art déco / Tarot"
# Erzeugt alle Karten-SVGs, Logo, App-Symbol und die HTML-Vorschauen.
# Aufruf (Git Bash):  perl generator/karten.pl   (im Ordner b-art-deco)
use strict;
use warnings;
use utf8;
use POSIX qw(floor);
use File::Basename qw(dirname);
use Cwd qw(abs_path);

my $ROOT = abs_path(dirname(abs_path($0)) . '/..');
my $PI = 4 * atan2(1, 1);
sub rad { $_[0] * $PI / 180 }
sub f { my $v = sprintf('%.1f', $_[0]); $v =~ s/\.0$//; $v eq '-0' ? '0' : $v }

# ------------------------------------------------------------------ Farben
our $IVORY  = '#F6EFDD';
our $PAPER2 = '#E8DABB';
our $INK    = '#1B1A33';
our $NIGHT  = '#0B0F28';
our $NIGHT2 = '#1A2150';
our $GOLD   = '#C9A24B';
our $GOLDL  = '#EBD08A';
our $GOLDD  = '#8E6A26';

sub hex2rgb { my $h = shift; $h =~ s/#//; map { hex } ($h =~ /(..)(..)(..)/) }
sub rgb2hex { sprintf('#%02X%02X%02X', map { my $x = floor($_ + 0.5); $x < 0 ? 0 : $x > 255 ? 255 : $x } @_) }
sub mix { my ($a, $b, $t) = @_; my @a = hex2rgb($a); my @b = hex2rgb($b); rgb2hex(map { $a[$_] + ($b[$_] - $a[$_]) * $t } 0 .. 2) }

my %PAL = (
  hell => {
    rot   => { core => q{#B3202A}, shade => q{#74131C}, txt => $IVORY, wort => 'ROT',   sym => 'flamme' },
    gelb  => { core => q{#FFDD33}, shade => q{#B88A12}, txt => $INK,   wort => 'GELB',  sym => 'sonne' },
    gruen => { core => q{#43B05C}, shade => q{#1F6B36}, txt => $INK,   wort => 'GRÜN',  sym => 'klee' },
    blau  => { core => q{#2A5BD7}, shade => q{#173A8F}, txt => $IVORY, wort => 'BLAU',  sym => 'kristall' },
    joker => { core => $INK,      txt => $IVORY, wort => '',      sym => '' },
    sonne => { core => q{#E8762B}, txt => $IVORY, wort => q{TAG}, sym => q{sonne} },
  },
  dunkel => {
    pink    => { core => '#FF99CC', glow => '#FFC6E2', txt => $INK,   wort => 'PINK',   sym => 'herz' },
    tuerkis => { core => '#00838F', glow => '#3FD9E4', txt => $IVORY, wort => 'TÜRKIS', sym => 'welle' },
    orange  => { core => '#FF6F00', glow => '#FFA64D', txt => $INK,   wort => 'ORANGE', sym => 'laterne' },
    lila    => { core => q{#4527A0}, glow => q{#B9A6FF}, txt => $IVORY, wort => 'LILA',   sym => 'stern' },
    joker   => { core => '#14193A', glow => $GOLDL,    txt => $GOLDL, wort => '',       sym => '' },
    mond    => { core => q{#6F55E8}, glow => q{#B9A8FF}, txt => $IVORY, wort => q{NACHT}, sym => q{stern} },
  },
);
my @HELL_ORDER   = qw(rot gelb gruen blau);
my @DUNKEL_ORDER = qw(pink tuerkis orange lila);

our $FONT_DISPLAY = "Limelight, 'Playfair Display', Georgia, serif";
our $FONT_LABEL   = "'Josefin Sans', 'Century Gothic', Futura, sans-serif";

# ------------------------------------------------------------------ Formsymbole
# Alle Symbole in einer 100er-Box um (0,0). Primitive: d (Pfad), mode fill|stroke, w, color, rule
sub poly_star {
  my ($n, $ro, $ri, $rot) = @_;
  my @p;
  for my $i (0 .. 2 * $n - 1) {
    my $r = $i % 2 ? $ri : $ro;
    my $a = rad($rot + $i * 180 / $n);
    push @p, f($r * cos($a)) . ',' . f($r * sin($a));
  }
  'M' . join(' L', @p) . ' Z';
}

sub sun_shape {
  my ($rc, $rl, $rs, $hw) = @_;
  my $d = sprintf('M%s,0 A%s,%s 0 1 0 -%s,0 A%s,%s 0 1 0 %s,0 Z ', ($rc) x 7);
  for my $i (0 .. 7) {
    my $a = rad($i * 45 - 90);
    my $R = $i % 2 ? $rs : $rl;
    my ($c, $s) = (cos($a), sin($a));
    my $rb = $rc + 4;
    $d .= sprintf('M%s,%s L%s,%s L%s,%s Z ',
      f($rb * $c - $hw * $s), f($rb * $s + $hw * $c), f($R * $c), f($R * $s), f($rb * $c + $hw * $s), f($rb * $s - $hw * $c));
  }
  $d;
}

sub clover_shape {
  my $leaf = 'M0,-3 C-12,-10 -27,-22 -25,-37 C-23,-50 -7,-52 0,-41 C7,-52 23,-50 25,-37 C27,-22 12,-10 0,-3 Z';
  my @prims;
  for my $a (45, 135, 225, 315) {
    push @prims, { d => $leaf, mode => 'fill', tf => "rotate($a)" };
  }
  push @prims, { d => 'M3,3 C10,16 16,28 30,40 L25,46 C12,32 5,20 -2,7 Z', mode => 'fill' };
  @prims;
}

sub sym_prims {
  my $n = shift;
  if ($n eq 'flamme') {
    return (
      { d => 'M2,-49 C10,-34 30,-22 33,0 C36,24 22,46 0,47 C-22,46 -36,26 -32,4 C-30,-10 -22,-18 -17,-30 C-12,-20 -10,-14 -8,-6 C-4,-22 -8,-36 2,-49 Z'
          . ' M1,8 C7,16 14,24 13,33 C12,40 6,43 0,43 C-7,43 -13,38 -12,30 C-11,22 -4,17 1,8 Z', mode => 'fill', rule => 'evenodd' },
    );
  }
  if ($n eq 'sonne')    { return ({ d => sun_shape(19, 49, 39, 8.5), mode => 'fill' }) }
  if ($n eq 'klee')     { return clover_shape() }
  if ($n eq 'kristall') {
    return (
      { d => 'M-46,-12 L-27,-37 L27,-37 L46,-12 L0,46 Z', mode => 'fill' },
      { d => 'M-46,-12 L46,-12 M-27,-37 L-13,-12 L0,-37 L13,-12 L27,-37 M-13,-12 L0,46 L13,-12', mode => 'stroke', w => 3.5, color => 'cut' },
    );
  }
  if ($n eq 'herz') {
    return ({ d => 'M0,45 C-12,34 -47,11 -47,-13 C-47,-32 -33,-42 -21,-42 C-11,-42 -4,-36 0,-27 C4,-36 11,-42 21,-42 C33,-42 47,-32 47,-13 C47,11 12,34 0,45 Z', mode => 'fill' });
  }
  if ($n eq 'welle') {
    my @p;
    for my $y (-25, 0, 25) {
      push @p, { d => sprintf('M-42,%s C-34,%s -24,%s -14,%s S6,%s 14,%s S34,%s 42,%s', $y + 5, $y - 9, $y - 9, $y, $y + 9, $y, $y - 9, $y - 5), mode => 'stroke', w => 11 };
    }
    return @p;
  }
  if ($n eq 'laterne') {
    return (
      { d => 'M0,-49 A7,7 0 1 1 -0.1,-49 Z', mode => 'stroke', w => 4.5 },
      { d => 'M-21,-31 L-11,-41 L11,-41 L21,-31 Z', mode => 'fill' },
      { d => 'M-19,-29 H19 L29,-12 V18 L19,33 H-19 L-29,18 V-12 Z M-10,-18 H10 L17,-7 V13 L10,23 H-10 L-17,13 V-7 Z', mode => 'fill', rule => 'evenodd' },
      { d => 'M0,-8 C4,-2 8,4 7,10 C6,15 3,17 0,17 C-3,17 -6,15 -7,10 C-8,4 -4,-2 0,-8 Z', mode => 'fill' },
      { d => 'M-15,35 H15 V44 H-15 Z', mode => 'fill' },
    );
  }
  if ($n eq 'stern') { return ({ d => poly_star(5, 52, 21, -90), mode => 'fill', tf => 'translate(0,5)' }) }
  die "unbekanntes Symbol $n";
}

# ------------------------------------------------------------------ Aktionspiktogramme
sub arrow_arc {
  my ($r, $a0, $a1, $hw, $hl) = @_;
  my ($x0, $y0) = ($r * cos(rad($a0)), $r * sin(rad($a0)));
  my ($x1, $y1) = ($r * cos(rad($a1)), $r * sin(rad($a1)));
  my $large = (($a1 - $a0) % 360) > 180 ? 1 : 0;
  my $arc = sprintf('M%s,%s A%s,%s 0 %d 1 %s,%s', f($x0), f($y0), $r, $r, $large, f($x1), f($y1));
  my ($nx, $ny) = (cos(rad($a1)), sin(rad($a1)));
  my ($tx, $ty) = (-$ny, $nx);
  my $head = sprintf('M%s,%s L%s,%s L%s,%s Z',
    f($x1 + $nx * $hw - $tx * 3), f($y1 + $ny * $hw - $ty * 3),
    f($x1 + $tx * $hl), f($y1 + $ty * $hl),
    f($x1 - $nx * $hw - $tx * 3), f($y1 - $ny * $hw - $ty * 3));
  return ({ d => $arc, mode => 'stroke', w => 12, cap => 'butt' }, { d => $head, mode => 'fill' });
}

sub icon_prims {
  my $n = shift;
  if ($n eq 'sanduhr') {
    return (
      { d => 'M-30,-36 V36 M30,-36 V36', mode => 'stroke', w => 3.5 },
      { d => 'M-25,-36 C-25,-13 -5,-8 -5,0 C-5,8 -25,13 -25,36 H25 C25,13 5,8 5,0 C5,-8 25,-13 25,-36 Z', mode => 'fill', color => 'glass', sw => 5 },
      { d => 'M-17,-21 H17 C12,-12 4,-8 0,-3 C-4,-8 -12,-12 -17,-21 Z', mode => 'fill', color => 'sand' },
      { d => 'M-22,32 C-15,21 -6,15 0,9 C6,15 15,21 22,32 Z', mode => 'fill', color => 'sand' },
      { d => 'M0,-3 V12', mode => 'stroke', w => 2.5, color => 'sand' },
      { d => 'M-38,-48 H38 V-36 H-38 Z M-38,36 H38 V48 H-38 Z', mode => 'fill' },
    );
  }
  if ($n eq 'sanduhr_kreis') {
    my @p = ({ d => 'M0,-46 A46,46 0 1 1 -0.1,-46 Z', mode => 'stroke', w => 6 });
    for my $a (0, 90, 180, 270) {
      my ($x, $y) = (46 * cos(rad($a + 45)), 46 * sin(rad($a + 45)));
      push @p, { d => sprintf('M%s,%s m-6,0 a6,6 0 1 0 12,0 a6,6 0 1 0 -12,0 Z', f($x), f($y)), mode => 'fill' };
    }
    for my $q (icon_prims('sanduhr')) { my %c = %$q; $c{tf} = 'scale(0.58)'; push @p, \%c }
    return @p;
  }
  if ($n eq 'richtung') {
    return (arrow_arc(31, 160, 292, 14, 20), arrow_arc(31, 340, 472, 14, 20));
  }
  if ($n eq 'flip') {
    my @p = (
      { d => 'M0,-33 A33,33 0 1 1 -0.1,-33 Z', mode => 'stroke', w => 5.5 },
      { d => 'M0,-33 A33,33 0 0 0 0,33 Z', mode => 'fill' },
      { d => 'M14,-14 L16.5,-6.5 L24,-4 L16.5,-1.5 L14,6 L11.5,-1.5 L4,-4 L11.5,-6.5 Z', mode => 'fill' },
      { d => 'M17,14 m-3.5,0 a3.5,3.5 0 1 0 7,0 a3.5,3.5 0 1 0 -7,0 Z', mode => 'fill' },
    );
    for my $a (120, 150, 180, 210, 240) {
      my ($c, $s) = (cos(rad($a)), sin(rad($a)));
      push @p, { d => sprintf('M%s,%s L%s,%s L%s,%s Z', f(40 * $c - 4.5 * $s), f(40 * $s + 4.5 * $c), f(53 * $c), f(53 * $s), f(40 * $c + 4.5 * $s), f(40 * $s - 4.5 * $c)), mode => 'fill' };
    }
    return @p;
  }
  if ($n eq 'pfote') {
    my @p = ({ d => 'M0,2 C16,2 30,13 38,27 C44,38 42,50 31,51 C24,52 20,47 14,47 C10,51 5,53 0,53 C-5,53 -10,51 -14,47 C-20,47 -24,52 -31,51 C-42,50 -44,38 -38,27 C-30,13 -16,2 0,2 Z', mode => 'fill', color => 'pad' });
    my @toes = ([-37, -13, -22], [-13, -35, -8], [13, -35, 8], [37, -13, 22]);
    for my $i (0 .. 3) {
      my ($x, $y, $r) = @{ $toes[$i] };
      push @p, { d => 'M0,-16 C7,-16 11,-8 11,0 C11,9 6,16 0,16 C-6,16 -11,9 -11,0 C-11,-8 -7,-16 0,-16 Z', mode => 'fill', color => "c$i", tf => "translate($x,$y) rotate($r)" };
    }
    return @p;
  }
  if ($n eq 'auge') {
    my @p = ({ d => 'M-49,0 C-29,-33 29,-33 49,0 C29,33 -29,33 -49,0 Z', mode => 'fill', color => 'eyewhite', sw => 4.5 });
    for my $i (0 .. 3) {
      my ($a0, $a1) = ($i * 90 - 90 + 9, $i * 90 - 90 + 81);
      push @p, { d => sprintf('M%s,%s A20,20 0 0 1 %s,%s', f(20 * cos(rad($a0))), f(20 * sin(rad($a0))), f(20 * cos(rad($a1))), f(20 * sin(rad($a1)))), mode => 'stroke', w => 9, color => "c$i", cap => 'butt' };
    }
    push @p, { d => 'M0,-14 A14,14 0 1 1 -0.1,-14 Z', mode => 'fill', color => 'pupilbg' };
    push @p, { d => 'M0,-15 C4,-7 4,7 0,15 C-4,7 -4,-7 0,-15 Z', mode => 'fill', color => 'pupil' };
    push @p, { d => 'M-8,-11 m-3,0 a3,3 0 1 0 6,0 a3,3 0 1 0 -6,0 Z', mode => 'fill', color => 'shine' };
    return @p;
  }
  if ($n eq 'joker4') {
    my @p;
    my @pos = ([0, -22], [22, 0], [0, 22], [-22, 0]);
    for my $i (0 .. 3) {
      my ($x, $y) = @{ $pos[$i] };
      push @p, { d => sprintf('M%s,%s l0,-13 l13,13 l-13,13 l-13,-13 Z', $x, $y), mode => 'fill', color => "c$i" };
    }
    return @p;
  }
  return sym_prims($n);
}

# Rendert Primitive. %o: col => {name => farbe}, main, stroke, sw (Konturbreite in Box-Einheiten),
# outline => 1 (alle Teile einfarbig in main, Breite + sw)
sub render_prims {
  my ($prims, %o) = @_;
  my $out = '';
  for my $p (@$prims) {
    my $cname = $p->{color} // 'main';
    my $col = $o{outline} ? $o{main} : ($cname eq 'main' ? $o{main} : ($o{col}{$cname} // $o{main}));
    my $tf = $p->{tf} ? qq( transform="$p->{tf}") : '';
    my $rule = $p->{rule} ? qq( fill-rule="$p->{rule}") : '';
    my $cap = $p->{cap} // 'round';
    if ($p->{mode} eq 'fill') {
      if ($o{outline}) {
        $out .= qq(<path d="$p->{d}"$tf$rule fill="$col" stroke="$col" stroke-width="@{[f($o{sw})]}" stroke-linejoin="round"/>);
      } else {
        my $sw = $p->{sw} // $o{sw} // 0;
        my $st = ($o{stroke} && $sw) ? qq( stroke="$o{stroke}" stroke-width="@{[f($sw)]}" stroke-linejoin="round") : '';
        $out .= qq(<path d="$p->{d}"$tf$rule fill="$col"$st/>);
      }
    } else {
      my $w = $p->{w};
      if ($o{outline}) {
        $out .= qq(<path d="$p->{d}"$tf fill="none" stroke="$col" stroke-width="@{[f($w + $o{sw})]}" stroke-linecap="$cap" stroke-linejoin="round"/>);
      } else {
        if ($o{stroke} && $o{sw} && !$o{nostrokeline}) {
          $out .= qq(<path d="$p->{d}"$tf fill="none" stroke="$o{stroke}" stroke-width="@{[f($w + $o{sw})]}" stroke-linecap="$cap" stroke-linejoin="round"/>);
        }
        $out .= qq(<path d="$p->{d}"$tf fill="none" stroke="$col" stroke-width="@{[f($w)]}" stroke-linecap="$cap" stroke-linejoin="round"/>);
      }
    }
  }
  $out;
}

sub place { my ($cx, $cy, $s, $inner) = @_; sprintf('<g transform="translate(%s %s) scale(%s)">%s</g>', f($cx), f($cy), $s, $inner) }

# ------------------------------------------------------------------ Karten
my ($W, $H, $R) = (560, 870, 34);
my ($AX0, $AX1, $AY, $AYB) = (72, 488, 104, 790);   # Bogenfenster
my ($ACX, $ACY, $AR) = (280, 312, 208);
my $HZ = 640;                                         # Horizont

sub arch_path { my $i = shift // 0; sprintf('M%s,%s L%s,%s A%s,%s 0 0 1 %s,%s L%s,%s Z', $AX0 + $i, $AYB - $i, $AX0 + $i, $ACY, $AR - $i, $AR - $i, $AX1 - $i, $ACY, $AX1 - $i, $AYB - $i) }

sub crescent {
  my ($cx, $cy, $r1, $dx, $dy, $r2) = @_;
  my $d = sqrt($dx * $dx + $dy * $dy);
  my $a = ($r1 * $r1 - $r2 * $r2 + $d * $d) / (2 * $d);
  my $h = sqrt($r1 * $r1 - $a * $a);
  my ($ux, $uy) = ($dx / $d, $dy / $d);
  my ($px, $py) = ($cx + $a * $ux, $cy + $a * $uy);
  my ($ix1, $iy1) = ($px - $h * $uy, $py + $h * $ux);
  my ($ix2, $iy2) = ($px + $h * $uy, $py - $h * $ux);
  sprintf('M%s,%s A%s,%s 0 1 1 %s,%s A%s,%s 0 0 0 %s,%s Z', f($ix1), f($iy1), $r1, $r1, f($ix2), f($iy2), $r2, $r2, f($ix1), f($iy1));
}

sub moon_phase {
  my ($cx, $cy, $r, $phase, $col, $line) = @_;    # phase: crescentL, halfL, full, halfR, crescentR
  my $o = sprintf('<circle cx="%s" cy="%s" r="%s" fill="none" stroke="%s" stroke-width="1.4"/>', f($cx), f($cy), $r, $line);
  if ($phase eq 'full') { return $o . sprintf('<circle cx="%s" cy="%s" r="%s" fill="%s"/>', f($cx), f($cy), $r, $col) }
  if ($phase =~ /half(L|R)/) {
    my $sweep = $1 eq 'L' ? 0 : 1;
    return $o . sprintf('<path d="M%s,%s A%s,%s 0 0 %d %s,%s Z" fill="%s"/>', f($cx), f($cy - $r), $r, $r, $sweep, f($cx), f($cy + $r), $col);
  }
  if ($phase =~ /crescent(L|R)/) {
    my $dx = $1 eq 'L' ? $r * 0.55 : -$r * 0.55;
    return $o . sprintf('<path d="%s" fill="%s"/>', crescent($cx, $cy, $r, $dx, -$r * 0.1, $r * 0.92), $col);
  }
}

sub sparkle {
  my ($x, $y, $s, $col, $op) = @_;
  $op //= 1;
  sprintf('<path d="M%s,%s L%s,%s L%s,%s L%s,%s L%s,%s L%s,%s L%s,%s L%s,%s Z" fill="%s" opacity="%s"/>',
    f($x), f($y - $s), f($x + $s * 0.22), f($y - $s * 0.22), f($x + $s), f($y), f($x + $s * 0.22), f($y + $s * 0.22),
    f($x), f($y + $s), f($x - $s * 0.22), f($y + $s * 0.22), f($x - $s), f($y), f($x - $s * 0.22), f($y - $s * 0.22), $col, $op);
}

sub defs_common {
  my ($P) = @_;
  return qq(<linearGradient id="$P-gold" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="560" y2="870">)
    . qq(<stop offset="0" stop-color="#A47A2C"/><stop offset="0.3" stop-color="#ECD38E"/><stop offset="0.55" stop-color="#B98F3E"/><stop offset="0.8" stop-color="#F1DA97"/><stop offset="1" stop-color="#9B7330"/></linearGradient>)
    . qq(<clipPath id="$P-card"><rect width="560" height="870" rx="$R"/></clipPath>)
    . qq(<clipPath id="$P-arch"><path d="@{[arch_path(0)]}"/></clipPath>)
    . qq(<filter id="$P-glow" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="7"/></filter>)
    . qq(<filter id="$P-glow2" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="3"/></filter>);
}

# Farben der vier Seitenfarben fuer Joker-Elemente
sub side_colors { my $side = shift; my @o = $side eq 'hell' ? @HELL_ORDER : @DUNKEL_ORDER; map { $PAL{$side}{$_}{core} } @o }

# --- Ebenen ---------------------------------------------------------------
sub layer_grund {
  my ($P, $side, $c) = @_;
  if ($side eq 'hell') {
    return qq(<radialGradient id="$P-paper" cx="0.5" cy="0.42" r="0.75"><stop offset="0" stop-color="#FBF6E9"/><stop offset="0.7" stop-color="$IVORY"/><stop offset="1" stop-color="$PAPER2"/></radialGradient>)
      . qq(<rect width="560" height="870" fill="url(#$P-paper)"/>);
  }
  return qq(<radialGradient id="$P-night" cx="0.5" cy="0.4" r="0.8"><stop offset="0" stop-color="$NIGHT2"/><stop offset="1" stop-color="$NIGHT"/></radialGradient>)
    . qq(<rect width="560" height="870" fill="url(#$P-night)"/>);
}

sub layer_motiv {
  my ($P, $side, $c, $joker, $opt) = @_;
  my $o = '';
  my $core = $c->{core};
  my @jc = side_colors($side);
  if ($side eq 'hell') {
    my $sky0 = $joker ? '#F8F1E0' : mix($IVORY, $core, 0.07);
    my $sky1 = $joker ? '#EFE2C4' : mix($IVORY, $core, 0.26);
    $o .= qq(<linearGradient id="$P-sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="$sky0"/><stop offset="1" stop-color="$sky1"/></linearGradient>);
    $o .= qq(<g clip-path="url(#$P-arch)"><rect x="$AX0" y="$AY" width="416" height="@{[$AYB-$AY]}" fill="url(#$P-sky)"/>);
    # Strahlenkranz
    my $n = 0;
    for (my $a = 180; $a < 360; $a += 7.5) {
      my ($a0, $a1) = (rad($a), rad($a + 3.75));
      my $fill = $joker ? $jc[$n % 4] : $core;
      my $op = $joker ? 0.28 : 0.13;
      $o .= sprintf('<path d="M280,%d L%s,%s L%s,%s Z" fill="%s" opacity="%s"/>', $HZ, f(280 + 700 * cos($a0)), f($HZ + 700 * sin($a0)), f(280 + 700 * cos($a1)), f($HZ + 700 * sin($a1)), $fill, $op);
      $n++;
    }
    for (my $a = 180 + 3.75; $a < 360; $a += 15) {
      $o .= sprintf('<path d="M280,%d L%s,%s" stroke="url(#%s-gold)" stroke-width="1.1" opacity="0.7"/>', $HZ, f(280 + 700 * cos(rad($a))), f($HZ + 700 * sin(rad($a))), $P);
    }
    # Sonne
    my $sunc = $joker ? "url(#$P-gold)" : $core;
    $o .= qq(<path d="M150,$HZ A130,130 0 0 1 410,$HZ Z" fill="$sunc"/>);
    for my $rr (106, 84, 62) {
      $o .= sprintf('<path d="M%s,%d A%s,%s 0 0 1 %s,%d" fill="none" stroke="%s" stroke-width="5" opacity="0.9"/>', 280 - $rr, $HZ, $rr, $rr, 280 + $rr, $HZ, $IVORY);
    }
    $o .= qq(<path d="M150,$HZ A130,130 0 0 1 410,$HZ" fill="none" stroke="url(#$P-gold)" stroke-width="3"/>);
    # Berge
    my $mt = $joker ? q{#3A3552} : ($c->{shade} // mix($core, $INK, 0.35));
    $o .= qq(<path d="M72,$HZ L72,586 L112,548 L146,574 L196,522 L262,$HZ Z" fill="$mt" opacity="0.92"/>);
    $o .= qq(<path d="M488,$HZ L488,580 L452,556 L414,584 L372,540 L304,$HZ Z" fill="$mt" opacity="0.92"/>);
    $o .= qq(<path d="M72,586 L112,548 L146,574 L196,522 L262,$HZ M488,580 L452,556 L414,584 L372,540 L304,$HZ" fill="none" stroke="url(#$P-gold)" stroke-width="2.2" stroke-linejoin="round"/>);
    # Wasser
    my $wat = $joker ? '#E6D6B4' : mix($IVORY, $core, 0.38);
    $o .= qq(<rect x="$AX0" y="$HZ" width="416" height="@{[$AYB-$HZ]}" fill="$wat"/>);
    my @bars = ([654, 118, 8], [672, 98, 7], [690, 80, 6], [708, 62, 5.5], [726, 46, 5], [744, 32, 4.5], [762, 20, 4]);
    my $k = 0;
    for my $b (@bars) {
      my ($y, $hw, $h) = @$b;
      my $bc = $joker ? $jc[$k++ % 4] : $core;
      $o .= sprintf('<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="%s"/>', f(280 - $hw), f($y - $h / 2), f(2 * $hw), f($h), f($h / 2), $bc);
    }
    for my $y (664, 700, 738, 776) {
      $o .= qq(<path d="M$AX0,$y H$AX1" stroke="url(#$P-gold)" stroke-width="1" opacity="0.55"/>);
    }
    $o .= qq(<path d="M$AX0,$HZ H$AX1" stroke="url(#$P-gold)" stroke-width="2.5"/>);
    $o .= '</g>';
    # kleine Sonnenpunkte entlang des Bogens
    for my $a (214, 240, 300, 326) {
      my ($x, $y) = ($ACX + 172 * cos(rad($a)), $ACY + 172 * sin(rad($a)));
      $o .= place($x, $y, 0.15, render_prims([{ d => sun_shape(19, 49, 39, 8.5), mode => 'fill' }], main => "url(#$P-gold)"));
    }
  } else {
    my $glow = $c->{glow};
    my $sky1 = $joker ? '#2A2350' : mix($NIGHT, $core, 0.42);
    $o .= qq(<linearGradient id="$P-sky" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#070A1E"/><stop offset="0.55" stop-color="#0E1338"/><stop offset="1" stop-color="$sky1"/></linearGradient>);
    $o .= qq(<g clip-path="url(#$P-arch)"><rect x="$AX0" y="$AY" width="416" height="@{[$AYB-$AY]}" fill="url(#$P-sky)"/>);
    # Sterne
    my @stars = ([120, 236, 9], [438, 270, 11], [176, 168, 5], [392, 186, 6], [110, 420, 6], [452, 452, 7], [140, 520, 4], [420, 520, 4], [330, 158, 4], [226, 150, 3]);
    for my $s (@stars) { $o .= sparkle(@$s, '#F4E7C3', 0.9) }
    for my $d ([150, 300], [410, 340], [196, 470], [370, 248], [96, 330], [466, 380], [250, 560], [318, 576]) {
      $o .= sprintf('<circle cx="%s" cy="%s" r="2" fill="#F4E7C3" opacity="0.7"/>', @$d);
    }
    # Mond
    unless ($opt->{nomoon}) {
      my $mc = $joker ? "url(#$P-gold)" : $core;
      my $mg = $joker ? $GOLDL : $glow;
      my $cres = crescent(280, 410, 168, 62, -52, 150);
      $o .= qq(<path d="$cres" fill="$mg" filter="url(#$P-glow)" opacity="0.85"/>);
      $o .= qq(<path d="$cres" fill="$mc"/>);
      $o .= qq(<path d="$cres" fill="none" stroke="$mg" stroke-width="2.5"/>);
    }
    # Berge
    $o .= qq(<path d="M72,$HZ L72,586 L112,548 L146,574 L196,522 L262,$HZ Z M488,$HZ L488,580 L452,556 L414,584 L372,540 L304,$HZ Z" fill="#060818"/>);
    my $ml = $joker ? $GOLDL : $glow;
    $o .= qq(<path d="M72,586 L112,548 L146,574 L196,522 L262,$HZ M488,580 L452,556 L414,584 L372,540 L304,$HZ" fill="none" stroke="$ml" stroke-width="2" stroke-linejoin="round" opacity="0.9"/>);
    # Wasser
    $o .= qq(<rect x="$AX0" y="$HZ" width="416" height="@{[$AYB-$HZ]}" fill="#070A1E"/>);
    my @bars = ([654, 118, 4], [672, 98, 3.5], [690, 80, 3.5], [708, 62, 3], [726, 46, 3], [744, 32, 2.5], [762, 20, 2.5]);
    my $k = 0;
    for my $b (@bars) {
      my ($y, $hw, $h) = @$b;
      my $bc = $joker ? $jc[$k++ % 4] : $glow;
      $o .= sprintf('<rect x="%s" y="%s" width="%s" height="%s" rx="%s" fill="%s"/>', f(280 - $hw), f($y - $h / 2), f(2 * $hw), f($h), f($h / 2), $bc);
    }
    $o .= qq(<path d="M$AX0,$HZ H$AX1" stroke="$ml" stroke-width="2.5"/>);
    $o .= '</g>';
    # Mondphasen entlang des Bogens
    my @ph = (['crescentL', 214], ['halfL', 240], ['halfR', 300], ['crescentR', 326]);
    for my $p (@ph) {
      my ($x, $y) = ($ACX + 172 * cos(rad($p->[1])), $ACY + 172 * sin(rad($p->[1])));
      $o .= moon_phase($x, $y, 8, $p->[0], $GOLDL, $GOLD);
    }
  }
  $o;
}

sub layer_rahmen {
  my ($P, $side, $c, $joker) = @_;
  my $g = "url(#$P-gold)";
  my $o = '';
  # Neon-Kontur (dunkel)
  if ($side eq 'dunkel') {
    my $gl = $c->{glow};
    $o .= qq(<path d="@{[arch_path(0)]}" fill="none" stroke="$gl" stroke-width="9" filter="url(#$P-glow)" opacity="0.9"/>);
    $o .= qq(<path d="@{[arch_path(0)]}" fill="none" stroke="$gl" stroke-width="3"/>);
    $o .= qq(<rect x="16" y="16" width="528" height="838" rx="22" fill="none" stroke="$gl" stroke-width="6" filter="url(#$P-glow2)" opacity="0.7"/>);
  } else {
    $o .= qq(<path d="@{[arch_path(0)]}" fill="none" stroke="$g" stroke-width="3.5"/>);
  }
  $o .= qq(<path d="@{[arch_path(-9)]}" fill="none" stroke="$g" stroke-width="1.2"/>);
  $o .= qq(<rect x="16" y="16" width="528" height="838" rx="22" fill="none" stroke="$g" stroke-width="3"/>);
  $o .= qq(<rect x="26" y="26" width="508" height="818" rx="14" fill="none" stroke="$g" stroke-width="1.2"/>);
  # Eckfächer oben rechts und unten links
  for my $corner ([520, 40, 90, 180], [40, 830, 270, 360]) {
    my ($cx, $cy, $a0, $a1) = @$corner;
    for my $rr (58, 44, 30) {
      $o .= sprintf('<path d="M%s,%s A%s,%s 0 0 1 %s,%s" fill="none" stroke="%s" stroke-width="1.3"/>',
        f($cx + $rr * cos(rad($a0))), f($cy + $rr * sin(rad($a0))), $rr, $rr, f($cx + $rr * cos(rad($a1))), f($cy + $rr * sin(rad($a1))), $g);
    }
    for (my $a = $a0 + 15; $a < $a1; $a += 15) {
      $o .= sprintf('<path d="M%s,%s L%s,%s" stroke="%s" stroke-width="1.3"/>', f($cx + 30 * cos(rad($a))), f($cy + 30 * sin(rad($a))), f($cx + 58 * cos(rad($a))), f($cy + 58 * sin(rad($a))), $g);
    }
    $o .= sprintf('<circle cx="%s" cy="%s" r="6" fill="%s"/>', $cx, $cy, $g);
  }
  # Titelband unten
  $o .= qq(<path d="M150,816 H410" stroke="$g" stroke-width="1"/>);
  $o;
}

# Wert in der Mitte
sub value_text_layers {
  my ($P, $side, $c, $txt, $x, $y, $size, $underline) = @_;
  my $o = '';
  my $core = $c->{core};
  my $fam = $FONT_DISPLAY;
  my $t = sub {
    my ($attrs) = @_;
    my $s = qq(<text x="$x" y="$y" font-family="$fam" font-size="$size" text-anchor="middle" $attrs>$txt</text>);
    if ($underline) {
      my $uw = $size * 0.42;
      my $uy = $y + $size * 0.07;
      my $uh = $size * 0.045;
      $s .= sprintf('<rect x="%s" y="%s" width="%s" height="%s" rx="%s" %s/>', f($x - $uw / 2), f($uy), f($uw), f($uh), f($uh / 2), $attrs);
    }
    $s;
  };
  if ($side eq 'hell') {
    $o .= $t->(qq(fill="url(#$P-gold)" stroke="url(#$P-gold)" stroke-width="30" stroke-linejoin="round"));
    $o .= $t->(qq(fill="$IVORY" stroke="$IVORY" stroke-width="22" stroke-linejoin="round"));
    $o .= $t->(qq(fill="$core" stroke="$INK" stroke-width="7" stroke-linejoin="round" paint-order="stroke"));
  } else {
    my $gl = $c->{glow};
    $o .= $t->(qq(fill="$gl" stroke="$gl" stroke-width="18" stroke-linejoin="round" filter="url(#$P-glow)" opacity="0.75"));
    $o .= $t->(qq(fill="$NIGHT" stroke="$NIGHT" stroke-width="20" stroke-linejoin="round"));
    $o .= $t->(qq(fill="$NIGHT" stroke="$gl" stroke-width="8" stroke-linejoin="round"));
  }
  $o;
}

sub icon_layers {
  my ($P, $side, $c, $prims, $cx, $cy, $s, %extra) = @_;
  my $core = $c->{core};
  my @jc = side_colors($side);
  my %col = (c0 => $jc[0], c1 => $jc[1], c2 => $jc[2], c3 => $jc[3]);
  my $o = '';
  if ($side eq 'hell') {
    %col = (%col, glass => '#FBF6EA', sand => $core, pad => $INK, eyewhite => $IVORY, pupilbg => $INK, pupil => "url(#$P-gold)", shine => $IVORY, cut => $IVORY, %extra);
    $o .= place($cx, $cy, $s, render_prims($prims, main => "url(#$P-gold)", outline => 1, sw => 10 / $s * 3));
    $o .= place($cx, $cy, $s, render_prims($prims, main => $IVORY, outline => 1, sw => 7.4 / $s * 3));
    $o .= place($cx, $cy, $s, render_prims($prims, main => $core, stroke => $INK, sw => 2.4 / $s * 3, col => \%col));
  } else {
    my $gl = $c->{glow};
    %col = (%col, glass => $NIGHT, sand => $gl, pad => $NIGHT, eyewhite => $NIGHT, pupilbg => '#05071A', pupil => $GOLDL, shine => '#FFFFFF', cut => $NIGHT, %extra);
    $o .= sprintf('<g filter="url(#%s-glow)" opacity="0.8">%s</g>', $P, place($cx, $cy, $s, render_prims($prims, main => $gl, outline => 1, sw => 8 / $s * 3)));
    $o .= place($cx, $cy, $s, render_prims($prims, main => $NIGHT, outline => 1, sw => 7 / $s * 3));
    $o .= place($cx, $cy, $s, render_prims($prims, main => $core, stroke => $gl, sw => 2.6 / $s * 3, col => \%col));
  }
  $o;
}

sub layer_wert {
  my ($P, $side, $c, $type, $val) = @_;
  return q{} if $type eq q{logo};
  if ($type eq 'zahl') {
    return value_text_layers($P, $side, $c, $val, 280, 548, 400, ($val eq '6' || $val eq '9'));
  }
  if ($type eq 'plus') {
    return value_text_layers($P, $side, $c, $val, 280, 535, 330, 0);
  }
  my %map = (aussetzen => 'sanduhr', alle_aussetzen => 'sanduhr_kreis', richtung => 'richtung', flip => 'flip', wuenscher => 'pfote', farbjagd => 'auge');
  if ($type eq 'wuenscher_plus2') {
    return icon_layers($P, $side, $c, [icon_prims(q{pfote})], 280, 300, 2.0) . pad_line($P, $side, 280, 300, 2.0) . value_text_layers($P, $side, $c, '+2', 280, 596, 230, 0);
  }
  my $icon = $map{$type} // die "Typ $type";
  my $s = { sanduhr => 3.0, sanduhr_kreis => 3.1, richtung => 3.2, flip => 3.2, pfote => 3.0, auge => 3.4 }->{$icon};
  return icon_layers($P, $side, $c, [icon_prims($icon)], 280, 420, $s) . ($icon eq q{pfote} ? pad_line($P, $side, 280, 420, $s) : q{});
}

sub pad_line {
  my ($P, $side, $cx, $cy, $s) = @_;
  my $d = (icon_prims(q{pfote}))[0]{d};
  my $col = $side eq q{hell} ? "url(#$P-gold)" : q{#EBD08A};
  return place($cx, $cy, $s, sprintf(q{<path d="%s" transform="translate(0 29) scale(0.72) translate(0 -29)" fill="none" stroke="%s" stroke-width="%s"/>}, $d, $col, f(2.2 / $s * 3 / 1.5)));
}

sub layer_symbol {
  my ($P, $side, $c, $joker, $type) = @_;
  my ($x, $y) = (280, $AY);
  my $o = '';
  my $g = "url(#$P-gold)";
  my $bg = $side eq 'hell' ? $IVORY : $NIGHT;
  $o .= qq(<circle cx="$x" cy="$y" r="37" fill="$bg" stroke="$g" stroke-width="3"/>);
  $o .= qq(<circle cx="$x" cy="$y" r="30" fill="none" stroke="$g" stroke-width="1"/>);
  my @jc = side_colors($side);
  if ($joker) {
    $o .= place($x, $y, 0.42, render_prims([icon_prims('joker4')], main => $GOLD, col => { c0 => $jc[0], c1 => $jc[1], c2 => $jc[2], c3 => $jc[3] }));
  } else {
    my @pr = sym_prims($c->{sym});
    if ($side eq 'hell') {
      $o .= place($x, $y, 0.46, render_prims(\@pr, main => $c->{core}, stroke => $INK, sw => 4, col => { cut => $IVORY }));
    } else {
      $o .= sprintf('<g filter="url(#%s-glow2)">%s</g>', $P, place($x, $y, 0.46, render_prims(\@pr, main => $c->{glow}, outline => 1, sw => 4)));
      $o .= place($x, $y, 0.46, render_prims(\@pr, main => $c->{core}, stroke => $c->{glow}, sw => 3, col => { cut => $NIGHT }));
    }
  }
  $o;
}

# Eckindex als Banner (oben links, unten rechts gedreht)
sub banner_one {
  my ($P, $side, $c, $joker, $type, $val) = @_;
  my ($x0, $x1, $y0, $yb, $yp) = (28, 132, 16, 252, 284);
  my $cx = ($x0 + $x1) / 2;
  my $g = "url(#$P-gold)";
  my $fill = $c->{core};
  my $txt = $c->{txt};
  my $shape = "M$x0,$y0 H$x1 V$yb L$cx,$yp L$x0,$yb Z";
  my $inner = sprintf('M%s,%s H%s V%s L%s,%s L%s,%s Z', $x0 + 6, $y0, $x1 - 6, $yb - 3, $cx, $yp - 9, $x0 + 6, $yb - 3);
  my $o = '';
  if ($side eq 'dunkel') {
    $o .= qq(<path d="$shape" fill="$c->{glow}" filter="url(#$P-glow)" opacity="0.55"/>);
  } else {
    $o .= qq(<path d="$shape" fill="$INK" opacity="0.18" transform="translate(0 4)"/>);
  }
  $o .= qq(<path d="$shape" fill="$fill" stroke="$g" stroke-width="3" stroke-linejoin="round"/>);
  $o .= qq(<path d="$inner" fill="none" stroke="$g" stroke-width="1.2" stroke-linejoin="round" opacity="0.9"/>);
  my @jc = side_colors($side);
  my %jcol = (c0 => $jc[0], c1 => $jc[1], c2 => $jc[2], c3 => $jc[3]);
  my $vy = 150;   # Grundlinie Wert
  my $sy = 210;   # Mitte Symbol
  my $valsvg = '';
  my $symsvg = '';
  my $font = qq(font-family="$FONT_DISPLAY" text-anchor="middle" fill="$txt");
  if ($type eq 'zahl') {
    $valsvg = qq(<text x="$cx" y="$vy" $font font-size="122">$val</text>);
    if ($val eq '6' || $val eq '9') {
      $valsvg .= sprintf('<rect x="%s" y="%s" width="54" height="7" rx="3.5" fill="%s"/>', $cx - 27, $vy + 9, $txt);
    }
  } elsif ($type eq 'plus' || $type eq 'wuenscher_plus2') {
    my $n = substr($val, 1);
    $valsvg = qq(<text x="@{[$cx+4]}" y="$vy" $font font-size="112" letter-spacing="-6"><tspan font-size="72" dy="-13">+</tspan><tspan dy="13">$n</tspan></text>);
  } else {
    my %map = (aussetzen => 'sanduhr', alle_aussetzen => 'sanduhr_kreis', richtung => 'richtung', flip => 'flip', wuenscher => 'pfote', farbjagd => 'auge');
    my $ic = $map{$type};
    my $s = { sanduhr => 0.86, sanduhr_kreis => 0.88, richtung => 1.0, flip => 0.98, pfote => 0.84, auge => 0.9 }->{$ic};
    my %col = (%jcol, glass => $fill, sand => $txt, pad => $txt, eyewhite => $txt, pupilbg => $fill, pupil => $txt, shine => $fill, cut => $fill);
    if ($ic eq 'pfote') { %col = (%col, pad => $txt) }
    if ($ic eq 'auge') { %col = (%col, eyewhite => $txt, pupilbg => $fill, pupil => $GOLDL, shine => $IVORY) }
    my $sw = $ic eq 'sanduhr' ? 0 : 0;
    $valsvg = place($cx, $vy - 54, $s, render_prims([icon_prims($ic)], main => $txt, col => \%col, stroke => ($ic eq 'sanduhr' ? $txt : undef), sw => ($ic eq 'sanduhr' ? 5 : 0), nostrokeline => 1));
  }
  if ($joker) {
    if ($type eq 'wuenscher_plus2') {
      $symsvg = place($cx, $sy + 4, 0.66, render_prims([icon_prims('pfote')], main => $txt, col => { %jcol, pad => $txt }));
    } else {
      $symsvg = place($cx, $sy + 4, 0.62, render_prims([icon_prims('joker4')], main => $txt, col => \%jcol));
    }
  } else {
    my @pr = sym_prims($c->{sym});
    $symsvg = place($cx, $sy + 4, 0.64, render_prims(\@pr, main => $txt, col => { cut => $fill }));
  }
  $o . $valsvg . $symsvg;
}

sub layer_index {
  my ($P, @a) = @_;
  return q{} if $a[3] eq q{logo};
  my $b = banner_one($P, @a);
  return qq(<g>$b</g><g transform="rotate(180 280 435)">$b</g>);
}

sub layer_titel {
  my ($P, $side, $c, $joker, $type) = @_;
  my %names = (wuenscher => 'WÜNSCHER', wuenscher_plus2 => 'WÜNSCHER', farbjagd => 'FARBJAGD');
  my $w = $joker ? $names{$type} : $c->{wort};
  my $col = $side eq 'hell' ? $INK : $GOLDL;
  return qq(<text x="280" y="836" font-family="$FONT_LABEL" font-weight="700" font-size="22" letter-spacing="7" text-anchor="middle" fill="$col">$w</text>);
}

sub card_svg {
  my ($spec, $P, $standalone) = @_;
  my ($name, $side, $color, $type, $val) = @$spec;
  my $c = $PAL{$side}{$color} or die "Farbe $side/$color";
  my $joker = $color eq 'joker';
  my $file = ($standalone // 0) eq q{1};
  my $nested = ($standalone // 0) eq q{nested};
  my $gid = sub { $file ? qq(id="$_[0]") : qq(class="ebene-$_[0]") };
  my $opt = {};
  $opt->{nomoon} = 0;
  my $svg = '';
  if ($nested) { $svg .= q{<svg viewBox="0 0 560 870" width="560" height="870" overflow="visible">} }
  else {
    $svg .= sprintf(q{<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 560 870" width="%s" height="%s"%s>},
      $file ? 560 : q{100%}, $file ? 870 : q{100%}, $file ? q{} : q{ preserveAspectRatio="xMidYMid meet"});
  }
  $svg .= "<title>Mau-Mau Flip – $name</title>" if $file;
  $svg .= '<defs>' . defs_common($P) . '</defs>';
  $svg .= qq(<g clip-path="url(#$P-card)">);
  $svg .= '<g ' . $gid->('grund') . '>' . layer_grund($P, $side, $c) . '</g>';
  $svg .= '<g ' . $gid->('motiv') . '>' . layer_motiv($P, $side, $c, $joker, $opt) . '</g>';
  $svg .= '<g ' . $gid->('rahmen') . '>' . layer_rahmen($P, $side, $c, $joker) . layer_titel($P, $side, $c, $joker, $type) . '</g>';
  $svg .= '<g ' . $gid->('wert') . '>' . layer_wert($P, $side, $c, $type, $val) . '</g>';
  $svg .= '<g ' . $gid->('symbol') . '>' . layer_symbol($P, $side, $c, $joker, $type) . '</g>';
  $svg .= '<g ' . $gid->('index') . '>' . layer_index($P, $side, $c, $joker, $type, $val) . '</g>';
  $svg .= '</g>';
  my $edge = $side eq 'hell' ? '#CDBB92' : '#000000';
  $svg .= qq(<rect x="0.75" y="0.75" width="558.5" height="868.5" rx="33.5" fill="none" stroke="$edge" stroke-width="1.5"/>);
  $svg .= '</svg>';
  $svg;
}

our @CARDS = (
  ['hell_rot_7',                 'hell', 'rot',   'zahl', '7'],
  ['hell_gelb_plus1',            'hell', 'gelb',  'plus', '+1'],
  ['hell_gruen_aussetzen',       'hell', 'gruen', 'aussetzen', ''],
  ['hell_blau_richtungswechsel', 'hell', 'blau',  'richtung', ''],
  ['hell_rot_flip',              'hell', 'rot',   'flip', ''],
  ['hell_wuenscher',             'hell', 'joker', 'wuenscher', ''],
  ['hell_wuenscher_plus2',       'hell', 'joker', 'wuenscher_plus2', '+2'],
  ['hell_blau_9',                'hell', 'blau',  'zahl', '9'],
  ['dunkel_tuerkis_7',           'dunkel', 'tuerkis', 'zahl', '7'],
  ['dunkel_pink_plus5',          'dunkel', 'pink',    'plus', '+5'],
  ['dunkel_orange_alle_aussetzen','dunkel', 'orange', 'alle_aussetzen', ''],
  ['dunkel_lila_richtungswechsel','dunkel', 'lila',   'richtung', ''],
  ['dunkel_pink_flip',           'dunkel', 'pink',    'flip', ''],
  ['dunkel_wuenscher',           'dunkel', 'joker',   'wuenscher', ''],
  ['dunkel_farbjagd',            'dunkel', 'joker',   'farbjagd', ''],
  ['dunkel_lila_6',              'dunkel', 'lila',    'zahl', '6'],
  # Zusatzkarten fuer die Handansicht
  ['hell_gelb_4',                'hell', 'gelb',  'zahl', '4'],
  ['hell_gruen_2',               'hell', 'gruen', 'zahl', '2'],
  ['hell_rot_5',                 'hell', 'rot',   'zahl', '5'],
  ['dunkel_orange_3',            'dunkel', 'orange', 'zahl', '3'],
  ['dunkel_pink_8',              'dunkel', 'pink',   'zahl', '8'],
  ['dunkel_tuerkis_alle_aussetzen','dunkel', 'tuerkis','alle_aussetzen', ''],
  ['dunkel_lila_1',              'dunkel', 'lila',   'zahl', '1'],
);

sub write_file {
  my ($rel, $content) = @_;
  my $path = "$ROOT/$rel";
  open(my $fh, '>:encoding(UTF-8)', $path) or die "$path: $!";
  print $fh $content;
  close $fh;
}

sub card_by_name { my $n = shift; for (@CARDS) { return $_ if $_->[0] eq $n } die "Karte $n" }

1;
