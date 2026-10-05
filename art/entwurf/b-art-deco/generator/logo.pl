#!/usr/bin/perl
# Logo (1600 x 900) und App-Symbol (512 x 512) fuer Entwurf B "Art déco / Tarot"
use strict;
use warnings;
use utf8;

our ($IVORY, $INK, $NIGHT, $GOLD, $GOLDL, $FONT_DISPLAY, $FONT_LABEL);

sub logo_card {
  my ($P, $side, $col, $cx, $cy, $rot, $s) = @_;
  my $spec = ["logo_$side", $side, $col, 'logo', ''];
  my $inner = card_svg($spec, $P, 'nested');
  return sprintf('<g transform="translate(%s %s) rotate(%s) scale(%s) translate(-280 -435)">%s</g>', $cx, $cy, $rot, $s, $inner);
}

sub sunburst_lines {
  my ($cx, $cy, $r0, $r1, $n, $a0, $a1, $stroke, $op, $w) = @_;
  my $o = qq(<g stroke="$stroke" stroke-width="$w" opacity="$op">);
  for my $i (0 .. $n) {
    my $a = rad($a0 + ($a1 - $a0) * $i / $n);
    $o .= sprintf('<line x1="%s" y1="%s" x2="%s" y2="%s"/>', f($cx + $r0 * cos($a)), f($cy + $r0 * sin($a)), f($cx + $r1 * cos($a)), f($cy + $r1 * sin($a)));
  }
  $o . '</g>';
}

sub bubble {
  my ($P, $x, $y, $tipx, $tipy) = @_;
  # Sprechblase: abgerundetes Rechteck mit gestufter Spitze nach unten links
  my ($w, $h, $r) = (250, 120, 26);
  my ($x0, $y0) = ($x - $w / 2, $y - $h / 2);
  my $shape = sprintf('M%s,%s H%s A%s,%s 0 0 1 %s,%s V%s A%s,%s 0 0 1 %s,%s H%s L%s,%s L%s,%s H%s A%s,%s 0 0 1 %s,%s V%s A%s,%s 0 0 1 %s,%s Z',
    $x0 + $r, $y0, $x0 + $w - $r, $r, $r, $x0 + $w, $y0 + $r, $y0 + $h - $r, $r, $r, $x0 + $w - $r, $y0 + $h,
    $x0 + 92, $tipx, $tipy, $x0 + 46, $y0 + $h, $x0 + $r, $r, $r, $x0, $y0 + $h - $r, $y0 + $r, $r, $r, $x0 + $r, $y0);
  my $o = '';
  $o .= qq(<path d="$shape" fill="#000" opacity="0.35" transform="translate(4 8)"/>);
  $o .= qq(<path d="$shape" fill="$IVORY" stroke="url(#$P-lgold)" stroke-width="5" stroke-linejoin="round"/>);
  my $inset = sprintf('M%s,%s H%s A%s,%s 0 0 1 %s,%s V%s A%s,%s 0 0 1 %s,%s H%s A%s,%s 0 0 1 %s,%s V%s A%s,%s 0 0 1 %s,%s Z',
    $x0 + $r, $y0 + 9, $x0 + $w - $r, $r - 9, $r - 9, $x0 + $w - 9, $y0 + $r, $y0 + $h - $r, $r - 9, $r - 9, $x0 + $w - $r, $y0 + $h - 9,
    $x0 + $r, $r - 9, $r - 9, $x0 + 9, $y0 + $h - $r, $y0 + $r, $r - 9, $r - 9, $x0 + $r, $y0 + 9);
  $o .= qq(<path d="$inset" fill="none" stroke="url(#$P-lgold)" stroke-width="1.4"/>);
  # kleine Faecher in den oberen Ecken
  for my $c ([$x0 + 9, $y0 + 9, 0, 90], [$x0 + $w - 9, $y0 + 9, 90, 180]) {
    my ($cx, $cy, $a0, $a1) = @$c;
    for my $rr (12, 20) {
      $o .= sprintf('<path d="M%s,%s A%s,%s 0 0 1 %s,%s" fill="none" stroke="url(#%s-lgold)" stroke-width="1.2"/>',
        f($cx + $rr * cos(rad($a0))), f($cy + $rr * sin(rad($a0))), $rr, $rr, f($cx + $rr * cos(rad($a1))), f($cy + $rr * sin(rad($a1))), $P);
    }
  }
  $o .= qq(<text x="$x" y="@{[$y+26]}" font-family="$FONT_DISPLAY" font-size="78" text-anchor="middle" fill="$INK">Mau!</text>);
  $o;
}

