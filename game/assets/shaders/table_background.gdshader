shader_type canvas_item;
// Tischhintergrund (Modul F1b, docs/recherche/06_hand_ux_effekte.md 4.4): tageszeit 0 = Tag (Papier mit Sonnenstrahlen und
// Korn, Sonne oben links), 1 = Nacht (tiefblau, Mond oben rechts, Sterne). Dazwischen Dämmerung: Die Sonne sinkt hinter den
// Tischrand, der Mond steigt. Ein einziger Vollbilddurchgang, keine Schleifen, kein SCREEN_TEXTURE (Compatibility/Web).
//
// Sonnenstrahlen („Licht durch Dunst“, Kontrollbilder docs/module/optik_strahlen_*.png): keine gleich breiten Keile, sondern ein Strahlenfeld
// aus glattem Rauschen über den Winkel (unterschiedliche Breiten) und drei Sinuswellen mit eigener Anzahl, die sehr langsam
// gegeneinander wandern (die Strahlen atmen, nichts dreht sich wie ein Rad). Jeder Strahl hat eine eigene Länge und klingt
// mit exp() weich in die Papierfarbe aus; am Sonnenrand ein weicher Lichthof. Alle Winkelfunktionen sind 2π-periodisch
// (keine Naht am Sprung von atan), alle Zeitfrequenzen passen in die Godot-Zeitschleife von 3600 s (kein Sprung).

uniform float tageszeit : hint_range(0.0, 1.0) = 0.0;
uniform vec2 size = vec2(1600.0, 720.0);     // Pixelgröße der Fläche
uniform vec2 center = vec2(800.0, 320.0);    // Tischmitte in Pixeln
uniform float motion = 1.0;                  // 0 = keine Daueranimation (Effekte reduziert): Strahlen stehen still
uniform float calm = 0.0;                    // 1 = ruhige Variante (großer Modus, Beta 1.1.1): keine Strahlen, kaum Sterne, mehr Kontrast

const float HOUR = 0.00174532925;            // 2π / 3600 s: Zeitfrequenzen sind Vielfache davon

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Ganzzahl-Hash ohne sin (günstig, stabil für kleine ganze Zahlen)
float hash1(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

// Glattes Wertrauschen über x, periodisch mit n Zellen
float pnoise(float x, float n) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash1(mod(i, n)), hash1(mod(i + 1.0, n)), f);
}

