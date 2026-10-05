#!/usr/bin/perl
# Mau-Mau Flip – Gestaltungsrichtung C "Geometrisch & kräftig"
# Erzeugt Karten (cards/*.svg), logo.svg, icon.svg sowie preview.html, logo.html, hand.html, icon.html.
# Aufruf aus beliebigem Ordner:  perl "<pfad>/werkzeug/build.pl"
use strict; use warnings; use utf8;
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use open qw(:std :encoding(UTF-8));

my $PI   = 4*atan2(1,1);
my $ROOT = abs_path(dirname(abs_path(__FILE__)) . '/..');

# ---------------------------------------------------------------- Hilfen
sub n   { my $v = sprintf('%.2f', $_[0]); $v =~ s/(\.\d*?)0+$/$1/; $v =~ s/\.$//; $v = '0' if $v eq '-0'; return $v; }
sub rad { $_[0]*$PI/180 }
sub pol { my ($cx,$cy,$r,$deg)=@_; return ($cx+$r*cos(rad($deg)), $cy+$r*sin(rad($deg))); }
sub pt  { join ' ', map { n($_) } @_ }
sub rrect { my ($x,$y,$w,$h,$r)=@_;
  return 'M'.pt($x+$r,$y).' H'.n($x+$w-$r)." A$r $r 0 0 1 ".pt($x+$w,$y+$r).' V'.n($y+$h-$r)." A$r $r 0 0 1 ".pt($x+$w-$r,$y+$h)
        .' H'.n($x+$r)." A$r $r 0 0 1 ".pt($x,$y+$h-$r).' V'.n($y+$r)." A$r $r 0 0 1 ".pt($x+$r,$y).' Z'; }
sub schreibe { my ($pfad,$inhalt)=@_; open(my $fh,'>:encoding(UTF-8)',"$ROOT/$pfad") or die "$pfad: $!"; print $fh $inhalt; close $fh; }

# ---------------------------------------------------------------- Grundwerte
my ($W,$H,$R,$IN,$RI,$CX,$CY) = (560,870,40,16,26,280,435);
my $CREME  = '#F8F2E6';   # Papier
my $TINTE  = '#17171F';   # Druckschwarz
my $MOND   = '#F1EDFF';   # Mondlicht (dunkle Seite)
my $NACHT1 = '#15183C'; my $NACHT2 = '#07081A'; my $NACHT = '#0C0E22';
my $FONT   = 'Jost, Futura, &quot;Century Gothic&quot;, sans-serif';
my $FONT_URL = 'https://fonts.googleapis.com/css2?family=Jost:wght@400;500;600;700;800;900&amp;display=block';
my $FONT_URL_HTML = 'https://fonts.googleapis.com/css2?family=Jost:wght@400;500;600;700;800;900&display=block';

my %FARBE = (
  rot     => { seite=>'hell',   name=>'Rot',    basis=>'#B3202A', scheibe=>'#9A1B24', tief=>'#80151D', text=>$CREME, symbol=>'flamme',   symname=>'Flamme' },
  gelb    => { seite=>'hell',   name=>'Gelb',   basis=>'#FFDD33', scheibe=>'#F7C91F', tief=>'#EDB40F', text=>$TINTE, symbol=>'sonne',    symname=>'Sonne' },
  gruen   => { seite=>'hell',   name=>'Grün',   basis=>'#43B05C', scheibe=>'#3A9D51', tief=>'#308845', text=>$TINTE, symbol=>'klee',     symname=>'Kleeblatt' },
  blau    => { seite=>'hell',   name=>'Blau',   basis=>'#2A5BD7', scheibe=>'#244FBF', tief=>'#1D42A4', text=>$CREME, symbol=>'kristall', symname=>'Kristall' },
  pink    => { seite=>'dunkel', name=>'Pink',   basis=>'#FF99CC', licht=>'#FFC8E3', symbol=>'herz',    symname=>'Herz' },
  tuerkis => { seite=>'dunkel', name=>'Türkis', basis=>'#00838F', licht=>'#4FDDE6', symbol=>'welle',   symname=>'Welle' },
  orange  => { seite=>'dunkel', name=>'Orange', basis=>'#FF6F00', licht=>'#FFA75A', symbol=>'laterne', symname=>'Laterne' },
  lila    => { seite=>'dunkel', name=>'Lila',   basis=>'#4527A0', licht=>'#A891FF', symbol=>'stern',   symname=>'Stern' },
);
my @HELL   = qw(rot gelb gruen blau);
my @DUNKEL = qw(pink tuerkis orange lila);

# ---------------------------------------------------------------- Farbsymbole (100er-Raster um 0,0)
sub symbol_form {
  my ($name,$c)=@_;
  if ($name eq 'flamme') {
    return qq{<path fill="$c" fill-rule="evenodd" d="M4 -50 C14 -28 38 -12 38 14 A38 38 0 0 1 -38 14 C-38 -4 -26 -16 -18 -28 C-16 -16 -10 -10 -4 -10 C-6 -26 -2 -40 4 -50 Z M0 10 C6 18 15 24 15 32 A15 15 0 0 1 -15 32 C-15 24 -6 18 0 10 Z"/>};
  }
  if ($name eq 'sonne') {
    my $s = qq{<circle r="24" fill="$c"/>};
    for my $i (0..7) { my $a=$i*45-90; $s .= qq{<path fill="$c" d="M}.pt(pol(0,0,31,$a-12)).' L'.pt(pol(0,0,50,$a)).' L'.pt(pol(0,0,31,$a+12)).qq{ Z"/>}; }
    return $s;
  }
  if ($name eq 'klee') {
    return qq{<g fill="$c"><circle cx="0" cy="-22" r="19"/><circle cx="-19" cy="8" r="19"/><circle cx="19" cy="8" r="19"/><circle cx="0" cy="-2" r="12"/><path d="M-4 10 L4 10 Q7 31 17 45 L10 50 Q-2 34 -4 10 Z"/></g>};
  }
  if ($name eq 'kristall') {
    return qq{<g fill="$c"><path d="M-24 -42 L24 -42 L44 -16 L-44 -16 Z"/><path d="M-46 -8 L46 -8 L0 46 Z"/></g>};
  }
  if ($name eq 'herz') {
    return qq{<path fill="$c" d="M0 41 L-35.4 5.6 A25 25 0 0 1 0 -29.7 A25 25 0 0 1 35.4 5.6 Z"/>};
  }
  if ($name eq 'welle') {
    return qq{<g fill="none" stroke="$c" stroke-width="12" stroke-linecap="round"><path d="M-42 -11 Q-31.5 -27 -21 -11 T0 -11 T21 -11 T42 -11"/><path d="M-42 17 Q-31.5 1 -21 17 T0 17 T21 17 T42 17"/></g>};
  }
  if ($name eq 'laterne') {
    my (@o,@i); for my $k (0..5) { my $a=-90+$k*60; push @o, pt(pol(0,10,37,$a)); push @i, pt(pol(0,10,15,$a)); }
    return qq{<path fill="$c" fill-rule="evenodd" d="M}.join(' L',@o).' Z M'.join(' L',reverse @i).qq{ Z"/><path d="M-11 -22 A11 11 0 0 1 11 -22" fill="none" stroke="$c" stroke-width="7" stroke-linecap="round"/>};
  }
  if ($name eq 'stern') {
    my @p; for my $k (0..9) { push @p, pt(pol(0,5,($k%2?21:50),-90+$k*36)); }
    return qq{<path fill="$c" d="M}.join(' L',@p).qq{ Z"/>};
  }
  die "unbekanntes Symbol $name";
}
sub symbol { my ($name,$cx,$cy,$size,$c,$extra)=@_; $extra//='';
  return qq{<g transform="translate(}.pt($cx,$cy).') scale('.n($size/100).qq{)"$extra>}.symbol_form($name,$c).'</g>'; }

# ---------------------------------------------------------------- Bausteine
sub txt { my ($x,$y,$size,$fill,$content,%o)=@_;
  my $w=$o{weight}//800; my $a=$o{anchor}//'middle'; my $e=$o{extra}//'';
  return qq{<text x="}.n($x).qq{" y="}.n($y).qq{" font-family="$FONT" font-weight="$w" font-size="}.n($size).qq{" text-anchor="$a" fill="$fill"$e>$content</text>}; }

sub plus { my ($cx,$cy,$arm,$th,$fill,$extra)=@_; $extra//=''; my $h=$arm/2; my $t=$th/2;
  return qq{<path d="M}.pt($cx-$t,$cy-$h).' H'.n($cx+$t).' V'.n($cy-$t).' H'.n($cx+$h).' V'.n($cy+$t).' H'.n($cx+$t).' V'.n($cy+$h)
        .' H'.n($cx-$t).' V'.n($cy+$t).' H'.n($cx-$h).' V'.n($cy-$t).' H'.n($cx-$t).qq{ Z" fill="$fill"$extra/>}; }

sub kreis_schnitt { my ($x1,$y1,$r1,$x2,$y2,$r2)=@_;
  my ($dx,$dy)=($x2-$x1,$y2-$y1); my $d=sqrt($dx*$dx+$dy*$dy);
  my $a=($r1*$r1-$r2*$r2+$d*$d)/(2*$d); my $h=sqrt($r1*$r1-$a*$a);
  my ($mx,$my)=($x1+$a*$dx/$d,$y1+$a*$dy/$d);
  return ($mx+$h*$dy/$d,$my-$h*$dx/$d,$mx-$h*$dy/$d,$my+$h*$dx/$d); }
sub winkel { my ($cx,$cy,$x,$y)=@_; my $a=atan2($y-$cy,$x-$cx)*180/$PI; $a+=360 while $a<0; return $a; }
sub bogen_info { my ($a0,$a1,$am)=@_;
  my $cw=$a1-$a0; $cw+=360 while $cw<0; $cw-=360 while $cw>=360;
  my $m=$am-$a0;  $m+=360 while $m<0;  $m-=360 while $m>=360;
  return $m<=$cw ? (1,($cw>180?1:0)) : (0,((360-$cw)>180?1:0)); }
sub sichel { my ($x1,$y1,$r1,$x2,$y2,$r2)=@_;
  my ($px,$py,$qx,$qy)=kreis_schnitt(@_);
  my $fern=winkel($x2,$y2,$x1,$y1);
  my ($s1,$l1)=bogen_info(winkel($x1,$y1,$px,$py),winkel($x1,$y1,$qx,$qy),$fern);
  my ($s2,$l2)=bogen_info(winkel($x2,$y2,$qx,$qy),winkel($x2,$y2,$px,$py),$fern);
  return 'M'.pt($px,$py).' A'.n($r1).' '.n($r1)." 0 $l1 $s1 ".pt($qx,$qy).' A'.n($r2).' '.n($r2)." 0 $l2 $s2 ".pt($px,$py).' Z'; }

sub bogenpfeil { my ($cx,$cy,$r,$a0,$a1,$w,$hl,$hb,$c,$rund)=@_;
  my $ak = $a1 - ($hl/$r)*180/$PI;
  my $large = ($ak-$a0)>180 ? 1 : 0;
  my $s = qq{<path d="M}.pt(pol($cx,$cy,$r,$a0)).' A'.n($r).' '.n($r)." 0 $large 1 ".pt(pol($cx,$cy,$r,$ak+0.6)).qq{" fill="none" stroke="$c" stroke-width="}.n($w).qq{" stroke-linecap="}.($rund?'round':'butt').qq{"/>};
  my ($bx,$by)=pol($cx,$cy,$r,$ak); my ($tx,$ty)=($bx-$hl*sin(rad($ak)), $by+$hl*cos(rad($ak)));
  $s .= qq{<path d="M}.pt(pol($cx,$cy,$r-$hb/2,$ak)).' L'.pt(pol($cx,$cy,$r+$hb/2,$ak)).' L'.pt($tx,$ty).qq{ Z" fill="$c" stroke="$c" stroke-width="3" stroke-linejoin="round"/>};
  return $s; }

sub richtung_glyph { my ($cx,$cy,$size,$c)=@_; my $r=$size*0.31; my $w=$size*0.135; my $hl=$size*0.2; my $hb=$size*0.3;
  return bogenpfeil($cx,$cy,$r,200,336,$w,$hl,$hb,$c,1).bogenpfeil($cx,$cy,$r,20,156,$w,$hl,$hb,$c,1); }

sub flip_glyph { my ($cx,$cy,$size,$c)=@_; my $r=$size/2; my $sw=$size*0.09;
  return qq{<circle cx="}.n($cx).qq{" cy="}.n($cy).qq{" r="}.n($r-$sw/2).qq{" fill="none" stroke="$c" stroke-width="}.n($sw).qq{"/>}
        .qq{<path d="M}.pt($cx,$cy-$r).' A'.n($r).' '.n($r).' 0 0 0 '.pt($cx,$cy+$r).qq{ Z" fill="$c"/>}; }

sub pfote_form { my ($pad,$zehen,$stroke,$sw)=@_;
  my $st = $stroke ? qq{ stroke="$stroke" stroke-width="}.n($sw).qq{" stroke-linejoin="round"} : '';
  my $s = qq{<path d="M-62 56 C-62 22 -30 4 0 4 C30 4 62 22 62 56 C62 82 40 90 20 84 C10 81 -10 81 -20 84 C-40 90 -62 82 -62 56 Z" fill="$pad"$st/>};
  my @z = ([-72,-26,-22],[-27,-62,-7],[27,-62,7],[72,-26,22]);
  for my $i (0..3) { my ($x,$y,$r)=@{$z[$i]}; $s .= qq{<ellipse cx="$x" cy="$y" rx="22" ry="29" transform="rotate($r $x $y)" fill="$zehen->[$i]"$st/>}; }
  return $s; }
sub pfote { my ($cx,$cy,$size,$pad,$zehen,$stroke,$sw,$rot)=@_; my $sc=$size/190;
  return qq{<g transform="translate(}.pt($cx,$cy).')'.($rot?" rotate($rot)":'').' scale('.n($sc).qq{)">}.pfote_form($pad,$zehen,$stroke,$sw?$sw/$sc:0).'</g>'; }

sub mini_raster { my ($cx,$cy,$size,$farben,$rand)=@_; my $g=$size*0.1; my $q=($size-$g)/2; my ($x0,$y0)=($cx-$size/2,$cy-$size/2); my $s='';
  $s .= qq{<rect x="}.n($x0-$g).qq{" y="}.n($y0-$g).qq{" width="}.n($size+2*$g).qq{" height="}.n($size+2*$g).qq{" rx="}.n($g*2).qq{" fill="$rand"/>} if $rand;
  my @pos=([0,0],[1,0],[0,1],[1,1]);
  for my $i (0..3) { my ($a,$b)=@{$pos[$i]}; $s .= qq{<rect x="}.n($x0+$a*($q+$g)).qq{" y="}.n($y0+$b*($q+$g)).qq{" width="}.n($q).qq{" height="}.n($q).qq{" rx="}.n($q*0.2).qq{" fill="$farben->[$i]"/>}; }
  return $s; }

sub stern4 { my ($x,$y,$s,$c)=@_; my $k=$s*0.2;
  return qq{<path fill="$c" d="M}.pt($x,$y-$s).' L'.pt($x+$k,$y-$k).' L'.pt($x+$s,$y).' L'.pt($x+$k,$y+$k).' L'.pt($x,$y+$s).' L'.pt($x-$k,$y+$k).' L'.pt($x-$s,$y).' L'.pt($x-$k,$y-$k).qq{ Z"/>}; }

# Schlafender Katzenkopf (Aussetzen) – Kreis, zwei Dreiecksohren, geschlossene Augenbögen
sub katzenkopf { my ($cx,$cy,$r,$fill,$detail,%o)=@_; my $ko=$o{ko}||0;
  my $s = qq{<g>};
  for my $seite (-1,1) {
    my @b1 = pol($cx,$cy,$r*0.97, $seite<0 ? -166 : -14);
    my @b2 = pol($cx,$cy,$r*0.97, $seite<0 ? -104 : -76);
    my @t  = pol($cx,$cy,$r*1.55, $seite<0 ? -128 : -52);
    $s .= qq{<path d="M}.pt(@b1).' L'.pt(@t).' L'.pt(@b2).qq{ Z" fill="$fill" stroke="$fill" stroke-width="}.n($r*0.12+$ko).qq{" stroke-linejoin="round"/>};
  }
  $s .= qq{<circle cx="}.n($cx).qq{" cy="}.n($cy).qq{" r="}.n($r+$ko/2).qq{" fill="$fill"/>};
  return $s."</g>" if $ko;
  my $lw = n($r*0.105);
  for my $seite (-1,1) { my $ex=$cx+$seite*$r*0.4; my $ey=$cy+$r*0.02;
    $s .= qq{<path d="M}.pt($ex-$r*0.2,$ey).' Q'.pt($ex,$ey+$r*0.22).' '.pt($ex+$r*0.2,$ey).qq{" fill="none" stroke="$detail" stroke-width="$lw" stroke-linecap="round"/>}; }
  unless ($o{klein}) {
    $s .= qq{<path d="M}.pt($cx-$r*0.11,$cy+$r*0.3).' L'.pt($cx+$r*0.11,$cy+$r*0.3).' L'.pt($cx,$cy+$r*0.42).qq{ Z" fill="$detail" stroke="$detail" stroke-width="}.n($r*0.05).qq{" stroke-linejoin="round"/>};
    $s .= qq{<path d="M}.pt($cx-$r*0.17,$cy+$r*0.5).' Q'.pt($cx-$r*0.085,$cy+$r*0.6).' '.pt($cx,$cy+$r*0.5).' Q'.pt($cx+$r*0.085,$cy+$r*0.6).' '.pt($cx+$r*0.17,$cy+$r*0.5).qq{" fill="none" stroke="$detail" stroke-width="}.n($r*0.05).qq{" stroke-linecap="round" stroke-linejoin="round"/>};
  }
  return $s.'</g>'; }

# Flip-Scheibe: links Tag (Papier, Sonne), rechts Nacht (Mondsichel)
sub flipscheibe { my ($cx,$cy,$r)=@_;
  my $s = qq{<path d="M}.pt($cx,$cy-$r).' A'.n($r).' '.n($r).' 0 0 0 '.pt($cx,$cy+$r).qq{ Z" fill="$CREME"/>};
  $s   .= qq{<path d="M}.pt($cx,$cy-$r).' A'.n($r).' '.n($r).' 0 0 1 '.pt($cx,$cy+$r).qq{ Z" fill="$NACHT"/>};
  my ($sx,$sy)=($cx-$r*0.47,$cy); my $sr=$r*0.19;
  $s .= qq{<circle cx="}.n($sx).qq{" cy="}.n($sy).qq{" r="}.n($sr).qq{" fill="$TINTE"/>};
  for my $i (0..7) { my $a=$i*45; $s .= qq{<path fill="$TINTE" d="M}.pt(pol($sx,$sy,$sr*1.3,$a-11)).' L'.pt(pol($sx,$sy,$sr*1.95,$a)).' L'.pt(pol($sx,$sy,$sr*1.3,$a+11)).qq{ Z"/>}; }
  my ($mx,$my)=($cx+$r*0.45,$cy); my $mr=$r*0.3;
  $s .= qq{<path fill="$CREME" d="}.sichel($mx,$my,$mr,$mx+$mr*0.45,$my-$mr*0.3,$mr*0.82).qq{"/>};
  $s .= stern4($cx+$r*0.72,$cy-$r*0.42,$r*0.08,$CREME).stern4($cx+$r*0.2,$cy+$r*0.5,$r*0.05,$CREME);
  return $s; }

# ---------------------------------------------------------------- Karte
my $DX = 300; my $DY = 432;          # Bildmitte der dunklen Seite (im Hohlraum der Sichel)
my @SICHEL = (280,435,215, 324,408,190);

sub sterne { my ($c1,$c2)=@_; my $s='';
  my @st = ([478,226,19],[425,150,8],[520,318,6]);
  my @pk = ([452,288,3.4],[505,170,2.8],[392,98,2.6]);
  for my $m (0,1) {
    for my $p (@st) { my ($x,$y,$g)=@$p; ($x,$y)=(560-$x,870-$y) if $m; $s .= stern4($x,$y,$g,$c1); }
    for my $p (@pk) { my ($x,$y,$g)=@$p; ($x,$y)=(560-$x,870-$y) if $m; $s .= qq{<circle cx="}.n($x).qq{" cy="}.n($y).qq{" r="$g" fill="$c2"/>}; }
  }
  return $s; }

sub index_inhalt { my (%o)=@_; my ($art,$wert,$tc,$sym,$wild,$seite)=@o{qw(art wert tc sym wild seite)};
  my $ix=92; my $base=180; my $fs=180; my $s='';
  if    ($art eq 'zahl')            { $s .= txt($ix,$base,$fs,$tc,$wert);
                                       $s .= qq{<rect x="}.n($ix-30).qq{" y="}.n($base+9).qq{" width="60" height="11" rx="5.5" fill="$tc"/>} if $wert==6 || $wert==9; }
  elsif ($art eq 'plus' || $art eq 'wuenscher_plus2') { my $f2=168; $s .= plus(40,$base-0.355*$f2,34,11,$tc).txt(113,$base,$f2,$tc,$wert); }
  elsif ($art eq 'aussetzen')       { $s .= txt($ix,$base-16,118,$tc,'Zz'); }
  elsif ($art eq 'alle_aussetzen')  { my $per=2*$PI*62/16;
                                       $s .= qq{<circle cx="$ix" cy="118" r="62" fill="none" stroke="$tc" stroke-width="11" stroke-linecap="round" stroke-dasharray="0.01 }.n($per-0.01).qq{"/>}.txt($ix,147,82,$tc,'Zz'); }
  elsif ($art eq 'richtung')        { $s .= richtung_glyph($ix,118,132,$tc); }
  elsif ($art eq 'flip')            { $s .= flip_glyph($ix,118,112,$tc); }
  elsif ($art eq 'wuenscher')       { $s .= pfote($ix,120,124,$tc,[($tc)x4]); }
  elsif ($art eq 'farbjagd')        { $s .= txt($ix,$base,$fs,$tc,'?'); }
  my $sy = $art eq 'motiv' ? 118 : 254;
  if ($sym)     { $s .= symbol($sym,$ix,$sy,($art eq 'motiv'?100:84),$tc); }
  elsif ($wild) { $s .= mini_raster($ix,$sy,62,$wild,($seite eq 'hell'?$CREME:undef)); }
  return $s; }

sub karte {
  my %o = @_;
  my ($seite,$fk,$art,$wert) = @o{qw(seite farbe art wert)}; $wert //= '';
  my $F = $fk eq 'wild' ? undef : $FARBE{$fk};
  my $innen  = rrect($IN,$IN,$W-2*$IN,$H-2*$IN,$RI);
  my $aussen = rrect(0,0,$W,$H,$R);
  my ($defs,$grund,$motiv,$sym,$wg,$idx,$rahmen) = ('') x 7;
  my @hellwild   = map { $FARBE{$_}{basis} } @HELL;
  my @dunkelwild = map { $FARBE{$_}{basis} } @DUNKEL;

  if ($seite eq 'hell') {
    my $tc = $F ? $F->{text} : $CREME;
    $defs .= qq{<clipPath id="innen"><path d="$innen"/></clipPath><clipPath id="scheibe"><circle cx="$CX" cy="$CY" r="205"/></clipPath>};
    # Grund
    if ($F) { $grund = qq{<path d="$innen" fill="$F->{basis}"/>}; }
    else {
      $grund = qq{<g clip-path="url(#innen)"><rect x="0" y="0" width="$CX" height="$CY" fill="$hellwild[0]"/><rect x="$CX" y="0" width="$CX" height="$CY" fill="$hellwild[1]"/>}
             . qq{<rect x="0" y="$CY" width="$CX" height="$CY" fill="$hellwild[2]"/><rect x="$CX" y="$CY" width="$CX" height="$CY" fill="$hellwild[3]"/></g>};
    }
    # Motiv: Sonnenscheibe mit Horizont
    if ($F) {
      $motiv = qq{<g clip-path="url(#innen)"><circle cx="$CX" cy="$CY" r="205" fill="$F->{scheibe}"/>}
             . qq{<path d="M75 $CY A205 205 0 0 0 485 $CY Z" fill="$F->{tief}"/>}
             . qq{<g clip-path="url(#scheibe)" fill="$F->{basis}"><rect x="60" y="474" width="440" height="9"/><rect x="60" y="522" width="440" height="15"/><rect x="60" y="576" width="440" height="22"/></g></g>};
    } else {
      $motiv = qq{<circle cx="$CX" cy="$CY" r="198" fill="$CREME"/><circle cx="$CX" cy="$CY" r="198" fill="none" stroke="$TINTE" stroke-width="8"/>};
    }
    # Symbol-Ebene: Farbsymbol oben rechts / unten links, Ton in Ton
    if ($F && $art ne 'motiv') {
      $sym = symbol($F->{symbol},474,94,62,$F->{scheibe}).qq{<g transform="rotate(180 $CX $CY)">}.symbol($F->{symbol},474,94,62,$F->{scheibe}).'</g>';
    }
    # Wert
    if    ($art eq 'zahl') { my $f=410; my $b=$CY+0.35*$f; $wg = txt($CX,$b,$f,$tc,$wert);
                             $wg .= qq{<rect x="}.n($CX-72).qq{" y="}.n($b+22).qq{" width="144" height="24" rx="12" fill="$tc"/>} if $wert==6 || $wert==9; }
    elsif ($art eq 'plus') { $wg = plus_wert($CX,$CY,$wert,$tc,undef); }
    elsif ($art eq 'aussetzen') { $wg = katzenkopf($CX,$CY+40,112,$tc,$F->{scheibe}).txt(398,318,124,$tc,'Z').txt(452,244,88,$tc,'z'); }
    elsif ($art eq 'richtung')  { $wg = bogenpfeil($CX,$CY,138,200,336,46,62,92,$tc,1).bogenpfeil($CX,$CY,138,20,156,46,62,92,$tc,1); }
    elsif ($art eq 'flip')      { $wg = flipscheibe($CX,$CY,138).bogenpfeil($CX,$CY,178,218,322,20,34,50,$tc,1).bogenpfeil($CX,$CY,178,38,142,20,34,50,$tc,1); }
    elsif ($art eq 'wuenscher') { $wg = pfote($CX,$CY+8,300,$TINTE,[@hellwild],$TINTE,7); }
    elsif ($art eq 'wuenscher_plus2') { $wg = pfote($CX,$CY-72,190,$TINTE,[@hellwild],$TINTE,6).plus_wert($CX,$CY+104,2,$TINTE,undef,150); }
    # Index
    {
      my $i = index_inhalt(art=>$art,wert=>$wert,tc=>$tc,sym=>($F?$F->{symbol}:undef),wild=>($F?undef:[@hellwild]),seite=>'hell');
      $idx = qq{<g>$i</g><g transform="rotate(180 $CX $CY)">}.($F ? $i : index_inhalt(art=>$art,wert=>$wert,tc=>$CREME,wild=>[@hellwild],seite=>'hell')).'</g>';
    }
    # Rahmen: Papierrand
    $rahmen = qq{<path d="$aussen $innen" fill="$CREME" fill-rule="evenodd"/>}
            . qq{<path d="}.rrect(1,1,$W-2,$H-2,$R-1).qq{" fill="none" stroke="$TINTE" stroke-opacity="0.22" stroke-width="2"/>};
  }
  else {
    my $tc = $F ? $F->{licht} : $MOND;
    my $basis = $F ? $F->{basis} : '#B9A8FF';
    $defs .= qq{<linearGradient id="nacht" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="$NACHT1"/><stop offset="1" stop-color="$NACHT2"/></linearGradient>}
           . qq{<radialGradient id="halo" cx="0.5" cy="0.5" r="0.5"><stop offset="0" stop-color="$basis" stop-opacity="0.34"/><stop offset="1" stop-color="$basis" stop-opacity="0"/></radialGradient>}
           . qq{<filter id="weich" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="7"/></filter>}
           . qq{<filter id="weich2" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="16"/></filter>}
           . qq{<clipPath id="karte"><path d="$aussen"/></clipPath>};
    unless ($F) {
      my @l = map { $FARBE{$_}{licht} } @DUNKEL;
      $defs .= qq{<linearGradient id="regenbogen" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="$l[0]"/><stop offset="0.36" stop-color="$l[1]"/><stop offset="0.64" stop-color="$l[2]"/><stop offset="1" stop-color="$l[3]"/></linearGradient>}
             . qq{<linearGradient id="regenbogen2" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="$dunkelwild[0]"/><stop offset="0.36" stop-color="$dunkelwild[1]"/><stop offset="0.64" stop-color="$dunkelwild[2]"/><stop offset="1" stop-color="$dunkelwild[3]"/></linearGradient>}
             . qq{<clipPath id="sichel"><path d="}.sichel(@SICHEL).qq{"/></clipPath>};
    }
    $grund = qq{<path d="$aussen" fill="url(#nacht)"/><circle cx="$DX" cy="$DY" r="330" fill="url(#halo)"/>};
    my $sp = sichel(@SICHEL);
    if ($F) {
      $motiv = qq{<g clip-path="url(#karte)"><path d="$sp" fill="$F->{basis}" filter="url(#weich2)" opacity="0.75"/>}
             . qq{<path d="$sp" fill="$F->{basis}" stroke="$F->{licht}" stroke-width="4" stroke-linejoin="round"/>}
             . sterne($MOND,$F->{licht}).'</g>';
    } else {
      my ($y0,$y1)=(218,652); my $hb=($y1-$y0)/4; my $bands='';
      for my $i (0..3) { $bands .= qq{<rect x="40" y="}.n($y0+$i*$hb).qq{" width="480" height="}.n($hb+1).qq{" fill="$dunkelwild[$i]"/>}; }
      $motiv = qq{<g clip-path="url(#karte)"><path d="$sp" fill="url(#regenbogen2)" filter="url(#weich2)" opacity="0.7"/>}
             . qq{<g clip-path="url(#sichel)">$bands</g><path d="$sp" fill="none" stroke="$MOND" stroke-width="4" stroke-linejoin="round"/>}
             . sterne($MOND,$MOND).'</g>';
    }
    if ($F && $art ne 'motiv') {
      $sym = qq{<g opacity="0.55">}.symbol($F->{symbol},474,94,60,$F->{licht}).qq{<g transform="rotate(180 $CX $CY)">}.symbol($F->{symbol},474,94,60,$F->{licht}).'</g></g>';
    }
    my $glow = sub { my ($inhalt)=@_; return qq{<g filter="url(#weich)" opacity="0.95">$inhalt</g>}; };
    if ($art eq 'zahl') {
      my $f=400; my $b=$DY+0.35*$f;
      $wg = neon_txt($DX,$b,$f,$wert,$F->{licht},$F->{basis});
      if ($wert==6 || $wert==9) { my $u = qq{<rect x="}.n($DX-70).qq{" y="}.n($b+26).qq{" width="140" height="22" rx="11"};
        $wg .= $glow->($u.qq{ fill="$F->{basis}"/>}).$u.qq{ fill="$NACHT" stroke="$F->{licht}" stroke-width="9"/>}; }
    }
    elsif ($art eq 'plus') { $wg = plus_wert($DX,$DY,$wert,$F->{licht},$F->{basis}); }
    elsif ($art eq 'alle_aussetzen') {
      my $kr=''; my $kg='';
      for my $k (0..5) { my ($x,$y)=pol($DX,$DY+6,142,-90+$k*60); $kr .= katzenkopf($x,$y+6,30,$NACHT,$NACHT,klein=>1,ko=>14).katzenkopf($x,$y+6,30,$F->{licht},$NACHT,klein=>1); $kg .= katzenkopf($x,$y+6,30,$F->{basis},$F->{basis},klein=>1); }
      $wg = $glow->($kg).$kr.neon_txt($DX-34,$DY+50,150,'Z',$F->{licht},$F->{basis}).neon_txt($DX+44,$DY+50,108,'z',$F->{licht},$F->{basis});
    }
    elsif ($art eq 'richtung') {
      my $p = sub { my $c=shift; bogenpfeil($DX,$DY,132,200,336,44,60,90,$c,1).bogenpfeil($DX,$DY,132,20,156,44,60,90,$c,1) };
      $wg = $glow->($p->($F->{basis})).$p->($F->{licht});
    }
    elsif ($art eq 'flip') {
      my $a = sub { my $c=shift; bogenpfeil($DX,$DY,172,218,322,18,32,46,$c,1).bogenpfeil($DX,$DY,172,38,142,18,32,46,$c,1) };
      $wg = $glow->(qq{<circle cx="$DX" cy="$DY" r="132" fill="none" stroke="$F->{basis}" stroke-width="16"/>}.$a->($F->{basis}))
          . flipscheibe($DX,$DY,126).qq{<circle cx="$DX" cy="$DY" r="128" fill="none" stroke="$F->{licht}" stroke-width="6"/>}.$a->($F->{licht});
    }
    elsif ($art eq 'wuenscher') {
      my @l = map { $FARBE{$_}{licht} } @DUNKEL;
      $wg = $glow->(pfote($DX,$DY+8,272,"#8E7BFF",[@dunkelwild],undef,0)).pfote($DX,$DY+8,272,$MOND,[@dunkelwild],undef,0);
      # Leuchtkanten der Zehen
      my $sc=272/190; my @z=([-72,-26,-22],[-27,-62,-7],[27,-62,7],[72,-26,22]);
      for my $i (0..3) { my ($x,$y,$r)=@{$z[$i]};
        $wg .= qq{<g transform="translate(}.pt($DX,$DY+8).') scale('.n($sc).qq{)"><ellipse cx="$x" cy="$y" rx="22" ry="29" transform="rotate($r $x $y)" fill="none" stroke="$l[$i]" stroke-width="3.2"/></g>}; }
    }
    elsif ($art eq 'farbjagd') {
      my @k = ([238,470,-15,$FARBE{pink}{licht}],[292,452,-3,$FARBE{tuerkis}{licht}],[348,438,9,$FARBE{orange}{licht}]);
      my $st='';
      for my $i (0..2) { my ($x,$y,$r,$c)=@{$k[$i]};
        $st .= qq{<g transform="translate($x $y) rotate($r)">}.$glow->(qq{<rect x="-66" y="-100" width="132" height="200" rx="18" fill="none" stroke="$c" stroke-width="12"/>})
             . qq{<rect x="-66" y="-100" width="132" height="200" rx="18" fill="$NACHT" stroke="$c" stroke-width="6"/>}
             . ($i==2 ? txt(0,56,160,$MOND,'?',weight=>900) : '').'</g>'; }
      $wg = $st;
    }
    my $i = index_inhalt(art=>$art,wert=>$wert,tc=>$tc,sym=>($F?$F->{symbol}:undef),wild=>($F?undef:[@dunkelwild]),seite=>'dunkel');
    $idx = qq{<g>$i</g><g transform="rotate(180 $CX $CY)">$i</g>};
    my $nr = rrect($IN+3,$IN+3,$W-2*$IN-6,$H-2*$IN-6,$RI-3);
    my ($nl,$ng) = $F ? ($F->{licht},$F->{basis}) : ('url(#regenbogen)','url(#regenbogen2)');
    $rahmen = qq{<g clip-path="url(#karte)"><path d="$nr" fill="none" stroke="$ng" stroke-width="16" filter="url(#weich)" opacity="0.95"/>}
            . qq{<path d="$nr" fill="none" stroke="$nl" stroke-width="4.5"/></g>}
            . qq{<path d="}.rrect(1,1,$W-2,$H-2,$R-1).qq{" fill="none" stroke="#2C3060" stroke-width="2"/>};
  }

  my $titel = $o{titel} // $o{name};
  return qq{<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $W $H" width="$W" height="$H">\n}
       . qq{<title>$titel</title>\n}
       . qq{<style>\@import url('$FONT_URL');</style>\n}
       . qq{<defs>$defs</defs>\n}
       . qq{<g id="grund">$grund</g>\n<g id="motiv">$motiv</g>\n<g id="symbol">$sym</g>\n<g id="wert">$wg</g>\n<g id="index">$idx</g>\n<g id="rahmen">$rahmen</g>\n</svg>\n};
}

sub neon_txt { my ($x,$y,$size,$content,$licht,$basis,%o)=@_; my $sw=$o{sw}//($size*0.024);
  return qq{<g filter="url(#weich)" opacity="0.95">}.txt($x,$y,$size,'none',$content,extra=>qq{ stroke="$basis" stroke-width="}.n($sw*2.8).qq{" stroke-linejoin="round"}).'</g>'
       . txt($x,$y,$size,$NACHT,$content,extra=>qq{ stroke="$licht" stroke-width="}.n($sw).qq{" stroke-linejoin="round"}); }

# "+N" groß: kompaktes Pluszeichen + Ziffer, als Gruppe zentriert
my %ADV = (1=>0.527,2=>0.682,3=>0.643,4=>0.732,5=>0.669,6=>0.697,7=>0.626,8=>0.651,9=>0.697);
sub plus_wert { my ($cx,$cy,$z,$licht,$basis,$f,$skala)=@_; $f//=380; $skala//=1;
  my $arm=110*$f/380; my $th=34*$f/380; my $gap=16*$f/380; my $adv=$ADV{$z}*$f;
  my $tot=$arm+$gap+$adv; my $x0=$cx-$tot/2; my $b=$cy+0.35*$f; my $pc=$b-0.355*$f;
  if (!$basis) { return plus($x0+$arm/2,$pc,$arm,$th,$licht).txt($x0+$arm+$gap+$adv/2,$b,$f,$licht,$z); }
  my $sw=$f*0.024;
  return qq{<g filter="url(#weich)" opacity="0.95">}.plus($x0+$arm/2,$pc,$arm,$th,'none',qq{ stroke="$basis" stroke-width="}.n($sw*2.8).qq{" stroke-linejoin="round"}).'</g>'
       . plus($x0+$arm/2,$pc,$arm,$th,$NACHT,qq{ stroke="$licht" stroke-width="}.n($sw).qq{" stroke-linejoin="round"})
       . neon_txt($x0+$arm+$gap+$adv/2,$b,$f,$z,$licht,$basis); }

# ---------------------------------------------------------------- Kartenliste
my @KARTEN = (
  [hell_rot_7                    => seite=>'hell',   farbe=>'rot',     art=>'zahl', wert=>7],
  [hell_gelb_plus1               => seite=>'hell',   farbe=>'gelb',    art=>'plus', wert=>1],
  [hell_gruen_aussetzen          => seite=>'hell',   farbe=>'gruen',   art=>'aussetzen'],
  [hell_blau_richtungswechsel    => seite=>'hell',   farbe=>'blau',    art=>'richtung'],
  [hell_rot_flip                 => seite=>'hell',   farbe=>'rot',     art=>'flip'],
  [hell_wuenscher                => seite=>'hell',   farbe=>'wild',    art=>'wuenscher'],
  [hell_wuenscher_plus2          => seite=>'hell',   farbe=>'wild',    art=>'wuenscher_plus2', wert=>2],
  [hell_blau_9                   => seite=>'hell',   farbe=>'blau',    art=>'zahl', wert=>9],
  [dunkel_tuerkis_7              => seite=>'dunkel', farbe=>'tuerkis', art=>'zahl', wert=>7],
  [dunkel_pink_plus5             => seite=>'dunkel', farbe=>'pink',    art=>'plus', wert=>5],
  [dunkel_orange_alle_aussetzen  => seite=>'dunkel', farbe=>'orange',  art=>'alle_aussetzen'],
  [dunkel_lila_richtungswechsel  => seite=>'dunkel', farbe=>'lila',    art=>'richtung'],
  [dunkel_pink_flip              => seite=>'dunkel', farbe=>'pink',    art=>'flip'],
  [dunkel_wuenscher              => seite=>'dunkel', farbe=>'wild',    art=>'wuenscher'],
  [dunkel_farbjagd               => seite=>'dunkel', farbe=>'wild',    art=>'farbjagd'],
  [dunkel_lila_6                 => seite=>'dunkel', farbe=>'lila',    art=>'zahl', wert=>6],
  # zusätzliche Karten für die Handansicht
  [hell_gelb_4                   => seite=>'hell',   farbe=>'gelb',    art=>'zahl', wert=>4],
  [hell_gruen_2                  => seite=>'hell',   farbe=>'gruen',   art=>'zahl', wert=>2],
  [hell_blau_2                   => seite=>'hell',   farbe=>'blau',    art=>'zahl', wert=>2],
  [hell_rot_2                    => seite=>'hell',   farbe=>'rot',     art=>'zahl', wert=>2],
  [dunkel_orange_3               => seite=>'dunkel', farbe=>'orange',  art=>'zahl', wert=>3],
  [dunkel_tuerkis_plus5          => seite=>'dunkel', farbe=>'tuerkis', art=>'plus', wert=>5],
  [dunkel_pink_8                 => seite=>'dunkel', farbe=>'pink',    art=>'zahl', wert=>8],
  [dunkel_lila_1                 => seite=>'dunkel', farbe=>'lila',    art=>'zahl', wert=>1],
  # Motivkarten für Logo
  [motiv_hell_gelb               => seite=>'hell',   farbe=>'gelb',    art=>'motiv'],
  [motiv_dunkel_lila             => seite=>'dunkel', farbe=>'lila',    art=>'motiv'],
);
my %SVG;
for my $k (@KARTEN) { my ($name,@o)=@$k; $SVG{$name} = karte(name=>$name,@o); }
for my $name (keys %SVG) { next if $name =~ /^motiv_/; schreibe("cards/$name.svg",$SVG{$name}); }

# ---------------------------------------------------------------- Einbetten (IDs eindeutig machen)
sub einbetten { my ($svg,$p)=@_; my $s=$svg;
  $s =~ s/<style>\@import[^<]*<\/style>\n?//g;
  $s =~ s/<title>[^<]*<\/title>\n?//g;
  $s =~ s/\bid="([^"]+)"/id="$p-$1"/g;
  $s =~ s/url\(#([^)]+)\)/url(#$p-$1)/g;
  $s =~ s/href="#([^"]+)"/href="#$p-$1"/g;
  return $s; }
sub als_symbol { my ($name,$p)=@_; my $s = einbetten($SVG{$name},$p);
  $s =~ s/^<svg[^>]*>/<symbol id="$p" viewBox="0 0 $W $H">/; $s =~ s/<\/svg>\s*$/<\/symbol>/; return $s; }

# ---------------------------------------------------------------- Katze (geometrisch)
my $FELL='#262631'; my $FELL2='#3B3B4B'; my $ROSA='#E58C9C'; my $MAUL='#4A1C2A'; my $ZUNGE='#F07D8F'; my $AUGE='#F5B83A';
my $KOPF_TF = 'rotate(-9 10 -468)';
sub katze_silhouette { my ($fill,$stroke,$extra)=@_;
  my $st = $stroke ? qq{ stroke="$stroke" stroke-linejoin="round"} : '';
  my $sw = sub { my $b=shift; my $w=$b+$extra; return $w>0 ? qq{ stroke-width="}.n($w).'"' : ''; };
  return qq{<g fill="$fill">}
    . qq{<circle cx="-112" cy="-108" r="108"$st}.$sw->(0).'/>'
    . qq{<circle cx="112" cy="-108" r="108"$st}.$sw->(0).'/>'
    . qq{<path d="M-150 0 L-150 -40 L-98 -318 A98 98 0 0 1 98 -318 L150 -40 L150 0 Z"$st}.$sw->(0).'/>'
    . qq{<g transform="$KOPF_TF"><circle cx="10" cy="-468" r="112"$st}.$sw->(0).'/>'
    . qq{<ellipse cx="10" cy="-428" rx="124" ry="80"$st}.$sw->(0).'/>'
    . qq{<path d="M-96 -500 L-40 -562 L-94 -642 Z"}.($stroke?$st:qq{ stroke="$fill" stroke-linejoin="round"}).$sw->(18).'/>'
    . qq{<path d="M60 -574 L120 -508 L134 -636 Z"}.($stroke?$st:qq{ stroke="$fill" stroke-linejoin="round"}).$sw->(18).'/></g>'
    . '</g>'; }
my $SCHWANZ = 'M146 -44 C232 -40 270 -110 256 -196 C246 -252 202 -270 176 -244';
my $ARM     = q{M-96 -318 L-26 -196 L-30 -380};
sub katze { my (%o)=@_; my $bg=$o{knockout}; my $ko=$o{ko}//14; my $s='';
  if ($bg) {
    $s .= qq{<path d="$SCHWANZ" fill="none" stroke="$bg" stroke-width="}.n(46+2*$ko).qq{" stroke-linecap="round"/>};
    $s .= katze_silhouette($bg,$bg,2*$ko);
    $s .= qq{<path d="$ARM" fill="none" stroke="$bg" stroke-width="}.n(52+2*$ko).qq{" stroke-linecap="round" stroke-linejoin="round"/>};
    $s .= qq{<circle cx="-30" cy="-390" r="}.n(31+$ko).qq{" fill="$bg"/>};
  }
  if ($o{rand}) { # farbige Randlichter
    my ($l,$r)=@{$o{rand}};
    $s .= qq{<g transform="translate(-7 0)">}.katze_silhouette($l,undef,0).'</g>';
    $s .= qq{<g transform="translate(7 0)">}.katze_silhouette($r,undef,0).qq{<path d="$SCHWANZ" fill="none" stroke="$r" stroke-width="46" stroke-linecap="round"/></g>};
  }
  $s .= qq{<path d="$SCHWANZ" fill="none" stroke="$FELL" stroke-width="46" stroke-linecap="round"/>};
  $s .= katze_silhouette($FELL,undef,0);
  # Brustlatz und Vorderbein
  $s .= qq{<ellipse cx="4" cy="-222" rx="66" ry="150" fill="$CREME"/>};
  $s .= qq{<rect x="14" y="-250" width="60" height="244" rx="30" fill="$CREME"/>};
  # Pfoten unten
  $s .= qq{<ellipse cx="44" cy="-8" rx="42" ry="22" fill="$CREME"/>};
  $s .= qq{<path d="M-210 0 A48 30 0 0 1 -114 0 Z M114 0 A48 30 0 0 1 210 0 Z" fill="$CREME"/>};
  $s .= qq{<g stroke="$FELL" stroke-width="5" stroke-linecap="round" opacity="0.55"><path d="M30 -14 V-2 M58 -14 V-2 M-178 -14 V-2 M-146 -14 V-2 M146 -14 V-2 M178 -14 V-2"/></g>};
  # Kopf mit Gesicht
  $s .= qq{<g transform="$KOPF_TF">};
  $s .= qq{<path d="M-82 -514 L-52 -552 L-84 -612 Z" fill="$ROSA" opacity="0.75" stroke="$ROSA" stroke-width="8" stroke-linejoin="round"/>};
  $s .= qq{<path d="M68 -566 L106 -522 L118 -606 Z" fill="$ROSA" opacity="0.75" stroke="$ROSA" stroke-width="8" stroke-linejoin="round"/>};
  $s .= qq{<path d="M-20 -536 L-11 -560 L10 -540 L31 -560 L40 -536" fill="none" stroke="$FELL2" stroke-width="9" stroke-linecap="round" stroke-linejoin="round"/>};
  $s .= qq{<circle cx="10" cy="-404" r="56" fill="$CREME"/>};
  # Maul offen
  $s .= qq{<defs><clipPath id="maul"><path d="M-24 -404 L44 -404 A34 34 0 0 1 -24 -404 Z"/></clipPath></defs>};
  $s .= qq{<path d="M-24 -404 L44 -404 A34 34 0 0 1 -24 -404 Z" fill="$MAUL"/>};
  $s .= qq{<g clip-path="url(#maul)"><ellipse cx="10" cy="-372" rx="22" ry="14" fill="$ZUNGE"/></g>};
  $s .= qq{<path d="M-14 -405 L-4 -405 L-9 -391 Z M24 -405 L34 -405 L29 -391 Z" fill="$CREME" stroke="$CREME" stroke-width="2" stroke-linejoin="round"/>};
  $s .= qq{<circle cx="-16" cy="-428" r="28" fill="$CREME"/><circle cx="36" cy="-428" r="28" fill="$CREME"/>};
  $s .= qq{<path d="M-6 -458 L26 -458 L10 -441 Z" fill="$ROSA" stroke="$ROSA" stroke-width="8" stroke-linejoin="round"/>};
  # Schnurrhaare
  $s .= qq{<g stroke="$CREME" stroke-width="3.5" stroke-linecap="round" opacity="0.9" fill="none"><path d="M-40 -432 L-100 -446 M-40 -422 L-104 -420 M-40 -412 L-98 -394"/><path d="M60 -432 L120 -446 M60 -422 L124 -420 M60 -412 L118 -394"/></g>};
  # Augen (mandelförmig, Blick nach oben)
  for my $e ([-34,-494,12,'l'],[54,-494,-12,'r']) { my ($ex,$ey,$rot,$k)=@$e;
    my $lens = 'M'.pt($ex-30,$ey).' A33 33 0 0 1 '.pt($ex+30,$ey).' A33 33 0 0 1 '.pt($ex-30,$ey).' Z';
    $s .= qq{<g transform="rotate($rot $ex $ey)"><defs><clipPath id="auge$k"><path d="$lens"/></clipPath></defs><path d="$lens" fill="$AUGE"/>}
        . qq{<g clip-path="url(#auge$k)"><circle cx="}.n($ex+4).qq{" cy="}.n($ey-6).qq{" r="15" fill="$TINTE"/><circle cx="}.n($ex-1).qq{" cy="}.n($ey-11).qq{" r="5" fill="#FFFFFF"/></g>}
        . qq{<path d="M}.pt($ex-30,$ey).' A33 33 0 0 1 '.pt($ex+30,$ey).qq{" fill="none" stroke="$TINTE" stroke-width="4"/></g>}; }
  $s .= '</g>';
  # erhobener Arm mit Pfote am Maul
  $s .= qq{<path d="$ARM" fill="none" stroke="$FELL" stroke-width="52" stroke-linecap="round" stroke-linejoin="round"/>};
  $s .= qq{<circle cx="-30" cy="-390" r="31" fill="$CREME" stroke="$FELL" stroke-width="6"/>};
  $s .= qq{<path d="M-46 -404 L-36 -396 M-34 -414 L-27 -403 M-20 -418 L-17 -406" stroke="$FELL" stroke-width="4.5" stroke-linecap="round" opacity="0.6"/>};
  return $s; }

# Sprechblase (drei runde Ecken, eine spitze Ecke unten links)
sub blase { my ($x,$y,$w,$h,$fill)=@_; my $r=$h/2;
  return qq{<path d="M}.pt($x,$y+$h).' V'.n($y+$r)." A$r $r 0 0 1 ".pt($x+$r,$y).' H'.n($x+$w-$r)." A$r $r 0 0 1 ".pt($x+$w,$y+$r)." A$r $r 0 0 1 ".pt($x+$w-$r,$y+$h).qq{ Z" fill="$fill"/>}; }

# ---------------------------------------------------------------- Logo
sub logo_svg { my ($p)=@_; $p//='logo';
  my $bg='#EEE6D7';
  my $kw=330; my $kh=$kw*$H/$W;
  my $defs = als_symbol('motiv_hell_gelb',"$p-kh").als_symbol('motiv_dunkel_lila',"$p-kd");
  my $karte = sub { my ($id,$x,$y,$rot)=@_;
    return qq{<g transform="translate($x $y) rotate($rot)"><rect x="}.n(-$kw/2+12).qq{" y="}.n(-$kh/2+16).qq{" width="$kw" height="}.n($kh).qq{" rx="24" fill="$TINTE" opacity="0.13"/>}
         . qq{<use href="#$id" x="}.n(-$kw/2).qq{" y="}.n(-$kh/2).qq{" width="$kw" height="}.n($kh).qq{"/></g>}; };
  my ($kx,$ky)=(526,838);
  my $s = qq{<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1600 900" width="1600" height="900">\n<title>Mau-Mau Flip – Logo (Entwurf C)</title>\n<style>\@import url('$FONT_URL');</style>\n<defs>$defs</defs>\n};
  $s .= qq{<g id="hintergrund"><rect width="1600" height="900" fill="$bg"/></g>\n};
  $s .= qq{<g id="karten">}.$karte->("$p-kh",300,420,-12).$karte->("$p-kd",762,420,12).qq{</g>\n};
  $s .= qq{<g id="boden"><ellipse cx="$kx" cy="}.n($ky+2).qq{" rx="270" ry="20" fill="$TINTE" opacity="0.12"/></g>\n};
  $s .= qq{<g id="katze" transform="translate($kx $ky)">}.katze(knockout=>$bg,ko=>13).qq{</g>\n};
  # Ausruf "Mau!"
  my ($bx,$by,$bw,$bh)=($kx+168,$ky-716,218,138);
  $s .= qq{<g id="ausruf">}.blase($bx,$by,$bw,$bh,'#B3202A')
      . txt($bx+$bw/2+4,$by+$bh/2+23,66,$CREME,'Mau!',weight=>900)
      . qq{</g>\n};
  # Schriftzug
  my ($wx,$wy)=(1000,398);
  my $f2=236; my $iy=$wy+272;
  my $dotx=$wx+0.880*$f2+0.142*$f2; my $doty=$iy-0.655*$f2; my $dr=0.118*$f2;
  $s .= qq{<g id="schriftzug">}
      . txt($wx,$wy,117,$TINTE,"Mau-Mau",weight=>900,anchor=>'start')
      . txt($wx-4,$iy,$f2,$TINTE,'Fl&#x131;p',weight=>900,anchor=>'start')
      . qq{<g id="flip-punkt">}.flipscheibe_klein($dotx,$doty,$dr).'</g>'
      . txt($wx+2,$iy+86,24.5,'#5C5662','KARTENSPIEL MIT ZWEI SEITEN',weight=>600,anchor=>'start',extra=>' letter-spacing="4.6"');
  my $sx=$wx+2; for my $i (0..7) { my $c = $FARBE{(@HELL,@DUNKEL)[$i]}{basis}; $s .= qq{<rect x="}.n($sx+$i*65.5).qq{" y="}.n($iy+116).qq{" width="56" height="12" rx="6" fill="$c"/>}; }
  $s .= qq{</g>\n</svg>\n};
  return $s; }

sub flipscheibe_klein { my ($cx,$cy,$r)=@_;
  return qq{<path d="M}.pt($cx,$cy-$r).' A'.n($r).' '.n($r).' 0 0 0 '.pt($cx,$cy+$r).qq{ Z" fill="#FFDD33"/>}
       . qq{<path d="M}.pt($cx,$cy-$r).' A'.n($r).' '.n($r).' 0 0 1 '.pt($cx,$cy+$r).qq{ Z" fill="$NACHT1"/>}
       . qq{<path fill="$MOND" d="}.sichel($cx+$r*0.42,$cy,$r*0.36,$cx+$r*0.6,$cy-$r*0.12,$r*0.3).qq{"/>}
       . qq{<circle cx="}.n($cx).qq{" cy="}.n($cy).qq{" r="}.n($r-2).qq{" fill="none" stroke="$TINTE" stroke-width="4"/>}; }

# ---------------------------------------------------------------- App-Symbol
sub icon_svg { my ($p)=@_; $p//='icon';
  my $s = qq{<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512" width="512" height="512">\n<title>Mau-Mau Flip – App-Symbol (Entwurf C)</title>\n}
        . qq{<defs><clipPath id="form"><rect width="512" height="512" rx="112"/></clipPath></defs>\n<g clip-path="url(#form)">};
  $s .= qq{<g id="grund"><rect width="512" height="512" fill="$NACHT1"/><rect width="256" height="512" fill="#FFDD33"/>}
      . qq{}
      . qq{<path fill="$MOND" d="}.sichel(424,104,36,442,90,30).qq{"/>}.stern4(360,72,9,$MOND).stern4(462,170,7,$MOND).qq{<circle cx="380" cy="150" r="4" fill="$MOND"/>}
      . qq{<g fill="$TINTE" opacity="0.14">}.join('',map { my $a=$_*30+90; qq{<path d="M}.pt(pol(84,96,40,$a-7)).' L'.pt(pol(84,96,62,$a)).' L'.pt(pol(84,96,40,$a+7)).qq{ Z"/>} } (0..11)).qq{<circle cx="84" cy="96" r="32"/></g>}
      . qq{</g>};
  $s .= qq{<g id="katze" transform="translate(250 714) scale(1.02)">}.katze(knockout=>$CREME,ko=>11).qq{</g>};
  $s .= qq{</g>\n</svg>\n};
  return $s; }

my $LOGO = logo_svg('logo');
my $ICON = icon_svg('icon');
schreibe('logo.svg',$LOGO);
schreibe('icon.svg',$ICON);

# ---------------------------------------------------------------- Handansicht 1600×720 (Dichte 2,0: 1 dp = 2 px)
sub hand_svg { my ($p)=@_;
  my @hand = qw(hell_rot_7 hell_rot_flip hell_gelb_4 hell_gelb_plus1 hell_gruen_2 hell_gruen_aussetzen hell_blau_9 hell_blau_richtungswechsel hell_wuenscher);
  my %spielbar = map { $_=>1 } qw(hell_gruen_2 hell_blau_9 hell_blau_richtungswechsel hell_wuenscher);
  my $fokus = 6;
  my @gegner = (
    ["Lena", 410, [qw(dunkel_pink_flip dunkel_tuerkis_7 dunkel_lila_6 dunkel_orange_alle_aussetzen dunkel_wuenscher)]],
    ['Tom',  800, [qw(dunkel_orange_3 dunkel_lila_1 dunkel_tuerkis_plus5 dunkel_pink_8 dunkel_farbjagd dunkel_lila_richtungswechsel dunkel_pink_plus5)]],
    ["Oma Gerda", 1190, [qw(dunkel_tuerkis_7)]],
  );
  my %brauch; $brauch{$_}=1 for @hand, qw(hell_blau_2 hell_rot_2 hell_gruen_aussetzen dunkel_orange_alle_aussetzen dunkel_lila_6); for my $g (@gegner) { $brauch{$_}=1 for @{$g->[2]}; }
  my $defs = join '', map { als_symbol($_,"$p-$_") } sort keys %brauch;
  $defs .= qq{<filter id="$p-schatten" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur in="SourceAlpha" stdDeviation="7"/><feOffset dy="6"/><feComponentTransfer><feFuncA type="linear" slope="0.45"/></feComponentTransfer><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>};
  $defs .= qq{<filter id="$p-glanz" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="9"/></filter>};
  my $karte = sub { my ($name,$cx,$cy,$w,$rot,$extra)=@_; $extra//=''; my $h=$w*$H/$W;
    return qq{<g transform="translate(}.pt($cx,$cy).") rotate(".n($rot).qq{)"$extra><use href="#$p-$name" x="}.n(-$w/2).qq{" y="}.n(-$h/2).qq{" width="}.n($w).qq{" height="}.n($h).qq{"/></g>}; };
  my $s = qq{<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1600 720" width="1600" height="720">\n<defs>$defs</defs>\n};
  # Tisch
  $s .= qq{<g id="tisch"><rect width="1600" height="720" fill="#181B2D"/>}
      . qq{<ellipse cx="800" cy="338" rx="600" ry="262" fill="#1F2339"/><ellipse cx="800" cy="338" rx="600" ry="262" fill="none" stroke="#2B3050" stroke-width="3"/>}
      . join('', map { my ($t0,$t1)=@$_; my @a=(800+600*cos(rad($t0)),338+262*sin(rad($t0))); my @e=(800+600*cos(rad($t1)),338+262*sin(rad($t1)));
          my @d=(-600*sin(rad($t1)),262*cos(rad($t1))); my $l=sqrt($d[0]**2+$d[1]**2); @d=map { $_/$l } @d;
          qq{<path d="M}.pt(@a).' A600 262 0 0 1 '.pt(@e).qq{" fill="none" stroke="#3A4068" stroke-width="6" stroke-linecap="round"/>}
          .qq{<path d="M}.pt($e[0]+$d[0]*22,$e[1]+$d[1]*22).' L'.pt($e[0]-$d[1]*14,$e[1]+$d[0]*14).' L'.pt($e[0]+$d[1]*14,$e[1]-$d[0]*14).qq{ Z" fill="#3A4068"/>} } ([148,200],[328,20]))
      . qq{</g>\n};
  # Gegner mit sichtbaren Rückseiten
  $s .= qq{<g id="gegner">};
  for my $g (@gegner) { my ($name,$gx,$karten)=@$g; my $nk=@$karten; my $kw=50;
    for my $i (0..$nk-1) { my $d=$i-($nk-1)/2; $s .= $karte->($karten->[$i],$gx+$d*24,92+abs($d)*2.2,$kw,$d*5); }
    my $pw = 40 + length($name)*13 + 44;
    $s .= qq{<rect x="}.n($gx-$pw/2).qq{" y="150" width="}.n($pw).qq{" height="40" rx="20" fill="#2A2F4D"/>}
        . txt($gx-$pw/2+22,177,22,$MOND,$name,weight=>600,anchor=>'start')
        . qq{<circle cx="}.n($gx+$pw/2-22).qq{" cy="170" r="15" fill="#FFDD33"/>}.txt($gx+$pw/2-22,177.5,19,$TINTE,$nk,weight=>800);
    if ($nk==1) { $s .= blase($gx+38,24,104,58,'#B3202A').txt($gx+92,62,30,$CREME,'Mau!',weight=>900); }
  }
  $s .= qq{<rect x="36" y="28" width="250" height="38" rx="19" fill="none" stroke="#3A4068" stroke-width="2"/>}.txt(56,54,19,'#9CA3C9','Regel: Rückseiten sichtbar',weight=>500,anchor=>'start');
  $s .= qq{</g>\n};
  # Tischmitte
  my $tw=128;
  $s .= qq{<g id="mitte">};
  for my $i (reverse 0..3) { $s .= qq{<rect x="}.n(640-$tw/2+$i*3).qq{" y="}.n(316-$tw*$H/$W/2+$i*3).qq{" width="$tw" height="}.n($tw*$H/$W).qq{" rx="10" fill="#0A0B18" stroke="#2C3060" stroke-width="1.5"/>}; }
  $s .= $karte->("dunkel_orange_alle_aussetzen",640,316,$tw,0);
  $s .= txt(640,462,20,'#9CA3C9','ZIEHEN',weight=>600,extra=>' letter-spacing="3"');
  $s .= qq{<circle cx="930" cy="316" r="140" fill="none" stroke="$FARBE{blau}{basis}" stroke-width="9"/><circle cx="930" cy="316" r="140" fill="none" stroke="#7FA2FF" stroke-width="2" opacity="0.6"/>};
  $s .= $karte->("hell_gruen_aussetzen",918,322,$tw,-14).$karte->("hell_rot_2",944,312,$tw,9).$karte->("hell_blau_2",930,316,$tw,-2);
  $s .= qq{<rect x="1004" y="182" width="122" height="44" rx="22" fill="$FARBE{blau}{basis}"/>}.symbol("kristall",1030,204,26,$CREME).txt(1050,212,22,$CREME,'Blau',weight=>700,anchor=>'start');
  $s .= qq{</g>\n};
  # Hand (Fächer, Fischauge um die angehobene Karte)
  my $kw=152; my $kh=$kw*$H/$W; my @gap; my $sum=0;
  for my $i (0..$#hand-1) { my $d=($i+0.5)-$fokus; my $g=22+30*exp(-($d/2.2)**2); push @gap,$g*2; $sum+=$g*2; }
  my $x=800-($sum+$kw)/2+$kw/2; my @pos;
  for my $i (0..$#hand) { push @pos,$x; $x+=$gap[$i] if $i<$#hand; }
  $s .= qq{<g id="hand">};
  for my $i (0..$#hand) { my $name=$hand[$i]; my $cx=$pos[$i]; my $rel=($cx-800)/420; my $rot=$rel*7; my $top=566+$rel*$rel*16;
    my $lift = $i==$fokus ? 64 : ($spielbar{$name} ? 16 : 0);
    my $cy=$top+$kh/2-$lift;
    if ($i==$fokus) { $s .= qq{<g transform="translate(}.pt($cx,$cy).') rotate('.n($rot).qq{)"><rect x="}.n(-$kw/2-6).qq{" y="}.n(-$kh/2-6).qq{" width="}.n($kw+12).qq{" height="}.n($kh+12).qq{" rx="26" fill="none" stroke="#7FA2FF" stroke-width="10" filter="url(#$p-glanz)"/></g>}; }
    $s .= $karte->($name,$cx,$cy,$kw,$rot,qq{ filter="url(#$p-schatten)"});
    unless ($spielbar{$name}) { $s .= qq{<g transform="translate(}.pt($cx,$cy).') rotate('.n($rot).qq{)"><rect x="}.n(-$kw/2).qq{" y="}.n(-$kh/2).qq{" width="$kw" height="}.n($kh).qq{" rx="11" fill="#0B0C18" opacity="0.22"/></g>}; }
  }
  my $fx=$pos[$fokus];
  $s .= qq{<rect x="}.n($fx-92).qq{" y="452" width="184" height="36" rx="18" fill="$MOND"/>}.txt($fx,477,19,$TINTE,'Tippen: spielen',weight=>600);
  $s .= qq{</g>\n};
  # Bedienung
  $s .= qq{<g id="bedienung">};
  $s .= qq{<rect x="32" y="560" width="270" height="44" rx="22" fill="#262B47"/>}.flip_glyph(62,582,24,'#C9CFF0').txt(86,590,20,'#C9CFF0','Rückseiten ansehen',weight=>600,anchor=>'start');
  my @seg=('Farbe','Wert','Punkte','Manuell'); my $sx=32;
  $s .= qq{<rect x="32" y="620" width="340" height="44" rx="22" fill="#262B47"/>};
  for my $i (0..3) { my $w=[78,70,86,98]->[$i]; if ($i==0) { $s .= qq{<rect x="}.n($sx+4).qq{" y="624" width="}.n($w).qq{" height="36" rx="18" fill="$MOND"/>}; }
    $s .= txt($sx+4+$w/2,649,18,($i==0?$TINTE:'#C9CFF0'),$seg[$i],weight=>600); $sx+=$w+4; }
  $s .= txt(36,546,18,'#9CA3C9','SORTIEREN · ANSICHT',weight=>600,anchor=>'start',extra=>' letter-spacing="2"');
  $s .= qq{<circle cx="1500" cy="616" r="60" fill="#FFDD33"/><circle cx="1500" cy="616" r="60" fill="none" stroke="$TINTE" stroke-width="4" opacity="0.15"/>}.txt(1500,628,34,$TINTE,'Mau!',weight=>900);
  $s .= qq{<rect x="1390" y="28" width="174" height="38" rx="19" fill="#262B47"/>}.txt(1477,54,19,'#C9CFF0','Du bist dran',weight=>600);
  $s .= qq{</g>\n</svg>\n};
  return $s; }

my $HAND = hand_svg('hand');

# ---------------------------------------------------------------- Farbprüfung (OKLab, Machado 2009, Schweregrad 1)
sub lin { my $c=shift; $c/=255; return $c<=0.04045 ? $c/12.92 : (($c+0.055)/1.055)**2.4; }
sub hex_rgb { my $h=shift; $h=~s/#//; return map { hex($_) } ($h=~/(..)(..)(..)/); }
sub oklab { my ($r,$g,$b)=@_;
  my $l=0.4122214708*$r+0.5363325363*$g+0.0514459929*$b; my $m=0.2119034982*$r+0.6806995451*$g+0.1073969566*$b; my $s=0.0883024619*$r+0.2817188376*$g+0.6299787005*$b;
  ($l,$m,$s)=map { $_<0 ? -((-$_)**(1/3)) : $_**(1/3) } ($l,$m,$s);
  return (0.2104542553*$l+0.7936177850*$m-0.0040720468*$s, 1.9779984951*$l-2.4285922050*$m+0.4505937099*$s, 0.0259040371*$l+0.7827717662*$m-0.8086757660*$s); }
my %SIM = (
  normal => [[1,0,0],[0,1,0],[0,0,1]],
  protan => [[0.152286,1.052583,-0.204868],[0.114503,0.786281,0.099216],[-0.003882,-0.048116,1.051998]],
  deutan => [[0.367322,0.860646,-0.227968],[0.280085,0.672501,0.047413],[-0.011820,0.042940,0.968881]],
  tritan => [[1.255528,-0.076749,-0.178779],[-0.078411,0.930809,0.147602],[0.004733,0.691367,0.303900]],
);
sub sim_lab { my ($hex,$art)=@_; my @c=map { lin($_) } hex_rgb($hex); my $M=$SIM{$art};
  my @o = map { my $z=$M->[$_]; my $v=$z->[0]*$c[0]+$z->[1]*$c[1]+$z->[2]*$c[2]; $v<0?0:($v>1?1:$v) } 0..2; return oklab(@o); }
my %PRUEF;
for my $seite (['hell',\@HELL],['dunkel',\@DUNKEL]) { my ($sn,$liste)=@$seite;
  for my $art (qw(normal protan deutan tritan)) { my $min=9; my $paar='';
    for my $i (0..3) { for my $j ($i+1..3) { my @a=sim_lab($FARBE{$liste->[$i]}{basis},$art); my @b=sim_lab($FARBE{$liste->[$j]}{basis},$art);
      my $d=sqrt(($a[0]-$b[0])**2+($a[1]-$b[1])**2+($a[2]-$b[2])**2); if ($d<$min) { $min=$d; $paar="$FARBE{$liste->[$i]}{name}–$FARBE{$liste->[$j]}{name}"; } } }
    $PRUEF{$sn}{$art}=[$min,$paar]; } }
my %LSTERN; for my $k (@HELL,@DUNKEL) { my @l=sim_lab($FARBE{$k}{basis},'normal'); $LSTERN{$k}=$l[0]; }

# ---------------------------------------------------------------- HTML-Seiten
sub seite { my ($titel,$body,$css,$bg)=@_; $bg//='#E9E2D3';
  return qq{<!doctype html>\n<html lang="de"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">\n<title>$titel</title>\n}
       . qq{<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>\n<link href="$FONT_URL_HTML" rel="stylesheet">\n}
       . qq{<style>html,body{margin:0;padding:0;background:$bg;}body{font-family:Jost,Futura,sans-serif;color:#17171F;}svg{display:block}$css</style></head>\n<body>\n$body\n<script>addEventListener('load',()=>setTimeout(()=>{document.body.dataset.h=document.documentElement.scrollHeight},300))</script>\n</body></html>\n}; }

schreibe('logo.html', seite('Mau-Mau Flip – Logo', einbetten($LOGO,'L'), 'body{width:1600px;height:900px;overflow:hidden}'));
schreibe('hand.html', seite('Mau-Mau Flip – Handansicht', $HAND, 'body{width:1600px;height:720px;overflow:hidden}', '#181B2D'));
schreibe('icon.html', seite('Mau-Mau Flip – App-Symbol', einbetten($ICON,'I'), 'body{width:512px;height:512px;overflow:hidden;background:transparent}', 'transparent'));

# Vorschau
my @PAARE = (
  ['hell_rot_7','dunkel_tuerkis_7','Zahl'],
  ['hell_gelb_plus1','dunkel_pink_plus5','Zieh 1 / Zieh 5'],
  ['hell_gruen_aussetzen','dunkel_orange_alle_aussetzen','Aussetzen / Alle aussetzen'],
  ['hell_blau_richtungswechsel','dunkel_lila_richtungswechsel','Richtungswechsel'],
  ['hell_rot_flip','dunkel_pink_flip','Flip'],
  ['hell_wuenscher','dunkel_wuenscher','Wünscher'],
  ['hell_wuenscher_plus2','dunkel_farbjagd','Wünscher +2 / Farbjagd'],
  ['hell_blau_9','dunkel_lila_6','6 und 9 unterstrichen'],
);
my $karten_html = '';
for my $pr (@PAARE) { my ($a,$b,$t)=@$pr;
  $karten_html .= qq{<figure class="paar"><div class="zwei"><div class="k">}.einbetten($SVG{$a},"g-$a").qq{</div><div class="k">}.einbetten($SVG{$b},"g-$b").qq{</div></div><figcaption><b>$t</b><span>$a · $b</span></figcaption></figure>\n}; }

my $streifen_html='';
for my $pr (@PAARE) { for my $name (@$pr[0,1]) {
  $streifen_html .= qq{<div class="strip" title="$name"><div class="clip">}.einbetten($SVG{$name},"s-$name").qq{</div></div>}; } }

my $pal_html='';
for my $k (@HELL,@DUNKEL) { my $F=$FARBE{$k}; my $hell=$F->{seite} eq 'hell';
  my $sw = $hell
    ? qq{<svg viewBox="0 0 120 120" width="120" height="120"><rect x="4" y="4" width="112" height="112" rx="18" fill="$CREME"/><rect x="12" y="12" width="96" height="96" rx="12" fill="$F->{basis}"/>}.symbol($F->{symbol},60,60,62,$F->{text}).'</svg>'
    : qq{<svg viewBox="0 0 120 120" width="120" height="120"><rect x="4" y="4" width="112" height="112" rx="18" fill="$NACHT"/><rect x="12" y="12" width="96" height="96" rx="12" fill="none" stroke="$F->{licht}" stroke-width="3"/><circle cx="60" cy="60" r="36" fill="$F->{basis}"/>}.symbol($F->{symbol},60,60,50,$F->{licht}).'</svg>';
  $pal_html .= qq{<div class="farbe">$sw<div class="fi"><b>$F->{name}</b><span>$F->{symname}</span><code>$F->{basis}</code><span>OKLab L }.sprintf('%.2f',$LSTERN{$k}).qq{</span><span class="mini">}
    . qq{<svg viewBox="0 0 64 22" width="64" height="22">}.symbol($F->{symbol},11,11,20,$TINTE).symbol($F->{symbol},40,11,13,$TINTE).'</svg>'
    . qq{</span></div></div>}; }

my $pruef_html = qq{<table class="pruef"><tr><th>Seite</th><th>normal</th><th>Rotschwäche</th><th>Grünschwäche</th><th>Blau-Gelb-Schwäche</th></tr>};
for my $sn (qw(hell dunkel)) { $pruef_html .= qq{<tr><td>$sn</td>};
  for my $art (qw(normal protan deutan tritan)) { my ($m,$p)=@{$PRUEF{$sn}{$art}}; $pruef_html .= '<td>'.sprintf('%.3f',$m).qq{<small>$p</small></td>}; }
  $pruef_html .= '</tr>'; }
$pruef_html .= '</table>';

my $filter_defs = qq{<svg width="0" height="0" style="position:absolute"><defs>}
  . qq{<filter id="cvd-protan" color-interpolation-filters="linearRGB"><feColorMatrix type="matrix" values="0.152286 1.052583 -0.204868 0 0 0.114503 0.786281 0.099216 0 0 -0.003882 -0.048116 1.051998 0 0 0 0 0 1 0"/></filter>}
  . qq{<filter id="cvd-deutan" color-interpolation-filters="linearRGB"><feColorMatrix type="matrix" values="0.367322 0.860646 -0.227968 0 0 0.280085 0.672501 0.047413 0 0 -0.011820 0.042940 0.968881 0 0 0 0 0 1 0"/></filter>}
  . qq{<filter id="cvd-tritan" color-interpolation-filters="linearRGB"><feColorMatrix type="matrix" values="1.255528 -0.076749 -0.178779 0 0 -0.078411 0.930809 0.147602 0 0 0.004733 0.691367 0.303900 0 0 0 0 0 1 0"/></filter>}
  . qq{<filter id="cvd-grau" color-interpolation-filters="linearRGB"><feColorMatrix type="saturate" values="0"/></filter></defs></svg>};

my @simkarten = qw(hell_rot_7 hell_gelb_plus1 hell_gruen_aussetzen hell_blau_9 dunkel_pink_plus5 dunkel_tuerkis_7 dunkel_orange_alle_aussetzen dunkel_lila_6);
my $sim_html='';
for my $art (['normal','Normal',''],['protan','Rotschwäche','url(#cvd-protan)'],['deutan','Grünschwäche','url(#cvd-deutan)'],['tritan','Blau-Gelb-Schwäche','url(#cvd-tritan)'],['grau','ohne Farbe','url(#cvd-grau)']) {
  my ($id,$label,$f)=@$art;
  $sim_html .= qq{<div class="simreihe"><span>$label</span><div class="simkarten" style="filter:$f">};
  for my $name (@simkarten) { $sim_html .= qq{<div class="sk"><div class="clip">}.einbetten($SVG{$name},"c$id-$name").qq{</div></div>}; }
  $sim_html .= qq{</div></div>}; }

my $css = <<'CSS';
.wrap{width:1520px;margin:0 auto;padding:40px 0 60px}
header{display:flex;align-items:flex-end;justify-content:space-between;border-bottom:3px solid #17171F;padding-bottom:18px;margin-bottom:34px}
header h1{font-size:60px;font-weight:900;margin:0;letter-spacing:-0.5px;line-height:1}
header h1 span{display:block;font-size:28px;font-weight:500;color:#6B6470;margin-top:10px;letter-spacing:0}
header p{margin:0;font-size:19px;color:#4A4550;max-width:520px;text-align:right;line-height:1.35}
h2{font-size:15px;letter-spacing:4px;text-transform:uppercase;font-weight:700;margin:46px 0 16px;display:flex;align-items:center;gap:14px}
h2:before{content:"";width:22px;height:22px;border-radius:50%;background:linear-gradient(90deg,#FFDD33 50%,#15183C 50%);box-shadow:0 0 0 2px #17171F}
.logo svg{width:1520px;height:855px;border-radius:22px;box-shadow:0 2px 0 #d6cdbb}
.icons{display:flex;gap:40px;align-items:flex-end;background:#F4EFE5;border-radius:22px;padding:28px 34px}
.icons figure{margin:0;display:flex;flex-direction:column;align-items:center;gap:10px;font-size:16px;color:#4A4550}
.icons .i512 svg{width:512px;height:512px}.icons .i96 svg{width:96px;height:96px}.icons .i48 svg{width:48px;height:48px}
.icons .home{margin-left:auto;width:520px;height:330px;border-radius:18px;background:linear-gradient(160deg,#2A2F4D,#14172B);display:grid;grid-template-columns:repeat(5,1fr);align-items:center;justify-items:center;padding:20px;box-sizing:border-box;color:#fff;font-size:13px}
.icons .home .app{display:flex;flex-direction:column;align-items:center;gap:6px}
.icons .home .app i{display:block;width:58px;height:58px;border-radius:16px;background:#3a4064}
.icons .home .app svg{width:58px;height:58px}
.karten{display:grid;grid-template-columns:repeat(4,1fr);gap:26px 30px}
.paar{margin:0;background:#F4EFE5;border-radius:18px;padding:18px 18px 12px}
.paar .zwei{display:flex;gap:14px;justify-content:center}
.paar .k svg{width:150px;height:233px;filter:drop-shadow(0 3px 4px rgba(0,0,0,.18))}
.paar figcaption{margin-top:10px;font-size:16px;display:flex;flex-direction:column;align-items:center}
.paar figcaption span{font-size:11.5px;color:#7A7480;margin-top:2px}
.hand{margin-bottom:18px}.hand svg{width:1520px;height:684px;border-radius:26px;box-shadow:0 0 0 10px #17171F,0 0 0 12px #3a3a46}
.streifen{display:flex;gap:6px;align-items:flex-start;background:#181B2D;border-radius:18px;padding:22px 24px;flex-wrap:wrap}
.strip{width:44px;height:142px;overflow:hidden;border-radius:8px 0 0 0}
.strip .clip svg{width:152px;height:236px}
.erkl{font-size:17px;line-height:1.5;color:#2E2A33;max-width:1400px}
.palette{display:grid;grid-template-columns:repeat(4,1fr);gap:18px}
.farbe{display:flex;gap:14px;align-items:center;background:#F4EFE5;border-radius:16px;padding:10px 14px}
.farbe .fi{display:flex;flex-direction:column;font-size:14px;color:#4A4550;gap:1px}
.farbe .fi b{font-size:21px;color:#17171F}
.farbe code{font-size:13px}
.pruef{border-collapse:collapse;margin-top:18px;font-size:16px;background:#F4EFE5;border-radius:12px;overflow:hidden}
.pruef th,.pruef td{padding:8px 16px;text-align:left;border-bottom:1px solid #ddd3c2}
.pruef td small{display:block;color:#7A7480;font-size:12px}
.simreihe{display:flex;align-items:center;gap:16px;margin:6px 0}
.simreihe>span{width:170px;font-size:15px;font-weight:600}
.simkarten{display:flex;gap:10px}
.sk .clip svg{width:76px;height:118px}
.text{display:grid;grid-template-columns:1fr 1fr;gap:28px 46px;font-size:17px;line-height:1.5}
.text h3{margin:0 0 6px;font-size:20px}
.text p{margin:0}
.fuss{margin-top:40px;font-size:14px;color:#6B6470;border-top:2px solid #17171F;padding-top:14px}
CSS

my $body = qq{$filter_defs<div class="wrap">
<header><h1>Mau-Mau Flip<span>Entwurf C · Geometrisch &amp; kräftig</span></h1><p>Entwurf: Karten, Logo, App-Symbol und Spielansicht im Querformat. Bauhaus-Formen, große Ziffern, Tag- und Nachtseite.</p></header>
<h2>Logo</h2><div class="logo">}.einbetten($LOGO,'pl').qq{</div>
<h2>App-Symbol · 512 / 96 / 48 px</h2>
<div class="icons"><figure class="i512">}.einbetten($ICON,'pi1').qq{<figcaption>512 px</figcaption></figure><figure class="i96">}.einbetten($ICON,'pi2').qq{<figcaption>96 px</figcaption></figure><figure class="i48">}.einbetten($ICON,'pi3').qq{<figcaption>48 px</figcaption></figure>
<div class="home"><div class="app"><i></i>Kamera</div><div class="app"><i></i>Karten</div><div class="app">}.einbetten($ICON,'pi4').qq{Mau-Mau Flip</div><div class="app"><i></i>Fotos</div><div class="app"><i></i>Uhr</div><div class="app"><i></i>Wetter</div><div class="app"><i></i>Notizen</div><div class="app"><i></i>Musik</div><div class="app"><i></i>Rechner</div><div class="app"><i></i>Spiele</div></div></div>
<h2>Karten · hell und dunkel</h2><div class="karten">$karten_html</div>
<h2>Handansicht · Querformat 1600×720 (Dichte 2,0)</h2><div class="hand">}.$HAND =~ s/\bid="hand-/id="ph-/gr =~ s/#hand-/#ph-/gr =~ s/url\(#hand-/url(#ph-/gr .qq{</div>
<p class="erkl">Neun Karten im Fächer, unten vom Bildschirmrand angeschnitten. Die Abstände folgen dem Fischauge: um die angehobene Karte 52 dp, außen 22 dp. Spielbare Karten sind 8 dp angehoben, die übrigen leicht abgedunkelt. Der Ziehstapel zeigt – wie im echten Spiel – die dunkle Seite der nächsten Karte, die Gegnerhände zeigen ihre Rückseiten (globale Regel „Rückseiten sichtbar“).</p>
<h2>Streifentest · 22 dp sichtbar (44 px bei Dichte 2,0), oberer Kartenteil</h2><div class="streifen">$streifen_html</div>
<p class="erkl">So sieht jede Karte aus, wenn im Fächer nur der linke 22-dp-Streifen und der obere Teil zu sehen ist (Karte 76×118 dp). Wert und Farbsymbol bleiben vollständig im Streifen.</p>
<h2>Palette und Formsymbole</h2><div class="palette">$pal_html</div>
$pruef_html
<p class="erkl">Mindestabstand in OKLab je Seite unter Simulation (Machado 2009, Schweregrad 1). Unterhalb von 0,15 hilft das Formsymbol; die Werte stammen aus diesem Generator und sollten auf dem Gerät gegengeprüft werden.</p>
<h2>Simulation · Farbsehschwäche und ohne Farbe</h2>$sim_html
<h2>Gestaltungsbegründung</h2>
<div class="text">
<div><h3>Bauhaus statt Kinderzimmer</h3><p>Alles ist aus Kreis, Halbkreis, Dreieck und Balken gebaut. Große, ruhige Flächen, harte Kanten, keine Verläufe auf der Tagseite. So wirkt das Spiel wie ein moderner Brettspielverlag: verspielt, aber erwachsen.</p></div>
<div><h3>Tag und Nacht ohne Farbe unterscheidbar</h3><p>Hell = Papierrand und volle Farbfläche, Ziffer massiv. Dunkel = Nachtgrund, leuchtende Kontur, Ziffer als Leuchtröhre. Selbst in Graustufen sind die Seiten sofort klar.</p></div>
<div><h3>Eigene Bildsprache</h3><p>Die Mitte trägt eine aufrechte Sonnenscheibe mit Horizontstreifen bzw. eine Mondsichel aus zwei Kreisen. Kein schräges Oval, kein Schlagschatten, kein fremdes Logo. Aktionen sind eigene Piktogramme: Katzenkopf mit „Zz“, Kreispfeile mit Schwanzspitze, Tag-Nacht-Scheibe, Pfote mit Farbballen.</p></div>
<div><h3>Für den Fächer gebaut</h3><p>Der Eckindex (Wert ≈ 17 dp, Symbol ≈ 11 dp) passt in den 22-dp-Streifen. „+“ ist kompakt gezeichnet, damit „+5“ und „+2“ nicht breiter werden. Das Farbsymbol wiederholt sich Ton in Ton oben rechts, damit auch der obere Rand der vordersten Karte eindeutig ist.</p></div>
<div><h3>Die Mau-Katze</h3><p>Eine Smoking-Katze aus Kreisen und Dreiecken: sitzend, Blick nach oben, Pfote am offenen Maul. Mandelaugen und ein „M“ auf der Stirn machen sie erwachsen und doch süß. Sie sagt „Mau!“ in einer Sprechblase mit einer spitzen Ecke.</p></div>
<div><h3>Schrift</h3><p>Jost (Owen Earl, indestructible type*), SIL Open Font License 1.1, über Google Fonts. Geometrisch wie die klassische Bauhaus-Grotesk, mit klaren, breiten Ziffern.</p></div>
</div>
<div class="fuss">Erzeugt mit <code>werkzeug/build.pl</code>. Alle Grafiken sind selbst gezeichnete Vektoren; keine fremden Bilder.</div>
</div>};

schreibe('preview.html', seite('Mau-Mau Flip – Entwurf C: Geometrisch & kräftig', $body, $css));
print "fertig: ".scalar(keys %SVG)." Karten\n";
for my $sn (qw(hell dunkel)) { for my $art (qw(normal protan deutan tritan)) { printf "%-6s %-6s %.3f %s\n",$sn,$art,@{$PRUEF{$sn}{$art}}; } }

# ---------------------------------------------------------------- Prüfseite (nur Entwicklung)
if (-d "$ROOT/werkzeug/tmp") {
  my @alle = map { $_->[0] } @KARTEN;
  my $b = '<div style="display:flex;flex-wrap:wrap;gap:20px;padding:20px">';
  for my $nm (@alle) { $b .= qq{<div style="width:370px">}.einbetten($SVG{$nm},"t-$nm").qq{<div style="font-size:14px">$nm</div></div>}; }
  $b .= '</div>';
  schreibe('werkzeug/tmp/karten_gross.html', seite('Prüfung', $b, 'svg{width:370px;height:575px}', '#bdb5a6'));
}
