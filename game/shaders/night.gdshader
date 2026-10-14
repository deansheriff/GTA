// Night / NEPA overlay: multiplies the screen by a dark tint, lifted wherever the light buffer is lit.
shader_type canvas_item;
render_mode blend_mul;

uniform sampler2D light_tex : filter_linear;
uniform vec3 dark = vec3(0.36, 0.34, 0.52);
uniform bool use_lights = true;

void fragment() {
	vec3 light = use_lights ? texture(light_tex, SCREEN_UV).rgb : vec3(0.0);
	// Warm pools: brighten toward a lamp-lit colour, never above white.
	COLOR = vec4(clamp(dark + light * 1.15, vec3(0.0), vec3(1.0)), 1.0);
}
