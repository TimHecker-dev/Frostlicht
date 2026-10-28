shader_type canvas_item;
// Stimmung über allem: weiche dunkle Ränder (Vignette) und ganz leichter, ziehender Dunst.

uniform float vignette_strength : hint_range(0.0, 1.0) = 0.62;
uniform vec4 vignette_color : source_color = vec4(0.03, 0.05, 0.13, 1.0);
uniform float fog_amount : hint_range(0.0, 0.5) = 0.10;
uniform vec4 fog_color : source_color = vec4(0.78, 0.87, 1.0, 1.0);

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.0;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	float d = distance(UV, vec2(0.5));
	float va = smoothstep(0.32, 0.88, d) * vignette_strength;
	float fa = smoothstep(0.25, 0.85, fbm(UV * vec2(3.2, 2.0) + vec2(TIME * 0.018, TIME * 0.007))) * fog_amount;
	// Dunst liegt unten, Vignette darüber – zu einer Farbe mit einer Deckkraft verrechnet
	float a = va + fa * (1.0 - va);
	vec3 c = (vignette_color.rgb * va + fog_color.rgb * fa * (1.0 - va)) / max(a, 0.0001);
	COLOR = vec4(c, a);
}
