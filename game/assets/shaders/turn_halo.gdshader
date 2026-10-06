shader_type canvas_item;
// Schein von hinten für den Spieler am Zug (0.1.4, Vorbild docs/geraetetest/0.1.4/nutzer_dran_vorbild_strahlen.webp): ein
// Strahlenbündel aus der Mitte hinter Name und Fächer bzw. Hand, dazu ein weicher Lichthof. Nichts folgt der Kastenform
// (Nutzerwunsch 06.10.2026: kein Kasten, kein Rand); gerechnet wird in einer Ellipse um die Kastenmitte, und alles läuft vor dem
// Rand der Zeichenfläche weich auf null aus. Tag golden, Nacht bläulich schimmernd.
// Gezeichnet wird ein Rechteck um den Ursprung (Kastenmitte); gerechnet in lokalen Pixeln (VERTEX), nicht in UV.

uniform vec2 half_size = vec2(100.0, 40.0);   // halbe Kastengröße in Pixeln
uniform float corner = 18.0;                  // Eckenradius
uniform float reach = 70.0;                   // mittlere Strahlenlänge
uniform float night = 0.0;                    // 0 Tag (gold) … 1 Nacht (bläulich)
uniform float motion = 1.0;                   // 0 = steht still (Effekte reduziert)
uniform float strength = 1.0;                 // Ein-/Ausblenden
uniform float pad = 141.0;                    // Abstand Kasten → Rand der Zeichenfläche (TurnHalo._draw)

varying vec2 local;

void vertex() {
	local = VERTEX;
}

float hash1(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float pnoise(float x, float n) {
	float i = floor(x);
	float f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(hash1(mod(i, n)), hash1(mod(i + 1.0, n)), f);
}

void fragment() {
	vec2 ext = half_size + vec2(reach * 0.5);
	vec2 n = local / max(ext, vec2(1.0));          // elliptisch normiert: 1 = etwas außerhalb des Kastens
	float r = length(n);
	float ang = atan(n.y, n.x);
	float u = ang / TAU;
	float tm = TIME * motion;
	float base = pnoise(u * 28.0, 28.0);
	float w1 = sin(ang * 11.0 + tm * 0.9);
	float w2 = sin(ang * 17.0 - tm * 0.7 + 1.7);
	float w3 = sin(ang * 29.0 + tm * 1.3 + 4.2);
	float beam = smoothstep(0.32, 0.82, 0.45 * base + 0.55 * (0.5 + 0.22 * w1 + 0.16 * w2 + 0.12 * w3));
	float len = mix(0.5, 1.4, pnoise(u * 21.0 + 0.37, 21.0));       // Strahlenlänge über die Ellipse hinaus
	float rays = beam * smoothstep(0.25, 0.75, r) * (1.0 - smoothstep(0.85, 0.85 + len, r));
	float glow = exp(-pow(r / 0.9, 2.0));                           // Lichthof aus der Mitte
	vec2 to_edge = half_size + pad - abs(local);
	float edge_fade = smoothstep(0.0, pad * 0.7, min(to_edge.x, to_edge.y));
	float pulse = 0.82 + 0.18 * sin(tm * 3.4);

	vec3 ray_col = mix(vec3(1.0, 0.66, 0.08), vec3(0.58, 0.78, 1.0), night);
	vec3 core_col = mix(vec3(1.0, 0.92, 0.62), vec3(0.88, 0.95, 1.0), night);
	vec3 col = mix(ray_col, core_col, clamp(glow, 0.0, 1.0));
	float a = clamp(rays * pulse * 0.9 + glow * 0.6 * (0.9 + 0.1 * pulse), 0.0, 1.0) * edge_fade * strength;
	COLOR = vec4(col, a);
}
