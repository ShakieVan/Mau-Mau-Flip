#!/usr/bin/perl
# Mau-Katze im Art-déco-Stil: sitzend im Profil, Kopf gehoben, Pfote am offenen Maul.
# Lokales Koordinatensystem: etwa 0..520 x 0..660, Boden bei y = 650.
use strict;
use warnings;
use utf8;

our $IVORY; our $INK; our $NIGHT; our $GOLD; our $GOLDL;

sub cat_defs {
  my ($P) = @_;
  return qq(<linearGradient id="$P-catfill" x1="0" y1="0" x2="0.35" y2="1"><stop offset="0" stop-color="#2B336B"/><stop offset="0.55" stop-color="#1A1F4A"/><stop offset="1" stop-color="#11143A"/></linearGradient>)
    . qq(<linearGradient id="$P-rim" gradientUnits="userSpaceOnUse" x1="60" y1="0" x2="420" y2="0"><stop offset="0" stop-color="#FFD27A"/><stop offset="0.45" stop-color="#E9C27A"/><stop offset="0.62" stop-color="#B9A2FF"/><stop offset="1" stop-color="#8F74FF"/></linearGradient>)
    . qq(<linearGradient id="$P-catgold" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="520" y2="660"><stop offset="0" stop-color="#B98E3C"/><stop offset="0.4" stop-color="#F2DA98"/><stop offset="0.7" stop-color="#C79C4A"/><stop offset="1" stop-color="#F0D690"/></linearGradient>)
    . qq(<radialGradient id="$P-iris" cx="0.45" cy="0.4" r="0.7"><stop offset="0" stop-color="#FFE7A0"/><stop offset="0.6" stop-color="#F2B53C"/><stop offset="1" stop-color="#C9822A"/></radialGradient>)
    . qq(<filter id="$P-catglow" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="9"/></filter>)
    . qq(<filter id="$P-catglow2" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="3"/></filter>);
}

# Kopf in Kopfkoordinaten (waagerecht, Blick nach rechts, Mitte 0,0)
my $HEAD = 'M-66,6 C-68,-36 -36,-64 0,-64 C28,-64 50,-50 60,-30 C66,-22 72,-16 82,-12 C90,-10 93,-3 89,4 C86,9 82,12 77,15 '
         . 'C66,19 52,23 42,27 C52,32 62,36 72,39 C71,47 65,54 56,58 C40,65 18,67 0,64 C-30,61 -58,42 -66,6 Z';
my $EAR_NEAR = 'M-44,-44 C-42,-76 -36,-102 -28,-122 C-10,-104 6,-84 12,-60 Z';
my $EAR_NEAR_IN = 'M-34,-56 C-33,-80 -30,-98 -26,-108 C-15,-94 -5,-80 0,-64 Z';
my $EAR_FAR = 'M-4,-58 C0,-84 6,-102 14,-118 C26,-98 32,-78 34,-50 Z';
my $MUZZLE = q{M78,-26 C68,-14 58,-6 48,-3 C36,1 30,12 28,26 C26,42 14,56 -4,68 L110,92 L110,-26 Z};
my $JAW = q{M60,56 C42,65 18,67 0,64 C-24,62 -44,50 -56,34};
my $MOUTH = 'M84,10 C70,15 52,22 40,27 C52,33 64,38 76,42 C82,32 86,20 84,10 Z';
my $TONGUE = 'M46,29 C56,33 66,37 75,41 C70,44 62,43 56,40 C51,37 48,33 46,29 Z';

# Koerper (global)
my $BODY = q{M250,200 C224,238 202,290 190,338 C176,392 146,434 132,476 C110,532 114,604 150,632 C162,642 176,648 196,650 } . q{L402,650 C408,646 406,634 396,628 C386,622 382,600 380,560 C378,500 378,440 380,392 C382,336 372,288 350,244 L330,210 Z};
my $ARM  = q{M392,232 C384,300 358,360 346,410 C338,446 354,466 374,462 C394,458 400,430 404,404 C411,350 418,290 422,232 Z};
my $TAIL = 'M170,636 C104,656 40,640 32,584 C24,524 74,494 66,440 C61,404 32,394 22,414';
my $BIB  = q{M336,238 C356,262 376,296 380,336 C383,380 374,424 360,468 C346,432 330,392 320,346 C312,304 316,266 336,238 Z};

