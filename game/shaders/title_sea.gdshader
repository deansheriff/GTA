shader_type canvas_item;
// The aerial title (ui/title_aerial.gd): the baked island with living water. All water is painted
// here from the shore-distance map (R = distance from land, G = open sea): shallow turquoise to
// deep blue, ripples and glints, swells rolling in and surf breaking white on every beach.
// The same shader paints the open ocean around the map (is_map = 0) so the two meet seamlessly.

uniform sampler2D shore_tex : filter_linear;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec2 bake_size = vec2(3072.0, 2112.0);
uniform vec2 origin = vec2(0.0);
uniform float is_map = 1.0;

varying vec2 wpos;

void vertex() {
	wpos = VERTEX + origin;
}

void fragment() {
	vec2 p = wpos;
	float t = TIME;
	vec3 sh = is_map > 0.5 ? texture(shore_tex, p / bake_size).rgb : vec3(1.0, 1.0, 0.0);
	float d = sh.r;
	float sea = sh.g;
	vec3 base = is_map > 0.5 ? texture(TEXTURE, UV).rgb : vec3(0.0);
	float water = is_map > 0.5 ? smoothstep(0.03, 0.08, d) : 1.0;

	// Depth colour: open sea vs the calmer, greener lagoon.
	float depth = smoothstep(0.06, 0.75, d);
	vec3 sea_c = mix(vec3(0.16, 0.64, 0.68), vec3(0.05, 0.26, 0.46), depth);
	vec3 lag_c = mix(vec3(0.20, 0.52, 0.50), vec3(0.08, 0.32, 0.38), depth);
	vec3 wc = mix(lag_c, sea_c, sea);

	// Ripples and sun glints.
	float n1 = texture(noise_tex, p / 260.0 + vec2(t * 0.010, t * 0.006)).r;
	float n2 = texture(noise_tex, p / 170.0 - vec2(t * 0.008, -t * 0.011)).r;
	float rip = n1 * n2 * 2.0;
	wc *= 0.93 + 0.12 * rip;
	wc += vec3(0.75, 0.8, 0.7) * smoothstep(1.25, 1.5, rip) * 0.22;

	// Swells: thin crests marching toward the shore (open sea only).
	float nb = texture(noise_tex, p / 420.0 + vec2(t * 0.004, t * 0.002)).r;
	float phase = d * 30.0 + t * 1.25 + nb * 5.0;
	float crest = pow(0.5 + 0.5 * sin(phase), 16.0);
	float near_shore = (1.0 - smoothstep(0.1, 0.5, d)) * sea;
	wc = mix(wc, vec3(0.92, 0.97, 0.96), crest * near_shore * 0.55);

	// Surf: foam breaking on the beach, surging each time a swell lands.
	float surge = pow(0.5 + 0.5 * sin(t * 1.25 + nb * 5.0 + 2.6), 3.0);
	float band = 1.0 - smoothstep(0.05, 0.10 + 0.07 * surge, d);
	float foam_n = texture(noise_tex, p / 40.0 + vec2(t * 0.03, t * 0.01)).r;
	float surf = band * smoothstep(0.3, 0.62, foam_n + 0.25 * surge) * mix(0.35, 1.0, sea);
	wc = mix(wc, vec3(0.97, 0.98, 0.96), clamp(surf, 0.0, 1.0) * 0.9);

	vec3 col = mix(base, wc, water);
	// Distant cloud shadows drifting over land and sea.
	float cs = texture(noise_tex, p / 1100.0 + vec2(t * 0.010, t * 0.004)).r;
	col *= 1.0 - 0.2 * smoothstep(0.58, 0.78, cs);
	COLOR = vec4(col, 1.0);
}