sub logo_defs {
  my ($P) = @_;
  return qq(<linearGradient id="$P-lgold" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="1600" y2="900"><stop offset="0" stop-color="#A47A2C"/><stop offset="0.3" stop-color="#F1DA97"/><stop offset="0.5" stop-color="#BC9240"/><stop offset="0.72" stop-color="#F3DD9C"/><stop offset="1" stop-color="#A07733"/></linearGradient>)
    . qq(<radialGradient id="$P-bg" cx="800" cy="400" r="900" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="#232A63"/><stop offset="0.55" stop-color="#121640"/><stop offset="1" stop-color="#070A1E"/></radialGradient>)
    . qq(<linearGradient id="$P-word" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFF8E2"/><stop offset="0.55" stop-color="#F3DDA0"/><stop offset="1" stop-color="#D6AE5C"/></linearGradient>)
    . qq(<linearGradient id="$P-flip" gradientUnits="userSpaceOnUse" x1="916" y1="0" x2="1400" y2="0"><stop offset="0" stop-color="#FFF3D0"/><stop offset="0.5" stop-color="#FFF3D0"/><stop offset="0.5" stop-color="#C9BBFF"/><stop offset="1" stop-color="#A994FF"/></linearGradient>)
    . qq(<filter id="$P-lglow" x="-20%" y="-50%" width="140%" height="200%"><feGaussianBlur stdDeviation="10"/></filter>)
    . qq(<filter id="$P-soft" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="30"/></filter>);
}

sub logo_inner {
  my ($P, %o) = @_;
  my $g = "url(#$P-lgold)";
  my $s = '';
  # --- Hintergrund
  $s .= qq(<g id="hintergrund">);
  $s .= qq(<rect width="1600" height="900" fill="url(#$P-bg)"/>);
  $s .= qq(<circle cx="560" cy="360" r="300" fill="#E8762B" opacity="0.10" filter="url(#$P-soft)"/>);
  $s .= qq(<circle cx="1040" cy="360" r="300" fill="#6F55E8" opacity="0.16" filter="url(#$P-soft)"/>);
  $s .= sunburst_lines(800, 700, 120, 900, 48, 180, 360, $g, 0.13, 1.2);
  $s .= qq(<circle cx="800" cy="390" r="352" fill="none" stroke="$g" stroke-width="1.4" opacity="0.45"/>);
  $s .= qq(<circle cx="800" cy="390" r="366" fill="none" stroke="$g" stroke-width="0.8" opacity="0.3"/>);
  for my $st ([1270, 120, 9], [1350, 260, 6], [1460, 170, 11], [1500, 380, 5], [1210, 520, 5], [1400, 560, 7], [1300, 420, 4]) {
    $s .= sparkle(@$st, '#F4E7C3', 0.8);
  }
  for my $st ([300, 140], [190, 260], [130, 420], [260, 520], [380, 600]) {
    $s .= sprintf('<circle cx="%s" cy="%s" r="2.2" fill="#F1DA97" opacity="0.55"/>', @$st);
  }
  $s .= qq(</g>);
  # --- Karten
  $s .= qq(<g id="karten">);
  $s .= logo_card("$P-kh", 'hell', 'sonne', 548, 370, -12, 0.62);
  $s .= logo_card("$P-kd", 'dunkel', 'mond', 1052, 370, 12, 0.62);
  $s .= qq(</g>);
  # --- Buehne
  $s .= qq(<g id="buehne"><path d="M520,704 H1080" stroke="$g" stroke-width="2"/><path d="M800,694 l10,10 l-10,10 l-10,-10 Z" fill="$g"/>)
     . qq(<path d="M600,712 H1000" stroke="$g" stroke-width="0.8" opacity="0.7"/></g>);
  # --- Katze
  $s .= qq(<g id="katze" transform="translate(@{[790 - 272*1.0]} @{[706 - 652*1.0]}) scale(1.0)">) . cat_group("$P-cat") . qq(</g>);
  # --- Sprechblase
  $s .= qq(<g id="mau">) . bubble($P, 1130, 118, 950, 196) . qq(</g>);
  # --- Schriftzug
  my $tx = qq(x="800" y="842" font-family="$FONT_DISPLAY" font-size="138" text-anchor="middle");
  my $word = qq(Mau-Mau <tspan fill="url(#$P-flip)">Flip</tspan>);
  $s .= qq(<g id="schriftzug">);
  $s .= qq(<text $tx fill="#B9A2FF" stroke="#B9A2FF" stroke-width="10" opacity="0.35" filter="url(#$P-lglow)">Mau-Mau Flip</text>);
  $s .= qq(<text $tx fill="$g" stroke="$g" stroke-width="18" stroke-linejoin="round">Mau-Mau Flip</text>);
  $s .= qq(<text $tx fill="#0B0F28" stroke="#0B0F28" stroke-width="11" stroke-linejoin="round">Mau-Mau Flip</text>);
  $s .= qq(<text $tx fill="url(#$P-word)">$word</text>);
  $s .= qq(</g>);
  $s;
}

sub logo_svg {
  my ($P, $file) = @_;
  my $head = $file
    ? '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1600 900" width="1600" height="900">'
    : '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1600 900" width="100%" height="100%">';
  return $head . '<title>Mau-Mau Flip – Logo (Entwurf B, Art déco)</title><defs>' . logo_defs($P) . cat_defs("$P-cat") . '</defs>' . logo_inner($P) . '</svg>';
}

# ------------------------------------------------------------------ App-Symbol
sub icon_svg {
  my ($P, $file, $size) = @_;
  $size //= 512;
  my $g = "url(#$P-igold)";
  my $head = $file
    ? '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">'
    : qq(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="$size" height="$size">);
  my $s = $head . '<title>Mau-Mau Flip – App-Symbol (Entwurf B)</title><defs>';
  $s .= qq(<linearGradient id="$P-igold" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="512" y2="512"><stop offset="0" stop-color="#A47A2C"/><stop offset="0.3" stop-color="#F1DA97"/><stop offset="0.55" stop-color="#BC9240"/><stop offset="0.8" stop-color="#F3DD9C"/><stop offset="1" stop-color="#A07733"/></linearGradient>);
  $s .= qq(<radialGradient id="$P-ibg" cx="0.5" cy="0.42" r="0.75"><stop offset="0" stop-color="#262D68"/><stop offset="1" stop-color="#090C24"/></radialGradient>);
  $s .= qq(<linearGradient id="$P-iday" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FFF4D8"/><stop offset="1" stop-color="#F3C98A"/></linearGradient>);
  $s .= qq(<linearGradient id="$P-inight" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2A2470"/><stop offset="1" stop-color="#5A44C8"/></linearGradient>);
  $s .= qq(<clipPath id="$P-idisc"><circle cx="256" cy="226" r="168"/></clipPath><clipPath id="$P-iframe"><rect x="16" y="16" width="480" height="480" rx="98"/></clipPath>);
  $s .= cat_defs("$P-cat");
  $s .= '</defs>';
  $s .= qq(<rect width="512" height="512" rx="112" fill="url(#$P-ibg)"/>);
  # Scheibe Tag | Nacht
  $s .= qq(<g clip-path="url(#$P-idisc)">);
  $s .= qq(<rect x="80" y="50" width="176" height="360" fill="url(#$P-iday)"/>);
  $s .= qq(<rect x="256" y="50" width="176" height="360" fill="url(#$P-inight)"/>);
  $s .= sunburst_lines(256, 226, 30, 200, 12, 90, 270, '#D9A24A', 0.7, 3);
  $s .= qq(<path d="@{[crescent(388, 300, 30, 14, -9, 26)]}" fill="#E8E0FF"/>);
  $s .= sparkle(398, 208, 9, q{#F4E7C3}, 1) . sparkle(352, 90, 7, q{#F4E7C3}, 0.9) . sparkle(404, 140, 5, q{#F4E7C3}, 0.9) . sparkle(350, 360, 5, q{#F4E7C3}, 0.8);
  $s .= qq(</g>);
  $s .= qq(<circle cx="256" cy="226" r="168" fill="none" stroke="$g" stroke-width="6"/>);
  $s .= qq(<circle cx="256" cy="226" r="180" fill="none" stroke="$g" stroke-width="1.5" opacity="0.8"/>);
  # Katze
  $s .= qq(<g clip-path="url(#$P-iframe)"><g transform="translate(@{[238 - 305*0.9]} @{[206 - 178*0.9]}) scale(0.9)">) . cat_group("$P-cat", notail => 1) . qq(</g>);
  $s .= qq(<rect x="0" y="432" width="512" height="80" fill="#0C1030"/><path d="M16,432 H496" stroke="$g" stroke-width="4"/><path d="M16,444 H496" stroke="$g" stroke-width="1.2" opacity="0.8"/>);
  $s .= qq(<path d="M256,420 l12,12 l-12,12 l-12,-12 Z" fill="$g"/>);
  for my $i (-3 .. 3) { next unless $i; $s .= sprintf(q{<circle cx="%s" cy="470" r="4" fill="%s" opacity="0.8"/>}, 256 + $i * 40, $g) }
  $s .= qq(</g>);
  # Rahmen
  $s .= qq(<rect x="16" y="16" width="480" height="480" rx="98" fill="none" stroke="$g" stroke-width="5"/>);
  $s .= qq(<rect x="28" y="28" width="456" height="456" rx="88" fill="none" stroke="$g" stroke-width="1.4" opacity="0.8"/>);
  $s .= '</svg>';
  $s;
}

1;