sub head_group {
  my ($P) = @_;
  my $o = '';
  $o .= qq(<path d="$EAR_FAR" fill="#151A40"/>);
  $o .= qq(<path d="$EAR_NEAR" fill="url(#$P-catfill)"/>);
  $o .= qq(<path d="$EAR_NEAR_IN" fill="#E79AAE" opacity="0.9"/>);
  $o .= qq(<path d="$MOUTH" fill="#9E3A55"/>);
  $o .= qq(<path d="$TONGUE" fill="#F08AA0"/>);
  $o .= qq(<path d="$HEAD" fill="url(#$P-catfill)"/>);
  $o .= qq(<clipPath id="$P-headclip"><path d="$HEAD"/></clipPath>);
  $o .= qq(<path d="$MUZZLE" fill="$IVORY" clip-path="url(#$P-headclip)"/>);
  $o .= qq(<path d="M70,15 L76,14 L72,23 Z" fill="#FFFFFF"/>);
  $o .= qq(<path d="$JAW" fill="none" stroke="url(#$P-rim)" stroke-width="2.2" stroke-linecap="round"/>);
  $o .= qq(<path d="M-28,-64 C-26,-80 -24,-92 -24,-100 M-18,-64 C-15,-76 -12,-86 -10,-92" fill="none" stroke="url(#$P-catgold)" stroke-width="1.6" stroke-linecap="round"/>);
  # Nase
  $o .= qq(<path d="M83,-11 C90,-10 94,-4 91,3 C87,1 84,-4 83,-11 Z" fill="#D9798F"/>);
  # Auge
  $o .= qq(<g transform="translate(34 -20) rotate(-6) scale(1.12)">)
     . qq(<path d="M-21,2 C-12,-14 12,-16 22,-2 C14,12 -12,14 -21,2 Z" fill="url(#$P-iris)"/>)
     . qq(<circle cx="4" cy="-4" r="8.5" fill="#120E1E"/>)
     . qq(<circle cx="7" cy="-8" r="3" fill="#FFFFFF"/><circle cx="0" cy="-1" r="1.4" fill="#FFFFFF" opacity="0.8"/>)
     . qq(<path d="M-21,2 C-12,-14 12,-16 22,-2" fill="none" stroke="url(#$P-catgold)" stroke-width="3" stroke-linecap="round"/>)
     . qq(<path d="M22,-2 C14,12 -12,14 -21,2" fill="none" stroke="url(#$P-catgold)" stroke-width="1.3"/>)
     . qq(<path d="M18,-8 L27,-14 M12,-12 L18,-20" stroke="url(#$P-catgold)" stroke-width="1.6" stroke-linecap="round"/>)
     . qq(</g>);
  # Schnurrhaare
  $o .= qq(<g fill="none" stroke="url(#$P-catgold)" stroke-width="1.5" stroke-linecap="round" opacity="0.95">)
     . qq(<path d="M70,4 C96,-6 120,-14 146,-18"/><path d="M72,10 C100,6 124,6 150,10"/><path d="M70,16 C96,20 118,28 140,40"/>)
     . qq(</g>);
  # Fellkante Wange
  $o .= qq(<path d="M-48,40 C-38,50 -26,56 -12,60" fill="none" stroke="url(#$P-catgold)" stroke-width="1.4" opacity="0.8"/>);
  $o;
}

