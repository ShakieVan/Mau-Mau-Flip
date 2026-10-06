shader_type canvas_item;
// Richtungs-Plattform (DirectionRing, game/scripts/ui/direction_ring.gd): flacher, dicker Ring, schräg von oben gesehen.
// Ein Netz mit fünf Teilen, codiert in UV.y (Teil * 2 + v, v = 0..1 quer bzw. von oben nach unten):
//   0 Oberseite (v innen → außen, UV.x = Lauf in Zellen)   1 Außenkante (v oben → unten)   2 Innenkante (Bühnenloch)
//   3 Schatten außen (v Kontakt → weich)                     4 Schatten innen
// Tag: dicker Karton in Creme, Druckfarben-Kontur, Prägelinie, Winkel in Druckfarbe. Nacht: dunkles Glas, Neonkante,
// leuchtende Winkel. Keine Schleifen, kein SCREEN_TEXTURE; Kanten weich über fwidth (kein MSAA im Compatibility-Renderer).

uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform vec4 neon : source_color = vec4(0.604, 0.525, 1.0, 1.0);
uniform float flash = 0.0;          // einmaliges Aufglimmen (Richtungswechsel, Flip zur Nacht)
uniform float phase = 0.0;          // Fluss in Zellen
uniform float bend = 1.0;           // Richtung und Form der Winkel: 1 = vorwärts, 0 = Balken, -1 = rückwärts (Überschwinger > 1)
uniform float group = 5.0;          // Zellen je Gruppe (davon 3 mit Winkel)
uniform float cell_px = 36.0;       // Zelllänge in Weltpixeln (längs)
uniform float band_px = 64.0;       // Bandbreite in Weltpixeln (quer)
uniform float wall_px = 14.0;       // Kantenhöhe in Pixeln
uniform vec2 ell = vec2(400.0, 180.0);   // Halbachsen der Bandmitte auf dem Bildschirm (für die Lichtrichtung)
uniform vec2 ell_center = vec2(0.0);    // Mitte dieser Halbachsen
uniform float square = 2.5;         // Exponent der Superellipse (wie DirectionRing.SQUARE)
uniform vec2 quiet = vec2(95.0, 60.0);   // vorn in der Mitte liegt die Hinweisleiste: Winkel dort gedämpft (halbe Breite, Übergang)

varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

