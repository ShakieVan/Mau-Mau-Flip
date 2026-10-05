#!/usr/bin/perl
# Mau-Mau Flip, Modul B: TrueType (auch variabel) → WOFF2 für den Browser-Client, ohne Python/fonttools.
# WOFF2 (W3C-Empfehlung 2018) mit Null-Transformation aller Tabellen: Die Tabellen bleiben Byte für Byte gleich und werden nur
# gemeinsam mit Brotli gepackt (brotli-Befehl aus Git für Windows). glyf/loca tragen dafür Transformationsversion 3, alle anderen 0.
# Aufruf: perl woff2.pl <eingabe.ttf> <ausgabe.woff2>
# Prüft den Brotli-Strom per Rückentpackung; die Prüfung im Browser (Glyphen gleich der TTF) macht schriften.html.
use strict;
use warnings;

my ($in, $out) = @ARGV;
die "Aufruf: perl woff2.pl <eingabe.ttf> <ausgabe.woff2>\n" unless defined $out;

# Bekannte Tabellennamen (WOFF2, Abschnitt 5.1): Index 0–62, 63 = Name folgt ausgeschrieben
my @KNOWN = qw(cmap head hhea hmtx maxp name OS/2 post cvt fpgm glyf loca prep CFF VORG EBDT EBLC gasp hdmx kern LTSH PCLT
	VDMX vhea vmtx BASE GDEF GPOS GSUB EBSC JSTF MATH CBDT CBLC COLR CPAL SVG sbix acnt avar bdat bloc bsln cvar fdsc feat fmtx
	fvar gvar hsty just lcar mort morx opbd prop trak Zapf Silf Glat Gloc Feat Sill);
my %KNOWN_IDX;
for my $i (0 .. $#KNOWN) { $KNOWN_IDX{sprintf('%-4s', $KNOWN[$i])} = $i; }

sub slurp { my $f = shift; open(my $h, '<:raw', $f) or die "$f: $!\n"; local $/; my $d = <$h>; close $h; return $d; }
sub spew { my ($f, $d) = @_; open(my $h, '>:raw', $f) or die "$f: $!\n"; print $h $d; close $h or die "$f: $!\n"; }

# UIntBase128: 7 Bit je Byte, höchstwertige zuerst, Folgebit 0x80, ohne führende Null
sub base128 {
	my $v = shift;
	my @b = ($v & 0x7F);
	$v >>= 7;
	while ($v) { unshift @b, 0x80 | ($v & 0x7F); $v >>= 7; }
	die "UIntBase128 zu lang\n" if @b > 5;
	return pack('C*', @b);
}

my $ttf = slurp($in);
my ($flavor, $num) = unpack('N n', $ttf);
die "$in: keine TrueType-Schrift (0x" . sprintf('%08X', $flavor) . ")\n" unless $flavor == 0x00010000;

my %tables;
for my $i (0 .. $num - 1) {
	my ($tag, $sum, $off, $len) = unpack('a4 N N N', substr($ttf, 12 + 16 * $i, 16));
	die "$in: Tabelle $tag reicht über das Dateiende\n" if $off + $len > length($ttf);
	$tables{$tag} = substr($ttf, $off, $len);
}
die "$in: glyf ohne loca\n" if exists($tables{glyf}) != exists($tables{loca});

# Reihenfolge wie der Referenz-Encoder: nach Namen sortiert, loca direkt hinter glyf (Pflicht für Decoder)
my @order = grep { $_ ne 'loca' } sort keys %tables;
if (exists $tables{loca}) {
	my ($g) = grep { $order[$_] eq 'glyf' } 0 .. $#order;
	splice(@order, $g + 1, 0, 'loca');
}

my ($dir, $data, $sfnt_size) = ('', '', 12 + 16 * $num);
for my $tag (@order) {
	my $t = $tables{$tag};
	my $xform = ($tag eq 'glyf' || $tag eq 'loca') ? 3 : 0;   # 3 bzw. 0 = Null-Transformation
	if (exists $KNOWN_IDX{$tag}) { $dir .= pack('C', $KNOWN_IDX{$tag} | ($xform << 6)); }
	else { $dir .= pack('C a4', 63 | ($xform << 6), $tag); }
	$dir .= base128(length $t);
	$data .= $t;                                               # im Brotli-Strom ohne Füllbytes
	$sfnt_size += (length($t) + 3) & ~3;
}

# Brotli über den Befehl (Qualität 11, Fenster 2^24)
my $tmp = $out . '.tabellen';
spew($tmp, $data);
system('brotli', '-q', '11', '-w', '24', '-f', '-n', '-o', "$tmp.br", $tmp) == 0 or die "brotli fehlgeschlagen\n";
my $comp = slurp("$tmp.br");
system('brotli', '-d', '-f', '-n', '-o', "$tmp.prob", "$tmp.br") == 0 or die "brotli -d fehlgeschlagen\n";
my $back = slurp("$tmp.prob");
unlink $tmp, "$tmp.br", "$tmp.prob";
die "Brotli-Rückentpackung weicht ab\n" unless $back eq $data;

# Kopf (48 Byte), Verzeichnis, Daten, auf 4 Byte aufgefüllt
my $body_len = 48 + length($dir) + length($comp);
my $total = ($body_len + 3) & ~3;
my ($major, $minor) = unpack('n n', substr($tables{head}, 4, 4));   # fontRevision als Version
my $head = pack('a4 N N n n N N n n N N N N N', 'wOF2', $flavor, $total, $num, 0, $sfnt_size, length($comp),
	$major, $minor, 0, 0, 0, 0, 0);
spew($out, $head . $dir . $comp . ("\0" x ($total - $body_len)));
printf "%s: %d Tabellen, %d → %d Byte (%.0f %%)\n", $out =~ s{.*[/\\]}{}r, $num, length($ttf), $total, 100 * $total / length($ttf);
