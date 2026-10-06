shader_type canvas_item;
// Sanfte Lichtstrahlen um einen Punkt (Rundenende, 0.1.4): dieselbe Art wie die Sonnenstrahlen des Tischs (table_background):
// glattes Rauschen über den Winkel (verschiedene Breiten), drei langsam wandernde Wellen, je Strahl eigene Länge, weicher Ausklang.
// Keine Keile, nichts dreht sich. Gerechnet in lokalen Pixeln um den Ursprung (VERTEX).

uniform vec4 tint : source_color = vec4(1.0, 0.86, 0.5, 0.5);
uniform float radius = 600.0;
uniform float inner = 60.0;
uniform float motion = 1.0;

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
	float d = length(local);
	float ang = atan(local.y, local.x);
	float u = ang / TAU;
	float tm = TIME * motion;
	float base = pnoise(u * 34.0, 34.0);
	float w1 = sin(ang * 19.0 + 0.8 + tm * 0.035);
	float w2 = sin(ang * 31.0 + 2.6 - tm * 0.026);
	float w3 = sin(ang * 53.0 + 4.1 + tm * 0.017);
	float beam = smoothstep(0.40, 0.85, 0.5 * base + 0.5 * (0.5 + 0.24 * w1 + 0.16 * w2 + 0.10 * w3));
	float reach = radius * mix(0.35, 1.0, pnoise(u * 29.0 + 0.71, 29.0));
	float along = smoothstep(inner * 0.5, inner * 2.5, d) * exp(-d / reach) * smoothstep(radius, radius * 0.7, d);
	float halo = exp(-d / (inner * 2.0)) * 0.35;
	float breathe = 0.9 + 0.1 * sin(tm * 0.42);
	COLOR = vec4(tint.rgb, tint.a * clamp(beam * along * breathe * 1.4 + halo, 0.0, 1.0));
}
