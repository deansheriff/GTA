// The whole tropical-island Lagos as one continuous painted surface (D-004, D-007, D-008).
// Masks come from MaskBaker; painted tiling textures from game/art/ground. GLES3-safe.
shader_type canvas_item;

uniform vec2 world_size = vec2(12288.0, 8448.0);
uniform sampler2D land_tex : filter_linear;  // R land, G lagoon
uniform sampler2D road_tex : filter_linear;  // R 0.33 walk, 0.66 gutter, 1.0 road
uniform sampler2D dist_tex : filter_linear;  // R land->water, G water->land (cells, normalised)
uniform sampler2D noise_lo : repeat_enable, filter_linear;
uniform sampler2D noise_hi : repeat_enable, filter_linear;
uniform int quality = 1;

uniform bool use_tex = false;
uniform sampler2D tex_dirt : repeat_enable, filter_linear_mipmap, source_color;
uniform sampler2D tex_grass : repeat_enable, filter_linear_mipmap, source_color;
uniform sampler2D tex_asphalt : repeat_enable, filter_linear_mipmap, source_color;
uniform sampler2D tex_walk : repeat_enable, filter_linear_mipmap, source_color;
uniform sampler2D tex_sand : repeat_enable, filter_linear_mipmap, source_color;
uniform bool use_sand_tex = false;
uniform float tex_tile = 256.0;

uniform vec3 c_dirt : source_color = vec3(0.54, 0.46, 0.34);
uniform vec3 c_laterite : source_color = vec3(0.56, 0.37, 0.25);
uniform vec3 c_grass : source_color = vec3(0.37, 0.48, 0.23);
uniform vec3 c_asphalt : source_color = vec3(0.29, 0.275, 0.26);
uniform vec3 c_gutter : source_color = vec3(0.17, 0.19, 0.15);
uniform vec3 c_walk : source_color = vec3(0.63, 0.54, 0.41);
uniform vec3 c_kerb : source_color = vec3(0.62, 0.59, 0.54);
uniform vec3 c_ink : source_color = vec3(0.11, 0.085, 0.067);
uniform vec3 c_sand : source_color = vec3(0.86, 0.74, 0.52);
uniform vec3 c_shallow : source_color = vec3(0.29, 0.72, 0.7);
uniform vec3 c_deep : source_color = vec3(0.1, 0.33, 0.47);
uniform vec3 c_lagoon : source_color = vec3(0.32, 0.55, 0.48);
uniform vec3 c_bridge : source_color = vec3(0.62, 0.6, 0.56);

float nlo(vec2 p, float s) { return texture(noise_lo, p / s).r; }
float nhi(vec2 p, float s) { return texture(noise_hi, p / s).r; }
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

vec3 sand_at(vec2 p, float wet) {
	vec3 s = use_sand_tex ? texture(tex_sand, p / tex_tile).rgb : c_sand * (0.9 + 0.2 * nhi(p, 40.0));
	return mix(s, s * vec3(0.76, 0.72, 0.68), wet);
}

vec3 water_at(vec2 p, float depth, bool lagoon, float shore) {
	vec2 flow = vec2(TIME * 6.0, TIME * 3.5);
	float w1 = texture(noise_hi, (p + flow) / 70.0).r;
	float w2 = texture(noise_hi, (p * vec2(1.0, 1.6) - flow * 0.7) / 45.0).r;
	vec3 col = lagoon ? mix(c_lagoon * 1.15, c_lagoon * 0.8, depth) : mix(c_shallow, c_deep, depth);
	col *= 0.88 + 0.22 * w1;
	col = mix(col, vec3(0.9, 0.97, 0.95), smoothstep(0.78, 0.86, w2) * 0.4 * (1.0 - depth * 0.6));
	// Foam breathing along the shoreline (shore = land mask value just outside the coast).
	float band = 0.36 + 0.06 * sin(TIME * 1.4 + p.x * 0.01 + p.y * 0.013);
	float foam = smoothstep(band - 0.08, band, shore) * (1.0 - smoothstep(0.48, 0.5, shore));
	col = mix(col, vec3(0.96, 0.97, 0.94), foam * (lagoon ? 0.35 : 0.75) * (0.65 + 0.35 * w1));
	return col;
}

