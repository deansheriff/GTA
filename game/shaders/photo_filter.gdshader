shader_type canvas_item;
// Photo mode filters (M11 #22): 0 normal, 1 warm golden hour, 2 black & white, 3 "Nollywood"
// (punchy colour, soft vignette, a touch of film grain).

uniform int mode = 0;
uniform sampler2D screen : hint_screen_texture, filter_linear;

void fragment() {
	vec3 c = texture(screen, SCREEN_UV).rgb;
	if (mode == 1) {
		c = c * vec3(1.08, 0.98, 0.84) + vec3(0.03, 0.01, 0.0);
	} else if (mode == 2) {
		float l = dot(c, vec3(0.299, 0.587, 0.114));
		c = vec3(smoothstep(0.05, 0.95, l));
	} else if (mode == 3) {
		float l = dot(c, vec3(0.299, 0.587, 0.114));
		c = mix(vec3(l), c, 1.35);
		c = (c - 0.5) * 1.12 + 0.5;
		float v = distance(SCREEN_UV, vec2(0.5));
		c *= 1.0 - smoothstep(0.35, 0.8, v) * 0.55;
		c += (fract(sin(dot(SCREEN_UV * 731.0 + TIME, vec2(12.9898, 78.233))) * 43758.5453) - 0.5) * 0.05;
	}
	COLOR = vec4(clamp(c, 0.0, 1.0), 1.0);
}
