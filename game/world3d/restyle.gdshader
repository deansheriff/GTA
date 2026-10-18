// Restyle (D-023): gives a shared Meshy person a new look without new art. Clothing colours are
// hue-shifted and re-toned; skin tones (warm browns) are left alone so faces stay natural.
shader_type spatial;

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float hue = 0.0; // 0..1 turn of the colour wheel
uniform float sat = 1.0;
uniform float val = 1.0;
uniform vec3 tint : source_color = vec3(1.0); // for greys and blacks, which have no hue to shift
uniform float tint_mix = 0.0;

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

void fragment() {
	vec4 c = texture(tex, UV);
	vec3 h = rgb2hsv(c.rgb);
	bool skin = h.x > 0.015 && h.x < 0.11 && h.y > 0.2 && h.y < 0.78 && h.z < 0.72;
	if (!skin) {
		h.x = fract(h.x + hue);
		h.y = clamp(h.y * sat, 0.0, 1.0);
		h.z = clamp(h.z * val, 0.0, 1.0);
	}
	vec3 rgb = hsv2rgb(h);
	if (!skin) {
		rgb = mix(rgb, rgb * tint * 1.6, tint_mix);
	}
	ALBEDO = rgb;
	ROUGHNESS = 0.8;
}
