/*
	Inspired by: Procedural Electric Current Shader by Yui Kinomoto (@arlez80)
	Adapted for Dust Diesel car EMP overlay effect.
*/
shader_type spatial;
render_mode unshaded, blend_add, cull_back;

uniform vec4 light_color : source_color = vec4(0.22, 0.45, 0.95, 0.55);
uniform vec4 arc_color : source_color = vec4(0.60, 0.85, 1.0, 1.0);

uniform vec2 seed = vec2(0.0, 0.0);
uniform float speed : hint_range(0.1, 30.0) = 5.1;
uniform float random_scale : hint_range(0.1, 24.0) = 4.6;
uniform float electro_scale : hint_range(0.1, 48.0) = 11.459;
uniform float intensity : hint_range(0.0, 3.0) = 1.0;

vec2 random2(vec2 pos) {
	return fract(
		sin(
			vec2(
				dot(pos, vec2(12.9898, 78.233)),
				dot(pos, vec2(-148.998, -65.233))
			)
		) * 43758.5453
	);
}

float value_noise(vec2 pos) {
	vec2 p = floor(pos);
	vec2 f = fract(pos);

	float v00 = random2(p + vec2(0.0, 0.0)).x;
	float v10 = random2(p + vec2(1.0, 0.0)).x;
	float v01 = random2(p + vec2(0.0, 1.0)).x;
	float v11 = random2(p + vec2(1.0, 1.0)).x;

	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(v00, v10, u.x), mix(v01, v11, u.x), u.y);
}

float noise_tex(vec2 p) {
	return (
		value_noise(p * 0.984864) * 0.5
		+ value_noise(p * 2.543) * 0.25
		+ value_noise(p * 9.543543) * 0.125
		+ value_noise(p * 21.65436) * 0.0625
		+ value_noise(p * 42.0) * 0.03125
		+ value_noise(p * 87.135148) * 0.015625
		+ value_noise(p * 340.66534654) * 0.0078125
	);
}

void fragment() {
	vec2 uv = seed + vec2(
		UV.x + cos(TIME * 1321.21 + UV.y * 348.513) * 0.004,
		UV.y + sin(TIME * 421.21 + UV.x * 314.513) * 0.0016
	);

	float wave = abs(cos(TIME * speed + noise_tex(uv * random_scale) * electro_scale));
	float arc = 1.0 - clamp((wave - 0.08) * 20.0, 0.0, 1.0);
	float pulse = 1.0 - clamp((wave - 0.3) * 3.0, 0.0, 1.0);

	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 2.5);
	float alpha = clamp((pulse * 0.75 + fresnel * 0.35) * intensity, 0.0, 1.0);

	ALBEDO = mix(light_color.rgb, arc_color.rgb, arc);
	ALPHA = alpha;
}