float seg(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
	return length(pa - ba * h);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// weiche Linie der Breite w (px) um den Abstand d (px); aa = Pixelbreite
float stroke(float d, float w, float aa) {
	return 1.0 - smoothstep(w * 0.5 - aa * 0.5, w * 0.5 + aa * 0.5, abs(d));
}

void fragment() {
	float part = floor(UV.y * 0.5);
	float v = UV.y - part * 2.0;
	float nt = smoothstep(0.0, 1.0, night);
	// Bildschirmnormale der Superellipse (außen), Licht von oben links (Sonne)
	vec2 q = lp - ell_center;
	vec2 nrm = normalize(sign(q) * pow(abs(q) / ell, vec2(square - 1.0)) / ell + vec2(0.0, 1e-6));
	vec2 light = normalize(vec2(-0.55, -0.83));
	float lit = dot(nrm, light);                    // +1 zur Sonne, −1 abgewandt
	vec3 ink = vec3(0.129, 0.106, 0.173);
	vec3 nc = neon.rgb;
	float glow_k = 1.0 + 0.9 * flash;
	vec4 col = vec4(0.0);

	if (part < 0.5) {
		// ---------------- Oberseite
		float y = v * band_px;                       // 0 innen … band_px außen
		float aa = max(fwidth(y), 1e-3);
		float edge_in = y;
		float edge_out = band_px - y;
		float mask = smoothstep(0.0, aa, edge_in) * smoothstep(0.0, aa, edge_out);
		// Winkel: Zellkoordinaten in Weltpixeln
		float x = UV.x - phase;
		float ci = floor(x);
		vec2 p = vec2((fract(x) - 0.5) * cell_px, (v - 0.5) * band_px);
		float b = clamp(bend, -1.4, 1.4);
		float hy = band_px * 0.25;
		float hx = hy * 0.78 * b;
		vec2 tip = vec2(hx * 0.5, 0.0);
		float sw = max(band_px * 0.1, 3.4);           // Strichstärke
		float d = min(seg(p, tip, vec2(-hx * 0.5, hy)), seg(p, tip, vec2(-hx * 0.5, -hy))) - sw * 0.5;
		float daa = max(fwidth(d), 1e-3);
		float g = mod(ci, group);
		float on = step(g, 2.0);
		float k = mix(2.0 - g, g, smoothstep(-0.3, 0.3, b)) * 0.5;   // 0 hinten … 1 vorn in Laufrichtung
		float inten = on * mix(0.45, 1.0, k);
		inten *= mix(0.35, 1.0, min(smoothstep(quiet.x - quiet.y * 0.5, quiet.x + quiet.y * 0.5, abs(lp.x)) + step(lp.y, ell_center.y), 1.0));
		float chev = (1.0 - smoothstep(-daa * 0.5, daa * 0.5, d)) * inten;

		// Tag: Karton (Ränder hell, dazwischen eine leicht vertiefte Laufbahn)
		vec3 card = mix(vec3(1.0, 0.98, 0.935), vec3(0.965, 0.925, 0.845), smoothstep(-0.9, 0.9, -lit) * 0.8);
		card *= 0.985 + 0.03 * hash(floor(lp * 0.75));
		float rim = band_px * 0.2;
		float ch_in = rim;
		float ch_out = band_px - rim;
		float in_ch = smoothstep(ch_in - aa * 0.5, ch_in + aa * 0.5, y) * (1.0 - smoothstep(ch_out - aa * 0.5, ch_out + aa * 0.5, y));
		card = mix(card, card * vec3(0.925, 0.86, 0.74), in_ch);                       // Sand wie die Papierkante
		// Fase außen und innen (dicker Karton, Licht von oben links)
		float bev = 5.0;
		float bo = 1.0 - smoothstep(0.0, bev, edge_out);
		float bi = 1.0 - smoothstep(0.0, bev * 0.8, edge_in);
		card += vec3(0.05) * bo * lit - vec3(0.06) * bo * max(-lit, 0.0);
		card += vec3(0.04) * bi * (-lit) - vec3(0.05) * bi * max(lit, 0.0);
		// Prägekanten der Laufbahn: dunkle Linie an der Stufe, Licht auf dem Rand daneben
		card = mix(card, ink, 0.26 * (stroke(y - ch_in, 1.2, aa) + stroke(y - ch_out, 1.2, aa)));
		card = mix(card, vec3(1.0, 0.995, 0.97), 0.6 * (stroke(y - ch_in + 1.4, 1.1, aa) + stroke(y - ch_out - 1.4, 1.1, aa)));
		// Druckfarben-Kontur an beiden Rändern
		float contour = stroke(edge_out - 0.9, 2.0, aa) + stroke(edge_in - 0.8, 1.7, aa) * 0.85;
		card = mix(card, ink, clamp(contour, 0.0, 1.0) * 0.9);
		// Winkel in Druckfarbe mit Lichtkante (geprägt), beim Aufglimmen warm hinterlegt
		float halo = (1.0 - smoothstep(0.0, 2.2, d - 0.6)) * inten;
		card = mix(card, vec3(1.0, 0.99, 0.95), halo * 0.55 * (1.0 - chev));
		card = mix(card, vec3(1.0, 0.86, 0.42), flash * 0.4 * in_ch);                 // Aufglimmen: Laufbahn warm
		card = mix(card, vec3(1.0, 0.80, 0.25), flash * 0.7 * (1.0 - smoothstep(0.0, 8.0, d)) * on);
		card = mix(card, ink, chev * 0.92);
		vec4 day = vec4(card, mask);

		// Nacht: dunkles Glas (Laufbahn dunkler), Neonkanten außen und innen
		vec3 glass = mix(vec3(0.090, 0.106, 0.235), vec3(0.059, 0.067, 0.157), v);
		glass = mix(glass, glass * 0.62, in_ch);
		glass += nc * 0.16 * flash * in_ch;
		glass += vec3(0.10, 0.11, 0.22) * smoothstep(0.2, 1.0, lit) * (1.0 - in_ch) * 0.5;   // Spiegelung hinten links
		glass += nc * 0.07 * (1.0 - smoothstep(0.0, 16.0, edge_out));                     // Licht der Neonkante im Glas
		float neon_o = stroke(edge_out - 2.2, 2.4, aa);
		float neon_og = exp(-max(edge_out - 2.2, 0.0) / 7.0);
		float neon_i = stroke(edge_in - 1.8, 1.6, aa);
		float neon_ig = exp(-max(edge_in - 1.8, 0.0) / 5.0);
		float neon_c = stroke(y - ch_in, 1.0, aa) + stroke(y - ch_out, 1.0, aa);
		vec3 glass_c = glass;
		glass_c += nc * (0.28 * neon_og + 0.16 * neon_ig) * glow_k;
		glass_c = mix(glass_c, nc * 0.75, neon_c * 0.35);
		glass_c = mix(glass_c, mix(nc, vec3(1.0), 0.35), clamp(neon_o * 0.95 + neon_i * 0.6, 0.0, 1.0));
		float cg = exp(-max(d, 0.0) / 5.5) * inten;
		glass_c += nc * cg * 0.55 * glow_k;
		glass_c = mix(glass_c, mix(nc, vec3(1.0), 0.45 + 0.25 * flash), chev);
		vec4 nightc = vec4(glass_c, mask * 0.94);
		col = mix(day, nightc, nt);
	} else if (part < 1.5) {
		// ---------------- Außenkante (sichtbar vorn)
		float y = v * wall_px;
		float aa = max(fwidth(y), 1e-3);
		float mask = smoothstep(0.0, aa, wall_px - y);
		float side = clamp(-lit * 0.6 + 0.4, 0.0, 1.0);   // abgewandt dunkler
		vec3 board = mix(vec3(0.878, 0.784, 0.612), vec3(0.749, 0.643, 0.471), side);
		board *= 1.0 - 0.14 * v;
		board = mix(board, board * 0.86, stroke(y - wall_px * 0.4, 1.0, aa) * 0.7 + stroke(y - wall_px * 0.7, 1.0, aa) * 0.7);   // Kartonlagen
		board = mix(board, vec3(1.0, 0.98, 0.93), stroke(y - 1.8, 1.8, aa) * 0.8);           // Glanzrand
		board = mix(board, ink, stroke(wall_px - y - 0.9, 2.0, aa) * 0.85);                   // Kontur unten
		vec4 day = vec4(board, mask);
		vec3 gw = mix(vec3(0.055, 0.067, 0.16), vec3(0.027, 0.031, 0.086), v);
		gw = mix(gw, gw * 0.7, side * 0.5);
		gw += nc * 0.22 * exp(-y / 3.0) * glow_k;
		gw = mix(gw, mix(nc, vec3(1.0), 0.3), stroke(y - 1.2, 1.6, aa) * 0.8);                 // Neon-Glanzrand oben
		gw += nc * 0.18 * stroke(wall_px - y - 1.0, 1.4, aa) * glow_k;                           // Spiegelung am Fuß
		vec4 nightc = vec4(gw, mask);
		col = mix(day, nightc, nt);
	} else if (part < 2.5) {
		// ---------------- Innenkante (sichtbar hinten im Bühnenloch)
		float y = v * wall_px;
		float aa = max(fwidth(y), 1e-3);
		float mask = smoothstep(0.0, aa, wall_px - y);
		vec3 board = mix(vec3(0.80, 0.70, 0.53), vec3(0.66, 0.565, 0.41), v);
		board *= 0.92 + 0.08 * clamp(lit, 0.0, 1.0);
		board = mix(board, ink, stroke(wall_px - y - 0.8, 1.7, aa) * 0.7);
		vec4 day = vec4(board, mask);
		vec3 gw = mix(vec3(0.035, 0.043, 0.11), vec3(0.02, 0.024, 0.07), v);
		gw += nc * 0.10 * exp(-(wall_px - y) / 3.0) * glow_k;
		vec4 nightc = vec4(gw, mask);
		col = mix(day, nightc, nt);
	} else if (part < 3.5) {
		// ---------------- weicher Schatten außen (nach unten rechts, von der Sonne weg)
		float f = 1.0 - v;
		float dir = smoothstep(-0.75, 0.55, nrm.y + 0.35 * nrm.x);
		float a = f * f * (0.12 + 0.24 * dir);
		vec4 day = vec4(ink, a);
		vec4 nightc = vec4(mix(vec3(0.0), nc * 0.6, 0.35 + 0.25 * flash), f * f * (0.22 + 0.16 * dir));
		col = mix(day, nightc, nt);
	} else {
		// ---------------- Schatten innen (hinten ins Loch geworfen)
		float f = 1.0 - v;
		float dir = smoothstep(0.35, -0.75, nrm.y);
		float a = f * f * 0.16 * dir;
		vec4 day = vec4(ink, a);
		vec4 nightc = vec4(0.0, 0.0, 0.02, f * f * 0.28 * dir);
		col = mix(day, nightc, nt);
	}
	COLOR = col;
}
