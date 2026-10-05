shader_type canvas_item;
// Roter Randpuls für Strafe/Erwischt (ein einzelner Puls, kein Blinken; WCAG 2.3.1): nur der Rand, die Mitte bleibt frei.
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.898, 0.282, 0.302, 1.0);
uniform vec2 size = vec2(1600.0, 720.0);

void fragment() {
	vec2 px = UV * size;
	float edge = min(min(px.x, size.x - px.x), min(px.y, size.y - px.y));
	float v = 1.0 - smoothstep(0.0, 120.0, edge);
	COLOR = vec4(tint.rgb, tint.a * intensity * v * v);
}
