shader_type canvas_item;
// Tischhintergrund (Modul F1b, docs/recherche/06_hand_ux_effekte.md 4.4): tageszeit 0 = Tag (Papier mit Sonnenstrahlen und
// Korn, Sonne oben links), 1 = Nacht (tiefblau, Mond oben rechts, Sterne). Dazwischen Dämmerung: Die Sonne sinkt hinter den
// Tischrand, der Mond steigt. Ein einziger Vollbilddurchgang, keine Schleifen, kein SCREEN_TEXTURE (Compatibility/Web).

uniform float tageszeit : hint_range(0.0, 1.0) = 0.0;
uniform vec2 size = vec2(1600.0, 720.0);     // Pixelgröße der Fläche
uniform vec2 center = vec2(800.0, 320.0);    // Tischmitte in Pixeln
uniform float motion = 1.0;                  // 0 = keine Daueranimation (Effekte reduziert)

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 px = UV * size;
	float t = smoothstep(0.0, 1.0, tageszeit);
	vec2 d = (px - center) / vec2(size.x * 0.62, size.y * 0.78);
	float r = length(d);

	// --- Tag: warmes Papier, Rand dunkler
	vec3 day = mix(vec3(0.961, 0.925, 0.862), vec3(0.862, 0.784, 0.659), smoothstep(0.2, 1.25, r));
	vec2 sun = vec2(size.x * 0.07, size.y * (0.03 + 1.05 * t));
	vec2 sv = px - sun;
	float ang = atan(sv.y, sv.x);
	float rays = smoothstep(-0.25, 0.25, sin(ang * 18.0 + TIME * 0.04 * motion));
	float sd = length(sv);
	day *= 1.0 - 0.05 * rays * smoothstep(60.0, 260.0, sd);
	vec3 sun_col = vec3(1.0, 0.80, 0.22);
	day += sun_col * 0.22 * exp(-sd / 190.0);
	day = mix(day, sun_col, smoothstep(66.0, 62.0, sd));
	day = mix(day, vec3(1.0, 0.90, 0.55), smoothstep(52.0, 40.0, sd) * 0.6);
	day *= 0.982 + 0.036 * hash(floor(px / 2.0));

	// --- Nacht: Verlauf wie im Entwurf (#26305A → #171C38 → #0C0F22)
	vec3 night = mix(vec3(0.149, 0.188, 0.353), vec3(0.090, 0.110, 0.220), smoothstep(0.0, 0.55, r));
	night = mix(night, vec3(0.047, 0.059, 0.133), smoothstep(0.55, 1.15, r));
	vec2 cell = floor(px / 28.0);
	float h = hash(cell);
	vec2 sp = (cell + vec2(0.2 + 0.6 * hash(cell + 1.3), 0.2 + 0.6 * hash(cell + 7.1))) * 28.0;
	float star = step(0.86, h) * smoothstep(1.7, 0.2, length(px - sp));
	float tw = 0.65 + 0.35 * sin(TIME * (0.8 + h * 1.6) * motion + h * 40.0);
	night += vec3(0.86, 0.86, 1.0) * star * tw * smoothstep(0.25, 0.75, r) * smoothstep(0.35, 0.9, t);
	vec2 moon = vec2(size.x * 0.94, size.y * (1.12 - 1.04 * t));
	float md = length(px - moon);
	float md2 = length(px - moon - vec2(17.0, -12.0));
	float crescent = smoothstep(40.0, 37.5, md) * smoothstep(31.0, 34.0, md2);
	night += vec3(0.62, 0.56, 1.0) * 0.16 * exp(-md / 150.0);
	night = mix(night, vec3(0.957, 0.941, 1.0), crescent);

	// --- Dämmerung in der Mitte des Übergangs
	vec3 dusk = mix(vec3(0.95, 0.60, 0.45), vec3(0.33, 0.25, 0.47), clamp(UV.y * 1.15, 0.0, 1.0));
	float dusk_w = 1.0 - abs(t * 2.0 - 1.0);
	vec3 col = mix(day, night, t);
	col = mix(col, dusk * mix(1.0, 0.7, clamp(r, 0.0, 1.0)), dusk_w * 0.6);
	COLOR = vec4(col, 1.0);
}
