// Gives code-drawn placeholder shapes a painted, grimy finish: soft tonal dabs in world space,
// fine grain, and ink lines kept pure. Shared by every placeholder actor.
shader_type canvas_item;

uniform sampler2D noise_hi : repeat_enable, filter_linear;
uniform float strength = 1.0;

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 c = COLOR;
	float lum = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	if (lum > 0.14) { // leave dark ink outlines untouched
		float n = texture(noise_hi, world_pos / 17.0).r;
		float n2 = texture(noise_hi, world_pos / 53.0 + 0.37).r;
		c.rgb *= mix(1.0, 0.82 + 0.3 * n * (0.75 + 0.5 * n2), strength);
		float g = fract(sin(dot(floor(world_pos / 1.5), vec2(12.9898, 78.233))) * 43758.5453);
		if (g > 0.975) c.rgb *= 0.8;
	}
	COLOR = c;
}
