shader_type canvas_item;
render_mode blend_add;
// Polarlicht-Schimmer über der Frosthöhle: langsam ziehende, weiche Farbbänder (additiv, sehr dezent).

uniform float intensity : hint_range(0.0, 1.0) = 0.16;
uniform vec4 color_a : source_color = vec4(0.25, 1.0, 0.65, 1.0);
uniform vec4 color_b : source_color = vec4(0.55, 0.35, 1.0, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
			mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * 0.05;
	float band = noise(vec2(uv.x * 2.6 + t, uv.y * 0.9 - t * 0.6)) * 0.65 + noise(vec2(uv.x * 5.2 - t * 1.3, uv.y * 1.7 + t)) * 0.35;
	float curtain = smoothstep(0.38, 0.85, band) * (0.65 + 0.35 * sin(uv.x * 7.0 + TIME * 0.35));
	vec3 col = mix(color_a.rgb, color_b.rgb, clamp(uv.y + 0.35 * sin(TIME * 0.18 + uv.x * 3.0), 0.0, 1.0));
	COLOR = vec4(col * curtain * intensity, 1.0);
}