sub cat_group {
  my ($P, %opt) = @_;
  my $o = '';
  my $g = "url(#$P-catgold)";
  # Schatten
  $o .= qq(<ellipse cx="270" cy="652" rx="210" ry="16" fill="#000000" opacity="0.35"/>);
  # Glanzsaum (Glow) hinter der Silhouette
  $o .= qq(<g filter="url(#$P-catglow)" opacity="0.75">)
     . ($opt{notail} ? q{} : qq(<path d="$TAIL" fill="none" stroke="url(#$P-rim)" stroke-width="40" stroke-linecap="round"/>))
     . qq(<path d="$BODY" fill="url(#$P-rim)"/>)
     . qq(<g transform="translate(305 178) rotate(-28) scale(1.25)"><path d="$HEAD" fill="url(#$P-rim)"/><path d="$EAR_NEAR" fill="url(#$P-rim)"/><path d="$EAR_FAR" fill="url(#$P-rim)"/></g>)
     . qq(</g>);
  # Konturpass: Saum nur an der Aussenkante
  $o .= qq(<g fill="url(#$P-rim)" stroke="url(#$P-rim)" stroke-width="5" stroke-linejoin="round">)
     . ($opt{notail} ? q{} : qq(<path d="$TAIL" fill="none" stroke-width="35" stroke-linecap="round"/>))
     . qq(<path d="$BODY"/>)
     . qq(<g transform="translate(305 178) rotate(-28) scale(1.25)" stroke-width="4"><path d="$EAR_FAR"/><path d="$EAR_NEAR"/><path d="$HEAD"/><path d="$MOUTH"/></g>)
     . qq(</g>);
  # Schwanz
  unless ($opt{notail}) {
    $o .= qq(<path d="$TAIL" fill="none" stroke="url(#$P-catfill)" stroke-width="30" stroke-linecap="round"/>);
    $o .= qq(<path d="M150,640 C96,652 46,636 40,586" fill="none" stroke="$g" stroke-width="1.4" opacity="0.8"/>);
  }
  # Koerper
  $o .= qq(<path d="$BODY" fill="url(#$P-catfill)"/>);
  $o .= qq(<clipPath id="$P-bodyclip"><path d="$BODY"/></clipPath>);
  $o .= qq(<path d="$BIB" fill="$IVORY" clip-path="url(#$P-bodyclip)"/>);
  # Brustfell-Chevrons
  $o .= qq(<g fill="none" stroke="$g" stroke-width="1.6" stroke-linecap="round" opacity="0.9">)
     . qq(<path d="M340,286 L354,300 L368,288"/><path d="M334,322 L352,340 L372,326"/><path d="M336,362 L352,380 L370,366"/><path d="M342,402 L354,416 L366,404"/>)
     . qq(</g>);
  # Oberschenkel (Art-déco-Bögen)
  $o .= qq(<g fill="none" stroke="$g" stroke-linecap="round">)
     . qq(<path d="M150,486 C196,446 286,468 300,556 C304,596 300,626 292,646" stroke-width="2.2"/>)
     . qq(<path d="M168,514 C204,486 270,502 280,566" stroke-width="1.3" opacity="0.8"/>)
     . qq(<path d="M184,540 C210,522 252,532 260,574" stroke-width="1.1" opacity="0.6"/>)
     . qq(</g>);
  # Vorderbein-Linie und Pfoten
  $o .= qq(<path d="M346,396 C344,470 344,560 350,628" fill="none" stroke="$g" stroke-width="1.8"/>);
  $o .= qq(<path d="M352,650 C350,636 360,626 376,626 C392,626 404,636 404,650 Z" fill="$IVORY"/>);
  $o .= qq(<path d="M378,640 V650 M391,641 V650" stroke="#B9A57A" stroke-width="1.5"/>);
  $o .= qq(<path d="M266,650 C270,634 292,628 314,632 C328,636 334,644 334,650 Z" fill="$IVORY"/>);
  $o .= qq(<path d="M302,640 V650 M318,640 V650" stroke="#B9A57A" stroke-width="1.5"/>);
  # Halsband mit Tag/Nacht-Medaillon
  $o .= qq(<path d="M244,232 C276,252 314,262 350,252" fill="none" stroke="$g" stroke-width="9" stroke-linecap="round"/>);
  $o .= qq(<path d="M244,232 C276,252 314,262 350,252" fill="none" stroke="#7A5A20" stroke-width="1" stroke-dasharray="2 6"/>);
  $o .= qq(<line x1="330" y1="258" x2="331" y2="270" stroke="$g" stroke-width="2"/>);
  $o .= qq(<g transform="translate(331 282)"><circle r="14" fill="#11143A" stroke="$g" stroke-width="2.5"/><path d="M0,-11 A11,11 0 0 0 0,11 Z" fill="#F6E7BF"/><path d="M6,-5 A6,6 0 1 0 6,5 A4.5,5 0 1 1 6,-5 Z" fill="#B9A2FF"/></g>);
  # Kopf
  $o .= qq(<g transform="translate(305 178) rotate(-28) scale(1.25)">) . head_group($P) . qq(</g>);
  # erhobener Arm mit Pfote
  $o .= qq(<path d="$ARM" fill="url(#$P-catfill)" stroke="url(#$P-rim)" stroke-width="2.5" stroke-linejoin="round"/>);
  $o .= qq(<path d="M414,250 C408,320 400,378 394,420" fill="none" stroke="$g" stroke-width="1.4" opacity="0.8"/>);
  $o .= qq(<g transform="translate(407 214) rotate(9) scale(1.18)"><path d="M-21,8 C-24,-12 -14,-28 0,-29 C14,-28 24,-12 21,8 C18,24 -18,24 -21,8 Z" fill="$IVORY" stroke="url(#$P-catgold)" stroke-width="2"/>)
     . qq(<path d="M-8,-27 C-9,-20 -9,-15 -8,-10 M6,-28 C7,-21 7,-16 6,-11" fill="none" stroke="#B9A57A" stroke-width="1.6" stroke-linecap="round"/></g>);
  $o;
}

1;