void fragment() {
	vec2 px = UV * size;
	float t = smoothstep(0.0, 1.0, tageszeit);
	float sc = max(size.x / 1600.0, size.y / 720.0);
	vec2 d = (px - center) / vec2(size.x * 0.62, size.y * 0.78);
	float r = length(d);
	float tm = TIME * motion;

	// Tag und Nacht werden nur berechnet, solange sie sichtbar sind (einheitliche Verzweigung über die Uniform: am Tag
	// keine Sterne, nachts keine Strahlen).
	vec3 day = vec3(0.0);
	if (t < 1.0) {
		// --- Tag: warmes Papier, Rand dunkler
		day = mix(vec3(0.961, 0.925, 0.862), vec3(0.862, 0.784, 0.659), smoothstep(0.2, 1.25, r));
		vec2 sun = vec2(size.x * 0.07, size.y * (0.03 + 1.05 * t));
		vec2 sv = px - sun;
		float sd = length(sv);
		float ang = atan(sv.y, sv.x);
		float u = ang / TAU;

		// Strahlenfeld: unregelmäßige Grundstruktur (steht) + drei langsam wandernde Wellen (atmen)
		float base = pnoise(u * 34.0, 34.0);
		float w1 = sin(ang * 19.0 + 0.8 + tm * HOUR * 20.0);
		float w2 = sin(ang * 31.0 + 2.6 - tm * HOUR * 15.0);
		float w3 = sin(ang * 53.0 + 4.1 + tm * HOUR * 10.0);
		float beam = smoothstep(0.40, 0.85, 0.5 * base + 0.5 * (0.5 + 0.24 * w1 + 0.16 * w2 + 0.10 * w3));
		// Länge je Strahl verschieden, Anfang im Lichthof, Ende als langer weicher Ausklang
		float reach = mix(380.0, 1100.0, pnoise(u * 29.0 + 0.71, 29.0)) * sc;
		float along = smoothstep(50.0 * sc, 210.0 * sc, sd) * exp(-sd / reach);
		float zone = exp(-sd / (760.0 * sc));
		float breathe = 0.9 + 0.1 * sin(tm * HOUR * 240.0);          // 15 s
		float lit = beam * along * (1.0 - calm);
		day *= 1.0 - zone * (1.0 - lit) * vec3(0.032, 0.042, 0.056);  // zwischen den Strahlen eine Spur warmer Dunst-Schatten
		day = mix(day, vec3(1.0, 0.86, 0.50), lit * breathe * 0.5);  // Strahlen: goldenes Licht

		day = mix(day, vec3(0.972, 0.948, 0.900), calm * 0.75);  // ruhig: glattes helles Papier, die Sonne bleibt
		// Sonne mit weichem Lichthof
		vec3 sun_col = vec3(1.0, 0.80, 0.22);
		day += sun_col * 0.16 * exp(-sd / (150.0 * sc));
		day += sun_col * 0.10 * exp(-max(sd - 64.0, 0.0) / 34.0);
		day = mix(day, sun_col, smoothstep(66.0, 62.0, sd));
		day = mix(day, vec3(1.0, 0.90, 0.55), smoothstep(52.0, 40.0, sd) * 0.6);
		day *= 0.982 + 0.036 * hash(floor(px / 2.0)) * (1.0 - calm);
	}

	vec3 night = vec3(0.0);
	if (t > 0.0) {
		// --- Nacht: Verlauf wie im Entwurf (#26305A → #171C38 → #0C0F22)
		night = mix(vec3(0.149, 0.188, 0.353), vec3(0.090, 0.110, 0.220), smoothstep(0.0, 0.55, r));
		night = mix(night, vec3(0.047, 0.059, 0.133), smoothstep(0.55, 1.15, r));
		vec2 cell = floor(px / 28.0);
		float h = hash(cell);
		vec2 sp = (cell + vec2(0.2 + 0.6 * hash(cell + 1.3), 0.2 + 0.6 * hash(cell + 7.1))) * 28.0;
		float star = step(0.86, h) * smoothstep(1.7, 0.2, length(px - sp));
		float tw = 0.65 + 0.35 * sin(tm * (0.8 + h * 1.6) + h * 40.0);
		star *= 1.0 - calm * 0.85;
		night += vec3(0.86, 0.86, 1.0) * star * tw * smoothstep(0.25, 0.75, r) * smoothstep(0.35, 0.9, t);
		vec2 moon = vec2(size.x * 0.94, size.y * (1.12 - 1.04 * t));
		float md = length(px - moon);
		float md2 = length(px - moon - vec2(17.0, -12.0));
		float crescent = smoothstep(40.0, 37.5, md) * smoothstep(31.0, 34.0, md2);
		// Mondschein: enger Schein und weiter, sehr schwacher Dunst
		night += vec3(0.62, 0.56, 1.0) * (0.16 * exp(-md / 150.0) + 0.05 * exp(-md / (480.0 * sc)));
		night = mix(night, vec3(0.055, 0.066, 0.150), calm * 0.55 * (1.0 - crescent));  // ruhig: dunkler, gleichmäßiger Grund
		night = mix(night, vec3(0.957, 0.941, 1.0), crescent);
	}

	// --- Dämmerung in der Mitte des Übergangs
	vec3 dusk = mix(vec3(0.95, 0.60, 0.45), vec3(0.33, 0.25, 0.47), clamp(UV.y * 1.15, 0.0, 1.0));
	float dusk_w = 1.0 - abs(t * 2.0 - 1.0);
	vec3 col = mix(day, night, t);
	col = mix(col, dusk * mix(1.0, 0.7, clamp(r, 0.0, 1.0)), dusk_w * 0.6);
	COLOR = vec4(col, 1.0);
}
