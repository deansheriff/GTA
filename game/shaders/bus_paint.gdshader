shader_type canvas_item;
// Bus paint (M10): recolours only the yellow danfo body of the painted art, keeping its shading,
// ink lines, glass, wheels and roof rack. paint.a = 0 leaves the art as painted.

uniform vec4 paint : source_color = vec4(0.0);

vec3 rgb2hsv(vec3 c) {
	vec4 K = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, K.wz), vec4(c.gb, K.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + 1e-10)), d / (q.x + 1e-10), q.x);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (paint.a > 0.0) {
		vec3 hsv = rgb2hsv(c.rgb);
		// Danfo yellow: hue ~0.10–0.17, saturated.
		float body = smoothstep(0.06, 0.09, hsv.x) * (1.0 - smoothstep(0.17, 0.2, hsv.x)) * smoothstep(0.35, 0.5, hsv.y);
		vec3 painted = paint.rgb * (0.35 + 0.85 * hsv.z);
		c.rgb = mix(c.rgb, painted, body * paint.a);
	}
	COLOR = c * COLOR;
}
