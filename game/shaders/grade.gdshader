shader_type canvas_item;
// Colour grade (M13): a light touch by time of day, like the title painting. Morning a little
// cool and fresh, midday clean with a bit more colour, late afternoon golden. Night is handled by
// the lighting layer, so the grade fades out after dusk.

uniform sampler2D screen : hint_screen_texture, filter_linear;
uniform vec3 tint = vec3(1.0);
uniform float saturation = 1.0;
uniform float contrast = 1.0;
uniform float strength = 1.0;

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	vec3 g = c * tint;
	float l = dot(g, vec3(0.299, 0.587, 0.114));
	g = mix(vec3(l), g, saturation);
	g = (g - 0.5) * contrast + 0.5;
	COLOR = vec4(mix(c, clamp(g, 0.0, 1.0), strength), 1.0);
}
