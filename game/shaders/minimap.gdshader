// Minimap / map screen: draws the baked land and road masks in a clean painted-map palette.
shader_type canvas_item;

uniform sampler2D land_tex : filter_linear;
uniform sampler2D road_tex : filter_linear;
uniform vec2 center_uv = vec2(0.5);  // map uv shown at the centre
uniform vec2 span_uv = vec2(1.0);    // map uv span shown across the control
uniform bool round_mask = false;

void fragment() {
	vec2 uv = center_uv + (UV - 0.5) * span_uv;
	vec4 land = texture(land_tex, uv);
	float road = texture(road_tex, uv).r;
	vec3 col = mix(vec3(0.16, 0.42, 0.52), vec3(0.19, 0.45, 0.5), land.g);           // sea / lagoon (close tones: no hard lagoon box)
	if (land.r > 0.5) col = vec3(0.58, 0.62, 0.38);                                    // land
	if (road > 0.16 && land.r > 0.5) col = vec3(0.78, 0.72, 0.6);                      // pavements
	if (road > 0.6) col = vec3(0.93, 0.9, 0.82);                                       // roads and bridges
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) col = vec3(0.12, 0.3, 0.4);
	float a = 1.0;
	if (round_mask) {
		float d = length(UV - 0.5) * 2.0;
		a = 1.0 - smoothstep(0.96, 1.0, d);
		col = mix(col, vec3(0.11, 0.09, 0.07), smoothstep(0.9, 0.96, d)); // ink rim
	}
	COLOR = vec4(col, a);
}
