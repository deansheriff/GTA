shader_type canvas_item;
// Outfits (M10): recolours a hero's shirt in the painted walk sheet. Only Tunde's red shirt
// sits in a hue range that skin tones never reach (tools/art/hue_stats.mjs), so only his
// sheet uses it; everyone gets headwear drawn on top instead (actors/walker.gd).

uniform vec4 tint : source_color = vec4(0.0);
uniform float hue_center = 0.0; // red
uniform float hue_width = 0.045;
uniform float min_sat = 0.5;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (tint.a > 0.0) {
		vec3 hsv = rgb2hsv(c.rgb);
		float dh = abs(fract(hsv.x - hue_center + 0.5) - 0.5);
		float m = (1.0 - smoothstep(hue_width * 0.6, hue_width, dh)) * smoothstep(min_sat - 0.1, min_sat, hsv.y);
		c.rgb = mix(c.rgb, tint.rgb * (0.3 + 0.9 * hsv.z), m);
	}
	COLOR = c * COLOR;
}