void fragment() {
	vec2 p = UV * world_size;
	vec2 uv = p / world_size;
	vec2 jit = vec2(nhi(p, 97.0) - 0.5, nhi(p + 311.0, 89.0) - 0.5);
	float land = texture(land_tex, uv + jit * 14.0 / world_size).r;
	// Soft lagoon tint: average a ring of taps so it blends into the open sea.
	float lag = 0.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		lag += texture(land_tex, uv + vec2(cos(a), sin(a)) * 420.0 / world_size).g;
	}
	lag = smoothstep(0.15, 0.85, lag / 8.0);
	bool lagoon = lag > 0.5;
	float road = texture(road_tex, uv + jit * 3.0 / world_size).r;
	vec2 dist = texture(dist_tex, uv).rg;
	bool is_land = land > 0.5;

	float dab = nhi(p, 21.0);
	float dab2 = nhi(p * vec2(1.0, 2.4) + 311.0, 47.0);
	float paint_mod = 0.86 + 0.26 * dab + (quality > 0 ? 0.08 * (dab2 - 0.5) : 0.0);

	vec3 col;
	if (road > 0.83) {
		if (is_land) {
			col = use_tex ? texture(tex_asphalt, p / tex_tile).rgb : c_asphalt * (0.9 + 0.22 * nlo(p, 140.0));
			float ph = nhi(p + 57.0, 62.0);
			if (ph > 0.8) col = mix(vec3(0.12, 0.11, 0.1), vec3(0.32, 0.35, 0.27), smoothstep(0.84, 0.9, ph));
			else if (ph > 0.775) col = mix(col, c_ink, 0.75);
			col = mix(col, c_ink, (1.0 - smoothstep(0.83, 0.88, road)) * 0.8); // inked kerb
		} else {
			// Bridge deck: concrete with expansion joints.
			col = c_bridge * (0.92 + 0.12 * nhi(p, 30.0));
			col *= mod(p.x + p.y, 96.0) < 3.0 ? 0.75 : 1.0;
		}
	} else if (road > 0.5) {
		col = is_land ? mix(c_gutter * (0.8 + 0.4 * nhi(p, 13.0)), c_kerb, smoothstep(0.75, 0.82, road)) : c_bridge * 0.7;
		col = mix(col, c_ink, smoothstep(0.52, 0.5, road) * 0.6);
	} else if (road > 0.16) {
		if (is_land) {
			col = use_tex ? texture(tex_walk, p / (tex_tile * 0.5)).rgb : c_walk * (0.88 + 0.2 * hash(floor(p / vec2(16.0, 9.0))));
			col = mix(col, c_dirt, smoothstep(0.55, 0.75, nlo(p + 17.0, 110.0)) * 0.45);
		} else {
			col = c_bridge * 0.85; // bridge footway
			col = mix(col, c_ink, (1.0 - smoothstep(0.16, 0.2, road)) * 0.9); // railing line
		}
	} else if (is_land) {
		// Tropical: grass dominates; red laterite and dusty yards show through in patches.
		float lat = smoothstep(0.56, 0.68, nlo(p + vec2(731.0, 219.0), 620.0));
		float grass = smoothstep(0.4, 0.5, nlo(p, 480.0) + (dab - 0.5) * 0.12);
		vec3 g = use_tex ? texture(tex_grass, p / tex_tile).rgb : mix(c_grass, c_grass * 1.3, nhi(p + 5.0, 34.0));
		vec3 dirt = use_tex ? texture(tex_dirt, p / tex_tile).rgb : c_dirt;
		col = mix(dirt, use_tex ? dirt * vec3(1.05, 0.9, 0.82) : c_laterite, lat);
		col = mix(col, g, grass);
		// Beach band near open water (lagoon shores are muddier), wet sand right at the edge.
		float beach = (1.0 - smoothstep(0.32, 0.5, dist.r)) * (lagoon ? 0.35 : 1.0);
		col = mix(col, sand_at(p, 1.0 - smoothstep(0.5, 0.62, land)), beach);
		float h = hash(floor(p / 3.0));
		if (h > 0.9965) col = mix(col, vec3(0.86, 0.86, 0.84), 0.85);
	} else {
		vec3 sea = water_at(p, smoothstep(0.0, 0.7, dist.g), false, land);
		vec3 lagw = water_at(p, smoothstep(0.0, 0.7, dist.g), true, land);
		col = mix(sea, lagw, lag);
	}

	if (is_land || road > 0.16) {
		col *= use_tex ? mix(1.0, paint_mod, 0.35) : paint_mod;
		float grime = smoothstep(0.55, 0.85, nlo(p + 1234.0, 300.0));
		col = mix(col, col * vec3(0.78, 0.74, 0.68), grime * 0.7);
		if (quality > 0) {
			float speck = hash(floor(p / 1.6) + 7.0);
			if (speck > 0.985) col *= 0.7;
		}
	}
	COLOR = vec4(col, 1.0);
}
