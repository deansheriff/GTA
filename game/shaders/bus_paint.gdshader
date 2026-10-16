shader_type canvas_item;
// Bus paint (M10, fixed M13): recolours only the yellow danfo body of the painted art, keeping its
// shading, ink lines, glass, wheels and the roof-rack luggage. paint.a = 0 leaves the art as is.
// "Yellow" = red and green both well above blue; brown luggage, grey glass and black ink aren't.

uniform vec4 paint : source_color = vec4(0.0);

// In a canvas shader the incoming COLOR is already texture × modulate, so keep the modulate
// from the vertex stage and multiply by that alone.
varying vec4 modulate;

void vertex() {
	modulate = COLOR;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	if (paint.a > 0.0) {
		float yellowness = min(c.r, c.g) - c.b;
		float body = smoothstep(0.16, 0.3, yellowness) * smoothstep(0.35, 0.5, c.r);
		float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
		vec3 painted = clamp(paint.rgb * (l / 0.6), 0.0, 1.0); // keep the painting's light and shade
		c.rgb = mix(c.rgb, painted, body * paint.a);
	}
	COLOR = c * modulate;
}
